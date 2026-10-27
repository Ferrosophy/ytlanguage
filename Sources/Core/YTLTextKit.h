#import <Foundation/Foundation.h>

// Pure text helpers shared by translation, track selection and word lookup. No UIKit, no network.

@interface YTLGoogleResult : NSObject
@property (nonatomic, copy) NSString *translation;                  // all [0][i][0] pieces joined
@property (nonatomic, copy) NSArray <NSString *> *dictionaryLines;  // "名词: 爱好, 嗜好"
@property (nonatomic, copy) NSString *sourceLanguage;
@end

@interface YTLTextKit : NSObject

// Response of translate.googleapis.com/translate_a/single?client=gtx (dt=t, optional dt=bd).
+ (YTLGoogleResult *)googleResultFromJSON:(NSData *)data;

// Splits `texts` into chunks whose "\n"-joined length stays within maxChars (a single long text gets its own chunk).
+ (NSArray <NSArray <NSString *> *> *)chunks:(NSArray <NSString *> *)texts maxChars:(NSUInteger)maxChars;

// Numbered-line prompt body ("1. text") and its parser; returns nil unless every number 1...count is present.
+ (NSString *)numberedLines:(NSArray <NSString *> *)texts;
+ (NSArray <NSString *> *)parseNumberedLines:(NSString *)reply count:(NSUInteger)count;

// tracks: @{ @"languageCode", @"VSSID", @"name", @"trackType" }. Index of the best human-made Simplified Chinese
// track, excluding auto-generated (VSSID "a.*") and auto-translated (VSSID "ta.*", trackType 2) tracks; NSNotFound if none.
+ (NSUInteger)indexOfHumanSimplifiedChineseTrack:(NSArray <NSDictionary *> *)tracks;

// Word (letters/digits with inner ' ’ -) containing character index, or {NSNotFound, 0}.
+ (NSRange)wordRangeInString:(NSString *)string atIndex:(NSUInteger)index;
// Lowercased, curly apostrophes straightened, surrounding punctuation removed.
+ (NSString *)normalizedWord:(NSString *)word;

@end
