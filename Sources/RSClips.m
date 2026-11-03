#import "RSClips.h"
#import "RSSubtitles.h"
#import "RSReport.h"

const double RSClipShortest = 120, RSClipLongest = 180;

@implementation RSClipPlan

- (void)dealloc
{
    [_video release];
    [super dealloc];
}

@end

static BOOL RSInWorked(double start, NSArray *worked)
{
    for (NSDictionary *w in worked) {
        double a = [[w objectForKey:@"start"] doubleValue], b = [[w objectForKey:@"end"] doubleValue];
        if (start >= a - 0.01 && start < b - 0.01) return YES;
    }
    return NO;
}

static NSUInteger RSHelpTotal(NSDictionary *line)
{
    NSUInteger n = 0;
    for (NSString *key in line) {
        id v = [line objectForKey:key];
        if ([v isKindOfClass:[NSNumber class]] && ![key isEqualToString:@"start"]) n += [v unsignedIntegerValue];
    }
    return n;
}

RSClipPlan *RSChooseClip(NSString *video, RSSubtitles *subtitles, NSArray *helped, NSArray *worked)
{
    NSArray *lines = [subtitles lines];
    if ([lines count] == 0) return nil;
    NSUInteger first = NSNotFound;
    // The line most asked about, not yet worked.
    NSUInteger best = 0;
    for (NSDictionary *h in helped) {
        double start = [[h objectForKey:@"start"] doubleValue];
        NSUInteger n = RSHelpTotal(h);
        if (n == 0 || n < best || RSInWorked(start, worked)) continue;
        NSUInteger i = [subtitles indexAtTime:start + 0.05];
        if (i == NSNotFound) continue;
        if (n > best || i < first) { best = n; first = i; }
    }
    if (first == NSNotFound) {
        // The first line after the last clip worked.
        double after = 0;
        for (NSDictionary *w in worked) after = MAX(after, [[w objectForKey:@"end"] doubleValue]);
        for (NSUInteger i = 0; i < [lines count]; i++)
            if ([(RSLine *)[lines objectAtIndex:i] start] >= after - 0.01 && !RSInWorked([(RSLine *)[lines objectAtIndex:i] start], worked)) { first = i; break; }
    }
    if (first == NSNotFound) return nil;
    return RSClipFromLine(video, subtitles, first);
}

RSClipPlan *RSClipFromLine(NSString *video, RSSubtitles *subtitles, NSUInteger first)
{
    NSArray *lines = [subtitles lines];
    if (first >= [lines count]) return nil;
    double start = [(RSLine *)[lines objectAtIndex:first] start];
    // On to the last line that ends within the longest span; at least the
    // shortest span if there are lines for it.
    NSUInteger last = first;
    for (NSUInteger i = first; i < [lines count]; i++) {
        RSLine *line = [lines objectAtIndex:i];
        if ([line end] - start <= RSClipLongest) last = i;
        else if ([(RSLine *)[lines objectAtIndex:last] end] - start < RSClipShortest) last = i;
        else break;
    }
    RSClipPlan *plan = [[[RSClipPlan alloc] init] autorelease];
    [plan setVideo:video];
    [plan setStart:start];
    [plan setEnd:[(RSLine *)[lines objectAtIndex:last] end]];
    [plan setFirstLine:first];
    [plan setLastLine:last];
    return plan;
}

NSString *RSClipSpan(double start, double end)
{
    return [NSString stringWithFormat:@"%@–%@", RSClock(start), RSClock(end)];
}
