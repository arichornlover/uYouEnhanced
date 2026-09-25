#import "uYouPlus.h"
#import "UYTLog.h"
#import "uYouPlusPatches.h"

#pragma mark - Localization Bundle

NSBundle *uYouPlusBundle() {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
 	dispatch_once(&onceToken, ^{
        NSString *tweakBundlePath = [[NSBundle mainBundle] pathForResource:@"uYouPlus" ofType:@"bundle"];
        if (tweakBundlePath)
            bundle = [NSBundle bundleWithPath:tweakBundlePath];
        else
            bundle = [NSBundle bundleWithPath:ROOT_PATH_NS(@"/Library/Application Support/uYouPlus.bundle")];
    });
    return bundle;
}
NSBundle *tweakBundle = uYouPlusBundle();

#pragma mark - Save To Playlist Reroute

@protocol UYTSlimTapDelegate <NSObject>
- (void)didTapButton:(id)button fromRect:(CGRect)rect inView:(id)view;
@end

static BOOL UYTIsSaveChipView(UIView *view) {
    if (!view) return NO;
    NSString *ident = view.accessibilityIdentifier ?: @"";
    return [ident isEqualToString:@"id.video.save_to.playlist.button"] ||
           [ident containsString:@"save_to_playlist"] ||
           [ident containsString:@"save.to.playlist"];
}

static UIView *UYTFindSaveChip(UIView *root, NSInteger depth) {
    if (!root || depth > 20) return nil;
    if (UYTIsSaveChipView(root)) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = UYTFindSaveChip(sub, depth + 1);
        if (found) return found;
    }
    return nil;
}

static NSArray<UIWindow *> *UYTCandidateWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        if (scene.activationState != UISceneActivationStateForegroundActive &&
            scene.activationState != UISceneActivationStateForegroundInactive) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) [windows addObject:w];
    }
    UIWindow *key = UIApplication.sharedApplication.keyWindow;
    if (key && ![windows containsObject:key]) [windows insertObject:key atIndex:0];
    return windows;
}

static BOOL UYTFireGestureTargets(UIView *view) {
    for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
        @try {
            NSArray *targets = [gesture valueForKey:@"_targets"];
            for (id targetEntry in targets) {
                id target = [targetEntry valueForKey:@"_target"];
                NSString *actionName = [targetEntry valueForKey:@"_action"];
                if (!target || !actionName.length) continue;
                SEL action = NSSelectorFromString(actionName);
                if (![target respondsToSelector:action]) continue;
                NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:
                    [(id)target methodSignatureForSelector:action]];
                [invocation setTarget:target];
                [invocation setSelector:action];
                if ([invocation.methodSignature numberOfArguments] > 2) {
                    __strong id arg = gesture;
                    [invocation setArgument:&arg atIndex:2];
                }
                [invocation invoke];
                UYTDebugInfo(@"[uYouPlus] Save reroute: fired gesture target %@", actionName);
                return YES;
            }
        } @catch (NSException *e) {}
    }
    return NO;
}

static BOOL UYTActivateRealSaveChip(void) {
    UIView *chip = nil;
    for (UIWindow *window in UYTCandidateWindows()) {
        chip = UYTFindSaveChip(window, 0);
        if (chip) break;
    }
    if (!chip) {
        UYTDebugWarn(@"[uYouPlus] Save reroute: real save chip not visible on screen");
        return NO;
    }

    if ([chip isKindOfClass:[UIControl class]]) {
        UIControl *control = (UIControl *)chip;
        [control sendActionsForControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
        UYTDebugInfo(@"[uYouPlus] Save reroute: sent control actions to %@", NSStringFromClass([chip class]));
        return YES;
    }
    if ([chip respondsToSelector:@selector(accessibilityActivate)]) {
        @try {
            BOOL ok = [(id)chip accessibilityActivate];
            if (ok) {
                UYTDebugInfo(@"[uYouPlus] Save reroute: activated via accessibilityActivate");
                return YES;
            }
        } @catch (NSException *e) {}
    }
    Class slimActionClass = %c(YTSlimVideoDetailsActionView);
    if (slimActionClass && [chip isKindOfClass:slimActionClass]) {
        id delegate = [chip respondsToSelector:@selector(delegate)] ? [chip performSelector:@selector(delegate)] : nil;
        SEL tap = @selector(didTapButton:fromRect:inView:);
        if (delegate && [delegate respondsToSelector:tap]) {
            [(id<UYTSlimTapDelegate>)delegate didTapButton:chip fromRect:chip.bounds inView:chip];
            UYTDebugInfo(@"[uYouPlus] Save reroute: invoked slim action delegate");
            return YES;
        }
    }
    if (UYTFireGestureTargets(chip)) return YES;

        UYTDebugWarn(@"[uYouPlus] Save reroute: chip found (%@) but no activation path matched", NSStringFromClass([chip class]));
    return NO;
}

@interface UYTSaveRerouteRouter : NSObject
+ (instancetype)sharedRouter;
- (void)rerouteTapped:(UIButton *)sender;
@end
@implementation UYTSaveRerouteRouter
+ (instancetype)sharedRouter {
    static UYTSaveRerouteRouter *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}
- (void)rerouteTapped:(UIButton *)sender {
    @try {
        if (!UYTActivateRealSaveChip()) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (!UYTActivateRealSaveChip()) {
                    UYTDebugInfo(@"[uYouPlus] Save reroute: real save chip unavailable");
                }
            });
        }
    } @catch (NSException *e) {
        UYTDebugErr(@"uYouPlus Save reroute exception: %@", e);
    }
}
@end

#pragma mark - uYou Button forward diagnostics (12.20.7+ / Shorts rebuild)

static NSString *UYTDNSLogFilePath(void) {
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [dirs.firstObject stringByAppendingPathComponent:@"uYouUnrecognizedSelector.log"];
}

static void UYTAppendSelectorLog(NSString *line) {
    NSString *path = UYTDNSLogFilePath();
    static NSDateFormatter *stamp;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        stamp = [NSDateFormatter new];
        stamp.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    });
    NSString *dated = [NSString stringWithFormat:@"[%@] %@", [stamp stringFromDate:[NSDate date]], line];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingToURL:[NSURL fileURLWithPath:path] error:nil];
    if (!fh) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        fh = [NSFileHandle fileHandleForWritingToURL:[NSURL fileURLWithPath:path] error:nil];
    }
    if (fh) {
        @try {
            [fh seekToEndOfFile];
            [fh writeData:[[dated stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        } @catch (NSException *e) {}
    }
}

%hook UIResponder
- (void)doesNotRecognizeSelector:(SEL)aSelector {
    NSString *selName = NSStringFromSelector(aSelector) ?: @"<nil-sel>";
    NSString *clsName = NSStringFromClass([self class]) ?: @"<nil-class>";
    NSString *line = [NSString stringWithFormat:
        @"[uYouButtonForward] UNRECOGNIZED SELECTOR target=%@ (%@) SEL=[%@] inst=%p",
        clsName, self, selName, self];
    UYTDebugInfo(@"%@", line);
    UYTAppendSelectorLog(line);
    %orig;
}
%end

%group gAlwaysOn

YTMainAppControlsOverlayView *controlsOverlayView;
%hook YTMainAppControlsOverlayView
- (id)initWithDelegate:(id)arg1 {
    controlsOverlayView = %orig;
    return controlsOverlayView;
}
%end
%hook YTElementsDefaultSheetController
+ (void)showSheetController:(id)arg1 showCommand:(id)arg2 commandContext:(id)arg3 handler:(id)arg4 {
    if (IS_ENABLED(kReplaceYTDownloadWithuYou) && [arg2 isKindOfClass:%c(ELMPBShowActionSheetCommand)]) {
        ELMPBShowActionSheetCommand *showCommand = (ELMPBShowActionSheetCommand *)arg2;
        NSArray *listOptions = [showCommand listOptionArray];
        BOOL overlayAvailable = controlsOverlayView && [controlsOverlayView respondsToSelector:@selector(uYou)];

        NSString *sheetId = showCommand.sheetId;
        BOOL isOfflineUpsell = (sheetId.length > 0 && [sheetId containsString:@"offline_upsell"]);
        if (isOfflineUpsell) {
            UYTDebugInfo(@"[uYouPlus] offline upsell detected via sheetId: %@", sheetId);
        }

        for (ELMPBElement *element in isOfflineUpsell ? @[] : listOptions) {
            ELMPBProperties *properties = [element properties];
            if (!properties) continue;

            NSMutableArray<NSString *> *idHints = [NSMutableArray array];

            if ([properties respondsToSelector:@selector(firstSubmessage)]) {
                id sub = [properties firstSubmessage];
                if ([sub respondsToSelector:@selector(identifier)] && [sub identifier]) {
                    [idHints addObject:[sub identifier]];
                }
            }
            if ([properties respondsToSelector:@selector(submessageAtIndex:)]) {
                id sub = [properties submessageAtIndex:0];
                if ([sub respondsToSelector:@selector(identifier)] && [sub identifier]) {
                    [idHints addObject:[sub identifier]];
                }
            }
            NSString *desc = [properties description] ?: @"";

            BOOL isOfflineUpsell = NO;
            for (NSString *hint in idHints) {
                if ([hint containsString:@"offline_upsell"]) {
                    isOfflineUpsell = YES;
                    break;
                }
            }
            if (!isOfflineUpsell && [desc containsString:@"offline_upsell_dialog"]) {
                isOfflineUpsell = YES;
            }

            if (isOfflineUpsell) {
                if (overlayAvailable) {
                    UYTDebugInfo(@"[uYouPlus] intercepted offline upsell sheet — launching uYou download");
                    [controlsOverlayView uYou];
                    return;
                }
                UYTDebugWarn(@"[uYouPlus] offline upsell detected but YTMainAppControlsOverlayView was never "
                          "captured (iPad layout?) — showing original sheet");
                break;
            }
        }

        if (!overlayAvailable) {
            UYTDebugInfo(@"[uYouEnhanced] action sheet with %lu option(s); overlay view not captured",
                      (unsigned long)listOptions.count);
        }
    }
    %orig;
}
%end

# pragma mark - Other hooks

%hook YTAppDelegate
- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions {
    BOOL didFinishLaunching = %orig;

    if (IS_ENABLED(kFlex)) {
        [[%c(FLEXManager) performSelector:@selector(sharedManager)] performSelector:@selector(showExplorer)];
    }

    if (IS_ENABLED(kDisableResumeToShorts)) {
    }

    return didFinishLaunching;
}
- (void)appWillResignActive:(id)arg1 {
    %orig;
         if (IS_ENABLED(kFlex)) {
        [[%c(FLEXManager) performSelector:@selector(sharedManager)] performSelector:@selector(showExplorer)];
    }
}
%end

%hook SKStoreReviewController
+ (void)requestReview { }
%end

%hook UIApplication
- (BOOL)supportsAlternateIcons {
    return YES;
}
- (NSString *)alternateIconName {
    NSString *savedIcon = [[NSUserDefaults standardUserDefaults] stringForKey:@"customAppIcon_name"];
    BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"appIconCustomization_enabled"];
    if (enabled && savedIcon.length > 0) {
        return savedIcon;
    }
    return %orig;
}
- (void)setAlternateIconName:(NSString *)alternateIconName completionHandler:(void (^)(NSError *_Nullable))completionHandler {
    if (alternateIconName.length > 0) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"appIconCustomization_enabled"];
        [[NSUserDefaults standardUserDefaults] setObject:alternateIconName forKey:@"customAppIcon_name"];
    } else {
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"appIconCustomization_enabled"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"customAppIcon_name"];
    }
    %orig;
}
%end

%end

%group gDisableResumeToShorts
%hook YTAppViewControllerImpl
- (void)setSelectedIndex:(NSUInteger)index {
    if (IS_ENABLED(kDisableResumeToShorts) && index == 1) {
        %orig(
            0
        );
        return;
    }
    %orig(
        index
    );
}
%end
%hook YTTabBarController
- (void)setSelectedIndex:(NSUInteger)index {
    if (IS_ENABLED(kDisableResumeToShorts) && index == 1) {
        %orig(
            0
        );
        return;
    }
    %orig(
        index
    );
}
%end
%end

#pragma mark - [3] Feature Groups

%group gHideYouTubeLogo

%hook YTHeaderLogoController

- (YTHeaderLogoController *)init {
    return nil;
}

%end

%hook YTNavigationBarTitleView

- (void)layoutSubviews {
    %orig;

    if (self.subviews.count > 1 &&
        [self.subviews[1].accessibilityIdentifier isEqualToString:@"id.yoodle.logo"]) {
        self.subviews[1].hidden = YES;
    }
}

%end
%end

%group gCenterYouTubeLogo

%hook YTNavigationBarTitleView

- (void)layoutSubviews {
    %orig;

    @try {
        UIView *superview = self.superview;

        if (!superview || superview.bounds.size.width <= 0) {
            return;
        }

        if (self.hidden || self.frame.size.width <= 0) {
            return;
        }

        CGRect frame = self.frame;
        CGFloat centeredX =
            (superview.bounds.size.width - frame.size.width) / 2.0;

        if (fabs(centeredX - frame.origin.x) > 0.5) {
            frame.origin.x = centeredX;
            self.frame = frame;
        }
    }
    @catch (NSException *exception) {
        UYTDebugInfo(@"[uYouEnhanced] CenterYouTubeLogo Exception: %@", exception);
    }
}

%end
%end

%group gMisc1

%hook YTWatchMiniBarViewController

- (void)updateMiniBarPlayerStateFromRenderer {
    if (!IS_ENABLED(kYTMiniPlayer)) {
        %orig;
    }
}

%end

%hook YTIPlayerBarPlayingState

- (BOOL)enableSnapToChapter {
    if (IS_ENABLED(kSnapToChapter)) {
        return NO;
    }

    return %orig;
}

%end

%hook YTSegmentableInlinePlayerBarView

- (void)didMoveToWindow {
    %orig;

    if (IS_ENABLED(kSnapToChapter)) {
        self.enableSnapToChapter = NO;
    }
}

%end

%hook YTCreatorEndscreenView

- (void)setHidden:(BOOL)hidden {
    if (IS_ENABLED(kHideHoverCards)) {
        hidden = YES;
    }

    %orig;
}

%end

%hook YTIMediaQualitySettingsHotConfig

%new(B@:)
- (BOOL)enableQuickMenuVideoQualitySettings {
    return NO;
}

%end

%end

%group gYTMiniPlayerEnabler

%hook YTIMiniplayerRenderer

%new
- (BOOL)hasMinimizedEndpoint {
    return NO;
}

%new
- (BOOL)hasPlaybackMode {
    return NO;
}

%end
%end

%group gMisc1b

%hook YTColdConfig

- (BOOL)respectDeviceCaptionSetting {
    return NO;
}

- (BOOL)isLandscapeEngagementPanelSwipeRightToDismissEnabled {
    return YES;
}

- (BOOL)enableModularPlayerBarController {
    return NO;
}

- (BOOL)mainAppCoreClientEnableCairoSettings {
    return IS_ENABLED(@"newSettingsUI_enabled");
}

%end
%end

%group gMisc1c

%hook YTColdConfig

- (BOOL)isPinchToEnterFullscreenEnabled {
    if (IS_ENABLED(kClassicVideoPlayer)) {
        return YES;
    }

    return %orig;
}

- (BOOL)deprecateTabletPinchFullscreenGestures {
    if (IS_ENABLED(kClassicVideoPlayer)) {
        return NO;
    }

    return %orig;
}

- (BOOL)disableCinematicForLowPowerMode {
    if (IS_ENABLED(kDisableAmbientMode)) {
        return NO;
    }

    return %orig;
}

- (BOOL)enableCinematicContainer {
    if (IS_ENABLED(kDisableAmbientMode)) {
        return NO;
    }

    return %orig;
}

- (BOOL)enableCinematicContainerOnClient {
    if (IS_ENABLED(kDisableAmbientMode)) {
        return NO;
    }

    return %orig;
}

- (BOOL)enableCinematicContainerOnTablet {
    if (IS_ENABLED(kDisableAmbientMode)) {
        return NO;
    }

    return %orig;
}

- (BOOL)iosCinematicContainerClientImprovement {
    if (IS_ENABLED(kDisableAmbientMode)) {
        return NO;
    }

    return %orig;
}

- (BOOL)mainAppCoreClientEnableClientCinematicPlaylists {
    if (IS_ENABLED(kDisableAmbientMode)) {
        return NO;
    }

    return %orig;
}

- (BOOL)mainAppCoreClientEnableClientCinematicPlaylistsPostMvp {
    if (IS_ENABLED(kDisableAmbientMode)) {
        return NO;
    }

    return %orig;
}

- (BOOL)mainAppCoreClientEnableClientCinematicTablets {
    if (IS_ENABLED(kDisableAmbientMode)) {
        return NO;
    }

    return %orig;
}

- (BOOL)videoZoomFreeZoomEnabledGlobalConfig {
    if (IS_ENABLED(kPinchToZoom)) {
        return NO;
    }

    return %orig;
}

- (BOOL)iosUseSystemVolumeControlInFullscreen {
    if (IS_ENABLED(kStockVolumeHUD)) {
        return YES;
    }

    return NO;
}

- (BOOL)speedMasterArm2FastForwardWithoutSeekBySliding {
    if (IS_ENABLED(kSlideToSeek)) {
        return NO;
    }

    return %orig;
}

- (BOOL)iosEnableFeaturedChannelWatermarkOverlayFix {
    if (IS_ENABLED(kHideChannelWatermark)) {
        return NO;
    }

    return %orig;
}

- (BOOL)removeNextPaddleForAllVideos {
    if (IS_ENABLED(kHidePreviousAndNextButton)) {
        return YES;
    }

    return %orig;
}

- (BOOL)removePreviousPaddleForAllVideos {
    if (IS_ENABLED(kHidePreviousAndNextButton)) {
        return YES;
    }

    return %orig;
}

- (BOOL)isLandscapeEngagementPanelEnabled {
    if (IS_ENABLED(kHideRightPanel)) {
        return NO;
    }

    return %orig;
}

- (BOOL)iosEnableVideoPlayerScrubber {
    if (IS_ENABLED(kShortsProgressBar)) {
        return YES;
    }

    return %orig;
}

- (BOOL)mobileShortsTablnlinedExpandWatchOnDismiss {
    if (IS_ENABLED(kShortsProgressBar)) {
        return YES;
    }

    return %orig;
}

- (BOOL)mainAppCoreClientIosEnableStartupAnimation {
    if (IS_ENABLED(kYTStartupAnimation)) {
        return YES;
    }

    return NO;
}

%end

%end

%group gMisc2

%hook YTCommerceEventGroupHandler
- (void)addEventHandlers {}
%end

%hook YTInterstitialPromoEventGroupHandler
- (void)addEventHandlers {}
%end

%hook YTPromosheetEventGroupHandler
- (void)addEventHandlers {}
%end

%hook YTPromoThrottleController
- (BOOL)canShowThrottledPromo { return NO; }
- (BOOL)canShowThrottledPromoWithFrequencyCap:(id)arg1 { return NO; }
- (BOOL)canShowThrottledPromoWithFrequencyCaps:(id)arg1 { return NO; }
%end

%hook YTPromoThrottleControllerImpl
- (BOOL)canShowThrottledPromo { return NO; }
- (BOOL)canShowThrottledPromoWithFrequencyCap:(id)arg1 { return NO; }
- (BOOL)canShowThrottledPromoWithFrequencyCaps:(id)arg1 { return NO; }
%end

%hook YTIShowFullscreenInterstitialCommand
- (BOOL)shouldThrottleInterstitial {
    if (self.hasModalClientThrottlingRules)
        self.modalClientThrottlingRules.oncePerTimeWindow = YES;
    return %orig;
}
%end

%hook YTSettingsSectionItemManager
- (void)updatePremiumEarlyAccessSectionWithEntry:(id)arg1 {}
%end

%hook YTSurveyController
- (void)showSurveyWithRenderer:(id)arg1 surveyParentResponder:(id)arg2 {}
%end

%end

%group gHidePremiumPromos
%hook YTAppCollectionViewController
- (void)loadWithModel:(YTISectionListRenderer *)model {
    NSMutableArray <YTISectionListSupportedRenderers *> *overallContentsArray = model.contentsArray;
    YTISectionListSupportedRenderers *supportedRenderers;
    for (supportedRenderers in overallContentsArray) {
        YTIItemSectionRenderer *itemSectionRenderer = supportedRenderers.itemSectionRenderer;
        NSMutableArray <YTIItemSectionSupportedRenderers *> *subContentsArray = itemSectionRenderer.contentsArray;
        bool found = NO;
        YTIItemSectionSupportedRenderers *itemSectionSupportedRenderers;
        for (itemSectionSupportedRenderers in subContentsArray) {
            if ([itemSectionSupportedRenderers hasCompactLinkRenderer]) {
                YTICompactLinkRenderer *compactLinkRenderer = [itemSectionSupportedRenderers compactLinkRenderer];
                if ([compactLinkRenderer hasIcon]) {
                    YTIIcon *icon = [compactLinkRenderer icon];
                    if ([icon hasIconType] && icon.iconType == 117) {
                        found = YES;
                        break;
                    }
                }
            }
        }
        if (found) {
            [subContentsArray removeObject:itemSectionSupportedRenderers];
            break;
        }
    }
    %orig;
}
%end
%end

%group gMisc3

%hook YTHeaderLogoController
- (void)setTopbarLogoRenderer:(YTITopbarLogoRenderer *)renderer {
    if (!IS_ENABLED(kYTPremiumLogo)) {
        %orig;
        return;
    }
    YTIIcon *icon = renderer.iconImage;
    if (icon) {
        @try {
            icon.iconType = YT_PREMIUM_LOGO;
        } @catch (NSException *e) {
            UYTDebugWarn(@"[uYouEnhanced] premium logo iconType %d rejected by YouTube: %@", (int)YT_PREMIUM_LOGO, e.reason);
        }
    }
    %orig(
        renderer
    );
}
- (void)setPremiumLogo:(BOOL)arg {
    if (IS_ENABLED(kYTPremiumLogo)) {
        %orig(
            YES
        );
    } else {
        %orig;
    }
}
- (BOOL)isPremiumLogo {
    if (IS_ENABLED(kYTPremiumLogo)) {
        return YES;
    }
    return %orig;
}
%end

%hook YTHeaderLogoControllerImpl
- (void)setTopbarLogoRenderer:(YTITopbarLogoRenderer *)renderer {
    if (!IS_ENABLED(kYTPremiumLogo)) {
        %orig;
        return;
    }
    YTIIcon *icon = renderer.iconImage;
    if (icon) {
        @try {
            icon.iconType = YT_PREMIUM_LOGO;
        } @catch (NSException *e) {
            UYTDebugWarn(@"[uYouEnhanced] premium logo iconType %d rejected by YouTube: %@", (int)YT_PREMIUM_LOGO, e.reason);
        }
    }
    %orig(
        renderer
    );
}
- (void)setPremiumLogo:(BOOL)arg {
    if (IS_ENABLED(kYTPremiumLogo)) {
        %orig(
            YES
        );
    } else {
        %orig;
    }
}
- (BOOL)isPremiumLogo {
    if (IS_ENABLED(kYTPremiumLogo)) {
        return YES;
    }
    return %orig;
}
%end

%hook YTHeaderLogoControllerImpl
- (void)configureYoodleNitrateController {
    if (IS_ENABLED(kDisableAnimatedYouTubeLogo)) {
        return;
    }
    %orig;
}
%end

%hook YTMainAppVideoPlayerOverlayViewController
- (void)setPaidContentWithPlayerData:(id)data {
    if (!IS_ENABLED(kHidePaidPromotionCard)) {
        %orig;
    }
}
- (void)playerOverlayProvider:(YTPlayerOverlayProvider *)provider didInsertPlayerOverlay:(YTPlayerOverlay *)overlay {
    if ([[overlay overlayIdentifier] isEqualToString:@"player_overlay_paid_content"] && IS_ENABLED(kHidePaidPromotionCard)) return;
    %orig;
}
%end

%hook YTInlineMutedPlaybackPlayerOverlayViewController
- (void)setPaidContentWithPlayerData:(id)data {
    if (!IS_ENABLED(kHidePaidPromotionCard)) {
        %orig;
    }
}
%end

%end

%group gClassicVideoPlayer
%hook YTHotConfig
- (BOOL)isTabletFullscreenSwipeGesturesEnabled { return NO; }
%end
%end

%group gDisableAmbientMode
%hook YTCinematicContainerView
- (BOOL)watchFullScreenCinematicSupported {
    return NO;
}
- (BOOL)watchFullScreenCinematicEnabled {
    return NO;
}
%end
%end

%group gHideHeatwaves
%hook YTInlinePlayerBarContainerView
- (BOOL)canShowHeatwave { return NO; }
%end
%hook YTPlayerBarController
- (void)setHeatmap:(id)arg1 {
    %orig(
        NULL
    );
}
%end
%end

%group gSection5

%hook YTMainAppVideoPlayerOverlayViewController
- (bool)shouldShowAutonavEndscreen {
    if (IS_ENABLED(@"noSuggestedVideo_enabled")) {
        return false;
    }
    return %orig;
}
%end

%end

%group gYTTapToSeek
    %hook YTInlinePlayerBarContainerView
    - (void)didPressScrubber:(id)arg1 {
        %orig;
        YTMainAppVideoPlayerOverlayViewController *mainAppController = [self.delegate valueForKey:@"_delegate"];
        YTPlayerViewController *playerViewController = [mainAppController valueForKey:@"parentViewController"];
        UIGestureRecognizer *gestureRecognizer = (UIGestureRecognizer *)arg1;
        CGPoint location = [gestureRecognizer locationInView:self];
        CGFloat x = location.x;
        double timestampFraction = [self scrubRangeForScrubX:x];
        double timestamp = [mainAppController totalTime] * timestampFraction;
        [playerViewController seekToTime:timestamp];
    }
    %end
%end

%hook YTFullscreenEngagementOverlayController
- (BOOL)isEnabled {
    return IS_ENABLED(@"repeatVideo") ? NO : %orig;
}
%end

# pragma mark - Hide Notification Button && SponsorBlock Button && uYouPlus Button
%hook YTRightNavigationButtons
- (void)layoutSubviews {
    %orig;
    if (IS_ENABLED(@"hideNotificationButton_enabled")) {
        self.notificationButton.hidden = YES;
    }
}
%end

%group hideFullscreenActions
%hook YTMainAppVideoPlayerOverlayViewController
- (BOOL)isFullscreenActionsEnabled {
    return NO;
}
%end
%hook YTFullscreenActionsView
- (BOOL)enabled {
    return NO;
}
- (void)layoutSubviews {
    if (self.superview) {
        [self removeFromSuperview];
    }
    self.hidden = YES;
    self.frame = CGRectZero;
    %orig;
}
%end
%end

# pragma mark - uYouPlus

%group gSection6

%hook YTPlayabilityResolutionUserActionUIController
- (void)showConfirmAlert { [self confirmAlertDidPressConfirm]; }
%end

%end

%group gPortraitFullscreen
%hook YTWatchViewController
- (unsigned long long)allowedFullScreenOrientations {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}
%end
%end

%group gFullscreenToTheRight
%hook YTWatchViewController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscapeRight;
}
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationLandscapeRight;
}
%end
%end

%group gSection7

%hook YTDoubleTapToSeekController
- (void)didTwoFingerDoubleTap:(id)arg1 {
    if (IS_ENABLED(kDisableChapterSkip)) {
        return;
    }
    %orig;
}
%end

%end

%group gStockVolumeHUD
%hook UIApplication
- (void)setSystemVolumeHUDEnabled:(BOOL)arg1 forAudioCategory:(id)arg2 {
        %orig(
            true,
            arg2
        );
}
%end
%end

%group gSection8

%hook YTDoubleTapToSeekController
- (void)enableDoubleTapToSeek:(BOOL)arg1 {
    if (IS_ENABLED(kDoubleTapToSeek)) {
        %orig(
            NO
        );
    } else {
        %orig;
    }
}
%end

%end

%group gDisablePullToFull
%hook YTWatchPullToFullController
- (BOOL)shouldRecognizeOverscrollEventsFromWatchOverscrollController:(id)arg1 {
    YTWatchViewController *watchViewController = (YTWatchViewController *)self.playerViewSource;
    NSUInteger allowedFullScreenOrientations = [watchViewController allowedFullScreenOrientations];
    if (allowedFullScreenOrientations == UIInterfaceOrientationMaskAllButUpsideDown
            || allowedFullScreenOrientations == UIInterfaceOrientationMaskPortrait
            || allowedFullScreenOrientations == UIInterfaceOrientationMaskPortraitUpsideDown) {
        return %orig;
    } else {
        return NO;
    }
}
%end
%end

@interface YTMainAppControlsOverlayView (uYouEnhanced)
- (void)uyt_attachSaveRerouteToSubviews:(UIView *)view depth:(NSInteger)depth;
@end

%group gSection9

%hook YTMainAppControlsOverlayView
%new - (void)uyt_attachSaveRerouteToSubviews:(UIView *)view depth:(NSInteger)depth {
    if (!view || depth > 8) return;
    for (UIView *sub in [view.subviews copy]) {
        if ([sub isKindOfClass:[UIControl class]]) {
            NSString *ident = sub.accessibilityIdentifier.lowercaseString ?: @"";
            NSString *lbl = sub.accessibilityLabel.lowercaseString ?: @"";
            BOOL isSaveButton = [ident containsString:@"save_to"] || [ident containsString:@"add_to"]
                             || [lbl containsString:@"save"] || [lbl containsString:@"add to"];
            if (isSaveButton) {
                id router = [UYTSaveRerouteRouter sharedRouter];
                SEL reroute = @selector(rerouteTapped:);
                NSArray *existing = [(UIControl *)sub actionsForTarget:router forControlEvent:UIControlEventTouchUpInside];
                if (![existing containsObject:NSStringFromSelector(reroute)]) {
                    [(UIControl *)sub addTarget:router action:reroute
                                 forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
        UYTDebugInfo(@"[uYouPlus] Save reroute attached via overlay scan (%@ / %@)", ident, lbl);
                }
            }
        }
        [self uyt_attachSaveRerouteToSubviews:sub depth:depth + 1];
    }
}
- (YTQTMButton *)buttonWithImage:(UIImage *)image accessibilityLabel:(NSString *)accessibilityLabel verticalContentPadding:(CGFloat)verticalContentPadding {
    YTQTMButton *button = %orig;
    if (IS_ENABLED(kEnableSaveToButton) && button) {
        NSString *ident = button.accessibilityIdentifier.lowercaseString ?: @"";
        NSString *lbl = accessibilityLabel.lowercaseString ?: @"";
        BOOL isSaveButton = [ident containsString:@"save_to"] || [ident containsString:@"add_to"]
                         || [lbl containsString:@"save"];
        if (isSaveButton) {
            id router = [UYTSaveRerouteRouter sharedRouter];
            SEL reroute = @selector(rerouteTapped:);
            NSArray *existing = [button actionsForTarget:router forControlEvent:UIControlEventTouchUpInside];
            if (![existing containsObject:NSStringFromSelector(reroute)]) {
                [button addTarget:router action:reroute
                           forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
                UYTDebugInfo(@"[uYouPlus] Save reroute attached to overlay button (%@)", accessibilityLabel);
            }
        }
    }
    return button;
}
- (void)setClosedCaptionsOrSubtitlesButtonAvailable:(BOOL)arg1 {
    if (IS_ENABLED(kHideCC)) {
        %orig(
            NO
        );
    } else {
        %orig;
    }
}
- (void)setAutoplaySwitchButtonRenderer:(id)arg1 {
    if (!IS_ENABLED(kHideAutoplaySwitch)) {
        %orig;
    }
}
- (void)setYoutubeMusicButton:(id)arg1 {
    if (IS_ENABLED(kHideYTMusicButton)) {
    } else {
        %orig(
            arg1
        );
    }
}
- (void)setShareButtonAvailable:(BOOL)arg1 {
    if (IS_ENABLED(kEnableShareButton)) {
        %orig(
            YES
        );
    } else {
        %orig(
            NO
        );
    }
}
- (void)setAddToButtonAvailable:(BOOL)arg1 {
    if (IS_ENABLED(kEnableSaveToButton)) {
        %orig(
            YES
        );
        [self uyt_attachSaveRerouteToSubviews:self depth:0];
    } else {
        %orig(
            NO
        );
    }
}
%end

%hook YTMainAppControlsOverlayView
- (void)layoutSubviews {
    %orig;
    if (IS_ENABLED(kDisableCollapseButton)) {
        if (self.watchCollapseButton) {
            [self.watchCollapseButton removeFromSuperview];
        }
    }
}
- (BOOL)watchCollapseButtonHidden {
    if (IS_ENABLED(kDisableCollapseButton)) {
        return YES;
    } else {
        return %orig;
    }
}
- (void)setWatchCollapseButtonAvailable:(BOOL)available {
    if (IS_ENABLED(kDisableCollapseButton)) {
    } else {
        %orig(
            available
        );
    }
}
%end

%end

%group gHideFullscreenButton
%hook YTInlinePlayerBarContainerView
- (BOOL)fullscreenButtonDisabled { return YES; }
- (BOOL)canShowFullscreenButton { return NO; }
- (BOOL)canShowFullscreenButtonExperimental { return NO; }
- (void)layoutSubviews {
    %orig;
    if (self.exitFullscreenButton && !self.exitFullscreenButton.hidden) {
        self.exitFullscreenButton.hidden = YES;
    }
    if (self.enterFullscreenButton && !self.enterFullscreenButton.hidden) {
        self.enterFullscreenButton.hidden = YES;
    }
}
%end
%end

%group gSection10

%hook YTPlayerBarController
- (void)setActiveSingleVideo:(id)arg1 {
    %orig;
    if (IS_ENABLED(@"alwaysShowRemainingTime_enabled")) {
        YTInlinePlayerBarContainerView *playerBar = self.playerBar;
        if (playerBar) {
            playerBar.shouldDisplayTimeRemaining = YES;
        }
    }
}
%end

%hook YTInlinePlayerBarContainerView
- (void)setShouldDisplayTimeRemaining:(BOOL)arg1 {
    if (IS_ENABLED(@"disableRemainingTime_enabled")) {
        if (IS_ENABLED(@"alwaysShowRemainingTime_enabled")) {
            %orig(
                YES
            );
        } else {
            %orig(
                NO
            );
        }
        return;
    }
    %orig;
}
%end

%end

%group gSection11

%hook YTMainAppControlsOverlayView
- (BOOL)titleViewHidden {
    return IS_ENABLED(@"hideVideoTitle_enabled") ? YES : %orig;
}
%end

%end

%group gHideOverlayDarkBackground
%hook YTMainAppVideoPlayerOverlayView
- (void)setBackgroundVisible:(BOOL)arg1 isGradientBackground:(BOOL)arg2 {
    %orig(
        NO,
        arg2
    );
}
%end
%end

%group gHideVideoPlayerShadowOverlayButtons
%hook YTMainAppControlsOverlayView
- (void)layoutSubviews {
	%orig();
    MSHookIvar<YTTransportControlsButtonView *>(self, "_previousButtonView").backgroundColor = nil;
    MSHookIvar<YTTransportControlsButtonView *>(self, "_nextButtonView").backgroundColor = nil;
    MSHookIvar<YTTransportControlsButtonView *>(self, "_seekBackwardAccessibilityButtonView").backgroundColor = nil;
    MSHookIvar<YTTransportControlsButtonView *>(self, "_seekForwardAccessibilityButtonView").backgroundColor = nil;
    MSHookIvar<YTPlaybackButton *>(self, "_playPauseButton").backgroundColor = nil;
}
%end
%end

%group gRedProgressBar

static BOOL YouSliderIsEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"YouSliderEnabled"];
}

%hook YTPlayerBarSegmentView
- (void)setBufferedProgressBarColor:(id)arg1 {
    %orig(
        [UIColor colorWithRed:1.00 green:1.00 blue:1.00 alpha:0.50]
    );
}
%end

%hook YTSegmentableInlinePlayerBarView
- (void)setBufferedProgressBarColor:(id)arg1 {
    %orig(
        [UIColor colorWithRed:1.00 green:1.00 blue:1.00 alpha:0.50]
    );
}
%end

%hook YTPlayerBarRectangleDecorationView
- (void)drawRectangleDecorationWithSideMasks:(CGRect)rect {
    if (IS_ENABLED(kRedProgressBar) && !YouSliderIsEnabled()) {
        YTIPlayerBarDecorationModel *model = [(id)self valueForKey:@"_model"];
        YTIPlayerBarPlayingStateOverlayMode overlayMode = model.playingState.overlayMode;
        model.playingState.overlayMode = PLAYER_BAR_OVERLAY_MODE_DEFAULT;
        if ([model respondsToSelector:@selector(style)] && [model style]) {
            model.style.gradientColor = nil;
        }
        %orig;
        model.playingState.overlayMode = overlayMode;
    } else
        %orig;
}
- (void)drawProgressRect:(CGRect)rect withColor:(UIColor *)color {
    if (IS_ENABLED(kRedProgressBar) && !YouSliderIsEnabled()) {
        YTIPlayerBarDecorationModel *model = [self valueForKey:@"_model"];
        BOOL isLive = model.playingState.mode == PLAYER_BAR_MODE_LIVE || model.playingState.mode == PLAYER_BAR_MODE_LIVE_VDR;
        UIColor *targetColor = isLive ? [UIColor colorWithRed:1.00 green:0.00 blue:0.00 alpha:1.00] : [UIColor redColor];
        %orig(rect, targetColor);
    } else {
        %orig(rect, color);
    }
}
%end

%hook YTPlayerBarProgressDecorationView
- (BOOL)shouldApplyGradientColor {
    return (IS_ENABLED(kRedProgressBar) && !YouSliderIsEnabled()) ? NO : %orig;
}
- (void)drawProgressRect:(CGRect)rect withColor:(UIColor *)color {
    if (IS_ENABLED(kRedProgressBar) && !YouSliderIsEnabled()) {
        YTIPlayerBarDecorationModel *model = [self valueForKey:@"_model"];
        BOOL isLive = model.playingState.mode == PLAYER_BAR_MODE_LIVE || model.playingState.mode == PLAYER_BAR_MODE_LIVE_VDR;
        UIColor *targetColor = isLive ? [UIColor colorWithRed:1.00 green:0.00 blue:0.00 alpha:1.00] : [UIColor redColor];
        %orig(rect, targetColor);
    } else {
        %orig(rect, color);
    }
}
%end

%hook YTInlinePlayerBarContainerView
- (id)quietProgressBarColor {
    return [UIColor redColor];
}
%end
%end

%group gShortsQualityPicker
%hook YTHotConfig
- (BOOL)enableOmitAdvancedMenuInShortsVideoQualityPicker { return YES; }
- (BOOL)enableShortsVideoQualityPicker { return YES; }
- (BOOL)iosEnableImmersiveLivePlayerVideoQuality { return YES; }
- (BOOL)iosEnableShortsPlayerVideoQuality { return YES; }
- (BOOL)iosEnableShortsPlayerVideoQualityRestartVideo { return YES; }
- (BOOL)iosEnableSimplerTitleInShortsVideoQualityPicker { return YES; }
%end
%end

%group gSection12

%hook YTShortsPlayerViewController
- (BOOL)shouldAlwaysEnablePlayerBar { return YES; }
- (BOOL)shouldEnablePlayerBarOnlyOnPause { return NO; }
%end

%hook YTReelPlayerViewController
- (BOOL)shouldAlwaysEnablePlayerBar { return YES; }
- (BOOL)shouldEnablePlayerBarOnlyOnPause { return NO; }
%end

%hook YTReelPlayerViewControllerSub
- (BOOL)shouldAlwaysEnablePlayerBar { return YES; }
- (BOOL)shouldEnablePlayerBarOnlyOnPause { return NO; }
%end

static NSMutableArray <YTIItemSectionRenderer *> *filteredShortsArray(NSArray <YTIItemSectionRenderer *> *array) {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"hideShortsCells"] || !array) {
        return [array mutableCopy];
    }
    NSMutableArray <YTIItemSectionRenderer *> *newArray = [array mutableCopy];
    NSIndexSet *removeIndexes = [newArray indexesOfObjectsPassingTest:^BOOL(YTIItemSectionRenderer *sectionRenderer, NSUInteger idx, BOOL *stop) {
        if ([sectionRenderer isKindOfClass:%c(YTIShelfRenderer)]) {
            YTIShelfSupportedRenderers *content = ((YTIShelfRenderer *)sectionRenderer).content;
            YTIHorizontalListRenderer *horizontalListRenderer = content.horizontalListRenderer;
            NSMutableArray <YTIHorizontalListSupportedRenderers *> *itemsArray = horizontalListRenderer.itemsArray;
            NSIndexSet *removeItemsArrayIndexes = [itemsArray indexesOfObjectsPassingTest:^BOOL(YTIHorizontalListSupportedRenderers *horizontalListSupportedRenderers, NSUInteger idx2, BOOL *stop2) {
                YTIElementRenderer *elementRenderer = horizontalListSupportedRenderers.elementRenderer;
                NSString *description = [elementRenderer description];
                BOOL hasShorts = [description containsString:@"shorts_video_cell"] || [description containsString:@"shorts_shelf"];
                if (hasShorts) *stop2 = YES;
                return hasShorts;
            }];
            return removeItemsArrayIndexes.count > 0;
        }
        if ([sectionRenderer isKindOfClass:%c(YTIItemSectionRenderer)]) {
            NSString *description = [sectionRenderer description];
            if ([description containsString:@"shorts_shelf.eml"] || [description containsString:@"shorts_shelf"])
                return YES;
            NSMutableArray <YTIItemSectionSupportedRenderers *> *contentsArray = sectionRenderer.contentsArray;
            for (YTIItemSectionSupportedRenderers *supported in contentsArray) {
                NSString *elDesc = [supported.elementRenderer description];
                if ([elDesc containsString:@"shorts_shelf"] || [elDesc containsString:@"shorts_video_cell"]) {
                    return YES;
                }
            }
        }
        return NO;
    }];
    [newArray removeObjectsAtIndexes:removeIndexes];
    return newArray;
}

%hook YTInnerTubeCollectionViewController
- (void)displaySectionsWithReloadingSectionControllerByRenderer:(id)renderer {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"hideShortsCells"]) {
        NSMutableArray *sectionRenderers = [self valueForKey:@"_sectionRenderers"];
        if (sectionRenderers && [sectionRenderers isKindOfClass:[NSArray class]]) {
            [self setValue:filteredShortsArray(sectionRenderers) forKey:@"_sectionRenderers"];
        }
    }
    %orig;
}

- (void)addSectionsFromArray:(NSArray <YTIItemSectionRenderer *> *)array {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"hideShortsCells"] && array) {
        %orig(
            filteredShortsArray(array)
        );
    } else {
        %orig;
    }
}
%end

%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    if ((IS_ENABLED(kHideBuySuperThanks)) && ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.suggested_action"])) {
        self.hidden = YES;
    }

    if (IS_ENABLED(kHideShortsClipButton) && ([self.accessibilityIdentifier isEqualToString:@"clip_button.eml"])) {
        self.hidden = YES;
    }
    if (IS_ENABLED(kHideShortsDownloadButton) && ([self.accessibilityIdentifier isEqualToString:@"id.ui.add_to.offline.button"])) {
        self.hidden = YES;
    }
    if (IS_ENABLED(kHideShortsRemixButton) && ([self.accessibilityIdentifier isEqualToString:@"id.video.remix.button"])) {
        self.hidden = YES;
    }
    if (IS_ENABLED(kHideShortsStatsButton) && ([self.accessibilityIdentifier isEqualToString:@"id.video.stats_for_nerds.button"])) {
        self.hidden = YES;
    }
    if (IS_ENABLED(kHideShortsClipButton) || IS_ENABLED(kHideShortsDownloadButton) || IS_ENABLED(kHideShortsRemixButton) || IS_ENABLED(kHideShortsStatsButton)) {
        NSString *desc = self.accessibilityLabel;
        if (desc) {
            if (IS_ENABLED(kHideShortsClipButton) && [desc isEqualToString:@"Clip"]) self.hidden = YES;
            if (IS_ENABLED(kHideShortsDownloadButton) && [desc isEqualToString:@"Download"]) self.hidden = YES;
            if (IS_ENABLED(kHideShortsRemixButton) && [desc isEqualToString:@"Remix"]) self.hidden = YES;
            if (IS_ENABLED(kHideShortsStatsButton) && [desc isEqualToString:@"Stats for nerds"]) self.hidden = YES;
        }
    }

    if ((IS_ENABLED(kHideChannelHeaderLinks)) && ([self.accessibilityIdentifier isEqualToString:@"eml.channel_header_links"])) {
        self.hidden = YES;
        self.opaque = YES;
        self.userInteractionEnabled = NO;
        [self sizeToFit];
        [self.superview layoutIfNeeded];
        [self setNeedsLayout];
        [self removeFromSuperview];
    }

    if ((IS_ENABLED(kHideCommentSection)) && ([self.accessibilityIdentifier isEqualToString:@"id.ui.comments_entry_point_teaser"]
    || [self.accessibilityIdentifier isEqualToString:@"id.ui.comments_entry_point_simplebox"]
    || [self.accessibilityIdentifier isEqualToString:@"id.ui.video_metadata_carousel"]
    || [self.accessibilityIdentifier isEqualToString:@"id.ui.carousel_header"])) {
        self.hidden = YES;
        self.opaque = YES;
        self.userInteractionEnabled = NO;
        CGRect bounds = self.frame;
        bounds.size.height = 0;
        self.frame = bounds;
        [self.superview layoutIfNeeded];
        [self setNeedsLayout];
        [self removeFromSuperview];
    }

    if ((IS_ENABLED(kHidePreviewCommentSection)) && ([self.accessibilityIdentifier isEqualToString:@"id.ui.comments_entry_point_teaser"])) {
        self.hidden = YES;
        self.opaque = YES;
        self.userInteractionEnabled = NO;
        CGRect bounds = self.frame;
        bounds.size.height = 0;
        self.frame = bounds;
        [self.superview layoutIfNeeded];
        [self setNeedsLayout];
        [self removeFromSuperview];
    }
}
%end

%hook YTReelWatchRootViewController
- (void)setPausedStateCarouselView {
    if (!IS_ENABLED(kHideSubscriptions)) {
        %orig;
    }
}
%end

%hook ELMContainerNode
- (void)layoutSubviews {
    %orig;

    NSString *desc = [self description];

    if ([desc containsString:@"eml.compact_subscribe_button"] && IS_ENABLED(kRedSubscribeButton)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self applyRedColorToSubscribeButton:self];
        });
    }
    if (IS_ENABLED(kHideButtonContainers)) {
        if ([desc containsString:@"id.video.like.button"] ||
            [desc containsString:@"id.video.dislike.button"] ||
            [desc containsString:@"id.video.share.button"] ||
            [desc containsString:@"id.video.remix.button"] ||
            [desc containsString:@"id.ui.add_to.offline.button"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self hideMatchingSubviews:self];
            });
        }
    }
}
- (void)applyRedColorToSubscribeButton:(id)view {
    if (!view) return;

    NSString *desc = [view description];
    if ([desc containsString:@"eml.compact_subscribe_button"]) {
        if ([view respondsToSelector:@selector(setBackgroundColor:)]) {
            [view setBackgroundColor:[UIColor redColor]];
        }
    }
    if ([view respondsToSelector:@selector(subviews)]) {
        for (id subview in [view subviews]) {
            [self applyRedColorToSubscribeButton:subview];
        }
    }
}
- (void)hideMatchingSubviews:(id)view {
    if (!view) return;

    if ([view respondsToSelector:@selector(subviews)]) {
        for (id subview in [view subviews]) {
            NSString *desc = [subview description];

            if ([desc containsString:@"id.video.like.button"] ||
                [desc containsString:@"id.video.dislike.button"] ||
                [desc containsString:@"id.video.share.button"] ||
                [desc containsString:@"id.video.remix.button"] ||
                [desc containsString:@"id.ui.add_to.offline.button"]) {
                if ([subview respondsToSelector:@selector(setHidden:)]) {
                    [subview setHidden:YES];
                }
            } else {
                [self hideMatchingSubviews:subview];
            }
        }
    }
}
%end

%end

%group gDisableAccountSection
%hook YTSettingsSectionItemManager
- (void)updateAccountSwitcherSectionWithEntry:(id)arg1 {}
%end
%end

%group gDisableAutoplaySection
%hook YTSettingsSectionItemManager
- (void)updateAutoplaySectionWithEntry:(id)arg1 {}
%end
%end

%group gDisableTryNewFeaturesSection
%hook YTSettingsSectionItemManager
- (void)updatePremiumEarlyAccessSectionWithEntry:(id)arg1 {}
%end
%end

%group gDisableVideoQualityPreferencesSection
%hook YTSettingsSectionItemManager
- (void)updateVideoQualitySectionWithEntry:(id)arg1 {}
%end
%end

%group gDisableNotificationsSection
%hook YTSettingsSectionItemManager
- (void)updateNotificationSectionWithEntry:(id)arg1 {}
%end
%end

%group gDisableManageAllHistorySection
%hook YTSettingsSectionItemManager
- (void)updateHistorySectionWithEntry:(id)arg1 {}
%end
%end

%group gDisableYourDataInYouTubeSection
%hook YTSettingsSectionItemManager
- (void)updateYourDataSectionWithEntry:(id)arg1 {}
%end
%end

%group gDisablePrivacySection
%hook YTSettingsSectionItemManager
- (void)updatePrivacySectionWithEntry:(id)arg1 {}
%end
%end

%group gDisableLiveChatSection
%hook YTSettingsSectionItemManager
- (void)updateLiveChatSectionWithEntry:(id)arg1 {}
%end
%end

%group gHideHomeTab
%hook YTPivotBarView
- (void)setRenderer:(YTIPivotBarRenderer *)renderer {
    UYTDebugInfo(@"bhackel: setting renderer");
    NSUInteger indexToRemove = -1;
    NSMutableArray <YTIPivotBarSupportedRenderers *> *itemsArray = renderer.itemsArray;
    UYTDebugInfo(@"bhackel: starting loop");
    for (NSUInteger i = 0; i < itemsArray.count; i++) {
        UYTDebugInfo(@"bhackel: iterating index %lu", (unsigned long)i);
        YTIPivotBarSupportedRenderers *item = itemsArray[i];
        UYTDebugInfo(@"bhackel: checking identifier");
        YTIPivotBarItemRenderer *pivotBarItemRenderer = item.pivotBarItemRenderer;
        NSString *pivotIdentifier = pivotBarItemRenderer.pivotIdentifier;
        if ([pivotIdentifier isEqualToString:@"FEwhat_to_watch"]) {
            UYTDebugInfo(@"bhackel: removing home tab button");
            indexToRemove = i;
            break;
        }
    }
    if (indexToRemove != -1) {
        [itemsArray removeObjectAtIndex:indexToRemove];
    }
    %orig;
}
%end
%end

%group gAutoHideHomeBar
%hook UIViewController
- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}
%end
%end

%group gDisableHints
%hook YTSettings
- (BOOL)areHintsDisabled {
	return YES;
}
- (void)setHintsDisabled:(BOOL)arg1 {
    %orig(
        YES
    );
}
%end
%hook YTUserDefaults
- (BOOL)areHintsDisabled {
	return YES;
}
- (void)setHintsDisabled:(BOOL)arg1 {
    %orig(
        YES
    );
}
%end
%end

%group gStickNavigationBar
%hook YTHeaderView
- (BOOL)stickyNavHeaderEnabled { return YES; }
%end
%end

%group gHideChipBar
%hook YTMySubsFilterHeaderView
- (void)setChipFilterView:(id)arg1 {}
%end

%hook YTHeaderContentComboView
- (void)enableSubheaderBarWithView:(id)arg1 {}
%end

%hook YTHeaderContentComboView
- (void)setFeedHeaderScrollMode:(int)arg1 {
    %orig(
        0
    );
}
%end

%end

%group gSection13

%hook YTMenuItemVisibilityHandler
- (BOOL)shouldShowServiceItemRenderer:(YTIMenuConditionalServiceItemRenderer *)renderer {
    if (IS_ENABLED(kHidePlayNextInQueue) && renderer.icon.iconType == YT_QUEUE_PLAY_NEXT) {
        return NO;
    }
    return %orig;
}
%end

%hook YTMenuItemVisibilityHandlerImpl
- (BOOL)shouldShowServiceItemRenderer:(YTIMenuConditionalServiceItemRenderer *)renderer {
    if (IS_ENABLED(kHidePlayNextInQueue) && renderer.icon.iconType == YT_QUEUE_PLAY_NEXT) {
        return NO;
    }
    return %orig;
}
%end

%end

%group gNoRelatedWatchNexts
%hook YTWatchNextResultsViewController
- (void)setVisibleSections:(NSInteger)arg1 {
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad && UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation)) {
        return;
    } else {
        arg1 = 1;
        %orig(
            arg1
        );
    }
}
%end
%end

%group gNoVideosInFullscreen
%hook YTFullScreenEngagementOverlayView
- (void)setRelatedVideosView:(id)view {
}
- (void)updateRelatedVideosViewSafeAreaInsets {
}
- (id)relatedVideosView {
    return nil;
}
%end

%hook YTFullScreenEngagementOverlayController
- (void)setRelatedVideosVisible:(BOOL)visible {
}
- (BOOL)relatedVideosPeekingEnabled {
    return NO;
}
%end
%end

%group giPhoneLayout
%hook UIDevice
- (UIUserInterfaceIdiom)userInterfaceIdiom {
    return UIUserInterfaceIdiomPhone;
}
%end
%hook UIStatusBarStyleAttributes
- (long long)idiom {
    return YES;
}
%end
%hook UIKBTree
- (long long)nativeIdiom {
    if ([UIApplication sharedApplication].statusBarOrientation == UIInterfaceOrientationPortrait) {
        return NO;
    } else {
        return YES;
    }
}
%end
%hook UIKBRenderer
- (long long)assetIdiom {
    if ([UIApplication sharedApplication].statusBarOrientation == UIInterfaceOrientationPortrait) {
        return NO;
    } else {
        return YES;
    }
}
%end
%end

%group gHideSubscriptionsNotificationBadge
%hook YTPivotBarIndicatorView
- (void)didMoveToWindow {
    [self setHidden:YES];
    %orig;
}
- (void)setFillColor:(id)arg1 {
    %orig(
        [UIColor clearColor]
    );
}
- (void)setBorderColor:(id)arg1 {
    %orig(
        [UIColor clearColor]
    );
}
%end
%hook YTCountView
- (void)layoutSubviews {
    %orig;
    self.hidden = YES;
}
%end
%end

%group gBlurrySettingsUI
%hook YTSettingsViewController
- (void)viewDidLoad {
    %orig;

    if (IS_ENABLED(kNewSettingsUI)) {
        @try {
            UIView *settingsView = [(UIViewController *)self view];

            UIView *frostedView = nil;
            @try {
                Class frostedGlassClass = %c(YTFrostedGlassView);
                if (frostedGlassClass) {
                    if ([frostedGlassClass instancesRespondToSelector:@selector(initWithBlurEffectStyle:)]) {
                        frostedView = [[frostedGlassClass alloc] initWithBlurEffectStyle:1];
                    } else if ([frostedGlassClass instancesRespondToSelector:@selector(initWithBlurEffectStyle:alpha:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                        frostedView = [frostedGlassClass performSelector:@selector(initWithBlurEffectStyle:alpha:) withObject:@1 withObject:@1.0];
#pragma clang diagnostic pop
                    }
                }
                if (frostedView) {
                    [frostedView setAutoresizingMask:
                        UIViewAutoresizingFlexibleWidth |
                        UIViewAutoresizingFlexibleHeight];
                }
            } @catch (NSException *e) {
                frostedView = nil;
            }

            if (!frostedView) {
                frostedView = (YTFrostedGlassView *)[[UIVisualEffectView alloc]
                    initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
                frostedView.autoresizingMask =
                    UIViewAutoresizingFlexibleWidth |
                    UIViewAutoresizingFlexibleHeight;
            }

            frostedView.frame = settingsView.bounds;
            [settingsView insertSubview:frostedView atIndex:0];
        } @catch (NSException *e) {
            UYTDebugWarn(@"uYouPlus frosted glass failed: %@", e);
        }
    }
}
%end
%end

#pragma mark - [4] Constructor
%ctor {

    %init;
    %init(gAlwaysOn);
    %init(gMisc1);
    %init(gMisc1b);
    %init(gMisc1c);
    %init(gMisc2);
    %init(gMisc3);
    %init(gSection5);
    %init(gSection6);
    %init(gSection7);
    %init(gSection8);
    %init(gSection9);
    %init(gSection10);
    %init(gSection11);
    %init(gSection12);
    %init(gSection13);

    if (IS_ENABLED(kYTMiniPlayer)) {
        %init(gYTMiniPlayerEnabler);
    }
    if (IS_ENABLED(kHideYouTubeLogo)) {
        %init(gHideYouTubeLogo);
    }
    if (IS_ENABLED(kCenterYouTubeLogo)) {
        %init(gCenterYouTubeLogo);
    }
    if (IS_ENABLED(kHideSubscriptionsNotificationBadge)) {
        %init(gHideSubscriptionsNotificationBadge);
    }
    if (IS_ENABLED(kHideOverlayDarkBackground)) {
        %init(gHideOverlayDarkBackground);
    }
    if (IS_ENABLED(kHideVideoPlayerShadowOverlayButtons)) {
        %init(gHideVideoPlayerShadowOverlayButtons);
    }
    if (IS_ENABLED(kDisableHints)) {
        %init(gDisableHints);
    }
    if (IS_ENABLED(kRedProgressBar)) {
        %init(gRedProgressBar);
    }
    if (IS_ENABLED(kStickNavigationBar)) {
        %init(gStickNavigationBar);
    }
    if (IS_ENABLED(kHideChipBar)) {
        %init(gHideChipBar);
    }
    if (IS_ENABLED(kNewSettingsUI)) {
        %init(gBlurrySettingsUI);
    }
    if (IS_ENABLED(kPortraitFullscreen)) {
        %init(gPortraitFullscreen);
    }
    if (IS_ENABLED(kFullscreenToTheRight)) {
        %init(gFullscreenToTheRight);
    }
    if (IS_ENABLED(kDisableFullscreenButton)) {
        %init(gHideFullscreenButton);
    }
    if (IS_ENABLED(kHideFullscreenActions)) {
        %init(hideFullscreenActions);
    }
    if (IS_ENABLED(kiPhoneLayout) && (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad)) {
        %init(giPhoneLayout);
    }
    if (IS_ENABLED(kStockVolumeHUD)) {
        %init(gStockVolumeHUD);
    }
    if (IS_ENABLED(kHideHeatwaves)) {
        %init(gHideHeatwaves);
    }
    if (IS_ENABLED(kHideRelatedWatchNexts)) {
        %init(gNoRelatedWatchNexts);
    }
    if (IS_ENABLED(kHideVideosInFullscreen)) {
        %init(gNoVideosInFullscreen);
    }
    if (IS_ENABLED(kClassicVideoPlayer)) {
        %init(gClassicVideoPlayer);
    }
    if (IS_ENABLED(kDisableAmbientMode)) {
        %init(gDisableAmbientMode);
    }
    if (IS_ENABLED(kDisableAccountSection)) {
        %init(gDisableAccountSection);
    }
    if (IS_ENABLED(kDisableAutoplaySection)) {
        %init(gDisableAutoplaySection);
    }
    if (IS_ENABLED(kDisableTryNewFeaturesSection)) {
        %init(gDisableTryNewFeaturesSection);
    }
    if (IS_ENABLED(kDisableVideoQualityPreferencesSection)) {
        %init(gDisableVideoQualityPreferencesSection);
    }
    if (IS_ENABLED(kDisableNotificationsSection)) {
        %init(gDisableNotificationsSection);
    }
    if (IS_ENABLED(kDisableManageAllHistorySection)) {
        %init(gDisableManageAllHistorySection);
    }
    if (IS_ENABLED(kDisableYourDataInYouTubeSection)) {
        %init(gDisableYourDataInYouTubeSection);
    }
    if (IS_ENABLED(kDisablePrivacySection)) {
        %init(gDisablePrivacySection);
    }
    if (IS_ENABLED(kDisableLiveChatSection)) {
        %init(gDisableLiveChatSection);
    }
    if (IS_ENABLED(kYTTapToSeek)) {
        %init(gYTTapToSeek);
    }
    if (IS_ENABLED(kHidePremiumPromos)) {
        %init(gHidePremiumPromos);
    }
    if (IS_ENABLED(kDisablePullToFull)) {
        %init(gDisablePullToFull);
    }
    if (IS_ENABLED(kHideHomeTab)) {
        %init(gHideHomeTab);
    }
    if (IS_ENABLED(kAutoHideHomeBar)) {
        %init(gAutoHideHomeBar);
    }
    if (IS_ENABLED(kShortsQualityPicker)) {
        %init(gShortsQualityPicker);
    }
    if (IS_ENABLED(kDisableResumeToShorts)) {
        %init(gDisableResumeToShorts);
    }

    NSArray *allKeys = [[[NSUserDefaults standardUserDefaults] dictionaryRepresentation] allKeys];
    if (![allKeys containsObject:kHidePlayNextInQueue]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kHidePlayNextInQueue];
    }
    if (![allKeys containsObject:@"relatedVideosAtTheEndOfYTVideos"]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"relatedVideosAtTheEndOfYTVideos"];
    }
    if (![allKeys containsObject:@"shortsProgressBar"]) {
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"shortsProgressBar"];
    }
    if (![allKeys containsObject:@"RYD-ENABLED"]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"RYD-ENABLED"];
    }
    if (![allKeys containsObject:@"YouPiPEnabled"]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"YouPiPEnabled"];
    }
    if (![allKeys containsObject:kReplaceYTDownloadWithuYou]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kReplaceYTDownloadWithuYou];
    }
    if (![allKeys containsObject:kAdBlockWorkaroundLite]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kAdBlockWorkaroundLite];
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kAdBlockWorkaround];
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"removeYouTubeAds"];
    }
    if (![allKeys containsObject:kAdBlockWorkaround]) {
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kAdBlockWorkaroundLite];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kAdBlockWorkaround];
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"removeYouTubeAds"];
    }
    if (![allKeys containsObject:@"noSuggestedVideoAtEnd"]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"noSuggestedVideoAtEnd"];
    }
    if (![allKeys containsObject:@"showPlaybackRate"]) {
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"showPlaybackRate"];
        } else {
            [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"showPlaybackRate"];
        }
    }
    if (![allKeys containsObject:@"newSettingsUI_enabled"]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kNewSettingsUI];
    }
}

