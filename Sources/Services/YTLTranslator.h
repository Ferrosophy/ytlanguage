#import <Foundation/Foundation.h>

typedef void (^YTLTranslateCompletion)(NSArray <NSString *> *translations, NSString *provider, NSString *error);
typedef void (^YTLLookupCompletion)(NSString *translation, NSArray <NSString *> *definitions, NSString *provider, NSString *error);

// Machine translation into Simplified Chinese.
// The service chosen in settings (Google gtx, no key / DeepSeek, needs a key) first, the other as fallback.
// Word lookup: Google dictionary, then DeepSeek if a key is set.
// Completions run on the main queue. Request URLs/keys are never logged.
@interface YTLTranslator : NSObject
+ (instancetype)shared;
- (void)translate:(NSArray <NSString *> *)texts completion:(YTLTranslateCompletion)completion;
- (void)lookupWord:(NSString *)word context:(NSString *)sentence completion:(YTLLookupCompletion)completion;
@end
