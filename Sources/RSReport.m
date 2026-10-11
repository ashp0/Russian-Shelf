#import "RSReport.h"
#import "RSLibrary.h"
#import "RSShelf.h"

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

NSString *RSReportText(RSShelf *shelf, RSLibrary *library, time_t now)
{
    NSMutableString *s = [NSMutableString stringWithString:@"Russian Shelf report\n"];
    [s appendFormat:@"shelf: %@ (sealed %@)\n", [shelf startText], [shelf sealed]];
    [s appendFormat:@"written: %@\n\n", RSLocalTime(now, "%Y-%m-%d %H:%M")];
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
    return s;
}
