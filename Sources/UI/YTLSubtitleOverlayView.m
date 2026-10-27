#import "YTLSubtitleOverlayView.h"
#import "../Core/YTLTextKit.h"
#import "../Services/YTLSubtitleStyle.h"

static const CGFloat kLineSpacing = 2;

// Draws an attributed string with its own TextKit stack. Sizing, drawing and touch → character mapping all
// use that one layout, so the word under the finger is the word on screen (v0.4.0 drew with UILabel and
// hit-tested with a separate TextKit copy, which drifted apart).
@interface YTLTextLayoutView : UIView
@property (nonatomic, copy) NSAttributedString *attributedText;
- (NSUInteger)characterIndexAtPoint:(CGPoint)point;
@end

@implementation YTLTextLayoutView {
    NSTextStorage *_storage;
    NSLayoutManager *_layout;
    NSTextContainer *_container;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.opaque = NO;
        self.backgroundColor = UIColor.clearColor;
        self.contentMode = UIViewContentModeRedraw;
        _storage = [NSTextStorage new];
        _layout = [NSLayoutManager new];
        _container = [[NSTextContainer alloc] initWithSize:CGSizeMake(frame.size.width, CGFLOAT_MAX)];
        _container.lineFragmentPadding = 0;
        [_storage addLayoutManager:_layout];
        [_layout addTextContainer:_container];
    }
    return self;
}

- (void)setAttributedText:(NSAttributedString *)text {
    _attributedText = [text copy];
    [_storage setAttributedString:text ?: [NSAttributedString new]];
    [self setNeedsDisplay];
}

- (CGSize)sizeThatFits:(CGSize)size {
    _container.size = CGSizeMake(size.width, CGFLOAT_MAX);
    [_layout ensureLayoutForTextContainer:_container];
    CGRect used = [_layout usedRectForTextContainer:_container];
    return CGSizeMake(ceil(used.size.width), ceil(used.size.height));
}

- (void)syncContainer {
    if (_container.size.width != self.bounds.size.width) _container.size = CGSizeMake(self.bounds.size.width, CGFLOAT_MAX);
}

- (void)drawRect:(CGRect)rect {
    [self syncContainer];
    NSRange glyphs = [_layout glyphRangeForTextContainer:_container];
    [_layout drawBackgroundForGlyphRange:glyphs atPoint:CGPointZero];
    [_layout drawGlyphsForGlyphRange:glyphs atPoint:CGPointZero];
}

- (NSUInteger)characterIndexAtPoint:(CGPoint)point {
    if (!_storage.length) return NSNotFound;
    [self syncContainer];
    CGFloat fraction = 0;
    NSUInteger glyph = [_layout glyphIndexForPoint:point inTextContainer:_container fractionOfDistanceThroughGlyph:&fraction];
    CGRect line = [_layout lineFragmentUsedRectForGlyphAtIndex:glyph effectiveRange:NULL];
    if (!CGRectContainsPoint(CGRectInset(line, -8, -8), point)) return NSNotFound;
    return [_layout characterIndexForGlyphAtIndex:glyph];
}

@end

@implementation YTLSubtitleOverlayView {
    UIView *_bubble;
    UIVisualEffectView *_blurView;
    UIViewPropertyAnimator *_blurAnimator;
    YTLTextLayoutView *_originalView;
    YTLTextLayoutView *_translationView;
    NSString *_translationText;
    NSRange _highlight;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _highlight = NSMakeRange(NSNotFound, 0);
        _style = [YTLSubtitleStyle current];
        _bottomLimit = 1;

        _bubble = [UIView new];
        _bubble.clipsToBounds = YES;
        _bubble.hidden = YES;
        [self addSubview:_bubble];

        _blurView = [[UIVisualEffectView alloc] initWithEffect:nil];
        [_bubble addSubview:_blurView];

        _originalView = [YTLTextLayoutView new];
        _translationView = [YTLTextLayoutView new];
        _translationView.userInteractionEnabled = NO;
        [_bubble addSubview:_originalView];
        [_bubble addSubview:_translationView];

        UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
        press.minimumPressDuration = 0.35;
        [_originalView addGestureRecognizer:press];

        // Property animators are finished when the app goes to the background; rebuild the partial blur after.
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applyBlur)
                                                   name:UIApplicationWillEnterForegroundNotification object:nil];
        [self applyStyle];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_blurAnimator stopAnimation:YES];
}

#pragma mark - Style

- (void)setStyle:(YTLSubtitleStyle *)style {
    _style = [style copy];
    [self applyStyle];
}

- (void)setBottomLimit:(CGFloat)limit {
    if (fabs(limit - _bottomLimit) < 0.001) return;
    _bottomLimit = limit;
    [UIView animateWithDuration:0.2 animations:^{
        [self setNeedsLayout];
        [self layoutIfNeeded];
    }];
}

- (void)applyStyle {
    _bubble.backgroundColor = _style.backgroundEnabled ? _style.backgroundColor : UIColor.clearColor;
    _bubble.layer.cornerRadius = _style.backgroundEnabled ? _style.cornerRadius : 0;
    [self applyBlur];
    [self renderText];
}

// UIBlurEffect has no radius; a paused animator gives a partial effect (0–100%).
- (void)applyBlur {
    [_blurAnimator stopAnimation:YES];
    _blurAnimator = nil;
    _blurView.effect = nil;
    BOOL show = _style.backgroundEnabled && _style.backgroundBlur > 0;
    _blurView.hidden = !show;
    if (!show) return;
    UIVisualEffectView *blurView = _blurView;
    _blurAnimator = [[UIViewPropertyAnimator alloc] initWithDuration:1 curve:UIViewAnimationCurveLinear animations:^{
        blurView.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    }];
    _blurAnimator.pausesOnCompletion = YES;
    _blurAnimator.fractionComplete = _style.backgroundBlur / 100.0;
}

- (NSDictionary *)textAttributesWithFont:(UIFont *)font color:(UIColor *)color {
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = NSTextAlignmentCenter;
    NSMutableDictionary *attrs = [@{ NSFontAttributeName: font, NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: paragraph } mutableCopy];
    if (_style.effect == YTLTextEffectShadow) {
        NSShadow *shadow = [NSShadow new];
        shadow.shadowColor = [UIColor colorWithWhite:0 alpha:0.9];
        shadow.shadowOffset = CGSizeMake(0, 1);
        shadow.shadowBlurRadius = 3;
        attrs[NSShadowAttributeName] = shadow;
    } else if (_style.effect == YTLTextEffectOutline) {
        attrs[NSStrokeColorAttributeName] = UIColor.blackColor;
        attrs[NSStrokeWidthAttributeName] = @(-3);   // negative: fill and stroke
    }
    return attrs;
}

- (void)renderText {
    UIFont *originalFont = [UIFont systemFontOfSize:_style.fontSize weight:_style.fontWeight];
    UIFont *translationFont = [UIFont systemFontOfSize:round(_style.fontSize * 0.9) weight:_style.fontWeight];
    if (_originalText.length) {
        NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:_originalText
                                                                                 attributes:[self textAttributesWithFont:originalFont color:_style.originalColor]];
        if (_highlight.location != NSNotFound && NSMaxRange(_highlight) <= text.length) {
            [text addAttributes:@{ NSBackgroundColorAttributeName: [UIColor colorWithRed:0.2 green:0.55 blue:1 alpha:0.85] } range:_highlight];
        }
        _originalView.attributedText = text;
    } else {
        _originalView.attributedText = nil;
    }
    _translationView.attributedText = _translationText.length
        ? [[NSAttributedString alloc] initWithString:_translationText attributes:[self textAttributesWithFont:translationFont color:_style.translationColor]]
        : nil;
    [self setNeedsLayout];
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize bounds = self.bounds.size;
    if (_bubble.hidden || bounds.width < 1 || bounds.height < 1) return;

    CGFloat padding = _style.backgroundPadding;
    CGFloat maxWidth = MAX(60, bounds.width * _style.backgroundMaxWidth / 100.0);
    CGFloat inner = MAX(20, maxWidth - padding * 2);
    CGSize originalSize = _originalView.hidden ? CGSizeZero : [_originalView sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)];
    CGSize translationSize = _translationView.hidden ? CGSizeZero : [_translationView sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)];
    originalSize.width = MIN(inner, originalSize.width);
    translationSize.width = MIN(inner, translationSize.width);
    CGFloat spacing = (!_originalView.hidden && !_translationView.hidden) ? kLineSpacing : 0;
    CGFloat textWidth = MAX(originalSize.width, translationSize.width);
    CGFloat textHeight = originalSize.height + spacing + translationSize.height;

    CGSize bubbleSize = CGSizeMake(MIN(bounds.width, textWidth + padding * 2), MIN(bounds.height, textHeight + padding * 2));
    CGFloat cx = bounds.width * _style.positionX / 100.0, cy = bounds.height * _style.positionY / 100.0;
    CGFloat maxBottom = bounds.height * MIN(1, MAX(0.2, _bottomLimit));
    cx = MIN(bounds.width - bubbleSize.width / 2, MAX(bubbleSize.width / 2, cx));
    cy = MIN(maxBottom - bubbleSize.height / 2, cy);
    cy = MAX(bubbleSize.height / 2, cy);
    _bubble.frame = CGRectIntegral(CGRectMake(cx - bubbleSize.width / 2, cy - bubbleSize.height / 2, bubbleSize.width, bubbleSize.height));
    _blurView.frame = _bubble.bounds;

    // Each text view is as wide as the text column, so its TextKit layout matches what sizeThatFits measured.
    CGFloat columnX = (bubbleSize.width - textWidth) / 2;
    CGFloat y = padding;
    if (!_originalView.hidden) {
        _originalView.frame = CGRectMake(columnX, y, textWidth, originalSize.height);
        y += originalSize.height + spacing;
    }
    if (!_translationView.hidden) {
        _translationView.frame = CGRectMake(columnX, y, textWidth, translationSize.height);
    }
    [_originalView setNeedsDisplay];
    [_translationView setNeedsDisplay];
}

// Only the original line is touchable; the rest of the player keeps working.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (_bubble.hidden || _originalView.hidden) return nil;
    CGPoint inText = [self convertPoint:point toView:_originalView];
    return [_originalView pointInside:inText withEvent:event] ? _originalView : nil;
}

#pragma mark - Content

- (void)showOriginal:(NSString *)original translation:(NSString *)translation {
    BOOL same = (original == _originalText || [original isEqualToString:_originalText]) &&
                (translation == _translationText || [translation isEqualToString:_translationText]);
    if (same) return;
    _originalText = [original copy];
    _translationText = [translation copy];
    _highlight = NSMakeRange(NSNotFound, 0);
    _originalView.hidden = !original.length;
    _translationView.hidden = !translation.length;
    _bubble.hidden = !original.length && !translation.length;
    [self renderText];
}

- (void)highlightWordRange:(NSRange)range {
    _highlight = range;
    [self renderText];
}

- (void)longPressed:(UILongPressGestureRecognizer *)press {
    if (press.state != UIGestureRecognizerStateBegan || !_originalText.length) return;
    NSUInteger index = [_originalView characterIndexAtPoint:[press locationInView:_originalView]];
    if (index == NSNotFound) return;
    NSRange range = [YTLTextKit wordRangeInString:_originalText atIndex:index];
    if (range.location == NSNotFound) return;
    [self highlightWordRange:range];
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];
    [self.delegate subtitleOverlay:self didSelectWord:[_originalText substringWithRange:range] inSentence:_originalText];
}

@end
