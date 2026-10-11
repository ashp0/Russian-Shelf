#import "RSSync.h"
#import "RSProcess.h"

static const NSTimeInterval RSGitTimeout = 120;
static NSTimeInterval RSLockRetryDelay = 4;
static const int RSLockTries = 6;            // about twenty seconds of someone else's git
static const int RSPushTries = 3;

@implementation RSSyncResult

- (void)dealloc
{
    [_summary release];
    [_output release];
    [super dealloc];
}

@end

static RSSyncResult *RSResult(BOOL ok, BOOL changed, NSString *summary, NSString *output)
{
    RSSyncResult *r = [[[RSSyncResult alloc] init] autorelease];
    [r setOk:ok];
    [r setChanged:changed];
    [r setSummary:summary];
    [r setOutput:output ?: @""];
    return r;
}

static BOOL RSHas(NSString *haystack, NSString *needle)
{
    return [haystack rangeOfString:needle].location != NSNotFound;
}

static NSString *RSTrimmed(NSString *s)
{
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@implementation RSSync

+ (void)setLockRetryDelay:(NSTimeInterval)seconds
{
    RSLockRetryDelay = seconds;
}

+ (NSString *)gitPath
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *candidates = [NSMutableArray array];
    NSString *chosen = [[NSUserDefaults standardUserDefaults] stringForKey:@"GitPath"];
    if ([chosen length]) [candidates addObject:[chosen stringByExpandingTildeInPath]];
    // MacPorts and the git.org installer bring their own, newer TLS; the
    // Command Line Tools' git uses the system's.
    [candidates addObjectsFromArray:[NSArray arrayWithObjects:
        @"/opt/local/bin/git",
        @"/usr/local/bin/git",
        @"/usr/local/git/bin/git",
        @"/Library/Developer/CommandLineTools/usr/bin/git",
        @"/Applications/Xcode.app/Contents/Developer/usr/bin/git", nil]];
    for (NSString *path in candidates)
        if ([fm isExecutableFileAtPath:path]) return path;
    return nil;
}

+ (BOOL)isRepository:(NSString *)folder
{
    if ([folder length] == 0) return NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:[folder stringByAppendingPathComponent:@".git"]];
}

+ (NSString *)reportsFolder
{
    return @"Russian/Reports";
}

+ (BOOL)isReportPath:(NSString *)path
{
    NSString *prefix = [[self reportsFolder] stringByAppendingString:@"/"];
    if (![path hasPrefix:prefix]) return NO;
    NSString *name = [path substringFromIndex:[prefix length]];
    if ([name length] == 0 || [name length] > 100 || ![name hasSuffix:@".txt"] || [name hasPrefix:@"."]) return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"];
    return [name rangeOfCharacterFromSet:[allowed invertedSet]].location == NSNotFound &&
           [name rangeOfString:@".."].location == NSNotFound;
}

+ (BOOL)isLockContention:(NSString *)output
{
    NSString *o = [output lowercaseString] ?: @"";
    if (RSHas(o, @"another git process seems to be running")) return YES;
    if (RSHas(o, @"cannot lock ref")) return YES;
    return RSHas(o, @".lock") && (RSHas(o, @"unable to create") || RSHas(o, @"file exists"));
}

+ (RSSyncResult *)resultForStatus:(int)status output:(NSString *)output timedOut:(BOOL)timedOut
{
    NSString *o = [output lowercaseString] ?: @"";
    if (timedOut)
        return RSResult(NO, NO, @"Gave up after two minutes. The network may be slow or down.", output);
    if (status == 0) {
        BOOL same = RSHas(o, @"already up to date") || RSHas(o, @"already up-to-date");
        return RSResult(YES, !same, same ? @"Up to date." : @"Updated from the MacBook.", output);
    }
    if (status == 97)
        return RSResult(NO, NO, @"The study folder couldn’t be opened.", output);
    if (status == 126 || status == 127)
        return RSResult(NO, NO, @"git couldn’t be started.", output);

    NSArray *offline = [NSArray arrayWithObjects:@"could not resolve host", @"could not resolve hostname",
                        @"network is unreachable", @"no route to host", @"connection timed out",
                        @"operation timed out", @"failed to connect", @"connection refused",
                        @"couldn't connect", @"timed out", nil];
    for (NSString *s in offline)
        if (RSHas(o, s))
            return RSResult(NO, NO, @"Couldn’t reach the server. Is this Mac online?", output);
    if (RSHas(o, @"host key verification failed"))
        return RSResult(NO, NO, @"SSH doesn’t know github.com yet. Do the one-time step in Syllabus’s README.", output);
    if (RSHas(o, @"marked as read only") || RSHas(o, @"denied to deploy key") ||
        RSHas(o, @"write access to repository not granted") || (RSHas(o, @"permission to") && RSHas(o, @"denied"))) {
        RSSyncResult *r = RSResult(NO, NO, @"This Mac’s key can only read, so reports wait here until it can write.", output);
        [r setReadOnly:YES];
        return r;
    }
    if (RSHas(o, @"permission denied (publickey"))
        return RSResult(NO, NO, @"The server didn’t accept this Mac’s key. Check the deploy key (Syllabus’s README).", output);
    if (RSHas(o, @"authentication failed") || RSHas(o, @"could not read username") ||
        RSHas(o, @"could not read password") || RSHas(o, @"terminal prompts disabled"))
        return RSResult(NO, NO, @"The server wants a login this Mac hasn’t saved. See Syllabus’s README.", output);
    if (RSHas(o, @"repository not found") || RSHas(o, @"does not appear to be a git repository"))
        return RSResult(NO, NO, @"The server says the repository isn’t there, or this Mac isn’t allowed to see it.", output);
    if (RSHas(o, @"ssl") || RSHas(o, @"tls") || RSHas(o, @"certificate") || RSHas(o, @"handshake"))
        return RSResult(NO, NO, @"This Mac couldn’t make a secure HTTPS connection. Use the SSH address instead.", output);
    if (RSHas(o, @"would be overwritten")) {
        NSString *file = nil;
        BOOL listing = NO;
        for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
            if (RSHas([line lowercaseString], @"would be overwritten")) { listing = YES; continue; }
            if (listing && [line hasPrefix:@"\t"]) { file = RSTrimmed(line); break; }
        }
        NSString *summary = file
            ? [NSString stringWithFormat:@"“%@” was changed on this Mac and the update would replace it. Nothing was changed.", file]
            : @"A file changed on this Mac is in the update’s way. Nothing was changed.";
        return RSResult(NO, NO, summary, output);
    }
    if (RSHas(o, @"not possible to fast-forward") || RSHas(o, @"diverg") ||
        RSHas(o, @"non-fast-forward") || RSHas(o, @"refusing to merge"))
        return RSResult(NO, NO, @"This copy and the MacBook’s have gone separate ways. Nothing was changed; see Syllabus’s README.", output);
    if (RSHas(o, @"not a git repository"))
        return RSResult(NO, NO, @"The study folder isn’t a git repository.", output);
    if (RSHas(o, @"no tracking information"))
        return RSResult(NO, NO, @"The study folder doesn’t know which branch to pull.", output);
    if ([self isLockContention:output])
        return RSResult(NO, NO, @"Another git (Syllabus’s, perhaps) was busy in the study folder. Trying again later.", output);

    NSString *said = nil;
    for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
        NSString *l = RSTrimmed(line);
        if ([l hasPrefix:@"fatal: "]) said = [l substringFromIndex:7];
        else if ([l hasPrefix:@"error: "] && said == nil) said = [l substringFromIndex:7];
    }
    if ([said length])
        return RSResult(NO, NO, [NSString stringWithFormat:@"git said: %@", said], output);
    return RSResult(NO, NO, [NSString stringWithFormat:@"git stopped with status %d.", status], output);
}

// The environment every git here runs in: no prompts, plain English, our
// ssh, and a name for the commits this app makes.
+ (NSDictionary *)environmentForGit:(NSString *)git
{
    NSMutableDictionary *env = [[[[NSProcessInfo processInfo] environment] mutableCopy] autorelease];
    [env setObject:@"0" forKey:@"GIT_TERMINAL_PROMPT"];
    [env setObject:@"/usr/bin/false" forKey:@"GIT_ASKPASS"];
    [env setObject:@"/usr/bin/false" forKey:@"SSH_ASKPASS"];
    [env removeObjectForKey:@"DISPLAY"];
    [env removeObjectForKey:@"GIT_INDEX_FILE"];
    [env setObject:@"C" forKey:@"LC_ALL"];
    [env setObject:@"C" forKey:@"LANG"];
    [env setObject:@"1000" forKey:@"GIT_HTTP_LOW_SPEED_LIMIT"];
    [env setObject:@"30" forKey:@"GIT_HTTP_LOW_SPEED_TIME"];
    [env setObject:@"no" forKey:@"GIT_MERGE_AUTOEDIT"];
    for (NSString *who in [NSArray arrayWithObjects:@"AUTHOR", @"COMMITTER", nil]) {
        [env setObject:@"Russian Shelf (Mac Pro)" forKey:[NSString stringWithFormat:@"GIT_%@_NAME", who]];
        [env setObject:@"russian-shelf@mac-pro.local" forKey:[NSString stringWithFormat:@"GIT_%@_EMAIL", who]];
    }
    NSString *ssh = [[NSBundle mainBundle] pathForResource:@"shelf-ssh" ofType:nil];
    if (ssh && [env objectForKey:@"GIT_SSH"] == nil && [env objectForKey:@"GIT_SSH_COMMAND"] == nil)
        [env setObject:ssh forKey:@"GIT_SSH"];
    [env setObject:[NSString stringWithFormat:@"%@:/usr/bin:/bin:/usr/sbin:/sbin",
                    [git stringByDeletingLastPathComponent]] forKey:@"PATH"];
    return env;
}

+ (RSProcessResult *)git:(NSString *)git in:(NSString *)folder args:(NSArray *)args
                   extra:(NSDictionary *)extra
{
    NSMutableDictionary *env = [[[self environmentForGit:git] mutableCopy] autorelease];
    if (extra) [env addEntriesFromDictionary:extra];
    return [RSProcess run:[[NSArray arrayWithObject:git] arrayByAddingObjectsFromArray:args]
              environment:env directory:folder stdin:nil timeout:RSGitTimeout handle:nil line:nil];
}

// A git command that may meet Syllabus's git holding a lock: tried again a
// few times before giving up.
+ (RSProcessResult *)patientGit:(NSString *)git in:(NSString *)folder args:(NSArray *)args
{
    RSProcessResult *r = nil;
    for (int attempt = 0; attempt < RSLockTries; attempt++) {
        r = [self git:git in:folder args:args extra:nil];
        if ([r status] == 0 || [r timedOut] || ![self isLockContention:[r output]]) break;
        [NSThread sleepForTimeInterval:RSLockRetryDelay];
    }
    return r;
}

+ (RSSyncResult *)checkFolder:(NSString *)folder git:(NSString *)git
{
    if ([folder length] == 0)
        return RSResult(NO, NO, @"There’s no study folder.", nil);
    if (![self isRepository:folder])
        return RSResult(NO, NO, @"The study folder isn’t a git repository, so there’s nothing to pull.", nil);
    if (git == nil)
        return RSResult(NO, NO, @"git isn’t installed on this Mac. Syllabus’s README says how to get it.", nil);
    return nil;
}

+ (RSSyncResult *)pullFolder:(NSString *)folder
{
    NSString *git = [self gitPath];
    RSSyncResult *early = [self checkFolder:folder git:git];
    if (early) return early;
    RSProcessResult *r = [self patientGit:git in:folder args:[NSArray arrayWithObjects:@"pull", @"--ff-only", nil]];
    return [self resultForStatus:[r status] output:[r output] timedOut:[r timedOut]];
}

static NSString *RSOut(RSProcessResult *r)
{
    return [r status] == 0 ? RSTrimmed([r output]) : nil;
}

+ (RSSyncResult *)pushReports:(NSDictionary *)reports folder:(NSString *)folder
{
    NSString *git = [self gitPath];
    RSSyncResult *early = [self checkFolder:folder git:git];
    if (early) return early;
    if ([reports count] == 0) return RSResult(YES, NO, @"Nothing to report.", nil);
    for (NSString *name in reports)
        if (![self isReportPath:[[self reportsFolder] stringByAppendingPathComponent:name]])
            return RSResult(NO, NO, [NSString stringWithFormat:@"“%@” isn’t a report’s name.", name], nil);

    // Which remote branch this clone follows.
    NSString *branch = RSOut([self git:git in:folder args:[NSArray arrayWithObjects:@"symbolic-ref", @"--short", @"HEAD", nil] extra:nil]);
    NSString *remote = branch ? RSOut([self git:git in:folder args:[NSArray arrayWithObjects:@"config", @"--get",
                                       [NSString stringWithFormat:@"branch.%@.remote", branch], nil] extra:nil]) : nil;
    NSString *merge = branch ? RSOut([self git:git in:folder args:[NSArray arrayWithObjects:@"config", @"--get",
                                      [NSString stringWithFormat:@"branch.%@.merge", branch], nil] extra:nil]) : nil;
    if ([remote length] == 0 || ![merge hasPrefix:@"refs/heads/"])
        return RSResult(NO, NO, @"The study folder doesn’t know which branch to push to.", nil);
    NSString *tracking = [NSString stringWithFormat:@"refs/remotes/%@/%@", remote, [merge substringFromIndex:11]];

    NSString *scratch = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"russian-shelf-push-%d", getpid()]];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:scratch error:NULL];
    [fm createDirectoryAtPath:scratch withIntermediateDirectories:YES attributes:nil error:NULL];
    NSDictionary *privateIndex = [NSDictionary dictionaryWithObject:[scratch stringByAppendingPathComponent:@"index"]
                                                             forKey:@"GIT_INDEX_FILE"];
    RSSyncResult *result = nil;

    for (int attempt = 0; attempt < RSPushTries && result == nil; attempt++) {
        RSProcessResult *r = [self patientGit:git in:folder args:[NSArray arrayWithObjects:@"fetch", @"--quiet", remote, nil]];
        if ([r status] != 0) { result = [self resultForStatus:[r status] output:[r output] timedOut:[r timedOut]]; break; }
        NSString *base = RSOut([self git:git in:folder args:[NSArray arrayWithObjects:@"rev-parse", @"--verify",
                                [tracking stringByAppendingString:@"^{commit}"], nil] extra:nil]);
        if ([base length] == 0) { result = RSResult(NO, NO, @"The remote branch couldn’t be found.", nil); break; }

        [fm removeItemAtPath:[privateIndex objectForKey:@"GIT_INDEX_FILE"] error:NULL];
        r = [self git:git in:folder args:[NSArray arrayWithObjects:@"read-tree", base, nil] extra:privateIndex];
        if ([r status] != 0) {
            result = RSResult(NO, NO, @"git couldn’t read the remote branch.", [r output]);
            break;
        }
        NSMutableArray *added = [NSMutableArray array];
        for (NSString *name in [[reports allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            NSString *path = [[self reportsFolder] stringByAppendingPathComponent:name];
            NSString *temp = [scratch stringByAppendingPathComponent:name];
            [[reports objectForKey:name] writeToFile:temp atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            r = [self git:git in:folder args:[NSArray arrayWithObjects:@"hash-object", @"-w",
                                    @"--no-filters", temp, nil] extra:nil];
            NSString *blob = RSOut(r);
            BOOL exists = [[self git:git in:folder args:[NSArray arrayWithObjects:@"cat-file", @"-e",
                            [NSString stringWithFormat:@"%@:%@", base, path], nil] extra:nil] status] == 0;
            if ([blob length] == 0 || exists) {
                result = RSResult(NO, NO, exists ? [NSString stringWithFormat:@"%@ is already in the repository.", path]
                                                 : @"git couldn’t store the report.", exists ? nil : [r output]);
                break;
            }
            // Mode, blob and path as three arguments: the comma form
            // ("100644,<blob>,<path>") came in git 2.0, and the Command Line
            // Tools for 10.9 bring git 1.9 at the newest.
            r = [self git:git in:folder args:[NSArray arrayWithObjects:@"update-index", @"--add", @"--cacheinfo",
                                              @"100644", blob, path, nil] extra:privateIndex];
            if ([r status] != 0) {
                result = RSResult(NO, NO, @"git couldn’t add the report.", [r output]);
                break;
            }
            [added addObject:path];
        }
        if (result) break;
        r = [self git:git in:folder args:[NSArray arrayWithObject:@"write-tree"] extra:privateIndex];
        NSString *tree = RSOut(r);
        NSString *message = [NSString stringWithFormat:@"Russian Shelf: what was watched\n\n%@\n",
                             [added componentsJoinedByString:@"\n"]];
        if (tree) r = [self git:git in:folder args:[NSArray arrayWithObjects:@"commit-tree", tree,
                                                    @"-p", base, @"-m", message, nil] extra:nil];
        NSString *commit = tree ? RSOut(r) : nil;
        if ([commit length] == 0) { result = RSResult(NO, NO, @"git couldn’t make the commit.", [r output]); break; }

        // The commit may add these reports and nothing else.
        NSString *diff = RSOut([self git:git in:folder args:[NSArray arrayWithObjects:@"diff-tree", @"--no-commit-id",
                                @"--name-status", @"-r", base, commit, nil] extra:nil]);
        NSMutableSet *expected = [NSMutableSet set];
        for (NSString *path in added) [expected addObject:[@"A\t" stringByAppendingString:path]];
        NSSet *actual = [NSSet setWithArray:[diff componentsSeparatedByString:@"\n"]];
        if (diff == nil || ![actual isEqualToSet:expected]) {
            result = RSResult(NO, NO, @"The report’s commit would have changed more than Russian/Reports. Nothing was sent.", diff);
            break;
        }

        r = [self git:git in:folder args:[NSArray arrayWithObjects:@"push", @"--quiet", remote,
                                          [NSString stringWithFormat:@"%@:%@", commit, merge], nil] extra:nil];
        if ([r status] == 0) {
            RSSyncResult *pulled = [self pullFolder:folder];
            result = RSResult(YES, YES, [pulled ok] ? @"Sent what was watched to the MacBook."
                                                    : [NSString stringWithFormat:@"Sent what was watched. Then: %@", [pulled summary]],
                              [r output]);
            break;
        }
        NSString *o = [[r output] lowercaseString];
        BOOL raced = RSHas(o, @"fetch first") || RSHas(o, @"non-fast-forward") || RSHas(o, @"[rejected]");
        if (!raced || attempt + 1 == RSPushTries)
            result = [self resultForStatus:[r status] output:[r output] timedOut:[r timedOut]];
        // Raced with a push from the MacBook: fetch and build on that.
    }
    [fm removeItemAtPath:scratch error:NULL];
    return result;
}

@end
