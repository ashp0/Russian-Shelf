#import "RSReading.h"
#import "RSShelf.h"
#import "RSDate.h"

static NSString *const RSReadingHeader = @"Russian Reading 1";
static const NSUInteger RSReadingTitleMax = 300;

NSString *RSWithoutStress(NSString *text)
{
    return [text stringByReplacingOccurrencesOfString:@"́" withString:@""];
}

static NSString *RSTrim(NSString *s)
{
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

@implementation RSReadingItem

- (void)dealloc
{
    [_title release];
    [_lesson release];
    [_by release];
    [_metre release];
    [_wordsToLearn release];
    [_text release];
    [_key release];
    [super dealloc];
}

- (NSString *)plainText
{
    return RSWithoutStress(_text ?: @"");
}

- (NSArray *)sentences
{
    NSMutableArray *sentences = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    NSString *text = _text ?: @"";
    NSCharacterSet *closers = [NSCharacterSet characterSetWithCharactersInString:@"»\"”’)"];
    for (NSUInteger i = 0; i < [text length]; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == '\n') {
            if (_poem || (i + 1 < [text length] && [text characterAtIndex:i + 1] == '\n')) {
                // A line of verse, or a paragraph's end, ends a sentence.
                NSString *s = RSTrim(current);
                if ([s length]) [sentences addObject:s];
                [current setString:@""];
                continue;
            }
            [current appendString:@" "];
            continue;
        }
        [current appendFormat:@"%C", c];
        if (c == '.' || c == '!' || c == '?' || c == 0x2026) {
            // Closing quotes go with the sentence; "..." is one stop.
            NSUInteger j = i + 1;
            while (j < [text length] && ([closers characterIsMember:[text characterAtIndex:j]] || [text characterAtIndex:j] == c)) {
                [current appendFormat:@"%C", [text characterAtIndex:j]];
                j++;
            }
            i = j - 1;
            // "Но вдруг... экзамен!" and "«Что делать?» — подумал он." are one
            // sentence each: a stop followed by a small letter or a dash goes on.
            NSUInteger k = j;
            while (k < [text length] && [text characterAtIndex:k] == ' ') k++;
            if (k < [text length]) {
                unichar next = [text characterAtIndex:k];
                BOOL dash = next == '-' || next == 0x2013 || next == 0x2014;
                BOOL small = [[NSCharacterSet lowercaseLetterCharacterSet] characterIsMember:next];
                if (dash || small) continue;
            }
            NSString *s = RSTrim(current);
            if ([s length]) [sentences addObject:s];
            [current setString:@""];
        }
    }
    NSString *s = RSTrim(current);
    if ([s length]) [sentences addObject:s];
    return sentences;
}

@end

@interface RSReadingSet ()
@property (nonatomic, readwrite) long start;
@property (nonatomic, readwrite, copy) NSString *startText, *sealed, *fingerprint;
@property (nonatomic, readwrite, copy) NSArray *items;
@end

static BOOL RSHasControl(NSString *s)
{
    return [s rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound;
}

static BOOL RSIsSealedTime(NSString *s)
{
    if ([s length] != 19) return NO;
    int ok = 0;
    RSParseDay([[s substringToIndex:10] UTF8String], &ok);
    if (!ok || [s characterAtIndex:10] != ' ') return NO;
    int h, m, sec, used = 0;
    if (sscanf([[s substringFromIndex:11] UTF8String], "%2d:%2d:%2d%n", &h, &m, &sec, &used) != 3 || used != 8) return NO;
    return h >= 0 && h < 24 && m >= 0 && m < 60 && sec >= 0 && sec < 60;
}

// The text of a reading from its raw lines: a story's lines run together
// into paragraphs (blank lines between), a poem keeps every line.
static NSString *RSJoinText(NSArray *raw, BOOL poem)
{
    NSMutableArray *paragraphs = [NSMutableArray array];
    NSMutableArray *current = [NSMutableArray array];
    for (NSString *line in raw) {
        if ([line length] == 0) {
            if ([current count]) { [paragraphs addObject:[current componentsJoinedByString:poem ? @"\n" : @" "]]; [current removeAllObjects]; }
            continue;
        }
        [current addObject:line];
    }
    if ([current count]) [paragraphs addObject:[current componentsJoinedByString:poem ? @"\n" : @" "]];
    return [paragraphs componentsJoinedByString:@"\n\n"];
}

@implementation RSReadingSet

- (void)dealloc
{
    [_startText release];
    [_sealed release];
    [_items release];
    [_fingerprint release];
    [super dealloc];
}

BOOL RSTextIsReadingList(NSString *text)
{
    for (NSString *raw in [[text ?: @"" stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] componentsSeparatedByString:@"\n"]) {
        NSString *line = RSTrim(raw);
        if ([line length] == 0 || [line hasPrefix:@"#"]) continue;
        return [line isEqualToString:RSReadingHeader];
    }
    return NO;
}

+ (RSReadingSet *)setWithText:(NSString *)text problem:(NSString **)problem
{
    *problem = nil;
    NSArray *lines = [[text ?: @"" stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] componentsSeparatedByString:@"\n"];
    BOOL headerSeen = NO;
    NSString *startText = nil, *sealed = nil;
    long start = 0;
    NSMutableArray *items = [NSMutableArray array];
    RSReadingItem *item = nil;              // the reading being read
    NSMutableArray *raw = nil;              // its text lines so far
    NSUInteger stories = 0, number = 0;
    NSArray *keys = [NSArray arrayWithObjects:@"start", @"sealed", @"story", @"poem", @"new", @"metre", nil];

    for (NSUInteger i = 0; i < [lines count]; i++) {
        NSString *line = RSTrim([lines objectAtIndex:i]);
        NSUInteger lineNumber = i + 1;
        if ([line hasPrefix:@"#"]) continue;
        if (!headerSeen) {
            if ([line length] == 0) continue;
            if (![line isEqualToString:RSReadingHeader]) {
                *problem = [NSString stringWithFormat:@"Line %lu should say “%@”.", (unsigned long)lineNumber, RSReadingHeader];
                return nil;
            }
            headerSeen = YES;
            continue;
        }
        NSRange colon = [line rangeOfString:@":"];
        NSString *key = colon.location == NSNotFound ? @"" : RSTrim([line substringToIndex:colon.location]);
        NSString *value = colon.location == NSNotFound ? @"" : RSTrim([line substringFromIndex:NSMaxRange(colon)]);
        if (![keys containsObject:key]) {
            // A line of the reading's text (or a blank line between paragraphs).
            if (item == nil) {
                if ([line length] == 0) continue;
                *problem = [NSString stringWithFormat:@"Line %lu isn’t part of a reading list.", (unsigned long)lineNumber];
                return nil;
            }
            if (RSHasControl(line)) { *problem = [NSString stringWithFormat:@"Line %lu has control characters.", (unsigned long)lineNumber]; return nil; }
            [raw addObject:line];
            continue;
        }
        if ([key isEqualToString:@"start"]) {
            int ok = 0;
            long day = RSParseDay([value UTF8String], &ok);
            if (!ok || startText) {
                *problem = [NSString stringWithFormat:@"Line %lu: %@.", (unsigned long)lineNumber,
                            startText ? @"a second start date" : @"the start date should look like 2026-11-09"];
                return nil;
            }
            startText = value;
            start = day;
        } else if ([key isEqualToString:@"sealed"]) {
            if (!RSIsSealedTime(value) || sealed) {
                *problem = [NSString stringWithFormat:@"Line %lu: the sealed time should look like 2026-11-08 20:15:07.", (unsigned long)lineNumber];
                return nil;
            }
            sealed = value;
        } else if ([key isEqualToString:@"story"] || [key isEqualToString:@"poem"]) {
            if (item) [item setText:RSJoinText(raw, [item poem])];
            BOOL poem = [key isEqualToString:@"poem"];
            NSArray *parts = [value componentsSeparatedByString:@" | "];
            if ([parts count] < 3) {
                *problem = [NSString stringWithFormat:@"Line %lu: a %@ is “%@”.", (unsigned long)lineNumber, key,
                            poem ? @"title | by | lesson" : @"number | title | lesson"];
                return nil;
            }
            NSString *title, *lesson, *by = nil;
            if (poem) {
                title = RSTrim([parts objectAtIndex:0]);
                by = RSTrim([parts objectAtIndex:1]);
                lesson = RSTrim([[parts subarrayWithRange:NSMakeRange(2, [parts count] - 2)] componentsJoinedByString:@" | "]);
            } else {
                stories++;
                if ((NSUInteger)[RSTrim([parts objectAtIndex:0]) integerValue] != stories) {
                    *problem = [NSString stringWithFormat:@"Line %lu: the stories count 1, 2, 3…; this one should be %lu.", (unsigned long)lineNumber, (unsigned long)stories];
                    return nil;
                }
                title = RSTrim([parts objectAtIndex:1]);
                lesson = RSTrim([[parts subarrayWithRange:NSMakeRange(2, [parts count] - 2)] componentsJoinedByString:@" | "]);
            }
            if ([title length] == 0 || [lesson length] == 0 || [title length] > RSReadingTitleMax || [lesson length] > RSReadingTitleMax ||
                [by length] > RSReadingTitleMax || RSHasControl(title) || RSHasControl(lesson) || RSHasControl(by ?: @"")) {
                *problem = [NSString stringWithFormat:@"Line %lu: the title or lesson is empty or too long.", (unsigned long)lineNumber];
                return nil;
            }
            number++;
            if (number > RSReadingMaxItems) continue;        // counted, refused below
            item = [[[RSReadingItem alloc] init] autorelease];
            [item setNumber:number];
            [item setPoem:poem];
            [item setTitle:title];
            [item setLesson:lesson];
            [item setBy:[by length] ? by : nil];
            [items addObject:item];
            raw = [NSMutableArray array];
        } else if ([key isEqualToString:@"new"] || [key isEqualToString:@"metre"]) {
            if (item == nil) {
                *problem = [NSString stringWithFormat:@"Line %lu: %@ before any reading.", (unsigned long)lineNumber, key];
                return nil;
            }
            if (RSHasControl(value) || [value length] > 1000) { *problem = [NSString stringWithFormat:@"Line %lu is too long.", (unsigned long)lineNumber]; return nil; }
            if ([key isEqualToString:@"metre"]) [item setMetre:[value length] ? value : nil];
            else {
                NSMutableArray *words = [NSMutableArray array];
                for (NSString *w in [value componentsSeparatedByString:@","])
                    if ([RSTrim(w) length]) [words addObject:RSTrim(w)];
                [item setWordsToLearn:words];
            }
        }
    }
    if (item) [item setText:RSJoinText(raw, [item poem])];
    if (!headerSeen) { *problem = @"It’s empty."; return nil; }
    if (startText == nil) { *problem = @"It has no start date."; return nil; }
    if (number == 0) { *problem = @"It has no readings."; return nil; }
    if (number > RSReadingMaxItems) {
        *problem = [NSString stringWithFormat:@"It has %lu readings; a week holds at most %d.", (unsigned long)number, RSReadingMaxItems];
        return nil;
    }
    for (RSReadingItem *it in items) {
        if ([[it text] length] == 0) { *problem = [NSString stringWithFormat:@"“%@” has no text.", [it title]]; return nil; }
        if ([[it text] length] > RSReadingMaxTextLength) {
            *problem = [NSString stringWithFormat:@"“%@” is longer than %d characters.", [it title], RSReadingMaxTextLength];
            return nil;
        }
        [it setKey:[NSString stringWithFormat:@"%@-%lu", startText, (unsigned long)[it number]]];
    }
    RSReadingSet *set = [[[RSReadingSet alloc] init] autorelease];
    [set setStart:start];
    [set setStartText:startText];
    [set setSealed:sealed];
    [set setItems:items];
    return set;
}

- (NSString *)text
{
    NSMutableString *s = [NSMutableString stringWithFormat:@"%@\nstart: %@\n", RSReadingHeader, _startText];
    if (_sealed) [s appendFormat:@"sealed: %@\n", _sealed];
    NSUInteger story = 0;
    for (RSReadingItem *item in _items) {
        if ([item poem]) [s appendFormat:@"poem: %@ | %@ | %@\n", [item title], [item by] ?: @"", [item lesson]];
        else [s appendFormat:@"story: %lu | %@ | %@\n", (unsigned long)++story, [item title], [item lesson]];
        if ([item metre]) [s appendFormat:@"metre: %@\n", [item metre]];
        if ([[item wordsToLearn] count]) [s appendFormat:@"new: %@\n", [[item wordsToLearn] componentsJoinedByString:@", "]];
        [s appendFormat:@"%@\n", [item text]];
    }
    return s;
}

- (RSReadingSet *)setSealedAt:(NSString *)sealed
{
    RSReadingSet *copy = [[[RSReadingSet alloc] init] autorelease];
    [copy setStart:_start];
    [copy setStartText:_startText];
    [copy setSealed:sealed];
    [copy setItems:_items];
    return copy;
}

- (RSReadingItem *)itemWithKey:(NSString *)key
{
    for (RSReadingItem *item in _items)
        if ([[item key] isEqualToString:key]) return item;
    return nil;
}

- (RSReadingItem *)itemForDay:(long)day
{
    if ([_items count] == 0 || day < _start) return nil;
    long offset = day - _start;
    NSUInteger i = offset >= (long)[_items count] ? [_items count] - 1 : (NSUInteger)offset;
    return [_items objectAtIndex:i];
}

- (BOOL)isNewerThan:(RSReadingSet *)other
{
    if (other == nil) return YES;
    if (_start != [other start]) return _start > [other start];
    return [(_sealed ?: @"") compare:([other sealed] ?: @"")] == NSOrderedDescending;
}

@end

RSReadingSet *RSOpenSealedReadingSet(NSData *file, NSData *aesKey, NSData *publicKey, NSString **problem)
{
    NSString *fingerprint = nil;
    NSString *plain = RSOpenSealedText(file, aesKey, publicKey, &fingerprint, problem);
    if (plain == nil) return nil;
    if (!RSTextIsReadingList(plain)) { *problem = @"It’s sealed, but it isn’t a reading list."; return nil; }
    RSReadingSet *set = [RSReadingSet setWithText:plain problem:problem];
    if (set == nil) return nil;
    if ([set sealed] == nil) { *problem = @"It has no sealed time."; return nil; }
    [set setFingerprint:fingerprint];
    return set;
}

RSReadingSet *RSOpenReadingFile(NSData *file, NSString **problem)
{
    return RSOpenSealedReadingSet(file, RSAppAESKey(), RSAppPublicKey(), problem);
}
