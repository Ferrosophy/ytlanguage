#import <Foundation/Foundation.h>

@class YTPlayerViewController;

// Pause/resume for word lookup. YouTubeHeader declares no pause/play on YTPlayerViewController, so this is
// an experimental capability: used only when the runtime class responds to -pause and -play, and the
// caller verifies via the media clock that the pause took effect.
@interface YTLPlayback : NSObject
+ (BOOL)canPause:(YTPlayerViewController *)player;
+ (void)pause:(YTPlayerViewController *)player;
+ (void)play:(YTPlayerViewController *)player;
// -seekToTime: is declared in YouTubeHeader's YTPlayerViewController.h; still checked at runtime.
+ (BOOL)seek:(YTPlayerViewController *)player toTime:(double)time;
@end
