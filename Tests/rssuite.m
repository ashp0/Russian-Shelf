// Russian Shelf's model, checked: the cryptography, the shelf format, the
// sealed file, subtitles of both kinds, the library's rules for new shelves,
// rotation and deletion, kept lines and their days, cutting a line's sound,
// the yt-dlp command lines, reports, and git: real
// pulls (with another git holding the lock) and real report pushes against a
// bare repository.
//
//   rssuite <Tests/Fixtures>
//
// Built for the shipping target like the app; on an Apple silicon Mac it
// runs under Rosetta. Signing in the tests uses two throwaway keys below and
// the 10.7-era SecSignTransform, never the real key.

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <sys/stat.h>
#import "RSCrypto.h"
#import "RSShelf.h"
#import "RSSubtitles.h"
#import "RSLibrary.h"
#import "RSDownloader.h"
#import "RSReport.h"
#import "RSSync.h"
#import "RSDate.h"
#import "RSLines.h"
#import "RSClip.h"

static int failures = 0, checks = 0;

#define CHECK(cond, ...) do { checks++; if (!(cond)) { failures++; \
    fprintf(stderr, "FAIL %s:%d: ", __FILE__, __LINE__); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } } while (0)

static BOOL Has(NSString *s, NSString *part)
{
    return s && [s rangeOfString:part].location != NSNotFound;
}

static NSString *Temp(NSString *name)
{
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"rssuite-%d", getpid()]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return [dir stringByAppendingPathComponent:name];
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

// ---- Test keys (throwaway: made for these tests, used nowhere else) --------

static const char *KeyAPrivate =
    "-----BEGIN EC PRIVATE KEY-----\n"
    "MHcCAQEEIGbk9I7O8dyxuo149WwYWIY9B1ByiOXawOSpVntqOXMloAoGCCqGSM49\n"
    "AwEHoUQDQgAEzhubex2CwB7M6jhxQ7gV5NZg7h5sTMmbDGZqUN5uF//iskG6wpay\n"
    "WPE8Fdyakh2SNf4KK62rVDAPVF2FhfWLqw==\n"
    "-----END EC PRIVATE KEY-----\n";
static const char *KeyAPublic =
    "3059301306072a8648ce3d020106082a8648ce3d03010703420004ce1b9b7b1d82c01ecc"
    "ea387143b815e4d660ee1e6c4cc99b0c666a50de6e17ffe2b241bac296b258f13c15dc9a"
    "921d9235fe0a2badab54300f545d8585f58bab";
static const char *KeyBPrivate =
    "-----BEGIN EC PRIVATE KEY-----\n"
    "MHcCAQEEIMzFYrLO/8LCjcsVLtxIjjtazqSxb2Y4qNuH8NtD3V8moAoGCCqGSM49\n"
    "AwEHoUQDQgAEKzaPd+ooMo3yHPfTG6KhrQouwxDwAzibALqDa3K9eAmm/crwBVJW\n"
    "VYyiOtrfQCHWzK1uLQX4wiPBamjgODVb8g==\n"
    "-----END EC PRIVATE KEY-----\n";
static const char *KeyBPublic =
    "3059301306072a8648ce3d020106082a8648ce3d030107034200042b368f77ea28328df2"
    "1cf7d31ba2a1ad0a2ec310f003389b00ba836b72bd7809a6fdcaf0055256558ca23adadf"
    "4021d6ccad6e2d05f8c223c16a68e038355bf2";
static NSData *TestAES(void) { return Hex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"); }
static NSData *TestIV(void) { return Hex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"); }

static NSData *Sign(NSData *message, const char *pem)
{
    SecExternalFormat format = kSecFormatOpenSSL;
    SecExternalItemType type = kSecItemTypePrivateKey;
    SecItemImportExportKeyParameters params;
    memset(&params, 0, sizeof params);
    params.version = SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION;
    CFArrayRef items = NULL;
    NSData *keyData = [NSData dataWithBytes:pem length:strlen(pem)];
    if (SecItemImport((CFDataRef)keyData, NULL, &format, &type, 0, &params, NULL, &items) != errSecSuccess || items == NULL)
        return nil;
    SecKeyRef key = (SecKeyRef)CFArrayGetValueAtIndex(items, 0);
    CFErrorRef error = NULL;
    SecTransformRef signer = SecSignTransformCreate(key, &error);
    int bits = 256;
    CFNumberRef length = CFNumberCreate(NULL, kCFNumberIntType, &bits);
    SecTransformSetAttribute(signer, kSecTransformInputAttributeName, (CFDataRef)message, NULL);
    SecTransformSetAttribute(signer, kSecDigestTypeAttribute, kSecDigestSHA2, NULL);
    SecTransformSetAttribute(signer, kSecDigestLengthAttribute, length, NULL);
    NSData *signature = (NSData *)SecTransformExecute(signer, &error);
    CFRelease(length);
    CFRelease(signer);
    CFRelease(items);
    return [signature autorelease];
}

static NSString *ListText(int videos, NSString *start)
{
    NSMutableString *s = [NSMutableString stringWithFormat:@"Russian Shelf 1\nstart: %@\n", start];
    for (int i = 0; i < videos; i++)
        [s appendFormat:@"video: %@ | Sergey Storyteller | Story number %d | with a bar\n",
         [NSString stringWithFormat:@"vid%08d", i], i + 1];
    return s;
}

// A sealed file made from any text at all, so the tests can seal what
// RSShelf itself would refuse to (13 videos, say).
static NSData *SealRaw(NSString *plain, NSData *aes, NSData *iv, const char *pem)
{
    NSData *ciphertext = RSAESCTR([plain dataUsingEncoding:NSUTF8StringEncoding], aes, iv);
    NSData *signature = Sign(RSSignedMessage(iv, ciphertext), pem);
    NSString *file = [NSString stringWithFormat:@"Russian Shelf sealed 1\niv: %@\ndata: %@\nsignature: %@\n",
                      [iv base64EncodedStringWithOptions:0], [ciphertext base64EncodedStringWithOptions:0],
                      [signature base64EncodedStringWithOptions:0]];
    return [file dataUsingEncoding:NSUTF8StringEncoding];
}

static NSData *Seal(int videos, NSString *start, NSString *sealed, const char *pem)
{
    NSString *text = ListText(videos, start);
    if (sealed) text = [text stringByAppendingFormat:@"sealed: %@\n", sealed];
    return SealRaw(text, TestAES(), TestIV(), pem);
}

static NSString *Field(NSData *file, NSString *key)
{
    NSString *s = [[[NSString alloc] initWithData:file encoding:NSUTF8StringEncoding] autorelease];
    for (NSString *line in [s componentsSeparatedByString:@"\n"])
        if ([line hasPrefix:[key stringByAppendingString:@": "]]) return [line substringFromIndex:[key length] + 2];
    return nil;
}

static NSData *Replace(NSData *file, NSString *key, NSString *value)
{
    NSString *s = [[[NSString alloc] initWithData:file encoding:NSUTF8StringEncoding] autorelease];
    s = [s stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"%@: %@", key, Field(file, key)]
                                     withString:[NSString stringWithFormat:@"%@: %@", key, value]];
    return [s dataUsingEncoding:NSUTF8StringEncoding];
}

// ---- Cryptography -----------------------------------------------------------

static void TestAESVector(void)
{
    // NIST SP 800-38A, F.5.5 CTR-AES256.Encrypt.
    NSData *key = Hex("603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4");
    NSData *iv = Hex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff");
    NSData *plain = Hex("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51"
                        "30c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710");
    NSData *cipher = Hex("601ec313775789a5b7a7f504bbf3d228f443e3ca4d62b59aca84e990cacaf5c5"
                         "2b0930daa23de94ce87017ba2d84988ddfc9c58db67aada613c2dd08457941a6");
    CHECK([RSAESCTR(plain, key, iv) isEqualToData:cipher], "AES-256-CTR matches NIST SP 800-38A F.5.5");
    CHECK([RSAESCTR(cipher, key, iv) isEqualToData:plain], "and decrypts back");
    NSData *odd = [plain subdataWithRange:NSMakeRange(0, 37)];
    CHECK([RSAESCTR(odd, key, iv) isEqualToData:[cipher subdataWithRange:NSMakeRange(0, 37)]], "a length that isn't whole blocks");
    CHECK(RSAESCTR(plain, [key subdataWithRange:NSMakeRange(0, 16)], iv) == nil, "a 128-bit key is refused");
    CHECK(RSAESCTR(plain, key, [iv subdataWithRange:NSMakeRange(0, 8)]) == nil, "a short IV is refused");
    NSData *other = RSAESCTR(cipher, TestAES(), iv);
    CHECK(other && ![other isEqualToData:plain], "the wrong key gives something else");
}

static void TestSignatures(void)
{
    NSData *message = [@"Russian Shelf sealed 1\nsomething" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *signature = Sign(message, KeyAPrivate);
    CHECK([signature length] > 60, "test key A signs (%lu bytes)", (unsigned long)[signature length]);
    NSString *problem = nil;
    CHECK(RSVerifySignature(message, signature, Hex(KeyAPublic), &problem), "a good signature passes (%s)", [problem UTF8String]);

    NSMutableData *tampered = [[message mutableCopy] autorelease];
    ((unsigned char *)[tampered mutableBytes])[25] ^= 1;
    CHECK(!RSVerifySignature(tampered, signature, Hex(KeyAPublic), &problem) && Has(problem, @"doesn’t match"),
          "a tampered message fails: %s", [problem UTF8String]);
    CHECK(!RSVerifySignature(message, signature, Hex(KeyBPublic), &problem) && Has(problem, @"doesn’t match"),
          "the wrong key fails: %s", [problem UTF8String]);
    NSMutableData *badSignature = [[signature mutableCopy] autorelease];
    ((unsigned char *)[badSignature mutableBytes])[[badSignature length] - 3] ^= 0x40;
    CHECK(!RSVerifySignature(message, badSignature, Hex(KeyAPublic), &problem), "a damaged signature fails");
    CHECK(!RSVerifySignature(message, [@"not DER at all, really" dataUsingEncoding:NSUTF8StringEncoding], Hex(KeyAPublic), &problem),
          "a signature that isn't DER fails");
    CHECK(!RSVerifySignature(message, signature, [@"junk" dataUsingEncoding:NSUTF8StringEncoding], &problem) &&
          Has(problem, @"couldn’t load"), "a broken public key says so: %s", [problem UTF8String]);

    // The point <-> SubjectPublicKeyInfo helper, used by shelfsign.
    NSData *info = Hex(KeyAPublic);
    CHECK([RSPublicKeyInfoFromPoint([info subdataWithRange:NSMakeRange(26, 65)]) isEqualToData:info], "SPKI from a point");
    CHECK(RSPublicKeyInfoFromPoint([info subdataWithRange:NSMakeRange(0, 65)]) == nil, "not a point");

    // The app's own public key loads (it's checked for real in TestRealKey).
    CHECK([RSAppPublicKey() length] == 91 && [RSAppAESKey() length] == 32, "the built-in keys are the right size");
}

// ---- The shelf --------------------------------------------------------------

static void TestShelfFormat(void)
{
    NSString *problem = nil;
    RSShelf *s = [RSShelf shelfWithText:ListText(3, @"2026-10-12") problem:&problem];
    CHECK(s && [[s videos] count] == 3 && [[s startText] isEqualToString:@"2026-10-12"] &&
          [s start] == RSDaysFromCivil(2026, 10, 12), "a three-video list reads (%s)", [problem UTF8String]);
    RSVideo *v = [[s videos] objectAtIndex:1];
    CHECK([[v identifier] isEqualToString:@"vid00000001"] && [[v channel] isEqualToString:@"Sergey Storyteller"] &&
          [[v title] isEqualToString:@"Story number 2 | with a bar"], "a title may contain ' | '");
    RSShelf *again = [RSShelf shelfWithText:[s text] problem:&problem];
    CHECK([[again text] isEqualToString:[s text]], "text round-trips");
    CHECK([RSShelf shelfWithText:ListText(12, @"2026-10-12") problem:&problem] != nil, "twelve is fine");
    CHECK([RSShelf shelfWithText:ListText(13, @"2026-10-12") problem:&problem] == nil && Has(problem, @"13 videos"),
          "thirteen is refused: %s", [problem UTF8String]);

    struct { NSString *text, *expect; } bad[] = {
        { @"", @"empty" },
        { @"Russian Shelf 2\nstart: 2026-10-12\n", @"should say" },
        { @"Russian Shelf 1\nvideo: JE4cI_Knzvc | S | T\n", @"no start" },
        { @"Russian Shelf 1\nstart: 2026-13-01\nvideo: JE4cI_Knzvc | S | T\n", @"start date" },
        { @"Russian Shelf 1\nstart: 2026-10-12\n", @"no videos" },
        { @"Russian Shelf 1\nstart: 2026-10-12\nvideo: JE4cI_Knzv | S | T\n", @"isn’t a YouTube video id" },
        { @"Russian Shelf 1\nstart: 2026-10-12\nvideo: --exec=rm | S | T\n", @"isn’t a YouTube video id" },
        { @"Russian Shelf 1\nstart: 2026-10-12\nvideo: JE4cI_Knzvc | S\n", @"id | channel | title" },
        { @"Russian Shelf 1\nstart: 2026-10-12\nvideo: JE4cI_Knzvc | S | T\nvideo: JE4cI_Knzvc | S | U\n", @"twice" },
        { @"Russian Shelf 1\nstart: 2026-10-12\nvideo: JE4cI_Knzvc |  | T\n", @"empty or too long" },
        { @"Russian Shelf 1\nstart: 2026-10-12\nurl: https://example.com\n", @"isn’t part of a shelf" },
        { @"Russian Shelf 1\nstart: 2026-10-12\nsealed: yesterday\nvideo: JE4cI_Knzvc | S | T\n", @"sealed time" },
    };
    for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
        RSShelf *shelf = [RSShelf shelfWithText:bad[i].text problem:&problem];
        CHECK(shelf == nil && Has(problem, bad[i].expect), "malformed list %zu: %s", i, [problem UTF8String]);
    }
    CHECK([RSShelf shelfWithText:@"# Claude's note\n\nRussian Shelf 1\r\nstart: 2026-10-12\r\nvideo: JE4cI_Knzvc | S | T\r\n"
                         problem:&problem] != nil, "comments, blank lines and CRLF are fine");

    RSShelf *a = [[RSShelf shelfWithText:ListText(1, @"2026-10-12") problem:&problem] shelfSealedAt:@"2026-10-11 20:00:00"];
    RSShelf *b = [a shelfSealedAt:@"2026-10-11 21:00:00"];
    RSShelf *c = [[RSShelf shelfWithText:ListText(1, @"2026-10-19") problem:&problem] shelfSealedAt:@"2026-10-11 19:00:00"];
    CHECK([b isNewerThan:a] && ![a isNewerThan:b] && [c isNewerThan:b] && ![a isNewerThan:a], "newer: later start, or sealed later");
}

static void TestSealed(void)
{
    NSString *problem = nil;
    RSShelf *shelf = [[RSShelf shelfWithText:ListText(2, @"2026-10-12") problem:&problem] shelfSealedAt:@"2026-10-11 20:15:07"];
    NSData *file = RSSealShelf(shelf, TestAES(), TestIV(), ^NSData *(NSData *message, NSString **why) {
        return Sign(message, KeyAPrivate);
    }, &problem);
    CHECK(file != nil, "seals (%s)", [problem UTF8String]);

    RSShelf *opened = RSOpenSealedShelf(file, TestAES(), Hex(KeyAPublic), &problem);
    CHECK(opened && [[opened text] isEqualToString:[shelf text]] && [[opened fingerprint] length] == 16,
          "a good sealed shelf opens: %s", [problem UTF8String]);
    NSString *data = Field(file, @"data");
    CHECK(!Has(data, @"Sergey") && !Has([[[NSString alloc] initWithData:file encoding:NSUTF8StringEncoding] autorelease], @"Story"),
          "nothing of the list shows in the file");

    // Tampering: a flipped bit in the ciphertext, a different IV, the
    // signature of another file, a key that isn't Claude's.
    NSMutableData *cipher = [[[[NSData alloc] initWithBase64EncodedString:data options:0] autorelease] mutableCopy];
    ((unsigned char *)[cipher mutableBytes])[5] ^= 0x01;
    NSData *tampered = Replace(file, @"data", [cipher base64EncodedStringWithOptions:0]);
    [cipher release];
    CHECK(RSOpenSealedShelf(tampered, TestAES(), Hex(KeyAPublic), &problem) == nil && Has(problem, @"doesn’t match"),
          "a tampered list is refused: %s", [problem UTF8String]);
    NSData *otherIV = Replace(file, @"iv", [Hex("00000000000000000000000000000001") base64EncodedStringWithOptions:0]);
    CHECK(RSOpenSealedShelf(otherIV, TestAES(), Hex(KeyAPublic), &problem) == nil && Has(problem, @"doesn’t match"),
          "a swapped IV is refused");
    NSData *otherFile = Seal(2, @"2026-10-19", @"2026-10-18 10:00:00", KeyAPrivate);
    NSData *borrowed = Replace(file, @"signature", Field(otherFile, @"signature"));
    CHECK(RSOpenSealedShelf(borrowed, TestAES(), Hex(KeyAPublic), &problem) == nil, "another file's signature is refused");
    NSData *wrongKey = Seal(2, @"2026-10-12", @"2026-10-11 20:15:07", KeyBPrivate);
    CHECK(RSOpenSealedShelf(wrongKey, TestAES(), Hex(KeyAPublic), &problem) == nil && Has(problem, @"doesn’t match"),
          "signed with the wrong key: refused: %s", [problem UTF8String]);
    CHECK(RSOpenSealedShelf(file, TestAES(), Hex(KeyBPublic), &problem) == nil, "checked against the wrong key: refused");

    // Signed by the right key, but more than twelve videos.
    NSData *thirteen = Seal(13, @"2026-10-12", @"2026-10-11 20:15:07", KeyAPrivate);
    CHECK(RSOpenSealedShelf(thirteen, TestAES(), Hex(KeyAPublic), &problem) == nil && Has(problem, @"13 videos"),
          "13 videos, properly signed: refused: %s", [problem UTF8String]);
    // Signed, but not decryptable with the app's key.
    NSData *otherAES = SealRaw([ListText(1, @"2026-10-12") stringByAppendingString:@"sealed: 2026-10-11 20:15:07\n"],
                               Hex("1111111111111111111111111111111111111111111111111111111111111111"), TestIV(), KeyAPrivate);
    CHECK(RSOpenSealedShelf(otherAES, TestAES(), Hex(KeyAPublic), &problem) == nil, "a different AES key: refused (%s)", [problem UTF8String]);
    // Signed and decryptable, but no sealed time.
    CHECK(RSOpenSealedShelf(Seal(1, @"2026-10-12", nil, KeyAPrivate), TestAES(), Hex(KeyAPublic), &problem) == nil &&
          Has(problem, @"sealed"), "no sealed time: refused");

    struct { const char *text; const char *expect; } malformed[] = {
        { "", "empty" },
        { "hello", "isn’t a sealed shelf" },
        { "Russian Shelf sealed 1\niv: AAAA\ndata: AAAA\n", "isn’t a sealed shelf" },
        { "Russian Shelf sealed 1\niv: AAAA\ndata: AAAA\nsignature: AAAA\n", "damaged" },
        { "Russian Shelf sealed 1\niv: !!!!\ndata: ????\nsignature: ....\n", "damaged" },
        { "Russian Shelf sealed 2\niv: AAAA\ndata: AAAA\nsignature: AAAA\n", "isn’t a sealed shelf" },
    };
    for (size_t i = 0; i < sizeof malformed / sizeof malformed[0]; i++) {
        NSData *d = [NSData dataWithBytes:malformed[i].text length:strlen(malformed[i].text)];
        CHECK(RSOpenSealedShelf(d, TestAES(), Hex(KeyAPublic), &problem) == nil &&
              Has(problem, [NSString stringWithUTF8String:malformed[i].expect]), "malformed file %zu: %s", i, [problem UTF8String]);
    }
    NSMutableData *huge = [NSMutableData dataWithLength:70 * 1024];
    CHECK(RSOpenSealedShelf(huge, TestAES(), Hex(KeyAPublic), &problem) == nil && Has(problem, @"too big"), "a huge file is refused");
}

// A shelf sealed by `shelfsign` with the real key in the MacBook's keychain,
// opened with the keys built into the app.
static void TestRealKey(NSString *fixtures)
{
    NSData *file = [NSData dataWithContentsOfFile:[fixtures stringByAppendingPathComponent:@"real.signed"]];
    NSString *problem = nil;
    RSShelf *shelf = RSOpenShelfFile(file, &problem);
    CHECK(shelf && [[[[shelf videos] objectAtIndex:0] identifier] isEqualToString:@"JE4cI_Knzvc"],
          "a shelf sealed with the real key opens with the app's keys: %s", [problem UTF8String]);
    NSMutableData *tampered = [[file mutableCopy] autorelease];
    ((unsigned char *)[tampered mutableBytes])[40] ^= 0x02;
    CHECK(RSOpenShelfFile(tampered, &problem) == nil, "and refuses it tampered");
    CHECK(RSOpenShelfFile(Seal(1, @"2026-10-12", @"2026-10-11 20:15:07", KeyAPrivate), &problem) == nil,
          "the app refuses a shelf signed with any other key: %s", [problem UTF8String]);
}

// ---- Subtitles --------------------------------------------------------------

static void TestSubtitles(NSString *fixtures)
{
    CHECK(fabs(RSParseVTTTime(@"00:01:02.345") - 62.345) < 1e-9 && fabs(RSParseVTTTime(@"01:02.5") - 62.5) < 1e-9 &&
          fabs(RSParseVTTTime(@"1:00:00.000") - 3600) < 1e-9 && RSParseVTTTime(@"c") < 0 && RSParseVTTTime(@"00:61.000") < 0 &&
          RSParseVTTTime(@"00:00:60.000") < 0, "VTT times");
    CHECK([RSSubtitles subtitlesWithVTT:@"1\n00:00:01.000 --> 00:00:02.000\nhi\n"] == nil, "SRT isn't VTT");

    // Made by a person: JE4cI_Knzvc's own Russian subtitles (first minute).
    RSSubtitles *made = [RSSubtitles subtitlesWithFile:[fixtures stringByAppendingPathComponent:@"JE4cI_Knzvc.ru.vtt"]];
    CHECK(made && ![made automatic] && [[made lines] count] >= 10, "human subtitles read (%lu lines)", (unsigned long)[[made lines] count]);
    RSLine *first = [[made lines] objectAtIndex:0];
    CHECK([[first text] isEqualToString:@"Привет.\nМеня зовут Сергей,"] && fabs([first start] - 0.16) < 1e-6 &&
          fabs([first end] - 3.309) < 1e-6, "a two-line cue stays two lines: %s", [[first text] UTF8String]);
    RSLine *second = [[made lines] objectAtIndex:1];
    CHECK([[second text] isEqualToString:@"и сегодня я расскажу вам историю."], "&nbsp; is a space: %s", [[second text] UTF8String]);

    // Lookups, on the human file. Lines: [0.16, 3.309) [3.309, 8.545) ... a
    // gap from 16.929 to 17.744.
    CHECK([made indexAtTime:0.1] == NSNotFound && [made indexAtTime:0.2] == 0 && [made indexAtTime:3.309] == 1, "the line at a time");
    NSUInteger gapLine = [made indexAtTime:16.0];
    CHECK(gapLine != NSNotFound && [made indexAtTime:17.2] == NSNotFound, "nothing in the gap");
    CHECK([made indexToRevealAtTime:17.2] == gapLine, "revealing just after a line ends shows that line");
    CHECK([made indexToRevealAtTime:0.05] == NSNotFound, "nothing to reveal before the first line");
    CHECK([made indexToReplayAtTime:6.0] == 1, "replay: the start of the line being spoken");
    CHECK([made indexToReplayAtTime:3.6] == 0, "replay just after a line began: the line before");
    CHECK([made indexToReplayAtTime:0.3] == 0, "replay in the first line: that line");
    CHECK([made indexToReplayAtTime:17.2] == gapLine, "replay in a gap: the last line spoken");
    CHECK([made indexToHighlightAtTime:17.2] == gapLine && [made indexToHighlightAtTime:0.0] == NSNotFound, "highlight");

    // Speech recognition, the same minute: a rolling window rebuilt into
    // sentences.
    RSSubtitles *autoSubs = [RSSubtitles subtitlesWithFile:[fixtures stringByAppendingPathComponent:@"JE4cI_Knzvc.ru-orig.vtt"]];
    CHECK(autoSubs && [autoSubs automatic], "automatic captions are recognised");
    NSArray *lines = [autoSubs lines];
    NSMutableArray *texts = [NSMutableArray array];
    for (RSLine *l in lines) [texts addObject:[l text]];
    CHECK([[texts objectAtIndex:0] isEqualToString:@"Привет."], "first sentence: %s", [[texts objectAtIndex:0] UTF8String]);
    CHECK([texts count] > 1 && [[texts objectAtIndex:1] isEqualToString:@"Меня зовут Сергей, и сегодня я расскажу вам историю."],
          "a sentence across two rolling lines is one line: %s", [[texts objectAtIndex:1] UTF8String]);
    CHECK([texts count] > 2 && [[texts objectAtIndex:2] isEqualToString:@"Эта история называется Василиса Микулишна."],
          "one-word fragments join their sentence: %s", [[texts objectAtIndex:2] UTF8String]);
    CHECK([texts count] > 3 && [[texts objectAtIndex:3] isEqualToString:@"Ну что, вы готовы?"], "%s", [[texts objectAtIndex:3] UTF8String]);
    RSLine *l1 = [lines objectAtIndex:1], *l2 = [lines objectAtIndex:2];
    CHECK(fabs([l1 start] - 1.16) < 1e-6, "a sentence starts at its first word's timestamp: %.3f", [l1 start]);
    CHECK(fabs([l2 start] - 8.719) < 1e-6 && [l1 end] <= [l2 start] + 1e-6, "and ends before the next begins: %.3f..%.3f", [l1 end], [l2 start]);
    NSUInteger total = 0;
    for (NSString *t in texts) {
        total++;
        CHECK([t length] <= 84 + 20, "no runaway line: %s", [t UTF8String]);
        if (total > 1) CHECK(![t isEqualToString:[texts objectAtIndex:total - 2]], "no line repeated: %s", [t UTF8String]);
    }
    NSString *joined = [texts componentsJoinedByString:@" "];
    CHECK([[joined componentsSeparatedByString:@"Микулишна"] count] == 2, "each word once, not three times");
    CHECK(!Has(joined, @"<") && !Has(joined, @"00:"), "no tags left");
    for (NSUInteger i = 1; i < [lines count]; i++)
        CHECK([(RSLine *)[lines objectAtIndex:i] start] >= [(RSLine *)[lines objectAtIndex:i - 1] start], "in order");

    // Rolling captions with no punctuation at all: long runs break at the
    // length limit, after a comma when there is one, and at pauses.
    NSMutableString *vtt = [NSMutableString stringWithString:@"WEBVTT\nKind: captions\nLanguage: ru\n\n"];
    NSString *prev = nil;
    double t = 0;
    for (int i = 0; i < 12; i++) {
        NSString *line = [NSString stringWithFormat:@"слово%d<00:00:%06.3f><c> ещё%d</c><00:00:%06.3f><c> одно%d</c>", i, t + 0.5, i, t + 1.0, i];
        NSString *plain = [NSString stringWithFormat:@"слово%d ещё%d одно%d", i, i, i];
        [vtt appendFormat:@"00:00:%06.3f --> 00:00:%06.3f align:start position:0%%\n%@\n%@\n\n", t, t + 1.5, prev ?: @" ", line];
        [vtt appendFormat:@"00:00:%06.3f --> 00:00:%06.3f align:start position:0%%\n%@\n \n\n", t + 1.5, t + 1.51, plain];
        prev = plain;
        t += (i == 5) ? 6.0 : 1.51;     // a long pause after the sixth
    }
    RSSubtitles *unpunctuated = [RSSubtitles subtitlesWithVTT:vtt];
    CHECK([unpunctuated automatic] && [[unpunctuated lines] count] >= 2, "unpunctuated captions read (%lu lines)",
          (unsigned long)[[unpunctuated lines] count]);
    BOOL brokeAtPause = NO;
    for (RSLine *l in [unpunctuated lines]) {
        CHECK([[l text] length] <= 84, "unpunctuated line within the limit: %lu", (unsigned long)[[l text] length]);
        if ([[l text] hasPrefix:@"слово6 "]) brokeAtPause = YES;
    }
    CHECK(brokeAtPause, "a long pause starts a new line");
}

// ---- The library: new shelves, rotation, deletion ------------------------

static void FakeDownload(RSLibrary *library, NSString *identifier, double duration)
{
    NSString *staging = [library stagingFolder:identifier];
    [[NSFileManager defaultManager] createDirectoryAtPath:staging withIntermediateDirectories:YES attributes:nil error:NULL];
    [@"not really a movie" writeToFile:[staging stringByAppendingPathComponent:@"video.mp4"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [@"WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nПривет.\n" writeToFile:[staging stringByAppendingPathComponent:@"subtitles.ru.vtt"]
                                                          atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [@"WEBVTT\n\n00:00:01.000 --> 00:00:02.000\n \nПривет<00:00:01.500><c> мир</c>\n" writeToFile:[staging stringByAppendingPathComponent:@"subtitles.ru-orig.vtt"]
                                                          atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [@"jpeg" writeToFile:[staging stringByAppendingPathComponent:@"thumbnail.jpg"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSString *problem = nil;
    CHECK([library installDownload:identifier duration:duration problem:&problem], "install %s (%s)", [identifier UTF8String], [problem UTF8String]);
}

static NSString *Id(int i) { return [NSString stringWithFormat:@"vid%08d", i]; }

static NSString *ShelfText(NSArray *ids, NSString *start, NSString *sealed)
{
    NSMutableString *s = [NSMutableString stringWithFormat:@"Russian Shelf 1\nstart: %@\nsealed: %@\n", start, sealed];
    for (NSString *identifier in ids) [s appendFormat:@"video: %@ | Sergey Storyteller | Story %@\n", identifier, identifier];
    return s;
}

static void TestLibrary(void)
{
    NSString *folder = Temp(@"library");
    [[NSFileManager defaultManager] removeItemAtPath:folder error:NULL];
    long oct12 = RSDaysFromCivil(2026, 10, 12), oct19 = RSDaysFromCivil(2026, 10, 19);
    RSLibrary *library = [[[RSLibrary alloc] initWithFolder:folder aesKey:TestAES() publicKey:Hex(KeyAPublic)] autorelease];
    CHECK([library current] == nil && [library nextIdentifier] == nil, "an empty library");

    NSArray *week1 = [NSArray arrayWithObjects:Id(1), Id(2), Id(3), nil];
    NSArray *week2 = [NSArray arrayWithObjects:Id(3), Id(4), Id(5), nil];       // Id(3) repeats: not finished
    NSData *a = SealRaw(ShelfText(week1, @"2026-10-12", @"2026-10-11 20:00:00"), TestAES(), TestIV(), KeyAPrivate);
    NSData *b = SealRaw(ShelfText(week2, @"2026-10-19", @"2026-10-18 20:00:00"), TestAES(), TestIV(), KeyAPrivate);

    // The first shelf is taken even before its day: there's nothing else.
    CHECK([library offerShelfFile:a today:oct12 - 1] == RSOfferTaken && [[[library current] startText] isEqualToString:@"2026-10-12"],
          "the first shelf is taken");
    CHECK([library offerShelfFile:a today:oct12] == RSOfferNothingNew, "the same file again: nothing new");
    CHECK([[library identifiersToDownload] isEqualToArray:week1], "its videos are wanted, in order");
    CHECK([[library nextIdentifier] isEqualToString:Id(1)], "the first is next");

    // A tampered shelf, one with the wrong key, too many videos, garbage:
    // each refused with a reason, this week's shelf kept.
    NSMutableData *tampered = [[b mutableCopy] autorelease];
    ((unsigned char *)[tampered mutableBytes])[60] ^= 0x04;
    NSData *thirteen = Seal(13, @"2026-10-19", @"2026-10-18 20:00:00", KeyAPrivate);
    NSData *wrongKey = SealRaw(ShelfText(week2, @"2026-10-19", @"2026-10-18 20:00:00"), TestAES(), TestIV(), KeyBPrivate);
    struct { NSData *file; NSString *why; } refused[] = {
        { tampered, @"signature" }, { wrongKey, @"signature" }, { thirteen, @"13 videos" },
        { [@"garbage" dataUsingEncoding:NSUTF8StringEncoding], @"isn’t a sealed shelf" },
    };
    for (size_t i = 0; i < 4; i++) {
        CHECK([library offerShelfFile:refused[i].file today:oct12] == RSOfferRefused && Has([library notice], refused[i].why) &&
              [[[library current] startText] isEqualToString:@"2026-10-12"] && [library pending] == nil,
              "refused %zu, last good shelf kept: %s", i, [[library notice] UTF8String]);
    }

    CHECK([library offerShelfFile:a today:oct12] == RSOfferNothingNew && [library notice] == nil,
          "the good file back in the study folder clears the warning");
    [library offerShelfFile:tampered today:oct12];

    // Downloads; then next week's shelf arrives early.
    FakeDownload(library, Id(1), 600);
    FakeDownload(library, Id(2), 300);
    CHECK(![library isCurrentComplete] && [[library removeLeftovers] count] == 0, "nothing removed while this week is incomplete");
    FakeDownload(library, Id(3), 400);
    CHECK([library isCurrentComplete], "this week is all here");
    CHECK([[[library infoFor:Id(1)] objectForKey:@"subtitles"] isEqualToString:@"made"], "the human subtitles were kept over the automatic");
    CHECK([[NSFileManager defaultManager] fileExistsAtPath:[library subtitlesPath:Id(1)]] &&
          [[NSFileManager defaultManager] fileExistsAtPath:[library thumbnailPath:Id(1)]] &&
          ![[NSFileManager defaultManager] fileExistsAtPath:[library stagingFolder:Id(1)]], "files in place, staging gone");

    CHECK([library offerShelfFile:b today:oct12 + 3] == RSOfferQueued && [library notice] == nil &&
          [[[library pending] startText] isEqualToString:@"2026-10-19"] && [[[library current] startText] isEqualToString:@"2026-10-12"],
          "next week's shelf waits for its day");
    CHECK(([[library identifiersToDownload] isEqualToArray:[NSArray arrayWithObjects:Id(4), Id(5), nil]]),
          "its new videos are downloaded ahead; the repeat isn't fetched again");
    CHECK([library offerShelfFile:a today:oct12 + 3] == RSOfferNothingNew, "this week's file again: nothing new");

    // Watching this week.
    CHECK(![library recordPosition:200 furthest:200 duration:600 for:Id(1)], "a third of the way: not finished");
    CHECK([library recordPosition:545 furthest:545 duration:600 for:Id(1)], "90%%: finished");
    CHECK(![library recordPosition:10 furthest:10 duration:600 for:Id(1)] && [[library watchFor:Id(1)] finished] &&
          [[library watchFor:Id(1)] furthest] == 545, "finished stays finished; furthest doesn't go back");
    [library recordPosition:100 furthest:100 duration:400 for:Id(3)];
    CHECK([[library nextIdentifier] isEqualToString:Id(2)], "the next unwatched");
    [library save];

    // Nothing changes before the 19th.
    RSShelf *replaced = nil;
    CHECK(![library advanceToDay:oct19 - 1 replaced:&replaced], "no rotation before its day");
    // An older shelf can't come back, even one that never was here.
    NSData *older = SealRaw(ShelfText(week1, @"2026-10-05", @"2026-10-04 20:00:00"), TestAES(), TestIV(), KeyAPrivate);
    CHECK([library offerShelfFile:older today:oct12 + 4] == RSOfferRefused && Has([library notice], @"older"),
          "an older shelf is refused: %s", [[library notice] UTF8String]);

    // A fresh start reads everything back.
    library = [[[RSLibrary alloc] initWithFolder:folder aesKey:TestAES() publicKey:Hex(KeyAPublic)] autorelease];
    CHECK([[[library current] startText] isEqualToString:@"2026-10-12"] && [[[library pending] startText] isEqualToString:@"2026-10-19"] &&
          [[library watchFor:Id(1)] finished] && Has([library notice], @"older"), "state survives a relaunch");
    // Shelves are checked again when read back: one edited in place is dropped.
    RSLibrary *wrong = [[[RSLibrary alloc] initWithFolder:folder aesKey:TestAES() publicKey:Hex(KeyBPublic)] autorelease];
    CHECK([wrong current] == nil && [wrong pending] == nil, "stored shelves are re-checked at launch");

    // The 19th.
    CHECK([library advanceToDay:oct19 replaced:&replaced] && [[replaced startText] isEqualToString:@"2026-10-12"] &&
          [[[library current] startText] isEqualToString:@"2026-10-19"] && [library pending] == nil, "rotation on its day");
    CHECK(![[NSFileManager defaultManager] fileExistsAtPath:[folder stringByAppendingPathComponent:@"Next Shelf.signed"]],
          "the next-shelf file is gone");
    CHECK([[library removeLeftovers] count] == 0 && [library isDownloaded:Id(1)], "old files stay until this week is all here");
    FakeDownload(library, Id(4), 500);
    [[NSFileManager defaultManager] createDirectoryAtPath:[library stagingFolder:Id(2)] withIntermediateDirectories:YES attributes:nil error:NULL];
    FakeDownload(library, Id(5), 500);
    NSArray *removed = [library removeLeftovers];
    CHECK(([[NSSet setWithArray:removed] isEqualToSet:[NSSet setWithObjects:Id(1), Id(2), nil]]),
          "last week's files are deleted once this week's are all here (%s)", [[removed description] UTF8String]);
    CHECK([library isDownloaded:Id(3)] && [library isDownloaded:Id(4)] && ![library isDownloaded:Id(1)] &&
          ![[NSFileManager defaultManager] fileExistsAtPath:[library stagingFolder:Id(2)]], "the repeat stays; stray downloads go");
    CHECK([[library watchFor:Id(3)] furthest] == 100 && ![[library watchFor:Id(1)] finished] && [[library watchFor:Id(1)] furthest] == 0,
          "the repeat keeps its place; last week's watching is forgotten");
    CHECK([[library nextIdentifier] isEqualToString:Id(3)], "the repeat is next");

    // A same-day correction (sealed later) replaces this week's shelf.
    NSData *fix = SealRaw(ShelfText([NSArray arrayWithObjects:Id(3), Id(4), nil], @"2026-10-19", @"2026-10-19 08:00:00"),
                          TestAES(), TestIV(), KeyAPrivate);
    CHECK([library offerShelfFile:fix today:oct19] == RSOfferTaken && [[[library current] videos] count] == 2, "a correction is taken");
    CHECK([library offerShelfFile:b today:oct19] == RSOfferRefused, "and the uncorrected one can't come back");
}

// ---- yt-dlp ------------------------------------------------------------------

static NSUInteger IndexOf(NSArray *a, NSString *s) { return [a indexOfObject:s]; }

static NSString *After(NSArray *a, NSString *option)
{
    NSUInteger i = [a indexOfObject:option];
    return i != NSNotFound && i + 1 < [a count] ? [a objectAtIndex:i + 1] : nil;
}

static void TestCommandLines(void)
{
    RSTools *tools = [RSTools toolsInFolder:@"/App/Contents/Resources"];
    NSArray *a = RSDownloadArguments(tools, @"/Support/yt-dlp", @"JE4cI_Knzvc", @"/Support/Downloads/JE4cI_Knzvc", @"/Support/Cache");
    NSString *all = [a componentsJoinedByString:@" "];
    CHECK(([[a objectAtIndex:0] isEqualToString:@"/App/Contents/Resources/python3/bin/python3.14"] &&
          [[a subarrayWithRange:NSMakeRange(1, 5)] isEqualToArray:[NSArray arrayWithObjects:@"-I", @"-B", @"-X", @"utf8", @"/Support/yt-dlp", nil]]),
          "bundled Python, isolated, running the updatable copy");
    CHECK([[a lastObject] isEqualToString:@"https://www.youtube.com/watch?v=JE4cI_Knzvc"] &&
          [[a objectAtIndex:[a count] - 2] isEqualToString:@"--"], "the watch URL, last, after --");
    NSUInteger urls = 0;
    for (NSString *arg in a) if (Has(arg, @"youtube.com")) urls++;
    CHECK(urls == 1, "exactly one URL");
    CHECK(!Has(all, @"no-check-certificate") && !Has(all, @"nocheckcertificate"), "certificates are always checked");
    CHECK(IndexOf(a, @"--ignore-config") != NSNotFound && IndexOf(a, @"--no-plugin-dirs") != NSNotFound &&
          IndexOf(a, @"--no-playlist") != NSNotFound && [After(a, @"--match-filters") isEqualToString:@"id=JE4cI_Knzvc"],
          "no config, plugins or playlists; only this id");
    CHECK(IndexOf(a, @"--batch-file") == NSNotFound && IndexOf(a, @"--exec") == NSNotFound, "nothing else runs");
    CHECK(Has(After(a, @"--format"), @"[height<=1080]") && !Has(After(a, @"--format"), @"bestaudio/best[height<=1080]/bestaudio"),
          "at most 1080p, never sound alone");
    CHECK([After(a, @"--format-sort") hasPrefix:@"+hdr,res,fps,vcodec:h264,"] && Has(After(a, @"--format-sort"), @"acodec:aac"),
          "the prefpane's format sort");
    CHECK([After(a, @"--merge-output-format") isEqualToString:@"mp4"], "MP4");
    CHECK([After(a, @"--postprocessor-args") isEqualToString:@"Merger+ffmpeg_o1:-bsf:v h264_metadata=level=auto"], "the H.264 level fix");
    CHECK([After(a, @"--ffmpeg-location") isEqualToString:@"/App/Contents/Resources/ffmpeg"], "bundled ffmpeg");
    CHECK([After(a, @"--js-runtimes") isEqualToString:@"quickjs:/App/Contents/Resources/qjs"] && !Has(all, @"deno"),
          "bundled QuickJS as the JavaScript runtime");
    CHECK(IndexOf(a, @"--write-subs") != NSNotFound && IndexOf(a, @"--write-auto-subs") != NSNotFound &&
          [After(a, @"--sub-langs") isEqualToString:@"ru,ru-orig"] && [After(a, @"--sub-format") isEqualToString:@"vtt"] &&
          IndexOf(a, @"--embed-subs") == NSNotFound, "Russian subtitles, made or automatic, as a sidecar file");
    CHECK(IndexOf(a, @"--write-thumbnail") != NSNotFound && [After(a, @"--convert-thumbnails") isEqualToString:@"jpg"], "a JPEG thumbnail");
    CHECK([After(a, @"--retry-sleep") isEqualToString:@"30"] && [After(a, @"--sleep-subtitles") isEqualToString:@"8"] &&
          [After(a, @"--sleep-requests") isEqualToString:@"1.5"] && [After(a, @"--sleep-interval") isEqualToString:@"15"] &&
          [After(a, @"--max-sleep-interval") isEqualToString:@"40"], "the prefpane's rate limits and retries");
    CHECK([After(a, @"--paths") isEqualToString:@"/Support/Downloads/JE4cI_Knzvc"] && [After(a, @"--cache-dir") isEqualToString:@"/Support/Cache"] &&
          [After(a, @"--output") isEqualToString:@"video.%(ext)s"] && Has(all, @"subtitle:subtitles.%(ext)s") &&
          !Has(all, @"Movies"), "everything inside Application Support");

    CHECK(RSDownloadArguments(tools, @"/y", @"JE4cI_Knzv", @"/s", @"/c") == nil, "a short id: nothing");
    CHECK(RSDownloadArguments(tools, @"/y", @"--exec=rm -", @"/s", @"/c") == nil, "an option as an id: nothing");
    CHECK(RSDownloadArguments(tools, @"/y", @"https://x.y", @"/s", @"/c") == nil, "a URL as an id: nothing");
    CHECK(RSWatchURL(@"a-b_c1234567") == nil && [RSWatchURL(@"a-b_c123456") isEqualToString:@"https://www.youtube.com/watch?v=a-b_c123456"],
          "ids: eleven of A-Z a-z 0-9 - _");

    NSArray *u = RSUpdateArguments(tools, @"/Support/yt-dlp");
    CHECK([[u lastObject] isEqualToString:@"--update"] && [u containsObject:@"/Support/yt-dlp"] &&
          !Has([u componentsJoinedByString:@" "], @"check-certificate"), "the self-update checks certificates");
    NSDictionary *env = RSToolEnvironment(tools, @"/Support/Temporary");
    CHECK([[env objectForKey:@"SSL_CERT_FILE"] isEqualToString:@"/App/Contents/Resources/python3/lib/python3.14/site-packages/certifi/cacert.pem"],
          "certifi's list, for OpenSSL");
    CHECK([env objectForKey:@"PYTHONPATH"] == nil && [[env objectForKey:@"TMPDIR"] isEqualToString:@"/Support/Temporary"], "a clean environment");

    double f = -1;
    CHECK(RSParseProgress(@"RSP downloading 500 1000 NA avc1.640028", &f) && fabs(f - 0.425) < 1e-9, "video half done: %.3f", f);
    CHECK(RSParseProgress(@"RSP downloading 50 NA 100 none", &f) && fabs(f - 0.925) < 1e-9, "sound half done, by the estimate: %.3f", f);
    CHECK(RSParseProgress(@"RSP finished 100 100 NA none", &f) && fabs(f - 1) < 1e-9, "all done");
    CHECK(!RSParseProgress(@"[download] 50% of 10MiB", &f), "not ours");
    CHECK(RSParseDone(@"RSDONE 1160") == 1160 && RSParseDone(@"RSDONE NA") == 0 && RSParseDone(@"other") < 0, "the length when done");

    CHECK(Has(RSDownloadProblem(@"[youtube] x\nERROR: [youtube] JE4cI_Knzvc: Sign in to confirm you’re not a bot.\n", 1), @"robot"), "bot check");
    CHECK(Has(RSDownloadProblem(@"ERROR: unable to download video data: HTTP Error 429: Too Many Requests\n", 1), @"pause"), "rate limited");
    CHECK(Has(RSDownloadProblem(@"ERROR: [youtube] abc: Video unavailable\n", 1), @"isn’t available"), "unavailable");
    CHECK(Has(RSDownloadProblem(@"ERROR: [SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed\n", 1), @"secure connection"), "TLS");
    CHECK([RSDownloadProblem(@"ERROR: [youtube] JE4cI_Knzvc: Something odd\n", 1) isEqualToString:@"yt-dlp said: Something odd"],
          "otherwise yt-dlp's own words: %s", [RSDownloadProblem(@"ERROR: [youtube] JE4cI_Knzvc: Something odd\n", 1) UTF8String]);
}

// ---- Reports ----------------------------------------------------------------

static void TestReports(void)
{
    NSString *folder = Temp(@"report-library");
    [[NSFileManager defaultManager] removeItemAtPath:folder error:NULL];
    RSLibrary *library = [[[RSLibrary alloc] initWithFolder:folder aesKey:TestAES() publicKey:Hex(KeyAPublic)] autorelease];
    NSArray *ids = [NSArray arrayWithObjects:Id(1), Id(2), Id(3), Id(4), nil];
    [library offerShelfFile:SealRaw(ShelfText(ids, @"2026-10-12", @"2026-10-11 20:00:00"), TestAES(), TestIV(), KeyAPrivate) today:0];
    FakeDownload(library, Id(1), 690);
    FakeDownload(library, Id(2), 690);
    FakeDownload(library, Id(3), 552);
    [library recordPosition:680 furthest:680 duration:690 for:Id(1)];
    [library recordPosition:250 furthest:250 duration:690 for:Id(2)];

    struct tm tm = { 0 };
    tm.tm_year = 2026 - 1900; tm.tm_mon = 9; tm.tm_mday = 14; tm.tm_hour = 21; tm.tm_min = 5; tm.tm_isdst = -1;
    time_t when = mktime(&tm);
    NSString *name = RSReportName([library current], when);
    CHECK([name isEqualToString:@"shelf-2026-10-12_2026-10-14-2105.txt"], "report name: %s", [name UTF8String]);
    CHECK([RSSync isReportPath:[@"Russian/Reports/" stringByAppendingString:name]], "and it's a report path");
    RSLines *none = [[[RSLines alloc] initWithFolder:Temp(@"report-lines-none")] autorelease];
    NSString *text = RSReportText([library current], library, none, when);
    CHECK(Has(text, @"shelf: 2026-10-12 (sealed 2026-10-11 20:00:00)") && Has(text, @"written: 2026-10-14 21:05"), "report header");
    CHECK(Has(text, [Id(1) stringByAppendingString:@" | finished | 11:30 of 11:30 | Story"]), "finished line:\n%s", [text UTF8String]);
    CHECK(Has(text, [Id(2) stringByAppendingString:@" | partly | 4:10 of 11:30 | Story"]), "partly line");
    CHECK(Has(text, [Id(3) stringByAppendingString:@" | not started | 0:00 of 9:12 | Story"]), "not started line");
    CHECK(Has(text, [Id(4) stringByAppendingString:@" | not downloaded | - | Story"]), "not downloaded line");
    NSString *from = [NSString stringWithFormat:@"written: 2026-10-14 21:05\nfrom: %@\n\n", RSComputerName()];
    CHECK(Has(text, from) &&
          ![RSComputerName() hasSuffix:@".local"] && [RSComputerName() length] > 0, "which Mac wrote it: %s", [RSComputerName() UTF8String]);
    CHECK(!Has(text, @"Help (") && !Has(text, @"Kept:"), "no help asked, nothing kept: no sections");

    // Lines shown, heard again and kept, and the kept lines themselves.
    [library countHelp:RSHelpShown for:Id(2) line:@"Она отрезала\nволосы." start:250.4];
    [library countHelp:RSHelpShown for:Id(2)];
    [library countHelp:RSHelpHeardAgain for:Id(2) line:@"Она отрезала\nволосы." start:250.4];
    [library countHelp:RSHelpLooped for:Id(2) line:@"Потом она ушла." start:12];
    [library countHelp:RSHelpSlowed for:Id(2) line:@"Потом она ушла." start:12];
    [library countHelp:RSHelpTranscript for:Id(2) line:nil start:0];
    [library countHelp:RSHelpSubtitles for:Id(2) line:@"Потом она ушла." start:12];
    [library countHelp:RSHelpKept for:Id(2)];
    [library countHelp:RSHelpKinds for:Id(2) line:@"x" start:1];         // not a kind: ignored
    [library countHelp:RSHelpShown for:@"notonshelf1"];
    RSLines *lines = [[[RSLines alloc] initWithFolder:Temp(@"report-lines")] autorelease];
    RSKeptLine *withMeaning = [lines keepText:@"Она отрезала\nволосы." before:nil video:Id(2) title:@"Story" start:250.4 end:252 today:100 problem:NULL];
    [withMeaning setMeaning:@"She cut\nher hair."];
    [lines keepText:@"Elsewhere." before:nil video:@"notonshelf1" title:@"Other" start:5 end:6 today:100 problem:NULL];
    text = RSReportText([library current], library, lines, when);
    NSString *helpLine = [NSString stringWithFormat:@"\nHelp (shown, heard again, looped, slowed, transcript, subtitles, kept):\n"
                          "%@ | shown 2 | heard again 1 | looped 1 | slowed 1 | transcript 1 | subtitles 1 | kept 1\n", Id(2)];
    CHECK(Has(text, helpLine), "help section:\n%s", [text UTF8String]);
    NSString *askedLines = [NSString stringWithFormat:@"\nLines help was asked on:\n%@ | 0:12 | looped 1, slowed 1, subtitles 1 | Потом она ушла.\n"
                            "%@ | 4:10 | shown 1, heard again 1 | Она отрезала / волосы.\n", Id(2), Id(2)];
    CHECK(Has(text, askedLines), "the lines, by time, with what was asked on each");
    CHECK(!Has(text, @"How it felt"), "nothing chosen: no feelings section");
    CHECK(!Has(text, [Id(1) stringByAppendingString:@" | shown"]) && !Has(text, @"notonshelf1"), "only this shelf's videos, only those helped");
    NSString *keptLine = [NSString stringWithFormat:@"\nKept:\n%@ | 4:10 | Она отрезала / волосы. | means: She cut / her hair.\n", Id(2)];
    CHECK(Has(text, keptLine) && !Has(text, @"Elsewhere"), "kept section, on one line each");
    CHECK(Has(text, [Id(2) stringByAppendingString:@" | partly | 4:10 of 11:30 | Story"]) && [text rangeOfString:@"\nHelp ("].location > [text rangeOfString:Id(4)].location, "the video lines are as before, then help");
    // Help counts survive more watching, and a reload.
    [library recordPosition:300 furthest:300 duration:690 for:Id(2)];
    [library save];
    RSLibrary *again = [[[RSLibrary alloc] initWithFolder:folder aesKey:TestAES() publicKey:Hex(KeyAPublic)] autorelease];
    CHECK([again help:RSHelpShown for:Id(2)] == 2 && [again help:RSHelpHeardAgain for:Id(2)] == 1 &&
          [again help:RSHelpKept for:Id(2)] == 1 && [again help:RSHelpShown for:Id(3)] == 0 && [[again watchFor:Id(2)] furthest] == 300,
          "help counts kept with the watching, and saved");
    NSArray *helped = [again helpedLinesFor:Id(2)];
    CHECK([helped count] == 2 && [[[helped objectAtIndex:1] objectForKey:@"heard again"] intValue] == 1 &&
          [[[helped objectAtIndex:0] objectForKey:@"looped"] intValue] == 1 && [[helped objectAtIndex:0] objectForKey:@"shown"] == nil,
          "the lines, saved");

    // How it felt: one word each, about the video; only the known words.
    CHECK([again feltFor:Id(1)] == nil && [again wantFor:Id(1)] == nil, "nothing chosen yet");
    [again setFelt:RSFeltAboutRight want:nil for:Id(1)];
    [again setFelt:RSFeltTooHard want:RSWantMore for:Id(3)];
    [again setFelt:@"5 stars" want:@"great" for:Id(4)];
    CHECK([[again feltFor:Id(1)] isEqualToString:@"about right"] && [again wantFor:Id(1)] == nil &&
          [again feltFor:Id(4)] == nil && [again wantFor:Id(4)] == nil, "chosen, and anything else refused");
    [again recordPosition:400 furthest:400 duration:690 for:Id(3)];
    [again save];
    RSLibrary *third = [[[RSLibrary alloc] initWithFolder:folder aesKey:TestAES() publicKey:Hex(KeyAPublic)] autorelease];
    CHECK([[third feltFor:Id(3)] isEqualToString:@"too hard"] && [[third wantFor:Id(3)] isEqualToString:@"more like this"],
          "kept through watching and a reload");
    text = RSReportText([third current], third, lines, when);
    NSString *feltLines = [NSString stringWithFormat:@"\nHow it felt (the owner's own choice, about the video):\n%@ | about right | -\n"
                           "%@ | too hard | more like this\n", Id(1), Id(3)];
    CHECK(Has(text, feltLines), "how it felt, in the report:\n%s", [text UTF8String]);
    [third setFelt:nil want:nil for:Id(1)];
    CHECK([third feltFor:Id(1)] == nil, "cleared");

    // At most forty lines a video in the report.
    for (int i = 0; i < 45; i++) [third countHelp:RSHelpShown for:Id(1) line:[NSString stringWithFormat:@"Line %d", i] start:i];
    text = RSReportText([third current], third, lines, when);
    CHECK(Has(text, [Id(1) stringByAppendingString:@" | 0:39 | shown 1 | Line 39\n"]) && !Has(text, @"| Line 40\n") &&
          Has(text, [Id(1) stringByAppendingString:@" | … and 5 more lines\n"]), "forty, then how many more");
    CHECK([RSClock(3725) isEqualToString:@"1:02:05"] && [RSClock(59.6) isEqualToString:@"1:00"] && [RSClock(-3) isEqualToString:@"0:00"], "clock");

    NSArray *bad = [NSArray arrayWithObjects:@"Russian/Reports/../shelf.signed", @"Inbox/note.txt", @"Russian/Reports/a/b.txt",
                    @"Russian/shelf.signed", @"Russian/Reports/.hidden.txt", @"Russian/Reports/x.sh", @"Russian/Reports/", nil];
    for (NSString *p in bad) CHECK(![RSSync isReportPath:p], "not a report path: %s", [p UTF8String]);
}

// ---- Kept lines ------------------------------------------------------------

static void TestLines(void)
{
    NSString *folder = Temp(@"lines");
    [[NSFileManager defaultManager] removeItemAtPath:folder error:NULL];
    RSLines *lines = [[[RSLines alloc] initWithFolder:folder] autorelease];
    long day = RSDaysFromCivil(2026, 10, 27);
    CHECK([[lines lines] count] == 0 && [[lines dueOn:day] count] == 0, "no lines yet");
    CHECK(RSLineGap(0) == 1 && RSLineGap(1) == 3 && RSLineGap(2) == 7 && RSLineGap(3) == 16 && RSLineGap(4) == 35 &&
          RSLineGap(5) == 75 && RSLineGap(6) == 0, "the gaps: 1, 3, 7, 16, 35, 75 days, then put away");

    NSString *problem = nil;
    RSKeptLine *a = [lines keepText:@"Привет, друзья!" before:@"Сегодня" video:@"JE4cI_Knzvc" title:@"She Cut Her Hair"
                              start:12.345 end:14.5 today:day problem:&problem];
    CHECK(a && [a due] == day + 1 && [a kept] == day && [a step] == 0 && ![a putAway], "kept, back tomorrow");
    CHECK([[a key] isEqualToString:@"JE4cI_Knzvc-0000012345"], "its key: %s", [[a key] UTF8String]);
    CHECK([[lines soundPath:a] isEqualToString:[folder stringByAppendingPathComponent:@"JE4cI_Knzvc-0000012345.m4a"]], "its sound's file");
    CHECK([lines isKept:@"JE4cI_Knzvc" start:12.345] && ![lines isKept:@"JE4cI_Knzvc" start:13], "is it kept");
    CHECK([lines keepText:@"Привет, друзья!" before:nil video:@"JE4cI_Knzvc" title:@"x" start:12.345 end:14.5 today:day problem:&problem] == nil &&
          Has(problem, @"kept already"), "the same line twice: %s", [problem UTF8String]);
    CHECK([lines keepText:@"" before:nil video:@"JE4cI_Knzvc" title:@"x" start:20 end:21 today:day problem:&problem] == nil &&
          Has(problem, @"no line"), "an empty line");
    CHECK([[lines dueOn:day] count] == 0, "nothing due the day it's kept");

    // Fifteen a day.
    CHECK(RSKeepPerDay == 15 && RSHearPerDay == 60 && RSWaitingBrake == 45, "the limits: 15 kept, 60 heard, 45 waiting");
    for (int i = 1; i < (int)RSKeepPerDay; i++)
    {
        NSString *text = [NSString stringWithFormat:@"Line %d", i];
        CHECK([lines keepText:text before:nil video:@"JE4cI_Knzvc" title:@"t" start:100 + i end:101 + i today:day problem:NULL] != nil,
              "line %d kept", i);
    }
    CHECK([lines keptOn:day] == RSKeepPerDay, "fifteen today");
    CHECK([lines keepText:@"Sixteen" before:nil video:@"JE4cI_Knzvc" title:@"t" start:200 end:201 today:day problem:&problem] == nil &&
          Has(problem, @"15 lines kept today"), "the sixteenth waits for tomorrow: %s", [problem UTF8String]);
    RSKeptLine *b = [lines keepText:@"Tomorrow's" before:nil video:@"abcdefghijk" title:@"t" start:200 end:201 today:day + 1 problem:NULL];
    CHECK(b != nil, "and tomorrow it's kept");

    NSArray *due = [lines dueOn:day + 1];
    CHECK([due count] == RSKeepPerDay && [due objectAtIndex:0] == a, "the next day, the fifteen are due, in the order kept");
    CHECK([lines waitingOn:day + 1] == RSKeepPerDay && [lines waitingOn:day] == 0, "waiting");

    // "Knew it" every time: 3, 7, 16, 35, 75 days, then put away.
    long d = day + 1;
    long expect[] = { 3, 7, 16, 35, 75 };
    for (int i = 0; i < 5; i++) {
        [lines answer:a knew:YES today:d];
        CHECK([a due] == d + expect[i] && [a step] == (NSUInteger)i + 1 && ![a putAway], "knew it %d: back in %ld days", i + 1, expect[i]);
        d = [a due];
    }
    [lines answer:a knew:YES today:d];
    CHECK([a putAway], "known: put away");
    CHECK(![[lines dueOn:d + 1000] containsObject:a], "and never due again");

    // "Not yet": the next day, from the start; put away after six.
    RSKeptLine *c = [due objectAtIndex:1];
    [lines answer:c knew:YES today:day + 1];
    [lines answer:c knew:NO today:day + 4];
    CHECK([c step] == 0 && [c lapses] == 1 && [c due] == day + 5, "not yet: tomorrow, from the start");
    for (int i = 2; i <= 6; i++) [lines answer:c knew:NO today:day + 4 + i];
    CHECK([c lapses] == 6 && [c putAway], "six times not yet: put away");
    RSKeptLine *e = [due objectAtIndex:2];
    [lines putAway:e];
    CHECK([e putAway] && ![[lines dueOn:day + 30] containsObject:e], "put away by hand");
    CHECK([[lines linesFromVideo:@"abcdefghijk"] count] == 1 && [[lines linesFromVideo:@"JE4cI_Knzvc"] count] == RSKeepPerDay, "lines by video");

    // Not yet today: heard once more today, also after the window is closed.
    RSKeptLine *f = [due objectAtIndex:3], *g = [due objectAtIndex:4];
    [lines answer:f knew:NO today:day + 1];
    [lines answer:g knew:YES today:day + 1];
    NSArray *notYet = [lines notYetOn:day + 1];
    CHECK([notYet containsObject:f] && ![notYet containsObject:g] && ![notYet containsObject:a] && [f heard] == day + 1 && ![f knewLast],
          "today's not-yets: %lu", (unsigned long)[notYet count]);
    CHECK([[lines notYetOn:day + 2] count] == 0 || ![[lines notYetOn:day + 2] containsObject:f], "only today's");

    // Saved and read back, the same.
    CHECK([lines save], "saved");
    RSLines *read = [[[RSLines alloc] initWithFolder:folder] autorelease];
    CHECK([[read lines] count] == RSKeepPerDay + 1, "read back: %lu", (unsigned long)[[read lines] count]);
    RSKeptLine *a2 = [[read lines] objectAtIndex:0], *c2 = [[read lines] objectAtIndex:1];
    CHECK([[a2 text] isEqualToString:@"Привет, друзья!"] && [[a2 before] isEqualToString:@"Сегодня"] && [[a2 title] isEqualToString:@"She Cut Her Hair"] &&
          fabs([a2 start] - 12.345) < 1e-9 && [a2 end] == 14.5 && [a2 putAway] && [a2 step] == 6 && [a2 kept] == day,
          "a line read back");
    CHECK([c2 lapses] == 6 && [c2 putAway] && [[[read lines] objectAtIndex:3] before] == nil, "another, and no context is nil");
    RSKeptLine *f2 = [[read lines] objectAtIndex:3];
    CHECK([f2 heard] == day + 1 && ![f2 knewLast] && [[read notYetOn:day + 1] count] == 1, "the last answer read back");

    // Sixty a day, then the rest the next day; and no keeping while 45 wait.
    NSString *many = Temp(@"lines-many");
    [[NSFileManager defaultManager] removeItemAtPath:many error:NULL];
    [[NSFileManager defaultManager] createDirectoryAtPath:many withIntermediateDirectories:YES attributes:nil error:NULL];
    NSMutableArray *seventy = [NSMutableArray array];
    for (int i = 0; i < 70; i++)
        [seventy addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"vid-%03d", i], @"key", @"vid", @"video",
            [NSString stringWithFormat:@"L%d", i], @"text", [NSNumber numberWithLong:day - 2], @"kept",
            [NSNumber numberWithLong:day - 1 - (i < 5 ? 1 : 0)], @"due", nil]];
    [[NSDictionary dictionaryWithObject:seventy forKey:@"lines"] writeToFile:[many stringByAppendingPathComponent:@"Lines.plist"] atomically:YES];
    RSLines *m = [[[RSLines alloc] initWithFolder:many] autorelease];
    NSArray *today = [m dueOn:day];
    CHECK([today count] == 60 && [[[today objectAtIndex:0] text] isEqualToString:@"L0"], "sixty at most: %lu", (unsigned long)[today count]);
    CHECK([m waitingOn:day] == 70, "seventy waiting");
    CHECK([m keepText:@"More" before:nil video:@"vid" title:@"t" start:500 end:501 today:day problem:&problem] == nil &&
          Has(problem, @"70 lines are waiting"), "no keeping while 45 or more wait: %s", [problem UTF8String]);
    for (int i = 0; i < 30; i++) [m answer:[today objectAtIndex:i] knew:YES today:day];
    [m save];
    RSLines *m2 = [[[RSLines alloc] initWithFolder:many] autorelease];
    CHECK([[m2 dueOn:day] count] == 30, "after thirty heard, thirty more today (also after a reload): %lu", (unsigned long)[[m2 dueOn:day] count]);
    CHECK([[m2 dueOn:day + 1] count] == 40, "the next day the rest are due: %lu", (unsigned long)[[m2 dueOn:day + 1] count]);
    CHECK([m2 keepText:@"More" before:nil video:@"vid" title:@"t" start:500 end:501 today:day problem:&problem] != nil,
          "with 40 waiting, keeping works again: %s", [problem UTF8String]);

    // Your words: then the line comes up both ways, turn about.
    RSKeptLine *w = [m2 keepText:@"Мне кажется, что он прав." before:nil video:@"vid" title:@"t" start:600 end:602 today:day problem:NULL];
    CHECK(![m2 asksToSay:w], "no meaning: always listen");
    [w setStep:1];
    CHECK(![m2 asksToSay:w], "no meaning, even later");
    [w setMeaning:@"   "];
    CHECK(![m2 asksToSay:w], "a blank meaning is none");
    [w setMeaning:@"I think he's right."];
    [w setStep:0];
    CHECK(![m2 asksToSay:w], "the first time: listen");
    BOOL turns[] = { NO, YES, NO, YES, NO, YES };
    BOOL alternates = YES;
    for (NSUInteger st = 0; st < 6; st++) { [w setStep:st]; if ([m2 asksToSay:w] != turns[st]) alternates = NO; }
    CHECK(alternates, "after the first knew-it: say, listen, say, listen, say");
    [m2 save];
    RSLines *m3 = [[[RSLines alloc] initWithFolder:many] autorelease];
    CHECK([[[[m3 lines] lastObject] meaning] isEqualToString:@"I think he's right."], "the meaning is saved");

    // A damaged file: the readable lines stay.
    NSDictionary *bad = [NSDictionary dictionaryWithObject:[NSArray arrayWithObjects:@"junk",
        [NSDictionary dictionaryWithObjectsAndKeys:@"k", @"key", @"v", @"video", nil],
        [NSDictionary dictionaryWithObjectsAndKeys:@"k2", @"key", @"v", @"video", @"Hi", @"text", nil], nil] forKey:@"lines"];
    NSString *damaged = Temp(@"lines-damaged");
    [[NSFileManager defaultManager] createDirectoryAtPath:damaged withIntermediateDirectories:YES attributes:nil error:NULL];
    [bad writeToFile:[damaged stringByAppendingPathComponent:@"Lines.plist"] atomically:YES];
    RSLines *dl = [[[RSLines alloc] initWithFolder:damaged] autorelease];
    CHECK([[dl lines] count] == 1 && [[[[dl lines] objectAtIndex:0] text] isEqualToString:@"Hi"], "damaged entries skipped");
}

// ---- Cutting a line's sound ------------------------------------------------

// Four seconds of a 440 Hz tone, as a WAV file.
static NSString *ToneFile(NSString *path, double seconds)
{
    int rate = 22050, samples = (int)(rate * seconds);
    NSMutableData *d = [NSMutableData data];
    uint32_t u32; uint16_t u16;
    [d appendBytes:"RIFF" length:4]; u32 = 36 + samples * 2; [d appendBytes:&u32 length:4];
    [d appendBytes:"WAVEfmt " length:8]; u32 = 16; [d appendBytes:&u32 length:4];
    u16 = 1; [d appendBytes:&u16 length:2]; u16 = 1; [d appendBytes:&u16 length:2];
    u32 = rate; [d appendBytes:&u32 length:4]; u32 = rate * 2; [d appendBytes:&u32 length:4];
    u16 = 2; [d appendBytes:&u16 length:2]; u16 = 16; [d appendBytes:&u16 length:2];
    [d appendBytes:"data" length:4]; u32 = samples * 2; [d appendBytes:&u32 length:4];
    for (int i = 0; i < samples; i++) {
        int16_t v = (int16_t)(8000 * sin(2 * M_PI * 440 * i / rate));
        [d appendBytes:&v length:2];
    }
    [d writeToFile:path atomically:YES];
    return path;
}

static void TestClip(void)
{
    NSString *tone = ToneFile(Temp(@"tone.wav"), 4);
    CHECK(fabs(RSMediaDuration(tone) - 4) < 0.05, "the tone is 4 seconds: %.3f", RSMediaDuration(tone));
    NSString *out = Temp(@"clip.m4a"), *problem = nil;
    CHECK(RSCutClipNow(tone, 1.0, 2.0, out, &problem), "cut: %s", [problem UTF8String]);
    double d = RSMediaDuration(out);
    CHECK(fabs(d - (1.0 + RSClipLeadIn + RSClipTail)) < 0.1, "a little before and after the line: %.3f s", d);
    CHECK(![[NSFileManager defaultManager] fileExistsAtPath:Temp(@"clip.partial.m4a")], "no partial file left");

    // At the very end: cut short at the end of the sound.
    CHECK(RSCutClipNow(tone, 3.5, 4.0, Temp(@"end.m4a"), &problem) && fabs(RSMediaDuration(Temp(@"end.m4a")) - 0.65) < 0.1,
          "at the end: %.3f s", RSMediaDuration(Temp(@"end.m4a")));
    CHECK(!RSCutClipNow(Temp(@"missing.mp4"), 1, 2, Temp(@"x.m4a"), &problem) && Has(problem, @"no sound"), "no video: %s", [problem UTF8String]);
    [@"not a movie" writeToFile:Temp(@"text.mp4") atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    CHECK(!RSCutClipNow(Temp(@"text.mp4"), 1, 2, Temp(@"y.m4a"), &problem) && ![[NSFileManager defaultManager] fileExistsAtPath:Temp(@"y.m4a")],
          "not a movie: %s", [problem UTF8String]);
    CHECK(!RSCutClipNow(tone, 5, 6, Temp(@"z.m4a"), &problem) && Has(problem, @"too short"), "past the end: %s", [problem UTF8String]);
}

// ---- git ---------------------------------------------------------------------

static void TestSyncMessages(void)
{
    RSSyncResult *r;
    r = [RSSync resultForStatus:0 output:@"Already up to date.\n" timedOut:NO];
    CHECK([r ok] && ![r changed], "up to date");
    r = [RSSync resultForStatus:0 output:@"Updating 1a2b..3c4d\nFast-forward\n Russian/shelf.signed | 4 +-\n" timedOut:NO];
    CHECK([r ok] && [r changed], "updated");
    r = [RSSync resultForStatus:128 output:@"ssh: Could not resolve hostname github.com: nodename nor servname provided, or not known\n" timedOut:NO];
    CHECK(![r ok] && Has([r summary], @"reach the server"), "offline");
    r = [RSSync resultForStatus:128 output:@"fatal: Unable to create '/Users/me/Study/.git/index.lock': File exists.\n\nAnother git process seems to be running in this repository" timedOut:NO];
    CHECK(Has([r summary], @"Another git") && [RSSync isLockContention:[r output]], "index.lock: %s", [[r summary] UTF8String]);
    CHECK([RSSync isLockContention:@"error: cannot lock ref 'refs/remotes/origin/main': is at abc but expected def"], "a ref lock");
    CHECK(![RSSync isLockContention:@"fatal: Not possible to fast-forward, aborting."], "not a lock");
    r = [RSSync resultForStatus:128 output:@"ERROR: The key you are authenticating with has been marked as read only.\nfatal: Could not read from remote repository.\n" timedOut:NO];
    CHECK([r readOnly] && Has([r summary], @"can only read"), "a read-only deploy key: %s", [[r summary] UTF8String]);
    r = [RSSync resultForStatus:128 output:@"ERROR: Permission to ashp0/Study.git denied to deploy key\n" timedOut:NO];
    CHECK([r readOnly], "denied to a deploy key");
    r = [RSSync resultForStatus:128 output:@"Permission denied (publickey).\r\nfatal: Could not read from remote repository.\n" timedOut:NO];
    CHECK(![r readOnly] && Has([r summary], @"deploy key"), "no key at all");
    r = [RSSync resultForStatus:-1 output:@"" timedOut:YES];
    CHECK(![r ok] && Has([r summary], @"two minutes"), "timeout");
}

static BOOL Run(NSString *dir, NSString *script)
{
    NSString *cmd = [NSString stringWithFormat:@"cd '%@' && (%@) >/dev/null 2>&1", dir, script];
    return system([cmd UTF8String]) == 0;
}

static NSString *Capture(NSString *dir, NSString *script)
{
    NSString *out = Temp(@"capture.txt");
    system([[NSString stringWithFormat:@"cd '%@' && (%@) > '%@' 2>&1", dir, script, out] UTF8String]);
    return [[NSString stringWithContentsOfFile:out encoding:NSUTF8StringEncoding error:NULL]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static void TestRealGit(void)
{
    NSString *git = [RSSync gitPath];
    if (git == nil) { printf("  (no git here: skipping the real pulls and pushes)\n"); return; }
    [RSSync setLockRetryDelay:0.5];
    NSString *base = Temp(@"git");
    NSString *g = [NSString stringWithFormat:@"'%@' -c user.name=t -c user.email=t@example.com", git];
    CHECK(Run(Temp(@""), [NSString stringWithFormat:
        @"rm -rf git && mkdir -p git && cd git && %@ init -q --bare origin.git && %@ --git-dir=origin.git symbolic-ref HEAD refs/heads/main && %@ clone -q origin.git mac && cd mac && "
        @"git checkout -q -b main 2>/dev/null; mkdir -p Russian Inbox Calendar && echo sealed > Russian/shelf.signed && "
        @"echo '# notes' > Inbox/keep.txt && %@ add -A && %@ commit -q -m one && %@ push -q origin HEAD:main && "
        @"cd .. && %@ clone -q origin.git macpro", g, g, g, g, g, g, g]), "set up repositories");
    NSString *mac = [base stringByAppendingPathComponent:@"mac"];
    NSString *macpro = [base stringByAppendingPathComponent:@"macpro"];
    CHECK([RSSync isRepository:macpro] && ![RSSync isRepository:base], "repository detection");

    RSSyncResult *r = [RSSync pullFolder:macpro];
    CHECK([r ok] && ![r changed], "first pull: up to date (%s)", [[r output] UTF8String]);
    Run(mac, [NSString stringWithFormat:@"echo sealed2 > Russian/shelf.signed && %@ commit -q -am two && %@ push -q origin HEAD:main", g, g]);
    r = [RSSync pullFolder:macpro];
    CHECK([r ok] && [r changed], "a new shelf arrives (%s)", [[r output] UTF8String]);

    // Syllabus is pulling the same clone: its index.lock is there for a
    // moment. The pull waits and tries again.
    Run(mac, [NSString stringWithFormat:@"echo sealed3 > Russian/shelf.signed && %@ commit -q -am three && %@ push -q origin HEAD:main", g, g]);
    NSString *lock = [macpro stringByAppendingPathComponent:@".git/index.lock"];
    [@"" writeToFile:lock atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_global_queue(0, 0), ^{
        [[NSFileManager defaultManager] removeItemAtPath:lock error:NULL];
    });
    r = [RSSync pullFolder:macpro];
    CHECK([r ok] && [r changed], "a pull waits out another git's index.lock (%s)", [[r output] UTF8String]);
    NSString *text = [NSString stringWithContentsOfFile:[macpro stringByAppendingPathComponent:@"Russian/shelf.signed"]
                                               encoding:NSUTF8StringEncoding error:NULL];
    CHECK(Has(text, @"sealed3"), "and the file arrived");
    // A lock nobody lets go of: it gives up and says so.
    [@"" writeToFile:lock atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    Run(mac, [NSString stringWithFormat:@"echo sealed4 > Russian/shelf.signed && %@ commit -q -am four && %@ push -q origin HEAD:main", g, g]);
    r = [RSSync pullFolder:macpro];
    CHECK(![r ok] && Has([r summary], @"Another git"), "a stuck lock is reported: %s", [[r summary] UTF8String]);
    [[NSFileManager defaultManager] removeItemAtPath:lock error:NULL];
    [RSSync pullFolder:macpro];

    // The Mac Pro's git is 1.9 at the newest (Command Line Tools for 10.9),
    // so the reports go through a git that, like 1.9, takes update-index
    // --cacheinfo only as three arguments, never "mode,blob,path".
    NSString *oldGit = Temp(@"git-1.9");
    [[NSString stringWithFormat:@"#!/bin/sh\n"
      @"if [ \"$1\" = update-index ]; then for a; do case \"$a\" in *,*,*) echo 'usage: git update-index [options] [--] [<file>...]' >&2; exit 129;; esac; done; fi\n"
      @"exec '%@' \"$@\"\n", git] writeToFile:oldGit atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    chmod([oldGit fileSystemRepresentation], 0755);
    [[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObject:oldGit forKey:@"GitPath"]];
    CHECK([[RSSync gitPath] isEqualToString:oldGit], "the pushes use the git-1.9 stand-in");

    // A report: one new file under Russian/Reports, nothing else, and the
    // clone fast-forwards to it.
    NSString *head = Capture(macpro, [NSString stringWithFormat:@"%@ rev-parse HEAD", g]);
    NSDictionary *reports = [NSDictionary dictionaryWithObject:@"Russian Shelf report\nshelf: 2026-10-12\n"
                                                        forKey:@"shelf-2026-10-12_2026-10-14-2105.txt"];
    r = [RSSync pushReports:reports folder:macpro];
    CHECK([r ok], "a report is pushed: %s / %s", [[r summary] UTF8String], [[r output] UTF8String]);
    NSString *changed = Capture(mac, [NSString stringWithFormat:@"%@ pull -q origin main && %@ diff-tree --no-commit-id --name-status -r HEAD~1 HEAD", g, g]);
    CHECK([changed isEqualToString:@"A\tRussian/Reports/shelf-2026-10-12_2026-10-14-2105.txt"], "it added only the report: %s", [changed UTF8String]);
    CHECK([Capture(macpro, [NSString stringWithFormat:@"%@ rev-parse HEAD~1", g]) isEqualToString:head], "on top of what was there");
    CHECK([Capture(macpro, [NSString stringWithFormat:@"%@ status --porcelain", g]) length] == 0, "the clone is clean and current");
    CHECK([[NSFileManager defaultManager] fileExistsAtPath:[macpro stringByAppendingPathComponent:@"Russian/Reports/shelf-2026-10-12_2026-10-14-2105.txt"]],
          "and has the file");
    CHECK([Capture(mac, @"cat Inbox/keep.txt") isEqualToString:@"# notes"], "Inbox untouched");

    // The MacBook pushed in the meantime: the report goes on top of that.
    Run(mac, [NSString stringWithFormat:@"echo sealed5 > Russian/shelf.signed && %@ commit -q -am five && %@ push -q origin HEAD:main", g, g]);
    r = [RSSync pushReports:[NSDictionary dictionaryWithObject:@"second\n" forKey:@"shelf-2026-10-12_2026-10-15-0800.txt"] folder:macpro];
    CHECK([r ok], "a report after the MacBook pushed: %s", [[r summary] UTF8String]);
    CHECK(Has([NSString stringWithContentsOfFile:[macpro stringByAppendingPathComponent:@"Russian/shelf.signed"] encoding:NSUTF8StringEncoding error:NULL], @"sealed5"),
          "and the clone has the MacBook's change too");

    // Names that would leave Russian/Reports are refused before git runs.
    r = [RSSync pushReports:[NSDictionary dictionaryWithObject:@"x" forKey:@"../../Inbox/x.txt"] folder:macpro];
    CHECK(![r ok] && Has([r summary], @"isn’t a report"), "a path outside Reports is refused");

    // A key that can only read (the server refuses the push): nothing in
    // the clone changes, so Syllabus's next pull still fast-forwards.
    Run(base, @"printf '#!/bin/sh\\necho \"ERROR: The key you are authenticating with has been marked as read only.\" >&2\\nexit 1\\n' > origin.git/hooks/pre-receive && chmod +x origin.git/hooks/pre-receive");
    head = Capture(macpro, [NSString stringWithFormat:@"%@ rev-parse HEAD", g]);
    r = [RSSync pushReports:[NSDictionary dictionaryWithObject:@"third\n" forKey:@"shelf-2026-10-12_2026-10-16-0800.txt"] folder:macpro];
    CHECK(![r ok] && [r readOnly], "a read-only key: %s", [[r summary] UTF8String]);
    CHECK([Capture(macpro, [NSString stringWithFormat:@"%@ rev-parse HEAD", g]) isEqualToString:head] &&
          [Capture(macpro, [NSString stringWithFormat:@"%@ status --porcelain", g]) length] == 0, "the clone is exactly as it was");
    Run(base, @"rm origin.git/hooks/pre-receive");
    Run(mac, [NSString stringWithFormat:@"%@ pull -q origin main && echo sealed6 > Russian/shelf.signed && %@ commit -q -am six && %@ push -q origin HEAD:main", g, g, g]);
    r = [RSSync pullFolder:macpro];
    CHECK([r ok] && [r changed], "and pulls still fast-forward afterwards (%s)", [[r summary] UTF8String]);

    r = [RSSync pullFolder:base];
    CHECK(![r ok] && Has([r summary], @"isn’t a git repository"), "not a repository");
    [[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObject:@"" forKey:@"GitPath"]];
    Run(Temp(@""), @"rm -rf git git-1.9");
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc != 2) { fprintf(stderr, "usage: rssuite <Tests/Fixtures>\n"); return 2; }
        NSString *fixtures = [NSString stringWithUTF8String:argv[1]];
        TestAESVector();
        TestSignatures();
        TestShelfFormat();
        TestSealed();
        TestRealKey(fixtures);
        TestSubtitles(fixtures);
        TestLibrary();
        TestLines();
        TestClip();
        TestCommandLines();
        TestReports();
        TestSyncMessages();
        TestRealGit();
        [[NSFileManager defaultManager] removeItemAtPath:Temp(@"") error:NULL];
        printf("%d checks, %d failed\n", checks, failures);
    }
    return failures ? 1 : 0;
}
