// A week's shelf: the videos Claude chose, in order, and the day they start.
//
// Claude writes it as plain text on the MacBook:
//
//     Russian Shelf 1
//     start: 2026-10-12
//     video: JE4cI_Knzvc | Sergey Storyteller | She Cut Her Hair to Save Her Husband
//     video: ...                                          (1 to 12 of these)
//
// `shelfsign seal` adds a `sealed:` line (when it was sealed, to the second),
// encrypts the text with AES-256-CTR under the key built into the app, signs
// the result with ECDSA P-256 / SHA-256, and writes Russian/shelf.signed:
//
//     Russian Shelf sealed 1
//     iv: <16 bytes, base64>
//     data: <the encrypted text, base64>
//     signature: <DER signature, base64>
//
// The signature covers the first line, the IV and the encrypted text, so none
// of them can be changed or swapped. The app checks it before decrypting.

#import <Foundation/Foundation.h>

enum { RSShelfMaxVideos = 12 };

@interface RSVideo : NSObject
@property (nonatomic, copy) NSString *identifier;   // YouTube's 11-character id
@property (nonatomic, copy) NSString *channel;
@property (nonatomic, copy) NSString *title;
+ (BOOL)isValidIdentifier:(NSString *)identifier;
@end

@interface RSShelf : NSObject

@property (nonatomic, readonly) long start;                  // day number (RSDate.h)
@property (nonatomic, readonly, copy) NSString *startText;   // "2026-10-12"
@property (nonatomic, readonly, copy) NSString *sealed;      // "2026-10-11 20:15:07", nil until sealed
@property (nonatomic, readonly, copy) NSArray *videos;       // RSVideo, in Claude's order
@property (nonatomic, readonly, copy) NSString *fingerprint; // of the sealed file; nil for plain text

// The plain list. nil with *problem set (naming the line) if it doesn't read.
+ (RSShelf *)shelfWithText:(NSString *)text problem:(NSString **)problem;
// The same list written out again, with `sealed:` when there is one.
- (NSString *)text;
- (RSShelf *)shelfSealedAt:(NSString *)sealed;

- (RSVideo *)videoWithIdentifier:(NSString *)identifier;
- (NSArray *)identifiers;
// Later start, or the same start sealed later (a correction).
- (BOOL)isNewerThan:(RSShelf *)other;

@end

// The signed part of a sealed file: its first line, the IV, the ciphertext.
NSData *RSSignedMessage(NSData *iv, NSData *ciphertext);

// Builds a sealed file from a list that already carries `sealed:`. `sign`
// returns a DER signature of the message it's given, or nil with a problem.
NSData *RSSealShelf(RSShelf *shelf, NSData *aesKey, NSData *iv,
                    NSData *(^sign)(NSData *message, NSString **problem), NSString **problem);

// Checks a sealed file's signature with `publicKey`, decrypts it with
// `aesKey` and reads the list. nil with *problem set to one plain sentence
// otherwise: a bad signature, more than 12 videos, a malformed file.
RSShelf *RSOpenSealedShelf(NSData *file, NSData *aesKey, NSData *publicKey, NSString **problem);

// The same, with the keys built into the app (RSKeys.c).
RSShelf *RSOpenShelfFile(NSData *file, NSString **problem);
NSData *RSAppAESKey(void);
NSData *RSAppPublicKey(void);
