// Each Mac's own folder in the study repository, Russian/Sync/<host>/, kept
// equal to a staging folder on this Mac (RSSyncManager's "Sync Out"), the
// way RSSync sends reports: the commit is built in a private index on top of
// the remote branch, may change paths under Russian/Sync/<host>/ and nothing
// else (it adds, updates and deletes there), and is pushed; then an ordinary
// fast-forward pull brings it in. The clone's own index, working tree and
// branch are never touched, so Syllabus's pulls never find it diverged. A
// push the other Mac got in first is fetched and the commit built again on
// top of it. A key that can only read leaves everything as it was.
//
// The other way, every other Mac's folder is read out of the commit the
// clone is at (git archive), not from the working tree, which Syllabus may
// be in the middle of updating.
//
// Only git 1.9 forms (the Command Line Tools for 10.9): read-tree, ls-files
// -z, update-index --force-remove -z --stdin and --index-info, hash-object
// -w --stdin-paths, write-tree, commit-tree, diff-tree -z, push, archive -o.

#import <Foundation/Foundation.h>

@class RSSyncResult;

@interface RSSyncFolder : NSObject

// "Ashwin’s Mac Pro" -> "ashwins-mac-pro": letters and digits (Latin,
// lower case), runs of anything else one hyphen, at most 40 characters.
// "mac" if nothing is left.
+ (NSString *)slugForName:(NSString *)name;
+ (NSString *)hostSlug;                        // this Mac's: slugForName(RSComputerName())

+ (NSString *)syncFolder;                      // "Russian/Sync"
+ (NSString *)pathForHost:(NSString *)slug;    // "Russian/Sync/<slug>"
// A path a staging folder may hold: up to two folders deep, each part
// letters or digits (any script), '.', '_' or '-', never starting with a dot.
+ (BOOL)isStagingPath:(NSString *)relative;
// The files under `staging`, relative, sorted; those not isStagingPath are
// left out. nil if there's no such folder.
+ (NSArray *)filesIn:(NSString *)staging;

// Synchronous: call on a background thread. Makes Russian/Sync/<slug>/ hold
// exactly the files in `staging`; one commit, pushed, then pulled. Nothing
// pushed when nothing changed (`changed` is NO then).
+ (RSSyncResult *)publish:(NSString *)staging host:(NSString *)slug folder:(NSString *)studyFolder;

// Synchronous. Writes every host's folder but `slug`'s, from the clone's
// HEAD, into `destination` (made afresh: <destination>/<host>/...). NO, with
// *problem, if git couldn't; YES with an empty folder if there are none.
+ (BOOL)copyOtherHosts:(NSString *)slug from:(NSString *)studyFolder into:(NSString *)destination
               problem:(NSString **)problem;

@end
