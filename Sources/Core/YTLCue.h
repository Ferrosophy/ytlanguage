#import <Foundation/Foundation.h>

// A timed piece of text in seconds. Used for host cues, fetched track cues and segmented sentences.
@interface YTLCue : NSObject
@property (nonatomic) double start;
@property (nonatomic) double end;
@property (nonatomic, copy) NSString *text;
+ (instancetype)cueWithStart:(double)start end:(double)end text:(NSString *)text;
@end

// Index of the last cue whose start <= time, or NSNotFound. `cues` must be sorted by start.
FOUNDATION_EXPORT NSUInteger YTLIndexAtTime(NSArray <YTLCue *> *cues, double time);

// Text of every cue active at `time` (start <= time < end), joined by "\n", or nil.
FOUNDATION_EXPORT NSString *YTLActiveText(NSArray <YTLCue *> *cues, double time);
