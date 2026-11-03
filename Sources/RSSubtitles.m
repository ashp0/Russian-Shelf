#import "RSSubtitles.h"

static const double RSRevealAfterEnd = 3.0;    // seconds a finished line can still be asked for
static const double RSReplayGrace = 1.0;       // a line this new means "the one before"
static const NSUInteger RSLineMaxLength = 84;   // characters in a rebuilt automatic line
static const double RSPauseBreak = 2.0;         // seconds of silence that end a rebuilt line

@implementation RSLine

- (void)dealloc
{
    [_text release];
    [super dealloc];
}

@end

@interface RSSubtitles ()
@property (nonatomic, readwrite, copy) NSArray *lines;
@property (nonatomic, readwrite) BOOL automatic;
@end

double RSParseVTTTime(NSString *s)
{
    s = [s stringByReplacingOccurrencesOfString:@"," withString:@"."];
    NSArray *parts = [s componentsSeparatedByString:@":"];
    if ([parts count] < 2 || [parts count] > 3) return -1;
    double total = 0;
    for (NSUInteger i = 0; i < [parts count]; i++) {
        NSString *p = [parts objectAtIndex:i];
        BOOL last = i + 1 == [parts count];
        if ([p length] == 0) return -1;
        NSScanner *scanner = [NSScanner scannerWithString:p];
        double value = 0;
        if (last) {
            if (![scanner scanDouble:&value] || ![scanner isAtEnd] || value < 0 || value >= 60) return -1;
        } else {
            int whole = 0;
            if (![scanner scanInt:&whole] || ![scanner isAtEnd] || whole < 0 || (i > 0 && whole >= 60)) return -1;
            value = whole;
        }
        total = total * 60 + value;
    }
    return total;
}

// Text without tags (<c>, </c>, <i>, <00:00:01.234>, voice spans) or
// entities, with runs of white space as one space.
static NSString *RSCleanText(NSString *raw)
{
    NSMutableString *s = [NSMutableString stringWithCapacity:[raw length]];
    NSUInteger i = 0, n = [raw length];
    while (i < n) {
        unichar c = [raw characterAtIndex:i];
        if (c == '<') {
            NSRange close = [raw rangeOfString:@">" options:0 range:NSMakeRange(i, n - i)];
            if (close.location != NSNotFound) { i = NSMaxRange(close); continue; }
        }
        [s appendFormat:@"%C", c];
        i++;
    }
    NSDictionary *entities = [NSDictionary dictionaryWithObjectsAndKeys:
        @"<", @"&lt;", @">", @"&gt;", @"\"", @"&quot;", @"'", @"&#39;", @"'", @"&apos;",
        @" ", @"&nbsp;", @"", @"&lrm;", @"", @"&rlm;", nil];
    for (NSString *entity in entities)
        [s replaceOccurrencesOfString:entity withString:[entities objectForKey:entity] options:0 range:NSMakeRange(0, [s length])];
    [s replaceOccurrencesOfString:@"&amp;" withString:@"&" options:0 range:NSMakeRange(0, [s length])];
    NSArray *words = [s componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableArray *kept = [NSMutableArray array];
    for (NSString *w in words) if ([w length]) [kept addObject:w];
    return [kept componentsJoinedByString:@" "];
}

static BOOL RSHasWordTimings(NSString *raw)
{
    if ([raw rangeOfString:@"<c>"].location != NSNotFound || [raw rangeOfString:@"<c."].location != NSNotFound) return YES;
    NSRange open = [raw rangeOfString:@"<"];
    while (open.location != NSNotFound) {
        NSRange close = [raw rangeOfString:@">" options:0 range:NSMakeRange(open.location, [raw length] - open.location)];
        if (close.location == NSNotFound) break;
        NSString *inside = [raw substringWithRange:NSMakeRange(open.location + 1, close.location - open.location - 1)];
        if (RSParseVTTTime(inside) >= 0) return YES;
        open = [raw rangeOfString:@"<" options:0 range:NSMakeRange(NSMaxRange(close), [raw length] - NSMaxRange(close))];
    }
    return NO;
}

// One spoken word of the automatic captions, with when it starts and ends.
@interface RSWord : NSObject
@property (nonatomic) double start, end;
@property (nonatomic, copy) NSString *text;
@end

@implementation RSWord
- (void)dealloc
{
    [_text release];
    [super dealloc];
}
@end

// The words of one new line of a rolling cue: the text before the first
// timestamp starts with the cue, each <00:00:01.160> moves the clock on.
static void RSAppendWords(NSMutableArray *words, NSString *raw, double cueStart, double cueEnd)
{
    double clock = cueStart;
    NSUInteger i = 0, n = [raw length];
    while (i < n) {
        if ([raw characterAtIndex:i] == '<') {
            NSRange close = [raw rangeOfString:@">" options:0 range:NSMakeRange(i, n - i)];
            if (close.location == NSNotFound) break;
            double t = RSParseVTTTime([raw substringWithRange:NSMakeRange(i + 1, close.location - i - 1)]);
            if (t >= 0) clock = t;
            i = NSMaxRange(close);
            continue;
        }
        NSRange open = [raw rangeOfString:@"<" options:0 range:NSMakeRange(i, n - i)];
        NSUInteger stop = open.location == NSNotFound ? n : open.location;
        NSString *chunk = RSCleanText([raw substringWithRange:NSMakeRange(i, stop - i)]);
        for (NSString *token in [chunk componentsSeparatedByString:@" "]) {
            if ([token length] == 0) continue;
            RSWord *w = [[[RSWord alloc] init] autorelease];
            [w setStart:clock];
            [w setEnd:cueEnd];
            [w setText:token];
            [words addObject:w];
        }
        i = stop;
    }
}

static BOOL RSEndsSentence(NSString *word)
{
    NSString *w = [word stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"»\"')]”"]];
    return [w hasSuffix:@"."] || [w hasSuffix:@"!"] || [w hasSuffix:@"?"] || [w hasSuffix:@"…"];
}

static BOOL RSEndsClause(NSString *word)
{
    return [word hasSuffix:@","] || [word hasSuffix:@";"] || [word hasSuffix:@":"] || [word isEqualToString:@"—"];
}

static RSLine *RSMakeLine(double start, double end, NSString *text);

static void RSFlushWords(NSMutableArray *lines, NSArray *words)
{
    if ([words count] == 0) return;
    NSMutableArray *texts = [NSMutableArray array];
    for (RSWord *w in words) [texts addObject:[w text]];
    [lines addObject:RSMakeLine([(RSWord *)[words objectAtIndex:0] start], [(RSWord *)[words lastObject] end],
                                [texts componentsJoinedByString:@" "])];
}

// Speech-recognition words into lines a reader would make: a sentence each,
// broken after a comma when one runs long, and at a long pause.
static NSArray *RSLinesFromWords(NSArray *words)
{
    // A word lasts until the next begins, if that's sooner than its cue's end.
    for (NSUInteger i = 0; i + 1 < [words count]; i++) {
        RSWord *w = [words objectAtIndex:i], *next = [words objectAtIndex:i + 1];
        if ([next start] < [w end]) [w setEnd:MAX([w start], [next start])];
    }
    NSMutableArray *lines = [NSMutableArray array];
    NSMutableArray *current = [NSMutableArray array];
    NSUInteger length = 0;
    for (RSWord *w in words) {
        RSWord *last = [current lastObject];
        if (last && [w start] - [last end] > RSPauseBreak) {
            RSFlushWords(lines, current);
            [current removeAllObjects];
            length = 0;
        }
        if ([current count] && length + 1 + [[w text] length] > RSLineMaxLength) {
            // Too long: end at the last comma in its second half, else here.
            NSUInteger cut = [current count];
            for (NSUInteger k = [current count] - 1; k >= [current count] / 2 && k > 0; k--)
                if (RSEndsClause([(RSWord *)[current objectAtIndex:k] text])) { cut = k + 1; break; }
            NSArray *head = [current subarrayWithRange:NSMakeRange(0, cut)];
            NSArray *tail = [current subarrayWithRange:NSMakeRange(cut, [current count] - cut)];
            RSFlushWords(lines, head);
            [current setArray:tail];
            length = 0;
            for (RSWord *t in current) length += [[t text] length] + 1;
        }
        [current addObject:w];
        length += [[w text] length] + 1;
        if (RSEndsSentence([w text])) {
            RSFlushWords(lines, current);
            [current removeAllObjects];
            length = 0;
        }
    }
    RSFlushWords(lines, current);
    return lines;
}

static RSLine *RSMakeLine(double start, double end, NSString *text)
{
    RSLine *line = [[[RSLine alloc] init] autorelease];
    [line setStart:start];
    [line setEnd:MAX(end, start)];
    [line setText:text];
    return line;
}

@implementation RSSubtitles

- (void)dealloc
{
    [_lines release];
    [super dealloc];
}

+ (RSSubtitles *)subtitlesWithFile:(NSString *)path
{
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data == nil || [data length] > 8 * 1024 * 1024) return nil;
    NSString *text = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    return text ? [self subtitlesWithVTT:text] : nil;
}

+ (RSSubtitles *)subtitlesWithVTT:(NSString *)vtt
{
    if ([vtt hasPrefix:@"﻿"]) vtt = [vtt substringFromIndex:1];
    if (![vtt hasPrefix:@"WEBVTT"]) return nil;
    vtt = [[vtt stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
           stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];

    // Cues end at an empty line. Not at a line of spaces: the rolling
    // captions begin each cue with one.
    NSMutableArray *cues = [NSMutableArray array];     // [start, end, raw lines]
    BOOL rolling = NO;
    NSMutableArray *block = [NSMutableArray array];
    NSArray *all = [[vtt componentsSeparatedByString:@"\n"] arrayByAddingObject:@""];
    for (NSString *line in all) {
        if ([line length]) { [block addObject:line]; continue; }
        if ([block count] == 0) continue;
        NSUInteger timing = NSNotFound;
        for (NSUInteger i = 0; i < [block count]; i++)
            if ([[block objectAtIndex:i] rangeOfString:@"-->"].location != NSNotFound) { timing = i; break; }
        if (timing != NSNotFound && ![[block objectAtIndex:0] hasPrefix:@"NOTE"]) {
            NSString *t = [block objectAtIndex:timing];
            NSRange arrow = [t rangeOfString:@"-->"];
            NSString *from = [[t substringToIndex:arrow.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSString *rest = [[t substringFromIndex:NSMaxRange(arrow)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSString *to = [[rest componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] objectAtIndex:0];
            double start = RSParseVTTTime(from), end = RSParseVTTTime(to);
            if (start >= 0 && end >= 0) {
                NSArray *text = [block subarrayWithRange:NSMakeRange(timing + 1, [block count] - timing - 1)];
                for (NSString *raw in text) if (RSHasWordTimings(raw)) rolling = YES;
                [cues addObject:[NSArray arrayWithObjects:[NSNumber numberWithDouble:start],
                                 [NSNumber numberWithDouble:end], text, nil]];
            }
        }
        [block removeAllObjects];
    }

    NSMutableArray *lines = [NSMutableArray array];
    NSMutableArray *words = [NSMutableArray array];
    NSString *previous = nil;       // rolling: the last new line, to spot it carried over
    for (NSArray *cue in cues) {
        double start = [[cue objectAtIndex:0] doubleValue], end = [[cue objectAtIndex:1] doubleValue];
        NSMutableArray *raws = [NSMutableArray array], *texts = [NSMutableArray array];
        for (NSString *raw in [cue objectAtIndex:2]) {
            NSString *clean = RSCleanText(raw);
            if ([clean length] == 0) continue;
            [raws addObject:raw];
            [texts addObject:clean];
        }
        if ([texts count] == 0) continue;
        if (!rolling) {
            [lines addObject:RSMakeLine(start, end, [texts componentsJoinedByString:@"\n"])];
            continue;
        }
        // The top line is the one before, carried over; a cue holding only
        // that line is the flash between two.
        if (previous && [[texts objectAtIndex:0] isEqualToString:previous]) {
            [raws removeObjectAtIndex:0];
            [texts removeObjectAtIndex:0];
        }
        for (NSUInteger i = 0; i < [raws count]; i++) {
            RSAppendWords(words, [raws objectAtIndex:i], start, end);
            previous = [texts objectAtIndex:i];
        }
    }
    if (rolling) [lines setArray:RSLinesFromWords(words)];
    [lines sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(RSLine *a, RSLine *b) {
        return a.start < b.start ? NSOrderedAscending : a.start > b.start ? NSOrderedDescending : NSOrderedSame;
    }];

    RSSubtitles *subtitles = [[[RSSubtitles alloc] init] autorelease];
    [subtitles setLines:lines];
    [subtitles setAutomatic:rolling];
    return subtitles;
}

// The last line starting at or before t, or NSNotFound.
- (NSUInteger)lastStartedAtTime:(double)t
{
    NSUInteger lo = 0, hi = [_lines count];
    while (lo < hi) {
        NSUInteger mid = (lo + hi) / 2;
        if ([(RSLine *)[_lines objectAtIndex:mid] start] <= t) lo = mid + 1; else hi = mid;
    }
    return lo == 0 ? NSNotFound : lo - 1;
}

- (NSUInteger)indexAtTime:(double)t
{
    // Lines can overlap in hand-made files: the latest one that started and
    // hasn't ended.
    NSUInteger i = [self lastStartedAtTime:t];
    for (NSUInteger k = i; k != NSNotFound; k = k == 0 ? NSNotFound : k - 1) {
        RSLine *line = [_lines objectAtIndex:k];
        if (t < [line end]) return k;
        if (t - [line start] > 30) break;      // nothing earlier is still on screen
    }
    return NSNotFound;
}

- (NSUInteger)indexToRevealAtTime:(double)t
{
    NSUInteger i = [self indexAtTime:t];
    if (i != NSNotFound) return i;
    i = [self lastStartedAtTime:t];
    if (i == NSNotFound) return NSNotFound;
    return t - [(RSLine *)[_lines objectAtIndex:i] end] <= RSRevealAfterEnd ? i : NSNotFound;
}

- (NSUInteger)indexToReplayAtTime:(double)t
{
    NSUInteger i = [self indexAtTime:t];
    if (i == NSNotFound) i = [self lastStartedAtTime:t];
    if (i == NSNotFound) return [_lines count] ? 0 : NSNotFound;
    if (t - [(RSLine *)[_lines objectAtIndex:i] start] < RSReplayGrace && i > 0) i--;
    return i;
}

static BOOL RSOpensTurn(NSString *text)
{
    NSString *t = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([t length] == 0) return NO;
    unichar c = [t characterAtIndex:0];
    return c == '-' || c == 0x2013 || c == 0x2014;
}

- (NSArray *)sentencesFrom:(NSUInteger)first to:(NSUInteger)last
{
    NSMutableArray *units = [NSMutableArray array];
    NSUInteger i = first;
    while (i <= last && i < [_lines count]) {
        RSLine *a = [_lines objectAtIndex:i];
        RSLine *unit = [[[RSLine alloc] init] autorelease];
        [unit setStart:[a start]];
        [unit setEnd:[a end]];
        [unit setText:[a text]];
        if (i + 1 <= last && i + 1 < [_lines count] &&
            !RSEndsSentence([[a text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]])) {
            RSLine *b = [_lines objectAtIndex:i + 1];
            if ([b start] - [a end] < 1.0 && !RSOpensTurn([b text])) {
                [unit setEnd:MAX([a end], [b end])];
                [unit setText:[NSString stringWithFormat:@"%@ %@", [a text], [b text]]];
                i++;
            }
        }
        [units addObject:unit];
        i++;
    }
    return units;
}

- (NSUInteger)indexToHighlightAtTime:(double)t
{
    NSUInteger i = [self indexAtTime:t];
    return i != NSNotFound ? i : [self lastStartedAtTime:t];
}

@end
