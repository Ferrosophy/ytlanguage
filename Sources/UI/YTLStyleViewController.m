#import "YTLStyleViewController.h"
#import "../Services/YTLSettings.h"
#import "../Services/YTLSubtitleStyle.h"

typedef NS_ENUM(NSInteger, YTLStyleSection) { YTLStyleText, YTLStyleBackground, YTLStylePosition, YTLStyleSentence, YTLStyleReset, YTLStyleSectionCount };
typedef NS_ENUM(NSInteger, YTLColorTarget) { YTLColorOriginal, YTLColorTranslation, YTLColorBackground };

// One numeric setting shown as a slider row.
@interface YTLNumberRow : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *unit;
@property (nonatomic) CGFloat min, max;
@property (nonatomic, copy) CGFloat (^get)(void);
@property (nonatomic, copy) void (^set)(CGFloat value);
@end

@implementation YTLNumberRow
@end

@interface YTLStyleViewController () <UIColorPickerViewControllerDelegate>
@end

@implementation YTLStyleViewController {
    YTLSubtitleStyle *_style;
    YTLColorTarget _colorTarget;
    NSArray <YTLNumberRow *> *_textNumbers, *_backgroundNumbers, *_positionNumbers, *_sentenceNumbers;
}

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        self.title = @"字幕样式";
        _style = [YTLSubtitleStyle current];
        [self buildRows];
    }
    return self;
}

- (YTLNumberRow *)row:(NSString *)title unit:(NSString *)unit min:(CGFloat)min max:(CGFloat)max
                  get:(CGFloat (^)(void))get set:(void (^)(CGFloat))set {
    YTLNumberRow *row = [YTLNumberRow new];
    row.title = title;
    row.unit = unit;
    row.min = min;
    row.max = max;
    row.get = get;
    row.set = set;
    return row;
}

- (void)buildRows {
    __weak typeof(self) weakSelf = self;
    YTLSubtitleStyle * (^s)(void) = ^YTLSubtitleStyle *{
        typeof(self) strongSelf = weakSelf;
        return strongSelf ? strongSelf->_style : nil;
    };
    _textNumbers = @[
        [self row:@"字号" unit:@"pt" min:10 max:40 get:^{ return s().fontSize; } set:^(CGFloat v) { s().fontSize = v; }],
    ];
    _backgroundNumbers = @[
        [self row:@"模糊程度" unit:@"%" min:0 max:100 get:^{ return s().backgroundBlur; } set:^(CGFloat v) { s().backgroundBlur = v; }],
        [self row:@"内边距" unit:@"pt" min:0 max:30 get:^{ return s().backgroundPadding; } set:^(CGFloat v) { s().backgroundPadding = v; }],
        [self row:@"最大宽度" unit:@"%" min:40 max:100 get:^{ return s().backgroundMaxWidth; } set:^(CGFloat v) { s().backgroundMaxWidth = v; }],
        [self row:@"圆角" unit:@"pt" min:0 max:20 get:^{ return s().cornerRadius; } set:^(CGFloat v) { s().cornerRadius = v; }],
    ];
    _positionNumbers = @[
        [self row:@"X" unit:@"%" min:0 max:100 get:^{ return s().positionX; } set:^(CGFloat v) { s().positionX = v; }],
        [self row:@"Y" unit:@"%" min:0 max:100 get:^{ return s().positionY; } set:^(CGFloat v) { s().positionY = v; }],
    ];
    _sentenceNumbers = @[
        [self row:@"单句最多词数" unit:@"词" min:8 max:40 get:^{ return (CGFloat)YTLSettings.maxSentenceWords; }
              set:^(CGFloat v) { YTLSettings.maxSentenceWords = (NSInteger)lround(v); }],
    ];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    YTLSettings.stylePreviewActive = YES;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    YTLSettings.stylePreviewActive = NO;
}

- (void)commit {
    [_style save];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return YTLStyleSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case YTLStyleText: return _textNumbers.count + 4;            // size, weight, effect, 2 colors
        case YTLStyleBackground: return _backgroundNumbers.count + 2; // switch, color, numbers
        case YTLStylePosition: return _positionNumbers.count;
        case YTLStyleSentence: return _sentenceNumbers.count;
        default: return 1;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"文字", @"背景", @"位置", @"分句", @""][section];
}

- (UITableViewCell *)plainCell {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UITableViewCell *)numberCell:(YTLNumberRow *)row {
    UITableViewCell *cell = [self plainCell];
    UILabel *title = [UILabel new];
    title.text = row.title;
    UIButton *value = [UIButton buttonWithType:UIButtonTypeSystem];
    value.titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightMedium];
    [value setTitle:[NSString stringWithFormat:@"%.0f %@", row.get(), row.unit] forState:UIControlStateNormal];
    UISlider *slider = [UISlider new];
    slider.minimumValue = row.min;
    slider.maximumValue = row.max;
    slider.value = row.get();

    __weak typeof(self) weakSelf = self;
    __weak UIButton *weakValue = value;
    [slider addAction:[UIAction actionWithHandler:^(UIAction *action) {
        CGFloat v = round(((UISlider *)action.sender).value);
        row.set(v);
        [weakValue setTitle:[NSString stringWithFormat:@"%.0f %@", v, row.unit] forState:UIControlStateNormal];
        [weakSelf commit];
    }] forControlEvents:UIControlEventValueChanged];
    [value addAction:[UIAction actionWithHandler:^(UIAction *action) { [weakSelf promptNumber:row]; }] forControlEvents:UIControlEventTouchUpInside];

    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[title, value]];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[top, slider]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 4;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:stack];
    UILayoutGuide *margins = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:margins.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
    ]];
    return cell;
}

- (UITableViewCell *)segmentCell:(NSString *)title items:(NSArray *)items selected:(NSInteger)selected handler:(void (^)(NSInteger))handler {
    UITableViewCell *cell = [self plainCell];
    cell.textLabel.text = title;
    UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:items];
    control.selectedSegmentIndex = selected;
    [control addAction:[UIAction actionWithHandler:^(UIAction *action) {
        handler(((UISegmentedControl *)action.sender).selectedSegmentIndex);
    }] forControlEvents:UIControlEventValueChanged];
    [control sizeToFit];
    cell.accessoryView = control;
    return cell;
}

- (UITableViewCell *)colorCell:(NSString *)title color:(UIColor *)color {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = title;
    UIView *swatch = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 28, 28)];
    swatch.backgroundColor = color;
    swatch.layer.cornerRadius = 6;
    swatch.layer.borderWidth = 1;
    swatch.layer.borderColor = UIColor.separatorColor.CGColor;
    cell.accessoryView = swatch;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    __weak typeof(self) weakSelf = self;
    NSInteger row = indexPath.row;
    switch (indexPath.section) {
        case YTLStyleText:
            if (row < (NSInteger)_textNumbers.count) return [self numberCell:_textNumbers[row]];
            row -= _textNumbers.count;
            if (row == 0) return [self segmentCell:@"粗细" items:YTLSubtitleStyle.weightNames selected:_style.weight handler:^(NSInteger i) {
                typeof(self) strongSelf = weakSelf;
                strongSelf->_style.weight = i;
                [strongSelf commit];
            }];
            if (row == 1) return [self segmentCell:@"效果" items:YTLSubtitleStyle.effectNames selected:_style.effect handler:^(NSInteger i) {
                typeof(self) strongSelf = weakSelf;
                strongSelf->_style.effect = (YTLTextEffect)i;
                [strongSelf commit];
            }];
            return row == 2 ? [self colorCell:@"原文颜色" color:_style.originalColor] : [self colorCell:@"译文颜色" color:_style.translationColor];
        case YTLStyleBackground: {
            if (row == 0) {
                UITableViewCell *cell = [self plainCell];
                cell.textLabel.text = @"显示背景";
                UISwitch *toggle = [UISwitch new];
                toggle.on = _style.backgroundEnabled;
                [toggle addAction:[UIAction actionWithHandler:^(UIAction *action) {
                    typeof(self) strongSelf = weakSelf;
                    strongSelf->_style.backgroundEnabled = ((UISwitch *)action.sender).on;
                    [strongSelf commit];
                }] forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = toggle;
                return cell;
            }
            if (row == 1) return [self colorCell:@"背景颜色" color:_style.backgroundColor];
            return [self numberCell:_backgroundNumbers[row - 2]];
        }
        case YTLStylePosition:
            return [self numberCell:_positionNumbers[row]];
        case YTLStyleSentence:
            return [self numberCell:_sentenceNumbers[row]];
        default: {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
            cell.textLabel.text = @"恢复默认样式";
            cell.textLabel.textColor = UIColor.systemRedColor;
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            return cell;
        }
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSInteger textColorRow = indexPath.row - (NSInteger)_textNumbers.count - 2;
    if (indexPath.section == YTLStyleText && textColorRow >= 0) {
        [self pickColor:textColorRow == 0 ? YTLColorOriginal : YTLColorTranslation];
    } else if (indexPath.section == YTLStyleBackground && indexPath.row == 1) {
        [self pickColor:YTLColorBackground];
    } else if (indexPath.section == YTLStyleReset) {
        [YTLSubtitleStyle resetToDefaults];
        YTLSettings.maxSentenceWords = 18;
        _style = [YTLSubtitleStyle current];
        [self.tableView reloadData];
    }
}

#pragma mark - Input

- (void)promptNumber:(YTLNumberRow *)row {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:row.title
        message:[NSString stringWithFormat:@"%.0f – %.0f %@", row.min, row.max, row.unit] preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.keyboardType = UIKeyboardTypeNumberPad;
        field.text = [NSString stringWithFormat:@"%.0f", row.get()];
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text = alert.textFields.firstObject.text;
        if (!text.length) return;
        row.set(MIN(row.max, MAX(row.min, text.doubleValue)));
        [weakSelf commit];
        [weakSelf.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)pickColor:(YTLColorTarget)target {
    _colorTarget = target;
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.delegate = self;
    picker.supportsAlpha = target == YTLColorBackground;
    picker.selectedColor = target == YTLColorOriginal ? _style.originalColor
                         : target == YTLColorTranslation ? _style.translationColor : _style.backgroundColor;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)picker {
    UIColor *color = picker.selectedColor;
    if (_colorTarget == YTLColorOriginal) _style.originalColor = color;
    else if (_colorTarget == YTLColorTranslation) _style.translationColor = color;
    else _style.backgroundColor = color;
    [self commit];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)picker {
    [self.tableView reloadData];
}

@end
