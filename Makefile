.PHONY: all setup build test run clean

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

clean:
	rm -rf build
