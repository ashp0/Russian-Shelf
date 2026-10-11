#import "RSShelf.h"
#import "RSCrypto.h"
#import "RSDate.h"
#import "RSKeys.h"

#import <CommonCrypto/CommonDigest.h>

static NSString *const RSPlainHeader = @"Russian Shelf 1";
static NSString *const RSSealedHeader = @"Russian Shelf sealed 1";
static const NSUInteger RSSealedMaxBytes = 64 * 1024;
static const NSUInteger RSTitleMaxLength = 300;

@implementation RSVideo

- (void)dealloc
{
    [_identifier release];
    [_channel release];
    [_title release];
    [super dealloc];
}

+ (BOOL)isValidIdentifier:(NSString *)identifier
{
    if ([identifier length] != 11) return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"];
    return [identifier rangeOfCharacterFromSet:[allowed invertedSet]].location == NSNotFound;
}

@end

@interface RSShelf ()
@property (nonatomic, readwrite) long start;
@property (nonatomic, readwrite, copy) NSString *startText;
@property (nonatomic, readwrite, copy) NSString *sealed;
@property (nonatomic, readwrite, copy) NSArray *videos;
@property (nonatomic, readwrite, copy) NSString *fingerprint;
@end

static NSString *RSTrim(NSString *s)
{
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

static BOOL RSHasControlCharacters(NSString *s)
{
    return [s rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound;
}

static BOOL RSIsSealedTime(NSString *s)
{
    // "2026-10-11 20:15:07"
    if ([s length] != 19) return NO;
    int ok = 0;
    RSParseDay([[s substringToIndex:10] UTF8String], &ok);
    if (!ok || [s characterAtIndex:10] != ' ') return NO;
    int h, m, sec, used = 0;
    if (sscanf([[s substringFromIndex:11] UTF8String], "%2d:%2d:%2d%n", &h, &m, &sec, &used) != 3 || used != 8) return NO;
    return h >= 0 && h < 24 && m >= 0 && m < 60 && sec >= 0 && sec < 60;
}

@implementation RSShelf

- (void)dealloc
{
    [_startText release];
    [_sealed release];
    [_videos release];
    [_fingerprint release];
    [super dealloc];
}

+ (RSShelf *)shelfWithText:(NSString *)text problem:(NSString **)problem
{
    *problem = nil;
    NSArray *lines = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
                      componentsSeparatedByString:@"\n"];
    BOOL headerSeen = NO;
    NSString *startText = nil, *sealed = nil;
    long start = 0;
    NSMutableArray *videos = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSUInteger count = 0;

    for (NSUInteger i = 0; i < [lines count]; i++) {
        NSString *line = RSTrim([lines objectAtIndex:i]);
        NSUInteger number = i + 1;
        if ([line length] == 0 || [line hasPrefix:@"#"]) continue;
        if (!headerSeen) {
            if (![line isEqualToString:RSPlainHeader]) {
                *problem = [NSString stringWithFormat:@"Line %lu should say “%@”.", (unsigned long)number, RSPlainHeader];
                return nil;
            }
            headerSeen = YES;
            continue;
        }
        NSRange colon = [line rangeOfString:@":"];
        NSString *key = colon.location == NSNotFound ? @"" : RSTrim([line substringToIndex:colon.location]);
        NSString *value = colon.location == NSNotFound ? @"" : RSTrim([line substringFromIndex:NSMaxRange(colon)]);
        if ([key isEqualToString:@"start"]) {
            int ok = 0;
            long day = RSParseDay([value UTF8String], &ok);
            if (!ok || startText) {
                *problem = [NSString stringWithFormat:@"Line %lu: %@.", (unsigned long)number,
                            startText ? @"a second start date" : @"the start date should look like 2026-10-12"];
                return nil;
            }
            startText = value;
            start = day;
        } else if ([key isEqualToString:@"sealed"]) {
            if (!RSIsSealedTime(value) || sealed) {
                *problem = [NSString stringWithFormat:@"Line %lu: the sealed time should look like 2026-10-11 20:15:07.", (unsigned long)number];
                return nil;
            }
            sealed = value;
        } else if ([key isEqualToString:@"video"]) {
            count++;
            if (count > RSShelfMaxVideos) continue;     // counted, refused below
            NSArray *parts = [value componentsSeparatedByString:@" | "];
            if ([parts count] < 3) {
                *problem = [NSString stringWithFormat:@"Line %lu: a video is “id | channel | title”.", (unsigned long)number];
                return nil;
            }
            NSString *identifier = RSTrim([parts objectAtIndex:0]);
            NSString *channel = RSTrim([parts objectAtIndex:1]);
            NSString *title = RSTrim([[parts subarrayWithRange:NSMakeRange(2, [parts count] - 2)]
                                      componentsJoinedByString:@" | "]);
            if (![RSVideo isValidIdentifier:identifier]) {
                *problem = [NSString stringWithFormat:@"Line %lu: “%@” isn’t a YouTube video id.", (unsigned long)number, identifier];
                return nil;
            }
            if ([seen containsObject:identifier]) {
                *problem = [NSString stringWithFormat:@"Line %lu: %@ is on the shelf twice.", (unsigned long)number, identifier];
                return nil;
            }
            if ([channel length] == 0 || [title length] == 0 || [title length] > RSTitleMaxLength ||
                [channel length] > RSTitleMaxLength || RSHasControlCharacters(title) || RSHasControlCharacters(channel)) {
                *problem = [NSString stringWithFormat:@"Line %lu: the channel or title is empty or too long.", (unsigned long)number];
                return nil;
            }
            [seen addObject:identifier];
            RSVideo *video = [[[RSVideo alloc] init] autorelease];
            [video setIdentifier:identifier];
            [video setChannel:channel];
            [video setTitle:title];
            [videos addObject:video];
        } else {
            *problem = [NSString stringWithFormat:@"Line %lu isn’t part of a shelf.", (unsigned long)number];
            return nil;
        }
    }
    if (!headerSeen) { *problem = @"It’s empty."; return nil; }
    if (startText == nil) { *problem = @"It has no start date."; return nil; }
    if (count == 0) { *problem = @"It has no videos."; return nil; }
    if (count > RSShelfMaxVideos) {
        *problem = [NSString stringWithFormat:@"It has %lu videos; a shelf holds at most %d.", (unsigned long)count, RSShelfMaxVideos];
        return nil;
    }
    RSShelf *shelf = [[[RSShelf alloc] init] autorelease];
    [shelf setStart:start];
    [shelf setStartText:startText];
    [shelf setSealed:sealed];
    [shelf setVideos:videos];
    return shelf;
}

- (NSString *)text
{
    NSMutableString *s = [NSMutableString stringWithFormat:@"%@\nstart: %@\n", RSPlainHeader, _startText];
    if (_sealed) [s appendFormat:@"sealed: %@\n", _sealed];
    for (RSVideo *v in _videos)
        [s appendFormat:@"video: %@ | %@ | %@\n", [v identifier], [v channel], [v title]];
    return s;
}

- (RSShelf *)shelfSealedAt:(NSString *)sealed
{
    RSShelf *copy = [[[RSShelf alloc] init] autorelease];
    [copy setStart:_start];
    [copy setStartText:_startText];
    [copy setSealed:sealed];
    [copy setVideos:_videos];
    return copy;
}

- (RSVideo *)videoWithIdentifier:(NSString *)identifier
{
    for (RSVideo *v in _videos)
        if ([[v identifier] isEqualToString:identifier]) return v;
    return nil;
}

- (NSArray *)identifiers
{
    NSMutableArray *ids = [NSMutableArray array];
    for (RSVideo *v in _videos) [ids addObject:[v identifier]];
    return ids;
}

- (BOOL)isNewerThan:(RSShelf *)other
{
    if (other == nil) return YES;
    if (_start != [other start]) return _start > [other start];
    return [(_sealed ?: @"") compare:([other sealed] ?: @"")] == NSOrderedDescending;
}

@end

NSData *RSSignedMessage(NSData *iv, NSData *ciphertext)
{
    NSMutableData *message = [NSMutableData data];
    [message appendData:[[RSSealedHeader stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    [message appendData:iv];
    [message appendData:ciphertext];
    return message;
}

static NSString *RSFingerprint(NSData *file)
{
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256([file bytes], (CC_LONG)[file length], digest);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < 8; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

NSData *RSSealShelf(RSShelf *shelf, NSData *aesKey, NSData *iv,
                    NSData *(^sign)(NSData *message, NSString **problem), NSString **problem)
{
    *problem = nil;
    if ([shelf sealed] == nil) { *problem = @"The shelf has no sealed time."; return nil; }
    NSData *plain = [[shelf text] dataUsingEncoding:NSUTF8StringEncoding];
    NSData *ciphertext = RSAESCTR(plain, aesKey, iv);
    if (ciphertext == nil) { *problem = @"Encryption failed."; return nil; }
    NSData *signature = sign(RSSignedMessage(iv, ciphertext), problem);
    if (signature == nil) return nil;
    NSString *file = [NSString stringWithFormat:@"%@\niv: %@\ndata: %@\nsignature: %@\n", RSSealedHeader,
                      [iv base64EncodedStringWithOptions:0], [ciphertext base64EncodedStringWithOptions:0],
                      [signature base64EncodedStringWithOptions:0]];
    return [file dataUsingEncoding:NSUTF8StringEncoding];
}

RSShelf *RSOpenSealedShelf(NSData *file, NSData *aesKey, NSData *publicKey, NSString **problem)
{
    *problem = nil;
    if ([file length] == 0 || [file length] > RSSealedMaxBytes) {
        *problem = [file length] ? @"The file is too big to be a shelf." : @"The file is empty.";
        return nil;
    }
    NSString *text = [[[NSString alloc] initWithData:file encoding:NSUTF8StringEncoding] autorelease];
    NSArray *lines = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] componentsSeparatedByString:@"\n"];
    NSMutableArray *content = [NSMutableArray array];
    for (NSString *line in lines)
        if ([RSTrim(line) length]) [content addObject:RSTrim(line)];
    if (text == nil || [content count] != 4 || ![[content objectAtIndex:0] isEqualToString:RSSealedHeader] ||
        ![[content objectAtIndex:1] hasPrefix:@"iv: "] || ![[content objectAtIndex:2] hasPrefix:@"data: "] ||
        ![[content objectAtIndex:3] hasPrefix:@"signature: "]) {
        *problem = @"The file isn’t a sealed shelf.";
        return nil;
    }
    NSData *iv = [[[NSData alloc] initWithBase64EncodedString:[[content objectAtIndex:1] substringFromIndex:4] options:0] autorelease];
    NSData *ciphertext = [[[NSData alloc] initWithBase64EncodedString:[[content objectAtIndex:2] substringFromIndex:6] options:0] autorelease];
    NSData *signature = [[[NSData alloc] initWithBase64EncodedString:[[content objectAtIndex:3] substringFromIndex:11] options:0] autorelease];
    if ([iv length] != 16 || [ciphertext length] == 0 || [signature length] == 0) {
        *problem = @"The file is damaged.";
        return nil;
    }
    if (!RSVerifySignature(RSSignedMessage(iv, ciphertext), signature, publicKey, problem))
        return nil;
    NSData *plain = RSAESCTR(ciphertext, aesKey, iv);
    NSString *list = plain ? [[[NSString alloc] initWithData:plain encoding:NSUTF8StringEncoding] autorelease] : nil;
    if (list == nil) {
        *problem = @"It’s signed, but doesn’t decrypt with this app’s key.";
        return nil;
    }
    RSShelf *shelf = [RSShelf shelfWithText:list problem:problem];
    if (shelf == nil) return nil;
    if ([shelf sealed] == nil) {
        *problem = @"It has no sealed time.";
        return nil;
    }
    [shelf setFingerprint:RSFingerprint(file)];
    return shelf;
}

NSData *RSAppAESKey(void)
{
    return [NSData dataWithBytes:RSKeyAES length:sizeof RSKeyAES];
}

NSData *RSAppPublicKey(void)
{
    return [NSData dataWithBytes:RSKeyPublic length:sizeof RSKeyPublic];
}

RSShelf *RSOpenShelfFile(NSData *file, NSString **problem)
{
    return RSOpenSealedShelf(file, RSAppAESKey(), RSAppPublicKey(), problem);
}
