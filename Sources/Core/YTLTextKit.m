#import "YTLTextKit.h"

@implementation YTLGoogleResult
@end

static BOOL YTLIsWordChar(unichar c) {
    return [NSCharacterSet.alphanumericCharacterSet characterIsMember:c];
}

static BOOL YTLIsInnerJoiner(unichar c) {
    return c == '\'' || c == 0x2019 || c == '-';
}

@implementation YTLTextKit

+ (YTLGoogleResult *)googleResultFromJSON:(NSData *)data {
    if (!data.length) return nil;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![root isKindOfClass:NSArray.class] || ![root count]) return nil;
    YTLGoogleResult *result = [YTLGoogleResult new];

    NSMutableString *translation = [NSMutableString string];
    if ([root[0] isKindOfClass:NSArray.class]) {
        for (id piece in root[0]) {
            if ([piece isKindOfClass:NSArray.class] && [piece count] && [piece[0] isKindOfClass:NSString.class]) {
                [translation appendString:piece[0]];
            }
        }
    }
    result.translation = translation;

    NSMutableArray *lines = [NSMutableArray array];
    if ([root count] > 1 && [root[1] isKindOfClass:NSArray.class]) {
        for (id entry in root[1]) {
            if (![entry isKindOfClass:NSArray.class] || [entry count] < 2) continue;
            NSString *pos = [entry[0] isKindOfClass:NSString.class] ? entry[0] : @"";
            NSArray *terms = [entry[1] isKindOfClass:NSArray.class] ? entry[1] : nil;
            NSMutableArray *kept = [NSMutableArray array];
            for (id term in terms) {
                if ([term isKindOfClass:NSString.class] && kept.count < 8) [kept addObject:term];
            }
            if (kept.count) {
                [lines addObject:pos.length ? [NSString stringWithFormat:@"%@: %@", pos, [kept componentsJoinedByString:@", "]]
                                            : [kept componentsJoinedByString:@", "]];
            }
        }
    }
    result.dictionaryLines = lines;

    if ([root count] > 2 && [root[2] isKindOfClass:NSString.class]) result.sourceLanguage = root[2];
    return result;
}

+ (NSArray <NSArray <NSString *> *> *)chunks:(NSArray <NSString *> *)texts maxChars:(NSUInteger)maxChars {
    NSMutableArray *chunks = [NSMutableArray array];
    NSMutableArray *current = [NSMutableArray array];
    NSUInteger length = 0;
    for (NSString *text in texts) {
        NSUInteger add = text.length + (current.count ? 1 : 0);
        if (current.count && length + add > maxChars) {
            [chunks addObject:[current copy]];
            [current removeAllObjects];
            length = 0;
            add = text.length;
        }
        [current addObject:text];
        length += add;
    }
    if (current.count) [chunks addObject:[current copy]];
    return chunks;
}

+ (NSString *)numberedLines:(NSArray <NSString *> *)texts {
    NSMutableString *body = [NSMutableString string];
    [texts enumerateObjectsUsingBlock:^(NSString *text, NSUInteger i, BOOL *stop) {
        [body appendFormat:@"%lu. %@\n", (unsigned long)(i + 1), [text stringByReplacingOccurrencesOfString:@"\n" withString:@" "]];
    }];
    return body;
}

+ (NSArray <NSString *> *)parseNumberedLines:(NSString *)reply count:(NSUInteger)count {
    NSMutableDictionary <NSNumber *, NSString *> *found = [NSMutableDictionary dictionary];
    for (NSString *raw in [reply componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSScanner *scanner = [NSScanner scannerWithString:line];
        NSInteger number = 0;
        if (![scanner scanInteger:&number] || number < 1 || (NSUInteger)number > count) continue;
        NSString *rest = [line substringFromIndex:scanner.scanLocation];
        NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@".、)）:： \t"];
        rest = [rest stringByTrimmingCharactersInSet:separators];
        if (rest.length && !found[@(number)]) found[@(number)] = rest;
    }
    if (found.count != count) return nil;
    NSMutableArray *ordered = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 1; i <= count; i++) [ordered addObject:found[@(i)]];
    return ordered;
}

+ (NSUInteger)indexOfHumanSimplifiedChineseTrack:(NSArray <NSDictionary *> *)tracks {
    NSArray *excludedNameParts = @[@"自动", @"自動", @"auto-generated", @"automatic", @"auto-translated", @"翻译", @"翻譯", @"translated"];
    NSDictionary <NSString *, NSNumber *> *rank = @{ @"zh-hans": @0, @"zh-cn": @0, @"zh-hans-cn": @0, @"zh-sg": @1, @"zh-hans-sg": @1, @"zh": @2 };
    NSUInteger best = NSNotFound;
    NSInteger bestRank = NSIntegerMax;
    for (NSUInteger i = 0; i < tracks.count; i++) {
        NSDictionary *track = tracks[i];
        NSString *language = [track[@"languageCode"] description].lowercaseString;
        NSNumber *r = language ? rank[[language stringByReplacingOccurrencesOfString:@"_" withString:@"-"]] : nil;
        if (!r) continue;
        // a.xx = auto-generated (ASR), ta.<src>.<dst> = auto-translated (type 2), per the v0.4.0 diagnostics.
        NSString *vssid = [track[@"VSSID"] description];
        if ([vssid hasPrefix:@"a."] || [vssid hasPrefix:@"ta."] || [track[@"trackType"] integerValue] == 2) continue;
        NSString *name = [track[@"name"] description].lowercaseString ?: @"";
        BOOL excluded = NO;
        for (NSString *part in excludedNameParts) {
            if ([name containsString:part]) { excluded = YES; break; }
        }
        if (excluded) continue;
        if (r.integerValue < bestRank) {
            bestRank = r.integerValue;
            best = i;
        }
    }
    return best;
}

+ (NSRange)wordRangeInString:(NSString *)string atIndex:(NSUInteger)index {
    if (index >= string.length || !YTLIsWordChar([string characterAtIndex:index])) return NSMakeRange(NSNotFound, 0);
    NSUInteger start = index, end = index + 1;
    while (start > 0) {
        unichar c = [string characterAtIndex:start - 1];
        if (YTLIsWordChar(c)) start--;
        else if (YTLIsInnerJoiner(c) && start >= 2 && YTLIsWordChar([string characterAtIndex:start - 2])) start--;
        else break;
    }
    while (end < string.length) {
        unichar c = [string characterAtIndex:end];
        if (YTLIsWordChar(c)) end++;
        else if (YTLIsInnerJoiner(c) && end + 1 < string.length && YTLIsWordChar([string characterAtIndex:end + 1])) end++;
        else break;
    }
    return NSMakeRange(start, end - start);
}

+ (NSString *)normalizedWord:(NSString *)word {
    NSString *straight = [word stringByReplacingOccurrencesOfString:@"’" withString:@"'"];
    NSMutableCharacterSet *trim = [NSMutableCharacterSet punctuationCharacterSet];
    [trim formUnionWithCharacterSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [straight stringByTrimmingCharactersInSet:trim].lowercaseString;
}

@end
