// mkicon -- writes RussianShelf.iconset: the app's icon, drawn at every size.
//
// A host tool: built for and run on the development machine, never shipped.
// A 2013 Mac icon, an object rather than a tile: a small walnut bookcase,
// seen from the front, with three leather-bound books standing in it in the
// flag's white, blue and red. Gilt bands on the spines, and a gilt play mark
// tooled into the blue one. Below 64 pixels the bands, the grain and the
// bevels go, and the books grow to fill the case, so 16 and 32 still read
// as three coloured spines in a box.
//
//   mkicon <output.iconset>      then: iconutil -c icns <output.iconset>

#import <Cocoa/Cocoa.h>

static void SetFill(CGContextRef c, unsigned rgb, CGFloat a)
{
    CGContextSetRGBFillColor(c, ((rgb >> 16) & 0xFF) / 255.0, ((rgb >> 8) & 0xFF) / 255.0, (rgb & 0xFF) / 255.0, a);
}

static void SetStroke(CGContextRef c, unsigned rgb, CGFloat a, CGFloat width)
{
    CGContextSetRGBStrokeColor(c, ((rgb >> 16) & 0xFF) / 255.0, ((rgb >> 8) & 0xFF) / 255.0, (rgb & 0xFF) / 255.0, a);
    CGContextSetLineWidth(c, width);
}

// Core Graphics measures shadow offsets and blurs in device pixels, not in
// the 1024-unit space the icon is drawn in, so every shadow goes through the
// icon's own scale (Nightlatch's lesson).
static CGFloat gPixelsPerUnit = 1.0;

static void Shadow(CGContextRef c, CGFloat dy, CGFloat blur, CGFloat alpha)
{
    CGColorRef color = CGColorCreateGenericRGB(0, 0, 0, alpha);
    CGContextSetShadowWithColor(c, CGSizeMake(0, -dy * gPixelsPerUnit), blur * gPixelsPerUnit, color);
    CGColorRelease(color);
}

static void RoundRect(CGContextRef c, CGRect r, CGFloat radius)
{
    CGPathRef p = CGPathCreateWithRoundedRect(r, radius, radius, NULL);
    CGContextAddPath(c, p);
    CGPathRelease(p);
}

// A gradient through `count` colours along a line, over the current clip.
static void Gradient(CGContextRef c, const unsigned *rgb, const CGFloat *locations, int count, CGPoint from, CGPoint to)
{
    CGFloat comps[32];
    for (int i = 0; i < count && i < 8; i++) {
        comps[i * 4 + 0] = ((rgb[i] >> 16) & 0xFF) / 255.0;
        comps[i * 4 + 1] = ((rgb[i] >> 8) & 0xFF) / 255.0;
        comps[i * 4 + 2] = (rgb[i] & 0xFF) / 255.0;
        comps[i * 4 + 3] = 1;
    }
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, locations, count);
    CGContextDrawLinearGradient(c, g, from, to, kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    CGGradientRelease(g);
    CGColorSpaceRelease(cs);
}

static void Vertical(CGContextRef c, CGRect r, unsigned top, unsigned bottom)
{
    unsigned rgb[2] = { bottom, top };
    CGFloat loc[2] = { 0, 1 };
    Gradient(c, rgb, loc, 2, CGPointMake(0, CGRectGetMinY(r)), CGPointMake(0, CGRectGetMaxY(r)));
}

// Grain: thin, slightly wavy lines across a board, from a fixed seed so every
// size draws the same wood.
static void Grain(CGContextRef c, CGRect r, unsigned rgb, CGFloat alpha, int seed)
{
    unsigned s = (unsigned)seed * 2654435761u;
    CGContextSaveGState(c);
    CGContextClipToRect(c, r);
    for (CGFloat y = CGRectGetMinY(r) + 6; y < CGRectGetMaxY(r); y += 9) {
        s = s * 1103515245u + 12345u;
        CGFloat a = alpha * (0.35 + (s >> 16 & 0xff) / 255.0 * 0.65);
        CGFloat amp = 2 + (s >> 8 & 0x7) * 0.8, phase = (s & 0xff) / 40.0;
        SetStroke(c, rgb, a, 2.2);
        CGContextMoveToPoint(c, CGRectGetMinX(r), y);
        for (CGFloat x = CGRectGetMinX(r); x <= CGRectGetMaxX(r); x += 16)
            CGContextAddLineToPoint(c, x, y + amp * sin(x / 70.0 + phase) + 1.5 * sin(x / 23.0 + phase * 2));
        CGContextStrokePath(c);
    }
    CGContextRestoreGState(c);
}

// One book standing on the floor of the case: a rounded leather spine,
// shaded like a cylinder, with gilt bands.
static void Book(CGContextRef c, CGRect r, unsigned light, unsigned mid, unsigned dark, BOOL detail)
{
    CGContextSaveGState(c);
    Shadow(c, 0, detail ? 14 : 3, 0.55);
    SetFill(c, mid, 1);
    RoundRect(c, r, detail ? 10 : 3);
    CGContextFillPath(c);
    CGContextRestoreGState(c);

    CGContextSaveGState(c);
    RoundRect(c, r, detail ? 10 : 3);
    CGContextClip(c);
    unsigned rgb[5] = { dark, mid, light, mid, dark };
    CGFloat loc[5] = { 0, 0.18, 0.42, 0.78, 1 };
    Gradient(c, rgb, loc, 5, CGPointMake(CGRectGetMinX(r), 0), CGPointMake(CGRectGetMaxX(r), 0));
    if (detail) {
        // Raised bands top and bottom, and gilt lines beside them.
        const CGFloat bands[2] = { CGRectGetMaxY(r) - 70, CGRectGetMinY(r) + 48 };
        for (int i = 0; i < 2; i++) {
            CGRect band = CGRectMake(CGRectGetMinX(r), bands[i], r.size.width, 22);
            unsigned b[3] = { dark, light, dark };
            CGFloat bl[3] = { 0, 0.5, 1 };
            CGContextSaveGState(c);
            CGContextClipToRect(c, band);
            Gradient(c, b, bl, 3, CGPointMake(0, CGRectGetMinY(band)), CGPointMake(0, CGRectGetMaxY(band)));
            CGContextRestoreGState(c);
            unsigned gilt[3] = { 0x8a6420, 0xf7dd8a, 0xa87a2a };
            CGFloat gl[3] = { 0, 0.5, 1 };
            for (int k = 0; k < 2; k++) {
                CGRect line = CGRectMake(CGRectGetMinX(r), k ? CGRectGetMaxY(band) + 7 : CGRectGetMinY(band) - 13, r.size.width, 6);
                CGContextSaveGState(c);
                CGContextClipToRect(c, line);
                Gradient(c, gilt, gl, 3, CGPointMake(0, CGRectGetMinY(line)), CGPointMake(0, CGRectGetMaxY(line)));
                CGContextRestoreGState(c);
            }
        }
        // The worn top edge.
        SetFill(c, 0xffffff, 0.18);
        CGContextFillRect(c, CGRectMake(CGRectGetMinX(r), CGRectGetMaxY(r) - 5, r.size.width, 5));
    }
    CGContextRestoreGState(c);
}

static void PlayMark(CGContextRef c, CGPoint centre, CGFloat s, BOOL detail)
{
    CGContextSaveGState(c);
    CGContextMoveToPoint(c, centre.x - s * 0.55, centre.y - s);
    CGContextAddLineToPoint(c, centre.x + s * 0.95, centre.y);
    CGContextAddLineToPoint(c, centre.x - s * 0.55, centre.y + s);
    CGContextClosePath(c);
    if (detail) {
        // Tooled into the leather: a dark rim below, then gilt.
        CGContextSaveGState(c);
        Shadow(c, -2, 2, 0.6);
        SetFill(c, 0xd9b45a, 1);
        CGContextFillPath(c);
        CGContextRestoreGState(c);
        CGContextMoveToPoint(c, centre.x - s * 0.55, centre.y - s);
        CGContextAddLineToPoint(c, centre.x + s * 0.95, centre.y);
        CGContextAddLineToPoint(c, centre.x - s * 0.55, centre.y + s);
        CGContextClosePath(c);
        CGContextClip(c);
        unsigned gilt[3] = { 0x9a7024, 0xfbe7a0, 0xc19234 };
        CGFloat gl[3] = { 0, 0.55, 1 };
        Gradient(c, gilt, gl, 3, CGPointMake(0, centre.y - s), CGPointMake(0, centre.y + s));
    } else {
        SetFill(c, 0xf2d27a, 1);
        CGContextFillPath(c);
    }
    CGContextRestoreGState(c);
}

static void Draw(CGContextRef c, int pixels)
{
    gPixelsPerUnit = pixels / 1024.0;
    CGContextScaleCTM(c, gPixelsPerUnit, gPixelsPerUnit);
    BOOL detail = pixels >= 64;
    BOOL tiny = pixels <= 32;

    // The case: about 88% of the canvas, its shadow inside it.
    CGRect box = CGRectMake(92, 96, 840, 820);
    CGFloat side = tiny ? 96 : 70, top = tiny ? 96 : 74, base = tiny ? 120 : 112;
    CGContextSaveGState(c);
    Shadow(c, 18, 36, 0.5);
    SetFill(c, 0x6a3f20, 1);
    RoundRect(c, box, 34);
    CGContextFillPath(c);
    CGContextRestoreGState(c);

    CGContextSaveGState(c);
    RoundRect(c, box, 34);
    CGContextClip(c);
    unsigned wood[4] = { 0x5e3519, 0x8a5530, 0xa66d3f, 0x7a4723 };
    CGFloat wl[4] = { 0, 0.35, 0.8, 1 };
    Gradient(c, wood, wl, 4, CGPointMake(0, CGRectGetMinY(box)), CGPointMake(0, CGRectGetMaxY(box)));
    if (detail) Grain(c, box, 0x3a1e0c, 0.35, 7);
    CGContextRestoreGState(c);

    // The bevel: light along the top edge, dark along the bottom.
    if (detail) {
        SetStroke(c, 0xffe0b0, 0.45, 5);
        CGContextMoveToPoint(c, CGRectGetMinX(box) + 34, CGRectGetMaxY(box) - 3);
        CGContextAddLineToPoint(c, CGRectGetMaxX(box) - 34, CGRectGetMaxY(box) - 3);
        CGContextStrokePath(c);
    }
    SetStroke(c, 0x2a1408, 0.9, tiny ? 18 : 4);
    RoundRect(c, CGRectInset(box, tiny ? 9 : 2, tiny ? 9 : 2), tiny ? 26 : 32);
    CGContextStrokePath(c);

    // The opening: the dark back, in shadow from the top and the left side.
    CGRect hole = CGRectMake(CGRectGetMinX(box) + side, CGRectGetMinY(box) + base,
                             box.size.width - 2 * side, box.size.height - base - top);
    CGContextSaveGState(c);
    RoundRect(c, hole, tiny ? 8 : 12);
    CGContextClip(c);
    Vertical(c, hole, 0x24130a, 0x40260f);
    if (detail) Grain(c, hole, 0x1a0c04, 0.4, 3);
    // The case's own shadow inside: the top board and the left side.
    {
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGFloat comps[8] = { 0, 0, 0, 0.55, 0, 0, 0, 0 }, loc[2] = { 0, 1 };
        CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, loc, 2);
        CGContextDrawLinearGradient(c, g, CGPointMake(0, CGRectGetMaxY(hole)), CGPointMake(0, CGRectGetMaxY(hole) - 90), 0);
        comps[3] = 0.3;
        CGGradientRelease(g);
        g = CGGradientCreateWithColorComponents(cs, comps, loc, 2);
        CGContextDrawLinearGradient(c, g, CGPointMake(CGRectGetMinX(hole), 0), CGPointMake(CGRectGetMinX(hole) + 70, 0), 0);
        CGGradientRelease(g);
        CGColorSpaceRelease(cs);
    }
    CGContextRestoreGState(c);
    if (detail) {
        // The inner edges catch the light: the floor's lip and the right side.
        SetStroke(c, 0xd99a62, 0.8, 4);
        CGContextMoveToPoint(c, CGRectGetMinX(hole) + 6, CGRectGetMinY(hole) - 2);
        CGContextAddLineToPoint(c, CGRectGetMaxX(hole) - 6, CGRectGetMinY(hole) - 2);
        CGContextStrokePath(c);
        SetStroke(c, 0x1a0c04, 0.9, 4);
        RoundRect(c, CGRectInset(hole, -2, -2), 14);
        CGContextStrokePath(c);
    }

    // The books, standing on the floor of the opening, centred on what's drawn.
    CGFloat floorY = CGRectGetMinY(hole);
    CGFloat w = tiny ? 166 : 168, gap = tiny ? 20 : 26;
    CGFloat total = 3 * w + 2 * gap, x = CGRectGetMidX(hole) - total / 2;
    CGFloat room = hole.size.height;
    CGFloat heights[3] = { room - (tiny ? 70 : 100), room - (tiny ? 34 : 46), room - (tiny ? 90 : 128) };
    Book(c, CGRectMake(x, floorY, w, heights[0]), 0xffffff, 0xe9e4d8, 0xb3ab98, detail);
    Book(c, CGRectMake(x + w + gap, floorY, w, heights[1]), 0x4a7ad8, 0x1f4fb4, 0x0f2a6a, detail);
    Book(c, CGRectMake(x + 2 * (w + gap), floorY, w, heights[2]), 0xf0524e, 0xc8242a, 0x6e1014, detail);

    // The play mark, tooled into the blue spine between its bands.
    CGFloat s = tiny ? 62 : 58;
    PlayMark(c, CGPointMake(x + w + gap + w / 2 - (tiny ? 6 : 4), floorY + heights[1] / 2 - 4), s, detail);
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc != 2) { fprintf(stderr, "usage: mkicon <output.iconset>\n"); return 2; }
        NSString *dir = [NSString stringWithUTF8String:argv[1]];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        int sizes[] = { 16, 32, 128, 256, 512 };
        for (int i = 0; i < 5; i++) {
            for (int scale = 1; scale <= 2; scale++) {
                int px = sizes[i] * scale;
                CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
                CGContextRef c = CGBitmapContextCreate(NULL, px, px, 8, 0, cs, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
                CGColorSpaceRelease(cs);
                Draw(c, px);
                CGImageRef image = CGBitmapContextCreateImage(c);
                NSString *name = scale == 1 ? [NSString stringWithFormat:@"icon_%dx%d.png", sizes[i], sizes[i]]
                                            : [NSString stringWithFormat:@"icon_%dx%d@2x.png", sizes[i], sizes[i]];
                NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:image];
                // NSPNGFileType, not NSBitmapImageFileTypePNG (10.12), so this
                // also builds with the Mac Pro's 10.9 Command Line Tools.
                [[rep representationUsingType:NSPNGFileType properties:@{}] writeToFile:[dir stringByAppendingPathComponent:name] atomically:YES];
                CGImageRelease(image);
                CGContextRelease(c);
            }
        }
    }
    return 0;
}
