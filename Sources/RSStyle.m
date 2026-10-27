#import "RSStyle.h"
#import "RSReport.h"
#include <math.h>

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

// Ink on the cards: brown-black, like a typewriter ribbon on card stock.
static NSColor *RSInk(void)        { return RSRGB(0x2b2118, 1); }
static NSColor *RSInkSoft(void)    { return RSRGB(0x6f5f4c, 1); }
static NSColor *RSInkFaint(void)   { return RSRGB(0xa08f78, 1); }
static NSColor *RSRibbon(void)     { return RSRGB(0xb8262b, 1); }   // what's next
static NSColor *RSStampInk(void)   { return RSRGB(0x2f7a3a, 1); }   // finished
static NSColor *RSProblem(void)    { return RSRGB(0xb3261e, 1); }
static NSColor *RSCream(void)      { return RSRGB(0xf1e4c6, 1); }   // type on the wood

static NSFont *RSFont(CGFloat size)     { return [NSFont systemFontOfSize:size]; }
static NSFont *RSBold(CGFloat size)     { return [NSFont boldSystemFontOfSize:size]; }

// Georgia is on every Mac since 10.0 and has Cyrillic; the system font stands
// in if it's ever missing.
static NSFont *RSSerif(CGFloat size)
{
    return [NSFont fontWithName:@"Georgia" size:size] ?: RSFont(size);
}

static NSFont *RSSerifBold(CGFloat size)
{
    return [NSFont fontWithName:@"Georgia-Bold" size:size] ?: RSBold(size);
}

static NSFont *RSSerifItalic(CGFloat size)
{
    return [NSFont fontWithName:@"Georgia-Italic" size:size] ?: RSFont(size);
}

static NSDictionary *RSText(NSFont *font, NSColor *color, NSTextAlignment alignment, NSLineBreakMode mode)
{
    NSMutableParagraphStyle *p = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [p setAlignment:alignment];
    [p setLineBreakMode:mode];
    return [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, color, NSForegroundColorAttributeName,
            p, NSParagraphStyleAttributeName, nil];
}

// The same, with a one-point shadow: light under engraved type, dark under
// type printed on the wood.
static NSDictionary *RSTextShadowed(NSFont *font, NSColor *color, NSTextAlignment alignment, NSColor *shadowColor, CGFloat dy)
{
    NSShadow *shadow = [[[NSShadow alloc] init] autorelease];
    [shadow setShadowColor:shadowColor];
    [shadow setShadowOffset:NSMakeSize(0, dy)];
    [shadow setShadowBlurRadius:0];
    NSMutableDictionary *d = [[RSText(font, color, alignment, NSLineBreakByTruncatingTail) mutableCopy] autorelease];
    [d setObject:shadow forKey:NSShadowAttributeName];
    return d;
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

static void RSShadowOn(CGFloat dy, CGFloat blur, CGFloat alpha)
{
    NSShadow *s = [[[NSShadow alloc] init] autorelease];
    [s setShadowColor:RSRGB(0x000000, alpha)];
    // NSShadow offsets are in base space: negative is down, flipped view or not.
    [s setShadowOffset:NSMakeSize(0, -dy)];
    [s setShadowBlurRadius:blur];
    [s set];
}

static BOOL RSFlipped(void)
{
    return [[NSGraphicsContext currentContext] isFlipped];
}

// The visual top and bottom of a rect, whichever way the view is flipped.
static NSRect RSTopStrip(NSRect r, CGFloat h)
{
    return RSFlipped() ? NSMakeRect(NSMinX(r), NSMinY(r), NSWidth(r), h) : NSMakeRect(NSMinX(r), NSMaxY(r) - h, NSWidth(r), h);
}

static NSRect RSBottomStrip(NSRect r, CGFloat h)
{
    return RSFlipped() ? NSMakeRect(NSMinX(r), NSMaxY(r) - h, NSWidth(r), h) : NSMakeRect(NSMinX(r), NSMinY(r), NSWidth(r), h);
}

// A gradient from the visual top of a rect to its bottom.
static void RSDrawDown(NSGradient *g, NSRect r)
{
    [g drawInRect:r angle:RSFlipped() ? 90 : -90];
}

// ---- Wood -------------------------------------------------------------------
//
// Walnut, drawn once into 256-point tiles at twice the pixels, so it's sharp
// on a Retina screen and in the @2x shots. Every noise term wraps at the
// tile's edge, so the tiles meet without a seam. The grain runs across, as
// in a bookcase's boards.

static double RSHash(int x, int y, int seed)
{
    unsigned int h = (unsigned int)(x * 374761393 + y * 668265263 + seed * 2246822519u);
    h = (h ^ (h >> 13)) * 1274126177u;
    h ^= h >> 16;
    return (h & 0xffff) / 65535.0;
}

// Smooth noise along one axis, wrapping every `period` cells.
static double RSNoise1(double v, int period, int seed, int salt)
{
    int i = (int)floor(v), j = i + 1;
    double f = v - i, s = f * f * (3 - 2 * f);
    i = ((i % period) + period) % period;
    j = ((j % period) + period) % period;
    return RSHash(i, salt, seed) * (1 - s) + RSHash(j, salt, seed) * s;
}

static NSImage *RSWoodTile(unsigned light, unsigned dark, int seed, double rings)
{
    const int px = 512;
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:px pixelsHigh:px
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace
        bytesPerRow:px * 4 bitsPerPixel:32] autorelease];
    unsigned char *data = [rep bitmapData];
    double lr = (light >> 16) & 0xff, lg = (light >> 8) & 0xff, lb = light & 0xff;
    double dr = (dark >> 16) & 0xff, dg = (dark >> 8) & 0xff, db = dark & 0xff;
    for (int y = 0; y < px; y++) {
        for (int x = 0; x < px; x++) {
            double u = (double)x / px;
            // The grain drifts gently up and down along the board.
            double drift = 10 * (RSNoise1(u * 4, 4, seed, 1) - 0.5) + 4 * (RSNoise1(u * 9, 9, seed, 2) - 0.5);
            double v = y + drift;
            // Broad figure: a few soft bands per tile, of uneven width.
            double figure = RSNoise1(v / px * rings, (int)rings, seed, 3);
            // Fine grain lines: per-line noise, thin and close.
            double lines = RSNoise1(v / 2.0, px / 2, seed, 4);
            double fine = RSNoise1(v / 8.0, px / 8, seed, 5);
            // Pores: short dark flecks along the grain.
            int cell = 24, cx = x / cell, nx = (cx + 1) % ((px + cell - 1) / cell);
            double f = (double)(x % cell) / cell;
            int row = ((int)floor(v) % px + px) % px;
            double pore = RSHash(cx, row, seed + 7) * (1 - f) + RSHash(nx, row, seed + 7) * f;
            double g = 0.25 + 0.45 * figure + 0.16 * lines + 0.12 * fine - (pore > 0.93 ? 0.12 : 0);
            g = g < 0 ? 0 : g > 1 ? 1 : g;
            unsigned char *p = data + (y * px + x) * 4;
            p[0] = (unsigned char)(dr + (lr - dr) * g);
            p[1] = (unsigned char)(dg + (lg - dg) * g);
            p[2] = (unsigned char)(db + (lb - db) * g);
            p[3] = 255;
        }
    }
    [rep setSize:NSMakeSize(px / 2, px / 2)];
    NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(px / 2, px / 2)] autorelease];
    [image addRepresentation:rep];
    return image;
}

static NSImage *RSBackWood(void)
{
    static NSImage *tile;
    if (tile == nil) tile = [RSWoodTile(0x6a4227, 0x351f11, 3, 8) retain];
    return tile;
}

static NSImage *RSPlankWood(void)
{
    static NSImage *tile;
    if (tile == nil) tile = [RSWoodTile(0xb47a48, 0x7a4825, 11, 4) retain];
    return tile;
}

// Tiles laid from the view's origin, so the wood scrolls with what's on it
// and adjacent rows' wood lines up.
static void RSDrawTiled(NSImage *tile, NSRect rect)
{
    NSSize s = [tile size];
    [NSGraphicsContext saveGraphicsState];
    NSRectClip(rect);
    CGFloat x0 = floor(NSMinX(rect) / s.width) * s.width, y0 = floor(NSMinY(rect) / s.height) * s.height;
    for (CGFloat y = y0; y < NSMaxY(rect); y += s.height)
        for (CGFloat x = x0; x < NSMaxX(rect); x += s.width)
            [tile drawInRect:NSMakeRect(x, y, s.width, s.height) fromRect:NSZeroRect operation:NSCompositeCopy
                    fraction:1 respectFlipped:YES hints:nil];
    [NSGraphicsContext restoreGraphicsState];
}

// The bookcase's back, behind the shelves.
static void RSDrawBack(NSRect rect)
{
    RSDrawTiled(RSBackWood(), rect);
}

// The shadow a shelf (or the crown) casts on the back just under it.
static void RSDrawCastShadow(NSRect rect, CGFloat depth)
{
    NSGradient *g = [[[NSGradient alloc] initWithStartingColor:RSRGB(0x000000, 0.55) endingColor:RSRGB(0x000000, 0)] autorelease];
    RSDrawDown(g, RSTopStrip(rect, depth));
}

static CGFloat const RSPlankHeight = 14;

// A plank seen from the front: its top in light, its edge in wood, a dark
// line under it.
static void RSDrawPlank(NSRect plank)
{
    RSDrawTiled(RSPlankWood(), plank);
    [RSRGB(0xffe2b8, 0.35) set];
    NSRectFillUsingOperation(RSTopStrip(plank, 1), NSCompositeSourceOver);
    NSGradient *top = [[[NSGradient alloc] initWithStartingColor:RSRGB(0xffffff, 0.16) endingColor:RSRGB(0xffffff, 0)] autorelease];
    RSDrawDown(top, RSTopStrip(NSInsetRect(plank, 0, 0), 5));
    NSGradient *front = [[[NSGradient alloc] initWithStartingColor:RSRGB(0x000000, 0) endingColor:RSRGB(0x000000, 0.28)] autorelease];
    RSDrawDown(front, RSBottomStrip(plank, NSHeight(plank) - 5));
    [RSRGB(0x1e1109, 0.9) set];
    NSRectFillUsingOperation(RSBottomStrip(plank, 1), NSCompositeSourceOver);
}

// A row's worth of bookcase: back, the shadow of the shelf above, and its own plank.
static NSRect RSDrawBay(NSRect rect)
{
    RSDrawBack(rect);
    RSDrawCastShadow(rect, 12);
    NSRect plank = RSBottomStrip(rect, RSPlankHeight);
    RSDrawPlank(plank);
    return plank;
}

// ---- Brass, paper, keys -----------------------------------------------------

static void RSDrawScrew(NSPoint c, CGFloat r)
{
    NSRect box = NSMakeRect(c.x - r, c.y - r, 2 * r, 2 * r);
    NSGradient *g = [[[NSGradient alloc] initWithColorsAndLocations:RSRGB(0xfff2c4, 1), 0.0, RSRGB(0xb08a3c, 1), 0.6,
                      RSRGB(0x7a5c22, 1), 1.0, nil] autorelease];
    [g drawInBezierPath:[NSBezierPath bezierPathWithOvalInRect:box] angle:RSFlipped() ? 60 : -60];
    [RSRGB(0x5a4214, 0.9) set];
    NSBezierPath *slot = [NSBezierPath bezierPath];
    [slot moveToPoint:NSMakePoint(c.x - r * 0.7, c.y + r * 0.35)];
    [slot lineToPoint:NSMakePoint(c.x + r * 0.7, c.y - r * 0.35)];
    [slot setLineWidth:1];
    [slot stroke];
}

// A brass plate with an engraved title, screwed to the crown.
static void RSDrawBrassPlate(NSRect plate, NSString *title, NSString *subtitle)
{
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:plate xRadius:4 yRadius:4];
    [NSGraphicsContext saveGraphicsState];
    RSShadowOn(2, 4, 0.6);
    [RSRGB(0x8a6a2a, 1) set];
    [outline fill];
    [NSGraphicsContext restoreGraphicsState];
    NSGradient *brass = [[[NSGradient alloc] initWithColorsAndLocations:RSRGB(0xf6e3a4, 1), 0.0, RSRGB(0xe0c06e, 1), 0.35,
                          RSRGB(0xc79f48, 1), 0.7, RSRGB(0xb08636, 1), 1.0, nil] autorelease];
    NSBezierPath *face = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(plate, 1, 1) xRadius:3 yRadius:3];
    [brass drawInBezierPath:face angle:RSFlipped() ? 90 : -90];
    // Brushed lines across the metal.
    [NSGraphicsContext saveGraphicsState];
    [face addClip];
    for (CGFloat y = NSMinY(plate) + 2; y < NSMaxY(plate); y += 2) {
        [RSRGB(((int)y / 2) % 3 ? 0xffffff : 0x000000, 0.05) set];
        NSRectFillUsingOperation(NSMakeRect(NSMinX(plate), y, NSWidth(plate), 1), NSCompositeSourceOver);
    }
    [NSGraphicsContext restoreGraphicsState];
    [RSRGB(0xfff6d6, 0.8) set];
    NSRectFillUsingOperation(RSTopStrip(NSInsetRect(plate, 4, 1), 1), NSCompositeSourceOver);
    [RSRGB(0x6b4f18, 0.9) set];
    [outline setLineWidth:1];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(plate, 0.5, 0.5) xRadius:4 yRadius:4] stroke];

    CGFloat r = 3.5, inset = 9;
    RSDrawScrew(NSMakePoint(NSMinX(plate) + inset, NSMidY(plate)), r);
    RSDrawScrew(NSMakePoint(NSMaxX(plate) - inset, NSMidY(plate)), r);

    // Engraved: dark letters with a bright edge under them.
    CGFloat textWidth = NSWidth(plate) - 2 * (inset + 10);
    NSDictionary *t = RSTextShadowed(RSSerifBold(17), RSRGB(0x3d2a0a, 1), NSCenterTextAlignment, RSRGB(0xfff3cf, 0.75), -1);
    NSDictionary *s = RSTextShadowed(RSSerifItalic(11.5), RSRGB(0x5a4318, 1), NSCenterTextAlignment, RSRGB(0xfff3cf, 0.6), -1);
    BOOL flipped = RSFlipped();
    CGFloat titleHeight = 22, subtitleHeight = subtitle ? 16 : 0, total = titleHeight + subtitleHeight;
    CGFloat top = round(NSMidY(plate) - total / 2);
    NSRect titleRect = NSMakeRect(NSMidX(plate) - textWidth / 2, flipped ? top : NSMaxY(plate) - (top - NSMinY(plate)) - titleHeight,
                                  textWidth, titleHeight);
    RSDrawText(title, t, titleRect);
    if (subtitle) {
        NSRect subRect = NSMakeRect(NSMinX(titleRect), flipped ? NSMaxY(titleRect) : NSMinY(titleRect) - subtitleHeight,
                                    textWidth, subtitleHeight);
        RSDrawText(subtitle, s, subRect);
    }
}

// Cream card stock, lying flat on the shelf's back with a soft shadow.
static void RSDrawCard(NSRect card, CGFloat brighten, BOOL lifted)
{
    [NSGraphicsContext saveGraphicsState];
    RSShadowOn(lifted ? 3 : 2, lifted ? 7 : 4, 0.55);
    [RSRGB(0xf3ead6, 1) set];
    NSRectFill(card);
    [NSGraphicsContext restoreGraphicsState];
    NSGradient *paper = [[[NSGradient alloc] initWithStartingColor:RSRGB(0xfdf8ec, 1) endingColor:RSRGB(0xf0e5cc, 1)] autorelease];
    RSDrawDown(paper, card);
    if (brighten > 0) {
        [RSRGB(0xffffff, brighten) set];
        NSRectFillUsingOperation(card, NSCompositeSourceOver);
    } else if (brighten < 0) {
        [RSRGB(0x8a6a3a, -brighten) set];
        NSRectFillUsingOperation(card, NSCompositeSourceOver);
    }
    // The card's cut edge.
    [RSRGB(0xd9cba8, 1) set];
    NSFrameRectWithWidth(card, 1);
}

// The red silk ribbon hanging over the top of the next card.
static void RSDrawRibbon(NSRect card)
{
    CGFloat w = 14, h = 38, x = NSMaxX(card) - 34;
    BOOL flipped = RSFlipped();
    CGFloat top = flipped ? NSMinY(card) - 4 : NSMaxY(card) + 4;
    CGFloat dir = flipped ? 1 : -1;
    NSBezierPath *p = [NSBezierPath bezierPath];
    [p moveToPoint:NSMakePoint(x, top)];
    [p lineToPoint:NSMakePoint(x + w, top)];
    [p lineToPoint:NSMakePoint(x + w, top + dir * h)];
    [p lineToPoint:NSMakePoint(x + w / 2, top + dir * (h - 6))];
    [p lineToPoint:NSMakePoint(x, top + dir * h)];
    [p closePath];
    [NSGraphicsContext saveGraphicsState];
    RSShadowOn(1, 2, 0.45);
    [RSRibbon() set];
    [p fill];
    [NSGraphicsContext restoreGraphicsState];
    // Silk: a sheen down one side.
    [NSGraphicsContext saveGraphicsState];
    [p addClip];
    NSGradient *sheen = [[[NSGradient alloc] initWithColorsAndLocations:RSRGB(0x000000, 0.18), 0.0, RSRGB(0xffffff, 0.22), 0.35,
                          RSRGB(0x000000, 0.0), 0.6, RSRGB(0x000000, 0.2), 1.0, nil] autorelease];
    [sheen drawInRect:NSMakeRect(x, MIN(top, top + dir * h), w, h) angle:0];
    [NSGraphicsContext restoreGraphicsState];
}

// A rubber stamp in green ink, a little crooked, as stamps are.
static void RSDrawStamp(NSString *word, NSPoint centre, CGFloat alpha)
{
    NSDictionary *a = RSText(RSSerifBold(12), RSRGB(0x2f7a3a, alpha), NSCenterTextAlignment, NSLineBreakByClipping);
    NSSize s = [word sizeWithAttributes:a];
    NSRect box = NSMakeRect(-ceil(s.width) / 2 - 8, -10, ceil(s.width) + 16, 20);
    [NSGraphicsContext saveGraphicsState];
    NSAffineTransform *t = [NSAffineTransform transform];
    [t translateXBy:centre.x yBy:centre.y];
    [t rotateByDegrees:RSFlipped() ? -7 : 7];
    [t concat];
    [[RSStampInk() colorWithAlphaComponent:alpha] set];
    NSBezierPath *outer = [NSBezierPath bezierPathWithRoundedRect:box xRadius:3 yRadius:3];
    [outer setLineWidth:1.6];
    [outer stroke];
    NSBezierPath *inner = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(box, 2.5, 2.5) xRadius:2 yRadius:2];
    [inner setLineWidth:0.7];
    [inner stroke];
    CGFloat textHeight = RSLineHeight(RSSerifBold(12));
    [word drawInRect:NSMakeRect(NSMinX(box), NSMidY(box) - textHeight / 2, NSWidth(box), textHeight) withAttributes:a];
    [NSGraphicsContext restoreGraphicsState];
}

// A groove pressed into the card, and how far along it is.
static void RSDrawBar(NSRect r, double fraction, NSColor *fill)
{
    NSBezierPath *track = [NSBezierPath bezierPathWithRoundedRect:r xRadius:NSHeight(r) / 2 yRadius:NSHeight(r) / 2];
    NSGradient *groove = [[[NSGradient alloc] initWithStartingColor:RSRGB(0xcbbd9c, 1) endingColor:RSRGB(0xe6dcc4, 1)] autorelease];
    [groove drawInBezierPath:track angle:RSFlipped() ? 90 : -90];
    [RSRGB(0xffffff, 0.6) set];
    NSRectFillUsingOperation(RSBottomStrip(NSInsetRect(r, NSHeight(r) / 2, 0), 0.5), NSCompositeSourceOver);
    if (fraction <= 0) return;
    NSRect f = r;
    f.size.width = MAX(NSHeight(r), round(NSWidth(r) * MIN(1, fraction)));
    NSBezierPath *bar = [NSBezierPath bezierPathWithRoundedRect:f xRadius:NSHeight(r) / 2 yRadius:NSHeight(r) / 2];
    NSColor *top = [fill blendedColorWithFraction:0.35 ofColor:[NSColor whiteColor]];
    NSColor *bottom = [fill blendedColorWithFraction:0.15 ofColor:[NSColor blackColor]];
    NSGradient *gloss = [[[NSGradient alloc] initWithColorsAndLocations:top, 0.0, fill, 0.5, bottom, 1.0, nil] autorelease];
    [gloss drawInBezierPath:bar angle:RSFlipped() ? 90 : -90];
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

+ (NSColor *)windowBackground
{
    static NSColor *color;
    if (color == nil) color = [[NSColor colorWithPatternImage:RSBackWood()] retain];
    return color;
}

// ---- The shelf --------------------------------------------------------------

+ (CGFloat)headerHeight     { return 80; }
+ (CGFloat)rowHeight        { return 138; }
+ (CGFloat)statusBarHeight  { return 24; }

// The crown of the bookcase, with the brass plate on it.
+ (void)drawHeaderIn:(NSRect)rect title:(NSString *)title subtitle:(NSString *)subtitle
{
    RSDrawTiled(RSPlankWood(), rect);
    NSGradient *light = [[[NSGradient alloc] initWithColorsAndLocations:RSRGB(0xffffff, 0.14), 0.0, RSRGB(0xffffff, 0), 0.4,
                          RSRGB(0x000000, 0.0), 0.6, RSRGB(0x000000, 0.35), 1.0, nil] autorelease];
    RSDrawDown(light, rect);
    // A moulding: two thin grooves near the bottom.
    NSRect bottom = RSBottomStrip(rect, 9);
    [RSRGB(0x2a170b, 0.7) set];
    NSRectFillUsingOperation(RSTopStrip(bottom, 1), NSCompositeSourceOver);
    [RSRGB(0xffd9a8, 0.25) set];
    NSRectFillUsingOperation(NSOffsetRect(RSTopStrip(bottom, 1), 0, RSFlipped() ? 1 : -1), NSCompositeSourceOver);
    [RSRGB(0x1e1109, 1) set];
    NSRectFillUsingOperation(RSBottomStrip(rect, 1), NSCompositeSourceOver);

    CGFloat width = MIN(440, NSWidth(rect) - 40);
    NSRect plate = NSMakeRect(round(NSMidX(rect) - width / 2), 0, width, 54);
    plate.origin.y = round(NSMinY(rect) + (NSHeight(rect) - 9 - NSHeight(plate)) / 2 + (RSFlipped() ? 0 : 9));
    RSDrawBrassPlate(plate, title, subtitle);
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

// The video's still, in a thin black bezel with a glassy top, standing on the plank.
static void RSDrawThumbnail(NSImage *image, NSRect r, BOOL dim)
{
    [NSGraphicsContext saveGraphicsState];
    RSShadowOn(3, 6, 0.7);
    [RSRGB(0x111111, 1) set];
    NSRectFill(r);
    [NSGraphicsContext restoreGraphicsState];

    NSRect pic = NSInsetRect(r, 2, 2);
    [NSGraphicsContext saveGraphicsState];
    NSRectClip(pic);
    if (image) {
        NSSize s = [image size];
        // Fill the frame, cropping what's over (YouTube thumbnails are 16:9 already).
        CGFloat scale = MAX(NSWidth(pic) / MAX(1, s.width), NSHeight(pic) / MAX(1, s.height));
        NSSize d = NSMakeSize(s.width * scale, s.height * scale);
        NSRect dest = NSMakeRect(NSMidX(pic) - d.width / 2, NSMidY(pic) - d.height / 2, d.width, d.height);
        [image drawInRect:dest fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1
           respectFlipped:YES hints:nil];
        if (dim) {
            [RSRGB(0x2a1a0e, 0.55) set];
            NSRectFillUsingOperation(pic, NSCompositeSourceOver);
        }
    } else {
        NSGradient *g = [[[NSGradient alloc] initWithStartingColor:RSRGB(0x4a4a4e, 1) endingColor:RSRGB(0x232326, 1)] autorelease];
        RSDrawDown(g, pic);
        NSBezierPath *play = [NSBezierPath bezierPath];
        BOOL flipped = RSFlipped();
        CGFloat up = flipped ? -1 : 1;
        [play moveToPoint:NSMakePoint(NSMidX(pic) - 9, NSMidY(pic) - 12 * up)];
        [play lineToPoint:NSMakePoint(NSMidX(pic) + 13, NSMidY(pic))];
        [play lineToPoint:NSMakePoint(NSMidX(pic) - 9, NSMidY(pic) + 12 * up)];
        [play closePath];
        [RSRGB(0xffffff, 0.35) set];
        [play fill];
    }
    // Glass: a soft sheen across the top half.
    NSRect gloss = RSTopStrip(pic, round(NSHeight(pic) * 0.45));
    NSGradient *sheen = [[[NSGradient alloc] initWithStartingColor:RSRGB(0xffffff, 0.16) endingColor:RSRGB(0xffffff, 0.02)] autorelease];
    RSDrawDown(sheen, gloss);
    [NSGraphicsContext restoreGraphicsState];
    [RSRGB(0xffffff, 0.12) set];
    NSRectFillUsingOperation(RSTopStrip(NSInsetRect(r, 1, 1), 1), NSCompositeSourceOver);
}

+ (void)drawRow:(RSRowModel *)row in:(NSRect)rect hover:(BOOL)hover pressed:(BOOL)pressed selected:(BOOL)selected
{
    BOOL playable = [row state] == RSRowReady;
    BOOL flipped = RSFlipped();
    NSRect plank = RSDrawBay(rect);
    // What stands on the plank: top of the plank, going up.
    CGFloat standY = flipped ? NSMinY(plank) : NSMaxY(plank);
    CGFloat up = flipped ? -1 : 1;
    CGFloat itemHeight = 100;
    CGFloat itemTop = flipped ? standY - itemHeight : standY + itemHeight;

    NSRect thumb = NSMakeRect(NSMinX(rect) + 20, MIN(standY, itemTop), 178, itemHeight);
    RSDrawThumbnail([row thumbnail], thumb, !playable);

    NSRect card = NSMakeRect(NSMaxX(thumb) + 16, MIN(standY, itemTop), NSMaxX(rect) - NSMaxX(thumb) - 16 - 20, itemHeight);
    CGFloat brighten = playable && pressed ? -0.10 : playable && hover ? 0.35 : 0;
    RSDrawCard(card, brighten, playable && hover && !pressed);
    if (selected) {
        [RSRGB(0xd99a2b, 0.9) set];
        NSFrameRectWithWidth(NSInsetRect(card, -2, -2), 2);
    }
    if ([row next]) RSDrawRibbon(card);

    // The card's text, from its top. Drawn flipped-style: work out each
    // line's top, then place it whichever way the view runs.
    CGFloat pad = 10, x = NSMinX(card) + pad, width = NSWidth(card) - 2 * pad - ([row next] ? 30 : 0);
    __block CGFloat y = 8;  // from the card's top
    NSRect (^line)(CGFloat) = ^NSRect(CGFloat h) {
        NSRect r = NSMakeRect(x, flipped ? NSMinY(card) + y : NSMaxY(card) - y - h, width, h);
        y += h;
        return r;
    };
    if ([row next]) {
        RSDrawText(@"NEXT", RSText(RSSerifBold(9.5), RSRibbon(), NSLeftTextAlignment, NSLineBreakByClipping), line(13));
        y += 1;
    }
    NSFont *titleFont = RSSerifBold(14);
    NSDictionary *title = RSTextFixed(titleFont, playable ? RSInk() : RSInkSoft());
    CGFloat lines = [row next] ? 1 : 2;
    CGFloat titleHeight = MIN(RSHeightOf([row title], title, width), RSLineHeight(titleFont) * lines);
    RSDrawText([row title], title, line(titleHeight));
    y += 2;
    RSDrawText([self metaTextFor:row], RSText(RSSerifItalic(12), RSInkSoft(), NSLeftTextAlignment, NSLineBreakByTruncatingTail),
               line(16));

    // The bottom line: how far, or the download.
    BOOL stamped = [row finished] && playable && NSWidth(card) >= 360;
    CGFloat barWidth = MIN(200, NSWidth(card) - 2 * pad - (stamped ? 140 : 0));
    NSColor *noteColor = [row state] == RSRowFailed ? RSProblem() : [row finished] && playable ? RSStampInk() : RSInkSoft();
    NSFont *noteFont = [row finished] && playable ? RSSerifBold(11) : RSSerif(11);
    y = itemHeight - pad - 5 - 4 - 15;
    RSDrawText([self progressTextFor:row], RSText(noteFont, noteColor, NSLeftTextAlignment, NSLineBreakByTruncatingTail),
               NSMakeRect(x, flipped ? NSMinY(card) + y : NSMaxY(card) - y - 15, NSWidth(card) - 2 * pad, 15));
    y = itemHeight - pad - 5;
    NSRect bar = NSMakeRect(x, flipped ? NSMinY(card) + y : NSMaxY(card) - y - 5, MAX(40, barWidth), 5);
    if ([row state] == RSRowDownloading) RSDrawBar(bar, [row progress], RSRGB(0x8a7a62, 1));
    else if (playable && [row duration] > 0) RSDrawBar(bar, [row finished] ? 1 : [row watched] / [row duration],
                                                       [row finished] ? RSStampInk() : RSRibbon());
    if (stamped) RSDrawStamp(@"ПРОСМОТРЕНО", NSMakePoint(NSMaxX(card) - 74, NSMidY(card) + up * -18), 0.8);
}

+ (void)drawBareShelvesIn:(NSRect)rect from:(CGFloat)top
{
    // Rows of the same height carry on below the last video, empty.
    CGFloat h = [self rowHeight];
    BOOL flipped = RSFlipped();
    if (!flipped) { RSDrawBack(rect); return; }
    for (CGFloat y = top; y < NSMaxY(rect); y += h) {
        NSRect bay = NSMakeRect(NSMinX(rect), y, NSWidth(rect), h);
        if (NSMaxY(bay) < NSMinY(rect)) continue;
        RSDrawBay(bay);
    }
}

+ (void)drawEmptyShelfIn:(NSRect)rect title:(NSString *)title message:(NSString *)message
{
    // An empty bookcase with a note pinned to its back.
    if (RSFlipped()) [self drawBareShelvesIn:rect from:NSMinY(rect)];
    else RSDrawBack(rect);
    CGFloat width = MIN(400, NSWidth(rect) - 60);
    NSDictionary *t = RSText(RSSerifBold(16), RSInk(), NSCenterTextAlignment, NSLineBreakByWordWrapping);
    NSDictionary *m = RSText(RSSerif(13), RSInkSoft(), NSCenterTextAlignment, NSLineBreakByWordWrapping);
    CGFloat th = RSHeightOf(title, t, width), mh = RSHeightOf(message, m, width);
    CGFloat h = th + mh + 8 + 40;
    // In the second bay, between its shelves, when the window is tall enough.
    CGFloat bay = [self rowHeight], room = bay - RSPlankHeight;
    CGFloat top = NSHeight(rect) >= 2 * bay && h <= room ? NSMinY(rect) + bay + round((room - h) / 2)
                                                         : NSMinY(rect) + MAX(40, (NSHeight(rect) - h) * 0.36);
    NSRect note = NSMakeRect(round(NSMidX(rect) - width / 2 - 20), RSFlipped() ? top : NSMaxY(rect) - (top - NSMinY(rect)) - h,
                             width + 40, h);
    RSDrawCard(note, 0, YES);
    // A red pushpin at the top.
    NSPoint pin = NSMakePoint(NSMidX(note), RSFlipped() ? NSMinY(note) + 11 : NSMaxY(note) - 11);
    [NSGraphicsContext saveGraphicsState];
    RSShadowOn(2, 3, 0.5);
    NSGradient *g = [[[NSGradient alloc] initWithColorsAndLocations:RSRGB(0xff8a80, 1), 0.0, RSRGB(0xc62828, 1), 0.55,
                      RSRGB(0x7f1010, 1), 1.0, nil] autorelease];
    [g drawInBezierPath:[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(pin.x - 6, pin.y - 6, 12, 12)]
       relativeCenterPosition:NSMakePoint(-0.4, RSFlipped() ? -0.4 : 0.4)];
    [NSGraphicsContext restoreGraphicsState];
    BOOL flipped = RSFlipped();
    CGFloat ty = flipped ? NSMinY(note) + 26 : NSMaxY(note) - 26 - th;
    RSDrawText(title, t, NSMakeRect(NSMidX(note) - width / 2, ty, width, th));
    CGFloat my = flipped ? ty + th + 8 : ty - 8 - mh;
    RSDrawText(message, m, NSMakeRect(NSMidX(note) - width / 2, my, width, mh));
}

// The bookcase's plinth, along the bottom of the window.
+ (void)drawStatusBarIn:(NSRect)rect text:(NSString *)text problem:(BOOL)problem
{
    RSDrawTiled(RSBackWood(), rect);
    [RSRGB(0x000000, 0.35) set];
    NSRectFillUsingOperation(rect, NSCompositeSourceOver);
    [RSRGB(0x1a0e06, 1) set];
    NSRectFillUsingOperation(RSTopStrip(rect, 1), NSCompositeSourceOver);
    [RSRGB(0xffd9a8, 0.18) set];
    NSRectFillUsingOperation(NSOffsetRect(RSTopStrip(rect, 1), 0, RSFlipped() ? 1 : -1), NSCompositeSourceOver);
    NSDictionary *a = RSTextShadowed(RSFont(11), problem ? RSRGB(0xffb3a6, 1) : RSCream(), NSLeftTextAlignment,
                                     RSRGB(0x000000, 0.8), 1);
    RSDrawText(text ?: @"", a, NSMakeRect(NSMinX(rect) + 12, NSMinY(rect) + 5, NSWidth(rect) - 24, 15));
}

+ (void)drawScrollerSlotIn:(NSRect)rect
{
    RSDrawTiled(RSBackWood(), rect);
    [RSRGB(0x000000, 0.45) set];
    NSRectFillUsingOperation(rect, NSCompositeSourceOver);
    [RSRGB(0x000000, 0.5) set];
    NSRectFillUsingOperation(NSMakeRect(NSMinX(rect), NSMinY(rect), 1, NSHeight(rect)), NSCompositeSourceOver);
}

// ---- The player -------------------------------------------------------------

+ (CGFloat)hintBarHeight { return 30; }

// Charcoal, brushed, with the keys as keycaps: the bar under a 2013 player.
+ (void)drawHintBarIn:(NSRect)rect items:(NSArray *)items
{
    NSGradient *bar = [[[NSGradient alloc] initWithColorsAndLocations:RSRGB(0x4a4a4e, 1), 0.0, RSRGB(0x2c2c2f, 1), 0.5,
                        RSRGB(0x1d1d1f, 1), 1.0, nil] autorelease];
    RSDrawDown(bar, rect);
    [RSRGB(0x000000, 1) set];
    NSRectFillUsingOperation(RSTopStrip(rect, 1), NSCompositeSourceOver);
    [RSRGB(0xffffff, 0.14) set];
    NSRectFillUsingOperation(NSOffsetRect(RSTopStrip(rect, 1), 0, RSFlipped() ? 1 : -1), NSCompositeSourceOver);

    NSDictionary *key = RSTextShadowed([NSFont boldSystemFontOfSize:10], RSRGB(0x3a3a3c, 1), NSCenterTextAlignment,
                                       RSRGB(0xffffff, 0.8), -1);
    NSDictionary *label = RSTextShadowed(RSFont(11), RSRGB(0xd8d8dc, 1), NSLeftTextAlignment, RSRGB(0x000000, 0.8), 1);
    CGFloat x = NSMinX(rect) + 12, mid = NSMidY(rect);
    for (NSUInteger i = 0; i + 1 < [items count]; i += 2) {
        NSString *k = [items objectAtIndex:i], *l = [items objectAtIndex:i + 1];
        CGFloat kw = MAX(20, ceil([k sizeWithAttributes:key].width) + 12);
        CGFloat lw = ceil([l sizeWithAttributes:label].width);
        if (x + kw + 6 + lw > NSMaxX(rect) - 8) break;
        NSRect cap = NSMakeRect(x, round(mid - 9.5), kw, 19);
        NSBezierPath *capPath = [NSBezierPath bezierPathWithRoundedRect:cap xRadius:3.5 yRadius:3.5];
        [NSGraphicsContext saveGraphicsState];
        RSShadowOn(1, 1.5, 0.9);
        [RSRGB(0x9a9a9e, 1) set];
        [capPath fill];
        [NSGraphicsContext restoreGraphicsState];
        NSGradient *face = [[[NSGradient alloc] initWithStartingColor:RSRGB(0xfbfbfb, 1) endingColor:RSRGB(0xd2d2d6, 1)] autorelease];
        [face drawInBezierPath:[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(cap, 0.5, 0.5) xRadius:3 yRadius:3]
                         angle:RSFlipped() ? 90 : -90];
        [k drawInRect:NSMakeRect(NSMinX(cap), NSMinY(cap) + 2.5, kw, 15) withAttributes:key];
        [l drawInRect:NSMakeRect(NSMaxX(cap) + 6, mid - 8, lw + 2, 16) withAttributes:label];
        x = NSMaxX(cap) + 6 + lw + 16;
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
//
// A sheet of ruled exercise paper: a blue rule under each line, the time in
// the margin left of a red rule, and a yellow highlighter on the line being
// spoken.

+ (CGFloat)transcriptPadding { return 10; }

static CGFloat const RSMarginX = 54;      // the red rule, from the sheet's left edge

static NSDictionary *RSTranscriptText(BOOL current)
{
    return RSText(current ? RSSerifBold(14) : RSSerif(14), RSInk(), NSLeftTextAlignment, NSLineBreakByWordWrapping);
}

+ (CGFloat)heightOfTranscriptLine:(NSString *)text width:(CGFloat)width
{
    CGFloat textWidth = width - [self transcriptPadding] - RSMarginX - 8;
    return MAX(RSHeightOf(text, RSTranscriptText(YES), textWidth), RSHeightOf(text, RSTranscriptText(NO), textWidth)) + 12;
}

+ (void)drawTranscriptLine:(NSString *)text time:(double)seconds in:(NSRect)rect current:(BOOL)current hover:(BOOL)hover
{
    CGFloat pad = [self transcriptPadding];
    NSRect textRect = NSMakeRect(NSMinX(rect) + RSMarginX + 8, NSMinY(rect) + 6,
                                 NSWidth(rect) - RSMarginX - 8 - pad, NSHeight(rect) - 10);
    if (current) {
        // A highlighter stroke: translucent, a little wider than the words.
        NSRect swipe = NSMakeRect(NSMinX(textRect) - 4, NSMinY(rect) + 3, NSWidth(textRect) + 6, NSHeight(rect) - 6);
        [RSRGB(0xffe94d, 0.55) set];
        [[NSBezierPath bezierPathWithRoundedRect:swipe xRadius:3 yRadius:3] fill];
    } else if (hover) {
        [RSRGB(0xe8dcbc, 0.45) set];
        NSRectFillUsingOperation(NSMakeRect(NSMinX(rect) + RSMarginX + 1, NSMinY(rect), NSWidth(rect) - RSMarginX - 1, NSHeight(rect)),
                                 NSCompositeSourceOver);
    }
    // 10.9's system font, Lucida Grande, already has digits of one width.
    NSDictionary *time = RSText(RSFont(10.5), current ? RSRibbon() : RSInkFaint(), NSRightTextAlignment, NSLineBreakByClipping);
    RSDrawText(RSClock(seconds), time, NSMakeRect(NSMinX(rect) + pad - 4, NSMinY(rect) + 8, RSMarginX - pad - 2, 15));
    RSDrawText(text, RSTranscriptText(current), textRect);
    // The rule under the line.
    [RSRGB(0xa9c4e0, 0.75) set];
    NSRectFillUsingOperation(RSBottomStrip(rect, 1), NSCompositeSourceOver);
}

+ (void)drawTranscriptBackgroundIn:(NSRect)rect
{
    [RSRGB(0xfdfaf0, 1) set];
    NSRectFill(rect);
    // The margin's red rule (the view starts at x = 0).
    [RSRGB(0xe08a8a, 0.8) set];
    NSRectFillUsingOperation(NSMakeRect(RSMarginX, NSMinY(rect), 1, NSHeight(rect)), NSCompositeSourceOver);
    // The binding's edge, on the left.
    NSGradient *edge = [[[NSGradient alloc] initWithStartingColor:RSRGB(0x000000, 0.12) endingColor:RSRGB(0x000000, 0)] autorelease];
    [edge drawInRect:NSMakeRect(0, NSMinY(rect), 6, NSHeight(rect)) angle:0];
}

+ (void)drawTranscriptEmptyIn:(NSRect)rect message:(NSString *)message
{
    [self drawTranscriptBackgroundIn:rect];
    NSDictionary *m = RSText(RSSerifItalic(13), RSInkSoft(), NSCenterTextAlignment, NSLineBreakByWordWrapping);
    RSDrawText(message, m, NSMakeRect(NSMinX(rect) + RSMarginX + 10, NSMinY(rect) + 40, NSWidth(rect) - RSMarginX - 30, 80));
}

// ---- Lines to hear again ------------------------------------------------------
//
// A library index card, propped on a shelf: a red rule under the heading,
// faint blue rules below, the line written large once it's shown.

+ (NSSize)reviewWindowSize { return NSMakeSize(640, 400); }

+ (void)drawReviewIn:(NSRect)rect heading:(NSString *)heading source:(NSString *)source before:(NSString *)before
                text:(NSString *)text message:(NSString *)message note:(NSString *)note keys:(NSArray *)keys
{
    CGFloat bar = [self hintBarHeight];
    NSRect wall = rect;
    wall.origin.y += bar;
    wall.size.height -= bar;
    RSDrawBack(wall);
    RSDrawCastShadow(wall, 10);
    NSRect plank = NSMakeRect(NSMinX(wall), NSMinY(wall), NSWidth(wall), RSPlankHeight);
    RSDrawPlank(plank);
    [self drawHintBarIn:RSBottomStrip(rect, bar) items:keys];

    NSRect card = NSMakeRect(NSMinX(wall) + 44, NSMaxY(plank) + 6, NSWidth(wall) - 88, NSHeight(wall) - RSPlankHeight - 6 - 30);
    RSDrawCard(card, 0, YES);
    CGFloat pad = 24;
    CGFloat ruleY = NSMaxY(card) - 44;
    // Blue rules, then the red one under the heading.
    [RSRGB(0xa9c4e0, 0.55) set];
    for (CGFloat y = ruleY - 30; y > NSMinY(card) + 14; y -= 30)
        NSRectFillUsingOperation(NSMakeRect(NSMinX(card) + 1, y, NSWidth(card) - 2, 1), NSCompositeSourceOver);
    [RSRGB(0xe08a8a, 0.85) set];
    NSRectFillUsingOperation(NSMakeRect(NSMinX(card) + 1, ruleY, NSWidth(card) - 2, 1), NSCompositeSourceOver);

    CGFloat width = NSWidth(card) - 2 * pad;
    NSDictionary *h = RSText(RSSerifBold(16), RSInk(), NSLeftTextAlignment, NSLineBreakByTruncatingTail);
    RSDrawText(heading, h, NSMakeRect(NSMinX(card) + pad, ruleY + 10, width, 22));
    CGFloat top = ruleY - 8;
    if ([source length]) {
        NSDictionary *a = RSText(RSSerifItalic(11.5), RSInkSoft(), NSLeftTextAlignment, NSLineBreakByTruncatingTail);
        RSDrawText(source, a, NSMakeRect(NSMinX(card) + pad, top - 16, width, 16));
        top -= 26;
    }
    CGFloat bottom = NSMinY(card) + ([note length] ? 34 : 16);
    if ([before length]) {
        NSDictionary *b = RSText(RSSerifItalic(13), RSInkFaint(), NSLeftTextAlignment, NSLineBreakByWordWrapping);
        NSString *one = [[before componentsSeparatedByString:@"\n"] componentsJoinedByString:@" "];
        CGFloat bh = MIN(36, RSHeightOf(one, b, width));
        RSDrawText(one, b, NSMakeRect(NSMinX(card) + pad, top - bh, width, bh));
        top -= bh + 8;
    }
    NSRect body = NSMakeRect(NSMinX(card) + pad, bottom, width, MAX(0, top - bottom));
    if ([text length]) {
        NSDictionary *t = RSText(RSSerif(24), RSInk(), NSCenterTextAlignment, NSLineBreakByWordWrapping);
        CGFloat th = MIN(NSHeight(body), RSHeightOf(text, t, width));
        RSDrawText(text, t, NSMakeRect(NSMinX(body), round(NSMidY(body) - th / 2), width, th));
    } else if ([message length]) {
        NSDictionary *m = RSText(RSSerif(15), RSInkSoft(), NSCenterTextAlignment, NSLineBreakByWordWrapping);
        CGFloat mh = MIN(NSHeight(body), RSHeightOf(message, m, width - 40));
        RSDrawText(message, m, NSMakeRect(NSMinX(body) + 20, round(NSMidY(body) - mh / 2), width - 40, mh));
    } else {
        // Still hidden: where the line will go.
        NSDictionary *w = RSText(RSSerifItalic(14), RSInkFaint(), NSCenterTextAlignment, NSLineBreakByWordWrapping);
        CGFloat wh = RSLineHeight(RSSerifItalic(14));
        RSDrawText(@"Try to say it, then ↓ shows the line.", w, NSMakeRect(NSMinX(body), round(NSMidY(body) - wh / 2), width, wh));
    }
    if ([note length]) {
        NSDictionary *n = RSText(RSSerifItalic(12), RSRibbon(), NSCenterTextAlignment, NSLineBreakByTruncatingTail);
        RSDrawText(note, n, NSMakeRect(NSMinX(card) + pad, NSMinY(card) + 12, width, 16));
    }
}

@end
