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
//     Help (lines shown, heard again, kept):
//     JE4cI_Knzvc | shown 12 | heard again 8 | kept 2
//
//     Kept:
//     JE4cI_Knzvc | 4:10 | Она отрезала волосы.
//
// "partly" gives the furthest point reached by playing (skipping ahead
// doesn't count). "from:" names the Mac that wrote it: each Mac keeps its own
// record of what was watched there, so the newest report from each Mac says
// it all for that Mac; older ones from the same Mac can be ignored. The help
// and kept sections are there only when something was asked for or kept:
// how often a line had to be shown or heard again tells Claude whether the
// shelf is at the right level. The app never shows these numbers.

#import <Foundation/Foundation.h>
#include <time.h>

@class RSShelf, RSLibrary, RSLines;

// "shelf-2026-10-12_2026-10-14-2105.txt": the shelf's start, then when.
NSString *RSReportName(RSShelf *shelf, time_t now);
NSString *RSReportText(RSShelf *shelf, RSLibrary *library, RSLines *lines, time_t now);
// This Mac's host name, without ".local" ("Mac-Pro").
NSString *RSComputerName(void);
// "4:10", "1:02:03".
NSString *RSClock(double seconds);
