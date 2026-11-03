#import "RSReport.h"
#import "RSLibrary.h"
#import "RSShelf.h"
#import "RSLines.h"
#import "RSClips.h"
#import "RSDate.h"
#include <unistd.h>
#include <CoreServices/CoreServices.h>

static NSString *RSLocalTime(time_t t, const char *format)
{
    struct tm tm;
    char buffer[64];
    localtime_r(&t, &tm);
    strftime(buffer, sizeof buffer, format, &tm);
    return [NSString stringWithUTF8String:buffer];
}

NSString *RSClock(double seconds)
{
    long s = seconds > 0 ? (long)(seconds + 0.5) : 0;
    if (s >= 3600) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", s / 3600, (s / 60) % 60, s % 60];
    return [NSString stringWithFormat:@"%ld:%02ld", s / 60, s % 60];
}

NSString *RSReportName(RSShelf *shelf, time_t now)
{
    return [NSString stringWithFormat:@"shelf-%@_%@.txt", [shelf startText], RSLocalTime(now, "%Y-%m-%d-%H%M")];
}

// The name in Sharing. Not NSHost (it can wait on the network, and a report is
// written on the main thread, often offline), and not gethostname alone (it
// can follow the network: a campus DHCP name one day, the Mac's own the next).
NSString *RSComputerName(void)
{
    NSString *name = [(NSString *)CSCopyMachineName() autorelease];
    if ([name length] == 0) {
        char buffer[256] = { 0 };
        name = gethostname(buffer, sizeof buffer - 1) == 0 ? [NSString stringWithUTF8String:buffer] : nil;
        if ([name hasSuffix:@".local"]) name = [name substringToIndex:[name length] - 6];
    }
    name = [[name componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
    return [name length] ? name : @"this Mac";
}

const NSUInteger RSReportLinesPerVideo = 40;

// "2026-11-03", from a day number.
NSString *RSDayNumberText(long day)
{
    int y, m, d;
    RSCivilFromDays(day, &y, &m, &d);
    return [NSString stringWithFormat:@"%04d-%02d-%02d", y, m, d];
}

BOOL RSIsReadingKey(NSString *key)
{
    // "2026-11-09-3": a day, a hyphen, a number.
    if ([key length] < 12 || [key length] > 14 || [key characterAtIndex:10] != '-') return NO;
    int ok = 0;
    RSParseDay([[key substringToIndex:10] UTF8String], &ok);
    if (!ok) return NO;
    for (NSUInteger i = 11; i < [key length]; i++)
        if ([key characterAtIndex:i] < '0' || [key characterAtIndex:i] > '9') return NO;
    return YES;
}

static NSString *RSOneLine(NSString *text)
{
    return [[text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" / "];
}

NSString *RSReportText(RSShelf *shelf, RSLibrary *library, RSLines *lines, time_t now)
{
    return RSReportTextWithNotes(shelf, library, lines, nil, now);
}

NSString *RSReportTextWithNotes(RSShelf *shelf, RSLibrary *library, RSLines *lines, NSString *tutor, time_t now)
{
    NSMutableString *s = [NSMutableString stringWithString:@"Russian Shelf report\n"];
    [s appendFormat:@"shelf: %@ (sealed %@)\n", [shelf startText], [shelf sealed]];
    [s appendFormat:@"written: %@\n", RSLocalTime(now, "%Y-%m-%d %H:%M")];
    [s appendFormat:@"from: %@\n\n", RSComputerName()];
    for (RSVideo *video in [shelf videos]) {
        NSString *identifier = [video identifier];
        RSWatch *watch = [library watchFor:identifier];
        NSString *state, *amount;
        if (![library isDownloaded:identifier] && ![watch finished] && [watch furthest] <= 0) {
            state = @"not downloaded";
            amount = @"-";
        } else {
            state = [watch finished] ? @"finished" : [watch furthest] >= 1 ? @"partly" : @"not started";
            amount = [NSString stringWithFormat:@"%@ of %@", RSClock([watch finished] ? [watch duration] : [watch furthest]),
                      RSClock([watch duration])];
        }
        [s appendFormat:@"%@ | %@ | %@ | %@\n", identifier, state, amount, [video title]];
    }
    // The order the Help columns come in.
    static const RSHelp order[] = { RSHelpShown, RSHelpHeardAgain, RSHelpLooped, RSHelpSlowed, RSHelpTranscript,
                                    RSHelpSubtitles, RSHelpLookedUp, RSHelpKept };
    const size_t kinds = sizeof order / sizeof order[0];
    NSMutableString *help = [NSMutableString string], *felt = [NSMutableString string],
                    *asked = [NSMutableString string], *kept = [NSMutableString string], *words = [NSMutableString string];
    for (RSVideo *video in [shelf videos]) {
        NSString *identifier = [video identifier];
        NSMutableString *row = [NSMutableString stringWithString:identifier];
        NSUInteger any = 0;
        for (size_t k = 0; k < kinds; k++) {
            NSUInteger n = [library help:order[k] for:identifier];
            any += n;
            [row appendFormat:@" | %@ %lu", RSHelpName(order[k]), (unsigned long)n];
        }
        // The slowest speed ever chosen for it, when it was slowed at all.
        float slowest = [library slowestFor:identifier];
        if (slowest < 1) { [row appendFormat:@" | slowest %.1f", slowest]; any++; }
        if (any) [help appendFormat:@"%@\n", row];

        NSString *f = [library feltFor:identifier], *w = [library wantFor:identifier];
        if (f || w) [felt appendFormat:@"%@ | %@ | %@\n", identifier, f ?: @"-", w ?: @"-"];

        NSArray *helped = [library helpedLinesFor:identifier];
        NSUInteger shownLines = 0;
        for (NSDictionary *line in helped) {
            if (shownLines++ == RSReportLinesPerVideo) {
                [asked appendFormat:@"%@ | … and %lu more lines\n", identifier, (unsigned long)([helped count] - RSReportLinesPerVideo)];
                break;
            }
            NSMutableArray *what = [NSMutableArray array];
            for (size_t k = 0; k < kinds; k++) {
                NSNumber *n = [line objectForKey:RSHelpName(order[k])];
                if (n) [what addObject:[NSString stringWithFormat:@"%@ %@", RSHelpName(order[k]), n]];
            }
            [asked appendFormat:@"%@ | %@ | %@ | %@\n", identifier, RSClock([[line objectForKey:@"start"] doubleValue]),
             [what componentsJoinedByString:@", "], RSOneLine([line objectForKey:@"text"])];
        }

        for (RSKeptLine *line in [lines linesFromVideo:identifier]) {
            if ([line isWord]) {
                [words appendFormat:@"%@ | %@ | %@ (%@) | %@ | in: %@\n", identifier, RSClock([line start]), [line word],
                 [line lemma] ?: @"", RSOneLine([line gloss] ?: @""), RSOneLine([line text])];
                continue;
            }
            [kept appendFormat:@"%@ | %@ | %@", identifier, RSClock([line start]), RSOneLine([line text])];
            if ([[line meaning] length]) [kept appendFormat:@" | means: %@", RSOneLine([line meaning])];
            [kept appendString:@"\n"];
        }
    }
    if ([help length])
        [s appendFormat:@"\nHelp (shown, heard again, looped, slowed, transcript, subtitles, looked up, kept):\n%@", help];
    if ([felt length]) [s appendFormat:@"\nHow it felt (the owner's own choice, about the video):\n%@", felt];
    if ([asked length]) [s appendFormat:@"\nLines help was asked on:\n%@", asked];
    NSMutableString *clips = [NSMutableString string];
    for (RSVideo *video in [shelf videos])
        for (NSDictionary *c in [library clipsFor:[video identifier]])
            [clips appendFormat:@"%@ | %@ | passes %@ | day %@\n", [video identifier],
             RSClipSpan([[c objectForKey:@"start"] doubleValue], [[c objectForKey:@"end"] doubleValue]), [c objectForKey:@"passes"],
             RSDayNumberText([[c objectForKey:@"day"] longValue])];
    if ([clips length]) [s appendFormat:@"\nClips worked (stretch | passes of 3 | day):\n%@", clips];
    if ([kept length]) [s appendFormat:@"\nKept:\n%@", kept];
    if ([words length]) [s appendFormat:@"\nWords kept (word (lemma) | gloss | the line):\n%@", words];
    NSMutableString *say = [NSMutableString string];
    for (NSNumber *day in [library sayDays]) {
        if ([day longValue] < [shelf start]) continue;
        NSDictionary *d = [library sayOnDay:[day longValue]];
        if ([[d objectForKey:@"island"] length])
            [say appendFormat:@"%@ | %@ | passes %@ | %@\n", RSDayNumberText([day longValue]), [d objectForKey:@"island"],
             [d objectForKey:@"passes"], [[d objectForKey:@"recorded"] boolValue] ? @"recorded" : @"not recorded"];
        // Rounds the owner added on their own, whenever they liked.
        NSArray *more = [[d objectForKey:@"more"] isKindOfClass:[NSArray class]] ? [d objectForKey:@"more"] : nil;
        for (NSUInteger i = 0; i < [more count]; i++) {
            NSDictionary *m = [more objectAtIndex:i];
            if (![m isKindOfClass:[NSDictionary class]] || ![[m objectForKey:@"island"] length]) continue;
            [say appendFormat:@"%@ | %@ | passes %@ | %@ | round %lu\n", RSDayNumberText([day longValue]), [m objectForKey:@"island"],
             [m objectForKey:@"passes"], [[m objectForKey:@"recorded"] boolValue] ? @"recorded" : @"not recorded", (unsigned long)i + 2];
        }
    }
    if ([say length]) [s appendFormat:@"\nSaid (day | topic | passes of 3 | recorded):\n%@", say];
    // The week's readings: those read since the shelf began.
    NSMutableString *read = [NSMutableString string];
    for (NSString *key in [library readingKeys]) {
        NSDictionary *p = [library readingProgressFor:key];
        if ([[p objectForKey:@"day"] longValue] < [shelf start]) continue;
        NSMutableArray *times = [NSMutableArray array];
        for (NSNumber *t in [[p objectForKey:@"times"] isKindOfClass:[NSArray class]] ? [p objectForKey:@"times"] : [NSArray array])
            [times addObject:RSClock([t doubleValue])];
        BOOL recorded = NO;
        for (NSNumber *r in [[p objectForKey:@"recorded"] isKindOfClass:[NSArray class]] ? [p objectForKey:@"recorded"] : [NSArray array])
            recorded |= [r boolValue];
        [read appendFormat:@"%@ | %@ | reads %@ | %@ | %@\n", RSDayNumberText([[p objectForKey:@"day"] longValue]), [p objectForKey:@"title"] ?: key,
         [p objectForKey:@"reads"], [times count] ? [times componentsJoinedByString:@" · "] : @"-", recorded ? @"recorded" : @"not recorded"];
    }
    if ([read length]) [s appendFormat:@"\nRead (day | story | reads of 3 | times | recorded):\n%@", read];
    NSMutableString *readingWords = [NSMutableString string];
    for (RSKeptLine *line in [lines lines]) {
        if (![line isWord] || !RSIsReadingKey([line video]) || [line kept] < [shelf start]) continue;
        [readingWords appendFormat:@"%@ | %@ (%@) | %@ | in: %@\n", [line video], [line word], [line lemma] ?: @"",
         RSOneLine([line gloss] ?: @""), RSOneLine([line text])];
    }
    if ([readingWords length]) [s appendFormat:@"\nReading words kept (word (lemma) | gloss | the sentence):\n%@", readingWords];
    if ([tutor length]) [s appendFormat:@"\nFor the tutor:\n%@%@", tutor, [tutor hasSuffix:@"\n"] ? @"" : @"\n"];
    return s;
}
