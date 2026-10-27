#import <UIKit/UIKit.h>

@class YTPlayerViewController;

// Opened by the player button: subtitle mode, translation status/settings, lookup options, diagnostics.
@interface YTLPanelViewController : UITableViewController
- (instancetype)initWithPlayer:(YTPlayerViewController *)player;
@end
