#import "RSLibrary.h"
#import "RSSubtitles.h"

const double RSFinishedFraction = 0.9;

static NSString *const RSCurrentFile = @"Shelf.signed";
static NSString *const RSPendingFile = @"Next Shelf.signed";
static NSString *const RSStateFile = @"State.plist";

@implementation RSWatch
@end

@interface RSLibrary () {
    NSData *_aesKey, *_publicKey;
    NSMutableDictionary *_watched;      // id -> {position, furthest, duration, finished}
}
@property (nonatomic, readwrite, copy) NSString *folder;
@property (nonatomic, readwrite, retain) RSShelf *current;
@property (nonatomic, readwrite, retain) RSShelf *pending;
@property (nonatomic, readwrite, copy) NSString *notice;
@end

@implementation RSLibrary

+ (NSString *)defaultFolder
{
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = [dirs count] ? [dirs objectAtIndex:0] : [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
    return [base stringByAppendingPathComponent:@"Russian Shelf"];
}

- (id)initWithFolder:(NSString *)folder
{
    return [self initWithFolder:folder aesKey:RSAppAESKey() publicKey:RSAppPublicKey()];
}

- (id)initWithFolder:(NSString *)folder aesKey:(NSData *)aesKey publicKey:(NSData *)publicKey
{
    if (!(self = [super init])) return nil;
    _folder = [folder copy];
    _aesKey = [aesKey copy];
    _publicKey = [publicKey copy];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:[folder stringByAppendingPathComponent:@"Videos"] withIntermediateDirectories:YES attributes:nil error:NULL];

    NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:[folder stringByAppendingPathComponent:RSStateFile]];
    _watched = [[NSMutableDictionary alloc] init];
    NSDictionary *watched = [state objectForKey:@"watched"];
    if ([watched isKindOfClass:[NSDictionary class]])
        for (NSString *identifier in watched)
            if ([[watched objectForKey:identifier] isKindOfClass:[NSDictionary class]])
                [_watched setObject:[[[watched objectForKey:identifier] mutableCopy] autorelease] forKey:identifier];
    if ([[state objectForKey:@"notice"] isKindOfClass:[NSString class]]) _notice = [[state objectForKey:@"notice"] copy];

    // Shelves are checked again every time: a file here is no more trusted
    // than one in the study folder.
    NSString *problem = nil;
    NSData *file = [NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:RSCurrentFile]];
    if (file) _current = [RSOpenSealedShelf(file, _aesKey, _publicKey, &problem) retain];
    file = [NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:RSPendingFile]];
    if (file) _pending = [RSOpenSealedShelf(file, _aesKey, _publicKey, &problem) retain];
    return self;
}

- (void)dealloc
{
    [_folder release];
    [_aesKey release];
    [_publicKey release];
    [_watched release];
    [_current release];
    [_pending release];
    [_notice release];
    [super dealloc];
}

- (BOOL)save
{
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    [state setObject:_watched forKey:@"watched"];
    if (_notice) [state setObject:_notice forKey:@"notice"];
    return [state writeToFile:[_folder stringByAppendingPathComponent:RSStateFile] atomically:YES];
}

- (BOOL)writeShelfFile:(NSData *)file named:(NSString *)name
{
    NSString *path = [_folder stringByAppendingPathComponent:name];
    if (file == nil) return [[NSFileManager defaultManager] removeItemAtPath:path error:NULL] || YES;
    return [file writeToFile:path atomically:YES];
}

- (RSOffer)offerShelfFile:(NSData *)file today:(long)today
{
    NSString *problem = nil;
    RSShelf *shelf = RSOpenSealedShelf(file, _aesKey, _publicKey, &problem);
    if (shelf && ([[shelf fingerprint] isEqualToString:[_current fingerprint]] ||
                  [[shelf fingerprint] isEqualToString:[_pending fingerprint]])) {
        // The study folder is back to a shelf already here: whatever was
        // turned away is gone, and so is the warning.
        if (_notice) { [self setNotice:nil]; [self save]; }
        return RSOfferNothingNew;
    }
    RSShelf *newest = _pending ?: _current;
    if (shelf && newest && ![shelf isNewerThan:newest])
        problem = [NSString stringWithFormat:@"It’s older than the shelf of %@.", [newest startText]];
    if (problem) {
        [self setNotice:[NSString stringWithFormat:@"A new shelf was turned away. %@", problem]];
        [self save];
        return RSOfferRefused;
    }

    [self setNotice:nil];
    RSOffer offer;
    if (_current == nil || [shelf start] <= today) {
        [self setCurrent:shelf];
        [self setPending:nil];
        [self writeShelfFile:file named:RSCurrentFile];
        [self writeShelfFile:nil named:RSPendingFile];
        offer = RSOfferTaken;
    } else {
        [self setPending:shelf];
        [self writeShelfFile:file named:RSPendingFile];
        offer = RSOfferQueued;
    }
    [self save];
    return offer;
}

- (BOOL)advanceToDay:(long)today replaced:(RSShelf **)replaced
{
    if (replaced) *replaced = nil;
    if (_pending == nil || [_pending start] > today) return NO;
    NSData *file = [NSData dataWithContentsOfFile:[_folder stringByAppendingPathComponent:RSPendingFile]];
    if (file == nil || ![self writeShelfFile:file named:RSCurrentFile]) return NO;
    if (replaced) *replaced = [[_current retain] autorelease];
    [self setCurrent:_pending];
    [self setPending:nil];
    [self writeShelfFile:nil named:RSPendingFile];
    return YES;
}

// ---- Files ---------------------------------------------------------------

- (NSString *)videoFolder:(NSString *)identifier
{
    return [[_folder stringByAppendingPathComponent:@"Videos"] stringByAppendingPathComponent:identifier];
}

- (NSString *)moviePath:(NSString *)identifier
{
    return [[self videoFolder:identifier] stringByAppendingPathComponent:@"video.mp4"];
}

- (NSString *)subtitlesPath:(NSString *)identifier
{
    return [[self videoFolder:identifier] stringByAppendingPathComponent:@"subtitles.vtt"];
}

- (NSString *)thumbnailPath:(NSString *)identifier
{
    return [[self videoFolder:identifier] stringByAppendingPathComponent:@"thumbnail.jpg"];
}

- (NSString *)stagingFolder:(NSString *)identifier
{
    return [[_folder stringByAppendingPathComponent:@"Downloads"] stringByAppendingPathComponent:identifier];
}

- (NSDictionary *)infoFor:(NSString *)identifier
{
    return [NSDictionary dictionaryWithContentsOfFile:[[self videoFolder:identifier] stringByAppendingPathComponent:@"info.plist"]];
}

- (BOOL)isDownloaded:(NSString *)identifier
{
    NSFileManager *fm = [NSFileManager defaultManager];
    return [fm fileExistsAtPath:[self moviePath:identifier]] &&
           [fm fileExistsAtPath:[[self videoFolder:identifier] stringByAppendingPathComponent:@"info.plist"]];
}

- (NSArray *)identifiersToDownload
{
    NSMutableArray *ids = [NSMutableArray array];
    for (RSShelf *shelf in [NSArray arrayWithObjects:_current ?: (id)[NSNull null], _pending ?: (id)[NSNull null], nil]) {
        if ((id)shelf == [NSNull null]) continue;
        for (NSString *identifier in [shelf identifiers])
            if (![self isDownloaded:identifier] && ![ids containsObject:identifier]) [ids addObject:identifier];
    }
    return ids;
}

- (BOOL)isCurrentComplete
{
    if (_current == nil) return NO;
    for (NSString *identifier in [_current identifiers])
        if (![self isDownloaded:identifier]) return NO;
    return YES;
}

static NSString *RSFirstFile(NSString *folder, NSString *prefix, NSArray *extensions)
{
    NSArray *names = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:NULL]
                      sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *ext in extensions)
        for (NSString *name in names)
            if ([name hasPrefix:prefix] && [[name pathExtension] isEqualToString:ext] &&
                ![name hasSuffix:@".part"] && [name rangeOfString:@".temp."].location == NSNotFound)
                return [folder stringByAppendingPathComponent:name];
    return nil;
}

- (BOOL)installDownload:(NSString *)identifier duration:(double)duration problem:(NSString **)problem
{
    *problem = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *staging = [self stagingFolder:identifier];
    NSString *movie = [staging stringByAppendingPathComponent:@"video.mp4"];
    NSDictionary *attributes = [fm attributesOfItemAtPath:movie error:NULL];
    if ([attributes fileSize] == 0) { *problem = @"The download didn’t leave an MP4 behind."; return NO; }
    // yt-dlp fetches both "ru" (made by a person, when there is one; else a
    // machine translation) and "ru-orig" (speech recognition). Keep the one
    // a person made, else the speech recognition.
    NSString *subtitles = nil, *kind = @"none";
    for (NSString *name in [[fm contentsOfDirectoryAtPath:staging error:NULL] sortedArrayUsingSelector:@selector(compare:)]) {
        if (![name hasPrefix:@"subtitles."] || ![[name pathExtension] isEqualToString:@"vtt"]) continue;
        RSSubtitles *parsed = [RSSubtitles subtitlesWithFile:[staging stringByAppendingPathComponent:name]];
        if ([[parsed lines] count] == 0) continue;
        BOOL original = [name rangeOfString:@"-orig."].location != NSNotFound;
        if (![parsed automatic] && !original) { subtitles = name; kind = @"made"; break; }
        if ([parsed automatic] && (original || subtitles == nil)) { subtitles = name; kind = @"auto"; }
    }
    if (subtitles) subtitles = [staging stringByAppendingPathComponent:subtitles];
    NSString *thumbnail = RSFirstFile(staging, @"thumbnail", [NSArray arrayWithObjects:@"jpg", @"jpeg", @"png", nil]);

    NSString *final = [self videoFolder:identifier];
    NSString *temp = [final stringByAppendingString:@".new"];
    [fm removeItemAtPath:temp error:NULL];
    if (![fm createDirectoryAtPath:temp withIntermediateDirectories:YES attributes:nil error:NULL] ||
        ![fm moveItemAtPath:movie toPath:[temp stringByAppendingPathComponent:@"video.mp4"] error:NULL]) {
        *problem = @"The video couldn’t be moved into place.";
        return NO;
    }
    if (subtitles && ![fm moveItemAtPath:subtitles toPath:[temp stringByAppendingPathComponent:@"subtitles.vtt"] error:NULL])
        kind = @"none";
    if (thumbnail)
        [fm moveItemAtPath:thumbnail toPath:[temp stringByAppendingPathComponent:
                                            [@"thumbnail" stringByAppendingPathExtension:@"jpg"]] error:NULL];
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithDouble:duration], @"duration",
        kind, @"subtitles",
        [NSDate date], @"downloaded", nil];
    [info writeToFile:[temp stringByAppendingPathComponent:@"info.plist"] atomically:YES];
    [fm removeItemAtPath:final error:NULL];
    if (![fm moveItemAtPath:temp toPath:final error:NULL]) {
        *problem = @"The video couldn’t be moved into place.";
        return NO;
    }
    [fm removeItemAtPath:staging error:NULL];
    return YES;
}

- (NSArray *)removeLeftovers
{
    if (![self isCurrentComplete]) return [NSArray array];
    NSMutableSet *keep = [NSMutableSet setWithArray:[_current identifiers]];
    if (_pending) [keep addObjectsFromArray:[_pending identifiers]];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *removed = [NSMutableArray array];
    for (NSString *sub in [NSArray arrayWithObjects:@"Videos", @"Downloads", nil]) {
        NSString *dir = [_folder stringByAppendingPathComponent:sub];
        for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:NULL]) {
            NSString *identifier = [name hasSuffix:@".new"] ? [name stringByDeletingPathExtension] : name;
            if ([keep containsObject:identifier] && ![name hasSuffix:@".new"]) continue;
            if ([fm removeItemAtPath:[dir stringByAppendingPathComponent:name] error:NULL] &&
                [sub isEqualToString:@"Videos"] && ![name hasSuffix:@".new"] && ![removed containsObject:identifier])
                [removed addObject:identifier];
        }
    }
    for (NSString *identifier in [_watched allKeys])
        if (![keep containsObject:identifier]) [_watched removeObjectForKey:identifier];
    [self save];
    return removed;
}

// ---- Watching ------------------------------------------------------------

- (RSWatch *)watchFor:(NSString *)identifier
{
    NSDictionary *w = [_watched objectForKey:identifier];
    RSWatch *watch = [[[RSWatch alloc] init] autorelease];
    [watch setPosition:[[w objectForKey:@"position"] doubleValue]];
    [watch setFurthest:[[w objectForKey:@"furthest"] doubleValue]];
    [watch setDuration:[[w objectForKey:@"duration"] doubleValue]];
    [watch setFinished:[[w objectForKey:@"finished"] boolValue]];
    if ([watch duration] <= 0) [watch setDuration:[[[self infoFor:identifier] objectForKey:@"duration"] doubleValue]];
    return watch;
}

- (BOOL)recordPosition:(double)position furthest:(double)furthest duration:(double)duration for:(NSString *)identifier
{
    RSWatch *old = [self watchFor:identifier];
    if (duration <= 0) duration = [old duration];
    double far = MAX([old furthest], furthest);
    if (duration > 0) far = MIN(far, duration);
    BOOL finished = [old finished] || (duration > 0 && far >= RSFinishedFraction * duration);
    NSMutableDictionary *w = [NSMutableDictionary dictionaryWithDictionary:[_watched objectForKey:identifier] ?: [NSDictionary dictionary]];
    [w setObject:[NSNumber numberWithDouble:MAX(0, position)] forKey:@"position"];
    [w setObject:[NSNumber numberWithDouble:far] forKey:@"furthest"];
    [w setObject:[NSNumber numberWithDouble:MAX(0, duration)] forKey:@"duration"];
    [w setObject:[NSNumber numberWithBool:finished] forKey:@"finished"];
    [_watched setObject:w forKey:identifier];
    return finished && ![old finished];
}

static NSString *RSHelpKey(RSHelp kind)
{
    return kind == RSHelpShown ? @"shown" : kind == RSHelpHeardAgain ? @"heardAgain" : @"kept";
}

- (void)countHelp:(RSHelp)kind for:(NSString *)identifier
{
    if ([identifier length] == 0) return;
    NSMutableDictionary *w = [NSMutableDictionary dictionaryWithDictionary:[_watched objectForKey:identifier] ?: [NSDictionary dictionary]];
    NSUInteger n = [[w objectForKey:RSHelpKey(kind)] unsignedIntegerValue] + 1;
    [w setObject:[NSNumber numberWithUnsignedInteger:n] forKey:RSHelpKey(kind)];
    [_watched setObject:w forKey:identifier];
}

- (NSUInteger)help:(RSHelp)kind for:(NSString *)identifier
{
    return [[[_watched objectForKey:identifier] objectForKey:RSHelpKey(kind)] unsignedIntegerValue];
}

- (NSString *)nextIdentifier
{
    for (NSString *identifier in [_current identifiers])
        if (![[self watchFor:identifier] finished]) return identifier;
    return nil;
}

@end
