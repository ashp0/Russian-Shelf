// How Russian Shelf looks: every font, colour, size and drawn shape, in
// this one file and RSStyle.m. The views (RSShelfView, RSPlayer) decide what
// goes where and ask this for everything else, so a new look is a new
// RSStyle.m.
//
// The look is 2013 skeuomorphic: a walnut bookcase. Each
// video stands on its own plank beside a cream library card in Georgia; a
// red silk ribbon marks the next one and a green ink stamp the finished ones.
// The header is a brass nameplate, the player's keys are real keycaps, and
// the transcript is ruled paper with a highlighter on the line being spoken.
// The wood is drawn here, once, into tiles (no image files).

#import <Cocoa/Cocoa.h>

typedef enum {
    RSRowReady = 0,         // downloaded: click to play
    RSRowWaiting,           // not downloaded yet
    RSRowDownloading,       // progress is a fraction
    RSRowFailed             // the last try failed; `note` says why
} RSRowState;

// One video on the shelf, as the shelf view draws it.
@interface RSRowModel : NSObject
@property (nonatomic, copy) NSString *identifier, *title, *channel, *note;
@property (nonatomic, retain) NSImage *thumbnail;     // nil: a placeholder
@property (nonatomic) RSRowState state;
@property (nonatomic) double progress;                // download, 0...1
@property (nonatomic) double duration;                // seconds, 0 if unknown
@property (nonatomic) double watched;                 // furthest point played, seconds
@property (nonatomic) BOOL finished, next;            // finished; the next one to watch
@end

@interface RSStyle : NSObject

// ---- Windows ----
+ (NSSize)shelfWindowSize;
+ (NSSize)shelfWindowMinSize;
+ (NSSize)playerVideoSize;            // the player's video area, to begin with
+ (CGFloat)transcriptWidth;
+ (NSColor *)windowBackground;

// ---- The shelf ----
+ (CGFloat)headerHeight;
+ (CGFloat)rowHeight;
+ (CGFloat)statusBarHeight;
+ (void)drawHeaderIn:(NSRect)rect title:(NSString *)title subtitle:(NSString *)subtitle;
+ (void)drawRow:(RSRowModel *)row in:(NSRect)rect hover:(BOOL)hover pressed:(BOOL)pressed selected:(BOOL)selected;
+ (void)drawEmptyShelfIn:(NSRect)rect title:(NSString *)title message:(NSString *)message;
// Bare shelves, rowHeight apart, for the space under the last video.
+ (void)drawBareShelvesIn:(NSRect)rect from:(CGFloat)top;
+ (void)drawStatusBarIn:(NSRect)rect text:(NSString *)text problem:(BOOL)problem;
+ (void)drawScrollerSlotIn:(NSRect)rect;        // the shelf's scroller track, in the wood
// The text a row shows under the title: "Sergey Storyteller · 11:30".
+ (NSString *)metaTextFor:(RSRowModel *)row;
+ (NSString *)progressTextFor:(RSRowModel *)row;

// ---- The player ----
+ (CGFloat)hintBarHeight;
+ (void)drawHintBarIn:(NSRect)rect items:(NSArray *)items;     // [@"Space", @"Play or pause", ...] pairs
+ (void)drawCaption:(NSString *)text in:(NSRect)videoRect;      // the revealed line, over the video
+ (void)drawCaptionPlaceholder:(NSString *)text in:(NSRect)videoRect;
+ (void)drawVideoPlaceholderIn:(NSRect)rect;                    // what the shots show where video goes

// ---- The transcript ----
+ (CGFloat)transcriptPadding;
+ (CGFloat)heightOfTranscriptLine:(NSString *)text width:(CGFloat)width;
+ (void)drawTranscriptLine:(NSString *)text time:(double)seconds in:(NSRect)rect current:(BOOL)current hover:(BOOL)hover;
+ (void)drawTranscriptBackgroundIn:(NSRect)rect;
+ (void)drawTranscriptEmptyIn:(NSRect)rect message:(NSString *)message;

// ---- Shared ----
+ (NSString *)clock:(double)seconds;                            // "4:10"

@end
