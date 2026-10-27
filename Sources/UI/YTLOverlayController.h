#import <UIKit/UIKit.h>

@class YTPlayerViewController, YTLSubtitleSession;

// One per YTPlayerViewController: owns the subtitle overlay, follows the player clock and video changes,
// feeds the session with the host's caption document and hides YouTube's own captions while ours are shown.
@interface YTLOverlayController : NSObject
+ (void)attachToPlayer:(YTPlayerViewController *)player;               // idempotent
+ (YTLOverlayController *)controllerForPlayer:(YTPlayerViewController *)player;
+ (void)registerNativeCaptionController:(UIViewController *)controller;
// Re-hides YouTube's caption view at once while YTLanguage is suppressing it (called from caption VC hooks).
+ (void)enforceNativeCaptions:(UIViewController *)controller;
// YTMainAppControlsOverlayView instances, seen through the YTVideoOverlay buttonImage: hook.
+ (void)registerControlsOverlay:(UIView *)overlay;
+ (void)setPictureInPictureActive:(BOOL)active;
@property (nonatomic, readonly) YTLSubtitleSession *session;
// Opens (or brings back) the right-side transcript drawer for this player.
- (void)showTranscript;
- (NSString *)statusDescription;
@end
