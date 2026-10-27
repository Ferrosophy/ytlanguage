#import <UIKit/UIKit.h>

// Bottom sheet for a long-pressed word: Chinese meaning (Google/DeepSeek), context, save, system dictionary.
@interface YTLWordCardViewController : UIViewController
@property (nonatomic, copy) void (^onDismiss)(void);
- (instancetype)initWithWord:(NSString *)word sentence:(NSString *)sentence translation:(NSString *)translation
                     videoID:(NSString *)videoID timeMs:(long long)timeMs;
@end
