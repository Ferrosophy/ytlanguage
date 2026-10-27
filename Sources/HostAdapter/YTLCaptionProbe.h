#import <Foundation/Foundation.h>
#import "../Core/YTLCue.h"

@class YTPlayerViewController, MLFormat3Captions;

@interface YTLProbeReport : NSObject
@property (nonatomic, copy) NSString *summary;   // shown on screen
@property (nonatomic, copy) NSString *full;      // summary + every cue, for the shared file
@property (nonatomic, copy) NSString *fileName;
@end

// Records every MLFormat3Captions document the host creates, extracts its cues, and builds the
// diagnostics report (player, caption path, tracks, cue checks, runtime classes).
@interface YTLCaptionProbe : NSObject
+ (void)noteFormat3Captions:(id)captions;
+ (NSUInteger)currentSequence;
+ (MLFormat3Captions *)latestDocumentAfterSequence:(NSUInteger)after sequence:(NSUInteger *)sequence;
// Cues sorted by start; nil if the document's caption tree cannot be read.
+ (NSArray <YTLCue *> *)cuesFromDocument:(MLFormat3Captions *)document;
// `extra` is appended as its own section (overlay/translation status).
+ (YTLProbeReport *)reportForPlayer:(YTPlayerViewController *)player extra:(NSString *)extra;
@end
