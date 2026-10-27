#import "YTLStudyViewController.h"
#import "../Services/YTLWordStore.h"

typedef NS_ENUM(NSInteger, YTLStudyDisplay) {
    YTLStudyDisplayOriginal = 0,
    YTLStudyDisplayTranslation = 1,
    YTLStudyDisplayBoth = 2,
};

static NSString *const kWordDisplayKey = @"YTLanguage-StudyWordDisplay";
static NSString *const kSentenceDisplayKey = @"YTLanguage-StudySentenceDisplay";

static NSString *YTLCSVField(NSString *value) {
    NSString *text = value ?: @"";
    return [NSString stringWithFormat:@"\"%@\"", [text stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
}

static NSString *gSettingsPushInfo;

@implementation YTLStudyViewController {
    BOOL _sentences;
    NSArray <NSDictionary *> *_rows;
    UISegmentedControl *_tabs;
    UISegmentedControl *_display;
    UIButton *_exportButton;
    UILabel *_emptyLabel;
}

+ (NSString *)settingsPushInfo {
    return gSettingsPushInfo;
}

+ (void)setSettingsPushInfo:(NSString *)info {
    gSettingsPushInfo = [info copy];
}

- (instancetype)initShowingSentences:(BOOL)sentences {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _sentences = sentences;
        self.title = @"双语学习";
    }
    return self;
}

- (NSString *)displayKey {
    return _sentences ? kSentenceDisplayKey : kWordDisplayKey;
}

- (YTLStudyDisplay)display {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:[self displayKey]];
    NSInteger display = value ? [value integerValue] : YTLStudyDisplayBoth;
    return display >= YTLStudyDisplayOriginal && display <= YTLStudyDisplayBoth ? display : YTLStudyDisplayBoth;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    if (self.navigationController.viewControllers.firstObject == self) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                                                              target:self action:@selector(close)];
    }

    _tabs = [[UISegmentedControl alloc] initWithItems:@[@"单词", @"句子"]];
    _tabs.selectedSegmentIndex = _sentences ? 1 : 0;
    [_tabs addTarget:self action:@selector(tabChanged) forControlEvents:UIControlEventValueChanged];

    _exportButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_exportButton setImage:[UIImage systemImageNamed:@"square.and.arrow.up"] forState:UIControlStateNormal];
    _exportButton.accessibilityLabel = @"导出";
    [_exportButton addTarget:self action:@selector(export) forControlEvents:UIControlEventTouchUpInside];

    _display = [[UISegmentedControl alloc] initWithItems:@[@"原文", @"译文", @"原文与译文"]];
    [_display addTarget:self action:@selector(displayChanged) forControlEvents:UIControlEventValueChanged];

    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[_tabs, _exportButton]];
    top.spacing = 12;
    top.alignment = UIStackViewAlignmentCenter;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[top, _display]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 96)];
    [header addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.trailingAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [_exportButton.widthAnchor constraintEqualToConstant:36],
        [_tabs.heightAnchor constraintEqualToConstant:32],
        [_display.heightAnchor constraintEqualToConstant:32],
    ]];
    self.tableView.tableHeaderView = header;

    _emptyLabel = [UILabel new];
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.textColor = UIColor.secondaryLabelColor;
    _emptyLabel.font = [UIFont systemFontOfSize:15];
    self.tableView.backgroundView = _emptyLabel;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64;
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)reload {
    _rows = _sentences ? YTLWordStore.shared.allSentences : YTLWordStore.shared.allWords;
    _display.selectedSegmentIndex = [self display];
    _emptyLabel.text = _rows.count ? nil : (_sentences ? @"还没有收藏的句子" : @"还没有收藏的单词");
    _exportButton.enabled = _rows.count > 0;
    [self.tableView reloadData];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)tabChanged {
    _sentences = _tabs.selectedSegmentIndex == 1;
    [self reload];
}

- (void)displayChanged {
    [NSUserDefaults.standardUserDefaults setInteger:_display.selectedSegmentIndex forKey:[self displayKey]];
    [self.tableView reloadData];
}

#pragma mark - Export

- (void)export {
    if (!_rows.count) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *format in @[@"TXT", @"CSV", @"JSON"]) {
        [sheet addAction:[UIAlertAction actionWithTitle:format style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self shareFormat:format.lowercaseString];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = _exportButton;
    sheet.popoverPresentationController.sourceRect = _exportButton.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

// Words: word + translation. Sentences: sentence + translation + video title / link / start time.
- (NSData *)exportDataForFormat:(NSString *)format {
    NSString *textKey = _sentences ? @"sentence" : @"word";
    NSMutableArray <NSDictionary *> *items = [NSMutableArray array];
    for (NSDictionary *row in _rows) {
        NSMutableDictionary *item = [NSMutableDictionary dictionary];
        item[textKey] = row[@"text"];
        item[@"translation"] = row[@"translation"] ?: @"";
        if (_sentences) {
            item[@"video_title"] = row[@"title"] ?: @"";
            long long startMs = [row[@"startMs"] longLongValue];
            item[@"video_url"] = row[@"videoID"] ? [NSString stringWithFormat:@"https://youtu.be/%@?t=%lld", row[@"videoID"], startMs / 1000] : @"";
            item[@"start"] = [NSString stringWithFormat:@"%02lld:%02lld", startMs / 60000, (startMs / 1000) % 60];
        }
        [items addObject:item];
    }
    NSArray *columns = _sentences ? @[textKey, @"translation", @"video_title", @"video_url", @"start"] : @[textKey, @"translation"];
    if ([format isEqualToString:@"json"]) {
        return [NSJSONSerialization dataWithJSONObject:items options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    }
    NSMutableString *out = [NSMutableString string];
    if ([format isEqualToString:@"csv"]) {
        [out appendString:@"﻿"];   // BOM so Excel / Numbers read UTF-8
        [out appendFormat:@"%@\r\n", [columns componentsJoinedByString:@","]];
        for (NSDictionary *item in items) {
            NSMutableArray *fields = [NSMutableArray array];
            for (NSString *column in columns) [fields addObject:YTLCSVField(item[column])];
            [out appendFormat:@"%@\r\n", [fields componentsJoinedByString:@","]];
        }
    } else {
        for (NSDictionary *item in items) {
            [out appendFormat:@"%@\n", item[textKey]];
            if ([item[@"translation"] length]) [out appendFormat:@"%@\n", item[@"translation"]];
            if (_sentences && [item[@"video_url"] length]) [out appendFormat:@"%@ %@\n", item[@"video_title"], item[@"video_url"]];
            [out appendString:@"\n"];
        }
    }
    return [out dataUsingEncoding:NSUTF8StringEncoding];
}

- (void)shareFormat:(NSString *)format {
    NSData *data = [self exportDataForFormat:format];
    if (!data) return;
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"yyyyMMdd-HHmm";
    NSString *name = [NSString stringWithFormat:@"YTLanguage-%@-%@.%@", _sentences ? @"句子" : @"单词", [formatter stringFromDate:NSDate.date], format];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    if (![data writeToURL:url atomically:YES]) return;
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    share.popoverPresentationController.sourceView = _exportButton;
    share.popoverPresentationController.sourceRect = _exportButton.bounds;
    [self presentViewController:share animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"] ?:
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"row"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;

    NSDictionary *row = _rows[indexPath.row];
    NSString *original = row[@"text"];
    NSString *translation = row[@"translation"];
    UIFont *originalFont = _sentences ? [UIFont systemFontOfSize:17] : [UIFont systemFontOfSize:19 weight:UIFontWeightSemibold];
    switch ([self display]) {
        case YTLStudyDisplayOriginal:
            cell.textLabel.text = original;
            cell.textLabel.font = originalFont;
            cell.textLabel.textColor = UIColor.labelColor;
            cell.detailTextLabel.text = nil;
            break;
        case YTLStudyDisplayTranslation:
            cell.textLabel.text = translation.length ? translation : @"无译文";
            cell.textLabel.font = [UIFont systemFontOfSize:17];
            cell.textLabel.textColor = translation.length ? UIColor.labelColor : UIColor.tertiaryLabelColor;
            cell.detailTextLabel.text = nil;
            break;
        default:
            cell.textLabel.text = original;
            cell.textLabel.font = originalFont;
            cell.textLabel.textColor = UIColor.labelColor;
            cell.detailTextLabel.text = translation;
            cell.detailTextLabel.font = [UIFont systemFontOfSize:15];
            cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
            break;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete || indexPath.row >= (NSInteger)_rows.count) return;
    long long rowID = [_rows[indexPath.row][@"id"] longLongValue];
    BOOL ok = _sentences ? [YTLWordStore.shared deleteSentenceWithID:rowID] : [YTLWordStore.shared deleteWordWithID:rowID];
    if (!ok) return;
    NSMutableArray *rows = [_rows mutableCopy];
    [rows removeObjectAtIndex:indexPath.row];
    _rows = rows;
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    if (!_rows.count) {
        _emptyLabel.text = _sentences ? @"还没有收藏的句子" : @"还没有收藏的单词";
        _exportButton.enabled = NO;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    return @"删除";
}

@end
