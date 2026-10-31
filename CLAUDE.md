# Shelf — notes for Claude

Native Objective-C app for the user's OS X 10.9.5 Mac Pro (Russian Shelf until
2026-10-30; `DESIGN.md` is the redesign and why). It plays a **sealed weekly shelf** of
about 12 Russian videos that Claude chooses, in three kinds (easy / natural / fast, each
under a brass plate; a fast video opens with Russian subtitles the first time), and
keeps the desk around them: a **desk card** saying what today holds (Cards, Clip, Say,
then the story; a line goes when its thing is done, no ticks), a **dictionary** (W: the
line's words, the rarest first; OpenRussian in `Resources/dict.sqlite`, RNC ranks; K
keeps a word card), **today's clip** (⌘K/C: 2–3 min of the fast video, three passes:
listen twice, read line by line, say along; R records the say-along), **Cards** (⌘L:
lines and words, sound first, 1·3·7·16·35·75 days, fifteen kept and sixty heard a day
counting the other Mac, no keeping while 45 wait, both ways once a card has words), and
**Say** (⌘S: islands in `Say/Islands.txt`, 2·1½·1 passes with a sand-glass and the
microphone, hear it back, Tab a note for the tutor, the month's recording, M last
month's then today's). The list is encrypted and signed so the user can't edit it; that
was their idea ("so I have no control over it so I don't doomscroll"). The owner is
A2–B1 (structure ahead, vocabulary behind, speaks in fragments): size things for that,
not for a beginner, but keep easy Russian as most of the shelf (~60/30/10 easy /
natural / fast, their own wish: endings heard clearly become automatic). H in the
player asks, once and optionally, too easy / about right / too hard and more / less like
this. Reports carry all of it (help, lines, words, clips, said, the tutor's notes) for
the skill to choose by; the app shows no number about the owner. `README.md` is the
full spec; the research is the Russian Fluency Brief (2026-10-30) and
`~/dendron-autopilot/reports/r1-research.md` on the Mac Pro.

This repo is **private**: downloading builds on Wowfunhappy's unlicensed
media-subscriptions-prefpane. Never push it anywhere public.

## Two machines

- **MacBook** (macOS 27, Xcode): builds. `make dist` runs verify (107 bundled binaries
  checked against the 10.9 SDK), analyze, ~440 unit checks and 11 TLS checks, then
  writes `Shelf.zip`.
- **Mac Pro** (10.9.5): runs it. Its git is ≤ 1.9 (Command Line Tools for 10.9): no
  post-1.9 git syntax anywhere that runs there, tests included (the
  `update-index --cacheinfo mode,sha,path` form broke report pushes once; `git init -b`
  broke the suite). If you are Claude on the Mac Pro: install, run `--selftest`, read
  `Logs/report.log`, report back.
- The Mac Pro *can* build the app, the tests, the shots and the icon with its own
  Apple LLVM 6.0: `make SDK=/`, `make SDK=/ test` (440/440 on 2026-10-30, branch shelf-sync),
  `make SDK=/ shots`, `make SDK=/ icon` (519/519 on 2026-10-30, branch shelf). Not `dist`
  (verify needs `dyld_info`), so `Shelf.zip` is still rebuilt on the MacBook.

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
- Each Mac that runs the app keeps its own State.plist and Lines/ (synced between Macs
  since 2026-10-30, below), and reports say `from: <host>`: the skill must combine the
  newest report from each Mac for help counts and lines.
- Sync between Macs (README "Sync between Macs", `RSSyncManager.h`, `RSMerge.h`): after
  each good pull, every other Mac's `Russian/Sync/<host>/` is merged in (progress, cards
  with sound, islands, tutor notes, monthly recordings), then this Mac's folder is
  published with the same private-index plumbing as reports, touching only that folder.
  Help counts and help lines are per-Mac facts and are never merged, so reports keep
  combining the newest from each Mac. Nothing about shelves, sealing or keys syncs.
- The Help counts, Kept lines and words, clips, Said and tutor notes in reports are for
  Claude choosing the next shelf (the level ladder in the skill); never show counts,
  scores or streaks in the app.
- **10.9 API only.** The Mac Pro builds against the 10.10 SDK, so a 10.10 method compiles
  and then crashes at run time (`-[NSString containsString:]` did, 2026-10-30). Use
  `rangeOfString:`; link only what 10.9 has (`libsqlite3` is allowed in `make verify`).
- Never rename the bundle identifier (`com.russianshelf.RussianShelf`: the Application
  Support folder, the keychain ACL and the sealed formats depend on it) or the sealed
  headers (`Russian Shelf 1` / `Russian Shelf sealed 1`); the rename to Shelf is the
  user-facing name, the executable and the icon only.
- The dictionary: `make dict DICT_SRC=<the CSV mirror> DICT_FREQ=<freqrnc2011.csv>`
  rebuilds `Resources/dict.sqlite` (34.7 MB, CC BY-SA 4.0 data; attribution in README);
  the tests use `Tests/Fixtures/dict.sqlite`, built the same way from `Tests/Fixtures/dict/`.

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

- 2026-10-30 (the redesign): the desk card, kinds and plates, the word slip and word
  cards, today's clip (its passes, the say-along recording), Say (the sand-glass, the
  microphone, the month's recording, the tutor's note, the islands editor) ran in tests
  and shots only; nobody has pressed the keys on the real Mac yet. The Say and
  say-along recordings use the built-in microphone through AVAudioRecorder.

- Sync between Macs (2026-10-30, branch shelf-sync): tested only through a bare
  repository (two app folders, git 1.9.5), never between the real two Macs and never
  with the MacBook's newer git pushing its own `Russian/Sync/<host>/` folder.

- 2026-10-27 (r1): L, −, K and the Lines window (with Tab for a meaning and the "say
  it in Russian" cards) and the H slip ran in tests and shots only; typing in the meaning
  field and clicking the slip over a playing AVPlayerView haven't been tried by a person. The sound
  cut (AVAssetExportSession, Apple M4A) is tested on 10.9.5 with a WAV in `make test`
  and on a real shelf video by `--selftest`; slower playback, the loop's pause and the
  review's AVAudioPlayer rate haven't been heard by a person yet.
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
