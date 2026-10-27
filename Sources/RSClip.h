// A line's sound, cut from its video into an .m4a of its own, so a kept line
// can be heard again after the video has left the shelf.
//
// AVAssetExportSession with the Apple M4A preset (OS X 10.7 and later): the
// audio only, from a little before the line starts to a little after it
// ends, so the first and last sounds aren't clipped.

#import <Foundation/Foundation.h>

extern const double RSClipLeadIn;       // seconds before the line (0.15)
extern const double RSClipTail;         // seconds after it (0.35)

// Calls done on the main queue: ok, or a sentence saying why not.
void RSCutClip(NSString *moviePath, double start, double end, NSString *outPath,
               void (^done)(BOOL ok, NSString *problem));

// The same, waiting for it (for the tests and the self-test; not on the main
// thread, since `done` goes there).
BOOL RSCutClipNow(NSString *moviePath, double start, double end, NSString *outPath, NSString **problem);

// How long a sound or movie file is, in seconds; 0 if it can't be read.
double RSMediaDuration(NSString *path);
