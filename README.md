# Russian Shelf

A shelf of about twelve Russian videos for the week, chosen by Claude, on the
Mac Pro (OS X 10.9). Click one and it plays in a plain window, with Russian
subtitles kept out of sight until you ask for a line.

It looks like a 2013 Mac app: a walnut bookcase with a brass nameplate, each
video standing on its own shelf beside a cream library card, a red silk
ribbon on the one to watch next and a green ПРОСМОТРЕНО stamp on the ones
you've finished. The transcript is ruled paper with a highlighter on the line
being spoken. Everything is drawn in `Sources/RSStyle.m` (the wood too), and
the icon, a small bookcase of white, blue and red books, in `Tools/mkicon.m`.

There is nothing else to do in it: no browsing, no search, no URL field, no
File > Open, no dragging a file in, no recommendations, no "up next". Claude
writes the week's list on the MacBook, seals it, and the app shows it. The
one other window holds the few lines you kept from those videos, to hear
again on later days.

The spine is [Sergey Storyteller](https://www.youtube.com/@SergeyStoryteller):
stories in easy Russian, made for learners. When his stories run short,
Claude adds one or two from Easy Russian or Comprehensible Russian.

## This is friction, not a vault

You own both machines. The encryption and signature stop the list being
edited, added to or read in the repo by accident or on a weak evening. They
can't stop someone who owns the MacBook's keychain, can rebuild the app, or
can run yt-dlp by hand. That's the point: it's a shelf, not a lock. The
honest way round it is to ask Claude.

## Thanks, and keep it private

The downloading is Wowfunhappy's: [media-subscriptions-prefpane][msp], a 10.9
preference pane that brings YouTube channels to the Movies folder. Its
`downloader.sh` is where the format sort, the H.264 level fix and the pace
of requests come from, and its `Deps/build-python.sh` built the Python this
app carries (adapted; see `Deps/`).

That repository has no licence, so this project is **local and private**: don't
publish it, and don't push it anywhere public.

[msp]: https://github.com/Wowfunhappy/media-subscriptions-prefpane

## Using it

The shelf window lists the week in Claude's order: thumbnail, title, channel,
length, and how far you've got (the furthest point you reached by playing).
The next one to watch has a blue bar and **NEXT**. Videos still downloading
show their progress; one that failed says why and is tried again within the
hour.

Click a video (or select it with ↑ ↓ and press Return) to play it.

| Key | In the player |
| --- | --- |
| Space | Play or pause |
| ← → | Five seconds back or on |
| ↓ | **Show this line.** It stays until the line ends (at least two seconds) |
| ↑ | **Hear this line again.** From its start; if the line has only just begun (under a second), the one before |
| S | Subtitles stay on (and off again) |
| T | The transcript: every line, the one being spoken marked. Click a line to go there |
| F | Full screen (or double-click the picture). Esc leaves it |
| L | **Loop this line.** It plays, then waits as long as it took (at least a second and a half) for you to say it back, then plays again. ↓ shows it for the whole loop. L, Space or an arrow stops |
| − | **Slower:** three-quarter speed, the voice's pitch kept. Again for full speed |
| K | **Keep this line**, with its sound, to hear again tomorrow and on later days (below) |

Subtitles are off when a video opens. Each video remembers where you left it.
A video counts as finished at 90%, and skipping ahead with the scrubber
doesn't count towards that.

### A line you missed

The keys follow what the research says trains the ear for fast speech
(`dendron-autopilot/reports/r1-research.md`): hear the line again (↑) a
time or two and try to say what it was; then show it (↓) and compare; slow
it down (−) only after a try at full speed, and go back to full speed;
loop it (L) and say it along in the pause. Keep (K) the few worth knowing.

### Lines to hear again

**Shelf > Lines to Hear Again** (⌘L) shows today's kept lines on an index
card, one at a time. When there are some, the shelf's nameplate says how
many.

| Key | |
| --- | --- |
| Space | Hear it again (it plays by itself when it comes up) |
| − | Three-quarter speed, and full speed again |
| ↓ | Show the line, and the one before it for context |
| ← | **Not yet.** Back tomorrow, from the start, and once more before today's are done |
| → | **Knew it.** Back later |
| ⌫ | Put it away for good |
| Esc | Close |

Sound first, so it's the ear that's tested, not reading. A line kept today
comes back tomorrow; each "knew it" waits longer: 3, 7, 16, 35, then 75
days, and after that it's known and put away. Six "not yet"s put it away
too: a line that hard is better met again in a story. At most **ten lines
kept a day** and **thirty heard again a day**, so the review stays a few
minutes and never grows into a backlog that eats the listening. Nothing is
counted, scored or kept in a row on screen. When today's are done it says
so and stops.

A kept line's sound is cut from the video when you keep it (the line, from
0.15 s before to 0.35 s after), so it stays when the video leaves the shelf.
If the cut fails the line is kept without it, and the card says to read it
aloud instead. Each Mac keeps its own lines.

## How the shelf gets here

```
MacBook                                         Mac Pro
-------                                         -------
Claude (skill russian-shelf)                    Russian Shelf, every hour,
  writes the list (plain text, never saved        at launch, at wake, ⌘R:
  in the repo)                                    git pull ~/Study
  shelfsign seal  ->  Russian/shelf.signed       checks the signature
  commits; asks you before pushing  ------>      decrypts, reads the list
                                                 downloads with yt-dlp
                    <------  Russian/Reports/    sends what was watched
```

### The list

```
Russian Shelf 1
start: 2026-10-12
video: JE4cI_Knzvc | Sergey Storyteller | She Cut Her Hair to Save Her Husband ✂️ Story in Easy Russian
video: ...
```

One to twelve `video:` lines, `id | channel | title`, in order. The title may
contain ` | `. `#` lines are comments. `shelfsign` adds `sealed: <date time>`
itself.

### Sealing

`shelfsign seal list.txt Russian/shelf.signed`:

1. reads the list with the app's own parser, so a list it accepts is one the
   app reads
2. encrypts it with **AES-256-CTR** (CommonCrypto) under a key built into the
   app, with a fresh 16-byte IV
3. signs `"Russian Shelf sealed 1\n" + IV + ciphertext` with **ECDSA P-256 /
   SHA-256**, using the key in the MacBook's login keychain
4. opens the result exactly as the app will, with the app's own code and keys,
   before writing it

```
Russian Shelf sealed 1
iv: <base64>
data: <base64>
signature: <base64, DER>
```

### The keys

- **The signing key** was made once (`make keys`, 2026-10-09) in the
  MacBook's **login keychain**, as "Russian Shelf signing key",
  **non-extractable**. It exists nowhere else: not in a repo, not in this
  project, not in a file. Its access list lets only a program signed as
  `com.russianshelf.shelfsign` with your Apple Development certificate use
  it, so a rebuilt `shelfsign` works without a keychain dialog and anything
  else gets one.
- **The public key** and **the AES key** are in `Sources/RSKeys.c`, built
  into the app. The AES key is no secret from anyone with the app (see
  above).
- `make keys` refuses to run again. If the signing key were ever lost, new
  keys mean a new `RSKeys.c`, a rebuilt app on the Mac Pro, and shelves
  sealed again.

### Checking it on 10.9

10.9 has no `SecKeyVerifySignature`, and its SDK doesn't declare
`SecKeyRawVerify` for the Mac. The app uses what 10.9 does have:
`SecItemImport` to load the public key (DER SubjectPublicKeyInfo, as
`kSecFormatOpenSSL`) and a `SecVerifyTransform` with SHA-2/256 over the
signed bytes. Only then does it decrypt (CommonCrypto, AES-256-CTR) and read
the list.

### What it refuses

A new `shelf.signed` is turned away, and the last good shelf kept, if:

- the signature doesn't match (an edited file, the wrong key, a signature
  borrowed from another file, a swapped IV)
- it has more than 12 videos, or any line that doesn't read
- it isn't a sealed shelf at all, is damaged, or doesn't decrypt
- it's older than the newest shelf the app has: an earlier start, or the
  same start sealed earlier. An old file can't come back

The status line says which, in a sentence. Shelves the app has stored are
checked again at every launch.

### Rotation

A shelf whose start day has come becomes this week's at once. One that
arrives early waits, its videos downloaded ahead, and takes over on its start
day. Videos are kept by id, so a story on both shelves (one you didn't
finish) is downloaded once and keeps its place. Once every video on this
week's shelf is downloaded, everything on neither shelf is deleted.

## Downloading

Everything lives in `~/Library/Application Support/Russian Shelf/`, not
`~/Movies`, so there is no pile of videos to browse:

| | |
| --- | --- |
| `Shelf.signed`, `Next Shelf.signed` | the shelves, as they arrived |
| `State.plist` | how far each video has been watched; why the last shelf was turned away |
| `Videos/<id>/` | `video.mp4`, `subtitles.vtt`, `thumbnail.jpg`, `info.plist` |
| `Downloads/<id>/` | a download in progress |
| `yt-dlp`, `Cache/`, `Logs/` | the downloader, its cache, the last run's output per video, and what git said the last time a report was sent (`report.log`) |
| `Outbox/` | reports not sent yet |
| `Lines/` | kept lines: `Lines.plist` (each line, its video, when it comes back) and `<id>-<ms>.m4a`, its sound. Kept when videos are deleted |

Before each batch the app updates its copy of yt-dlp (`--update`), and then
fetches one video per run from `https://www.youtube.com/watch?v=<id>`,
where the id comes only from a shelf that opened. The yt-dlp command line
follows the prefpane:

- its format sort (`+hdr,res,fps,vcodec:h264,…,acodec:aac,…`), at most
  1080p, as MP4, asking first for H.264 + AAC, which is what 10.9's
  AVFoundation plays
- its H.264 level fix: `Merger+ffmpeg_o1:-bsf:v h264_metadata=level=auto`
- a thumbnail, converted to JPEG
- Russian subtitles: `--write-subs --write-auto-subs --sub-langs ru,ru-orig`.
  The app keeps the one a person made when there is one, otherwise YouTube's
  speech recognition (`ru-orig`), as a sidecar `.vtt` it parses. Nothing is
  embedded in the MP4
- its pace: `--retry-sleep 30 --sleep-subtitles 8 --sleep-requests 1.5
  --sleep-interval 15 --max-sleep-interval 40`

It differs from the prefpane where the prefpane would be wrong here:

- **Certificates are always checked.** The prefpane passes
  `--no-check-certificates`, even to the self-update, which downloads code.
  Here Python's OpenSSL is pointed at the bundled certifi list
  (`SSL_CERT_FILE`, since this Python can't find certificates by itself), and
  `make tlstest` proves it: without that list nothing is trusted; with it
  YouTube and GitHub are; a self-signed server on this Mac and badssl.com's
  expired, self-signed, wrong-host and untrusted-root certificates are
  refused, by Python and by yt-dlp.
- **QuickJS, not deno.** yt-dlp needs a JavaScript runtime for YouTube's
  player challenges. The prefpane's deno has a minimum OS of 10.12, loads
  `/usr/local/lib/libMavericksLegacySystem.B.dylib` (not part of OS X), and
  imports `clock_gettime`, `getentropy`, `openat` and 11 more functions 10.9
  doesn't have. QuickJS 2026-06-04, built here against the 10.9 SDK (1 MB),
  does the same job.
- **Python rebuilt** with the prefpane's own script, using Xcode's clang and the
  real 10.9 SDK. The prefpane's build carries `<name>.eh` symbols in four
  modules that today's dyld refuses. It would likely still load on 10.9, but it
  couldn't be tested here.
- `--ignore-config --no-plugin-dirs --no-playlist --match-filters id=<id>`: no
  config file, plugin or playlist can add anything to a download.

`make verify` checks every bundled binary (Python, its 100-odd modules,
ffmpeg, QuickJS) against the 10.9 SDK with `Tools/check109.sh`: its minimum
OS, every library it loads, and every symbol it imports.

## Subtitles

YouTube gives two kinds, and the app reads both from WebVTT:

- **Made by a person.** Ordinary cues of a line or two, kept as they are.
- **Speech recognition.** A rolling two-line window: every cue repeats the
  line before, new words arrive with a timestamp each, and a 10 ms cue flashes
  the finished line in between. Read naively that's every line three times,
  broken wherever the speaker paused. The app reads each new line once, word
  by word, and sets the words again as sentences (broken after a comma past
  84 characters, and at pauses over two seconds), each starting with its first
  word.

`JE4cI_Knzvc` has both: Russian subtitles made by a person (`ru`), and
speech recognition (`ru-orig`). The tests use the first minute of each.

## What was watched

When a video is finished, when the player closes after you've watched
something (or asked for a line), and when a shelf is replaced, the app
writes a report:

```
Russian Shelf report
shelf: 2026-10-12 (sealed 2026-10-11 20:15:07)
written: 2026-10-14 21:05
from: Ashwins-Mac-Pro

JE4cI_Knzvc | finished | 19:20 of 19:20 | She Cut Her Hair to Save Her Husband ✂️ Story in Easy Russian
abcdefghijk | partly | 4:10 of 11:30 | The Fox and the Crane
lmnopqrstuv | not started | 0:00 of 9:12 | ...

Help (lines shown, heard again, kept):
JE4cI_Knzvc | shown 12 | heard again 8 | kept 2

Kept:
JE4cI_Knzvc | 4:10 | Она отрезала волосы, чтобы спасти мужа.
```

- `from:` is the Mac's host name. Each Mac keeps its own record of what was
  watched on it, so a shelf watched on two Macs has two sets of reports: the
  newest from each Mac counts.
- **Help** (only for videos where something was asked for): how many times a
  line was shown (↓), heard again (↑ or a loop), and kept (K). It's how Claude
  can tell whether a shelf is at the right level: a lot of help means stay at
  this rung, little means move up. The app never shows these numbers.
- **Kept** lists the lines kept from this shelf's videos, one per line (a
  two-line cue joined with " / ").

It adds it as a new file, `Russian/Reports/shelf-<start>_<when>.txt`, in one
commit that adds that file and nothing else. The commit is built in a
private index on top of the remote branch and checked before pushing. The
clone's own index, working tree and branch are never touched, so a push
that fails (while the Mac Pro's key can only read) leaves nothing behind to
trip Syllabus's `git pull --ff-only`. Reports wait in `Outbox/` until the key
can write. It never writes anywhere else in the repo, and never to `Inbox/`
(WatDash's).

Pulls are Syllabus's (`SYSync.m`): `git pull --ff-only`, git over SSH with
`BatchMode=yes` (`Resources/shelf-ssh`), no prompts, a two-minute limit. When
Syllabus is pulling the same clone at the same moment and holds
`index.lock`, the pull waits and tries again for about twenty seconds.

## On the Mac Pro

`Mavericks Projects/Mac Pro Setup.zip` does it all: copy it over, unzip it,
double-click "Set Up Mac Pro". It installs this app with Syllabus and
Postview, gives the Mac its read-write deploy key for `ashp0/Study` (the
private study repository, `~/Documents/University of Waterloo Classes` on the
MacBook), clones it to `~/Study`, runs the self-test below, and adds the apps
to Login Items. The app reads `~/Study/Russian/shelf.signed`, the clone
Syllabus uses. (The `StudyFolder` default changes that, for testing.)

`Russian Shelf.app/Contents/MacOS/RussianShelf --selftest` checks everything
the app relies on, on the Mac it runs on, and prints a line each:

- the real key opens a sealed shelf through 10.9's Security framework, and an
  altered one doesn't
- AES and both kinds of subtitles
- Python, QuickJS, ffmpeg and yt-dlp start
- certificates: YouTube's accepted, bad ones refused (needs the network)
- git, `~/Study`, and the shelf in it
- a downloaded video is one AVFoundation can play, and a line's sound can be
  cut from it

## Building

```
make            build/RussianShelf.app
make test       the model, under Rosetta: crypto, the shelf format, sealed files
                (good, tampered, wrong key, too many videos), decryption, subtitles
                of both kinds, rotation and deletion, kept lines and their days,
                cutting a line's sound, the yt-dlp command lines, reports, real git
                pulls and report pushes against a bare repository
make tlstest    the certificate checks above (needs the network)
make shots      the shelf, the player and the Lines window, rendered to build/shots
make verify     the app and every bundled binary are Mavericks-compatible
make analyze    the static analyser
make dist       all of these, then Russian Shelf.zip
make shelfsign  build/shelfsign, for the MacBook
```

Like Syllabus, it's built with today's Xcode against the real 10.9 SDK in
`~/Developer/SDKs/MacOSX10.9.sdk`, with manual retain/release, and `make
verify` checks every Foundation name the linker bound to CoreFoundation
against what 10.9's CoreFoundation exports.

`shelfsign` is code-signed with `SHELFSIGN_IDENTITY` (default "Apple
Development", the only identity on this Mac).

`Deps/README.md` says where each bundled tool comes from and how to rebuild it.

All styling is in `Sources/RSStyle.m`. The views decide what goes where and
ask it for every font, colour and shape.
