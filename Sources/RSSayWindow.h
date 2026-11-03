// The Say window (⌘S): today's topic on an index card, the three passes with
// a sand-glass, the microphone, and afterwards: hear the last pass, write a
// note for the tutor, keep the month's recording, hear last month's. And
// since 2026-11-02, whenever the owner likes: another round on any island
// (↑ ↓ choose, Space starts), every recording kept by day and listed (R), and
// a recording made on its own (N), to listen back and hear their own errors.
//
//   Space    start the first pass; the next pass once one is done; after the
//            last, hear it
//   ↑ ↓      another topic (before a round, or after one): the islands in turn
//   M        hear last month's recording, then today's last pass
//   Tab      write a note for the tutor (Return keeps it, Esc leaves it)
//   R        the recordings: every day's, newest first. There: ↑ ↓ choose,
//            Space plays (or stops), N records a new one on its own (Space
//            or N stops it), Tab names it, Esc comes back to the card
//   N        a recording on its own, from the card too
//   ⌘I       the islands: write them on the card, one a line (⌘I or Esc keeps)
//   Esc      close
//
// Retelling a story (Перескажи: «…», a reading of the week): after the three
// passes a fourth, short one asks for the lesson in the owner's own words,
// then shows the story's own line to compare.
//
// Nothing is counted or scored; the only time shown is the pass's own clock.

#import <Cocoa/Cocoa.h>

@class RSSay, RSSayWindow;

@protocol RSSayWindowDelegate <NSObject>
// A pass finished (1, 2 or 3 of 3; 4: the lesson) of round `round` (1: the
// day's first) on `topic`; `recorded` if the microphone caught it.
- (void)sayWindow:(RSSayWindow *)window finishedPass:(NSUInteger)pass topic:(NSString *)topic round:(NSUInteger)round recorded:(BOOL)recorded;
- (void)sayWindowClosed:(RSSayWindow *)window;
@end

typedef enum {
    RSSayReady = 0,     // the topic; Space starts
    RSSayRunning,       // a pass under way
    RSSayBetween,       // a pass done; Space starts the next
    RSSayDone,          // all passes done
    RSSayIslands,       // writing the islands
    RSSayRecordings     // the recordings list
} RSSayState;

@interface RSSayWindow : NSObject <NSWindowDelegate, NSTextFieldDelegate>

// `topic`: today's island, or "Перескажи: «story»" (the controller decides);
// `setting`: which lengths (RSSayLengths).
- (id)initWithSay:(RSSay *)say topic:(NSString *)topic setting:(NSUInteger)setting today:(long)today;

@property (nonatomic, assign) id<RSSayWindowDelegate> delegate;
@property (nonatomic, readonly) NSWindow *window;
@property (nonatomic, readonly) RSSayState state;
@property (nonatomic, readonly) NSUInteger pass;           // the pass under way or just done (0 before the first)
@property (nonatomic, readonly) NSUInteger round;          // 1 for the day's first round
@property (nonatomic, readonly, copy) NSString *topic;
@property (nonatomic, readonly) long today;
// Topics ↑ ↓ move through (the retell topics first, then the islands); the
// lessons of the retell topics (topic -> the story's lesson line), for the
// fourth pass. Set before -show.
@property (nonatomic, copy) NSArray *topics;
@property (nonatomic, copy) NSDictionary *lessons;

- (void)show;
- (void)close;
- (void)space;
- (void)chooseTopic:(NSInteger)direction;      // ↑ -1, ↓ +1
- (void)hearLastMonth;
- (void)writeNote;
- (void)toggleIslands;
- (void)toggleRecordings;
- (void)moveSelection:(NSInteger)direction;    // in the recordings list
- (void)recordFree;                            // start a recording on its own, or stop it
@property (nonatomic, readonly) NSInteger selectedRecording;
@property (nonatomic, readonly) BOOL recordingFree;

// For the tests and shots: no microphone, no sound; the clock moved by hand.
- (void)setSilentForTesting;
- (void)setSecondsLeftForTesting:(double)seconds;
- (NSString *)visibleNote;

@end
