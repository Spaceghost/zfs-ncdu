# zfs-ncdu

PREFIX     ?= /usr/local
BINDIR     ?= $(PREFIX)/bin
SHAREDIR   ?= $(PREFIX)/share/zfs-ncdu
MANDIR     ?= $(PREFIX)/share/man/man1
DOCDIR     ?= $(PREFIX)/share/doc/zfs-ncdu
INSTALL    ?= install
AWK        ?= awk

.PHONY: all check test install uninstall lint images demo clean

all:
	@echo "Nothing to build. Targets: check, install, uninstall, lint."

check test:
	@AWK='$(AWK)' ./tests/run.sh

install:
	$(INSTALL) -d $(DESTDIR)$(BINDIR) $(DESTDIR)$(SHAREDIR) $(DESTDIR)$(MANDIR) $(DESTDIR)$(DOCDIR)
	$(INSTALL) -m 0755 bin/zfs-ncdu $(DESTDIR)$(BINDIR)/zfs-ncdu
	$(INSTALL) -m 0644 lib/zfs-ncdu.awk $(DESTDIR)$(SHAREDIR)/zfs-ncdu.awk
	$(INSTALL) -m 0644 doc/zfs-ncdu.1 $(DESTDIR)$(MANDIR)/zfs-ncdu.1
	$(INSTALL) -m 0644 README.md LICENSE $(DESTDIR)$(DOCDIR)

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/zfs-ncdu
	rm -f $(DESTDIR)$(SHAREDIR)/zfs-ncdu.awk
	rm -f $(DESTDIR)$(MANDIR)/zfs-ncdu.1
	rm -f $(DESTDIR)$(DOCDIR)/README.md $(DESTDIR)$(DOCDIR)/LICENSE
	-rmdir $(DESTDIR)$(SHAREDIR) $(DESTDIR)$(DOCDIR) 2>/dev/null || true

lint:
	@command -v shellcheck >/dev/null 2>&1 && shellcheck bin/zfs-ncdu tests/run.sh || \
		echo "shellcheck not installed; skipping"

# Re-render the README images from the recorded ncdu captures in doc/demo.
images:
	$(AWK) -v title="zfs-ncdu tank" -v cols=92 \
		-f doc/tools/term2svg.awk doc/demo/capture-pool.txt > doc/screenshot.svg
	$(AWK) -v title="zfs-ncdu tank/backups/[snapshots]" -v cols=92 \
		-f doc/tools/term2svg.awk doc/demo/capture-snapshots.txt > doc/snapshots.svg
	@command -v rsvg-convert >/dev/null 2>&1 && \
		rsvg-convert -w 256 doc/icon.svg -o doc/icon-256.png || \
		echo "rsvg-convert not installed; icon PNG left as is"

# Rebuild the demo export the images are captured from.
demo:
	$(AWK) -F'\t' '{ k = $$1; gsub(/\//, "\001", k); print k "\t" $$0 }' \
		doc/demo/tank.datasets.tsv | \
		LC_ALL=C sort -t "$$(printf '\t')" -k1,1 | cut -f2- > doc/demo/sorted.tsv
	$(AWK) -v ts=1789900000 -v version=0.1.0 \
		-v snapfile=doc/demo/tank.snapshots.tsv -v rootname=tank \
		-f lib/zfs-ncdu.awk doc/demo/sorted.tsv > doc/demo/tank.ncdu
	@rm -f doc/demo/sorted.tsv
	@echo "doc/demo/tank.ncdu rebuilt; view it with: ncdu -f doc/demo/tank.ncdu"

clean:
	@echo "Nothing to clean."
