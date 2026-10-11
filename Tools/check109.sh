#!/bin/sh
# check109.sh <10.9 SDK> <Mach-O file>...
#
# For each file: x86_64, minimum OS at most 10.9 (LC_VERSION_MIN_MACOSX, no
# LC_BUILD_VERSION), every library it loads present in the 10.9 SDK (or
# inside the bundle, by @loader_path / @executable_path), and every symbol it
# imports by two-level namespace exported by that library on 10.9, following
# re-exports (libSystem's usr/lib/system, umbrella frameworks). Weak imports
# may be missing. Prints one line per problem; exits 1 if there was any.
#
# Made for the binaries Russian Shelf bundles but did not build (Python and
# its modules, ffmpeg), where nothing else proves they will load on 10.9.

set -u
SDK="$1"; shift
CACHE="${TMPDIR:-/tmp}/check109.$$"
mkdir -p "$CACHE"
trap 'rm -rf "$CACHE"' EXIT
status=0

# The SDK file standing for an install name: a Mach-O stub or a .tbd.
sdkfile() {
    local p t
    p="$SDK$1"
    [ -f "$p" ] && { echo "$p"; return; }
    t="${p%.dylib}.tbd"
    [ -f "$t" ] && { echo "$t"; return; }
    [ -f "$p.tbd" ] && { echo "$p.tbd"; return; }
    echo ""
}

# Every symbol an install name exports on 10.9, re-exports included.
exports() {
    local key out f r
    key="$(printf '%s' "$1" | tr '/' '_')"
    out="$CACHE/$key"
    [ -f "$out" ] && { cat "$out"; return; }
    f="$(sdkfile "$1")"
    : > "$out"
    [ -n "$f" ] || return
    case "$f" in
    *.tbd) grep -oE "_[A-Za-z0-9_\$.]+" "$f" >> "$out" ;;
    # dyld_info, not nm: 10.9 exports memcpy and friends as re-exported
    # aliases (libsystem_c -> libsystem_platform), which nm doesn't list.
    *)  dyld_info -arch x86_64 -exports "$f" 2>/dev/null | \
            awk '$1 == "[re-export]" {print $2; next} $1 ~ /^0x/ {print $2}' >> "$out"
        for r in $(otool -arch x86_64 -l "$f" | awk '/LC_REEXPORT_DYLIB/{getline;getline;print $2}'); do
            exports "$r" >> "$out"
        done ;;
    esac
    sort -u -o "$out" "$out"
    cat "$out"
}

fail() { echo "FAIL: $*"; status=1; }

for bin in "$@"; do
    name="${bin##*/}"
    lipo -archs "$bin" 2>/dev/null | grep -qw x86_64 || { fail "$name: no x86_64"; continue; }
    lc="$(otool -arch x86_64 -l "$bin")"
    printf '%s\n' "$lc" | grep -q LC_BUILD_VERSION && fail "$name: LC_BUILD_VERSION (newer than 10.9's loader understands)"
    min="$(printf '%s\n' "$lc" | awk '/LC_VERSION_MIN_MACOSX/{getline;getline;print $2;exit}')"
    case "$min" in
    10.[0-9]|10.[0-9].*) ;;
    *) fail "$name: minimum macOS is '${min:-none}'" ;;
    esac
    printf '%s\n' "$lc" | grep -q LC_DYLD_CHAINED_FIXUPS && fail "$name: chained fixups"
    # Libraries, in load-command order: two-level ordinals count from 1.
    libs="$(printf '%s\n' "$lc" | awk '/cmd LC_(LOAD|LOAD_WEAK|REEXPORT|LOAD_UPWARD|LAZY_LOAD)_DYLIB/{c=$2; getline; getline; print c, $2}')"
    printf '%s\n' "$libs" | while read -r cmd lib; do
        [ -n "$lib" ] || continue
        case "$lib" in
        @loader_path/*|@executable_path/*|@rpath/*) continue ;;
        esac
        [ -n "$(sdkfile "$lib")" ] && continue
        [ "$cmd" = LC_LOAD_WEAK_DYLIB ] && continue
        echo "FAIL: $name: loads $lib, which 10.9 doesn't have"
    done | grep . && status=1
    # Imports: "(undefined) [weak] external _sym (from Lib)".
    nm -arch x86_64 -um "$bin" 2>/dev/null | grep '(from ' | grep -v 'weak external' | \
        sed -E 's/.*external ([^ ]+) \(from ([^)]+)\).*/\2 \1/' > "$CACHE/imports"
    printf '%s\n' "$libs" | awk '{print $2}' > "$CACHE/libs"
    while read -r short sym; do
        # nm names the library by its short name; find the install name.
        lib="$(grep -E "/(lib)?$short(\.[A-Za-z0-9]+)*(\.dylib)?$|/$short\.framework/" "$CACHE/libs" | head -1)"
        [ -n "$lib" ] || { echo "?? $name: can't place $short for $sym"; continue; }
        case "$lib" in @*) continue ;; esac
        exports "$lib" > "$CACHE/exp"
        grep -qxF "$sym" "$CACHE/exp" || echo "FAIL: $name: $sym (from ${lib##*/}) isn't exported on 10.9"
    done < "$CACHE/imports" > "$CACHE/out"
    if grep -q . "$CACHE/out"; then cat "$CACHE/out"; grep -q FAIL "$CACHE/out" && status=1; fi
done
exit $status
