// The week's readings: six short stories with a lesson and a poem, written
// by Claude on the MacBook from the words the owner has met on the shelf
// (the request of 2026-11-02; the research: ~98% known words for reading
// without help, 95% the floor for learning from text (Hu & Nation 2000;
// Nation 2006); repeated reading raises reading rate and fluency (Taguchi,
// Takayasu-Maass & Gorsuch 2004); retelling is task repetition).
//
// Claude writes them as plain text and seals them with `shelfsign` into
// Russian/reading.signed, the same sealed format as a shelf (RSShelf.h:
// the outer file still says "Russian Shelf sealed 1"; what's inside says
// what it is), so the owner can't add or change them:
//
//     Russian Reading 1
//     start: 2026-11-09
//     story: 1 | Честный студент | Честность дороже оценки.
//     new: сда́ть, экза́мен, обмануть
//     Жил-был студе́нт. Он учи́лся в университе́те...
//
//     Но вдруг...
//     story: 2 | ...
//     poem: Стрекоза и Муравей | Иван Крылов, 1808 | Кто летом поёт, тот зимой голодает.
//     metre: четырёхстопный хорей, парная рифма
//     Попрыгунья Стрекоза
//     Лето красное пропела;
//
// A `story:` or `poem:` line begins a reading: its number (stories count
// 1, 2, 3...), its title, and its lesson in one line (`Мораль: …` as the
// owner will retell it); a poem gives its author between. `new:` lists the
// reading's new words, `metre:` a poem's metre and rhyme in a few words.
// Everything else up to the next reading is its text: a story's lines run
// together into paragraphs at blank lines; a poem keeps its lines. Stress
// marks (the combining acute, U+0301) are written on every word of two or
// more syllables; the app can hide them. `#` lines are comments. At most
// seven readings, each up to 8,000 characters.
//
// Which is today's: the readings in order, one a day from the start day,
// the last (the poem) staying up until the next week's arrive. The owner
// may open any of the week's. `shelfsign seal` adds the `sealed:` line.

#import <Foundation/Foundation.h>

enum { RSReadingMaxItems = 7, RSReadingMaxTextLength = 8000 };

@interface RSReadingItem : NSObject
@property (nonatomic) NSUInteger number;                 // 1-based, in the list's order
@property (nonatomic) BOOL poem;
@property (nonatomic, copy) NSString *title, *lesson;    // the lesson in one line
@property (nonatomic, copy) NSString *by, *metre;        // a poem's author and metre, or nil
@property (nonatomic, copy) NSArray *wordsToLearn;           // from `new:`, as written (with stress)
@property (nonatomic, copy) NSString *text;              // paragraphs or stanzas apart by a blank line
@property (nonatomic, copy) NSString *key;               // "<start>-<number>": safe as a file or card name
// The text without stress marks.
- (NSString *)plainText;
// The sentences of the text, in order, for keeping a word with its sentence.
- (NSArray *)sentences;
@end

// "челове́к" -> "человек": the combining acute taken out.
NSString *RSWithoutStress(NSString *text);

@interface RSReadingSet : NSObject

@property (nonatomic, readonly) long start;                  // day number (RSDate.h)
@property (nonatomic, readonly, copy) NSString *startText;   // "2026-11-09"
@property (nonatomic, readonly, copy) NSString *sealed;      // nil until sealed
@property (nonatomic, readonly, copy) NSArray *items;        // RSReadingItem, in order
@property (nonatomic, readonly, copy) NSString *fingerprint; // of the sealed file; nil for plain text

// The plain list. nil with *problem set (naming the line) if it doesn't read.
+ (RSReadingSet *)setWithText:(NSString *)text problem:(NSString **)problem;
- (NSString *)text;
- (RSReadingSet *)setSealedAt:(NSString *)sealed;

- (RSReadingItem *)itemWithKey:(NSString *)key;
// Today's reading: the n-th from the start day, the last one from then on;
// nil before the start.
- (RSReadingItem *)itemForDay:(long)day;
// Later start, or the same start sealed later.
- (BOOL)isNewerThan:(RSReadingSet *)other;

@end

// Opens a sealed file (RSShelf.h's format) that holds a reading list. nil
// with *problem otherwise.
RSReadingSet *RSOpenSealedReadingSet(NSData *file, NSData *aesKey, NSData *publicKey, NSString **problem);
RSReadingSet *RSOpenReadingFile(NSData *file, NSString **problem);     // with the app's keys
// Whether a plain text is a reading list rather than a shelf (its first
// line), for shelfsign.
BOOL RSTextIsReadingList(NSString *text);
