#import "uYouPlus.h"

// Keys for "Copy settings" button (for: uYouEnhanced)
// In alphabetical order for tweaks after uYouEnhanced
NSArray *NSUserDefaultsCopyKeys = @[
    // uYouEnhanced - gathered using get_keys.py
    @"autoHideHomeBar_enabled", @"bigYTMiniPlayer_enabled", @"centerYouTubeLogo_enabled", @"classicVideoPlayer_enabled", @"disableAmbientMode_enabled", @"disableAnimatedYouTubeLogo_enabled", @"disableChapterSkip_enabled", @"disableCollapseButton_enabled", @"disableFullscreenButton_enabled", @"disableHints_enabled",
    @"disableLiveChatSection_enabled", @"disableManageAllHistorySection_enabled", @"disableModernButtons_enabled", @"disableModernFlags_enabled", @"disableNotificationsSection_enabled", @"disablePrivacySection_enabled", @"disablePullToFull_enabled", @"disableRemainingTime_enabled", @"disableResumeToShorts_enabled",@"disableRoundedHints_enabled", @"disableTryNewFeaturesSection_enabled", @"disableVideoQualityPreferencesSection_enabled", @"disableAccountSection_enabled",
    @"doubleTapToSeek_disabled", @"enableShareButton_enabled", @"enableSaveToButton_enabled", @"enableVersionSpoofer_enabled", @"fixLowContrastMode_enabled", @"flex_enabled", @"hideAutoplaySwitch_enabled", @"hideBuySuperThanks_enabled", @"hideCC_enabled", @"hideChannelHeaderLinks_enabled", @"hideChannelWatermark_enabled",
    @"hideChipBar_enabled", @"hideClipButton_enabled", @"hideCommentSection_enabled", @"hideCommunityPosts_enabled", @"hideConnectButton_enabled", @"hideDownloadButton_enabled", @"hideDoubleTapToSeekOverlay_enabled", @"hideFullscreenActions_enabled", @"hideHeatwaves_enabled", @"hideHomeTab_enabled", @"hideHoverCards_enabled", @"hideHUD_enabled", @"hideModernFlags_enabled", @"hidePaidPromotionCard_enabled", @"hidePlayNextInQueue_enabled",
    @"hidePreviewCommentSection_enabled", @"hidePreviousAndNextButton_enabled", @"hideRemixButton_enabled", @"hideReportButton_enabled", @"hideRightPanel_enabled", @"hideShareButton_enabled", @"hideSponsorBlockButton_enabled", @"hideSubcriptions_enabled", @"hideSubscriptionsNotificationBadge_enabled", @"hideThanksButton_enabled", @"hideVideoPlayerShadowOverlayButtons_enabled", @"hideVideoTitle_enabled", @"hideYouTubeLogo_enabled",
    @"lowContrastMode_enabled", @"newSettingsUI_enabled", @"noRelatedWatchNexts_enabled", @"noSuggestedVideo_enabled", @"noVideosInFullscreen_enabled",
    @"pinchToZoom_enabled", @"portraitFullscreen_enabled", @"redProgressBar_enabled", @"redSubscribeButton_enabled", @"reExplore_enabled", @"shortsQualityPicker_enabled", @"slideToSeek_enabled", @"snapToChapter_enabled", @"stockVolumeHUD_enabled", @"stickNavigationBar_enabled", @"uYouAdBlockingWorkaround_enabled", @"uYouAdBlockingWorkaroundLite_enabled", @"ytMiniPlayer_enabled", @"ytNoModernUI_enabled", @"ytStartupAnimation_enabled",
    // uYou - https://github.com/MiRO92/uYou-for-YouTube
    @"showedWelcomeVC", @"hideShortsTab", @"hideCreateTab", @"hideCastButton", @"relatedVideosAtTheEndOfYTVideos", @"removeYouTubeAds", @"backgroundPlayback", @"disableAgeRestriction", @"iPadLayout", @"noSuggestedVideoAtEnd", @"shortsProgressBar", @"hideShortsCells", @"removeShortsCell", @"startupPage",
    // DEMC - https://github.com/therealFoxster/DontEatMyContent/blob/master/Tweak.h
    @"DEMC_enabled", @"DEMC_colorViewsEnabled", @"DEMC_safeAreaConstant", @"DEMC_disableAmbientMode", 
    @"DEMC_limitZoomToFill", @"DEMC_enableForAllVideos",
    // iSponsorBlock cannot be exported using this method - it is also being removed in v5
    // Return-YouTube-Dislike - https://github.com/PoomSmart/Return-YouTube-Dislikes/blob/main/TweakSettings.h
    @"RYD-ENABLED", @"RYD-VOTE-SUBMISSION", @"RYD-EXACT-LIKE-NUMBER", @"RYD-EXACT-NUMBER",
    // All YTVideoOverlay Tweaks - https://github.com/PoomSmart/YTVideoOverlay/blob/0fc6d29d1aa9e75f8c13d675daec9365f753d45e/Tweak.x#L28C1-L41C84
    @"YTVideoOverlay-YouLoop-Enabled", @"YTVideoOverlay-YouTimeStamp-Enabled", @"YTVideoOverlay-YouMute-Enabled", 
    @"YTVideoOverlay-YouQuality-Enabled", @"YTVideoOverlay-YouLoop-Position", @"YTVideoOverlay-YouTimeStamp-Position", 
    @"YTVideoOverlay-YouMute-Position", @"YTVideoOverlay-YouQuality-Position",
    // YouPiP - https://github.com/PoomSmart/YouPiP/blob/main/Header.h
    @"YouPiPPosition", @"CompatibilityModeKey", @"PiPActivationMethodKey", @"PiPActivationMethod2Key", 
    @"NoMiniPlayerPiPKey", @"NonBackgroundableKey",
    // YTABConfig cannot be reasonably exported using this method
    // YTHoldForSpeed will be removed in v5
    // YouTube Plus / YTLite cannot be exported using this method
    // YTUHD - https://github.com/PoomSmart/YTUHD/blob/master/Header.h
    @"EnableVP9", @"AllVP9",
    // Useful YouTube Keys
    @"inline_muted_playback_enabled",
];


// Some default values to ignore when exporting settings
NSDictionary *NSUserDefaultsCopyKeysDefaults = @{
    @"fixCasting_enabled": @1,
    @"inline_muted_playback_enabled": @5,
    @"newSettingsUI_enabled": @1,
    @"DEMC_safeAreaConstant": @21.5,
    @"RYD-ENABLED": @1,
    @"RYD-VOTE-SUBMISSION": @1,
    // Duplicate keys are not allowed in NSDictionary. If present, only the last one will be kept.
};
