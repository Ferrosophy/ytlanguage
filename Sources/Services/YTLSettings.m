#import "YTLSettings.h"
#import <Security/Security.h>

NSString *const YTLSettingsDidChangeNotification = @"YTLSettingsDidChangeNotification";

static NSString *const kModeKey = @"YTLanguage-SubtitleMode";
static NSString *const kPauseKey = @"YTLanguage-PauseOnLookup";
static NSString *const kProviderKey = @"YTLanguage-TranslationProvider";
static NSString *const kModelKey = @"YTLanguage-DeepSeekModel";
static NSString *const kMaxWordsKey = @"YTLanguage-MaxSentenceWords";
static NSString *const kKeychainService = @"com.ytlanguage.tweak";
static NSString *const kKeychainAccount = @"deepseek-api-key";
static NSString *const kDefaultModel = @"deepseek-flash";   // per api-docs.deepseek.com, 2026-10-28
static BOOL gStylePreviewActive;

static void YTLSettingsChanged(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:YTLSettingsDidChangeNotification object:nil];
}

static NSDictionary *YTLKeychainQuery(NSString *account) {
    return @{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService: kKeychainService,
              (__bridge id)kSecAttrAccount: account };
}

@implementation YTLSettings

+ (void)initialize {
    if (self != YTLSettings.class) return;
    [NSUserDefaults.standardUserDefaults registerDefaults:@{ kModeKey: @(YTLSubtitleModeBilingual), kPauseKey: @YES, kMaxWordsKey: @18,
                                                            kProviderKey: @(YTLTranslationProviderGoogle) }];
    // v0.3–0.4 stored a SiliconFlow key and model; that provider is gone, so drop them.
    SecItemDelete((__bridge CFDictionaryRef)YTLKeychainQuery(@"siliconflow-api-key"));
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"YTLanguage-SiliconFlowModel"];
}

+ (NSInteger)maxSentenceWords {
    return MIN(40, MAX(8, [NSUserDefaults.standardUserDefaults integerForKey:kMaxWordsKey]));
}

+ (void)setMaxSentenceWords:(NSInteger)words {
    [NSUserDefaults.standardUserDefaults setInteger:MIN(40, MAX(8, words)) forKey:kMaxWordsKey];
    YTLSettingsChanged();
}

+ (BOOL)stylePreviewActive {
    return gStylePreviewActive;
}

+ (void)setStylePreviewActive:(BOOL)active {
    gStylePreviewActive = active;
    YTLSettingsChanged();
}

+ (YTLSubtitleMode)mode {
    NSInteger value = [NSUserDefaults.standardUserDefaults integerForKey:kModeKey];
    return value >= YTLSubtitleModeBilingual && value <= YTLSubtitleModeOff ? (YTLSubtitleMode)value : YTLSubtitleModeBilingual;
}

+ (void)setMode:(YTLSubtitleMode)mode {
    [NSUserDefaults.standardUserDefaults setInteger:mode forKey:kModeKey];
    YTLSettingsChanged();
}

+ (BOOL)pauseOnLookup {
    return [NSUserDefaults.standardUserDefaults boolForKey:kPauseKey];
}

+ (void)setPauseOnLookup:(BOOL)pause {
    [NSUserDefaults.standardUserDefaults setBool:pause forKey:kPauseKey];
    YTLSettingsChanged();
}

+ (YTLTranslationProvider)translationProvider {
    return [NSUserDefaults.standardUserDefaults integerForKey:kProviderKey] == YTLTranslationProviderDeepSeek
        ? YTLTranslationProviderDeepSeek : YTLTranslationProviderGoogle;
}

+ (void)setTranslationProvider:(YTLTranslationProvider)provider {
    [NSUserDefaults.standardUserDefaults setInteger:provider forKey:kProviderKey];
    YTLSettingsChanged();
}

+ (NSString *)deepSeekModel {
    NSString *model = [NSUserDefaults.standardUserDefaults stringForKey:kModelKey];
    return model.length ? model : kDefaultModel;
}

+ (void)setDeepSeekModel:(NSString *)model {
    NSString *trimmed = [model stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length) [NSUserDefaults.standardUserDefaults setObject:trimmed forKey:kModelKey];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:kModelKey];
    YTLSettingsChanged();
}

+ (NSString *)deepSeekKey {
    NSMutableDictionary *query = [YTLKeychainQuery(kKeychainAccount) mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess || !result) return nil;
    NSData *data = (__bridge_transfer NSData *)result;
    NSString *key = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return key.length ? key : nil;
}

+ (void)setDeepSeekKey:(NSString *)key {
    SecItemDelete((__bridge CFDictionaryRef)YTLKeychainQuery(kKeychainAccount));
    NSString *trimmed = [key stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length) {
        NSMutableDictionary *item = [YTLKeychainQuery(kKeychainAccount) mutableCopy];
        item[(__bridge id)kSecValueData] = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
        item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
        SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    }
    YTLSettingsChanged();
}

@end
