#import <Foundation/Foundation.h>
#import "../Core/YTLCue.h"

@class YTPlayerViewController;

// Host caption access. Only uses selectors observed in the v0.2.0 runtime dump; each is guarded.
@interface YTLHostCaptions : NSObject

+ (id)captionControllerForPlayer:(YTPlayerViewController *)player;
// activeVideo.singleVideo.playbackData.video.videoDetails.title — path per YouTubeHeader; `title` itself is not
// declared there, so this returns nil unless the object responds to it at runtime.
+ (NSString *)videoTitleForPlayer:(YTPlayerViewController *)player;
+ (NSString *)activeTrackLanguage:(YTPlayerViewController *)player;
// NO when YouTube's CC is off: activeCaptionTrack is nil (v0.5.0 diagnostics, taken after the user switched CC off).
// YES when the caption controller cannot be read, so the overlay keeps working without that signal.
+ (BOOL)captionsEnabledForPlayer:(YTPlayerViewController *)player;

// @{languageCode, VSSID, name, trackType} for every available track (diagnostics + selection).
+ (NSArray <NSDictionary *> *)trackDescriptionsForPlayer:(YTPlayerViewController *)player;

// Finds a human-made Simplified Chinese track (auto-generated / auto-translated excluded), downloads it from
// the track URL the host already holds and parses it. cues == nil when unavailable; status explains why.
+ (void)fetchHumanChineseTrackForPlayer:(YTPlayerViewController *)player
                             completion:(void (^)(NSArray <YTLCue *> *cues, NSString *status))completion;

// Most recent MLFormat3Captions document registered after `sequence` (see YTLCaptionProbe), as cues.
+ (NSArray <YTLCue *> *)cuesOfLatestDocumentAfterSequence:(NSUInteger)sequence documentSequence:(NSUInteger *)documentSequence;

@end
