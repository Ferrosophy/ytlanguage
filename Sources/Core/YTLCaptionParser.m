#import "YTLCaptionParser.h"

@interface YTLTimedTextXMLDelegate : NSObject <NSXMLParserDelegate>
@property (nonatomic, readonly) NSMutableArray <YTLCue *> *cues;
@property (nonatomic, copy) NSString *format;
@end

@implementation YTLTimedTextXMLDelegate {
    NSMutableString *_text;
    double _start, _end;
}

- (instancetype)init {
    if ((self = [super init])) _cues = [NSMutableArray array];
    return self;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)name namespaceURI:(NSString *)ns qualifiedName:(NSString *)qn attributes:(NSDictionary *)attrs {
    if ([name isEqualToString:@"timedtext"] && !self.format) {
        self.format = [attrs[@"format"] isEqualToString:@"3"] ? @"srv3" : @"timedtext";
    } else if ([name isEqualToString:@"transcript"] && !self.format) {
        self.format = @"srv1";
    } else if ([name isEqualToString:@"p"] && attrs[@"t"]) {        // srv3: milliseconds
        _start = [attrs[@"t"] doubleValue] / 1000.0;
        _end = _start + [attrs[@"d"] doubleValue] / 1000.0;
        _text = [NSMutableString string];
    } else if ([name isEqualToString:@"text"] && attrs[@"start"]) {  // srv1: seconds
        _start = [attrs[@"start"] doubleValue];
        _end = _start + [attrs[@"dur"] doubleValue];
        _text = [NSMutableString string];
    } else if ([name isEqualToString:@"br"]) {
        [_text appendString:@" "];
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    [_text appendString:string];
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)name namespaceURI:(NSString *)ns qualifiedName:(NSString *)qn {
    if (!_text || !([name isEqualToString:@"p"] || [name isEqualToString:@"text"])) return;
    NSString *text = _text;
    if ([self.format isEqualToString:@"srv1"]) {
        // srv1 text is commonly HTML-escaped a second time.
        text = [[[[text stringByReplacingOccurrencesOfString:@"&#39;" withString:@"'"]
                 stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""]
                 stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"]
                 stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
        text = [text stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    }
    text = [YTLCaptionParser cleanText:text];
    if (text.length) [_cues addObject:[YTLCue cueWithStart:_start end:MAX(_end, _start) text:text]];
    _text = nil;
}

@end

@implementation YTLCaptionParser

+ (NSString *)cleanText:(NSString *)text {
    NSArray *parts = [text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray *words = [NSMutableArray arrayWithCapacity:parts.count];
    for (NSString *part in parts) {
        if (part.length) [words addObject:part];
    }
    return [words componentsJoinedByString:@" "];
}

+ (NSArray <YTLCue *> *)json3Cues:(NSDictionary *)root {
    NSMutableArray *cues = [NSMutableArray array];
    NSArray *events = [root[@"events"] isKindOfClass:NSArray.class] ? root[@"events"] : nil;
    for (NSDictionary *event in events) {
        if (![event isKindOfClass:NSDictionary.class]) continue;
        NSArray *segs = event[@"segs"];
        if (![segs isKindOfClass:NSArray.class]) continue;
        NSMutableString *text = [NSMutableString string];
        for (NSDictionary *seg in segs) {
            if ([seg isKindOfClass:NSDictionary.class] && [seg[@"utf8"] isKindOfClass:NSString.class]) [text appendString:seg[@"utf8"]];
        }
        NSString *clean = [self cleanText:text];
        if (!clean.length) continue;
        double start = [event[@"tStartMs"] doubleValue] / 1000.0;
        double end = start + [event[@"dDurationMs"] doubleValue] / 1000.0;
        [cues addObject:[YTLCue cueWithStart:start end:end text:clean]];
    }
    return cues;
}

+ (NSArray <YTLCue *> *)cuesFromData:(NSData *)data format:(NSString **)format {
    if (format) *format = nil;
    if (!data.length) return @[];

    // Sniff the first non-whitespace byte.
    const unsigned char *bytes = data.bytes;
    NSUInteger i = 0;
    if (data.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) i = 3;
    while (i < data.length && (bytes[i] == ' ' || bytes[i] == '\n' || bytes[i] == '\r' || bytes[i] == '\t')) i++;
    if (i >= data.length) return @[];

    NSArray <YTLCue *> *cues = @[];
    if (bytes[i] == '{') {
        id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([root isKindOfClass:NSDictionary.class] && root[@"events"]) {
            cues = [self json3Cues:root];
            if (format) *format = @"json3";
        }
    } else if (bytes[i] == '<') {
        NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
        YTLTimedTextXMLDelegate *delegate = [YTLTimedTextXMLDelegate new];
        parser.delegate = delegate;
        if ([parser parse] || delegate.cues.count) {
            cues = delegate.cues;
            if (format) *format = [delegate.format isEqualToString:@"timedtext"] ? @"srv3" : delegate.format;
        }
    }
    return [cues sortedArrayUsingComparator:^NSComparisonResult(YTLCue *a, YTLCue *b) {
        return a.start < b.start ? NSOrderedAscending : a.start > b.start ? NSOrderedDescending : NSOrderedSame;
    }];
}

@end
