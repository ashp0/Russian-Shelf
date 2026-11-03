// shelfsign -- seals the week's shelf on the MacBook.
//
//   shelfsign seal <list.txt> <shelf.signed>   check the list, encrypt it, sign
//                                              it, check the result opens in
//                                              the app, write it. A list whose
//                                              first line is "Russian Reading 1"
//                                              (RSReading.h) is sealed the same
//                                              way, into Russian/reading.signed
//   shelfsign open <shelf.signed>              check and print a sealed shelf
//                                              or reading list
//   shelfsign pubkey                           the keychain key's public half
//   shelfsign keygen <RSKeys.c>                once: make the keys (make keys)
//
// The list format is in RSShelf.h and the README. Built for this Mac by
// `make shelfsign`, from the app's own shelf and crypto code, so it seals
// exactly what Russian Shelf opens; code-signed, so the keychain lets it use
// the key without asking after every rebuild.
//
// The private key never leaves the login keychain: it is created there,
// non-extractable, and used through SecKeyCreateSignature.

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "RSShelf.h"
#import "RSReading.h"
#import "RSCrypto.h"

static NSString *const RSKeyLabel = @"Russian Shelf signing key";
static NSString *const RSKeyTag = @"com.russianshelf.signing";

static void Fail(NSString *message)
{
    fprintf(stderr, "shelfsign: %s\n", [message UTF8String]);
    exit(1);
}

static NSString *ErrorText(CFErrorRef error)
{
    return error ? [(NSError *)error localizedDescription] : @"no reason given";
}

static SecKeyRef CopyPrivateKey(void)
{
    NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys:
        (id)kSecClassKey, (id)kSecClass,
        [RSKeyTag dataUsingEncoding:NSUTF8StringEncoding], (id)kSecAttrApplicationTag,
        (id)kSecAttrKeyTypeECSECPrimeRandom, (id)kSecAttrKeyType,
        (id)kSecAttrKeyClassPrivate, (id)kSecAttrKeyClass,
        (id)kCFBooleanTrue, (id)kSecReturnRef, nil];
    CFTypeRef key = NULL;
    OSStatus status = SecItemCopyMatching((CFDictionaryRef)query, &key);
    if (status == errSecItemNotFound) return NULL;
    if (status != errSecSuccess) Fail([NSString stringWithFormat:@"the keychain refused (error %d)", (int)status]);
    return (SecKeyRef)key;
}

static NSData *PublicKeyInfo(SecKeyRef privateKey)
{
    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
    if (publicKey == NULL) Fail(@"the key has no public half");
    CFErrorRef error = NULL;
    NSData *point = (NSData *)SecKeyCopyExternalRepresentation(publicKey, &error);
    CFRelease(publicKey);
    if (point == nil) Fail([NSString stringWithFormat:@"can't read the public key: %@", ErrorText(error)]);
    NSData *info = RSPublicKeyInfoFromPoint(point);
    [point release];
    if (info == nil) Fail(@"the key isn't a P-256 key");
    return info;
}

static NSData *RandomBytes(size_t count)
{
    NSMutableData *data = [NSMutableData dataWithLength:count];
    if (SecRandomCopyBytes(kSecRandomDefault, count, [data mutableBytes]) != errSecSuccess) Fail(@"no random bytes");
    return data;
}

// Local time on this Mac, as "2026-10-11 20:15:07" (or another strftime format).
static NSString *Now(const char *format)
{
    char buffer[64];
    time_t t = time(NULL);
    struct tm tm;
    localtime_r(&t, &tm);
    strftime(buffer, sizeof buffer, format, &tm);
    return [NSString stringWithUTF8String:buffer];
}

static NSString *CArray(NSData *data)
{
    NSMutableString *s = [NSMutableString string];
    const unsigned char *b = [data bytes];
    for (NSUInteger i = 0; i < [data length]; i++)
        [s appendFormat:@"%s0x%02x,", i % 12 == 0 ? "\n    " : " ", b[i]];
    return s;
}

static int Keygen(NSString *path)
{
    if ([[NSFileManager defaultManager] fileExistsAtPath:path])
        Fail([NSString stringWithFormat:@"%@ already exists; the keys are made once", path]);
    SecKeyRef existing = CopyPrivateKey();
    if (existing) { CFRelease(existing); Fail(@"the keychain already has a Russian Shelf signing key"); }

    NSData *tag = [RSKeyTag dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *privateAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
        (id)kCFBooleanTrue, (id)kSecAttrIsPermanent,
        (id)kCFBooleanFalse, (id)kSecAttrIsExtractable,
        tag, (id)kSecAttrApplicationTag,
        RSKeyLabel, (id)kSecAttrLabel, nil];
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
        (id)kSecAttrKeyTypeECSECPrimeRandom, (id)kSecAttrKeyType,
        [NSNumber numberWithInt:256], (id)kSecAttrKeySizeInBits,
        (id)kCFBooleanFalse, (id)kSecAttrIsExtractable,
        RSKeyLabel, (id)kSecAttrLabel,
        privateAttributes, (id)kSecPrivateKeyAttrs, nil];
    CFErrorRef error = NULL;
    SecKeyRef key = SecKeyCreateRandomKey((CFDictionaryRef)attributes, &error);
    if (key == NULL) Fail([NSString stringWithFormat:@"couldn't make the key: %@", ErrorText(error)]);
    NSData *publicKey = PublicKeyInfo(key);
    CFRelease(key);

    NSString *source = [NSString stringWithFormat:
        @"// Russian Shelf's keys, made by `shelfsign keygen` on %@. See RSKeys.h.\n"
        @"//\n"
        @"// The signing key's private half is in the MacBook's login keychain,\n"
        @"// labelled \"%@\", and nowhere else.\n\n"
        @"#include \"RSKeys.h\"\n\n"
        @"const unsigned char RSKeyAES[32] = {%@\n};\n\n"
        @"const unsigned char RSKeyPublic[91] = {%@\n};\n",
        Now("%Y-%m-%d"),
        RSKeyLabel, CArray(RandomBytes(32)), CArray(publicKey)];
    if (![source writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL])
        Fail([NSString stringWithFormat:@"can't write %@", path]);
    printf("Made the signing key in the login keychain (\"%s\", not extractable)\n", [RSKeyLabel UTF8String]);
    printf("Wrote %s\n", [path UTF8String]);
    printf("Public key: %s\n", [[publicKey base64EncodedStringWithOptions:0] UTF8String]);
    return 0;
}

static int Pubkey(void)
{
    SecKeyRef key = CopyPrivateKey();
    if (key == NULL) Fail(@"the keychain has no Russian Shelf signing key (make keys)");
    NSData *publicKey = PublicKeyInfo(key);
    CFRelease(key);
    printf("%s\n", [[publicKey base64EncodedStringWithOptions:0] UTF8String]);
    printf("%s\n", [publicKey isEqualToData:RSAppPublicKey()] ? "This is the key built into the app."
                                                             : "This is NOT the key built into the app.");
    return 0;
}

static SecKeyRef SigningKey(void)
{
    SecKeyRef key = CopyPrivateKey();
    if (key == NULL) Fail(@"the keychain has no Russian Shelf signing key (make keys)");
    if (![PublicKeyInfo(key) isEqualToData:RSAppPublicKey()])
        Fail(@"the keychain's key isn't the one built into the app: rebuild the app after make keys");
    return key;
}

static NSData *(^Signer(SecKeyRef key))(NSData *, NSString **)
{
    return [[^NSData *(NSData *message, NSString **why) {
        CFErrorRef error = NULL;
        NSData *signature = (NSData *)SecKeyCreateSignature(key, kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                                            (CFDataRef)message, &error);
        if (signature == nil) *why = [NSString stringWithFormat:@"signing failed: %@", ErrorText(error)];
        return [signature autorelease];
    } copy] autorelease];
}

// A reading list (RSReading.h): checked, sealed and checked again as the app will.
static int SealReading(NSString *listPath, NSString *text, NSString *outPath)
{
    NSString *problem = nil;
    RSReadingSet *set = [RSReadingSet setWithText:text problem:&problem];
    if (set == nil) Fail([NSString stringWithFormat:@"%@: %@", [listPath lastPathComponent], problem]);
    if ([set sealed]) Fail(@"the list already has a sealed: line; shelfsign writes that itself");
    set = [set setSealedAt:Now("%Y-%m-%d %H:%M:%S")];
    SecKeyRef key = SigningKey();
    NSData *file = RSSealText([set text], RSAppAESKey(), RandomBytes(16), Signer(key), &problem);
    CFRelease(key);
    if (file == nil) Fail(problem);
    RSReadingSet *opened = RSOpenReadingFile(file, &problem);
    if (opened == nil) Fail([NSString stringWithFormat:@"the sealed file doesn't open: %@", problem]);
    if (![[opened text] isEqualToString:[set text]]) Fail(@"the sealed file opens to a different list");
    if (![file writeToFile:outPath atomically:YES]) Fail([NSString stringWithFormat:@"can't write %@", outPath]);
    printf("Sealed %lu reading%s from %s (sealed %s) into %s\n", (unsigned long)[[opened items] count],
           [[opened items] count] == 1 ? "" : "s", [[opened startText] UTF8String], [[opened sealed] UTF8String], [outPath UTF8String]);
    return 0;
}

static int Seal(NSString *listPath, NSString *outPath)
{
    NSError *readError = nil;
    NSString *text = [NSString stringWithContentsOfFile:listPath encoding:NSUTF8StringEncoding error:&readError];
    if (text == nil) Fail([NSString stringWithFormat:@"can't read %@", listPath]);
    if (RSTextIsReadingList(text)) return SealReading(listPath, text, outPath);
    NSString *problem = nil;
    RSShelf *shelf = [RSShelf shelfWithText:text problem:&problem];
    if (shelf == nil) Fail([NSString stringWithFormat:@"%@: %@", [listPath lastPathComponent], problem]);
    if ([shelf sealed]) Fail(@"the list already has a sealed: line; shelfsign writes that itself");
    shelf = [shelf shelfSealedAt:Now("%Y-%m-%d %H:%M:%S")];

    SecKeyRef key = SigningKey();
    NSData *file = RSSealShelf(shelf, RSAppAESKey(), RandomBytes(16), Signer(key), &problem);
    CFRelease(key);
    if (file == nil) Fail(problem);

    // Open it exactly as the app will, with the app's own code and keys.
    RSShelf *opened = RSOpenShelfFile(file, &problem);
    if (opened == nil) Fail([NSString stringWithFormat:@"the sealed file doesn't open: %@", problem]);
    if (![[opened text] isEqualToString:[shelf text]]) Fail(@"the sealed file opens to a different list");

    if (![file writeToFile:outPath atomically:YES]) Fail([NSString stringWithFormat:@"can't write %@", outPath]);
    printf("Sealed %lu video%s from %s (sealed %s) into %s\n", (unsigned long)[[opened videos] count],
           [[opened videos] count] == 1 ? "" : "s", [[opened startText] UTF8String], [[opened sealed] UTF8String],
           [outPath UTF8String]);
    return 0;
}

static int Open(NSString *path)
{
    NSData *file = [NSData dataWithContentsOfFile:path];
    if (file == nil) Fail([NSString stringWithFormat:@"can't read %@", path]);
    NSString *problem = nil;
    NSString *plain = RSOpenSealedText(file, RSAppAESKey(), RSAppPublicKey(), NULL, &problem);
    if (plain == nil) Fail(problem);
    if (RSTextIsReadingList(plain)) {
        RSReadingSet *set = [RSReadingSet setWithText:plain problem:&problem];
        if (set == nil) Fail(problem);
        printf("%s", [[set text] UTF8String]);
        return 0;
    }
    RSShelf *shelf = RSOpenShelfFile(file, &problem);
    if (shelf == nil) Fail(problem);
    printf("%s", [[shelf text] UTF8String]);
    return 0;
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        NSString *command = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"";
        if ([command isEqualToString:@"seal"] && argc == 4)
            return Seal([NSString stringWithUTF8String:argv[2]], [NSString stringWithUTF8String:argv[3]]);
        if ([command isEqualToString:@"open"] && argc == 3)
            return Open([NSString stringWithUTF8String:argv[2]]);
        if ([command isEqualToString:@"pubkey"] && argc == 2)
            return Pubkey();
        if ([command isEqualToString:@"keygen"] && argc == 3)
            return Keygen([NSString stringWithUTF8String:argv[2]]);
        fprintf(stderr, "usage: shelfsign seal <list.txt> <shelf.signed>      (a shelf, or a reading list into reading.signed)\n"
                        "       shelfsign open <shelf.signed>\n"
                        "       shelfsign pubkey\n"
                        "       shelfsign keygen <RSKeys.c>\n");
        return 2;
    }
}
