#import <UIKit/UIKit.h>
#import <LocalAuthentication/LocalAuthentication.h>
#import <CaptainHook/CaptainHook.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <sys/utsname.h>
#import <substrate.h>
#import <rootless.h>

#import "uYouPlusThemes.h" // Hide "Buy Super Thanks" banner (_ASDisplayView)
#import <YouTubeHeader/YTAppDelegate.h> // Activate FLEX
#import <YouTubeHeader/YTIMenuConditionalServiceItemRenderer.h>
#import <YouTubeHeader/YTIPlayerBarDecorationModel.h>
#import <YouTubeHeader/YTPlayerBarRectangleDecorationView.h>
#import <YouTubeHeader/YTVideoQualitySwitchOriginalController.h>
#import <YouTubeHeader/YTIGuideResponse.h>
#import <YouTubeHeader/YTIGuideResponseSupportedRenderers.h>
#import <YouTubeHeader/YTIPivotBarSupportedRenderers.h>
#import <YouTubeHeader/YTIPivotBarItemRenderer.h>
#import <YouTubeHeader/YTIBrowseRequest.h>
#import <YouTubeHeader/YTIButtonRenderer.h>
#import <YouTubeHeader/YTIElementRenderer.h>
#import <YouTubeHeader/YTISectionListRenderer.h>
#import <YouTubeHeader/YTWatchNextResultsViewController.h>
#import <YouTubeHeader/YTPlayerOverlay.h>
#import <YouTubeHeader/YTPlayerOverlayProvider.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayView.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayViewController.h>
#import <YouTubeHeader/YTReelWatchPlaybackOverlayView.h>
#import <YouTubeHeader/YTInlinePlayerBarContainerView.h>
#import <YouTubeHeader/YTInnerTubeCollectionViewController.h>
#import <YouTubeHeader/YTPivotBarItemView.h>
#import <YouTubeHeader/YTCollectionViewCell.h>
#import <YouTubeHeader/YTIFormattedString.h>
#import <YouTubeHeader/GPBMessage.h>
#import <YouTubeHeader/YTIStringRun.h>
#import <YouTubeHeader/YTWatchViewController.h>
#import <YouTubeHeader/YTIPivotBarRenderer.h>
#import <YouTubeHeader/YTPlayerOverlayManager.h> // Fixes uYou crash when trying to play video (#1422)

// Hide buttons under the video player by @PoomSmart
#import <YouTubeHeader/ASCollectionElement.h>
#import <YouTubeHeader/ASCollectionView.h>
#import <YouTubeHeader/ELMNodeController.h>

// YouTube-X
#import <YouTubeHeader/YTReelModel.h>
#import <YouTubeHeader/YTVideoWithContextNode.h>
#import <YouTubeHeader/ELMCellNode.h>

#define LOC(x) [tweakBundle localizedStringForKey:x value:nil table:nil]
#define IS_ENABLED(k) [[NSUserDefaults standardUserDefaults] boolForKey:k]
#define APP_THEME_IDX [[NSUserDefaults standardUserDefaults] integerForKey:@"appTheme"]
#define YT_BUNDLE_ID @"com.google.ios.youtube"
#define YT_NAME @"YouTube"
#define DEFAULT_RATE 1.0f // YTSpeed
#define LOWCONTRASTMODE_CUTOFF_VERSION @"17.38.10" // LowContrastMode (v17.33.2-17.38.10)

// Always show remaining time in video player - @bhackel
@interface YTPlayerBarController : NSObject
@property(nonatomic, strong) YTInlinePlayerBarContainerView *playerBar;
@end
@interface YTInlinePlayerBarContainerView (uYouEnhanced)
@property(nonatomic, assign) BOOL shouldDisplayTimeRemaining;
@end

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
@interface YTPivotBarItemView (uYouEnhanced)
@property (nonatomic, strong) YTPivotBarItemViewAccessibilityControl *hitTarget;
@end

// YTTapToSeek - https://github.com/bhackel/YTTapToSeek
// Header has been moved to https://github.com/arichornlover/YouTubeHeader/blob/main/YTMainAppVideoPlayerOverlayViewController.h

// Enable Premium logo - @bhackel
@interface YTITopbarLogoRenderer : NSObject
@property(readonly, nonatomic) YTIIcon *iconImage;
@end

// Hide Premium Promo in You tab - @bhackel
@interface YTIIconThumbnailRenderer : GPBMessage
@property (nonatomic, strong) YTIIcon *icon;
- (BOOL)hasIcon;
@end
@interface YTICompactListItemThumbnailSupportedRenderers : GPBMessage
@property (nonatomic, strong) YTIIconThumbnailRenderer *iconThumbnailRenderer;
- (BOOL)hasIconThumbnailRenderer;
@end
@interface YTICompactListItemRenderer : GPBMessage
@property (nonatomic, strong) YTICompactListItemThumbnailSupportedRenderers *thumbnail;
@property (nonatomic, strong) YTIFormattedString *title;
- (BOOL)hasThumbnail;
- (BOOL)hasTitle;
@end
@interface YTIIcon (uYouEnhanced)
- (BOOL)hasIconType;
@end
@interface YTICompactLinkRenderer : GPBMessage
@property (nonatomic, strong) YTIIcon *icon;
@property (nonatomic, strong) YTIFormattedString *title;
@property (nonatomic, strong) YTICompactListItemThumbnailSupportedRenderers *thumbnail;
- (BOOL)hasIcon;
- (BOOL)hasThumbnail;
@end
@interface YTIItemSectionSupportedRenderers (uYouEnhanced)
@property(readonly, nonatomic) YTICompactLinkRenderer *compactLinkRenderer;
@property(readonly, nonatomic) YTICompactListItemRenderer *compactListItemRenderer;
- (BOOL)hasCompactLinkRenderer;
- (BOOL)hasCompactListItemRenderer;
@end
@interface YTAppCollectionViewController : YTInnerTubeCollectionViewController
- (void)uYouEnhancedFakePremiumModel:(YTISectionListRenderer *)model;
@end
@interface YTInnerTubeCollectionViewController (uYouEnhanced)
@property(readonly, nonatomic) YTISectionListRenderer *model;
@end

// Disable Pull to Full for landscape videos - @bhackel
@interface YTWatchPullToFullController : NSObject
@property(nonatomic, strong) YTWatchViewController *playerViewSource;
@end
@interface YTWatchViewController (uYouEnhanced)
@property(nonatomic, strong) YTWatchPullToFullController *pullToFullController;
- (NSUInteger) allowedFullScreenOrientations;
// Fullscreen to the Right (uYouEnhanced Version) - @arichornlover
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
@property(readonly, nonatomic) YTQTMButton *searchButton;
@property(readonly, nonatomic) YTQTMButton *notificationButton;
@property(strong, nonatomic) YTQTMButton *sponsorBlockButton;
@property(strong, nonatomic) YTQTMButton *uYouPlusButton;
- (void)setLeadingPadding:(CGFloat)arg1;
- (void)uYouPlusRootOptionsAction;
@end

@interface YTISlimMetadataButtonSupportedRenderers : NSObject
- (id)slimButton_buttonRenderer;
- (id)slimMetadataButtonRenderer;
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

@interface MLPlayerStickySettings (uYouPlus)
- (void)setRate:(float)rate;
@end

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
