# zfs-ncdu.awk - turn ZFS space accounting into an ncdu JSON export.
#
# Input (tab separated, one line per dataset, sorted so that a dataset is
# followed by its descendants):
#   name  used  usedds  usedsnap  usedrefreserv  compressratio
#
# Variables:
#   ts        export timestamp (seconds since epoch)
#   version   version string recorded in the export header
#   snapfile  optional file of "name<TAB>used<TAB>compressratio" snapshot rows
#   rootname  name for the synthetic root when the input holds several trees
#
# Output: ncdu export format 1.2, as consumed by `ncdu -f`.
#
# Sizes follow ZFS's own accounting, where for every dataset
#   USED = USEDDS + USEDSNAP + USEDREFRESERV + USEDCHILD
# so a dataset directory contributes no bytes of its own; its USEDCHILD is the
# sum of the nested dataset directories, and the other three components are
# emitted as files inside it. Disk size is bytes on disk; apparent size is the
# logical size those bytes represent, so ncdu's 'a' toggle shows compression.

function esc(s) {
  gsub(/\\/, "\\\\", s)
  gsub(/"/, "\\\"", s)
  return s
}

function logical(disk, ratio) {
  return (ratio > 0) ? int(disk * ratio + 0.5) : disk
}

function obj(name, dsize, asize) {
  return sprintf("{\"name\":\"%s\",\"asize\":%d,\"dsize\":%d}", esc(name), asize, dsize)
}

# Separator bookkeeping: each nesting level records whether it has already
# emitted a child, so commas land in the right places.
function sep(level) {
  if (haschild[level]) printf(",\n")
  haschild[level] = 1
}

function open_dir(name, level) {
  sep(level)
  printf("[%s", obj(name, 0, 0))
  haschild[level + 1] = 1   # the directory's own object counts as the first item
}

function close_dir() {
  printf("]")
}

function emit_file(name, dsize, asize, level) {
  sep(level)
  printf("%s", obj(name, dsize, asize))
}

function split_path(name, parts,   n) {
  n = split(name, parts, "/")
  return n
}

# Close open directories until only `keep` levels remain open.
function unwind(keep) {
  while (open_levels > keep) {
    close_dir()
    open_levels--
  }
}

BEGIN {
  FS = "\t"
  OFS = "\t"

  if (snapfile != "") {
    while ((getline line < snapfile) > 0) {
      nf = split(line, s, "\t")
      if (nf < 2) continue
      ds = s[1]
      sub(/@.*$/, "", ds)
      i = ++snapcount[ds]
      snapname[ds, i] = s[1]
      snapused[ds, i] = s[2] + 0
      snapratio[ds, i] = s[3] + 0
    }
    close(snapfile)
  }

  printf("[1,2,{\"progname\":\"zfs-ncdu\",\"progver\":\"%s\",\"timestamp\":%d},\n",
         (version == "" ? "0" : version), ts)
  open_levels = 0
  nprev = 0
}

# Collect rows first so we can tell whether a synthetic root is needed.
{
  nrows++
  row[nrows] = $0
  rname[nrows] = $1
}

END {
  # How many of the rows are roots (no listed ancestor)?
  for (i = 1; i <= nrows; i++) {
    isroot[i] = 1
    for (j = 1; j <= nrows; j++) {
      if (i == j) continue
      if (index(rname[i], rname[j] "/") == 1) { isroot[i] = 0; break }
    }
    if (isroot[i]) nroots++
  }

  base = 0
  if (nroots != 1) {
    # Several (or zero) trees: wrap them in one synthetic root so the export
    # still has the single root directory the format requires.
    open_dir((rootname == "" ? "zfs" : rootname), 0)
    open_levels = 1
    base = 1
  }

  for (i = 1; i <= nrows; i++) {
    $0 = row[i]
    name = $1; used = $2 + 0; usedds = $3 + 0; usedsnap = $4 + 0
    refres = $5 + 0; ratio = $6 + 0

    np = split_path(name, parts)

    # Common prefix with the previously emitted dataset.
    common = 0
    while (common < np && common < nprev && parts[common + 1] == prev[common + 1])
      common++

    unwind(base + common)

    # Open any ancestors that were not themselves listed (for example when the
    # user asked for pool/a/b directly), then the dataset itself.
    for (k = common + 1; k < np; k++) {
      open_dir(parts[k], open_levels)
      open_levels++
    }
    open_dir(parts[np], open_levels)
    open_levels++

    level = open_levels   # children of this dataset live one level in

    if (usedds > 0)
      emit_file("[data]", usedds, logical(usedds, ratio), level)

    if (refres > 0)
      emit_file("[refreservation]", refres, refres, level)

    if (usedsnap > 0) {
      if (snapcount[name] > 0) {
        open_dir("[snapshots]", level)
        open_levels++
        unique = 0
        for (k = 1; k <= snapcount[name]; k++) {
          su = snapused[name, k]
          if (su <= 0) continue
          unique += su
          sn = snapname[name, k]
          sub(/^.*@/, "", sn)
          emit_file(sn, su, logical(su, snapratio[name, k]), open_levels)
        }
        # A snapshot's USED counts only the space unique to it; space held by
        # two or more snapshots together belongs to none of them individually.
        # Carry that remainder explicitly or the tree would total less than
        # USEDSNAP, and so less than USED.
        shared = usedsnap - unique
        if (shared > 0)
          emit_file("[shared between snapshots]", shared, logical(shared, ratio), open_levels)
        close_dir()
        open_levels--
      } else {
        emit_file("[snapshots]", usedsnap, logical(usedsnap, ratio), level)
      }
    }

    for (k = 1; k <= np; k++) prev[k] = parts[k]
    nprev = np
  }

  unwind(0)
  printf("\n]\n")
}
