#import <UIKit/UIKit.h>

@class YTLProbeReport;

// Scrollable, selectable probe report with a share button for the full text file.
@interface YTLProbeViewController : UIViewController
- (instancetype)initWithReport:(YTLProbeReport *)report;
@end
