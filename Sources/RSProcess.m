#import "RSProcess.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static const NSUInteger RSProcessMaxOutput = 256 * 1024;

@implementation RSProcessResult

- (void)dealloc
{
    [_output release];
    [super dealloc];
}

@end

// strdup'd C strings in a NULL-terminated array, for posix_spawn.
static char **RSCStrings(NSArray *strings)
{
    char **out = calloc([strings count] + 1, sizeof(char *));
    if (out == NULL) return NULL;
    NSUInteger i = 0;
    for (NSString *s in strings) {
        const char *c = [s UTF8String];
        out[i++] = strdup(c ? c : "");
    }
    return out;
}

static void RSFreeCStrings(char **strings)
{
    if (strings == NULL) return;
    for (char **p = strings; *p; p++) free(*p);
    free(strings);
}

@interface RSProcess () {
    dispatch_queue_t _guard;
    pid_t _pid;             // the group to signal while running, else 0
    BOOL _cancelled;
}
@end

@implementation RSProcess

- (id)init
{
    if ((self = [super init])) _guard = dispatch_queue_create("russianshelf.process.guard", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (void)dealloc
{
    dispatch_release(_guard);
    [super dealloc];
}

- (void)cancel
{
    dispatch_sync(_guard, ^{
        _cancelled = YES;
        if (_pid > 0) kill(-_pid, SIGTERM);
    });
}

- (BOOL)isCancelled
{
    __block BOOL cancelled;
    dispatch_sync(_guard, ^{ cancelled = _cancelled; });
    return cancelled;
}

static RSProcessResult *RSResult(int status, NSString *output)
{
    RSProcessResult *r = [[[RSProcessResult alloc] init] autorelease];
    [r setStatus:status];
    [r setOutput:output ?: @""];
    return r;
}

+ (RSProcessResult *)run:(NSArray *)arguments
             environment:(NSDictionary *)environment
               directory:(NSString *)directory
                   stdin:(NSString *)stdinPath
                 timeout:(NSTimeInterval)timeout
                  handle:(RSProcess *)handle
                    line:(void (^)(NSString *))lineHandler
{
    RSProcess *own = handle ? [[handle retain] autorelease] : [[[RSProcess alloc] init] autorelease];
    if ([own isCancelled]) {
        RSProcessResult *r = RSResult(128 + SIGTERM, @"");
        [r setCancelled:YES];
        return r;
    }

    NSMutableArray *envStrings = [NSMutableArray array];
    for (NSString *key in environment)
        [envStrings addObject:[NSString stringWithFormat:@"%@=%@", key, [environment objectForKey:key]]];

    // sh does the cd: posix_spawn can't change directory on 10.9.
    NSMutableArray *argv = [NSMutableArray arrayWithObjects:@"/bin/sh", @"-c",
                            @"cd \"$1\" || exit 97; shift; exec \"$@\"", @"russian-shelf",
                            directory ?: @"/", nil];
    [argv addObjectsFromArray:arguments];
    char **cargv = RSCStrings(argv);
    char **cenvp = RSCStrings(envStrings);
    int fds[2] = { -1, -1 };
    if (cargv == NULL || cenvp == NULL || pipe(fds) != 0) {
        RSFreeCStrings(cargv);
        RSFreeCStrings(cenvp);
        return RSResult(126, @"out of resources");
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, 0, stdinPath ? [stdinPath fileSystemRepresentation] : "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_adddup2(&actions, fds[1], 1);
    posix_spawn_file_actions_adddup2(&actions, fds[1], 2);

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    // Its own process group, so a timeout can stop it and whatever it starts
    // (ssh under git, ffmpeg and QuickJS under yt-dlp); default signal
    // handling and no inherited descriptors besides 0, 1, 2.
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF |
                                    POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT);
    posix_spawnattr_setpgroup(&attr, 0);
    sigset_t defaults, mask;
    sigfillset(&defaults);
    sigdelset(&defaults, SIGKILL);
    sigdelset(&defaults, SIGSTOP);
    sigemptyset(&mask);
    posix_spawnattr_setsigdefault(&attr, &defaults);
    posix_spawnattr_setsigmask(&attr, &mask);

    __block pid_t pid = 0;
    __block int err = 0;
    // Spawn under the guard, so a cancel can't miss the process.
    dispatch_sync(own->_guard, ^{
        err = posix_spawn(&pid, "/bin/sh", &actions, &attr, cargv, cenvp);
        if (err == 0) own->_pid = pid;
    });
    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attr);
    RSFreeCStrings(cargv);
    RSFreeCStrings(cenvp);
    close(fds[1]);
    if (err != 0) {
        close(fds[0]);
        return RSResult(126, [NSString stringWithFormat:@"couldn’t start %@ (%s)", [arguments objectAtIndex:0], strerror(err)]);
    }
    if ([own isCancelled]) kill(-pid, SIGTERM);

    // The timeout and the reaping share one serial queue, so the process
    // group is never signalled after its leader's pid could be reused.
    __block BOOL finished = NO, timedOut = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), own->_guard, ^{
        if (finished) return;
        timedOut = YES;
        kill(-pid, SIGTERM);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), own->_guard, ^{
            if (!finished) kill(-pid, SIGKILL);
        });
    });

    NSMutableData *data = [NSMutableData data];
    NSMutableData *pending = [NSMutableData data];
    char buffer[4096];
    for (;;) {
        ssize_t n = read(fds[0], buffer, sizeof buffer);
        if (n > 0) {
            [data appendBytes:buffer length:(NSUInteger)n];
            if ([data length] > 2 * RSProcessMaxOutput)
                [data replaceBytesInRange:NSMakeRange(0, [data length] - RSProcessMaxOutput) withBytes:NULL length:0];
            if (lineHandler) {
                [pending appendBytes:buffer length:(NSUInteger)n];
                const char *bytes = [pending bytes];
                NSUInteger start = 0;
                for (NSUInteger i = 0; i < [pending length]; i++) {
                    if (bytes[i] != '\n' && bytes[i] != '\r') continue;
                    if (i > start) {
                        NSString *line = [[NSString alloc] initWithBytes:bytes + start length:i - start encoding:NSUTF8StringEncoding];
                        if (line) lineHandler(line);
                        [line release];
                    }
                    start = i + 1;
                }
                [pending replaceBytesInRange:NSMakeRange(0, start) withBytes:NULL length:0];
            }
            continue;
        }
        if (n < 0 && errno == EINTR) continue;
        break;
    }
    close(fds[0]);

    // Wait for the exit without reaping, close the window on the timer and
    // on cancel, then reap.
    siginfo_t info;
    while (waitid(P_PID, (id_t)pid, &info, WEXITED | WNOWAIT) == -1 && errno == EINTR) {}
    __block BOOL cancelled = NO;
    dispatch_sync(own->_guard, ^{
        finished = YES;
        own->_pid = 0;
        cancelled = own->_cancelled;
    });
    int status = 0;
    while (waitpid(pid, &status, 0) == -1 && errno == EINTR) {}

    if ([data length] > RSProcessMaxOutput)
        [data replaceBytesInRange:NSMakeRange(0, [data length] - RSProcessMaxOutput) withBytes:NULL length:0];
    NSString *output = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (output == nil) output = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    int code = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + (WIFSIGNALED(status) ? WTERMSIG(status) : 0);
    RSProcessResult *result = RSResult(code, output);
    [result setTimedOut:timedOut];
    [result setCancelled:cancelled];
    return result;
}

@end
