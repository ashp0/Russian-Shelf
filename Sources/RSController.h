// The app: the shelf window, the menus, and the round it makes every hour
// (and at launch, at wake, and on ⌘R):
//
//   1. pull the study folder (~/Study, a clone Syllabus pulls too)
//   2. offer Russian/shelf.signed to the library, which keeps the last good
//      shelf if this one doesn't check out, and says why
//   3. on a shelf's start day, make it this week's
//   4. download what's missing; once this week's are all here, delete last
//      week's
//   5. send what was watched (Russian/Reports/), if this Mac's key can write
//
// No File menu, no Open, no URL field, nothing dropped in: the shelf is the
// only way to a video.

#import <Cocoa/Cocoa.h>
#import "RSShelfView.h"
#import "RSPlayer.h"
#import "RSDownloader.h"
#import "RSReview.h"

@class RSLibrary, RSLines, RSDictionary, RSClipPlan;

@interface RSController : NSObject <NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate,
                                    RSShelfViewDelegate, RSPlayerDelegate, RSDownloaderDelegate, RSReviewDelegate>

// nil for both: the real ones (Application Support, ~/Study).
- (id)initWithLibrary:(RSLibrary *)library studyFolder:(NSString *)studyFolder;

@property (nonatomic, readonly) NSWindow *window;
@property (nonatomic, readonly) RSShelfView *shelfView;
@property (nonatomic, readonly) RSPlayer *player;
@property (nonatomic, readonly) RSLibrary *library;
@property (nonatomic, readonly) RSLines *lines;          // kept lines, in the library's Lines/
@property (nonatomic, readonly) RSReview *review;        // the Lines window, while open

- (void)showWindow;
- (void)reloadRows;
- (RSPlayer *)playVideo:(NSString *)identifier;
- (RSReview *)showLines;
// Today's clip (RSClips.h): chosen once a day, remembered until worked.
- (RSClipPlan *)todaysClip;
- (RSPlayer *)startTodaysClip;

// The dictionary players look words up in: the bundle's, unless one is set
// (the screenshots use the test fixture's).
- (RSDictionary *)dictionary;
- (void)setDictionary:(RSDictionary *)dictionary;

// For the screenshots.
- (void)setStatusForTesting:(NSString *)text problem:(BOOL)problem;
- (void)setDownload:(NSString *)identifier progress:(double)progress problem:(NSString *)problem;

@end

// "Monday, October 12"
NSString *RSDayText(long day);
