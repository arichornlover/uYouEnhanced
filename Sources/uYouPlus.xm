#import "uYouPlus.h"

// Tweak's bundle for Localizations support - @PoomSmart - https://github.com/PoomSmart/YouPiP/commit/aea2473f64c75d73cab713e1e2d5d0a77675024f
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
//

# pragma mark - Other hooks

// Activate FLEX
%hook YTAppDelegate
- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions {
    BOOL didFinishLaunching = %orig;

    if (IS_ENABLED(@"flex_enabled")) {
        [[%c(FLEXManager) performSelector:@selector(sharedManager)] performSelector:@selector(showExplorer)];
    }

    return didFinishLaunching;
}
- (void)appWillResignActive:(id)arg1 {
    %orig;
         if (IS_ENABLED(@"flex_enabled")) {
        [[%c(FLEXManager) performSelector:@selector(sharedManager)] performSelector:@selector(showExplorer)];
    }
}
%end

// Fixes uYou crash when trying to play video (qnblackcat/#1422) - @Dayanch96
%hook YTPlayerOverlayManager
%property (nonatomic, assign) float currentPlaybackRate;

%new
- (void)setCurrentPlaybackRate:(float)rate {
    [self varispeedSwitchController:self.varispeedController didSelectRate:rate];
}

%new
- (void)setPlaybackRate:(float)rate {
    [self varispeedSwitchController:self.varispeedController didSelectRate:rate];
}
%end

// Enable Alternate Icons - @arichornlover
%hook UIApplication
- (BOOL)supportsAlternateIcons {
    return YES;
}
%end

// uYou AdBlock Workaround LITE (This Version will only remove ads from Videos/Shorts!) - @PoomSmart
%group uYouAdBlockingWorkaroundLite
%hook YTHotConfig
- (BOOL)disableAfmaIdfaCollection { return NO; }
%end

%hook YTIPlayerResponse
- (BOOL)isMonetized { return NO; }
%end

%hook YTAdShieldUtils
+ (id)spamSignalsDictionary { return @{}; }
+ (id)spamSignalsDictionaryWithoutIDFA { return @{}; }
%end

%hook YTDataUtils
+ (id)spamSignalsDictionary { return @{}; }
+ (id)spamSignalsDictionaryWithoutIDFA { return @{}; }
%end

%hook YTAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context { %orig(nil); }
%end

%hook YTAccountScopedAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context { %orig(nil); }
%end

%hook YTReelInfinitePlaybackDataSource
- (void)setReels:(NSMutableOrderedSet <YTReelModel *> *)reels {
    [reels removeObjectsAtIndexes:[reels indexesOfObjectsPassingTest:^BOOL(YTReelModel *obj, NSUInteger idx, BOOL *stop) {
        return [obj respondsToSelector:@selector(videoType)] ? obj.videoType == 3 : NO;
    }]];
    %orig;
}
%end
%end

// uYou AdBlock Workaround (Note: disables uYou's "Remove YouTube Ads" Option) - @PoomSmart, @arichornlover & @Dodieboy
%group uYouAdBlockingWorkaround
// Workaround: uYou 3.0.3 Adblock fix
%hook YTHotConfig
- (BOOL)disableAfmaIdfaCollection { return NO; }
%end
%hook YTIPlayerResponse
- (BOOL)isMonetized { return NO; }
%end
%hook YTAdShieldUtils
+ (id)spamSignalsDictionary { return @{}; }
+ (id)spamSignalsDictionaryWithoutIDFA { return @{}; }
%end
%hook YTDataUtils
+ (id)spamSignalsDictionary { return @{}; }
+ (id)spamSignalsDictionaryWithoutIDFA { return @{}; }
%end
%hook YTAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context { %orig(nil); }
%end
%hook YTAccountScopedAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context { %orig(nil); }
%end
%hook YTReelInfinitePlaybackDataSource
- (void)setReels:(NSMutableOrderedSet <YTReelModel *> *)reels {
    [reels removeObjectsAtIndexes:[reels indexesOfObjectsPassingTest:^BOOL(YTReelModel *obj, NSUInteger idx, BOOL *stop) {
        return [obj respondsToSelector:@selector(videoType)] ? obj.videoType == 3 : NO;
    }]];
    %orig;
}
%end
NSString *getAdString(NSString *description) {
    if ([description containsString:@"brand_promo"])
        return @"brand_promo";
    if ([description containsString:@"carousel_footered_layout"])
        return @"carousel_footered_layout";
    if ([description containsString:@"carousel_headered_layout"])
        return @"carousel_headered_layout";
    if ([description containsString:@"feed_ad_metadata"])
        return @"feed_ad_metadata";
    if ([description containsString:@"full_width_portrait_image_layout"])
        return @"full_width_portrait_image_layout";
    if ([description containsString:@"full_width_square_image_layout"])
        return @"full_width_square_image_layout";
    if ([description containsString:@"landscape_image_wide_button_layout"])
        return @"landscape_image_wide_button_layout";
    if ([description containsString:@"post_shelf"])
        return @"post_shelf";
    if ([description containsString:@"product_carousel"])
        return @"product_carousel";
    if ([description containsString:@"product_engagement_panel"])
        return @"product_engagement_panel";
    if ([description containsString:@"product_item"])
        return @"product_item";
    if ([description containsString:@"statement_banner"])
        return @"statement_banner";
    if ([description containsString:@"square_image_layout"])
        return @"square_image_layout";
    if ([description containsString:@"text_image_button_layout"])
        return @"text_image_button_layout";
    if ([description containsString:@"text_search_ad"])
        return @"text_search_ad";
    if ([description containsString:@"video_display_full_layout"])
        return @"video_display_full_layout";
    if ([description containsString:@"video_display_full_buttoned_layout"])
        return @"video_display_full_buttoned_layout";
    return nil;
}
static __strong NSData *cellDividerData;
%hook YTIElementRenderer
- (NSData *)elementData {
    NSString *description = [self description];
    if ([description containsString:@"cell_divider"]) {
        if (!cellDividerData) cellDividerData = %orig;
        return cellDividerData;
    }
    if (!cellDividerData) return %orig;
    if ([self respondsToSelector:@selector(hasCompatibilityOptions)] && self.hasCompatibilityOptions && self.compatibilityOptions.hasAdLoggingData) {
        // HBLogInfo(@"YTX adLogging 1 %@", cellDividerData);
        return cellDividerData;
    }
    NSString *adString = getAdString(description);
    if (adString) {
        // HBLogInfo(@"YTX getAdString 1 %@ %@", adString, cellDividerData);
        return cellDividerData;
    }
    return %orig;
}
%end
%hook YTInnerTubeCollectionViewController
- (void)loadWithModel:(YTISectionListRenderer *)model {
    if ([model isKindOfClass:%c(YTISectionListRenderer)]) {
        NSMutableArray <YTISectionListSupportedRenderers *> *contentsArray = model.contentsArray;
        NSIndexSet *removeIndexes = [contentsArray indexesOfObjectsPassingTest:^BOOL(YTISectionListSupportedRenderers *renderers, NSUInteger idx, BOOL *stop) {
            if (![renderers isKindOfClass:%c(YTISectionListSupportedRenderers)])
                return NO;
            YTIItemSectionRenderer *sectionRenderer = renderers.itemSectionRenderer;
            YTIItemSectionSupportedRenderers *firstObject = [sectionRenderer.contentsArray firstObject];
            YTIElementRenderer *elementRenderer = firstObject.elementRenderer;
            if ([elementRenderer respondsToSelector:@selector(hasCompatibilityOptions)] && elementRenderer.hasCompatibilityOptions && elementRenderer.compatibilityOptions.hasAdLoggingData) {
                // HBLogInfo(@"YTX adLogging 2 %@", elementRenderer);
                return YES;
            }
            NSString *description = [elementRenderer description];
            NSString *adString = getAdString(description);
            if (adString) {
                // HBLogInfo(@"YTX getAdString 2 %@ %@", adString, elementRenderer);
                return YES;
            }
            return NO;
        }];
        [contentsArray removeObjectsAtIndexes:removeIndexes];
    }
    %orig;
}
%end
%end

// Hide YouTube Logo - @dayanch96
%group gHideYouTubeLogo
%hook YTHeaderLogoController
- (YTHeaderLogoController *)init {
    return NULL;
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

%group gCenterYouTubeLogo
%hook YTNavigationBarTitleView
- (void)setShouldCenterNavBarTitleView:(BOOL)center {
    %orig(YES);
}
- (BOOL)shouldCenterNavBarTitleView {
    return YES;
}
- (void)alignCustomViewToCenterOfWindow {
}
%end
%end

// Fix App Group Directory by move it to document directory
%hook NSFileManager
- (NSURL *)containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
    if (groupIdentifier != nil) {
        NSArray *paths = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
        NSURL *documentsURL = [paths lastObject];
        return [documentsURL URLByAppendingPathComponent:@"AppGroup"];
    }
    return %orig(groupIdentifier);
}
%end

// Remove App Rating Prompt in YouTube (for Sideloaded - iOS 14+) - @arichornlover
%hook SKStoreReviewController
+ (void)requestReview { }
%end

// YTMiniPlayerEnabler: https://github.com/level3tjg/YTMiniplayerEnabler/
%hook YTWatchMiniBarViewController
- (void)updateMiniBarPlayerStateFromRenderer {
    if (IS_ENABLED(@"ytMiniPlayer_enabled")) {}
    else { return %orig; }
}
%end

// YTNoHoverCards: https://github.com/level3tjg/YTNoHoverCards
%hook YTCreatorEndscreenView
- (void)setHidden:(BOOL)hidden {
    if (IS_ENABLED(@"hideHoverCards_enabled"))
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
- (BOOL)respectDeviceCaptionSetting { return NO; } // YouRememberCaption: https://poomsmart.github.io/repo/depictions/youremembercaption.html
- (BOOL)isLandscapeEngagementPanelSwipeRightToDismissEnabled { return YES; } // Swipe right to dismiss the right panel in fullscreen mode
- (BOOL)enableModularPlayerBarController { return NO; } // fixes some of the iSponorBlock problems
- (BOOL)mainAppCoreClientEnableCairoSettings { return IS_ENABLED(@"newSettingsUI_enabled"); } // New grouped settings UI
- (BOOL)enableIosFloatingMiniplayer { return IS_ENABLED(@"floatingMiniplayer_enabled"); } // Floating Miniplayer
- (BOOL)enableIosFloatingMiniplayerSwipeUpToExpand { return IS_ENABLED(@"floatingMiniplayer_enabled"); } // Floating Miniplayer
- (BOOL)enableIosFloatingMiniplayerRepositioning { return IS_ENABLED(@"floatingMiniplayer2_enabled"); } // Floating Miniplayer (Repositioning Support, Removes Swiping Up Gesture)
%end

// Fix Casting: https://github.com/arichornlover/uYouEnhanced/issues/606#issuecomment-2098289942
%group gFixCasting
%hook YTColdConfig
- (BOOL)cxClientEnableIosLocalNetworkPermissionReliabilityFixes { return YES; }
- (BOOL)cxClientEnableIosLocalNetworkPermissionUsingSockets { return NO; }
- (BOOL)cxClientEnableIosLocalNetworkPermissionWifiFixes { return YES; }
%end
%hook YTHotConfig
- (BOOL)isPromptForLocalNetworkPermissionsEnabled { return YES; }
%end
%end

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

%hook YTIShowFullscreenInterstitialCommand
- (BOOL)shouldThrottleInterstitial { return YES; }
%end

%hook YTSurveyController
- (void)showSurveyWithRenderer:(id)arg1 surveyParentResponder:(id)arg2 {}
%end

%hook YTIOfflineabilityFormat
%new
- (int)availabilityType { return 1; }
%new
- (BOOL)savedSettingShouldExpire { return NO; }
%end

// Restore Settings Button in Navigaton Bar - @arichornlover & @bhackel - https://github.com/arichornlover/uYouEnhanced/issues/178
/* WILL RESULT IN LOSING THE SETTINGS BUTTON!
%hook YTRightNavigationButtons
- (id)visibleButtons {
    Class YTVersionUtilsClass = %c(YTVersionUtils);
    NSString *appVersion = [YTVersionUtilsClass performSelector:@selector(appVersion)];
    NSComparisonResult result = [appVersion compare:@"18.35.4" options:NSNumericSearch];
    if (result == NSOrderedAscending) {
        return %orig;
    }
    return [self dynamicButtons];
}
%end
*/

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

// Fake premium - @bhackel
%group gFakePremium
// YouTube Premium Logo - @arichornlover & bhackel
%hook YTHeaderLogoController
- (void)setTopbarLogoRenderer:(YTITopbarLogoRenderer *)renderer {
    // Modify the type of the icon before setting the renderer
    YTIIcon *iconImage = renderer.iconImage;
    iconImage.iconType = 537; // magic number for Premium icon, hopefully it doesnt change. 158 is default logo.
    // Use this modified renderer
    %orig;
}
// For when spoofing before 18.34.5
- (void)setPremiumLogo:(BOOL)isPremiumLogo {
    isPremiumLogo = YES;
    %orig;
}
- (BOOL)isPremiumLogo {
    return YES;
}
%end
%hook YTAppCollectionViewController
/**
  * Modify a given renderer data model to fake premium in the You tab
  * Replaces the "Get YouTube Premium" cell with a "Your Premium benefits" cell
  * and adds a "Downloads" cell below the "Your videos" cell
  * @param model The model for the You tab
  */
%new
- (void)uYouEnhancedFakePremiumModel:(YTISectionListRenderer *)model {
    // Don't do anything if the version is too low
    Class YTVersionUtilsClass = %c(YTVersionUtils);
    NSString *appVersion = [YTVersionUtilsClass performSelector:@selector(appVersion)];
    NSComparisonResult result = [appVersion compare:@"18.35.4" options:NSNumericSearch];
    if (result == NSOrderedAscending) {
        return;
    }
    NSUInteger yourVideosCellIndex = -1;
    NSMutableArray <YTISectionListSupportedRenderers *> *overallContentsArray = model.contentsArray;
    // Check each item in the overall array - this represents the whole You page
    YTISectionListSupportedRenderers *supportedRenderers;
    for (supportedRenderers in overallContentsArray) {
        YTIItemSectionRenderer *itemSectionRenderer = supportedRenderers.itemSectionRenderer;
        // Check each subobject - this would be visible as a cell in the You page
        NSMutableArray <YTIItemSectionSupportedRenderers *> *subContentsArray = itemSectionRenderer.contentsArray;
        YTIItemSectionSupportedRenderers *itemSectionSupportedRenderers;
        for (itemSectionSupportedRenderers in subContentsArray) {
            // Check for Get Youtube Premium cell, which is of type CompactLinkRenderer
            if ([itemSectionSupportedRenderers hasCompactLinkRenderer]) {
                YTICompactLinkRenderer *compactLinkRenderer = [itemSectionSupportedRenderers compactLinkRenderer];
                // Check for an icon in this cell
                if ([compactLinkRenderer hasIcon]) {
                    YTIIcon *icon = [compactLinkRenderer icon];
                    // Check if the icon is for the premium advertisement - 117 is magic number for the icon
                    if ([icon hasIconType] && icon.iconType == 117) {
                        // Modify the icon type to be Premium
                        icon.iconType = 741; // Magic number for premium icon
                        // Modify the text
                        ((YTIStringRun *)(compactLinkRenderer.title.runsArray.firstObject)).text = LOC(@"FAKE_YOUR_PREMIUM_BENEFITS");
                    }
                }
            }
            // Check for Your Videos cell using similar logic explained above
            if ([itemSectionSupportedRenderers hasCompactListItemRenderer]) {
                YTICompactListItemRenderer *compactListItemRenderer = itemSectionSupportedRenderers.compactListItemRenderer;
                if ([compactListItemRenderer hasThumbnail]) {
                    YTICompactListItemThumbnailSupportedRenderers *thumbnail = compactListItemRenderer.thumbnail;
                    if ([thumbnail hasIconThumbnailRenderer]) {
                        YTIIconThumbnailRenderer *iconThumbnailRenderer = thumbnail.iconThumbnailRenderer;
                        if ([iconThumbnailRenderer hasIcon]) {
                            YTIIcon *icon = iconThumbnailRenderer.icon;
                            if ([icon hasIconType] && icon.iconType == 658) {
                                // Store the index of this cell
                                yourVideosCellIndex = [subContentsArray indexOfObject:itemSectionSupportedRenderers];
                            }
                        }
                    }
                }
            }
        }
        if (yourVideosCellIndex != -1 && subContentsArray[yourVideosCellIndex].accessibilityLabel == nil) {
            // Create the fake Downloads page by copying the Your Videos page and modifying it
            // Note that this must be done outside the loop to avoid a runtime exception
            // TODO Link this to the uYou downloads page
            YTIItemSectionSupportedRenderers *newItemSectionSupportedRenderers = [subContentsArray[yourVideosCellIndex] copy];
            ((YTIStringRun *)(newItemSectionSupportedRenderers.compactListItemRenderer.title.runsArray.firstObject)).text = LOC(@"FAKE_DOWNLOADS");
            newItemSectionSupportedRenderers.compactListItemRenderer.thumbnail.iconThumbnailRenderer.icon.iconType = 147;
            // Insert this cell after the Your Videos cell
            [subContentsArray insertObject:newItemSectionSupportedRenderers atIndex:yourVideosCellIndex + 1];
            // Inject a note to not modify this again
            subContentsArray[yourVideosCellIndex].accessibilityLabel = @"uYouEnhanced Modified";
            yourVideosCellIndex = -1;
        }
    }
}
- (void)loadWithModel:(YTISectionListRenderer *)model {
    // This method is called on first load of the You page
    [self uYouEnhancedFakePremiumModel:model];
    %orig;
}
- (void)setupSectionListWithModel:(YTISectionListRenderer *)model isLoadingMore:(BOOL)isLoadingMore isRefreshingFromContinuation:(BOOL)isRefreshingFromContinuation {
    // This method is called on refresh of the You page
    [self uYouEnhancedFakePremiumModel:model];
    %orig;
}
%end
%end

// Disable animated YouTube Logo - @bhackel
%hook YTHeaderLogoController
- (void)configureYoodleNitrateController {
    if (IS_ENABLED(@"disableAnimatedYouTubeLogo_enabled")) {
        return;
    }
    %orig;
}
%end

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

// YTNoPaidPromo: https://github.com/PoomSmart/YTNoPaidPromo
%hook YTMainAppVideoPlayerOverlayViewController
- (void)setPaidContentWithPlayerData:(id)data {
    if (IS_ENABLED(@"hidePaidPromotionCard_enabled")) {}
    else { return %orig; }
}
- (void)playerOverlayProvider:(YTPlayerOverlayProvider *)provider didInsertPlayerOverlay:(YTPlayerOverlay *)overlay {
    if ([[overlay overlayIdentifier] isEqualToString:@"player_overlay_paid_content"] && IS_ENABLED(@"hidePaidPromotionCard_enabled")) return;
    %orig;
}
%end

%hook YTInlineMutedPlaybackPlayerOverlayViewController
- (void)setPaidContentWithPlayerData:(id)data {
    if (IS_ENABLED(@"hidePaidPromotionCard_enabled")) {}
    else { return %orig; }
}
%end

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

// Fix LowContrastMode - @arichornlover
static int contrastMode() {
    NSString *appVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    NSComparisonResult result1 = [appVersion compare:@"17.33.2" options:NSNumericSearch];
    NSComparisonResult result2 = [appVersion compare:@"17.38.10" options:NSNumericSearch];

    if (result1 != NSOrderedAscending && result2 != NSOrderedDescending) {
        return [[NSUserDefaults standardUserDefaults] integerForKey:@"lcm"];
    } else {
        return 0;
    }
}

%group gFixLowContrastMode
%hook NSUserDefaults
- (NSInteger)integerForKey:(NSString *)defaultName {
    if ([defaultName isEqualToString:@"lcm"]) {
        return contrastMode();
    }
    return %orig;
}
%end

%hook NSBundle
- (id)objectForInfoDictionaryKey:(NSString *)key {
    if ([key isEqualToString:@"CFBundleShortVersionString"]) {
        return @"17.38.10";
    }
    return %orig;
}
%end

%hook YTVersionUtils
+ (NSString *)appVersion { 
    return @"17.38.10";
}
%end

/*
%hook YTSettingsCell // Remove v17.38.10 Version Number - @Dayanch96
- (void)setDetailText:(id)arg1 {
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *appVersion = infoDictionary[@"CFBundleShortVersionString"];

    if ([arg1 isEqualToString:@"17.38.10"]) {
        arg1 = appVersion;
    } %orig(arg1);
}
%end
*/
%end

// Disable Modern/Rounded Buttons (_ASDisplayView Version's not supported) - @arichornlover
%group gDisableModernButtons 
%hook YTQTMButton // Disable Modern/Rounded Buttons
+ (BOOL)buttonModernizationEnabled { return NO; }
%end
%end

// Disable Rounded Hints with no Rounded Corners - @arichornlover
%group gDisableRoundedHints
%hook YTBubbleHintView // Disable Modern/Rounded Hints
+ (BOOL)modernRoundedCornersEnabled { return NO; }
%end
%end

// Disable Modern Flags - @arichornlover
%group gDisableModernFlags
%hook YTColdConfig
// Disable Modern Content
- (BOOL)creatorClientConfigEnableStudioModernizedMdeThumbnailPickerForClient { return NO; }
- (BOOL)cxClientEnableModernizedActionSheet { return NO; }
- (BOOL)enableClientShortsSheetsModernization { return NO; }
- (BOOL)enableTimestampModernizationForNative { return NO; }
- (BOOL)modernizeElementsTextColor { return NO; }
- (BOOL)modernizeElementsBgColor { return NO; }
- (BOOL)modernizeCollectionLockups { return NO; }
- (BOOL)uiSystemsClientGlobalConfigEnableModernButtonsForNative { return NO; }
- (BOOL)uiSystemsClientGlobalConfigIosEnableModernTabsForNative { return NO; }
- (BOOL)uiSystemsClientGlobalConfigIosEnableEpUxUpdates { return NO; }
- (BOOL)uiSystemsClientGlobalConfigIosEnableSheetsUxUpdates { return NO; }
- (BOOL)uiSystemsClientGlobalConfigIosEnableSnackbarModernization { return NO; }
// Disable Rounded Content
- (BOOL)iosDownloadsPageRoundedThumbs { return NO; }
- (BOOL)iosRoundedSearchBarSuggestZeroPadding { return NO; }
- (BOOL)uiSystemsClientGlobalConfigEnableRoundedDialogForNative { return NO; }
- (BOOL)uiSystemsClientGlobalConfigEnableRoundedThumbnailsForNative { return NO; }
- (BOOL)uiSystemsClientGlobalConfigEnableRoundedThumbnailsForNativeLongTail { return NO; }
- (BOOL)uiSystemsClientGlobalConfigEnableRoundedTimestampForNative { return NO; }
// Disable Optional Content
- (BOOL)elementsClientIosElementsEnableLayoutUpdateForIob { return NO; }
- (BOOL)supportElementsInMenuItemSupportedRenderers { return NO; }
- (BOOL)isNewRadioButtonStyleEnabled { return NO; }
- (BOOL)uiSystemsClientGlobalConfigEnableButtonSentenceCasingForNative { return NO; }
- (BOOL)mainAppCoreClientEnableClientYouTab { return NO; }
- (BOOL)mainAppCoreClientEnableClientYouLatency { return NO; }
- (BOOL)mainAppCoreClientEnableClientYouTabTablet { return NO; }
%end

%hook YTHotConfig
- (BOOL)liveChatIosUseModernRotationDetection { return NO; } // Disable Modern Content (YTHotConfig)
- (BOOL)liveChatModernizeClassicElementizeTextMessage { return NO; }
- (BOOL)iosShouldRepositionChannelBar { return NO; }
- (BOOL)enableElementRendererOnChannelCreation { return NO; }
%end
%end

// Disable Ambient Mode in Fullscreen - @arichornlover
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
- (BOOL)enableTurnOffCinematicForFrameWithBlackBars { return YES; }
- (BOOL)enableTurnOffCinematicForVideoWithBlackBars { return YES; }
- (BOOL)iosCinematicContainerClientImprovement { return NO; }
- (BOOL)iosEnableGhostCardInlineTitleCinematicContainerFix { return NO; }
- (BOOL)iosUseFineScrubberMosaicStoreForCinematic { return NO; }
- (BOOL)mainAppCoreClientEnableClientCinematicPlaylists { return NO; }
- (BOOL)mainAppCoreClientEnableClientCinematicPlaylistsPostMvp { return NO; }
- (BOOL)mainAppCoreClientEnableClientCinematicTablets { return NO; }
- (BOOL)iosEnableFullScreenAmbientMode { return NO; }
%end
%end

// Hide YouTube Heatwaves in Video Player - v17.33.2+ - @arichornlover
%group gHideHeatwaves
%hook YTInlinePlayerBarContainerView
- (BOOL)canShowHeatwave { return NO; }
%end
%hook YTPlayerBarHeatwaveView
- (id)initWithFrame:(CGRect)frame heatmap:(id)heat {
    return NULL;
}
%end
%hook YTPlayerBarController
- (void)setHeatmap:(id)arg1 {
    %orig(NULL);
}
%end
%end

// YTNoSuggestedVideo - https://github.com/bhackel/YTNoSuggestedVideo
%hook YTMainAppVideoPlayerOverlayViewController
- (bool)shouldShowAutonavEndscreen {
    if (IS_ENABLED(@"noSuggestedVideo_enabled")) {
        return false;
    }
    return %orig;
}
%end

// YTTapToSeek - https://github.com/bhackel/YTTapToSeek
%group YTTTS_Tweak
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
    if (IS_ENABLED(@"hideSponsorBlockButton_enabled")) { 
        self.sponsorBlockButton.hidden = YES;
        self.sponsorBlockButton.frame = CGRectZero;
    }
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
// Video Player Options
// Skips content warning before playing *some videos - @PoomSmart
%hook YTPlayabilityResolutionUserActionUIController
- (void)showConfirmAlert { [self confirmAlertDidPressConfirm]; }
%end

// Portrait Fullscreen - @Dayanch96
%group gPortraitFullscreen
%hook YTWatchViewController
- (unsigned long long)allowedFullScreenOrientations {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}
%end
%end

// Disable Double tap to skip chapter - @bhackel
%hook YTDoubleTapToSeekController
- (void)didTwoFingerDoubleTap:(id)arg1 {
    if (IS_ENABLED(@"disableChapterSkip_enabled")) {
        return;
    }
    %orig;
}
%end

// Disable snap to chapter
%hook YTSegmentableInlinePlayerBarView
- (void)didMoveToWindow {
    %orig;
    if (IS_ENABLED(@"snapToChapter_enabled")) {
        self.enableSnapToChapter = NO;
    }
}
%end

// Disable Pinch to zoom
%hook YTColdConfig
- (BOOL)videoZoomFreeZoomEnabledGlobalConfig {
    return IS_ENABLED(@"pinchToZoom_enabled") ? NO : %orig;
}
%end

// Use stock iOS volume HUD
// Use YTColdConfig's method, see https://x.com/PoomSmart/status/1756904290445332653
%group gStockVolumeHUD
%hook YTColdConfig
- (BOOL)iosUseSystemVolumeControlInFullscreen {
    return IS_ENABLED(@"stockVolumeHUD_enabled") ? YES : %orig;
}
%end
%hook UIApplication 
- (void)setSystemVolumeHUDEnabled:(BOOL)arg1 forAudioCategory:(id)arg2 {
        %orig(true, arg2);
}
%end
%end

%hook YTColdConfig
- (BOOL)speedMasterArm2FastForwardWithoutSeekBySliding {
    return IS_ENABLED(@"slideToSeek_enabled") ? NO : %orig;
}
%end

// Disable double tap to seek
%hook YTDoubleTapToSeekController
- (void)enableDoubleTapToSeek:(BOOL)arg1 {
    return IS_ENABLED(@"doubleTapToSeek_disabled") ? %orig(NO) : %orig;
}
%end

// Hide double tap to seek overlay - @arichornlover & @bhackel
%group gHideDoubleTapToSeekOverlay
%hook YTInlinePlayerDoubleTapIndicatorView
%property(nonatomic, strong) CABasicAnimation *uYouEnhancedBlankAlphaAnimation;
%property(nonatomic, strong) CABasicAnimation *uYouEnhancedBlankColorAnimation;
/**
 * @return A clear color animation
 */
%new
- (CABasicAnimation *)uYouEnhancedGetBlankColorAnimation {
    if (!self.uYouEnhancedBlankColorAnimation) {
        // Create a new basic animation for the color property
        self.uYouEnhancedBlankColorAnimation = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
        // Set values to 0 to prevent visibility
        self.uYouEnhancedBlankColorAnimation.fromValue = (id)[UIColor clearColor].CGColor;
        self.uYouEnhancedBlankColorAnimation.toValue = (id)[UIColor clearColor].CGColor;
        self.uYouEnhancedBlankColorAnimation.duration = 0.0;
        self.uYouEnhancedBlankColorAnimation.fillMode = kCAFillModeForwards;
        self.uYouEnhancedBlankColorAnimation.removedOnCompletion = NO;
    }
    return self.uYouEnhancedBlankColorAnimation;
}
// Replace all color animations with a clear one
- (CABasicAnimation *)fillColorAnimation {
    return [self uYouEnhancedGetBlankColorAnimation];
}
- (CABasicAnimation *)earlyBackgroundColorAnimation {
    return [self uYouEnhancedGetBlankColorAnimation];
}
- (CABasicAnimation *)laterBackgroundcolorAnimation {
    return [self uYouEnhancedGetBlankColorAnimation];
}
// Replace the opacity animation with a clear one
- (CABasicAnimation *)alphaAnimation {
    if (!self.uYouEnhancedBlankAlphaAnimation) {
        // Create a new basic animation for the opacity property
        self.uYouEnhancedBlankAlphaAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
        // Set values to 0 to prevent visibility
        self.uYouEnhancedBlankAlphaAnimation.fromValue = @0.0;
        self.uYouEnhancedBlankAlphaAnimation.toValue = @0.0;
        self.uYouEnhancedBlankAlphaAnimation.duration = 0.0;
        self.uYouEnhancedBlankAlphaAnimation.fillMode = kCAFillModeForwards;
        self.uYouEnhancedBlankAlphaAnimation.removedOnCompletion = NO; 
    }
    return self.uYouEnhancedBlankAlphaAnimation;
}
// Remove the screen darkening effect
- (void)layoutSubviews {
    %orig;
    // Set the 0th subview (which darkens the screen) to hidden
    self.subviews[0].hidden = YES;
}
%end
%end

// Disable pull to enter vertical/portrait fullscreen gesture - @bhackel
// This was introduced in version 19.XX
// This only applies to landscape videos
%group gDisablePullToFull
%hook YTWatchPullToFullController
- (BOOL)shouldRecognizeOverscrollEventsFromWatchOverscrollController:(id)arg1 {
    // Get the current player orientation
    YTWatchViewController *watchViewController = self.playerViewSource;
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

// Video Controls Overlay Options
// Hide CC / Hide Autoplay switch / Hide YTMusic Button / Enable Share Button / Enable Save to Playlist Button
%hook YTMainAppControlsOverlayView
- (void)setClosedCaptionsOrSubtitlesButtonAvailable:(BOOL)arg1 { // hide CC button
    return IS_ENABLED(@"hideCC_enabled") ? %orig(NO) : %orig;
}
- (void)setAutoplaySwitchButtonRenderer:(id)arg1 { // hide Autoplay
    if (IS_ENABLED(@"hideAutoplaySwitch_enabled")) {}
    else { return %orig; }
}
- (void)setYoutubeMusicButton:(id)arg1 {
    if (IS_ENABLED(@"hideYTMusicButton_enabled")) {
    } else {
        %orig(arg1);
    }
}
- (void)setShareButtonAvailable:(BOOL)arg1 {
    if (IS_ENABLED(@"enableShareButton_enabled")) {
        %orig(YES);
    } else {
        %orig(NO);
    }
}
- (void)setAddToButtonAvailable:(BOOL)arg1 {
    if (IS_ENABLED(@"enableSaveToButton_enabled")) {
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
    if (IS_ENABLED(@"disableCollapseButton_enabled")) {  
        if (self.watchCollapseButton) {
            [self.watchCollapseButton removeFromSuperview];
        }
    }
}
- (BOOL)watchCollapseButtonHidden {
    if (IS_ENABLED(@"disableCollapseButton_enabled")) {
        return YES;
    } else {
        return %orig;
    }
}
- (void)setWatchCollapseButtonAvailable:(BOOL)available {
    if (IS_ENABLED(@"disableCollapseButton_enabled")) {
    } else {
        %orig(available);
    }
}
%end

// LEGACY VERSION ⚠️
// Hide Fullscreen Button - @arichornlover - PoomSmart's Newer Version of the *YouQuality* tweak breaks when enabling this
%hook YTInlinePlayerBarContainerView
- (void)layoutSubviews {
    %orig; 
    if (IS_ENABLED(@"disableFullscreenButton_enabled")) {
        if (self.exitFullscreenButton) {
            [self.exitFullscreenButton removeFromSuperview];
            self.exitFullscreenButton.frame = CGRectZero;
        }
        if (self.enterFullscreenButton) {
            [self.enterFullscreenButton removeFromSuperview];
            self.enterFullscreenButton.frame = CGRectZero;
        }
        self.fullscreenButtonDisabled = YES;
    }
}
%end

// NEW VERSION
// Hide Fullscreen Button - @arichornlover - UNTESTED!
// %hook YTInlinePlayerBarContainerView
// - (BOOL)fullscreenButtonDisabled { return YES; }
// - (BOOL)canShowFullscreenButton { return NO; }
// - (BOOL)canShowFullscreenButtonExperimental { return NO; }
// - (void)setFullscreenButtonDisabled:(BOOL) // this line should remain disabled for now.
// %end

// Hide HUD Messages
%hook YTHUDMessageView
- (id)initWithMessage:(id)arg1 dismissHandler:(id)arg2 {
    return IS_ENABLED(@"hideHUD_enabled") ? nil : %orig;
}
%end

// Hide Channel Watermark
%hook YTColdConfig
- (BOOL)iosEnableFeaturedChannelWatermarkOverlayFix {
    return IS_ENABLED(@"hideChannelWatermark_enabled") ? NO : %orig;
}
%end
// Hide Channel Watermark (for Backwards Compatibility)
%hook YTAnnotationsViewController
- (void)loadFeaturedChannelWatermark {
    if (IS_ENABLED(@"hideChannelWatermark_enabled")) {}
    else { return %orig; }
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

// Hide Video Title (in Fullscreen) - @arichornlover
%hook YTMainAppControlsOverlayView
- (BOOL)titleViewHidden {
    return IS_ENABLED(@"hideVideoTitle_enabled") ? YES : %orig;
}
%end

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

%hook YTInlinePlayerBarContainerView // Red Progress Bar - Old (Compatible for v17.33.2-v19.10.7)
- (id)quietProgressBarColor {
    return [UIColor redColor];
}
%end

%hook YTPlayerBarRectangleDecorationView // Red Progress Bar - New (Compatible for v19.10.7-latest)
- (void)drawRectangleDecorationWithSideMasks:(CGRect)rect {
    if (IS_ENABLED(@"redProgressBar_enabled")) {
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

// Disable the right panel in fullscreen mode
%hook YTColdConfig
- (BOOL)isLandscapeEngagementPanelEnabled {
    return IS_ENABLED(@"hideRightPanel_enabled") ? NO : %orig;
}
%end

// Shorts Controls Overlay Options
%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    if ((IS_ENABLED(@"hideBuySuperThanks_enabled")) && ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.suggested_action"])) { 
        self.hidden = YES; 
    }

// Hide Header Links under Channel Profile - @arichornlover
    if ((IS_ENABLED(@"hideChannelHeaderLinks_enabled")) && ([self.accessibilityIdentifier isEqualToString:@"eml.channel_header_links"])) {
        self.hidden = YES;
        self.opaque = YES;
        self.userInteractionEnabled = NO;
        [self sizeToFit];
        [self.superview layoutIfNeeded];
        [self setNeedsLayout];
        [self removeFromSuperview];
    }

// Completely Remove the Comment Section under the Video Player - @arichornlover
    if ((IS_ENABLED(@"hideCommentSection_enabled")) && ([self.accessibilityIdentifier isEqualToString:@"id.ui.comments_entry_point_teaser"] 
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
    if ((IS_ENABLED(@"hidePreviewCommentSection_enabled")) && ([self.accessibilityIdentifier isEqualToString:@"id.ui.comments_entry_point_teaser"])) {
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
    if (IS_ENABLED(@"hideSubscriptions_enabled")) {}
    else { return %orig; }
}
%end

/* DISABLED DUE TO CONFLICTS
// Hide Community Posts - @michael-winay, @arichornlover, @iCrazeiOS @PoomSmart & @Dayanch96
%hook YTIElementRenderer
- (NSData *)elementData {
    NSString *description = [self description];
    if (IS_ENABLED(@"hideCommunityPosts_enabled")) {
        if ([description containsString:@"post_base_wrapper.eml"]) {
            if (!cellDividerData) cellDividerData = [NSData dataWithBytes:cellDividerDataBytes length:cellDividerDataBytesLength];
            return cellDividerData;
        }
    }
    return %orig;
}
%end
*/

// Red Subscribe Button - 17.33.2 and up - @arichornlover
%hook ELMContainerNode
- (void)setBackgroundColor:(id)color {
    NSString *description = [self description];
    if (IS_ENABLED(@"redSubscribeButton_enabled")) {
        if ([description containsString:@"eml.compact_subscribe_button"]) {
            color = [UIColor redColor];
        }
    }
    // Hide the Button Containers under the Video Player - 17.33.2 and up - @arichornlover
    if (IS_ENABLED(@"hideButtonContainers_enabled")) {
        if ([description containsString:@"id.video.like.button"] ||
            [description containsString:@"id.video.dislike.button"] ||
            [description containsString:@"id.video.share.button"] ||
            [description containsString:@"id.video.remix.button"] ||
            [description containsString:@"id.ui.add_to.offline.button"]) {
//          self.hidden = YES;
        }
    }
    %orig(color);
}
%end

// LEGACY VERSION ⚠️
// Hide the (Connect / Thanks / Save / Report) Buttons under the Video Player - 17.33.2 and up - @arichornlover (inspired by @PoomSmart's version)
%hook _ASDisplayView
- (void)layoutSubviews {
    %orig;
    BOOL hideConnectButton = IS_ENABLED(@"hideConnectButton_enabled");
    BOOL hideThanksButton = IS_ENABLED(@"hideThanksButton_enabled");
    BOOL hideSaveToPlaylistButton = IS_ENABLED(@"hideSaveToPlaylistButton_enabled");
    BOOL hideReportButton = IS_ENABLED(@"hideReportButton_enabled");

    for (UIView *subview in self.subviews) {
        if ([subview.accessibilityLabel isEqualToString:@"connect account"]) {
            subview.hidden = hideConnectButton;
        } else if ([subview.accessibilityLabel isEqualToString:@"Thanks"]) {
            subview.hidden = hideThanksButton;
        } else if ([subview.accessibilityLabel isEqualToString:@"Save to playlist"]) {
            subview.hidden = hideSaveToPlaylistButton;
        } else if ([subview.accessibilityLabel isEqualToString:@"Report"]) {
            subview.hidden = hideReportButton;
        }
    }
}
%end

// UPDATED VERSION
// Hide the (Connect / Share / Remix / Thanks / Download / Clip / Save / Report) Buttons under the Video Player - 17.33.2 and up - @PoomSmart (inspired by @arichornlover) - METHOD BROKE Server-Side on May 14th 2024
static BOOL findCell(ASNodeController *nodeController, NSArray <NSString *> *identifiers) {
    for (id child in [nodeController children]) {
        if ([child isKindOfClass:%c(ELMNodeController)]) {
            NSArray <ELMComponent *> *elmChildren = [(ELMNodeController *)child children];
            for (ELMComponent *elmChild in elmChildren) {
                for (NSString *identifier in identifiers) {
                    if ([[elmChild description] containsString:identifier])
                        return YES;
                }
            }
        }

        if ([child isKindOfClass:%c(ASNodeController)]) {
            ASDisplayNode *childNode = ((ASNodeController *)child).node; // ELMContainerNode
            NSArray *yogaChildren = childNode.yogaChildren;
            for (ASDisplayNode *displayNode in yogaChildren) {
                if ([identifiers containsObject:displayNode.accessibilityIdentifier])
                    return YES;
            }

            return findCell(child, identifiers);
        }

        return NO;
    }
    return NO;
}

%hook ASCollectionView // This stopped working on May 14th 2024 due to a Server-Side Change from YouTube.

- (CGSize)sizeForElement:(ASCollectionElement *)element {
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.scrollable_action_bar"]) {
        ASCellNode *node = [element node];
        ASNodeController *nodeController = [node controller];
        if (IS_ENABLED(@"hideShareButton_enabled") && findCell(nodeController, @[@"id.video.share.button"])) {
            return CGSizeZero;
        }

        if (IS_ENABLED(@"hideRemixButton_enabled") && findCell(nodeController, @[@"id.video.remix.button"])) {
            return CGSizeZero;
        }

        if (IS_ENABLED(@"hideThanksButton_enabled") && findCell(nodeController, @[@"Thanks"])) {
            return CGSizeZero;
        }

        if (IS_ENABLED(@"hideClipButton_enabled") && findCell(nodeController, @[@"clip_button.eml"])) {
            return CGSizeZero;
        }

        if (IS_ENABLED(@"hideDownloadButton_enabled") && findCell(nodeController, @[@"id.ui.add_to.offline.button"])) {
            return CGSizeZero;
        }

        if (IS_ENABLED(@"hideCommentSection_enabled") && findCell(nodeController, @[@"id.ui.carousel_header"])) {
            return CGSizeZero;
        }
    }
    return %orig;
}

%end

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

// Auto-Hide Home Bar - @arichornlover
%group gAutoHideHomeBar
%hook UIViewController
- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}
%end
%end

// YT startup animation
%hook YTColdConfig
- (BOOL)mainAppCoreClientIosEnableStartupAnimation {
    return IS_ENABLED(@"ytStartupAnimation_enabled") ? YES : NO;
}
%end

// Disable hints - https://github.com/LillieH001/YouTube-Reborn/blob/v4/
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
- (void)setFeedHeaderScrollMode:(int)arg1 { %orig(0); }
%end

// Hide the chip bar under the video player?
// %hook YTChipCloudCell
// - (void)didMoveToWindow {
//     %orig;
//     self.hidden = YES;
// }
// %end
%end

// Remove “Play next in queue” from the menu (@PoomSmart) - qnblackcat/uYouPlus#1138
%hook YTMenuItemVisibilityHandler
- (BOOL)shouldShowServiceItemRenderer:(YTIMenuConditionalServiceItemRenderer *)renderer {
    return IS_ENABLED(@"hidePlayNextInQueue_enabled") && renderer.icon.iconType == 251 ? NO : %orig;
}
%end

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

// Hide Videos in Fullscreen - @arichornlover
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

// iPhone Layout - @LillieH1000 & @arichornlover
%group giPhoneLayout
%hook UIDevice
- (long long)userInterfaceIdiom {
    return NO;
} 
%end
%hook UIStatusBarStyleAttributes
- (long long)idiom {
    return YES;
} 
%end
%hook UIKBTree
- (long long)nativeIdiom {
    return YES;
} 
%end
%hook UIKBRenderer
- (long long)assetIdiom {
    return NO;
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
    if (IS_ENABLED(@"hideYouTubeLogo_enabled")) {
        %init(gHideYouTubeLogo);
    }
    if (IS_ENABLED(@"centerYouTubeLogo_enabled")) {
        %init(gCenterYouTubeLogo);
    }
    if (IS_ENABLED(@"hideSubscriptionsNotificationBadge_enabled")) {
        %init(gHideSubscriptionsNotificationBadge);
    }
    if (IS_ENABLED(@"hidePreviousAndNextButton_enabled")) {
        %init(gHidePreviousAndNextButton);
    }
    if (IS_ENABLED(@"hideOverlayDarkBackground_enabled")) {
        %init(gHideOverlayDarkBackground);
    }
    if (IS_ENABLED(@"hideVideoPlayerShadowOverlayButtons_enabled")) {
        %init(gHideVideoPlayerShadowOverlayButtons);
    }
    if (IS_ENABLED(@"disableHints_enabled")) {
        %init(gDisableHints);
    }
    if (IS_ENABLED(@"redProgressBar_enabled")) {
        %init(gRedProgressBar);
    }
    if (IS_ENABLED(@"stickNavigationBar_enabled")) {
        %init(gStickNavigationBar);
    }
    if (IS_ENABLED(@"hideChipBar_enabled")) {
        %init(gHideChipBar);
    }
    if (IS_ENABLED(@"portraitFullscreen_enabled")) {
        %init(gPortraitFullscreen);
    }
    if (IS_ENABLED(@"hideFullscreenActions_enabled")) {
        %init(hideFullscreenActions);
    }
    if (IS_ENABLED(@"iPhoneLayout_enabled") && (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad)) {
        %init(giPhoneLayout);
    }
    if (IS_ENABLED(@"stockVolumeHUD_enabled")) {
        %init(gStockVolumeHUD);
    }
    if (IS_ENABLED(@"hideHeatwaves_enabled")) {
        %init(gHideHeatwaves);
    }
    if (IS_ENABLED(@"noRelatedWatchNexts_enabled")) {
        %init(gNoRelatedWatchNexts);
    }
    if (IS_ENABLED(@"noVideosInFullscreen_enabled")) {
        %init(gNoVideosInFullscreen);
    }
    if (IS_ENABLED(@"classicVideoPlayer_enabled")) {
        %init(gClassicVideoPlayer);
    }
    if (IS_ENABLED(@"fixLowContrastMode_enabled")) {
        %init(gFixLowContrastMode);
    }
    if (IS_ENABLED(@"disableModernButtons_enabled")) {
        %init(gDisableModernButtons);
    }
    if (IS_ENABLED(@"disableRoundedHints_enabled")) {
        %init(gDisableRoundedHints);
    }
    if (IS_ENABLED(@"disableModernFlags_enabled")) {
        %init(gDisableModernFlags);
    }
    if (IS_ENABLED(@"disableAmbientMode_enabled")) {
        %init(gDisableAmbientMode);
    }
    if (IS_ENABLED(@"disableAccountSection_enabled")) {
        %init(gDisableAccountSection);
    }
    if (IS_ENABLED(@"disableAutoplaySection_enabled")) {
        %init(gDisableAutoplaySection);
    }
    if (IS_ENABLED(@"disableTryNewFeaturesSection_enabled")) {
        %init(gDisableTryNewFeaturesSection);
    }
    if (IS_ENABLED(@"disableVideoQualityPreferencesSection_enabled")) {
        %init(gDisableVideoQualityPreferencesSection);
    }
    if (IS_ENABLED(@"disableNotificationsSection_enabled")) {
        %init(gDisableNotificationsSection);
    }
    if (IS_ENABLED(@"disableManageAllHistorySection_enabled")) {
        %init(gDisableManageAllHistorySection);
    }
    if (IS_ENABLED(@"disableYourDataInYouTubeSection_enabled")) {
        %init(gDisableYourDataInYouTubeSection);
    }
    if (IS_ENABLED(@"disablePrivacySection_enabled")) {
        %init(gDisablePrivacySection);
    }
    if (IS_ENABLED(@"disableLiveChatSection_enabled")) {
        %init(gDisableLiveChatSection);
    }
    if (IS_ENABLED(@"YTTapToSeek_enabled")) {
        %init(YTTTS_Tweak);
    }
    if (IS_ENABLED(@"hidePremiumPromos_enabled")) {
        %init(gHidePremiumPromos);
    }
    if (IS_ENABLED(@"youTabFakePremium_enabled")) {
        %init(gFakePremium);
    }
    if (IS_ENABLED(@"disablePullToFull_enabled")) {
        %init(gDisablePullToFull);
    }
    if (IS_ENABLED(@"uYouAdBlockingWorkaroundLite_enabled")) {
        %init(uYouAdBlockingWorkaroundLite);
    }
    if (IS_ENABLED(@"uYouAdBlockingWorkaround_enabled")) {
        %init(uYouAdBlockingWorkaround);
    }
    if (IS_ENABLED(@"hideHomeTab_enabled")) {
        %init(gHideHomeTab);
    }
    if (IS_ENABLED(@"autoHideHomeBar_enabled")) {
        %init(gAutoHideHomeBar);
    }
    if (IS_ENABLED(@"hideDoubleTapToSeekOverlay_enabled")) {
        %init(gHideDoubleTapToSeekOverlay);
    }
    if (IS_ENABLED(@"shortsQualityPicker_enabled")) {
        %init(gShortsQualityPicker);
    }
    if (IS_ENABLED(@"fixCasting_enabled")) {
        %init(gFixCasting);
    }

    // YTNoModernUI - @arichorn
    BOOL ytNoModernUIEnabled = IS_ENABLED(@"ytNoModernUI_enabled");
    if (ytNoModernUIEnabled) {
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        [userDefaults setBool:NO forKey:@"enableVersionSpoofer_enabled"];
    } else {
        BOOL enableVersionSpooferEnabled = IS_ENABLED(@"enableVersionSpoofer_enabled");

        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        [userDefaults setBool:enableVersionSpooferEnabled forKey:@"enableVersionSpoofer_enabled"];
    }
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setBool:ytNoModernUIEnabled ? ytNoModernUIEnabled : [userDefaults boolForKey:@"fixLowContrastMode_enabled"] forKey:@"fixLowContrastMode_enabled"];
    [userDefaults setBool:ytNoModernUIEnabled ? ytNoModernUIEnabled : [userDefaults boolForKey:@"disableModernButtons_enabled"] forKey:@"disableModernButtons_enabled"];
    [userDefaults setBool:ytNoModernUIEnabled ? ytNoModernUIEnabled : [userDefaults boolForKey:@"disableRoundedHints_enabled"] forKey:@"disableRoundedHints_enabled"];
    [userDefaults setBool:ytNoModernUIEnabled ? ytNoModernUIEnabled : [userDefaults boolForKey:@"disableModernFlags_enabled"] forKey:@"disableModernFlags_enabled"];
    [userDefaults setBool:ytNoModernUIEnabled ? ytNoModernUIEnabled : [userDefaults boolForKey:@"disableAmbientMode_enabled"] forKey:@"disableAmbientMode_enabled"];
    [userDefaults setBool:ytNoModernUIEnabled ? ytNoModernUIEnabled : [userDefaults boolForKey:@"redProgressBar_enabled"] forKey:@"redProgressBar_enabled"];

    // Change the default value of some options
    NSArray *allKeys = [[[NSUserDefaults standardUserDefaults] dictionaryRepresentation] allKeys];
    if (![allKeys containsObject:@"hidePlayNextInQueue_enabled"]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"hidePlayNextInQueue_enabled"];
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
    if (![allKeys containsObject:@"uYouAdBlockingWorkaroundLite_enabled"]) { 
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"uYouAdBlockingWorkaroundLite_enabled"];
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"uYouAdBlockingWorkaround_enabled"];
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"removeYouTubeAds"];
    }
    if (![allKeys containsObject:@"uYouAdBlockingWorkaround_enabled"]) { 
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"uYouAdBlockingWorkaroundLite_enabled"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"uYouAdBlockingWorkaround_enabled"];
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
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"fixCasting_enabled"]; 
    }
    // Set new grouped settings UI to default enabled
    if (![allKeys containsObject:@"newSettingsUI_enabled"]) { 
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"newSettingsUI_enabled"]; 
    }
}
