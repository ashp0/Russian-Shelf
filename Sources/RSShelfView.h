// The shelf: the week's videos in Claude's order, drawn by RSStyle, under a
// header saying which week. A click (or Return) on a downloaded video asks the
// delegate to play it. Nothing else happens here: no search, no links, no
// dragging in or out.

#import <Cocoa/Cocoa.h>
#import "RSStyle.h"

@class RSShelfView;

@protocol RSShelfViewDelegate <NSObject>
- (void)shelfView:(RSShelfView *)view choseRow:(RSRowModel *)row;
@end

@interface RSShelfView : NSView

@property (nonatomic, assign) id<RSShelfViewDelegate> delegate;
@property (nonatomic, copy) NSString *title, *subtitle;            // the header
@property (nonatomic, copy) NSString *emptyTitle, *emptyMessage;   // when there are no rows
@property (nonatomic, copy) NSArray *rows;                         // RSRowModel

- (NSInteger)rowAtPoint:(NSPoint)point;
- (NSRect)rectOfRow:(NSInteger)index;
- (void)fitToWidth;      // height for the rows, at least the visible height
- (void)hoverRow:(NSInteger)index;     // for the screenshots

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
