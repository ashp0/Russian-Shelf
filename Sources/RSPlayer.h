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
// A line was shown, heard again or looped (counted for the report).
- (void)player:(RSPlayer *)player helped:(RSHelp)kind;
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

// For the screenshots: no movie playing, the clock set by hand, a painted
// stand-in where the video goes.
- (void)setTimeForTesting:(double)seconds;
- (void)usePlaceholderVideoForTesting;
- (NSString *)visibleCaption;     // what's shown over the video now, or nil
- (NSString *)visibleNote;        // the short note over the video now, or nil

@end
