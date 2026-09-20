#!/bin/sh
# zfs-ncdu test suite. Runs against fixtures, so it needs no pools and no
# privileges. Usage: tests/run.sh [awk-implementation]
set -eu

here=$(cd "$(dirname "$0")" && pwd -P)
root=$(cd "$here/.." && pwd -P)
fixtures=$here/fixtures
# AWK may name an implementation with arguments, e.g. "busybox awk", so it is
# deliberately left unquoted at the call sites below.
# shellcheck disable=SC2086
AWK=${1:-${AWK:-awk}}
lib=$root/lib/zfs-ncdu.awk

tmp=$(mktemp -d "${TMPDIR:-/tmp}/zfs-ncdu-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0

ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ $# -lt 2 ] || printf '       %s\n' "$2"; }

check_eq() {
	if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected '$3', got '$2'"; fi
}

check_contains() {
	if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else no "$1" "missing: $3"; fi
}

# Sort fixture rows the way bin/zfs-ncdu does before handing them to the awk.
generate() { # generate <datasets.tsv> <snapshots.tsv> [rootname]
	$AWK -F'\t' '{ k = $1; gsub(/\//, "\001", k); print k "\t" $0 }' "$1" |
		LC_ALL=C sort -t "$(printf '\t')" -k1,1 | cut -f2- > "$tmp/sorted.tsv"
	$AWK -v ts=1 -v version=test -v snapfile="$2" -v rootname="${3:-zfs}" \
		-f "$lib" "$tmp/sorted.tsv"
}

# Sum of every dsize in an export: the number ncdu will show as total usage.
total_dsize() {
	printf '%s' "$1" | tr ',' '\n' | sed -n 's/.*"dsize":\([0-9]*\).*/\1/p' |
		$AWK '{ s += $1 } END { printf "%d\n", s }'
}

# Expected total straight from ZFS accounting: USEDDS + USEDSNAP + USEDREFRESERV
# summed over every dataset (USEDCHILD is the nesting, so it must not be added).
expected_total() {
	$AWK -F'\t' '{ s += $3 + $4 + $5 } END { printf "%d\n", s }' "$1"
}

balanced() {
	printf '%s' "$1" | $AWK '
		{ n = length($0)
		  for (i = 1; i <= n; i++) {
			c = substr($0, i, 1)
			if (c == "[") d++
			else if (c == "]") d--
			if (d < 0) { print "negative"; exit }
		  } }
		END { print (d == 0 ? "balanced" : "unbalanced:" d) }'
}

printf 'zfs-ncdu tests (awk: %s)\n\n' "$AWK"

printf 'nesting\n'
out=$(generate "$fixtures/nesting.datasets.tsv" "$fixtures/nesting.snapshots.tsv" tank)
check_eq "totals match ZFS accounting" "$(total_dsize "$out")" "$(expected_total "$fixtures/nesting.datasets.tsv")"
check_eq "brackets balanced" "$(balanced "$out")" "balanced"
check_contains "refreservation is reported" "$out" '"name":"[refreservation]"'
# tank/data-old must not be nested inside tank/data: '-' sorts before '/', so an
# unsorted-by-component run would misplace it and change the tree shape.
check_contains "sibling with dash stays a sibling" "$out" '[{"name":"data-old","asize":0,"dsize":0}'
check_contains "child nests under its parent" "$out" '[{"name":"child","asize":0,"dsize":0}'

printf 'snapshots\n'
out=$(generate "$fixtures/snapshots.datasets.tsv" "$fixtures/snapshots.snapshots.tsv" tank)
check_eq "totals match ZFS accounting" "$(total_dsize "$out")" "$(expected_total "$fixtures/snapshots.datasets.tsv")"
check_contains "individual snapshots listed" "$out" '"name":"monday"'
# USEDSNAP is 600 but the snapshots' own USED is 100 + 150: the remaining 350 is
# held jointly and belongs to no single snapshot.
check_contains "shared snapshot space is carried" "$out" '"name":"[shared between snapshots]","asize":700,"dsize":350'
check_contains "compression shows in apparent size" "$out" '"name":"[data]","asize":800,"dsize":400'

printf 'summarised snapshots\n'
out=$(generate "$fixtures/snapshots.datasets.tsv" "$fixtures/empty.snapshots.tsv" tank)
check_eq "totals match with -S" "$(total_dsize "$out")" "$(expected_total "$fixtures/snapshots.datasets.tsv")"
check_contains "snapshots collapse to one entry" "$out" '"name":"[snapshots]","asize":1200,"dsize":600'

printf 'forest\n'
out=$(generate "$fixtures/forest.datasets.tsv" "$fixtures/empty.snapshots.tsv" zfs)
check_eq "totals match across pools" "$(total_dsize "$out")" "$(expected_total "$fixtures/forest.datasets.tsv")"
check_eq "brackets balanced" "$(balanced "$out")" "balanced"
check_contains "synthetic root wraps the pools" "$out" '[{"name":"zfs","asize":0,"dsize":0}'

printf 'unlisted ancestors\n'
out=$(generate "$fixtures/orphan.datasets.tsv" "$fixtures/empty.snapshots.tsv" tank/deep/nested)
check_eq "totals match" "$(total_dsize "$out")" "$(expected_total "$fixtures/orphan.datasets.tsv")"
check_eq "brackets balanced" "$(balanced "$out")" "balanced"

printf 'tree shape\n'
out=$(generate "$fixtures/nesting.datasets.tsv" "$fixtures/nesting.snapshots.tsv" tank)
# The root dataset's row sorts after its own children unless the sort key is
# compared on its own: the tab delimiter sorts above the \001 separator. When
# that happened the root was emitted a second time, as an empty child.
roots=$(printf '%s' "$out" | grep -o '"name":"tank"' | wc -l | tr -d ' ')
check_eq "root appears exactly once" "$roots" "1"
check_eq "root heads the tree" "$(printf '%s' "$out" | sed -n '2p')" '[{"name":"tank","asize":0,"dsize":0},'

printf 'export validity\n'
out=$(generate "$fixtures/nesting.datasets.tsv" "$fixtures/nesting.snapshots.tsv" tank)
printf '%s' "$out" > "$tmp/export.ncdu"
if command -v python3 >/dev/null 2>&1; then
	if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$tmp/export.ncdu" 2>/dev/null
	then ok "export parses as JSON"; else no "export parses as JSON"; fi
else
	printf '  skip export parses as JSON (no python3)\n'
fi
if command -v ncdu >/dev/null 2>&1; then
	if ncdu -f "$tmp/export.ncdu" -o /dev/null >/dev/null 2>&1
	then ok "ncdu imports the export"; else no "ncdu imports the export"; fi
else
	printf '  skip ncdu imports the export (no ncdu)\n'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
