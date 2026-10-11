#import "RSDownloader.h"
#import "RSLibrary.h"
#import "RSProcess.h"
#import "RSShelf.h"

static const NSTimeInterval RSUpdateTimeout = 5 * 60;
static const NSTimeInterval RSDownloadTimeout = 3 * 60 * 60;
static const double RSVideoShare = 0.85;     // of a video's progress bar, the picture; the rest is sound

// The prefpane's format sort (downloader.sh): H.264 and AAC first, at the
// best resolution and frame rate.
static NSString *const RSFormatSort = @"+hdr,res,fps,vcodec:h264,vcodec:vp9.2,vcodec:vp9,vcodec:h265,vcodec:h263,"
                                      @"vcodec:vp8,vcodec:theora,vcodec:av1,acodec:aac,acodec:mp4a,acodec:ac3,acodec:opus";
// Its 1080p limit, asking first for what 10.9's AVFoundation can play
// (H.264 with AAC); then its own choice, so a video that only exists in
// other codecs still arrives and the player can say so.
static NSString *const RSFormat = @"bestvideo[height<=1080][vcodec^=avc1]+bestaudio[acodec^=mp4a]"
                                  @"/best[height<=1080][vcodec^=avc1]"
                                  @"/bestvideo[height<=1080]+bestaudio/best[height<=1080]";

@implementation RSTools

- (void)dealloc
{
    [_python release];
    [_bundledYtDlp release];
    [_ffmpeg release];
    [_quickjs release];
    [_certificates release];
    [super dealloc];
}

+ (RSTools *)toolsInFolder:(NSString *)resources
{
    RSTools *t = [[[RSTools alloc] init] autorelease];
    [t setPython:[resources stringByAppendingPathComponent:@"python3/bin/python3.14"]];
    [t setBundledYtDlp:[resources stringByAppendingPathComponent:@"yt-dlp"]];
    [t setFfmpeg:[resources stringByAppendingPathComponent:@"ffmpeg"]];
    [t setQuickjs:[resources stringByAppendingPathComponent:@"qjs"]];
    [t setCertificates:[resources stringByAppendingPathComponent:@"python3/lib/python3.14/site-packages/certifi/cacert.pem"]];
    return t;
}

+ (RSTools *)bundled
{
    return [self toolsInFolder:[[NSBundle mainBundle] resourcePath]];
}

- (NSString *)missing
{
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm isExecutableFileAtPath:_python]) return @"Python";
    if (![fm fileExistsAtPath:_bundledYtDlp]) return @"yt-dlp";
    if (![fm isExecutableFileAtPath:_ffmpeg]) return @"ffmpeg";
    if (![fm isExecutableFileAtPath:_quickjs]) return @"QuickJS";
    if (![fm fileExistsAtPath:_certificates]) return @"the certificate list";
    return nil;
}

@end

NSString *RSWatchURL(NSString *identifier)
{
    if (![RSVideo isValidIdentifier:identifier]) return nil;
    return [@"https://www.youtube.com/watch?v=" stringByAppendingString:identifier];
}

// python3.14 -I (isolated: no PYTHON* variables, no user site packages, no
// current directory), -B (no .pyc files written), -X utf8.
static NSMutableArray *RSPythonPrefix(RSTools *tools, NSString *ytdlp)
{
    return [NSMutableArray arrayWithObjects:[tools python], @"-I", @"-B", @"-X", @"utf8", ytdlp, nil];
}

NSArray *RSDownloadArguments(RSTools *tools, NSString *ytdlp, NSString *identifier, NSString *staging, NSString *cache)
{
    NSString *url = RSWatchURL(identifier);
    if (url == nil || [staging length] == 0) return nil;
    NSMutableArray *a = RSPythonPrefix(tools, ytdlp);
    [a addObjectsFromArray:[NSArray arrayWithObjects:
        // No config files, plugins or playlists: exactly this one video.
        @"--ignore-config", @"--no-plugin-dirs", @"--no-playlist",
        @"--match-filters", [@"id=" stringByAppendingString:identifier],
        @"--cache-dir", cache,
        // The prefpane's choice of format, as MP4.
        @"--format", RSFormat,
        @"--format-sort", RSFormatSort,
        @"--merge-output-format", @"mp4",
        @"--postprocessor-args", @"Merger+ffmpeg_o1:-bsf:v h264_metadata=level=auto",
        @"--ffmpeg-location", [tools ffmpeg],
        @"--js-runtimes", [@"quickjs:" stringByAppendingString:[tools quickjs]],
        // Russian subtitles beside the video, made by a person if there are
        // any (yt-dlp prefers those), else YouTube's automatic ones.
        @"--write-subs", @"--write-auto-subs", @"--sub-langs", @"ru,ru-orig", @"--sub-format", @"vtt",
        @"--write-thumbnail", @"--convert-thumbnails", @"jpg",
        // The prefpane's pace and patience.
        @"--retry-sleep", @"30", @"--sleep-subtitles", @"8", @"--sleep-requests", @"1.5",
        @"--sleep-interval", @"15", @"--max-sleep-interval", @"40",
        @"--socket-timeout", @"30",
        // Progress for the shelf, and the length when done.
        @"--newline", @"--progress",
        @"--progress-template", @"download:RSP %(progress.status)s %(progress.downloaded_bytes)s "
                                @"%(progress.total_bytes)s %(progress.total_bytes_estimate)s %(info.vcodec)s",
        @"--print", @"after_move:RSDONE %(duration)s",
        @"--paths", staging,
        @"--output", @"video.%(ext)s",
        @"--output", @"thumbnail:thumbnail.%(ext)s",
        @"--output", @"subtitle:subtitles.%(ext)s",
        @"--", url, nil]];
    return a;
}

NSArray *RSUpdateArguments(RSTools *tools, NSString *ytdlp)
{
    NSMutableArray *a = RSPythonPrefix(tools, ytdlp);
    [a addObjectsFromArray:[NSArray arrayWithObjects:@"--ignore-config", @"--no-plugin-dirs", @"--update", nil]];
    return a;
}

NSArray *RSVersionArguments(RSTools *tools, NSString *ytdlp)
{
    NSMutableArray *a = RSPythonPrefix(tools, ytdlp);
    [a addObjectsFromArray:[NSArray arrayWithObjects:@"--ignore-config", @"--no-plugin-dirs", @"--version", nil]];
    return a;
}

NSDictionary *RSToolEnvironment(RSTools *tools, NSString *temporary)
{
    // Python's OpenSSL was built with its own idea of where certificates
    // live, which doesn't exist here; certifi's list does, and yt-dlp checks
    // every certificate against it.
    return [NSDictionary dictionaryWithObjectsAndKeys:
        NSHomeDirectory(), @"HOME",
        temporary, @"TMPDIR",
        @"/usr/bin:/bin:/usr/sbin:/sbin", @"PATH",
        @"en_US.UTF-8", @"LANG",
        [tools certificates], @"SSL_CERT_FILE", nil];
}

BOOL RSParseProgress(NSString *line, double *fraction)
{
    if (![line hasPrefix:@"RSP "]) return NO;
    NSArray *f = [line componentsSeparatedByString:@" "];
    if ([f count] < 6) return NO;
    double done = [[f objectAtIndex:2] doubleValue];
    double total = [[f objectAtIndex:3] doubleValue];
    if (total <= 0) total = [[f objectAtIndex:4] doubleValue];
    double part = [[f objectAtIndex:1] isEqualToString:@"finished"] ? 1 : total > 0 ? MIN(1, done / total) : 0;
    BOOL sound = [[f objectAtIndex:5] isEqualToString:@"none"];
    *fraction = sound ? RSVideoShare + (1 - RSVideoShare) * part : RSVideoShare * part;
    return YES;
}

double RSParseDone(NSString *line)
{
    if (![line hasPrefix:@"RSDONE "]) return -1;
    double d = [[line substringFromIndex:7] doubleValue];
    return d > 0 ? d : 0;
}

NSString *RSDownloadProblem(NSString *output, int status)
{
    NSString *error = nil;
    for (NSString *line in [output componentsSeparatedByString:@"\n"])
        if ([line hasPrefix:@"ERROR:"]) error = line;
    NSString *e = [error lowercaseString] ?: @"";
    if ([e rangeOfString:@"confirm you"].location != NSNotFound && [e rangeOfString:@"bot"].location != NSNotFound)
        return @"YouTube wants to check this Mac isn’t a robot. It will try again later.";
    if ([e rangeOfString:@"429"].location != NSNotFound || [e rangeOfString:@"too many requests"].location != NSNotFound)
        return @"YouTube asked for a pause. It will try again later.";
    if ([e rangeOfString:@"certificate"].location != NSNotFound)
        return @"A secure connection couldn’t be checked, so nothing was downloaded.";
    if ([e rangeOfString:@"unavailable"].location != NSNotFound || [e rangeOfString:@"private video"].location != NSNotFound)
        return @"YouTube says this video isn’t available.";
    if ([e rangeOfString:@"getaddrinfo"].location != NSNotFound || [e rangeOfString:@"nodename"].location != NSNotFound ||
        [e rangeOfString:@"timed out"].location != NSNotFound || [e rangeOfString:@"network is unreachable"].location != NSNotFound)
        return @"Couldn’t reach YouTube. Is this Mac online?";
    if (error) {
        // "ERROR: [youtube] JE4cI_Knzvc: Something" -> "Something"
        NSString *s = [[error substringFromIndex:6] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSRange r = [s rangeOfString:@"]"];
        if ([s hasPrefix:@"["] && r.location != NSNotFound) s = [s substringFromIndex:NSMaxRange(r)];
        r = [s rangeOfString:@": "];
        if (r.location != NSNotFound && r.location <= 12) s = [s substringFromIndex:NSMaxRange(r)];
        s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([s length] > 140) s = [[s substringToIndex:140] stringByAppendingString:@"…"];
        return [NSString stringWithFormat:@"yt-dlp said: %@", s];
    }
    return [NSString stringWithFormat:@"The download stopped (status %d).", status];
}

@interface RSDownloader () {
    RSLibrary *_library;
    RSTools *_tools;
    RSProcess *_handle;
    dispatch_queue_t _queue;
}
@property (nonatomic, readwrite) BOOL busy;
@property (nonatomic, readwrite, copy) NSString *updateSummary;
@end

@implementation RSDownloader

- (id)initWithLibrary:(RSLibrary *)library tools:(RSTools *)tools
{
    if (!(self = [super init])) return nil;
    _library = [library retain];
    _tools = [tools retain];
    _queue = dispatch_queue_create("russianshelf.downloads", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (void)dealloc
{
    [_library release];
    [_tools release];
    [_handle release];
    [_updateSummary release];
    dispatch_release(_queue);
    [super dealloc];
}

- (void)cancel
{
    [_handle cancel];
}

- (NSString *)folder:(NSString *)name
{
    NSString *path = [[_library folder] stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
    return path;
}

static NSString *RSVersionOf(RSTools *tools, NSString *ytdlp, NSDictionary *env)
{
    RSProcessResult *r = [RSProcess run:RSVersionArguments(tools, ytdlp) environment:env directory:nil
                                  stdin:nil timeout:60 handle:nil line:nil];
    NSString *v = [[r output] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [r status] == 0 && [v length] >= 10 && [v length] <= 32 ? v : nil;
}

// The copy in Application Support, which -U may replace: put there from the
// bundle when it's missing, broken, or older than the bundle's.
- (NSString *)preparedYtDlp:(NSDictionary *)env
{
    NSString *copy = [[_library folder] stringByAppendingPathComponent:@"yt-dlp"];
    NSString *have = [[NSFileManager defaultManager] fileExistsAtPath:copy] ? RSVersionOf(_tools, copy, env) : nil;
    NSString *bundled = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"RSBundledYtDlpVersion"];
    if (have == nil || (bundled && [have compare:bundled] == NSOrderedAscending)) {
        NSString *temp = [copy stringByAppendingString:@".new"];
        [[NSFileManager defaultManager] removeItemAtPath:temp error:NULL];
        if ([[NSFileManager defaultManager] copyItemAtPath:[_tools bundledYtDlp] toPath:temp error:NULL]) {
            [[NSFileManager defaultManager] removeItemAtPath:copy error:NULL];
            [[NSFileManager defaultManager] moveItemAtPath:temp toPath:copy error:NULL];
        }
    }
    return copy;
}

- (void)downloadIdentifiers:(NSArray *)identifiers
{
    if (_busy || [identifiers count] == 0) return;
    NSString *missing = [_tools missing];
    if (missing) {
        for (NSString *identifier in identifiers)
            [_delegate downloader:self finishedVideo:identifier
                          problem:[NSString stringWithFormat:@"This copy of the app is missing %@.", missing]];
        [_delegate downloaderFinished:self];
        return;
    }
    [self setBusy:YES];
    [_handle release];
    _handle = [[RSProcess alloc] init];
    RSProcess *handle = [[_handle retain] autorelease];
    NSArray *ids = [[identifiers copy] autorelease];
    NSString *cache = [self folder:@"Cache"];
    NSString *logs = [self folder:@"Logs"];
    NSString *temporary = [self folder:@"Temporary"];
    NSDictionary *env = RSToolEnvironment(_tools, temporary);
    [self retain];
    dispatch_async(_queue, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *ytdlp = [self preparedYtDlp:env];

        // Update before every batch, certificates checked (never
        // --no-check-certificates: this downloads code).
        RSProcessResult *update = [RSProcess run:RSUpdateArguments(_tools, ytdlp) environment:env directory:nil
                                           stdin:nil timeout:RSUpdateTimeout handle:handle line:nil];
        [[update output] writeToFile:[logs stringByAppendingPathComponent:@"update.log"] atomically:YES
                            encoding:NSUTF8StringEncoding error:NULL];
        NSString *summary = nil;
        for (NSString *line in [[update output] componentsSeparatedByString:@"\n"])
            if ([line length] && ![line hasPrefix:@"[debug]"]) summary = line;
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self setUpdateSummary:[update status] == 0 ? summary : [NSString stringWithFormat:@"yt-dlp couldn’t update: %@", summary]];
        });

        for (NSString *identifier in ids) {
            if ([handle isCancelled]) break;
            __block NSString *staging = nil;
            dispatch_sync(dispatch_get_main_queue(), ^{
                staging = [[[self delegate] downloader:self stillWanted:identifier] copy];
            });
            [staging autorelease];
            if (staging == nil) continue;
            [[NSFileManager defaultManager] createDirectoryAtPath:staging withIntermediateDirectories:YES attributes:nil error:NULL];
            NSArray *args = RSDownloadArguments(_tools, ytdlp, identifier, staging, cache);
            if (args == nil) continue;

            __block double duration = 0;
            __block CFAbsoluteTime lastReport = 0;
            RSProcessResult *r = [RSProcess run:args environment:env directory:staging stdin:nil
                                        timeout:RSDownloadTimeout handle:handle line:^(NSString *line) {
                double fraction = 0, d = RSParseDone(line);
                if (d >= 0) duration = d;
                if (!RSParseProgress(line, &fraction)) return;
                CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
                if (now - lastReport < 0.5 && fraction < 1) return;
                lastReport = now;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[self delegate] downloader:self progress:fraction video:identifier];
                });
            }];
            [[r output] writeToFile:[logs stringByAppendingPathComponent:[identifier stringByAppendingPathExtension:@"log"]]
                         atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            __block NSString *problem = nil;
            if ([r cancelled]) {
                problem = @"Stopped.";
            } else if ([r status] != 0 || [r timedOut]) {
                problem = [r timedOut] ? @"The download took over three hours and was stopped." : RSDownloadProblem([r output], [r status]);
            }
            dispatch_sync(dispatch_get_main_queue(), ^{
                NSString *why = problem;
                if (why == nil && ![_library installDownload:identifier duration:duration problem:&why]) {}
                [[self delegate] downloader:self finishedVideo:identifier problem:why];
            });
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setBusy:NO];
            [[self delegate] downloaderFinished:self];
            [self release];
        });
        [pool drain];
    });
}

@end
