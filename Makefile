.PHONY: all setup build test run clean install-desktop

all: build

.local/share/pkgconfig/libghostty-vt.pc:
	scripts/build-libghostty.sh

build/build.ninja: meson.build .local/share/pkgconfig/libghostty-vt.pc
	PKG_CONFIG_PATH=$(PWD)/.local/share/pkgconfig meson setup build

setup: build/build.ninja

build: build/build.ninja
	ninja -C build

test: build
	meson test -C build
	./hooks/test-derive.sh
	./tests/install-hooks-check.sh
	./tests/install-codex-check.sh

run: build
	./build/cc-status

install-desktop: build
	mkdir -p $(HOME)/.local/share/applications
	sed "s|__EXEC__|$(abspath build/cc-status)|" cc-status.desktop > $(HOME)/.local/share/applications/cc-status.desktop
	update-desktop-database $(HOME)/.local/share/applications 2>/dev/null || true

clean:
	rm -rf build
