#import "RSSay.h"
#import "RSDate.h"
#import "RSReport.h"

NSString *const RSSayFolderName = @"Say";
const NSUInteger RSSaySettings = 3;

static NSString *const RSIslandsFile = @"Islands.txt", *const RSTutorFile = @"Tutor.txt";
static NSString *const RSTodayFolder = @"Today", *const RSRecordingsFolder = @"Recordings";

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
    [fm createDirectoryAtPath:[folder stringByAppendingPathComponent:RSTodayFolder] withIntermediateDirectories:YES attributes:nil error:NULL];
    [fm createDirectoryAtPath:[folder stringByAppendingPathComponent:RSRecordingsFolder] withIntermediateDirectories:YES attributes:nil error:NULL];
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

// ---- Today's passes ---------------------------------------------------------------

- (NSString *)passPath:(NSUInteger)pass
{
    return [[_folder stringByAppendingPathComponent:RSTodayFolder] stringByAppendingPathComponent:
            [NSString stringWithFormat:@"pass-%lu.m4a", (unsigned long)pass]];
}

- (BOOL)hasPass:(NSUInteger)pass
{
    return [[NSFileManager defaultManager] fileExistsAtPath:[self passPath:pass]];
}

- (void)clearPassesNotFrom:(long)day
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *today = [_folder stringByAppendingPathComponent:RSTodayFolder];
    for (NSString *name in [fm contentsOfDirectoryAtPath:today error:NULL]) {
        NSString *path = [today stringByAppendingPathComponent:name];
        NSDate *made = [[fm attributesOfItemAtPath:path error:NULL] fileModificationDate];
        if (made == nil) continue;
        time_t t = (time_t)[made timeIntervalSince1970];
        struct tm tm;
        localtime_r(&t, &tm);
        if (RSDaysFromCivil(tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday) != day) [fm removeItemAtPath:path error:NULL];
    }
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
