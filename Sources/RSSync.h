// The study folder, over git: Syllabus's refresh (SYSync.m), shared.
//
// ~/Study is one clone that Syllabus pulls too, maybe at the same moment.
// Pulls are `git pull --ff-only`, exactly as Syllabus does them; if the other
// app holds a lock (index.lock, a ref's .lock), this waits and tries again.
//
// Reports go the other way without touching the clone's index, working tree
// or branch: the commit is built in a private index on top of the remote
// branch, checked to add exactly one file under Russian/Reports/ and nothing
// else, and pushed. Then an ordinary fast-forward pull brings it in. A push
// that fails (a read-only key, say) leaves the clone exactly as it was, so
// Syllabus's pulls never find a diverged branch.

#import <Foundation/Foundation.h>

@interface RSSyncResult : NSObject
@property (nonatomic) BOOL ok;
@property (nonatomic) BOOL changed;            // new commits arrived
@property (nonatomic) BOOL readOnly;           // a push the server refused for permissions
@property (nonatomic, copy) NSString *summary; // one plain sentence
@property (nonatomic, copy) NSString *output;  // what git said, for the log
@end

@interface RSSync : NSObject

// The git to run, or nil. Never /usr/bin/git: on a Mac without the Command
// Line Tools that is a stub that pops up an installer.
+ (NSString *)gitPath;
+ (BOOL)isRepository:(NSString *)folder;

// Synchronous: call on a background thread.
+ (RSSyncResult *)pullFolder:(NSString *)folder;
// Adds each file in `reports` (name -> text) under Russian/Reports/ in one
// commit and pushes it; then pulls. Nothing else in the repository changes.
+ (RSSyncResult *)pushReports:(NSDictionary *)reports folder:(NSString *)folder;

// Turns git's output and exit status into a sentence. Exposed for the tests.
+ (RSSyncResult *)resultForStatus:(int)status output:(NSString *)output timedOut:(BOOL)timedOut;
+ (BOOL)isLockContention:(NSString *)output;

// The only folder reports go in, and a check that a path is a report there.
+ (NSString *)reportsFolder;                   // "Russian/Reports"
+ (BOOL)isReportPath:(NSString *)path;

// Seconds between tries while another git holds a lock (tests shorten it).
+ (void)setLockRetryDelay:(NSTimeInterval)seconds;

@end
