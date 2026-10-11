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
//
// It remembers where it was left. "How far" is the furthest point reached by
// playing: dragging the scrubber to the end doesn't count.

#import <Cocoa/Cocoa.h>

@class RSPlayer, RSSubtitles;

@protocol RSPlayerDelegate <NSObject>
// Now and then while playing, at a pause, at the end, and on closing.
- (void)player:(RSPlayer *)player position:(double)position furthest:(double)furthest duration:(double)duration;
- (void)playerClosed:(RSPlayer *)player;
@end

@interface RSPlayer : NSObject <NSWindowDelegate>

- (id)initWithIdentifier:(NSString *)identifier title:(NSString *)title movie:(NSString *)moviePath
               subtitles:(RSSubtitles *)subtitles position:(double)position furthest:(double)furthest
                duration:(double)duration;

@property (nonatomic, assign) id<RSPlayerDelegate> delegate;
@property (nonatomic, readonly, copy) NSString *identifier;
@property (nonatomic, readonly) NSWindow *window;
@property (nonatomic, readonly) BOOL subtitlesOn, transcriptShown, playing, fullScreen;

- (void)show;
- (void)close;

- (void)togglePlay;
- (void)skip:(double)seconds;
- (void)revealLine;
- (void)replayLine;
- (void)toggleSubtitles;
- (void)toggleTranscript;
- (void)toggleFullScreen;

// For the screenshots: no movie playing, the clock set by hand, a painted
// stand-in where the video goes.
- (void)setTimeForTesting:(double)seconds;
- (void)usePlaceholderVideoForTesting;
- (NSString *)visibleCaption;     // what's shown over the video now, or nil

@end
