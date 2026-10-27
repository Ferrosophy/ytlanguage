#import <UIKit/UIKit.h>

// 双语学习: saved words and sentences. The header holds the 单词 / 句子 tabs, an export button (TXT / CSV / JSON
// of the current tab) and 原文 / 译文 / 原文与译文 (remembered per tab); swipe a row to delete it.
// Pushed from the player panel; from YouTube settings it opens full screen in its own navigation (close button).
@interface YTLStudyViewController : UITableViewController
- (instancetype)initShowingSentences:(BOOL)sentences;
// What YouTube settings last pushed (class, title, section keys), for diagnostics.
@property (class, nonatomic, copy) NSString *settingsPushInfo;
@end
