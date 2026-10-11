#!/bin/sh
# tlstest.sh <the app's Resources> <work folder>
#
# Proves the bundled Python and yt-dlp check certificates, as the app runs
# them (python3.14 -I with SSL_CERT_FILE set to certifi's list), and that the
# check is what certifi makes work:
#
#   1. Without SSL_CERT_FILE this Python trusts nothing, not even YouTube
#      (its OpenSSL looks for certificates where it was built, which isn't
#      here). So the list it uses is certifi's, and only that.
#   2. With it, YouTube and GitHub are accepted.
#   3. A server on this Mac with a self-signed certificate is refused, by
#      Python and by yt-dlp itself.
#   4. badssl.com's expired, self-signed and wrong-host certificates are
#      refused.
#   5. yt-dlp's self-update, which downloads code, runs with checks on.
#
# Needs the network (1-2, 4, 5). Run by `make tlstest` and `make dist`.

set -u
RES="$1"
WORK="$2"
PY="$RES/python3/bin/python3.14"
YT="$RES/yt-dlp"
CERTS="$RES/python3/lib/python3.14/site-packages/certifi/cacert.pem"
rm -rf "$WORK"
mkdir -p "$WORK"
failures=0
ok()   { echo "   ok    $*"; }
fail() { echo "   FAIL  $*"; failures=$((failures + 1)); }

echo "== Certificates are checked =="
test -f "$CERTS" || { echo "FAIL: no certifi list in the bundle"; exit 1; }

# A URL's fate with a given certificate list (none: ""): "ok", "refused" or
# "other: why".
fetch() {   # certificates url
    if [ -n "$1" ]; then set -- "$2" SSL_CERT_FILE="$1"; else set -- "$2" NO_CERTIFICATES=1; fi
    env -i HOME="$HOME" PATH=/usr/bin:/bin TMPDIR="$WORK" "$2" "$PY" -I -B -c '
import sys, ssl, urllib.request, urllib.error
try:
    urllib.request.urlopen(sys.argv[1], timeout=20).read(64)
    print("ok")
except urllib.error.HTTPError:
    print("ok")
except Exception as e:
    r = getattr(e, "reason", e)
    print("refused" if isinstance(r, ssl.SSLCertVerificationError) or "CERTIFICATE_VERIFY_FAILED" in str(e) else "other: %s" % r)
' "$1" 2>&1 | tail -1
}

r="$(fetch "" https://www.youtube.com/)"
[ "$r" = refused ] && ok "without SSL_CERT_FILE, nothing is trusted (YouTube refused): the list in use is certifi's" \
                   || fail "without SSL_CERT_FILE: expected refused, got: $r"

for url in https://www.youtube.com/ https://github.com/; do
    r="$(fetch "$CERTS" "$url")"
    [ "$r" = ok ] && ok "accepted $url" || fail "$url should be accepted: $r"
done

# 3. A local server with a self-signed certificate.
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -days 1 \
    -subj /CN=localhost >/dev/null 2>&1 || { echo "FAIL: openssl couldn't make a test certificate"; exit 1; }
printf 'hello' > "$WORK/x.mp4"
env -i HOME="$HOME" PATH=/usr/bin:/bin "$PY" -I -B -c '
import http.server, ssl, sys, os, functools
os.chdir(sys.argv[1])
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=sys.argv[1])
handler.log_message = lambda *a: None
server = http.server.HTTPServer(("127.0.0.1", 0), handler)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(os.path.join(sys.argv[1], "cert.pem"), os.path.join(sys.argv[1], "key.pem"))
server.socket = ctx.wrap_socket(server.socket, server_side=True)
open(os.path.join(sys.argv[1], "port"), "w").write(str(server.server_address[1]))
server.serve_forever()
' "$WORK" >/dev/null 2>&1 &
server=$!
trap 'kill $server 2>/dev/null' EXIT
for i in 1 2 3 4 5 6 7 8 9 10; do [ -s "$WORK/port" ] && break; sleep 1; done
port="$(cat "$WORK/port" 2>/dev/null)"
[ -n "$port" ] || { echo "FAIL: the test server didn't start"; exit 1; }

r="$(fetch "$CERTS" "https://localhost:$port/x.mp4")"
[ "$r" = refused ] && ok "Python refused a self-signed server on this Mac" || fail "self-signed server: expected refused, got: $r"

out="$(env -i HOME="$HOME" PATH=/usr/bin:/bin TMPDIR="$WORK" SSL_CERT_FILE="$CERTS" \
       "$PY" -I -B -X utf8 "$YT" --ignore-config --no-plugin-dirs --no-cache-dir -o "$WORK/got.%(ext)s" \
       "https://localhost:$port/x.mp4" 2>&1)"
status=$?
if [ $status -ne 0 ] && printf '%s' "$out" | grep -qi 'certificate verify failed' && [ ! -f "$WORK/got.mp4" ]; then
    ok "yt-dlp refused the self-signed server and downloaded nothing"
else
    fail "yt-dlp and the self-signed server (status $status): $(printf '%s' "$out" | tail -2)"
fi
# The same server, trusted on purpose: the refusal above was the certificate.
r="$(fetch "$WORK/cert.pem" "https://localhost:$port/x.mp4")"
[ "$r" = ok ] && ok "with its certificate trusted, the same server is accepted" || fail "trusted local server: $r"

# 4. badssl.com.
for url in https://expired.badssl.com/ https://self-signed.badssl.com/ https://wrong.host.badssl.com/ https://untrusted-root.badssl.com/; do
    r="$(fetch "$CERTS" "$url")"
    [ "$r" = refused ] && ok "refused $url" || fail "$url should be refused: $r"
done

# 5. The self-update, on a copy, as the app runs it (never --no-check-certificates).
cp "$YT" "$WORK/yt-dlp"
out="$(env -i HOME="$HOME" PATH=/usr/bin:/bin TMPDIR="$WORK" SSL_CERT_FILE="$CERTS" \
       "$PY" -I -B -X utf8 "$WORK/yt-dlp" --ignore-config --no-plugin-dirs --update 2>&1)"
status=$?
if [ $status -eq 0 ] && printf '%s' "$out" | grep -qiE 'is up to date|updated yt-dlp to'; then
    ok "yt-dlp's self-update, certificates checked: $(printf '%s' "$out" | grep -iE 'up to date|updated' | tail -1)"
else
    fail "yt-dlp's self-update (status $status): $(printf '%s' "$out" | tail -2)"
fi

[ $failures -eq 0 ] || { echo "FAIL: $failures certificate checks"; exit 1; }
echo "OK"
