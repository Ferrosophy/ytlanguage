// Minimal declarations of YouTube / YTVideoOverlay types used by YTLanguage.
// Shapes copied from, and only from:
//   YouTubeHeader 4b9977e (2026-10-17, MIT): YTPlayerViewController.h, YTSingleVideoController.h,
//     MLHAMPlayerItem.h, MLInnerTubeCaptionController.h, MLFormat3Captions.h, MLCaption.h,
//     MLCaptionSegment.h, YTIntervalTree.h, YTMainAppControlsOverlayView.h, YTInlinePlayerBarContainerView.h
//   YTVideoOverlay 8fd630b (2026-10-06, MIT): Header.h, Init.h
// Device-verified on YouTube 21.37.5 / iOS 27.0.1: overlay button, currentVideoID, media time (v0.1.0).
// Everything else is unverified on that host; call sites must guard with respondsToSelector.

#import <UIKit/UIKit.h>

// --- Overlay (YTVideoOverlay) ---

@interface YTQTMButton : UIButton
@end

@interface YTMainAppControlsOverlayView : UIView
@property (retain, nonatomic) NSMutableDictionary <NSString *, YTQTMButton *> *overlayButtons;
- (UIImage *)buttonImage:(NSString *)tweakId;
- (void)didPressYTLanguage:(id)arg;
- (void)didPressYTLTranscript:(id)arg;
@end

@interface YTInlinePlayerBarContainerView : UIView
@property (retain, nonatomic) NSMutableDictionary <NSString *, YTQTMButton *> *overlayButtons;
@property (nonatomic, weak) id delegate;
- (UIImage *)buttonImage:(NSString *)tweakId;
- (void)didPressYTLanguage:(id)arg;
- (void)didPressYTLTranscript:(id)arg;
@end

@interface NSObject (YTVideoOverlayInit)
+ (void)registerTweak:(NSString *)tweakId metadata:(NSDictionary *)metadata;
@end

// --- Settings (YouTubeHeader: YTSettingsSectionItem.h, YTSettingsViewController.h, YTIIcon.h; usage as in
// YouPiP Settings.x / YTVideoOverlay Tweak.x; device-verified with YouGroupSettings in v0.8.1) ---

@interface YTIIcon : NSObject
@property (nonatomic, assign, readwrite) NSInteger iconType;
@end

@interface YTSettingsSectionItem : NSObject
+ (instancetype)itemWithTitle:(NSString *)title accessibilityIdentifier:(NSString *)accessibilityIdentifier
              detailTextBlock:(NSString *(^)(void))detailTextBlock selectBlock:(BOOL (^)(id cell, NSUInteger arg))selectBlock;
@end

@interface NSObject (YTLSettingsViewController)
- (void)setSectionItems:(NSMutableArray *)sectionItems forCategory:(NSInteger)category title:(NSString *)title
       titleDescription:(NSString *)titleDescription headerHidden:(BOOL)headerHidden;
- (void)setSectionItems:(NSMutableArray *)sectionItems forCategory:(NSInteger)category title:(NSString *)title icon:(YTIIcon *)icon
       titleDescription:(NSString *)titleDescription headerHidden:(BOOL)headerHidden;
- (void)pushViewController:(UIViewController *)viewController;
- (NSMutableDictionary *)settingsSectionControllers;   // category → YTSettingsSectionController
+ (id)tweaks;   // YouGroupSettings
@end

@interface YTSettingsViewController : UIViewController
@end

// --- Player ---

// Methods below were listed by the v0.2.0 runtime dump on YouTube 21.37.5 (docs/COMPATIBILITY.md).
@interface MLInnerTubeCaptionTrack : NSObject
- (NSString *)languageCode;
- (NSString *)displayName;
- (NSString *)trackName;
- (NSString *)VSSID;
- (NSUInteger)trackType;
- (NSURL *)URL;
@end

@interface MLInnerTubeCaptionController : NSObject
@property (nonatomic, strong, readonly) MLInnerTubeCaptionTrack *activeCaptionTrack;
@property (nonatomic, strong, readonly) MLInnerTubeCaptionTrack *selectedCaptionTrack;
- (NSArray *)availableCaptionTracks;   // element type not yet observed; check each element
@end

// Listed by the v0.4.0 runtime dump on YouTube 21.37.5 (not declared in YouTubeHeader).
@interface YTCaptionViewController : UIViewController
- (void)setCaptionsHidden:(BOOL)hidden;
- (UIView *)captionView;
@end

@interface MLHAMPlayerItem : NSObject
@property (nonatomic, strong, readonly) MLInnerTubeCaptionController *captionController;
@property (nonatomic, strong, readonly) MLInnerTubeCaptionTrack *activeCaptionTrack;
@end

@interface YTSingleVideoController : NSObject
@property (nonatomic, strong, readwrite) MLHAMPlayerItem *playerItem;
@end

@interface YTPlayerViewController : UIViewController
@property (nonatomic, readonly, assign) BOOL isPlayingAd;
- (NSString *)currentVideoID;
- (YTSingleVideoController *)activeVideo;
- (CGFloat)currentVideoMediaTime;
- (CGFloat)currentVideoTotalMediaTime;
- (void)seekToTime:(CGFloat)time;
@end

// Listed by the v0.4.0 runtime dump on YouTube 21.37.5 (not declared in YouTubeHeader).
@interface YTPlayerViewController (YTLRuntimeObserved)
- (BOOL)arePlayerControlsHidden;
- (void)playbackControllerDidStartPIP:(id)controller;
- (void)playbackControllerDidStopPIP:(id)controller;
@end

// --- Captions ---

@interface MLCaptionSegment : NSObject
- (NSString *)text;
@end

@interface MLCaption : NSObject
- (CGFloat)startTime;
- (CGFloat)endTime;
- (NSArray <MLCaptionSegment *> *)segments;
@end

@interface YTIntervalTree : NSObject
- (NSUInteger)count;
- (NSMutableSet *)allIntervals;
- (void)enumerateAllIntervalsWithBlock:(void (^)(id interval))block;
@end

@interface MLFormat3Captions : NSObject
- (YTIntervalTree *)captions;
@end
