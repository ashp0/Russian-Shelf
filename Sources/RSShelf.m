#import "RSShelf.h"
#import "RSCrypto.h"
#import "RSDate.h"
#import "RSKeys.h"

#import <CommonCrypto/CommonDigest.h>

static NSString *const RSPlainHeader = @"Russian Shelf 1";
static NSString *const RSSealedHeader = @"Russian Shelf sealed 1";
static const NSUInteger RSSealedMaxBytes = 64 * 1024;
static const NSUInteger RSTitleMaxLength = 300;

NSString *const RSKindEasy = @"easy", *const RSKindNatural = @"natural", *const RSKindFast = @"fast";

NSArray *RSKinds(void)
{
    return [NSArray arrayWithObjects:RSKindEasy, RSKindNatural, RSKindFast, nil];
}

NSString *RSKindTitle(NSString *kind)
{
    if ([kind isEqualToString:RSKindEasy]) return @"Easy stories";
    if ([kind isEqualToString:RSKindNatural]) return @"Natural speech";
    if ([kind isEqualToString:RSKindFast]) return @"Fast speech";
    return nil;
}

// "# kind: fast" -> "fast"; nil for any other comment.
static NSString *RSKindInComment(NSString *line)
{
    NSString *rest = [[line substringFromIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (![[rest lowercaseString] hasPrefix:@"kind:"]) return nil;
    NSString *kind = [[[rest substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
    return [RSKinds() containsObject:kind] ? kind : nil;
}

@implementation RSVideo

- (void)dealloc
{
    [_identifier release];
    [_channel release];
    [_title release];
    [_kind release];
    [super dealloc];
}

- (NSString *)displayTitle
{
    NSRange r = [_title rangeOfString:@" — Russian subtitles"];
    if (r.location == NSNotFound) r = [_title rangeOfString:@" - Russian subtitles"];
    if (r.location == NSNotFound) r = [_title rangeOfString:@" -- Russian subtitles"];
    return r.location == NSNotFound ? _title : [_title substringToIndex:r.location];
}

static BOOL RSHasWord(NSString *s, NSString *word)
{
    return [s rangeOfString:word options:NSCaseInsensitiveSearch].location != NSNotFound;
}

+ (NSString *)inferredKindForChannel:(NSString *)channel title:(NSString *)title
{
    channel = channel ?: @"";
    title = title ?: @"";
    if (RSHasWord(channel, @"Easy Russian")) return RSKindFast;
    if (RSHasWord(channel, @"Comprehensible Russian")) return RSKindEasy;
    static NSString *const easy[] = { @"Level A1", @"Level A2", @"TPRS", @"Complete Beginners", @"Short Stories",
                                      @"Story in Easy Russian", @"Stories in Easy Russian", @"for Beginners" };
    for (size_t i = 0; i < sizeof easy / sizeof easy[0]; i++)
        if (RSHasWord(title, easy[i])) return RSKindEasy;
    return RSKindNatural;
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
@property (nonatomic, readwrite, copy) NSDictionary *subtitleHashes;
@end

static BOOL RSIsSHA256Hex(NSString *s)
{
    if ([s length] != 64) return NO;
    for (NSUInteger i = 0; i < 64; i++) {
        unichar c = [s characterAtIndex:i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return NO;
    }
    return YES;
}

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
    [_subtitleHashes release];
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
    NSMutableDictionary *hashes = [NSMutableDictionary dictionary];
    NSUInteger count = 0;
    NSString *kind = nil;          // the last "# kind:" seen, for the videos after it

    for (NSUInteger i = 0; i < [lines count]; i++) {
        NSString *line = RSTrim([lines objectAtIndex:i]);
        NSUInteger number = i + 1;
        if ([line length] == 0) continue;
        if ([line hasPrefix:@"#"]) {
            NSString *k = RSKindInComment(line);
            if (k) kind = k;
            continue;
        }
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
            [video setKind:kind];
            [videos addObject:video];
        } else if ([key isEqualToString:@"subtitles"]) {
            NSArray *parts = [[value componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
                              filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
            NSString *identifier = [parts count] ? [parts objectAtIndex:0] : @"";
            NSString *hex = [parts count] > 1 ? [[parts objectAtIndex:1] lowercaseString] : @"";
            if ([parts count] != 2 || ![RSVideo isValidIdentifier:identifier] || !RSIsSHA256Hex(hex)) {
                *problem = [NSString stringWithFormat:@"Line %lu: subtitles are “id <sha-256 in hex>”.", (unsigned long)number];
                return nil;
            }
            if ([hashes objectForKey:identifier]) {
                *problem = [NSString stringWithFormat:@"Line %lu: %@ has subtitles twice.", (unsigned long)number, identifier];
                return nil;
            }
            [hashes setObject:hex forKey:identifier];
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
    for (NSString *identifier in hashes)
        if (![seen containsObject:identifier]) {
            *problem = [NSString stringWithFormat:@"Subtitles for %@, which isn’t on the shelf.", identifier];
            return nil;
        }
    RSShelf *shelf = [[[RSShelf alloc] init] autorelease];
    [shelf setStart:start];
    [shelf setStartText:startText];
    [shelf setSealed:sealed];
    [shelf setVideos:videos];
    [shelf setSubtitleHashes:hashes];
    return shelf;
}

- (NSString *)text
{
    NSMutableString *s = [NSMutableString stringWithFormat:@"%@\nstart: %@\n", RSPlainHeader, _startText];
    if (_sealed) [s appendFormat:@"sealed: %@\n", _sealed];
    NSString *kind = nil;
    for (RSVideo *v in _videos) {
        // A kind line only where the kind changes, so a list without them
        // reads back as it was.
        if ([v kind] && ![[v kind] isEqualToString:kind]) {
            kind = [v kind];
            [s appendFormat:@"# kind: %@\n", kind];
        }
        [s appendFormat:@"video: %@ | %@ | %@\n", [v identifier], [v channel], [v title]];
    }
    for (RSVideo *v in _videos)
        if ([_subtitleHashes objectForKey:[v identifier]])
            [s appendFormat:@"subtitles: %@ %@\n", [v identifier], [_subtitleHashes objectForKey:[v identifier]]];
    return s;
}

- (RSShelf *)shelfSealedAt:(NSString *)sealed
{
    RSShelf *copy = [[[RSShelf alloc] init] autorelease];
    [copy setStart:_start];
    [copy setStartText:_startText];
    [copy setSealed:sealed];
    [copy setVideos:_videos];
    [copy setSubtitleHashes:_subtitleHashes];
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

- (BOOL)fillKinds:(NSDictionary *)kinds
{
    BOOL changed = NO;
    for (RSVideo *v in _videos) {
        if ([v kind]) continue;
        NSString *k = [kinds objectForKey:[v identifier]];
        if (![RSKinds() containsObject:k]) k = [RSVideo inferredKindForChannel:[v channel] title:[v title]];
        [v setKind:k];
        changed = YES;
    }
    return changed;
}

- (NSArray *)videosOfKind:(NSString *)kind
{
    NSMutableArray *found = [NSMutableArray array];
    for (RSVideo *v in _videos)
        if (kind ? [[v kind] isEqualToString:kind] : [v kind] == nil) [found addObject:v];
    return found;
}

- (BOOL)isNewerThan:(RSShelf *)other
{
    if (other == nil) return YES;
    if (_start != [other start]) return _start > [other start];
    return [(_sealed ?: @"") compare:([other sealed] ?: @"")] == NSOrderedDescending;
}

@end

NSDictionary *RSKindsFromHistory(NSString *text)
{
    NSMutableDictionary *kinds = [NSMutableDictionary dictionary];
    NSString *kind = nil;
    for (NSString *raw in [[text ?: @"" stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] componentsSeparatedByString:@"\n"]) {
        NSString *line = RSTrim(raw);
        if ([line length] == 0) continue;
        if ([line hasPrefix:@"#"]) {
            kind = RSKindInComment(line) ?: kind;
            continue;
        }
        NSArray *parts = [line componentsSeparatedByString:@"|"];
        NSString *identifier = [parts count] ? RSTrim([parts objectAtIndex:0]) : nil;
        if (kind && [RSVideo isValidIdentifier:identifier]) [kinds setObject:kind forKey:identifier];
    }
    return kinds;
}

NSData *RSSignedMessage(NSData *iv, NSData *ciphertext)
{
    NSMutableData *message = [NSMutableData data];
    [message appendData:[[RSSealedHeader stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    [message appendData:iv];
    [message appendData:ciphertext];
    return message;
}

NSString *RSSHA256Hex(NSData *data)
{
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256([data bytes], (CC_LONG)[data length], digest);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

static NSString *RSFingerprint(NSData *file)
{
    return [RSSHA256Hex(file) substringToIndex:16];
}

NSData *RSSealText(NSString *text, NSData *aesKey, NSData *iv,
                   NSData *(^sign)(NSData *message, NSString **problem), NSString **problem)
{
    *problem = nil;
    NSData *plain = [text dataUsingEncoding:NSUTF8StringEncoding];
    NSData *ciphertext = RSAESCTR(plain, aesKey, iv);
    if (ciphertext == nil) { *problem = @"Encryption failed."; return nil; }
    NSData *signature = sign(RSSignedMessage(iv, ciphertext), problem);
    if (signature == nil) return nil;
    NSString *file = [NSString stringWithFormat:@"%@\niv: %@\ndata: %@\nsignature: %@\n", RSSealedHeader,
                      [iv base64EncodedStringWithOptions:0], [ciphertext base64EncodedStringWithOptions:0],
                      [signature base64EncodedStringWithOptions:0]];
    return [file dataUsingEncoding:NSUTF8StringEncoding];
}

NSData *RSSealShelf(RSShelf *shelf, NSData *aesKey, NSData *iv,
                    NSData *(^sign)(NSData *message, NSString **problem), NSString **problem)
{
    *problem = nil;
    if ([shelf sealed] == nil) { *problem = @"The shelf has no sealed time."; return nil; }
    return RSSealText([shelf text], aesKey, iv, sign, problem);
}

NSString *RSOpenSealedText(NSData *file, NSData *aesKey, NSData *publicKey, NSString **fingerprint, NSString **problem)
{
    *problem = nil;
    if (fingerprint) *fingerprint = nil;
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
    if (fingerprint) *fingerprint = RSFingerprint(file);
    return list;
}

RSShelf *RSOpenSealedShelf(NSData *file, NSData *aesKey, NSData *publicKey, NSString **problem)
{
    NSString *fingerprint = nil;
    NSString *list = RSOpenSealedText(file, aesKey, publicKey, &fingerprint, problem);
    if (list == nil) return nil;
    RSShelf *shelf = [RSShelf shelfWithText:list problem:problem];
    if (shelf == nil) return nil;
    if ([shelf sealed] == nil) {
        *problem = @"It has no sealed time.";
        return nil;
    }
    [shelf setFingerprint:fingerprint];
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
