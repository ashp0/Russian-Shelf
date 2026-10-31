// How Shelf looks: every font, colour, size and drawn shape, in
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
@property (nonatomic, copy) NSString *kind;           // RSKind..., for the plate above its group
@end

// One line of the desk card: a thing to do today, in the research's order
// (DESIGN.md): Cards, Clip, Say, then the story. Each opens when clicked.
typedef enum {
    RSDeskCards = 0,
    RSDeskClip,
    RSDeskSay,
    RSDeskWatch
} RSDeskAction;

@interface RSDeskLine : NSObject
@property (nonatomic, copy) NSString *label, *text, *key;    // "Cards", "7 to hear again", "⌘L"
@property (nonatomic, copy) NSString *identifier;            // the video, for RSDeskWatch
@property (nonatomic) RSDeskAction action;
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
// The desk card under the crown: cream, "Today", one line per thing to do.
// Height 0 for no lines (then nothing is drawn).
+ (CGFloat)deskCardHeightForLines:(NSUInteger)count;
+ (NSArray *)deskLineRectsIn:(NSRect)rect count:(NSUInteger)count;      // NSValue rects, for clicks
+ (void)drawDeskCardIn:(NSRect)rect lines:(NSArray *)lines hover:(NSInteger)hover;
// A small brass plate on the back wall above a group of one kind.
+ (CGFloat)kindPlateHeight;
+ (void)drawKindPlateIn:(NSRect)rect title:(NSString *)title;
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

// ---- After watching: how was it? ----
// A dark slip at the top of the picture: "This video was  too easy · about
// right · too hard   more like this · less like this  ✕". The chosen words are
// shown as chosen; no stars, numbers or marks of any kind.
+ (NSArray *)feedbackChoices;                  // the five, in order (RSFelt..., RSWant...)
+ (NSSize)feedbackPanelSize;
+ (NSArray *)feedbackItemRectsIn:(NSRect)panel; // NSValue rects: the five choices, then the ✕
+ (void)drawFeedbackIn:(NSRect)panel felt:(NSString *)felt want:(NSString *)want hover:(NSInteger)hover;

// ---- A word looked up (RSDictionary) ----
// A cream slip at the top of the picture: the line's words as small cards,
// the chosen one lifted; under them the lemma with its stress, what kind of
// word, the glosses, and where it stands in the frequency list.
+ (NSSize)wordSlipSizeIn:(NSRect)videoRect words:(NSArray *)words;
+ (NSArray *)wordSlipItemRectsIn:(NSRect)slip words:(NSArray *)words;      // NSValue rects, one a word
+ (void)drawWordSlipIn:(NSRect)slip words:(NSArray *)words selected:(NSInteger)selected
                 lemma:(NSString *)lemma detail:(NSString *)detail rank:(NSString *)rank note:(NSString *)note
                 hover:(NSInteger)hover;

// ---- Today's clip (RSClips) ----
// A ruled card at the top of the picture: which stretch, the three passes
// with the one under way marked, what to do now, and the keys.
+ (NSSize)clipCardSizeIn:(NSRect)videoRect;
+ (void)drawClipCardIn:(NSRect)card span:(NSString *)span pass:(NSInteger)pass instruction:(NSString *)instruction
                  keys:(NSString *)keys recording:(BOOL)recording;

// ---- The transcript ----
+ (CGFloat)transcriptPadding;
+ (CGFloat)heightOfTranscriptLine:(NSString *)text width:(CGFloat)width;
+ (void)drawTranscriptLine:(NSString *)text time:(double)seconds in:(NSRect)rect current:(BOOL)current hover:(BOOL)hover;
+ (void)drawTranscriptBackgroundIn:(NSRect)rect;
+ (void)drawTranscriptEmptyIn:(NSRect)rect message:(NSString *)message;

// ---- Lines to hear again (RSReview) ----
+ (NSSize)reviewWindowSize;
// An index card on the bookcase's back, the keys along the bottom. `text`
// nil: the line is still hidden. `prompt`: the owner's own words, to say in
// Russian (then `text` is nil). `message` is for when there's no line up.
// `meaningRow`: leave room at the card's foot for the meaning field.
// `word`: a word card: that word is underlined in `text`, and `detail` (its
// lemma, kind and gloss) is written under the line.
+ (void)drawReviewIn:(NSRect)rect heading:(NSString *)heading source:(NSString *)source before:(NSString *)before
                text:(NSString *)text word:(NSString *)word detail:(NSString *)detail prompt:(NSString *)prompt
             message:(NSString *)message note:(NSString *)note meaningRow:(BOOL)meaningRow keys:(NSArray *)keys;
// Where the meaning field goes on the card, and how it looks.
+ (NSRect)reviewMeaningRectIn:(NSRect)rect note:(BOOL)note;
+ (void)styleMeaningField:(NSTextField *)field;

// ---- Shared ----
+ (NSString *)clock:(double)seconds;                            // "4:10"

@end
