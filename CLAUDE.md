# Russian Shelf — notes for Claude

Native Objective-C app for the user's OS X 10.9.5 Mac Pro: plays a **sealed weekly
shelf** of about 12 Russian videos that Claude chooses (Sergey Storyteller's TPRS
stories are the spine). The list is encrypted and signed so the user can't edit it;
that was their idea ("so I have no control over it so I don't doomscroll").
Subtitles off by default, with reveal-line, replay-line, keep-on and a transcript.
`README.md` is the full spec.

This repo is **private**: downloading builds on Wowfunhappy's unlicensed
media-subscriptions-prefpane. Never push it anywhere public.

## Two machines

- **MacBook** (macOS 27, Xcode): builds. `make dist` runs verify (107 bundled binaries
  checked against the 10.9 SDK), analyze, ~248 unit checks and 11 TLS checks, then
  writes `Russian Shelf.zip`.
- **Mac Pro** (10.9.5): runs it. Its git is ≤ 1.9 (Command Line Tools for 10.9): no
  post-1.9 git syntax anywhere that runs there, tests included (the
  `update-index --cacheinfo mode,sha,path` form broke report pushes once; `git init -b`
  broke the suite). If you are Claude on the Mac Pro: install, run `--selftest`, read
  `Logs/report.log`, report back.
- The Mac Pro *can* build the app, the tests, the shots and the icon with its own
  Apple LLVM 6.0: `make SDK=/`, `make SDK=/ test` (249/249 on 2026-10-10),
  `make SDK=/ shots`, `make SDK=/ icon`. Not `dist` (verify needs `dyld_info`), so
  `Russian Shelf.zip` is still rebuilt on the MacBook.

## Rules

- **Never run `make keys` again.** The signing key lives in the MacBook's login
  keychain ("Russian Shelf signing key", tag com.russianshelf.signing, non-extractable;
  ACL trusts `com.russianshelf.shelfsign` signed with the Apple Development cert).
  Public and AES keys are in `Sources/RSKeys.c`.
- Seal shelves only through `build/shelfsign` / the `russian-shelf` skill in
  `ashp0/Study` (`Russian/shelf.signed`, `Russian/history.txt`). The skill drops a
  story left unfinished 3 times.
- Reports are pushed to `ashp0/Study` via private-index plumbing (add-only), so the
  Mac Pro's read-write deploy key never diverges the clone.

## Bundled tools (verified)

- deno from the prefpane can't run on 10.9; yt-dlp uses **QuickJS**
  (`--js-runtimes quickjs:PATH`), built against the 10.9 SDK with a clock_gettime shim.
- Python 3.14.7 was rebuilt with the 10.9 SDK (`.eh` symbols in the original's
  extension modules break modern dyld; a static `__isOSVersionAtLeast` shim was needed).
- ffmpeg 4.4.6 passes as is.
- Check imports with `Tools/check109.sh <SDK> <files>`; use `dyld_info -exports`, not
  `nm -gU` (10.9 re-exports memcpy/strcmp as aliases nm doesn't list).
- Easy Russian's channel is `@EasyRussianVideos`.

## Still untested on the real Mac Pro

- SecItemImport of the EC public key + SecVerifyTransform (selftest's first lines).
- The layer-backed caption overlay over AVPlayerView; inline controls.
- 2026-10-10 fixes (git-1.9 report push; full screen via F / double-click / title bar,
  Esc leaves) are in the zip but the Mac Pro may still have the old app.
- The skeuomorphic pass (2026-10-10, `RSStyle.m`, new icon) was built and installed
  on the Mac Pro from source, and its self-test passed; `Russian Shelf.zip` predates it
  until the next `make dist` on the MacBook.

## Working with the user

Push this repo without asking. Russian matters to them personally; it's the planned
sixth course next term. Limit supply, not time: no feeds. A future idea: the day's
story unlocks after a conjugation drill. Mavvy doesn't work on Waterloo wifi; don't use it.
