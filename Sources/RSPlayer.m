#import "RSPlayer.h"
#import "RSStyle.h"
#import "RSSubtitles.h"
#import "RSShelf.h"

#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

static const double RSSkipSeconds = 5;
static const double RSRevealAtLeast = 2.0;     // a revealed line stays at least this long (media time)
static const double RSReportEvery = 5;          // seconds of wall time between position reports
static const double RSUserScrollQuiet = 5;      // after the reader scrolls the transcript, leave it alone
static const CGFloat RSControlBarHeight = 48;   // AVPlayerView's inline controls, along the bottom of the picture
static const float RSSlowerRate = 0.75;         // "slower": three-quarter speed
static const double RSLoopPauseAtLeast = 1.5;   // the pause after a looped line, to say it back (seconds)

@class RSPlayer;

// ---- The window: the player's keys come here before AVPlayerView sees them -

@interface RSPlayerWindow : NSWindow
@property (nonatomic, assign) RSPlayer *owner;
@end

@interface RSPlayer ()
- (BOOL)handleKey:(NSEvent *)event;
- (BOOL)handleDoubleClick:(NSEvent *)event;
- (void)seekToLine:(NSUInteger)index;
@end

@implementation RSPlayerWindow

- (void)sendEvent:(NSEvent *)event
{
    if ([event type] == NSKeyDown &&
        ([event modifierFlags] & (NSCommandKeyMask | NSControlKeyMask | NSAlternateKeyMask)) == 0 &&
        [_owner handleKey:event])
        return;
    if ([event type] == NSLeftMouseDown && [event clickCount] == 2 && [_owner handleDoubleClick:event])
        return;
    [super sendEvent:event];
}

@end

// ---- Over the video: the revealed line, or a short note ---------------------

@interface RSCaptionView : NSView
@property (nonatomic, copy) NSString *caption, *note;
@property (nonatomic) BOOL placeholderVideo;
@end

@implementation RSCaptionView

- (void)dealloc
{
    [_caption release];
    [_note release];
    [super dealloc];
}

- (NSView *)hitTest:(NSPoint)point { return nil; }     // clicks go to the player beneath
- (BOOL)isOpaque { return _placeholderVideo; }

- (void)setCaption:(NSString *)caption note:(NSString *)note
{
    if ((caption == _caption || [caption isEqualToString:_caption]) && (note == _note || [note isEqualToString:_note])) return;
    [self setCaption:caption];
    [self setNote:note];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirty
{
    if (_placeholderVideo) [RSStyle drawVideoPlaceholderIn:[self bounds]];
    if ([_caption length]) [RSStyle drawCaption:_caption in:[self bounds]];
    else if ([_note length]) [RSStyle drawCaptionPlaceholder:_note in:[self bounds]];
}

@end

// ---- After watching: how was it? -----------------------------------------------

@interface RSFeedbackView : NSView {
    NSInteger _hover;
}
@property (nonatomic, copy) NSString *felt, *want;
@property (nonatomic, assign) RSPlayer *owner;
@end

@interface RSPlayer ()
- (void)feedbackClicked:(NSInteger)item;
@end

@implementation RSFeedbackView

- (id)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame])) _hover = -1;
    return self;
}

- (void)dealloc
{
    [_felt release];
    [_want release];
    [super dealloc];
}

- (NSView *)hitTest:(NSPoint)point
{
    return ![self isHidden] && NSPointInRect(point, [self frame]) ? self : nil;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

- (NSInteger)itemAt:(NSEvent *)event
{
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    NSArray *rects = [RSStyle feedbackItemRectsIn:[self bounds]];
    for (NSUInteger i = 0; i < [rects count]; i++)
        if (NSPointInRect(p, NSInsetRect([[rects objectAtIndex:i] rectValue], -4, -6))) return (NSInteger)i;
    return -1;
}

- (void)mouseDown:(NSEvent *)event { }
- (void)mouseUp:(NSEvent *)event
{
    NSInteger i = [self itemAt:event];
    if (i >= 0) [_owner feedbackClicked:i];
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
    [RSStyle drawFeedbackIn:[self bounds] felt:_felt want:_want hover:_hover];
}

@end

// ---- The transcript ---------------------------------------------------------

@interface RSTranscriptView : NSView {
    NSMutableArray *_tops;      // y of each line, then the total height
    CGFloat _laidOutWidth;
    NSInteger _hover;
}
@property (nonatomic, retain) RSSubtitles *subtitles;
@property (nonatomic) NSUInteger current;
@property (nonatomic, assign) RSPlayer *owner;
- (NSRect)rectOfLine:(NSUInteger)index;
@end

@implementation RSTranscriptView

- (id)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        _current = NSNotFound;
        _hover = -1;
        _tops = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_subtitles release];
    [_tops release];
    [super dealloc];
}

- (BOOL)isFlipped { return YES; }

- (void)layoutLines
{
    CGFloat width = NSWidth([[[self enclosingScrollView] contentView] bounds]);
    if (width <= 0) width = NSWidth([self frame]);
    if (width == _laidOutWidth && [_tops count]) return;
    _laidOutWidth = width;
    [_tops removeAllObjects];
    CGFloat y = 6;
    for (RSLine *line in [_subtitles lines]) {
        [_tops addObject:[NSNumber numberWithDouble:y]];
        y += [RSStyle heightOfTranscriptLine:[[line text] stringByReplacingOccurrencesOfString:@"\n" withString:@" "] width:width];
    }
    [_tops addObject:[NSNumber numberWithDouble:y + 6]];
    NSSize visible = [[[self enclosingScrollView] contentView] bounds].size;
    [self setFrameSize:NSMakeSize(width, MAX(visible.height, y + 6))];
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldSize
{
    [super resizeWithOldSuperviewSize:oldSize];
    _laidOutWidth = -1;
    [self layoutLines];
}

- (void)setSubtitles:(RSSubtitles *)subtitles
{
    [_subtitles release];
    _subtitles = [subtitles retain];
    _laidOutWidth = -1;
    [self layoutLines];
    [self setNeedsDisplay:YES];
}

- (NSRect)rectOfLine:(NSUInteger)index
{
    [self layoutLines];
    if (index + 1 >= [_tops count]) return NSZeroRect;
    CGFloat top = [[_tops objectAtIndex:index] doubleValue], bottom = [[_tops objectAtIndex:index + 1] doubleValue];
    if (index + 2 == [_tops count]) bottom -= 6;
    return NSMakeRect(0, top, NSWidth([self bounds]), bottom - top);
}

- (NSInteger)lineAtPoint:(NSPoint)p
{
    [self layoutLines];
    for (NSUInteger i = 0; i + 1 < [_tops count]; i++)
        if (NSPointInRect(p, [self rectOfLine:i])) return (NSInteger)i;
    return -1;
}

- (void)setCurrent:(NSUInteger)current
{
    if (current == _current) return;
    if (_current != NSNotFound) [self setNeedsDisplayInRect:[self rectOfLine:_current]];
    _current = current;
    if (_current != NSNotFound) [self setNeedsDisplayInRect:[self rectOfLine:_current]];
}

- (void)drawRect:(NSRect)dirty
{
    [self layoutLines];
    if ([[_subtitles lines] count] == 0) {
        [RSStyle drawTranscriptEmptyIn:[self bounds] message:@"This video has no Russian subtitles, so there’s no transcript."];
        return;
    }
    [RSStyle drawTranscriptBackgroundIn:dirty];
    NSArray *lines = [_subtitles lines];
    for (NSUInteger i = 0; i < [lines count]; i++) {
        NSRect r = [self rectOfLine:i];
        if (NSMaxY(r) < NSMinY(dirty)) continue;
        if (NSMinY(r) > NSMaxY(dirty)) break;
        RSLine *line = [lines objectAtIndex:i];
        [RSStyle drawTranscriptLine:[[line text] stringByReplacingOccurrencesOfString:@"\n" withString:@" "]
                               time:[line start] in:r current:i == _current hover:(NSInteger)i == _hover];
    }
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

- (void)setHover:(NSInteger)i
{
    if (i == _hover) return;
    if (_hover >= 0) [self setNeedsDisplayInRect:[self rectOfLine:(NSUInteger)_hover]];
    _hover = i;
    if (_hover >= 0) [self setNeedsDisplayInRect:[self rectOfLine:(NSUInteger)_hover]];
}

- (void)mouseMoved:(NSEvent *)event { [self setHover:[self lineAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]]]; }
- (void)mouseExited:(NSEvent *)event { [self setHover:-1]; }

- (void)mouseUp:(NSEvent *)event
{
    NSInteger i = [self lineAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
    if (i >= 0) [_owner seekToLine:(NSUInteger)i];
}

@end

// ---- The key hints along the bottom ---------------------------------------

@interface RSHintBar : NSView
@property (nonatomic, copy) NSArray *items;
@end

@implementation RSHintBar

- (void)dealloc
{
    [_items release];
    [super dealloc];
}

- (void)setItems:(NSArray *)items
{
    [_items release];
    _items = [items copy];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirty
{
    [RSStyle drawHintBarIn:[self bounds] items:_items];
}

@end

// ---- The player -------------------------------------------------------------

@interface RSPlayer () {
    RSPlayerWindow *_window;
    AVPlayerView *_playerView;
    AVPlayer *_player;
    id _timeObserver;
    RSCaptionView *_captionView;
    NSScrollView *_transcriptScroll;
    RSTranscriptView *_transcriptView;
    RSHintBar *_hintBar;
    RSFeedbackView *_feedbackView;
    NSString *_felt, *_want;
    BOOL _feedbackOffered;
    RSSubtitles *_subtitles;
    NSString *_title, *_note, *_kind, *_openingNote;
    double _position, _furthest, _duration, _lastTime, _testingTime, _revealAt;
    NSUInteger _revealIndex, _loopIndex;
    float _rate;
    CFAbsoluteTime _lastReport, _noteUntil, _userScrolledAt, _loopSeekAt;
    BOOL _scrollingTranscript, _closed, _loopPaused, _observingRate;
}
@property (nonatomic, readwrite, copy) NSString *identifier;
@property (nonatomic, readwrite) BOOL subtitlesOn, transcriptShown;
@end

@implementation RSPlayer

- (id)initWithIdentifier:(NSString *)identifier title:(NSString *)title movie:(NSString *)moviePath
               subtitles:(RSSubtitles *)subtitles position:(double)position furthest:(double)furthest
                duration:(double)duration
{
    if (!(self = [super init])) return nil;
    _identifier = [identifier copy];
    _title = [title copy];
    _subtitles = [subtitles retain];
    _position = position;
    _furthest = furthest;
    _duration = duration;
    _testingTime = -1;
    _revealIndex = NSNotFound;
    _loopIndex = NSNotFound;
    _rate = 1;

    NSSize video = [RSStyle playerVideoSize];
    NSRect frame = NSMakeRect(0, 0, video.width, video.height + [RSStyle hintBarHeight]);
    _window = [[RSPlayerWindow alloc] initWithContentRect:frame
        styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask
          backing:NSBackingStoreBuffered defer:YES];
    [_window setOwner:self];
    [_window setTitle:title];
    [_window setReleasedWhenClosed:NO];
    [_window setDelegate:self];
    [_window setMinSize:NSMakeSize(480, 320)];
    [_window setBackgroundColor:[NSColor blackColor]];
    [_window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
    NSView *content = [_window contentView];
    [content setWantsLayer:YES];        // so the line can sit over the video

    _playerView = [[AVPlayerView alloc] initWithFrame:NSZeroRect];
    [_playerView setControlsStyle:AVPlayerViewControlsStyleInline];
    // Not AVPlayerView's own full screen: it carries the video off to a
    // window of its own, where the keys, the line and the hints can't follow.
    // The window goes full screen instead (F, a double-click, or the title
    // bar's button), with all of them.
    [_playerView setShowsFullScreenToggleButton:NO];
    [content addSubview:_playerView];
    if (moviePath) {
        _player = [[AVPlayer alloc] initWithURL:[NSURL fileURLWithPath:moviePath]];
        // Slower keeps the voice's pitch (Spectral is OS X's default; said
        // here so it stays that way).
        [[_player currentItem] setAudioTimePitchAlgorithm:AVAudioTimePitchAlgorithmSpectral];
        [_player addObserver:self forKeyPath:@"rate" options:0 context:NULL];
        _observingRate = YES;
        [_playerView setPlayer:_player];
        __block RSPlayer *me = self;      // not retained: the observer is removed in -close
        _timeObserver = [[_player addPeriodicTimeObserverForInterval:CMTimeMake(1, 10) queue:dispatch_get_main_queue()
                                                          usingBlock:^(CMTime time) { [me tick]; }] retain];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playedToEnd:)
                                                     name:AVPlayerItemDidPlayToEndTimeNotification object:[_player currentItem]];
        if (position > 3 && (duration <= 0 || position < duration - 5)) [self seekTo:position];
    }

    _captionView = [[RSCaptionView alloc] initWithFrame:NSZeroRect];
    [content addSubview:_captionView];

    _transcriptScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    [_transcriptScroll setHasVerticalScroller:YES];
    [_transcriptScroll setBorderType:NSNoBorder];
    [_transcriptScroll setDrawsBackground:YES];
    [_transcriptScroll setBackgroundColor:[NSColor whiteColor]];
    _transcriptView = [[RSTranscriptView alloc] initWithFrame:NSMakeRect(0, 0, [RSStyle transcriptWidth], 100)];
    [_transcriptView setOwner:self];
    [_transcriptView setAutoresizingMask:NSViewWidthSizable];
    [_transcriptScroll setDocumentView:_transcriptView];
    [_transcriptView setSubtitles:_subtitles];
    [_transcriptScroll setHidden:YES];
    [content addSubview:_transcriptScroll];
    [[_transcriptScroll contentView] setPostsBoundsChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(transcriptScrolled:)
                                                 name:NSViewBoundsDidChangeNotification object:[_transcriptScroll contentView]];

    _feedbackView = [[RSFeedbackView alloc] initWithFrame:NSZeroRect];
    [_feedbackView setOwner:self];
    [_feedbackView setHidden:YES];
    [content addSubview:_feedbackView];
    // Asked once a visit, at 90%, unless it was answered or watched to there before.
    _feedbackOffered = duration > 0 && furthest >= 0.9 * duration;

    _hintBar = [[RSHintBar alloc] initWithFrame:NSZeroRect];
    [content addSubview:_hintBar];
    [self updateHints];

    for (NSString *name in [NSArray arrayWithObjects:NSWindowDidResizeNotification, NSWindowDidEnterFullScreenNotification,
                            NSWindowDidExitFullScreenNotification, nil])
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowChangedSize:) name:name object:_window];
    [self layout];
    [_window center];
    [_window setFrameAutosaveName:@"Player"];
    return self;
}

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_observingRate) [_player removeObserver:self forKeyPath:@"rate"];
    [_window setOwner:nil];
    [_window setDelegate:nil];
    [_window release];
    [_playerView release];
    [_player release];
    [_timeObserver release];
    [_captionView release];
    [_transcriptScroll release];
    [_transcriptView release];
    [_hintBar release];
    [_feedbackView setOwner:nil];
    [_feedbackView release];
    [_felt release];
    [_want release];
    [_subtitles release];
    [_identifier release];
    [_title release];
    [_note release];
    [_kind release];
    [_openingNote release];
    [super dealloc];
}

- (NSWindow *)window { return _window; }

- (BOOL)fullScreen
{
    return ([_window styleMask] & NSFullScreenWindowMask) != 0;
}

- (void)windowChangedSize:(NSNotification *)n
{
    [self layout];
    [self updateHints];
}

- (void)layout
{
    NSRect b = [[_window contentView] bounds];
    CGFloat hint = [RSStyle hintBarHeight];
    CGFloat side = _transcriptShown ? MIN([RSStyle transcriptWidth], floor(NSWidth(b) * 0.45)) : 0;
    NSRect video = NSMakeRect(0, hint, NSWidth(b) - side, NSHeight(b) - hint);
    [_hintBar setFrame:NSMakeRect(0, 0, NSWidth(b), hint)];
    [_playerView setFrame:video];
    [_captionView setFrame:video];
    NSSize panel = [RSStyle feedbackPanelSize];
    [_feedbackView setFrame:NSMakeRect(round(NSMidX(video) - panel.width / 2), NSMaxY(video) - 18 - panel.height,
                                       panel.width, panel.height)];
    [_transcriptScroll setFrame:NSMakeRect(NSMaxX(video), hint, side, NSHeight(b) - hint)];
    [_transcriptScroll setHidden:!_transcriptShown];
    [_captionView setNeedsDisplay:YES];
}

- (NSString *)kind { return _kind; }

- (void)setKind:(NSString *)kind firstViewing:(BOOL)first
{
    [_kind release];
    _kind = [kind copy];
    [_openingNote release];
    _openingNote = nil;
    if ([kind isEqualToString:RSKindFast] && first && [[_subtitles lines] count]) {
        [self setSubtitlesOn:YES];
        _openingNote = [@"Fast speech, first time through: Russian subtitles on. S turns them off." copy];
        [self updateHints];
    }
}

- (void)show
{
    [_window makeKeyAndOrderFront:nil];
    [self play];
    [self tick];
    if (_openingNote) {
        [self showNote:_openingNote for:4];
        [_openingNote release];
        _openingNote = nil;
    }
}

- (void)close
{
    if (_closed) return;
    _closed = YES;
    [self report];
    [self stopLoop];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    if (_observingRate) [_player removeObserver:self forKeyPath:@"rate"];
    _observingRate = NO;
    [_player pause];
    if (_timeObserver) [_player removeTimeObserver:_timeObserver];
    [_timeObserver release];
    _timeObserver = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_window orderOut:nil];
    [_delegate playerClosed:self];
}

- (void)windowWillClose:(NSNotification *)notification
{
    [self close];
}

// ---- Time -------------------------------------------------------------------

- (double)currentTime
{
    if (_testingTime >= 0) return _testingTime;
    double t = CMTimeGetSeconds([_player currentTime]);
    return isfinite(t) && t > 0 ? t : 0;
}

- (double)duration
{
    CMTime d = [[_player currentItem] duration];
    if (CMTIME_IS_NUMERIC(d)) {
        double s = CMTimeGetSeconds(d);
        if (isfinite(s) && s > 0) return s;
    }
    return _duration;
}

- (BOOL)playing
{
    return [_player rate] > 0;
}

- (BOOL)slower
{
    return _rate < 1;
}

- (BOOL)looping
{
    return _loopIndex != NSNotFound;
}

// Plays at the chosen speed.
- (void)play
{
    [_player setRate:_rate];
}

// AVPlayerView's own play button plays at full speed: keep to the chosen one.
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (object == _player && [keyPath isEqualToString:@"rate"]) {
        float rate = [_player rate];
        if (rate > 0 && fabsf(rate - _rate) > 0.01f) [_player setRate:_rate];
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)report
{
    double t = [self currentTime], d = [self duration];
    double position = d > 0 && t >= d - 2 ? 0 : t;      // at the end: next time, from the start
    _lastReport = CFAbsoluteTimeGetCurrent();
    [_delegate player:self position:position furthest:_furthest duration:d];
}

- (void)tick
{
    double t = [self currentTime];
    // Furthest moves only by playing on from it: small steps (the ticks, or
    // a five-second skip) from at most a skip past it.
    if ([self playing] && t > _lastTime && t - _lastTime <= RSSkipSeconds + 1 && _lastTime <= _furthest + RSSkipSeconds + 1)
        _furthest = MAX(_furthest, t);
    _lastTime = t;
    double d = [self duration];
    if (!_feedbackOffered && d > 0 && _furthest >= 0.9 * d) {
        _feedbackOffered = YES;
        if (!(_felt && _want)) [self showFeedback];
    }
    [self loopAt:t];
    [self updateCaptionAt:t];
    [self updateTranscriptAt:t];
    if ([self playing] && CFAbsoluteTimeGetCurrent() - _lastReport >= RSReportEvery) [self report];
}

- (void)seekTo:(double)t
{
    double d = [self duration];
    t = MAX(0, d > 0 ? MIN(t, d - 0.1) : t);
    _lastTime = t;
    if (_testingTime >= 0) _testingTime = t;
    [_player seekToTime:CMTimeMakeWithSeconds(t, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    [self updateCaptionAt:t];
    [self updateTranscriptAt:t];
}

- (void)playedToEnd:(NSNotification *)n
{
    // A looped line that runs to the very end: the end is its pause.
    if ([self looping] && !_loopPaused) {
        RSLine *line = [[_subtitles lines] objectAtIndex:_loopIndex];
        _loopPaused = YES;
        [self performSelector:@selector(loopAgain) withObject:nil
                   afterDelay:MAX(RSLoopPauseAtLeast, ([line end] - [line start]) / _rate + 0.5)];
        return;
    }
    double d = [self duration];
    if (_lastTime >= _furthest - RSSkipSeconds - 1) _furthest = MAX(_furthest, d);
    [self report];
    [self showNote:@"The end." for:3];
}

- (void)setTimeForTesting:(double)seconds
{
    _testingTime = seconds;
    _lastTime = seconds;
    [self updateCaptionAt:seconds];
    [self updateTranscriptAt:seconds];
}

- (void)usePlaceholderVideoForTesting
{
    [_playerView setHidden:YES];
    [_captionView setPlaceholderVideo:YES];
    [_captionView setNeedsDisplay:YES];
}

- (NSString *)visibleCaption
{
    return [_captionView caption];
}

- (NSString *)visibleNote
{
    return [_captionView note];
}

// ---- What's over the video ----------------------------------------------------

- (void)showNote:(NSString *)note for:(double)seconds
{
    [_note release];
    _note = [note copy];
    _noteUntil = CFAbsoluteTimeGetCurrent() + seconds;
    [self updateCaptionAt:[self currentTime]];
    [self performSelector:@selector(noteExpired) withObject:nil afterDelay:seconds + 0.05];
}

- (void)noteExpired
{
    [self updateCaptionAt:[self currentTime]];
}

- (void)updateCaptionAt:(double)t
{
    NSString *caption = nil;
    NSArray *lines = [_subtitles lines];
    if (_revealIndex != NSNotFound && _revealIndex < [lines count]) {
        RSLine *line = [lines objectAtIndex:_revealIndex];
        // Shown while it's said (at least two seconds), or all through a loop of it.
        if (_revealIndex == _loopIndex) caption = [line text];
        else if (t < [line start] - 0.25 || t >= MAX([line end], _revealAt + RSRevealAtLeast)) _revealIndex = NSNotFound;
        else caption = [line text];
    }
    if (caption == nil && _subtitlesOn) {
        NSUInteger i = [_subtitles indexAtTime:t];
        if (i != NSNotFound) caption = [(RSLine *)[lines objectAtIndex:i] text];
    }
    NSString *note = CFAbsoluteTimeGetCurrent() < _noteUntil ? _note : nil;
    [_captionView setCaption:caption note:note];
}

- (void)updateTranscriptAt:(double)t
{
    if (!_transcriptShown) return;
    NSUInteger i = [_subtitles indexToHighlightAtTime:t];
    if (i == [_transcriptView current]) return;
    [_transcriptView setCurrent:i];
    if (i != NSNotFound && CFAbsoluteTimeGetCurrent() - _userScrolledAt > RSUserScrollQuiet) {
        NSRect r = [_transcriptView rectOfLine:i];
        NSRect visible = [_transcriptView visibleRect];
        if (!NSContainsRect(visible, r)) {
            _scrollingTranscript = YES;
            NSPoint target = NSMakePoint(0, MAX(0, NSMinY(r) - NSHeight(visible) * 0.3));
            [_transcriptView scrollPoint:target];
            _scrollingTranscript = NO;
        }
    }
}

- (void)transcriptScrolled:(NSNotification *)n
{
    if (!_scrollingTranscript) _userScrolledAt = CFAbsoluteTimeGetCurrent();
}

// ---- What the keys do --------------------------------------------------------

- (void)togglePlay
{
    if ([self looping]) {
        // Space ends a loop where it is: paused if it was waiting for you.
        BOOL waiting = _loopPaused;
        [self stopLoop];
        [self showNote:@"Loop off." for:1.2];
        if (waiting) return;
    }
    if ([self playing]) {
        [_player pause];
        [self report];
    } else {
        double d = [self duration];
        if (d > 0 && [self currentTime] >= d - 0.3) [self seekTo:0];
        [self play];
    }
}

- (void)skip:(double)seconds
{
    [self stopLoop];
    [self seekTo:[self currentTime] + seconds];
}

- (void)revealLine
{
    double t = [self currentTime];
    if ([[_subtitles lines] count] == 0) { [self showNote:@"This video has no Russian subtitles." for:2.5]; return; }
    NSUInteger i = [self lineMeantAt:t];
    if (i == NSNotFound) { [self showNote:@"Nothing is being said just now." for:1.5]; return; }
    if (_revealIndex != i) [_delegate player:self helped:RSHelpShown line:[[_subtitles lines] objectAtIndex:i]];
    _revealIndex = i;
    _revealAt = t;
    [self updateCaptionAt:t];
}

- (void)replayLine
{
    if ([[_subtitles lines] count] == 0) {
        [self skip:-RSSkipSeconds];
        [self showNote:@"No subtitles to find the line: back five seconds." for:2];
        return;
    }
    NSUInteger i = [self looping] ? _loopIndex : [_subtitles indexToReplayAtTime:[self currentTime]];
    [self stopLoop];
    if (i == NSNotFound) return;
    [self seekTo:MAX(0, [(RSLine *)[[_subtitles lines] objectAtIndex:i] start] - 0.05)];
    [self play];
    [_delegate player:self helped:RSHelpHeardAgain line:[[_subtitles lines] objectAtIndex:i]];
}

// A click on a line in the transcript: it was read there.
- (void)seekToLine:(NSUInteger)index
{
    [self stopLoop];
    if (index >= [[_subtitles lines] count]) return;
    [_delegate player:self helped:RSHelpTranscript line:[[_subtitles lines] objectAtIndex:index]];
    [self seekTo:MAX(0, [(RSLine *)[[_subtitles lines] objectAtIndex:index] start] - 0.05)];
}

- (void)toggleSubtitles
{
    if ([[_subtitles lines] count] == 0) { [self showNote:@"This video has no Russian subtitles." for:2.5]; return; }
    [self setSubtitlesOn:!_subtitlesOn];
    if (_subtitlesOn) [_delegate player:self helped:RSHelpSubtitles line:[self lineAt:[self currentTime]]];
    [self updateHints];
    [self showNote:_subtitlesOn ? @"Subtitles stay on." : @"Subtitles off." for:1.2];
}

- (void)toggleTranscript
{
    [self setTranscriptShown:!_transcriptShown];
    if (_transcriptShown) [_delegate player:self helped:RSHelpTranscript line:[self lineAt:[self currentTime]]];
    // Keep the video the size it was: the window grows by the transcript.
    if (![self fullScreen]) {
        NSRect f = [_window frame];
        CGFloat delta = [RSStyle transcriptWidth] * (_transcriptShown ? 1 : -1);
        f.size.width += delta;
        NSRect screen = [[_window screen] visibleFrame];
        if (NSMaxX(f) > NSMaxX(screen)) f.origin.x = MAX(NSMinX(screen), NSMaxX(screen) - NSWidth(f));
        if (NSWidth(f) > NSWidth(screen)) f.size.width = NSWidth(screen);
        [_window setFrame:f display:YES animate:NO];
    }
    [self layout];
    [self updateHints];
    if (_transcriptShown) {
        [_transcriptView setCurrent:NSNotFound];
        _userScrolledAt = 0;
        [self updateTranscriptAt:[self currentTime]];
    }
}

// ---- Working on one line ------------------------------------------------------

// The line a key means: the one being looped, or being said, or the one just
// said.
- (NSUInteger)lineMeantAt:(double)t
{
    if ([self looping]) return _loopIndex;
    return [_subtitles indexToRevealAtTime:t];
}

- (void)toggleLoop
{
    if ([self looping]) {
        [self stopLoop];
        [self showNote:@"Loop off." for:1.2];
        [self updateHints];
        return;
    }
    if ([[_subtitles lines] count] == 0) { [self showNote:@"This video has no Russian subtitles, so there are no lines to loop." for:2.5]; return; }
    NSUInteger i = [_subtitles indexToReplayAtTime:[self currentTime]];
    if (i == NSNotFound) { [self showNote:@"Nothing has been said yet." for:1.5]; return; }
    _loopIndex = i;
    _loopPaused = NO;
    _loopSeekAt = CFAbsoluteTimeGetCurrent();
    [self seekTo:MAX(0, [(RSLine *)[[_subtitles lines] objectAtIndex:i] start] - 0.05)];
    [self play];
    [_delegate player:self helped:RSHelpLooped line:[[_subtitles lines] objectAtIndex:i]];
    [self showNote:@"This line, again and again. Say it back in the pause. L stops." for:3];
    [self updateHints];
}

- (void)stopLoop
{
    if (_loopIndex == NSNotFound) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(loopAgain) object:nil];
    if (_revealIndex == _loopIndex) _revealIndex = NSNotFound;
    _loopIndex = NSNotFound;
    _loopPaused = NO;
    [self updateHints];
}

// At the end of a looped line: pause as long as the line took (at least a
// second and a half), then from its start again.
- (void)loopAt:(double)t
{
    if (_loopIndex == NSNotFound || _loopPaused || ![self playing]) return;
    // Just sent back to the line's start: the clock may not show it yet.
    if (CFAbsoluteTimeGetCurrent() - _loopSeekAt < 0.5) return;
    RSLine *line = [[_subtitles lines] objectAtIndex:_loopIndex];
    // Moved away with the scrubber: the loop is over.
    if (t < [line start] - 1 || t > [line end] + 2) { [self stopLoop]; return; }
    if (t < [line end] + 0.1) return;
    [_player pause];
    _loopPaused = YES;
    double pause = MAX(RSLoopPauseAtLeast, ([line end] - [line start]) / _rate + 0.5);
    [self performSelector:@selector(loopAgain) withObject:nil afterDelay:pause];
}

- (void)loopAgain
{
    if (_loopIndex == NSNotFound || _closed) return;
    // Played on, or moved with the scrubber, during the pause: the loop is over.
    RSLine *line = [[_subtitles lines] objectAtIndex:_loopIndex];
    double t = [self currentTime];
    if ([self playing] || t < [line start] - 1 || t > [line end] + 2) { [self stopLoop]; return; }
    _loopPaused = NO;
    _loopSeekAt = CFAbsoluteTimeGetCurrent();
    [self seekTo:MAX(0, [(RSLine *)[[_subtitles lines] objectAtIndex:_loopIndex] start] - 0.05)];
    [self play];
}

- (void)toggleSlower
{
    _rate = _rate < 1 ? 1 : RSSlowerRate;
    if ([self playing]) [self play];
    if (_rate < 1) [_delegate player:self helped:RSHelpSlowed line:[self lineAt:[self currentTime]]];
    [self showNote:_rate < 1 ? @"Three-quarter speed." : @"Full speed." for:1.2];
    [self updateHints];
}

// The line being said at t, or the one just said; nil if none.
- (RSLine *)lineAt:(double)t
{
    NSUInteger i = [self lineMeantAt:t];
    return i == NSNotFound || i >= [[_subtitles lines] count] ? nil : [[_subtitles lines] objectAtIndex:i];
}

// ---- How was it? ---------------------------------------------------------------

- (NSString *)felt { return _felt; }
- (NSString *)want { return _want; }
- (BOOL)feedbackShown { return ![_feedbackView isHidden]; }

- (void)setFelt:(NSString *)felt want:(NSString *)want
{
    [_felt release];
    _felt = [felt copy];
    [_want release];
    _want = [want copy];
    [_feedbackView setFelt:_felt];
    [_feedbackView setWant:_want];
    [_feedbackView setNeedsDisplay:YES];
}

- (void)showFeedback
{
    [_feedbackView setHidden:NO];
    [_feedbackView setNeedsDisplay:YES];
    [self quietFeedbackLater];
}

- (void)hideFeedback
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideFeedback) object:nil];
    [_feedbackView setHidden:YES];
}

// Left alone, it goes after a while: skipping is doing nothing.
- (void)quietFeedbackLater
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideFeedback) object:nil];
    [self performSelector:@selector(hideFeedback) withObject:nil afterDelay:12];
}

- (void)toggleFeedback
{
    if ([self feedbackShown]) [self hideFeedback];
    else [self showFeedback];
}

- (void)chooseFeedback:(NSString *)choice
{
    NSString *felt = _felt, *want = _want;
    if ([choice isEqualToString:RSFeltTooEasy] || [choice isEqualToString:RSFeltAboutRight] || [choice isEqualToString:RSFeltTooHard])
        felt = [choice isEqualToString:_felt] ? nil : choice;
    else if ([choice isEqualToString:RSWantMore] || [choice isEqualToString:RSWantLess])
        want = [choice isEqualToString:_want] ? nil : choice;
    else return;
    [self setFelt:felt want:want];
    [_delegate player:self felt:_felt want:_want];
    if ([self feedbackShown]) [self quietFeedbackLater];
}

- (void)feedbackClicked:(NSInteger)item
{
    NSArray *choices = [RSStyle feedbackChoices];
    if (item < 0) return;
    if ((NSUInteger)item >= [choices count]) { [self hideFeedback]; return; }      // the ✕
    [self chooseFeedback:[choices objectAtIndex:(NSUInteger)item]];
}

- (void)keepLine
{
    if ([[_subtitles lines] count] == 0) { [self showNote:@"This video has no Russian subtitles, so there’s no line to keep." for:2.5]; return; }
    double t = [self currentTime];
    NSUInteger i = [self lineMeantAt:t];
    if (i == NSNotFound) { [self showNote:@"Nothing is being said just now." for:1.5]; return; }
    NSArray *lines = [_subtitles lines];
    NSString *said = [_delegate player:self keepLine:[lines objectAtIndex:i] before:i > 0 ? [lines objectAtIndex:i - 1] : nil];
    // Show what was kept.
    _revealIndex = i;
    _revealAt = t;
    [self showNote:said for:2.5];
}

- (void)updateHints
{
    [_hintBar setItems:[NSArray arrayWithObjects:
        @"Space", @"Play",
        @"←  →", @"5 s",
        @"↓", @"Show line",
        @"↑", @"Again",
        @"L", [self looping] ? @"Stop loop" : @"Loop",
        @"−", [self slower] ? @"Full speed" : @"Slower",
        @"K", @"Keep",
        @"S", _subtitlesOn ? @"Subtitles off" : @"Subtitles",
        @"T", _transcriptShown ? @"Hide transcript" : @"Transcript",
        [self fullScreen] ? @"Esc" : @"F", [self fullScreen] ? @"Leave full screen" : @"Full screen", nil]];
}

- (void)toggleFullScreen
{
    [_window toggleFullScreen:nil];
}

// A double-click on the picture (not on its control bar) is full screen.
- (BOOL)handleDoubleClick:(NSEvent *)event
{
    NSRect picture = [_playerView frame];
    picture.origin.y += RSControlBarHeight;
    picture.size.height -= RSControlBarHeight;
    NSPoint p = [[_window contentView] convertPoint:[event locationInWindow] fromView:nil];
    if (!NSPointInRect(p, picture)) return NO;
    if ([self feedbackShown] && NSPointInRect(p, [_feedbackView frame])) return NO;
    [self toggleFullScreen];
    return YES;
}

- (BOOL)handleKey:(NSEvent *)event
{
    NSString *chars = [event charactersIgnoringModifiers];
    if ([chars length] != 1) return NO;
    switch ([chars characterAtIndex:0]) {
        case ' ':                       [self togglePlay]; return YES;
        case NSLeftArrowFunctionKey:    [self skip:-RSSkipSeconds]; return YES;
        case NSRightArrowFunctionKey:   [self skip:RSSkipSeconds]; return YES;
        case NSDownArrowFunctionKey:    [self revealLine]; return YES;
        case NSUpArrowFunctionKey:      [self replayLine]; return YES;
        case 's': case 'S':             [self toggleSubtitles]; return YES;
        case 't': case 'T':             [self toggleTranscript]; return YES;
        case 'f': case 'F':             [self toggleFullScreen]; return YES;
        case 'l': case 'L':             [self toggleLoop]; return YES;
        case '-': case 0x2212:          [self toggleSlower]; return YES;
        case 'k': case 'K':             [self keepLine]; return YES;
        case 'h': case 'H':             [self toggleFeedback]; return YES;
        case 27:                        // Escape
            if (![self fullScreen]) return NO;
            [self toggleFullScreen];
            return YES;
    }
    return NO;
}

@end
