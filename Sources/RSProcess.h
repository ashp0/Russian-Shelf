// Runs a helper program (git, the bundled Python running yt-dlp) the way
// Syllabus runs git (SYSync.m): in its own process group, with no terminal
// and nothing on stdin, so it can't stop and ask for anything; killed with
// everything it started if it runs past its time or is cancelled.

#import <Foundation/Foundation.h>

@interface RSProcessResult : NSObject
@property (nonatomic) int status;            // exit status; 128 + signal if killed
@property (nonatomic) BOOL timedOut, cancelled;
@property (nonatomic, copy) NSString *output;    // stdout and stderr together (the last 256 KB)
@end

@interface RSProcess : NSObject

// Runs synchronously on the calling (background) thread. `directory` is
// where it starts (nil: this process's). `stdinPath` feeds stdin (nil:
// /dev/null). `line` gets each line of output as it comes, on that thread.
+ (RSProcessResult *)run:(NSArray *)arguments
             environment:(NSDictionary *)environment
               directory:(NSString *)directory
                   stdin:(NSString *)stdinPath
                 timeout:(NSTimeInterval)timeout
                  handle:(RSProcess *)handle
                    line:(void (^)(NSString *line))line;

// Something to cancel a run with, from any thread.
- (void)cancel;
@property (nonatomic, readonly) BOOL isCancelled;

@end
