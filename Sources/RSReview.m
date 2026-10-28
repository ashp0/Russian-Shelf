#import "RSReview.h"
#import "RSLines.h"
#import "RSStyle.h"
#import "RSReport.h"

#import <AVFoundation/AVFoundation.h>

static const float RSReviewSlowerRate = 0.75;

@class RSReview;

@interface RSReview ()
- (BOOL)handleKey:(NSEvent *)event;
- (BOOL)editingMeaning;
- (void)cancelMeaning;
- (void)drawIn:(NSRect)rect;
@end

// ---- The window: keys come to the review first ------------------------------

@interface RSReviewWindow : NSWindow
@property (nonatomic, assign) RSReview *owner;
@end

@implementation RSReviewWindow

- (void)sendEvent:(NSEvent *)event
{
    // While the meaning is being written, keys are letters; only Esc is ours.
    if ([event type] == NSKeyDown && [_owner editingMeaning]) {
        NSString *chars = [event charactersIgnoringModifiers];
        if ([chars length] == 1 && [chars characterAtIndex:0] == 27) { [_owner cancelMeaning]; return; }
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

@interface RSReviewView : NSView
@property (nonatomic, assign) RSReview *owner;
@end

@implementation RSReviewView

- (BOOL)isOpaque { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }      // so the keys come back here after writing
- (void)drawRect:(NSRect)dirty { [_owner drawIn:[self bounds]]; }

@end

// ---- The review -------------------------------------------------------------

@interface RSReview () <NSTextFieldDelegate> {
    RSReviewWindow *_window;
    RSReviewView *_view;
    NSTextField *_meaningField;
    RSLines *_lines;
    long _today;
    NSMutableArray *_queue;         // RSKeptLine still to hear today
    NSMutableSet *_again;           // keys already sent round again today
    RSKeptLine *_line;              // the one up now
    AVAudioPlayer *_sound;
    NSString *_note;
    BOOL _silent, _closed;
}
@property (nonatomic, readwrite) RSReviewState state;
@property (nonatomic, readwrite) BOOL slower;
@end

@implementation RSReview

- (id)initWithLines:(RSLines *)lines today:(long)today
{
    if (!(self = [super init])) return nil;
    _lines = [lines retain];
    _today = today;
    _queue = [[lines dueOn:today] mutableCopy];
    _again = [[NSMutableSet alloc] init];
    // "Not yet"s from earlier today (the window was closed): once more, at the end.
    for (RSKeptLine *line in [lines notYetOn:today]) {
        [_again addObject:[line key]];
        if (![_queue containsObject:line]) [_queue addObject:line];
    }

    NSSize size = [RSStyle reviewWindowSize];
    _window = [[RSReviewWindow alloc] initWithContentRect:NSMakeRect(0, 0, size.width, size.height)
        styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask
          backing:NSBackingStoreBuffered defer:YES];
    [_window setOwner:self];
    [_window setTitle:@"Lines to Hear Again"];
    [_window setReleasedWhenClosed:NO];
    [_window setDelegate:self];
    _view = [[RSReviewView alloc] initWithFrame:[[_window contentView] bounds]];
    [_view setOwner:self];
    [_view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [[_window contentView] addSubview:_view];
    _meaningField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [RSStyle styleMeaningField:_meaningField];
    [_meaningField setDelegate:self];
    [_meaningField setTarget:self];
    [_meaningField setAction:@selector(meaningEntered:)];
    [_meaningField setHidden:YES];
    [_view addSubview:_meaningField];
    [_window center];
    [_window setFrameAutosaveName:@"Lines"];
    [self next];
    return self;
}

- (void)dealloc
{
    [_window setOwner:nil];
    [_window setDelegate:nil];
    [_window release];
    [_meaningField setDelegate:nil];
    [_meaningField setTarget:nil];
    [_meaningField release];
    [_view setOwner:nil];
    [_view release];
    [_lines release];
    [_queue release];
    [_again release];
    [_line release];
    [_sound stop];
    [_sound release];
    [_note release];
    [super dealloc];
}

- (NSWindow *)window { return _window; }

- (void)show
{
    [_window makeKeyAndOrderFront:nil];
    [self hearAgain];
}

- (void)close
{
    if (_closed) return;
    _closed = YES;
    [_sound stop];
    [_lines save];
    [_window orderOut:nil];
    [_delegate reviewClosed:self];
}

- (void)windowWillClose:(NSNotification *)notification
{
    [self close];
}

- (void)setSilentForTesting
{
    _silent = YES;
    [_sound stop];
}

- (NSString *)visibleText
{
    return _state == RSReviewShown ? [_line text] : _state == RSReviewSaying ? [_line meaning] : nil;
}

// ---- The meaning, in the owner's words ---------------------------------------

- (void)placeMeaningField
{
    BOOL shown = _state == RSReviewShown && _line != nil;
    [_meaningField setHidden:!shown];
    if (!shown) {
        if ([self editingMeaning]) [_window makeFirstResponder:_view];
        return;
    }
    [_meaningField setFrame:[RSStyle reviewMeaningRectIn:[_view bounds] note:[_note length] > 0]];
    if (![self editingMeaning]) [_meaningField setStringValue:[_line meaning] ?: @""];
}

- (BOOL)editingMeaning
{
    NSResponder *r = [_window firstResponder];
    return [r isKindOfClass:[NSTextView class]] && [(NSTextView *)r delegate] == (id)_meaningField;
}

- (void)setMeaning:(NSString *)meaning
{
    if (_line == nil) return;
    NSString *m = [meaning stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [_line setMeaning:[m length] ? m : nil];
    [_lines save];
    [_meaningField setStringValue:[_line meaning] ?: @""];
}

- (void)meaningEntered:(id)sender
{
    [self setMeaning:[_meaningField stringValue]];
    [_window makeFirstResponder:_view];
    [_view setNeedsDisplay:YES];
}

- (void)controlTextDidEndEditing:(NSNotification *)n
{
    if (_line && [n object] == _meaningField) [self setMeaning:[_meaningField stringValue]];
}

- (void)cancelMeaning
{
    [_meaningField abortEditing];
    [_meaningField setStringValue:[_line meaning] ?: @""];
    [_window makeFirstResponder:_view];
}

- (void)writeMeaning
{
    if (_state != RSReviewShown || _line == nil) return;
    [self placeMeaningField];
    [_window makeFirstResponder:_meaningField];
}

- (void)setNote:(NSString *)note
{
    [_note release];
    _note = [note copy];
}

// ---- Going through them -----------------------------------------------------

- (void)next
{
    [_sound stop];
    [_sound release];
    _sound = nil;
    [self setNote:nil];
    [_line release];
    _line = nil;
    if ([_queue count] == 0) {
        [self setState:[[_lines lines] count] ? RSReviewDone : RSReviewNothingKept];
        [self placeMeaningField];
        [_view setNeedsDisplay:YES];
        return;
    }
    _line = [[_queue objectAtIndex:0] retain];
    [_queue removeObjectAtIndex:0];
    BOOL say = [_lines asksToSay:_line];
    [self setState:say ? RSReviewSaying : RSReviewListening];
    NSString *path = [_lines soundPath:_line];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        _sound = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:NULL];
        [_sound setEnableRate:YES];         // before prepareToPlay, or rate is ignored
        [_sound prepareToPlay];
    }
    if (_sound == nil) {
        // Without its sound, the line is all there is.
        [self setNote:@"No sound for this line: read it aloud instead."];
        if (!say) [self setState:RSReviewShown];
    }
    [self placeMeaningField];
    [_view setNeedsDisplay:YES];
    // A "say it" card waits for the owner to speak first.
    if (!say && _window && [_window isVisible]) [self hearAgain];
}

- (void)hearAgain
{
    if (_state == RSReviewSaying) { [self showLine]; return; }
    [self playSound];
}

- (void)playSound
{
    if (_sound == nil || _silent) return;
    [_sound stop];
    [_sound setCurrentTime:0];
    [_sound setRate:_slower ? RSReviewSlowerRate : 1];
    [_sound play];
}

- (void)showLine
{
    if (_state != RSReviewListening && _state != RSReviewSaying) return;
    BOOL said = _state == RSReviewSaying;
    [self setState:RSReviewShown];
    [self placeMeaningField];
    [_view setNeedsDisplay:YES];
    if (said) [self playSound];         // now hear how the speaker says it
}

- (void)answer:(BOOL)knew
{
    if (_line == nil) return;
    // The first answer today moves it on; a line sent round again is only
    // heard once more.
    if (![_again containsObject:[_line key]]) {
        [_lines answer:_line knew:knew today:_today];
        if (!knew && ![_line putAway]) {
            [_again addObject:[_line key]];
            [_queue addObject:_line];
        }
        [_lines save];
    }
    [self next];
}

- (void)putAway
{
    if (_line == nil) return;
    [_lines putAway:_line];
    [_lines save];
    [_queue removeObject:_line];
    [self next];
}

- (void)toggleSlower
{
    [self setSlower:!_slower];
    [self setNote:_slower ? @"Three-quarter speed." : @"Full speed."];
    [self placeMeaningField];
    [_view setNeedsDisplay:YES];
    if (_state != RSReviewSaying) [self playSound];
}

- (BOOL)handleKey:(NSEvent *)event
{
    NSString *chars = [event charactersIgnoringModifiers];
    if ([chars length] != 1) return NO;
    switch ([chars characterAtIndex:0]) {
        case ' ':                       [self hearAgain]; return YES;
        case NSDownArrowFunctionKey:    [self showLine]; return YES;
        case NSLeftArrowFunctionKey:    [self answer:NO]; return YES;
        case NSRightArrowFunctionKey:   [self answer:YES]; return YES;
        case 127: case NSDeleteFunctionKey: [self putAway]; return YES;
        case '-': case 0x2212:          [self toggleSlower]; return YES;
        case '\t':                      [self writeMeaning]; return YES;
        case 27:                        [_window performClose:nil]; return YES;
    }
    return NO;
}

// ---- Drawing ----------------------------------------------------------------

- (void)drawIn:(NSRect)rect
{
    NSString *heading = nil, *source = nil, *before = nil, *text = nil, *prompt = nil, *message = nil;
    NSArray *keys = nil;
    switch (_state) {
        case RSReviewListening:
        case RSReviewShown:
            heading = _state == RSReviewListening ? @"Listen. What does it say?" : @"Now say it aloud.";
            if ([[_line title] length])
                source = [NSString stringWithFormat:@"From “%@”, at %@", [_line title], RSClock([_line start])];
            if (_state == RSReviewShown) {
                before = [_line before];
                text = [_line text];
            }
            keys = [NSArray arrayWithObjects:@"Space", @"Hear it again", @"−", _slower ? @"Full speed" : @"Slower",
                    _state == RSReviewListening ? @"↓" : @"Tab", _state == RSReviewListening ? @"Show the line" : @"Meaning",
                    @"←", @"Not yet", @"→", @"Knew it", @"⌫", @"Put away", nil];
            break;
        case RSReviewSaying:
            heading = @"Say it in Russian.";
            if ([[_line title] length])
                source = [NSString stringWithFormat:@"From “%@”, at %@", [_line title], RSClock([_line start])];
            prompt = [_line meaning];
            keys = [NSArray arrayWithObjects:@"↓", @"Hear it and see it", @"←", @"Not yet", @"→", @"Knew it",
                    @"⌫", @"Put away", nil];
            break;
        case RSReviewDone:
            heading = @"That’s all for today.";
            message = @"Each line you kept comes back on its day: the next day, then after 3, 7, 16, 35 and 75 days.";
            keys = [NSArray arrayWithObjects:@"Esc", @"Close", nil];
            break;
        case RSReviewNothingKept:
            heading = @"No lines kept yet.";
            message = @"While a video plays, K keeps the line just said, with its sound. It comes back here the next day.";
            keys = [NSArray arrayWithObjects:@"Esc", @"Close", nil];
            break;
    }
    NSMutableArray *items = [NSMutableArray array];
    for (NSUInteger i = 0; i + 1 < [keys count]; i += 2) {
        if ([[keys objectAtIndex:i] length] == 0) continue;
        [items addObject:[keys objectAtIndex:i]];
        [items addObject:[keys objectAtIndex:i + 1]];
    }
    [RSStyle drawReviewIn:rect heading:heading source:source before:before text:text prompt:prompt message:message
                     note:_note meaningRow:_state == RSReviewShown keys:items];
}

@end
