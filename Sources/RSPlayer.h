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
//   −            three-quarter speed, and full speed again (the pitch stays)
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

@class RSPlayer, RSSubtitles, RSLine;

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
@end

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
- (void)toggleSlower;
- (void)keepLine;

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
