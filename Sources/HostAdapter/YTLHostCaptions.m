#import "YTLHostCaptions.h"
#import "YTLHostHeaders.h"
#import "YTLCaptionProbe.h"
#import "../Core/YTLCaptionParser.h"
#import "../Core/YTLTextKit.h"

static id YTLSafeGet(id object, NSString *key) {
    if (!object || ![object respondsToSelector:NSSelectorFromString(key)]) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (NSException *e) {
        return nil;
    }
}

@implementation YTLHostCaptions

+ (id)captionControllerForPlayer:(YTPlayerViewController *)player {
    return YTLSafeGet(YTLSafeGet(YTLSafeGet(player, @"activeVideo"), @"playerItem"), @"captionController");
}

+ (NSString *)videoTitleForPlayer:(YTPlayerViewController *)player {
    id object = player;
    for (NSString *key in @[@"activeVideo", @"singleVideo", @"playbackData", @"video", @"videoDetails", @"title"]) {
        object = YTLSafeGet(object, key);
    }
    return [object isKindOfClass:NSString.class] && [object length] ? object : nil;
}

+ (NSString *)activeTrackLanguage:(YTPlayerViewController *)player {
    id track = YTLSafeGet([self captionControllerForPlayer:player], @"activeCaptionTrack");
    id language = YTLSafeGet(track, @"languageCode");
    return [language isKindOfClass:NSString.class] ? language : nil;
}

+ (BOOL)captionsEnabledForPlayer:(YTPlayerViewController *)player {
    id controller = [self captionControllerForPlayer:player];
    if (![controller respondsToSelector:@selector(activeCaptionTrack)]) return YES;
    return YTLSafeGet(controller, @"activeCaptionTrack") != nil;
}

+ (NSArray *)tracksForPlayer:(YTPlayerViewController *)player {
    id tracks = YTLSafeGet([self captionControllerForPlayer:player], @"availableCaptionTracks");
    return [tracks isKindOfClass:NSArray.class] ? tracks : @[];
}

+ (NSDictionary *)describeTrack:(id)track {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"languageCode", @"VSSID", @"trackType"]) {
        id value = YTLSafeGet(track, key);
        if (value) info[key] = value;
    }
    id name = YTLSafeGet(track, @"displayName") ?: YTLSafeGet(track, @"trackName");
    if ([name isKindOfClass:NSString.class]) info[@"name"] = name;
    info[@"class"] = NSStringFromClass([track class]);
    return info;
}

+ (NSArray <NSDictionary *> *)trackDescriptionsForPlayer:(YTPlayerViewController *)player {
    NSMutableArray *out = [NSMutableArray array];
    for (id track in [self tracksForPlayer:player]) [out addObject:[self describeTrack:track]];
    return out;
}

+ (void)fetchHumanChineseTrackForPlayer:(YTPlayerViewController *)player
                             completion:(void (^)(NSArray <YTLCue *> *cues, NSString *status))completion {
    NSArray *tracks = [self tracksForPlayer:player];
    NSMutableArray *descriptions = [NSMutableArray array];
    for (id track in tracks) [descriptions addObject:[self describeTrack:track]];
    NSUInteger index = [YTLTextKit indexOfHumanSimplifiedChineseTrack:descriptions];
    if (index == NSNotFound) {
        return completion(nil, [NSString stringWithFormat:@"没有人工简体中文字幕（共 %lu 条字幕轨）", (unsigned long)tracks.count]);
    }

    NSDictionary *info = descriptions[index];
    NSURL *url = YTLSafeGet(tracks[index], @"URL");
    NSString *label = [NSString stringWithFormat:@"%@ %@", info[@"languageCode"], info[@"VSSID"] ?: @""];
    if (![url isKindOfClass:NSURL.class]) {
        return completion(nil, [NSString stringWithFormat:@"人工中文字幕 %@ 没有 URL", label]);
    }

    // The URL belongs to the host's own track object; it is never logged or shown.
    NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:15];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        NSString *format = nil;
        NSArray <YTLCue *> *cues = status == 200 ? [YTLCaptionParser cuesFromData:data format:&format] : nil;
        NSString *message;
        if (cues.count) {
            message = [NSString stringWithFormat:@"人工中文字幕 %@：%lu 句（%@）", label, (unsigned long)cues.count, format];
        } else if (status == 200) {
            message = [NSString stringWithFormat:@"人工中文字幕 %@ 下载成功但无法解析（%lu 字节，格式 %@）", label, (unsigned long)data.length, format ?: @"未知"];
            cues = nil;
        } else {
            message = [NSString stringWithFormat:@"人工中文字幕 %@ 下载失败：%@", label,
                       error ? error.localizedDescription : [NSString stringWithFormat:@"HTTP %ld", (long)status]];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(cues, message); });
    }] resume];
}

+ (NSArray <YTLCue *> *)cuesOfLatestDocumentAfterSequence:(NSUInteger)sequence documentSequence:(NSUInteger *)documentSequence {
    NSUInteger found = 0;
    MLFormat3Captions *document = [YTLCaptionProbe latestDocumentAfterSequence:sequence sequence:&found];
    if (documentSequence) *documentSequence = found;
    return document ? [YTLCaptionProbe cuesFromDocument:document] : nil;
}

@end
