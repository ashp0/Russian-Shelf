// mkicon -- writes RussianShelf.iconset: the app's icon, drawn at every size.
//
// A host tool: built for and run on the development machine, never shipped.
// A 2013 Mac icon, an object rather than a tile, kept quiet on purpose
// (muted leather): three books in the flag's colours, faded to
// cream, dusty navy and brick, on a slim walnut wall shelf, the red one
// leaning on the blue. Gilt bands on the spines and a gilt play mark tooled
// into the blue one. Below 64 pixels the bands, grain and brackets go and
// the books stand straight and wider, so 16 and 32 still read as three
// coloured spines on a shelf.
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
            unsigned gilt[3] = { 0x7a6038, 0xd9c48e, 0x957545 };
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
        unsigned gilt[3] = { 0x8a6c3c, 0xe2cf98, 0xa8874e };
        CGFloat gl[3] = { 0, 0.55, 1 };
        Gradient(c, gilt, gl, 3, CGPointMake(0, centre.y - s), CGPointMake(0, centre.y + s));
    } else {
        SetFill(c, 0xd9c48e, 1);
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
    // The shelf: a slim floating plank, its top catching the light.
    // About three quarters of the canvas wide, with air all round.
    CGFloat left = tiny ? 90 : 96, right = tiny ? 934 : 928;
    CGFloat front = tiny ? 70 : 44, topDepth = tiny ? 0 : 22;
    CGFloat plankY = tiny ? 70 : 80;
    CGRect face = CGRectMake(left, plankY, right - left, front);
    CGContextSaveGState(c);
    Shadow(c, 14, 26, 0.45);
    SetFill(c, 0x8a5530, 1);
    RoundRect(c, CGRectMake(left, plankY, right - left, front + topDepth), tiny ? 6 : 8);
    CGContextFillPath(c);
    CGContextRestoreGState(c);
    // The front edge.
    CGContextSaveGState(c);
    RoundRect(c, face, tiny ? 6 : 8);
    CGContextClip(c);
    unsigned edge[3] = { 0x5e3519, 0x8f5a32, 0xa86f42 };
    CGFloat el[3] = { 0, 0.6, 1 };
    Gradient(c, edge, el, 3, CGPointMake(0, CGRectGetMinY(face)), CGPointMake(0, CGRectGetMaxY(face)));
    if (detail) Grain(c, face, 0x3a1e0c, 0.35, 5);
    CGContextRestoreGState(c);
    // The top, seen a little from above.
    CGFloat floorY = CGRectGetMaxY(face) + topDepth * 0.55;
    if (!tiny) {
        CGContextSaveGState(c);
        CGRect top = CGRectMake(left + 6, CGRectGetMaxY(face), right - left - 12, topDepth);
        CGContextClipToRect(c, top);
        Vertical(c, top, 0xa36a3d, 0xc58b58);
        CGContextRestoreGState(c);
        SetStroke(c, 0xf2c99a, 0.7, 3);
        CGContextMoveToPoint(c, left + 8, CGRectGetMaxY(face) + 1);
        CGContextAddLineToPoint(c, right - 8, CGRectGetMaxY(face) + 1);
        CGContextStrokePath(c);
    }

    // The books, of different widths and heights, centred on what's drawn.
    // The red one leans on the blue.
    CGFloat wW = tiny ? 190 : 168, wB = tiny ? 210 : 194, wR = tiny ? 190 : 166;
    CGFloat hW = tiny ? 700 : 690, hB = tiny ? 820 : 800, hR = tiny ? 700 : 700;
    CGFloat gap = tiny ? 16 : 10;
    CGFloat lean = tiny ? 0 : 12 * M_PI / 180;
    CGFloat total = wW + gap + wB + 2 + wR * cos(lean) + hR * sin(lean);
    CGFloat x = (left + right) / 2 - total / 2;
    Book(c, CGRectMake(x, floorY, wW, hW), 0xf1ead8, 0xddd3bb, 0xa89c80, detail);
    CGFloat bx = x + wW + gap;
    Book(c, CGRectMake(bx, floorY, wB, hB), 0x5d7299, 0x3b4f78, 0x1f2b45, detail);
    CGFloat s = tiny ? 74 : 62;
    PlayMark(c, CGPointMake(bx + wB / 2 - 3, floorY + hB * 0.52), s, detail);
    // The red book stands on its bottom-left corner and leans left until its
    // top touches the blue one's side.
    CGFloat px = tiny ? bx + wB + gap : bx + wB + 2 + hR * sin(lean);
    CGContextSaveGState(c);
    CGContextTranslateCTM(c, px, floorY);
    CGContextRotateCTM(c, lean);
    Book(c, CGRectMake(0, 0, wR, hR), 0xb5584e, 0x8f3a32, 0x4f1d19, detail);
    CGContextRestoreGState(c);
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
