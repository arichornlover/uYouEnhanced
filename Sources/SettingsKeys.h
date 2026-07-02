#import "uYouPlus.h"
#import "uYouPlusSettings.h"

// Keys for "Copy settings" button (for: uYouEnhanced)
NSArray *NSUserDefaultsCopyKeys = @[
    // uYouEnhanced keys (cleaned - only existing ones)
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
    kAdBlockWorkaroundLite, kAdBlockWorkaround, 
    kYTPremiumLogo, kDisableAnimatedYouTubeLogo, kCenterYouTubeLogo, 
    kHideYouTubeLogo, kYTStartupAnimation, kDisableHints, 
    kStickNavigationBar, kHideiSponsorBlockButton, kHideChipBar, 
    kShowNotificationsTab, kHidePlayNextInQueue, kHideCommunityPosts, 
    kHideChannelHeaderLinks, kiPhoneLayout, kBigYTMiniPlayer, 
    kReExplore, kAutoHideHomeBar, kHideSubscriptionsNotificationBadge, 
    kFixCasting, kNewSettingsUI, kFlex, kGoogleSigninFix,

    // uYou 3.0.4 keys
    @"showedWelcomeVC", @"hideShortsTab", @"hideCreateTab", 
    @"hideCastButton", @"relatedVideosAtTheEndOfYTVideos", 
    @"removeYouTubeAds", @"backgroundPlayback", @"disableAgeRestriction", 
    @"iPadLayout", @"noSuggestedVideoAtEnd", @"shortsProgressBar", 
    @"hideShortsCells", @"removeShortsCell", @"startupPage",

    // DEMC
    @"DEMC_enabled", @"DEMC_colorViewsEnabled", @"DEMC_safeAreaConstant", 
    @"DEMC_disableAmbientMode", @"DEMC_limitZoomToFill", 
    @"DEMC_enableForAllVideos",

    // Return-YouTube-Dislike
    @"RYD-ENABLED", @"RYD-VOTE-SUBMISSION", @"RYD-EXACT-LIKE-NUMBER", 
    @"RYD-EXACT-NUMBER",

    // YTVideoOverlay
    @"YTVideoOverlay-YouLoop-Enabled", @"YTVideoOverlay-YouTimeStamp-Enabled", 
    @"YTVideoOverlay-YouMute-Enabled", @"YTVideoOverlay-YouQuality-Enabled", 
    @"YTVideoOverlay-YouLoop-Position", @"YTVideoOverlay-YouTimeStamp-Position", 
    @"YTVideoOverlay-YouMute-Position", @"YTVideoOverlay-YouQuality-Position",

    // YouPiP
    @"YouPiPPosition", @"CompatibilityModeKey", @"PiPActivationMethodKey", 
    @"PiPActivationMethod2Key", @"NoMiniPlayerPiPKey", @"NonBackgroundableKey",

    // YTUHD
    @"EnableVP9", @"AllVP9",

    // Useful YouTube Keys
    @"inline_muted_playback_enabled",
];

// Default values to ignore when exporting
NSDictionary *NSUserDefaultsCopyKeysDefaults = @{
    @"fixCasting_enabled": @1,
    @"inline_muted_playback_enabled": @5,
    @"newSettingsUI_enabled": @1,
    @"DEMC_safeAreaConstant": @21.5,
    @"RYD-ENABLED": @1,
    @"RYD-VOTE-SUBMISSION": @1,
};
