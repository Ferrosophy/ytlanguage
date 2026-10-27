#import <Foundation/Foundation.h>
#import "../Core/YTLCue.h"

@class YTPlayerViewController;

// Subtitle state for one video: source cues → sentences → Simplified Chinese translations.
// Translation source order: human Simplified Chinese track → the chosen machine service (Google/DeepSeek) → none.
@interface YTLSubtitleSession : NSObject
@property (nonatomic, copy, readonly) NSString *videoID;
@property (nonatomic, copy, readonly) NSArray <YTLCue *> *sentences;
@property (nonatomic, copy, readonly) NSString *sourceLanguage;
@property (nonatomic, readonly) NSUInteger documentSequence;
@property (nonatomic, copy, readonly) NSString *translationStatus;

- (instancetype)initWithVideoID:(NSString *)videoID;
// Replaces the source when YouTube loads a new caption document (e.g. a track switch).
- (void)setSourceCues:(NSArray <YTLCue *> *)cues language:(NSString *)language documentSequence:(NSUInteger)sequence;
- (void)startHumanTrackLookupWithPlayer:(YTPlayerViewController *)player;
// Index of the sentence to show at `time`, or NSNotFound.
- (NSUInteger)sentenceIndexAtTime:(double)time;
// Chinese text to show for that sentence/time; nil while pending or unavailable.
- (NSString *)translationForSentence:(NSUInteger)index time:(double)time;
// Chinese text for a whole sentence (transcript list): machine translation, or the human-track cues it overlaps.
- (NSString *)translationForSentenceAtIndex:(NSUInteger)index;
// Re-splits the source cues if YTLSettings.maxSentenceWords changed.
- (void)resegmentIfNeeded;
// Keeps machine translation moving forward from `index`; cheap to call every tick.
- (void)pumpTranslationsFromIndex:(NSUInteger)index;
- (void)invalidate;
- (NSString *)statusDescription;
@end
