// Sync between the two Macs: progress, cards with their sound, islands,
// notes for the tutor and the month's recordings, through the study clone
// both Macs already pull and push. Nothing about shelves, the seal or the
// keys. In the app's folder:
//
//   Sync Out/      what this Mac publishes as Russian/Sync/<host>/:
//                    State.plist          <- State.plist
//                    Cards.plist          <- Lines/Lines.plist
//                    Cards/<key>.m4a      <- Lines/<key>.m4a (each card's sound)
//                    Islands.txt          <- Say/Islands.txt
//                    Tutor.txt            <- Say/Tutor.txt
//                    Recordings/<month>.m4a <- Say/Recordings/YYYY-MM.m4a
//   Sync In/<host>/  every other Mac's folder as last pulled (from git's
//                  objects at HEAD, never Syllabus's half-updated files)
//
// Say/Today/ is each Mac's own and never goes anywhere. The rules for
// merging are in RSMerge.h. The round, after each successful pull:
//
//   1. (background) -takeOtherHosts: Sync In/ from the clone
//   2. (main thread, with the library and the cards saved first, so nothing
//      done on this Mac is lost) -mergeInCards: into the files on disk;
//      then the app reads them again
//   3. (main thread) -stage: Sync Out/ from the files on disk
//   4. (background) -publish: Russian/Sync/<host>/ = Sync Out/, pushed
//
// Background steps run on +gitQueue, as the reports' push does: never two
// gits of this app at once in the clone.

#import <Foundation/Foundation.h>

@class RSSyncResult;

@interface RSSyncManager : NSObject

- (id)initWithAppFolder:(NSString *)appFolder studyFolder:(NSString *)studyFolder;
- (id)initWithAppFolder:(NSString *)appFolder studyFolder:(NSString *)studyFolder host:(NSString *)slug;

@property (nonatomic, readonly, copy) NSString *appFolder, *studyFolder, *host;
@property (nonatomic, readonly, copy) NSString *outFolder, *inFolder;   // Sync Out, Sync In
@property (nonatomic) BOOL busy;                // a round is under way (the controller's to set)
@property (nonatomic, copy) NSString *note;     // what went wrong last round, in a sentence, or nil

+ (dispatch_queue_t)gitQueue;

// 1. NO, with *problem, if git couldn't read the clone.
- (BOOL)takeOtherHosts:(NSString **)problem;
// 2. Merges every folder in Sync In/ (hosts in name order) into the files on
// disk; the cards only if `cards` (not while the Lines window has them).
// YES if a file here changed.
- (BOOL)mergeInCards:(BOOL)cards;
// The same from any folder of host folders (the tests' fixtures).
- (BOOL)mergeFrom:(NSString *)hostsFolder cards:(BOOL)cards;
// 3.
- (void)stage;
// 4.
- (RSSyncResult *)publish;

// For the daily brakes, what other Macs did today as of their last sync:
// lines heard again (their heardCount for today; never merged, so this is
// on top of this Mac's), and cards kept today that aren't among this Mac's
// cards yet (those merged in already count in RSLines's -keptOn:).
+ (NSUInteger)heardTodayOnOtherHosts:(NSString *)appFolder today:(long)today;
+ (NSUInteger)keptTodayOnOtherHosts:(NSString *)appFolder today:(long)today;

@end
