PREFIX ?= /usr/local

build:
	swift build -c release

install: build
	install -d $(PREFIX)/bin
	install .build/release/launchpad $(PREFIX)/bin/launchpad
	@echo "Installed to $(PREFIX)/bin/launchpad"

uninstall:
	rm -f $(PREFIX)/bin/launchpad

clean:
	swift package clean

.PHONY: build install uninstall clean
