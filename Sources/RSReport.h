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
// "partly" gives the furthest point reached by playing (skipping ahead
// doesn't count). The newest report for a shelf says it all; older ones can
// be ignored.

#import <Foundation/Foundation.h>
#include <time.h>

@class RSShelf, RSLibrary;

// "shelf-2026-10-12_2026-10-14-2105.txt": the shelf's start, then when.
NSString *RSReportName(RSShelf *shelf, time_t now);
NSString *RSReportText(RSShelf *shelf, RSLibrary *library, time_t now);
// "4:10", "1:02:03".
NSString *RSClock(double seconds);
