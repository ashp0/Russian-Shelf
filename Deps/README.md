# What the app carries

Copied into `RussianShelf.app/Contents/Resources/` by `make`. `make verify`
checks every Mach-O file here against the 10.9 SDK (`Tools/check109.sh`): its
minimum OS, every library it loads, every symbol it imports.

| | From | Notes |
| --- | --- | --- |
| `python3/` | `build-python.sh` here | Python 3.14.7 for 10.9 (x86_64), OpenSSL 3.5.8 and SQLite linked in, with brotli, certifi, charset-normalizer, idna, mutagen, pycryptodomex, requests, urllib3, websockets. The prefpane's script, adapted: Xcode's clang and the real 10.9 SDK, checked downloads, run in an x86_64 shell, `py-availability.c` linked in. About 15 minutes. |
| `yt-dlp` | Wowfunhappy's media-subscriptions-prefpane (`Deps/yt-dlp`), 2026.08.19 | The zipapp from yt-dlp's releases (Unlicense). The app copies it to Application Support and updates that copy before each batch. |
| `ffmpeg` | the same prefpane (`Deps/ffmpeg`) | ffmpeg 4.4.6 built for 10.9 (minimum OS 10.9, SDK 10.9): decoders for images and subtitles only, the `h264_metadata` filter, MJPEG/PNG encoders. Passes the 10.9 check as it is. |
| `qjs` | `build-quickjs.sh` here | QuickJS 2026-06-04 (Fabrice Bellard), built against the 10.9 SDK with `qjs-compat.h` (10.9 has no `clock_gettime`). Replaces the prefpane's deno, which needs 10.12 and `/usr/local/lib/libMavericksLegacySystem.B.dylib`. |
| `LICENSES/` | | QuickJS's licence; Python's and OpenSSL's are in `python3/LICENSES/`. |

The prefpane has no licence: it's credited in the README, and this project
stays private.

Rebuild:

```
Deps/build-python.sh       # replaces Deps/python3
Deps/build-quickjs.sh      # replaces Deps/qjs
```

Both download their sources over checked TLS and refuse anything that doesn't
match the SHA-256 pinned in the script (`SOURCES=<folder>` uses tarballs
already downloaded).
