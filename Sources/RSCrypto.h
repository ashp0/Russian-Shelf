// The two pieces of cryptography a shelf needs, with only what OS X 10.9 has.
//
// AES-256-CTR comes from CommonCrypto. The signature check uses the Security
// framework's 10.7-era API: SecItemImport to load the public key and a
// SecVerifyTransform to check the signature. (SecKeyVerifySignature arrived
// in 10.12, and the 10.9 SDK doesn't declare SecKeyRawVerify for the Mac:
// 10.9's Security has the symbol, but not as public API.)

#import <Foundation/Foundation.h>

// AES-256 in CTR mode with a big-endian counter starting at `iv`. The same
// call encrypts and decrypts. nil if key isn't 32 bytes or iv 16, or if
// CommonCrypto refuses.
NSData *RSAESCTR(NSData *input, NSData *key, NSData *iv);

// YES if `signature` (DER, X9.62) is an ECDSA P-256 / SHA-256 signature of
// `message` by the private half of `publicKey` (DER SubjectPublicKeyInfo).
// Otherwise NO, and *problem says which: the signature doesn't match, or this
// Mac couldn't check it at all (a key it can't load, say).
BOOL RSVerifySignature(NSData *message, NSData *signature, NSData *publicKey, NSString **problem);

// The P-256 SubjectPublicKeyInfo wrapping an uncompressed X9.63 point
// (04 || X || Y, 65 bytes), or nil if it isn't one.
NSData *RSPublicKeyInfoFromPoint(NSData *point);
