#import "uYouPlus.h"
#import "uYouPlusPatches.h"

// Tweak's bundle for Localizations support - @PoomSmart - https://github.com/PoomSmart/YouPiP/commit/aea2473f64c75d73cab713e1e2d5d0a77675024f
NSBundle *uYouPlusBundle() {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
 	dispatch_once(&onceToken, ^{
        NSString *tweakBundlePath = [[NSBundle mainBundle] pathForResource:@"uYouPlus" ofType:@"bundle"];
        if (tweakBundlePath)
            bundle = [NSBundle bundleWithPath:tweakBundlePath];
        else
            bundle = [NSBundle bundleWithPath:ROOT_PATH_NS(@"/Library/Application Support/uYouPlus.bundle")]; // ROOT_PATH_NS = JBROOT_PATH_NSSTRING
    });
    return bundle;
}
NSBundle *tweakBundle = uYouPlusBundle();
//


%group gAlwaysOn

// Hide Player Buttons - moved to Sources/HidePlayerButtons.xm

// Replace YouTube's download with uYou's - 19.30.2+
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

        for (ELMPBElement *element in listOptions) {
            ELMPBProperties *properties = [element properties];
            if (!properties) continue;

            NSString *identifier = nil;

            if ([properties respondsToSelector:@selector(firstSubmessage)]) {
                id sub = [properties firstSubmessage];
                if ([sub respondsToSelector:@selector(identifier)]) {
                    identifier = [sub identifier];
                }
            } else if ([properties respondsToSelector:@selector(submessageAtIndex:)]) {
                id sub = [properties submessageAtIndex:0];
                if ([sub respondsToSelector:@selector(identifier)]) {
                    identifier = [sub identifier];
                }
            } else if ([properties respondsToSelector:@selector(description)]) {
                NSString *desc = [properties description];
                if ([desc containsString:@"offline_upsell_dialog"]) {
                    identifier = @"offline_upsell_dialog";
                }
            }

            if (identifier && [identifier containsString:@"offline_upsell_dialog"]) {
                if (controlsOverlayView && [controlsOverlayView respondsToSelector:@selector(uYou)]) {
                    [controlsOverlayView uYou];
                }
                return;
            }
        }
    }
    %orig;
}
%end

# pragma mark - Other hooks

// Activate FLEX
%hook YTAppDelegate
- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions {
    BOOL didFinishLaunching = %orig;

    if (IS_ENABLED(kFlex)) {
        [[%c(FLEXManager) performSelector:@selector(sharedManager)] performSelector:@selector(showExplorer)];
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

// YTPlayerOverlayManager + NSFileManager fix - moved to Sources/uYouPlusPatches.xm

// Remove App Rating Prompt in YouTube (for Sideloaded - iOS 14+) - @arichornlover
%hook SKStoreReviewController
+ (void)requestReview { }
%end

// Enable Alternate Icons - @arichornlover
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

%end // gAlwaysOn

// Ad Blocking - moved to Sources/AdBlocking.xm

// Hide YouTube Logo - @dayanch96
%group gHideYouTubeLogo
%hook YTHeaderLogoController
- (YTHeaderLogoController *)init {
    return nil;
}
%end
%hook YTNavigationBarTitleView
- (void)layoutSubviews {
    %orig;
    if (self.subviews.count > 1 && [self.subviews[1].accessibilityIdentifier isEqualToString:@"id.yoodle.logo"]) {
        self.subviews[1].hidden = YES;
    }
}
%end
%end

// Center YouTube Logo - @arichornlover
%group gCenterYouTubeLogo
%hook YTNavigationBarTitleView
- (void)alignCustomViewToCenterOfWindow {
    UIView *superview = self.superview;
    if (!superview) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            CGRect frame = self.frame;
            CGFloat newX = (superview.bounds.size.width - frame.size.width) / 2;
            frame.origin.x = newX;
            self.frame = frame;
            [self setNeedsLayout];
            [self layoutIfNeeded];
        } @catch (NSException *ex) {
            NSLog(@"[alignCustomViewToCenterOfWindow] Exception: %@", ex);
        }
    });
}
%end
%end

%group gMisc1

// YTMiniPlayerEnabler: https://github.com/level3tjg/YTMiniplayerEnabler/
%hook YTWatchMiniBarViewController
- (void)updateMiniBarPlayerStateFromRenderer {
    if (!IS_ENABLED(kYTMiniPlayer)) {
        %orig;
    }
}
%end

// YTNoHoverCards: https://github.com/level3tjg/YTNoHoverCards
%hook YTCreatorEndscreenView
- (void)setHidden:(BOOL)hidden {
    if (IS_ENABLED(kHideHoverCards))
        hidden = YES;
    %orig;
}
%end

// YTClassicVideoQuality: https://github.com/PoomSmart/YTClassicVideoQuality
%hook YTIMediaQualitySettingsHotConfig

%new(B@:) - (BOOL)enableQuickMenuVideoQualitySettings { return NO; }

%end

// %hook YTVideoQualitySwitchControllerFactory
// - (id)videoQualitySwitchControllerWithParentResponder:(id)responder {
//     Class originalClass = %c(YTVideoQualitySwitchOriginalController);
//     return originalClass ? [[originalClass alloc] initWithParentResponder:responder] : %orig;
// }
// %end

// A/B flags
%hook YTColdConfig 
- (BOOL)respectDeviceCaptionSetting { return NO; } // YouRememberCaption: https://poomsmart.github.io/repo/depictions/youremembercaption.html - deprecated flag ⚠️
- (BOOL)isLandscapeEngagementPanelSwipeRightToDismissEnabled { return YES; } // Swipe right to dismiss the right panel in fullscreen mode - deprecated flag ⚠️
- (BOOL)enableModularPlayerBarController { return NO; } // fixes some of the iSponorBlock problems
- (BOOL)mainAppCoreClientEnableCairoSettings { return IS_ENABLED(@"newSettingsUI_enabled"); } // New grouped settings UI
- (BOOL)enableIosFloatingMiniplayer { return IS_ENABLED(@"floatingMiniplayer_enabled"); } // Floating Miniplayer
- (BOOL)enableIosFloatingMiniplayerSwipeUpToExpand { return IS_ENABLED(@"floatingMiniplayer_enabled"); } // Floating Miniplayer - deprecated flag ⚠️
- (BOOL)enableIosFloatingMiniplayerRepositioning { return IS_ENABLED(@"floatingMiniplayer2_enabled"); } // Floating Miniplayer (Repositioning Support, Removes Swiping Up Gesture) - deprecated fla[...]
%end

%end // gMisc1

// Fix Casting: https://github.com/arichornlover/uYouEnhanced/issues/606#issuecomment-2098289942
%group gFixCasting
%hook YTColdConfig
- (BOOL)cxClientEnableIosLocalNetworkPermissionReliabilityFixes { return YES; }
- (BOOL)cxClientEnableIosLocalNetworkPermissionUsingSockets { return NO; }
- (BOOL)cxClientEnableIosLocalNetworkPermissionWifiFixes { return YES; }
%end
%hook YTHotConfig
- (BOOL)isPromptForLocalNetworkPermissionsEnabled { return YES; } // deprecated flag ⚠️
%end
%end

%group gMisc2

// NOYTPremium - https://github.com/PoomSmart/NoYTPremium/
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

// Restore Settings Button in Navigaton Bar - @arichornlover & @bhackel - https://github.com/arichornlover/uYouEnhanced/issues/178
// WILL RESULT IN LOSING THE SETTINGS BUTTON!
// %hook YTRightNavigationButtons
// - (id)visibleButtons {
//     Class YTVersionUtilsClass = %c(YTVersionUtils);
//     NSString *appVersion = [YTVersionUtilsClass performSelector:@selector(appVersion)];
//     NSComparisonResult result = [appVersion compare:@"18.35.4" options:NSNumericSearch];
//     if (result == NSOrderedAscending) {
//         return %orig;
//     }
//     return [self dynamicButtons];
// }
// %end

%end // gMisc2

// Hide "Get Youtube Premium" in "You" tab - @bhackel
%group gHidePremiumPromos
%hook YTAppCollectionViewController
- (void)loadWithModel:(YTISectionListRenderer *)model {
    NSMutableArray <YTISectionListSupportedRenderers *> *overallContentsArray = model.contentsArray;
    // Check each item in the overall array - this represents the whole You page
    YTISectionListSupportedRenderers *supportedRenderers;
    for (supportedRenderers in overallContentsArray) {
        YTIItemSectionRenderer *itemSectionRenderer = supportedRenderers.itemSectionRenderer;
        // Check each subobject - this would be visible as a cell in the You page
        NSMutableArray <YTIItemSectionSupportedRenderers *> *subContentsArray = itemSectionRenderer.contentsArray;
        bool found = NO;
        YTIItemSectionSupportedRenderers *itemSectionSupportedRenderers;
        for (itemSectionSupportedRenderers in subContentsArray) {
            // Check for a link cell
            if ([itemSectionSupportedRenderers hasCompactLinkRenderer]) {
                YTICompactLinkRenderer *compactLinkRenderer = [itemSectionSupportedRenderers compactLinkRenderer];
                // Check for an icon in this cell
                if ([compactLinkRenderer hasIcon]) {
                    YTIIcon *icon = [compactLinkRenderer icon];
                    // Check if the icon is for the premium promo
                    if ([icon hasIconType] && icon.iconType == 117) {
                        found = YES;
                        break;
                    }
                }
            }
        }
        // Remove object from array - perform outside of loop to avoid error
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

// YouTube Premium logo - @bhackel & @Tonwalter888
%hook YTHeaderLogoController
- (void)setTopbarLogoRenderer:(YTITopbarLogoRenderer *)renderer {
    if (!IS_ENABLED(kYTPremiumLogo)) {
        %orig;
        return;
    }
    // Modify the type of the icon before setting the renderer
    YTIIcon *icon = renderer.iconImage;
    if (icon) {
        icon.iconType = YT_PREMIUM_LOGO;
    }
    %orig(renderer);
}
// For when spoofing before 18.34.5
- (void)setPremiumLogo:(BOOL)arg {
    if (IS_ENABLED(kYTPremiumLogo)) {
        %orig(YES);
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
    // Modify the type of the icon before setting the renderer
    YTIIcon *icon = renderer.iconImage;
    if (icon) {
        icon.iconType = YT_PREMIUM_LOGO;
    }
    %orig(renderer);
}
// For when spoofing before 18.34.5
- (void)setPremiumLogo:(BOOL)arg {
    if (IS_ENABLED(kYTPremiumLogo)) {
        %orig(YES);
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

// Disable animated YouTube Logo - @bhackel
%hook YTHeaderLogoControllerImpl // originally was "YTHeaderLogoController"
- (void)configureYoodleNitrateController {
    if (IS_ENABLED(kDisableAnimatedYouTubeLogo)) {
        return;
    }
    %orig;
}
%end

// YTNoPaidPromo: https://github.com/PoomSmart/YTNoPaidPromo
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

%end // gMisc3

// Classic Video Player (Restores the v16.xx.x Video Player Functionality) - @arichornlover
// To-do: disabling "Precise Video Scrubbing" https://9to5google.com/2022/06/29/youtube-precise-video-scrubbing/
%group gClassicVideoPlayer
%hook YTColdConfig
- (BOOL)isPinchToEnterFullscreenEnabled { return YES; } // Restore Pinch-to-fullscreen
- (BOOL)deprecateTabletPinchFullscreenGestures { return NO; } // Restore Pinch-to-fullscreen
%end
%hook YTHotConfig
- (BOOL)isTabletFullscreenSwipeGesturesEnabled { return NO; } // Disable Swipe-to-fullscreen (iPad)
%end
%end

// Disable Ambient Mode in Fullscreen - v21.10.2+ - @arichornlover
%group gDisableAmbientMode
%hook YTCinematicContainerView
- (BOOL)watchFullScreenCinematicSupported {
    return NO;
}
- (BOOL)watchFullScreenCinematicEnabled {
    return NO;
}
%end
%hook YTColdConfig
- (BOOL)disableCinematicForLowPowerMode { return NO; }
- (BOOL)enableCinematicContainer { return NO; }
- (BOOL)enableCinematicContainerOnClient { return NO; }
- (BOOL)enableCinematicContainerOnTablet { return NO; }
- (BOOL)iosCinematicContainerClientImprovement { return NO; }
- (BOOL)mainAppCoreClientEnableClientCinematicPlaylists { return NO; }
- (BOOL)mainAppCoreClientEnableClientCinematicPlaylistsPostMvp { return NO; }
- (BOOL)mainAppCoreClientEnableClientCinematicTablets { return NO; }
%end
%end

// Hide YouTube Heatwaves in Video Player - v20.02.3+ - @arichornlover
%group gHideHeatwaves
%hook YTInlinePlayerBarContainerView
- (BOOL)canShowHeatwave { return NO; }
%end
%hook YTPlayerBarController
- (void)setHeatmap:(id)arg1 {
    %orig(NULL);
}
%end
%end

%group gSection5

// YTNoSuggestedVideo - https://github.com/bhackel/YTNoSuggestedVideo
%hook YTMainAppVideoPlayerOverlayViewController
- (bool)shouldShowAutonavEndscreen {
    if (IS_ENABLED(@"noSuggestedVideo_enabled")) {
        return false;
    }
    return %orig;
}
%end

%end // gSection5

// YTTapToSeek - https://github.com/bhackel/YTTapToSeek
%group gYTTapToSeek
    %hook YTInlinePlayerBarContainerView
    - (void)didPressScrubber:(id)arg1 {
        %orig;
        // Get access to the seekToTime method
        YTMainAppVideoPlayerOverlayViewController *mainAppController = [self.delegate valueForKey:@"_delegate"];
        YTPlayerViewController *playerViewController = [mainAppController valueForKey:@"parentViewController"];
        // Get the X position of this tap from arg1
        UIGestureRecognizer *gestureRecognizer = (UIGestureRecognizer *)arg1;
        CGPoint location = [gestureRecognizer locationInView:self];
        CGFloat x = location.x;
        // Get the associated proportion of time using scrubRangeForScrubX
        double timestampFraction = [self scrubRangeForScrubX:x];
        // Get the timestamp from the fraction
        double timestamp = [mainAppController totalTime] * timestampFraction;
        // Jump to the timestamp
        [playerViewController seekToTime:timestamp];
    }
    %end
%end

// Fix uYou Repeat - @bhackel
// When uYou repeat is enabled, and Suggested Video Popup is disabled,
// the endscreen view with multiple suggestions is overlayed when it
// should not be.
%hook YTFullscreenEngagementOverlayController
- (BOOL)isEnabled {
    // repeatVideo is the key for uYou Repeat
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
    // iSponsorBlock integration temporarily disabled for stability.
    // if (IS_ENABLED(kHideiSponsorBlockButton) && [self respondsToSelector:@selector(sponsorBlockButton)]) {
    //     self.sponsorBlockButton.hidden = YES;
    //     self.sponsorBlockButton.frame = CGRectZero;
    // }
}
%end

// Hide Fullscreen Actions buttons - @bhackel & @arichornlover
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
    // Check if already removed from superview
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

// Video Player Options
// Skips content warning before playing *some videos - @PoomSmart
%hook YTPlayabilityResolutionUserActionUIController
- (void)showConfirmAlert { [self confirmAlertDidPressConfirm]; }
%end

%end // gSection6

// Portrait Fullscreen - @Dayanch96
%group gPortraitFullscreen
%hook YTWatchViewController
- (unsigned long long)allowedFullScreenOrientations {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}
%end
%end

// Fullscreen to the Right (iPhone-exclusive) - @arichornlover & @bhackel
// WARNING: Please turn off the “Portrait Fullscreen” and "iPad Layout" Options while the option "Fullscreen to the Right" is enabled below.
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

// Disable Double tap to skip chapter - @bhackel
%hook YTDoubleTapToSeekController
- (void)didTwoFingerDoubleTap:(id)arg1 {
    if (IS_ENABLED(kDisableChapterSkip)) {
        return;
    }
    %orig;
}
%end

// Disable snap to chapter
%hook YTSegmentableInlinePlayerBarView
- (void)didMoveToWindow {
    %orig;
    if (IS_ENABLED(kSnapToChapter)) {
        self.enableSnapToChapter = NO;
    }
}
%end

// Disable Pinch to zoom
%hook YTColdConfig
- (BOOL)videoZoomFreeZoomEnabledGlobalConfig {
    return IS_ENABLED(kPinchToZoom) ? NO : %orig;
}
%end

%end // gSection7

// Use stock iOS volume HUD
// Use YTColdConfig's method, see https://x.com/PoomSmart/status/1756904290445332653
%group gStockVolumeHUD
%hook YTColdConfig
- (BOOL)iosUseSystemVolumeControlInFullscreen {
    return IS_ENABLED(kStockVolumeHUD) ? YES : NO;
}
%end
%hook UIApplication 
- (void)setSystemVolumeHUDEnabled:(BOOL)arg1 forAudioCategory:(id)arg2 {
        %orig(true, arg2);
}
%end
%end

%group gSection8

%hook YTColdConfig
- (BOOL)speedMasterArm2FastForwardWithoutSeekBySliding {
    return IS_ENABLED(kSlideToSeek) ? NO : %orig;
}
%end

// Disable double tap to seek
%hook YTDoubleTapToSeekController
- (void)enableDoubleTapToSeek:(BOOL)arg1 {
    if (IS_ENABLED(kDoubleTapToSeek)) {
        %orig(NO);
    } else {
        %orig;
    }
}
%end

%end // gSection8

// Disable pull to enter vertical/portrait fullscreen gesture - @bhackel
// This was introduced in version 19.XX
// This only applies to landscape videos
%group gDisablePullToFull
%hook YTWatchPullToFullController
- (BOOL)shouldRecognizeOverscrollEventsFromWatchOverscrollController:(id)arg1 {
    // Get the current player orientation
    YTWatchViewController *watchViewController = (YTWatchViewController *)self.playerViewSource;
    NSUInteger allowedFullScreenOrientations = [watchViewController allowedFullScreenOrientations];
    // Check if the current player orientation is portrait
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

%group gSection9

// Video Controls Overlay Options
// Hide CC / Hide Autoplay switch / Hide YTMusic Button / Enable Share Button / Enable Save to Playlist Button
%hook YTMainAppControlsOverlayView
- (void)setClosedCaptionsOrSubtitlesButtonAvailable:(BOOL)arg1 { // hide CC button
    if (IS_ENABLED(kHideCC)) {
        %orig(NO);
    } else {
        %orig;
    }
}
- (void)setAutoplaySwitchButtonRenderer:(id)arg1 { // hide Autoplay
    if (!IS_ENABLED(kHideAutoplaySwitch)) {
        %orig;
    }
}
- (void)setYoutubeMusicButton:(id)arg1 {
    if (IS_ENABLED(kHideYTMusicButton)) {
    } else {
        %orig(arg1);
    }
}
- (void)setShareButtonAvailable:(BOOL)arg1 {
    if (IS_ENABLED(kEnableShareButton)) {
        %orig(YES);
    } else {
        %orig(NO);
    }
}
- (void)setAddToButtonAvailable:(BOOL)arg1 {
    if (IS_ENABLED(kEnableSaveToButton)) {
        %orig(YES);
    } else {
        %orig(NO);
    }
}
%end

// Hide Video Player Collapse Button - @arichornlover
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
        %orig(available);
    }
}
%end

%end // gSection9

// Hide Fullscreen Button - @arichornlover
%group gHideFullscreenButton
%hook YTInlinePlayerBarContainerView
- (BOOL)fullscreenButtonDisabled { return YES; }
- (BOOL)canShowFullscreenButton { return NO; }
- (BOOL)canShowFullscreenButtonExperimental { return NO; }
// - (void)setFullscreenButtonDisabled:(BOOL) // Might implement this if useful - @arichornlover
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

// Hide Channel Watermark
// (YTHUDMessageView / YTAnnotationsViewController removed — classes no longer
// exist in YouTube 21.x per PoomSmart/YouTubeHeader)
%hook YTColdConfig
- (BOOL)iosEnableFeaturedChannelWatermarkOverlayFix {
    return IS_ENABLED(kHideChannelWatermark) ? NO : %orig;
}
%end

// Always use remaining time in the video player - @bhackel
%hook YTPlayerBarController
// When a new video is played, enable time remaining flag
- (void)setActiveSingleVideo:(id)arg1 {
    %orig;
    if (IS_ENABLED(@"alwaysShowRemainingTime_enabled")) {
        // Get the player bar view
        YTInlinePlayerBarContainerView *playerBar = self.playerBar;
        if (playerBar) {
            // Enable the time remaining flag
            playerBar.shouldDisplayTimeRemaining = YES;
        }
    }
}
%end

// Disable toggle time remaining - @bhackel
%hook YTInlinePlayerBarContainerView
- (void)setShouldDisplayTimeRemaining:(BOOL)arg1 {
    if (IS_ENABLED(@"disableRemainingTime_enabled")) {
        // Set true if alwaysShowRemainingTime
        if (IS_ENABLED(@"alwaysShowRemainingTime_enabled")) {
            %orig(YES);
        } else {
            %orig(NO);
        }
        return;
    }
    %orig;
}
%end

%end // gSection10

// Hide previous and next buttons in all videos - @bhackel
%group gHidePreviousAndNextButton
%hook YTColdConfig
- (BOOL)removeNextPaddleForAllVideos { 
    return YES; 
}
- (BOOL)removePreviousPaddleForAllVideos { 
    return YES; 
}
%end
%end

%group gSection11

// Hide Video Title when in Fullscreen - @arichornlover
%hook YTMainAppControlsOverlayView
- (BOOL)titleViewHidden {
    return IS_ENABLED(@"hideVideoTitle_enabled") ? YES : %orig;
}
%end

%end // gSection11

// Hide Dark Overlay Background - @Dayanch96
%group gHideOverlayDarkBackground
%hook YTMainAppVideoPlayerOverlayView
- (void)setBackgroundVisible:(BOOL)arg1 isGradientBackground:(BOOL)arg2 {
    %orig(NO, arg2);
}
%end
%end

// Replace Next & Previous button with Fast forward & Rewind button
// %group gReplacePreviousAndNextButton
// %hook YTColdConfig
// - (BOOL)replaceNextPaddleWithFastForwardButtonForSingletonVods { return YES; }
// - (BOOL)replacePreviousPaddleWithRewindButtonForSingletonVods { return YES; }
// %end
// %end

// Hide Shadow Overlay Buttons (Play/Pause, Next, previous, Fast forward & Rewind buttons)
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

// Bring back the Red Progress Bar and Gray Buffer Progress
%group gRedProgressBar
%hook YTSegmentableInlinePlayerBarView
- (void)setBufferedProgressBarColor:(id)arg1 {
     [UIColor colorWithRed:1.00 green:1.00 blue:1.00 alpha:0.50];
}
%end

%hook YTInlinePlayerBarContainerView // Red Progress Bar - Old (Compatible for v17.33.2-v19.10.7) - Planned for removal ⚠️
- (id)quietProgressBarColor {
    return [UIColor redColor];
}
%end

%hook YTPlayerBarRectangleDecorationView // Red Progress Bar - New (Compatible for v19.10.7-latest)
- (void)drawRectangleDecorationWithSideMasks:(CGRect)rect {
    if (IS_ENABLED(kRedProgressBar)) {
        YTIPlayerBarDecorationModel *model = [self valueForKey:@"_model"];
        int overlayMode = model.playingState.overlayMode;
        model.playingState.overlayMode = 1;
        %orig;
        model.playingState.overlayMode = overlayMode;
    } else
        %orig;
}
%end
%end

%group gSection12

// Disable the right panel in fullscreen mode
%hook YTColdConfig
- (BOOL)isLandscapeEngagementPanelEnabled {
    return IS_ENABLED(kHideRightPanel) ? NO : %orig;
}
%end

%end // gSection12

// Shorts Quality Picker - @arichornlover
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

%group gSection13

// YTShortsProgress - https://github.com/PoomSmart/YTShortsProgress/
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

%hook YTColdConfig
- (BOOL)iosEnableVideoPlayerScrubber { return YES; }
- (BOOL)mobileShortsTablnlinedExpandWatchOnDismiss { return YES; }
%end

%hook YTHotConfig
- (BOOL)enablePlayerBarForVerticalVideoWhenControlsHiddenInFullscreen { return YES; }
%end

// Hide Shorts Cells - LEGACY v1.2.3 - for uYou 3.0.4+ (PoomSmart/YTUnShorts)
%hook YTIElementRenderer
- (NSData *)elementData {
    // Check if hideShortsCells is enabled
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"hideShortsCells"]) {
        NSString *description = [self description];
        
        BOOL hasShorts = ([description containsString:@"shorts_shelf"] || [description containsString:@"shorts_video_cell"] || [description containsString:@"shorts_grid_shelf_footer"] || [description containsString:@"youtube_shorts_24"]);
        BOOL hasShortsInHistory = [description containsString:@"compact_video.eml"] && [description containsString:@"youtube_shorts_"];

        if (hasShorts || hasShortsInHistory) {
            return [NSData data];
        }
    }
    return %orig;
}
%end

// Shorts Controls Overlay Options
%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    if ((IS_ENABLED(kHideBuySuperThanks)) && ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.suggested_action"])) { 
        self.hidden = YES; 
    }

// Hide Shorts Buttons when Paused - Clip, Download, Remix, Stats for Nerds
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
    // Fallback: hide by description for Shorts pause-state buttons
    if (IS_ENABLED(kHideShortsClipButton) || IS_ENABLED(kHideShortsDownloadButton) || IS_ENABLED(kHideShortsRemixButton) || IS_ENABLED(kHideShortsStatsButton)) {
        NSString *desc = self.accessibilityLabel;
        if (desc) {
            if (IS_ENABLED(kHideShortsClipButton) && [desc isEqualToString:@"Clip"]) self.hidden = YES;
            if (IS_ENABLED(kHideShortsDownloadButton) && [desc isEqualToString:@"Download"]) self.hidden = YES;
            if (IS_ENABLED(kHideShortsRemixButton) && [desc isEqualToString:@"Remix"]) self.hidden = YES;
            if (IS_ENABLED(kHideShortsStatsButton) && [desc isEqualToString:@"Stats for nerds"]) self.hidden = YES;
        }
    }

// Hide Header Links under Channel Profile - @arichornlover
    if ((IS_ENABLED(kHideChannelHeaderLinks)) && ([self.accessibilityIdentifier isEqualToString:@"eml.channel_header_links"])) {
        self.hidden = YES;
        self.opaque = YES;
        self.userInteractionEnabled = NO;
        [self sizeToFit];
        [self.superview layoutIfNeeded];
        [self setNeedsLayout];
        [self removeFromSuperview];
    }

// Completely Remove the Comment Section under the Video Player - @arichornlover
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

// Hide the Comment Section Previews under the Video Player - @arichornlover
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

// Red Subscribe Button + Hide the Button Containers under the Video Player - @arichornlover
// Hide the Button Containers under the Video Player - v20.02.3+ - @arichornlover
%hook ELMContainerNode
- (void)layoutSubviews {
    %orig;

    NSString *desc = [self description];

// Red Subscribe Button - v20.02.3+ - @arichornlover
    if ([desc containsString:@"eml.compact_subscribe_button"] && IS_ENABLED(kRedSubscribeButton)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self applyRedColorToSubscribeButton:self];
        });
    }
// Hide the Button Containers under the Video Player - v20.02.3+ - @arichornlover
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

%end // gSection13

// App Settings Overlay Options
%group gDisableAccountSection
%hook YTSettingsSectionItemManager
- (void)updateAccountSwitcherSectionWithEntry:(id)arg1 {} // Account
%end
%end

%group gDisableAutoplaySection
%hook YTSettingsSectionItemManager
- (void)updateAutoplaySectionWithEntry:(id)arg1 {} // Autoplay
%end
%end

%group gDisableTryNewFeaturesSection
%hook YTSettingsSectionItemManager
- (void)updatePremiumEarlyAccessSectionWithEntry:(id)arg1 {} // Try new features
%end
%end

%group gDisableVideoQualityPreferencesSection
%hook YTSettingsSectionItemManager
- (void)updateVideoQualitySectionWithEntry:(id)arg1 {} // Video quality preferences
%end
%end

%group gDisableNotificationsSection
%hook YTSettingsSectionItemManager
- (void)updateNotificationSectionWithEntry:(id)arg1 {} // Notifications
%end
%end

%group gDisableManageAllHistorySection
%hook YTSettingsSectionItemManager
- (void)updateHistorySectionWithEntry:(id)arg1 {} // Manage all history
%end
%end

%group gDisableYourDataInYouTubeSection
%hook YTSettingsSectionItemManager
- (void)updateYourDataSectionWithEntry:(id)arg1 {} // Your data in YouTube
%end
%end

%group gDisablePrivacySection
%hook YTSettingsSectionItemManager
- (void)updatePrivacySectionWithEntry:(id)arg1 {} // Privacy
%end
%end

%group gDisableLiveChatSection
%hook YTSettingsSectionItemManager
- (void)updateLiveChatSectionWithEntry:(id)arg1 {} // Live chat
%end
%end

// Miscellaneous

// Hide Home Tab - @bhackel
%group gHideHomeTab
%hook YTPivotBarView
- (void)setRenderer:(YTIPivotBarRenderer *)renderer {
    // Iterate over each renderer item
    NSLog(@"bhackel: setting renderer");
    NSUInteger indexToRemove = -1;
    NSMutableArray <YTIPivotBarSupportedRenderers *> *itemsArray = renderer.itemsArray;
    NSLog(@"bhackel: starting loop");
    for (NSUInteger i = 0; i < itemsArray.count; i++) {
        NSLog(@"bhackel: iterating index %lu", (unsigned long)i);
        YTIPivotBarSupportedRenderers *item = itemsArray[i];
        // Check if this is the home tab button
        NSLog(@"bhackel: checking identifier");
        YTIPivotBarItemRenderer *pivotBarItemRenderer = item.pivotBarItemRenderer;
        NSString *pivotIdentifier = pivotBarItemRenderer.pivotIdentifier;
        if ([pivotIdentifier isEqualToString:@"FEwhat_to_watch"]) {
            NSLog(@"bhackel: removing home tab button");
            // Remove the home tab button
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

// Auto-Hide Home Bar
%group gAutoHideHomeBar
%hook UIViewController
- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}
%end
%end

%group gSection14

// YT startup animation
%hook YTColdConfig
- (BOOL)mainAppCoreClientIosEnableStartupAnimation {
    return IS_ENABLED(kYTStartupAnimation) ? YES : NO;
}
%end

%end // gSection14

// Disable hints
%group gDisableHints
%hook YTSettings
- (BOOL)areHintsDisabled {
	return YES;
}
- (void)setHintsDisabled:(BOOL)arg1 {
    %orig(YES);
}
%end
%hook YTUserDefaults
- (BOOL)areHintsDisabled {
	return YES;
}
- (void)setHintsDisabled:(BOOL)arg1 {
    %orig(YES);
}
%end
%end

// Stick Navigation bar
%group gStickNavigationBar
%hook YTHeaderView
- (BOOL)stickyNavHeaderEnabled { return YES; } 
%end
%end

// Hide the Chip Bar (Upper Bar) in Home feed
%group gHideChipBar
%hook YTMySubsFilterHeaderView 
- (void)setChipFilterView:(id)arg1 {}
%end

%hook YTHeaderContentComboView
- (void)enableSubheaderBarWithView:(id)arg1 {}
%end

%hook YTHeaderContentComboView
- (void)setFeedHeaderScrollMode:(int)arg1 {
    %orig(0);
}
%end

// Hide the chip bar under the video player?
// %hook YTChipCloudCell
// - (void)didMoveToWindow {
//     %orig;
//     self.hidden = YES;
// }
// %end
%end

%group gSection15

// Hide "Play next in queue" - qnblackcat/uYouPlus#1138
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

%end // gSection15

// Hide the Videos under the Video Player - @Dayanch96 & @arichornlover
%group gNoRelatedWatchNexts
%hook YTWatchNextResultsViewController
- (void)setVisibleSections:(NSInteger)arg1 {
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad && UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation)) {
        // doesn't hide Videos under the Video Player if iPad is in Landscape mode to prevent conflicts
        return;
    } else {
        arg1 = 1;
        %orig(arg1);
    }
}
%end
%end

// Hide Videos when in Fullscreen - @arichornlover
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

// iPhone Layout - @arichornlover
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

// Hide Indicators - @Dayanch96 & @arichornlover
%group gHideSubscriptionsNotificationBadge
%hook YTPivotBarIndicatorView
- (void)didMoveToWindow {
    [self setHidden:YES];
    %orig();
}
- (void)setFillColor:(id)arg1 {
    %orig([UIColor clearColor]);
}
- (void)setBorderColor:(id)arg1 {
    %orig([UIColor clearColor]);
}
%end
%hook YTCountView
- (void)layoutSubviews {
    %orig;
    self.hidden = YES;
}
%end
%end

# pragma mark - ctor
%ctor {
    // Load uYou first so its functions are available for hooks.
    // dlopen([[NSString stringWithFormat:@"%@/Frameworks/uYou.dylib", [[NSBundle mainBundle] bundlePath]] UTF8String], RTLD_LAZY);

    %init;
    %init(gAlwaysOn);
    %init(gMisc1);
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
    %init(gSection14);
    %init(gSection15);
//  if (IS_ENABLED(kSettingsStyle_enabled)) {
//      %init(gSettingsStyle);
//  }

    if (IS_ENABLED(kHideYouTubeLogo)) {
        %init(gHideYouTubeLogo);
    }
    if (IS_ENABLED(kCenterYouTubeLogo)) {
        %init(gCenterYouTubeLogo);
    }
    if (IS_ENABLED(kHideSubscriptionsNotificationBadge)) {
        %init(gHideSubscriptionsNotificationBadge);
    }
    if (IS_ENABLED(kHidePreviousAndNextButton)) {
        %init(gHidePreviousAndNextButton);
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
    // gShowNotificationsTab - initialized in Sources/NotificationsTab.xm
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
    // uYouAdBlockingWorkaroundLite + uYouAdBlockingWorkaround - initialized in Sources/AdBlocking.xm
    if (IS_ENABLED(kHideHomeTab)) {
        %init(gHideHomeTab);
    }
    if (IS_ENABLED(kAutoHideHomeBar)) {
        %init(gAutoHideHomeBar);
    }
    if (IS_ENABLED(kShortsQualityPicker)) {
        %init(gShortsQualityPicker);
    }
    if (IS_ENABLED(kFixCasting)) {
        %init(gFixCasting);
    }

    // Change the default value of some options
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
    // Broken uYou 3.0.3 setting: No Suggested Videos at The Video End
    // Set default to allow autoplay, user can disable later
    if (![allKeys containsObject:@"noSuggestedVideoAtEnd"]) { 
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"noSuggestedVideoAtEnd"]; 
    }
    // Broken uYou 3.0.2 setting: Playback Speed Controls
    // Set default to disabled on iPads
    if (![allKeys containsObject:@"showPlaybackRate"]) {
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"showPlaybackRate"]; 
        } else {
            [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"showPlaybackRate"]; 
        }
    }
    // Set video casting fix default to enabled
    if (![allKeys containsObject:@"fixCasting_enabled"]) { 
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kFixCasting]; 
    }
    // Set new grouped settings UI to default enabled
    if (![allKeys containsObject:@"newSettingsUI_enabled"]) { 
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kNewSettingsUI]; 
    }
}
