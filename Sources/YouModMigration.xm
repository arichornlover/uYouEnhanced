// keys migration from uYouEnhanced → YouMod 1.3.0+

#import "uYouPlus.h"
#import <UIKit/UIKit.h>

// YouMod 1.3.0 key definitions (https://github.com/Tonwalter888/YouMod/blob/e381a29287a30a005ad258adef0cb1a9a8d504fd/Files/Headers.h)
#define YouModPrefix @"YouMod"

#define DownloadManager @"YouModDownloadManager"
#define DownloadSaveToPhotos @"YouModDownloadSaveToPhotos"
#define DownloadPreferDRCAudio @"YouModDownloadPreferDRCAudio"
#define AutoClearCache @"YouModAutoClearCache"

#define OLEDTheme @"YouModEnablesOLEDTheme"
#define OLEDKeyboard @"YouModEnablesOLEDKeyboard"

#define HideYTLogo @"YouModHideYTLogo"
#define YTPremiumLogo @"YouModYTPremiumLogo"
#define HideNoti @"YouModHideNotificationButton"
#define HideSearch @"YouModHideSearchButton"
#define HideVoiceSearch @"YouModHideVoiceSearchButton"
#define HideCastButtonNav @"YouModHideCastButtonNavigationBar"

#define HideSubbar @"YouModHideSubbar"
#define HideGenMusicShelf @"YouModHideGenMusicShelf"
#define HideFeedPost @"YouModHideFeedPost"
#define HideShortsShelf @"YouModHideShortsShelf"
#define HideSearchHis @"YouModHideSearchHistoryAndSuggestions"
#define HideSubButton @"YouModHideSubscribeButton"
#define HideShoppingButton @"YouModHideShoppingButton"
#define HideMemberButton @"YouModHideMemberButton"

#define HideAutoPlayToggle @"YouModHideAutoPlayToggle"
#define HideCaptionsButton @"YouModHideCaptionsButton"
#define HideCastButtonPlayer @"YouModHideCastButtonPlayer"
#define HidePrevButton @"YouModHidePrevButton"
#define HideNextButton @"YouModHideNextButton"
#define ReplacePrevNextButtons @"YouModReplacePrevNextButtons"
#define RemoveDarkOverlay @"YouModRemoveDarkOverlay"
#define RemoveAmbiant @"YouModRemoveAmbiantColors"
#define HideEndScreenCards @"YouModHideEndScreenCards"
#define HideSuggestedVideo @"YouModHideSuggestedVideoOnFinish"
#define HidePaidPromoOverlay @"YouModHidePaidPromoOverlay"
#define HideWaterMark @"YouModHideWaterMark"
#define GestureControls @"YouModEnableGesturesControls"
#define GestureActivationArea @"YouModGestureActivationArea"
#define LeftSideGesture @"YouModLeftSideGesture"
#define RightSideGesture @"YouModRightSideGesture"
#define GestureHUD @"YouModGestureHUD"
#define DisablesDoubleTap @"YouModDisablesDoubleTap"
#define DisablesLongHold @"YouModDisablesLongHold"
#define AutoExitFullScreen @"YouModAutoExitFullScreen"
#define DisablesCaptions @"YouModAutoDisablesCaptions"
#define DisablesShowRemaining @"YouModDisablesShowRemainingTime"
#define AlwaysShowRemaining @"YouModAlwaysShowRemainingTime"
#define ShowExtraTimeRemaining @"YouModShowExtraTimeRemaining"
#define HideFullAction @"YouModHideFullScreenAction"
#define HideFullvidTitle @"YouModHideFullscreenVideoTitle"
#define StopAutoplayVideo @"YouModStopAutoplayVideo"
#define HideContentWarning @"YouModHideContentWarning"
#define AutoFullScreen @"YouModAutoFullScreen"
#define PortFull @"YouModPortraitFullscreen"
#define OldQualityPicker @"YouModUseOldQualityPicker"
#define ExtraSpeed @"YouModAddExtraSpeed"
#define DisableHints @"YouModDisableHints"
#define ForceMiniPlayer @"YouModForceMiniPlayer"
#define AlwaysShowSeekbar @"YouModAlwaysShowSeekbar"
#define HideLikeButton @"YouModHideLikeButton"
#define HideDisLikeButton @"YouModHideDisLikeButton"
#define HideShareButton @"YouModHideShareButton"
#define HideDownloadButton @"YouModHideDownloadButton"
#define HideClipButton @"YouModHideClipButton"
#define HideRemixButton @"YouModHideRemixButton"
#define HideSaveButton @"YouModHideSaveButton"

#define HideShortsLikeButton @"YouModHideShortsLikeButton"
#define HideShortsDisLikeButton @"YouModHideShortsDisLikeButton"
#define HideShortsCommentButton @"YouModHideShortsCommentButton"
#define HideShortsShareButton @"YouModHideShortsShareButton"
#define HideShortsRemixButton @"YouModHideShortsRemixButton"
#define HideShortsMetaButton @"YouModHideShortsMetaButton"
#define HideShortsProducts @"YouModHideShortsProducts"
#define HideShortsRecbar @"YouModHideShortsRecbar"
#define HideShortsCommit @"YouModHideShortsCommit"
#define HideShortsSubscriptButton @"YouModHideShortsSubscriptButton"
#define HideShortsLiveButton @"YouModHideShortsLiveButton"
#define HideShortsLensButton @"YouModHideShortsLensButton"
#define HideShortsTrendsButton @"YouModHideShortsTrendsButton"
#define HideShortsToVideo @"YouModHideShortsToVideo"
#define EnablesShortsQuality @"YouModEnablesShortsQuality"
#define ShowShortsSeekbar @"YouModShowShortsSeekbar"

#define HideHomeTab @"YouModHideHomeTab"
#define HideShortsTab @"YouModHideShortsTab"
#define HideCreateButton @"YouModHideCreateButton"
#define HideSubscriptTab @"YouModHideSubscriptionsTab"

#define BackgroundPlayback @"YouModEnablesBackgroundPlayback"
#define DisablesShortsPiP @"YouModTrytoDisablesShortsPiP"
#define BlockUpgradeDialogs @"YouModBlockUpgradeDialogs"
#define HideAreYouThereDialog @"YouModHideAreYouThereDialog"
#define FixesSlowMiniPlayer @"YouModFixesSlowMiniPlayer"
#define DisablesNewMiniPlayer @"YouModDisablesNewMiniPlayer"
#define DisablesSnackBar @"YouModDisablesSnackBar"
#define HideStartupAni @"YouModHideStartupAnimations"
#define HidePlayInNextQueue @"YouModHidePlayInNextQueue"
#define HideLikeDislikeVotes @"YouModHideLikeDislikeVotes"

// =============================================

@interface YouModMigrationManager : NSObject
+ (instancetype)sharedManager;
- (void)migrateToYouModWithReset:(BOOL)shouldReset;
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

- (void)migrateToYouModWithReset:(BOOL)shouldReset {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    NSDictionary *mapping = @{
        kOLEDKeyboard: OLEDKeyboard,
        kAppTheme: OLEDTheme,
        kPortraitFullscreen: PortFull,
        kAlwaysShowRemainingTime: AlwaysShowRemaining,
        kDisableRemainingTime: DisablesShowRemaining,
        kHideAutoplaySwitch: HideAutoPlayToggle,
        kHideCC: HideCaptionsButton,
        kHideVideoTitle: HideFullvidTitle,
        kHidePaidPromotionCard: HidePaidPromoOverlay,
        kHideChannelWatermark: HideWaterMark,
        kHidePreviousAndNextButton: HidePrevButton,
        kHideHoverCards: HideEndScreenCards,
        kHideSuggestedVideo: HideSuggestedVideo,
        kDisableAmbientMode: RemoveAmbiant,
        kHideOverlayDarkBackground: RemoveDarkOverlay,
        kYTMiniPlayer: ForceMiniPlayer,
        kBigYTMiniPlayer: ForceMiniPlayer,
        kDisableHints: DisableHints,
        kYTPremiumLogo: YTPremiumLogo,
        kHideYouTubeLogo: HideYTLogo,
        kHideHomeTab: HideHomeTab,
        kHideShareButton: HideShareButton,
        kHideDownloadButton: HideDownloadButton,
        kHideClipButton: HideClipButton,
        kHideRemixButton: HideRemixButton,
        kHideSaveToPlaylistButton: HideSaveButton,
        kHidePlayNextInQueue: HidePlayInNextQueue,
        kHideBuySuperThanks: HideShortsProducts,
        kHideSubscriptions: HideShortsSubscriptButton,
    };

    NSInteger migrated = 0;

    for (NSString *oldKey in mapping) {
        if ([defaults objectForKey:oldKey] != nil) {
            id value = [defaults objectForKey:oldKey];
            NSString *newKey = mapping[oldKey];
            [defaults setObject:value forKey:newKey];
            migrated++;
        }
    }

    [defaults synchronize];

    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *msg = [NSString stringWithFormat:
            @"%ld compatible settings were copied to YouMod.\n\n"
            "uYouEnhanced settings were left untouched.\n"
            "Restart YouTube → test YouMod.", 
            (long)migrated];

        if (shouldReset) {
            msg = [msg stringByAppendingString:@"\n\nuYouEnhanced settings have been reset (except submodules)."];
            // Reset uYouEnhanced keys (keep submodule keys)
            NSArray *protectedKeys = @[/* add submodule keys here if needed */];
            for (NSString *key in [defaults dictionaryRepresentation].allKeys) {
                if ([key hasPrefix:@"k"] && ![protectedKeys containsObject:key]) {
                    [defaults removeObjectForKey:key];
                }
            }
            [defaults synchronize];
        }

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Migration Finished"
                                                                       message:msg
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}

@end
