// Renders Shelf's windows to PNG, offscreen, at 1x and 2x.
//
//   rsshots <Tests/Fixtures> <output folder>      (RUSSIAN_SHELF_NOW fixes the clock)
//
// The real controller, shelf view and player, built for 10.9 like the app,
// on a made-up library: a twelve-video shelf sealed with a throwaway test
// key, thumbnails painted here, and JE4cI_Knzvc's real subtitles (first
// minute) from the fixtures. The player's video can't be drawn offscreen,
// so a painted stand-in takes its place; the end-to-end run shows the real
// thing.
//
// It also checks that a few redraws are narrow and complete: the shelf while a
// video plays, the desk card, the sand running in Say (exits 1 if not).

#import <Cocoa/Cocoa.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "RSController.h"
#import "RSLibrary.h"
#import "RSShelf.h"
#import "RSCrypto.h"
#import "RSPlayer.h"
#import "RSReview.h"
#import "RSLines.h"
#import "RSDate.h"
#import "RSClip.h"
#import "RSDictionary.h"
#import "RSSay.h"
#import "RSSayWindow.h"

static const char *KeyPrivate =
    "-----BEGIN EC PRIVATE KEY-----\n"
    "MHcCAQEEIGbk9I7O8dyxuo149WwYWIY9B1ByiOXawOSpVntqOXMloAoGCCqGSM49\n"
    "AwEHoUQDQgAEzhubex2CwB7M6jhxQ7gV5NZg7h5sTMmbDGZqUN5uF//iskG6wpay\n"
    "WPE8Fdyakh2SNf4KK62rVDAPVF2FhfWLqw==\n"
    "-----END EC PRIVATE KEY-----\n";
static const char *KeyPublic =
    "3059301306072a8648ce3d020106082a8648ce3d03010703420004ce1b9b7b1d82c01ecc"
    "ea387143b815e4d660ee1e6c4cc99b0c666a50de6e17ffe2b241bac296b258f13c15dc9a"
    "921d9235fe0a2badab54300f545d8585f58bab";

static NSData *Hex(const char *hex)
{
    NSMutableData *d = [NSMutableData data];
    for (const char *p = hex; p[0] && p[1]; p += 2) {
        unsigned int byte;
        sscanf(p, "%2x", &byte);
        unsigned char b = (unsigned char)byte;
        [d appendBytes:&b length:1];
    }
    return d;
}

static NSData *Sign(NSData *message)
{
    SecExternalFormat format = kSecFormatOpenSSL;
    SecExternalItemType type = kSecItemTypePrivateKey;
    SecItemImportExportKeyParameters params;
    memset(&params, 0, sizeof params);
    params.version = SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION;
    CFArrayRef items = NULL;
    NSData *pem = [NSData dataWithBytes:KeyPrivate length:strlen(KeyPrivate)];
    SecItemImport((CFDataRef)pem, NULL, &format, &type, 0, &params, NULL, &items);
    SecTransformRef signer = SecSignTransformCreate((SecKeyRef)CFArrayGetValueAtIndex(items, 0), NULL);
    int bits = 256;
    CFNumberRef length = CFNumberCreate(NULL, kCFNumberIntType, &bits);
    SecTransformSetAttribute(signer, kSecTransformInputAttributeName, (CFDataRef)message, NULL);
    SecTransformSetAttribute(signer, kSecDigestTypeAttribute, kSecDigestSHA2, NULL);
    SecTransformSetAttribute(signer, kSecDigestLengthAttribute, length, NULL);
    NSData *signature = (NSData *)SecTransformExecute(signer, NULL);
    CFRelease(length);
    CFRelease(signer);
    CFRelease(items);
    return [signature autorelease];
}

static NSData *AES(void) { return Hex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"); }

// The shelf, as Claude might write it. Only the first is a real video; the
// rest are stand-ins of the right shape.
static const char *Videos[12][4] = {
    { "JE4cI_Knzvc", "Sergey Storyteller", "She Cut Her Hair to Save Her Husband ✂️ Story in Easy Russian", "1160" },
    { "aaaaaaaaaa1", "Sergey Storyteller", "The Fox and the Crane 🦊 Story in Easy Russian", "690" },
    { "aaaaaaaaaa2", "Sergey Storyteller", "Why the Bear Has a Short Tail 🐻 Story in Easy Russian", "784" },
    { "aaaaaaaaaa3", "Sergey Storyteller", "Masha and the Bear: the Old Tale, Not the Cartoon", "903" },
    { "aaaaaaaaaa4", "Sergey Storyteller", "The Frog Princess 🐸 Story in Easy Russian (Part 1)", "1022" },
    { "aaaaaaaaaa5", "Sergey Storyteller", "The Frog Princess 🐸 Story in Easy Russian (Part 2)", "998" },
    { "aaaaaaaaaa6", "Sergey Storyteller", "Ivan the Fool and the Flying Ship", "1240" },
    { "aaaaaaaaaa7", "Sergey Storyteller", "The Snow Maiden ❄️ Story in Easy Russian", "811" },
    { "aaaaaaaaaa8", "Sergey Storyteller", "Baba Yaga's Hut on Chicken Legs", "760" },
    { "aaaaaaaaaa9", "Sergey Storyteller", "The Golden Fish 🐟 Story in Easy Russian", "655" },
    { "aaaaaaaaab0", "Easy Russian", "What Do Russians Eat for Breakfast? | Easy Russian 12", "642" },
    { "aaaaaaaaab1", "Comprehensible Russian", "A Walk Through Old Moscow (Beginner)", "1305" },
};

static NSImage *Painted(int i, NSString *letter)
{
    static const unsigned colors[12] = { 0x7a4b2a, 0xc0662b, 0x5b6f3a, 0x3f6f8f, 0x4f7d4a, 0x6a5a8c,
                                         0x8c3b3b, 0x3d5f8c, 0x5a4636, 0x2e7b7b, 0x8a6d2f, 0x4b4b6e };
    NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(480, 270)] autorelease];
    [image lockFocus];
    unsigned c = colors[i % 12];
    NSColor *a = [NSColor colorWithCalibratedRed:((c >> 16) & 255) / 255.0 green:((c >> 8) & 255) / 255.0 blue:(c & 255) / 255.0 alpha:1];
    NSGradient *g = [[[NSGradient alloc] initWithStartingColor:[a blendedColorWithFraction:0.35 ofColor:[NSColor whiteColor]] endingColor:a] autorelease];
    [g drawInRect:NSMakeRect(0, 0, 480, 270) angle:-70];
    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:[NSFont boldSystemFontOfSize:120], NSFontAttributeName,
                           [NSColor colorWithCalibratedWhite:1 alpha:0.85], NSForegroundColorAttributeName, nil];
    NSSize s = [letter sizeWithAttributes:attrs];
    [letter drawAtPoint:NSMakePoint(240 - s.width / 2, 135 - s.height / 2) withAttributes:attrs];
    [image unlockFocus];
    return image;
}

static void WriteJPEG(NSImage *image, NSString *path)
{
    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:[image TIFFRepresentation]];
    [[rep representationUsingType:NSJPEGFileType properties:[NSDictionary dictionary]] writeToFile:path atomically:YES];
}

static void Install(RSLibrary *library, NSString *identifier, NSString *subtitles, NSImage *thumbnail, double duration)
{
    NSString *staging = [library stagingFolder:identifier];
    [[NSFileManager defaultManager] createDirectoryAtPath:staging withIntermediateDirectories:YES attributes:nil error:NULL];
    [@"stand-in" writeToFile:[staging stringByAppendingPathComponent:@"video.mp4"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    if (subtitles) [[NSFileManager defaultManager] copyItemAtPath:subtitles toPath:[staging stringByAppendingPathComponent:
                    [@"subtitles." stringByAppendingString:[[subtitles lastPathComponent] substringFromIndex:12]]] error:NULL];
    WriteJPEG(thumbnail, [staging stringByAppendingPathComponent:@"thumbnail.jpg"]);
    NSString *problem = nil;
    if (![library installDownload:identifier duration:duration problem:&problem])
        fprintf(stderr, "rsshots: install %s: %s\n", [identifier UTF8String], [problem UTF8String]);
}

static void Shoot(NSView *view, NSString *path, CGFloat scale)
{
    NSRect r = [view bounds];
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)(NSWidth(r) * scale) pixelsHigh:(NSInteger)(NSHeight(r) * scale)
                   bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace
                     bytesPerRow:0 bitsPerPixel:0] autorelease];
    [rep setSize:r.size];
    [view displayIfNeeded];
    [view cacheDisplayInRect:r toBitmapImageRep:rep];
    NSData *png = [rep representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]];
    if (![png writeToFile:path atomically:YES]) { fprintf(stderr, "rsshots: can't write %s\n", [path fileSystemRepresentation]); exit(1); }
    printf("  shot     %s\n", [[path lastPathComponent] UTF8String]);
}

static void ShootBoth(NSWindow *window, NSString *out, NSString *name)
{
    NSView *content = [window contentView];
    [content setNeedsDisplay:YES];
    Shoot(content, [out stringByAppendingPathComponent:[name stringByAppendingString:@".png"]], 1);
    Shoot(content, [out stringByAppendingPathComponent:[name stringByAppendingString:@"@2x.png"]], 2);
}

static void Spin(double seconds)
{
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

// ---- Redraws: a view marks only what changed, and that is enough --------------
//
// Watch() has a view note each rect it marks to be drawn again; Patched()
// clears and draws just those over a picture of the view from before, as the
// window would, and Same() compares that with the view drawn whole afterwards.

static NSMutableArray *Marked;
static int Failed;

static void MarkRect(id self, SEL _cmd, NSRect r)
{
    [Marked addObject:[NSValue valueWithRect:r]];
    struct objc_super up = { self, class_getSuperclass(object_getClass(self)) };
    ((void (*)(struct objc_super *, SEL, NSRect))objc_msgSendSuper)(&up, _cmd, r);
}

static void MarkAll(id self, SEL _cmd, BOOL flag)
{
    if (flag) [Marked addObject:[NSValue valueWithRect:[(NSView *)self bounds]]];
    struct objc_super up = { self, class_getSuperclass(object_getClass(self)) };
    ((void (*)(struct objc_super *, SEL, BOOL))objc_msgSendSuper)(&up, _cmd, flag);
}

static void Watch(NSView *view)
{
    Class plain = object_getClass(view);
    NSString *name = [@"Marking" stringByAppendingString:NSStringFromClass(plain)];
    Class marking = NSClassFromString(name);
    if (marking == Nil) {
        marking = objc_allocateClassPair(plain, [name UTF8String], 0);
        class_addMethod(marking, @selector(setNeedsDisplayInRect:), (IMP)MarkRect, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}");
        class_addMethod(marking, @selector(setNeedsDisplay:), (IMP)MarkAll, "v@:c");
        objc_registerClassPair(marking);
    }
    [Marked release];
    Marked = [[NSMutableArray alloc] init];
    object_setClass(view, marking);
}

static NSArray *Unwatch(NSView *view)
{
    object_setClass(view, class_getSuperclass(object_getClass(view)));
    return Marked;
}

// Drawn as the window draws it (the same call as for a part, so text is
// smoothed the same way), onto nothing.
static NSBitmapImageRep *Snapshot(NSView *view)
{
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:[view bounds]];
    memset([rep bitmapData], 0, (size_t)([rep bytesPerRow] * [rep pixelsHigh]));
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [view displayRectIgnoringOpacity:[view bounds] inContext:context];
    [context flushGraphics];
    return rep;
}

// Each rect cleared, as a window clears what it draws again, then drawn.
static NSBitmapImageRep *Patched(NSView *view, NSBitmapImageRep *before, NSArray *rects)
{
    NSRect b = [view bounds];
    CGFloat scale = [before pixelsWide] / NSWidth(b);
    NSMutableArray *clipped = [NSMutableArray array];
    for (NSValue *v in rects) {
        NSRect r = NSIntersectionRect(NSIntegralRect([v rectValue]), b);
        [clipped addObject:[NSValue valueWithRect:r]];
        CGFloat top = [view isFlipped] ? NSMinY(r) - NSMinY(b) : NSMaxY(b) - NSMaxY(r);
        NSInteger x0 = (NSInteger)(NSMinX(r) * scale), x1 = (NSInteger)(NSMaxX(r) * scale);
        for (NSInteger y = (NSInteger)(top * scale); y < (NSInteger)((top + NSHeight(r)) * scale); y++)
            memset([before bitmapData] + y * [before bytesPerRow] + x0 * [before bitsPerPixel] / 8, 0,
                   (size_t)((x1 - x0) * [before bitsPerPixel] / 8));
    }
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:before];
    for (NSValue *v in clipped) [view displayRectIgnoringOpacity:[v rectValue] inContext:context];
    [context flushGraphics];
    return before;
}

// The same pixels, give or take `slack` in a channel (a gradient drawn in
// part rounds a level differently, as it does in a window).
static BOOL Same(NSBitmapImageRep *a, NSBitmapImageRep *b, int slack)
{
    if ([a pixelsWide] != [b pixelsWide] || [a pixelsHigh] != [b pixelsHigh] || [a bytesPerRow] != [b bytesPerRow]) return NO;
    const unsigned char *p = [a bitmapData], *q = [b bitmapData];
    for (NSInteger i = 0; i < [a bytesPerRow] * [a pixelsHigh]; i++)
        if (abs((int)p[i] - (int)q[i]) > slack) return NO;
    return YES;
}

static NSRect Union(NSArray *rects)
{
    NSRect u = NSZeroRect;
    for (NSValue *v in rects) u = NSUnionRect(u, [v rectValue]);
    return u;
}

static void Check(BOOL ok, NSString *what)
{
    printf("  redraw   %s: %s\n", ok ? "ok" : "FAILED", [what UTF8String]);
    if (!ok) Failed++;
}

// The view drawn after `change`, whole, is the picture before with only the
// marked rects drawn again. Returns the rects.
static NSArray *Redraws(NSView *view, NSString *what, void (^change)(void))
{
    NSBitmapImageRep *before = Snapshot(view);
    NSBitmapImageRep *again = Snapshot(view);
    Watch(view);
    change();
    NSArray *rects = [[Unwatch(view) copy] autorelease];
    NSBitmapImageRep *after = Snapshot(view);
    Check(!Same(again, after, 1), [what stringByAppendingString:@" changes the picture"]);
    Check(Same(Patched(view, before, rects), after, 1), [what stringByAppendingString:@": what was marked is all that changed"]);
    return rects;
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc != 3) { fprintf(stderr, "usage: rsshots <Tests/Fixtures> <output folder>\n"); return 2; }
        NSString *fixtures = [NSString stringWithUTF8String:argv[1]];
        NSString *out = [NSString stringWithUTF8String:argv[2]];
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];

        NSString *folder = [out stringByAppendingPathComponent:@"library"];
        [[NSFileManager defaultManager] removeItemAtPath:folder error:NULL];
        RSLibrary *library = [[[RSLibrary alloc] initWithFolder:folder aesKey:AES() publicKey:Hex(KeyPublic)] autorelease];
        NSMutableString *text = [NSMutableString stringWithString:@"Russian Shelf 1\nstart: 2026-10-12\nsealed: 2026-10-11 20:15:07\n"];
        for (int i = 0; i < 12; i++) {
            if (i == 0) [text appendString:@"# kind: easy\n"];
            if (i == 7) [text appendString:@"# kind: natural\n"];
            if (i == 10) [text appendString:@"# kind: fast\n"];
            [text appendFormat:@"video: %@ | %@ | %@\n", [NSString stringWithUTF8String:Videos[i][0]],
             [NSString stringWithUTF8String:Videos[i][1]], [NSString stringWithUTF8String:Videos[i][2]]];
        }
        NSData *iv = Hex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff");
        NSString *problem = nil;
        NSData *file = RSSealShelf([RSShelf shelfWithText:text problem:&problem], AES(), iv,
                                   ^NSData *(NSData *message, NSString **why) { return Sign(message); }, &problem);
        [library offerShelfFile:file today:0];

        NSString *made = [fixtures stringByAppendingPathComponent:@"JE4cI_Knzvc.ru.vtt"];
        NSString *automatic = [fixtures stringByAppendingPathComponent:@"JE4cI_Knzvc.ru-orig.vtt"];
        NSArray *letters = [NSArray arrayWithObjects:@"Ж", @"Л", @"М", @"Б", @"Ц", @"Ц", @"И", @"С", @"Я", @"Р", @"Е", @"Г", nil];
        for (int i = 0; i < 5; i++)
            Install(library, [NSString stringWithUTF8String:Videos[i][0]], i == 1 ? automatic : made,
                    Painted(i, [letters objectAtIndex:i]), atof(Videos[i][3]));
        [library recordPosition:0 furthest:1160 duration:1160 for:@"JE4cI_Knzvc"];
        [library recordPosition:0 furthest:690 duration:690 for:@"aaaaaaaaaa1"];
        [library recordPosition:250 furthest:250 duration:784 for:@"aaaaaaaaaa2"];
        [library save];

        RSController *c = [[[RSController alloc] initWithLibrary:library studyFolder:@"/nonexistent/Study"] autorelease];
        [c setDictionary:[[[RSDictionary alloc] initWithFile:[fixtures stringByAppendingPathComponent:@"dict.sqlite"]] autorelease]];
        [c showWindow];
        [[c window] orderOut:nil];
        [[c window] setContentSize:[RSStyle shelfWindowSize]];
        [c setDownload:@"aaaaaaaaaa5" progress:0.45 problem:nil];
        [c setDownload:@"aaaaaaaaab1" progress:0 problem:@"YouTube asked for a pause. It will try again later."];
        [c setStatusForTesting:@"Looked for a new shelf at 8:30 PM.  Downloading 6 videos." problem:NO];
        ShootBoth([c window], out, @"shelf");
        [[c shelfView] hoverRow:2];
        ShootBoth([c window], out, @"shelf-hover");
        [[c shelfView] hoverRow:-1];
        NSScrollView *scroll = [[c shelfView] enclosingScrollView];
        [[scroll contentView] scrollToPoint:NSMakePoint(0, NSHeight([[c shelfView] frame]) - NSHeight([[scroll contentView] bounds]))];
        [scroll reflectScrolledClipView:[scroll contentView]];
        ShootBoth([c window], out, @"shelf-end");
        [[c window] setContentSize:[RSStyle shelfWindowMinSize]];
        [[scroll contentView] scrollToPoint:NSZeroPoint];
        [scroll reflectScrolledClipView:[scroll contentView]];
        [c setStatusForTesting:@"A new shelf was turned away. The signature doesn’t match Claude’s key. Keeping this week’s shelf." problem:YES];
        ShootBoth([c window], out, @"shelf-small");

        // The player: a line revealed; then subtitles on with the transcript.
        RSPlayer *player = [c playVideo:@"JE4cI_Knzvc"];
        [player usePlaceholderVideoForTesting];
        [[player window] orderOut:nil];
        [[player window] setContentSize:NSMakeSize([RSStyle playerVideoSize].width, [RSStyle playerVideoSize].height + [RSStyle hintBarHeight])];
        [player setTimeForTesting:5.0];
        [player revealLine];
        printf("  revealed %s\n", [[[player visibleCaption] stringByReplacingOccurrencesOfString:@"\n" withString:@" / "] UTF8String]);
        ShootBoth([player window], out, @"player-reveal");
        [player setTimeForTesting:12.0];
        printf("  later    %s\n", [player visibleCaption] ? [[player visibleCaption] UTF8String] : "(hidden again)");
        ShootBoth([player window], out, @"player");
        [player toggleTranscript];
        [player toggleSubtitles];
        Spin(1.4);      // let the "Subtitles stay on." note pass
        [player setTimeForTesting:27.5];
        ShootBoth([player window], out, @"player-transcript");
        [player toggleTranscript];
        [player toggleSubtitles];
        Spin(1.4);
        // Working on one line: looped, slower, then kept.
        [player setTimeForTesting:8.0];
        [player toggleSlower];
        [player toggleLoop];
        [player revealLine];
        printf("  looping  %s\n", [player looping] ? "yes" : "no");
        ShootBoth([player window], out, @"player-loop");
        [player toggleLoop];
        [player toggleSlower];
        [player setTimeForTesting:16.0];
        [player keepLine];
        printf("  kept     %s\n", [[player visibleNote] UTF8String]);
        ShootBoth([player window], out, @"player-keep");
        // A word looked up: the slip over the picture, the rarest word chosen.
        Spin(2.6);      // let the "Kept." note pass
        [player toggleWordSlip];
        [player chooseSlipWord:1];      // "что": a word the fixture dictionary knows
        printf("  word     slip %s, word %ld\n", [player wordSlipShown] ? "shown" : "hidden", (long)[player slipSelection]);
        ShootBoth([player window], out, @"player-word");
        [player keepSlipWord];
        printf("  kept     %s\n", [[player visibleNote] UTF8String]);
        [player toggleWordSlip];
        // Today's clip: the card in each of its passes.
        Spin(2.6);
        [player setTimeForTesting:5.0];
        [player setClipPassForTesting:RSClipListen];
        printf("  clip     pass %d\n", (int)[player clipPass]);
        ShootBoth([player window], out, @"player-clip-listen");
        [player setClipPassForTesting:RSClipRead];
        [player revealLine];
        ShootBoth([player window], out, @"player-clip-read");
        [player setClipPassForTesting:RSClipSay];
        [player toggleRecordSayAlong];
        Spin(2.2);
        ShootBoth([player window], out, @"player-clip-say");
        [player toggleRecordSayAlong];
        [player setClipPassForTesting:RSClipDone];
        Spin(2.2);
        ShootBoth([player window], out, @"player-clip-done");
        [player leaveClip];
        // The desk card the next day: a card to hear again, then the story.
        setenv("RUSSIAN_SHELF_NOW", "2026-10-15 20:30", 1);
        [c reloadRows];
        [[c shelfView] hoverDeskLine:0];
        printf("  desk     %lu lines\n", (unsigned long)[[[c shelfView] deskLines] count]);
        ShootBoth([c window], out, @"shelf-desk");
        // The mouse over the last line must light the last line (the view is flipped).
        NSInteger last = (NSInteger)[[[c shelfView] deskLines] count] - 1;
        NSRect lastRect = [[[RSStyle deskLineRectsIn:[[c shelfView] deskCardRect] count:(NSUInteger)last + 1 flipped:YES] lastObject] rectValue];
        [[c shelfView] hoverDeskLine:[[c shelfView] deskLineAtPoint:NSMakePoint(NSMidX(lastRect), NSMidY(lastRect))]];
        printf("  desk     hovering the last line lights %ld (expected %ld)\n", (long)[[c shelfView] deskHover], (long)last);
        ShootBoth([c window], out, @"shelf-desk-last");
        [[c shelfView] hoverDeskLine:-1];
        setenv("RUSSIAN_SHELF_NOW", "2026-10-14 20:30", 1);
        // After watching: how was it? One click each, about the video.
        [player chooseFeedback:RSFeltAboutRight];
        [player chooseFeedback:RSWantMore];
        [player toggleFeedback];
        printf("  felt     %s / %s, shown %d\n", [[player felt] UTF8String], [[player want] UTF8String], (int)[player feedbackShown]);
        ShootBoth([player window], out, @"player-feedback");
        [player chooseFeedback:RSWantMore];
        printf("  again    want %s; stored %s / %s\n", [player want] ? [[player want] UTF8String] : "(cleared)",
               [[[c library] feltFor:@"JE4cI_Knzvc"] UTF8String], [[c library] wantFor:@"JE4cI_Knzvc"] ? "set" : "(cleared)");
        [player close];

        // Automatic captions, rebuilt into sentences, in the transcript.
        player = [c playVideo:@"aaaaaaaaaa1"];
        [player usePlaceholderVideoForTesting];
        [[player window] orderOut:nil];
        [player toggleTranscript];
        [player setTimeForTesting:10.0];
        [player revealLine];
        ShootBoth([player window], out, @"player-auto");
        [player close];

        // Lines to hear again: kept yesterday, so due today.
        RSLines *lines = [c lines];
        RSKeptLine *first = [lines keepText:@"Она отрезала волосы, чтобы спасти мужа." before:@"И тогда она решила."
                  video:@"JE4cI_Knzvc" title:[NSString stringWithUTF8String:Videos[0][2]] start:250 end:253 today:RSToday() - 1 problem:NULL];
        [lines keepText:@"Вася любит кошек." before:nil video:@"aaaaaaaaaa1" title:[NSString stringWithUTF8String:Videos[1][2]]
                  start:61 end:63 today:RSToday() - 1 problem:NULL];
        // A sound for the first (a second of silence, never played here), so
        // it comes up as "listen"; the second has none.
        NSString *wav = [out stringByAppendingPathComponent:@"silence.wav"];
        NSMutableData *pcm = [NSMutableData dataWithLength:44 + 44100];
        unsigned char *h = [pcm mutableBytes];
        uint32_t u32; uint16_t u16;
        memcpy(h, "RIFF", 4); u32 = 36 + 44100; memcpy(h + 4, &u32, 4); memcpy(h + 8, "WAVEfmt ", 8);
        u32 = 16; memcpy(h + 16, &u32, 4); u16 = 1; memcpy(h + 20, &u16, 2); memcpy(h + 22, &u16, 2);
        u32 = 22050; memcpy(h + 24, &u32, 4); u32 = 44100; memcpy(h + 28, &u32, 4);
        u16 = 2; memcpy(h + 32, &u16, 2); u16 = 16; memcpy(h + 34, &u16, 2);
        memcpy(h + 36, "data", 4); u32 = 44100; memcpy(h + 40, &u32, 4);
        [pcm writeToFile:wav atomically:YES];
        NSString *why = nil;
        if (!RSCutClipNow(wav, 0.2, 0.8, [lines soundPath:first], &why))
            fprintf(stderr, "rsshots: sound: %s\n", [why UTF8String]);
        [[NSFileManager defaultManager] removeItemAtPath:wav error:NULL];
        [[c window] setContentSize:[RSStyle shelfWindowSize]];
        [c setStatusForTesting:@"Looked for a new shelf at 8:30 PM." problem:NO];
        [c reloadRows];
        ShootBoth([c window], out, @"shelf-lines-due");
        RSReview *review = [[[RSReview alloc] initWithLines:lines today:RSToday()] autorelease];
        [review setSilentForTesting];
        [[review window] orderOut:nil];
        printf("  lines    state %d\n", (int)[review state]);
        ShootBoth([review window], out, @"lines");
        [review showLine];
        ShootBoth([review window], out, @"lines-shown");
        [review setMeaning:@"She cut off her hair to save her husband."];
        ShootBoth([review window], out, @"lines-meaning");
        [review answer:YES];
        printf("  next     %s\n", [[review visibleText] UTF8String]);
        ShootBoth([review window], out, @"lines-nosound");
        [review answer:YES];
        ShootBoth([review window], out, @"lines-done");
        [review close];
        // The same line, later: with the owner's words it comes up as "say it".
        [first setStep:1];
        [first setDue:RSToday()];
        [lines save];
        RSReview *say = [[[RSReview alloc] initWithLines:lines today:RSToday()] autorelease];
        [say setSilentForTesting];
        [[say window] orderOut:nil];
        printf("  say      state %d: %s\n", (int)[say state], [[say visibleText] UTF8String]);
        ShootBoth([say window], out, @"lines-say");
        [say showLine];
        ShootBoth([say window], out, @"lines-say-shown");
        [say close];
        // A word card: the line's sound, then the word underlined in its line.
        RSKeptLine *wordCard = [lines keepWord:@"волосы" lemma:@"во\u0301лосы" gloss:@"hair" rank:1840
                                        inLine:@"Она отрезала волосы, чтобы спасти мужа." before:@"И тогда она решила."
                                         video:@"JE4cI_Knzvc" title:[NSString stringWithUTF8String:Videos[0][2]] start:250 end:253
                                         today:RSToday() - 1 problem:NULL];
        [first setDue:RSToday() + 3];
        [wordCard setDue:RSToday()];
        [lines save];
        RSReview *wordReview = [[[RSReview alloc] initWithLines:lines today:RSToday()] autorelease];
        [wordReview setSilentForTesting];
        [[wordReview window] orderOut:nil];
        printf("  word     state %d\n", (int)[wordReview state]);
        [wordReview showLine];
        ShootBoth([wordReview window], out, @"lines-word");
        [wordReview close];
        [c reloadRows];
        ShootBoth([c window], out, @"shelf-after-lines");

        // Say: the topic, a pass running, between passes, done; the islands.
        RSSayWindow *say2 = [c showSay];
        [say2 setSilentForTesting];
        [[say2 window] orderOut:nil];
        printf("  say      topic state %d\n", (int)[say2 state]);
        ShootBoth([say2 window], out, @"say");
        [say2 space];
        [say2 setSecondsLeftForTesting:71];
        ShootBoth([say2 window], out, @"say-running");
        // A quarter second of sand: the glass's column is drawn again, not the card.
        NSView *sayView = nil;
        for (NSView *v in [[[say2 window] contentView] subviews]) if ([NSStringFromClass([v class]) isEqualToString:@"RSSayView"]) sayView = v;
        NSArray *sand = Redraws(sayView, @"the sand running", ^{ [say2 performSelector:@selector(tick:) withObject:nil]; });
        Check(NSEqualRects(Union(sand), [RSStyle sayGlassAreaIn:[sayView bounds]]) &&
              NSWidth(Union(sand)) * 3 < NSWidth([sayView bounds]), @"only the sand-glass's column");
        [say2 setSecondsLeftForTesting:0];
        printf("  say      after pass 1: state %d, %s\n", (int)[say2 state], [[say2 visibleNote] UTF8String]);
        ShootBoth([say2 window], out, @"say-between");
        [say2 space];
        [say2 setSecondsLeftForTesting:0];
        [say2 space];
        [say2 setSecondsLeftForTesting:0];
        printf("  say      done: state %d\n", (int)[say2 state]);
        ShootBoth([say2 window], out, @"say-done");
        [say2 toggleIslands];
        ShootBoth([say2 window], out, @"say-islands");
        [say2 toggleIslands];
        [say2 close];
        [c reloadRows];
        ShootBoth([c window], out, @"shelf-after-say");

        // The shelf while a video plays: its row and nothing else.
        RSShelfView *shelf = [c shelfView];
        NSArray *ids = [[shelf rows] valueForKey:@"identifier"];
        NSUInteger playing = [ids indexOfObject:@"aaaaaaaaaa2"];
        NSArray *row = Redraws(shelf, @"five seconds more watched", ^{
            [[c library] recordPosition:300 furthest:300 duration:784 for:@"aaaaaaaaaa2"];
            [c reloadRows];
        });
        Check(playing != NSNotFound && NSEqualRects(Union(row), [shelf rectOfRow:(NSInteger)playing]), @"only the playing video's row");
        Watch(shelf);
        [c reloadRows];
        Check([Unwatch(shelf) count] == 0, @"nothing new: nothing drawn again");
        NSUInteger deskLines = [[shelf deskLines] count];
        NSArray *desk = Redraws(shelf, @"one more card to hear", ^{
            [[c lines] keepText:@"Ещё одна строчка." before:nil video:@"JE4cI_Knzvc" title:@"Story" start:300 end:302
                          today:RSToday() - 1 problem:NULL];
            [c reloadRows];
        });
        if ([[shelf deskLines] count] == deskLines)
            Check(NSEqualRects(Union(desk), [shelf deskCardRect]), @"only the desk card");

        // No shelf at all, and one turned away.
        NSString *emptyFolder = [out stringByAppendingPathComponent:@"empty-library"];
        [[NSFileManager defaultManager] removeItemAtPath:emptyFolder error:NULL];
        RSLibrary *empty = [[[RSLibrary alloc] initWithFolder:emptyFolder aesKey:AES() publicKey:Hex(KeyPublic)] autorelease];
        RSController *e = [[[RSController alloc] initWithLibrary:empty studyFolder:@"/nonexistent/Study"] autorelease];
        [e showWindow];
        [[e window] orderOut:nil];
        [[e window] setContentSize:NSMakeSize(680, 520)];
        [e setStatusForTesting:@"~/Study isn’t here yet." problem:YES];
        ShootBoth([e window], out, @"empty");
    }
    return Failed ? 1 : 0;
}
