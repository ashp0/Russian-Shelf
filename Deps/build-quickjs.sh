#!/bin/bash
#
# Builds Deps/qjs: QuickJS (Fabrice Bellard's), the JavaScript runtime yt-dlp
# uses to answer YouTube's player challenges, for OS X 10.9 (x86_64).
#
# The prefpane passes yt-dlp a bundled deno instead. That deno can't start on
# a stock 10.9: its minimum OS is 10.12, it loads
# /usr/local/lib/libMavericksLegacySystem.B.dylib (not part of OS X), and it
# imports clock_gettime, getentropy, openat and 11 more functions 10.9's
# libSystem doesn't have (Tools/check109.sh lists them). yt-dlp supports
# QuickJS 2025-04-26 or later as well; this one is about 1 MB.
#
#   Deps/build-quickjs.sh       (a minute; replaces Deps/qjs)

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${SDK:-$HOME/Developer/SDKs/MacOSX10.9.sdk}"
VERSION=2026-06-04
SHA256=b376e839b322978313d929fd20663b11ba58b75df5a46c126dd19ea2fa70ad2a
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/russian-shelf-quickjs.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

[ -f "$SDK/SDKSettings.plist" ] || { echo "No 10.9 SDK at $SDK" >&2; exit 1; }

cd "$BUILD_DIR"
name="quickjs-$VERSION.tar.xz"
if [ -f "${SOURCES:-/nonexistent}/$name" ]; then cp "$SOURCES/$name" .; else curl -fsSLO "https://bellard.org/quickjs/$name"; fi
echo "$SHA256  $name" | shasum -a 256 -c - >/dev/null || { echo "$name doesn't match its pinned SHA-256" >&2; exit 1; }
tar -xf "$name"
cd "quickjs-$VERSION"
cp "$PROJECT_DIR/Deps/qjs-compat.h" .
# The compiler, as one word: the Makefile splits CC at spaces and qjsc bakes
# it into a string.
cat > cc109 <<CC
#!/bin/sh
exec "$(xcrun -f clang)" -arch x86_64 -isysroot "$SDK" -mmacosx-version-min=10.9 -include "$PWD/qjs-compat.h" -Wl,-w -Wno-unused-command-line-argument "\$@"
CC
chmod +x cc109

# The Makefile builds qjsc for the target too and runs it to compile repl.js:
# here that runs under Rosetta.
make -j8 CONFIG_DARWIN=y CC="$PWD/cc109" qjs
strip -x qjs
./qjs --help 2>&1 | head -1
echo 'print([1, 2, 3].map(x => x * 2).join(","))' > t.js && ./qjs --script t.js
/bin/sh "$PROJECT_DIR/Tools/check109.sh" "$SDK" qjs
mkdir -p "$PROJECT_DIR/Deps/LICENSES"
cp LICENSE "$PROJECT_DIR/Deps/LICENSES/QuickJS.txt"
cp qjs "$PROJECT_DIR/Deps/qjs"
echo "built $PROJECT_DIR/Deps/qjs ($(du -h "$PROJECT_DIR/Deps/qjs" | cut -f1))"
