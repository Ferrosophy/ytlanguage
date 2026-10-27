// Offline fixture tests for Sources/Core (no UIKit, no host). Run: bash Tests/run.sh (in WSL).
// Fixture texts are written for these tests, not taken from real videos.

#import <Foundation/Foundation.h>
#import "../Sources/Core/YTLCue.h"
#import "../Sources/Core/YTLCaptionParser.h"
#import "../Sources/Core/YTLSentenceSegmenter.h"
#import "../Sources/Core/YTLTextKit.h"

static int gFailures = 0, gChecks = 0;

#define CHECK(cond, ...) do { gChecks++; if (!(cond)) { gFailures++; \
    fprintf(stderr, "FAIL %s:%d: %s — %s\n", __FILE__, __LINE__, #cond, [[NSString stringWithFormat:__VA_ARGS__] UTF8String]); } } while (0)

static NSData *D(NSString *s) { return [s dataUsingEncoding:NSUTF8StringEncoding]; }
static BOOL Near(double a, double b) { return fabs(a - b) < 0.001; }

static void testParsers(void) {
    NSString *format = nil;
    NSArray <YTLCue *> *cues = [YTLCaptionParser cuesFromData:D(@"{\"events\":[{\"tStartMs\":1500,\"dDurationMs\":2000,\"segs\":[{\"utf8\":\"Hello \"},{\"utf8\":\"world\"}]},"
                                                              "{\"tStartMs\":4000,\"dDurationMs\":10,\"segs\":[{\"utf8\":\"\\n\"}]},"
                                                              "{\"tStartMs\":0,\"dDurationMs\":1000,\"segs\":[{\"utf8\":\"First\\nline\"}]}]}") format:&format];
    CHECK([format isEqualToString:@"json3"], @"format %@", format);
    CHECK(cues.count == 2, @"json3 count %lu", (unsigned long)cues.count);
    CHECK([cues[0].text isEqualToString:@"First line"] && Near(cues[0].end, 1.0), @"json3 sorted/cleaned: %@", cues);
    CHECK([cues[1].text isEqualToString:@"Hello world"] && Near(cues[1].start, 1.5) && Near(cues[1].end, 3.5), @"json3 cue: %@", cues[1]);

    cues = [YTLCaptionParser cuesFromData:D(@"<?xml version=\"1.0\" encoding=\"utf-8\" ?><timedtext format=\"3\"><body>"
                                             "<p t=\"2000\" d=\"1500\">我们<s>出发</s>吧</p><p t=\"500\" d=\"1000\">第一句 &amp; 开始</p><p t=\"9000\" d=\"100\"> </p>"
                                             "</body></timedtext>") format:&format];
    CHECK([format isEqualToString:@"srv3"], @"format %@", format);
    CHECK(cues.count == 2, @"srv3 count %lu", (unsigned long)cues.count);
    CHECK([cues[0].text isEqualToString:@"第一句 & 开始"] && Near(cues[0].start, 0.5), @"srv3 first: %@", cues[0]);
    CHECK([cues[1].text isEqualToString:@"我们出发吧"] && Near(cues[1].end, 3.5), @"srv3 second: %@", cues[1]);

    cues = [YTLCaptionParser cuesFromData:D(@"<?xml version=\"1.0\"?><transcript><text start=\"1.25\" dur=\"2\">it&amp;#39;s fine</text></transcript>") format:&format];
    CHECK([format isEqualToString:@"srv1"] && cues.count == 1, @"srv1 %@ %@", format, cues);
    CHECK([cues.firstObject.text isEqualToString:@"it's fine"] && Near(cues.firstObject.end, 3.25), @"srv1 cue %@", cues.firstObject);

    cues = [YTLCaptionParser cuesFromData:D(@"WEBVTT\n\n00:00.000 --> 00:01.000\nhi") format:&format];
    CHECK(cues.count == 0 && format == nil, @"unsupported format must be empty, got %@ %@", format, cues);
    CHECK([YTLCaptionParser cuesFromData:[NSData data] format:&format].count == 0, @"empty data");
}

static void testIndex(void) {
    NSArray *cues = @[[YTLCue cueWithStart:0 end:4 text:@"a"], [YTLCue cueWithStart:3 end:6 text:@"b"], [YTLCue cueWithStart:8 end:9 text:@"c"]];
    CHECK(YTLIndexAtTime(cues, -1) == NSNotFound, @"before first");
    CHECK(YTLIndexAtTime(cues, 0) == 0, @"at 0");
    CHECK(YTLIndexAtTime(cues, 3.5) == 1, @"at 3.5");
    CHECK(YTLIndexAtTime(cues, 100) == 2, @"after last");
    CHECK([YTLActiveText(cues, 3.5) isEqualToString:@"a\nb"], @"overlap text %@", YTLActiveText(cues, 3.5));
    CHECK(YTLActiveText(cues, 7) == nil, @"gap has no text");
    CHECK(YTLIndexAtTime(@[], 1) == NSNotFound, @"empty");
}

static void testSegmenter(void) {
    // Roll-up style: overlapping cues, sentence crosses cue boundaries.
    NSArray *rollup = @[
        [YTLCue cueWithStart:0.0 end:5.0 text:@"I grew up in a small\ntown. It was quiet"],
        [YTLCue cueWithStart:3.0 end:8.0 text:@"and calm. Mr. Smith ran"],
        [YTLCue cueWithStart:6.0 end:10.0 text:@"the shop! Did you know?"],
    ];
    NSArray <YTLCue *> *s = [YTLSentenceSegmenter sentencesFromCues:rollup maxWords:18];
    CHECK(s.count == 4, @"rollup sentence count %lu: %@", (unsigned long)s.count, s);
    if (s.count == 4) {
        CHECK([s[0].text isEqualToString:@"I grew up in a small town."], @"s0 %@", s[0].text);
        CHECK([s[1].text isEqualToString:@"It was quiet and calm."], @"s1 %@", s[1].text);
        CHECK([s[2].text isEqualToString:@"Mr. Smith ran the shop!"], @"abbreviation kept: %@", s[2].text);
        CHECK([s[3].text isEqualToString:@"Did you know?"], @"s3 %@", s[3].text);
        CHECK(Near(s[0].start, 0.0) && s[1].start >= s[0].start && s[2].start >= s[1].start && s[3].start >= s[2].start, @"monotonic starts");
        for (YTLCue *x in s) CHECK(x.end > x.start, @"positive duration %@", x);
        CHECK(s[1].start < 3.0 && s[2].start >= 3.0, @"word interpolation inside cue 1 span [0,3): %@", s);
        CHECK(Near(s[3].end, 10.0), @"last sentence ends at last cue end: %@", s[3]);
    }

    // Speaker change marker and long pause split sentences without punctuation.
    NSArray *speakers = @[[YTLCue cueWithStart:0 end:2 text:@">> hello there"], [YTLCue cueWithStart:2 end:4 text:@">> hi back"],
                          [YTLCue cueWithStart:10 end:12 text:@"after a pause"]];
    s = [YTLSentenceSegmenter sentencesFromCues:speakers maxWords:18];
    CHECK(s.count == 3, @"speaker/pause split %@", s);
    CHECK([s.firstObject.text isEqualToString:@"hello there"], @"speaker marker removed: %@", s.firstObject.text);

    // Very long unpunctuated speech is capped at maxWords (0.3 s/word, so the 8 s cap does not trigger first).
    NSMutableArray *words = [NSMutableArray array];
    for (int i = 0; i < 100; i++) [words addObject:@"word"];
    s = [YTLSentenceSegmenter sentencesFromCues:@[[YTLCue cueWithStart:0 end:30 text:[words componentsJoinedByString:@" "]]] maxWords:18];
    CHECK(s.count == 6, @"cap 18 words → 6 segments, got %lu", (unsigned long)s.count);
    for (YTLCue *x in s) CHECK([x.text componentsSeparatedByString:@" "].count <= 18, @"segment too long: %@", x.text);

    // Slow speech is cut by duration: 10 words over 20 s → 2 s/word, 8 s cap → 4-word segments.
    s = [YTLSentenceSegmenter sentencesFromCues:@[[YTLCue cueWithStart:0 end:20 text:@"one two three four five six seven eight nine ten"]] maxWords:18];
    CHECK(s.count == 3, @"duration cap → 3 segments, got %@", s);

    // Past 60% of maxWords, a conjunction starts a new segment.
    s = [YTLSentenceSegmenter sentencesFromCues:@[[YTLCue cueWithStart:0 end:4 text:@"we went to the market on a sunny day in town and bought some apples"]] maxWords:18];
    CHECK(s.count == 2 && [s[1].text hasPrefix:@"and bought"], @"conjunction split %@", s);

    // CJK cues are kept as they are.
    NSArray *cjk = @[[YTLCue cueWithStart:0 end:2 text:@"今天天气很好我们出去玩吧"], [YTLCue cueWithStart:2 end:4 text:@"好的马上就来不要着急"]];
    s = [YTLSentenceSegmenter sentencesFromCues:cjk maxWords:18];
    CHECK(s.count == 2 && [s[1].text isEqualToString:@"好的马上就来不要着急"], @"cjk passthrough %@", s);

    CHECK([YTLSentenceSegmenter sentencesFromCues:@[] maxWords:18].count == 0, @"empty");
}

static void testTextKit(void) {
    NSString *json = @"[[[\"爱好\",\"hobby\",null,null,10]],[[\"名词\",[\"爱好\",\"嗜好\",\"业余爱好\"],[[\"爱好\",[\"hobby\"]]],\"hobby\",1]],\"en\"]";
    YTLGoogleResult *r = [YTLTextKit googleResultFromJSON:D(json)];
    CHECK([r.translation isEqualToString:@"爱好"], @"translation %@", r.translation);
    CHECK(r.dictionaryLines.count == 1 && [r.dictionaryLines[0] isEqualToString:@"名词: 爱好, 嗜好, 业余爱好"], @"dict %@", r.dictionaryLines);
    CHECK([r.sourceLanguage isEqualToString:@"en"], @"lang %@", r.sourceLanguage);
    r = [YTLTextKit googleResultFromJSON:D(@"[[[\"第一行\\n\",\"line one\\n\"],[\"第二行\",\"line two\"]],null,\"en\"]")];
    CHECK([[r.translation componentsSeparatedByString:@"\n"] count] == 2, @"multi-piece join %@", r.translation);
    CHECK([YTLTextKit googleResultFromJSON:D(@"<html>")] == nil, @"garbage → nil");

    NSArray *chunks = [YTLTextKit chunks:@[@"aaaa", @"bbbb", @"cccc", @"dddddddddddd"] maxChars:9];
    CHECK(chunks.count == 3 && [chunks[0] count] == 2, @"chunks %@", chunks);

    NSString *body = [YTLTextKit numberedLines:@[@"one", @"two\nlines"]];
    CHECK([body isEqualToString:@"1. one\n2. two lines\n"], @"numbered %@", body);
    NSArray *parsed = [YTLTextKit parseNumberedLines:@"好的：\n1. 一\n2、 二\n" count:2];
    NSArray *expected = @[@"一", @"二"];
    CHECK([parsed isEqualToArray:expected], @"parsed %@", parsed);
    CHECK([YTLTextKit parseNumberedLines:@"1. 一" count:2] == nil, @"missing line → nil");

    NSArray *tracks = @[
        @{ @"languageCode": @"en", @"VSSID": @".en", @"name": @"English" },
        @{ @"languageCode": @"zh-Hans", @"VSSID": @"a.zh-Hans", @"name": @"中文（简体）" },
        @{ @"languageCode": @"zh-Hans", @"VSSID": @".zh-Hans", @"name": @"中文（简体）（自动翻译）" },
        @{ @"languageCode": @"zh", @"VSSID": @".zh", @"name": @"中文" },
        @{ @"languageCode": @"zh-CN", @"VSSID": @".zh-CN", @"name": @"中文（中国）" },
        @{ @"languageCode": @"zh-TW", @"VSSID": @".zh-TW", @"name": @"中文（台灣）" },
    ];
    CHECK([YTLTextKit indexOfHumanSimplifiedChineseTrack:tracks] == 4, @"prefers human zh-CN over zh");
    CHECK([YTLTextKit indexOfHumanSimplifiedChineseTrack:[tracks subarrayWithRange:NSMakeRange(0, 3)]] == NSNotFound, @"auto and auto-translated excluded");
    CHECK([YTLTextKit indexOfHumanSimplifiedChineseTrack:@[tracks[5]]] == NSNotFound, @"traditional excluded");
    // Shape seen on device (v0.4.0 diagnostics): auto-translated tracks have VSSID ta.<src>.<dst>, type 2, plain names.
    NSArray *translated = @[@{ @"languageCode": @"zh-Hans", @"VSSID": @"ta.en.zh-Hans", @"name": @"中文（简体）", @"trackType": @2 }];
    CHECK([YTLTextKit indexOfHumanSimplifiedChineseTrack:translated] == NSNotFound, @"ta.* auto-translated excluded");

    NSString *line = @"Don't stop, well-known friends.";
    NSRange w = [YTLTextKit wordRangeInString:line atIndex:2];
    CHECK([[line substringWithRange:w] isEqualToString:@"Don't"], @"apostrophe word %@", NSStringFromRange(w));
    w = [YTLTextKit wordRangeInString:line atIndex:14];
    CHECK([[line substringWithRange:w] isEqualToString:@"well-known"], @"hyphen word %@", NSStringFromRange(w));
    w = [YTLTextKit wordRangeInString:line atIndex:29];
    CHECK([[line substringWithRange:w] isEqualToString:@"friends"], @"trailing punctuation excluded");
    CHECK([YTLTextKit wordRangeInString:line atIndex:10].location == NSNotFound, @"comma is not a word");
    CHECK([[YTLTextKit normalizedWord:@"“Don\u2019t,"] isEqualToString:@"don't"], @"normalized %@", [YTLTextKit normalizedWord:@"“Don\u2019t,"]);
}

int main(void) {
    @autoreleasepool {
        testParsers();
        testIndex();
        testSegmenter();
        testTextKit();
        printf("%d checks, %d failures\n", gChecks, gFailures);
    }
    return gFailures ? 1 : 0;
}
