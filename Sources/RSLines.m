#import "RSLines.h"
#import "RSSyncManager.h"
#include <math.h>

const NSUInteger RSKeepPerDay = 15;
const NSUInteger RSHearPerDay = 60;
const NSUInteger RSWaitingBrake = 45;
const NSUInteger RSPutAwayAfter = 6;

static NSString *const RSLinesFile = @"Lines.plist";
NSString *const RSCardLine = @"line", *const RSCardWord = @"word";

long RSLineGap(NSUInteger step)
{
    static const long gaps[] = { 1, 3, 7, 16, 35, 75 };
    return step < sizeof gaps / sizeof gaps[0] ? gaps[step] : 0;
}

@implementation RSKeptLine

- (void)dealloc
{
    [_key release];
    [_video release];
    [_title release];
    [_text release];
    [_before release];
    [_meaning release];
    [_kind release];
    [_word release];
    [_lemma release];
    [_gloss release];
    [super dealloc];
}

- (BOOL)isWord
{
    return [_kind isEqualToString:RSCardWord];
}

- (NSDictionary *)plist
{
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        _key, @"key", _video, @"video", _title ?: @"", @"title", _text, @"text",
        [NSNumber numberWithDouble:_start], @"start", [NSNumber numberWithDouble:_end], @"end",
        [NSNumber numberWithLong:_kept], @"kept", [NSNumber numberWithLong:_due], @"due",
        [NSNumber numberWithUnsignedInteger:_step], @"step", [NSNumber numberWithUnsignedInteger:_lapses], @"lapses",
        [NSNumber numberWithBool:_putAway], @"putAway",
        [NSNumber numberWithLong:_heard], @"heard", [NSNumber numberWithBool:_knewLast], @"knewLast", nil];
    if (_before) [d setObject:_before forKey:@"before"];
    if ([_meaning length]) [d setObject:_meaning forKey:@"meaning"];
    if ([self isWord]) {
        [d setObject:RSCardWord forKey:@"kind"];
        [d setObject:_word ?: @"" forKey:@"word"];
        [d setObject:_lemma ?: @"" forKey:@"lemma"];
        [d setObject:_gloss ?: @"" forKey:@"gloss"];
        [d setObject:[NSNumber numberWithUnsignedInteger:_rank] forKey:@"rank"];
    }
    return d;
}

+ (RSKeptLine *)lineWithPlist:(NSDictionary *)d
{
    if (![d isKindOfClass:[NSDictionary class]]) return nil;
    NSString *key = [d objectForKey:@"key"], *video = [d objectForKey:@"video"], *text = [d objectForKey:@"text"];
    if (![key isKindOfClass:[NSString class]] || ![video isKindOfClass:[NSString class]] || ![text isKindOfClass:[NSString class]])
        return nil;
    RSKeptLine *line = [[[RSKeptLine alloc] init] autorelease];
    [line setKey:key];
    [line setVideo:video];
    [line setText:text];
    if ([[d objectForKey:@"title"] isKindOfClass:[NSString class]]) [line setTitle:[d objectForKey:@"title"]];
    if ([[d objectForKey:@"before"] isKindOfClass:[NSString class]]) [line setBefore:[d objectForKey:@"before"]];
    if ([[d objectForKey:@"meaning"] isKindOfClass:[NSString class]]) [line setMeaning:[d objectForKey:@"meaning"]];
    if ([[d objectForKey:@"kind"] isEqualToString:RSCardWord]) {
        [line setKind:RSCardWord];
        if ([[d objectForKey:@"word"] isKindOfClass:[NSString class]]) [line setWord:[d objectForKey:@"word"]];
        if ([[d objectForKey:@"lemma"] isKindOfClass:[NSString class]]) [line setLemma:[d objectForKey:@"lemma"]];
        if ([[d objectForKey:@"gloss"] isKindOfClass:[NSString class]]) [line setGloss:[d objectForKey:@"gloss"]];
        [line setRank:[[d objectForKey:@"rank"] unsignedIntegerValue]];
    }
    [line setStart:[[d objectForKey:@"start"] doubleValue]];
    [line setEnd:[[d objectForKey:@"end"] doubleValue]];
    [line setKept:[[d objectForKey:@"kept"] longValue]];
    [line setDue:[[d objectForKey:@"due"] longValue]];
    [line setStep:[[d objectForKey:@"step"] unsignedIntegerValue]];
    [line setLapses:[[d objectForKey:@"lapses"] unsignedIntegerValue]];
    [line setPutAway:[[d objectForKey:@"putAway"] boolValue]];
    [line setHeard:[[d objectForKey:@"heard"] longValue]];
    [line setKnewLast:[[d objectForKey:@"knewLast"] boolValue]];
    return line;
}

@end

@interface RSLines () {
    NSMutableArray *_lines;
    long _heardDay;
    NSUInteger _heardCount;
}
@property (nonatomic, readwrite, copy) NSString *folder;
@end

@implementation RSLines

- (id)initWithFolder:(NSString *)folder
{
    if (!(self = [super init])) return nil;
    _folder = [folder copy];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    _lines = [[NSMutableArray alloc] init];
    NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:[folder stringByAppendingPathComponent:RSLinesFile]];
    NSArray *lines = [state objectForKey:@"lines"];
    if ([lines isKindOfClass:[NSArray class]])
        for (NSDictionary *d in lines) {
            RSKeptLine *line = [RSKeptLine lineWithPlist:d];
            if (line) [_lines addObject:line];
        }
    _heardDay = [[state objectForKey:@"heardDay"] longValue];
    _heardCount = [[state objectForKey:@"heardCount"] unsignedIntegerValue];
    return self;
}

- (void)dealloc
{
    [_folder release];
    [_lines release];
    [super dealloc];
}

- (NSArray *)lines
{
    return [[_lines copy] autorelease];
}

- (BOOL)save
{
    NSMutableArray *lines = [NSMutableArray array];
    for (RSKeptLine *line in _lines) [lines addObject:[line plist]];
    NSDictionary *state = [NSDictionary dictionaryWithObjectsAndKeys:lines, @"lines",
        [NSNumber numberWithLong:_heardDay], @"heardDay", [NSNumber numberWithUnsignedInteger:_heardCount], @"heardCount", nil];
    return [state writeToFile:[_folder stringByAppendingPathComponent:RSLinesFile] atomically:YES];
}

// "JE4cI_Knzvc-0000250120": the video and the start in milliseconds, so a
// line is kept once and its file name is safe.
static NSString *RSLineKey(NSString *video, double start)
{
    return [NSString stringWithFormat:@"%@-%010ld", video, (long)llround(MAX(0, start) * 1000)];
}

- (BOOL)isKept:(NSString *)video start:(double)start
{
    NSString *key = RSLineKey(video, start);
    for (RSKeptLine *line in _lines)
        if ([[line key] isEqualToString:key]) return YES;
    return NO;
}

- (NSUInteger)keptOn:(long)today
{
    NSUInteger n = 0;
    for (RSKeptLine *line in _lines)
        if ([line kept] == today) n++;
    return n;
}

// The app's folder: Lines/ is inside it, and so is Sync In/, where the other
// Mac's day is read from (RSSyncManager.h).
- (NSString *)appFolder
{
    return [_folder stringByDeletingLastPathComponent];
}

// Why nothing more can be kept today, or nil. The other Mac's day counts: the
// dose is the owner's dose, whichever Mac they sit at.
- (NSString *)brakeOn:(long)today
{
    if ([self keptOn:today] + [RSSyncManager keptTodayOnOtherHosts:[self appFolder] today:today] >= RSKeepPerDay)
        return [NSString stringWithFormat:@"%lu kept today: that’s plenty. More tomorrow.", (unsigned long)RSKeepPerDay];
    if ([self waitingOn:today] >= RSWaitingBrake)
        return [NSString stringWithFormat:@"%lu cards are waiting to be heard again (⌘L). Those first.", (unsigned long)[self waitingOn:today]];
    return nil;
}

- (RSKeptLine *)keepText:(NSString *)text before:(NSString *)before video:(NSString *)video title:(NSString *)title
                   start:(double)start end:(double)end today:(long)today problem:(NSString **)problem
{
    NSString *why = nil;
    if ([text length] == 0 || [video length] == 0) why = @"There’s no line here to keep.";
    else if ([self isKept:video start:start]) why = @"This line is kept already.";
    else why = [self brakeOn:today];
    if (why) {
        if (problem) *problem = why;
        return nil;
    }
    RSKeptLine *line = [[[RSKeptLine alloc] init] autorelease];
    [line setKey:RSLineKey(video, start)];
    [line setVideo:video];
    [line setTitle:title];
    [line setText:text];
    [line setBefore:[before length] ? before : nil];
    [line setStart:start];
    [line setEnd:MAX(start, end)];
    [line setKept:today];
    [line setDue:today + RSLineGap(0)];
    [_lines addObject:line];
    return line;
}

static NSString *RSWordKey(NSString *video, double start, NSString *word)
{
    return [NSString stringWithFormat:@"%@-%@", RSLineKey(video, start), [word lowercaseString]];
}

- (BOOL)isKeptWord:(NSString *)word video:(NSString *)video start:(double)start
{
    NSString *key = RSWordKey(video, start, word);
    for (RSKeptLine *line in _lines)
        if ([[line key] isEqualToString:key]) return YES;
    return NO;
}

- (RSKeptLine *)keepWord:(NSString *)word lemma:(NSString *)lemma gloss:(NSString *)gloss rank:(NSUInteger)rank
                  inLine:(NSString *)text before:(NSString *)before video:(NSString *)video title:(NSString *)title
                   start:(double)start end:(double)end today:(long)today problem:(NSString **)problem
{
    NSString *why = nil;
    if ([word length] == 0 || [text length] == 0 || [video length] == 0) why = @"There’s no word here to keep.";
    else if ([self isKeptWord:word video:video start:start]) why = @"This word is kept already.";
    else why = [self brakeOn:today];
    if (why) {
        if (problem) *problem = why;
        return nil;
    }
    RSKeptLine *card = [[[RSKeptLine alloc] init] autorelease];
    [card setKey:RSWordKey(video, start, word)];
    [card setKind:RSCardWord];
    [card setWord:word];
    [card setLemma:lemma];
    [card setGloss:gloss];
    [card setRank:rank];
    [card setMeaning:[gloss length] ? gloss : nil];      // the gloss is its meaning, until the owner writes their own
    [card setVideo:video];
    [card setTitle:title];
    [card setText:text];
    [card setBefore:[before length] ? before : nil];
    [card setStart:start];
    [card setEnd:MAX(start, end)];
    [card setKept:today];
    [card setDue:today + RSLineGap(0)];
    [_lines addObject:card];
    return card;
}

- (NSUInteger)heardOn:(long)today
{
    return _heardDay == today ? _heardCount : 0;
}

- (NSArray *)dueOn:(long)today
{
    NSMutableArray *due = [NSMutableArray array];
    for (RSKeptLine *line in _lines)
        if (![line putAway] && [line due] <= today) [due addObject:line];
    // Oldest due first; among those, in the order kept (a stable sort).
    NSArray *sorted = [due sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(id a, id b) {
        long da = [(RSKeptLine *)a due], db = [(RSKeptLine *)b due];
        return da < db ? NSOrderedAscending : da > db ? NSOrderedDescending : NSOrderedSame;
    }];
    NSUInteger heard = [self heardOn:today] + [RSSyncManager heardTodayOnOtherHosts:[self appFolder] today:today];
    NSUInteger room = heard >= RSHearPerDay ? 0 : RSHearPerDay - heard;
    return [sorted count] > room ? [sorted subarrayWithRange:NSMakeRange(0, room)] : sorted;
}

- (NSUInteger)waitingOn:(long)today
{
    NSUInteger n = 0;
    for (RSKeptLine *line in _lines)
        if (![line putAway] && [line due] <= today) n++;
    return n;
}

- (BOOL)asksToSay:(RSKeptLine *)line
{
    return [[[line meaning] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0 &&
           [line step] % 2 == 1;
}

- (void)answer:(RSKeptLine *)line knew:(BOOL)knew today:(long)today
{
    if (line == nil || ![_lines containsObject:line]) return;
    if (_heardDay != today) { _heardDay = today; _heardCount = 0; }
    _heardCount++;
    [line setHeard:today];
    [line setKnewLast:knew];
    if (knew) {
        [line setStep:[line step] + 1];
        long gap = RSLineGap([line step]);
        if (gap == 0) [line setPutAway:YES];
        else [line setDue:today + gap];
    } else {
        [line setStep:0];
        [line setLapses:[line lapses] + 1];
        [line setDue:today + RSLineGap(0)];
        if ([line lapses] >= RSPutAwayAfter) [line setPutAway:YES];
    }
}

- (NSArray *)notYetOn:(long)today
{
    NSMutableArray *found = [NSMutableArray array];
    for (RSKeptLine *line in _lines)
        if ([line heard] == today && ![line knewLast] && ![line putAway]) [found addObject:line];
    return found;
}

- (void)putAway:(RSKeptLine *)line
{
    [line setPutAway:YES];
}

- (NSString *)soundPath:(RSKeptLine *)line
{
    NSString *key = [line isWord] ? RSLineKey([line video], [line start]) : [line key];
    return [_folder stringByAppendingPathComponent:[key stringByAppendingPathExtension:@"m4a"]];
}

- (NSArray *)linesFromVideo:(NSString *)video
{
    NSMutableArray *found = [NSMutableArray array];
    for (RSKeptLine *line in _lines)
        if ([[line video] isEqualToString:video]) [found addObject:line];
    return found;
}

@end
