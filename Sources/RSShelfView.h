// The shelf: the week's videos in Claude's order, drawn by RSStyle, under a
// header saying which week. A click (or Return) on a downloaded video asks the
// delegate to play it. Nothing else happens here: no search, no links, no
// dragging in or out.

#import <Cocoa/Cocoa.h>
#import "RSStyle.h"

@class RSShelfView;

@protocol RSShelfViewDelegate <NSObject>
- (void)shelfView:(RSShelfView *)view choseRow:(RSRowModel *)row;
- (void)shelfView:(RSShelfView *)view choseDeskLine:(RSDeskLine *)line;
@end

@interface RSShelfView : NSView

@property (nonatomic, assign) id<RSShelfViewDelegate> delegate;
@property (nonatomic, copy) NSString *title, *subtitle;            // the header
@property (nonatomic, copy) NSString *emptyTitle, *emptyMessage;   // when there are no rows
@property (nonatomic, copy) NSArray *rows;                         // RSRowModel, grouped by kind
@property (nonatomic, copy) NSArray *deskLines;                    // RSDeskLine; empty: no card

- (NSInteger)rowAtPoint:(NSPoint)point;
- (NSRect)rectOfRow:(NSInteger)index;
- (void)fitToWidth;      // height for the rows, at least the visible height
- (void)hoverRow:(NSInteger)index;     // for the screenshots
- (void)hoverDeskLine:(NSInteger)index;
- (NSInteger)deskLineAtPoint:(NSPoint)point;      // in the view's coordinates; -1 for none
- (NSInteger)deskHover;
- (NSRect)deskCardRect;

@end

// The line along the bottom of the shelf window.
@interface RSStatusBar : NSView
@property (nonatomic, copy) NSString *text;
@property (nonatomic) BOOL problem;
@end

// The shelf's scroller: a light knob in a slot cut into the wood, where a
// legacy (always-shown) scroller would otherwise put a white track.
@interface RSScroller : NSScroller
@end
