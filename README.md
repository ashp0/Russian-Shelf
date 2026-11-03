# Shelf

A walnut bookcase of about twelve Russian videos for the week, chosen by
Claude, on the Mac Pro (OS X 10.9), and the desk around them: a card that says
what today holds, a dictionary for any word in a line, a daily clip worked in
three passes, cards to hear again on spaced days, and a speaking practice with
the microphone. Russian Shelf until 2026-10-30; `DESIGN.md` is why it changed
(the research is in the Russian Fluency Brief of 2026-10-30 and
`dendron-autopilot/reports/r1-research.md`).

It looks like a 2013 Mac app: the bookcase with a brass nameplate, each video
standing on its own plank beside a cream library card, a red silk ribbon on
the one to watch next and a green ПРОСМОТРЕНО stamp on the ones you've
finished; brass plates over each group of videos; ruled index cards for the
rest. Everything is drawn in `Sources/RSStyle.m` (the wood too), and the icon,
a small bookcase of white, blue and red books, in `Tools/mkicon.m`.

There is nothing to browse in it: no search, no URL field, no File > Open, no
dragging a file in, no recommendations, no "up next". Claude writes the week's
list on the MacBook, seals it, and the app shows it. Nothing is counted,
scored or kept in a row: the only numbers on screen are how many cards wait
and facts about words.

The spine is [Sergey Storyteller](https://www.youtube.com/@SergeyStoryteller):
stories in easy Russian, made for learners, with one or two fast native
videos a week (Easy Russian's street interviews) to work line by line.

## Four things, in order

The research (DESIGN.md) says a learner needs four kinds of time, and that an
intermediate stalls when the easy one crowds out the others:

1. **Listening you understand**, most of the time: the bookcase, in kinds.
2. **A short deliberate slice**, ten to fifteen minutes: today's **Clip**, the
   dictionary (**W**), and the **Cards**.
3. **Speaking as a skill**, which only speaking builds: **Say**.
4. **Habit, not willpower**: the **desk card**, which removes the decision.

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

### The bookcase and the desk card

The shelf window shows the week in three groups, each under a small brass
plate: **Easy stories**, **Natural speech**, **Fast speech** (the list's kinds,
from the `# kind:` lines Claude writes, or history.txt, or a guess from the
channel and title). In each group, Claude's order: thumbnail, title, channel,
length, how far you've got. The next one to watch has the ribbon and **NEXT**.
Videos still downloading show their progress; one that failed says why and is
tried again within the hour.

Under the nameplate, a cream card says what today holds, in the research's
order, one line each, each a click away:

```
Today
Cards        7 to hear again                         ⌘L
Clip         What Are You Doing Today?, 2:10–4:40     ⌘K
Say          «Мой университет», 2·1½·1                ⌘S
Then watch   Теремок                                 Return
```

A line is there until its thing is done for the day, then gone: no ticks, no
counts of days. If nothing is waiting the card says only what to watch. Click
any line in any order; the order is a suggestion (short retrieval first while
fresh, the hard slice second, speaking third, the long easy listening last).

Click a video (or select it with ↑ ↓ and press Return) to play it.

### The player

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
| − = | **Slower, faster:** a ladder of 1.0, 0.9, 0.8, 0.7, 0.6 and 0.5, the voice's pitch kept (nothing under 0.5: there the words smear). The note says the speed ("0.6×"). A video reopens at the speed it was left at; the report carries the slowest ever chosen for it |
| K | **Keep this line**, with its sound, as a card to hear again tomorrow and on later days (below) |
| W | **A word.** A slip over the picture with the line's words as small cards, the rarest chosen first (the one you most likely don't know): its lemma with the stress marked, what kind of word, two or three English glosses, and where it stands in the frequency list (*common: 1,840th · less common: 6,200th · rare: past the common 10,000*). ← → choose a word (or click one), **K keeps the word** as a card with its line's sound, W or Esc closes |
| C | **A clip from here** (below): from the line being said, two to three minutes on, whenever you want to shadow; C again leaves it |
| H | **How was this video?** A slip at the top of the picture: *too easy · about right · too hard* and *more like this · less like this*. One click each, about the video, never a score; click a chosen word again to take it back, ✕ or H to put it away, or just ignore it (it goes by itself). It also comes up once by itself when the video is 90% watched, unless both are already chosen |

Subtitles are off when an easy or natural video opens. A **fast** video opens
with Russian subtitles **on** the first time through (the research for hard
native video: same-language captions help, English ones hurt), and off from
the second viewing; S still toggles. Each video remembers where you left it.
A video counts as finished at 90%, and skipping ahead with the scrubber
doesn't count towards that.

The dictionary is OpenRussian's (en.openrussian.org, CC BY-SA 4.0; the CSV
mirror at github.com/Badestrand/russian-dictionary), 46,000 lemmas with their
forms, built into `Resources/dict.sqlite` by `Tools/mkdict.py`; the ranks are
the Russian National Corpus's (Lyashevskaya & Sharoff, *A Frequency Dictionary
of Modern Russian*, 2009, dict.ruslang.ru/freq.php). It works offline; 10.9's
own SQLite reads it. Pronoun cases are added by hand (the dump has no forms
for them); ё and е both find a word.

### A line you missed

The keys follow what the research says trains the ear for fast speech: hear
the line again (↑) a time or two and try to say what it was; then show it (↓)
and compare; slow it down (−) only after a try at full speed, and go back to
full speed; loop it (L) and say the whole sentence back in the pause (for
someone who speaks in short phrases, saying native sentences whole is practice
in building them). Look up (W) the word that stopped you and see whether it's
worth keeping: a common word is, a rare one can wait. Keep (K) the few worth
knowing: a new verb, a chunk you'd like to say yourself.

### Today's clip (⌘K)

Two or three minutes of the week's fast video (or the natural one, or any
with subtitles a person made), chosen once a day: it starts at the line you
asked for most help on in earlier viewings (replayed, shown, looped, looked
up) that no earlier clip covered, else at the first line after the last clip
worked, and ends on a sentence boundary. A ruled card at the top of the
picture walks three passes (ten to fifteen minutes; the deliberate kind of
listening: bottom-up decoding, shadowing, words met on purpose):

1. **Listen.** No text. The stretch plays twice.
2. **Read.** Captions on; it pauses after each sentence. Space goes on, W
   looks a word up, K keeps the sentence or the word, ↑ hears it again, − and
   = change the speed.
3. **Say along.** Each sentence once to hear, then again for you to speak
   over it. **R** records your say-along through the built-in microphone and
   plays it back after the speaker's, so you hear the two next to each other.

The lines of passes 2 and 3 are whole sentences, or what one person said: a
cue that doesn't end a sentence is joined with the next (at most two), so a
line replayed with ↑ is one thing one person said. A **fast** video's clip
climbs a speed ladder, 0.6× for the listening, 0.8× for the reading, full
speed for the say-along (the research: let the listener set the rate, then
fade it); − and = during a pass still override it; any other video's clip
runs at full speed. Your say-along plays back at the speed you said it.

Then: "Done." Shadowing isn't rationed: **C** in the player starts a clip
from the line being said, whenever you like, and ⌘K after today's is done
chooses the next stretch. The desk card names today's clip until its three
passes are done; a clip half worked is picked up where it stopped. ← → or C
leave the clip. Reports say which stretches and how far each got.

Never on YouTube's automatic captions: their lines are cut every few words
at arbitrary points, so they aren't what anyone said and say-along can't
work on them. A video with only those gets no clip; the player says so when
C is pressed, and the desk card names the video. The skill makes Russian
subtitles for such a fast video and seals them with the shelf (below).

### Cards (⌘L)

**Shelf > Cards** shows today's kept lines and words on an index card, one at
a time. When there are some, the desk card says how many.

| Key | |
| --- | --- |
| Space | Hear it again (it plays by itself when it comes up). On a "say it" card: hear it and see it |
| − | Three-quarter speed, and full speed again |
| ↓ | Show the line, and the one before it for context. On a word card, the word is underlined in its line, with its lemma and gloss under it |
| Tab | **Write what it means**, in your own words, under the shown line. Return keeps it, Esc leaves it as it was |
| ← | **Not yet.** Back tomorrow, from the start, and once more before today's are done |
| → | **Knew it.** Back later |
| ⌫ | Put it away for good |
| Esc | Close |

Sound first, so it's the ear that's tested, not reading. A card kept today
comes back tomorrow; each "knew it" waits longer: 3, 7, 16, 35, then 75
days, and after that it's known and put away. Six "not yet"s put it away
too: a line that hard is better met again in a story.

**Both ways, once it has your words.** The first time a line is shown, write
what it means (Tab). From then on it comes up turn about: as its sound
(understand it) and, every other time after the first "knew it", as **your
words in blue ink: say it in Russian**, aloud, as a whole sentence; then ↓
plays the speaker and shows the line, to compare. Hearing and understanding
trains the ear; saying it from the meaning trains the speaking (recalling the
Russian from the meaning builds what you can say, not just what you
recognise). A word card has its gloss as its meaning from the start, so it
comes both ways at once; a line without your words is only ever heard.

At most **fifteen cards kept a day** and **sixty heard again a day** (about
twenty minutes), counting the other Mac's day too, and K keeps nothing while
**forty-five are already waiting**: the review never grows into a backlog
that eats the listening. These sizes are for an A2–B1 learner adding about
fifteen items a day. When today's are done it says so and stops.

A kept line's sound is cut from the video when you keep it (the line, from
0.15 s before to 0.35 s after), so it stays when the video leaves the shelf; a
word card shares its line's sound. If the cut fails the card is kept without
it, and says to read it aloud instead.

### Say (⌘S)

The speaking practice, on an index card with a sand-glass. **Islands** (⌘I)
are the topics you can talk about, in Russian, one a line, yours to edit; it
starts with eight for a Waterloo student (Мой день, Университет и учёба, Моя
семья, Непал, Что я смотрел на этой неделе, Еда, Планы на выходные, Почему я
учу русский). Each day proposes the next island in turn, or **Перескажи:
«story»** when you finished a story today (retelling is task repetition).

The same topic **three times, shorter each time**: 2 min · 1½ · 1 by default
(Shelf > Pass Lengths also has 3·2·1½ and 4·3·2; Nation's 4/3/2). Space starts
a pass; the sand runs down; each pass is recorded through the built-in
microphone. After the third:

| Key | |
| --- | --- |
| Space | Hear the last pass |
| Tab | **A note for the tutor**: something you fumbled or lacked, up to three a day, kept in `Say/Tutor.txt` under the date and carried in reports |
| M | **Last month**: play the previous month's recording, then today's, back to back. Your own voice, two dates, no number |
| ⌘I | The islands, written on the card (⌘I or Esc keeps them) |
| Esc | Close |

**Whenever you like, another round.** ↑ ↓ choose another topic (the islands
in turn, after any retelling that's waiting) and Space starts a fresh round;
the desk card counts only the day's first. When the topic retells one of the
week's readings (Перескажи: «story»), a fourth, half-minute pass follows the
three: the lesson in your own words, and then the story's own line to compare.

**Every recording stays**, by day (`Say/Recordings/YYYY-MM-DD/`: the passes,
a reading's reads aloud, recordings made on their own), none deleted, so you
can hear this week next to last week and catch your own errors. **R** lists
them, newest first: ↑ ↓ choose, Space plays, Tab names one, **N** records a
new one on your own (up to fifteen minutes; Space or N stops), Esc comes
back. The last pass of the **first Say of each month** also stays as the
month's recording (`Say/Recordings/YYYY-MM.m4a`), the one that syncs between
the Macs. Without a microphone the sand still runs and the card says so once.

### Reading (⌘D)

Six short stories a week, each with a life lesson, and a poem, written by
Claude on the MacBook from the words you've met on the shelf (the videos'
subtitles and the words you kept: at least 95% known running words, 5–8 new
ones used three times or more) and sealed with the shelf
(`Russian/reading.signed`, below), so you can't add or change them. The
stories take the shape Sergey's tales do (Жил-был… / Однажды…, the problem,
three tries, the turn, the end, Мораль: …), on the topics of your islands and
of student life; after three of the owner's own rhymed fables come real ones,
Крылов first. Stress marks on every word of two syllables or more.

One a day from the week's start, the poem last and staying up until next
week's arrive; ← → open the week's others. The day's reading is on the desk
card ("Read"), and comes up on a sheet of paper in Georgia. **Three reads,**
the way a clip has three passes:

1. **Silently,** at any pace. Click a word and **W** looks it up (the slip
   from the player: lemma with its stress, kind, glosses, rank; ← → along the
   sentence); **K** keeps it as a card with its sentence, to read aloud when
   it comes back. **A** hides the stress marks, and shows them again.
2. **Aloud, recorded.**
3. **Aloud again, recorded;** then Space plays read 2, then read 3, so you
   hear the difference.

Space starts a read and ends it. The sheet shows "read 2 of 3" and the
read's own clock; the time of each read goes to the report only (the research
wants rereads, not a timer: repeated reading is what builds rate and
fluency). After the third read, Say offers to retell the story (⌘S).

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

A `subtitles: <id> <sha-256 in hex>` line seals a Russian subtitle file the
skill made for a fast video whose own track doesn't match the speech (Easy
Russian's subtitles are burned into the picture; YouTube's automatic captions
aren't what anyone said). The file goes in `Russian/Subtitles/<id>.vtt`
(ordinary WebVTT, a sentence or a turn a cue); the app takes it only while
its hash is the sealed one, checked again every time it's read, and uses it
over the downloaded track for captions, the transcript and the clip.

### The readings

```
Russian Reading 1
start: 2026-11-09
story: 1 | Че́стный студе́нт | Че́стность доро́же оце́нки.
new: обману́ть, экза́мен
Жил-был студе́нт. Он учи́лся в университе́те…

Но вдруг… экза́мен!
story: 2 | …
poem: Стрекоза́ и Мураве́й | Ива́н Крыло́в, 1808 | Кто ле́том поёт, тот зимо́й голода́ет.
metre: четырёхстопный хорей, парная рифма
Попрыгу́нья Стрекоза́
Ле́то кра́сное пропе́ла;
```

A `story: number | title | lesson` or `poem: title | by | lesson` line begins
a reading (stories count 1, 2, 3…; the lesson in one line, as it will be
retold); `new:` lists its new words, `metre:` a poem's metre and rhyme in a
few words; everything up to the next reading is its text (a story's lines run
together into paragraphs at blank lines; a poem keeps its lines). Stress
marks are the combining acute (U+0301). At most seven readings, each up to
8,000 characters. `shelfsign seal readings.txt Russian/reading.signed` seals
it exactly as a shelf (the same key, the same sealed file format: the inside
says which it is), and the app takes it by the shelves' rules: newer only, an
early one waiting for its start day. Each reading's key is
`<start>-<number>` (`2026-11-09-3`); its words kept are cards under that key.

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
| `Reading.signed`, `Next Reading.signed` | the week's readings and the next week's, as they arrived |
| `State.plist` | how far each video has been watched, at what speed; clips, Say rounds and reads; why the last shelf or readings were turned away |
| `Videos/<id>/` | `video.mp4`, `subtitles.vtt`, `thumbnail.jpg`, `info.plist` |
| `Subtitles/<id>.vtt` | subtitles the skill made, taken from `Russian/Subtitles/` only while their SHA-256 is the one sealed in the shelf |
| `Say/` | `Islands.txt`, `Tutor.txt`, `Recordings/YYYY-MM-DD/` (every recording, kept) and `Recordings/YYYY-MM.m4a` (the month's) |
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
from: Ashwin’s Mac Pro

JE4cI_Knzvc | finished | 19:20 of 19:20 | She Cut Her Hair to Save Her Husband ✂️ Story in Easy Russian
abcdefghijk | partly | 4:10 of 11:30 | The Fox and the Crane
lmnopqrstuv | not started | 0:00 of 9:12 | ...

Help (shown, heard again, looped, slowed, transcript, subtitles, looked up, kept):
JE4cI_Knzvc | shown 12 | heard again 8 | looped 2 | slowed 1 | transcript 1 | subtitles 0 | looked up 3 | kept 2 | slowest 0.6

How it felt (the owner's own choice, about the video):
JE4cI_Knzvc | about right | more like this

Lines help was asked on:
JE4cI_Knzvc | 4:10 | shown 1, heard again 3, looped 1 | Она отрезала волосы, чтобы спасти мужа.

Clips worked (stretch | passes of 3 | day):
abcdefghijk | 2:10–4:40 | passes 3 | day 2026-10-14

Kept:
JE4cI_Knzvc | 4:10 | Она отрезала волосы, чтобы спасти мужа. | means: She cut off her hair to save her husband.

Words kept (word (lemma) | gloss | the line):
JE4cI_Knzvc | 4:10 | отрезала (отре́зать) | cut off | in: Она отрезала волосы, чтобы спасти мужа.

Said (day | topic | passes of 3 | recorded):
2026-10-14 | Мой день | passes 3 | recorded
2026-10-14 | Еда | passes 3 | recorded | round 2

Read (day | story | reads of 3 | times | recorded):
2026-10-14 | Честный студент | reads 3 | 4:10 · 3:05 · 2:50 | recorded

Reading words kept (word (lemma) | gloss | the sentence):
2026-10-12-1 | обмануть (обману́ть) | deceive | in: Но Вася не хотел обмануть учителя.

For the tutor:
## 2026-10-14
я путаю винительный и родительный
```

- `from:` is the Mac's name in Sharing (not its network host name, which can
  change with the wifi). Each Mac keeps its own record of what was
  watched on it, so a shelf watched on two Macs has two sets of reports: the
  newest from each Mac counts. Since the Macs sync (below), the first lines
  (finished, how far) and how it felt are the same in both. Help, the lines
  help was asked on and Kept are still each Mac's own.
- **Help** (only for videos where something was asked for): how many times a
  line was shown (↓), heard again (↑), looped (L), slowed (− turned on), the
  transcript opened or a line in it clicked (T), subtitles turned on (S), and
  kept (K).
- **How it felt**: the owner's own word on the video from the H slip, `-` for
  a question left alone. Only videos where something was chosen.
- **Lines help was asked on**: each line, by time, with what was asked on it
  (at most 40 a video, then "… and N more lines"). This is where Claude on the
  MacBook sees *which* verbs, endings and reductions needed help; the app
  doesn't try to sort words into verbs and nouns itself (Russian needs a real
  morphological dictionary for that, which the Mac Pro doesn't have).
- **Kept** lists the lines kept from this shelf's videos, one per line (a
  two-line cue joined with " / "), with `means:` and the owner's own words
  when they wrote some. **Words kept** lists the word cards: the word as it
  stood, its lemma with the stress, the gloss, and the line.
- **Clips worked**: each stretch of a video worked as today's clip, how many
  of its three passes were finished, and the day. **Said**: each day of this
  shelf a Say was done, the topic, how many passes, whether the microphone
  caught it. **For the tutor**: the owner's own notes, by date, as written.

All of it is for Claude choosing the next shelf (the level mix, more or less of
a kind, which verbs to look for). The app never shows these numbers.

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

## Sync between Macs

Each Mac still keeps its own `State.plist` and `Lines/`, and its own reports.
On top of that, after every pull that worked (each hour, at launch, at wake,
⌘R), both Macs end up with the same progress, cards and their sound, islands,
notes for the tutor and the month's recordings. All of it goes through the
study clone both already pull and push. The app shows nothing about it except
one sentence in the status bar when a round fails.

Each Mac writes only its own folder, `Russian/Sync/<host>/`. `<host>` is the
Mac's name in Sharing, in Latin letters, lower case, with hyphens
(`ashwins-mac-pro`; `RSSyncFolder +slugForName:`):

```
Russian/Sync/<host>/State.plist          the Mac's State.plist
                    Cards.plist          its Lines/Lines.plist
                    Cards/<key>.m4a      each card's sound
                    Islands.txt          Say/Islands.txt
                    Tutor.txt            Say/Tutor.txt
                    Recordings/YYYY-MM.m4a   Say/Recordings/
```

`Say/Today/` is each Mac's own and never goes anywhere. The round
(`RSSyncManager.h`):

1. Every other Mac's folder is read out of the commit the clone is at
   (`git archive`) into `Sync In/` in the app's folder. It is never read from
   the working tree, which Syllabus may be updating at that moment. When the
   other Macs' folders at that commit are as they were last round (one
   `git ls-tree`), `Sync In/` is already right and isn't read again.
2. With the library and the cards saved first, on the main thread (so
   nothing done on this Mac in between can be lost), the other Macs' files are
   merged into the files here, and the app reads them again. While the Lines
   window is open its cards are left alone until the next round.
3. The files here are copied into `Sync Out/`.
4. `Russian/Sync/<host>/` is made equal to `Sync Out/`: paths there are
   added, updated and deleted, in one commit built in a private index on top
   of the remote branch. The commit is checked to change nothing outside
   that folder, then pushed and pulled, as reports are. Nothing is committed
   when nothing changed. If the other Mac pushed first, this one fetches and
   builds the commit again. A key that can only read leaves the clone as it
   was. This step and the reports' push run one after the other, never at
   once. When `Sync Out/` and this Mac's folder upstream are as the last
   publish left them, there is nothing to do and nothing is run, not even a
   fetch (the app remembers that only while it runs).

The merge (`RSMerge.h`, pure functions; deterministic and idempotent, so both
Macs end alike):

- **Progress**, per video: the furthest point and the duration are the larger;
  finished on either Mac is finished; the position is that of the Mac that
  got further (as far on both: the later position). How it felt and more or
  less like this: this Mac's if it chose one, else the other's. **Help counts
  and the lines help was asked on are not merged**: each Mac reports its own,
  as before. A video only the other Mac has comes in with its progress only.
  Clips: one per stretch, the one with more passes. Say: by day, this Mac's
  day if it has one. The notice, and anything the merge doesn't know: this
  Mac's.
- **Cards**, by key: the card heard most recently wins, unknown keys
  included. If both were heard the same day, the higher step wins, then the
  one put away, then the one with more lapses. A key only the other card has
  is kept, so a Mac running an older Shelf, which saves its cards without
  keys it doesn't know, can't erase a word's details everywhere. A card put away on either Mac
  stays put away, since nothing ever takes a card back out. A meaning
  written on either Mac is kept. A card only one Mac has is kept, with its
  sound. Cards are in the order kept. Today's count of cards heard is each
  Mac's own.
- **Islands**: this Mac's in its order, then the other's new ones. **Notes for
  the tutor**: sections by their `## YYYY-MM-DD` heading, in date order; a day
  both wrote keeps both Macs' lines. **Recordings**: a month this Mac lacks is
  copied; a month's recording is never replaced.

Deleting is not synced. An island removed on one Mac, or a month's recording
deleted, comes back from the other. Merged text only grows.

The daily brakes (fifteen kept, sixty heard) can count the other Mac's day:
`+[RSSyncManager heardTodayOnOtherHosts:today:]` (its count of lines heard
today, as of its last sync) and `keptTodayOnOtherHosts:today:` (cards it kept
today that this Mac doesn't have yet).

What git said each round is in `Logs/sync.log`.

## Battery

Left alone, with the bookcase showing, the app sleeps: no timers but the
hourly round and the five-minute day check (both with tolerance, so OS X can
run them with other wakeups), no polling, App Nap allowed. Measured on the Mac
Pro (2026-10-31, `proc_pid_rusage`): idle, about 0 % of the CPU and a few
wakeups a minute; a quiet round, one `git pull` (about 0.8 s of git 1.9's CPU)
and two `git ls-tree`. Playing costs what AVFoundation's decoding costs (about
4 % here); AVKit keeps the Mac awake only while a video plays. A Say pass,
about 1.4 % for its minutes. The heavy things run rarely: yt-dlp (about 10 s
of CPU a video, once, when a shelf arrives; a video that fails is tried again
each round), the sound cut when a line is kept.

What keeps it that way: views mark only the rect that changed (`make shots`
checks the bookcase and the sand-glass pixel for pixel); a timer exists only
while something moves; files are written only when they change
(`RSWritePlist`), so the sync sees nothing new when there is nothing new.

## On the Mac Pro

`Mavericks Projects/Mac Pro Setup.zip` does it all: copy it over, unzip it,
double-click "Set Up Mac Pro". It installs this app with Syllabus and
Postview, gives the Mac its read-write deploy key for `ashp0/Study` (the
private study repository, `~/Documents/University of Waterloo Classes` on the
MacBook), clones it to `~/Study`, runs the self-test below, and adds the apps
to Login Items. The app reads `~/Study/Russian/shelf.signed`, the clone
Syllabus uses. (The `StudyFolder` default changes that, for testing.)

`Shelf.app/Contents/MacOS/Shelf --selftest` checks everything
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
make            build/Shelf.app
make test       the model, under Rosetta: crypto, the shelf format and its kinds,
                sealed files (good, tampered, wrong key, too many videos),
                decryption, subtitles of both kinds, rotation and deletion, cards
                (lines and words) and their days, the dictionary, today's clip,
                Say, cutting a line's sound, the yt-dlp command lines, reports,
                real git pulls, report pushes and the sync between two app
                folders against a bare repository
make tlstest    the certificate checks above (needs the network)
make shots      the shelf, the player, the slips and cards, Cards and Say, to build/shots
make verify     the app and every bundled binary are Mavericks-compatible
make analyze    the static analyser
make dist       all of these, then Shelf.zip
make shelfsign  build/shelfsign, for the MacBook
make dict       Resources/dict.sqlite from OpenRussian's CSVs and the RNC list:
                make dict DICT_SRC=<folder> DICT_FREQ=<freqrnc2011.csv>
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
