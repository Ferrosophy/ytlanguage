// YTLanguage — host hooks.
//
// - Player top-row button via YTVideoOverlay (PoomSmart, MIT), which the user already injects;
//   tapping it opens the YTLanguage panel (subtitle mode, translation, lookup, diagnostics).
// - Bilingual subtitle overlay attached to YTPlayerViewController's view.
// - MLFormat3Captions documents are recorded as the host creates/uses them (observation only).
// - YouTube's own caption view controllers are registered so the overlay can hide them while active.
// Declarations and provenance: Sources/HostAdapter/YTLHostHeaders.h.
// If YTVideoOverlay is missing, falls back to a floating badge (public UIKit only).

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/log.h>
#import "Sources/HostAdapter/YTLHostHeaders.h"
#import "Sources/HostAdapter/YTLCaptionProbe.h"
#import "Sources/UI/YTLOverlayController.h"
#import "Sources/UI/YTLPanelViewController.h"
#import "Sources/UI/YTLStudyViewController.h"
#import "Sources/Services/YTLWordStore.h"

#ifndef YTL_VERSION
#define YTL_VERSION "dev"
#endif

#define TweakKey @"YTLanguage"
#define TranscriptKey @"YTLTranscript"
#define OVERLAY_BUTTON_SIZE 24

static os_log_t YTLLog(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create("com.ytlanguage.tweak", "M0"); });
    return log;
}

static UIImage *YTLSymbol(NSString *name) {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:OVERLAY_BUTTON_SIZE * 0.8 weight:UIImageSymbolWeightMedium];
    UIImage *image = [UIImage systemImageNamed:name withConfiguration:config];
    return [image imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
}

// nil for buttons that are not ours, so the hook falls through to %orig.
static UIImage *YTLButtonImage(NSString *tweakId) {
    if ([tweakId isEqualToString:TweakKey]) return YTLSymbol(@"character.book.closed");
    if ([tweakId isEqualToString:TranscriptKey]) return YTLSymbol(@"list.bullet.rectangle");
    return nil;
}

static id YTLValueForKey(id object, NSString *key) {
    @try {
        return [object valueForKey:key];
    } @catch (NSException *e) {
        os_log(YTLLog(), "[YTL] valueForKey %{public}@ failed: %{public}@", key, e.reason);
        return nil;
    }
}

static UIViewController *YTLTopViewController(UIViewController *from) {
    UIViewController *top = from.view.window.rootViewController ?: from;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

// overlayVC is YTMainAppVideoPlayerOverlayViewController; its parent is YTPlayerViewController (per YouPiP).
static YTPlayerViewController *YTLPlayerFromOverlay(UIViewController *overlayVC) {
    UIViewController *parent = overlayVC.parentViewController;
    YTPlayerViewController *player = [parent isKindOfClass:NSClassFromString(@"YTPlayerViewController")] ? (YTPlayerViewController *)parent : nil;
    [YTLOverlayController attachToPlayer:player];
    return player;
}

static void YTLShowPanel(UIViewController *overlayVC) {
    YTPlayerViewController *player = YTLPlayerFromOverlay(overlayVC);
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[[YTLPanelViewController alloc] initWithPlayer:player]];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    // Half-height sheet (iOS 15+) keeps the video visible while adjusting subtitle style.
    if ([nav respondsToSelector:@selector(sheetPresentationController)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
        nav.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
        nav.sheetPresentationController.prefersGrabberVisible = YES;
#pragma clang diagnostic pop
    }
    [YTLTopViewController(overlayVC) presentViewController:nav animated:YES completion:nil];
}

static void YTLShowTranscript(UIViewController *overlayVC) {
    [[YTLOverlayController controllerForPlayer:YTLPlayerFromOverlay(overlayVC)] showTranscript];
}

// --- Player overlay button (via YTVideoOverlay) ---

%group Top

%hook YTMainAppControlsOverlayView

- (UIImage *)buttonImage:(NSString *)tweakId {
    [YTLOverlayController registerControlsOverlay:self];
    return YTLButtonImage(tweakId) ?: %orig;
}

%new(v@:@)
- (void)didPressYTLanguage:(id)arg {
    YTLShowPanel(YTLValueForKey(self, @"_eventsDelegate"));
}

%new(v@:@)
- (void)didPressYTLTranscript:(id)arg {
    YTLShowTranscript(YTLValueForKey(self, @"_eventsDelegate"));
}

%end

%end

%group Bottom

%hook YTInlinePlayerBarContainerView

- (UIImage *)buttonImage:(NSString *)tweakId {
    return YTLButtonImage(tweakId) ?: %orig;
}

%new(v@:@)
- (void)didPressYTLanguage:(id)arg {
    YTLShowPanel(YTLValueForKey(self.delegate, @"_delegate"));
}

%new(v@:@)
- (void)didPressYTLTranscript:(id)arg {
    YTLShowTranscript(YTLValueForKey(self.delegate, @"_delegate"));
}

%end

%end

// --- Caption capture (observation only; never changes what the host does) ---

%group Captions

%hook MLFormat3Captions

+ (id)allocWithZone:(struct _NSZone *)zone {
    id document = %orig;
    [YTLCaptionProbe noteFormat3Captions:document];
    return document;
}

- (YTIntervalTree *)captions {
    [YTLCaptionProbe noteFormat3Captions:self];
    return %orig;
}

%end

%end

// --- Subtitle overlay ---

%group Player

%hook YTPlayerViewController

// UIKit lifecycle method; attach is idempotent (associated object check).
- (void)viewDidLayoutSubviews {
    %orig;
    [YTLOverlayController attachToPlayer:self];
}

%end

%end

// PiP start/stop callbacks listed by the v0.4.0 runtime dump; installed only if both exist.
%group PiP

%hook YTPlayerViewController

- (void)playbackControllerDidStartPIP:(id)controller {
    %orig;
    [YTLOverlayController setPictureInPictureActive:YES];
}

- (void)playbackControllerDidStopPIP:(id)controller {
    %orig;
    [YTLOverlayController setPictureInPictureActive:NO];
}

%end

%end

%group NativeCaptions

%hook YTCaptionViewController

- (void)viewDidLoad {
    %orig;
    [YTLOverlayController registerNativeCaptionController:self];
}

// YouTube relayouts / re-shows its captions when the controls toggle; re-hide in the same pass while YTLanguage
// shows its own subtitles. Both are UIKit / runtime-observed (v0.4.0 dump) methods with known signatures.
- (void)viewDidLayoutSubviews {
    %orig;
    [YTLOverlayController enforceNativeCaptions:self];
}

- (void)setCaptionsHidden:(BOOL)hidden {
    %orig;
    [YTLOverlayController enforceNativeCaptions:self];
}

%end

%end

// --- 双语学习 section in YouTube settings, Tweaks group ---
// Same mechanism as YouPiP / YTVideoOverlay (MIT): a custom settings category added to
// YTAppSettingsPresentationData +settingsCategoryOrder and filled in -updateSectionForCategory:withEntry:.
// With YouGroupSettings installed, its +[YTSettingsGroupData tweaks] list decides the Tweaks group; otherwise
// the category goes first in group type 1, as YouPiP does.

static const NSInteger YTLStudySection = 2617;

// The study page always opens as its own full-screen page (UIKit navigation, close button). Pushed into YouTube's
// settings navigation, the UIKit back button was drawn off-screen (v0.7.0 / v0.8.0 screenshots).
static void YTLPresentStudy(UIViewController *from, BOOL sentences) {
    if (!from) return;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[[YTLStudyViewController alloc] initShowingSentences:sentences]];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    UIViewController *top = from;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:nav animated:YES completion:nil];
}

// The page YouTube pushes when 双语学习 is tapped in settings: titled 双语学习, or a settings page whose section
// controllers are exactly our category. v0.8.0 showed the embed check never matched, so what is actually pushed
// is recorded for diagnostics.
static BOOL YTLIsStudySettingsPage(UIViewController *vc) {
    if ([vc isKindOfClass:YTLStudyViewController.class]) return NO;
    id sections = [vc respondsToSelector:@selector(settingsSectionControllers)] ? YTLValueForKey(vc, @"settingsSectionControllers") : nil;
    NSArray *keys = [sections isKindOfClass:NSDictionary.class] ? [sections allKeys] : nil;
    NSString *title = vc.title ?: vc.navigationItem.title;
    YTLStudyViewController.settingsPushInfo = [NSString stringWithFormat:@"%@ title %@ sections %@",
        NSStringFromClass(vc.class), title ?: @"nil", keys ? [keys componentsJoinedByString:@","] : @"n/a"];
    return [title isEqualToString:@"双语学习"] || [keys isEqualToArray:@[@(YTLStudySection)]];
}

%group StudySettings

%hook YTAppSettingsPresentationData

+ (NSArray <NSNumber *> *)settingsCategoryOrder {
    NSArray <NSNumber *> *order = %orig;
    NSUInteger insertIndex = [order indexOfObject:@(1)];
    if (insertIndex != NSNotFound && ![order containsObject:@(YTLStudySection)]) {
        NSMutableArray <NSNumber *> *mutableOrder = order.mutableCopy;
        [mutableOrder insertObject:@(YTLStudySection) atIndex:insertIndex + 1];
        order = mutableOrder.copy;
    }
    return order;
}

%end

%hook YTSettingsGroupData

- (NSArray <NSNumber *> *)orderedCategories {
    Class groupData = objc_getClass("YTSettingsGroupData");
    if (class_getClassMethod(groupData, @selector(tweaks))) {
        id tweaks = ((id (*)(id, SEL))objc_msgSend)(groupData, @selector(tweaks));
        if ([tweaks isKindOfClass:NSMutableArray.class] && ![tweaks containsObject:@(YTLStudySection)]) [tweaks addObject:@(YTLStudySection)];
        return %orig;
    }
    NSArray *categories = %orig;
    if ([YTLValueForKey(self, @"type") unsignedIntegerValue] != 1 || [categories containsObject:@(YTLStudySection)]) return categories;
    NSMutableArray *mutableCategories = categories.mutableCopy;
    [mutableCategories insertObject:@(YTLStudySection) atIndex:0];
    return mutableCategories.copy;
}

%end

%hook YTSettingsSectionItemManager

- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry {
    if (category != YTLStudySection) {
        %orig;
        return;
    }
    id settingsVC = nil;
    for (NSString *key in @[@"_settingsViewControllerDelegate", @"_dataDelegate"]) {
        settingsVC = YTLValueForKey(self, key);
        if (settingsVC) break;
    }
    Class itemClass = objc_getClass("YTSettingsSectionItem");
    if (!settingsVC || !itemClass) return;
    __weak id weakVC = settingsVC;
    NSMutableArray *items = [NSMutableArray array];
    [items addObject:[itemClass itemWithTitle:@"单词" accessibilityIdentifier:nil
        detailTextBlock:^NSString *{ return [NSString stringWithFormat:@"%ld", (long)YTLWordStore.shared.wordCount]; }
        selectBlock:^BOOL (id cell, NSUInteger arg) { YTLPresentStudy(weakVC, NO); return YES; }]];
    [items addObject:[itemClass itemWithTitle:@"句子" accessibilityIdentifier:nil
        detailTextBlock:^NSString *{ return [NSString stringWithFormat:@"%ld", (long)YTLWordStore.shared.sentenceCount]; }
        selectBlock:^BOOL (id cell, NSUInteger arg) { YTLPresentStudy(weakVC, YES); return YES; }]];
    if ([settingsVC respondsToSelector:@selector(setSectionItems:forCategory:title:icon:titleDescription:headerHidden:)]) {
        YTIIcon *icon = [objc_getClass("YTIIcon") new];
        if ([icon respondsToSelector:@selector(setIconType:)]) icon.iconType = 540;   // YT_TRANSLATE (YouTubeHeader YTIcon.h)
        [settingsVC setSectionItems:items forCategory:YTLStudySection title:@"双语学习" icon:icon titleDescription:nil headerHidden:NO];
    } else {
        [settingsVC setSectionItems:items forCategory:YTLStudySection title:@"双语学习" titleDescription:nil headerHidden:NO];
    }
}

%end

%hook UINavigationController

// Only inside YouTube settings: the 双语学习 category page is replaced by the study page.
- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated {
    Class settingsClass = objc_getClass("YTSettingsViewController");
    if (settingsClass && [self.topViewController isKindOfClass:settingsClass] && YTLIsStudySettingsPage(viewController)) {
        YTLPresentStudy(self, NO);
        return;
    }
    %orig;
}

%end

%end

// --- Fallback floating badge (no YTVideoOverlay) ---

static UIWindow *YTLKeyWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) return window;
        }
    }
    return nil;
}

@interface YTLFallbackBadge : NSObject
+ (void)install;
@end

@implementation YTLFallbackBadge

+ (void)install {
    UIWindow *window = YTLKeyWindow();
    if (!window) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self install]; });
        return;
    }
    static const NSInteger kBadgeTag = 0x59544C; // 'YTL'
    if ([window viewWithTag:kBadgeTag]) return;

    UIButton *badge = [UIButton buttonWithType:UIButtonTypeSystem];
    badge.tag = kBadgeTag;
    [badge setTitle:@"YTL" forState:UIControlStateNormal];
    [badge setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    badge.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    badge.backgroundColor = [UIColor colorWithRed:0.85 green:0.1 blue:0.1 alpha:0.85];
    badge.layer.cornerRadius = 18;
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    [badge addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
    [window addSubview:badge];
    [NSLayoutConstraint activateConstraints:@[
        [badge.widthAnchor constraintEqualToConstant:36],
        [badge.heightAnchor constraintEqualToConstant:36],
        [badge.trailingAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [badge.bottomAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.bottomAnchor constant:-120],
    ]];
}

+ (void)tapped:(UIButton *)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"YTLanguage v%s", YTL_VERSION]
        message:@"YTVideoOverlay.dylib not found, so the player button is unavailable.\nInject YTVideoOverlay to get the in-player button."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *top = sender.window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:alert animated:YES completion:nil];
}

@end

// --- Init ---

// Mirrors YTVideoOverlay/Init.x, but checks that registration is actually available.
static BOOL YTLRegisterWithVideoOverlay(void) {
    dlopen([[NSString stringWithFormat:@"%@/Frameworks/YTVideoOverlay.dylib", NSBundle.mainBundle.bundlePath] UTF8String], RTLD_LAZY);
    Class manager = NSClassFromString(@"YTSettingsSectionItemManager");
    if (![manager respondsToSelector:@selector(registerTweak:metadata:)]) return NO;
    [manager registerTweak:TweakKey metadata:@{
        @"accessibilityLabel": @"YTLanguage",
        @"selector": @"didPressYTLanguage:",
    }];
    [manager registerTweak:TranscriptKey metadata:@{
        @"accessibilityLabel": @"YTLanguage 字幕列表",
        @"selector": @"didPressYTLTranscript:",
    }];
    return YES;
}

%ctor {
    os_log(YTLLog(), "[YTL] v%{public}s loaded into %{public}@", YTL_VERSION, NSBundle.mainBundle.bundleIdentifier);

    Class captions = objc_getClass("MLFormat3Captions");
    if (captions && class_getInstanceMethod(captions, @selector(captions))) {
        %init(Captions);
    } else {
        os_log(YTLLog(), "[YTL] MLFormat3Captions -captions not found; caption capture disabled");
    }
    Class playerClass = objc_getClass("YTPlayerViewController");
    if (playerClass) {
        %init(Player);
        if (class_getInstanceMethod(playerClass, @selector(playbackControllerDidStartPIP:)) &&
            class_getInstanceMethod(playerClass, @selector(playbackControllerDidStopPIP:))) {
            %init(PiP);
        }
    }
    if (objc_getClass("YTCaptionViewController")) {
        %init(NativeCaptions);
    }
    if (objc_getClass("YTAppSettingsPresentationData") && objc_getClass("YTSettingsGroupData") && objc_getClass("YTSettingsSectionItemManager") && objc_getClass("YTSettingsViewController")) {
        %init(StudySettings);
    }

    // YTVideoOverlay buttons are off unless "YTVideoOverlay-<id>-Enabled" is set; default ours to on
    // (registerDefaults never overrides a value the user picked in YTVideoOverlay settings).
    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        @"YTVideoOverlay-" TweakKey @"-Enabled": @YES,
        @"YTVideoOverlay-" TranscriptKey @"-Enabled": @YES,
    }];

    if (YTLRegisterWithVideoOverlay()) {
        os_log(YTLLog(), "[YTL] registered with YTVideoOverlay");
        %init(Top);
        %init(Bottom);
        return;
    }

    os_log(YTLLog(), "[YTL] YTVideoOverlay unavailable, using fallback badge");
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                    object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *note) {
        [YTLFallbackBadge install];
    }];
}
