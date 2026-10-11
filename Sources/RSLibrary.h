// Everything the app keeps, in ~/Library/Application Support/Russian Shelf/
// (not ~/Movies: there is no pile of videos to browse):
//
//   Shelf.signed           this week's shelf, as it arrived (checked again at
//                          every launch)
//   Next Shelf.signed      a shelf that arrived early: it starts on a later day
//   State.plist            how far each video has been watched; the last
//                          refusal
//   Videos/<id>/           video.mp4, subtitles.vtt, thumbnail.jpg, info.plist
//   Downloads/<id>/        a download in progress
//   yt-dlp, Cache/, Logs/  the downloader (RSDownloader.h)
//   Outbox/                reports not yet pushed (RSReport.h)
//
// The rules for a shelf.signed read from the study folder:
//
//   - It must open: right signature, at most 12 videos, well formed. If not,
//     it's refused, what is here stays, and `notice` says why.
//   - It must be newer than the newest shelf here (a later start, or the
//     same start sealed later): an old file can't come back.
//   - If its day has come it becomes this week's shelf at once; otherwise it
//     waits as the next shelf, its videos downloaded ahead, and takes over on
//     its start day.
//   - Videos are kept by id, so one on both shelves is downloaded once. Once
//     every video on this week's shelf is downloaded, anything on neither
//     shelf is deleted, with what was known about watching it.

#import <Foundation/Foundation.h>
#import "RSShelf.h"

@interface RSWatch : NSObject
@property (nonatomic) double position;   // where it was left (seconds)
@property (nonatomic) double furthest;   // the furthest point reached by playing, not by skipping
@property (nonatomic) double duration;
@property (nonatomic) BOOL finished;     // got to 90% once
@end

typedef enum {
    RSOfferNothingNew = 0,      // the shelf already here
    RSOfferTaken,               // now this week's shelf
    RSOfferQueued,              // the next shelf, from its start day
    RSOfferRefused              // see -notice
} RSOffer;

extern const double RSFinishedFraction;     // 0.9

@interface RSLibrary : NSObject

+ (NSString *)defaultFolder;
- (id)initWithFolder:(NSString *)folder;                  // the app's own keys
- (id)initWithFolder:(NSString *)folder aesKey:(NSData *)aesKey publicKey:(NSData *)publicKey;

@property (nonatomic, readonly, copy) NSString *folder;
@property (nonatomic, readonly, retain) RSShelf *current;
@property (nonatomic, readonly, retain) RSShelf *pending;
@property (nonatomic, readonly, copy) NSString *notice;   // why the last shelf was refused, or nil

- (RSOffer)offerShelfFile:(NSData *)file today:(long)today;
// Makes the next shelf this week's once its day has come. YES if it did;
// *replaced is the shelf it took over from (nil if there was none).
- (BOOL)advanceToDay:(long)today replaced:(RSShelf **)replaced;

// ---- Files ----
- (NSString *)videoFolder:(NSString *)identifier;
- (NSString *)moviePath:(NSString *)identifier;
- (NSString *)subtitlesPath:(NSString *)identifier;
- (NSString *)thumbnailPath:(NSString *)identifier;
- (NSString *)stagingFolder:(NSString *)identifier;
- (NSDictionary *)infoFor:(NSString *)identifier;          // duration, subtitles ("made"/"auto"/"none")
- (BOOL)isDownloaded:(NSString *)identifier;
// This week's videos, then the next shelf's, that aren't here yet. Only ids
// from shelves that opened: nothing else is ever downloaded.
- (NSArray *)identifiersToDownload;
- (BOOL)isCurrentComplete;
// Moves a finished download from its staging folder into Videos/<id>.
- (BOOL)installDownload:(NSString *)identifier duration:(double)duration problem:(NSString **)problem;
// Once this week's shelf is all here: deletes every video on neither shelf,
// and any half-finished download of one. Returns the ids removed.
- (NSArray *)removeLeftovers;

// ---- Watching ----
- (RSWatch *)watchFor:(NSString *)identifier;             // never nil
// Returns YES if this made the video finished.
- (BOOL)recordPosition:(double)position furthest:(double)furthest duration:(double)duration
                   for:(NSString *)identifier;
// The first video on this week's shelf not finished yet, or nil.
- (NSString *)nextIdentifier;

- (BOOL)save;

@end
