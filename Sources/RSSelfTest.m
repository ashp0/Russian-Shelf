#import "RSSelfTest.h"
#import "RSCrypto.h"
#import "RSShelf.h"
#import "RSSubtitles.h"
#import "RSLibrary.h"
#import "RSDownloader.h"
#import "RSProcess.h"
#import "RSSync.h"

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "RSClip.h"
#import <CoreMedia/CoreMedia.h>

static int passed = 0, failed = 0;

static void Line(BOOL ok, NSString *what, NSString *detail)
{
    if (ok) passed++; else failed++;
    printf("%s  %s%s%s\n", ok ? "ok  " : "FAIL", [what UTF8String], [detail length] ? ": " : "", [detail UTF8String] ?: "");
    fflush(stdout);
}

static void Note(NSString *what)
{
    printf("--    %s\n", [what UTF8String]);
    fflush(stdout);
}

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

static NSString *FirstLine(NSString *s)
{
    for (NSString *line in [s componentsSeparatedByString:@"\n"]) {
        NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([t length]) return t;
    }
    return @"";
}

static RSProcessResult *Run(NSArray *args, NSDictionary *env, NSTimeInterval timeout)
{
    return [RSProcess run:args environment:env directory:nil stdin:nil timeout:timeout handle:nil line:nil];
}

static void TestCrypto(void)
{
    NSData *key = Hex("603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4");
    NSData *iv = Hex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff");
    NSData *plain = Hex("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51");
    NSData *cipher = Hex("601ec313775789a5b7a7f504bbf3d228f443e3ca4d62b59aca84e990cacaf5c5");
    Line([RSAESCTR(plain, key, iv) isEqualToData:cipher], @"AES-256-CTR with CommonCrypto (NIST test vector)", nil);

    NSData *file = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"selftest" ofType:@"signed"]];
    NSString *problem = nil;
    RSShelf *shelf = file ? RSOpenShelfFile(file, &problem) : nil;
    Line(shelf != nil, @"a shelf sealed with Claude's key opens (SecItemImport + SecVerifyTransform)",
         shelf ? [NSString stringWithFormat:@"%lu video, sealed %@", (unsigned long)[[shelf videos] count], [shelf sealed]]
               : (problem ?: @"selftest.signed is missing"));
    if (file) {
        NSMutableData *tampered = [[file mutableCopy] autorelease];
        ((unsigned char *)[tampered mutableBytes])[60] ^= 0x01;
        Line(RSOpenShelfFile(tampered, &problem) == nil, @"the same shelf, altered by one bit, is refused", problem);
    }
}

static void TestSubtitles(void)
{
    RSSubtitles *made = [RSSubtitles subtitlesWithVTT:
        @"WEBVTT\nKind: captions\nLanguage: ru\n\n00:00:00.160 --> 00:00:03.309\nПривет. \nМеня зовут Сергей,\n\n"
        @"00:00:03.309 --> 00:00:08.545\nи&nbsp;сегодня я расскажу вам историю.\n"];
    Line(made && ![made automatic] && [[made lines] count] == 2 &&
         [[(RSLine *)[[made lines] objectAtIndex:1] text] isEqualToString:@"и сегодня я расскажу вам историю."],
         @"subtitles made by a person", nil);
    RSSubtitles *rolling = [RSSubtitles subtitlesWithVTT:
        @"WEBVTT\n\n00:00:00.160 --> 00:00:05.990 align:start position:0%\n \nПривет.<00:00:01.160><c> Меня</c><00:00:01.880><c> зовут</c>\n\n"
        @"00:00:05.990 --> 00:00:06.000 align:start position:0%\nПривет. Меня зовут\n \n\n"
        @"00:00:06.000 --> 00:00:09.990 align:start position:0%\nПривет. Меня зовут\nСергей.<00:00:07.120><c> Ну</c><00:00:07.879><c> что?</c>\n"];
    NSArray *lines = [rolling lines];
    Line([rolling automatic] && [lines count] == 3 && [[(RSLine *)[lines objectAtIndex:1] text] isEqualToString:@"Меня зовут Сергей."],
         @"automatic captions, rebuilt into sentences", nil);
}

static NSString *OSVersion(void)
{
    NSDictionary *v = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
    return [NSString stringWithFormat:@"%@ %@ (%@)", [v objectForKey:@"ProductName"], [v objectForKey:@"ProductVersion"],
            [v objectForKey:@"ProductBuildVersion"]];
}

static void TestTools(RSTools *tools, NSDictionary *env)
{
    NSString *missing = [tools missing];
    Line(missing == nil, @"the bundled tools are all here", missing ? [@"missing " stringByAppendingString:missing] : nil);
    if (missing) return;

    RSProcessResult *r = Run([NSArray arrayWithObjects:[tools python], @"-I", @"-B", @"-c",
        @"import ssl, socket, sqlite3, ctypes, hashlib, subprocess, certifi, Cryptodome; print(ssl.OPENSSL_VERSION)", nil], env, 60);
    Line([r status] == 0, @"Python 3.14 starts, with its modules", FirstLine([r output]));

    r = Run([NSArray arrayWithObjects:[tools quickjs], @"--help", nil], env, 30);
    NSString *qjsVersion = FirstLine([r output]);
    r = Run([NSArray arrayWithObjects:[tools quickjs], @"-e", @"print([1, 2, 3].map(x => x * 14).join(','))", nil], env, 30);
    Line([FirstLine([r output]) isEqualToString:@"14,28,42"], @"QuickJS runs JavaScript", qjsVersion);

    r = Run([NSArray arrayWithObjects:[tools ffmpeg], @"-hide_banner", @"-bsfs", nil], env, 30);
    BOOL bsf = [[r output] rangeOfString:@"h264_metadata"].location != NSNotFound;
    r = Run([NSArray arrayWithObjects:[tools ffmpeg], @"-version", nil], env, 30);
    Line([r status] == 0 && bsf, @"ffmpeg starts and has the H.264 level fix", FirstLine([r output]));

    NSString *copy = [[RSLibrary defaultFolder] stringByAppendingPathComponent:@"yt-dlp"];
    BOOL haveCopy = [[NSFileManager defaultManager] fileExistsAtPath:copy];
    r = Run(RSVersionArguments(tools, [tools bundledYtDlp]), env, 60);
    NSString *detail = [NSString stringWithFormat:@"bundled %@", FirstLine([r output])];
    if (haveCopy) {
        RSProcessResult *c = Run(RSVersionArguments(tools, copy), env, 60);
        detail = [detail stringByAppendingFormat:@", in use %@", [c status] == 0 ? FirstLine([c output]) : @"(broken: replaced next time)"];
    }
    Line([r status] == 0, @"yt-dlp starts", detail);
}

static void TestCertificates(RSTools *tools, NSDictionary *env)
{
    // Each URL: "ok", "refused" (a certificate problem), or "offline".
    NSString *script =
        @"import sys, ssl, urllib.request, urllib.error\n"
        @"for url in sys.argv[1:]:\n"
        @"    try:\n"
        @"        urllib.request.urlopen(url, timeout=20).read(64)\n"
        @"        print('ok', url)\n"
        @"    except urllib.error.HTTPError:\n"
        @"        print('ok', url)\n"
        @"    except Exception as e:\n"
        @"        r = getattr(e, 'reason', e)\n"
        @"        print('refused' if isinstance(r, ssl.SSLCertVerificationError) or 'CERTIFICATE_VERIFY_FAILED' in str(e) else 'offline', url, str(r)[:90])\n";
    RSProcessResult *r = Run([NSArray arrayWithObjects:[tools python], @"-I", @"-B", @"-c", script,
                              @"https://www.youtube.com/", @"https://github.com/",
                              @"https://self-signed.badssl.com/", @"https://expired.badssl.com/", @"https://wrong.host.badssl.com/", nil], env, 120);
    NSArray *lines = [[r output] componentsSeparatedByString:@"\n"];
    BOOL offline = [r status] != 0 || [[r output] rangeOfString:@"offline https://www.youtube.com/"].location != NSNotFound;
    if (offline) {
        Note([NSString stringWithFormat:@"certificates: skipped, this Mac seems to be offline (%@)", FirstLine([r output])]);
        return;
    }
    for (NSString *line in lines) {
        if ([line length] == 0) continue;
        BOOL good = [line rangeOfString:@"badssl"].location == NSNotFound;
        BOOL ok = good ? [line hasPrefix:@"ok "] : [line hasPrefix:@"refused "];
        NSArray *words = [line componentsSeparatedByString:@" "];
        NSString *url = [words count] > 1 ? [words objectAtIndex:1] : line;
        Line(ok, good ? [NSString stringWithFormat:@"certificate accepted: %@", url]
                      : [NSString stringWithFormat:@"bad certificate refused: %@", url], ok ? nil : line);
    }
}

static void TestStudyFolder(void)
{
    NSString *chosen = [[NSUserDefaults standardUserDefaults] stringForKey:@"StudyFolder"];
    NSString *study = [chosen length] ? [chosen stringByExpandingTildeInPath] : [NSHomeDirectory() stringByAppendingPathComponent:@"Study"];
    NSString *git = [RSSync gitPath];
    Line(git != nil, @"git is installed", git);
    Line([RSSync isRepository:study], [NSString stringWithFormat:@"%@ is a git clone", [study stringByAbbreviatingWithTildeInPath]], nil);
    NSData *file = [NSData dataWithContentsOfFile:[study stringByAppendingPathComponent:@"Russian/shelf.signed"]];
    if (file == nil) {
        Note(@"no Russian/shelf.signed in the study folder yet");
    } else {
        NSString *problem = nil;
        RSShelf *shelf = RSOpenShelfFile(file, &problem);
        Line(shelf != nil, @"the study folder's shelf opens",
             shelf ? [NSString stringWithFormat:@"%lu video%s from %@", (unsigned long)[[shelf videos] count],
                      [[shelf videos] count] == 1 ? "" : "s", [shelf startText]] : problem);
    }
}

static void TestLibrary(void)
{
    NSString *folder = [RSLibrary defaultFolder];
    RSLibrary *library = [[[RSLibrary alloc] initWithFolder:folder] autorelease];
    BOOL writable = [[NSFileManager defaultManager] isWritableFileAtPath:folder];
    Line(writable, [NSString stringWithFormat:@"%@ is writable", [folder stringByAbbreviatingWithTildeInPath]], nil);
    if ([library notice]) Note([NSString stringWithFormat:@"the last shelf turned away: %@", [library notice]]);
    RSShelf *shelf = [library current];
    if (shelf == nil) { Note(@"no shelf taken yet"); return; }
    NSUInteger downloaded = 0;
    NSString *sample = nil;
    for (NSString *identifier in [shelf identifiers])
        if ([library isDownloaded:identifier]) { downloaded++; if (!sample) sample = identifier; }
    Note([NSString stringWithFormat:@"this week's shelf: %lu video%s from %@, %lu downloaded", (unsigned long)[[shelf videos] count],
          [[shelf videos] count] == 1 ? "" : "s", [shelf startText], (unsigned long)downloaded]);
    if (sample == nil) return;

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:[library moviePath:sample]] options:nil];
    NSArray *video = [asset tracksWithMediaType:AVMediaTypeVideo];
    NSString *codec = @"none";
    if ([video count]) {
        NSArray *descriptions = [(AVAssetTrack *)[video objectAtIndex:0] formatDescriptions];
        if ([descriptions count]) {
            FourCharCode c = CMFormatDescriptionGetMediaSubType((CMFormatDescriptionRef)[descriptions objectAtIndex:0]);
            codec = [NSString stringWithFormat:@"%c%c%c%c", (char)(c >> 24), (char)(c >> 16), (char)(c >> 8), (char)c];
        }
    }
    Line([asset isPlayable] && [codec isEqualToString:@"avc1"],
         [NSString stringWithFormat:@"AVFoundation can play %@", sample],
         [NSString stringWithFormat:@"%@, %@", codec, [library subtitlesPath:sample] && [[library infoFor:sample] objectForKey:@"subtitles"]
                                                    ? [NSString stringWithFormat:@"subtitles %@", [[library infoFor:sample] objectForKey:@"subtitles"]] : @""]);

    // What K does: two seconds of its sound cut into a file of their own.
    NSString *clip = [NSTemporaryDirectory() stringByAppendingPathComponent:@"russian-shelf-selftest-line.m4a"];
    NSString *problem = nil;
    BOOL cut = RSCutClipNow([library moviePath:sample], 10, 12, clip, &problem);
    double length = RSMediaDuration(clip);
    Line(cut && length > 2 && length < 3, @"a line's sound can be cut from it, for Lines to Hear Again",
         cut ? [NSString stringWithFormat:@"%.1f seconds", length] : problem);
    [[NSFileManager defaultManager] removeItemAtPath:clip error:NULL];
}

int RSSelfTestRun(void)
{
    @autoreleasepool {
        printf("Shelf self-test on %s\n", [OSVersion() UTF8String]);
        RSTools *tools = [RSTools bundled];
        NSString *temporary = [NSTemporaryDirectory() stringByAppendingPathComponent:@"russian-shelf-selftest"];
        [[NSFileManager defaultManager] createDirectoryAtPath:temporary withIntermediateDirectories:YES attributes:nil error:NULL];
        NSDictionary *env = RSToolEnvironment(tools, temporary);
        TestCrypto();
        TestSubtitles();
        TestTools(tools, env);
        if (![tools missing]) TestCertificates(tools, env);
        TestStudyFolder();
        TestLibrary();
        [[NSFileManager defaultManager] removeItemAtPath:temporary error:NULL];
        printf("%d passed, %d failed\n", passed, failed);
    }
    return failed ? 1 : 0;
}
