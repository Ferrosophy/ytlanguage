#import "YTLTranslator.h"
#import "YTLSettings.h"
#import "../Core/YTLTextKit.h"

static NSString *const kGoogleEndpoint = @"https://translate.googleapis.com/translate_a/single";
static NSString *const kDeepSeekEndpoint = @"https://api.deepseek.com/chat/completions";   // OpenAI-compatible
static const NSUInteger kGoogleChunkChars = 1500;
static const NSUInteger kDeepSeekChunkChars = 2500;

typedef void (^YTLLinesCompletion)(NSArray <NSString *> *lines, NSString *error);
typedef void (^YTLLinesEngine)(NSArray <NSString *> *texts, YTLLinesCompletion done);

@implementation YTLTranslator {
    NSURLSession *_session;
    NSCache <NSString *, NSString *> *_cache;
}

+ (instancetype)shared {
    static YTLTranslator *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [self new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        config.timeoutIntervalForRequest = 15;
        _session = [NSURLSession sessionWithConfiguration:config];
        _cache = [NSCache new];
        _cache.countLimit = 5000;
    }
    return self;
}

#pragma mark - Google

- (NSURLRequest *)googleRequestForText:(NSString *)text dictionary:(BOOL)dictionary {
    NSURLComponents *components = [NSURLComponents componentsWithString:kGoogleEndpoint];
    NSMutableArray *items = [NSMutableArray arrayWithArray:@[
        [NSURLQueryItem queryItemWithName:@"client" value:@"gtx"],
        [NSURLQueryItem queryItemWithName:@"sl" value:@"auto"],
        [NSURLQueryItem queryItemWithName:@"tl" value:@"zh-CN"],
        [NSURLQueryItem queryItemWithName:@"hl" value:@"zh-CN"],
        [NSURLQueryItem queryItemWithName:@"dt" value:@"t"],
    ]];
    if (dictionary) [items addObject:[NSURLQueryItem queryItemWithName:@"dt" value:@"bd"]];
    [items addObject:[NSURLQueryItem queryItemWithName:@"q" value:text]];
    components.queryItems = items;
    // NSURLComponents leaves '+' unescaped, which the server would read as a space.
    components.percentEncodedQuery = [components.percentEncodedQuery stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"];
    return [NSURLRequest requestWithURL:components.URL];
}

- (void)googleRequest:(NSURLRequest *)request completion:(void (^)(YTLGoogleResult *result, NSString *error))completion {
    [[_session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        YTLGoogleResult *result = status == 200 ? [YTLTextKit googleResultFromJSON:data] : nil;
        NSString *message = result ? nil : error ? [NSString stringWithFormat:@"Google: %@", error.localizedDescription]
                                                 : [NSString stringWithFormat:@"Google: HTTP %ld", (long)status];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(result, message); });
    }] resume];
}

// Translates one chunk joined by "\n"; if the line count comes back different, splits the chunk in half.
- (void)googleLines:(NSArray <NSString *> *)texts completion:(YTLLinesCompletion)completion {
    NSString *joined = [texts componentsJoinedByString:@"\n"];
    [self googleRequest:[self googleRequestForText:joined dictionary:NO] completion:^(YTLGoogleResult *result, NSString *error) {
        if (!result) return completion(nil, error);
        NSArray *lines = [result.translation componentsSeparatedByString:@"\n"];
        if (lines.count == texts.count) return completion(lines, nil);
        if (texts.count == 1) return completion(@[[result.translation stringByReplacingOccurrencesOfString:@"\n" withString:@" "]], nil);
        [self splitLines:texts engine:^(NSArray *part, YTLLinesCompletion done) { [self googleLines:part completion:done]; } completion:completion];
    }];
}

#pragma mark - DeepSeek

- (void)deepSeekPrompt:(NSString *)system user:(NSString *)user completion:(void (^)(NSString *reply, NSString *error))completion {
    NSString *key = YTLSettings.deepSeekKey;
    if (!key) return completion(nil, @"DeepSeek: 未设置 API Key");
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kDeepSeekEndpoint]];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 60;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{
        @"model": YTLSettings.deepSeekModel,
        @"temperature": @0.2,
        @"stream": @NO,
        @"messages": @[ @{ @"role": @"system", @"content": system }, @{ @"role": @"user", @"content": user } ],
    } options:0 error:nil];
    [[_session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        NSString *reply = nil;
        if (status == 200 && data) {
            NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *choices = [root isKindOfClass:NSDictionary.class] ? root[@"choices"] : nil;
            id content = [choices isKindOfClass:NSArray.class] && choices.count ? choices[0][@"message"][@"content"] : nil;
            if ([content isKindOfClass:NSString.class]) reply = content;
        }
        NSString *message = reply ? nil : error ? [NSString stringWithFormat:@"DeepSeek: %@", error.localizedDescription]
                                                : [NSString stringWithFormat:@"DeepSeek: HTTP %ld", (long)status];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(reply, message); });
    }] resume];
}

- (void)deepSeekLines:(NSArray <NSString *> *)texts completion:(YTLLinesCompletion)completion {
    NSString *system = @"你是字幕翻译。把用户给出的每一行编号文本翻译成简体中文。按相同编号逐行输出，格式为“编号. 译文”，行数必须与输入一致，不要解释，不要合并或拆分行。";
    [self deepSeekPrompt:system user:[YTLTextKit numberedLines:texts] completion:^(NSString *reply, NSString *error) {
        if (!reply) return completion(nil, error);
        NSArray *lines = [YTLTextKit parseNumberedLines:reply count:texts.count];
        if (lines) return completion(lines, nil);
        if (texts.count == 1) return completion(@[[reply stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]], nil);
        [self splitLines:texts engine:^(NSArray *part, YTLLinesCompletion done) { [self deepSeekLines:part completion:done]; } completion:completion];
    }];
}

#pragma mark - Batching

// Halves a chunk whose line count did not round-trip.
- (void)splitLines:(NSArray <NSString *> *)texts engine:(YTLLinesEngine)engine completion:(YTLLinesCompletion)completion {
    NSUInteger half = texts.count / 2;
    engine([texts subarrayWithRange:NSMakeRange(0, half)], ^(NSArray *first, NSString *e1) {
        if (!first) return completion(nil, e1);
        engine([texts subarrayWithRange:NSMakeRange(half, texts.count - half)], ^(NSArray *second, NSString *e2) {
            completion(second ? [first arrayByAddingObjectsFromArray:second] : nil, e2);
        });
    });
}

// Runs chunks one after another so a long transcript never floods the endpoint.
- (void)runChunks:(NSArray <NSArray <NSString *> *> *)chunks index:(NSUInteger)index results:(NSMutableArray *)results
           engine:(YTLLinesEngine)engine completion:(YTLLinesCompletion)completion {
    if (index >= chunks.count) return completion(results, nil);
    engine(chunks[index], ^(NSArray <NSString *> *lines, NSString *error) {
        if (!lines) return completion(nil, error);
        [results addObjectsFromArray:lines];
        [self runChunks:chunks index:index + 1 results:results engine:engine completion:completion];
    });
}

- (void)translateAll:(NSArray <NSString *> *)texts provider:(YTLTranslationProvider)provider completion:(YTLLinesCompletion)completion {
    __weak typeof(self) weakSelf = self;
    BOOL google = provider == YTLTranslationProviderGoogle;
    YTLLinesEngine engine = google ? ^(NSArray *chunk, YTLLinesCompletion done) { [weakSelf googleLines:chunk completion:done]; }
                                   : ^(NSArray *chunk, YTLLinesCompletion done) { [weakSelf deepSeekLines:chunk completion:done]; };
    [self runChunks:[YTLTextKit chunks:texts maxChars:google ? kGoogleChunkChars : kDeepSeekChunkChars] index:0
            results:[NSMutableArray array] engine:engine completion:completion];
}

static NSString *YTLProviderName(YTLTranslationProvider provider) {
    return provider == YTLTranslationProviderDeepSeek ? @"DeepSeek" : @"Google";
}

#pragma mark - Public

- (void)translate:(NSArray <NSString *> *)texts completion:(YTLTranslateCompletion)completion {
    NSMutableArray <NSString *> *missing = [NSMutableArray array];
    for (NSString *text in texts) {
        if (![_cache objectForKey:text] && ![missing containsObject:text]) [missing addObject:text];
    }
    void (^finish)(NSString *, NSString *) = ^(NSString *provider, NSString *error) {
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:texts.count];
        for (NSString *text in texts) {
            NSString *hit = [self->_cache objectForKey:text];
            if (!hit) return completion(nil, provider, error ?: @"翻译结果缺失");
            [out addObject:hit];
        }
        completion(out, provider, nil);
    };
    if (!missing.count) return finish(@"cache", nil);

    void (^store)(NSArray <NSString *> *) = ^(NSArray <NSString *> *lines) {
        [missing enumerateObjectsUsingBlock:^(NSString *text, NSUInteger i, BOOL *stop) {
            NSString *line = [lines[i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (line.length) [self->_cache setObject:line forKey:text];
        }];
    };

    // The chosen service first; the other one as fallback (DeepSeek only when a key is set).
    YTLTranslationProvider primary = YTLSettings.translationProvider;
    if (primary == YTLTranslationProviderDeepSeek && !YTLSettings.deepSeekKey) primary = YTLTranslationProviderGoogle;
    YTLTranslationProvider secondary = primary == YTLTranslationProviderGoogle ? YTLTranslationProviderDeepSeek : YTLTranslationProviderGoogle;
    BOOL hasSecondary = secondary == YTLTranslationProviderGoogle || YTLSettings.deepSeekKey != nil;

    __weak typeof(self) weakSelf = self;
    [self translateAll:missing provider:primary completion:^(NSArray *lines, NSString *firstError) {
        if (lines.count == missing.count) {
            store(lines);
            return finish(YTLProviderName(primary), nil);
        }
        if (!hasSecondary) return completion(nil, YTLProviderName(primary), firstError);
        [weakSelf translateAll:missing provider:secondary completion:^(NSArray *fallback, NSString *secondError) {
            if (fallback.count != missing.count) {
                return completion(nil, YTLProviderName(secondary), [NSString stringWithFormat:@"%@；%@", firstError ?: @"失败", secondError ?: @"失败"]);
            }
            store(fallback);
            finish(YTLProviderName(secondary), nil);
        }];
    }];
}

- (void)lookupWord:(NSString *)word context:(NSString *)sentence completion:(YTLLookupCompletion)completion {
    __weak typeof(self) weakSelf = self;
    [self googleRequest:[self googleRequestForText:word dictionary:YES] completion:^(YTLGoogleResult *result, NSString *googleError) {
        if (result.translation.length || result.dictionaryLines.count) {
            return completion(result.translation, result.dictionaryLines, @"Google", nil);
        }
        if (!YTLSettings.deepSeekKey) return completion(nil, nil, @"Google", googleError ?: @"没有查到释义");
        NSString *system = @"你是英汉词典。只输出简体中文释义，最多4行：第一行是该词在句中的意思，其余行是“词性. 常见释义”。不要其他内容。";
        NSString *user = [NSString stringWithFormat:@"单词：%@\n句子：%@", word, sentence ?: @""];
        [weakSelf deepSeekPrompt:system user:user completion:^(NSString *reply, NSString *dsError) {
            if (!reply) return completion(nil, nil, @"DeepSeek", [NSString stringWithFormat:@"%@；%@", googleError ?: @"Google 失败", dsError]);
            NSMutableArray *lines = [NSMutableArray array];
            for (NSString *line in [reply componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
                NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                if (trimmed.length) [lines addObject:trimmed];
            }
            completion(lines.firstObject, lines.count > 1 ? [lines subarrayWithRange:NSMakeRange(1, lines.count - 1)] : @[], @"DeepSeek", nil);
        }];
    }];
}

@end
