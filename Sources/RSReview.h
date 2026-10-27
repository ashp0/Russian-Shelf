// The Lines window: today's kept lines, one at a time, sound first.
//
//   Space    hear it again
//   −        three-quarter speed, and full speed again
//   ↓        show the line (and the one before it, for context)
//   ←        not yet: it comes back tomorrow, and once more at the end of today's
//   →        knew it: it comes back later (RSLines says when)
//   ⌫        put it away for good
//   Esc      close
//
// The sound plays by itself when a line comes up. Nothing is counted or
// scored on screen; when today's are done it says so and stops.

#import <Cocoa/Cocoa.h>

@class RSLines, RSReview;

@protocol RSReviewDelegate <NSObject>
- (void)reviewClosed:(RSReview *)review;
@end

typedef enum {
    RSReviewListening = 0,      // the sound, the text hidden
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

// For the screenshots and tests: no sound played.
- (void)setSilentForTesting;
- (NSString *)visibleText;       // the line shown now, or nil

@end
