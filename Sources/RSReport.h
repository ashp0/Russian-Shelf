// What was watched, for Claude: a small text file the app adds under
// Russian/Reports/ in the study repo (RSSync pushes it), one line a video.
//
//     Russian Shelf report
//     shelf: 2026-10-12 (sealed 2026-10-11 20:15:07)
//     written: 2026-10-14 21:05
//
//     JE4cI_Knzvc | finished | 11:30 of 11:30 | She Cut Her Hair to Save Her Husband
//     abcdefghijk | partly | 4:10 of 11:30 | The Wolf and the Seven Kids
//     lmnopqrstuv | not started | 0:00 of 9:12 | ...
//     wxyz0123456 | not downloaded | - | ...
//
//     Help (shown, heard again, looped, slowed, transcript, subtitles, looked up, kept):
//     JE4cI_Knzvc | shown 12 | heard again 8 | looped 2 | slowed 1 | transcript 1 | subtitles 0 | looked up 3 | kept 2
//
//     How it felt (the owner's own choice, about the video):
//     JE4cI_Knzvc | about right | more like this
//
//     Lines help was asked on:
//     JE4cI_Knzvc | 4:10 | shown 1, heard again 3, looped 1 | Она отрезала волосы.
//
//     Kept:
//     JE4cI_Knzvc | 4:10 | Она отрезала волосы. | means: She cut her hair.
//
//     Words kept (word (lemma) | gloss | the line):
//     JE4cI_Knzvc | 4:10 | отрезала (отре́зать) | cut off | in: Она отрезала волосы.
//
// "partly" gives the furthest point reached by playing (skipping ahead
// doesn't count). "from:" names the Mac that wrote it: each Mac keeps its own
// record of what was watched there, so the newest report from each Mac says
// it all for that Mac; older ones from the same Mac can be ignored. The help
// and later sections are there only when there's something to say: how
// often, and on which lines (so which verbs, endings, reductions), help was
// asked tells Claude whether the shelf is at the right level and what to
// look for next week; "how it felt" is the owner's own word on the video
// ("-" for a question left alone). At most RSReportLinesPerVideo lines a
// video. The app never shows any of these numbers.

#import <Foundation/Foundation.h>
#include <time.h>

@class RSShelf, RSLibrary, RSLines;

// "shelf-2026-10-12_2026-10-14-2105.txt": the shelf's start, then when.
NSString *RSReportName(RSShelf *shelf, time_t now);
extern const NSUInteger RSReportLinesPerVideo;      // 40
NSString *RSReportText(RSShelf *shelf, RSLibrary *library, RSLines *lines, time_t now);
// The same, with the owner's notes for the tutor (RSSay's Tutor.txt) at the end.
NSString *RSReportTextWithNotes(RSShelf *shelf, RSLibrary *library, RSLines *lines, NSString *tutor, time_t now);
// This Mac's name, as in Sharing ("Ashwin’s Mac Pro").
NSString *RSComputerName(void);
// "4:10", "1:02:03".
NSString *RSClock(double seconds);
// "2026-11-03", from a day number (RSDate.h).
NSString *RSDayNumberText(long day);
