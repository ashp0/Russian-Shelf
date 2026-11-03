#import "RSController.h"
#import "RSLibrary.h"
#import "RSShelf.h"
#import "RSSubtitles.h"
#import "RSSync.h"
#import "RSSyncManager.h"
#import "RSReport.h"
#import "RSDate.h"
#import "RSLines.h"
#import "RSClip.h"
#import "RSDictionary.h"
#import "RSClips.h"
#import "RSSay.h"
#import "RSReading.h"

static const NSTimeInterval RSRefreshEvery = 60 * 60;
static const NSTimeInterval RSDayCheckEvery = 5 * 60;

NSString *RSDayText(long day)
{
    static NSString *const weekdays[7] = { @"Sunday", @"Monday", @"Tuesday", @"Wednesday", @"Thursday", @"Friday", @"Saturday" };
    static NSString *const months[12] = { @"January", @"February", @"March", @"April", @"May", @"June", @"July",
                                          @"August", @"September", @"October", @"November", @"December" };
    int y, m, d;
    RSCivilFromDays(day, &y, &m, &d);
    return [NSString stringWithFormat:@"%@, %@ %d", weekdays[RSWeekday(day)], months[m - 1], d];
}

static NSString *RSTimeText(time_t t)
{
    struct tm tm;
    char buffer[32];
    localtime_r(&t, &tm);
    strftime(buffer, sizeof buffer, "%l:%M %p", &tm);
    return [[NSString stringWithUTF8String:buffer] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

@interface RSController () {
    NSWindow *_window;
    RSShelfView *_shelfView;
    RSStatusBar *_statusBar;
    RSLibrary *_library;
    RSDownloader *_downloader;
    RSPlayer *_player;
    RSLines *_lines;
    RSReview *_review;
    RSSay *_say;
    RSSayWindow *_sayWindow;
    RSReadingWindow *_readingWindow;
    RSSyncManager *_sync;               // sync between the Macs, from the first pull
    NSString *_studyFolder;
    NSMutableDictionary *_progress;     // id -> NSNumber, while downloading
    NSMutableDictionary *_problems;     // id -> why the last try failed
    NSMutableDictionary *_thumbnails;   // id -> NSImage
    NSString *_syncSummary, *_reportNote, *_testingStatus;
    NSDictionary *_kinds;               // id -> kind, from Russian/history.txt
    RSDictionary *_dictionary;          // the bundled one, or one set for the shots
    BOOL _syncProblem, _testingProblem, _refreshing, _pushing, _watchChanged;
    time_t _checkedAt;
    NSTimer *_refreshTimer, *_dayTimer;
}
@end

@implementation RSController

- (id)initWithLibrary:(RSLibrary *)library studyFolder:(NSString *)studyFolder
{
    if (!(self = [super init])) return nil;
    _library = library ? [library retain] : [[RSLibrary alloc] initWithFolder:[RSLibrary defaultFolder]];
    NSString *chosen = [[NSUserDefaults standardUserDefaults] stringForKey:@"StudyFolder"];
    _studyFolder = [(studyFolder ?: ([chosen length] ? [chosen stringByExpandingTildeInPath]
                                                     : [NSHomeDirectory() stringByAppendingPathComponent:@"Study"])) copy];
    _progress = [[NSMutableDictionary alloc] init];
    _problems = [[NSMutableDictionary alloc] init];
    _thumbnails = [[NSMutableDictionary alloc] init];
    _downloader = [[RSDownloader alloc] initWithLibrary:_library tools:[RSTools bundled]];
    [_downloader setDelegate:self];
    _lines = [[RSLines alloc] initWithFolder:[[_library folder] stringByAppendingPathComponent:@"Lines"]];
    _say = [[RSSay alloc] initWithFolder:[[_library folder] stringByAppendingPathComponent:RSSayFolderName]];
    return self;
}

- (void)dealloc
{
    [_refreshTimer invalidate];
    [_dayTimer invalidate];
    [_downloader setDelegate:nil];
    [_downloader release];
    [_window release];
    [_shelfView release];
    [_statusBar release];
    [_library release];
    [_player release];
    [_review setDelegate:nil];
    [_review release];
    [_sayWindow setDelegate:nil];
    [_sayWindow release];
    [_readingWindow setDelegate:nil];
    [_readingWindow release];
    [_say release];
    [_lines release];
    [_sync release];
    [_studyFolder release];
    [_progress release];
    [_problems release];
    [_thumbnails release];
    [_syncSummary release];
    [_reportNote release];
    [_testingStatus release];
    [_kinds release];
    [_dictionary release];
    [super dealloc];
}

- (NSWindow *)window { return _window; }
- (RSShelfView *)shelfView { return _shelfView; }
- (RSPlayer *)player { return _player; }
- (RSLibrary *)library { return _library; }
- (RSLines *)lines { return _lines; }
- (RSReview *)review { return _review; }
- (RSSay *)say { return _say; }
- (RSSayWindow *)sayWindow { return _sayWindow; }
- (RSReadingWindow *)readingWindow { return _readingWindow; }

// ---- Launch -------------------------------------------------------------------

- (void)applicationDidFinishLaunching:(NSNotification *)n
{
    [self buildMenus];
    [self showWindow];
    [self advanceDay];
    [self refresh:nil];
    _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:RSRefreshEvery target:self selector:@selector(refresh:)
                                                   userInfo:nil repeats:YES];
    _dayTimer = [NSTimer scheduledTimerWithTimeInterval:RSDayCheckEvery target:self selector:@selector(advanceDay)
                                               userInfo:nil repeats:YES];
    // Neither needs the minute: OS X may run them with other wakeups.
    [_refreshTimer setTolerance:RSRefreshEvery / 12];
    [_dayTimer setTolerance:RSDayCheckEvery / 5];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(didWake:)
                                                               name:NSWorkspaceDidWakeNotification object:nil];
}

- (void)didWake:(NSNotification *)n
{
    // The network takes a moment to come back after sleep.
    [self performSelector:@selector(refresh:) withObject:nil afterDelay:30];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)visible
{
    if (!visible) [_window makeKeyAndOrderFront:nil];
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)n
{
    [_player close];
    [_review close];
    [_sayWindow close];
    [_readingWindow close];
    [_downloader cancel];
    [_library save];
    [_lines save];
}

- (void)showWindow
{
    if (_window == nil) {
        NSSize size = [RSStyle shelfWindowSize];
        _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, size.width, size.height)
            styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask
              backing:NSBackingStoreBuffered defer:YES];
        [_window setTitle:@"Shelf"];
        [_window setReleasedWhenClosed:NO];
        [_window setMinSize:[RSStyle shelfWindowMinSize]];
        [_window setBackgroundColor:[RSStyle windowBackground]];
        [_window setDelegate:self];
        NSView *content = [_window contentView];
        NSRect b = [content bounds];
        CGFloat bar = [RSStyle statusBarHeight];
        NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, bar, NSWidth(b), NSHeight(b) - bar)] autorelease];
        [scroll setVerticalScroller:[[[RSScroller alloc] initWithFrame:NSMakeRect(0, 0, 15, 100)] autorelease]];
        [scroll setHasVerticalScroller:YES];
        [scroll setAutohidesScrollers:YES];
        [scroll setBorderType:NSNoBorder];
        [scroll setDrawsBackground:YES];
        [scroll setBackgroundColor:[RSStyle windowBackground]];
        [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        _shelfView = [[RSShelfView alloc] initWithFrame:[[scroll contentView] bounds]];
        [_shelfView setAutoresizingMask:NSViewWidthSizable];
        [_shelfView setDelegate:self];
        [scroll setDocumentView:_shelfView];
        [content addSubview:scroll];
        _statusBar = [[RSStatusBar alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(b), bar)];
        [_statusBar setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
        [content addSubview:_statusBar];
        [_window center];
        [_window setFrameAutosaveName:@"Shelf"];
        [_window setInitialFirstResponder:_shelfView];
    }
    [self reloadRows];
    [self updateStatus];
    [_window makeKeyAndOrderFront:nil];
    [_window makeFirstResponder:_shelfView];
}

// ---- The round ----------------------------------------------------------------

- (NSString *)shelfFilePath
{
    return [_studyFolder stringByAppendingPathComponent:@"Russian/shelf.signed"];
}

- (NSString *)readingFilePath
{
    return [_studyFolder stringByAppendingPathComponent:@"Russian/reading.signed"];
}

- (void)refresh:(id)sender
{
    if (_refreshing) return;
    _refreshing = YES;
    [self updateStatus];
    NSString *folder = [[_studyFolder copy] autorelease];
    BOOL repository = [RSSync isRepository:folder];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        RSSyncResult *result = repository ? [[RSSync pullFolder:folder] retain] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishRefresh:result repository:repository];
            [result release];
        });
        [pool drain];
    });
}

- (void)finishRefresh:(RSSyncResult *)result repository:(BOOL)repository
{
    _refreshing = NO;
    _checkedAt = RSNowTime();
    [_syncSummary release];
    _syncSummary = nil;
    _syncProblem = NO;
    BOOL folderThere = [[NSFileManager defaultManager] fileExistsAtPath:_studyFolder];
    if (result && ![result ok]) {
        _syncSummary = [[result summary] copy];
        _syncProblem = YES;
    } else if (!folderThere) {
        _syncSummary = [[NSString stringWithFormat:@"%@ isn’t here yet.", [_studyFolder stringByAbbreviatingWithTildeInPath]] copy];
        _syncProblem = YES;
    }

    [self loadKinds];
    NSData *file = [NSData dataWithContentsOfFile:[self shelfFilePath]];
    if (file) {
        RSShelf *before = [[[_library current] retain] autorelease];
        RSOffer offer = [_library offerShelfFile:file today:RSToday()];
        if (offer == RSOfferTaken && before && ![[before fingerprint] isEqualToString:[[_library current] fingerprint]])
            [self queueReportFor:before];       // last word on the shelf that just went
    }
    [self takeSealedSubtitles];
    NSData *readings = [NSData dataWithContentsOfFile:[self readingFilePath]];
    if (readings) [_library offerReadingFile:readings today:RSToday()];
    [self advanceDay];
    [self reloadRows];
    [self updateStatus];
    [self startDownloads];
    [self pushReports];
    if (result && [result ok]) [self syncWithOtherMacs];
}

// Subtitles the skill made for a video (Russian/Subtitles/<id>.vtt): taken
// only when the shelf seals their hash (RSLibrary.h).
- (void)takeSealedSubtitles
{
    NSString *folder = [_studyFolder stringByAppendingPathComponent:@"Russian/Subtitles"];
    BOOL any = NO;
    for (RSShelf *shelf in [NSArray arrayWithObjects:[_library current] ?: (id)[NSNull null], [_library pending] ?: (id)[NSNull null], nil]) {
        if ((id)shelf == [NSNull null]) continue;
        for (NSString *identifier in [shelf subtitleHashes]) {
            NSData *vtt = [NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:[identifier stringByAppendingPathExtension:@"vtt"]]];
            if (vtt && [_library takeMadeSubtitles:vtt for:identifier]) any = YES;
        }
    }
    // An open player goes on with the track it has; the next opening reads the made one.
    (void)any;
}

// Which kind each video is, from the MacBook's history.txt (the sealed list
// may carry it too; the list's word wins, then history, then a guess from
// the channel and title).
- (void)loadKinds
{
    NSString *text = [NSString stringWithContentsOfFile:[_studyFolder stringByAppendingPathComponent:@"Russian/history.txt"]
                                               encoding:NSUTF8StringEncoding error:NULL];
    [_kinds release];
    _kinds = [RSKindsFromHistory(text) copy];
}

- (void)fillKinds
{
    [[_library current] fillKinds:_kinds];
    [[_library pending] fillKinds:_kinds];
}

// A shelf that arrived early becomes this week's on its start day.
- (void)advanceDay
{
    RSShelf *replaced = nil;
    if ([_library advanceReadingToDay:RSToday()]) [self reloadRows];
    if ([_library advanceToDay:RSToday() replaced:&replaced]) {
        if (replaced) [self queueReportFor:replaced];
        [self removeLeftovers];
        [self reloadRows];
        [self updateStatus];
        [self startDownloads];
        [self pushReports];
    }
}

- (void)removeLeftovers
{
    if ([[_library removeLeftovers] count]) {
        [_thumbnails removeAllObjects];
        [self reloadRows];
    }
}

// ---- Downloads ----------------------------------------------------------------

- (void)startDownloads
{
    if ([_downloader busy]) return;
    [self removeLeftovers];
    NSArray *wanted = [_library identifiersToDownload];
    if ([wanted count] == 0) return;
    for (NSString *identifier in wanted) [_progress setObject:[NSNumber numberWithDouble:0] forKey:identifier];
    [_downloader downloadIdentifiers:wanted];
    [self reloadRows];
    [self updateStatus];
}

- (NSString *)downloader:(RSDownloader *)downloader stillWanted:(NSString *)identifier
{
    return [[_library identifiersToDownload] containsObject:identifier] ? [_library stagingFolder:identifier] : nil;
}

- (void)downloader:(RSDownloader *)downloader progress:(double)fraction video:(NSString *)identifier
{
    [_progress setObject:[NSNumber numberWithDouble:MAX(0.001, fraction)] forKey:identifier];
    [_problems removeObjectForKey:identifier];
    for (RSRowModel *row in [_shelfView rows]) {
        if (![[row identifier] isEqualToString:identifier]) continue;
        [row setState:RSRowDownloading];
        [row setProgress:fraction];
        NSUInteger i = [[_shelfView rows] indexOfObject:row];
        [_shelfView setNeedsDisplayInRect:[_shelfView rectOfRow:(NSInteger)i]];
    }
}

- (void)downloader:(RSDownloader *)downloader finishedVideo:(NSString *)identifier problem:(NSString *)problem
{
    [_progress removeObjectForKey:identifier];
    if (problem) [_problems setObject:problem forKey:identifier];
    else [_problems removeObjectForKey:identifier];
    [_thumbnails removeObjectForKey:identifier];
    if ([_library isCurrentComplete]) [self removeLeftovers];
    [self reloadRows];
    [self updateStatus];
}

- (void)downloaderFinished:(RSDownloader *)downloader
{
    [_progress removeAllObjects];
    [self removeLeftovers];
    [self reloadRows];
    [self updateStatus];
}

- (void)setDownload:(NSString *)identifier progress:(double)progress problem:(NSString *)problem
{
    if (problem) [_problems setObject:problem forKey:identifier];
    else [_progress setObject:[NSNumber numberWithDouble:progress] forKey:identifier];
    [self reloadRows];
}

// ---- The shelf ------------------------------------------------------------------

- (NSImage *)thumbnailFor:(NSString *)identifier
{
    NSImage *image = [_thumbnails objectForKey:identifier];
    if (image == nil && [_library isDownloaded:identifier]) {
        image = [[[NSImage alloc] initWithContentsOfFile:[_library thumbnailPath:identifier]] autorelease];
        if (image) [_thumbnails setObject:image forKey:identifier];
    }
    return image;
}

// The videos grouped by kind: easy stories first, then natural speech, then
// fast speech; within a group, Claude's order.
- (NSArray *)videosGrouped:(RSShelf *)shelf
{
    NSMutableArray *videos = [NSMutableArray array];
    for (NSString *kind in RSKinds()) [videos addObjectsFromArray:[shelf videosOfKind:kind]];
    [videos addObjectsFromArray:[shelf videosOfKind:nil]];
    return videos;
}

- (NSArray *)deskLines
{
    RSShelf *shelf = [_library current];
    if (shelf == nil) return [NSArray array];
    NSMutableArray *lines = [NSMutableArray array];
    NSUInteger due = [[_lines dueOn:RSToday()] count];
    if (due) {
        RSDeskLine *cards = [[[RSDeskLine alloc] init] autorelease];
        [cards setLabel:@"Cards"];
        [cards setText:[NSString stringWithFormat:@"%lu to hear again", (unsigned long)due]];
        [cards setKey:@"⌘L"];
        [cards setAction:RSDeskCards];
        [lines addObject:cards];
    }
    RSClipPlan *clip = [self todaysClip];
    NSDictionary *today = [_library clipOnDay:RSToday()];
    NSUInteger passes = [[today objectForKey:@"passes"] unsignedIntegerValue];
    if (clip && passes < 3) {
        RSDeskLine *line = [[[RSDeskLine alloc] init] autorelease];
        [line setLabel:@"Clip"];
        NSString *title = [[shelf videoWithIdentifier:[clip video]] displayTitle] ?: @"";
        [line setText:passes ? [NSString stringWithFormat:@"%@, %@ (pass %lu of 3 done)", title, RSClipSpan([clip start], [clip end]), (unsigned long)passes]
                              : [NSString stringWithFormat:@"%@, %@", title, RSClipSpan([clip start], [clip end])]];
        [line setKey:@"⌘K"];
        [line setIdentifier:[clip video]];
        [line setAction:RSDeskClip];
        [lines addObject:line];
    } else if (clip == nil && !today) {
        RSVideo *automatic = [self videoWithOnlyAutomaticCaptions];
        if (automatic) {
            RSDeskLine *line = [[[RSDeskLine alloc] init] autorelease];
            [line setLabel:@"Clip"];
            [line setText:[NSString stringWithFormat:@"none: %@ has only YouTube’s automatic captions, which don’t match the speech", [automatic displayTitle]]];
            [line setKey:@""];
            [line setAction:RSDeskClip];
            [lines addObject:line];
        }
    }
    RSReadingItem *reading = [_library readingForDay:RSToday()];
    NSUInteger reads = [[[_library readingProgressFor:[reading key]] objectForKey:@"reads"] unsignedIntegerValue];
    if (reading && reads < 3) {
        RSDeskLine *line = [[[RSDeskLine alloc] init] autorelease];
        [line setLabel:@"Read"];
        NSString *what = [reading poem] ? @"the week’s poem" : @"today’s story";
        [line setText:reads ? [NSString stringWithFormat:@"%@, %@ (read %lu of 3 done)", RSWithoutStress([reading title]), what, (unsigned long)reads]
                            : [NSString stringWithFormat:@"%@, %@, three reads", RSWithoutStress([reading title]), what]];
        [line setKey:@"⌘D"];
        [line setAction:RSDeskRead];
        [lines addObject:line];
    }
    NSDictionary *said = [_library sayOnDay:RSToday()];
    NSString *topic = [self todaysTopic];
    if (topic && [[said objectForKey:@"passes"] unsignedIntegerValue] < 3) {
        RSDeskLine *line = [[[RSDeskLine alloc] init] autorelease];
        [line setLabel:@"Say"];
        NSUInteger passes = [[said objectForKey:@"passes"] unsignedIntegerValue];
        [line setText:passes ? [NSString stringWithFormat:@"%@ (pass %lu of 3 done)", topic, (unsigned long)passes]
                              : [NSString stringWithFormat:@"%@, %@", topic, RSSayLengthsText([self sayLengthsSetting])]];
        [line setKey:@"⌘S"];
        [line setAction:RSDeskSay];
        [lines addObject:line];
    }
    NSString *next = [_library nextIdentifier];
    RSVideo *video = next ? [shelf videoWithIdentifier:next] : nil;
    if (video) {
        RSDeskLine *watch = [[[RSDeskLine alloc] init] autorelease];
        [watch setLabel:[lines count] ? @"Then watch" : @"Watch"];
        [watch setText:[_library isDownloaded:next] ? [video displayTitle]
                                                    : [[video displayTitle] stringByAppendingString:@" (downloading)"]];
        [watch setKey:@"Return"];
        [watch setIdentifier:next];
        [watch setAction:RSDeskWatch];
        [lines addObject:watch];
    }
    return lines;
}

- (void)reloadRows
{
    if (_shelfView == nil) return;
    [self fillKinds];
    RSShelf *shelf = [_library current];
    NSString *next = [_library nextIdentifier];
    NSMutableArray *rows = [NSMutableArray array];
    for (RSVideo *video in [self videosGrouped:shelf]) {
        NSString *identifier = [video identifier];
        RSWatch *watch = [_library watchFor:identifier];
        RSRowModel *row = [[[RSRowModel alloc] init] autorelease];
        [row setIdentifier:identifier];
        [row setTitle:[video displayTitle]];
        [row setChannel:[video channel]];
        [row setKind:[video kind]];
        [row setThumbnail:[self thumbnailFor:identifier]];
        [row setDuration:[watch duration]];
        [row setWatched:[watch furthest]];
        [row setFinished:[watch finished]];
        [row setNext:[identifier isEqualToString:next]];
        if ([_library isDownloaded:identifier]) {
            [row setState:RSRowReady];
        } else if ([_problems objectForKey:identifier]) {
            [row setState:RSRowFailed];
            [row setNote:[_problems objectForKey:identifier]];
        } else if ([[_progress objectForKey:identifier] doubleValue] > 0) {
            [row setState:RSRowDownloading];
            [row setProgress:[[_progress objectForKey:identifier] doubleValue]];
        } else {
            [row setState:RSRowWaiting];
        }
        [rows addObject:row];
    }
    [_shelfView setDeskLines:[self deskLines]];
    [_shelfView setRows:rows];
    if (shelf) {
        [_shelfView setTitle:@"This week’s shelf"];
        NSMutableString *sub = [NSMutableString stringWithFormat:@"From %@, chosen by Claude.", RSDayText([shelf start])];
        if ([_library pending]) [sub appendFormat:@" Next shelf from %@.", RSDayText([[_library pending] start])];
        [_shelfView setSubtitle:sub];
    }
    [_shelfView setEmptyTitle:@"No shelf yet"];
    [_shelfView setEmptyMessage:[_library notice] ?:
        [NSString stringWithFormat:@"Claude puts the week’s videos in %@ on the MacBook. This Mac looks for them every hour.",
         [[self shelfFilePath] stringByAbbreviatingWithTildeInPath]]];
}

- (void)updateStatus
{
    if (_statusBar == nil) return;
    if (_testingStatus) {
        [_statusBar setText:_testingStatus];
        [_statusBar setProblem:_testingProblem];
        return;
    }
    NSMutableArray *parts = [NSMutableArray array];
    BOOL problem = NO;
    if ([_library notice] && [_library current]) {
        [parts addObject:[[_library notice] stringByAppendingString:@" Keeping this week’s shelf."]];
        problem = YES;
    } else if (_refreshing) {
        [parts addObject:@"Looking for a new shelf…"];
    } else if (_syncSummary) {
        [parts addObject:_syncSummary];
        problem = _syncProblem;
    } else if (_checkedAt) {
        [parts addObject:[NSString stringWithFormat:@"Looked for a new shelf at %@.", RSTimeText(_checkedAt)]];
    }
    NSUInteger downloading = [_progress count];
    if (downloading) [parts addObject:[NSString stringWithFormat:@"Downloading %lu video%s.", (unsigned long)downloading, downloading == 1 ? "" : "s"]];
    if (_reportNote) [parts addObject:_reportNote];
    if ([_sync note]) [parts addObject:[_sync note]];
    [_statusBar setText:[parts componentsJoinedByString:@"  "]];
    [_statusBar setProblem:problem];
}

- (void)setStatusForTesting:(NSString *)text problem:(BOOL)problem
{
    [_testingStatus release];
    _testingStatus = [text copy];
    _testingProblem = problem;
    [self updateStatus];
}

- (void)shelfView:(RSShelfView *)view choseRow:(RSRowModel *)row
{
    [self playVideo:[row identifier]];
}

- (void)shelfView:(RSShelfView *)view choseDeskLine:(RSDeskLine *)line
{
    switch ([line action]) {
        case RSDeskCards: [self showLines]; break;
        case RSDeskWatch: if (![self playVideo:[line identifier]]) NSBeep(); break;
        case RSDeskClip:  if (![self startTodaysClip]) NSBeep(); break;
        case RSDeskSay:   [self showSay]; break;
        case RSDeskRead:  if (![self showReading]) NSBeep(); break;
    }
}

// ---- Playing ------------------------------------------------------------------------

- (RSDictionary *)dictionary
{
    return _dictionary ?: [RSDictionary bundled];
}

- (void)setDictionary:(RSDictionary *)dictionary
{
    [_dictionary release];
    _dictionary = [dictionary retain];
}

- (RSPlayer *)playVideo:(NSString *)identifier
{
    RSVideo *video = [[_library current] videoWithIdentifier:identifier];
    if (video == nil || ![_library isDownloaded:identifier]) return nil;
    if (_player) {
        if ([[_player identifier] isEqualToString:identifier]) { [[_player window] makeKeyAndOrderFront:nil]; return _player; }
        [_player close];
    }
    RSWatch *watch = [_library watchFor:identifier];
    RSSubtitles *subtitles = [_library subtitlesFor:identifier];
    _player = [[RSPlayer alloc] initWithIdentifier:identifier title:[video displayTitle] movie:[_library moviePath:identifier]
                                         subtitles:subtitles position:[watch position] furthest:[watch furthest]
                                          duration:[watch duration]];
    [_player setDelegate:self];
    [_player setFelt:[_library feltFor:identifier] want:[_library wantFor:identifier]];
    [_player setKind:[video kind] firstViewing:![watch finished]];
    [_player setRate:[_library rateFor:identifier]];
    [_player setDictionary:[self dictionary]];
    [_player show];
    return _player;
}

- (void)player:(RSPlayer *)player position:(double)position furthest:(double)furthest duration:(double)duration
{
    RSWatch *before = [_library watchFor:[player identifier]];
    BOOL finishedNow = [_library recordPosition:position furthest:furthest duration:duration for:[player identifier]];
    if (furthest > [before furthest] + 1) _watchChanged = YES;
    [_library save];
    if (finishedNow) {
        [self queueReportFor:[_library current]];
        [self pushReports];
    }
    [self reloadRows];
}

- (void)player:(RSPlayer *)player helped:(RSHelp)kind line:(RSLine *)line
{
    [_library countHelp:kind for:[player identifier] line:[line text] start:[line start]];
    [_library save];
    _watchChanged = YES;
}

- (void)player:(RSPlayer *)player rateChanged:(float)rate
{
    [_library setRate:rate for:[player identifier]];
    [_library save];
    _watchChanged = YES;
}

- (void)player:(RSPlayer *)player felt:(NSString *)felt want:(NSString *)want
{
    [_library setFelt:felt want:want for:[player identifier]];
    [_library save];
    _watchChanged = YES;
}

- (NSString *)player:(RSPlayer *)player keepLine:(RSLine *)line before:(RSLine *)before
{
    NSString *identifier = [player identifier];
    NSString *problem = nil;
    RSKeptLine *kept = [_lines keepText:[line text] before:[before text] video:identifier
                                  title:[[[_library current] videoWithIdentifier:identifier] title]
                                  start:[line start] end:[line end] today:RSToday() problem:&problem];
    if (kept == nil) return problem;
    [_lines save];
    [_library countHelp:RSHelpKept for:identifier];
    [_library save];
    _watchChanged = YES;
    // The sound is cut in the background; without it the line is still kept.
    RSCutClip([_library moviePath:identifier], [line start], [line end], [_lines soundPath:kept], ^(BOOL ok, NSString *why) {
        if (!ok) NSLog(@"Shelf: %@", why);
    });
    [self reloadRows];
    return @"Kept. It comes back tomorrow (⌘L).";
}

- (NSString *)player:(RSPlayer *)player keepWord:(NSString *)word entry:(RSDictionaryEntry *)entry
                line:(RSLine *)line before:(RSLine *)before
{
    NSString *identifier = [player identifier];
    NSString *problem = nil;
    RSKeptLine *kept = [_lines keepWord:word lemma:[entry accented] gloss:[entry gloss] rank:[entry rank]
                                 inLine:[line text] before:[before text] video:identifier
                                  title:[[[_library current] videoWithIdentifier:identifier] displayTitle]
                                  start:[line start] end:[line end] today:RSToday() problem:&problem];
    if (kept == nil) return problem;
    [_lines save];
    [_library countHelp:RSHelpKept for:identifier];
    [_library save];
    _watchChanged = YES;
    // The line's sound, once: a kept line may have cut it already.
    NSString *sound = [_lines soundPath:kept];
    if (![[NSFileManager defaultManager] fileExistsAtPath:sound])
        RSCutClip([_library moviePath:identifier], [line start], [line end], sound, ^(BOOL ok, NSString *why) {
            if (!ok) NSLog(@"Shelf: %@", why);
        });
    [self reloadRows];
    return [NSString stringWithFormat:@"Kept “%@”. It comes back tomorrow (⌘L).", word];
}

- (void)playerClosed:(RSPlayer *)player
{
    if (player != _player) return;
    [_player setDelegate:nil];
    [_player autorelease];
    _player = nil;
    if (_watchChanged && [_library current]) {
        [self queueReportFor:[_library current]];
        [self pushReports];
    }
    [self reloadRows];
    [_window makeKeyAndOrderFront:nil];
}

// ---- Today's clip --------------------------------------------------------------------

// Today's clip: the one begun today, else a new one from the week's fast video
// (or the natural one, or any) that is downloaded and has subtitles. Once
// today's is done, another (the next stretch): shadowing whenever the owner
// wants it.
- (RSClipPlan *)todaysClip
{
    RSShelf *shelf = [_library current];
    if (shelf == nil) return nil;
    NSDictionary *today = [_library clipOnDay:RSToday()];
    if (today && [[today objectForKey:@"passes"] unsignedIntegerValue] < 3) {
        RSClipPlan *plan = [[[RSClipPlan alloc] init] autorelease];
        [plan setVideo:[today objectForKey:@"video"]];
        [plan setStart:[[today objectForKey:@"start"] doubleValue]];
        [plan setEnd:[[today objectForKey:@"end"] doubleValue]];
        return plan;
    }
    NSMutableArray *candidates = [NSMutableArray array];
    for (NSString *kind in [NSArray arrayWithObjects:RSKindFast, RSKindNatural, RSKindEasy, nil])
        [candidates addObjectsFromArray:[shelf videosOfKind:kind]];
    [candidates addObjectsFromArray:[shelf videosOfKind:nil]];
    for (RSVideo *video in candidates) {
        NSString *identifier = [video identifier];
        if (![_library isDownloaded:identifier]) continue;
        RSSubtitles *subtitles = [_library subtitlesFor:identifier];
        // Never a clip on YouTube's automatic captions: their lines aren't what
        // anyone said, so read and say-along passes would be on the wrong words.
        if ([[subtitles lines] count] == 0 || [subtitles automatic]) continue;
        RSClipPlan *plan = RSChooseClip(identifier, subtitles, [_library helpedLinesFor:identifier], [_library clipsFor:identifier]);
        if (plan) return plan;
    }
    return nil;
}

// The downloaded video with lines that has only automatic captions, when no
// clip can be made at all: the desk card says why.
- (RSVideo *)videoWithOnlyAutomaticCaptions
{
    RSShelf *shelf = [_library current];
    for (NSString *kind in [NSArray arrayWithObjects:RSKindFast, RSKindNatural, nil])
        for (RSVideo *video in [shelf videosOfKind:kind])
            if ([_library isDownloaded:[video identifier]] && [[_library subtitlesKindFor:[video identifier]] isEqualToString:@"auto"])
                return video;
    return nil;
}

- (RSPlayer *)startTodaysClip
{
    RSClipPlan *plan = [self todaysClip];
    if (plan == nil) return nil;
    RSPlayer *player = [self playVideo:[plan video]];
    if (player == nil) return nil;
    if (![_library clipOnDay:RSToday()]) {
        [_library recordClip:[plan video] start:[plan start] end:[plan end] passes:0 day:RSToday()];
        [_library save];
    }
    [player startClipFrom:[plan start] to:[plan end]];
    [self reloadRows];
    return player;
}

- (void)startTodaysClip:(id)sender
{
    if (![self startTodaysClip]) NSBeep();
}

- (void)player:(RSPlayer *)player clipFrom:(double)start to:(double)end passes:(NSUInteger)passes
{
    [_library recordClip:[player identifier] start:start end:end passes:passes day:RSToday()];
    [_library save];
    _watchChanged = YES;
    [self reloadRows];
}

// ---- Say ---------------------------------------------------------------------------------

- (NSUInteger)sayLengthsSetting
{
    NSInteger n = [[NSUserDefaults standardUserDefaults] integerForKey:@"SayLengths"];
    return n < 0 || n >= (NSInteger)RSSaySettings ? 0 : (NSUInteger)n;
}

// The retell topics today: a reading read three times today (with its
// lesson, for the fourth pass), then a story finished today.
- (NSArray *)retellTopicsWithLessons:(NSMutableDictionary *)lessons
{
    NSMutableArray *topics = [NSMutableArray array];
    NSString *key = [_library readingFinishedOnDay:RSToday()];
    RSReadingItem *item = key ? [[_library reading] itemWithKey:key] : nil;
    if (item) {
        NSString *topic = [NSString stringWithFormat:@"Перескажи: «%@»", RSWithoutStress([item title])];
        [topics addObject:topic];
        if (lessons) [lessons setObject:[item lesson] forKey:topic];
    }
    RSShelf *shelf = [_library current];
    for (RSVideo *video in [shelf videos]) {
        RSWatch *watch = [_library watchFor:[video identifier]];
        if ([watch finished] && [_library finishedOnDay:RSToday() video:[video identifier]])
            [topics addObject:[NSString stringWithFormat:@"Перескажи: «%@»", [video displayTitle]]];
    }
    return topics;
}

// Today's topic: what was begun today; else a reading or a story finished
// today, retold; otherwise the day's island.
- (NSString *)todaysTopic
{
    NSDictionary *said = [_library sayOnDay:RSToday()];
    if ([[said objectForKey:@"island"] length]) return [said objectForKey:@"island"];
    NSArray *retell = [self retellTopicsWithLessons:nil];
    if ([retell count]) return [retell objectAtIndex:0];
    return [_say islandForDay:RSToday()];
}

- (RSSayWindow *)showSay
{
    if (_sayWindow && [_sayWindow today] != RSToday()) [_sayWindow close];
    if (_sayWindow == nil) {
        _sayWindow = [[RSSayWindow alloc] initWithSay:_say topic:[self todaysTopic] setting:[self sayLengthsSetting] today:RSToday()];
        [_sayWindow setDelegate:self];
    }
    NSMutableDictionary *lessons = [NSMutableDictionary dictionary];
    [_sayWindow setTopics:[self retellTopicsWithLessons:lessons]];
    [_sayWindow setLessons:lessons];
    [_sayWindow show];
    return _sayWindow;
}

// ---- Reading --------------------------------------------------------------------------

- (RSReadingWindow *)showReading
{
    RSReadingItem *item = [_library readingForDay:RSToday()];
    if (item == nil) return nil;
    if (_readingWindow && [_readingWindow today] != RSToday()) [_readingWindow close];
    if (_readingWindow == nil) {
        _readingWindow = [[RSReadingWindow alloc] initWithSet:[_library reading] item:item say:_say today:RSToday()];
        [_readingWindow setDelegate:self];
        [_readingWindow setDictionary:[self dictionary]];
    }
    [_readingWindow show];
    return _readingWindow;
}

- (void)showReading:(id)sender
{
    if (![self showReading]) NSBeep();
}

- (NSUInteger)readingWindow:(RSReadingWindow *)window readsOf:(RSReadingItem *)item
{
    return [[[_library readingProgressFor:[item key]] objectForKey:@"reads"] unsignedIntegerValue];
}

- (void)readingWindow:(RSReadingWindow *)window item:(RSReadingItem *)item finishedRead:(NSUInteger)n seconds:(double)seconds recorded:(BOOL)recorded
{
    [_library recordRead:[item key] title:RSWithoutStress([item title]) read:n seconds:seconds recorded:recorded day:RSToday()];
    [_library save];
    _watchChanged = YES;
    if (n >= 3 && [_library current]) { [self queueReportFor:[_library current]]; [self pushReports]; }
    [self reloadRows];
}

- (NSString *)readingWindow:(RSReadingWindow *)window keepWord:(NSString *)word entry:(RSDictionaryEntry *)entry
                   sentence:(NSString *)sentence item:(RSReadingItem *)item
{
    // The card's place in its "video" is the sentence's number, so the same
    // word in the same sentence is kept once.
    NSArray *sentences = [item sentences];
    NSUInteger index = 0;
    for (NSUInteger i = 0; i < [sentences count]; i++)
        if ([RSWithoutStress([sentences objectAtIndex:i]) isEqualToString:sentence]) { index = i + 1; break; }
    NSString *problem = nil;
    RSKeptLine *kept = [_lines keepWord:word lemma:[entry accented] gloss:[entry gloss] rank:[entry rank] inLine:sentence before:nil
                                  video:[item key] title:RSWithoutStress([item title]) start:(double)index end:0 today:RSToday() problem:&problem];
    if (kept == nil) return problem;
    [_lines save];
    _watchChanged = YES;
    [self reloadRows];
    return [NSString stringWithFormat:@"Kept “%@”. It comes back tomorrow (⌘L), to read aloud.", word];
}

- (void)readingWindowClosed:(RSReadingWindow *)window
{
    if (window != _readingWindow) return;
    [_readingWindow setDelegate:nil];
    [_readingWindow autorelease];
    _readingWindow = nil;
    [self reloadRows];
}

- (void)showSay:(id)sender { [self showSay]; }

- (void)showIslands:(id)sender
{
    RSSayWindow *w = [self showSay];
    if ([w state] != RSSayIslands) [w toggleIslands];
}

- (void)chooseSayLengths:(id)sender
{
    [[NSUserDefaults standardUserDefaults] setInteger:[sender tag] forKey:@"SayLengths"];
    [self reloadRows];
}

- (void)sayWindow:(RSSayWindow *)window finishedPass:(NSUInteger)pass topic:(NSString *)topic round:(NSUInteger)round recorded:(BOOL)recorded
{
    NSDictionary *said = [_library sayOnDay:RSToday()];
    BOOL wasRecorded = NO;
    if (round <= 1) wasRecorded = [[said objectForKey:@"recorded"] boolValue];
    else {
        NSArray *more = [[said objectForKey:@"more"] isKindOfClass:[NSArray class]] ? [said objectForKey:@"more"] : nil;
        if ([more count] >= round - 1) wasRecorded = [[[more objectAtIndex:round - 2] objectForKey:@"recorded"] boolValue];
    }
    [_library recordSayOnDay:RSToday() island:topic passes:pass recorded:recorded || wasRecorded round:round];
    [_library save];
    _watchChanged = YES;
    [self reloadRows];
}

- (void)sayWindowClosed:(RSSayWindow *)window
{
    if (window != _sayWindow) return;
    [_sayWindow setDelegate:nil];
    [_sayWindow autorelease];
    _sayWindow = nil;
    [self reloadRows];
}

// ---- Reports ------------------------------------------------------------------------

- (NSString *)outbox
{
    NSString *path = [[_library folder] stringByAppendingPathComponent:@"Outbox"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
    return path;
}

// One unsent report per shelf: a newer one replaces it.
- (void)queueReportFor:(RSShelf *)shelf
{
    if (shelf == nil) return;
    _watchChanged = NO;
    NSString *outbox = [self outbox];
    NSString *prefix = [NSString stringWithFormat:@"shelf-%@_", [shelf startText]];
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:outbox error:NULL])
        if ([name hasPrefix:prefix]) [[NSFileManager defaultManager] removeItemAtPath:[outbox stringByAppendingPathComponent:name] error:NULL];
    time_t now = RSNowTime();
    [RSReportTextWithNotes(shelf, _library, _lines, [_say tutorNotes], now) writeToFile:[outbox stringByAppendingPathComponent:RSReportName(shelf, now)]
                                         atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (void)pushReports
{
    if (_pushing || ![RSSync isRepository:_studyFolder]) return;
    NSString *outbox = [self outbox];
    NSMutableDictionary *reports = [NSMutableDictionary dictionary];
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:outbox error:NULL]) {
        NSString *text = [NSString stringWithContentsOfFile:[outbox stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:NULL];
        if (text && [RSSync isReportPath:[[RSSync reportsFolder] stringByAppendingPathComponent:name]]) [reports setObject:text forKey:name];
    }
    if ([reports count] == 0) return;
    _pushing = YES;
    NSString *folder = [[_studyFolder copy] autorelease];
    NSString *log = [[[_library folder] stringByAppendingPathComponent:@"Logs"] stringByAppendingPathComponent:@"report.log"];
    dispatch_async([RSSyncManager gitQueue], ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        RSSyncResult *result = [[RSSync pushReports:reports folder:folder] retain];
        // What git said, for when the summary isn't enough.
        [[NSFileManager defaultManager] createDirectoryAtPath:[log stringByDeletingLastPathComponent]
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        [[NSString stringWithFormat:@"%@\ngit: %@\n\n%@", [result summary], [RSSync gitPath], [result output]]
            writeToFile:log atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        dispatch_async(dispatch_get_main_queue(), ^{
            _pushing = NO;
            [_reportNote release];
            _reportNote = nil;
            if ([result ok]) {
                for (NSString *name in reports)
                    [[NSFileManager defaultManager] removeItemAtPath:[outbox stringByAppendingPathComponent:name] error:NULL];
            } else {
                _reportNote = [([result readOnly] ? @"What you watched waits here until this Mac’s key can write."
                                                  : [@"What you watched wasn’t sent: " stringByAppendingString:[result summary]]) copy];
            }
            [result release];
            [self updateStatus];
        });
        [pool drain];
    });
}

// ---- Sync between the Macs (RSSyncManager.h) ---------------------------------------

// After a pull: what the other Mac did comes in, then what this Mac did goes
// out. One round at a time; its gits wait their turn behind the reports'.
- (void)syncWithOtherMacs
{
    if (_sync == nil) _sync = [[RSSyncManager alloc] initWithAppFolder:[_library folder] studyFolder:_studyFolder];
    if ([_sync busy] || ![RSSync isRepository:_studyFolder]) return;
    [_sync setBusy:YES];
    RSSyncManager *sync = _sync;
    NSString *log = [[[_library folder] stringByAppendingPathComponent:@"Logs"] stringByAppendingPathComponent:@"sync.log"];
    dispatch_async([RSSyncManager gitQueue], ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *problem = nil;
        BOOL taken = [sync takeOtherHosts:&problem];
        [problem retain];
        dispatch_async(dispatch_get_main_queue(), ^{
            // What was done here is on disk before the merge reads it, and
            // nothing can be done in between: this is the main thread.
            [_library save];
            [_lines save];
            if (taken && [sync mergeInCards:_review == nil]) [self reloadAfterSync];
            [sync stage];
            dispatch_async([RSSyncManager gitQueue], ^{
                NSAutoreleasePool *inner = [[NSAutoreleasePool alloc] init];
                RSSyncResult *result = [[sync publish] retain];
                [[NSFileManager defaultManager] createDirectoryAtPath:[log stringByDeletingLastPathComponent]
                                          withIntermediateDirectories:YES attributes:nil error:NULL];
                [[NSString stringWithFormat:@"%@\n%@\ngit: %@\n\n%@", problem ?: @"", [result summary], [RSSync gitPath], [result output]]
                    writeToFile:log atomically:YES encoding:NSUTF8StringEncoding error:NULL];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [sync setBusy:NO];
                    // Only what went wrong, in a sentence; a read-only key
                    // is said once, by the reports' note if it's there.
                    if ([result ok] || ([result readOnly] && _reportNote)) [sync setNote:nil];
                    else if ([result readOnly]) [sync setNote:[result summary]];
                    else [sync setNote:[@"Not synced with the other Mac: " stringByAppendingString:[result summary]]];
                    [result release];
                    [problem release];
                    [self updateStatus];
                });
                [inner drain];
            });
        });
        [pool drain];
    });
}

// The merge changed the files here: read them again. The cards only when
// the Lines window hasn't got them (then they weren't merged).
- (void)reloadAfterSync
{
    if (_review == nil) {
        [_lines release];
        _lines = [[RSLines alloc] initWithFolder:[[_library folder] stringByAppendingPathComponent:@"Lines"]];
    }
    [_library reload];
    [self reloadRows];
}

// ---- Lines to hear again ----------------------------------------------------------

- (RSReview *)showLines
{
    if (_review && [_review today] != RSToday()) [_review close];       // left open overnight
    if (_review == nil) {
        _review = [[RSReview alloc] initWithLines:_lines today:RSToday()];
        [_review setDelegate:self];
    }
    [_review show];
    return _review;
}

- (void)showLines:(id)sender
{
    [self showLines];
}

- (void)reviewClosed:(RSReview *)review
{
    if (review != _review) return;
    [_review setDelegate:nil];
    [_review autorelease];
    _review = nil;
    [self reloadRows];
}

// ---- Menus --------------------------------------------------------------------------

static NSMenuItem *RSItem(NSMenu *menu, NSString *title, SEL action, NSString *key, NSUInteger mask, id target)
{
    NSMenuItem *item = [menu addItemWithTitle:title action:action keyEquivalent:key ?: @""];
    [item setKeyEquivalentModifierMask:mask];
    if (target) [item setTarget:target];
    return item;
}

static NSString *RSKey(unichar c)
{
    return [NSString stringWithCharacters:&c length:1];
}

- (void)buildMenus
{
    NSMenu *bar = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    NSUInteger cmd = NSCommandKeyMask;

    NSMenu *app = [[[NSMenu alloc] initWithTitle:@"Shelf"] autorelease];
    RSItem(app, @"About Shelf", @selector(orderFrontStandardAboutPanel:), nil, 0, NSApp);
    [app addItem:[NSMenuItem separatorItem]];
    RSItem(app, @"Hide Shelf", @selector(hide:), @"h", cmd, NSApp);
    RSItem(app, @"Hide Others", @selector(hideOtherApplications:), @"h", cmd | NSAlternateKeyMask, NSApp);
    RSItem(app, @"Show All", @selector(unhideAllApplications:), nil, 0, NSApp);
    [app addItem:[NSMenuItem separatorItem]];
    RSItem(app, @"Quit Shelf", @selector(terminate:), @"q", cmd, NSApp);

    NSMenu *shelf = [[[NSMenu alloc] initWithTitle:@"Shelf"] autorelease];
    RSItem(shelf, @"Show the Shelf", @selector(showShelf:), @"1", cmd, self);
    RSItem(shelf, @"Look for a New Shelf", @selector(refresh:), @"r", cmd, self);
    [shelf addItem:[NSMenuItem separatorItem]];
    RSItem(shelf, @"Cards", @selector(showLines:), @"l", cmd, self);
    RSItem(shelf, @"Today’s Clip", @selector(startTodaysClip:), @"k", cmd, self);
    RSItem(shelf, @"Reading", @selector(showReading:), @"d", cmd, self);
    RSItem(shelf, @"Say", @selector(showSay:), @"s", cmd, self);
    RSItem(shelf, @"Islands…", @selector(showIslands:), @"i", cmd, self);
    NSMenu *lengths = [[[NSMenu alloc] initWithTitle:@"Pass Lengths"] autorelease];
    for (NSUInteger i = 0; i < RSSaySettings; i++)
        [RSItem(lengths, RSSayLengthsText(i), @selector(chooseSayLengths:), nil, 0, self) setTag:(NSInteger)i];
    [[shelf addItemWithTitle:@"Pass Lengths" action:NULL keyEquivalent:@""] setSubmenu:lengths];

    // Shown for the keys; the player window takes them itself, before
    // AVPlayerView does.
    NSMenu *play = [[[NSMenu alloc] initWithTitle:@"Playback"] autorelease];
    [play setAutoenablesItems:YES];
    RSItem(play, @"Play or Pause", @selector(playPause:), @" ", 0, self);
    RSItem(play, @"Back 5 Seconds", @selector(back:), RSKey(NSLeftArrowFunctionKey), 0, self);
    RSItem(play, @"On 5 Seconds", @selector(forward:), RSKey(NSRightArrowFunctionKey), 0, self);
    [play addItem:[NSMenuItem separatorItem]];
    RSItem(play, @"Show This Line", @selector(reveal:), RSKey(NSDownArrowFunctionKey), 0, self);
    RSItem(play, @"Hear This Line Again", @selector(replay:), RSKey(NSUpArrowFunctionKey), 0, self);
    RSItem(play, @"Loop This Line", @selector(loop:), @"l", 0, self);
    RSItem(play, @"Slower", @selector(slower:), @"-", 0, self);
    RSItem(play, @"Faster", @selector(faster:), @"=", 0, self);
    RSItem(play, @"Keep This Line", @selector(keep:), @"k", 0, self);
    RSItem(play, @"A Word", @selector(word:), @"w", 0, self);
    RSItem(play, @"A Clip from Here", @selector(clipHere:), @"c", 0, self);
    [play addItem:[NSMenuItem separatorItem]];
    RSItem(play, @"How Was This Video?", @selector(feedback:), @"h", 0, self);
    [play addItem:[NSMenuItem separatorItem]];
    RSItem(play, @"Subtitles Stay On", @selector(subtitles:), @"s", 0, self);
    RSItem(play, @"Transcript", @selector(transcript:), @"t", 0, self);
    RSItem(play, @"Full Screen", @selector(fullScreen:), @"f", 0, self);

    NSMenu *window = [[[NSMenu alloc] initWithTitle:@"Window"] autorelease];
    RSItem(window, @"Minimize", @selector(performMiniaturize:), @"m", cmd, nil);
    RSItem(window, @"Zoom", @selector(performZoom:), nil, 0, nil);
    RSItem(window, @"Close", @selector(performClose:), @"w", cmd, nil);
    [window addItem:[NSMenuItem separatorItem]];
    RSItem(window, @"Bring All to Front", @selector(arrangeInFront:), nil, 0, NSApp);

    for (NSMenu *m in [NSArray arrayWithObjects:app, shelf, play, window, nil]) {
        NSMenuItem *top = [bar addItemWithTitle:[m title] action:NULL keyEquivalent:@""];
        [top setSubmenu:m];
    }
    [NSApp setMainMenu:bar];
    [NSApp setWindowsMenu:window];
}

- (BOOL)playerIsKey
{
    return _player && [[_player window] isKeyWindow];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    SEL a = [item action];
    if (a == @selector(refresh:)) return !_refreshing;
    if (a == @selector(showShelf:) || a == @selector(showLines:)) return YES;
    if (a == @selector(startTodaysClip:)) return [self todaysClip] != nil;
    if (a == @selector(showReading:)) return [_library readingForDay:RSToday()] != nil;
    if (a == @selector(showSay:) || a == @selector(showIslands:)) return YES;
    if (a == @selector(chooseSayLengths:)) { [item setState:[item tag] == (NSInteger)[self sayLengthsSetting] ? NSOnState : NSOffState]; return YES; }
    if (a == @selector(loop:)) [item setState:[_player looping] ? NSOnState : NSOffState];
    if (a == @selector(slower:)) [item setState:[_player slower] ? NSOnState : NSOffState];
    if (a == @selector(subtitles:)) [item setState:[_player subtitlesOn] ? NSOnState : NSOffState];
    if (a == @selector(transcript:)) [item setState:[_player transcriptShown] ? NSOnState : NSOffState];
    if (a == @selector(fullScreen:)) [item setState:[_player fullScreen] ? NSOnState : NSOffState];
    if (a == @selector(word:)) [item setState:[_player wordSlipShown] ? NSOnState : NSOffState];
    return [self playerIsKey];
}

- (void)showShelf:(id)sender  { [_window makeKeyAndOrderFront:nil]; }
- (void)playPause:(id)sender  { [_player togglePlay]; }
- (void)back:(id)sender       { [_player skip:-5]; }
- (void)forward:(id)sender    { [_player skip:5]; }
- (void)reveal:(id)sender     { [_player revealLine]; }
- (void)replay:(id)sender     { [_player replayLine]; }
- (void)subtitles:(id)sender  { [_player toggleSubtitles]; }
- (void)transcript:(id)sender { [_player toggleTranscript]; }
- (void)fullScreen:(id)sender { [_player toggleFullScreen]; }
- (void)loop:(id)sender       { [_player toggleLoop]; }
- (void)slower:(id)sender     { [_player stepSlower]; }
- (void)faster:(id)sender     { [_player stepFaster]; }
- (void)keep:(id)sender       { [_player keepLine]; }
- (void)word:(id)sender       { [_player toggleWordSlip]; }
- (void)feedback:(id)sender   { [_player toggleFeedback]; }
- (void)clipHere:(id)sender   { if ([_player clipPass]) [_player leaveClip]; else [_player startClipHere]; }

@end
