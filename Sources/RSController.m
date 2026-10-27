#import "RSController.h"
#import "RSLibrary.h"
#import "RSShelf.h"
#import "RSSubtitles.h"
#import "RSSync.h"
#import "RSReport.h"
#import "RSDate.h"
#import "RSLines.h"
#import "RSClip.h"

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
    NSString *_studyFolder;
    NSMutableDictionary *_progress;     // id -> NSNumber, while downloading
    NSMutableDictionary *_problems;     // id -> why the last try failed
    NSMutableDictionary *_thumbnails;   // id -> NSImage
    NSString *_syncSummary, *_reportNote, *_testingStatus;
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
    [_lines release];
    [_studyFolder release];
    [_progress release];
    [_problems release];
    [_thumbnails release];
    [_syncSummary release];
    [_reportNote release];
    [_testingStatus release];
    [super dealloc];
}

- (NSWindow *)window { return _window; }
- (RSShelfView *)shelfView { return _shelfView; }
- (RSPlayer *)player { return _player; }
- (RSLibrary *)library { return _library; }
- (RSLines *)lines { return _lines; }
- (RSReview *)review { return _review; }

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
        [_window setTitle:@"Russian Shelf"];
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

    NSData *file = [NSData dataWithContentsOfFile:[self shelfFilePath]];
    if (file) {
        RSShelf *before = [[[_library current] retain] autorelease];
        RSOffer offer = [_library offerShelfFile:file today:RSToday()];
        if (offer == RSOfferTaken && before && ![[before fingerprint] isEqualToString:[[_library current] fingerprint]])
            [self queueReportFor:before];       // last word on the shelf that just went
    }
    [self advanceDay];
    [self reloadRows];
    [self updateStatus];
    [self startDownloads];
    [self pushReports];
}

// A shelf that arrived early becomes this week's on its start day.
- (void)advanceDay
{
    RSShelf *replaced = nil;
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

- (void)reloadRows
{
    if (_shelfView == nil) return;
    RSShelf *shelf = [_library current];
    NSString *next = [_library nextIdentifier];
    NSMutableArray *rows = [NSMutableArray array];
    for (RSVideo *video in [shelf videos]) {
        NSString *identifier = [video identifier];
        RSWatch *watch = [_library watchFor:identifier];
        RSRowModel *row = [[[RSRowModel alloc] init] autorelease];
        [row setIdentifier:identifier];
        [row setTitle:[video title]];
        [row setChannel:[video channel]];
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
    [_shelfView setRows:rows];
    if (shelf) {
        [_shelfView setTitle:@"This week’s shelf"];
        NSMutableString *sub = [NSMutableString stringWithFormat:@"From %@, chosen by Claude.", RSDayText([shelf start])];
        if ([_library pending]) [sub appendFormat:@" Next shelf from %@.", RSDayText([[_library pending] start])];
        NSUInteger due = [[_lines dueOn:RSToday()] count];
        if (due) [sub appendFormat:@" %lu line%s to hear again (⌘L).", (unsigned long)due, due == 1 ? "" : "s"];
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

// ---- Playing ------------------------------------------------------------------------

- (RSPlayer *)playVideo:(NSString *)identifier
{
    RSVideo *video = [[_library current] videoWithIdentifier:identifier];
    if (video == nil || ![_library isDownloaded:identifier]) return nil;
    if (_player) {
        if ([[_player identifier] isEqualToString:identifier]) { [[_player window] makeKeyAndOrderFront:nil]; return _player; }
        [_player close];
    }
    RSWatch *watch = [_library watchFor:identifier];
    RSSubtitles *subtitles = [RSSubtitles subtitlesWithFile:[_library subtitlesPath:identifier]];
    _player = [[RSPlayer alloc] initWithIdentifier:identifier title:[video title] movie:[_library moviePath:identifier]
                                         subtitles:subtitles position:[watch position] furthest:[watch furthest]
                                          duration:[watch duration]];
    [_player setDelegate:self];
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

- (void)player:(RSPlayer *)player helped:(RSHelp)kind
{
    [_library countHelp:kind for:[player identifier]];
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
        if (!ok) NSLog(@"Russian Shelf: %@", why);
    });
    [self reloadRows];
    return @"Kept. It comes back tomorrow (⌘L).";
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
    [RSReportText(shelf, _library, _lines, now) writeToFile:[outbox stringByAppendingPathComponent:RSReportName(shelf, now)]
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
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
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

    NSMenu *app = [[[NSMenu alloc] initWithTitle:@"Russian Shelf"] autorelease];
    RSItem(app, @"About Russian Shelf", @selector(orderFrontStandardAboutPanel:), nil, 0, NSApp);
    [app addItem:[NSMenuItem separatorItem]];
    RSItem(app, @"Hide Russian Shelf", @selector(hide:), @"h", cmd, NSApp);
    RSItem(app, @"Hide Others", @selector(hideOtherApplications:), @"h", cmd | NSAlternateKeyMask, NSApp);
    RSItem(app, @"Show All", @selector(unhideAllApplications:), nil, 0, NSApp);
    [app addItem:[NSMenuItem separatorItem]];
    RSItem(app, @"Quit Russian Shelf", @selector(terminate:), @"q", cmd, NSApp);

    NSMenu *shelf = [[[NSMenu alloc] initWithTitle:@"Shelf"] autorelease];
    RSItem(shelf, @"Show the Shelf", @selector(showShelf:), @"1", cmd, self);
    RSItem(shelf, @"Look for a New Shelf", @selector(refresh:), @"r", cmd, self);
    [shelf addItem:[NSMenuItem separatorItem]];
    RSItem(shelf, @"Lines to Hear Again", @selector(showLines:), @"l", cmd, self);

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
    RSItem(play, @"Keep This Line", @selector(keep:), @"k", 0, self);
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
    if (a == @selector(loop:)) [item setState:[_player looping] ? NSOnState : NSOffState];
    if (a == @selector(slower:)) [item setState:[_player slower] ? NSOnState : NSOffState];
    if (a == @selector(subtitles:)) [item setState:[_player subtitlesOn] ? NSOnState : NSOffState];
    if (a == @selector(transcript:)) [item setState:[_player transcriptShown] ? NSOnState : NSOffState];
    if (a == @selector(fullScreen:)) [item setState:[_player fullScreen] ? NSOnState : NSOffState];
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
- (void)slower:(id)sender     { [_player toggleSlower]; }
- (void)keep:(id)sender       { [_player keepLine]; }

@end
