#import "RSReport.h"
#import "RSLibrary.h"
#import "RSShelf.h"
#import "RSLines.h"
#include <unistd.h>

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

// gethostname, not NSHost: NSHost can wait on the network, and a report is
// written on the main thread, often offline.
NSString *RSComputerName(void)
{
    char buffer[256] = { 0 };
    NSString *name = gethostname(buffer, sizeof buffer - 1) == 0 ? [NSString stringWithUTF8String:buffer] : nil;
    if ([name hasSuffix:@".local"]) name = [name substringToIndex:[name length] - 6];
    name = [[name componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
    return [name length] ? name : @"this Mac";
}

static NSString *RSOneLine(NSString *text)
{
    return [[text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" / "];
}

NSString *RSReportText(RSShelf *shelf, RSLibrary *library, RSLines *lines, time_t now)
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
    NSMutableString *help = [NSMutableString string], *kept = [NSMutableString string];
    for (RSVideo *video in [shelf videos]) {
        NSString *identifier = [video identifier];
        NSUInteger shown = [library help:RSHelpShown for:identifier], again = [library help:RSHelpHeardAgain for:identifier],
                   keptCount = [library help:RSHelpKept for:identifier];
        if (shown || again || keptCount)
            [help appendFormat:@"%@ | shown %lu | heard again %lu | kept %lu\n", identifier,
             (unsigned long)shown, (unsigned long)again, (unsigned long)keptCount];
        for (RSKeptLine *line in [lines linesFromVideo:identifier])
            [kept appendFormat:@"%@ | %@ | %@\n", identifier, RSClock([line start]), RSOneLine([line text])];
    }
    if ([help length]) [s appendFormat:@"\nHelp (lines shown, heard again, kept):\n%@", help];
    if ([kept length]) [s appendFormat:@"\nKept:\n%@", kept];
    return s;
}
