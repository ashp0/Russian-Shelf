// mkicon -- writes RussianShelf.iconset: the app's icon, drawn at every size.
//
// A host tool: built for and run on the development machine, never shipped.
// Plain for now (the skeuomorphic pass redraws it): three books on a shelf in
// the flag's white, blue and red, a play mark on the blue one, on a light
// rounded square.
//
//   mkicon <output.iconset>      then: iconutil -c icns <output.iconset>

#import <Cocoa/Cocoa.h>

static void Fill(CGContextRef c, unsigned rgb, CGFloat a)
{
    CGContextSetRGBFillColor(c, ((rgb >> 16) & 0xFF) / 255.0, ((rgb >> 8) & 0xFF) / 255.0, (rgb & 0xFF) / 255.0, a);
}

static void Stroke(CGContextRef c, unsigned rgb, CGFloat a, CGFloat width)
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

static void Book(CGContextRef c, CGRect r, unsigned face, unsigned edge, BOOL small)
{
    CGContextSaveGState(c);
    Shadow(c, 6, 10, 0.25);
    Fill(c, face, 1);
    RoundRect(c, r, small ? 10 : 14);
    CGContextFillPath(c);
    CGContextRestoreGState(c);
    Stroke(c, edge, 1, small ? 10 : 6);
    RoundRect(c, CGRectInset(r, small ? 5 : 3, small ? 5 : 3), small ? 8 : 12);
    CGContextStrokePath(c);
    if (!small) {
        // Two bands across the spine, as printed books have.
        Fill(c, edge, 0.55);
        CGContextFillRect(c, CGRectMake(r.origin.x + 18, r.origin.y + r.size.height - 70, r.size.width - 36, 12));
        CGContextFillRect(c, CGRectMake(r.origin.x + 18, r.origin.y + 58, r.size.width - 36, 12));
    }
}

static void Draw(CGContextRef c, int pixels)
{
    gPixelsPerUnit = pixels / 1024.0;
    CGContextScaleCTM(c, gPixelsPerUnit, gPixelsPerUnit);
    BOOL small = pixels <= 32;

    // The square, inset so its shadow stays inside the canvas.
    CGRect tile = CGRectMake(100, 110, 824, 824);
    CGContextSaveGState(c);
    Shadow(c, 12, 24, 0.35);
    Fill(c, 0xf4f1ea, 1);
    RoundRect(c, tile, 180);
    CGContextFillPath(c);
    CGContextRestoreGState(c);
    Stroke(c, 0x000000, 0.12, small ? 16 : 4);
    RoundRect(c, CGRectInset(tile, 2, 2), 178);
    CGContextStrokePath(c);

    // The shelf.
    CGRect shelf = CGRectMake(190, 250, 644, small ? 64 : 44);
    CGContextSaveGState(c);
    Shadow(c, 8, 12, 0.3);
    Fill(c, 0x8a5a33, 1);
    RoundRect(c, shelf, 10);
    CGContextFillPath(c);
    CGContextRestoreGState(c);

    // The books: white, blue, red. Centred on what's drawn.
    CGFloat w = small ? 170 : 150, gap = small ? 26 : 34, base = NSMaxY(NSRectFromCGRect(shelf));
    CGFloat total = 3 * w + 2 * gap, x = 512 - total / 2;
    Book(c, CGRectMake(x, base, w, 520), 0xffffff, 0xc9c9cf, small);
    Book(c, CGRectMake(x + w + gap, base, w, 580), 0x1f4fb4, 0x173d8c, small);
    Book(c, CGRectMake(x + 2 * (w + gap), base, w, 500), 0xd62a2a, 0xa51f1f, small);

    // A play mark on the blue book.
    CGFloat cx = x + w + gap + w / 2, cy = base + 290, s = small ? 70 : 54;
    Fill(c, 0xffffff, 0.95);
    CGContextMoveToPoint(c, cx - s * 0.6, cy - s);
    CGContextAddLineToPoint(c, cx + s * 0.9, cy);
    CGContextAddLineToPoint(c, cx - s * 0.6, cy + s);
    CGContextClosePath(c);
    CGContextFillPath(c);
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
                [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[dir stringByAppendingPathComponent:name] atomically:YES];
                CGImageRelease(image);
                CGContextRelease(c);
            }
        }
    }
    return 0;
}
