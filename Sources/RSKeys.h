// The keys built into the app, in RSKeys.c: written once by
// `shelfsign keygen` (make keys), never by hand.
//
//   RSKeyAES      encrypts and decrypts the list (AES-256-CTR). It's in the
//                 app, so anyone with the app has it: it keeps the list from
//                 being read or edited in the repo, nothing more.
//   RSKeyPublic   checks the signature (P-256, DER SubjectPublicKeyInfo). Its
//                 private half lives only in the MacBook's login keychain,
//                 marked non-extractable, labelled "Russian Shelf signing key".

#ifndef RS_KEYS_H
#define RS_KEYS_H

extern const unsigned char RSKeyAES[32];
extern const unsigned char RSKeyPublic[91];

#endif
