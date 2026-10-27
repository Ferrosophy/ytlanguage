#import "YTLWordCardViewController.h"
#import "../Services/YTLTranslator.h"
#import "../Services/YTLWordStore.h"

@implementation YTLWordCardViewController {
    NSString *_word, *_sentence, *_sentenceTranslation, *_videoID;
    long long _timeMs;
    NSString *_definition;
    UILabel *_meaningLabel;
    UIButton *_saveButton;
}

- (instancetype)initWithWord:(NSString *)word sentence:(NSString *)sentence translation:(NSString *)translation
                     videoID:(NSString *)videoID timeMs:(long long)timeMs {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _word = [word copy];
        _sentence = [sentence copy];
        _sentenceTranslation = [translation copy];
        _videoID = [videoID copy];
        _timeMs = timeMs;
        self.modalPresentationStyle = UIModalPresentationPageSheet;
        // iOS 15+; @available needs ___isOSVersionAtLeast, which the Linux toolchain does not link.
        if ([self respondsToSelector:@selector(sheetPresentationController)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
            UISheetPresentationController *sheet = self.sheetPresentationController;
            sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
            sheet.prefersGrabberVisible = YES;
#pragma clang diagnostic pop
        }
    }
    return self;
}

static UILabel *YTLLabel(UIFont *font, UIColor *color) {
    UILabel *label = [UILabel new];
    label.font = font;
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UILabel *wordLabel = YTLLabel([UIFont systemFontOfSize:30 weight:UIFontWeightBold], UIColor.labelColor);
    wordLabel.text = _word;
    _meaningLabel = YTLLabel([UIFont systemFontOfSize:17], UIColor.labelColor);
    _meaningLabel.text = @"查询中…";

    UILabel *contextTitle = YTLLabel([UIFont systemFontOfSize:13 weight:UIFontWeightSemibold], UIColor.secondaryLabelColor);
    contextTitle.text = @"原句";
    UILabel *contextLabel = YTLLabel([UIFont systemFontOfSize:15], UIColor.secondaryLabelColor);
    NSMutableAttributedString *context = [[NSMutableAttributedString alloc] initWithString:_sentence ?: @""];
    NSRange hit = [_sentence rangeOfString:_word];
    if (hit.location != NSNotFound) [context addAttribute:NSForegroundColorAttributeName value:UIColor.labelColor range:hit];
    if (_sentenceTranslation.length) [context appendAttributedString:[[NSAttributedString alloc] initWithString:[@"\n" stringByAppendingString:_sentenceTranslation]]];
    contextLabel.attributedText = context;

    _saveButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _saveButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [_saveButton addTarget:self action:@selector(save) forControlEvents:UIControlEventTouchUpInside];
    [self updateSaveButton];

    UIButton *dictionaryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [dictionaryButton setTitle:@"系统词典" forState:UIControlStateNormal];
    dictionaryButton.titleLabel.font = [UIFont systemFontOfSize:17];
    [dictionaryButton addTarget:self action:@selector(openSystemDictionary) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[_saveButton, dictionaryButton]];
    buttons.axis = UILayoutConstraintAxisHorizontal;
    buttons.distribution = UIStackViewDistributionFillEqually;
    buttons.spacing = 12;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[wordLabel, _meaningLabel, contextTitle, contextLabel, buttons]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    [stack setCustomSpacing:20 afterView:_meaningLabel];
    [stack setCustomSpacing:4 afterView:contextTitle];
    [stack setCustomSpacing:24 afterView:contextLabel];

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeClose];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    closeButton.accessibilityLabel = @"关闭";
    [closeButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];
    [self.view addSubview:closeButton];
    [scroll addSubview:stack];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [closeButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:14],
        [closeButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [closeButton.widthAnchor constraintEqualToConstant:30],
        [closeButton.heightAnchor constraintEqualToConstant:30],
        [scroll.topAnchor constraintEqualToAnchor:closeButton.bottomAnchor constant:4],
        [scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
    ]];

    __weak typeof(self) weakSelf = self;
    [YTLTranslator.shared lookupWord:_word context:_sentence completion:^(NSString *translation, NSArray <NSString *> *definitions, NSString *provider, NSString *error) {
        [weakSelf showTranslation:translation definitions:definitions provider:provider error:error];
    }];
}

- (void)showTranslation:(NSString *)translation definitions:(NSArray <NSString *> *)definitions provider:(NSString *)provider error:(NSString *)error {
    if (!translation.length && !definitions.count) {
        _meaningLabel.text = [NSString stringWithFormat:@"没有查到释义\n%@", error ?: @""];
        _meaningLabel.textColor = UIColor.secondaryLabelColor;
        return;
    }
    NSMutableArray *lines = [NSMutableArray array];
    if (translation.length) [lines addObject:translation];
    [lines addObjectsFromArray:definitions];
    _definition = [lines componentsJoinedByString:@"\n"];
    NSString *source = [provider isEqualToString:@"DeepSeek"] ? @"DeepSeek" : @"Google 翻译";
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:_definition attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:17] }];
    if (translation.length) [text addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:20 weight:UIFontWeightSemibold] range:NSMakeRange(0, translation.length)];
    [text appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\n来源：%@", source] attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:12], NSForegroundColorAttributeName: UIColor.tertiaryLabelColor }]];
    _meaningLabel.attributedText = text;
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)updateSaveButton {
    BOOL saved = [YTLWordStore.shared hasWord:_word language:@"en"];
    [_saveButton setTitle:saved ? @"已收藏 ✓" : @"收藏单词" forState:UIControlStateNormal];
}

- (void)save {
    NSString *error = nil;
    if (![YTLWordStore.shared saveWord:_word definition:_definition language:@"en" videoID:_videoID timeMs:_timeMs error:&error]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"收藏失败" message:error preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    [self updateSaveButton];
    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
}

- (void)openSystemDictionary {
    if (![UIReferenceLibraryViewController dictionaryHasDefinitionForTerm:_word]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"系统词典没有这个词"
            message:@"可以在 iPhone「设置 › 通用 › 词典」中下载英汉词典。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    [self presentViewController:[[UIReferenceLibraryViewController alloc] initWithTerm:_word] animated:YES completion:nil];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    // Only when the card itself goes away, not when it presents the dictionary on top.
    if (self.isBeingDismissed || self.presentingViewController == nil) {
        void (^onDismiss)(void) = self.onDismiss;
        self.onDismiss = nil;
        if (onDismiss) onDismiss();
    }
}

@end
