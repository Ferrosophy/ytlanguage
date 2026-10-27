#import "YTLPlayback.h"
#import "YTLHostHeaders.h"

// Unverified selectors; only sent after respondsToSelector succeeds.
@interface YTPlayerViewController (YTLPlayback)
- (void)pause;
- (void)play;
@end

@implementation YTLPlayback

+ (BOOL)canPause:(YTPlayerViewController *)player {
    return [player respondsToSelector:@selector(pause)] && [player respondsToSelector:@selector(play)];
}

+ (void)pause:(YTPlayerViewController *)player {
    if ([self canPause:player]) [player pause];
}

+ (void)play:(YTPlayerViewController *)player {
    if ([self canPause:player]) [player play];
}

+ (BOOL)seek:(YTPlayerViewController *)player toTime:(double)time {
    if (![player respondsToSelector:@selector(seekToTime:)]) return NO;
    [player seekToTime:MAX(0, time)];
    return YES;
}

@end
