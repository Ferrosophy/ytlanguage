#import "YTLCue.h"

// Turns caption cues (including overlapping roll-up auto captions) into sentence-sized cues.
// Word times are interpolated inside each cue; original cue order is kept, cue ranges are not altered.
@interface YTLSentenceSegmenter : NSObject
// maxWords caps a segment (clamped to 6...60). Long sentences are cut, in order of preference, at a clause
// punctuation mark or a conjunction once 60% of maxWords is reached, then at maxWords or after kMaxSeconds.
+ (NSArray <YTLCue *> *)sentencesFromCues:(NSArray <YTLCue *> *)cues maxWords:(NSUInteger)maxWords;
@end
