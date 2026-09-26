
#import "uYouPlus.h"
#import "UYTLog.h"
#import <UIKit/UIKit.h>

#define YouModPrefix @"YouMod"

#define DownloadManager @"YouModDownloadManager"

#define OLEDTheme @"YouModEnablesOLEDTheme"
#define OLEDKeyboard @"YouModEnablesOLEDKeyboard"

#define YTLogoIndex @"YouModYTLogoIndex"
#define StickyNavBar @"YouModStickyNavBar"

#define HideRelatedVideos @"YouModHideRelatedVideos"
#define HideCommunityButtonPanel @"YouModHideCommunityButtonPanel"

#define HideAutoPlayToggle @"YouModHideAutoPlayToggle"
#define HideCaptionsButton @"YouModHideCaptionsButton"
#define HideNextAndPrevButtons @"YouModHideNextAndPrevButtons"
#define RemoveDarkOverlay @"YouModRemoveDarkOverlay"
#define RemoveAmbiant @"YouModRemoveAmbiantColors"
#define HideEndScreenCards @"YouModHideEndScreenCards"
#define HideSuggestedVideo @"YouModHideSuggestedVideoOnFinish"
#define HidePaidPromoOverlay @"YouModHidePaidPromoOverlay"
#define HideWaterMark @"YouModHideWaterMark"
#define DontSnapToChapter @"YouModDontSnapToChapter"
#define DisablesShowRemaining @"YouModDisablesShowRemainingTime"
#define AlwaysShowRemaining @"YouModAlwaysShowRemainingTime"
#define HideFullvidTitle @"YouModHideFullscreenVideoTitle"
#define PortFull @"YouModPortraitFullscreen"
#define ForceMiniPlayer @"YouModForceMiniPlayer"
#define DisablesFreeZoom @"YouModDisablesFreeZoom"
#define DisablesDoubleTap @"YouModDisablesDoubleTap"
#define HideFullAction @"YouModHideFullScreenAction"
#define TapToSeek @"YouModTapToSeek"
#define HideCommentsSection @"YouModHideCommentsSection"
#define HideCommentsPreview @"YouModHideCommentsPreview"
#define RemoveVideoShareButton @"YouModRemoveVideoShareButton"
#define RemoveVideoSaveButton @"YouModRemoveVideoSaveButton"
#define RemoveVideoDownloadButton @"YouModRemoveVideoDownloadButton"
#define RemoveVideoClipButton @"YouModRemoveVideoClipButton"
#define RemoveVideoRemixButton @"YouModRemoveVideoRemixButton"

#define HideShortsProducts @"YouModHideShortsProducts"
#define EnablesShortsQuality @"YouModEnablesShortsQuality"
#define ShowShortsSeekbar @"YouModShowShortsSeekbar"
#define RemoveShortsRemixButton @"YouModRemoveShortsRemixButton"
#define RemoveShortsPausedSubButton @"YouModRemoveShortsPausedSubButton"

#define DisableHints @"YouModDisableHints"
#define HideStartupAni @"YouModHideStartupAnimations"
#define DeviceUIIndex @"YouModDeviceUIIndex"
#define FixPlaybackIssues @"YouModFixPlaybackIssues"

#define RemovePlayInNextQueueOption @"YouModRemovePlayInNextQueueOption"
#define RemoveReportOption @"YouModRemoveReportOption"
#define RemoveYouTubeMusicOption @"YouModRemoveYouTubeMusicOption"

#define MuteButton @"YouModMuteButton"
#define LoopButton @"YouModLoopButton"
#define QualityButton @"YouModQualityButton"

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

static void UYMCopyIfPresent(NSUserDefaults *defaults, NSString *oldKey, NSString *newKey, NSInteger *count) {
    if ([defaults objectForKey:oldKey] != nil) {
        [defaults setObject:[defaults objectForKey:oldKey] forKey:newKey];
        (*count)++;
    }
}

static void UYMCopyInverted(NSUserDefaults *defaults, NSString *oldKey, NSString *newKey, NSInteger *count) {
    if ([defaults objectForKey:oldKey] != nil) {
        [defaults setBool:![defaults boolForKey:oldKey] forKey:newKey];
        (*count)++;
    }
}

- (void)migrateToYouModWithReset:(BOOL)shouldReset {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSInteger migrated = 0;

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
        kHidePreviousAndNextButton: HideNextAndPrevButtons,
        kHideHoverCards: HideEndScreenCards,
        kHideSuggestedVideo: HideSuggestedVideo,
        kDisableAmbientMode: RemoveAmbiant,
        kHideOverlayDarkBackground: RemoveDarkOverlay,
        kYTMiniPlayer: ForceMiniPlayer,
        kDisableHints: DisableHints,
        kHideShareButton: RemoveVideoShareButton,
        kHideDownloadButton: RemoveVideoDownloadButton,
        kHideClipButton: RemoveVideoClipButton,
        kHideRemixButton: RemoveVideoRemixButton,
        kHideSaveToPlaylistButton: RemoveVideoSaveButton,
        kHidePlayNextInQueue: RemovePlayInNextQueueOption,
        kHideBuySuperThanks: HideShortsProducts,
        kHideSubscriptions: RemoveShortsPausedSubButton,
        kHideShortsRemixButton: RemoveShortsRemixButton,
        kShortsQualityPicker: EnablesShortsQuality,
        kFixPlaybackIssues: FixPlaybackIssues,
        kStickNavigationBar: StickyNavBar,
        kHideRelatedWatchNexts: HideRelatedVideos,
        kHideCommunityPosts: HideCommunityButtonPanel,
        kYTTapToSeek: TapToSeek,
        kHideCommentSection: HideCommentsSection,
        kHidePreviewCommentSection: HideCommentsPreview,
        kHideReportButton: RemoveReportOption,
        kHideYTMusicButton: RemoveYouTubeMusicOption,
        kYTStartupAnimation: HideStartupAni,
        kReplaceYTDownloadWithuYou: DownloadManager,
        kShortsProgressBar: ShowShortsSeekbar,
        kHideFullscreenActions: HideFullAction,
    };

    for (NSString *oldKey in directMapping) {
        UYMCopyIfPresent(defaults, oldKey, directMapping[oldKey], &migrated);
    }

    NSDictionary *invertedMapping = @{
        kSnapToChapter: DontSnapToChapter,
        kPinchToZoom: DisablesFreeZoom,
        kDoubleTapToSeek: DisablesDoubleTap,
    };

    for (NSString *oldKey in invertedMapping) {
        UYMCopyInverted(defaults, oldKey, invertedMapping[oldKey], &migrated);
    }

    if ([defaults objectForKey:kAppTheme] != nil) {
        [defaults setBool:([defaults integerForKey:kAppTheme] == 2) forKey:OLEDTheme];
        migrated++;
    }

    BOOL hasLogoPref = [defaults objectForKey:kYTPremiumLogo] != nil || [defaults objectForKey:kHideYouTubeLogo] != nil;
    if (hasLogoPref) {
        NSInteger logoIndex = 0;
        if ([defaults boolForKey:kHideYouTubeLogo]) logoIndex = 2;
        else if ([defaults boolForKey:kYTPremiumLogo]) logoIndex = 1;
        [defaults setInteger:logoIndex forKey:YTLogoIndex];
        migrated++;
    }

    if ([defaults objectForKey:kiPhoneLayout] != nil) {
        [defaults setInteger:2 forKey:DeviceUIIndex];
        migrated++;
    }

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
                @"%ld compatible settings were copied to YouMod 2.1.0.\n\n"
                "Restart YouTube → test YouMod.",
                (long)migrated];
            msg = [msg stringByAppendingString:@"\n\nuYouEnhanced settings have been reset (except submodules)."];
            NSInteger cleared = 0;
            for (NSString *key in [defaults dictionaryRepresentation].allKeys) {
                if ([key hasSuffix:@"_enabled"] && ![key hasPrefix:@"YouMod"]) {
                    [defaults removeObjectForKey:key];
                    cleared++;
                }
            }
            [defaults synchronize];
            UYTDebugInfo(@"[YouModMigration] migrated=%ld reset=%ld", (long)migrated, (long)cleared);

            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Migration Finished"
                                                                           message:msg
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
        }
    });
}

@end
