#import "RSMerge.h"

static NSDictionary *RSDict(id value)
{
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static NSArray *RSArray(id value)
{
    return [value isKindOfClass:[NSArray class]] ? value : nil;
}

static double RSNumber(NSDictionary *d, NSString *key)
{
    id value = [d objectForKey:key];
    return [value isKindOfClass:[NSNumber class]] ? [value doubleValue] : 0;
}

static NSString *RSText(NSDictionary *d, NSString *key)
{
    id value = [d objectForKey:key];
    return [value isKindOfClass:[NSString class]] &&
           [[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] ? value : nil;
}

static NSComparisonResult RSCompare(double a, double b)
{
    return a < b ? NSOrderedAscending : a > b ? NSOrderedDescending : NSOrderedSame;
}

static NSString *RSTrimmedLine(NSString *line)
{
    return [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSArray *RSLinesOf(NSString *text)
{
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *line in [text ?: @"" componentsSeparatedByString:@"\n"])
        [lines addObject:[line hasSuffix:@"\r"] ? [line substringToIndex:[line length] - 1] : line];
    return lines;
}

static void RSDropTrailingBlanks(NSMutableArray *lines)
{
    while ([lines count] && [RSTrimmedLine([lines lastObject]) length] == 0) [lines removeLastObject];
}

// Appends to `lines` each line of `more` that isn't blank and isn't there
// already (spaces aside). YES if any was.
static BOOL RSUnionLines(NSMutableArray *lines, NSArray *more)
{
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *line in lines) [seen addObject:RSTrimmedLine(line)];
    BOOL added = NO;
    for (NSString *line in more) {
        NSString *t = RSTrimmedLine(line);
        if ([t length] == 0 || [seen containsObject:t]) continue;
        [seen addObject:t];
        [lines addObject:t];
        added = YES;
    }
    return added;
}

@implementation RSMerge

// ---- State.plist ---------------------------------------------------------------

+ (NSDictionary *)video:(NSDictionary *)l with:(NSDictionary *)r
{
    NSMutableDictionary *m = l ? [[l mutableCopy] autorelease] : [NSMutableDictionary dictionary];
    double lf = RSNumber(l, @"furthest"), rf = RSNumber(r, @"furthest");
    double lp = RSNumber(l, @"position"), rp = RSNumber(r, @"position");
    [m setObject:[NSNumber numberWithDouble:MAX(lf, rf)] forKey:@"furthest"];
    [m setObject:[NSNumber numberWithDouble:rf > lf ? rp : lf > rf ? lp : MAX(lp, rp)] forKey:@"position"];
    [m setObject:[NSNumber numberWithDouble:MAX(RSNumber(l, @"duration"), RSNumber(r, @"duration"))] forKey:@"duration"];
    [m setObject:[NSNumber numberWithBool:[[l objectForKey:@"finished"] boolValue] || [[r objectForKey:@"finished"] boolValue]]
          forKey:@"finished"];
    for (NSString *key in [NSArray arrayWithObjects:@"felt", @"want", nil])
        if (RSText(l, key) == nil && RSText(r, key)) [m setObject:RSText(r, key) forKey:key];
    return m;
}

+ (NSArray *)clips:(NSArray *)l with:(NSArray *)r
{
    NSMutableDictionary *byPlace = [NSMutableDictionary dictionary];
    NSArray *sides[2] = { l ?: [NSArray array], r ?: [NSArray array] };
    for (int side = 0; side < 2; side++)
        for (NSDictionary *clip in sides[side]) {
            if (!RSDict(clip)) continue;
            NSString *place = [NSString stringWithFormat:@"%.3f %.3f", RSNumber(clip, @"start"), RSNumber(clip, @"end")];
            NSDictionary *had = [byPlace objectForKey:place];
            NSComparisonResult c = had ? RSCompare(RSNumber(clip, @"passes"), RSNumber(had, @"passes")) : NSOrderedDescending;
            if (c == NSOrderedSame) c = RSCompare(RSNumber(clip, @"day"), RSNumber(had, @"day"));
            if (c == NSOrderedDescending) [byPlace setObject:clip forKey:place];
        }
    return [[byPlace allValues] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        NSComparisonResult c = RSCompare(RSNumber(a, @"start"), RSNumber(b, @"start"));
        return c != NSOrderedSame ? c : RSCompare(RSNumber(a, @"end"), RSNumber(b, @"end"));
    }];
}

+ (NSDictionary *)state:(NSDictionary *)local with:(NSDictionary *)remote
{
    local = RSDict(local) ?: [NSDictionary dictionary];
    if (!RSDict(remote)) return local;
    NSMutableDictionary *out = [[local mutableCopy] autorelease];

    NSDictionary *lw = RSDict([local objectForKey:@"watched"]), *rw = RSDict([remote objectForKey:@"watched"]);
    if (rw) {
        NSMutableDictionary *watched = lw ? [[lw mutableCopy] autorelease] : [NSMutableDictionary dictionary];
        for (NSString *identifier in rw) {
            NSDictionary *r = RSDict([rw objectForKey:identifier]);
            if (![identifier isKindOfClass:[NSString class]] || [identifier length] == 0 || r == nil) continue;
            [watched setObject:[self video:RSDict([watched objectForKey:identifier]) with:r] forKey:identifier];
        }
        [out setObject:watched forKey:@"watched"];
    }

    NSDictionary *lc = RSDict([local objectForKey:@"clips"]), *rc = RSDict([remote objectForKey:@"clips"]);
    if (lc || rc) {
        NSMutableDictionary *clips = [NSMutableDictionary dictionary];
        NSMutableSet *ids = [NSMutableSet setWithArray:[lc allKeys] ?: [NSArray array]];
        [ids addObjectsFromArray:[rc allKeys] ?: [NSArray array]];
        for (NSString *identifier in ids) {
            if (![identifier isKindOfClass:[NSString class]]) continue;
            NSArray *merged = [self clips:RSArray([lc objectForKey:identifier]) with:RSArray([rc objectForKey:identifier])];
            if ([merged count]) [clips setObject:merged forKey:identifier];
        }
        [out setObject:clips forKey:@"clips"];
    }

    NSDictionary *ls = RSDict([local objectForKey:@"say"]), *rs = RSDict([remote objectForKey:@"say"]);
    if (rs) {
        NSMutableDictionary *say = ls ? [[ls mutableCopy] autorelease] : [NSMutableDictionary dictionary];
        for (NSString *day in rs)
            if ([say objectForKey:day] == nil && RSDict([rs objectForKey:day])) [say setObject:[rs objectForKey:day] forKey:day];
        [out setObject:say forKey:@"say"];
    }
    return out;
}

// ---- Lines.plist ------------------------------------------------------------------

+ (BOOL)isCardKey:(id)key
{
    if (![key isKindOfClass:[NSString class]] || [key length] == 0 || [key length] > 100 || [key hasPrefix:@"."]) return NO;
    NSMutableCharacterSet *allowed = [[[NSCharacterSet alphanumericCharacterSet] mutableCopy] autorelease];
    [allowed addCharactersInString:@"._-"];
    return [key rangeOfCharacterFromSet:[allowed invertedSet]].location == NSNotFound;
}

static BOOL RSIsCard(id card)
{
    return RSDict(card) && [[card objectForKey:@"key"] isKindOfClass:[NSString class]] &&
           [[card objectForKey:@"video"] isKindOfClass:[NSString class]] && [[card objectForKey:@"text"] isKindOfClass:[NSString class]];
}

// NSOrderedDescending: the remote card wins.
static NSComparisonResult RSCompareCards(NSDictionary *l, NSDictionary *r)
{
    NSComparisonResult c = RSCompare(RSNumber(r, @"heard"), RSNumber(l, @"heard"));
    if (c == NSOrderedSame) c = RSCompare(RSNumber(r, @"step"), RSNumber(l, @"step"));
    if (c == NSOrderedSame) c = RSCompare([[r objectForKey:@"putAway"] boolValue], [[l objectForKey:@"putAway"] boolValue]);
    if (c == NSOrderedSame) c = RSCompare(RSNumber(r, @"lapses"), RSNumber(l, @"lapses"));
    return c;
}

+ (NSDictionary *)card:(NSDictionary *)l with:(NSDictionary *)r
{
    BOOL theirs = RSCompareCards(l, r) == NSOrderedDescending;
    NSDictionary *winner = theirs ? r : l, *other = theirs ? l : r;
    NSMutableDictionary *m = [[winner mutableCopy] autorelease];
    // A key only the other card has stays: a Mac running an older Shelf
    // saves its cards without the keys it doesn't know, and must not erase
    // them everywhere by hearing a card last.
    for (id key in other)
        if ([m objectForKey:key] == nil) [m setObject:[other objectForKey:key] forKey:key];
    if ([[other objectForKey:@"putAway"] boolValue]) [m setObject:[NSNumber numberWithBool:YES] forKey:@"putAway"];
    if (RSText(winner, @"meaning") == nil && RSText(other, @"meaning")) [m setObject:RSText(other, @"meaning") forKey:@"meaning"];
    return m;
}

+ (NSDictionary *)cards:(NSDictionary *)local with:(NSDictionary *)remote
{
    local = RSDict(local) ?: [NSDictionary dictionary];
    NSArray *rl = RSArray([RSDict(remote) objectForKey:@"lines"]);
    if (rl == nil) return local;
    NSMutableDictionary *byKey = [NSMutableDictionary dictionary];
    for (NSDictionary *card in RSArray([local objectForKey:@"lines"]))
        if (RSIsCard(card) && [byKey objectForKey:[card objectForKey:@"key"]] == nil)
            [byKey setObject:card forKey:[card objectForKey:@"key"]];
    for (NSDictionary *card in rl) {
        if (!RSIsCard(card) || ![self isCardKey:[card objectForKey:@"key"]]) continue;
        NSString *key = [card objectForKey:@"key"];
        NSDictionary *had = [byKey objectForKey:key];
        [byKey setObject:had ? [self card:had with:card] : card forKey:key];
    }
    NSArray *lines = [[byKey allValues] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        NSComparisonResult c = RSCompare(RSNumber(a, @"kept"), RSNumber(b, @"kept"));
        return c != NSOrderedSame ? c : [[a objectForKey:@"key"] compare:[b objectForKey:@"key"]];
    }];
    NSMutableDictionary *out = [[local mutableCopy] autorelease];
    [out setObject:lines forKey:@"lines"];
    return out;
}

// ---- Say/*.txt -------------------------------------------------------------------

+ (NSString *)islands:(NSString *)local with:(NSString *)remote
{
    NSMutableArray *lines = [NSMutableArray arrayWithArray:RSLinesOf(local)];
    RSDropTrailingBlanks(lines);
    if (!RSUnionLines(lines, RSLinesOf(remote))) return local ?: @"";
    return [[lines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
}

// "## 2026-11-03 ..." -> "2026-11-03", else nil.
static NSString *RSSectionDate(NSString *line)
{
    if (![line hasPrefix:@"##"]) return nil;
    NSString *rest = RSTrimmedLine([line substringFromIndex:2]);
    if ([rest length] < 10) return nil;
    NSString *date = [rest substringToIndex:10];
    for (NSUInteger i = 0; i < 10; i++) {
        unichar c = [date characterAtIndex:i];
        if ((i == 4 || i == 7) ? c != '-' : (c < '0' || c > '9')) return nil;
    }
    return date;
}

// The text before the first heading under "", then each date's heading and
// lines: date -> [heading, line, line, ...], and the dates in order met.
static void RSParseTutor(NSString *text, NSMutableDictionary *sections, NSMutableArray *dates)
{
    NSString *current = @"";
    [sections setObject:[NSMutableArray array] forKey:@""];
    for (NSString *line in RSLinesOf(text)) {
        NSString *date = RSSectionDate(line);
        if (date) {
            current = date;
            if ([sections objectForKey:date] == nil) {
                [sections setObject:[NSMutableArray arrayWithObject:RSTrimmedLine(line)] forKey:date];
                [dates addObject:date];
            }
            continue;
        }
        [[sections objectForKey:current] addObject:line];
    }
}

+ (NSString *)tutor:(NSString *)local with:(NSString *)remote
{
    NSMutableDictionary *mine = [NSMutableDictionary dictionary], *theirs = [NSMutableDictionary dictionary];
    NSMutableArray *dates = [NSMutableArray array], *theirDates = [NSMutableArray array];
    RSParseTutor(local, mine, dates);
    RSParseTutor(remote, theirs, theirDates);
    for (NSString *date in mine) RSDropTrailingBlanks([mine objectForKey:date]);
    BOOL added = NO;
    for (NSString *date in [[NSArray arrayWithObject:@""] arrayByAddingObjectsFromArray:theirDates]) {
        NSMutableArray *lines = [mine objectForKey:date];
        NSArray *more = [theirs objectForKey:date];
        if (lines == nil) {
            lines = [NSMutableArray arrayWithObject:[more objectAtIndex:0]];
            [mine setObject:lines forKey:date];
            [dates addObject:date];
            added = YES;
        }
        if (![date length]) { added |= RSUnionLines(lines, more); continue; }
        // The heading stays first; the other Mac's heading isn't a line.
        added |= RSUnionLines(lines, [more subarrayWithRange:NSMakeRange(1, [more count] - 1)]);
    }
    if (!added) return local ?: @"";

    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *date in [[NSArray arrayWithObject:@""] arrayByAddingObjectsFromArray:
                            [dates sortedArrayUsingSelector:@selector(compare:)]]) {
        NSMutableArray *lines = [NSMutableArray arrayWithArray:[mine objectForKey:date]];
        while ([lines count] && ![date length] && [RSTrimmedLine([lines objectAtIndex:0]) length] == 0) [lines removeObjectAtIndex:0];
        RSDropTrailingBlanks(lines);
        if ([lines count]) [parts addObject:[lines componentsJoinedByString:@"\n"]];
    }
    return [[parts componentsJoinedByString:@"\n\n"] stringByAppendingString:@"\n"];
}

// ---- Files ---------------------------------------------------------------------------

+ (NSArray *)missing:(NSArray *)local from:(NSArray *)remote
{
    NSSet *here = [NSSet setWithArray:local ?: [NSArray array]];
    NSMutableSet *copy = [NSMutableSet set];
    for (NSString *name in remote)
        if (![here containsObject:name]) [copy addObject:name];
    return [[copy allObjects] sortedArrayUsingSelector:@selector(compare:)];
}

@end
