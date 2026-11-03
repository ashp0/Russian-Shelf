#import "RSSayWindow.h"
#import "RSSay.h"
#import "RSStyle.h"
#import "RSReport.h"
#import "RSClip.h"

#import <AVFoundation/AVFoundation.h>

static const double RSLessonPassLength = 30;        // the lesson in the owner's words: half a minute
static const double RSFreeRecordingLongest = 15 * 60;

@interface RSSayWindow ()
- (BOOL)handleKey:(NSEvent *)event;
- (BOOL)editingText;
- (void)cancelNote;
- (void)drawIn:(NSRect)rect;
- (void)clickedRow:(NSInteger)row;
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
@property (nonatomic) BOOL list;
@property (nonatomic) NSUInteger first, count;
@end

@implementation RSSayView
- (BOOL)isOpaque { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (void)drawRect:(NSRect)dirty { [_owner drawIn:[self bounds]]; }
- (void)mouseDown:(NSEvent *)event
{
    if (!_list) return;
    NSInteger row = [RSStyle sayListRowAtPoint:[self convertPoint:[event locationInWindow] fromView:nil] in:[self bounds] first:_first count:_count];
    if (row >= 0) [_owner clickedRow:row];
}
@end

@interface RSSayWindow () <AVAudioPlayerDelegate> {
    RSSayKeyWindow *_window;
    RSSayView *_view;
    NSTextField *_noteField;
    NSScrollView *_islandsScroll;
    NSTextView *_islandsText;
    RSSay *_say;
    NSString *_topic, *_note;
    NSUInteger _setting, _round, _passCount;
    long _today;
    NSTimer *_timer;
    double _secondsLeft, _passLength, _secondsRecorded;
    AVAudioRecorder *_recorder;
    AVAudioPlayer *_player, *_second;      // hearing a pass; last month's then today's
    BOOL _silent, _closed, _micFailed, _recordedThisPass, _recordingFree, _labelling;
    NSUInteger _notesToday;
    RSSayState _before;                    // the state before the islands or the recordings were opened
    NSArray *_recordings;                  // RSRecording, while the list is up
    NSInteger _selected, _playingRow;
    NSUInteger _first;
    NSString *_freePath;
}
@property (nonatomic, readwrite) RSSayState state;
@property (nonatomic, readwrite) NSUInteger pass;
@property (nonatomic, readwrite, copy) NSString *topic;
@end

@implementation RSSayWindow

- (id)initWithSay:(RSSay *)say topic:(NSString *)topic setting:(NSUInteger)setting today:(long)today
{
    if (!(self = [super init])) return nil;
    _say = [say retain];
    _topic = [topic copy];
    _setting = setting;
    _today = today;
    _round = 1;
    _passCount = 3;
    _selected = -1;
    _playingRow = -1;
    _notesToday = [[say tutorNotesForDay:today] count];
    // Picking up where today left off: passes already recorded count.
    while (_pass < 3 && [say hasPass:_pass + 1 forDay:today]) _pass++;
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
    [_topics release];
    [_lessons release];
    [_note release];
    [_recordings release];
    [_freePath release];
    [_recorder stop];
    [_recorder release];
    [_player stop];
    [_player release];
    [_second stop];
    [_second release];
    [super dealloc];
}

- (NSWindow *)window { return _window; }
- (NSUInteger)round { return _round; }
- (NSInteger)selectedRecording { return _state == RSSayRecordings ? _selected : -1; }
- (BOOL)recordingFree { return _recordingFree; }

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
    if (_recordingFree) [self stopFreeRecording];
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

// The story's lesson, when the topic retells a reading: then there's a
// fourth pass, the lesson in the owner's own words.
- (NSString *)lesson
{
    return _topic ? [_lessons objectForKey:_topic] : nil;
}

// ---- The passes ---------------------------------------------------------------------

- (NSArray *)lengths { return RSSayLengths(_setting); }

- (double)lengthOfPass:(NSUInteger)pass
{
    return pass <= 3 ? [[[self lengths] objectAtIndex:pass - 1] doubleValue] : RSLessonPassLength;
}

- (NSString *)passPath:(NSUInteger)pass
{
    NSString *path = [_say passPath:pass forDay:_today];
    if (_round > 1)
        path = [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:
                [NSString stringWithFormat:@"round%lu-pass-%lu.m4a", (unsigned long)_round, (unsigned long)pass]];
    return path;
}

- (BOOL)hasPass:(NSUInteger)pass
{
    return [[NSFileManager defaultManager] fileExistsAtPath:[self passPath:pass]];
}

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
            [self hearPass:_passCount];
            break;
        case RSSayIslands:
            break;
        case RSSayRecordings:
            if (_recordingFree) [self recordFree];
            else [self playSelected];
            break;
    }
}

- (void)startPass:(NSUInteger)pass
{
    _passCount = [self lesson] ? 4 : 3;
    if (pass < 1 || pass > _passCount) return;
    [_player stop];
    [_second stop];
    [self setPass:pass];
    [self setState:RSSayRunning];
    _passLength = [self lengthOfPass:pass];
    _secondsLeft = _passLength;
    _recordedThisPass = NO;
    [self setNote:pass == 4 ? @"The lesson, in your own words." : nil];
    [[NSFileManager defaultManager] removeItemAtPath:[self passPath:pass] error:NULL];
    if (!_silent) {
        NSDictionary *settings = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInt:kAudioFormatMPEG4AAC], AVFormatIDKey, [NSNumber numberWithFloat:44100], AVSampleRateKey,
            [NSNumber numberWithInt:1], AVNumberOfChannelsKey, nil];
        [_recorder release];
        _recorder = [[AVAudioRecorder alloc] initWithURL:[NSURL fileURLWithPath:[self passPath:pass]] settings:settings error:NULL];
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
    if (_recordingFree) {
        _secondsRecorded += 0.25;
        if (_secondsRecorded >= RSFreeRecordingLongest) [self recordFree];
        else [_view setNeedsDisplay:YES];
        return;
    }
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
    BOOL recorded = _recordedThisPass && [self hasPass:_pass];
    if (recorded)
        [_say labelRecording:[self passPath:_pass] as:_pass == 4 ? [NSString stringWithFormat:@"%@, the lesson", _topic]
                                                               : [NSString stringWithFormat:@"%@, pass %lu of %lu", _topic, (unsigned long)_pass, (unsigned long)_passCount]];
    if (_pass < _passCount) {
        [self setState:RSSayBetween];
        if (_pass == 3) [self setNote:@"Three tellings. Now the lesson, in your own words: Space, half a minute."];
        else [self setNote:[NSString stringWithFormat:@"Pass %lu done. The next is shorter: %@.", (unsigned long)_pass, RSClock([self lengthOfPass:_pass + 1])]];
    } else {
        [self setState:RSSayDone];
        NSString *month = nil;
        if (_pass == 4) {
            [self setNote:[NSString stringWithFormat:@"The story’s own line: %@", [self lesson]]];
        } else if (_round == 1 && recorded && [_say keepMonthRecording:[self passPath:3] forDay:_today]) {
            [self setNote:@"Kept as this month’s recording, to hear next to next month’s."];
        } else if (_round == 1 && [_say previousMonthRecordingBeforeDay:_today month:&month]) {
            [self setNote:[NSString stringWithFormat:@"M plays %@’s recording, then today’s.", month]];
        } else {
            [self setNote:recorded ? @"Space plays it back. Tab: a note for the tutor. ↑ ↓: another topic." : nil];
        }
    }
    [_delegate sayWindow:self finishedPass:_pass topic:_topic round:_round recorded:recorded];
    [self placeFields];
    [_view setNeedsDisplay:YES];
}

// ---- Another topic ------------------------------------------------------------------

- (void)chooseTopic:(NSInteger)direction
{
    if (_state == RSSayRunning || _state == RSSayIslands) return;
    if (_state == RSSayRecordings) { [self moveSelection:direction]; return; }
    NSMutableArray *topics = [NSMutableArray arrayWithArray:_topics ?: [NSArray array]];
    for (NSString *island in [_say islands]) if (![topics containsObject:island]) [topics addObject:island];
    if ([topics count] == 0) { [self setNote:@"No islands yet. ⌘I to write a few topics you can talk about."]; return; }
    NSInteger i = _topic ? (NSInteger)[topics indexOfObject:_topic] : NSNotFound;
    if (i == NSNotFound) i = direction > 0 ? -1 : 0;
    NSInteger n = (NSInteger)[topics count];
    i = ((i + direction) % n + n) % n;
    [self setTopic:[topics objectAtIndex:(NSUInteger)i]];
    // A fresh round: the passes already made today stay as they are.
    if (_state != RSSayReady) _round++;
    [_player stop];
    [_second stop];
    [self setPass:0];
    [self setState:RSSayReady];
    _passCount = [self lesson] ? 4 : 3;
    [self setNote:_round > 1 ? [NSString stringWithFormat:@"Round %lu. Space starts.", (unsigned long)_round] : nil];
    [self placeFields];
    [_view setNeedsDisplay:YES];
}

// ---- Hearing it back ------------------------------------------------------------------

- (void)hearPass:(NSUInteger)pass
{
    if (_silent || ![self hasPass:pass]) { if (![self hasPass:pass]) [self setNote:@"Nothing recorded to play."]; return; }
    [_player stop];
    [_player release];
    _player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:[self passPath:pass]] error:NULL];
    [_player play];
}

- (void)hearLastMonth
{
    if (_state == RSSayRunning) return;
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
    NSString *today = nil;
    for (NSUInteger p = 3; p >= 1 && today == nil; p--)
        if ([_say hasPass:p forDay:_today]) today = [_say passPath:p forDay:_today];
    if (today) _second = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:today] error:NULL];
    [_player play];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    if (player == _player && _second) [_second play];
    else if (player == _player && _state == RSSayRecordings) { _playingRow = -1; [_view setNeedsDisplay:YES]; }
}

// ---- The recordings -------------------------------------------------------------------

- (void)toggleRecordings
{
    if (_state == RSSayRecordings) {
        if (_recordingFree) [self recordFree];
        [_player stop];
        _playingRow = -1;
        [self setState:_before];
        [self setNote:nil];
        [self placeFields];
        [_window makeFirstResponder:_view];
        [_view setNeedsDisplay:YES];
        return;
    }
    if (_state == RSSayRunning || _state == RSSayIslands) return;
    _before = _state;
    [self setState:RSSayRecordings];
    [self loadRecordings];
    _selected = [_recordings count] ? 0 : -1;
    _first = 0;
    [self setNote:nil];
    [self placeFields];
    [_view setNeedsDisplay:YES];
}

- (void)loadRecordings
{
    [_recordings release];
    _recordings = [[_say recordings] copy];
    for (RSRecording *r in _recordings)
        if ([r seconds] <= 0 && !_silent) [r setSeconds:RSMediaDuration([r path])];
}

- (void)moveSelection:(NSInteger)direction
{
    if (_state != RSSayRecordings || [_recordings count] == 0) return;
    NSInteger n = (NSInteger)[_recordings count];
    _selected = MAX(0, MIN(n - 1, (_selected < 0 ? 0 : _selected) + direction));
    NSUInteger capacity = [RSStyle sayListCapacityIn:[_view bounds]];
    if ((NSUInteger)_selected < _first) _first = (NSUInteger)_selected;
    if ((NSUInteger)_selected >= _first + capacity) _first = (NSUInteger)_selected - capacity + 1;
    [_view setNeedsDisplay:YES];
}

- (void)clickedRow:(NSInteger)row
{
    if (_state != RSSayRecordings || row < 0 || (NSUInteger)row >= [_recordings count]) return;
    _selected = row;
    [self playSelected];
}

- (void)playSelected
{
    if (_selected < 0 || (NSUInteger)_selected >= [_recordings count]) return;
    if (_playingRow == _selected && [_player isPlaying]) { [_player stop]; _playingRow = -1; [_view setNeedsDisplay:YES]; return; }
    RSRecording *r = [_recordings objectAtIndex:(NSUInteger)_selected];
    _playingRow = _selected;
    [self setNote:nil];
    [_view setNeedsDisplay:YES];
    if (_silent) return;
    [_player stop];
    [_player release];
    _player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:[r path]] error:NULL];
    [_player setDelegate:self];
    [_second stop];
    [_second release];
    _second = nil;
    if (![_player play]) { _playingRow = -1; [self setNote:@"That recording won’t play."]; }
}

- (void)recordFree
{
    if (_recordingFree) { [self stopFreeRecording]; return; }
    if (_state == RSSayRunning || _state == RSSayIslands) return;
    if (_state != RSSayRecordings) [self toggleRecordings];
    [_player stop];
    _playingRow = -1;
    [_freePath release];
    _freePath = [[_say newFreeRecordingPathForDay:_today] copy];
    _secondsRecorded = 0;
    _recordingFree = YES;
    if (!_silent) {
        NSDictionary *settings = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInt:kAudioFormatMPEG4AAC], AVFormatIDKey, [NSNumber numberWithFloat:44100], AVSampleRateKey,
            [NSNumber numberWithInt:1], AVNumberOfChannelsKey, nil];
        [_recorder release];
        _recorder = [[AVAudioRecorder alloc] initWithURL:[NSURL fileURLWithPath:_freePath] settings:settings error:NULL];
        if (_recorder == nil || ![_recorder recordForDuration:RSFreeRecordingLongest]) {
            [_recorder release];
            _recorder = nil;
            _recordingFree = NO;
            [self setNote:@"No microphone here."];
            return;
        }
    }
    [self setNote:@"Recording. Space or N stops."];
    [_timer invalidate];
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    [_view setNeedsDisplay:YES];
}

- (void)stopFreeRecording
{
    [_timer invalidate];
    _timer = nil;
    [_recorder stop];
    [_recorder release];
    _recorder = nil;
    _recordingFree = NO;
    if (_silent) [@"" writeToFile:_freePath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    if ([[NSFileManager defaultManager] fileExistsAtPath:_freePath]) {
        [_say labelRecording:_freePath as:@"On my own"];
        [self loadRecordings];
        _selected = 0;
        for (NSUInteger i = 0; i < [_recordings count]; i++)
            if ([[(RSRecording *)[_recordings objectAtIndex:i] path] isEqualToString:_freePath]) _selected = (NSInteger)i;
        _first = 0;
        [self setNote:@"Kept. Tab names it; Space plays it."];
    } else {
        [self setNote:@"Nothing was recorded."];
    }
    [_view setNeedsDisplay:YES];
}

// ---- The note for the tutor, and a recording's name --------------------------------

- (void)placeFields
{
    BOOL noteRow = _state == RSSayDone || (_state == RSSayRecordings && _labelling);
    [_noteField setHidden:!noteRow];
    if (noteRow) [_noteField setFrame:[RSStyle sayNoteRectIn:[_view bounds]]];
    else if ([self editingText] && [_window firstResponder] != (NSResponder *)_islandsText) [_window makeFirstResponder:_view];
    BOOL islands = _state == RSSayIslands;
    [_islandsScroll setHidden:!islands];
    if (islands) [_islandsScroll setFrame:[RSStyle sayBodyRectIn:[_view bounds]]];
    [_view setList:_state == RSSayRecordings];
    [_view setFirst:_first];
    [_view setCount:[_recordings count]];
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
    if (_state == RSSayRecordings) {
        if (_selected < 0 || (NSUInteger)_selected >= [_recordings count]) return;
        _labelling = YES;
        [[_noteField cell] setPlaceholderString:@"What this recording is (Return keeps it)"];
        [_noteField setStringValue:[(RSRecording *)[_recordings objectAtIndex:(NSUInteger)_selected] label] ?: @""];
        [self placeFields];
        [_window makeFirstResponder:_noteField];
        return;
    }
    if (_state != RSSayDone) return;
    if (_notesToday >= 3) { [self setNote:@"Three notes today: enough for one lesson."]; return; }
    [[_noteField cell] setPlaceholderString:@"Something you noticed, for the tutor (Return keeps it)"];
    [self placeFields];
    [_window makeFirstResponder:_noteField];
}

- (void)noteEntered:(id)sender
{
    NSString *text = [[_noteField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (_labelling) {
        if (_selected >= 0 && (NSUInteger)_selected < [_recordings count]) {
            [_say labelRecording:[(RSRecording *)[_recordings objectAtIndex:(NSUInteger)_selected] path] as:text];
            [(RSRecording *)[_recordings objectAtIndex:(NSUInteger)_selected] setLabel:[text length] ? text : nil];
        }
        _labelling = NO;
    } else if ([text length] && [_say addTutorNote:text day:_today]) {
        _notesToday++;
        [self setNote:@"Kept for the tutor."];
    }
    [_noteField setStringValue:@""];
    [self placeFields];
    [_window makeFirstResponder:_view];
    [_view setNeedsDisplay:YES];
}

- (void)cancelNote
{
    _labelling = NO;
    [_noteField abortEditing];
    [_noteField setStringValue:@""];
    [self placeFields];
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
    if (_state == RSSayRunning || _recordingFree) return;
    if (_state == RSSayRecordings) [self toggleRecordings];
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
        case ' ':                       [self space]; return YES;
        case 'm': case 'M':             [self hearLastMonth]; return YES;
        case 'r': case 'R':             [self toggleRecordings]; return YES;
        case 'n': case 'N':             [self recordFree]; return YES;
        case NSUpArrowFunctionKey:      [self chooseTopic:-1]; return YES;
        case NSDownArrowFunctionKey:    [self chooseTopic:1]; return YES;
        case '\t':                      [self writeNote]; return YES;
        case 27:
            if (_state == RSSayIslands) [self toggleIslands];
            else if (_state == RSSayRecordings) [self toggleRecordings];
            else [_window performClose:nil];
            return YES;
    }
    return NO;
}

// ---- Drawing ----------------------------------------------------------------------------

- (void)drawIn:(NSRect)rect
{
    if (_state == RSSayRecordings) {
        NSMutableArray *rows = [NSMutableArray array];
        for (RSRecording *r in _recordings)
            [rows addObject:[NSArray arrayWithObjects:RSDayNumberText([r day]), [r label] ?: [r name],
                             [r seconds] > 0 ? RSClock([r seconds]) : @"", nil]];
        NSString *heading = _recordingFree ? [NSString stringWithFormat:@"Recording… %@", RSClock(_secondsRecorded)] : @"Your recordings, newest first.";
        NSArray *keys = _recordingFree ? [NSArray arrayWithObjects:@"Space", @"Stop", nil]
                                       : [NSArray arrayWithObjects:@"Space", _playingRow >= 0 ? @"Stop" : @"Play", @"↑ ↓", @"Choose", @"N", @"Record",
                                          @"Tab", @"Name it", @"Esc", @"Back", nil];
        [RSStyle drawSayListIn:rect heading:heading rows:rows selected:_selected first:_first recording:_recordingFree playing:_playingRow
                          note:_note keys:keys];
        return;
    }
    NSString *heading = nil, *passText = nil, *timeLeft = nil, *message = nil;
    double fraction = 1;
    NSArray *keys = nil;
    NSString *lengths = RSSayLengthsText(_setting);
    switch (_state) {
        case RSSayReady:
            heading = _round > 1 ? [NSString stringWithFormat:@"Round %lu. Three times, shorter each time.", (unsigned long)_round]
                                 : @"Say. Three times, shorter each time.";
            passText = [NSString stringWithFormat:@"Passes of %@. Space starts the first.", lengths];
            keys = [NSArray arrayWithObjects:@"Space", @"Start", @"↑ ↓", @"Another topic", @"R", @"Recordings", @"N", @"Record", @"⌘I", @"Islands", @"Esc", @"Close", nil];
            break;
        case RSSayRunning:
            heading = _pass == 4 ? @"The lesson, in your own words." : [NSString stringWithFormat:@"Pass %lu of 3. Keep talking.", (unsigned long)_pass];
            passText = [NSString stringWithFormat:@"%@ this time.", RSClock(_passLength)];
            timeLeft = RSClock(_secondsLeft);
            fraction = _passLength > 0 ? _secondsLeft / _passLength : 0;
            keys = [NSArray arrayWithObjects:@"Esc", @"Close", nil];
            break;
        case RSSayBetween:
            heading = [NSString stringWithFormat:@"Pass %lu done.", (unsigned long)_pass];
            passText = _pass == 3 ? @"Now the lesson, in your own words, in half a minute. Space starts it."
                                  : [NSString stringWithFormat:@"The same again, in %@. Space starts it.", RSClock([self lengthOfPass:_pass + 1])];
            keys = [NSArray arrayWithObjects:@"Space", @"Next pass", @"Esc", @"Close", nil];
            break;
        case RSSayDone:
            heading = _passCount == 4 ? @"Done. Three tellings and the lesson." : @"Done. Three tellings.";
            passText = [NSString stringWithFormat:@"%@. Hear the last one; note what you fumbled, for the tutor.", lengths];
            keys = [NSArray arrayWithObjects:@"Space", @"Hear it", @"Tab", @"For the tutor", @"↑ ↓", @"Another topic", @"R", @"Recordings",
                    @"M", @"Last month", @"Esc", @"Close", nil];
            break;
        case RSSayIslands:
            heading = @"Your islands: the topics you can talk about. One a line.";
            keys = [NSArray arrayWithObjects:@"⌘I", @"Keep", @"Esc", @"Keep", nil];
            break;
        case RSSayRecordings:
            break;
    }
    if (_state != RSSayIslands && [_topic length] == 0) message = @"No islands yet. ⌘I to write a few topics you can talk about.";
    [RSStyle drawSayIn:rect heading:heading topic:_state == RSSayIslands ? nil : _topic passText:passText timeLeft:timeLeft
              fraction:fraction recording:_recorder != nil message:message note:_note noteRow:_state == RSSayDone
               editing:_state == RSSayIslands keys:keys];
}

@end
