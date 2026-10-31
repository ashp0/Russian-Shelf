#import "RSDictionary.h"
#include <sqlite3.h>

const NSUInteger RSRankCommon = 3000, RSRankLessCommon = 10000;

@implementation RSDictionaryEntry

- (void)dealloc
{
    [_bare release];
    [_accented release];
    [_type release];
    [_gloss release];
    [super dealloc];
}

static NSString *RSOrdinal(NSUInteger n)
{
    NSString *suffix = @"th";
    NSUInteger last = n % 10, two = n % 100;
    if (two < 11 || two > 13) suffix = last == 1 ? @"st" : last == 2 ? @"nd" : last == 3 ? @"rd" : @"th";
    // Thousands with a comma, by hand: NSNumberFormatter's styles are more than this needs.
    NSString *digits = [NSString stringWithFormat:@"%lu", (unsigned long)n];
    NSMutableString *s = [NSMutableString string];
    for (NSUInteger i = 0; i < [digits length]; i++) {
        if (i && ([digits length] - i) % 3 == 0) [s appendString:@","];
        [s appendString:[digits substringWithRange:NSMakeRange(i, 1)]];
    }
    return [s stringByAppendingString:suffix];
}

- (NSString *)rankText
{
    if (_rank == 0 || _rank > RSRankLessCommon)
        return [NSString stringWithFormat:@"rare: past the common %@", [RSOrdinal(RSRankLessCommon) substringToIndex:6]];
    if (_rank <= RSRankCommon) return [NSString stringWithFormat:@"common: %@", RSOrdinal(_rank)];
    return [NSString stringWithFormat:@"less common: %@", RSOrdinal(_rank)];
}

@end

@interface RSDictionary () {
    sqlite3 *_db;
    sqlite3_stmt *_byForm, *_byBare, *_count;
}
@end

@implementation RSDictionary

+ (RSDictionary *)bundled
{
    static RSDictionary *shared;
    static BOOL tried;
    if (!tried) {
        tried = YES;
        NSString *path = [[NSBundle mainBundle] pathForResource:@"dict" ofType:@"sqlite"];
        if (path) shared = [[RSDictionary alloc] initWithFile:path];
    }
    return shared;
}

- (id)initWithFile:(NSString *)path
{
    if (!(self = [super init])) return nil;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path] ||
        sqlite3_open_v2([path fileSystemRepresentation], &_db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
        [self release];
        return nil;
    }
    const char *byForm = "SELECT w.id, w.bare, w.accented, w.type, w.rank, w.gloss FROM forms f JOIN words w ON w.id = f.word_id "
                         "WHERE f.form = ?1 ORDER BY CASE WHEN w.rank IS NULL OR w.rank = 0 THEN 1 ELSE 0 END, w.rank LIMIT 1";
    const char *byBare = "SELECT id, bare, accented, type, rank, gloss FROM words WHERE bare = ?1 "
                         "ORDER BY CASE WHEN rank IS NULL OR rank = 0 THEN 1 ELSE 0 END, rank LIMIT 1";
    if (sqlite3_prepare_v2(_db, byForm, -1, &_byForm, NULL) != SQLITE_OK ||
        sqlite3_prepare_v2(_db, byBare, -1, &_byBare, NULL) != SQLITE_OK ||
        sqlite3_prepare_v2(_db, "SELECT COUNT(*) FROM words", -1, &_count, NULL) != SQLITE_OK) {
        [self release];
        return nil;
    }
    return self;
}

- (void)dealloc
{
    if (_byForm) sqlite3_finalize(_byForm);
    if (_byBare) sqlite3_finalize(_byBare);
    if (_count) sqlite3_finalize(_count);
    if (_db) sqlite3_close(_db);
    [super dealloc];
}

- (NSUInteger)wordCount
{
    NSUInteger n = 0;
    sqlite3_reset(_count);
    if (sqlite3_step(_count) == SQLITE_ROW) n = (NSUInteger)sqlite3_column_int64(_count, 0);
    sqlite3_reset(_count);
    return n;
}

static NSString *RSColumn(sqlite3_stmt *s, int i)
{
    const unsigned char *text = sqlite3_column_text(s, i);
    return text ? [NSString stringWithUTF8String:(const char *)text] : @"";
}

- (RSDictionaryEntry *)entryFrom:(sqlite3_stmt *)statement key:(NSString *)key
{
    sqlite3_reset(statement);
    sqlite3_bind_text(statement, 1, [key UTF8String], -1, SQLITE_TRANSIENT);
    RSDictionaryEntry *entry = nil;
    if (sqlite3_step(statement) == SQLITE_ROW) {
        entry = [[[RSDictionaryEntry alloc] init] autorelease];
        [entry setBare:RSColumn(statement, 1)];
        [entry setAccented:RSStressMarked(RSColumn(statement, 2))];
        [entry setType:RSColumn(statement, 3)];
        [entry setRank:(NSUInteger)sqlite3_column_int64(statement, 4)];
        [entry setGloss:RSColumn(statement, 5)];
    }
    sqlite3_reset(statement);
    return entry;
}

// The letters of a word, lowercase, with ё as written: the dictionary's forms
// are stored with ё, and tried with е as well.
static NSString *RSBareForm(NSString *word)
{
    NSMutableString *s = [NSMutableString string];
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    NSString *lower = [word lowercaseString];
    for (NSUInteger i = 0; i < [lower length]; i++) {
        unichar c = [lower characterAtIndex:i];
        if ([letters characterIsMember:c] || (c == '-' && [s length] && i + 1 < [lower length])) [s appendFormat:@"%C", c];
    }
    while ([s hasSuffix:@"-"]) [s deleteCharactersInRange:NSMakeRange([s length] - 1, 1)];
    return s;
}

- (RSDictionaryEntry *)lookup:(NSString *)word
{
    NSString *bare = RSBareForm(word ?: @"");
    if ([bare length] == 0) return nil;
    NSString *withYe = [bare stringByReplacingOccurrencesOfString:@"ё" withString:@"е"];
    NSArray *tries = [NSArray arrayWithObjects:bare, withYe, nil];
    for (NSString *key in tries) {
        RSDictionaryEntry *e = [self entryFrom:_byForm key:key];
        if (e) return e;
    }
    for (NSString *key in tries) {
        RSDictionaryEntry *e = [self entryFrom:_byBare key:key];
        if (e) return e;
    }
    return nil;
}

@end

NSArray *RSWordsInLine(NSString *line)
{
    NSMutableArray *words = [NSMutableArray array];
    NSCharacterSet *cyrillic = [NSCharacterSet characterSetWithRange:NSMakeRange(0x0400, 0x0100)];
    NSMutableString *current = [NSMutableString string];
    for (NSUInteger i = 0; i <= [line length]; i++) {
        unichar c = i < [line length] ? [line characterAtIndex:i] : 0;
        BOOL letter = [cyrillic characterIsMember:c] || c == 0x0301;
        BOOL hyphen = c == '-' && [current length] && i + 1 < [line length] && [cyrillic characterIsMember:[line characterAtIndex:i + 1]];
        if (letter || hyphen) [current appendFormat:@"%C", c];
        else if ([current length]) { [words addObject:[[current copy] autorelease]]; [current setString:@""]; }
    }
    return words;
}

NSString *RSStressMarked(NSString *accented)
{
    // OpenRussian writes the stress as an apostrophe after the vowel; print it
    // as the combining acute accent, as dictionaries do.
    return [accented stringByReplacingOccurrencesOfString:@"'" withString:@"́"];
}
