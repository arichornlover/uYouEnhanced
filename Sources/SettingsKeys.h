#import "uYouPlus.h"
#import "uYouPlusSettings.h"

NSArray *NSUserDefaultsCopyKeys = @[
    kReplaceCopyandPasteButtons, kAppTheme, kOLEDKeyboard,
    kPortraitFullscreen, kFullscreenToTheRight, kSlideToSeek,
    kYTTapToSeek, kDoubleTapToSeek, kSnapToChapter, kPinchToZoom,
    kYTMiniPlayer, kStockVolumeHUD, kReplaceYTDownloadWithuYou,
    kDisablePullToFull, kDisableChapterSkip, kAlwaysShowRemainingTime,
    kDisableRemainingTime, kEnableShareButton, kEnableSaveToButton,
    kHideYTMusicButton, kHideAutoplaySwitch, kHideCC, kHideVideoTitle,
    kDisableCollapseButton, kDisableFullscreenButton, kHideHUD,
    kHidePaidPromotionCard, kHideChannelWatermark,
    kHideVideoPlayerShadowOverlayButtons, kHidePreviousAndNextButton,
    kRedProgressBar, kHideHoverCards, kHideRightPanel,
    kHideFullscreenActions, kHideSuggestedVideo, kHideHeatwaves,
    kHideOverlayDarkBackground, kDisableAmbientMode,
    kHideVideosInFullscreen, kHideRelatedWatchNexts,
    kHideBuySuperThanks, kHideSubscriptions, kShortsQualityPicker,
    kHideShortsClipButton, kHideShortsDownloadButton, kHideShortsRemixButton, kHideShortsStatsButton,
    kDisableResumeToShorts,
    kRedSubscribeButton, kHideButtonContainers, kHideConnectButton,
    kHideShareButton, kHideRemixButton, kHideThanksButton,
    kHideDownloadButton, kHideClipButton, kHideSaveToPlaylistButton,
    kHideReportButton, kHidePreviewCommentSection, kHideCommentSection,
    kDisableAccountSection, kDisableAutoplaySection,
    kDisableTryNewFeaturesSection, kDisableVideoQualityPreferencesSection,
    kDisableNotificationsSection, kDisableManageAllHistorySection,
    kDisableYourDataInYouTubeSection, kDisablePrivacySection,
    kDisableLiveChatSection, kHidePremiumPromos, kHideHomeTab,
    kLowContrastMode, kClassicVideoPlayer, kDisableModernButtons,
    kDisableModernFlags, kEnableVersionSpoofer, kGoogleSignInPatch,
    kEnableDynamicIslandFix, kAdBlockWorkaroundLite, kAdBlockWorkaround, kFixPlaybackIssues,
    kShortsProgressBar,
    kYTPremiumLogo, kDisableAnimatedYouTubeLogo, kCenterYouTubeLogo,
    kHideYouTubeLogo, kYTStartupAnimation, kDisableHints,
    kStickNavigationBar, kHideiSponsorBlockButton, kHideChipBar,
    kShowNotificationsTab, kHidePlayNextInQueue, kHideCommunityPosts,
    kHideChannelHeaderLinks, kiPhoneLayout,
    kAutoHideHomeBar, kHideSubscriptionsNotificationBadge,
    kNewSettingsUI, kFlex, kGoogleSigninFix,

    @"showedWelcomeVC", @"hideShortsTab", @"hideCreateTab",
    @"hideCastButton", @"relatedVideosAtTheEndOfYTVideos",
    @"removeYouTubeAds", @"backgroundPlayback", @"disableAgeRestriction",
    @"iPadLayout", @"noSuggestedVideoAtEnd", @"shortsProgressBar",
    @"hideShortsCells", @"removeShortsCell", @"startupPage",

    @"DEMC_enabled", @"DEMC_colorViewsEnabled", @"DEMC_safeAreaConstant",
    @"DEMC_disableAmbientMode", @"DEMC_limitZoomToFill",
    @"DEMC_enableForAllVideos",

    @"RYD-ENABLED", @"RYD-VOTE-SUBMISSION", @"RYD-EXACT-LIKE-NUMBER",
    @"RYD-EXACT-NUMBER",

    @"YTVideoOverlay-YouLoop-Enabled", @"YTVideoOverlay-YouTimeStamp-Enabled",
    @"YTVideoOverlay-YouMute-Enabled", @"YTVideoOverlay-YouQuality-Enabled",
    @"YTVideoOverlay-YouLoop-Position", @"YTVideoOverlay-YouTimeStamp-Position",
    @"YTVideoOverlay-YouMute-Position", @"YTVideoOverlay-YouQuality-Position",

    @"YouPiPPosition", @"CompatibilityModeKey", @"PiPActivationMethodKey",
    @"PiPActivationMethod2Key", @"NoMiniPlayerPiPKey", @"NonBackgroundableKey",

    @"EnableVP9", @"AllVP9",

    @"inline_muted_playback_enabled",
];

NSDictionary *NSUserDefaultsCopyKeysDefaults = @{
    @"fixCasting_enabled": @1,
    @"inline_muted_playback_enabled": @5,
    @"newSettingsUI_enabled": @1,
    @"DEMC_safeAreaConstant": @21.5,
    @"RYD-ENABLED": @1,
    @"RYD-VOTE-SUBMISSION": @1,
};

