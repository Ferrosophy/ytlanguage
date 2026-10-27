#import <UIKit/UIKit.h>

@class YTLSubtitleOverlayView, YTLSubtitleStyle;

@protocol YTLSubtitleOverlayDelegate <NSObject>
// Long press began on a word of the original line.
- (void)subtitleOverlay:(YTLSubtitleOverlayView *)overlay didSelectWord:(NSString *)word inSentence:(NSString *)sentence;
@end

// Transparent full-player view with one subtitle bubble (original + translation) styled by YTLSubtitleStyle.
// The text is laid out inside the bubble (max width and padding from the style); the bubble is centered at the
// style's X/Y percentages and clamped inside the player. Only the original line receives touches.
@interface YTLSubtitleOverlayView : UIView
@property (nonatomic, weak) id <YTLSubtitleOverlayDelegate> delegate;
@property (nonatomic, copy, readonly) NSString *originalText;
@property (nonatomic, copy) YTLSubtitleStyle *style;
// Highest allowed bubble bottom as a fraction of the player height (1 = no limit). Used to keep the
// subtitle above the progress bar while the player controls are visible; changes animate.
@property (nonatomic) CGFloat bottomLimit;
// nil hides that line; both nil hides the bubble. No-op if unchanged.
- (void)showOriginal:(NSString *)original translation:(NSString *)translation;
- (void)highlightWordRange:(NSRange)range;   // {NSNotFound, 0} clears
@end
