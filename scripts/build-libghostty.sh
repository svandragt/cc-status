#!/bin/sh
# Build libghostty-vt from source into ./.local, because distro packages lag
# badly: Ghostty 1.3.1 (the Ubuntu PPA build) ships libghostty-vt 0.1.0 whose C
# API has the OSC/SGR/key/paste parsers but NO terminal, screen or render API.
# Current main has ghostty_terminal_* and ghostty_render_state_*, which is what
# an actual terminal surface needs.
#
# Nothing here touches the system install; meson prefers ./.local via
# PKG_CONFIG_PATH (see the README).
set -e

ZIG_VERSION=0.16.0   # ghostty's build.zig.zon minimum_zig_version
PREFIX="$(cd "$(dirname "$0")/.." && pwd)/.local"
WORK="${TMPDIR:-/tmp}/libghostty-build"

mkdir -p "$WORK"
cd "$WORK"

if [ ! -x "zig-x86_64-linux-${ZIG_VERSION}/zig" ]; then
  echo "==> fetching zig ${ZIG_VERSION}"
  curl -fsSL -o zig.tar.xz \
    "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz"
  tar xf zig.tar.xz
fi
ZIG="$WORK/zig-x86_64-linux-${ZIG_VERSION}/zig"

if [ -d ghostty/.git ]; then
  echo "==> updating ghostty checkout"
  git -C ghostty fetch --depth 1 origin main
  git -C ghostty reset --hard origin/main
else
  echo "==> cloning ghostty"
  git clone --depth 1 https://github.com/ghostty-org/ghostty.git
fi

echo "==> building libghostty-vt into $PREFIX"
cd ghostty
# -Demit-lib-vt sets defaults for a vt-only build: no macOS app, no xcframework,
# no docs, so this needs neither pandoc nor a GTK toolchain.
"$ZIG" build -Demit-lib-vt=true -Doptimize=ReleaseFast --prefix "$PREFIX"

echo "==> built ghostty $(git rev-parse --short HEAD)"
ls -l "$PREFIX/lib/"
