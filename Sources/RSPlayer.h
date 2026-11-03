// The player: one plain window, AVKit's AVPlayerView (10.9 has it), and the
// subtitles kept out of sight until asked for.
//
//   Space        play or pause
//   ← →          five seconds back or on
//   ↓            show this line (it goes again when the line ends)
//   ↑            hear this line again (or the one before, if this one has
//                only just begun)
//   S            keep subtitles on, or off again
//   T            the transcript: every line, the current one marked; click
//                one to go there
//   F            full screen (or a double-click on the picture); Esc leaves it
//   L            this line again and again, with a pause after each time to
//                say it back; L (or Space, or an arrow) stops
//   − =          slower, faster: a ladder of 1.0, 0.9, 0.8, 0.7, 0.6, 0.5 (the
//                pitch stays). A video reopens at the speed it was left at
//   K            keep this line, with its sound, to hear again on later days
//                (RSLines)
//   H            how was this video? (too easy / about right / too hard; more
//                like this / less like this). It also comes up by itself, once,
//                at the top of the picture when the video is 90% watched. One
//                click, about the video, never a score; ignore it and it goes.
//
// It remembers where it was left. "How far" is the furthest point reached by
// playing: dragging the scrubber to the end doesn't count.

#import <Cocoa/Cocoa.h>
#import "RSLibrary.h"

@class RSPlayer, RSSubtitles, RSLine, RSDictionary, RSDictionaryEntry;

@protocol RSPlayerDelegate <NSObject>
// Now and then while playing, at a pause, at the end, and on closing.
- (void)player:(RSPlayer *)player position:(double)position furthest:(double)furthest duration:(double)duration;
- (void)playerClosed:(RSPlayer *)player;
// Help was asked for (shown, heard again, looped, slowed, transcript,
// subtitles), on this line (nil if none was being said). For the report.
- (void)player:(RSPlayer *)player helped:(RSHelp)kind line:(RSLine *)line;
// The owner's choice about the video changed (each nil if not chosen).
- (void)player:(RSPlayer *)player felt:(NSString *)felt want:(NSString *)want;
// Keep this line (with the one before it, for context). Returns what to say:
// that it's kept, or why not.
- (NSString *)player:(RSPlayer *)player keepLine:(RSLine *)line before:(RSLine *)before;
// Keep a word of this line, as the slip looked it up (entry nil: not in the
// dictionary; kept with the word alone). Returns what to say.
- (NSString *)player:(RSPlayer *)player keepWord:(NSString *)word entry:(RSDictionaryEntry *)entry
                line:(RSLine *)line before:(RSLine *)before;
// The clip moved on: `passes` of three are finished (3: done for today).
- (void)player:(RSPlayer *)player clipFrom:(double)start to:(double)end passes:(NSUInteger)passes;
// The owner stepped the speed (− or =) to `rate`: remembered for the video,
// with the slowest ever chosen, for the report.
- (void)player:(RSPlayer *)player rateChanged:(float)rate;
@end

// The clip's passes (RSClips.h): off, then listen, read, say along, done.
typedef enum {
    RSClipOff = 0,
    RSClipListen,
    RSClipRead,
    RSClipSay,
    RSClipDone
} RSClipPass;

@interface RSPlayer : NSObject <NSWindowDelegate>

- (id)initWithIdentifier:(NSString *)identifier title:(NSString *)title movie:(NSString *)moviePath
               subtitles:(RSSubtitles *)subtitles position:(double)position furthest:(double)furthest
                duration:(double)duration;

@property (nonatomic, assign) id<RSPlayerDelegate> delegate;
@property (nonatomic, readonly, copy) NSString *identifier;
@property (nonatomic, readonly) NSWindow *window;
@property (nonatomic, readonly) BOOL subtitlesOn, transcriptShown, playing, fullScreen, looping, slower;

- (void)show;
- (void)close;

// The video's kind (RSKind...) and whether this is the first time through.
// A fast video the first time through opens with Russian subtitles on (the
// research for hard native video); S still turns them off. Set before -show.
- (void)setKind:(NSString *)kind firstViewing:(BOOL)first;
@property (nonatomic, readonly, copy) NSString *kind;

- (void)togglePlay;
- (void)skip:(double)seconds;
- (void)revealLine;
- (void)replayLine;
- (void)toggleSubtitles;
- (void)toggleTranscript;
- (void)toggleFullScreen;
- (void)toggleLoop;
// − and = step down and up the speed ladder (RSPlayerRates); the clip's
// passes set their own (a fast video's clip: 0.6, 0.8, then 1.0), and − and =
// still override them.
- (void)stepSlower;
- (void)stepFaster;
@property (nonatomic) float rate;        // set before -show to reopen at a remembered speed
- (void)keepLine;

// W: the word slip over the picture, for the line being said: its words as
// small cards, the rarest chosen first (the one most likely unknown); ← →
// choose, K keeps the word, W (or Esc) closes. The dictionary comes from the
// controller (nil: the slip says so).
@property (nonatomic, retain) RSDictionary *dictionary;
@property (nonatomic, readonly) BOOL wordSlipShown;
@property (nonatomic, readonly) NSInteger slipSelection;     // which word, while shown
- (void)toggleWordSlip;
- (void)chooseSlipWord:(NSInteger)index;
- (void)keepSlipWord;

// Today's clip (C, or the desk card): the stretch from `start` to `end`,
// worked in three passes behind a ruled card at the top of the picture.
//   1 Listen: no text, the stretch twice.
//   2 Read: captions on, a line at a time, pausing after each; Space goes on,
//     W looks a word up, K keeps.
//   3 Say along: each line once to hear, then again to speak over it; R
//     records your say-along through the microphone and plays it back after
//     the speaker's.
// Space pauses and goes on; C or Esc leaves the clip; ← → leave it too.
- (void)startClipFrom:(double)start to:(double)end;
// C with no clip under way: a clip from the line being said, two to three
// minutes on (RSClipFromLine), whenever the owner wants to shadow. The
// delegate hears of it with passes 0.
- (void)startClipHere;
- (void)leaveClip;
@property (nonatomic, readonly) RSClipPass clipPass;
@property (nonatomic, readonly) BOOL recordingSayAlong;
- (void)toggleRecordSayAlong;
- (void)setClipPassForTesting:(RSClipPass)pass;

// How the video felt, as chosen before (the controller sets it on opening).
- (void)setFelt:(NSString *)felt want:(NSString *)want;
@property (nonatomic, readonly, copy) NSString *felt, *want;
@property (nonatomic, readonly) BOOL feedbackShown;
- (void)toggleFeedback;
- (void)chooseFeedback:(NSString *)choice;     // one of RSFelt... / RSWant...; the same again clears it

// For the screenshots: no movie playing, the clock set by hand, a painted
// stand-in where the video goes.
- (void)setTimeForTesting:(double)seconds;
- (void)usePlaceholderVideoForTesting;
- (NSString *)visibleCaption;     // what's shown over the video now, or nil
- (NSString *)visibleNote;        // the short note over the video now, or nil

@end

// The speed ladder: 1.0, 0.9, 0.8, 0.7, 0.6, 0.5. Nothing below 0.5: there the
// words smear and stop sounding like speech.
extern const float RSPlayerRates[];
extern const NSUInteger RSPlayerRateCount;
// The nearest step on the ladder to `rate` (1 for anything odd).
float RSPlayerRateOnLadder(float rate);
// "Full speed." or "0.6×".
NSString *RSPlayerRateText(float rate);
