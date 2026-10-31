#import "RSSyncManager.h"
#import "RSSyncFolder.h"
#import "RSMerge.h"
#import "RSSync.h"

@interface RSSyncManager ()
@property (nonatomic, readwrite, copy) NSString *appFolder, *studyFolder, *host;
@end

// "2026-11.m4a"
static BOOL RSIsMonthFile(NSString *name)
{
    if ([name length] != 11 || ![name hasSuffix:@".m4a"]) return NO;
    for (NSUInteger i = 0; i < 7; i++) {
        unichar c = [name characterAtIndex:i];
        if (i == 4 ? c != '-' : (c < '0' || c > '9')) return NO;
    }
    return YES;
}

// File names composed (HFS+ gives them back decomposed; the cards' keys
// are composed), so a word's card finds its sound.
static NSString *RSComposed(NSString *name)
{
    return [name precomposedStringWithCanonicalMapping];
}

static NSArray *RSNames(NSString *folder)
{
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:NULL])
        [names addObject:RSComposed(name)];
    return names;
}

static NSArray *RSCardList(NSDictionary *cards)
{
    id lines = [cards objectForKey:@"lines"];
    return [lines isKindOfClass:[NSArray class]] ? lines : [NSArray array];
}

static NSString *RSReadText(NSString *path)
{
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
}

// Copied beside, then moved into place: never half a file where it's read.
static BOOL RSCopyFile(NSString *from, NSString *to)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *temp = [[to stringByDeletingLastPathComponent] stringByAppendingPathComponent:
                      [@".sync-" stringByAppendingString:[to lastPathComponent]]];
    [fm createDirectoryAtPath:[to stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
    [fm removeItemAtPath:temp error:NULL];
    if (![fm copyItemAtPath:from toPath:temp error:NULL]) return NO;
    NSDate *modified = [[fm attributesOfItemAtPath:from error:NULL] fileModificationDate];
    if (modified) [fm setAttributes:[NSDictionary dictionaryWithObject:modified forKey:NSFileModificationDate] ofItemAtPath:temp error:NULL];
    [fm removeItemAtPath:to error:NULL];
    if ([fm moveItemAtPath:temp toPath:to error:NULL]) return YES;
    [fm removeItemAtPath:temp error:NULL];
    return NO;
}

static BOOL RSWriteText(NSString *text, NSString *path)
{
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    return [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

@implementation RSSyncManager

+ (dispatch_queue_t)gitQueue
{
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.russianshelf.git", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

- (id)initWithAppFolder:(NSString *)appFolder studyFolder:(NSString *)studyFolder
{
    return [self initWithAppFolder:appFolder studyFolder:studyFolder host:[RSSyncFolder hostSlug]];
}

- (id)initWithAppFolder:(NSString *)appFolder studyFolder:(NSString *)studyFolder host:(NSString *)slug
{
    if (!(self = [super init])) return nil;
    _appFolder = [appFolder copy];
    _studyFolder = [studyFolder copy];
    _host = [[RSSyncFolder slugForName:slug] copy];
    return self;
}

- (void)dealloc
{
    [_appFolder release];
    [_studyFolder release];
    [_host release];
    [super dealloc];
}

- (NSString *)outFolder { return [_appFolder stringByAppendingPathComponent:@"Sync Out"]; }
- (NSString *)inFolder { return [_appFolder stringByAppendingPathComponent:@"Sync In"]; }
- (NSString *)statePath { return [_appFolder stringByAppendingPathComponent:@"State.plist"]; }
- (NSString *)linesFolder { return [_appFolder stringByAppendingPathComponent:@"Lines"]; }
- (NSString *)cardsPath { return [[self linesFolder] stringByAppendingPathComponent:@"Lines.plist"]; }
- (NSString *)sayFolder { return [_appFolder stringByAppendingPathComponent:@"Say"]; }

// ---- In ------------------------------------------------------------------------------

- (BOOL)takeOtherHosts:(NSString **)problem
{
    return [RSSyncFolder copyOtherHosts:_host from:_studyFolder into:[self inFolder] problem:problem];
}

+ (NSArray *)hostsIn:(NSString *)hostsFolder except:(NSString *)slug
{
    NSMutableArray *hosts = [NSMutableArray array];
    for (NSString *name in [RSNames(hostsFolder) sortedArrayUsingSelector:@selector(compare:)]) {
        BOOL folder = NO;
        if ([name isEqualToString:slug] || ![[RSSyncFolder slugForName:name] isEqualToString:name] ||
            ![[NSFileManager defaultManager] fileExistsAtPath:[hostsFolder stringByAppendingPathComponent:name] isDirectory:&folder] || !folder)
            continue;
        [hosts addObject:[hostsFolder stringByAppendingPathComponent:name]];
    }
    return hosts;
}

// Copies what `remote` has and `local` lacks; YES if anything was.
static BOOL RSCopyMissing(NSString *remote, NSString *local, NSArray *names)
{
    BOOL copied = NO;
    for (NSString *name in [RSMerge missing:RSNames(local) from:names])
        copied |= RSCopyFile([remote stringByAppendingPathComponent:name], [local stringByAppendingPathComponent:name]);
    return copied;
}

- (BOOL)mergeInCards:(BOOL)cards
{
    return [self mergeFrom:[self inFolder] cards:cards];
}

- (BOOL)mergeFrom:(NSString *)hostsFolder cards:(BOOL)cards
{
    NSArray *hosts = [[self class] hostsIn:hostsFolder except:_host];
    if ([hosts count] == 0) return NO;
    NSString *islandsPath = [[self sayFolder] stringByAppendingPathComponent:@"Islands.txt"];
    NSString *tutorPath = [[self sayFolder] stringByAppendingPathComponent:@"Tutor.txt"];
    NSDictionary *state0 = [NSDictionary dictionaryWithContentsOfFile:[self statePath]];
    NSDictionary *cards0 = [NSDictionary dictionaryWithContentsOfFile:[self cardsPath]];
    NSString *islands0 = RSReadText(islandsPath), *tutor0 = RSReadText(tutorPath);
    NSDictionary *state = state0, *lines = cards0;
    NSString *islands = islands0, *tutor = tutor0;
    for (NSString *host in hosts) {
        NSDictionary *theirs = [NSDictionary dictionaryWithContentsOfFile:[host stringByAppendingPathComponent:@"State.plist"]];
        if (theirs) state = [RSMerge state:state with:theirs];
        theirs = cards ? [NSDictionary dictionaryWithContentsOfFile:[host stringByAppendingPathComponent:@"Cards.plist"]] : nil;
        if (theirs) lines = [RSMerge cards:lines with:theirs];
        NSString *text = RSReadText([host stringByAppendingPathComponent:@"Islands.txt"]);
        if (text) islands = [RSMerge islands:islands with:text];
        text = RSReadText([host stringByAppendingPathComponent:@"Tutor.txt"]);
        if (text) tutor = [RSMerge tutor:tutor with:text];
    }

    BOOL changed = NO;
    if (state && ![state isEqual:state0]) changed |= [state writeToFile:[self statePath] atomically:YES];
    if (lines && ![lines isEqual:cards0]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:[self linesFolder] withIntermediateDirectories:YES attributes:nil error:NULL];
        changed |= [lines writeToFile:[self cardsPath] atomically:YES];
    }
    if (islands && ![islands isEqualToString:islands0 ?: @""] && [islands length]) changed |= RSWriteText(islands, islandsPath);
    if (tutor && ![tutor isEqualToString:tutor0 ?: @""] && [tutor length]) changed |= RSWriteText(tutor, tutorPath);

    // The sounds of the cards here that only another Mac has; the months'
    // recordings this Mac hasn't got.
    NSMutableSet *keys = [NSMutableSet set];
    for (NSDictionary *card in RSCardList(lines))
        if ([card isKindOfClass:[NSDictionary class]] && [RSMerge isCardKey:[card objectForKey:@"key"]])
            [keys addObject:[[card objectForKey:@"key"] stringByAppendingPathExtension:@"m4a"]];
    for (NSString *host in hosts) {
        if (cards) {
            NSMutableArray *sounds = [NSMutableArray array];
            for (NSString *name in RSNames([host stringByAppendingPathComponent:@"Cards"]))
                if ([keys containsObject:name]) [sounds addObject:name];
            changed |= RSCopyMissing([host stringByAppendingPathComponent:@"Cards"], [self linesFolder], sounds);
        }
        NSMutableArray *months = [NSMutableArray array];
        for (NSString *name in RSNames([host stringByAppendingPathComponent:@"Recordings"]))
            if (RSIsMonthFile(name)) [months addObject:name];
        changed |= RSCopyMissing([host stringByAppendingPathComponent:@"Recordings"],
                                 [[self sayFolder] stringByAppendingPathComponent:@"Recordings"], months);
    }
    return changed;
}

// ---- Out ------------------------------------------------------------------------------

// What Sync Out should hold: its relative path -> the file here.
- (NSDictionary *)outgoing
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableDictionary *files = [NSMutableDictionary dictionary];
    NSString *say = [self sayFolder];
    NSDictionary *sources = [NSDictionary dictionaryWithObjectsAndKeys:
        [self statePath], @"State.plist", [self cardsPath], @"Cards.plist",
        [say stringByAppendingPathComponent:@"Islands.txt"], @"Islands.txt",
        [say stringByAppendingPathComponent:@"Tutor.txt"], @"Tutor.txt", nil];
    for (NSString *name in sources)
        if ([fm fileExistsAtPath:[sources objectForKey:name]]) [files setObject:[sources objectForKey:name] forKey:name];
    for (NSDictionary *card in RSCardList([NSDictionary dictionaryWithContentsOfFile:[self cardsPath]])) {
        if (![card isKindOfClass:[NSDictionary class]] || ![RSMerge isCardKey:[card objectForKey:@"key"]]) continue;
        NSString *name = [[card objectForKey:@"key"] stringByAppendingPathExtension:@"m4a"];
        NSString *sound = [[self linesFolder] stringByAppendingPathComponent:name];
        if ([fm fileExistsAtPath:sound]) [files setObject:sound forKey:[@"Cards" stringByAppendingPathComponent:name]];
    }
    NSString *recordings = [say stringByAppendingPathComponent:@"Recordings"];
    for (NSString *name in RSNames(recordings))
        if (RSIsMonthFile(name)) [files setObject:[recordings stringByAppendingPathComponent:name]
                                           forKey:[@"Recordings" stringByAppendingPathComponent:name]];
    return files;
}

- (void)stage
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *out = [self outFolder];
    [fm createDirectoryAtPath:out withIntermediateDirectories:YES attributes:nil error:NULL];
    NSDictionary *files = [self outgoing];
    for (NSString *relative in files) {
        NSString *from = [files objectForKey:relative], *to = [out stringByAppendingPathComponent:relative];
        NSDictionary *a = [fm attributesOfItemAtPath:from error:NULL], *b = [fm attributesOfItemAtPath:to error:NULL];
        if (b && [a fileSize] == [b fileSize] && [[a fileModificationDate] isEqualToDate:[b fileModificationDate]]) continue;
        RSCopyFile(from, to);
    }
    // Whatever isn't here any more goes from Sync Out, and so from this
    // Mac's folder in the repository.
    for (NSString *relative in [[fm subpathsOfDirectoryAtPath:out error:NULL] sortedArrayUsingSelector:@selector(compare:)]) {
        BOOL folder = NO;
        NSString *path = [out stringByAppendingPathComponent:relative];
        if ([fm fileExistsAtPath:path isDirectory:&folder] && !folder && [files objectForKey:RSComposed(relative)] == nil)
            [fm removeItemAtPath:path error:NULL];
    }
}

- (RSSyncResult *)publish
{
    return [RSSyncFolder publish:[self outFolder] host:_host folder:_studyFolder];
}

// ---- The brakes -------------------------------------------------------------------------

+ (NSArray *)otherCards:(NSString *)appFolder
{
    NSMutableArray *found = [NSMutableArray array];
    for (NSString *host in [self hostsIn:[appFolder stringByAppendingPathComponent:@"Sync In"] except:nil]) {
        NSDictionary *cards = [NSDictionary dictionaryWithContentsOfFile:[host stringByAppendingPathComponent:@"Cards.plist"]];
        if (cards) [found addObject:cards];
    }
    return found;
}

+ (NSUInteger)heardTodayOnOtherHosts:(NSString *)appFolder today:(long)today
{
    NSUInteger heard = 0;
    for (NSDictionary *cards in [self otherCards:appFolder])
        if ([[cards objectForKey:@"heardDay"] longValue] == today)
            heard += [[cards objectForKey:@"heardCount"] unsignedIntegerValue];
    return heard;
}

+ (NSUInteger)keptTodayOnOtherHosts:(NSString *)appFolder today:(long)today
{
    NSMutableSet *here = [NSMutableSet set], *kept = [NSMutableSet set];
    NSDictionary *mine = [NSDictionary dictionaryWithContentsOfFile:
                          [[appFolder stringByAppendingPathComponent:@"Lines"] stringByAppendingPathComponent:@"Lines.plist"]];
    for (NSDictionary *card in RSCardList(mine))
        if ([card isKindOfClass:[NSDictionary class]] && [card objectForKey:@"key"]) [here addObject:[card objectForKey:@"key"]];
    for (NSDictionary *cards in [self otherCards:appFolder])
        for (NSDictionary *card in RSCardList(cards))
            if ([card isKindOfClass:[NSDictionary class]] && [[card objectForKey:@"kept"] longValue] == today &&
                [RSMerge isCardKey:[card objectForKey:@"key"]] && ![here containsObject:[card objectForKey:@"key"]])
                [kept addObject:[card objectForKey:@"key"]];
    return [kept count];
}

@end
