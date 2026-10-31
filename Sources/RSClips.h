// Today's clip: two or three minutes of a video, worked in three passes
// (DESIGN.md): listen twice with no text; read it line by line with the
// captions on, looking words up; then say each line along with the speaker.
// Ten to fifteen minutes a day of the deliberate kind of listening (the
// research: bottom-up decoding, shadowing, words met on purpose).
//
// The stretch is chosen here, from the subtitles: it starts at the line the
// owner asked for most help on in earlier viewings (replayed, shown, looped,
// looked up) that no earlier clip covered, or else at the first line after the
// last clip worked; it ends at a sentence boundary two to three minutes on.

#import <Foundation/Foundation.h>

@class RSSubtitles;

@interface RSClipPlan : NSObject
@property (nonatomic, copy) NSString *video;
@property (nonatomic) double start, end;             // seconds, on line boundaries
@property (nonatomic) NSUInteger firstLine, lastLine; // indexes into the subtitles' lines
@end

extern const double RSClipShortest, RSClipLongest;    // 120 s, 180 s

// `helped`: RSLibrary's helpedLinesFor: (each {text, start, counts...});
// `worked`: earlier clips of this video, each {start, end} (NSNumber). nil if
// the video has no lines left to work.
RSClipPlan *RSChooseClip(NSString *video, RSSubtitles *subtitles, NSArray *helped, NSArray *worked);

// "2:10–4:40"
NSString *RSClipSpan(double start, double end);
