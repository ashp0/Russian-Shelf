// Renders Russian Shelf's windows to PNG, offscreen, at 1x and 2x.
//
//   rsshots <Tests/Fixtures> <output folder>      (RUSSIAN_SHELF_NOW fixes the clock)
//
// The real controller, shelf view and player, built for 10.9 like the app,
// on a made-up library: a twelve-video shelf sealed with a throwaway test
// key, thumbnails painted here, and JE4cI_Knzvc's real subtitles (first
// minute) from the fixtures. The player's video can't be drawn offscreen,
// so a painted stand-in takes its place; the end-to-end run shows the real
// thing.

#import <Cocoa/Cocoa.h>
#import <Security/Security.h>
#import "RSController.h"
#import "RSLibrary.h"
#import "RSShelf.h"
#import "RSCrypto.h"
#import "RSPlayer.h"

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
        for (int i = 0; i < 12; i++)
            [text appendFormat:@"video: %@ | %@ | %@\n", [NSString stringWithUTF8String:Videos[i][0]],
             [NSString stringWithUTF8String:Videos[i][1]], [NSString stringWithUTF8String:Videos[i][2]]];
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
    return 0;
}
