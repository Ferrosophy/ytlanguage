#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, YTLTextEffect) { YTLTextEffectNone = 0, YTLTextEffectShadow = 1, YTLTextEffectOutline = 2 };

// User-adjustable subtitle look, stored as one dictionary in NSUserDefaults. Mutate a copy of +current,
// then -save (posts YTLSettingsDidChangeNotification). Values are clamped on save.
@interface YTLSubtitleStyle : NSObject <NSCopying>
// Text
@property (nonatomic) CGFloat fontSize;               // pt, 10–40 (translation line uses 90%)
@property (nonatomic) NSInteger weight;               // 0 常规, 1 中等, 2 粗体, 3 特粗
@property (nonatomic) YTLTextEffect effect;
@property (nonatomic, strong) UIColor *originalColor;
@property (nonatomic, strong) UIColor *translationColor;
// Background (text is always laid out inside it)
@property (nonatomic) BOOL backgroundEnabled;
@property (nonatomic, strong) UIColor *backgroundColor;   // alpha included
@property (nonatomic) CGFloat backgroundBlur;             // 0–100
@property (nonatomic) CGFloat backgroundPadding;          // pt, 0–30
@property (nonatomic) CGFloat backgroundMaxWidth;         // % of player width, 40–100
@property (nonatomic) CGFloat cornerRadius;               // pt, 0–20
// Position: bubble center in % of the player; clamped so the bubble stays inside the player
@property (nonatomic) CGFloat positionX;                  // 0–100
@property (nonatomic) CGFloat positionY;                  // 0–100

+ (instancetype)current;
+ (void)resetToDefaults;
- (void)save;
- (UIFontWeight)fontWeight;
+ (NSArray <NSString *> *)weightNames;
+ (NSArray <NSString *> *)effectNames;
@end
