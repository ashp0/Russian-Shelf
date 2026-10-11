#import "RSShelfView.h"

@interface RSShelfView () {
    NSInteger _hover, _pressed, _selected;
    NSTrackingArea *_tracking;
}
@end

@implementation RSShelfView

- (id)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        _hover = _pressed = _selected = -1;
        _rows = [[NSArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_title release];
    [_subtitle release];
    [_emptyTitle release];
    [_emptyMessage release];
    [_rows release];
    [_tracking release];
    [super dealloc];
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

- (void)setRows:(NSArray *)rows
{
    if (rows == _rows) return;
    [_rows release];
    _rows = [rows copy];
    if (_selected >= (NSInteger)[_rows count]) _selected = -1;
    [self fitToWidth];
    [self setNeedsDisplay:YES];
}

- (void)setTitle:(NSString *)title
{
    [_title release];
    _title = [title copy];
    [self setNeedsDisplay:YES];
}

- (void)setSubtitle:(NSString *)subtitle
{
    [_subtitle release];
    _subtitle = [subtitle copy];
    [self setNeedsDisplay:YES];
}

- (void)fitToWidth
{
    NSScrollView *scroll = [self enclosingScrollView];
    NSSize visible = scroll ? [[scroll contentView] bounds].size : [self frame].size;
    CGFloat height = [RSStyle headerHeight] + [_rows count] * [RSStyle rowHeight];
    NSSize size = NSMakeSize(visible.width, MAX(visible.height, height));
    if (!NSEqualSizes(size, [self frame].size)) [self setFrameSize:size];
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldSize
{
    [super resizeWithOldSuperviewSize:oldSize];
    [self fitToWidth];
}

- (NSRect)rectOfRow:(NSInteger)index
{
    return NSMakeRect(0, [RSStyle headerHeight] + index * [RSStyle rowHeight], NSWidth([self bounds]), [RSStyle rowHeight]);
}

- (NSInteger)rowAtPoint:(NSPoint)point
{
    CGFloat y = point.y - [RSStyle headerHeight];
    if (y < 0 || point.x < 0 || point.x > NSWidth([self bounds])) return -1;
    NSInteger i = (NSInteger)floor(y / [RSStyle rowHeight]);
    return i < (NSInteger)[_rows count] ? i : -1;
}

- (void)drawRect:(NSRect)dirty
{
    NSRect b = [self bounds];
    NSRect header = NSMakeRect(0, 0, NSWidth(b), [RSStyle headerHeight]);
    if ([_rows count] == 0) {
        [RSStyle drawEmptyShelfIn:b title:_emptyTitle ?: @"" message:_emptyMessage ?: @""];
        return;
    }
    if (NSIntersectsRect(header, dirty)) [RSStyle drawHeaderIn:header title:_title ?: @"" subtitle:_subtitle];
    for (NSInteger i = 0; i < (NSInteger)[_rows count]; i++) {
        NSRect r = [self rectOfRow:i];
        if (!NSIntersectsRect(r, dirty)) continue;
        [RSStyle drawRow:[_rows objectAtIndex:i] in:r hover:i == _hover pressed:i == _pressed selected:i == _selected];
    }
    // Under the last video, the bookcase carries on with empty shelves.
    CGFloat end = NSMaxY([self rectOfRow:(NSInteger)[_rows count] - 1]);
    if (NSMaxY(dirty) > end) [RSStyle drawBareShelvesIn:NSMakeRect(0, end, NSWidth(b), NSMaxY(b) - end) from:end];
}

// ---- Mouse ------------------------------------------------------------------

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    [_tracking release];
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                             options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited |
                                                     NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                               owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}

- (void)setRow:(NSInteger *)which to:(NSInteger)index
{
    if (*which == index) return;
    if (*which >= 0 && *which < (NSInteger)[_rows count]) [self setNeedsDisplayInRect:[self rectOfRow:*which]];
    *which = index;
    if (index >= 0) [self setNeedsDisplayInRect:[self rectOfRow:index]];
}

- (void)hoverRow:(NSInteger)index
{
    [self setRow:&_hover to:index];
}

- (void)mouseMoved:(NSEvent *)event
{
    [self hoverRow:[self rowAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]]];
}

- (void)mouseExited:(NSEvent *)event
{
    [self hoverRow:-1];
}

- (void)mouseDown:(NSEvent *)event
{
    NSInteger i = [self rowAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
    [self setRow:&_pressed to:i];
    [self setRow:&_selected to:i];
}

- (void)mouseDragged:(NSEvent *)event
{
    NSInteger i = [self rowAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
    [self setRow:&_pressed to:i == _selected ? i : -1];
}

- (void)mouseUp:(NSEvent *)event
{
    NSInteger i = [self rowAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
    BOOL chosen = i >= 0 && i == _pressed;
    [self setRow:&_pressed to:-1];
    if (chosen) [self choose:i];
}

- (void)choose:(NSInteger)index
{
    if (index < 0 || index >= (NSInteger)[_rows count]) return;
    RSRowModel *row = [_rows objectAtIndex:index];
    if ([row state] == RSRowReady) [_delegate shelfView:self choseRow:row];
    else NSBeep();
}

// ---- Keyboard: up and down to move, Return to play --------------------------

- (void)keyDown:(NSEvent *)event
{
    NSString *chars = [event charactersIgnoringModifiers];
    unichar c = [chars length] ? [chars characterAtIndex:0] : 0;
    NSInteger count = (NSInteger)[_rows count];
    if (count == 0) { [super keyDown:event]; return; }
    if (c == NSDownArrowFunctionKey || c == NSUpArrowFunctionKey) {
        NSInteger i = _selected < 0 ? 0 : _selected + (c == NSDownArrowFunctionKey ? 1 : -1);
        i = MAX(0, MIN(count - 1, i));
        [self setRow:&_selected to:i];
        [self scrollRectToVisible:[self rectOfRow:i]];
    } else if (c == '\r' || c == 3 || c == ' ') {
        [self choose:_selected];
    } else {
        [super keyDown:event];
    }
}

@end

@implementation RSStatusBar

- (void)dealloc
{
    [_text release];
    [super dealloc];
}

- (BOOL)isFlipped { return YES; }

- (void)setText:(NSString *)text
{
    [_text release];
    _text = [text copy];
    [self setNeedsDisplay:YES];
}

- (void)setProblem:(BOOL)problem
{
    _problem = problem;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirty
{
    [RSStyle drawStatusBarIn:[self bounds] text:_text problem:_problem];
}

@end

@implementation RSScroller

- (id)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame])) [self setKnobStyle:NSScrollerKnobStyleLight];
    return self;
}

- (void)drawKnobSlotInRect:(NSRect)slotRect highlight:(BOOL)flag
{
    [RSStyle drawScrollerSlotIn:slotRect];
}

@end
