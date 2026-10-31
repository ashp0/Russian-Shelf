// Say: the speaking practice (DESIGN.md). Islands: a short list of topics
// the owner can talk about, in Russian, that they edit. 4/3/2 (Nation 1989;
// Arevart & Nation 1991): the same topic three times, shorter each time, so
// the second and third tellings come out faster and smoother; sized for
// A2-B1 as 2 min, 1½, 1 by default. Each pass is recorded through the
// built-in microphone. After the last pass the owner can hear it, write up
// to three things they noticed for their tutor, and once a month keep the
// recording to hear next to last month's (their own voice, two dates, no
// number).
//
// Everything lives in <app folder>/Say/:
//
//   Islands.txt            one topic a line (seeded the first time)
//   Tutor.txt              "## 2026-11-03" headings, a line a note
//   Today/pass-1.m4a ...   today's passes, gone at midnight (never synced)
//   Recordings/2026-11.m4a the month's recording: the last pass of the
//                          first Say of the month
//
// Which island is today's, the lengths, and what was done today are decided
// here; the window (RSSayWindow) only shows and records.

#import <Foundation/Foundation.h>

extern NSString *const RSSayFolderName;         // "Say"

// The three pass lengths, in seconds, for each setting (0: 2·1½·1 (the
// default), 1: 3·2·1½, 2: 4·3·2), and how they're printed ("2·1½·1").
NSArray *RSSayLengths(NSUInteger setting);
NSString *RSSayLengthsText(NSUInteger setting);
extern const NSUInteger RSSaySettings;          // 3

@interface RSSay : NSObject

- (id)initWithFolder:(NSString *)folder;        // <app folder>/Say, created, Islands.txt seeded
@property (nonatomic, readonly, copy) NSString *folder;

// ---- Islands ----
@property (nonatomic, readonly, copy) NSArray *islands;     // the topics, in the file's order
- (BOOL)saveIslands:(NSArray *)islands;                     // rewrites Islands.txt (empty lines dropped)
// Today's island: the topics in turn, a different one each day. nil if the list is empty.
- (NSString *)islandForDay:(long)day;

// ---- Today's passes ----
- (NSString *)passPath:(NSUInteger)pass;                    // Today/pass-<n>.m4a
// Removes passes recorded on another day (called when the window opens).
- (void)clearPassesNotFrom:(long)day;
- (BOOL)hasPass:(NSUInteger)pass;

// ---- The month's recording ----
- (NSString *)monthRecordingPathForDay:(long)day;           // Recordings/YYYY-MM.m4a
- (BOOL)hasMonthRecordingForDay:(long)day;
// Keeps `path` as the month's recording if the month has none yet. YES if kept.
- (BOOL)keepMonthRecording:(NSString *)path forDay:(long)day;
// The newest month's recording before this month, or nil. *month: "2026-10".
- (NSString *)previousMonthRecordingBeforeDay:(long)day month:(NSString **)month;

// ---- For the tutor ----
- (BOOL)addTutorNote:(NSString *)note day:(long)day;        // under today's heading
- (NSString *)tutorNotes;                                   // the whole file, or @""
- (NSArray *)tutorNotesForDay:(long)day;

@end

// "2026-11", from a day number.
NSString *RSMonthText(long day);
