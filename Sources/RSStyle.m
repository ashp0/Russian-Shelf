#import "RSStyle.h"
#import "RSReport.h"

@implementation RSRowModel

- (void)dealloc
{
    [_identifier release];
    [_title release];
    [_channel release];
    [_note release];
    [_thumbnail release];
    [super dealloc];
}

@end

// ---- Palette and type -------------------------------------------------------

static NSColor *RSRGB(unsigned int rgb, CGFloat alpha)
{
    return [NSColor colorWithCalibratedRed:((rgb >> 16) & 0xff) / 255.0 green:((rgb >> 8) & 0xff) / 255.0
                                      blue:(rgb & 0xff) / 255.0 alpha:alpha];
}

static NSColor *RSInk(void)        { return RSRGB(0x1d1d1f, 1); }
static NSColor *RSInkSoft(void)    { return RSRGB(0x6e6e73, 1); }
static NSColor *RSInkFaint(void)   { return RSRGB(0x9a9aa0, 1); }
static NSColor *RSAccent(void)     { return RSRGB(0x2f6fd6, 1); }   // what's next
static NSColor *RSDone(void)       { return RSRGB(0x3b8b3f, 1); }   // finished
static NSColor *RSProblem(void)    { return RSRGB(0xb3261e, 1); }
static NSColor *RSRule(void)       { return RSRGB(0xe3e3e6, 1); }
static NSColor *RSRowColor(void)   { return [NSColor whiteColor]; }

static NSFont *RSFont(CGFloat size)     { return [NSFont systemFontOfSize:size]; }
static NSFont *RSBold(CGFloat size)     { return [NSFont boldSystemFontOfSize:size]; }

static NSDictionary *RSText(NSFont *font, NSColor *color, NSTextAlignment alignment, NSLineBreakMode mode)
{
    NSMutableParagraphStyle *p = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [p setAlignment:alignment];
    [p setLineBreakMode:mode];
    return [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, color, NSForegroundColorAttributeName,
            p, NSParagraphStyleAttributeName, nil];
}

static CGFloat RSHeightOf(NSString *s, NSDictionary *attrs, CGFloat width)
{
    NSRect r = [s boundingRectWithSize:NSMakeSize(width, 10000)
                               options:NSStringDrawingUsesLineFragmentOrigin attributes:attrs];
    return ceil(NSHeight(r));
}

static void RSDrawText(NSString *s, NSDictionary *attrs, NSRect rect)
{
    [s drawWithRect:rect options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine
         attributes:attrs];
}

// A string's single line height in a font.
static CGFloat RSLineHeight(NSFont *font)
{
    return ceil([font ascender] - [font descender] + [font leading]);
}

// Text whose lines are all the font's own height, so an emoji (drawn from a
// taller fallback font) doesn't push the rest of the row down.
static NSDictionary *RSTextFixed(NSFont *font, NSColor *color)
{
    NSMutableParagraphStyle *p = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [p setLineBreakMode:NSLineBreakByWordWrapping];
    [p setMinimumLineHeight:RSLineHeight(font)];
    [p setMaximumLineHeight:RSLineHeight(font)];
    return [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, color, NSForegroundColorAttributeName,
            p, NSParagraphStyleAttributeName, nil];
}

@implementation RSStyle

+ (NSString *)clock:(double)seconds
{
    return RSClock(seconds);
}

// ---- Windows ----------------------------------------------------------------

+ (NSSize)shelfWindowSize      { return NSMakeSize(680, 820); }
+ (NSSize)shelfWindowMinSize   { return NSMakeSize(520, 400); }
+ (NSSize)playerVideoSize      { return NSMakeSize(960, 540); }
+ (CGFloat)transcriptWidth     { return 340; }
+ (NSColor *)windowBackground  { return RSRGB(0xececec, 1); }

// ---- The shelf --------------------------------------------------------------

+ (CGFloat)headerHeight     { return 66; }
+ (CGFloat)rowHeight        { return 114; }
+ (CGFloat)statusBarHeight  { return 24; }

+ (void)drawHeaderIn:(NSRect)rect title:(NSString *)title subtitle:(NSString *)subtitle
{
    [RSRowColor() set];
    NSRectFill(rect);
    [RSRule() set];
    NSRectFill(NSMakeRect(NSMinX(rect), NSMaxY(rect) - 1, NSWidth(rect), 1));
    NSDictionary *t = RSText(RSBold(18), RSInk(), NSLeftTextAlignment, NSLineBreakByTruncatingTail);
    NSDictionary *s = RSText(RSFont(12), RSInkSoft(), NSLeftTextAlignment, NSLineBreakByTruncatingTail);
    RSDrawText(title, t, NSMakeRect(NSMinX(rect) + 20, NSMinY(rect) + 13, NSWidth(rect) - 40, 24));
    if (subtitle) RSDrawText(subtitle, s, NSMakeRect(NSMinX(rect) + 20, NSMinY(rect) + 38, NSWidth(rect) - 40, 18));
}

+ (NSString *)metaTextFor:(RSRowModel *)row
{
    if ([row duration] > 0) return [NSString stringWithFormat:@"%@  ·  %@", [row channel], RSClock([row duration])];
    return [row channel];
}

+ (NSString *)progressTextFor:(RSRowModel *)row
{
    switch ([row state]) {
        case RSRowWaiting:     return @"Waiting to download";
        case RSRowDownloading: return [row progress] >= 0.999 ? @"Finishing the download…"
                                      : [NSString stringWithFormat:@"Downloading… %d%%", (int)([row progress] * 100)];
        case RSRowFailed:      return [NSString stringWithFormat:@"Couldn’t download. %@", [row note] ?: @""];
        case RSRowReady:       break;
    }
    if ([row finished]) return @"✓ Finished";
    if ([row watched] >= 1 && [row duration] > 0)
        return [NSString stringWithFormat:@"Watched %@ of %@", RSClock([row watched]), RSClock([row duration])];
    return @"Not started";
}

static void RSDrawBar(NSRect r, double fraction, NSColor *fill)
{
    NSBezierPath *track = [NSBezierPath bezierPathWithRoundedRect:r xRadius:NSHeight(r) / 2 yRadius:NSHeight(r) / 2];
    [RSRGB(0xe6e6ea, 1) set];
    [track fill];
    if (fraction <= 0) return;
    NSRect f = r;
    f.size.width = MAX(NSHeight(r), round(NSWidth(r) * MIN(1, fraction)));
    [fill set];
    [[NSBezierPath bezierPathWithRoundedRect:f xRadius:NSHeight(r) / 2 yRadius:NSHeight(r) / 2] fill];
}

static void RSDrawThumbnail(NSImage *image, NSRect r, BOOL dim)
{
    [NSGraphicsContext saveGraphicsState];
    NSBezierPath *clip = [NSBezierPath bezierPathWithRoundedRect:r xRadius:3 yRadius:3];
    [clip addClip];
    if (image) {
        NSSize s = [image size];
        // Fill the frame, cropping what's over (YouTube thumbnails are 16:9 already).
        CGFloat scale = MAX(NSWidth(r) / MAX(1, s.width), NSHeight(r) / MAX(1, s.height));
        NSSize d = NSMakeSize(s.width * scale, s.height * scale);
        NSRect dest = NSMakeRect(NSMidX(r) - d.width / 2, NSMidY(r) - d.height / 2, d.width, d.height);
        [image drawInRect:dest fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:dim ? 0.45 : 1
           respectFlipped:YES hints:nil];
    } else {
        [RSRGB(0xd9d9de, 1) set];
        NSRectFill(r);
        NSBezierPath *play = [NSBezierPath bezierPath];
        [play moveToPoint:NSMakePoint(NSMidX(r) - 9, NSMidY(r) - 12)];
        [play lineToPoint:NSMakePoint(NSMidX(r) + 13, NSMidY(r))];
        [play lineToPoint:NSMakePoint(NSMidX(r) - 9, NSMidY(r) + 12)];
        [play closePath];
        [RSRGB(0xffffff, 0.9) set];
        [play fill];
    }
    [NSGraphicsContext restoreGraphicsState];
    [RSRGB(0x000000, 0.12) set];
    NSBezierPath *edge = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, 0.5, 0.5) xRadius:3 yRadius:3];
    [edge setLineWidth:1];
    [edge stroke];
}

+ (void)drawRow:(RSRowModel *)row in:(NSRect)rect hover:(BOOL)hover pressed:(BOOL)pressed selected:(BOOL)selected
{
    BOOL playable = [row state] == RSRowReady;
    NSColor *back = RSRowColor();
    if (playable && pressed) back = RSRGB(0xdfe8f7, 1);
    else if (playable && hover) back = RSRGB(0xf2f5fb, 1);
    else if (selected) back = RSRGB(0xf2f5fb, 1);
    [back set];
    NSRectFill(rect);
    [RSRule() set];
    NSRectFill(NSMakeRect(NSMinX(rect) + 20, NSMaxY(rect) - 1, NSWidth(rect) - 20, 1));
    if ([row next]) {
        [RSAccent() set];
        NSRectFill(NSMakeRect(NSMinX(rect), NSMinY(rect), 4, NSHeight(rect) - 1));
    }

    NSRect thumb = NSMakeRect(NSMinX(rect) + 20, NSMinY(rect) + 12, 160, 90);
    RSDrawThumbnail([row thumbnail], thumb, !playable);

    CGFloat x = NSMaxX(thumb) + 16, width = NSMaxX(rect) - x - 20, y = NSMinY(rect) + 12;
    if ([row next]) {
        RSDrawText(@"NEXT", RSText(RSBold(10), RSAccent(), NSLeftTextAlignment, NSLineBreakByClipping),
                   NSMakeRect(x, y, width, 14));
        y += 15;
    }
    NSDictionary *title = RSTextFixed(RSBold(14), playable ? RSInk() : RSInkSoft());
    CGFloat lines = [row next] ? 1 : 2;
    CGFloat titleHeight = MIN(RSHeightOf([row title], title, width), RSLineHeight(RSBold(14)) * lines);
    RSDrawText([row title], title, NSMakeRect(x, y, width, titleHeight));
    y += titleHeight + 3;
    RSDrawText([self metaTextFor:row], RSText(RSFont(12), RSInkSoft(), NSLeftTextAlignment, NSLineBreakByTruncatingTail),
               NSMakeRect(x, y, width, 16));

    // The bottom line: how far, or the download.
    CGFloat bottom = NSMinY(rect) + 12 + 90;
    NSColor *noteColor = [row state] == RSRowFailed ? RSProblem() : [row finished] && playable ? RSDone() : RSInkSoft();
    NSFont *noteFont = [row finished] && playable ? RSBold(11) : RSFont(11);
    RSDrawText([self progressTextFor:row], RSText(noteFont, noteColor, NSLeftTextAlignment, NSLineBreakByTruncatingTail),
               NSMakeRect(x, bottom - 24, width, 15));
    NSRect bar = NSMakeRect(x, bottom - 5, MIN(220, width), 4);
    if ([row state] == RSRowDownloading) RSDrawBar(bar, [row progress], RSInkFaint());
    else if (playable && [row duration] > 0) RSDrawBar(bar, [row finished] ? 1 : [row watched] / [row duration],
                                                       [row finished] ? RSDone() : RSAccent());
}

+ (void)drawEmptyShelfIn:(NSRect)rect title:(NSString *)title message:(NSString *)message
{
    [RSRowColor() set];
    NSRectFill(rect);
    CGFloat width = MIN(420, NSWidth(rect) - 60);
    NSDictionary *t = RSText(RSBold(15), RSInk(), NSCenterTextAlignment, NSLineBreakByWordWrapping);
    NSDictionary *m = RSText(RSFont(12), RSInkSoft(), NSCenterTextAlignment, NSLineBreakByWordWrapping);
    CGFloat th = RSHeightOf(title, t, width), mh = RSHeightOf(message, m, width);
    CGFloat y = NSMinY(rect) + MAX(40, (NSHeight(rect) - th - mh - 8) * 0.38);
    RSDrawText(title, t, NSMakeRect(NSMidX(rect) - width / 2, y, width, th));
    RSDrawText(message, m, NSMakeRect(NSMidX(rect) - width / 2, y + th + 8, width, mh));
}

+ (void)drawStatusBarIn:(NSRect)rect text:(NSString *)text problem:(BOOL)problem
{
    [[self windowBackground] set];
    NSRectFill(rect);
    [RSRGB(0xc8c8cc, 1) set];
    NSRectFill(NSMakeRect(NSMinX(rect), NSMinY(rect), NSWidth(rect), 1));
    RSDrawText(text ?: @"", RSText(RSFont(11), problem ? RSProblem() : RSInkSoft(), NSLeftTextAlignment, NSLineBreakByTruncatingTail),
               NSMakeRect(NSMinX(rect) + 12, NSMinY(rect) + 5, NSWidth(rect) - 24, 15));
}

// ---- The player -------------------------------------------------------------

+ (CGFloat)hintBarHeight { return 28; }

+ (void)drawHintBarIn:(NSRect)rect items:(NSArray *)items
{
    [RSRGB(0x1c1c1e, 1) set];
    NSRectFill(rect);
    NSDictionary *key = RSText([NSFont boldSystemFontOfSize:10.5], RSRGB(0xf2f2f2, 1), NSCenterTextAlignment, NSLineBreakByClipping);
    NSDictionary *label = RSText(RSFont(11), RSRGB(0xb8b8bc, 1), NSLeftTextAlignment, NSLineBreakByClipping);
    CGFloat x = NSMinX(rect) + 12, mid = NSMidY(rect);
    for (NSUInteger i = 0; i + 1 < [items count]; i += 2) {
        NSString *k = [items objectAtIndex:i], *l = [items objectAtIndex:i + 1];
        CGFloat kw = MAX(18, ceil([k sizeWithAttributes:key].width) + 10);
        CGFloat lw = ceil([l sizeWithAttributes:label].width);
        if (x + kw + 5 + lw > NSMaxX(rect) - 8) break;
        NSRect cap = NSMakeRect(x, mid - 9, kw, 18);
        [RSRGB(0x3a3a3c, 1) set];
        [[NSBezierPath bezierPathWithRoundedRect:cap xRadius:4 yRadius:4] fill];
        [k drawInRect:NSMakeRect(NSMinX(cap), NSMinY(cap) + 2, kw, 15) withAttributes:key];
        [l drawInRect:NSMakeRect(NSMaxX(cap) + 5, mid - 8, lw + 2, 16) withAttributes:label];
        x = NSMaxX(cap) + 5 + lw + 16;
    }
}

static void RSDrawCaptionBox(NSString *text, NSRect videoRect, NSFont *font, NSColor *color)
{
    if ([text length] == 0 || NSWidth(videoRect) < 50) return;
    CGFloat maxWidth = round(NSWidth(videoRect) * 0.82);
    NSShadow *shadow = [[[NSShadow alloc] init] autorelease];
    [shadow setShadowColor:RSRGB(0x000000, 0.9)];
    [shadow setShadowBlurRadius:2];
    [shadow setShadowOffset:NSMakeSize(0, -1)];
    NSMutableDictionary *attrs = [[RSText(font, color, NSCenterTextAlignment, NSLineBreakByWordWrapping) mutableCopy] autorelease];
    [attrs setObject:shadow forKey:NSShadowAttributeName];
    NSRect bounds = [text boundingRectWithSize:NSMakeSize(maxWidth, 10000) options:NSStringDrawingUsesLineFragmentOrigin attributes:attrs];
    CGFloat w = ceil(NSWidth(bounds)), h = ceil(NSHeight(bounds));
    // Above AVPlayerView's control bar (about 40 points), in the lower part.
    CGFloat bottomGap = MAX(52, round(NSHeight(videoRect) * 0.10));
    NSRect box = NSMakeRect(round(NSMidX(videoRect) - w / 2) - 14, 0, w + 28, h + 12);
    BOOL flipped = [[NSGraphicsContext currentContext] isFlipped];
    box.origin.y = flipped ? NSMaxY(videoRect) - bottomGap - NSHeight(box) : NSMinY(videoRect) + bottomGap;
    [RSRGB(0x000000, 0.62) set];
    [[NSBezierPath bezierPathWithRoundedRect:box xRadius:6 yRadius:6] fill];
    [text drawWithRect:NSMakeRect(NSMinX(box) + 14, NSMinY(box) + 6, w, h)
               options:NSStringDrawingUsesLineFragmentOrigin attributes:attrs];
}

+ (void)drawCaption:(NSString *)text in:(NSRect)videoRect
{
    CGFloat size = MAX(18, MIN(34, round(NSHeight(videoRect) * 0.046)));
    RSDrawCaptionBox(text, videoRect, [NSFont systemFontOfSize:size], [NSColor whiteColor]);
}

+ (void)drawCaptionPlaceholder:(NSString *)text in:(NSRect)videoRect
{
    CGFloat size = MAX(13, MIN(20, round(NSHeight(videoRect) * 0.028)));
    RSDrawCaptionBox(text, videoRect, [NSFont systemFontOfSize:size], RSRGB(0xd0d0d4, 1));
}

+ (void)drawVideoPlaceholderIn:(NSRect)rect
{
    NSGradient *g = [[[NSGradient alloc] initWithStartingColor:RSRGB(0x3a4a5c, 1) endingColor:RSRGB(0x161b22, 1)] autorelease];
    [g drawInRect:rect angle:[[NSGraphicsContext currentContext] isFlipped] ? 90 : -90];
}

// ---- The transcript ---------------------------------------------------------

+ (CGFloat)transcriptPadding { return 10; }

static NSDictionary *RSTranscriptText(BOOL current)
{
    return RSText(current ? RSBold(13) : RSFont(13), RSInk(), NSLeftTextAlignment, NSLineBreakByWordWrapping);
}

+ (CGFloat)heightOfTranscriptLine:(NSString *)text width:(CGFloat)width
{
    CGFloat textWidth = width - 2 * [self transcriptPadding] - 46;
    return MAX(RSHeightOf(text, RSTranscriptText(YES), textWidth), RSHeightOf(text, RSTranscriptText(NO), textWidth)) + 12;
}

+ (void)drawTranscriptLine:(NSString *)text time:(double)seconds in:(NSRect)rect current:(BOOL)current hover:(BOOL)hover
{
    if (current) {
        [RSRGB(0xfff1b8, 1) set];
        NSRectFill(rect);
        [RSRGB(0xe0b400, 1) set];
        NSRectFill(NSMakeRect(NSMinX(rect), NSMinY(rect), 3, NSHeight(rect)));
    } else if (hover) {
        [RSRGB(0xf1f1f4, 1) set];
        NSRectFill(rect);
    }
    CGFloat pad = [self transcriptPadding];
    // 10.9's system font, Lucida Grande, already has digits of one width.
    NSDictionary *time = RSText(RSFont(11), RSInkFaint(),
                                NSRightTextAlignment, NSLineBreakByClipping);
    RSDrawText(RSClock(seconds), time, NSMakeRect(NSMinX(rect) + pad, NSMinY(rect) + 7, 36, 15));
    RSDrawText(text, RSTranscriptText(current), NSMakeRect(NSMinX(rect) + pad + 46, NSMinY(rect) + 6,
                                                           NSWidth(rect) - 2 * pad - 46, NSHeight(rect) - 10));
}

+ (void)drawTranscriptBackgroundIn:(NSRect)rect
{
    [RSRowColor() set];
    NSRectFill(rect);
}

+ (void)drawTranscriptEmptyIn:(NSRect)rect message:(NSString *)message
{
    [self drawTranscriptBackgroundIn:rect];
    NSDictionary *m = RSText(RSFont(12), RSInkSoft(), NSCenterTextAlignment, NSLineBreakByWordWrapping);
    RSDrawText(message, m, NSMakeRect(NSMinX(rect) + 20, NSMinY(rect) + 40, NSWidth(rect) - 40, 80));
}

@end
