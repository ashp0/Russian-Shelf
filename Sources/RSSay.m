#import "RSSay.h"
#import "RSDate.h"
#import "RSReport.h"
#import "RSClip.h"

NSString *const RSSayFolderName = @"Say";
const NSUInteger RSSaySettings = 3;

static NSString *const RSIslandsFile = @"Islands.txt", *const RSTutorFile = @"Tutor.txt";
static NSString *const RSTodayFolder = @"Today", *const RSRecordingsFolder = @"Recordings", *const RSLabelsFile = @"labels.txt";

@implementation RSRecording

- (void)dealloc
{
    [_path release];
    [_name release];
    [_label release];
    [super dealloc];
}

@end

// Eight islands to begin with, for a Waterloo student: topics they'll be
// asked about, so worth being fluent in (Shekhtman's islands).
static NSString *const RSSeedIslands =
    @"Мой день\nУниверситет и учёба\nМоя семья\nНепал\nЧто я смотрел на этой неделе\nЕда\nПланы на выходные\nПочему я учу русский\n";

NSArray *RSSayLengths(NSUInteger setting)
{
    switch (setting) {
        case 1:  return [NSArray arrayWithObjects:[NSNumber numberWithInt:180], [NSNumber numberWithInt:120], [NSNumber numberWithInt:90], nil];
        case 2:  return [NSArray arrayWithObjects:[NSNumber numberWithInt:240], [NSNumber numberWithInt:180], [NSNumber numberWithInt:120], nil];
        default: return [NSArray arrayWithObjects:[NSNumber numberWithInt:120], [NSNumber numberWithInt:90], [NSNumber numberWithInt:60], nil];
    }
}

NSString *RSSayLengthsText(NSUInteger setting)
{
    switch (setting) {
        case 1:  return @"3·2·1½";
        case 2:  return @"4·3·2";
        default: return @"2·1½·1";
    }
}

NSString *RSMonthText(long day)
{
    int y, m, d;
    RSCivilFromDays(day, &y, &m, &d);
    return [NSString stringWithFormat:@"%04d-%02d", y, m];
}

@interface RSSay ()
@property (nonatomic, readwrite, copy) NSString *folder;
@end

@implementation RSSay

- (id)initWithFolder:(NSString *)folder
{
    if (!(self = [super init])) return nil;
    _folder = [folder copy];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:[folder stringByAppendingPathComponent:RSRecordingsFolder] withIntermediateDirectories:YES attributes:nil error:NULL];
    // Before 2026-11-02 the day's passes lived in Today/ and went at
    // midnight; now every day keeps its own folder. Whatever is still in
    // Today/ moves to the day it was made.
    NSString *today = [folder stringByAppendingPathComponent:RSTodayFolder];
    for (NSString *name in [fm contentsOfDirectoryAtPath:today error:NULL]) {
        NSString *path = [today stringByAppendingPathComponent:name];
        NSDate *made = [[fm attributesOfItemAtPath:path error:NULL] fileModificationDate];
        if (made == nil || ![[name pathExtension] isEqualToString:@"m4a"]) continue;
        time_t t = (time_t)[made timeIntervalSince1970];
        struct tm tm;
        localtime_r(&t, &tm);
        NSString *to = [[self folderForDay:RSDaysFromCivil(tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday)] stringByAppendingPathComponent:name];
        if (![fm fileExistsAtPath:to]) [fm moveItemAtPath:path toPath:to error:NULL];
    }
    if ([[fm contentsOfDirectoryAtPath:today error:NULL] count] == 0) [fm removeItemAtPath:today error:NULL];
    NSString *islands = [folder stringByAppendingPathComponent:RSIslandsFile];
    if (![fm fileExistsAtPath:islands]) [RSSeedIslands writeToFile:islands atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    return self;
}

- (void)dealloc
{
    [_folder release];
    [super dealloc];
}

// ---- Islands ------------------------------------------------------------------

- (NSArray *)islands
{
    NSString *text = [NSString stringWithContentsOfFile:[_folder stringByAppendingPathComponent:RSIslandsFile]
                                               encoding:NSUTF8StringEncoding error:NULL];
    NSMutableArray *islands = [NSMutableArray array];
    for (NSString *raw in [[text ?: @"" stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] componentsSeparatedByString:@"\n"]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([line length] && ![line hasPrefix:@"#"]) [islands addObject:line];
    }
    return islands;
}

- (BOOL)saveIslands:(NSArray *)islands
{
    NSMutableString *text = [NSMutableString string];
    for (NSString *raw in islands) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([line length]) [text appendFormat:@"%@\n", line];
    }
    return [text writeToFile:[_folder stringByAppendingPathComponent:RSIslandsFile] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (NSString *)islandForDay:(long)day
{
    NSArray *islands = [self islands];
    if ([islands count] == 0) return nil;
    return [islands objectAtIndex:(NSUInteger)(((day % (long)[islands count]) + (long)[islands count]) % (long)[islands count])];
}

// ---- The day's recordings ---------------------------------------------------------

- (NSString *)folderForDay:(long)day
{
    NSString *folder = [[_folder stringByAppendingPathComponent:RSRecordingsFolder] stringByAppendingPathComponent:RSDayNumberText(day)];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    return folder;
}

- (NSString *)passPath:(NSUInteger)pass forDay:(long)day
{
    return [[self folderForDay:day] stringByAppendingPathComponent:[NSString stringWithFormat:@"pass-%lu.m4a", (unsigned long)pass]];
}

- (BOOL)hasPass:(NSUInteger)pass forDay:(long)day
{
    return [[NSFileManager defaultManager] fileExistsAtPath:[self passPath:pass forDay:day]];
}

- (NSString *)readPath:(NSUInteger)read forReading:(NSString *)key day:(long)day
{
    return [[self folderForDay:day] stringByAppendingPathComponent:[NSString stringWithFormat:@"read-%@-%lu.m4a", key, (unsigned long)read]];
}

- (NSString *)newFreeRecordingPathForDay:(long)day
{
    NSString *folder = [self folderForDay:day];
    for (NSUInteger n = 1; ; n++) {
        NSString *path = [folder stringByAppendingPathComponent:[NSString stringWithFormat:@"free-%lu.m4a", (unsigned long)n]];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return path;
    }
}

// labels.txt beside a recording: "<file> | <label>", a line each.
- (NSDictionary *)labelsIn:(NSString *)folder
{
    NSString *text = [NSString stringWithContentsOfFile:[folder stringByAppendingPathComponent:RSLabelsFile] encoding:NSUTF8StringEncoding error:NULL];
    NSMutableDictionary *labels = [NSMutableDictionary dictionary];
    for (NSString *line in [text ?: @"" componentsSeparatedByString:@"\n"]) {
        NSRange bar = [line rangeOfString:@" | "];
        if (bar.location == NSNotFound) continue;
        NSString *name = [[line substringToIndex:bar.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *label = [[line substringFromIndex:NSMaxRange(bar)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([name length] && [label length]) [labels setObject:label forKey:name];
    }
    return labels;
}

- (void)labelRecording:(NSString *)path as:(NSString *)label
{
    NSString *folder = [path stringByDeletingLastPathComponent], *name = [path lastPathComponent];
    NSString *one = [[[label componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "]
                     stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableDictionary *labels = [NSMutableDictionary dictionaryWithDictionary:[self labelsIn:folder]];
    if ([one length]) [labels setObject:one forKey:name]; else [labels removeObjectForKey:name];
    NSMutableString *text = [NSMutableString string];
    for (NSString *n in [[labels allKeys] sortedArrayUsingSelector:@selector(compare:)]) [text appendFormat:@"%@ | %@\n", n, [labels objectForKey:n]];
    [text writeToFile:[folder stringByAppendingPathComponent:RSLabelsFile] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (NSString *)labelForRecording:(NSString *)path
{
    return [[self labelsIn:[path stringByDeletingLastPathComponent]] objectForKey:[path lastPathComponent]];
}

- (NSArray *)recordings
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *recordings = [_folder stringByAppendingPathComponent:RSRecordingsFolder];
    NSMutableArray *found = [NSMutableArray array];
    NSArray *days = [[fm contentsOfDirectoryAtPath:recordings error:NULL] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *dayName in [days reverseObjectEnumerator]) {
        int ok = 0;
        long day = RSParseDay([dayName UTF8String], &ok);
        if (!ok) continue;
        NSString *folder = [recordings stringByAppendingPathComponent:dayName];
        NSDictionary *labels = [self labelsIn:folder];
        NSMutableArray *files = [NSMutableArray array];
        for (NSString *name in [fm contentsOfDirectoryAtPath:folder error:NULL])
            if ([[name pathExtension] isEqualToString:@"m4a"]) [files addObject:name];
        // In the order made.
        [files sortUsingComparator:^NSComparisonResult(id a, id b) {
            NSDate *da = [[fm attributesOfItemAtPath:[folder stringByAppendingPathComponent:a] error:NULL] fileModificationDate];
            NSDate *db = [[fm attributesOfItemAtPath:[folder stringByAppendingPathComponent:b] error:NULL] fileModificationDate];
            NSComparisonResult c = [da compare:db];
            return c != NSOrderedSame ? c : [a compare:b];
        }];
        for (NSString *name in files) {
            RSRecording *r = [[[RSRecording alloc] init] autorelease];
            [r setPath:[folder stringByAppendingPathComponent:name]];
            [r setName:name];
            [r setLabel:[labels objectForKey:name]];
            [r setDay:day];
            [found addObject:r];
        }
    }
    return found;
}

// ---- The month's recording ------------------------------------------------------------

- (NSString *)monthRecordingPathForDay:(long)day
{
    return [[_folder stringByAppendingPathComponent:RSRecordingsFolder] stringByAppendingPathComponent:
            [RSMonthText(day) stringByAppendingPathExtension:@"m4a"]];
}

- (BOOL)hasMonthRecordingForDay:(long)day
{
    return [[NSFileManager defaultManager] fileExistsAtPath:[self monthRecordingPathForDay:day]];
}

- (BOOL)keepMonthRecording:(NSString *)path forDay:(long)day
{
    if ([self hasMonthRecordingForDay:day] || ![[NSFileManager defaultManager] fileExistsAtPath:path]) return NO;
    return [[NSFileManager defaultManager] copyItemAtPath:path toPath:[self monthRecordingPathForDay:day] error:NULL];
}

- (NSString *)previousMonthRecordingBeforeDay:(long)day month:(NSString **)month
{
    NSString *thisMonth = RSMonthText(day), *best = nil;
    NSString *recordings = [_folder stringByAppendingPathComponent:RSRecordingsFolder];
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:recordings error:NULL]) {
        if (![[name pathExtension] isEqualToString:@"m4a"] || [name length] != 11) continue;
        NSString *m = [name stringByDeletingPathExtension];
        if ([m compare:thisMonth] != NSOrderedAscending) continue;
        if (best == nil || [m compare:best] == NSOrderedDescending) best = m;
    }
    if (month) *month = best;
    return best ? [recordings stringByAppendingPathComponent:[best stringByAppendingPathExtension:@"m4a"]] : nil;
}

// ---- For the tutor --------------------------------------------------------------------

- (NSString *)tutorNotes
{
    return [NSString stringWithContentsOfFile:[_folder stringByAppendingPathComponent:RSTutorFile] encoding:NSUTF8StringEncoding error:NULL] ?: @"";
}

- (BOOL)addTutorNote:(NSString *)note day:(long)day
{
    NSString *line = [[note componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
    line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([line length] == 0) return NO;
    NSMutableString *text = [[[self tutorNotes] mutableCopy] autorelease];
    NSString *heading = [NSString stringWithFormat:@"## %@", RSDayNumberText(day)];
    if ([text length] && ![text hasSuffix:@"\n"]) [text appendString:@"\n"];
    // Under today's heading if it's the last one; else a new heading.
    NSRange last = [text rangeOfString:@"## " options:NSBackwardsSearch];
    NSString *lastHeading = nil;
    if (last.location != NSNotFound) {
        NSRange eol = [text rangeOfString:@"\n" options:0 range:NSMakeRange(last.location, [text length] - last.location)];
        lastHeading = [text substringWithRange:NSMakeRange(last.location, (eol.location == NSNotFound ? [text length] : eol.location) - last.location)];
    }
    if (![lastHeading isEqualToString:heading]) [text appendFormat:@"%@%@\n", [text length] ? @"\n" : @"", heading];
    [text appendFormat:@"%@\n", line];
    return [text writeToFile:[_folder stringByAppendingPathComponent:RSTutorFile] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (NSArray *)tutorNotesForDay:(long)day
{
    NSString *heading = [NSString stringWithFormat:@"## %@", RSDayNumberText(day)];
    NSMutableArray *notes = [NSMutableArray array];
    BOOL inDay = NO;
    for (NSString *raw in [[self tutorNotes] componentsSeparatedByString:@"\n"]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([line hasPrefix:@"## "]) { inDay = [line isEqualToString:heading]; continue; }
        if (inDay && [line length]) [notes addObject:line];
    }
    return notes;
}

@end
