#import "RSShelfView.h"
#import "RSShelf.h"

@interface RSShelfView () {
    NSInteger _hover, _pressed, _selected, _deskHover, _deskPressed;
    NSTrackingArea *_tracking;
    NSMutableArray *_tops;          // y of each row (rows grouped by kind, a plate before each group)
    NSMutableArray *_plates;        // {y, title} of each kind plate
    CGFloat _contentHeight;
}
- (void)layoutRows;
@end

@implementation RSShelfView

- (id)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        _hover = _pressed = _selected = _deskHover = _deskPressed = -1;
        _rows = [[NSArray alloc] init];
        _deskLines = [[NSArray alloc] init];
        _tops = [[NSMutableArray alloc] init];
        _plates = [[NSMutableArray alloc] init];
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
    [_deskLines release];
    [_tops release];
    [_plates release];
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
    [self layoutRows];
    [self fitToWidth];
    [self setNeedsDisplay:YES];
}

- (void)setDeskLines:(NSArray *)lines
{
    if (lines == _deskLines) return;
    [_deskLines release];
    _deskLines = [lines copy];
    _deskHover = _deskPressed = -1;
    [self layoutRows];
    [self fitToWidth];
    [self setNeedsDisplay:YES];
}

- (NSRect)deskCardRect
{
    CGFloat h = [RSStyle deskCardHeightForLines:[_deskLines count]];
    return NSMakeRect(0, [RSStyle headerHeight], NSWidth([self bounds]), h);
}

// Rows come grouped by kind (the controller orders them); a plate stands
// above each group when there is more than one kind.
- (void)layoutRows
{
    [_tops removeAllObjects];
    [_plates removeAllObjects];
    NSMutableSet *kinds = [NSMutableSet set];
    for (RSRowModel *row in _rows) if ([row kind]) [kinds addObject:[row kind]];
    BOOL plates = [kinds count] > 1;
    CGFloat y = [RSStyle headerHeight] + [RSStyle deskCardHeightForLines:[_deskLines count]];
    NSString *kind = nil;
    for (RSRowModel *row in _rows) {
        if (plates && [row kind] && ![[row kind] isEqualToString:kind]) {
            kind = [row kind];
            [_plates addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithDouble:y], @"y",
                                RSKindTitle(kind) ?: kind, @"title", nil]];
            y += [RSStyle kindPlateHeight];
        }
        [_tops addObject:[NSNumber numberWithDouble:y]];
        y += [RSStyle rowHeight];
    }
    _contentHeight = y;
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
    if ([_tops count] != [_rows count]) [self layoutRows];
    CGFloat height = _contentHeight;
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
    if (index < 0 || index >= (NSInteger)[_tops count]) return NSZeroRect;
    return NSMakeRect(0, [[_tops objectAtIndex:(NSUInteger)index] doubleValue], NSWidth([self bounds]), [RSStyle rowHeight]);
}

- (NSInteger)rowAtPoint:(NSPoint)point
{
    if (point.x < 0 || point.x > NSWidth([self bounds])) return -1;
    for (NSInteger i = 0; i < (NSInteger)[_rows count]; i++)
        if (NSPointInRect(point, [self rectOfRow:i])) return i;
    return -1;
}

- (NSInteger)deskLineAtPoint:(NSPoint)point
{
    NSArray *rects = [RSStyle deskLineRectsIn:[self deskCardRect] count:[_deskLines count] flipped:[self isFlipped]];
    for (NSUInteger i = 0; i < [rects count]; i++)
        if (NSPointInRect(point, NSInsetRect([[rects objectAtIndex:i] rectValue], -6, 0))) return (NSInteger)i;
    return -1;
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
    NSRect desk = [self deskCardRect];
    if (NSHeight(desk) > 0 && NSIntersectsRect(desk, dirty)) [RSStyle drawDeskCardIn:desk lines:_deskLines hover:_deskHover];
    for (NSDictionary *plate in _plates) {
        NSRect r = NSMakeRect(0, [[plate objectForKey:@"y"] doubleValue], NSWidth(b), [RSStyle kindPlateHeight]);
        if (NSIntersectsRect(r, dirty)) [RSStyle drawKindPlateIn:r title:[plate objectForKey:@"title"]];
    }
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

- (NSInteger)deskHover { return _deskHover; }

- (void)hoverDeskLine:(NSInteger)index
{
    if (_deskHover == index) return;
    _deskHover = index;
    [self setNeedsDisplayInRect:[self deskCardRect]];
}

- (void)mouseMoved:(NSEvent *)event
{
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    [self hoverRow:[self rowAtPoint:p]];
    [self hoverDeskLine:[self deskLineAtPoint:p]];
}

- (void)mouseExited:(NSEvent *)event
{
    [self hoverRow:-1];
    [self hoverDeskLine:-1];
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    _deskPressed = [self deskLineAtPoint:p];
    if (_deskPressed >= 0) return;
    NSInteger i = [self rowAtPoint:p];
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
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    if (_deskPressed >= 0) {
        NSInteger d = [self deskLineAtPoint:p];
        if (d == _deskPressed && d < (NSInteger)[_deskLines count]) [_delegate shelfView:self choseDeskLine:[_deskLines objectAtIndex:(NSUInteger)d]];
        _deskPressed = -1;
        return;
    }
    NSInteger i = [self rowAtPoint:p];
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
