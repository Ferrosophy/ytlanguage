#import "YTLSubtitleStyle.h"
#import "YTLSettings.h"

static NSString *const kStyleKey = @"YTLanguage-SubtitleStyle";

static NSString *YTLHexFromColor(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat white = 0;
        [color getWhite:&white alpha:&a];
        r = g = b = white;
    }
    return [NSString stringWithFormat:@"#%02X%02X%02X%02X", (int)lround(r * 255), (int)lround(g * 255), (int)lround(b * 255), (int)lround(a * 255)];
}

static UIColor *YTLColorFromHex(id value, UIColor *fallback) {
    if (![value isKindOfClass:NSString.class]) return fallback;
    NSString *hex = [value stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (hex.length != 6 && hex.length != 8) return fallback;
    unsigned int rgba = 0;
    if (![[NSScanner scannerWithString:hex] scanHexInt:&rgba]) return fallback;
    if (hex.length == 6) rgba = (rgba << 8) | 0xFF;
    return [UIColor colorWithRed:((rgba >> 24) & 0xFF) / 255.0 green:((rgba >> 16) & 0xFF) / 255.0
                            blue:((rgba >> 8) & 0xFF) / 255.0 alpha:(rgba & 0xFF) / 255.0];
}

static CGFloat YTLClamp(CGFloat value, CGFloat lo, CGFloat hi) {
    return isnan(value) ? lo : MIN(hi, MAX(lo, value));
}

static CGFloat YTLNumber(NSDictionary *d, NSString *key, CGFloat fallback) {
    id value = d[key];
    return [value isKindOfClass:NSNumber.class] ? [value doubleValue] : fallback;
}

@implementation YTLSubtitleStyle

+ (instancetype)defaults {
    YTLSubtitleStyle *style = [self new];
    style.fontSize = 18;
    style.weight = 2;
    style.effect = YTLTextEffectShadow;
    style.originalColor = UIColor.whiteColor;
    style.translationColor = [UIColor colorWithRed:1 green:0.89 blue:0.54 alpha:1];
    style.backgroundEnabled = YES;
    style.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
    style.backgroundBlur = 0;
    style.backgroundPadding = 8;
    style.backgroundMaxWidth = 90;
    style.cornerRadius = 6;
    style.positionX = 50;
    style.positionY = 85;
    return style;
}

+ (instancetype)current {
    YTLSubtitleStyle *style = [self defaults];
    NSDictionary *d = [NSUserDefaults.standardUserDefaults dictionaryForKey:kStyleKey];
    if (!d) return style;
    style.fontSize = YTLNumber(d, @"fontSize", style.fontSize);
    style.weight = (NSInteger)YTLNumber(d, @"weight", style.weight);
    style.effect = (YTLTextEffect)YTLNumber(d, @"effect", style.effect);
    style.originalColor = YTLColorFromHex(d[@"originalColor"], style.originalColor);
    style.translationColor = YTLColorFromHex(d[@"translationColor"], style.translationColor);
    style.backgroundEnabled = YTLNumber(d, @"backgroundEnabled", style.backgroundEnabled) != 0;
    style.backgroundColor = YTLColorFromHex(d[@"backgroundColor"], style.backgroundColor);
    style.backgroundBlur = YTLNumber(d, @"backgroundBlur", style.backgroundBlur);
    style.backgroundPadding = YTLNumber(d, @"backgroundPadding", style.backgroundPadding);
    style.backgroundMaxWidth = YTLNumber(d, @"backgroundMaxWidth", style.backgroundMaxWidth);
    style.cornerRadius = YTLNumber(d, @"cornerRadius", style.cornerRadius);
    style.positionX = YTLNumber(d, @"positionX", style.positionX);
    style.positionY = YTLNumber(d, @"positionY", style.positionY);
    [style clamp];
    return style;
}

+ (void)resetToDefaults {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kStyleKey];
    [NSNotificationCenter.defaultCenter postNotificationName:YTLSettingsDidChangeNotification object:nil];
}

- (void)clamp {
    _fontSize = YTLClamp(_fontSize, 10, 40);
    _weight = (NSInteger)YTLClamp(_weight, 0, 3);
    _effect = (YTLTextEffect)YTLClamp(_effect, 0, 2);
    _backgroundBlur = YTLClamp(_backgroundBlur, 0, 100);
    _backgroundPadding = YTLClamp(_backgroundPadding, 0, 30);
    _backgroundMaxWidth = YTLClamp(_backgroundMaxWidth, 40, 100);
    _cornerRadius = YTLClamp(_cornerRadius, 0, 20);
    _positionX = YTLClamp(_positionX, 0, 100);
    _positionY = YTLClamp(_positionY, 0, 100);
}

- (void)save {
    [self clamp];
    [NSUserDefaults.standardUserDefaults setObject:@{
        @"fontSize": @(_fontSize), @"weight": @(_weight), @"effect": @(_effect),
        @"originalColor": YTLHexFromColor(_originalColor), @"translationColor": YTLHexFromColor(_translationColor),
        @"backgroundEnabled": @(_backgroundEnabled), @"backgroundColor": YTLHexFromColor(_backgroundColor),
        @"backgroundBlur": @(_backgroundBlur), @"backgroundPadding": @(_backgroundPadding),
        @"backgroundMaxWidth": @(_backgroundMaxWidth), @"cornerRadius": @(_cornerRadius),
        @"positionX": @(_positionX), @"positionY": @(_positionY),
    } forKey:kStyleKey];
    [NSNotificationCenter.defaultCenter postNotificationName:YTLSettingsDidChangeNotification object:nil];
}

- (id)copyWithZone:(NSZone *)zone {
    YTLSubtitleStyle *copy = [YTLSubtitleStyle new];
    copy.fontSize = _fontSize;
    copy.weight = _weight;
    copy.effect = _effect;
    copy.originalColor = _originalColor;
    copy.translationColor = _translationColor;
    copy.backgroundEnabled = _backgroundEnabled;
    copy.backgroundColor = _backgroundColor;
    copy.backgroundBlur = _backgroundBlur;
    copy.backgroundPadding = _backgroundPadding;
    copy.backgroundMaxWidth = _backgroundMaxWidth;
    copy.cornerRadius = _cornerRadius;
    copy.positionX = _positionX;
    copy.positionY = _positionY;
    return copy;
}

- (UIFontWeight)fontWeight {
    UIFontWeight weights[] = { UIFontWeightRegular, UIFontWeightMedium, UIFontWeightBold, UIFontWeightHeavy };
    return weights[MIN(3, MAX(0, _weight))];
}

+ (NSArray <NSString *> *)weightNames {
    return @[@"常规", @"中等", @"粗体", @"特粗"];
}

+ (NSArray <NSString *> *)effectNames {
    return @[@"无", @"阴影", @"描边"];
}

@end
