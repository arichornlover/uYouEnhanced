#import <ActivityKit/ActivityKit.h> 
#import <UIKit/UIKit.h>
#import <HBLog.h>
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
#import <YouTubeHeader/ELMPBElement.h>
#import <YouTubeHeader/ELMPBProperties.h>
#import <YouTubeHeader/ELMPBIdentifierProperties.h>
#import <YouTubeHeader/GPBMessage.h>
#import <YouTubeHeader/MLPlayerStickySettings.h>
#import <YouTubeHeader/YTAppDelegate.h>
#import <YouTubeHeader/YTAssetLoader.h>
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
#import <YouTubeHeader/YTIShelfRenderer.h>
#import <YouTubeHeader/YTBrowseViewController.h>
#import <YouTubeHeader/YTIPivotBarItemRenderer.h>
#import <YouTubeHeader/YTIPivotBarRenderer.h>
#import <YouTubeHeader/YTIPivotBarSupportedRenderers.h>
#import <YouTubeHeader/YTIPlayerBarDecorationModel.h>
#import <YouTubeHeader/YTISectionListRenderer.h>
#import <YouTubeHeader/YTIStringRun.h>
#import <YouTubeHeader/YTIWatchNextResponse.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayViewController.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayView.h>
#import <YouTubeHeader/YTNavigationBarTitleView.h>
#import <YouTubeHeader/YTPlayerBarController.h>
#import <YouTubeHeader/YTPlayerBarRectangleDecorationView.h>
#import <YouTubeHeader/YTPlayerOverlay.h>
#import <YouTubeHeader/YTPlayerOverlayProvider.h>
#import <YouTubeHeader/QTMIcon.h>
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

// Keys
// Copy/Paste Settings
static NSString *const kReplaceCopyandPasteButtons = @"replaceCopyandPasteButtons_enabled";
// App appearance
static NSString *const kAppTheme = @"appTheme";
static NSString *const kOLEDKeyboard = @"oledKeyBoard_enabled";
// Video player
static NSString *const kPortraitFullscreen = @"portraitFullscreen_enabled";
static NSString *const kFullscreenToTheRight = @"fullscreenToTheRight_enabled";
static NSString *const kSlideToSeek = @"slideToSeek_enabled";
static NSString *const kYTTapToSeek = @"YTTapToSeek_enabled";
static NSString *const kDoubleTapToSeek = @"doubleTapToSeek_enabled";
static NSString *const kSnapToChapter = @"snapToChapter_enabled";
static NSString *const kPinchToZoom = @"pinchToZoom_enabled";
static NSString *const kYTMiniPlayer = @"ytMiniPlayer_enabled";
static NSString *const kStockVolumeHUD = @"stockVolumeHUD_enabled";
static NSString *const kReplaceYTDownloadWithuYou = @"kReplaceYTDownloadWithuYou_enabled";
static NSString *const kDisablePullToFull = @"disablePullToFull_enabled";
static NSString *const kDisableChapterSkip = @"disableChapterSkip_enabled";
static NSString *const kAlwaysShowRemainingTime = @"alwaysShowRemainingTime_enabled";
static NSString *const kDisableRemainingTime = @"disableRemainingTime_enabled";
// Video controls overlay
static NSString *const kEnableShareButton = @"enableShareButton_enabled";
static NSString *const kEnableSaveToButton = @"enableSaveToButton_enabled";
static NSString *const kHideYTMusicButton = @"hideYTMusicButton_enabled";
static NSString *const kHideAutoplaySwitch = @"hideAutoplaySwitch_enabled";
static NSString *const kHideCC = @"hideCC_enabled";
static NSString *const kHideVideoTitle = @"hideVideoTitle_enabled";
static NSString *const kDisableCollapseButton = @"disableCollapseButton_enabled";
static NSString *const kDisableFullscreenButton = @"disableFullscreenButton_enabled";
static NSString *const kHideHUD = @"hideHUD_enabled";
static NSString *const kHidePaidPromotionCard = @"hidePaidPromotionCard_enabled";
static NSString *const kHideChannelWatermark = @"hideChannelWatermark_enabled";
static NSString *const kHideVideoPlayerShadowOverlayButtons = @"hideVideoPlayerShadowOverlayButtons_enabled";
static NSString *const kHidePreviousAndNextButton = @"hidePreviousAndNextButton_enabled";
static NSString *const kRedProgressBar = @"redProgressBar_enabled";
static NSString *const kHideHoverCards = @"hideHoverCards_enabled";
static NSString *const kHideRightPanel = @"hideRightPanel_enabled";
static NSString *const kHideFullscreenActions = @"hideFullscreenActions_enabled";
static NSString *const kHideSuggestedVideo = @"hideSuggestedVideo_enabled";
static NSString *const kHideHeatwaves = @"hideHeatwaves_enabled";
static NSString *const kHideDoubleTapToSeekOverlay = @"hideDoubleTapToSeekOverlay_enabled";
static NSString *const kHideOverlayDarkBackground = @"hideOverlayDarkBackground_enabled";
static NSString *const kDisableAmbientMode = @"disableAmbientMode_enabled";
static NSString *const kHideVideosInFullscreen = @"hideVideosInFullscreen_enabled";
static NSString *const kHideRelatedWatchNexts = @"hideRelatedWatchNexts_enabled";
// Shorts control overlay
static NSString *const kHideBuySuperThanks = @"hideBuySuperThanks_enabled";
static NSString *const kHideSubscriptions = @"hideSubscriptions_enabled";
static NSString *const kShortsQualityPicker = @"shortsQualityPicker_enabled";
// Video player buttons
static NSString *const kRedSubscribeButton = @"redSubscribeButton_enabled";
static NSString *const kHideButtonContainers = @"hideButtonContainers_enabled";
static NSString *const kHideConnectButton = @"hideConnectButton_enabled";
static NSString *const kHideShareButton = @"hideShareButton_enabled";
static NSString *const kHideRemixButton = @"hideRemixButton_enabled";
static NSString *const kHideThanksButton = @"hideRemixButton_enabled";
static NSString *const kHideDownloadButton = @"hideDownloadButton_enabled";
static NSString *const kHideClipButton = @"hideClipButton_enabled";
static NSString *const kHideSaveToPlaylistButton = @"hideSaveToPlaylistButton_enabled";
static NSString *const kHideReportButton = @"hideReportButton_enabled";
static NSString *const kHidePreviewCommentSection = @"hidePreviewCommentSection_enabled";
static NSString *const kHideCommentSection = @"hideCommentSection_enabled";
// App settings overlay
static NSString *const kDisableAccountSection = @"disableAccountSection_enabled";
static NSString *const kDisableAutoplaySection = @"disableAutoplaySection_enabled";
static NSString *const kDisableTryNewFeaturesSection = @"disableTryNewFeaturesSection_enabled";
static NSString *const kDisableVideoQualityPreferencesSection = @"disableVideoQualityPreferencesSection_enabled";
static NSString *const kDisableNotificationsSection = @"disableNotificationsSection_enabled";
static NSString *const kDisableManageAllHistorySection = @"disableManageAllHistorySection_enabled";
static NSString *const kDisableYourDataInYouTubeSection = @"disableYourDataInYouTubeSection_enabled";
static NSString *const kDisablePrivacySection = @"disablePrivacySection_enabled";
static NSString *const kDisableLiveChatSection = @"disableLiveChatSection_enabled";
static NSString *const kHidePremiumPromos = @"hidePremiumPromos_enabled";
// UI Interface
static NSString *const kHideHomeTab = @"hideHomeTab_enabled";
static NSString *const kLowContrastMode = @"lowContrastMode_enabled";
static NSString *const kClassicVideoPlayer = @"classicVideoPlayer_enabled";
static NSString *const kDisableModernButtons = @"disableModernButtons_enabled";
static NSString *const kDisableRoundedHints = @"disableRoundedHints_enabled";
static NSString *const kDisableModernFlags = @"disableModernFlags_enabled";
static NSString *const kYTNoModernUI = @"ytNoModernUI_enabled";
static NSString *const kEnableVersionSpoofer = @"enableVersionSpoofer_enabled";
// Miscellaneous
static NSString *const kGoogleSignInPatch = @"googleSignInPatch_enabled";
static NSString *const kAdBlockWorkaroundLite = @"adBlockWorkaroundLite_enabled";
static NSString *const kAdBlockWorkaround = @"adBlockWorkaround_enabled";
static NSString *const kYouTabFakePremium = @"youTabFakePremium_enabled";
static NSString *const kDisableAnimatedYouTubeLogo = @"disableAnimatedYouTubeLogo_enabled";
static NSString *const kCenterYouTubeLogo = @"centerYouTubeLogo_enabled";
static NSString *const kHideYouTubeLogo = @"hideYouTubeLogo_enabled";
static NSString *const kYTStartupAnimation = @"ytStartupAnimation_enabled";
static NSString *const kDisableHints = @"disableHints_enabled";
static NSString *const kStickNavigationBar = @"stickNavigationBar_enabled";
static NSString *const kHideiSponsorBlockButton = @"hideiSponsorBlockButton_enabled";
static NSString *const kHideChipBar = @"hideChipBar_enabled";
static NSString *const kShowNotificationsTab = @"showNotificationsTab_enabled";
static NSString *const kHidePlayNextInQueue = @"hidePlayNextInQueue_enabled";
static NSString *const kHideCommunityPosts = @"hideCommunityPosts_enabled";
static NSString *const kHideChannelHeaderLinks = @"hideChannelHeaderLinks_enabled";
static NSString *const kiPhoneLayout = @"iPhoneLayout_enabled";
static NSString *const kBigYTMiniPlayer = @"bigYTMiniPlayer_enabled";
static NSString *const kReExplore = @"reExplore_enabled";
static NSString *const kAutoHideHomeBar = @"autoHideHomeBar_enabled";
static NSString *const kHideSubscriptionsNotificationBadge = @"hideSubscriptionsNotificationBadge_enabled";
static NSString *const kFixCasting = @"fixCasting_enabled";
static NSString *const kNewSettingsUI = @"newSettingsUI_enabled";
static NSString *const kFlex = @"flex_enabled";
// unused (uYouEnhanced)
static NSString *const kGoogleSigninFix = @"googleSigninFix_enabled";

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

// OLED Live Chat - @bhackel
@interface YTLUserDefaults : NSUserDefaults
+ (void)exportYtlSettings;
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
@end

// Center YouTube Logo (Custom Version) - @arichornlover
@interface YTNavigationBarTitleView (uYouEnhanced)
@property (nonatomic, strong) UIView *customView;
- (void)alignCustomViewToCenterOfWindow;
@end

// uYouPlus
@interface YTHeaderLogoController : UIView
@property(readonly, nonatomic) long long pageStyle;
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

@interface HelperVC : UIViewController
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

@interface MLHAMQueuePlayer : NSObject
@property id playerEventCenter;
@property id delegate;
- (void)setRate:(float)rate;
- (void)internalSetRate;
@end

// MLPlayerStickySettings Header has been moved to https://github.com/arichornloverALT/YouTubeHeader/blob/main/MLPlayerStickySettings.h
// MLPlayerEventCenter Header has been moved to https://github.com/PoomSmart/YouTubeHeader/blob/main/MLPlayerEventCenter.h

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

@interface YTWrapperSplitView : UIView
@end

@interface YTAutonavEndscreenView : UIView
@end

@interface YTPivotBarIndicatorView : UIView
@end
