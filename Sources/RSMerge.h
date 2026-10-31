// Merging what another Mac did into what this Mac has: pure functions on
// the files' contents (plists as dictionaries, text as strings), no I/O.
// RSSyncManager reads the files, calls these and writes the results.
//
// Each is deterministic and idempotent: merging the same remote again
// changes nothing, merge(a, merge(a, b)) == merge(a, b), and two Macs that
// merge each other's files end with the same progress and the same cards.
// Anything a rule doesn't name is this Mac's, kept as it is (unknown keys
// included).
//
// State.plist (RSLibrary):
//   watched, per video:  furthest = the larger; finished = either; duration
//                        = the larger; position = the position of the side
//                        with the greater furthest (the same: the larger);
//                        felt, want = this Mac's if it has one, else the
//                        other's. Help counts and `lines` are facts about
//                        what was asked on each Mac and stay each Mac's own
//                        (each reports its own); so does any key this
//                        doesn't know. A video only the other Mac has comes
//                        in with its progress and feeling only.
//   clips                per video, by (start, end): the one with more
//                        passes (then the later day; then this Mac's).
//   say                  by day: this Mac's day if it has one, else theirs.
//   notice, anything else  this Mac's.
//
// Lines.plist (RSLines; the cards):
//   by key: the card heard later (`heard`) wins, every key in it; if both
//   were heard the same day: the higher step, then the one put away, then
//   more lapses, then this Mac's. A key only the losing card has is kept (a
//   Mac with an older Shelf saves cards without keys it doesn't know). A
//   card put away on either Mac stays put away (nothing ever takes a card
//   back out). If the winner has no meaning, the other's is taken (an empty
//   one counts as none). A card only one Mac has is kept. The
//   cards are in the order they were kept (`kept`, then key), so both Macs
//   list them alike. heardDay and heardCount are this Mac's day, and stay.
//
// Islands.txt: this Mac's lines in its order, then the other's new ones in
//   theirs (a line is new if no line here reads the same, spaces aside).
// Tutor.txt: sections by their "## YYYY-MM-DD" heading, sorted by date; a
//   section both have keeps this Mac's lines in order, then the other's new
//   ones. Text before the first heading is merged the same way.

#import <Foundation/Foundation.h>

@interface RSMerge : NSObject

+ (NSDictionary *)state:(NSDictionary *)local with:(NSDictionary *)remote;
+ (NSDictionary *)cards:(NSDictionary *)local with:(NSDictionary *)remote;
+ (NSString *)islands:(NSString *)local with:(NSString *)remote;
+ (NSString *)tutor:(NSString *)local with:(NSString *)remote;

// The names in `remote` to copy because `local` lacks them (never one
// already here: a month's recording or a card's sound is never replaced).
+ (NSArray *)missing:(NSArray *)local from:(NSArray *)remote;

// A card key that is safe as a file name ("JE4cI_Knzvc-0000250120").
+ (BOOL)isCardKey:(id)key;

@end
