// keys migration from uYouEnhanced → YouMod 2.0.0+

#import "uYouPlus.h"
#import <UIKit/UIKit.h>

// YouMod 2.0.0 key definitions
// (https://github.com/Tonwalter888/YouMod/blob/main/Files/Headers.h)
// NOTE: several 1.3.0 keys were renamed in 2.0.0 (e.g. HideShareButton →
// RemoveVideoShareButton, HidePrevButton+HideNextButton → HideNextAndPrevButtons).
// We always write to the 2.0.0 key names so a fresh YouMod 2.0.0 install picks
// them up.
#define YouModPrefix @"YouMod"

// Downloading
#define DownloadManager @"YouModDownloadManager"
#define DownloadFix @"YouModDownloadFix"
#define DownloadServerIndex @"YouModDownloadServerIndex"
#define SABRDownload @"YouModSABRDownload"
#define DownloadMethod @"YouModDownloadMethod"
#define PostDownloadAction @"YouModPostDownloadAction"
#define AddDownloadToShorts @"YouModAddDownloadToShorts"
#define AudioPreferIndex @"YouModAudioPreferIndex"
#define DownloadComment @"YouModDownloadComment"
#define DownloadPost @"YouModDownloadPost"
#define AutoClearCache @"YouModAutoClearCache"

// Appearance
#define OLEDTheme @"YouModEnablesOLEDTheme"
#define OLEDKeyboard @"YouModEnablesOLEDKeyboard"

// Navigation bar
#define YTLogoIndex @"YouModYTLogoIndex"
#define StickyNavBar @"YouModStickyNavBar"
#define HideNoti @"YouModHideNotificationButton"
#define HideSearch @"YouModHideSearchButton"
#define HideVoiceSearch @"YouModHideVoiceSearchButton"
#define HideCastButtonNav @"YouModHideCastButtonNavigationBar"

// Feed
#define HideSubbar @"YouModHideSubbar"
#define HideHoriShelf @"YouModHideHoriShelf"
#define HideGenMusicShelf @"YouModHideGenMusicShelf"
#define HideFeedPost @"YouModHideFeedPost"
#define HidePlayables @"YouModHidePlayables"
#define HideShortsShelf @"YouModHideShortsShelf"
#define KeepShortsSubscript @"YouModKeepShortsSubscript"
#define HideSearchHis @"YouModHideSearchHistoryAndSuggestions"
#define HideSurveys @"YouModHideSurveys"
#define HideRelatedVideos @"YouModHideRelatedVideos"
#define RemoveChannelCommunityButton @"YouModRemoveChannelCommunityButton"
#define RemoveChannelSponsorAll @"YouModRemoveChannelSponsorAll"

// Player
#define WifiQualityIndex @"YouModWifiQualityIndex"
#define CellQualityIndex @"YouModCellQualityIndex"
#define LowPowerQualityIndex @"YouModLowPowerQualityIndex"
#define AudioTrack @"YouModAudioTrackSegment"
#define AudioTrackLangIndex @"YouModAudioTrackLangIndex"
#define NoDubbedAudioTrack @"YouModNoDubbedAudioTrack"
#define CaptionTrack @"YouModCaptionTrack"
#define CaptionTrackLangIndex @"YouModCaptionTrackLangIndex"
#define DisablesCaptionTrack @"YouModDisablesCaptionTrack"
#define AutoSpeedIndex @"YouModAutoSpeedIndex"
#define HoldToSpeedIndex @"YouModHoldToSpeedIndex"
#define HideAutoPlayToggle @"YouModHideAutoPlayToggle"
#define HideCaptionsButton @"YouModHideCaptionsButton"
#define HideCastButtonPlayer @"YouModHideCastButtonPlayer"
#define HideNextAndPrevButtons @"YouModHideNextAndPrevButtons"
#define ReplacePrevNextButtons @"YouModReplacePrevNextButtons"
#define SkipBackwardEnabled @"YouModSkipBackwardEnabled"
#define SkipForwardEnabled @"YouModSkipForwardEnabled"
#define RewindSeconds @"YouModRewindSeconds"
#define ForwardSeconds @"YouModForwardSeconds"
#define RemoveDarkOverlay @"YouModRemoveDarkOverlay"
#define RemoveAmbiant @"YouModRemoveAmbiantColors"
#define HideEndScreenCards @"YouModHideEndScreenCards"
#define HideSuggestedVideo @"YouModHideSuggestedVideoOnFinish"
#define HidePaidPromoOverlay @"YouModHidePaidPromoOverlay"
#define HideWaterMark @"YouModHideWaterMark"
#define DisablesEngagementPanel @"YouModDisablesEngagementPanel"
#define DontSnapToChapter @"YouModDontSnapToChapter"
#define PauseOnOverlay @"YouModPauseOnOverlay"
#define GestureControls @"YouModEnableGesturesControls"
#define GestureActivationArea @"YouModGestureActivationArea"
#define LeftSideGesture @"YouModLeftSideGesture"
#define RightSideGesture @"YouModRightSideGesture"
#define GestureHUD @"YouModGestureHUD"
#define GestureHUDSize @"YouModGestureHUDSize"
#define GestureHUDPosition @"YouModGestureHUDPosition"
#define DisablesDoubleTap @"YouModDisablesDoubleTap"
#define DisablesLongHold @"YouModDisablesLongHold"
#define AutoExitFullScreen @"YouModAutoExitFullScreen"
#define DisablesShowRemaining @"YouModDisablesShowRemainingTime"
#define AlwaysShowRemaining @"YouModAlwaysShowRemainingTime"
#define ShowExtraTimeRemaining @"YouModShowExtraTimeRemaining"
#define Uses24HoursTime @"YouModUses24HoursTime"
#define CopyWithTimestampOnPause @"YouModCopyWithTimestampOnPause"
#define HideFullAction @"YouModHideFullScreenAction"
#define HideFullvidTitle @"YouModHideFullscreenVideoTitle"
#define StopAutoplayVideo @"YouModStopAutoplayVideo"
#define HideContentWarning @"YouModHideContentWarning"
#define AutoFullScreen @"YouModAutoFullScreen"
#define PortFull @"YouModPortraitFullscreen"
#define OldQualityPicker @"YouModUseOldQualityPicker"
#define ExtraSpeed @"YouModAddExtraSpeed"
#define ForceMiniPlayer @"YouModForceMiniPlayer"
#define AlwaysShowSeekbar @"YouModAlwaysShowSeekbar"
#define DisablesFreeZoom @"YouModDisablesFreeZoom"
#define TapToSeek @"YouModTapToSeek"
#define PauseTwoFingers @"YouModPauseTwoFingers"
#define HideCommentsSection @"YouModHideCommentsSection"
#define HideCommentsPreview @"YouModHideCommentsPreview"
#define LockSpeed @"YouModLockSpeed"
#define SeekOnOverlay @"YouModSeekOnOverlay"
#define AutoDRCAudioIndex @"YouModAutoDRCAudioIndex"
#define RemoveVideoLikeButton @"YouModRemoveVideoLikeButton"
#define RemoveVideoDislikeButton @"YouModRemoveVideoDislikeButton"
#define RemoveVideoShareButton @"YouModRemoveVideoShareButton"
#define RemoveVideoSaveButton @"YouModRemoveVideoSaveButton"
#define RemoveVideoDownloadButton @"YouModRemoveVideoDownloadButton"
#define RemoveVideoClipButton @"YouModRemoveVideoClipButton"
#define RemoveVideoRemixButton @"YouModRemoveVideoRemixButton"
#define RemoveVideoLiveChatButton @"YouModRemoveVideoLiveChatButton"
#define AutoFeedMute @"YouModAutoFeedMute"

// Shorts
#define HideShortsTopbar @"YouModHideShortsTopbar"
#define HideShortsSubbar @"YouModHideShortsSubbar"
#define FullScreenShorts @"YouModFullScreenShorts"
#define RemoveShortsLive @"YouModRemoveShortsLive"
#define RemoveShortsPosts @"YouModRemoveShortsPosts"
#define HideShortsProducts @"YouModHideShortsProducts"
#define HideShortsRecbar @"YouModHideShortsRecbar"
#define EnablesShortsQuality @"YouModEnablesShortsQuality"
#define ShowShortsSeekbar @"YouModShowShortsSeekbar"
#define ShortsActionIndex @"YouModMakeAShortsAction"
#define ShortsOnly @"YouModShortsOnly"
#define RemoveShortsLikeButton @"YouModRemoveShortsLikeButton"
#define RemoveShortsCommentButton @"YouModRemoveShortsCommentButton"
#define RemoveShortsShareButton @"YouModRemoveShortsShareButton"
#define RemoveShortsRemixButton @"YouModRemoveShortsRemixButton"
#define RemoveShortsSoundMetadataButton @"YouModRemoveShortsSoundMetadataButton"
#define RemoveShortsPausedSubButton @"YouModRemoveShortsPausedSubButton"
#define RemoveShortsPausedLiveButton @"YouModRemoveShortsPausedLiveButton"
#define RemoveShortsPausedLensButton @"YouModRemoveShortsPausedLensButton"
#define RemoveShortsPausedTrendsButton @"YouModRemoveShortsPausedTrendsButton"
#define RemoveShortsDisclosure @"YouModRemoveShortsDisclosure"

// Tab bar
#define DefaultTab @"YouModDefaultStartupTab"
#define TabOrder @"YouModTabOrder"
#define HideTabIndi @"YouModHideTabIndicators"
#define HideTabLabels @"YouModHideTabLabels"
#define UseFrostedTabBar @"YouModUseFrostedTabBar"

// Miscellaneous
#define BackgroundPlayback @"YouModEnablesBackgroundPlayback"
#define DisablesShortsPiP @"YouModTrytoDisablesShortsPiP"
#define DisableHints @"YouModDisableHints"
#define BlockUpgradeDialogs @"YouModBlockUpgradeDialogs"
#define HideAreYouThereDialog @"YouModHideAreYouThereDialog"
#define FixesSlowMiniPlayer @"YouModFixesSlowMiniPlayer"
#define DisablesNewMiniPlayer @"YouModDisablesNewMiniPlayer"
#define DisablesSnackBar @"YouModDisablesSnackBar"
#define HideStartupAni @"YouModHideStartupAnimations"
#define HideLikeDislikeVotes @"YouModHideLikeDislikeVotes"
#define HideCommuGuide @"YouModHideCommuGuide"
#define HideEngagementSubbar @"YouModHideEngagementSubbar"
#define DisablesRTL @"YouModDisablesRTL"
#define DeviceUIIndex @"YouModDeviceUIIndex"
#define FloatingKeyboard @"YouModFloatingKeyboard"
#define AutoOpenLink @"YouModAutoOpenLink"
#define FixPlaybackIssues @"YouModFixPlaybackIssues"

// Flyout menu
#define RemovePlayInNextQueueOption @"YouModRemovePlayInNextQueueOption"
#define RemoveDownloadOption @"YouModRemoveDownloadOption"
#define RemoveWatchLaterOption @"YouModRemoveWatchLaterOption"
#define RemoveSaveOption @"YouModRemoveSaveOption"
#define RemoveRemoveFromPlaylistOption @"YouModRemoveRemoveFromPlaylistOption"
#define RemoveShareOption @"YouModRemoveShareOption"
#define RemoveNotInterestedOption @"YouModRemoveNotInterestedOption"
#define RemoveInfoOption @"YouModRemoveInfoOption"
#define RemoveFilterOption @"YouModRemoveFilterOption"
#define RemoveReportOption @"YouModRemoveReportOption"
#define RemoveYouTubeMusicOption @"YouModRemoveYouTubeMusicOption"
#define RemoveFeedBackOption @"YouModRemoveFeedBackOption"
#define RemoveDontRecommendOption @"YouModRemoveDontRecommendOption"
#define RemoveCastOption @"YouModRemoveCastOption"
#define RemoveShuffleOption @"YouModRemoveShuffleOption"
#define RemoveUnSubOption @"YouModRemoveUnSubOption"
#define RemoveHideFromPlaylistOption @"YouModRemoveHideFromPlaylistOption"
#define RemoveHelpOption @"YouModRemoveHelpOption"
#define RemoveNotifyOption @"YouModRemoveNotifyOption"
#define RemoveClearScreenOption @"YouModRemoveClearScreenOption"
#define RemoveAddToLastQueueOption @"YouModRemoveAddToLastQueueOption"

// Overlay buttons (YouMod 2.0.0 player overlay registry)
#define MuteButton @"YouModMuteButton"
#define SpeedButton @"YouModSpeedButton"
#define ShareButton @"YouModShareButton"
#define LoopButton @"YouModLoopButton"
#define CaptionButton @"YouModCaptionButton"
#define QualityButton @"YouModQualityButton"
#define OverlayButtonOrder @"YouModOverlayButtonOrder"
#define GlobalSpeedLocked @"YouModGlobalSpeedLocked"
#define GlobalSavedNormalRate @"YouModGlobalSavedNormalRate"

// =============================================

@interface GOOHUDMessage : NSObject
+ (instancetype)messageWithText:(NSString *)text;
@end

@interface YTHUDMessage : GOOHUDMessage
@end

@interface GOOHUDManagerInternal : NSObject
+ (instancetype)sharedInstance;
- (void)showMessageMainThread:(YTHUDMessage *)message;
@end

@implementation YouModMigrationManager

+ (instancetype)sharedManager {
    static YouModMigrationManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

// Copies a value only when the source key is present, so we never clobber an
// existing YouMod 2.0.0 preference with a default.
static void UYMCopyIfPresent(NSUserDefaults *defaults, NSString *oldKey, NSString *newKey, NSInteger *count) {
    if ([defaults objectForKey:oldKey] != nil) {
        [defaults setObject:[defaults objectForKey:oldKey] forKey:newKey];
        (*count)++;
    }
}

// Copies a BOOL with its value inverted (uYouEnhanced "enable X" → YouMod "disable X").
static void UYMCopyInverted(NSUserDefaults *defaults, NSString *oldKey, NSString *newKey, NSInteger *count) {
    if ([defaults objectForKey:oldKey] != nil) {
        [defaults setBool:![defaults boolForKey:oldKey] forKey:newKey];
        (*count)++;
    }
}

- (void)migrateToYouModWithReset:(BOOL)shouldReset {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSInteger migrated = 0;

    // --- Direct BOOL / value copies (uYouEnhanced → YouMod 2.0.0) ---
    NSDictionary *directMapping = @{
        kOLEDKeyboard: OLEDKeyboard,
        kPortraitFullscreen: PortFull,
        kAlwaysShowRemainingTime: AlwaysShowRemaining,
        kDisableRemainingTime: DisablesShowRemaining,
        kHideAutoplaySwitch: HideAutoPlayToggle,
        kHideCC: HideCaptionsButton,
        kHideVideoTitle: HideFullvidTitle,
        kHidePaidPromotionCard: HidePaidPromoOverlay,
        kHideChannelWatermark: HideWaterMark,
        kHidePreviousAndNextButton: HideNextAndPrevButtons, // 2.0.0 merged prev+next
        kHideHoverCards: HideEndScreenCards,
        kHideSuggestedVideo: HideSuggestedVideo,
        kDisableAmbientMode: RemoveAmbiant,
        kHideOverlayDarkBackground: RemoveDarkOverlay,
        kYTMiniPlayer: ForceMiniPlayer,
        kBigYTMiniPlayer: ForceMiniPlayer,
        kDisableHints: DisableHints,
        kHideHomeTab: HideHomeTab,
        kHideShareButton: RemoveVideoShareButton,
        kHideDownloadButton: RemoveVideoDownloadButton,
        kHideClipButton: RemoveVideoClipButton,
        kHideRemixButton: RemoveVideoRemixButton,
        kHideSaveToPlaylistButton: RemoveVideoSaveButton,
        kHidePlayNextInQueue: RemovePlayInNextQueueOption,
        kHideBuySuperThanks: HideShortsProducts,
        kHideSubscriptions: RemoveShortsPausedSubButton, // Shorts subscribe button
        kHideShortsRemixButton: RemoveShortsRemixButton,
        kShortsQualityPicker: EnablesShortsQuality,
        kFixPlaybackIssues: FixPlaybackIssues,
        kStickNavigationBar: StickyNavBar,
        kHideRelatedWatchNexts: HideRelatedVideos,
        kHideCommunityPosts: RemoveChannelCommunityButton,
        kYTTapToSeek: TapToSeek,
        kHideCommentSection: HideCommentsSection,
        kHidePreviewCommentSection: HideCommentsPreview,
        kHideReportButton: RemoveReportOption,
        kHideYTMusicButton: RemoveYouTubeMusicOption,
        kYTStartupAnimation: HideStartupAni,
        kReplaceYTDownloadWithuYou: DownloadManager,
        // uYou 3.0.4 keys
        @"backgroundPlayback": BackgroundPlayback,
        @"startupPage": DefaultTab,
        @"reorderedTabs": TabOrder,
        @"shortsProgressBar": ShowShortsSeekbar,
        @"hideCastButton": RemoveCastOption,
    };

    for (NSString *oldKey in directMapping) {
        UYMCopyIfPresent(defaults, oldKey, directMapping[oldKey], &migrated);
    }

    // --- Inverted BOOL copies (uYouEnhanced "enable" → YouMod "disable") ---
    NSDictionary *invertedMapping = @{
        kSnapToChapter: DontSnapToChapter,   // snap enabled → don't snap
        kPinchToZoom: DisablesFreeZoom,      // pinch zoom enabled → disable free zoom
    };

    for (NSString *oldKey in invertedMapping) {
        UYMCopyInverted(defaults, oldKey, invertedMapping[oldKey], &migrated);
    }

    // --- Value transforms ---

    // appTheme (0=light, 1=dark, 2=OLED, 3=custom) → OLEDTheme BOOL
    if ([defaults objectForKey:kAppTheme] != nil) {
        [defaults setBool:([defaults integerForKey:kAppTheme] == 2) forKey:OLEDTheme];
        migrated++;
    }

    // kYTPremiumLogo / kHideYouTubeLogo → YTLogoIndex picker (0=default, 1=premium, 2=hide)
    BOOL hasLogoPref = [defaults objectForKey:kYTPremiumLogo] != nil || [defaults objectForKey:kHideYouTubeLogo] != nil;
    if (hasLogoPref) {
        NSInteger logoIndex = 0;
        if ([defaults boolForKey:kHideYouTubeLogo]) logoIndex = 2;
        else if ([defaults boolForKey:kYTPremiumLogo]) logoIndex = 1;
        [defaults setInteger:logoIndex forKey:YTLogoIndex];
        migrated++;
    }

    // iPhoneLayout / iPadLayout → DeviceUIIndex (0=default, 1=iPad, 2=iPhone)
    BOOL hasLayout = [defaults objectForKey:kiPhoneLayout] != nil || [defaults objectForKey:@"iPadLayout"] != nil;
    if (hasLayout) {
        NSInteger deviceIndex = 0;
        if ([defaults boolForKey:@"iPadLayout"]) deviceIndex = 1;
        else if ([defaults boolForKey:kiPhoneLayout]) deviceIndex = 2;
        [defaults setInteger:deviceIndex forKey:DeviceUIIndex];
        migrated++;
    }

    // YouVideoOverlay submodule buttons → YouMod 2.0.0 overlay button registry
    NSDictionary *overlayMapping = @{
        @"YTVideoOverlay-YouLoop-Enabled": LoopButton,
        @"YTVideoOverlay-YouMute-Enabled": MuteButton,
        @"YTVideoOverlay-YouQuality-Enabled": QualityButton,
    };
    for (NSString *oldKey in overlayMapping) {
        UYMCopyIfPresent(defaults, oldKey, overlayMapping[oldKey], &migrated);
    }

    [defaults synchronize];

    dispatch_async(dispatch_get_main_queue(), ^{
        YTHUDMessage *hud = [%c(YTHUDMessage) messageWithText:
            [NSString stringWithFormat:@"Migrated %ld settings to YouMod ✓", (long)migrated]];
        [[%c(GOOHUDManagerInternal) sharedInstance] showMessageMainThread:hud];

        if (shouldReset) {
            NSString *msg = [NSString stringWithFormat:
                @"%ld compatible settings were copied to YouMod 2.0.0.\n\n"
                "uYouEnhanced settings were left untouched.\n"
                "Restart YouTube → test YouMod.",
                (long)migrated];
            msg = [msg stringByAppendingString:@"\n\nuYouEnhanced settings have been reset (except submodules)."];
            // Reset uYouEnhanced keys (keep submodule keys)
            NSArray *protectedKeys = @[/* add submodule keys here if needed */];
            for (NSString *key in [defaults dictionaryRepresentation].allKeys) {
                if ([key hasPrefix:@"k"] && ![protectedKeys containsObject:key]) {
                    [defaults removeObjectForKey:key];
                }
            }
            [defaults synchronize];

            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Migration Finished"
                                                                           message:msg
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
        }
    });
}

@end
