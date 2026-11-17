#import "RSReview.h"
#import "RSLines.h"
#import "RSStyle.h"
#import "RSReport.h"
#import "RSDictionary.h"
#import "RSReading.h"

#import <AVFoundation/AVFoundation.h>

static const float RSReviewSlowerRate = 0.75;

@class RSReview;

@interface RSReview ()
- (BOOL)handleKey:(NSEvent *)event;
- (BOOL)editingMeaning;
- (void)cancelMeaning;
- (void)drawIn:(NSRect)rect;
- (NSRect)lineRect;
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

- (void)mouseDown:(NSEvent *)event
{
    [[self window] makeFirstResponder:self];
    [_owner lookUpWordAt:[self convertPoint:[event locationInWindow] fromView:nil]];
}

// A hand over the shown line: its words can be clicked.
- (void)resetCursorRects
{
    NSRect r = [_owner lineRect];
    if (!NSIsEmptyRect(r)) [self addCursorRect:r cursor:[NSCursor pointingHandCursor]];
}

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
    // A word looked up on the card up now.
    NSString *_hintWord, *_hintDetail;
    NSRange _hintRange;
}
@property (nonatomic, readwrite) BOOL hinted;
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
    [_window setTitle:@"Cards"];
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
    [_hintWord release];
    [_hintDetail release];
    [_dictionary release];
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
    [_window invalidateCursorRectsForView:_view];
}

// ---- A word looked up: a hint ------------------------------------------------

- (void)clearHint
{
    [_hintWord release];
    _hintWord = nil;
    [_hintDetail release];
    _hintDetail = nil;
    _hintRange = NSMakeRange(NSNotFound, 0);
}

- (RSDictionary *)dictionaryNow
{
    return _dictionary ?: [RSDictionary bundled];
}

- (NSString *)sourceNow
{
    if ([[_line title] length] == 0) return nil;
    return RSIsReadingKey([_line video]) ? [NSString stringWithFormat:@"From the reading “%@”", [_line title]]
                                         : [NSString stringWithFormat:@"From “%@”, at %@", [_line title], RSClock([_line start])];
}

// What's underlined in the shown line, and what's written under it: the
// word looked up, else a word card's own word.
- (NSString *)markNow
{
    if (_state != RSReviewShown) return nil;
    return _hintWord ?: ([_line isWord] ? [_line word] : nil);
}

- (NSString *)detailNow
{
    if (_state != RSReviewShown) return nil;
    if (_hintWord) return _hintDetail;
    if ([_line isWord]) return [NSString stringWithFormat:@"%@ · %@", [_line lemma] ?: [_line word], [_line gloss] ?: @""];
    return @"Click a word for its meaning.";
}

- (NSRect)lineRect
{
    if (_state != RSReviewShown || _line == nil) return NSZeroRect;
    return [RSStyle reviewTextRectIn:[_view bounds] source:[self sourceNow] before:[_line before] text:[_line text]
                              detail:[[self detailNow] length] > 0 note:[_note length] > 0 meaningRow:YES];
}

static BOOL RSIsWordCharacter(unichar c)
{
    return [[NSCharacterSet letterCharacterSet] characterIsMember:c];
}

- (BOOL)lookUpWordAt:(NSPoint)point
{
    if (_state != RSReviewShown || _line == nil) return NO;
    NSString *text = [_line text];
    NSUInteger i = [RSStyle reviewCharacterAt:point in:[_view bounds] source:[self sourceNow] before:[_line before] text:text
                                       detail:[[self detailNow] length] > 0 note:[_note length] > 0 meaningRow:YES];
    if (i == NSNotFound || i >= [text length] || !RSIsWordCharacter([text characterAtIndex:i])) return NO;
    // The whole word: letters (the stress mark is one) and a hyphen between them ("кто-то").
    NSUInteger start = i, end = i + 1, n = [text length];
    while (start > 0 && (RSIsWordCharacter([text characterAtIndex:start - 1]) ||
                         ([text characterAtIndex:start - 1] == '-' && start > 1 && RSIsWordCharacter([text characterAtIndex:start - 2]))))
        start--;
    while (end < n && (RSIsWordCharacter([text characterAtIndex:end]) ||
                       ([text characterAtIndex:end] == '-' && end + 1 < n && RSIsWordCharacter([text characterAtIndex:end + 1]))))
        end++;
    return [self lookUpRange:NSMakeRange(start, end - start)];
}

- (BOOL)lookUpWord:(NSString *)word
{
    if (_state != RSReviewShown || _line == nil || [word length] == 0) return NO;
    NSRange r = [[_line text] rangeOfString:word options:NSCaseInsensitiveSearch];
    return r.location != NSNotFound && [self lookUpRange:r];
}

- (BOOL)lookUpRange:(NSRange)range
{
    NSString *word = [[_line text] substringWithRange:range];
    if ([RSWordsInLine(word) count] == 0) return NO;             // not Russian
    NSString *bare = RSWithoutStress(word);
    [self clearHint];
    _hintWord = [word copy];
    _hintRange = range;
    // A word card's own word: its gloss is on the card already; not a hint.
    if ([_line isWord] && [[[_line word] lowercaseString] isEqualToString:[bare lowercaseString]]) {
        _hintDetail = [[NSString stringWithFormat:@"%@ · %@", [_line lemma] ?: [_line word], [_line gloss] ?: @""] copy];
        [self setNote:nil];
        [self refreshAfterHint];
        return YES;
    }
    RSDictionary *dictionary = [self dictionaryNow];
    RSDictionaryEntry *entry = [dictionary lookup:bare];
    if (entry == nil) {
        _hintDetail = [(dictionary ? @"Not in the dictionary." : @"No dictionary in this build.") copy];
        [self refreshAfterHint];
        return YES;
    }
    NSString *lemma = [[entry accented] length] ? [entry accented] : [entry bare];
    _hintDetail = [[NSString stringWithFormat:@"%@ · %@ · %@", lemma, [entry gloss] ?: @"", [entry rankText]] copy];
    if (!_hinted) {
        // The first word looked up on this card: it was a hint.
        [self setHinted:YES];
        [_line setHinted:_today];
        NSString *why = nil;
        RSKeptLine *card = [_lines keepWord:bare lemma:lemma gloss:[entry gloss] rank:[entry rank] inLine:[_line text]
                                     before:[_line before] video:[_line video] title:[_line title]
                                      start:[_line start] end:[_line end] today:_today problem:&why];
        [_lines save];
        [self setNote:card ? @"Looked up: once more before today’s are done, and the word gets its own card."
                           : @"Looked up: this card comes round once more before today’s are done."];
    }
    [self refreshAfterHint];
    return YES;
}

- (void)refreshAfterHint
{
    [self placeMeaningField];
    [_window invalidateCursorRectsForView:_view];
    [_view setNeedsDisplay:YES];
}

// ---- Going through them -----------------------------------------------------

- (void)next
{
    [_sound stop];
    [_sound release];
    _sound = nil;
    [self setNote:nil];
    [self clearHint];
    [self setHinted:NO];
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
    [_window invalidateCursorRectsForView:_view];
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
    [_window invalidateCursorRectsForView:_view];
    if (said) [self playSound];         // now hear how the speaker says it
}

- (void)answer:(BOOL)knew
{
    if (_line == nil) return;
    // The first answer today moves it on; a line sent round again is only
    // heard once more.
    if (![_again containsObject:[_line key]]) {
        [_lines answer:_line knew:knew hinted:_hinted today:_today];
        // Not yet, or known only with a word looked up: once more today.
        if ((!knew || _hinted) && ![_line putAway]) {
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
    BOOL word = [_line isWord];
    NSString *mark = [self markNow], *detail = [self detailNow];
    NSRange markRange = _hintWord ? _hintRange : NSMakeRange(NSNotFound, 0);
    switch (_state) {
        case RSReviewListening:
        case RSReviewShown:
            heading = _state == RSReviewListening ? (word ? @"Listen. Which word was it, and what does it mean?" : @"Listen. What does it say?")
                                                  : (word ? @"The word, in its line. Say the line aloud." : @"Now say it aloud.");
            source = [self sourceNow];
            if (_state == RSReviewShown) {
                before = [_line before];
                text = [_line text];
            }
            keys = [NSArray arrayWithObjects:@"Space", @"Hear it again", @"−", _slower ? @"Full speed" : @"Slower",
                    _state == RSReviewListening ? @"↓" : @"Tab", _state == RSReviewListening ? @"Show the line" : @"Meaning",
                    @"←", @"Not yet", @"→", @"Knew it", @"⌫", @"Put away", nil];
            break;
        case RSReviewSaying:
            heading = word ? @"Say the word in Russian, then the line." : @"Say it in Russian.";
            source = [self sourceNow];
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
            message = @"While a video plays, K keeps the line just said, with its sound, and W looks a word up to keep. They come back here the next day.";
            keys = [NSArray arrayWithObjects:@"Esc", @"Close", nil];
            break;
    }
    NSMutableArray *items = [NSMutableArray array];
    for (NSUInteger i = 0; i + 1 < [keys count]; i += 2) {
        if ([[keys objectAtIndex:i] length] == 0) continue;
        [items addObject:[keys objectAtIndex:i]];
        [items addObject:[keys objectAtIndex:i + 1]];
    }
    [RSStyle drawReviewIn:rect heading:heading source:source before:before text:text word:mark wordRange:markRange
                   detail:detail prompt:prompt message:message note:_note meaningRow:_state == RSReviewShown keys:items];
}

@end
