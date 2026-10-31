#import "RSSyncFolder.h"
#import "RSSync.h"
#import "RSProcess.h"
#import "RSReport.h"

static const int RSPublishTries = 3;
static const NSTimeInterval RSGitTimeout = 120;

// RSSync's own helpers (RSSync.m): the same environment, the same patience
// with Syllabus's locks.
@interface RSSync (RSSyncFolder)
+ (NSDictionary *)environmentForGit:(NSString *)git;
+ (RSProcessResult *)git:(NSString *)git in:(NSString *)folder args:(NSArray *)args extra:(NSDictionary *)extra;
+ (RSProcessResult *)patientGit:(NSString *)git in:(NSString *)folder args:(NSArray *)args;
+ (RSSyncResult *)checkFolder:(NSString *)folder git:(NSString *)git;
@end

static RSSyncResult *RSFolderResult(BOOL ok, BOOL changed, NSString *summary, NSString *output)
{
    RSSyncResult *r = [[[RSSyncResult alloc] init] autorelease];
    [r setOk:ok];
    [r setChanged:changed];
    [r setSummary:summary];
    [r setOutput:output ?: @""];
    return r;
}

static NSString *RSTrim(NSString *s)
{
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *RSOutput(RSProcessResult *r)
{
    return [r status] == 0 ? RSTrim([r output]) : nil;
}

static BOOL RSSays(NSString *haystack, NSString *needle)
{
    return [[haystack lowercaseString] rangeOfString:needle].location != NSNotFound;
}

@implementation RSSyncFolder

+ (NSString *)slugForName:(NSString *)name
{
    NSMutableString *latin = [NSMutableString stringWithString:name ?: @""];
    CFStringTransform((CFMutableStringRef)latin, NULL, kCFStringTransformToLatin, false);
    CFStringTransform((CFMutableStringRef)latin, NULL, kCFStringTransformStripCombiningMarks, false);
    NSMutableString *slug = [NSMutableString string];
    BOOL gap = NO;
    for (NSUInteger i = 0; i < [latin length]; i++) {
        unichar c = [latin characterAtIndex:i];
        if (c == '\'' || c == 0x2019 || c == 0x02BC) continue;     // "Ashwin’s": one word
        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z')) {
            if (gap && [slug length]) [slug appendString:@"-"];
            gap = NO;
            [slug appendFormat:@"%C", (unichar)(c >= 'A' && c <= 'Z' ? c + 32 : c)];
        } else {
            gap = YES;
        }
        if ([slug length] >= 40) break;
    }
    while ([slug hasSuffix:@"-"]) [slug deleteCharactersInRange:NSMakeRange([slug length] - 1, 1)];
    return [slug length] ? slug : @"mac";
}

+ (NSString *)hostSlug
{
    return [self slugForName:RSComputerName()];
}

+ (NSString *)syncFolder
{
    return @"Russian/Sync";
}

+ (NSString *)pathForHost:(NSString *)slug
{
    return [[self syncFolder] stringByAppendingPathComponent:slug];
}

+ (BOOL)isStagingPath:(NSString *)relative
{
    NSArray *parts = [relative componentsSeparatedByString:@"/"];
    if ([relative length] == 0 || [parts count] > 3) return NO;
    // Letters and digits of any script: a word's card is named for the word.
    NSMutableCharacterSet *allowed = [[[NSCharacterSet alphanumericCharacterSet] mutableCopy] autorelease];
    [allowed addCharactersInString:@"._-"];
    for (NSString *part in parts)
        if ([part length] == 0 || [part length] > 100 || [part hasPrefix:@"."] ||
            [part rangeOfCharacterFromSet:[allowed invertedSet]].location != NSNotFound)
            return NO;
    return YES;
}

+ (NSArray *)filesIn:(NSString *)staging
{
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL folder = NO;
    if (![fm fileExistsAtPath:staging isDirectory:&folder] || !folder) return nil;
    NSMutableArray *files = [NSMutableArray array];
    for (NSString *relative in [fm subpathsOfDirectoryAtPath:staging error:NULL]) {
        BOOL isFolder = NO;
        [fm fileExistsAtPath:[staging stringByAppendingPathComponent:relative] isDirectory:&isFolder];
        // Composed, as the cards' keys are (HFS+ gives names back decomposed).
        relative = [relative precomposedStringWithCanonicalMapping];
        if (!isFolder && [self isStagingPath:relative]) [files addObject:relative];
    }
    return [files sortedArrayUsingSelector:@selector(compare:)];
}

// git with a file on stdin.
+ (RSProcessResult *)git:(NSString *)git in:(NSString *)folder args:(NSArray *)args extra:(NSDictionary *)extra
                   stdin:(NSString *)input
{
    NSMutableDictionary *env = [[[RSSync environmentForGit:git] mutableCopy] autorelease];
    if (extra) [env addEntriesFromDictionary:extra];
    return [RSProcess run:[[NSArray arrayWithObject:git] arrayByAddingObjectsFromArray:args]
              environment:env directory:folder stdin:input timeout:RSGitTimeout handle:nil line:nil];
}

+ (RSSyncResult *)publish:(NSString *)staging host:(NSString *)slug folder:(NSString *)folder
{
    NSString *git = [RSSync gitPath];
    RSSyncResult *early = [RSSync checkFolder:folder git:git];
    if (early) return early;
    if ([slug length] == 0 || ![[self slugForName:slug] isEqualToString:slug])
        return RSFolderResult(NO, NO, [NSString stringWithFormat:@"“%@” isn’t a Mac’s folder name.", slug], nil);
    NSArray *files = [self filesIn:staging];
    if (files == nil) return RSFolderResult(NO, NO, @"There was nothing ready to sync.", nil);
    NSString *prefix = [self pathForHost:slug];

    // Which remote branch this clone follows (as RSSync's pushReports).
    NSString *branch = RSOutput([RSSync git:git in:folder args:[NSArray arrayWithObjects:@"symbolic-ref", @"--short", @"HEAD", nil] extra:nil]);
    NSString *remote = branch ? RSOutput([RSSync git:git in:folder args:[NSArray arrayWithObjects:@"config", @"--get",
                                          [NSString stringWithFormat:@"branch.%@.remote", branch], nil] extra:nil]) : nil;
    NSString *merge = branch ? RSOutput([RSSync git:git in:folder args:[NSArray arrayWithObjects:@"config", @"--get",
                                         [NSString stringWithFormat:@"branch.%@.merge", branch], nil] extra:nil]) : nil;
    if ([remote length] == 0 || ![merge hasPrefix:@"refs/heads/"])
        return RSFolderResult(NO, NO, @"The study folder doesn’t know which branch to push to.", nil);
    NSString *tracking = [NSString stringWithFormat:@"refs/remotes/%@/%@", remote, [merge substringFromIndex:11]];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *scratch = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"russian-shelf-sync-%d", getpid()]];
    [fm removeItemAtPath:scratch error:NULL];
    [fm createDirectoryAtPath:scratch withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *indexFile = [scratch stringByAppendingPathComponent:@"index"];
    NSDictionary *privateIndex = [NSDictionary dictionaryWithObject:indexFile forKey:@"GIT_INDEX_FILE"];
    RSSyncResult *result = nil;

    // Every file's blob, once: they stay good whatever the remote does.
    NSMutableString *paths = [NSMutableString string];
    for (NSString *relative in files) [paths appendFormat:@"%@\n", [staging stringByAppendingPathComponent:relative]];
    NSString *pathsFile = [scratch stringByAppendingPathComponent:@"paths"];
    [paths writeToFile:pathsFile atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSMutableArray *blobs = [NSMutableArray array];
    if ([files count]) {
        RSProcessResult *r = [self git:git in:folder args:[NSArray arrayWithObjects:@"hash-object", @"-w", @"--no-filters",
                                                           @"--stdin-paths", nil] extra:nil stdin:pathsFile];
        for (NSString *line in [[r output] componentsSeparatedByString:@"\n"]) {
            NSString *l = RSTrim(line);
            if ([l length] == 40 && [l rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:
                                                                  @"0123456789abcdef"] invertedSet]].location == NSNotFound)
                [blobs addObject:l];
        }
        if ([r status] != 0 || [blobs count] != [files count]) {
            [fm removeItemAtPath:scratch error:NULL];
            return RSFolderResult(NO, NO, @"git couldn’t store what was to be synced.", [r output]);
        }
    }
    NSMutableString *info = [NSMutableString string];
    for (NSUInteger i = 0; i < [files count]; i++)
        [info appendFormat:@"100644 %@\t%@/%@\n", [blobs objectAtIndex:i], prefix, [files objectAtIndex:i]];
    NSString *infoFile = [scratch stringByAppendingPathComponent:@"index-info"];
    [info writeToFile:infoFile atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSString *goneFile = [scratch stringByAppendingPathComponent:@"gone"];

    for (int attempt = 0; attempt < RSPublishTries && result == nil; attempt++) {
        RSProcessResult *r = [RSSync patientGit:git in:folder args:[NSArray arrayWithObjects:@"fetch", @"--quiet", remote, nil]];
        if ([r status] != 0) { result = [RSSync resultForStatus:[r status] output:[r output] timedOut:[r timedOut]]; break; }
        NSString *base = RSOutput([RSSync git:git in:folder args:[NSArray arrayWithObjects:@"rev-parse", @"--verify",
                                   [tracking stringByAppendingString:@"^{commit}"], nil] extra:nil]);
        NSString *baseTree = [base length] ? RSOutput([RSSync git:git in:folder args:[NSArray arrayWithObjects:@"rev-parse",
                                   @"--verify", [base stringByAppendingString:@"^{tree}"], nil] extra:nil]) : nil;
        if ([baseTree length] == 0) { result = RSFolderResult(NO, NO, @"The remote branch couldn’t be found.", nil); break; }

        // The remote branch, then this Mac's folder in it emptied and filled
        // again from the staging folder.
        [fm removeItemAtPath:indexFile error:NULL];
        r = [RSSync git:git in:folder args:[NSArray arrayWithObjects:@"read-tree", base, nil] extra:privateIndex];
        if ([r status] != 0) { result = RSFolderResult(NO, NO, @"git couldn’t read the remote branch.", [r output]); break; }
        r = [RSSync git:git in:folder args:[NSArray arrayWithObjects:@"ls-files", @"-z", @"--", prefix, nil] extra:privateIndex];
        if ([r status] != 0) { result = RSFolderResult(NO, NO, @"git couldn’t list this Mac’s folder.", [r output]); break; }
        [[[r output] dataUsingEncoding:NSUTF8StringEncoding] writeToFile:goneFile atomically:YES];
        if ([[r output] length]) {
            r = [self git:git in:folder args:[NSArray arrayWithObjects:@"update-index", @"--force-remove", @"-z", @"--stdin", nil]
                    extra:privateIndex stdin:goneFile];
            if ([r status] != 0) { result = RSFolderResult(NO, NO, @"git couldn’t empty this Mac’s folder.", [r output]); break; }
        }
        if ([files count]) {
            r = [self git:git in:folder args:[NSArray arrayWithObjects:@"update-index", @"--index-info", nil]
                    extra:privateIndex stdin:infoFile];
            if ([r status] != 0) { result = RSFolderResult(NO, NO, @"git couldn’t add what was to be synced.", [r output]); break; }
        }
        r = [RSSync git:git in:folder args:[NSArray arrayWithObject:@"write-tree"] extra:privateIndex];
        NSString *tree = RSOutput(r);
        if ([tree length] == 0) { result = RSFolderResult(NO, NO, @"git couldn’t make the commit.", [r output]); break; }
        if ([tree isEqualToString:baseTree]) {
            result = RSFolderResult(YES, NO, @"Synced with the other Mac.", nil);
            break;
        }
        NSString *message = [NSString stringWithFormat:@"Shelf: what was done on %@\n\n%@/\n", slug, prefix];
        r = [RSSync git:git in:folder args:[NSArray arrayWithObjects:@"commit-tree", tree, @"-p", base, @"-m", message, nil] extra:nil];
        NSString *commit = RSOutput(r);
        if ([commit length] == 0) { result = RSFolderResult(NO, NO, @"git couldn’t make the commit.", [r output]); break; }

        // The commit may change this Mac's folder and nothing else.
        r = [RSSync git:git in:folder args:[NSArray arrayWithObjects:@"diff-tree", @"-z", @"--no-commit-id", @"--name-status",
                                            @"-r", base, commit, nil] extra:nil];
        NSArray *fields = [[r output] componentsSeparatedByString:@"\0"];
        BOOL inside = [r status] == 0 && [fields count] > 1;
        for (NSUInteger i = 0; inside && i + 1 < [fields count]; i += 2)
            inside = [[fields objectAtIndex:i + 1] hasPrefix:[prefix stringByAppendingString:@"/"]];
        if (!inside) {
            result = RSFolderResult(NO, NO, [NSString stringWithFormat:@"The sync’s commit would have changed more than %@. Nothing was sent.", prefix],
                                    [r output]);
            break;
        }

        r = [RSSync git:git in:folder args:[NSArray arrayWithObjects:@"push", @"--quiet", remote,
                                            [NSString stringWithFormat:@"%@:%@", commit, merge], nil] extra:nil];
        if ([r status] == 0) {
            RSSyncResult *pulled = [RSSync pullFolder:folder];
            result = RSFolderResult(YES, YES, [pulled ok] ? @"Synced with the other Mac."
                                                          : [NSString stringWithFormat:@"Synced with the other Mac. Then: %@", [pulled summary]],
                                    [r output]);
            break;
        }
        // Raced with the other Mac's push: fetch and build on that.
        BOOL raced = RSSays([r output], @"fetch first") || RSSays([r output], @"non-fast-forward") || RSSays([r output], @"[rejected]");
        if (!raced || attempt + 1 == RSPublishTries)
            result = [RSSync resultForStatus:[r status] output:[r output] timedOut:[r timedOut]];
    }
    [fm removeItemAtPath:scratch error:NULL];
    return result;
}

+ (NSDictionary *)entriesAt:(NSString *)rev folder:(NSString *)folder
{
    NSString *git = [RSSync gitPath];
    if ([RSSync checkFolder:folder git:git] || [rev length] == 0) return nil;
    NSString *prefix = [[self syncFolder] stringByAppendingString:@"/"];
    // "040000 tree <id>\tRussian/Sync/<name>", NUL-terminated; nothing for a missing folder.
    RSProcessResult *r = [RSSync git:git in:folder args:[NSArray arrayWithObjects:@"ls-tree", @"-z", rev, prefix, nil] extra:nil];
    if ([r status] != 0) return nil;
    NSMutableDictionary *entries = [NSMutableDictionary dictionary];
    for (NSString *entry in [[r output] componentsSeparatedByString:@"\0"]) {
        NSRange tab = [entry rangeOfString:@"\t"];
        if (tab.location == NSNotFound) continue;
        NSArray *fields = [[entry substringToIndex:tab.location] componentsSeparatedByString:@" "];
        NSString *path = [entry substringFromIndex:NSMaxRange(tab)];
        if ([fields count] != 3 || ![path hasPrefix:prefix]) continue;
        [entries setObject:[fields objectAtIndex:2] forKey:[path substringFromIndex:[prefix length]]];
    }
    return entries;
}

+ (BOOL)copyOtherHosts:(NSString *)slug from:(NSString *)folder into:(NSString *)destination problem:(NSString **)problem
{
    NSString *git = [RSSync gitPath];
    RSSyncResult *early = [RSSync checkFolder:folder git:git];
    if (early) { if (problem) *problem = [early summary]; return NO; }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *fresh = [destination stringByAppendingString:@" (new)"];
    NSString *tar = [destination stringByAppendingString:@".tar"];
    [fm removeItemAtPath:fresh error:NULL];
    [fm createDirectoryAtPath:fresh withIntermediateDirectories:YES attributes:nil error:NULL];

    NSString *tree = [@"HEAD:" stringByAppendingString:[self syncFolder]];
    BOOL any = [[RSSync git:git in:folder args:[NSArray arrayWithObjects:@"cat-file", @"-e", tree, nil] extra:nil] status] == 0;
    if (any) {
        RSProcessResult *r = [RSSync git:git in:folder args:[NSArray arrayWithObjects:@"archive", @"--format=tar",
                                                             @"-o", tar, tree, nil] extra:nil];
        if ([r status] == 0)
            r = [RSProcess run:[NSArray arrayWithObjects:@"/usr/bin/tar", @"-x", @"-f", tar, @"-C", fresh, nil]
                   environment:nil directory:nil stdin:nil timeout:RSGitTimeout handle:nil line:nil];
        [fm removeItemAtPath:tar error:NULL];
        if ([r status] != 0) {
            [fm removeItemAtPath:fresh error:NULL];
            if (problem) *problem = [NSString stringWithFormat:@"The other Mac’s things couldn’t be read: %@", RSTrim([r output])];
            return NO;
        }
        [fm removeItemAtPath:[fresh stringByAppendingPathComponent:slug] error:NULL];
        // Folders that can't be a host's are no one's.
        for (NSString *name in [fm contentsOfDirectoryAtPath:fresh error:NULL])
            if (![[self slugForName:name] isEqualToString:name])
                [fm removeItemAtPath:[fresh stringByAppendingPathComponent:name] error:NULL];
    }
    [fm removeItemAtPath:destination error:NULL];
    if (![fm moveItemAtPath:fresh toPath:destination error:NULL]) {
        [fm removeItemAtPath:fresh error:NULL];
        if (problem) *problem = @"The other Mac’s things couldn’t be put in place.";
        return NO;
    }
    return YES;
}

@end
