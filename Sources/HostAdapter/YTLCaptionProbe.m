#import "YTLCaptionProbe.h"
#import "YTLHostHeaders.h"
#import "YTLHostCaptions.h"
#import <objc/runtime.h>

#ifndef YTL_VERSION
#define YTL_VERSION "dev"
#endif

@implementation YTLProbeReport
@end

// Format3 documents seen, weakly held, keyed by object identity (YTInterval may override -hash/-isEqual:).
static NSMapTable *gDocuments;   // MLFormat3Captions -> NSArray @[sequence, capturedAt]
static NSUInteger gSequence;

#pragma mark - Helpers

static NSString *YTLTime(double seconds) {
    if (isnan(seconds) || seconds < 0) return @"?";
    long ms = lround(seconds * 1000);
    long h = ms / 3600000, m = (ms / 60000) % 60, s = (ms / 1000) % 60, r = ms % 1000;
    return h ? [NSString stringWithFormat:@"%ld:%02ld:%02ld.%03ld", h, m, s, r]
             : [NSString stringWithFormat:@"%02ld:%02ld.%03ld", m, s, r];
}

static id YTLGet(id object, NSString *key) {
    if (!object || ![object respondsToSelector:NSSelectorFromString(key)]) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (NSException *e) {
        return nil;
    }
}

static NSString *YTLClassChain(id object) {
    NSMutableArray *names = [NSMutableArray array];
    for (Class c = object_getClass(object); c && c != NSObject.class; c = class_getSuperclass(c)) {
        [names addObject:NSStringFromClass(c)];
    }
    return [names componentsJoinedByString:@" : "];
}

// Never print URLs or anything that may carry signatures/tokens.
static NSString *YTLRedacted(id value) {
    NSString *text = [value description];
    NSString *lower = text.lowercaseString;
    if (text.length > 80 || [lower containsString:@"http"] || [lower containsString:@"://"] ||
        [lower containsString:@"sig"] || [lower containsString:@"token"] || [lower containsString:@"key="]) {
        return [NSString stringWithFormat:@"<redacted, %lu chars>", (unsigned long)text.length];
    }
    return text;
}

static BOOL YTLIsScalarOrStringType(const char *attrs) {
    if (!attrs || attrs[0] != 'T') return NO;
    if (strncmp(attrs, "T@\"NSString\"", 12) == 0 || strncmp(attrs, "T@\"NSNumber\"", 12) == 0) return YES;
    return strchr("cislqCISLQfdB", attrs[1]) != NULL;
}

static void YTLDumpObject(NSMutableString *out, id object, NSString *label) {
    if (!object) {
        [out appendFormat:@"%@: nil\n", label];
        return;
    }
    [out appendFormat:@"%@: <%@ %p>\n", label, YTLClassChain(object), object];
    NSSet *skip = [NSSet setWithObjects:@"hash", @"superclass", @"description", @"debugDescription", nil];
    for (Class c = object_getClass(object); c && c != NSObject.class; c = class_getSuperclass(c)) {
        unsigned int count = 0;
        objc_property_t *props = class_copyPropertyList(c, &count);
        for (unsigned int i = 0; i < count; i++) {
            NSString *name = @(property_getName(props[i]));
            if ([skip containsObject:name]) continue;
            const char *attrs = property_getAttributes(props[i]);
            if (YTLIsScalarOrStringType(attrs)) {
                id value = YTLGet(object, name);
                [out appendFormat:@"    .%@ = %@\n", name, value ? YTLRedacted(value) : @"nil"];
            } else {
                NSString *type = [[@(attrs) componentsSeparatedByString:@","] firstObject];
                [out appendFormat:@"    .%@ (%@)\n", name, [type substringFromIndex:MIN((NSUInteger)1, type.length)]];
            }
        }
        free(props);
    }
}

static void YTLDumpClass(NSMutableString *out, NSString *className, NSString *filter) {
    Class cls = NSClassFromString(className);
    if (!cls) {
        [out appendFormat:@"%@: class NOT FOUND\n", className];
        return;
    }
    [out appendFormat:@"%@ (super %@)%@\n", className, NSStringFromClass(class_getSuperclass(cls)),
        filter ? [NSString stringWithFormat:@" methods matching /%@/", filter] : @""];
    unsigned int count = 0;
    if (!filter) {
        Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            [out appendFormat:@"    ivar %s %s\n", ivar_getName(ivars[i]), ivar_getTypeEncoding(ivars[i]) ?: ""];
        }
        free(ivars);
    }
    NSRegularExpression *regex = filter ? [NSRegularExpression regularExpressionWithPattern:filter options:NSRegularExpressionCaseInsensitive error:nil] : nil;
    Method *methods = class_copyMethodList(cls, &count);
    NSUInteger shown = 0;
    for (unsigned int i = 0; i < count && shown < 120; i++) {
        NSString *name = NSStringFromSelector(method_getName(methods[i]));
        if (regex && ![regex firstMatchInString:name options:0 range:NSMakeRange(0, name.length)]) continue;
        [out appendFormat:@"    - %@\n", name];
        shown++;
    }
    if (shown >= 120) [out appendString:@"    ... more methods\n"];
    free(methods);
}

#pragma mark - Probe

@implementation YTLCaptionProbe

+ (void)noteFormat3Captions:(id)captions {
    if (!captions) return;
    @synchronized (self) {
        if (!gDocuments) {
            gDocuments = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality
                                                   valueOptions:NSPointerFunctionsStrongMemory
                                                       capacity:8];
        }
        if (![gDocuments objectForKey:captions]) {
            [gDocuments setObject:@[@(++gSequence), [NSDate date]] forKey:captions];
        }
    }
}

+ (NSUInteger)currentSequence {
    @synchronized (self) {
        return gSequence;
    }
}

+ (MLFormat3Captions *)latestDocumentAfterSequence:(NSUInteger)after sequence:(NSUInteger *)sequence {
    MLFormat3Captions *best = nil;
    NSUInteger bestSequence = 0;
    @synchronized (self) {
        for (id document in gDocuments.keyEnumerator) {
            NSUInteger seq = [[gDocuments objectForKey:document][0] unsignedIntegerValue];
            if (seq > after && seq > bestSequence) {
                best = document;
                bestSequence = seq;
            }
        }
    }
    if (sequence) *sequence = bestSequence;
    return best;
}

+ (NSArray <YTLCue *> *)cuesFromDocument:(MLFormat3Captions *)document {
    if (![document respondsToSelector:@selector(captions)]) return nil;
    YTIntervalTree *tree = document.captions;
    NSMutableArray *intervals = [NSMutableArray array];
    if ([tree respondsToSelector:@selector(enumerateAllIntervalsWithBlock:)]) {
        [tree enumerateAllIntervalsWithBlock:^(id interval) { [intervals addObject:interval]; }];
    } else if ([tree respondsToSelector:@selector(allIntervals)]) {
        [intervals addObjectsFromArray:tree.allIntervals.allObjects];
    } else {
        return nil;
    }

    NSMutableArray <YTLCue *> *cues = [NSMutableArray array];
    for (MLCaption *caption in intervals) {
        if (![caption respondsToSelector:@selector(startTime)] || ![caption respondsToSelector:@selector(endTime)]) continue;
        NSMutableString *text = [NSMutableString string];
        if ([caption respondsToSelector:@selector(segments)]) {
            for (MLCaptionSegment *segment in caption.segments) {
                if ([segment respondsToSelector:@selector(text)] && segment.text) [text appendString:segment.text];
            }
        }
        [cues addObject:[YTLCue cueWithStart:caption.startTime end:caption.endTime text:text]];
    }
    [cues sortUsingComparator:^NSComparisonResult(YTLCue *a, YTLCue *b) {
        return a.start < b.start ? NSOrderedAscending : a.start > b.start ? NSOrderedDescending : NSOrderedSame;
    }];
    return cues;
}

+ (YTLProbeReport *)reportForPlayer:(YTPlayerViewController *)player extra:(NSString *)extra {
    NSMutableString *out = [NSMutableString string];
    NSBundle *host = NSBundle.mainBundle;
    [out appendFormat:@"YTLanguage v%s diagnostics\n%@\nYouTube %@ (%@) · iOS %@\n\n", YTL_VERSION, [NSDate date],
        [host objectForInfoDictionaryKey:@"CFBundleShortVersionString"], [host objectForInfoDictionaryKey:@"CFBundleVersion"],
        UIDevice.currentDevice.systemVersion];

    // Player
    NSString *videoID = [player respondsToSelector:@selector(currentVideoID)] ? player.currentVideoID : nil;
    double now = [player respondsToSelector:@selector(currentVideoMediaTime)] ? player.currentVideoMediaTime : NAN;
    double duration = [player respondsToSelector:@selector(currentVideoTotalMediaTime)] ? player.currentVideoTotalMediaTime : NAN;
    [out appendFormat:@"== Player\nplayer: %@\nvideoID: %@\ntime: %@ / %@ (raw %.3f / %.3f)\n\n",
        player ? NSStringFromClass(player.class) : @"NOT FOUND", videoID ?: @"N/A", YTLTime(now), YTLTime(duration), now, duration];

    if (extra.length) [out appendFormat:@"== YTLanguage\n%@\n\n", extra];

    // Caption path and tracks
    [out appendString:@"== Caption path\n"];
    id controller = [YTLHostCaptions captionControllerForPlayer:player];
    [out appendFormat:@"captionController: %@\n", controller ? YTLClassChain(controller) : @"nil"];
    id activeTrack = YTLGet(controller, @"activeCaptionTrack");
    YTLDumpObject(out, activeTrack, @"activeCaptionTrack");
    NSArray *tracks = [YTLHostCaptions trackDescriptionsForPlayer:player];
    [out appendFormat:@"availableCaptionTracks: %lu\n", (unsigned long)tracks.count];
    for (NSDictionary *track in tracks) {
        [out appendFormat:@"  - %@ | VSSID %@ | type %@ | %@ <%@>\n", track[@"languageCode"], track[@"VSSID"],
            track[@"trackType"], track[@"name"], track[@"class"]];
    }
    [out appendString:@"\n"];

    // Captured Format3 documents
    NSMutableArray *documents = [NSMutableArray array];
    @synchronized (self) {
        for (id document in gDocuments.keyEnumerator) {
            NSArray *info = [gDocuments objectForKey:document];
            if (info) [documents addObject:@[document, info[0], info[1]]];
        }
    }
    [documents sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [b[1] compare:a[1]]; }];

    [out appendFormat:@"== MLFormat3Captions documents alive: %lu (class %@)\n", (unsigned long)documents.count,
        NSClassFromString(@"MLFormat3Captions") ? @"present" : @"NOT FOUND"];

    NSArray <YTLCue *> *primary = nil;
    for (NSArray *entry in documents) {
        NSArray <YTLCue *> *sorted = [self cuesFromDocument:entry[0]];
        [out appendFormat:@"\n#%@ captured %@\n", entry[1], entry[2]];
        if (!sorted.count) {
            [out appendString:sorted ? @"  0 cues\n" : @"  captions tree unreadable\n"];
            continue;
        }
        NSUInteger inverted = 0, overlaps = 0, gaps = 0, empty = 0;
        double maxEnd = 0;
        for (NSUInteger i = 0; i < sorted.count; i++) {
            YTLCue *cue = sorted[i];
            if (cue.end < cue.start) inverted++;
            if (!cue.text.length) empty++;
            if (i > 0 && cue.start < sorted[i - 1].end) overlaps++;
            if (i > 0 && cue.start - sorted[i - 1].end > 10) gaps++;
            maxEnd = MAX(maxEnd, cue.end);
        }
        double first = sorted.firstObject.start;
        NSString *coverage = @"unknown (no duration)";
        if (duration > 0) {
            BOOL likelyComplete = first <= 30 && maxEnd >= duration - 30;
            coverage = [NSString stringWithFormat:@"%.1f%%–%.1f%% of video → %@", first / duration * 100, maxEnd / duration * 100,
                        likelyComplete ? @"LIKELY COMPLETE" : @"PARTIAL or UNKNOWN"];
        }
        [out appendFormat:@"  cues: %lu, range %@ → %@; end<start %lu, overlaps %lu, gaps>10s %lu, empty %lu\n  coverage: %@\n",
            (unsigned long)sorted.count, YTLTime(first), YTLTime(maxEnd), (unsigned long)inverted, (unsigned long)overlaps,
            (unsigned long)gaps, (unsigned long)empty, coverage];
        if (!primary) primary = sorted;
    }
    if (primary) {
        NSString *current = isnan(now) ? nil : YTLActiveText(primary, now);
        [out appendFormat:@"\ncue at %@: %@\n", YTLTime(now), current ? [current stringByReplacingOccurrencesOfString:@"\n" withString:@" | "] : @"(none)"];
    }

    [out appendString:@"\n== Runtime classes\n"];
    YTLDumpClass(out, @"YTPlayerViewController", @"pause|play|seek|rate|state");
    YTLDumpClass(out, @"MLInnerTubeCaptionController", nil);
    YTLDumpClass(out, @"YTCaptionViewController", nil);
    YTLDumpClass(out, @"YTFormat3CaptionViewController", nil);

    YTLProbeReport *report = [YTLProbeReport new];
    report.summary = out;
    NSMutableString *full = [out mutableCopy];
    [full appendFormat:@"\n== All cues, most recent document (%lu)\n", (unsigned long)primary.count];
    for (YTLCue *cue in primary) {
        [full appendFormat:@"[%@ → %@] %@\n", YTLTime(cue.start), YTLTime(cue.end), [cue.text stringByReplacingOccurrencesOfString:@"\n" withString:@" / "]];
    }
    report.full = full;
    report.fileName = [NSString stringWithFormat:@"YTLanguage-v%s-diagnostics-%@.txt", YTL_VERSION, videoID ?: @"unknown"];
    return report;
}

@end
