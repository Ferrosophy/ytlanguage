#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, YTLSubtitleMode) {
    YTLSubtitleModeBilingual = 0,
    YTLSubtitleModeOriginal = 1,
    YTLSubtitleModeTranslation = 2,
    YTLSubtitleModeOff = 3,
};

typedef NS_ENUM(NSInteger, YTLTranslationProvider) {
    YTLTranslationProviderGoogle = 0,
    YTLTranslationProviderDeepSeek = 1,
};

FOUNDATION_EXPORT NSString *const YTLSettingsDidChangeNotification;

// NSUserDefaults-backed preferences; the DeepSeek key lives in the Keychain.
@interface YTLSettings : NSObject
@property (class, nonatomic) YTLSubtitleMode mode;
@property (class, nonatomic) BOOL pauseOnLookup;
@property (class, nonatomic) NSInteger maxSentenceWords;        // 8–40, default 18
@property (class, nonatomic) BOOL stylePreviewActive;           // not persisted; shows sample text while editing style
@property (class, nonatomic) YTLTranslationProvider translationProvider;
@property (class, nonatomic, copy) NSString *deepSeekModel;
@property (class, nonatomic, copy) NSString *deepSeekKey;      // nil = not set
@end
