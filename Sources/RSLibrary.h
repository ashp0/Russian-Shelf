// Everything the app keeps, in ~/Library/Application Support/Russian Shelf/
// (not ~/Movies: there is no pile of videos to browse):
//
//   Shelf.signed           this week's shelf, as it arrived (checked again at
//                          every launch)
//   Next Shelf.signed      a shelf that arrived early: it starts on a later day
//   Reading.signed         this week's readings (RSReading.h), and
//   Next Reading.signed    next week's, by the same rules as the shelves
//   State.plist            how far each video has been watched; the last
//                          refusal
//   Videos/<id>/           video.mp4, subtitles.vtt, thumbnail.jpg, info.plist
//   Subtitles/<id>.vtt     Russian subtitles the skill made for a video whose
//                          own track doesn't match the speech, taken from the
//                          study folder's Russian/Subtitles/<id>.vtt only when
//                          its SHA-256 is the one sealed in the shelf list
//                          (`subtitles:` lines, RSShelf.h); checked again
//                          each time they're read
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

@class RSSubtitles, RSReadingSet, RSReadingItem;

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

// What the player was asked for, counted per video for the report, with the
// line it was asked on: shown (↓), heard again (↑), looped (L), slowed (−,
// turned on), the transcript opened or a line clicked in it (T), subtitles
// turned on (S), kept (K). Facts for Claude choosing the next shelf (which
// lines, so which verbs and endings, needed help); the app never shows them.
typedef enum {
    RSHelpShown = 0,
    RSHelpHeardAgain,
    RSHelpKept,
    RSHelpLooped,
    RSHelpSlowed,
    RSHelpTranscript,
    RSHelpSubtitles,
    RSHelpLookedUp,             // a word looked up in the dictionary (W)
    RSHelpKinds                 // how many kinds there are
} RSHelp;

NSString *RSHelpName(RSHelp kind);          // "shown", "heard again", "looped", ...

// How a video felt, in the owner's own one-click words: about the video,
// never about them. nil until chosen; choosing the same again clears it.
extern NSString *const RSFeltTooEasy, *const RSFeltAboutRight, *const RSFeltTooHard;
extern NSString *const RSWantMore, *const RSWantLess;

// A property list written (XML, atomically) only when it isn't what the file
// already holds: saving what hasn't changed leaves the file and its date
// alone, so the disk stays idle and the sync sees nothing new. NO if it
// isn't a property list or couldn't be written.
BOOL RSWritePlist(id plist, NSString *path);

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

// ---- Readings (RSReading.h) ----
// The week's readings and the next week's, offered and advanced by the
// shelves' rules (newer only; early ones wait for their day). A refused
// reading list says why in `readingNotice`.
@property (nonatomic, readonly, retain) RSReadingSet *reading;
@property (nonatomic, readonly, retain) RSReadingSet *pendingReading;
@property (nonatomic, readonly, copy) NSString *readingNotice;
- (RSOffer)offerReadingFile:(NSData *)file today:(long)today;
- (BOOL)advanceReadingToDay:(long)today;
// Today's reading: the set's own choice for the day.
- (RSReadingItem *)readingForDay:(long)day;
// What was done with a reading, by its key: {reads (0-3), times (seconds, one a read),
// recorded (one a read), day (the last read's), title}; nil if never opened.
- (NSDictionary *)readingProgressFor:(NSString *)key;
// A read finished: the n-th of three took `seconds` (recorded or not).
- (void)recordRead:(NSString *)key title:(NSString *)title read:(NSUInteger)n seconds:(double)seconds recorded:(BOOL)recorded day:(long)day;
- (NSArray *)readingKeys;                                 // every key with progress, sorted
// The key of a reading whose third read was on `day`, or nil.
- (NSString *)readingFinishedOnDay:(long)day;

// ---- Files ----
- (NSString *)videoFolder:(NSString *)identifier;
- (NSString *)moviePath:(NSString *)identifier;
- (NSString *)subtitlesPath:(NSString *)identifier;
- (NSString *)thumbnailPath:(NSString *)identifier;
- (NSString *)stagingFolder:(NSString *)identifier;
- (NSDictionary *)infoFor:(NSString *)identifier;          // duration, subtitles ("made"/"auto"/"none")
// The subtitles the app uses for a video: the sealed made ones when they're
// here and still match the shelf's hash, else the downloaded track (made by a
// person, or YouTube's speech recognition: `automatic`). nil for none.
- (RSSubtitles *)subtitlesFor:(NSString *)identifier;
// "sealed", "made", "auto" or "none": which kind -subtitlesFor: gives.
- (NSString *)subtitlesKindFor:(NSString *)identifier;
- (NSString *)madeSubtitlesPath:(NSString *)identifier;     // Subtitles/<id>.vtt
// The hash sealed for a video's made subtitles (this week's shelf, then the
// next), or nil.
- (NSString *)sealedSubtitleHashFor:(NSString *)identifier;
// Keeps `vtt` as the video's made subtitles if its SHA-256 is the sealed one
// and it reads as subtitles made by a person. YES if it was written now (not
// if it was here already, or refused).
- (BOOL)takeMadeSubtitles:(NSData *)vtt for:(NSString *)identifier;
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
// Whether the video was finished on that day (the day it first reached 90%).
- (BOOL)finishedOnDay:(long)day video:(NSString *)identifier;
- (void)countHelp:(RSHelp)kind for:(NSString *)identifier;
// The same, and noted against the line it was asked on (text nil: no line).
- (void)countHelp:(RSHelp)kind for:(NSString *)identifier line:(NSString *)text start:(double)start;
- (NSUInteger)help:(RSHelp)kind for:(NSString *)identifier;
// The lines help was asked on, by time: each {text, start, and a count per
// RSHelpName}, kind -> NSNumber.
- (NSArray *)helpedLinesFor:(NSString *)identifier;
// The owner's choice about the video (RSFelt..., RSWant...), or nil.
- (NSString *)feltFor:(NSString *)identifier;
- (NSString *)wantFor:(NSString *)identifier;
- (void)setFelt:(NSString *)felt want:(NSString *)want for:(NSString *)identifier;
// The speed the video was left at (1 if never changed) and the slowest ever
// chosen for it (1 if never slowed): the player's ladder, RSPlayer.h. The
// report carries the slowest, so the skill can see when the owner stops
// needing it.
- (float)rateFor:(NSString *)identifier;
- (void)setRate:(float)rate for:(NSString *)identifier;
- (float)slowestFor:(NSString *)identifier;
// The first video on this week's shelf not finished yet, or nil.
- (NSString *)nextIdentifier;

// ---- Clips (RSClips.h) ----
// The clips worked on a video, each {start, end, passes, day} (NSNumbers), in
// the order worked; and today's, whatever video it's of (nil if none).
- (NSArray *)clipsFor:(NSString *)identifier;
- (NSDictionary *)clipOnDay:(long)day;             // adds "video"
// Notes a clip's progress: the same start on the same day is the same clip.
- (void)recordClip:(NSString *)identifier start:(double)start end:(double)end passes:(NSUInteger)passes day:(long)day;

// ---- Say (RSSay.h) ----
// What was said on a day: {island, passes, recorded} (NSString, NSNumbers)
// for the day's first round; nil for none. Later rounds (another topic,
// whenever the owner likes) are under "more", an array of the same.
- (NSDictionary *)sayOnDay:(long)day;
- (void)recordSayOnDay:(long)day island:(NSString *)island passes:(NSUInteger)passes recorded:(BOOL)recorded;
- (void)recordSayOnDay:(long)day island:(NSString *)island passes:(NSUInteger)passes recorded:(BOOL)recorded round:(NSUInteger)round;
- (NSArray *)sayDays;                                 // the days with an entry, ascending (NSNumber)

- (BOOL)save;
// Reads State.plist again (what was watched, the notice), after the sync
// between Macs merged into it. The shelves stay as they are.
- (void)reload;

@end
