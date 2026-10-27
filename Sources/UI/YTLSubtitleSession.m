#import "YTLSubtitleSession.h"
#import "../Core/YTLSentenceSegmenter.h"
#import "../HostAdapter/YTLHostCaptions.h"
#import "../Services/YTLTranslator.h"
#import "../Services/YTLSettings.h"

static const NSUInteger kBatchSentences = 25;
static const NSTimeInterval kRetryDelay = 15;
static const double kLinger = 1.2;   // keep a sentence on screen a little after its last word

typedef NS_ENUM(NSInteger, YTLHumanState) { YTLHumanPending, YTLHumanFound, YTLHumanMissing };

@implementation YTLSubtitleSession {
    NSMutableArray *_translations;      // NSString or NSNull, aligned with _sentences
    NSArray <YTLCue *> *_humanCues;
    YTLHumanState _humanState;
    NSString *_humanStatus;
    BOOL _inFlight;
    BOOL _invalidated;
    NSDate *_retryAfter;
    NSString *_provider;
    NSString *_lastError;
    NSUInteger _generation;
    NSArray <YTLCue *> *_sourceCues;
    NSUInteger _segmentedWithMaxWords;
}

- (instancetype)initWithVideoID:(NSString *)videoID {
    if ((self = [super init])) {
        _videoID = [videoID copy];
        _sentences = @[];
        _translations = [NSMutableArray array];
        _humanState = YTLHumanPending;
    }
    return self;
}

- (void)setSourceCues:(NSArray <YTLCue *> *)cues language:(NSString *)language documentSequence:(NSUInteger)sequence {
    _documentSequence = sequence;
    _sourceLanguage = [language copy];
    _sourceCues = [cues copy];
    [self segment];
}

- (void)resegmentIfNeeded {
    if (_sourceCues && _segmentedWithMaxWords != (NSUInteger)YTLSettings.maxSentenceWords) [self segment];
}

// Translations are keyed by sentence text in YTLTranslator's cache, so unchanged sentences come back instantly.
- (void)segment {
    _segmentedWithMaxWords = (NSUInteger)YTLSettings.maxSentenceWords;
    _sentences = [YTLSentenceSegmenter sentencesFromCues:_sourceCues maxWords:_segmentedWithMaxWords];
    _translations = [NSMutableArray arrayWithCapacity:_sentences.count];
    for (NSUInteger i = 0; i < _sentences.count; i++) [_translations addObject:NSNull.null];
    _generation++;
    _inFlight = NO;
    _retryAfter = nil;
}

- (BOOL)sourceIsChinese {
    return [_sourceLanguage.lowercaseString hasPrefix:@"zh"];
}

- (void)startHumanTrackLookupWithPlayer:(YTPlayerViewController *)player {
    if (_humanState != YTLHumanPending || _humanStatus) return;
    _humanStatus = @"正在查找人工中文字幕…";
    __weak typeof(self) weakSelf = self;
    [YTLHostCaptions fetchHumanChineseTrackForPlayer:player completion:^(NSArray <YTLCue *> *cues, NSString *status) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || strongSelf->_invalidated) return;
        strongSelf->_humanStatus = status;
        strongSelf->_humanCues = cues;
        strongSelf->_humanState = cues.count ? YTLHumanFound : YTLHumanMissing;
    }];
}

- (NSUInteger)sentenceIndexAtTime:(double)time {
    NSUInteger index = YTLIndexAtTime(_sentences, time);
    if (index == NSNotFound) return NSNotFound;
    return time <= _sentences[index].end + kLinger ? index : NSNotFound;
}

- (NSString *)translationForSentence:(NSUInteger)index time:(double)time {
    if (_humanState == YTLHumanFound) return YTLActiveText(_humanCues, time);
    if (index == NSNotFound || index >= _translations.count) return nil;
    id value = _translations[index];
    return [value isKindOfClass:NSString.class] ? value : nil;
}

- (NSString *)translationForSentenceAtIndex:(NSUInteger)index {
    if (index >= _sentences.count) return nil;
    if (_humanState != YTLHumanFound) return [self translationForSentence:index time:_sentences[index].start];
    YTLCue *sentence = _sentences[index];
    NSMutableArray *texts = [NSMutableArray array];
    for (YTLCue *cue in _humanCues) {
        if (cue.start >= sentence.end) break;
        if (cue.end > sentence.start && ![texts.lastObject isEqualToString:cue.text]) [texts addObject:cue.text];
    }
    return texts.count ? [texts componentsJoinedByString:@" "] : nil;
}

- (void)pumpTranslationsFromIndex:(NSUInteger)index {
    if (_invalidated || _inFlight || !_sentences.count || [self sourceIsChinese]) return;
    if (_humanState != YTLHumanMissing) return;   // wait for the human-track decision; found → no machine translation
    if (_retryAfter && [_retryAfter timeIntervalSinceNow] > 0) return;

    // First untranslated sentence at/after the current one, wrapping to the start.
    NSUInteger count = _sentences.count, start = index == NSNotFound ? 0 : index, first = NSNotFound;
    for (NSUInteger k = 0; k < count; k++) {
        NSUInteger i = (start + k) % count;
        if (_translations[i] == NSNull.null) { first = i; break; }
    }
    if (first == NSNotFound) return;

    NSMutableArray <NSNumber *> *indexes = [NSMutableArray array];
    NSMutableArray <NSString *> *texts = [NSMutableArray array];
    for (NSUInteger i = first; i < count && indexes.count < kBatchSentences; i++) {
        if (_translations[i] != NSNull.null) break;
        [indexes addObject:@(i)];
        [texts addObject:_sentences[i].text];
    }

    _inFlight = YES;
    NSUInteger generation = _generation;
    __weak typeof(self) weakSelf = self;
    [YTLTranslator.shared translate:texts completion:^(NSArray <NSString *> *translations, NSString *provider, NSString *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || strongSelf->_invalidated || generation != strongSelf->_generation) return;
        strongSelf->_inFlight = NO;
        if (translations.count != indexes.count) {
            strongSelf->_lastError = error ?: @"翻译失败";
            strongSelf->_retryAfter = [NSDate dateWithTimeIntervalSinceNow:kRetryDelay];
            return;
        }
        strongSelf->_lastError = nil;
        if (![provider isEqualToString:@"cache"]) strongSelf->_provider = provider;
        [indexes enumerateObjectsUsingBlock:^(NSNumber *i, NSUInteger k, BOOL *stop) {
            strongSelf->_translations[i.unsignedIntegerValue] = translations[k];
        }];
    }];
}

- (void)invalidate {
    _invalidated = YES;
}

- (NSString *)translationStatus {
    if ([self sourceIsChinese]) return @"原字幕已是中文，不翻译";
    if (_humanState == YTLHumanFound) return [NSString stringWithFormat:@"YouTube 人工中文字幕 · %@", _humanStatus];
    if (_humanState == YTLHumanPending) return _humanStatus ?: @"等待字幕…";
    NSUInteger done = 0;
    for (id value in _translations) if (value != NSNull.null) done++;
    NSString *provider = _provider ? ([_provider isEqualToString:@"DeepSeek"] ? @"DeepSeek" : @"Google 翻译") : @"机器翻译";
    NSMutableString *status = [NSMutableString stringWithFormat:@"%@ · %lu/%lu 句", provider, (unsigned long)done, (unsigned long)_translations.count];
    if (_lastError) [status appendFormat:@"\n上次失败：%@（%.0f 秒后重试）", _lastError, MAX(0, [_retryAfter timeIntervalSinceNow])];
    if (_humanStatus) [status appendFormat:@"\n%@", _humanStatus];
    return status;
}

- (NSString *)statusDescription {
    return [NSString stringWithFormat:@"video %@ · source %@ · document #%lu · %lu sentences\ntranslation: %@",
            _videoID, _sourceLanguage ?: @"?", (unsigned long)_documentSequence, (unsigned long)_sentences.count, self.translationStatus];
}

@end
