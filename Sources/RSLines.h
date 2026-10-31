// Lines kept to hear again: a few sentences from the week's videos, each
// with the speaker's own sound, brought back on spaced days (research:
// retrieval and spacing are the best-supported ways to keep words; a line
// heard, not read, trains the ear).
//
// In the player, K keeps the line just said. Its sound is cut from the video
// (RSClip) into Lines/, so it stays when the video goes. The Lines window
// plays each line due today, sound first: the text only when asked for, then
// "not yet" or "knew it". Under the shown line you can write what it means,
// in your own words. From then on the line comes up both ways, turn about:
// its sound (understand it) and your words (say it in Russian, then hear the
// speaker): one trains the ear, the other the speaking (research: recalling
// the form from the meaning builds productive knowledge).
//
//   - At most fifteen lines kept a day and sixty heard again a day (about
//     twenty minutes), and no keeping while forty-five are already waiting:
//     never a backlog that eats the listening.
//   - A new line comes back the next day. Each "knew it" waits longer: 3,
//     7, 16, 35, then 75 days; after that it's known and put away.
//   - "Not yet" brings it back the next day, from the start. A line not
//     known after six of those is put away too: it's better met again in a
//     story than drilled.
//
// No counts of right and wrong, no streaks. Everything lives in
//
//   Lines/Lines.plist       the lines and when each comes back
//   Lines/<key>.m4a         each line's sound

#import <Foundation/Foundation.h>

extern const NSUInteger RSKeepPerDay;          // 15
extern const NSUInteger RSHearPerDay;          // 60
extern const NSUInteger RSWaitingBrake;        // 45 waiting: keep no more
extern const NSUInteger RSPutAwayAfter;        // 6 times "not yet"

extern NSString *const RSCardLine, *const RSCardWord;

@interface RSKeptLine : NSObject
@property (nonatomic, copy) NSString *key;              // a line: "<video>-<ms>", also its sound's file name
@property (nonatomic, copy) NSString *kind;             // RSCardLine (nil counts as a line) or RSCardWord
// A word card: the word as it stands in the line, its lemma with the stress
// marked, its gloss, and its rank (0: none). Its sound is the line's.
@property (nonatomic, copy) NSString *word, *lemma, *gloss;
@property (nonatomic) NSUInteger rank;
- (BOOL)isWord;
@property (nonatomic, copy) NSString *video, *title;    // the video's id and title
@property (nonatomic) double start, end;                // where it is in the video (seconds)
@property (nonatomic, copy) NSString *text;             // the line (may hold a line break)
@property (nonatomic, copy) NSString *before;           // the line before it, for context, or nil
@property (nonatomic, copy) NSString *meaning;          // what it means, in the owner's words, or nil
@property (nonatomic) long kept, due;                   // days (RSDate)
@property (nonatomic) NSUInteger step, lapses;          // "knew it"s in a row; "not yet"s in all
@property (nonatomic) BOOL putAway;                     // known, or not for now
@property (nonatomic) long heard;                       // the day of the last answer (0: never)
@property (nonatomic) BOOL knewLast;                    // what that answer was
@end

@interface RSLines : NSObject

- (id)initWithFolder:(NSString *)folder;     // created if missing
@property (nonatomic, readonly, copy) NSString *folder;
@property (nonatomic, readonly, copy) NSArray *lines;   // RSKeptLine, in the order kept

// Keeps a line. nil, with *problem in a sentence, if it's already kept or
// today's ten are kept.
- (RSKeptLine *)keepText:(NSString *)text before:(NSString *)before video:(NSString *)video title:(NSString *)title
                   start:(double)start end:(double)end today:(long)today problem:(NSString **)problem;
- (BOOL)isKept:(NSString *)video start:(double)start;
// Keeps a word from a line (the line's text and sound go with it). nil with
// *problem as for a line; a word is kept once per line.
- (RSKeptLine *)keepWord:(NSString *)word lemma:(NSString *)lemma gloss:(NSString *)gloss rank:(NSUInteger)rank
                  inLine:(NSString *)text before:(NSString *)before video:(NSString *)video title:(NSString *)title
                   start:(double)start end:(double)end today:(long)today problem:(NSString **)problem;
- (BOOL)isKeptWord:(NSString *)word video:(NSString *)video start:(double)start;
- (NSUInteger)keptOn:(long)today;

// Today's lines to hear again: those due by today, oldest due first, as
// many as today still allows.
- (NSArray *)dueOn:(long)today;
// How many are due by today and not put away, whatever today allows.
- (NSUInteger)waitingOn:(long)today;
// Whether this time it's "say it from your words" rather than "listen": only
// for a line with a meaning, every other time after the first "knew it".
- (BOOL)asksToSay:(RSKeptLine *)line;
// Lines answered "not yet" today and not put away: heard once more before
// today's are done (not counted again, not moved again).
- (NSArray *)notYetOn:(long)today;
// "Knew it" (YES) or "not yet" (NO). Counts towards today's thirty.
- (void)answer:(RSKeptLine *)line knew:(BOOL)knew today:(long)today;
// Put a line away by hand.
- (void)putAway:(RSKeptLine *)line;

- (NSString *)soundPath:(RSKeptLine *)line;     // Lines/<key>.m4a, a word card's its line's (may not exist)
- (NSArray *)linesFromVideo:(NSString *)video;

- (BOOL)save;

@end

// Days until a line comes back after `step` "knew it"s in a row (0: the next
// day). 0 once the steps run out: put away.
long RSLineGap(NSUInteger step);
