#import "RSReadingWindow.h"
#import "RSReading.h"
#import "RSDictionary.h"
#import "RSSay.h"
#import "RSStyle.h"
#import "RSReport.h"

#import <AVFoundation/AVFoundation.h>

static const double RSReadLongest = 30 * 60;      // a read longer than this ends by itself

@interface RSReadingWindow ()
- (BOOL)handleKey:(NSEvent *)event;
- (void)drawIn:(NSRect)rect;
@end

@interface RSReadingKeyWindow : NSWindow
@property (nonatomic, assign) RSReadingWindow *owner;
@end

@implementation RSReadingKeyWindow

- (void)sendEvent:(NSEvent *)event
{
    if ([event type] == NSKeyDown &&
        ([event modifierFlags] & (NSCommandKeyMask | NSControlKeyMask | NSAlternateKeyMask)) == 0 &&
        [_owner handleKey:event])
        return;
    [super sendEvent:event];
}

@end

@interface RSReadingView : NSView
@property (nonatomic, assign) RSReadingWindow *owner;
@end

@implementation RSReadingView
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)dirty { [_owner drawIn:[self bounds]]; }
@end

// The word slip, as in the player: over the text, at the top of the sheet.
@interface RSReadingSlipView : NSView {
    NSInteger _hover;
}
@property (nonatomic, copy) NSArray *words;
@property (nonatomic) NSInteger selected;
@property (nonatomic, copy) NSString *lemma, *detail, *rank, *note;
@property (nonatomic, assign) RSReadingWindow *owner;
@end

@implementation RSReadingSlipView

- (id)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame])) _hover = -1;
    return self;
}

- (void)dealloc
{
    [_words release];
    [_lemma release];
    [_detail release];
    [_rank release];
    [_note release];
    [super dealloc];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

- (NSInteger)itemAt:(NSEvent *)event
{
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    NSArray *rects = [RSStyle wordSlipItemRectsIn:[self bounds] words:_words];
    for (NSUInteger i = 0; i < [rects count]; i++)
        if (NSPointInRect(p, NSInsetRect([[rects objectAtIndex:i] rectValue], -3, -3))) return (NSInteger)i;
    return -1;
}

- (void)mouseDown:(NSEvent *)event { }
- (void)mouseUp:(NSEvent *)event
{
    NSInteger i = [self itemAt:event];
    if (i >= 0) [_owner chooseSlipWord:i];
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    for (NSTrackingArea *a in [self trackingAreas]) [self removeTrackingArea:a];
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp | NSTrackingInVisibleRect
          owner:self userInfo:nil];
    [self addTrackingArea:area];
    [area release];
}

- (void)mouseMoved:(NSEvent *)event
{
    NSInteger i = [self itemAt:event];
    if (i != _hover) { _hover = i; [self setNeedsDisplay:YES]; }
}

- (void)mouseExited:(NSEvent *)event { _hover = -1; [self setNeedsDisplay:YES]; }

- (void)drawRect:(NSRect)dirty
{
    [RSStyle drawWordSlipIn:[self bounds] words:_words selected:_selected lemma:_lemma detail:_detail rank:_rank note:_note hover:_hover];
}

@end

@interface RSReadingWindow () <AVAudioPlayerDelegate> {
    RSReadingKeyWindow *_window;
    RSReadingView *_view;
    NSScrollView *_scroll;
    NSTextView *_text;
    RSReadingSlipView *_slip;
    RSReadingSet *_set;
    RSSay *_say;
    long _today;
    NSString *_note;
    NSTimer *_timer;
    double _seconds;
    CFAbsoluteTime _startedAt;
    AVAudioRecorder *_recorder;
    AVAudioPlayer *_player, *_second;
    BOOL _silent, _closed, _micFailed, _recordedThisRead, _stressShown;
    NSArray *_slipWords, *_slipEntries;
    NSString *_slipSentence;
    NSInteger _slipSelection;
    NSUInteger _caret;                      // for the tests: where the caret is said to be
}
@property (nonatomic, readwrite) RSReadState state;
@property (nonatomic, readwrite) NSUInteger read;
@property (nonatomic, readwrite, retain) RSReadingItem *item;
@end

@implementation RSReadingWindow

- (id)initWithSet:(RSReadingSet *)set item:(RSReadingItem *)item say:(RSSay *)say today:(long)today
{
    if (!(self = [super init])) return nil;
    _set = [set retain];
    _item = [item retain];
    _say = [say retain];
    _today = today;
    _stressShown = YES;
    _slipSelection = -1;
    _caret = NSNotFound;

    NSSize size = [RSStyle readingWindowSize];
    _window = [[RSReadingKeyWindow alloc] initWithContentRect:NSMakeRect(0, 0, size.width, size.height)
        styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask
          backing:NSBackingStoreBuffered defer:YES];
    [_window setOwner:self];
    [_window setTitle:@"Reading"];
    [_window setReleasedWhenClosed:NO];
    [_window setDelegate:self];
    [_window setMinSize:NSMakeSize(560, 420)];
    _view = [[RSReadingView alloc] initWithFrame:[[_window contentView] bounds]];
    [_view setOwner:self];
    [_view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [[_window contentView] addSubview:_view];

    _scroll = [[NSScrollView alloc] initWithFrame:[RSStyle readingTextRectIn:[_view bounds]]];
    [_scroll setBorderType:NSNoBorder];
    [_scroll setHasVerticalScroller:YES];
    [_scroll setScrollerStyle:NSScrollerStyleOverlay];     // no white track on the paper (10.7+)
    [_scroll setDrawsBackground:NO];
    [_scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    _text = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth([_scroll frame]), 100)];
    [RSStyle styleReadingTextView:_text];
    [_text setDelegate:self];
    [_text setAutoresizingMask:NSViewWidthSizable];
    [_text setVerticallyResizable:YES];
    [_text setHorizontallyResizable:NO];
    [[_text textContainer] setWidthTracksTextView:YES];
    [[_text textContainer] setLineFragmentPadding:8];     // the words stay off the paper's edge
    [_scroll setDocumentView:_text];
    [_view addSubview:_scroll];

    _slip = [[RSReadingSlipView alloc] initWithFrame:NSZeroRect];
    [_slip setOwner:self];
    [_slip setHidden:YES];
    [_view addSubview:_slip];

    [self loadItem];
    [_window center];
    [_window setFrameAutosaveName:@"Reading"];
    return self;
}

- (void)dealloc
{
    [_timer invalidate];
    [_window setOwner:nil];
    [_window setDelegate:nil];
    [_window release];
    [_text setDelegate:nil];
    [_text release];
    [_scroll release];
    [_slip setOwner:nil];
    [_slip release];
    [_view setOwner:nil];
    [_view release];
    [_set release];
    [_item release];
    [_say release];
    [_dictionary release];
    [_note release];
    [_slipWords release];
    [_slipEntries release];
    [_slipSentence release];
    [_recorder stop];
    [_recorder release];
    [_player stop];
    [_player release];
    [_second stop];
    [_second release];
    [super dealloc];
}

- (NSWindow *)window { return _window; }
- (BOOL)stressShown { return _stressShown; }
- (BOOL)slipShown { return ![_slip isHidden]; }
- (NSString *)visibleNote { return _note; }

- (void)show
{
    [_window makeKeyAndOrderFront:nil];
    [_window makeFirstResponder:_text];
}

- (void)close
{
    if (_closed) return;
    _closed = YES;
    if (_state == RSReadRunning) [self endRead];
    [_timer invalidate];
    _timer = nil;
    [_player stop];
    [_second stop];
    [_window orderOut:nil];
    [_delegate readingWindowClosed:self];
}

- (void)windowWillClose:(NSNotification *)notification
{
    [self close];
}

- (void)setSilentForTesting { _silent = YES; }
- (void)setCaretForTesting:(NSUInteger)offset { _caret = offset; }
- (void)setSecondsForTesting:(double)seconds { _seconds = seconds; _startedAt = 0; [_view setNeedsDisplay:YES]; }

- (void)setNote:(NSString *)note
{
    [_note release];
    _note = [note copy];
    [_view setNeedsDisplay:YES];
}

// ---- The text ----------------------------------------------------------------------

- (void)loadItem
{
    [self hideWordSlip];
    [_window setTitle:[NSString stringWithFormat:@"Reading — %@", RSWithoutStress([_item title] ?: @"")]];
    NSString *text = _stressShown ? [_item text] : [_item plainText];
    [[_text textStorage] setAttributedString:[[[NSAttributedString alloc] initWithString:text ?: @"" attributes:[RSStyle readingTextAttributes]] autorelease]];
    [_text setSelectedRange:NSMakeRange(0, 0)];
    [_text scrollPoint:NSZeroPoint];
    _read = [_delegate readingWindow:self readsOf:_item];
    if (_read > 3) _read = 3;
    [self setState:_read >= 3 ? RSReadDone : RSReadReady];
    _seconds = 0;
    [self setNote:nil];
}

- (void)toggleStress
{
    _stressShown = !_stressShown;          // allowed any time: the marks are an aid
    NSRange was = [_text selectedRange];
    NSString *text = _stressShown ? [_item text] : [_item plainText];
    [[_text textStorage] setAttributedString:[[[NSAttributedString alloc] initWithString:text ?: @"" attributes:[RSStyle readingTextAttributes]] autorelease]];
    // The caret stays near where it was (the marks shift it a little).
    NSUInteger at = MIN(was.location, [text length]);
    [_text setSelectedRange:NSMakeRange(at, 0)];
    [self hideWordSlip];
    [self setNote:_stressShown ? @"Stress marks on." : @"Stress marks off. A brings them back."];
}

- (void)showItem:(NSInteger)direction
{
    if (_state == RSReadRunning) { [self setNote:@"Finish this read first (Space ends it)."]; return; }
    NSArray *items = [_set items];
    NSUInteger i = [items indexOfObject:_item];
    if (i == NSNotFound || [items count] < 2) return;
    NSInteger n = (NSInteger)[items count];
    NSInteger next = (((NSInteger)i + direction) % n + n) % n;
    [_player stop];
    [_second stop];
    [self setItem:[items objectAtIndex:(NSUInteger)next]];
    [self loadItem];
}

// ---- The three reads ----------------------------------------------------------------

- (NSString *)readPath:(NSUInteger)n
{
    return [_say readPath:n forReading:[_item key] day:_today];
}

- (void)space
{
    switch (_state) {
        case RSReadReady:   [self startRead]; break;
        case RSReadRunning: [self endRead]; break;
        case RSReadDone:    [self hearBothReads]; break;
    }
}

- (void)startRead
{
    NSUInteger n = _read + 1;
    [_player stop];
    [_second stop];
    [self hideWordSlip];
    [self setState:RSReadRunning];
    _seconds = 0;
    _startedAt = CFAbsoluteTimeGetCurrent();
    _recordedThisRead = NO;
    [self setNote:nil];
    if (n >= 2) {
        [[NSFileManager defaultManager] removeItemAtPath:[self readPath:n] error:NULL];
        if (!_silent) {
            NSDictionary *settings = [NSDictionary dictionaryWithObjectsAndKeys:
                [NSNumber numberWithInt:kAudioFormatMPEG4AAC], AVFormatIDKey, [NSNumber numberWithFloat:44100], AVSampleRateKey,
                [NSNumber numberWithInt:1], AVNumberOfChannelsKey, nil];
            [_recorder release];
            _recorder = [[AVAudioRecorder alloc] initWithURL:[NSURL fileURLWithPath:[self readPath:n]] settings:settings error:NULL];
            if (_recorder && [_recorder recordForDuration:RSReadLongest]) {
                _recordedThisRead = YES;
            } else {
                [_recorder release];
                _recorder = nil;
                if (!_micFailed) [self setNote:@"No microphone here: read aloud all the same; nothing is kept."];
                _micFailed = YES;
            }
        }
    }
    [_timer invalidate];
    _timer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    [_view setNeedsDisplay:YES];
}

- (void)tick:(NSTimer *)timer
{
    if (_startedAt > 0) _seconds = CFAbsoluteTimeGetCurrent() - _startedAt;
    if (_seconds >= RSReadLongest) { [self endRead]; return; }
    [_view setNeedsDisplayInRect:[RSStyle readingClockAreaIn:[_view bounds]]];
}

- (void)endRead
{
    if (_state != RSReadRunning) return;
    [_timer invalidate];
    _timer = nil;
    if (_startedAt > 0) _seconds = CFAbsoluteTimeGetCurrent() - _startedAt;
    [_recorder stop];
    [_recorder release];
    _recorder = nil;
    NSUInteger n = _read + 1;
    BOOL recorded = _recordedThisRead && [[NSFileManager defaultManager] fileExistsAtPath:[self readPath:n]];
    if (recorded) [_say labelRecording:[self readPath:n] as:[NSString stringWithFormat:@"%@, read %lu of 3", RSWithoutStress([_item title]), (unsigned long)n]];
    _read = n;
    if (_read >= 3) {
        [self setState:RSReadDone];
        [self setNote:recorded ? @"Three reads. Space plays read 2, then read 3: hear the difference. Then ⌘S retells it."
                               : @"Three reads. ⌘S retells it."];
    } else {
        [self setState:RSReadReady];
        [self setNote:n == 1 ? @"Read 1 done. Read 2 is aloud, recorded: Space when you’re ready."
                             : @"Read 2 done. Once more aloud, recorded: Space when you’re ready."];
    }
    [_delegate readingWindow:self item:_item finishedRead:n seconds:_seconds recorded:recorded];
    [_view setNeedsDisplay:YES];
}

- (void)hearBothReads
{
    NSString *two = [self readPath:2], *three = [self readPath:3];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:two] && ![fm fileExistsAtPath:three]) { [self setNote:@"Nothing recorded to play."]; return; }
    [self setNote:@"Read 2, then read 3."];
    if (_silent) return;
    [_player stop];
    [_player release];
    _player = nil;
    [_second stop];
    [_second release];
    _second = nil;
    if ([fm fileExistsAtPath:two]) _player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:two] error:NULL];
    if ([fm fileExistsAtPath:three]) _second = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:three] error:NULL];
    if (_player) { [_player setDelegate:self]; [_player play]; }
    else [_second play];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    if (player == _player && _second) [_second play];
}

// ---- A word looked up ----------------------------------------------------------------

- (NSUInteger)caret
{
    if (_caret != NSNotFound) return _caret;
    return [_text selectedRange].location;
}

// The sentence around the caret, and which of its words the caret is in.
- (NSString *)sentenceAtCaret:(NSUInteger *)wordIndex
{
    NSString *text = [[_text textStorage] string];
    NSUInteger at = MIN([self caret], [text length]);
    NSCharacterSet *stops = [NSCharacterSet characterSetWithCharactersInString:@".!?…\n"];
    NSUInteger start = at, end = at;
    while (start > 0 && ![stops characterIsMember:[text characterAtIndex:start - 1]]) start--;
    while (end < [text length] && ![stops characterIsMember:[text characterAtIndex:end]]) end++;
    // The stop and any closing quotes go with the sentence.
    while (end < [text length] && ([stops characterIsMember:[text characterAtIndex:end]] || [text characterAtIndex:end] == 0xBB || [text characterAtIndex:end] == '"')
           && [text characterAtIndex:end] != '\n') end++;
    NSString *sentence = [[text substringWithRange:NSMakeRange(start, end - start)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    // Which word: count the words that begin before the caret.
    if (wordIndex) {
        NSArray *words = RSWordsInLine(sentence);
        NSUInteger index = 0, searchFrom = 0;
        NSString *sentenceText = sentence;
        NSUInteger caretInSentence = at > start ? at - start : 0;
        for (NSUInteger w = 0; w < [words count]; w++) {
            NSRange r = [sentenceText rangeOfString:[words objectAtIndex:w] options:0 range:NSMakeRange(searchFrom, [sentenceText length] - searchFrom)];
            if (r.location == NSNotFound) break;
            if (r.location <= caretInSentence) index = w;
            else break;
            searchFrom = NSMaxRange(r);
        }
        *wordIndex = index;
    }
    return sentence;
}

- (void)toggleWordSlip
{
    if ([self slipShown]) { [self hideWordSlip]; return; }
    NSUInteger which = 0;
    NSString *sentence = [self sentenceAtCaret:&which];
    NSArray *words = RSWordsInLine(sentence);
    if ([words count] == 0) { [self setNote:@"Click a word first, then W."]; return; }
    [_slipSentence release];
    _slipSentence = [sentence copy];
    [_slipWords release];
    _slipWords = [words copy];
    NSMutableArray *entries = [NSMutableArray array];
    for (NSString *w in words) {
        RSDictionaryEntry *e = [_dictionary lookup:RSWithoutStress(w)];
        [entries addObject:e ?: (id)[NSNull null]];
    }
    [_slipEntries release];
    _slipEntries = [entries copy];
    // The words on the slip without their stress marks: the slip's lemma carries the stress.
    NSMutableArray *bare = [NSMutableArray array];
    for (NSString *w in words) [bare addObject:RSWithoutStress(w)];
    [_slip setWords:bare];
    [self layoutSlip];
    [_slip setHidden:NO];
    [self chooseSlipWord:(NSInteger)which];
    [self setNote:nil];
}

- (void)layoutSlip
{
    NSRect text = [RSStyle readingTextRectIn:[_view bounds]];
    NSSize slip = [RSStyle wordSlipSizeIn:text words:[_slip words] ?: [NSArray array]];
    [_slip setFrame:NSMakeRect(round(NSMidX(text) - slip.width / 2), NSMaxY(text) - 6 - slip.height, slip.width, slip.height)];
}

- (void)hideWordSlip
{
    [_slip setHidden:YES];
    [_slipWords release];
    _slipWords = nil;
    [_slipEntries release];
    _slipEntries = nil;
    [_slipSentence release];
    _slipSentence = nil;
    _slipSelection = -1;
    [_view setNeedsDisplay:YES];
}

- (void)chooseSlipWord:(NSInteger)index
{
    if (![self slipShown] || [_slipWords count] == 0) return;
    NSInteger count = (NSInteger)[_slipWords count];
    _slipSelection = ((index % count) + count) % count;
    id e = [_slipEntries objectAtIndex:(NSUInteger)_slipSelection];
    RSDictionaryEntry *entry = e == [NSNull null] ? nil : e;
    [_slip setSelected:_slipSelection];
    [_slip setLemma:[entry accented]];
    [_slip setDetail:entry ? [NSString stringWithFormat:@"%@ · %@", [entry type], [entry gloss]] : nil];
    [_slip setRank:entry ? [entry rankText] : nil];
    [_slip setNote:_dictionary ? @"Not in the dictionary." : @"No dictionary in this build."];
    [_slip setNeedsDisplay:YES];
    [_view setNeedsDisplay:YES];
}

- (void)keepSlipWord
{
    if (![self slipShown] || _slipSelection < 0) { [self setNote:@"W first: a word on the slip is what K keeps."]; return; }
    id e = [_slipEntries objectAtIndex:(NSUInteger)_slipSelection];
    NSString *said = [_delegate readingWindow:self keepWord:RSWithoutStress([_slipWords objectAtIndex:(NSUInteger)_slipSelection])
                                        entry:e == [NSNull null] ? nil : e sentence:RSWithoutStress(_slipSentence) item:_item];
    [self setNote:said];
}

// A click in the text puts the caret there; a word slip that was up goes
// with the old sentence.
- (void)textViewDidChangeSelection:(NSNotification *)n
{
    if ([self slipShown]) [self hideWordSlip];
}

// ---- Keys ------------------------------------------------------------------------------

- (BOOL)handleKey:(NSEvent *)event
{
    NSString *chars = [event charactersIgnoringModifiers];
    if ([chars length] != 1) return NO;
    switch ([chars characterAtIndex:0]) {
        case ' ':                       [self space]; return YES;
        case 'w': case 'W':             [self toggleWordSlip]; return YES;
        case 'k': case 'K':             [self keepSlipWord]; return YES;
        case 'a': case 'A':             [self toggleStress]; return YES;
        case NSLeftArrowFunctionKey:    if ([self slipShown]) [self chooseSlipWord:_slipSelection - 1]; else [self showItem:-1]; return YES;
        case NSRightArrowFunctionKey:   if ([self slipShown]) [self chooseSlipWord:_slipSelection + 1]; else [self showItem:1]; return YES;
        case 27:                        if ([self slipShown]) [self hideWordSlip]; else [_window performClose:nil]; return YES;
    }
    return NO;
}

// ---- Drawing ----------------------------------------------------------------------------

- (NSString *)visibleInstruction
{
    switch (_state) {
        case RSReadReady:
            switch (_read) {
                case 0:  return @"Read 1 of 3: silently, at your own pace. Click a word and W looks it up. Space starts, Space ends.";
                case 1:  return @"Read 2 of 3: aloud, recorded. Space starts, Space ends.";
                default: return @"Read 3 of 3: aloud again, recorded. Space starts, Space ends.";
            }
        case RSReadRunning:
            return _read == 0 ? @"Read 1 of 3. Space when you reach the end." : [NSString stringWithFormat:@"Read %lu of 3, aloud. Space at the end.", (unsigned long)_read + 1];
        case RSReadDone:
            return @"Read three times. Space: hear read 2, then read 3. ⌘S: retell it.";
    }
    return nil;
}

- (void)drawIn:(NSRect)rect
{
    NSArray *items = [_set items];
    NSUInteger i = [items indexOfObject:_item];
    NSMutableString *about = [NSMutableString string];
    if ([_item poem]) [about appendFormat:@"The week’s poem%@%@", [_item by] ? @" · " : @"", [_item by] ?: @""];
    else [about appendFormat:@"Story %lu of %lu", (unsigned long)[_item number], (unsigned long)[[_set items] count]];
    if ([_item metre]) [about appendFormat:@" · %@", [_item metre]];
    if ([[_item wordsToLearn] count]) [about appendFormat:@" · new: %@", [[_item wordsToLearn] componentsJoinedByString:@", "]];
    if (i != NSNotFound && [items count] > 1) [about appendFormat:@"   (← → the week’s others)"];
    NSString *clock = _state == RSReadRunning ? RSClock(_seconds) : nil;
    NSArray *keys;
    if ([self slipShown]) keys = [NSArray arrayWithObjects:@"← →", @"A word", @"K", @"Keep the word", @"W", @"Close the slip", nil];
    else if (_state == RSReadRunning) keys = [NSArray arrayWithObjects:@"Space", @"End the read", @"W", @"A word", @"A", _stressShown ? @"Stress off" : @"Stress on", nil];
    else keys = [NSArray arrayWithObjects:@"Space", _state == RSReadDone ? @"Hear reads 2 and 3" : @"Start the read", @"W", @"A word", @"K", @"Keep",
                 @"A", _stressShown ? @"Stress off" : @"Stress on", @"← →", @"Other readings", @"Esc", @"Close", nil];
    [RSStyle drawReadingIn:rect title:[_item title] about:about instruction:[self visibleInstruction] clock:clock
                 recording:_recorder != nil note:_note keys:keys];
}

@end
