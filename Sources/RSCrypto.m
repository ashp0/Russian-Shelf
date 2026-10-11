#import "RSCrypto.h"

#import <CommonCrypto/CommonCryptor.h>
#import <Security/Security.h>

NSData *RSAESCTR(NSData *input, NSData *key, NSData *iv)
{
    if ([key length] != kCCKeySizeAES256 || [iv length] != kCCBlockSizeAES128 || input == nil) return nil;
    CCCryptorRef cryptor = NULL;
    // kCCModeOptionCTR_BE is required on 10.9 (it has no other counter) and
    // accepted, though deprecated, on later systems.
    CCCryptorStatus status = CCCryptorCreateWithMode(kCCEncrypt, kCCModeCTR, kCCAlgorithmAES, ccNoPadding,
                                                     [iv bytes], [key bytes], [key length], NULL, 0, 0,
                                                     kCCModeOptionCTR_BE, &cryptor);
    if (status != kCCSuccess || cryptor == NULL) return nil;
    NSMutableData *output = [NSMutableData dataWithLength:[input length]];
    size_t moved = 0, finished = 0;
    status = CCCryptorUpdate(cryptor, [input bytes], [input length], [output mutableBytes], [output length], &moved);
    if (status == kCCSuccess)
        status = CCCryptorFinal(cryptor, (char *)[output mutableBytes] + moved, [output length] - moved, &finished);
    CCCryptorRelease(cryptor);
    if (status != kCCSuccess || moved + finished != [input length]) return nil;
    return output;
}

NSData *RSPublicKeyInfoFromPoint(NSData *point)
{
    // SEQUENCE { SEQUENCE { id-ecPublicKey, prime256v1 }, BIT STRING point }
    static const unsigned char header[26] = {
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
        0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00 };
    if ([point length] != 65 || ((const unsigned char *)[point bytes])[0] != 0x04) return nil;
    NSMutableData *info = [NSMutableData dataWithBytes:header length:sizeof header];
    [info appendData:point];
    return info;
}

static NSString *RSErrorText(CFErrorRef error)
{
    if (error == NULL) return @"no reason given";
    NSString *text = [(NSError *)error localizedDescription];
    return [text length] ? text : [NSString stringWithFormat:@"error %ld", (long)CFErrorGetCode(error)];
}

BOOL RSVerifySignature(NSData *message, NSData *signature, NSData *publicKey, NSString **problem)
{
    *problem = nil;
    if ([signature length] < 8 || [signature length] > 80) {
        *problem = @"The signature doesn’t match Claude’s key.";
        return NO;
    }

    SecExternalFormat format = kSecFormatOpenSSL;     // DER SubjectPublicKeyInfo, for a public key
    SecExternalItemType type = kSecItemTypePublicKey;
    SecItemImportExportKeyParameters params;
    memset(&params, 0, sizeof params);
    params.version = SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION;
    CFArrayRef items = NULL;
    OSStatus status = SecItemImport((CFDataRef)publicKey, NULL, &format, &type, 0, &params, NULL, &items);
    if (status != errSecSuccess || items == NULL || CFArrayGetCount(items) != 1 ||
        CFGetTypeID(CFArrayGetValueAtIndex(items, 0)) != SecKeyGetTypeID()) {
        if (items) CFRelease(items);
        *problem = [NSString stringWithFormat:@"This Mac couldn’t load Claude’s public key (Security error %d).", (int)status];
        return NO;
    }
    SecKeyRef key = (SecKeyRef)CFArrayGetValueAtIndex(items, 0);

    BOOL valid = NO;
    CFErrorRef error = NULL;
    SecTransformRef verifier = SecVerifyTransformCreate(key, (CFDataRef)signature, &error);
    if (verifier == NULL) {
        *problem = [NSString stringWithFormat:@"This Mac couldn’t check the signature (%@).", RSErrorText(error)];
    } else {
        int bits = 256;
        CFNumberRef length = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &bits);
        if (SecTransformSetAttribute(verifier, kSecTransformInputAttributeName, (CFDataRef)message, &error) &&
            SecTransformSetAttribute(verifier, kSecDigestTypeAttribute, kSecDigestSHA2, &error) &&
            SecTransformSetAttribute(verifier, kSecDigestLengthAttribute, length, &error)) {
            CFTypeRef result = SecTransformExecute(verifier, &error);
            valid = result != NULL && CFGetTypeID(result) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)result);
            if (result) CFRelease(result);
            // A signature that isn't even well-formed DER comes back as an
            // error rather than false: either way, it doesn't match.
            if (!valid) *problem = @"The signature doesn’t match Claude’s key.";
        } else {
            *problem = [NSString stringWithFormat:@"This Mac couldn’t check the signature (%@).", RSErrorText(error)];
        }
        CFRelease(length);
        CFRelease(verifier);
    }
    if (error) CFRelease(error);
    CFRelease(items);
    return valid;
}
