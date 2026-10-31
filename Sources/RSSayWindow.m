#import "RSSayWindow.h"
#import "RSSay.h"
#import "RSStyle.h"
#import "RSReport.h"

#import <AVFoundation/AVFoundation.h>

@interface RSSayWindow ()
- (BOOL)handleKey:(NSEvent *)event;
- (BOOL)editingText;
- (void)cancelNote;
- (void)drawIn:(NSRect)rect;
@end

@interface RSSayKeyWindow : NSWindow
@property (nonatomic, assign) RSSayWindow *owner;
@end

@implementation RSSayKeyWindow

- (void)sendEvent:(NSEvent *)event
{
    if ([event type] == NSKeyDown && [_owner editingText]) {
        NSString *chars = [event charactersIgnoringModifiers];
        BOOL cmd = ([event modifierFlags] & NSCommandKeyMask) != 0;
        if ([chars length] == 1 && [chars characterAtIndex:0] == 27) { [_owner cancelNote]; return; }
        if (cmd && [chars length] == 1 && ([chars characterAtIndex:0] == 'i' || [chars characterAtIndex:0] == 'I')) { [_owner toggleIslands]; return; }
        [super sendEvent:event];
        return;
    }
    if ([event type] == NSKeyDown &&
        ([event modifierFlags] & (NSCommandKeyMask | NSControlKeyMask | NSAlternateKeyMask)) == 0 &&
        [_owner handleKey:event])
        return;
    [super sendEvent:event];
}

@end

@interface RSSayView : NSView
@property (nonatomic, assign) RSSayWindow *owner;
@end

@implementation RSSayView
- (BOOL)isOpaque { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (void)drawRect:(NSRect)dirty { [_owner drawIn:[self bounds]]; }
@end

@interface RSSayWindow () <AVAudioPlayerDelegate> {
    RSSayKeyWindow *_window;
    RSSayView *_view;
    NSTextField *_noteField;
    NSScrollView *_islandsScroll;
    NSTextView *_islandsText;
    RSSay *_say;
    NSString *_topic, *_note;
    NSUInteger _setting;
    long _today;
    NSTimer *_timer;
    double _secondsLeft, _passLength;
    AVAudioRecorder *_recorder;
    AVAudioPlayer *_player, *_second;      // hearing a pass; last month's then today's
    BOOL _silent, _closed, _micFailed, _recordedThisPass;
    NSUInteger _notesToday;
    RSSayState _before;                    // the state before the islands were opened
}
@property (nonatomic, readwrite) RSSayState state;
@property (nonatomic, readwrite) NSUInteger pass;
@end

@implementation RSSayWindow

- (id)initWithSay:(RSSay *)say topic:(NSString *)topic setting:(NSUInteger)setting today:(long)today
{
    if (!(self = [super init])) return nil;
    _say = [say retain];
    _topic = [topic copy];
    _setting = setting;
    _today = today;
    _notesToday = [[say tutorNotesForDay:today] count];
    [say clearPassesNotFrom:today];
    // Picking up where today left off: passes already recorded count.
    while (_pass < 3 && [say hasPass:_pass + 1]) _pass++;
    _state = _pass == 0 ? RSSayReady : _pass == 3 ? RSSayDone : RSSayBetween;

    NSSize size = [RSStyle sayWindowSize];
    _window = [[RSSayKeyWindow alloc] initWithContentRect:NSMakeRect(0, 0, size.width, size.height)
        styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask
          backing:NSBackingStoreBuffered defer:YES];
    [_window setOwner:self];
    [_window setTitle:@"Say"];
    [_window setReleasedWhenClosed:NO];
    [_window setDelegate:self];
    _view = [[RSSayView alloc] initWithFrame:[[_window contentView] bounds]];
    [_view setOwner:self];
    [_view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [[_window contentView] addSubview:_view];
    _noteField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [RSStyle styleMeaningField:_noteField];
    [[_noteField cell] setPlaceholderString:@"Something you noticed, for the tutor (Return keeps it)"];
    [_noteField setDelegate:self];
    [_noteField setTarget:self];
    [_noteField setAction:@selector(noteEntered:)];
    [_noteField setHidden:YES];
    [_view addSubview:_noteField];
    _islandsScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    [_islandsScroll setBorderType:NSNoBorder];
    [_islandsScroll setHasVerticalScroller:YES];
    [_islandsScroll setDrawsBackground:NO];
    _islandsText = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    [_islandsText setDrawsBackground:NO];
    [_islandsText setFont:[NSFont fontWithName:@"Georgia" size:18] ?: [NSFont systemFontOfSize:18]];
    [_islandsText setTextColor:[NSColor colorWithCalibratedRed:0x1f / 255.0 green:0x3f / 255.0 blue:0x8a / 255.0 alpha:1]];
    [_islandsText setRichText:NO];
    [_islandsText setAutoresizingMask:NSViewWidthSizable];
    [_islandsText setVerticallyResizable:YES];
    [_islandsText setHorizontallyResizable:NO];
    [[_islandsText textContainer] setWidthTracksTextView:YES];
    [_islandsScroll setDocumentView:_islandsText];
    [_islandsScroll setHidden:YES];
    [_view addSubview:_islandsScroll];
    [_window center];
    [_window setFrameAutosaveName:@"Say"];
    [self placeFields];
    return self;
}

- (void)dealloc
{
    [_timer invalidate];
    [_window setOwner:nil];
    [_window setDelegate:nil];
    [_window release];
    [_noteField setDelegate:nil];
    [_noteField setTarget:nil];
    [_noteField release];
    [_islandsScroll release];
    [_islandsText release];
    [_view setOwner:nil];
    [_view release];
    [_say release];
    [_topic release];
    [_note release];
    [_recorder stop];
    [_recorder release];
    [_player stop];
    [_player release];
    [_second stop];
    [_second release];
    [super dealloc];
}

- (NSWindow *)window { return _window; }

- (void)show
{
    [_window makeKeyAndOrderFront:nil];
    [_window makeFirstResponder:_view];
}

- (void)close
{
    if (_closed) return;
    _closed = YES;
    [_timer invalidate];
    _timer = nil;
    [_recorder stop];
    [_player stop];
    [_second stop];
    if (_state == RSSayIslands) [self saveIslands];
    [_window orderOut:nil];
    [_delegate sayWindowClosed:self];
}

- (void)windowWillClose:(NSNotification *)notification
{
    [self close];
}

- (void)setSilentForTesting { _silent = YES; }
- (NSString *)visibleNote { return _note; }

- (void)setNote:(NSString *)note
{
    [_note release];
    _note = [note copy];
    [_view setNeedsDisplay:YES];
}

// ---- The passes ---------------------------------------------------------------------

- (NSArray *)lengths { return RSSayLengths(_setting); }

- (void)space
{
    switch (_state) {
        case RSSayReady:
        case RSSayBetween:
            [self startPass:_pass + 1];
            break;
        case RSSayRunning:
            break;          // the sand runs; nothing to press
        case RSSayDone:
            [self hearPass:3];
            break;
        case RSSayIslands:
            break;
    }
}

- (void)startPass:(NSUInteger)pass
{
    if (pass < 1 || pass > 3) return;
    [_player stop];
    [_second stop];
    [self setPass:pass];
    [self setState:RSSayRunning];
    _passLength = [[[self lengths] objectAtIndex:pass - 1] doubleValue];
    _secondsLeft = _passLength;
    _recordedThisPass = NO;
    [self setNote:nil];
    [[NSFileManager defaultManager] removeItemAtPath:[_say passPath:pass] error:NULL];
    if (!_silent) {
        NSDictionary *settings = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInt:kAudioFormatMPEG4AAC], AVFormatIDKey, [NSNumber numberWithFloat:44100], AVSampleRateKey,
            [NSNumber numberWithInt:1], AVNumberOfChannelsKey, nil];
        [_recorder release];
        _recorder = [[AVAudioRecorder alloc] initWithURL:[NSURL fileURLWithPath:[_say passPath:pass]] settings:settings error:NULL];
        if (_recorder && [_recorder recordForDuration:_passLength + 0.5]) {
            _recordedThisPass = YES;
        } else {
            [_recorder release];
            _recorder = nil;
            if (!_micFailed) [self setNote:@"No microphone here: the clock runs, nothing is kept."];
            _micFailed = YES;
        }
    }
    [_timer invalidate];
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    [self placeFields];
    [_view setNeedsDisplay:YES];
}

- (void)tick:(NSTimer *)timer
{
    _secondsLeft -= 0.25;
    if (_secondsLeft <= 0) [self finishPass];
    else [_view setNeedsDisplayInRect:[RSStyle sayGlassAreaIn:[_view bounds]]];
}

- (void)setSecondsLeftForTesting:(double)seconds
{
    _secondsLeft = seconds;
    if (_state == RSSayRunning && seconds <= 0) [self finishPass];
    [_view setNeedsDisplay:YES];
}

- (void)finishPass
{
    [_timer invalidate];
    _timer = nil;
    _secondsLeft = 0;
    [_recorder stop];
    [_recorder release];
    _recorder = nil;
    BOOL recorded = _recordedThisPass && [_say hasPass:_pass];
    if (_pass < 3) {
        [self setState:RSSayBetween];
        [self setNote:[NSString stringWithFormat:@"Pass %lu done. The next is shorter: %@.", (unsigned long)_pass,
                       RSClock([[[self lengths] objectAtIndex:_pass] doubleValue])]];
    } else {
        [self setState:RSSayDone];
        NSString *month = nil;
        if (recorded && [_say keepMonthRecording:[_say passPath:3] forDay:_today]) {
            [self setNote:@"Kept as this month’s recording, to hear next to next month’s."];
        } else if ([_say previousMonthRecordingBeforeDay:_today month:&month]) {
            [self setNote:[NSString stringWithFormat:@"M plays %@’s recording, then today’s.", month]];
        } else {
            [self setNote:recorded ? @"Space plays it back. Tab: a note for the tutor." : nil];
        }
    }
    [_delegate sayWindow:self finishedPass:_pass recorded:recorded];
    [self placeFields];
    [_view setNeedsDisplay:YES];
}

// ---- Hearing it back ------------------------------------------------------------------

- (void)hearPass:(NSUInteger)pass
{
    if (_silent || ![_say hasPass:pass]) { if (![_say hasPass:pass]) [self setNote:@"Nothing recorded to play."]; return; }
    [_player stop];
    [_player release];
    _player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:[_say passPath:pass]] error:NULL];
    [_player play];
}

- (void)hearLastMonth
{
    NSString *month = nil;
    NSString *last = [_say previousMonthRecordingBeforeDay:_today month:&month];
    if (last == nil) { [self setNote:@"No earlier month’s recording yet."]; return; }
    [self setNote:[NSString stringWithFormat:@"%@, then today.", month]];
    if (_silent) return;
    [_player stop];
    [_player release];
    _player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:last] error:NULL];
    [_player setDelegate:self];
    [_second stop];
    [_second release];
    _second = nil;
    NSString *today = [_say hasPass:3] ? [_say passPath:3] : [_say hasPass:2] ? [_say passPath:2] : [_say hasPass:1] ? [_say passPath:1] : nil;
    if (today) _second = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:today] error:NULL];
    [_player play];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    if (player == _player && _second) [_second play];
}

// ---- The note for the tutor ---------------------------------------------------------

- (void)placeFields
{
    BOOL noteRow = _state == RSSayDone;
    [_noteField setHidden:!noteRow];
    if (noteRow) [_noteField setFrame:[RSStyle sayNoteRectIn:[_view bounds]]];
    else if ([self editingText] && [_window firstResponder] != (NSResponder *)_islandsText) [_window makeFirstResponder:_view];
    BOOL islands = _state == RSSayIslands;
    [_islandsScroll setHidden:!islands];
    if (islands) [_islandsScroll setFrame:[RSStyle sayBodyRectIn:[_view bounds]]];
}

- (BOOL)editingText
{
    NSResponder *r = [_window firstResponder];
    if ([r isKindOfClass:[NSTextView class]]) {
        NSTextView *tv = (NSTextView *)r;
        return [tv delegate] == (id)_noteField || tv == _islandsText;
    }
    return NO;
}

- (void)writeNote
{
    if (_state != RSSayDone) return;
    if (_notesToday >= 3) { [self setNote:@"Three notes today: enough for one lesson."]; return; }
    [self placeFields];
    [_window makeFirstResponder:_noteField];
}

- (void)noteEntered:(id)sender
{
    NSString *text = [[_noteField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([text length] && [_say addTutorNote:text day:_today]) {
        _notesToday++;
        [self setNote:@"Kept for the tutor."];
    }
    [_noteField setStringValue:@""];
    [_window makeFirstResponder:_view];
}

- (void)cancelNote
{
    [_noteField abortEditing];
    [_noteField setStringValue:@""];
    [_window makeFirstResponder:_view];
}

// ---- The islands ---------------------------------------------------------------------

- (void)toggleIslands
{
    if (_state == RSSayIslands) {
        [self saveIslands];
        [self setState:_before];
        [self placeFields];
        [_window makeFirstResponder:_view];
        [_view setNeedsDisplay:YES];
        return;
    }
    if (_state == RSSayRunning) return;
    _before = _state;
    [self setState:RSSayIslands];
    [_islandsText setString:[[[_say islands] componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"]];
    [self placeFields];
    [_window makeFirstResponder:_islandsText];
    [_view setNeedsDisplay:YES];
}

- (void)saveIslands
{
    [_say saveIslands:[[_islandsText string] componentsSeparatedByString:@"\n"]];
}

// ---- Keys ------------------------------------------------------------------------------

- (BOOL)handleKey:(NSEvent *)event
{
    NSString *chars = [event charactersIgnoringModifiers];
    if ([chars length] != 1) return NO;
    switch ([chars characterAtIndex:0]) {
        case ' ':           [self space]; return YES;
        case 'm': case 'M': [self hearLastMonth]; return YES;
        case '\t':          [self writeNote]; return YES;
        case 27:            if (_state == RSSayIslands) [self toggleIslands]; else [_window performClose:nil]; return YES;
    }
    return NO;
}

// ---- Drawing ----------------------------------------------------------------------------

- (void)drawIn:(NSRect)rect
{
    NSString *heading = nil, *passText = nil, *timeLeft = nil, *message = nil;
    double fraction = 1;
    NSArray *keys = nil;
    NSString *lengths = RSSayLengthsText(_setting);
    switch (_state) {
        case RSSayReady:
            heading = @"Say. Three times, shorter each time.";
            passText = [NSString stringWithFormat:@"Passes of %@. Space starts the first.", lengths];
            keys = [NSArray arrayWithObjects:@"Space", @"Start", @"⌘I", @"Islands", @"Esc", @"Close", nil];
            break;
        case RSSayRunning:
            heading = [NSString stringWithFormat:@"Pass %lu of 3. Keep talking.", (unsigned long)_pass];
            passText = [NSString stringWithFormat:@"%@ this time.", RSClock(_passLength)];
            timeLeft = RSClock(_secondsLeft);
            fraction = _passLength > 0 ? _secondsLeft / _passLength : 0;
            keys = [NSArray arrayWithObjects:@"Esc", @"Close", nil];
            break;
        case RSSayBetween:
            heading = [NSString stringWithFormat:@"Pass %lu done.", (unsigned long)_pass];
            passText = [NSString stringWithFormat:@"The same again, in %@. Space starts it.", RSClock([[[self lengths] objectAtIndex:_pass] doubleValue])];
            keys = [NSArray arrayWithObjects:@"Space", @"Next pass", @"Esc", @"Close", nil];
            break;
        case RSSayDone:
            heading = @"Done. Three tellings.";
            passText = [NSString stringWithFormat:@"%@. Hear the last one; note what you fumbled, for the tutor.", lengths];
            keys = [NSArray arrayWithObjects:@"Space", @"Hear it", @"Tab", @"For the tutor", @"M", @"Last month", @"Esc", @"Close", nil];
            break;
        case RSSayIslands:
            heading = @"Your islands: the topics you can talk about. One a line.";
            keys = [NSArray arrayWithObjects:@"⌘I", @"Keep", @"Esc", @"Keep", nil];
            break;
    }
    if (_state != RSSayIslands && [_topic length] == 0) message = @"No islands yet. ⌘I to write a few topics you can talk about.";
    [RSStyle drawSayIn:rect heading:heading topic:_state == RSSayIslands ? nil : _topic passText:passText timeLeft:timeLeft
              fraction:fraction recording:_recorder != nil message:message note:_note noteRow:_state == RSSayDone
               editing:_state == RSSayIslands keys:keys];
}

@end
