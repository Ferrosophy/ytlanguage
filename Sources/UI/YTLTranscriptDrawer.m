#import "YTLTranscriptDrawer.h"
#import "YTLSubtitleSession.h"
#import "../HostAdapter/YTLHostHeaders.h"
#import "../HostAdapter/YTLHostCaptions.h"
#import "../HostAdapter/YTLPlayback.h"
#import "../Services/YTLWordStore.h"

static NSString *const kCellID = @"YTLTranscriptCell";
static const NSTimeInterval kRefreshInterval = 1.0;

static NSString *YTLClock(double seconds) {
    long s = (long)MAX(0, seconds);
    return s >= 3600 ? [NSString stringWithFormat:@"%ld:%02ld:%02ld", s / 3600, (s / 60) % 60, s % 60]
                     : [NSString stringWithFormat:@"%ld:%02ld", s / 60, s % 60];
}

#pragma mark - Cell

@interface YTLTranscriptCell : UITableViewCell
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *originalLabel;
@property (nonatomic, strong) UILabel *translationLabel;
- (void)setCurrent:(BOOL)current;
@end

@implementation YTLTranscriptCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        _timeLabel = [UILabel new];
        _timeLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
        _timeLabel.textColor = UIColor.systemBlueColor;
        _originalLabel = [UILabel new];
        _originalLabel.numberOfLines = 0;
        _translationLabel = [UILabel new];
        _translationLabel.numberOfLines = 0;
        _translationLabel.font = [UIFont systemFontOfSize:14];
        _translationLabel.textColor = UIColor.secondaryLabelColor;

        UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[_originalLabel, _translationLabel]];
        text.axis = UILayoutConstraintAxisVertical;
        text.spacing = 2;
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[_timeLabel, text]];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.alignment = UIStackViewAlignmentFirstBaseline;
        row.spacing = 10;
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [_timeLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_timeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self.contentView addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
            [row.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8],
            [row.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [row.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
        ]];
    }
    return self;
}

- (void)setCurrent:(BOOL)current {
    self.contentView.backgroundColor = current ? [UIColor.systemBlueColor colorWithAlphaComponent:0.14] : UIColor.clearColor;
    self.originalLabel.font = [UIFont systemFontOfSize:16 weight:current ? UIFontWeightSemibold : UIFontWeightRegular];
}

@end

#pragma mark - Drawer

@interface YTLTranscriptDrawer () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation YTLTranscriptDrawer {
    __weak YTPlayerViewController *_player;
    UIView *_dim;
    UIView *_panel;
    UILabel *_statusLabel;
    UIButton *_followButton;
    UIButton *_backButton;
    UIButton *_exportButton;
    UILabel *_emptyLabel;
    UILabel *_toast;
    UITableView *_table;

    YTLSubtitleSession *_session;
    NSArray *_sentences;
    NSUInteger _currentIndex;
    double _time;
    BOOL _follow;
    BOOL _menuVisible;
    BOOL _dismissing;
    CFTimeInterval _lastRefresh;
}

- (instancetype)initWithPlayer:(YTPlayerViewController *)player {
    if ((self = [super initWithFrame:CGRectZero])) {
        _player = player;
        _follow = YES;
        _currentIndex = NSNotFound;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self buildViews];
    }
    return self;
}

- (void)buildViews {
    _dim = [UIView new];
    _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    [_dim addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)]];
    [self addSubview:_dim];

    _panel = [UIView new];
    _panel.backgroundColor = UIColor.systemBackgroundColor;
    _panel.layer.cornerRadius = 12;
    _panel.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner;
    _panel.layer.shadowColor = UIColor.blackColor.CGColor;
    _panel.layer.shadowOpacity = 0.25;
    _panel.layer.shadowRadius = 10;
    [self addSubview:_panel];

    UILabel *title = [UILabel new];
    title.text = @"字幕";
    title.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    _statusLabel = [UILabel new];
    _statusLabel.font = [UIFont systemFontOfSize:12];
    _statusLabel.textColor = UIColor.secondaryLabelColor;
    _statusLabel.numberOfLines = 2;

    _followButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _followButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [_followButton addTarget:self action:@selector(toggleFollow) forControlEvents:UIControlEventTouchUpInside];
    [self updateFollowButton];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeClose];
    close.accessibilityLabel = @"关闭";
    [close addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *titles = [[UIStackView alloc] initWithArrangedSubviews:@[title, _statusLabel]];
    titles.axis = UILayoutConstraintAxisVertical;
    titles.spacing = 2;
    _exportButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_exportButton setImage:[UIImage systemImageNamed:@"square.and.arrow.up"] forState:UIControlStateNormal];
    _exportButton.accessibilityLabel = @"导出字幕";
    [_exportButton addTarget:self action:@selector(exportTranscript) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[titles, _exportButton, _followButton, close]];
    header.axis = UILayoutConstraintAxisHorizontal;
    header.alignment = UIStackViewAlignmentCenter;
    header.spacing = 12;
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [titles setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [_panel addSubview:header];

    UIView *separator = [UIView new];
    separator.backgroundColor = UIColor.separatorColor;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [_panel addSubview:separator];

    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.translatesAutoresizingMaskIntoConstraints = NO;
    _table.dataSource = self;
    _table.delegate = self;
    _table.rowHeight = UITableViewAutomaticDimension;
    _table.estimatedRowHeight = 64;
    _table.separatorInset = UIEdgeInsetsMake(0, 12, 0, 12);
    [_table registerClass:YTLTranscriptCell.class forCellReuseIdentifier:kCellID];
    [_panel addSubview:_table];
    // The drawer sits directly in the window (no view controller), where UITableView context menus never appear;
    // a plain long press + action sheet works there.
    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(rowLongPressed:)];
    press.minimumPressDuration = 0.4;
    [_table addGestureRecognizer:press];

    _emptyLabel = [UILabel new];
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.textColor = UIColor.secondaryLabelColor;
    [_panel addSubview:_emptyLabel];

    _backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _backButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_backButton setTitle:@"  回到当前句  " forState:UIControlStateNormal];
    _backButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _backButton.backgroundColor = UIColor.systemBlueColor;
    [_backButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _backButton.layer.cornerRadius = 16;
    _backButton.hidden = YES;
    [_backButton addTarget:self action:@selector(backToCurrent) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:_backButton];

    _toast = [UILabel new];
    _toast.translatesAutoresizingMaskIntoConstraints = NO;
    _toast.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _toast.textColor = UIColor.whiteColor;
    _toast.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.85];
    _toast.textAlignment = NSTextAlignmentCenter;
    _toast.layer.cornerRadius = 8;
    _toast.clipsToBounds = YES;
    _toast.alpha = 0;
    [_panel addSubview:_toast];

    UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)];
    swipe.direction = UISwipeGestureRecognizerDirectionRight;
    [header addGestureRecognizer:swipe];

    UILayoutGuide *safe = _panel.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],
        [header.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor constant:14],
        [header.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [separator.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:8],
        [separator.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:_panel.trailingAnchor],
        [separator.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
        [_table.topAnchor constraintEqualToAnchor:separator.bottomAnchor],
        [_table.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor],
        [_table.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [_table.bottomAnchor constraintEqualToAnchor:_panel.bottomAnchor],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:_table.centerYAnchor],
        [_emptyLabel.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor constant:24],
        [_emptyLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],
        [_backButton.centerXAnchor constraintEqualToAnchor:_table.centerXAnchor],
        [_backButton.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-16],
        [_backButton.heightAnchor constraintEqualToConstant:32],
        [_toast.centerXAnchor constraintEqualToAnchor:_table.centerXAnchor],
        [_toast.topAnchor constraintEqualToAnchor:_table.topAnchor constant:12],
        [_toast.heightAnchor constraintEqualToConstant:32],
        [_toast.widthAnchor constraintGreaterThanOrEqualToConstant:100],
    ]];
}

#pragma mark - Presentation

- (CGRect)panelFrame {
    CGRect bounds = self.bounds;
    if (bounds.size.width > bounds.size.height) {   // landscape: right panel, video usable on the left
        CGFloat width = MIN(460, MAX(320, bounds.size.width * 0.38));
        return CGRectMake(bounds.size.width - width, 0, width, bounds.size.height);
    }
    // Portrait: start below the inline player when it sits at the top, so the video stays visible.
    CGFloat top = self.safeAreaInsets.top;
    YTPlayerViewController *player = _player;
    if (player.isViewLoaded && player.view.window == self.window) {
        CGRect playerFrame = [player.view convertRect:player.view.bounds toView:self];
        if (CGRectGetMaxY(playerFrame) > top && CGRectGetMaxY(playerFrame) < bounds.size.height * 0.6) top = CGRectGetMaxY(playerFrame);
    }
    CGFloat width = round(bounds.size.width * 0.92);
    return CGRectMake(bounds.size.width - width, top, width, bounds.size.height - top);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (_dismissing) return;
    CGRect panel = [self panelFrame];
    _panel.frame = panel;
    BOOL landscape = self.bounds.size.width > self.bounds.size.height;
    _dim.hidden = landscape;
    _dim.frame = CGRectMake(0, panel.origin.y, panel.origin.x, panel.size.height);
}

// Outside the panel (and the portrait dim strip) touches go to the app underneath.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}

- (void)presentInWindow:(UIWindow *)window {
    self.frame = window.bounds;
    [window addSubview:self];
    [self layoutIfNeeded];
    _panel.transform = CGAffineTransformMakeTranslation(_panel.bounds.size.width, 0);
    _dim.alpha = 0;
    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self->_panel.transform = CGAffineTransformIdentity;
        self->_dim.alpha = 1;
    } completion:nil];
}

- (void)dismiss {
    if (_dismissing || !self.superview) return;
    _dismissing = YES;
    [UIView animateWithDuration:0.2 animations:^{
        self->_panel.transform = CGAffineTransformMakeTranslation(self->_panel.bounds.size.width, 0);
        self->_dim.alpha = 0;
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}

#pragma mark - Updates

- (BOOL)userIsInteracting {
    return _menuVisible || _table.isTracking || _table.isDragging || _table.isDecelerating;
}

- (void)updateWithSession:(YTLSubtitleSession *)session time:(double)time {
    if (_dismissing) return;
    _time = time;
    if (session != _session || session.sentences != _sentences) {
        _session = session;
        _sentences = session.sentences;
        _currentIndex = NSNotFound;
        [_table reloadData];
        _follow = YES;
        [self updateFollowButton];
    }
    [self updateEmptyState];

    NSUInteger index = _sentences.count ? YTLIndexAtTime(_sentences, time) : NSNotFound;
    if (index != _currentIndex) {
        NSUInteger previous = _currentIndex;
        _currentIndex = index;
        for (NSIndexPath *path in _table.indexPathsForVisibleRows) {
            if ((NSUInteger)path.row == previous || (NSUInteger)path.row == index) {
                [(YTLTranscriptCell *)[_table cellForRowAtIndexPath:path] setCurrent:(NSUInteger)path.row == index];
            }
        }
        if (_follow && index != NSNotFound && ![self userIsInteracting]) {
            [_table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
        }
    }

    CFTimeInterval now = CACurrentMediaTime();
    if (now - _lastRefresh >= kRefreshInterval) {
        _lastRefresh = now;
        [self updateStatus];
        // Translations arrive in batches; refresh what is on screen unless the user is touching the list.
        if (![self userIsInteracting]) {
            for (NSIndexPath *path in _table.indexPathsForVisibleRows) {
                YTLTranscriptCell *cell = [_table cellForRowAtIndexPath:path];
                NSString *translation = [_session translationForSentenceAtIndex:path.row];
                if (cell && !(translation == cell.translationLabel.text || [translation isEqualToString:cell.translationLabel.text])) {
                    [UIView performWithoutAnimation:^{ [self->_table reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone]; }];
                }
            }
        }
    }
}

- (void)updateEmptyState {
    BOOL empty = _sentences.count == 0;
    _emptyLabel.hidden = !empty;
    _table.hidden = empty;
    if (empty) {
        _emptyLabel.text = _session ? @"还没有字幕。\n请在 YouTube 播放器里打开 CC 字幕，YTLanguage 才能读到字幕。"
                                    : @"等待视频加载…";
    }
}

- (void)updateStatus {
    if (!_sentences.count) {
        _statusLabel.text = nil;
        return;
    }
    YTPlayerViewController *player = _player;
    double duration = [player respondsToSelector:@selector(currentVideoTotalMediaTime)] ? player.currentVideoTotalMediaTime : 0;
    double first = [(YTLCue *)_sentences.firstObject start], last = [(YTLCue *)_sentences.lastObject end];
    NSString *coverage = @"完整性未知";
    if (duration > 0) {
        BOOL complete = first <= 30 && last >= duration - 30;
        coverage = complete ? @"完整" : [NSString stringWithFormat:@"部分（%.0f%%–%.0f%%）", first / duration * 100, MIN(100, last / duration * 100)];
    }
    NSString *translation = [[_session.translationStatus componentsSeparatedByString:@"\n"] firstObject];
    _statusLabel.text = [NSString stringWithFormat:@"%lu 句 · %@\n%@", (unsigned long)_sentences.count, coverage, translation ?: @""];
}

#pragma mark - Follow

- (void)updateFollowButton {
    [_followButton setTitle:_follow ? @"跟随 ✓" : @"跟随" forState:UIControlStateNormal];
    _backButton.hidden = _follow || !_sentences.count;
}

- (void)toggleFollow {
    _follow = !_follow;
    [self updateFollowButton];
    if (_follow) [self backToCurrent];
}

- (void)backToCurrent {
    _follow = YES;
    [self updateFollowButton];
    if (_currentIndex != NSNotFound && _currentIndex < _sentences.count) {
        [_table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:_currentIndex inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
    }
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    // Manual scrolling suspends auto-follow.
    if (_follow) {
        _follow = NO;
        [self updateFollowButton];
    }
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _sentences.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    YTLTranscriptCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellID forIndexPath:indexPath];
    YTLCue *sentence = _sentences[indexPath.row];
    cell.timeLabel.text = YTLClock(sentence.start);
    cell.originalLabel.text = sentence.text;
    NSString *translation = [_session translationForSentenceAtIndex:indexPath.row];
    cell.translationLabel.text = translation;
    cell.translationLabel.hidden = !translation.length;
    [cell setCurrent:(NSUInteger)indexPath.row == _currentIndex];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self seekToRow:indexPath.row];
}

- (void)seekToRow:(NSUInteger)row {
    if (row >= _sentences.count) return;
    if ([YTLPlayback seek:_player toTime:[(YTLCue *)_sentences[row] start]]) {
        _follow = YES;
        [self updateFollowButton];
    } else {
        [self showToast:@"当前播放器不支持跳转"];
    }
}

- (UIViewController *)topViewController {
    UIViewController *top = self.window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

- (void)rowLongPressed:(UILongPressGestureRecognizer *)press {
    if (press.state != UIGestureRecognizerStateBegan || _menuVisible) return;
    NSIndexPath *path = [_table indexPathForRowAtPoint:[press locationInView:_table]];
    NSUInteger row = path.row;
    if (!path || row >= _sentences.count) return;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    _menuVisible = YES;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:[(YTLCue *)_sentences[row] text]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    void (^add)(NSString *, UIAlertActionStyle, void (^)(void)) = ^(NSString *title, UIAlertActionStyle style, void (^handler)(void)) {
        [sheet addAction:[UIAlertAction actionWithTitle:title style:style handler:^(UIAlertAction *action) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf->_menuVisible = NO;
            if (handler) handler();
        }]];
    };
    add(@"收藏句子", UIAlertActionStyleDefault, ^{ [weakSelf saveRow:row]; });
    add(@"取消", UIAlertActionStyleCancel, nil);

    UITableViewCell *cell = [_table cellForRowAtIndexPath:path];
    sheet.popoverPresentationController.sourceView = cell ?: _table;
    sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : CGRectZero;
    [[self topViewController] presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Actions

- (void)saveRow:(NSUInteger)row {
    if (row >= _sentences.count) return;
    YTLCue *sentence = _sentences[row];
    NSString *error = nil;
    BOOL ok = [YTLWordStore.shared saveSentence:sentence.text translation:[_session translationForSentenceAtIndex:row] language:@"en"
                                        videoID:_session.videoID title:[YTLHostCaptions videoTitleForPlayer:_player]
                                        startMs:(long long)(sentence.start * 1000) endMs:(long long)(sentence.end * 1000) error:&error];
    [self showToast:ok ? @"已收藏句子" : [NSString stringWithFormat:@"收藏失败：%@", error]];
}

// Whole-video transcript, original text only, as Markdown: title, link, then one paragraph per sentence.
- (void)exportTranscript {
    if (!_sentences.count) {
        [self showToast:@"暂无字幕"];
        return;
    }
    NSString *title = [YTLHostCaptions videoTitleForPlayer:_player];
    NSString *videoID = _session.videoID ?: @"";
    NSMutableString *markdown = [NSMutableString stringWithFormat:@"# %@\n\nhttps://youtu.be/%@\n\n", title ?: videoID, videoID];
    for (YTLCue *sentence in _sentences) [markdown appendFormat:@"%@\n\n", sentence.text];

    NSString *base = title.length ? title : videoID;
    NSCharacterSet *illegal = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|\n\r"];
    base = [[base componentsSeparatedByCharactersInSet:illegal] componentsJoinedByString:@" "];
    if (base.length > 80) base = [base substringToIndex:80];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[base stringByAppendingString:@".md"]]];
    if (![[markdown dataUsingEncoding:NSUTF8StringEncoding] writeToURL:url atomically:YES]) {
        [self showToast:@"导出失败"];
        return;
    }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    share.popoverPresentationController.sourceView = _exportButton;
    share.popoverPresentationController.sourceRect = _exportButton.bounds;
    [[self topViewController] presentViewController:share animated:YES completion:nil];
}

- (void)showToast:(NSString *)text {
    _toast.text = [NSString stringWithFormat:@"  %@  ", text];
    [_panel bringSubviewToFront:_toast];
    [UIView animateWithDuration:0.15 animations:^{ self->_toast.alpha = 1; } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.3 delay:1.2 options:0 animations:^{ self->_toast.alpha = 0; } completion:nil];
    }];
}

@end
