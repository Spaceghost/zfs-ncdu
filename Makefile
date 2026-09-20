# zfs-ncdu

PREFIX     ?= /usr/local
BINDIR     ?= $(PREFIX)/bin
SHAREDIR   ?= $(PREFIX)/share/zfs-ncdu
MANDIR     ?= $(PREFIX)/share/man/man1
DOCDIR     ?= $(PREFIX)/share/doc/zfs-ncdu
INSTALL    ?= install
AWK        ?= awk

.PHONY: all check test install uninstall lint clean

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

clean:
	@echo "Nothing to clean."
