# Shelf — the redesign (2026-10-30)

Russian Shelf becomes **Shelf**: still a sealed weekly bookcase of Russian videos that Claude chooses, still a 2013 Mac
app with no browser, feeds, scores or streaks, and still the same locks. What changes is what the app does with the
owner's time around the videos. Today it serves one of the four things a language learner needs (listening to easy
Russian) and a sliver of a second (kept lines). The redesign gives each of the four its own place, sized by the
research in `~/dendron-autopilot/reports/r1-research.md` and the 2026-10-30 Russian Fluency Brief
(`~/Desktop/Russian Fluency Brief.html`; sources inside).

## The owner

A2–B1 (grammar near B1, vocabulary behind, speaks in fragments, follows 30–50% of a Russian friend's fast speech).
Goals: speak well; read real Russian books and a school geography textbook by early 2027; follow fast native speech.
First-year Waterloo student with a light course load, so time exists; what is scarce is decision energy and the habit.
They asked for easy Russian to stay most of the shelf (so endings become automatic), one or two fast native videos a
week, content feedback never scores, and nothing that nags.

## Why these four, in this order (the research in one paragraph each)

1. **Input you understand** (Nation's meaning-focused input strand). Learning from viewing is slow per hour and only
   happens at ~90–98% comprehension; staying with one series raises repeated encounters (Webb & Rodgers 2009; Rodgers &
   Webb 2011; Webb, Uchihara & Yanagisawa 2023). Same-language captions help listening and words; English subtitles hurt
   speech perception (Mitterer & McQueen 2009; Montero Pérez et al. 2013). So: the sealed shelf stays the engine, with
   kinds (easy / natural / fast) and a caption policy per kind.
2. **A short deliberate slice** (language-focused learning). Explicit learning has large effects (Li & Sun 2024, d≈0.8–1.1);
   bottom-up decoding predicts listening comprehension (r≈0.63) far more than strategies do; shadowing and dictation
   train it; a word needs ~10+ encounters or deliberate study to stick; spaced retrieval beats re-reading, and word cards
   are efficient when they hold frequent words and never pile up (Nation 2022; Hamada 2016; Webb 2007). So: a daily
   ten-to-fifteen-minute **Clip** worked in three passes, a bundled offline dictionary with frequency rank, and **Cards**
   (lines and words) with the existing brake.
3. **Speaking as a skill** (output + fluency strands). Skill acquisition theory: the endings are declarative knowledge
   until produced many times under mild time pressure (DeKeyser). Task repetition and Nation's 4/3/2 raise speech rate
   and cut hesitation (Nation 1989; Arevart & Nation 1991; Tran & Saito 2024); retelling a story again is task
   repetition; self-recording improves noticing and self-correction (Lynch 2001; Vercellotti 2018) and, in small studies,
   confidence. Prepared "islands" (Shekhtman) give fluent ground. So: a **Say** window: islands, 4·3·2 with the
   built-in microphone, a monthly recording to hear next to last month's, and notes for the tutor.
4. **Habit, not willpower** (the psychology). Daily short contact predicts persistence; people who slip to every 5–6
   days mostly quit (app data; Lally 2010: a cue-linked daily action becomes automatic in ~66 days, one missed day costs
   little). If-then plans raise follow-through (Gollwitzer & Sheeran 2006, d≈0.65). Informational feedback sustains
   motivation; controlling feedback (grades, rankings, streaks) undermines it (Deci; Butler & Nisan 1986). So: a **desk
   card** that removes the decision ("today: these, in this order"), one click from the card into each thing, doses with
   brakes, feedback that is about the content or the owner's own voice, never a number about the owner.

## What the owner sees

### 1. The bookcase (renamed Shelf)

As today, with three changes.

- **Kinds.** The sealed list may carry `# kind: easy|natural|fast` comment lines before the videos they describe (the
  skill already writes them into `history.txt`; the app's parser already ignores `#` lines, so it needs only to read
  them, and a list without them still opens). Videos sit grouped by kind on the bookcase, easy at the top, with a small
  brass plate per group: ЛЁГКИЕ · ОБЫЧНАЯ РЕЧЬ · БЫСТРАЯ РЕЧЬ (or plain English if that reads better in shots). The red
  ribbon ("next") still marks one video: the first unfinished easy one, unless the desk card says otherwise.
- **Caption policy per kind.** easy and natural: subtitles off, reveal-line as today. fast: Russian subtitles **on** the
  first time through (the research for hard native video), off from the second viewing. S still toggles. The title no
  longer needs the "subtitles on (S) the first time" suffix; strip that suffix for display if present.
- **The desk card.** A cream library card across the top of the bookcase, written like a note, not a checklist:

      Today
      Cards        7 to hear again                       (⌘L)
      Clip         Easy Russian 53, 2:10–4:40            (⌘K)
      Say          «Мой университет», 2·1½·1             (⌘S)
      Then watch   Теремок                               (Return)

  Each line opens that thing. A line disappears once its thing is done for the day (Cards: today's done; Clip: three
  passes finished; Say: a recording made; Watch: never disappears, it is the open-ended part). No ticks, no counts of
  days, nothing kept in a row. If nothing is waiting the card says just "Today: a story is waiting. Теремок". Order is
  fixed by the research (short retrieval first while fresh, the hard slice second, speaking third, the long easy
  listening last as the pleasant part) but nothing stops the owner clicking any line in any order. The card is the
  if-then plan: "when I open Shelf, I do the top line".

### 2. The player, plus Clip (⌘K, or C in the player)

Everything the player has stays (↓ ↑ S T F L − K H). Two additions.

- **A word, looked up (W, or click a word in the caption or transcript).** A small dictionary slip over the picture:
  the lemma with its stress mark (ударéние), part of speech, two or three English glosses, and its place in the
  frequency list: "common: 1,840th" / "less common: 6,200th" / "rare: past the common 10,000". Information about the
  word, never about the owner. From the slip, K keeps the **word** (with the line it came from and that line's sound).
  The data: OpenRussian's dictionary (openrussian.org, CC BY-SA 4.0; the CSV dump is mirrored at
  github.com/Badestrand/russian-dictionary: words with stress and rank, translations, inflected forms) built by a
  `Tools/mkdict.py` into one SQLite file in the bundle (10.9 has libsqlite3). Attribution in About and README. If the
  dump cannot be fetched on this Mac, build the pipeline and tests against a small fixture and say so in the report.
- **Clip mode.** The app proposes one clip a day: 2–3 minutes, from the week's fast video (or the natural one if there
  is no fast one), starting at the stretch with the most help asked for on earlier viewings, else the next stretch not
  yet worked; sentence boundaries from the subtitles. A ruled card at the top of the picture walks three passes:
    1. **Listen.** No text. The stretch plays twice. (Space pauses; nothing else.)
    2. **Read.** Russian captions on; the stretch plays line by line, pausing after each; W looks a word up, K keeps the
       line or the word, Space goes on.
    3. **Say along.** Each line: hear it, then it plays again for you to speak over it (shadowing), twice. − slows it if
       you want. R records your say-along for that line and plays it back after the speaker's (optional; needs the mic).
  Then: "Done. Another tomorrow." The clip is remembered as worked (reports carry which stretch and what was kept).
  Keyboard only, like the rest; the card never asks a question.

### 3. Cards (⌘L; the Lines window, renamed)

As today (sound first, ↓ shows, ← not yet / → knew it, Tab writes the meaning, both directions once it has words,
1·3·7·16·35·75 days, fifteen kept and sixty heard a day, no keeping while forty-five wait), extended to **words**: a word
card plays its line's sound, ↓ shows the line with the word underlined and its gloss and stress. "Say it in Russian"
cards for words show the gloss in blue ink. The nameplate keeps saying "N to hear again". Nothing else counted.

### 4. Say (⌘S)

A new window: a lined index card and a brass microphone grille drawn in RSStyle.

- **Islands.** A short list of topics the owner can talk about, in Russian, that they edit (Tools menu > Islands…; plain
  text, one per line, stored in Application Support and synced). Seeded with eight for a Waterloo student: Мой день;
  Университет и учёба; Моя семья; Непал; Что я смотрел на этой неделе; Еда; Планы на выходные; Почему я учу русский.
  Each day the card proposes the next island in turn, or "Retell today's story" when a story was finished today.
- **4·3·2 (sized for A2–B1).** Three passes on the same topic, shorter each time: default 2 min · 1½ · 1, with 3·2·1½ and
  4·3·2 available in the Tools menu. A sand-glass drawn on the card runs down; Space starts the next pass; nothing stops
  you early; nothing is transcribed or scored. Each pass is recorded with the built-in microphone (AVAudioRecorder,
  M4A). After the last pass the card offers: ▶ hear the last pass; Tab write up to three things you noticed (grammar you
  fumbled, a word you lacked) into **For the tutor**, a plain text file the owner can read before a lesson and that
  reports carry. Recordings of the day are kept until midnight, then only the last pass of the first Say of each month
  stays as **the month's recording** (`Recordings/2026-11.m4a`).
- **Hear last month.** When a month's recording exists, the card offers to play last month's and then today's, back to
  back. That is the progress check: the owner's own voice, two dates, no number.
- If the Mac has no input device, Say still runs the timer and the islands and says once that it cannot record here.

### 5. Reports and what Claude chooses from

Reports keep everything they carry today and add: `Clip` (which stretch, passes finished, words/lines kept),
`Say` (island, lengths, whether a recording was made), `Tutor` (the notes), `Words kept`. These are for the skill on
the MacBook to choose next week's shelf; the app shows none of them as numbers.

### 6. Sync between the two Macs (last phase)

Today each Mac keeps its own State.plist and Lines/, and only reports travel. Make progress, cards (lines and words,
with their sound), islands, tutor notes and the monthly recordings the same on both Macs, through the `~/Study` clone
both already pull and push:

- Each Mac writes only its own folder `Russian/Sync/<host>/` (State.plist, Cards.plist, Cards/*.m4a, Islands.txt,
  Tutor.txt, Recordings/*.m4a), with the same private-index plumbing `RSSync` uses for reports, extended to update and
  delete paths under its own folder only (still never touching the clone's index or working tree; still never any other
  path). Reports stay as they are.
- After each pull the app merges every other host's folder into its own state: a video's progress is the furthest; a
  card is the same card by id (video id + ms, or word + video id + ms), and the review with the later `last reviewed`
  wins; a card put away anywhere is put away; audio is copied in when missing; islands are the union keeping each file's
  order; tutor notes append by date. The merge is deterministic so both Macs converge, and it is unit-tested with two
  fixture folders.
- The daily brakes count what this Mac did today plus what the other Mac did today, so the dose stays the dose.
- Nothing about shelves, sealing or the keys changes.

## What does not change

The seal, the keys, `shelfsign`, the sealed formats (`Russian Shelf 1` / `Russian Shelf sealed 1` headers stay
exactly, for every shelf the MacBook ever sealed), the bundle identifier `com.russianshelf.RussianShelf` (the
Application Support folder, the keychain ACL on the MacBook, and State/Lines paths depend on it), the 12-video cap,
no browser/web view/feeds/recommendations, no streaks/badges/scores/grades/slogans, the 2013 skeuomorphic look, git 1.9.

## The rename

User-facing only: app name `Shelf.app` (CFBundleName / display name), window titles, the nameplate, menus, About,
README, CLAUDE.md, icon label, the zip name `Shelf.zip`. Internal identifiers, class prefixes (RS), the bundle id, the
sealed-format headers and the Study folder `Russian/` stay. `make` installs nothing; the owner installs.

## Phases (commit each; tests, shots and docs per phase)

1. Rename; kinds and caption policy; desk card.
2. Dictionary (mkdict, bundle, slip, W); word cards in Cards.
3. Clip mode.
4. Say window (islands, 4·3·2, recordings, month's recording, For the tutor); report sections.
5. Sync between Macs.
