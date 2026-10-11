// Downloads a shelf's videos with the bundled yt-dlp, the way Wowfunhappy's
// media-subscriptions-prefpane does (its downloader.sh), with three changes:
// certificates are always checked, one video is fetched per run (so progress
// is per video), and only ids from a shelf that opened are ever passed in.
//
// The bundle's Resources hold:
//
//   python3/     Python 3.14 for 10.9, with OpenSSL, certifi and the
//                packages yt-dlp uses (Deps/build-python.sh)
//   yt-dlp       copied to Application Support on first use and updated
//                there before each batch (-U), certificates checked
//   ffmpeg       merges video and sound, fixes the H.264 level, converts
//                thumbnails
//   qjs          QuickJS, the JavaScript runtime yt-dlp uses for YouTube's
//                player challenges (the prefpane's deno can't run on 10.9)
//
// Each video: MP4 at most 1080p, H.264 and AAC preferred, Russian subtitles
// (made by a person if there are any, else YouTube's automatic ones) as
// subtitles.ru.vtt beside it, and the thumbnail as JPEG.

#import <Foundation/Foundation.h>

@class RSLibrary, RSDownloader;

@interface RSTools : NSObject
@property (nonatomic, copy) NSString *python, *bundledYtDlp, *ffmpeg, *quickjs, *certificates;
+ (RSTools *)toolsInFolder:(NSString *)resources;
+ (RSTools *)bundled;                     // this app's Resources
- (NSString *)missing;                    // the first tool that isn't there, or nil
@end

// The command lines, kept apart so the tests can read them.
NSString *RSWatchURL(NSString *identifier);       // nil unless a valid id
NSArray *RSDownloadArguments(RSTools *tools, NSString *ytdlp, NSString *identifier, NSString *staging, NSString *cache);
NSArray *RSUpdateArguments(RSTools *tools, NSString *ytdlp);
NSArray *RSVersionArguments(RSTools *tools, NSString *ytdlp);
NSDictionary *RSToolEnvironment(RSTools *tools, NSString *temporary);

// "RSP downloading 1200 4800 NA avc1.640028": how far into this video
// (video first, then sound). NO if the line isn't progress.
BOOL RSParseProgress(NSString *line, double *fraction);
// The duration yt-dlp reports when it's done ("RSDONE 612"), or -1.
double RSParseDone(NSString *line);
// One sentence from yt-dlp's last ERROR line.
NSString *RSDownloadProblem(NSString *output, int status);

@protocol RSDownloaderDelegate <NSObject>
// All on the main thread.
- (void)downloader:(RSDownloader *)downloader progress:(double)fraction video:(NSString *)identifier;
- (void)downloader:(RSDownloader *)downloader finishedVideo:(NSString *)identifier problem:(NSString *)problem;
- (void)downloaderFinished:(RSDownloader *)downloader;
- (NSString *)downloader:(RSDownloader *)downloader stillWanted:(NSString *)identifier;   // staging folder, or nil
@end

@interface RSDownloader : NSObject

- (id)initWithLibrary:(RSLibrary *)library tools:(RSTools *)tools;
@property (nonatomic, assign) id<RSDownloaderDelegate> delegate;
@property (nonatomic, readonly) BOOL busy;
@property (nonatomic, readonly, copy) NSString *updateSummary;   // what the last -U said

// Updates yt-dlp, then fetches each id in turn, on a background queue.
// Ignored while a batch is running.
- (void)downloadIdentifiers:(NSArray *)identifiers;
- (void)cancel;

@end
