// The Say window (⌘S): today's island on an index card, the three passes with
// a sand-glass, the microphone, and afterwards: hear the last pass, write a
// note for the tutor, keep the month's recording, hear last month's.
//
//   Space    start the first pass; the next pass once one is done; after the
//            last, hear it
//   M        hear last month's recording, then today's last pass
//   Tab      write a note for the tutor (Return keeps it, Esc leaves it)
//   ⌘I       the islands: write them on the card, one a line (⌘I or Esc keeps)
//   Esc      close
//
// Nothing is counted or scored; the only time shown is the pass's own clock.

#import <Cocoa/Cocoa.h>

@class RSSay, RSSayWindow;

@protocol RSSayWindowDelegate <NSObject>
// A pass finished (1, 2 or 3 of 3); `recorded` if the microphone caught it.
- (void)sayWindow:(RSSayWindow *)window finishedPass:(NSUInteger)pass recorded:(BOOL)recorded;
- (void)sayWindowClosed:(RSSayWindow *)window;
@end

typedef enum {
    RSSayReady = 0,     // the topic; Space starts
    RSSayRunning,       // a pass under way
    RSSayBetween,       // a pass done; Space starts the next
    RSSayDone,          // all three done
    RSSayIslands        // writing the islands
} RSSayState;

@interface RSSayWindow : NSObject <NSWindowDelegate, NSTextFieldDelegate>

// `topic`: today's island, or "Перескажи: «story»" (the controller decides);
// `setting`: which lengths (RSSayLengths).
- (id)initWithSay:(RSSay *)say topic:(NSString *)topic setting:(NSUInteger)setting today:(long)today;

@property (nonatomic, assign) id<RSSayWindowDelegate> delegate;
@property (nonatomic, readonly) NSWindow *window;
@property (nonatomic, readonly) RSSayState state;
@property (nonatomic, readonly) NSUInteger pass;           // the pass under way or just done (0 before the first)
@property (nonatomic, readonly) long today;

- (void)show;
- (void)close;
- (void)space;
- (void)hearLastMonth;
- (void)writeNote;
- (void)toggleIslands;

// For the tests and shots: no microphone, no sound; the clock moved by hand.
- (void)setSilentForTesting;
- (void)setSecondsLeftForTesting:(double)seconds;
- (NSString *)visibleNote;

@end
