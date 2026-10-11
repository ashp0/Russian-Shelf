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

@class RSLibrary;

@interface RSController : NSObject <NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate,
                                    RSShelfViewDelegate, RSPlayerDelegate, RSDownloaderDelegate>

// nil for both: the real ones (Application Support, ~/Study).
- (id)initWithLibrary:(RSLibrary *)library studyFolder:(NSString *)studyFolder;

@property (nonatomic, readonly) NSWindow *window;
@property (nonatomic, readonly) RSShelfView *shelfView;
@property (nonatomic, readonly) RSPlayer *player;
@property (nonatomic, readonly) RSLibrary *library;

- (void)showWindow;
- (void)reloadRows;
- (RSPlayer *)playVideo:(NSString *)identifier;

// For the screenshots.
- (void)setStatusForTesting:(NSString *)text problem:(BOOL)problem;
- (void)setDownload:(NSString *)identifier progress:(double)progress problem:(NSString *)problem;

@end

// "Monday, October 12"
NSString *RSDayText(long day);
