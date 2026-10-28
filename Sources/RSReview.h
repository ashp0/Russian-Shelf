// The Lines window: today's kept lines, one at a time.
//
// Most times a line comes up as its sound (it plays by itself): understand
// it, then ↓ shows it. Once the owner has written what it means (Tab, under
// the shown line), every other time it comes up as those words instead: say
// it in Russian, then ↓ (or Space) plays the speaker and shows the line, to
// compare.
//
//   Space    hear it again (on a "say it" card: hear it and see it)
//   −        three-quarter speed, and full speed again
//   ↓        show the line (and the one before it, for context)
//   Tab      write what it means (Return keeps it, Esc leaves it as it was)
//   ←        not yet: it comes back tomorrow, and once more at the end of today's
//   →        knew it: it comes back later (RSLines says when)
//   ⌫        put it away for good
//   Esc      close
//
// Nothing is counted or scored on screen; when today's are done it says so
// and stops.

#import <Cocoa/Cocoa.h>

@class RSLines, RSReview;

@protocol RSReviewDelegate <NSObject>
- (void)reviewClosed:(RSReview *)review;
@end

typedef enum {
    RSReviewListening = 0,      // the sound, the text hidden
    RSReviewSaying,             // the owner's words: say it in Russian
    RSReviewShown,              // the text shown
    RSReviewDone,               // nothing more today
    RSReviewNothingKept         // no lines kept at all yet
} RSReviewState;

@interface RSReview : NSObject <NSWindowDelegate>

- (id)initWithLines:(RSLines *)lines today:(long)today;

@property (nonatomic, assign) id<RSReviewDelegate> delegate;
@property (nonatomic, readonly) NSWindow *window;
@property (nonatomic, readonly) RSReviewState state;
@property (nonatomic, readonly) BOOL slower;
@property (nonatomic, readonly) long today;

- (void)show;
- (void)close;

- (void)hearAgain;
- (void)showLine;
- (void)answer:(BOOL)knew;
- (void)putAway;
- (void)toggleSlower;
- (void)setMeaning:(NSString *)meaning;     // for the line up now (and saved)

// For the screenshots and tests: no sound played.
- (void)setSilentForTesting;
- (NSString *)visibleText;       // the line shown now, or nil

@end
