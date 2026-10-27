#import <UIKit/UIKit.h>

@class YTPlayerViewController, YTLSubtitleSession;

// Right-side transcript drawer, YouTube-web style. Lives in the player's window:
// - portrait: slides in from the right below the inline player (video stays visible), dimmed strip on the left;
// - landscape: right panel (~38% width), the video stays usable on the left.
// Rows: timestamp + sentence + translation; current row highlighted; auto-follow until the user scrolls;
// tap seeks; long press offers save / edit-and-save / copy.
@interface YTLTranscriptDrawer : UIView
- (instancetype)initWithPlayer:(YTPlayerViewController *)player;
- (void)presentInWindow:(UIWindow *)window;
- (void)dismiss;
// Called by YTLOverlayController every tick while the drawer is shown.
- (void)updateWithSession:(YTLSubtitleSession *)session time:(double)time;
@end
