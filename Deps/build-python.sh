#!/bin/bash
#
# Builds Deps/python3: Python 3.14.7 for OS X 10.9 (x86_64), with OpenSSL
# 3.5.8 and SQLite linked in statically, and the packages yt-dlp uses.
#
# Wowfunhappy's media-subscriptions-prefpane script (Deps/build-python.sh
# there), changed in four ways:
#
#   - Xcode's clang and the real 10.9 SDK (~/Developer/SDKs/MacOSX10.9.sdk)
#     instead of a custom clang-22 toolchain. The prefpane's own build loads
#     on 10.9 but four of its modules (_socket, _ctypes, _hashlib,
#     _posixsubprocess) carry "<name>.eh" symbols that today's dyld refuses,
#     so it can't run on this Mac, even under Rosetta, for the tests.
#   - curl checks certificates (the original passed -k), and every tarball
#     must match the SHA-256 pinned below.
#   - It runs in an x86_64 shell (arch -x86_64), so configure sees an Intel
#     Mac and its test programs run under Rosetta: not a cross build.
#   - Deps/py-availability.c is linked into everything: today's compiler-rt
#     answers __builtin_available with a function only macOS 11 has.
#   - The result is checked with Tools/check109.sh against the 10.9 SDK.
#
#   Deps/build-python.sh        (about 15 minutes; replaces Deps/python3)

set -e

if [ "$(uname -m)" != x86_64 ]; then
    exec arch -x86_64 /bin/bash "$0" "$@"
fi

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${SDK:-$HOME/Developer/SDKs/MacOSX10.9.sdk}"
CLANG="$(xcrun -f clang)"
JOBS="${JOBS:-8}"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/russian-shelf-python.XXXXXX")"
OPENSSL_PREFIX="$BUILD_DIR/openssl"
SQLITE_PREFIX="$BUILD_DIR/sqlite"
PYTHON_PREFIX="$BUILD_DIR/python"
PACKAGE_DIR="$BUILD_DIR/package"

[ -f "$SDK/SDKSettings.plist" ] || { echo "No 10.9 SDK at $SDK" >&2; exit 1; }

trap 'rm -rf "$BUILD_DIR"' EXIT

TARGET="-arch x86_64 -isysroot $SDK -mmacosx-version-min=10.9"
export SDKROOT="$SDK" MACOSX_DEPLOYMENT_TARGET=10.9
export CC="$CLANG $TARGET" CXX="$(xcrun -f clang++) $TARGET"
export AR="$(xcrun -f ar)" RANLIB="$(xcrun -f ranlib)"

fetch() {    # url sha256
    name="${1##*/}"
    if [ -f "${SOURCES:-/nonexistent}/$name" ]; then cp "$SOURCES/$name" .; else curl -fsSLO "$1"; fi
    echo "$2  $name" | shasum -a 256 -c - >/dev/null || { echo "$name doesn't match its pinned SHA-256" >&2; exit 1; }
}

cd "$BUILD_DIR"
# An archive, not an object: pip passes its LDFLAGS and Python's saved ones,
# and an archive listed twice links once.
$CC -Os -c "$PROJECT_DIR/Deps/py-availability.c" -o "$BUILD_DIR/py-availability.o"
$AR rcs "$BUILD_DIR/libpyavailability.a" "$BUILD_DIR/py-availability.o"
fetch https://www.python.org/ftp/python/3.14.7/Python-3.14.7.tar.xz \
    3b48dac8fb59f62eaa67ac83c1eb12bda1b7a08406dd286e252c11a66be27f81
fetch https://github.com/openssl/openssl/releases/download/openssl-3.5.8/openssl-3.5.8.tar.gz \
    a8f84a39918ec6415ce765d9b429d313ba97b8143169c172e734b9514464f5b2
fetch https://sqlite.org/2026/sqlite-autoconf-3530400.tar.gz \
    0e9483900e92cd5de8fd48d16bf9200145a61f7fd5be542a5ac81d8a9516eb9c

tar -xf Python-3.14.7.tar.xz
tar -xf openssl-3.5.8.tar.gz
tar -xf sqlite-autoconf-3530400.tar.gz

cd "$BUILD_DIR/openssl-3.5.8"
./Configure darwin64-x86_64-cc no-shared no-tests no-apps no-docs no-module no-legacy no-dso \
    --prefix="$OPENSSL_PREFIX" --openssldir="$OPENSSL_PREFIX/ssl" -mmacosx-version-min=10.9 -Os
make -j "$JOBS"
make install_sw

cd "$BUILD_DIR/sqlite-autoconf-3530400"
CFLAGS='-Os' ./configure --prefix="$SQLITE_PREFIX" --disable-shared --disable-readline --disable-load-extension
make -j "$JOBS"
make install

cd "$BUILD_DIR/Python-3.14.7"
CFLAGS='-Os' \
CPPFLAGS="-I$OPENSSL_PREFIX/include -I$SQLITE_PREFIX/include" \
LDFLAGS="-L$OPENSSL_PREFIX/lib -L$SQLITE_PREFIX/lib -Wl,-w $BUILD_DIR/libpyavailability.a" \
LIBSQLITE3_CFLAGS="-I$SQLITE_PREFIX/include" LIBSQLITE3_LIBS="$SQLITE_PREFIX/lib/libsqlite3.a" \
    ./configure --prefix="$PYTHON_PREFIX" --with-openssl="$OPENSSL_PREFIX" --with-openssl-rpath=no \
    --disable-test-modules --without-static-libpython --without-mimalloc --with-ensurepip=install
make -j "$JOBS"
make install

CFLAGS='-Os' LDFLAGS="-Wl,-w $BUILD_DIR/libpyavailability.a" \
    "$PYTHON_PREFIX/bin/python3" -m pip install --no-cache-dir --no-binary=:all: \
    brotli==1.2.0 certifi==2026.7.22 charset-normalizer==3.5.0 idna==3.18 mutagen==1.48.1 \
    pycryptodomex==3.23.0 requests==2.34.2 urllib3==2.7.0 websockets==17.0.1

cp -a "$PYTHON_PREFIX" "$PACKAGE_DIR"
PYTHON_LIB="$PACKAGE_DIR/lib/python3.14"
rm -rf "$PACKAGE_DIR/include" "$PACKAGE_DIR/share" "$PACKAGE_DIR/lib/pkgconfig" \
    "$PYTHON_LIB/idlelib" "$PYTHON_LIB/tkinter" "$PYTHON_LIB/turtledemo" "$PYTHON_LIB/ensurepip" \
    "$PYTHON_LIB/venv" "$PYTHON_LIB/pydoc_data" "$PYTHON_LIB/unittest" "$PYTHON_LIB/__phello__" \
    "$PYTHON_LIB/site-packages/Cryptodome/SelfTest" "$PYTHON_LIB/site-packages/certifi/tests"
rm -rf "$PYTHON_LIB"/site-packages/pip "$PYTHON_LIB"/site-packages/pip-*.dist-info
find "$PACKAGE_DIR" -type d -name __pycache__ -prune -exec rm -rf '{}' +
find "$PACKAGE_DIR" -type f -name '*.pyi' -delete
find "$PACKAGE_DIR/bin" -type f ! -name python3.14 -delete
find "$PACKAGE_DIR/bin" -type l ! -name python3 -delete
/usr/bin/strip -x "$PACKAGE_DIR/bin/python3.14"
find "$PACKAGE_DIR" -type f -name '*.so' -exec /usr/bin/strip -x '{}' +

cd "$PYTHON_LIB"
zip -9 -q -r ../python314.zip . -x './site-packages/*' './lib-dynload/*'
find "$PYTHON_LIB" -mindepth 1 -maxdepth 1 ! -name site-packages ! -name lib-dynload -exec rm -rf '{}' +

mkdir "$PACKAGE_DIR/LICENSES"
cp "$BUILD_DIR/Python-3.14.7/LICENSE" "$PACKAGE_DIR/LICENSES/CPython.txt"
cp "$BUILD_DIR/openssl-3.5.8/LICENSE.txt" "$PACKAGE_DIR/LICENSES/OpenSSL.txt"

env PYTHONDONTWRITEBYTECODE=1 "$PACKAGE_DIR/bin/python3" -I -c 'import brotli, certifi, charset_normalizer, Cryptodome, idna, mutagen, requests, sqlite3, ssl, urllib3, websockets, socket, ctypes, hashlib, subprocess; print(ssl.OPENSSL_VERSION)'
env PYTHONDONTWRITEBYTECODE=1 "$PACKAGE_DIR/bin/python3" -I "$PROJECT_DIR/Deps/yt-dlp" --version
/bin/sh "$PROJECT_DIR/Tools/check109.sh" "$SDK" "$PACKAGE_DIR/bin/python3.14" $(find "$PACKAGE_DIR" -name '*.so')

rm -rf "$PROJECT_DIR/Deps/python3"
cp -a "$PACKAGE_DIR" "$PROJECT_DIR/Deps/python3"
echo "built $PROJECT_DIR/Deps/python3"
