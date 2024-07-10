#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CaptainHook/CaptainHook.h>
#import <dlfcn.h>
#import <LocalAuthentication/LocalAuthentication.h>
#import <objc/runtime.h>
#import <rootless.h>
#import <substrate.h>
#import <sys/utsname.h>
#import <YouTubeHeader/ASCollectionElement.h>
#import <YouTubeHeader/ASCollectionView.h>
#import <YouTubeHeader/ELMCellNode.h>
#import <YouTubeHeader/ELMNodeController.h>
#import <YouTubeHeader/GPBMessage.h>
#import <YouTubeHeader/MLPlayerStickySettings.h>
#import <YouTubeHeader/YTAppDelegate.h>
#import <YouTubeHeader/YTCollectionViewCell.h>
#import <YouTubeHeader/YTIBrowseRequest.h>
#import <YouTubeHeader/YTIButtonRenderer.h>
#import <YouTubeHeader/YTICompactLinkRenderer.h>
#import <YouTubeHeader/YTICompactListItemRenderer.h>
#import <YouTubeHeader/YTICompactListItemThumbnailSupportedRenderers.h>
#import <YouTubeHeader/YTIIconThumbnailRenderer.h>
#import <YouTubeHeader/YTIElementRenderer.h>
#import <YouTubeHeader/YTIFormattedString.h>
#import <YouTubeHeader/YTIGuideResponse.h>
#import <YouTubeHeader/YTIGuideResponseSupportedRenderers.h>
#import <YouTubeHeader/YTIMenuConditionalServiceItemRenderer.h>
#import <YouTubeHeader/YTInnerTubeCollectionViewController.h>
#import <YouTubeHeader/YTInlinePlayerBarContainerView.h>
#import <YouTubeHeader/YTIPivotBarItemRenderer.h>
#import <YouTubeHeader/YTIPivotBarRenderer.h>
#import <YouTubeHeader/YTIPivotBarSupportedRenderers.h>
#import <YouTubeHeader/YTIPlayerBarDecorationModel.h>
#import <YouTubeHeader/YTISectionListRenderer.h>
#import <YouTubeHeader/YTIStringRun.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayViewController.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayView.h>
#import <YouTubeHeader/YTPlayerBarController.h>
#import <YouTubeHeader/YTPlayerBarRectangleDecorationView.h>
#import <YouTubeHeader/YTPlayerOverlay.h>
#import <YouTubeHeader/YTPlayerOverlayProvider.h>
#import <YouTubeHeader/YTPlayerOverlayManager.h>
#import <YouTubeHeader/YTReelModel.h>
#import <YouTubeHeader/YTReelWatchPlaybackOverlayView.h>
#import <YouTubeHeader/YTResponder.h>
#import <YouTubeHeader/YTVideoQualitySwitchOriginalController.h>
#import <YouTubeHeader/YTVideoWithContextNode.h>
#import <YouTubeHeader/YTWatchNextResultsViewController.h>
#import <YouTubeHeader/YTWatchPlayerViewLayoutSource.h>
#import <YouTubeHeader/YTWatchPullToFullController.h>
#import <YouTubeHeader/YTWatchViewController.h>
#import "uYouPlusThemes.h" // uYouPlus Themes

#define LOC(x) [tweakBundle localizedStringForKey:x value:nil table:nil]
#define IS_ENABLED(k) [[NSUserDefaults standardUserDefaults] boolForKey:k]
#define APP_THEME_IDX [[NSUserDefaults standardUserDefaults] integerForKey:@"appTheme"]
#define YT_BUNDLE_ID @"com.google.ios.youtube"
#define YT_NAME @"YouTube"
#define DEFAULT_RATE 1.0f // YTSpeed
#define LOWCONTRASTMODE_CUTOFF_VERSION @"17.38.10" // LowContrastMode (v17.33.2-17.38.10)

// Always show remaining time in video player - @bhackel
// Header has been moved to https://github.com/PoomSmart/YouTubeHeader/blob/main/YTPlayerBarController.h
// Header has been moved to https://github.com/PoomSmart/YouTubeHeader/blob/main/YTInlinePlayerBarContainerView.h

// IAmYouTube
@interface SSOConfiguration : NSObject
@end

// Disable Snap to chapter
@interface YTSegmentableInlinePlayerBarView : UIView
@property(nonatomic, assign) BOOL enableSnapToChapter;
@end

// Hide Double tap to seek Overlay
@interface YTInlinePlayerDoubleTapIndicatorView : UIView
@property (nonatomic, strong) UIView *scrimOverlay;
@property(nonatomic, strong) CABasicAnimation *uYouEnhancedBlankAlphaAnimation;
@property(nonatomic, strong) CABasicAnimation *uYouEnhancedBlankColorAnimation;
- (CABasicAnimation *)uYouEnhancedGetBlankColorAnimation;
@end

// Hide Home Tab - @bhackel
@interface YTPivotBarItemViewAccessibilityControl : UIControl
@end
// YTPivotBarItemView Header has been moved to https://github.com/arichornloverALT/YouTubeHeader/blob/main/YTPivotBarItemView.h

// YTTapToSeek - https://github.com/bhackel/YTTapToSeek
// YTMainAppVideoPlayerOverlayViewController Header has been moved to https://github.com/arichornloverALT/YouTubeHeader/blob/main/YTMainAppVideoPlayerOverlayViewController.h

// Enable Premium logo - @bhackel
@interface YTITopbarLogoRenderer : NSObject
@property(readonly, nonatomic) YTIIcon *iconImage;
@end

// Hide Premium Promo in You tab - @bhackel
// YTIIconThumbnailRenderer Header has been moved to https://github.com/arichornloverALT/YouTubeHeader/blob/main/YTIIconThumbnailRenderer.h
// YTICompactListItemThumbnailSupportedRenderers Header has been moved to https://github.com/arichornloverALT/YouTubeHeader/blob/main/YTICompactListItemThumbnailSupportedRenderers.h
// YTICompactListItemRenderer Header has been moved to https://github.com/arichornloverALT/YouTubeHeader/blob/main/YTICompactListItemRenderer.h
// YTIIcon Header has been moved to https://github.com/arichornloverALT/YouTubeHeader/blob/main/YTIIcon.h
// YTICompactLinkRenderer Header has been moved to https://github.com/arichornloverALT/YouTubeHeader/blob/main/YTICompactLinkRenderer.h
// YTIItemSectionSupportedRenderers Header has been moved to https://github.com/arichornloverALT/YouTubeHeader/blob/main/YTIItemSectionSupportedRenderers.h
@interface YTAppCollectionViewController : YTInnerTubeCollectionViewController
- (void)uYouEnhancedFakePremiumModel:(YTISectionListRenderer *)model;
@end
@interface YTInnerTubeCollectionViewController (uYouEnhanced)
@property(readonly, nonatomic) YTISectionListRenderer *model;
@end

// Disable Pull to Full for landscape videos - @bhackel
// YTWatchPullToFullController Header has been moved to https://github.com/PoomSmart/YouTubeHeader/blob/main/YTWatchPullToFullController.h

// Fullscreen to the Right (uYouEnhanced Version) - @arichornlover
@interface YTWatchViewController (uYouEnhanced)
- (UIInterfaceOrientationMask) supportedInterfaceOrientations;
- (UIInterfaceOrientation) preferredInterfaceOrientationForPresentation;
- (void)forceRightFullscreenOrientation;
@end

// uYouPlus
@interface YTHeaderLogoController : UIView
@property(readonly, nonatomic) long long pageStyle;
@end

@interface YTNavigationBarTitleView : UIView
@end

@interface YTChipCloudCell : UIView
@end

@interface YTCountView : UIView
@end

@interface YTPlayabilityResolutionUserActionUIController : NSObject // Skips content warning before playing *some videos - @PoomSmart
- (void)confirmAlertDidPressConfirm;
@end

@interface YTTransportControlsButtonView : UIView
@end

@interface YTFullscreenActionsView : UIView
@end

@interface _ASCollectionViewCell : UICollectionViewCell
- (id)node;
@end

@interface YTAsyncCollectionView : UICollectionView
@end

@interface FRPSliderCell : UITableViewCell
@end

@interface boolSettingsVC : UIViewController
@end

@interface YTPlaybackButton : UIControl
@end

@interface YTPlaylistHeaderViewController : UIViewController
@property UIButton *downloadsButton;
@end

// Buttons
@interface YTRightNavigationButtons : UIView
- (id)_viewControllerForAncestor;
@property (readonly, nonatomic) NSArray *dynamicButtons;
@property (readonly, nonatomic) NSArray *visibleButtons;
@property (readonly, nonatomic) NSArray *buttons;
@property (readonly, nonatomic) YTQTMButton *searchButton;
@property (readonly, nonatomic) YTQTMButton *notificationButton;
@property (strong, nonatomic) YTQTMButton *sponsorBlockButton;
@property (strong, nonatomic) YTQTMButton *settingsButton;
- (void)setDynamicButtons:(NSArray *)buttons;
- (void)setLeadingPadding:(CGFloat)arg1;
- (void)settingsAction;
@end

// YTSpeed
@interface YTVarispeedSwitchControllerOption : NSObject
- (id)initWithTitle:(id)title rate:(float)rate;
@end

@interface MLHAMQueuePlayer : NSObject
@property id playerEventCenter;
@property id delegate;
- (void)setRate:(float)rate;
- (void)internalSetRate;
@end

// MLPlayerStickySettings Header has been moved to https://github.com/arichornloverALT/YouTubeHeader/blob/main/MLPlayerStickySettings.h

@interface MLPlayerEventCenter : NSObject
- (void)broadcastRateChange:(float)rate;
@end

@interface HAMPlayerInternal : NSObject
- (void)setRate:(float)rate;
@end

// App Theme
@interface YTColor : NSObject
+ (UIColor *)white1;
+ (UIColor *)white2;
+ (UIColor *)white3;
+ (UIColor *)white4;
+ (UIColor *)white5;
+ (UIColor *)black0;
+ (UIColor *)black1;
+ (UIColor *)black2;
+ (UIColor *)black3;
+ (UIColor *)black4;
+ (UIColor *)blackPure;
+ (UIColor *)grey1;
+ (UIColor *)grey2;
@end

@interface YTPageStyleController
+ (NSInteger)pageStyle;
@end

@interface YCHLiveChatView : UIView
@end

@interface ELMView : UIView
@end

@interface ELMContainerNode : NSObject
@end

@interface YTAutonavEndscreenView : UIView
@end

@interface YTPivotBarIndicatorView : UIView
@end
