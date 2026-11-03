// The Reading window (⌘D): the day's story (or the week's poem) on a sheet
// of paper, in Georgia, stress marks shown (A hides them), read three times
// the way a clip has three passes (the research: repeated reading builds
// reading rate and fluency; hearing one's own reading is how the owner
// catches their errors):
//
//   1  silently, at any pace, looking words up
//   2  aloud, recorded
//   3  aloud again, recorded; then both played back, 2 then 3, to hear the
//      difference
//
// Then Say offers to retell it (the controller's topic for the day).
//
//   Space    start the read; end it; after the third, hear read 2 then 3
//   W        a word: the one under the caret (click a word), its lemma with
//            the stress, kind, glosses and rank, on a slip; ← → move along
//            the sentence's words; W or Esc closes
//   K        keep the word on the slip as a card, with its sentence (Cards)
//   A        stress marks off, and on again
//   ← →      the week's other readings (when no read is running)
//   Esc      close
//
// The time of each read goes to the report only: the sheet shows "read 2 of
// 3" and the read's own clock, never a speed or a score.

#import <Cocoa/Cocoa.h>

@class RSReadingSet, RSReadingItem, RSReadingWindow, RSDictionary, RSDictionaryEntry, RSSay;

@protocol RSReadingWindowDelegate <NSObject>
// A read finished: the n-th of three, how long it took, whether recorded.
- (void)readingWindow:(RSReadingWindow *)window item:(RSReadingItem *)item finishedRead:(NSUInteger)n seconds:(double)seconds recorded:(BOOL)recorded;
// Keep a word from the reading, as the slip looked it up (entry nil: not in
// the dictionary). Returns what to say.
- (NSString *)readingWindow:(RSReadingWindow *)window keepWord:(NSString *)word entry:(RSDictionaryEntry *)entry
                   sentence:(NSString *)sentence item:(RSReadingItem *)item;
// How many reads the item has had before (0-3), from the library.
- (NSUInteger)readingWindow:(RSReadingWindow *)window readsOf:(RSReadingItem *)item;
- (void)readingWindowClosed:(RSReadingWindow *)window;
@end

typedef enum {
    RSReadReady = 0,        // the text; Space starts the next read
    RSReadRunning,          // a read under way (2 and 3: recording)
    RSReadDone              // three reads done; Space hears 2 then 3
} RSReadState;

@interface RSReadingWindow : NSObject <NSWindowDelegate, NSTextViewDelegate>

- (id)initWithSet:(RSReadingSet *)set item:(RSReadingItem *)item say:(RSSay *)say today:(long)today;

@property (nonatomic, assign) id<RSReadingWindowDelegate> delegate;
@property (nonatomic, retain) RSDictionary *dictionary;
@property (nonatomic, readonly) NSWindow *window;
@property (nonatomic, readonly) RSReadState state;
@property (nonatomic, readonly) NSUInteger read;            // reads done (0-3)
@property (nonatomic, readonly, retain) RSReadingItem *item;
@property (nonatomic, readonly) long today;
@property (nonatomic, readonly) BOOL stressShown, slipShown;

- (void)show;
- (void)close;
- (void)space;
- (void)toggleStress;
- (void)toggleWordSlip;
- (void)chooseSlipWord:(NSInteger)index;
- (void)keepSlipWord;
- (void)showItem:(NSInteger)direction;        // ← -1, → +1 among the week's readings

// For the tests and shots: no microphone, no sound; the caret put by hand.
- (void)setSilentForTesting;
- (void)setCaretForTesting:(NSUInteger)offset;
- (void)setSecondsForTesting:(double)seconds;
- (NSString *)visibleNote;
- (NSString *)visibleInstruction;

@end
