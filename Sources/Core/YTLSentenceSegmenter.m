#import "YTLSentenceSegmenter.h"
#import "YTLCaptionParser.h"

static const double kPauseSplit = 2.0;       // seconds of silence between cues that end a sentence
static const double kMaxSeconds = 8.0;       // a segment on screen longer than this is cut at the next word

@interface YTLWord : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic) double start;
@property (nonatomic) double end;
@property (nonatomic) BOOL breakBefore;
@end

@implementation YTLWord
@end

// Set once in +initialize (thread-safe, and keeps Core free of libdispatch for the Linux tests).
static NSSet *gAbbreviations;
static NSSet *gConjunctions;
static NSCharacterSet *gClosers;

static BOOL YTLEndsSentence(NSString *word) {
    if ([gAbbreviations containsObject:word.lowercaseString]) return NO;
    NSString *trimmed = [word stringByTrimmingCharactersInSet:gClosers];
    if (!trimmed.length) return NO;
    unichar last = [trimmed characterAtIndex:trimmed.length - 1];
    return last == '.' || last == '?' || last == '!' || last == 0x2026 || last == 0x3002 || last == 0xFF01 || last == 0xFF1F;
}

static BOOL YTLEndsClause(NSString *word) {
    unichar last = [word characterAtIndex:word.length - 1];
    return last == ',' || last == ';' || last == ':' || last == 0xFF0C;
}

@implementation YTLSentenceSegmenter

+ (void)initialize {
    if (self != YTLSentenceSegmenter.class) return;
    gAbbreviations = [NSSet setWithObjects:@"mr.", @"mrs.", @"ms.", @"dr.", @"st.", @"vs.", @"etc.", @"e.g.", @"i.e.",
                      @"u.s.", @"u.k.", @"jr.", @"sr.", @"prof.", @"no.", @"approx.", nil];
    gConjunctions = [NSSet setWithObjects:@"and", @"but", @"so", @"because", @"or", @"which", @"who", @"that", @"when",
                     @"while", @"then", @"if", @"although", @"though", @"where", @"since", @"until", nil];
    gClosers = [NSCharacterSet characterSetWithCharactersInString:@"\"'”’)]"];
}

+ (NSArray <YTLCue *> *)sentencesFromCues:(NSArray <YTLCue *> *)input maxWords:(NSUInteger)maxWordsIn {
    NSUInteger maxWords = MIN((NSUInteger)60, MAX((NSUInteger)6, maxWordsIn));
    NSUInteger softWords = MAX((NSUInteger)4, maxWords * 3 / 5);
    NSArray <YTLCue *> *cues = [input sortedArrayUsingComparator:^NSComparisonResult(YTLCue *a, YTLCue *b) {
        return a.start < b.start ? NSOrderedAscending : a.start > b.start ? NSOrderedDescending : NSOrderedSame;
    }];
    if (!cues.count) return @[];

    // Text without spaces (CJK etc.) cannot be split into words: keep cues as they are.
    NSUInteger chars = 0, spaces = 0;
    for (YTLCue *cue in cues) {
        chars += cue.text.length;
        spaces += [cue.text componentsSeparatedByString:@" "].count - 1;
    }
    if (chars > 20 && spaces * 20 < chars) {
        NSMutableArray *copies = [NSMutableArray array];
        for (YTLCue *cue in cues) [copies addObject:[YTLCue cueWithStart:cue.start end:cue.end text:[YTLCaptionParser cleanText:cue.text]]];
        return copies;
    }

    // 1. Words with interpolated times.
    NSMutableArray <YTLWord *> *words = [NSMutableArray array];
    double previousEnd = -1;
    for (NSUInteger i = 0; i < cues.count; i++) {
        YTLCue *cue = cues[i];
        NSArray *tokens = [[YTLCaptionParser cleanText:cue.text] componentsSeparatedByString:@" "];
        double spanEnd = cue.end;
        if (i + 1 < cues.count && cues[i + 1].start > cue.start) spanEnd = MIN(cue.end, cues[i + 1].start);
        if (spanEnd <= cue.start) spanEnd = MAX(cue.end, cue.start + 0.5);
        BOOL pause = previousEnd >= 0 && cue.start - previousEnd > kPauseSplit;
        previousEnd = MAX(previousEnd, cue.end);

        NSMutableArray <NSString *> *kept = [NSMutableArray array];
        NSMutableIndexSet *speakerBreaks = [NSMutableIndexSet indexSet];
        for (NSString *token in tokens) {
            if (!token.length) continue;
            if ([token isEqualToString:@">>"] || [token isEqualToString:@"-"]) {
                [speakerBreaks addIndex:kept.count];   // new speaker: break before the next word
                continue;
            }
            [kept addObject:token];
        }
        double step = (spanEnd - cue.start) / MAX((NSUInteger)1, kept.count);
        for (NSUInteger k = 0; k < kept.count; k++) {
            YTLWord *word = [YTLWord new];
            word.text = kept[k];
            word.start = cue.start + step * k;
            word.end = word.start + step;
            word.breakBefore = (k == 0 && pause) || [speakerBreaks containsIndex:k];
            [words addObject:word];
        }
    }

    // 2. Group words into sentences.
    NSMutableArray <YTLCue *> *sentences = [NSMutableArray array];
    NSMutableArray <YTLWord *> *current = [NSMutableArray array];
    void (^flush)(void) = ^{
        if (!current.count) return;
        NSMutableArray *texts = [NSMutableArray arrayWithCapacity:current.count];
        for (YTLWord *w in current) [texts addObject:w.text];
        [sentences addObject:[YTLCue cueWithStart:current.firstObject.start end:current.lastObject.end
                                             text:[texts componentsJoinedByString:@" "]]];
        [current removeAllObjects];
    };
    for (YTLWord *word in words) {
        BOOL conjunction = [gConjunctions containsObject:word.text.lowercaseString];
        if (word.breakBefore || (current.count >= softWords && conjunction)) flush();
        [current addObject:word];
        BOOL tooLong = current.count >= maxWords || word.end - current.firstObject.start >= kMaxSeconds;
        if (YTLEndsSentence(word.text) || tooLong || (current.count >= softWords && YTLEndsClause(word.text))) {
            flush();
        }
    }
    flush();
    return sentences;
}

@end
