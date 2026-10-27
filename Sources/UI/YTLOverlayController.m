#import "YTLOverlayController.h"
#import "YTLSubtitleOverlayView.h"
#import "YTLSubtitleSession.h"
#import "YTLWordCardViewController.h"
#import "YTLTranscriptDrawer.h"
#import "../Services/YTLSubtitleStyle.h"
#import "../HostAdapter/YTLHostHeaders.h"
#import "../HostAdapter/YTLHostCaptions.h"
#import "../HostAdapter/YTLCaptionProbe.h"
#import "../HostAdapter/YTLPlayback.h"
#import "../Services/YTLSettings.h"
#import <objc/runtime.h>

static const NSTimeInterval kTickInterval = 0.15;
static const CGFloat kControlsBottomLimit = 0.76;   // keep subtitles above the progress bar while controls show
static const void *kControllerKey = &kControllerKey;
static NSHashTable <UIViewController *> *gNativeCaptionControllers;
static NSHashTable <YTMainAppControlsOverlayView *> *gControlsOverlays;
static NSHashTable <UIViewController *> *gPiPHiddenCaptions;   // caption VCs we setCaptionsHidden:YES for PiP
static BOOL gPiPActive;
static BOOL gSuppressNative;                         // YouTube's captions must stay hidden
static NSHashTable <UIView *> *gHiddenNativeViews;   // views YTLanguage hid, restored when suppression ends
static CADisplayLink *gNativeCaptionLink;

// Transparent view on top of the player that forwards touches on the subtitle's original line to the
// subtitle view underneath (which may sit below YouTube's controls). Everything else falls through.
@interface YTLTouchProxyView : UIView
@property (nonatomic, weak) UIView *target;
@property (nonatomic, copy) BOOL (^shouldPassThrough)(void);
@end

@implementation YTLTouchProxyView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *target = self.target;
    if (!target.window || target.hidden || (self.shouldPassThrough && self.shouldPassThrough())) return nil;
    return [target hitTest:[self convertPoint:point toView:target] withEvent:event];
}

@end

@interface YTLOverlayController () <YTLSubtitleOverlayDelegate>
@end

@implementation YTLOverlayController {
    __weak YTPlayerViewController *_player;
    YTLSubtitleOverlayView *_overlay;
    NSTimer *_timer;
    NSUInteger _sequenceBaseline;
    BOOL _hasHadSession;
    double _lastTime;
    BOOL _isPlaying;
    BOOL _frozen;
    NSString *_pauseStatus;
    YTLTranscriptDrawer *_drawer;
    BOOL _captionsOn;
    BOOL _controlsVisible;
    NSString *_controlsSignals;
    YTLTouchProxyView *_touchProxy;
    NSString *_layering;
}

+ (void)registerControlsOverlay:(UIView *)overlay {
    if (!gControlsOverlays) gControlsOverlays = [NSHashTable weakObjectsHashTable];
    [gControlsOverlays addObject:(YTMainAppControlsOverlayView *)overlay];
}

+ (void)registerNativeCaptionController:(UIViewController *)controller {
    if (!gNativeCaptionControllers) gNativeCaptionControllers = [NSHashTable weakObjectsHashTable];
    [gNativeCaptionControllers addObject:controller];
}

// No subtitles in picture-in-picture: our overlay is not part of the PiP window, and YouTube's own captions are
// switched off through YTCaptionViewController -setCaptionsHidden: (runtime-observed), then restored afterwards.
+ (void)setPictureInPictureActive:(BOOL)active {
    gPiPActive = active;
    if (!gPiPHiddenCaptions) gPiPHiddenCaptions = [NSHashTable weakObjectsHashTable];
    for (UIViewController *controller in gNativeCaptionControllers) {
        if (![controller respondsToSelector:@selector(setCaptionsHidden:)]) continue;
        if (active) {
            NSNumber *hidden = nil;
            @try {
                hidden = [controller valueForKey:@"captionsHidden"];   // ivar _captionsHidden
            } @catch (NSException *e) {
            }
            if (hidden.boolValue) continue;
            [(YTCaptionViewController *)controller setCaptionsHidden:YES];
            [gPiPHiddenCaptions addObject:controller];
        } else if ([gPiPHiddenCaptions containsObject:controller]) {
            [(YTCaptionViewController *)controller setCaptionsHidden:NO];
        }
    }
    if (!active) [gPiPHiddenCaptions removeAllObjects];
}

+ (YTLOverlayController *)controllerForPlayer:(YTPlayerViewController *)player {
    return player ? objc_getAssociatedObject(player, kControllerKey) : nil;
}

+ (void)attachToPlayer:(YTPlayerViewController *)player {
    if (!player || [self controllerForPlayer:player]) return;
    YTLOverlayController *controller = [[self alloc] initWithPlayer:player];
    objc_setAssociatedObject(player, kControllerKey, controller, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (instancetype)initWithPlayer:(YTPlayerViewController *)player {
    if ((self = [super init])) {
        _player = player;
        _overlay = [[YTLSubtitleOverlayView alloc] initWithFrame:CGRectZero];
        _overlay.delegate = self;
        _lastTime = -1;
        _pauseStatus = [YTLPlayback canPause:player] ? @"有 pause/play 方法，未实测" : @"播放器没有 pause/play 方法，查词时不暂停";
        __weak typeof(self) weakSelf = self;
        _timer = [NSTimer timerWithTimeInterval:kTickInterval repeats:YES block:^(NSTimer *timer) { [weakSelf tick]; }];
        [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(settingsChanged) name:YTLSettingsDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [_timer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)settingsChanged {
    _overlay.style = [YTLSubtitleStyle current];
    [_session resegmentIfNeeded];
    [self tick];
}

- (void)showTranscript {
    YTPlayerViewController *player = _player;
    UIWindow *window = player.isViewLoaded ? player.view.window : nil;
    if (!window) return;
    if (_drawer.superview) return;
    _drawer = [[YTLTranscriptDrawer alloc] initWithPlayer:player];
    [_drawer presentInWindow:window];
    [_drawer updateWithSession:_session time:_lastTime];
}

// YouTube re-shows its caption view when the controls show or hide (relayout), so hiding it once per 0.15 s tick
// let it flash. It is now re-hidden in the same frame: from the caption controller's own layout and
// setCaptionsHidden: hooks (Tweak.x), plus a display link that runs only while hiding is on.
// The view and its captionView (it may live in another container) are both hidden.
+ (void)enforceNativeCaptions:(UIViewController *)controller {
    if (!gSuppressNative || !controller.isViewLoaded) return;
    if (!gHiddenNativeViews) gHiddenNativeViews = [NSHashTable weakObjectsHashTable];
    NSMutableArray <UIView *> *views = [NSMutableArray arrayWithObject:controller.view];
    if ([controller respondsToSelector:@selector(captionView)]) {
        id captionView = [(YTCaptionViewController *)controller captionView];
        if ([captionView isKindOfClass:UIView.class] && captionView != controller.view) [views addObject:captionView];
    }
    for (UIView *view in views) {
        if (view.hidden) continue;
        view.hidden = YES;
        [gHiddenNativeViews addObject:view];
    }
}

+ (void)enforceAllNativeCaptions {
    for (UIViewController *controller in gNativeCaptionControllers) [self enforceNativeCaptions:controller];
}

- (void)setNativeCaptionsHidden:(BOOL)hide {
    gSuppressNative = hide;
    if (!gNativeCaptionLink) {
        gNativeCaptionLink = [CADisplayLink displayLinkWithTarget:YTLOverlayController.class selector:@selector(enforceAllNativeCaptions)];
        [gNativeCaptionLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    gNativeCaptionLink.paused = !hide;
    if (hide) {
        [YTLOverlayController enforceAllNativeCaptions];
        return;
    }
    for (UIView *view in gHiddenNativeViews) view.hidden = NO;   // only undo what we did
    [gHiddenNativeViews removeAllObjects];
}

- (void)tick {
    YTPlayerViewController *player = _player;
    if (!player) {
        [_timer invalidate];
        [self setNativeCaptionsHidden:NO];
        [_drawer dismiss];
        return;
    }
    UIView *host = player.isViewLoaded ? player.view : nil;
    if (!host.window) {
        // Player left the screen (closed, minimized to another window): drop the drawer safely.
        [_drawer dismiss];
        _drawer = nil;
        return;
    }
    [self placeOverlayInHost:host];

    double time = [player respondsToSelector:@selector(currentVideoMediaTime)] ? player.currentVideoMediaTime : 0;
    _isPlaying = _lastTime >= 0 && fabs(time - _lastTime) > 0.01;
    _lastTime = time;

    NSString *videoID = [player respondsToSelector:@selector(currentVideoID)] ? player.currentVideoID : nil;
    BOOL ad = [player respondsToSelector:@selector(isPlayingAd)] && player.isPlayingAd;
    if (videoID.length && !ad && ![videoID isEqualToString:_session.videoID]) {
        [_session invalidate];
        // The first video may already have its document; later videos only accept documents created after the switch.
        _sequenceBaseline = _hasHadSession ? YTLCaptionProbe.currentSequence : 0;
        _hasHadSession = YES;
        _session = [[YTLSubtitleSession alloc] initWithVideoID:videoID];
    }

    if (_session && !ad) {
        NSUInteger sequence = 0;
        MLFormat3Captions *document = [YTLCaptionProbe latestDocumentAfterSequence:_sequenceBaseline sequence:&sequence];
        if (document && sequence != _session.documentSequence) {
            NSArray *cues = [YTLCaptionProbe cuesFromDocument:document];
            if (cues.count) {
                [_session setSourceCues:cues language:[YTLHostCaptions activeTrackLanguage:player] documentSequence:sequence];
                [_session startHumanTrackLookupWithPlayer:player];
            }
        }
    }

    if (_drawer.superview) [_drawer updateWithSession:_session time:time];
    else _drawer = nil;

    // Translation keeps running even while subtitles are hidden, so the transcript list fills in.
    NSUInteger index = [_session sentenceIndexAtTime:time];
    [_session pumpTranslationsFromIndex:index];

    if (_frozen) return;
    YTLSubtitleMode mode = YTLSettings.mode;
    BOOL portrait = host.window.bounds.size.width < host.window.bounds.size.height;
    if (portrait || gPiPActive) {
        // No subtitles at all in portrait / PiP: ours hidden and YouTube's hidden too (the style preview is the exception).
        [self setNativeCaptionsHidden:YES];
        if (YTLSettings.stylePreviewActive) [self showPreviewForMode:mode];
        else [_overlay showOriginal:nil translation:nil];
        return;
    }
    // CC turned off in YouTube → our subtitles go away too.
    _captionsOn = [YTLHostCaptions captionsEnabledForPlayer:player];
    BOOL active = mode != YTLSubtitleModeOff && _captionsOn && _session.sentences.count && !ad;
    [self setNativeCaptionsHidden:active];
    // Lift above the progress bar only while the controls show; the style preview always shows the set position.
    _controlsVisible = [self controlsVisibleInHost:host];
    _overlay.bottomLimit = _controlsVisible && !YTLSettings.stylePreviewActive ? kControlsBottomLimit : 1;
    if (!active) {
        if (YTLSettings.stylePreviewActive) [self showPreviewForMode:mode];
        else [_overlay showOriginal:nil translation:nil];
        return;
    }

    if (index == NSNotFound && YTLSettings.stylePreviewActive) {
        [self showPreviewForMode:mode];
        return;
    }
    NSString *original = index != NSNotFound ? _session.sentences[index].text : nil;
    NSString *translation = [_session translationForSentence:index time:time];
    switch (mode) {
        case YTLSubtitleModeOriginal:
            [_overlay showOriginal:original translation:nil];
            break;
        case YTLSubtitleModeTranslation:
            [_overlay showOriginal:nil translation:translation ?: original];   // fall back to the original line
            break;
        default:
            [_overlay showOriginal:original translation:translation];
            break;
    }
}

- (YTMainAppControlsOverlayView *)controlsOverlayInHost:(UIView *)host {
    for (YTMainAppControlsOverlayView *overlay in gControlsOverlays) {
        if ([overlay isDescendantOfView:host]) return overlay;
    }
    return nil;
}

static BOOL YTLChainVisible(UIView *view, UIView *stop) {
    for (; view && view != stop; view = view.superview) {
        if (view.hidden || view.alpha < 0.01) return NO;
    }
    return YES;
}

// Preferred: the subtitle view sits just below YouTube's controls overlay, in the same parent and with the same
// frame. The play/pause buttons then draw on top of it, and when a side panel (comments etc.) shrinks the
// controls area, the subtitle shrinks with it instead of covering the panel. Touches reach the subtitle through
// a transparent proxy on top of the player, which passes everything through while the controls are visible.
// Fallback (no controls overlay found, or its parent is hidden): on top of the player view, as before.
- (void)placeOverlayInHost:(UIView *)host {
    YTMainAppControlsOverlayView *controls = [self controlsOverlayInHost:host];
    UIView *parent = controls.superview;
    // Only trust it if it spans most of the player height (a side panel narrows it, nothing should make it short).
    CGRect inHost = parent ? [parent convertRect:controls.frame toView:host] : CGRectZero;
    BOOL below = parent && inHost.size.width > 100 && inHost.size.height >= host.bounds.size.height * 0.6 && YTLChainVisible(parent, host);
    if (below) {
        NSUInteger controlsIndex = [parent.subviews indexOfObject:controls];
        if (_overlay.superview != parent || controlsIndex == 0 || parent.subviews[controlsIndex - 1] != _overlay) {
            [_overlay removeFromSuperview];
            [parent insertSubview:_overlay belowSubview:controls];
        }
        if (!CGRectEqualToRect(_overlay.frame, controls.frame)) _overlay.frame = controls.frame;
        if (!_touchProxy) {
            _touchProxy = [[YTLTouchProxyView alloc] initWithFrame:host.bounds];
            _touchProxy.target = _overlay;
            __weak typeof(self) weakSelf = self;
            _touchProxy.shouldPassThrough = ^BOOL {
                typeof(self) strongSelf = weakSelf;
                return !strongSelf || strongSelf->_controlsVisible;
            };
        }
        if (_touchProxy.superview != host) [host addSubview:_touchProxy];
        else if (host.subviews.lastObject != _touchProxy) [host bringSubviewToFront:_touchProxy];
        if (!CGRectEqualToRect(_touchProxy.frame, host.bounds)) _touchProxy.frame = host.bounds;
        _layering = @"below controls";
        return;
    }
    [_touchProxy removeFromSuperview];
    if (_overlay.superview != host) {
        [_overlay removeFromSuperview];
        [host addSubview:_overlay];
    } else if (host.subviews.lastObject != _overlay) {
        [host bringSubviewToFront:_overlay];
    }
    if (!CGRectEqualToRect(_overlay.frame, host.bounds)) _overlay.frame = host.bounds;
    _layering = controls ? @"on top (controls parent hidden or too small)" : @"on top (no controls overlay)";
}

// Two signals, both must agree: the player's arePlayerControlsHidden (runtime-observed) and whether a
// YTVideoOverlay button inside YTMainAppControlsOverlayView is actually visible (it fades with the controls).
- (BOOL)controlsVisibleInHost:(UIView *)host {
    YTPlayerViewController *player = _player;
    NSNumber *api = [player respondsToSelector:@selector(arePlayerControlsHidden)] ? @(!player.arePlayerControlsHidden) : nil;
    NSNumber *button = nil;
    YTMainAppControlsOverlayView *overlay = [self controlsOverlayInHost:host];
    if ([overlay respondsToSelector:@selector(overlayButtons)]) {
        NSDictionary *buttons = overlay.overlayButtons;
        UIView *probe = buttons[@"YTLanguage"] ?: buttons.allValues.firstObject;
        if (probe) button = @(probe.window != nil && YTLChainVisible(probe, host));
    }
    _controlsSignals = [NSString stringWithFormat:@"api %@ · button %@", api ? (api.boolValue ? @"shown" : @"hidden") : @"n/a",
                        button ? (button.boolValue ? @"shown" : @"hidden") : @"n/a"];
    if (!api && !button) return NO;
    return (api ? api.boolValue : YES) && (button ? button.boolValue : YES);
}

// Sample text while the style editor is open and no real subtitle is on screen.
- (void)showPreviewForMode:(YTLSubtitleMode)mode {
    NSString *original = @"This is how your subtitles will look.";
    NSString *translation = @"这是字幕样式预览。";
    if (mode == YTLSubtitleModeOriginal) [_overlay showOriginal:original translation:nil];
    else if (mode == YTLSubtitleModeTranslation) [_overlay showOriginal:nil translation:translation];
    else [_overlay showOriginal:original translation:translation];
}

#pragma mark - Word lookup

- (void)subtitleOverlay:(YTLSubtitleOverlayView *)overlay didSelectWord:(NSString *)word inSentence:(NSString *)sentence {
    YTPlayerViewController *player = _player;
    if (!player || _frozen) return;
    _frozen = YES;

    double time = _lastTime;
    BOOL pausedByUs = NO;
    if (YTLSettings.pauseOnLookup && _isPlaying && [YTLPlayback canPause:player]) {
        [YTLPlayback pause:player];
        pausedByUs = YES;
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            YTPlayerViewController *p = strongSelf->_player;
            if (!strongSelf || !p) return;
            BOOL stopped = fabs(p.currentVideoMediaTime - time) < 0.3;
            strongSelf->_pauseStatus = stopped ? @"pause 有效（时钟已停止）" : @"pause 无效（调用后时钟仍在走）";
        });
    }

    NSUInteger index = [_session sentenceIndexAtTime:time];
    NSString *translation = [_session translationForSentence:index time:time];
    YTLWordCardViewController *card = [[YTLWordCardViewController alloc] initWithWord:word sentence:sentence translation:translation
                                                                              videoID:_session.videoID timeMs:(long long)(time * 1000)];
    __weak typeof(self) weakSelf = self;
    card.onDismiss = ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_frozen = NO;
        [strongSelf->_overlay highlightWordRange:NSMakeRange(NSNotFound, 0)];
        YTPlayerViewController *p = strongSelf->_player;
        // Resume only if we paused and the user did not seek meanwhile.
        if (pausedByUs && p && fabs(p.currentVideoMediaTime - time) < 1.0) [YTLPlayback play:p];
    };

    UIViewController *top = player.view.window.rootViewController ?: player;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:card animated:YES completion:nil];
}

- (NSString *)statusDescription {
    NSUInteger registered = gNativeCaptionControllers.allObjects.count;
    YTPlayerViewController *player = _player;
    return [NSString stringWithFormat:@"mode %ld · CC %@ · controls %@ (%@) · overlay %@ · playing %@ · drawer %@ · max words %ld\n%@\nnative caption VCs: %lu registered, %lu views hidden by YTLanguage\npause-on-lookup: %@ · %@\nseekToTime: %@ · video title: %@",
            (long)YTLSettings.mode, _captionsOn ? @"on" : @"off", _controlsVisible ? @"shown" : @"hidden", _controlsSignals ?: @"-",
            _overlay.superview ? [NSString stringWithFormat:@"%@ %@", _layering ?: @"attached", NSStringFromCGRect(_overlay.frame)] : @"detached", _isPlaying ? @"yes" : @"no",
            _drawer.superview ? @"open" : @"closed", (long)YTLSettings.maxSentenceWords,
            _session ? _session.statusDescription : @"no session (no video ID yet)",
            (unsigned long)registered, (unsigned long)gHiddenNativeViews.allObjects.count,
            YTLSettings.pauseOnLookup ? @"on" : @"off", _pauseStatus,
            [player respondsToSelector:@selector(seekToTime:)] ? @"available" : @"MISSING",
            [YTLHostCaptions videoTitleForPlayer:player] ? @"found" : @"not found"];
}

@end
