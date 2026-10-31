#!/bin/sh
# ytlist.sh <channel or playlist URL> [more URLs...]
#
# For the weekly russian-shelf skill, on the MacBook: lists a channel's
# videos oldest first, one line each, "id | duration | title", with the
# yt-dlp, Python and certificate list bundled in the built app (x86_64; on
# an Apple silicon Mac it runs under Rosetta). Certificates are checked.
# Lists only (--flat-playlist): nothing is downloaded.
#
#   Tools/ytlist.sh https://www.youtube.com/@SergeyStoryteller/videos

set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
RES="$HERE/build/Shelf.app/Contents/Resources"
[ -x "$RES/python3/bin/python3.14" ] || { echo "Build the app first: make -C \"$HERE\"" >&2; exit 1; }
export SSL_CERT_FILE="$RES/python3/lib/python3.14/site-packages/certifi/cacert.pem"
exec "$RES/python3/bin/python3.14" -I -B -X utf8 "$RES/yt-dlp" --ignore-config --no-plugin-dirs \
    --flat-playlist --playlist-reverse --sleep-requests 1.5 \
    --print "%(id)s | %(duration_string|?)s | %(title)s" "$@"
