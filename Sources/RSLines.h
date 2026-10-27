// Lines kept to hear again: a few sentences from the week's videos, each
// with the speaker's own sound, brought back on spaced days (research:
// retrieval and spacing are the best-supported ways to keep words; a line
// heard, not read, trains the ear).
//
// In the player, K keeps the line just said. Its sound is cut from the video
// (RSClip) into Lines/, so it stays when the video goes. The Lines window
// plays each line due today, sound first: the text only when asked for, then
// "not yet" or "knew it".
//
//   - At most ten lines kept a day, and thirty heard again a day: a small
//     dose, never a backlog that eats the listening.
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

extern const NSUInteger RSKeepPerDay;          // 10
extern const NSUInteger RSHearPerDay;          // 30
extern const NSUInteger RSPutAwayAfter;        // 6 times "not yet"

@interface RSKeptLine : NSObject
@property (nonatomic, copy) NSString *key;              // also the sound's file name
@property (nonatomic, copy) NSString *video, *title;    // the video's id and title
@property (nonatomic) double start, end;                // where it is in the video (seconds)
@property (nonatomic, copy) NSString *text;             // the line (may hold a line break)
@property (nonatomic, copy) NSString *before;           // the line before it, for context, or nil
@property (nonatomic) long kept, due;                   // days (RSDate)
@property (nonatomic) NSUInteger step, lapses;          // "knew it"s in a row; "not yet"s in all
@property (nonatomic) BOOL putAway;                     // known, or not for now
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
- (NSUInteger)keptOn:(long)today;

// Today's lines to hear again: those due by today, oldest due first, as
// many as today still allows.
- (NSArray *)dueOn:(long)today;
// "Knew it" (YES) or "not yet" (NO). Counts towards today's thirty.
- (void)answer:(RSKeptLine *)line knew:(BOOL)knew today:(long)today;
// Put a line away by hand.
- (void)putAway:(RSKeptLine *)line;

- (NSString *)soundPath:(RSKeptLine *)line;     // Lines/<key>.m4a (may not exist)
- (NSArray *)linesFromVideo:(NSString *)video;

- (BOOL)save;

@end

// Days until a line comes back after `step` "knew it"s in a row (0: the next
// day). 0 once the steps run out: put away.
long RSLineGap(NSUInteger step);
