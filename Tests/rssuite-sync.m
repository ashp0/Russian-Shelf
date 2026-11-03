// Sync between the two Macs, checked (included by rssuite.m, which has
// CHECK, Has, Temp, Run and Capture): the host's folder name, every merge
// rule on two fixture folders (Tests/Fixtures/Sync/mac-pro and macbook),
// merging into and staging from an app folder, the brakes' counts, and real
// git: two app folders acting as two Macs publish, pull, merge and end
// alike through a bare repository, with a race and a read-only key.

#import "RSSyncFolder.h"
#import "RSMerge.h"
#import "RSSyncManager.h"

static NSDictionary *Plist(NSString *path)
{
    return [NSDictionary dictionaryWithContentsOfFile:path];
}

static NSString *Text(NSString *path)
{
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
}

static NSDictionary *CardNamed(NSDictionary *cards, NSString *key)
{
    for (NSDictionary *card in [cards objectForKey:@"lines"])
        if ([[card objectForKey:@"key"] isEqualToString:key]) return card;
    return nil;
}

static NSArray *CardKeys(NSDictionary *cards)
{
    NSMutableArray *keys = [NSMutableArray array];
    for (NSDictionary *card in [cards objectForKey:@"lines"]) [keys addObject:[card objectForKey:@"key"]];
    return keys;
}

// The parts of State.plist both Macs share: each video's progress, the clips.
static NSDictionary *Shared(NSDictionary *state)
{
    NSMutableDictionary *watched = [NSMutableDictionary dictionary];
    NSDictionary *w = [state objectForKey:@"watched"];
    for (NSString *identifier in w) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        for (NSString *key in [NSArray arrayWithObjects:@"position", @"furthest", @"duration", @"finished", nil])
            if ([[w objectForKey:identifier] objectForKey:key]) [d setObject:[[w objectForKey:identifier] objectForKey:key] forKey:key];
        [watched setObject:d forKey:identifier];
    }
    return [NSDictionary dictionaryWithObjectsAndKeys:watched, @"watched",
            [state objectForKey:@"clips"] ?: [NSDictionary dictionary], @"clips", nil];
}

static NSArray *Names(NSString *folder)
{
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:NULL])
        if (![name hasPrefix:@"."]) [names addObject:[name precomposedStringWithCanonicalMapping]];
    return [names sortedArrayUsingSelector:@selector(compare:)];
}

// An app folder laid out as the app keeps it, from a host's fixture folder
// (laid out as it's published).
static NSString *AppFolderFrom(NSString *host, NSString *name)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *app = Temp(name);
    [fm removeItemAtPath:app error:NULL];
    [fm createDirectoryAtPath:[app stringByAppendingPathComponent:@"Say"] withIntermediateDirectories:YES attributes:nil error:NULL];
    [fm copyItemAtPath:[host stringByAppendingPathComponent:@"State.plist"] toPath:[app stringByAppendingPathComponent:@"State.plist"] error:NULL];
    [fm copyItemAtPath:[host stringByAppendingPathComponent:@"Cards"] toPath:[app stringByAppendingPathComponent:@"Lines"] error:NULL];
    [fm copyItemAtPath:[host stringByAppendingPathComponent:@"Cards.plist"] toPath:[app stringByAppendingPathComponent:@"Lines/Lines.plist"] error:NULL];
    [fm copyItemAtPath:[host stringByAppendingPathComponent:@"Recordings"] toPath:[app stringByAppendingPathComponent:@"Say/Recordings"] error:NULL];
    for (NSString *text in [NSArray arrayWithObjects:@"Islands.txt", @"Tutor.txt", nil])
        [fm copyItemAtPath:[host stringByAppendingPathComponent:text] toPath:[[app stringByAppendingPathComponent:@"Say"]
                                                                              stringByAppendingPathComponent:text] error:NULL];
    return app;
}

static void TestSyncNames(void)
{
    CHECK([[RSSyncFolder slugForName:@"Ashwin’s Mac Pro"] isEqualToString:@"ashwins-mac-pro"], "a Mac's folder: %s",
          [[RSSyncFolder slugForName:@"Ashwin’s Mac Pro"] UTF8String]);
    CHECK([[RSSyncFolder slugForName:@"Ashwin's MacBook Pro (2)"] isEqualToString:@"ashwins-macbook-pro-2"], "brackets and digits");
    CHECK([[RSSyncFolder slugForName:@"Мак Про"] isEqualToString:@"mak-pro"], "Cyrillic, in Latin letters: %s",
          [[RSSyncFolder slugForName:@"Мак Про"] UTF8String]);
    CHECK([[RSSyncFolder slugForName:@"  --Mac__Pro--  "] isEqualToString:@"mac-pro"], "runs of anything else: one hyphen");
    CHECK([[RSSyncFolder slugForName:@""] isEqualToString:@"mac"] && [[RSSyncFolder slugForName:nil] isEqualToString:@"mac"] &&
          [[RSSyncFolder slugForName:@"’…"] isEqualToString:@"mac"], "nothing left: mac");
    CHECK([[RSSyncFolder slugForName:@"this Mac"] isEqualToString:@"this-mac"], "RSComputerName's last resort");
    NSString *longName = [RSSyncFolder slugForName:@"A very long computer name that someone typed into Sharing one day"];
    CHECK([longName length] <= 40 && ![longName hasSuffix:@"-"], "at most 40 characters: %s", [longName UTF8String]);
    NSString *slug = [RSSyncFolder hostSlug];
    CHECK([slug isEqualToString:[RSSyncFolder slugForName:RSComputerName()]] && [[RSSyncFolder slugForName:slug] isEqualToString:slug] &&
          [slug isEqualToString:[RSSyncFolder hostSlug]], "this Mac's folder is stable: %s", [slug UTF8String]);
    CHECK([[RSSyncFolder pathForHost:@"mac-pro"] isEqualToString:@"Russian/Sync/mac-pro"], "under Russian/Sync");
    CHECK([RSSyncFolder isStagingPath:@"State.plist"] && [RSSyncFolder isStagingPath:@"Cards/слово-vid-0000005000.m4a"] &&
          [RSSyncFolder isStagingPath:@"Recordings/2026-10.m4a"], "paths a staging folder holds");
    CHECK(![RSSyncFolder isStagingPath:@"../x"] && ![RSSyncFolder isStagingPath:@".git/config"] && ![RSSyncFolder isStagingPath:@"a/b/c/d"] &&
          ![RSSyncFolder isStagingPath:@"a b.txt"] && ![RSSyncFolder isStagingPath:@""] && ![RSSyncFolder isStagingPath:@"Cards/"],
          "and paths it doesn't");
    CHECK([RSMerge isCardKey:@"JE4cI_Knzvc-0000250120"] && [RSMerge isCardKey:@"слово-JE4cI_Knzvc-0000250120"] &&
          ![RSMerge isCardKey:@"../evil"] && ![RSMerge isCardKey:@"a/b"] && ![RSMerge isCardKey:@".hidden"] && ![RSMerge isCardKey:@"a b"] &&
          ![RSMerge isCardKey:[NSNumber numberWithInt:3]], "card keys that are safe file names");
}

static void TestSyncMerge(NSString *fixtures)
{
    NSString *a = [fixtures stringByAppendingPathComponent:@"Sync/mac-pro"], *b = [fixtures stringByAppendingPathComponent:@"Sync/macbook"];
    long T = RSDaysFromCivil(2026, 10, 30);

    // ---- State.plist
    NSDictionary *sa = Plist([a stringByAppendingPathComponent:@"State.plist"]), *sb = Plist([b stringByAppendingPathComponent:@"State.plist"]);
    CHECK(sa && sb, "the state fixtures read");
    NSDictionary *m = [RSMerge state:sa with:sb];
    NSDictionary *w = [m objectForKey:@"watched"];
    NSDictionary *va = [w objectForKey:@"vidAAAAAAAA"], *vb = [w objectForKey:@"vidBBBBBBBB"], *vc = [w objectForKey:@"vidCCCCCCCC"];
    NSDictionary *vd = [w objectForKey:@"vidDDDDDDDD"], *ve = [w objectForKey:@"vidEEEEEEEE"];
    CHECK([[va objectForKey:@"furthest"] doubleValue] == 400 && [[va objectForKey:@"position"] doubleValue] == 300,
          "further here: this Mac's furthest and position");
    CHECK([[vb objectForKey:@"furthest"] doubleValue] == 150 && [[vb objectForKey:@"position"] doubleValue] == 90 &&
          [[vb objectForKey:@"duration"] doubleValue] == 610, "further there: theirs, and the longer duration");
    CHECK([[vc objectForKey:@"furthest"] doubleValue] == 200 && [[vc objectForKey:@"position"] doubleValue] == 180,
          "as far on both: the later position");
    CHECK([[vc objectForKey:@"finished"] boolValue] && ![[va objectForKey:@"finished"] boolValue], "finished on either is finished");
    CHECK([[va objectForKey:@"felt"] isEqualToString:@"about right"] && [[vc objectForKey:@"felt"] isEqualToString:@"too hard"],
          "felt: this Mac's when both said");
    CHECK([[vb objectForKey:@"felt"] isEqualToString:@"about right"] && [[vc objectForKey:@"want"] isEqualToString:@"more like this"],
          "felt and want: theirs when only they said");
    CHECK([[va objectForKey:@"shown"] intValue] == 3 && [[va objectForKey:@"lines"] count] == 1 && [[vb objectForKey:@"heardAgain"] intValue] == 2,
          "help counts and their lines stay this Mac's");
    CHECK([[va objectForKey:@"macproOnly"] isEqualToString:@"kept here"], "a key this doesn't know survives");
    CHECK([vd isEqual:[[sa objectForKey:@"watched"] objectForKey:@"vidDDDDDDDD"]], "a video only here is as it was");
    CHECK(ve && [[ve objectForKey:@"furthest"] doubleValue] == 60 && [[ve objectForKey:@"position"] doubleValue] == 30 &&
          [[ve objectForKey:@"felt"] isEqualToString:@"too hard"] && [ve objectForKey:@"shown"] == nil && [ve objectForKey:@"lines"] == nil &&
          [ve objectForKey:@"macbookOnly"] == nil, "a video only there comes with its progress and feeling, not its help");
    CHECK([[m objectForKey:@"notice"] isEqualToString:[sa objectForKey:@"notice"]] && [[m objectForKey:@"futureKey"] isEqualToString:@"keep me"] &&
          [m objectForKey:@"otherFuture"] == nil, "notice and unknown top-level keys: this Mac's");
    // The speed a video was left at, and the slowest: this Mac's rate when it has one, the slower slowest.
    NSDictionary *rl = [NSDictionary dictionaryWithObject:[NSDictionary dictionaryWithObjectsAndKeys:
        [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithFloat:0.8f], @"rate", [NSNumber numberWithFloat:0.7f], @"slowest", nil], @"v1",
        [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithDouble:10], @"furthest", nil], @"v2", nil] forKey:@"watched"];
    NSDictionary *rr = [NSDictionary dictionaryWithObject:[NSDictionary dictionaryWithObjectsAndKeys:
        [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithFloat:0.6f], @"rate", [NSNumber numberWithFloat:0.5f], @"slowest", nil], @"v1",
        [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithFloat:0.9f], @"rate", [NSNumber numberWithFloat:0.9f], @"slowest", nil], @"v2", nil] forKey:@"watched"];
    NSDictionary *rm = [[RSMerge state:rl with:rr] objectForKey:@"watched"];
    CHECK(fabs([[[rm objectForKey:@"v1"] objectForKey:@"rate"] doubleValue] - 0.8) < 0.001 &&
          fabs([[[rm objectForKey:@"v1"] objectForKey:@"slowest"] doubleValue] - 0.5) < 0.001 &&
          fabs([[[rm objectForKey:@"v2"] objectForKey:@"rate"] doubleValue] - 0.9) < 0.001 &&
          fabs([[[rm objectForKey:@"v2"] objectForKey:@"slowest"] doubleValue] - 0.9) < 0.001, "speeds: this Mac's rate, the slower slowest, theirs when only they have one");
    NSArray *clips = [[m objectForKey:@"clips"] objectForKey:@"vidAAAAAAAA"];
    CHECK([clips count] == 3 && [[[clips objectAtIndex:0] objectForKey:@"passes"] intValue] == 3 &&
          [[[clips objectAtIndex:0] objectForKey:@"day"] longValue] == T - 4 && [[[clips objectAtIndex:1] objectForKey:@"start"] doubleValue] == 100 &&
          [[[clips objectAtIndex:2] objectForKey:@"start"] doubleValue] == 200, "clips: the union by place, more passes winning, in order");
    CHECK([[[m objectForKey:@"clips"] objectForKey:@"vidEEEEEEEE"] count] == 1, "and a video's clips only they have");
    NSDictionary *say = [m objectForKey:@"say"];
    NSString *day6 = [NSString stringWithFormat:@"%ld", T - 6], *day4 = [NSString stringWithFormat:@"%ld", T - 4];
    CHECK([say count] == 2 && [[[say objectForKey:day6] objectForKey:@"island"] isEqualToString:@"Мой день"] &&
          [[[say objectForKey:day4] objectForKey:@"island"] isEqualToString:@"Непал"],
          "say: by day, this Mac's day when both have it");
    CHECK([[RSMerge state:sa with:nil] isEqual:sa] && [[RSMerge state:sa with:(id)@"junk"] isEqual:sa], "nothing there: as it was");
    NSDictionary *fresh = [RSMerge state:nil with:sb];
    CHECK([[[fresh objectForKey:@"watched"] objectForKey:@"vidEEEEEEEE"] objectForKey:@"shown"] == nil &&
          [[[[fresh objectForKey:@"watched"] objectForKey:@"vidBBBBBBBB"] objectForKey:@"furthest"] doubleValue] == 150 &&
          [fresh objectForKey:@"notice"] == nil, "nothing here yet: their progress, no help, no notice");
    CHECK([[RSMerge state:m with:sb] isEqual:m] && [[RSMerge state:sa with:m] isEqual:m], "state: idempotent both ways");
    NSDictionary *mb = [RSMerge state:sb with:sa];
    CHECK([Shared(m) isEqual:Shared(mb)], "state: both Macs end with the same progress and clips");
    CHECK([Shared([RSMerge state:m with:mb]) isEqual:Shared(m)] && [[RSMerge state:m with:mb] isEqual:[RSMerge state:m with:m]],
          "and stay there");

    // ---- Lines.plist
    NSDictionary *ca = Plist([a stringByAppendingPathComponent:@"Cards.plist"]), *cb = Plist([b stringByAppendingPathComponent:@"Cards.plist"]);
    NSDictionary *mc = [RSMerge cards:ca with:cb];
    NSDictionary *k1 = CardNamed(mc, @"vidAAAAAAAA-0000004100");
    CHECK([[k1 objectForKey:@"heard"] longValue] == T && [[k1 objectForKey:@"lapses"] intValue] == 1 && [[k1 objectForKey:@"step"] intValue] == 0 &&
          [[k1 objectForKey:@"kind"] isEqualToString:@"line"] && [[k1 objectForKey:@"title"] isEqualToString:@"T vidAAAAAAAA"],
          "heard later there: their card, unknown keys too");
    CHECK([[k1 objectForKey:@"macproNote"] isEqualToString:@"mine"], "a key only this Mac's card has stays (an older Shelf drops keys)");
    NSMutableDictionary *stripped = [NSMutableDictionary dictionaryWithDictionary:CardNamed(cb, @"слово-vidEEEEEEEE-0000005000")];
    for (NSString *key in [NSArray arrayWithObjects:@"kind", @"word", @"lemma", @"gloss", @"rank", nil]) [stripped removeObjectForKey:key];
    [stripped setObject:[NSNumber numberWithLong:T] forKey:@"heard"];
    NSDictionary *old = [NSDictionary dictionaryWithObject:[NSArray arrayWithObject:stripped] forKey:@"lines"];
    NSDictionary *healed = CardNamed([RSMerge cards:cb with:old], @"слово-vidEEEEEEEE-0000005000");
    CHECK([[healed objectForKey:@"heard"] longValue] == T && [[healed objectForKey:@"lemma"] isEqualToString:@"сло́во"] &&
          [[healed objectForKey:@"kind"] isEqualToString:@"word"], "an older Mac hearing a word's card last doesn't erase the word");
    CHECK([[k1 objectForKey:@"meaning"] isEqualToString:@"She cut her hair."], "with the meaning written here, theirs having none");
    CHECK([[CardNamed(mc, @"vidAAAAAAAA-0000010000") objectForKey:@"step"] intValue] == 2 &&
          [[CardNamed(mc, @"vidAAAAAAAA-0000010000") objectForKey:@"due"] longValue] == T + 5, "heard the same day: the higher step");
    CHECK([[CardNamed(mc, @"vidBBBBBBBB-0000001000") objectForKey:@"putAway"] boolValue], "then the one put away");
    CHECK([[CardNamed(mc, @"vidBBBBBBBB-0000002000") objectForKey:@"lapses"] intValue] == 2, "then more lapses");
    NSDictionary *k5 = CardNamed(mc, @"vidCCCCCCCC-0000003000");
    CHECK([[k5 objectForKey:@"heard"] longValue] == T && [[k5 objectForKey:@"step"] intValue] == 1 && [[k5 objectForKey:@"putAway"] boolValue],
          "heard later here, put away there: this Mac's card, put away");
    CHECK(CardNamed(mc, @"vidDDDDDDDD-0000004000") && CardNamed(mc, @"vidEEEEEEEE-0000006000"), "a card only one Mac has is kept");
    NSDictionary *word = CardNamed(mc, @"слово-vidEEEEEEEE-0000005000");
    CHECK([[word objectForKey:@"lemma"] isEqualToString:@"сло́во"] && [[word objectForKey:@"rank"] intValue] == 180, "a word's card, with its own keys");
    CHECK(CardNamed(mc, @"../evil-0000000001") == nil && [[mc objectForKey:@"lines"] count] == 8, "a key that isn't a safe name stays out (%lu)",
          (unsigned long)[[mc objectForKey:@"lines"] count]);
    CHECK([[mc objectForKey:@"heardCount"] intValue] == 5 && [[mc objectForKey:@"heardDay"] longValue] == T, "heardDay and heardCount stay this Mac's");
    NSArray *keys = CardKeys(mc);
    CHECK([[keys objectAtIndex:0] isEqualToString:@"vidAAAAAAAA-0000004100"] &&
          [[keys lastObject] isEqualToString:@"слово-vidEEEEEEEE-0000005000"] &&
          [[keys objectAtIndex:6] isEqualToString:@"vidDDDDDDDD-0000004000"], "in the order kept: %s", [[keys description] UTF8String]);
    CHECK([[RSMerge cards:mc with:cb] isEqual:mc] && [[RSMerge cards:ca with:mc] isEqual:mc], "cards: idempotent both ways");
    // The MacBook keeps its own card with the unsafe key (a card made here
    // is never dropped; the app can't make such a key): leave it aside.
    NSDictionary *mcb = [RSMerge cards:cb with:ca];
    NSMutableArray *theirs = [NSMutableArray arrayWithArray:[mcb objectForKey:@"lines"]];
    [theirs removeObject:CardNamed(mcb, @"../evil-0000000001")];
    CHECK([[mc objectForKey:@"lines"] isEqual:theirs] && [[mcb objectForKey:@"lines"] count] == 9,
          "cards: both Macs end with the same cards (a card of its own always stays)");
    CHECK([[mcb objectForKey:@"heardCount"] intValue] == 7, "each with its own day's count");
    CHECK([[RSMerge cards:ca with:nil] isEqual:ca] && [[[RSMerge cards:nil with:cb] objectForKey:@"lines"] count] == 7,
          "nothing there: as it was; nothing here: theirs");

    // ---- Islands.txt, Tutor.txt
    NSString *ia = Text([a stringByAppendingPathComponent:@"Islands.txt"]), *ib = Text([b stringByAppendingPathComponent:@"Islands.txt"]);
    NSString *mi = [RSMerge islands:ia with:ib];
    CHECK([mi isEqualToString:@"Мой день\nУниверситет и учёба\nНепал\nЕда\nПланы на выходные\n"], "islands: ours in order, then their new ones: %s",
          [mi UTF8String]);
    CHECK([[RSMerge islands:mi with:ib] isEqualToString:mi] && [[RSMerge islands:ia with:mi] isEqualToString:mi] &&
          [[RSMerge islands:ia with:ia] isEqualToString:ia], "islands: idempotent");
    CHECK([[RSMerge islands:nil with:ib] isEqualToString:@"Мой день\nЕда\nНепал\nПланы на выходные\n"], "islands: none here yet");
    NSString *ta = Text([a stringByAppendingPathComponent:@"Tutor.txt"]), *tb = Text([b stringByAppendingPathComponent:@"Tutor.txt"]);
    NSString *mt = [RSMerge tutor:ta with:tb];
    CHECK([mt isEqualToString:@"For the tutor\n\n## 2026-10-28\n- забыл родительный падеж после «нет»\n- не знал слово «расписание»\n\n"
                              @"## 2026-10-29\n- вид глагола: сделал / делал\n\n"
                              @"## 2026-10-30\n- путаю «идти» и «ходить»\n- окончания в предложном падеже\n"], "tutor: by date, lines joined: %s",
          [mt UTF8String]);
    CHECK([[RSMerge tutor:mt with:tb] isEqualToString:mt] && [[RSMerge tutor:ta with:mt] isEqualToString:mt] &&
          [[RSMerge tutor:ta with:ta] isEqualToString:ta], "tutor: idempotent");
    NSString *mtb = [RSMerge tutor:tb with:ta];
    CHECK([[[mtb componentsSeparatedByString:@"\n"] sortedArrayUsingSelector:@selector(compare:)] isEqual:
           [[mt componentsSeparatedByString:@"\n"] sortedArrayUsingSelector:@selector(compare:)]] &&
          [mtb rangeOfString:@"## 2026-10-28"].location < [mtb rangeOfString:@"## 2026-10-29"].location, "tutor: both Macs hold the same notes");

    NSArray *copy = [RSMerge missing:[NSArray arrayWithObjects:@"2026-09.m4a", @"2026-10.m4a", nil]
                                from:[NSArray arrayWithObjects:@"2026-10.m4a", @"2026-08.m4a", nil]];
    CHECK([copy isEqual:[NSArray arrayWithObject:@"2026-08.m4a"]], "a month's recording is copied only when missing");
}

static void TestSyncFiles(NSString *fixtures)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *hosts = [fixtures stringByAppendingPathComponent:@"Sync"];
    NSString *a = [hosts stringByAppendingPathComponent:@"mac-pro"], *b = [hosts stringByAppendingPathComponent:@"macbook"];
    NSString *app = AppFolderFrom(a, @"app-mac-pro");
    long T = RSDaysFromCivil(2026, 10, 30);
    RSSyncManager *sync = [[[RSSyncManager alloc] initWithAppFolder:app studyFolder:Temp(@"no-study") host:@"mac-pro"] autorelease];

    // The brakes, before anything is merged: what the MacBook did today.
    [fm createDirectoryAtPath:[app stringByAppendingPathComponent:@"Sync In"] withIntermediateDirectories:YES attributes:nil error:NULL];
    [fm copyItemAtPath:b toPath:[app stringByAppendingPathComponent:@"Sync In/macbook"] error:NULL];
    CHECK([RSSyncManager heardTodayOnOtherHosts:app today:T] == 7 && [RSSyncManager heardTodayOnOtherHosts:app today:T + 1] == 0,
          "heard today on the other Mac: its count, on its day only");
    CHECK([RSSyncManager keptTodayOnOtherHosts:app today:T] == 1, "kept today there and not here yet: %lu",
          (unsigned long)[RSSyncManager keptTodayOnOtherHosts:app today:T]);
    CHECK([RSSyncManager heardTodayOnOtherHosts:Temp(@"nowhere") today:T] == 0, "no other Mac: nothing");

    // Merging the fixture folder (its own folder, mac-pro, is passed over).
    CHECK([sync mergeFrom:hosts cards:YES], "merging in changes the files here");
    NSDictionary *state = Plist([app stringByAppendingPathComponent:@"State.plist"]);
    CHECK([state isEqual:[RSMerge state:Plist([a stringByAppendingPathComponent:@"State.plist"])
                                    with:Plist([b stringByAppendingPathComponent:@"State.plist"])]], "State.plist is the merge");
    NSDictionary *cards = Plist([app stringByAppendingPathComponent:@"Lines/Lines.plist"]);
    CHECK([cards isEqual:[RSMerge cards:Plist([a stringByAppendingPathComponent:@"Cards.plist"])
                                   with:Plist([b stringByAppendingPathComponent:@"Cards.plist"])]], "Lines.plist is the merge");
    CHECK([fm fileExistsAtPath:[app stringByAppendingPathComponent:@"Lines/слово-vidEEEEEEEE-0000005000.m4a"]] &&
          [fm fileExistsAtPath:[app stringByAppendingPathComponent:@"Lines/vidEEEEEEEE-0000006000.m4a"]], "their cards' sounds came");
    CHECK([Text([app stringByAppendingPathComponent:@"Lines/vidAAAAAAAA-0000004100.m4a"]) hasPrefix:@"mac-pro"], "a sound here is never replaced");
    CHECK(![fm fileExistsAtPath:[app stringByAppendingPathComponent:@"evil-0000000001.m4a"]] &&
          ![fm fileExistsAtPath:[Temp(@"") stringByAppendingPathComponent:@"evil-0000000001.m4a"]], "nothing lands outside");
    NSArray *months = [NSArray arrayWithObjects:@"2026-08.m4a", @"2026-09.m4a", @"2026-10.m4a", nil];
    CHECK([Names([app stringByAppendingPathComponent:@"Say/Recordings"]) isEqual:months] &&
          [Text([app stringByAppendingPathComponent:@"Say/Recordings/2026-10.m4a"]) isEqualToString:@"mac-pro october"],
          "a month's recording that was missing came; this Mac's month stayed; not-a-month stayed out");
    CHECK([Text([app stringByAppendingPathComponent:@"Say/Islands.txt"]) hasSuffix:@"Еда\nПланы на выходные\n"] &&
          Has(Text([app stringByAppendingPathComponent:@"Say/Tutor.txt"]), @"## 2026-10-29"), "islands and notes for the tutor merged");
    CHECK(![sync mergeFrom:hosts cards:YES], "merging the same again changes nothing");
    CHECK([RSSyncManager keptTodayOnOtherHosts:app today:T] == 0, "kept today there and merged here: counted once, here");

    // The app reads what was merged.
    RSLines *lines = [[[RSLines alloc] initWithFolder:[app stringByAppendingPathComponent:@"Lines"]] autorelease];
    CHECK([[lines lines] count] == 8 && [lines isKept:@"vidEEEEEEEE" start:6.0], "RSLines opens the merged cards (%lu)",
          (unsigned long)[[lines lines] count]);
    RSLibrary *library = [[[RSLibrary alloc] initWithFolder:app aesKey:TestAES() publicKey:Hex(KeyAPublic)] autorelease];
    CHECK([[library watchFor:@"vidEEEEEEEE"] furthest] == 60 && [[library watchFor:@"vidCCCCCCCC"] finished], "RSLibrary opens the merged progress");
    NSMutableDictionary *later = [[state mutableCopy] autorelease];
    NSMutableDictionary *watched = [[[later objectForKey:@"watched"] mutableCopy] autorelease];
    [watched setObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithDouble:77], @"furthest",
                        [NSNumber numberWithDouble:70], @"position", nil] forKey:@"vidFFFFFFFF"];
    [later setObject:watched forKey:@"watched"];
    [later setObject:@"Another notice." forKey:@"notice"];
    [later writeToFile:[app stringByAppendingPathComponent:@"State.plist"] atomically:YES];
    [library reload];
    CHECK([[library watchFor:@"vidFFFFFFFF"] furthest] == 77 && [[library notice] isEqualToString:@"Another notice."],
          "-reload reads State.plist again");

    // The cards stay as they are while the Lines window has them.
    NSString *before = Text([app stringByAppendingPathComponent:@"Lines/Lines.plist"]);
    NSString *app2 = AppFolderFrom(a, @"app-mac-pro-2");
    RSSyncManager *sync2 = [[[RSSyncManager alloc] initWithAppFolder:app2 studyFolder:Temp(@"no-study") host:@"mac-pro"] autorelease];
    CHECK([sync2 mergeFrom:hosts cards:NO] && [Plist([app2 stringByAppendingPathComponent:@"Lines/Lines.plist"])
                                               isEqual:Plist([a stringByAppendingPathComponent:@"Cards.plist"])] &&
          ![fm fileExistsAtPath:[app2 stringByAppendingPathComponent:@"Lines/vidEEEEEEEE-0000006000.m4a"]], "cards: NO leaves the cards alone");
    CHECK(before != nil, "(the first app's cards are still there)");

    // Staging: Sync Out is what's here, laid out as published.
    [sync stage];
    NSString *out = [sync outFolder];
    NSArray *files = [RSSyncFolder filesIn:out];
    CHECK([files containsObject:@"State.plist"] && [files containsObject:@"Cards.plist"] && [files containsObject:@"Islands.txt"] &&
          [files containsObject:@"Tutor.txt"] && [files containsObject:@"Recordings/2026-08.m4a"] &&
          [files containsObject:@"Cards/слово-vidEEEEEEEE-0000005000.m4a"], "staged: %s", [[files description] UTF8String]);
    CHECK([Names([out stringByAppendingPathComponent:@"Cards"]) count] == 8 && [files count] == 4 + 8 + 3, "every card's sound, every month (%lu)",
          (unsigned long)[files count]);
    CHECK([[NSData dataWithContentsOfFile:[out stringByAppendingPathComponent:@"Cards.plist"]]
           isEqualToData:[NSData dataWithContentsOfFile:[app stringByAppendingPathComponent:@"Lines/Lines.plist"]]], "the cards as they are");
    [fm removeItemAtPath:[app stringByAppendingPathComponent:@"Say/Recordings/2026-09.m4a"] error:NULL];
    [@"junk" writeToFile:[out stringByAppendingPathComponent:@"Stray.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [@"partial" writeToFile:[app stringByAppendingPathComponent:@"Lines/vidAAAAAAAA-0000004100.partial.m4a"] atomically:YES
                   encoding:NSUTF8StringEncoding error:NULL];
    [sync stage];
    files = [RSSyncFolder filesIn:out];
    CHECK(![files containsObject:@"Recordings/2026-09.m4a"] && ![files containsObject:@"Stray.txt"] && [files count] == 4 + 8 + 2,
          "what's gone here goes from Sync Out; a sound still being cut never goes");
    CHECK([RSSyncFolder filesIn:Temp(@"no-such-folder")] == nil, "no staging folder: nil");
}

// One round as the app makes it after a pull.
static RSSyncResult *Round(RSSyncManager *sync)
{
    [RSSync pullFolder:[sync studyFolder]];
    NSString *problem = nil;
    if ([sync takeOtherHosts:&problem]) [sync mergeInCards:YES];
    else fprintf(stderr, "  take: %s\n", [problem UTF8String]);
    [sync stage];
    return [sync publish];
}

static void TestSyncRealGit(NSString *fixtures)
{
    NSString *git = [RSSync gitPath];
    if (git == nil) { printf("  (no git here: skipping the real sync)\n"); return; }
    [RSSync setLockRetryDelay:0.5];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *base = Temp(@"sync-git");
    NSString *g = [NSString stringWithFormat:@"'%@' -c user.name=t -c user.email=t@example.com", git];
    CHECK(Run(Temp(@""), [NSString stringWithFormat:
        @"rm -rf sync-git && mkdir -p sync-git && cd sync-git && %@ init -q --bare origin.git && %@ --git-dir=origin.git symbolic-ref HEAD refs/heads/main && "
        @"%@ clone -q origin.git macbook && cd macbook && git checkout -q -b main 2>/dev/null; "
        @"git config branch.main.remote origin && git config branch.main.merge refs/heads/main && mkdir -p Russian/Reports Inbox && "
        @"echo sealed > Russian/shelf.signed && echo report > Russian/Reports/r.txt && echo '# notes' > Inbox/keep.txt && "
        @"%@ add -A && %@ commit -q -m one && %@ push -q origin HEAD:main && cd .. && %@ clone -q origin.git macpro", g, g, g, g, g, g, g]),
          "set up the two clones");
    NSString *origin = [base stringByAppendingPathComponent:@"origin.git"];
    NSString *studyA = [base stringByAppendingPathComponent:@"macpro"], *studyB = [base stringByAppendingPathComponent:@"macbook"];

    // The git-1.9 stand-in again (see TestRealGit), which can also let the
    // other Mac push just before this one does.
    NSString *oldGit = Temp(@"git-1.9-sync");
    NSString *race = Temp(@"race.sh");
    NSString *calls = Temp(@"git-calls.txt");      // each command the app runs, one a line
    [[NSString stringWithFormat:@"#!/bin/sh\n"
      @"echo \"$1\" >> '%@'\n"
      @"if [ \"$1\" = update-index ]; then for a; do case \"$a\" in *,*,*) echo 'usage: git update-index [options] [--] [<file>...]' >&2; exit 129;; esac; done; fi\n"
      @"if [ \"$1\" = push ] && [ -f '%@' ]; then mv '%@' '%@.running' && sh '%@.running' >/dev/null 2>&1; rm -f '%@.running'; fi\n"
      @"exec '%@' \"$@\"\n", calls, race, race, race, race, race, git] writeToFile:oldGit atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    chmod([oldGit fileSystemRepresentation], 0755);
    [[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObject:oldGit forKey:@"GitPath"]];

    NSString *appA = AppFolderFrom([fixtures stringByAppendingPathComponent:@"Sync/mac-pro"], @"sync-app-a");
    NSString *appB = AppFolderFrom([fixtures stringByAppendingPathComponent:@"Sync/macbook"], @"sync-app-b");
    [fm removeItemAtPath:[appB stringByAppendingPathComponent:@"Say/Recordings/notes.m4a"] error:NULL];
    NSMutableDictionary *cardsB = [NSMutableDictionary dictionaryWithDictionary:Plist([appB stringByAppendingPathComponent:@"Lines/Lines.plist"])];
    NSMutableArray *linesB = [NSMutableArray arrayWithArray:[cardsB objectForKey:@"lines"]];
    [linesB removeObject:CardNamed(cardsB, @"../evil-0000000001")];       // the app never makes such a key
    [cardsB setObject:linesB forKey:@"lines"];
    [cardsB writeToFile:[appB stringByAppendingPathComponent:@"Lines/Lines.plist"] atomically:YES];
    RSSyncManager *a = [[[RSSyncManager alloc] initWithAppFolder:appA studyFolder:studyA host:@"Mac Pro"] autorelease];
    RSSyncManager *b = [[[RSSyncManager alloc] initWithAppFolder:appB studyFolder:studyB host:@"MacBook"] autorelease];
    CHECK([[a host] isEqualToString:@"mac-pro"] && [[b host] isEqualToString:@"macbook"], "the two Macs' folders");
    NSString *lastPaths = [NSString stringWithFormat:@"%@ -c core.quotepath=false --git-dir='%@' diff-tree -r --no-commit-id --name-only main~1 main", g, origin];
    NSString *originHead = [NSString stringWithFormat:@"%@ --git-dir='%@' rev-parse main", g, origin];

    // The Mac Pro goes first: its folder, nothing else.
    RSSyncResult *r = Round(a);
    CHECK([r ok] && [r changed] && [[r summary] isEqualToString:@"Synced with the other Mac."], "the Mac Pro publishes: %s / %s",
          [[r summary] UTF8String], [[r output] UTF8String]);
    NSArray *paths = [Capture(base, lastPaths) componentsSeparatedByString:@"\n"];
    BOOL inside = [paths count] == 4 + 6 + 2;
    for (NSString *p in paths) inside = inside && [p hasPrefix:@"Russian/Sync/mac-pro/"];
    CHECK(inside, "the commit holds Russian/Sync/mac-pro/ and nothing else (%lu): %s", (unsigned long)[paths count],
          [[paths description] UTF8String]);
    CHECK([Capture(studyA, [NSString stringWithFormat:@"%@ status --porcelain", g]) length] == 0 &&
          [Capture(studyA, [NSString stringWithFormat:@"%@ rev-parse HEAD", g]) isEqualToString:Capture(base, originHead)],
          "the clone is clean and current");
    CHECK([fm fileExistsAtPath:[studyA stringByAppendingPathComponent:@"Russian/Sync/mac-pro/Cards.plist"]] &&
          [Text([studyA stringByAppendingPathComponent:@"Inbox/keep.txt"]) isEqualToString:@"# notes\n"], "and has the folder; Inbox untouched");

    // The MacBook: pulls, merges the Mac Pro in, publishes; then the Mac Pro
    // takes that in, and then nothing is left to send.
    r = Round(b);
    CHECK([r ok] && [r changed], "the MacBook merges and publishes: %s", [[r summary] UTF8String]);
    paths = [Capture(base, lastPaths) componentsSeparatedByString:@"\n"];
    inside = [paths count] > 0;
    for (NSString *p in paths) inside = inside && [p hasPrefix:@"Russian/Sync/macbook/"];
    CHECK(inside, "its commit holds Russian/Sync/macbook/ only");
    CHECK([fm fileExistsAtPath:[appB stringByAppendingPathComponent:@"Lines/vidDDDDDDDD-0000004000.m4a"]] &&
          [Names([appB stringByAppendingPathComponent:@"Say/Recordings"]) containsObject:@"2026-09.m4a"], "the Mac Pro's sounds came over");
    r = Round(a);
    CHECK([r ok], "the Mac Pro takes it in: %s", [[r summary] UTF8String]);
    NSString *head = Capture(base, originHead);
    r = Round(b);
    CHECK([r ok] && ![r changed] && [Capture(base, originHead) isEqualToString:head], "nothing changed: nothing is committed (%s)",
          [[r output] UTF8String]);
    r = Round(a);
    CHECK([r ok] && ![r changed] && [Capture(base, originHead) isEqualToString:head], "on either Mac");

    // Then a round where nothing changed only looks: the pull and two
    // listings; no archive, no fetch, no publish, and Sync In stays as it was.
    NSString *left = [appA stringByAppendingPathComponent:@"Sync In/macbook/left.txt"];
    [@"left" writeToFile:left atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [@"" writeToFile:calls atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    r = Round(a);
    NSString *ran = [[Text(calls) stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]
                     stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    CHECK([r ok] && ![r changed] && [[r summary] isEqualToString:@"Synced with the other Mac."] &&
          [ran isEqualToString:@"pull ls-tree ls-tree"], "nothing changed: a pull and two looks (%s)", [ran UTF8String]);
    CHECK([fm fileExistsAtPath:left] && [Capture(base, originHead) isEqualToString:head], "Sync In isn't written again; nothing is sent");
    // The other Mac's folder changes: it's read again, and merged.
    Run(studyB, [NSString stringWithFormat:@"%@ pull -q --ff-only && echo 'Погода' >> Russian/Sync/macbook/Islands.txt && "
                 @"%@ commit -q -am 'the MacBook: an island' && %@ push -q origin HEAD:main", g, g, g]);
    r = Round(a);
    CHECK([r ok] && ![fm fileExistsAtPath:left] && Has(Text([appA stringByAppendingPathComponent:@"Say/Islands.txt"]), @"Погода"),
          "a change in the other Mac's folder: read again and merged (%s)", [[r summary] UTF8String]);
    // This Mac's folder changed upstream by someone else: the round puts it back.
    Run(studyB, [NSString stringWithFormat:@"%@ pull -q --ff-only && %@ rm -q Russian/Sync/mac-pro/Tutor.txt && "
                 @"%@ commit -q -m 'not the Mac Pro' && %@ push -q origin HEAD:main", g, g, g, g]);
    r = Round(a);
    CHECK([r ok] && [r changed] && [fm fileExistsAtPath:[studyA stringByAppendingPathComponent:@"Russian/Sync/mac-pro/Tutor.txt"]],
          "this Mac's folder not as it left it: published again (%s)", [[r summary] UTF8String]);
    r = Round(b);
    CHECK([r ok], "(the MacBook takes it in: %s)", [[r summary] UTF8String]);

    NSDictionary *la = Plist([appA stringByAppendingPathComponent:@"Lines/Lines.plist"]), *lb = Plist([appB stringByAppendingPathComponent:@"Lines/Lines.plist"]);
    CHECK([[la objectForKey:@"lines"] count] == 8 && [[la objectForKey:@"lines"] isEqual:[lb objectForKey:@"lines"]],
          "both Macs have the same cards (%lu)", (unsigned long)[[la objectForKey:@"lines"] count]);
    CHECK([[la objectForKey:@"heardCount"] intValue] == 5 && [[lb objectForKey:@"heardCount"] intValue] == 7, "each its own day's count");
    NSDictionary *stA = Plist([appA stringByAppendingPathComponent:@"State.plist"]), *stB = Plist([appB stringByAppendingPathComponent:@"State.plist"]);
    CHECK([Shared(stA) isEqual:Shared(stB)] && [[Shared(stA) objectForKey:@"watched"] count] == 5, "the same progress and clips");
    CHECK([[[[stA objectForKey:@"watched"] objectForKey:@"vidAAAAAAAA"] objectForKey:@"shown"] intValue] == 3 &&
          [[[[stB objectForKey:@"watched"] objectForKey:@"vidAAAAAAAA"] objectForKey:@"shown"] intValue] == 9, "and each its own help counts");
    CHECK([Names([appA stringByAppendingPathComponent:@"Lines"]) isEqual:Names([appB stringByAppendingPathComponent:@"Lines"])],
          "the same sounds");
    CHECK([Names([appA stringByAppendingPathComponent:@"Say/Recordings"]) isEqual:Names([appB stringByAppendingPathComponent:@"Say/Recordings"])] &&
          [Text([appA stringByAppendingPathComponent:@"Say/Recordings/2026-10.m4a"]) isEqualToString:@"mac-pro october"] &&
          [Text([appB stringByAppendingPathComponent:@"Say/Recordings/2026-10.m4a"]) isEqualToString:@"macbook october"],
          "the same months, each keeping its own recording of a month both made");
    NSString *ta = Text([appA stringByAppendingPathComponent:@"Say/Tutor.txt"]), *tb = Text([appB stringByAppendingPathComponent:@"Say/Tutor.txt"]);
    CHECK([[[ta componentsSeparatedByString:@"\n"] sortedArrayUsingSelector:@selector(compare:)] isEqual:
           [[tb componentsSeparatedByString:@"\n"] sortedArrayUsingSelector:@selector(compare:)]], "the same notes for the tutor");

    // A file gone from here goes from Sync Out, then from the Mac's folder,
    // and only that.
    [fm removeItemAtPath:[appA stringByAppendingPathComponent:@"Say/Recordings/2026-09.m4a"] error:NULL];
    [a stage];
    r = [a publish];
    CHECK([r ok] && [r changed] && [Capture(base, lastPaths) isEqualToString:@"Russian/Sync/mac-pro/Recordings/2026-09.m4a"],
          "a deleted file leaves the remote folder: %s", [Capture(base, lastPaths) UTF8String]);
    CHECK(![fm fileExistsAtPath:[studyA stringByAppendingPathComponent:@"Russian/Sync/mac-pro/Recordings/2026-09.m4a"]] &&
          [fm fileExistsAtPath:[studyA stringByAppendingPathComponent:@"Russian/Sync/macbook/Recordings/2026-09.m4a"]] &&
          [fm fileExistsAtPath:[studyA stringByAppendingPathComponent:@"Russian/Reports/r.txt"]], "the other Mac's folder and the reports stay");

    // A race: the MacBook's push lands between the Mac Pro's fetch and push.
    // The Mac Pro fetches again and builds on it.
    [[NSString stringWithFormat:@"cd '%@' && %@ pull -q --ff-only && echo raced >> Russian/Sync/macbook/Islands.txt && "
      @"%@ commit -q -am 'the MacBook, first' && %@ push -q origin HEAD:main\n", studyB, g, g, g]
        writeToFile:race atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSMutableDictionary *st = [[stA mutableCopy] autorelease];
    [st setObject:@"raced" forKey:@"futureKey"];
    [st writeToFile:[appA stringByAppendingPathComponent:@"State.plist"] atomically:YES];
    [a stage];
    r = [a publish];
    CHECK(![fm fileExistsAtPath:race], "(the MacBook did push first)");
    CHECK([r ok] && [r changed], "a race with the other Mac's push resolves: %s / %s", [[r summary] UTF8String], [[r output] UTF8String]);
    CHECK([Capture(base, [NSString stringWithFormat:@"%@ --git-dir='%@' log -1 --format=%%s main~1", g, origin]) isEqualToString:@"the MacBook, first"] &&
          [Capture(base, lastPaths) isEqualToString:@"Russian/Sync/mac-pro/State.plist"], "on top of the other Mac's commit, its own folder only");
    CHECK(Has(Text([studyA stringByAppendingPathComponent:@"Russian/Sync/macbook/Islands.txt"]), @"raced") &&
          [Capture(studyA, [NSString stringWithFormat:@"%@ status --porcelain", g]) length] == 0, "and the clone has both, clean");

    // A key that can only read: the clone stays exactly as it was.
    Run(base, @"printf '#!/bin/sh\\necho \"ERROR: The key you are authenticating with has been marked as read only.\" >&2\\nexit 1\\n' > origin.git/hooks/pre-receive && chmod +x origin.git/hooks/pre-receive");
    [st setObject:@"read only" forKey:@"futureKey"];
    [st writeToFile:[appA stringByAppendingPathComponent:@"State.plist"] atomically:YES];
    [a stage];
    head = Capture(studyA, [NSString stringWithFormat:@"%@ rev-parse HEAD", g]);
    r = [a publish];
    CHECK(![r ok] && [r readOnly] && Has([r summary], @"can only read"), "a read-only key: %s", [[r summary] UTF8String]);
    CHECK([Capture(studyA, [NSString stringWithFormat:@"%@ rev-parse HEAD", g]) isEqualToString:head] &&
          [Capture(studyA, [NSString stringWithFormat:@"%@ status --porcelain", g]) length] == 0, "and the clone is exactly as it was");
    Run(base, @"rm origin.git/hooks/pre-receive");
    r = [a publish];
    CHECK([r ok] && [r changed], "it goes once the key can write");

    CHECK(![[RSSyncFolder publish:[a outFolder] host:@"Mac Pro" folder:studyA] ok] &&
          ![[RSSyncFolder publish:[a outFolder] host:@"../reports" folder:studyA] ok], "a name that isn't a Mac's folder is refused");
    CHECK(![[RSSyncFolder publish:Temp(@"no-such-folder") host:@"mac-pro" folder:studyA] ok], "no staging folder: nothing is sent");
    [[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObject:@"" forKey:@"GitPath"]];
    Run(Temp(@""), @"rm -rf sync-git git-1.9-sync race.sh git-calls.txt");
}

static void TestSync(NSString *fixtures)
{
    TestSyncNames();
    TestSyncMerge(fixtures);
    TestSyncFiles(fixtures);
    TestSyncRealGit(fixtures);
}
