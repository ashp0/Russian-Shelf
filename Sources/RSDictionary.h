// A Russian-English dictionary, offline, for a word in a line: its lemma with
// the stress marked, what kind of word it is, two or three English glosses,
// and where it stands in the frequency list. Information about the word,
// never about the owner (DESIGN.md).
//
// The data is OpenRussian's (en.openrussian.org, CC BY-SA 4.0; the CSV mirror
// at github.com/Badestrand/russian-dictionary), built by Tools/mkdict.py into
// one SQLite file in the bundle (Resources/dict.sqlite; 10.9's own libsqlite3
// reads it). Ranks are the Russian National Corpus's (Lyashevskaya & Sharoff,
// A Frequency Dictionary of Modern Russian, 2009; dict.ruslang.ru/freq.php):
// lemmas by instances per million, the list the research brief cites.
//
//   words(id, bare, accented, type, rank, gloss)   accented: "челове'к" (' after the stressed vowel)
//   forms(form, word_id)                            every inflected form, bare, lowercase

#import <Foundation/Foundation.h>

// The frequency bands the slip names: "common" (the first 3,000), "less
// common" (to 10,000), "rare" (past that, or never met in the subtitles).
extern const NSUInteger RSRankCommon, RSRankLessCommon;

@interface RSDictionaryEntry : NSObject
@property (nonatomic, copy) NSString *bare;        // the lemma: "человек"
@property (nonatomic, copy) NSString *accented;    // with the stress mark: "челове́к"
@property (nonatomic, copy) NSString *type;        // "noun", "verb", "adjective", "other"
@property (nonatomic) NSUInteger rank;             // 1 = most frequent; 0 = not ranked
@property (nonatomic, copy) NSString *gloss;       // "person, people; man" (at most three senses)
// "common: 1,840th", "less common: 6,200th", "rare: past the common 10,000".
- (NSString *)rankText;
@end

@interface RSDictionary : NSObject

// The dictionary in the app bundle; nil (and nothing to look up) if it isn't there.
+ (RSDictionary *)bundled;
- (id)initWithFile:(NSString *)path;
@property (nonatomic, readonly) NSUInteger wordCount;

// The entry for a word as it appears in a line ("людей", "Людей,", "ещё"):
// case, punctuation and ё/е are forgiven; the most frequent lemma wins when
// a form belongs to several. nil if unknown.
- (RSDictionaryEntry *)lookup:(NSString *)word;

@end

// The words of a line, in order, as they'd be looked up: letters only, with
// hyphenated words kept whole ("кто-то"). Empty for a line with no Cyrillic.
NSArray *RSWordsInLine(NSString *line);
// "челове'к" -> "челове́к" (the combining acute accent, how stress is printed).
NSString *RSStressMarked(NSString *accented);
