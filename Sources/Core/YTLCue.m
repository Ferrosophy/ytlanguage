#import "YTLCue.h"

@implementation YTLCue

+ (instancetype)cueWithStart:(double)start end:(double)end text:(NSString *)text {
    YTLCue *cue = [self new];
    cue.start = start;
    cue.end = end;
    cue.text = text;
    return cue;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"[%.3f-%.3f] %@", self.start, self.end, self.text];
}

@end

NSUInteger YTLIndexAtTime(NSArray <YTLCue *> *cues, double time) {
    NSUInteger lo = 0, hi = cues.count;
    while (lo < hi) {
        NSUInteger mid = (lo + hi) / 2;
        if (cues[mid].start <= time) lo = mid + 1;
        else hi = mid;
    }
    return lo == 0 ? NSNotFound : lo - 1;
}

NSString *YTLActiveText(NSArray <YTLCue *> *cues, double time) {
    NSUInteger last = YTLIndexAtTime(cues, time);
    if (last == NSNotFound) return nil;
    NSMutableArray *texts = [NSMutableArray array];
    // Cues may overlap; walk back over the ones that started recently enough to still be visible.
    for (NSInteger i = (NSInteger)last; i >= 0 && texts.count < 3; i--) {
        YTLCue *cue = cues[(NSUInteger)i];
        if (time < cue.end && cue.text.length) [texts insertObject:cue.text atIndex:0];
        if (time - cue.start > 30) break;
    }
    return texts.count ? [texts componentsJoinedByString:@"\n"] : nil;
}
