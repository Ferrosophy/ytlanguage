#import "YTLCue.h"

// Parses caption documents fetched from a host-provided track URL.
// Supported: YouTube json3, srv3 (timedtext format 3 XML) and srv1 (<transcript><text>).
@interface YTLCaptionParser : NSObject
// Cues sorted by start, empty texts dropped. *format is "json3", "srv3", "srv1" or nil if unrecognized.
+ (NSArray <YTLCue *> *)cuesFromData:(NSData *)data format:(NSString **)format;
// Collapses whitespace/newlines to single spaces and trims.
+ (NSString *)cleanText:(NSString *)text;
@end
