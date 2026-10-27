#import "YTLPanelViewController.h"
#import "YTLOverlayController.h"
#import "YTLSubtitleSession.h"
#import "YTLProbeViewController.h"
#import "YTLStyleViewController.h"
#import "YTLStudyViewController.h"
#import "../HostAdapter/YTLCaptionProbe.h"
#import "../Services/YTLSettings.h"
#import "../Services/YTLWordStore.h"

#ifndef YTL_VERSION
#define YTL_VERSION "dev"
#endif

typedef NS_ENUM(NSInteger, YTLPanelSection) { YTLSectionMode, YTLSectionTranslation, YTLSectionLookup, YTLSectionDiagnostics, YTLSectionCount };

@implementation YTLPanelViewController {
    __weak YTPlayerViewController *_player;
    NSTimer *_refresh;
}

- (instancetype)initWithPlayer:(YTPlayerViewController *)player {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _player = player;
        self.title = [NSString stringWithFormat:@"YTLanguage v%s", YTL_VERSION];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
    // Translation progress changes while the panel is open.
    __weak typeof(self) weakSelf = self;
    _refresh = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        [weakSelf.tableView reloadSections:[NSIndexSet indexSetWithIndex:YTLSectionTranslation] withRowAnimation:UITableViewRowAnimationNone];
    }];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_refresh invalidate];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return YTLSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case YTLSectionMode: return 3;
        case YTLSectionTranslation: return 4;
        case YTLSectionLookup: return 3;
        default: return 1;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"字幕显示", @"翻译", @"查词与收藏", @"诊断"][section];
}

- (UITableViewCell *)cellWithStyle:(UITableViewCellStyle)style {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:nil];
    cell.detailTextLabel.numberOfLines = 0;
    cell.textLabel.numberOfLines = 0;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    YTLOverlayController *overlay = [YTLOverlayController controllerForPlayer:_player];
    switch (indexPath.section) {
        case YTLSectionMode: {
            if (indexPath.row > 0) {
                UITableViewCell *cell = [self cellWithStyle:UITableViewCellStyleDefault];
                cell.textLabel.text = indexPath.row == 1 ? @"字幕样式" : @"打开字幕列表";
                cell.imageView.image = [UIImage systemImageNamed:indexPath.row == 1 ? @"textformat.size" : @"list.bullet.rectangle"];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                return cell;
            }
            UITableViewCell *cell = [self cellWithStyle:UITableViewCellStyleDefault];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:@[@"双语", @"原文", @"译文", @"关闭"]];
            control.selectedSegmentIndex = YTLSettings.mode;
            [control addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
            control.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:control];
            [NSLayoutConstraint activateConstraints:@[
                [control.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
                [control.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
                [control.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10],
                [control.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10],
            ]];
            return cell;
        }
        case YTLSectionTranslation: {
            UITableViewCell *cell = [self cellWithStyle:UITableViewCellStyleSubtitle];
            if (indexPath.row == 0) {
                cell.textLabel.text = @"当前来源";
                cell.detailTextLabel.text = overlay.session ? overlay.session.translationStatus
                                                            : (overlay ? @"等待字幕（请打开 CC）" : @"播放器未连接");
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else if (indexPath.row == 1) {
                UITableViewCell *serviceCell = [self cellWithStyle:UITableViewCellStyleDefault];
                serviceCell.textLabel.text = @"翻译服务";
                serviceCell.selectionStyle = UITableViewCellSelectionStyleNone;
                UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:@[@"Google", @"DeepSeek"]];
                control.selectedSegmentIndex = YTLSettings.translationProvider;
                [control addTarget:self action:@selector(providerChanged:) forControlEvents:UIControlEventValueChanged];
                [control sizeToFit];
                serviceCell.accessoryView = control;
                return serviceCell;
            } else if (indexPath.row == 2) {
                cell.textLabel.text = @"DeepSeek API Key";
                cell.detailTextLabel.text = YTLSettings.deepSeekKey ? @"已设置" : @"未设置";
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else {
                cell.textLabel.text = @"DeepSeek 模型";
                cell.detailTextLabel.text = YTLSettings.deepSeekModel;
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }
            return cell;
        }
        case YTLSectionLookup: {
            if (indexPath.row == 0) {
                UITableViewCell *cell = [self cellWithStyle:UITableViewCellStyleDefault];
                cell.textLabel.text = @"查词时暂停视频";
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                UISwitch *toggle = [UISwitch new];
                toggle.on = YTLSettings.pauseOnLookup;
                [toggle addTarget:self action:@selector(pauseChanged:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = toggle;
                return cell;
            }
            UITableViewCell *cell = [self cellWithStyle:UITableViewCellStyleValue1];
            BOOL words = indexPath.row == 1;
            cell.textLabel.text = words ? @"已收藏单词" : @"已收藏句子";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld %@",
                (long)(words ? YTLWordStore.shared.wordCount : YTLWordStore.shared.sentenceCount), words ? @"个" : @"句"];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        default: {
            UITableViewCell *cell = [self cellWithStyle:UITableViewCellStyleDefault];
            cell.textLabel.text = @"诊断报告";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == YTLSectionMode && indexPath.row == 1) {
        [self.navigationController pushViewController:[YTLStyleViewController new] animated:YES];
    } else if (indexPath.section == YTLSectionMode && indexPath.row == 2) {
        YTLOverlayController *overlay = [YTLOverlayController controllerForPlayer:_player];
        [self dismissViewControllerAnimated:YES completion:^{ [overlay showTranscript]; }];
    } else if (indexPath.section == YTLSectionTranslation && indexPath.row == 2) [self editKey];
    else if (indexPath.section == YTLSectionTranslation && indexPath.row == 3) [self editModel];
    else if (indexPath.section == YTLSectionLookup && indexPath.row > 0) {
        [self.navigationController pushViewController:[[YTLStudyViewController alloc] initShowingSentences:indexPath.row == 2] animated:YES];
    } else if (indexPath.section == YTLSectionDiagnostics) [self showDiagnostics];
}

#pragma mark - Actions

- (void)modeChanged:(UISegmentedControl *)control {
    YTLSettings.mode = (YTLSubtitleMode)control.selectedSegmentIndex;
}

- (void)pauseChanged:(UISwitch *)toggle {
    YTLSettings.pauseOnLookup = toggle.on;
}

- (void)providerChanged:(UISegmentedControl *)control {
    YTLSettings.translationProvider = (YTLTranslationProvider)control.selectedSegmentIndex;
    if (YTLSettings.translationProvider == YTLTranslationProviderDeepSeek && !YTLSettings.deepSeekKey) [self editKey];
}

// The key is stored in the Keychain and only sent to api.deepseek.com.
- (void)editKey {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"DeepSeek API Key" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"sk-…";
        field.secureTextEntry = YES;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *key = alert.textFields.firstObject.text;
        if (key.length) YTLSettings.deepSeekKey = key;
        [weakSelf.tableView reloadData];
    }]];
    if (YTLSettings.deepSeekKey) {
        [alert addAction:[UIAlertAction actionWithTitle:@"清除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            YTLSettings.deepSeekKey = nil;
            [weakSelf.tableView reloadData];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)editModel {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"DeepSeek 模型" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = YTLSettings.deepSeekModel;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        YTLSettings.deepSeekModel = alert.textFields.firstObject.text;
        [weakSelf.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showDiagnostics {
    YTLProbeReport *report = nil;
    @try {
        report = [YTLCaptionProbe reportForPlayer:_player extra:[NSString stringWithFormat:@"%@\nsettings push: %@",
            [YTLOverlayController controllerForPlayer:_player].statusDescription ?: @"", YTLStudyViewController.settingsPushInfo ?: @"-"]];
    } @catch (NSException *e) {
        report = [YTLProbeReport new];
        report.summary = report.full = [NSString stringWithFormat:@"YTLanguage v%s\nDiagnostics failed: %@\n%@", YTL_VERSION, e.name, e.reason];
        report.fileName = @"YTLanguage-diagnostics-error.txt";
    }
    [self.navigationController pushViewController:[[YTLProbeViewController alloc] initWithReport:report] animated:YES];
}

@end
