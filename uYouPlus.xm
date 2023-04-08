#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <sys/utsname.h>
#import <substrate.h>
#import "Header.h"
#import "Tweaks/YouTubeHeader/YTVideoQualitySwitchOriginalController.h"
#import "Tweaks/YouTubeHeader/YTPlayerViewController.h"
#import "Tweaks/YouTubeHeader/YTWatchController.h"
#import "Tweaks/YouTubeHeader/YTIGuideResponse.h"
#import "Tweaks/YouTubeHeader/YTIGuideResponseSupportedRenderers.h"
#import "Tweaks/YouTubeHeader/YTIPivotBarSupportedRenderers.h"
#import "Tweaks/YouTubeHeader/YTIPivotBarRenderer.h"
#import "Tweaks/YouTubeHeader/YTIBrowseRequest.h"
#import "Tweaks/YouTubeHeader/YTColorPalette.h"
#import "Tweaks/YouTubeHeader/YTCommonColorPalette.h"
#import "Tweaks/YouTubeHeader/ASCollectionView.h"
#import "Tweaks/YouTubeHeader/YTPlayerOverlay.h"
#import "Tweaks/YouTubeHeader/YTPlayerOverlayProvider.h"
#import "Tweaks/YouTubeHeader/YTReelWatchPlaybackOverlayView.h"
#import "Tweaks/YouTubeHeader/YTReelPlayerBottomButton.h"
#import "Tweaks/YouTubeHeader/YTReelPlayerViewController.h"
#import "Tweaks/YouTubeHeader/YTAlertView.h"
#import "Tweaks/YouTubeHeader/YTISectionListRenderer.h"
#import "Tweaks/YouTubeHeader/YTPivotBarItemView.h"

// Tweak's bundle for Localizations support - @PoomSmart - https://github.com/PoomSmart/YouPiP/commit/aea2473f64c75d73cab713e1e2d5d0a77675024f
NSBundle *uYouPlusBundle() {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
 	dispatch_once(&onceToken, ^{
        NSString *tweakBundlePath = [[NSBundle mainBundle] pathForResource:@"uYouPlus" ofType:@"bundle"];
        if (tweakBundlePath)
            bundle = [NSBundle bundleWithPath:tweakBundlePath];
        else
            bundle = [NSBundle bundleWithPath:@"/Library/Application Support/uYouPlus.bundle"];
    });
    return bundle;
}
NSBundle *tweakBundle = uYouPlusBundle();

// Keychain patching
static NSString *accessGroupID() {
    NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys:
                           (__bridge NSString *)kSecClassGenericPassword, (__bridge NSString *)kSecClass,
                           @"bundleSeedID", kSecAttrAccount,
                           @"", kSecAttrService,
                           (id)kCFBooleanTrue, kSecReturnAttributes,
                           nil];
    CFDictionaryRef result = nil;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
    if (status == errSecItemNotFound)
        status = SecItemAdd((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
        if (status != errSecSuccess)
            return nil;
    NSString *accessGroup = [(__bridge NSDictionary *)result objectForKey:(__bridge NSString *)kSecAttrAccessGroup];

    return accessGroup;
}

//
static BOOL IsEnabled(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}
static BOOL isDarkMode() {
    return ([[NSUserDefaults standardUserDefaults] integerForKey:@"page_style"] == 1);
}
static BOOL oledDarkTheme() {
    return ([[NSUserDefaults standardUserDefaults] integerForKey:@"appTheme"] == 1);
}
static BOOL oldDarkTheme() {
    return ([[NSUserDefaults standardUserDefaults] integerForKey:@"appTheme"] == 2);
}
static int colorContrastMode() {
    return [[NSUserDefaults standardUserDefaults] integerForKey:@"lcmColor"];
}
static BOOL defaultContrastMode() {
    return IsEnabled(@"lowContrastMode_enabled") && colorContrastMode() == 0;
}
static BOOL redContrastMode() {
    return IsEnabled(@"lowContrastMode_enabled") && colorContrastMode() == 1;
}
static BOOL blueContrastMode() {
    return IsEnabled(@"lowContrastMode_enabled") && colorContrastMode() == 2;
}
static BOOL greenContrastMode() {
    return IsEnabled(@"lowContrastMode_enabled") && colorContrastMode() == 3;
}
static BOOL yellowContrastMode() {
    return IsEnabled(@"lowContrastMode_enabled") && colorContrastMode() == 4;
}
static BOOL orangeContrastMode() {
    return IsEnabled(@"lowContrastMode_enabled") && colorContrastMode() == 5;
}
static BOOL purpleContrastMode() {
   return IsEnabled(@"lowContrastMode_enabled") && colorContrastMode() == 6;
}
static BOOL pinkContrastMode() {
    return IsEnabled(@"lowContrastMode_enabled") && colorContrastMode() == 7;
}

//
# pragma mark - uYou's patches
// Workaround for https://github.com/MiRO92/uYou-for-YouTube/issues/94
%hook UIResponder
%new
- (id)entry {
    return nil;
}
%end

// Workaround for https://github.com/MiRO92/uYou-for-YouTube/issues/140
%hook YTLocalPlaybackController
%new
- (id)activeVideoController {
    return [self activeVideo];
}
%end

// Workaround for qnblackcat/uYouPlus#10
%hook boolSettingsVC
- (instancetype)initWithTitle:(NSString *)title sections:(NSArray *)sections footer:(NSString *)footer {
    if (@available(iOS 15, *))
        if (![self valueForKey:@"_lastNotifiedTraitCollection"])
            [self setValue:[UITraitCollection currentTraitCollection] forKey:@"_lastNotifiedTraitCollection"];
    return %orig;
}
%end

// Prevent uYou player bar from showing when not playing downloaded media
%hook PlayerManager
- (void)pause {
    if (isnan([self progress]))
        return;
    %orig;
}
%end

// Workaround for issue #54
%hook YTMainAppVideoPlayerOverlayViewController
- (void)updateRelatedVideos {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"relatedVideosAtTheEndOfYTVideos"] == NO) {}
    else { return %orig; }
}
%end

// Workaround for qnblackcat/uYouPlus#253, qnblackcat/uYouPlus#170
%hook YTReelWatchPlaybackOverlayView
- (YTQTMButton *)overflowButton {
    if ([self respondsToSelector:@selector(orderedRightSideButtons)] &&
        [self orderedRightSideButtons].count != 0)
        return [self orderedRightSideButtons][0];
    return %orig;
}
%end

%hook YTReelContentView
- (void)didTapOverflowButton:(id)sender {}
%end

%subclass YTReelPlayerBottomButton : YTReelPlayerButton
%end

%hook NSLayoutConstraint
+ (instancetype)constraintWithItem:(UIView *)view1
                         attribute:(NSLayoutAttribute)attr1
                         relatedBy:(NSLayoutRelation)relation
                            toItem:(UIView *)view2
                         attribute:(NSLayoutAttribute)attr2
                        multiplier:(CGFloat)multiplier
                          constant:(CGFloat)c {
    if (![view1 isKindOfClass:%c(YTReelPlayerBottomButton)] &&
        ![view1.accessibilityIdentifier isEqualToString:@"com.miro.uyou"])
        return %orig;
    if (!view2) {
        view1.hidden = YES;
        return [NSLayoutConstraint alloc];
    }
    YTReelPlayerBottomButton *uYouButton = (YTReelPlayerBottomButton *)view1;
    YTReelPlayerBottomButton *topButton = (YTReelPlayerBottomButton *)view2;
    NSString *uYouButtonTitle =
        [view2.accessibilityIdentifier isEqualToString:@"com.miro.uyou"]
            ? @"uYou"
            : @"uYouLocal";
    uYouButton.accessibilityLabel = uYouButtonTitle;
    uYouButton.uppercaseTitle = NO;
    [uYouButton setTitle:uYouButtonTitle forState:UIControlStateNormal];
    [uYouButton
        setTitleTypeKind:MSHookIvar<NSInteger>(topButton, "_typeKind")
            typeVariant:MSHookIvar<NSInteger>(topButton, "_typeVariant")];
    uYouButton.applyRightSideLayoutImageSize = topButton.applyRightSideLayoutImageSize;
    uYouButton.buttonImageTitlePadding = topButton.buttonImageTitlePadding;
    uYouButton.buttonLayoutStyle = topButton.buttonLayoutStyle;
    uYouButton.sizeWithPaddingAndInsets = topButton.sizeWithPaddingAndInsets;
    uYouButton.verticalContentPadding = topButton.verticalContentPadding;
    return %orig;
}
%end

// iOS 16 uYou crash fix - @level3tjg: https://github.com/qnblackcat/uYouPlus/pull/224
%group iOS16
%hook OBPrivacyLinkButton
%new
- (instancetype)initWithCaption:(NSString *)caption
                     buttonText:(NSString *)buttonText
                          image:(UIImage *)image
                      imageSize:(CGSize)imageSize
                   useLargeIcon:(BOOL)useLargeIcon {
  return [self initWithCaption:caption
                    buttonText:buttonText
                         image:image
                     imageSize:imageSize
                  useLargeIcon:useLargeIcon
               displayLanguage:[NSLocale currentLocale].languageCode];
}
%end
%end

// Workaround for qnblackcat/uYouPlus#617
static BOOL didFinishLaunching;

%hook YTAppDelegate
- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions {
    didFinishLaunching = %orig;
    self.downloadsVC = [self.downloadsVC init];

    if (IsEnabled(@"flex_enabled")) {
        [[%c(FLEXManager) performSelector:@selector(sharedManager)] performSelector:@selector(showExplorer)];
    }

    return didFinishLaunching;
}
- (void)appWillResignActive:(id)arg1 {
    %orig;
         if (IsEnabled(@"flex_enabled")) {
        [[%c(FLEXManager) performSelector:@selector(sharedManager)] performSelector:@selector(showExplorer)];
    }
}
%end

%hook DownloadsPagerVC
- (instancetype)init {
    return didFinishLaunching ? %orig : self;
}
%end

// uYou's slide settings?
%hook FRPSliderCell
- (void)didMoveToWindow {
    %orig;
    if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        MSHookIvar<UILabel *>(self, "_lLabel").textColor = [UIColor whiteColor];
        MSHookIvar<UILabel *>(self, "_rLabel").textColor = [UIColor whiteColor];
        MSHookIvar<UILabel *>(self, "_cLabel").textColor = [UIColor whiteColor];
    }
}
%end

// Remove uYou download button in playlists
// https://github.com/qnblackcat/uYouPlus/issues/798#issuecomment-1364853420
%hook YTPlaylistHeaderViewController
- (void)viewDidLoad {
    %orig;
    self.downloadsButton.hidden = YES;
}
%end

# pragma mark - YouTube's patches
// Workaround for MiRO92/uYou-for-YouTube#12, qnblackcat/uYouPlus#263
%hook YTDataUtils
+ (NSMutableDictionary *)spamSignalsDictionary {
    return nil;
}
%end

// Fix login for YouTube 17.33.2 and higher
%hook SSOKeychainCore
+ (NSString *)accessGroup {
    return accessGroupID();
}
+ (NSString *)sharedAccessGroup {
    return accessGroupID();
}
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

// Hide YouTube annoying banner in Home page? - @MiRO92 - YTNoShorts: https://github.com/MiRO92/YTNoShorts
%hook YTAsyncCollectionView
- (id)cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = %orig;
    if ([cell isKindOfClass:NSClassFromString(@"_ASCollectionViewCell")]) {
        _ASCollectionViewCell *cell = %orig;
        if ([cell respondsToSelector:@selector(node)]) {
            if ([[[cell node] accessibilityIdentifier] isEqualToString:@"statement_banner.view"]) { [self removeShortsAndFeaturesAdsAtIndexPath:indexPath]; }
            if ([[[cell node] accessibilityIdentifier] isEqualToString:@"compact.view"]) { [self removeShortsAndFeaturesAdsAtIndexPath:indexPath]; }
            // if ([[[cell node] accessibilityIdentifier] isEqualToString:@"id.ui.video_metadata_carousel"]) { [self removeShortsAndFeaturesAdsAtIndexPath:indexPath]; }
        }
    }
    return %orig;
}
%new
- (void)removeShortsAndFeaturesAdsAtIndexPath:(NSIndexPath *)indexPath {
        [self deleteItemsAtIndexPaths:[NSArray arrayWithObject:indexPath]];
}
%end

# pragma mark - Tweaks
// IAmYouTube - https://github.com/PoomSmart/IAmYouTube/
%hook YTVersionUtils
+ (NSString *)appName { return YT_NAME; }
+ (NSString *)appID { return YT_BUNDLE_ID; }
%end

%hook GCKBUtils
+ (NSString *)appIdentifier { return YT_BUNDLE_ID; }
%end

%hook GPCDeviceInfo
+ (NSString *)bundleId { return YT_BUNDLE_ID; }
%end

%hook OGLBundle
+ (NSString *)shortAppName { return YT_NAME; }
%end

%hook GVROverlayView
+ (NSString *)appName { return YT_NAME; }
%end

%hook OGLPhenotypeFlagServiceImpl
- (NSString *)bundleId { return YT_BUNDLE_ID; }
%end

%hook APMAEU
+ (BOOL)isFAS { return YES; }
%end

%hook GULAppEnvironmentUtil
+ (BOOL)isFromAppStore { return YES; }
%end

%hook SSOConfiguration
- (id)initWithClientID:(id)clientID supportedAccountServices:(id)supportedAccountServices {
    self = %orig;
    [self setValue:YT_NAME forKey:@"_shortAppName"];
    [self setValue:YT_BUNDLE_ID forKey:@"_applicationIdentifier"];
    return self;
}
%end

%hook NSBundle
- (NSString *)bundleIdentifier {
    NSArray *address = [NSThread callStackReturnAddresses];
    Dl_info info = {0};
    if (dladdr((void *)[address[2] longLongValue], &info) == 0)
        return %orig;
    NSString *path = [NSString stringWithUTF8String:info.dli_fname];
    if ([path hasPrefix:NSBundle.mainBundle.bundlePath])
        return YT_BUNDLE_ID;
    return %orig;
}
- (id)objectForInfoDictionaryKey:(NSString *)key {
    if ([key isEqualToString:@"CFBundleIdentifier"])
        return YT_BUNDLE_ID;
    if ([key isEqualToString:@"CFBundleDisplayName"] || [key isEqualToString:@"CFBundleName"])
        return YT_NAME;
    return %orig;
}
// Fix Google Sign in by @PoomSmart and @level3tjg (qnblackcat/uYouPlus#684)
- (NSDictionary *)infoDictionary {
    NSMutableDictionary *info = %orig.mutableCopy;
    NSString *altBundleIdentifier = info[@"ALTBundleIdentifier"];
    if (altBundleIdentifier) info[@"CFBundleIdentifier"] = altBundleIdentifier;
    return info;
}
%end

// YTMiniPlayerEnabler: https://github.com/level3tjg/YTMiniplayerEnabler/
%hook YTWatchMiniBarViewController
- (void)updateMiniBarPlayerStateFromRenderer {
    if (IsEnabled(@"ytMiniPlayer_enabled")) {}
    else { return %orig; }
}
%end

// YTAutoFullScreen: https://github.com/PoomSmart/YTAutoFullScreen/
%hook YTPlayerViewController
- (void)loadWithPlayerTransition:(id)arg1 playbackConfig:(id)arg2 {
    %orig;
    if (IsEnabled(@"autoFull_enabled"))
        [NSTimer scheduledTimerWithTimeInterval:0.75 target:self selector:@selector(autoFullscreen) userInfo:nil repeats:NO];
}
%new
- (void)autoFullscreen {
    YTWatchController *watchController = [self valueForKey:@"_UIDelegate"];
    [watchController showFullScreen];
}
%end

// YTNoHoverCards: https://github.com/level3tjg/YTNoHoverCards
%hook YTCreatorEndscreenView
- (void)setHidden:(BOOL)hidden {
    if (IsEnabled(@"hideHoverCards_enabled"))
        hidden = YES;
    %orig;
}
%end
 
//YTCastConfirm: https://github.com/JamieBerghmans/YTCastConfirm
%hook MDXPlaybackRouteButtonController
- (void)didPressButton:(id)arg1 {
    if (IsEnabled(@"castConfirm_enabled")) {
        NSBundle *tweakBundle = uYouPlusBundle();
        YTAlertView *alertView = [%c(YTAlertView) confirmationDialogWithAction:^{
            %orig;
        } actionTitle:LOC(@"MSG_YES")];
        alertView.title = LOC(@"CASTING");
        alertView.subtitle = LOC(@"MSG_ARE_YOU_SURE");
        [alertView show];
	} else {
    return %orig;
    }
}
%end

// Hide search ads by @PoomSmart - https://github.com/PoomSmart/YouTube-X
%hook YTIElementRenderer
- (NSData *)elementData {
    if (self.hasCompatibilityOptions && self.compatibilityOptions.hasAdLoggingData)
        return nil;
    return %orig;
}
%end

%hook YTSectionListViewController

- (void)loadWithModel:(YTISectionListRenderer *)model {
    NSMutableArray <YTISectionListSupportedRenderers *> *contentsArray = model.contentsArray;
    NSIndexSet *removeIndexes = [contentsArray indexesOfObjectsPassingTest:^BOOL(YTISectionListSupportedRenderers *renderers, NSUInteger idx, BOOL *stop) {
        YTIItemSectionRenderer *sectionRenderer = renderers.itemSectionRenderer;
        YTIItemSectionSupportedRenderers *firstObject = [sectionRenderer.contentsArray firstObject];
        return firstObject.hasPromotedVideoRenderer || firstObject.hasCompactPromotedVideoRenderer || firstObject.hasPromotedVideoInlineMutedRenderer;
    }];
    [contentsArray removeObjectsAtIndexes:removeIndexes];
    %orig;
}

%end

// YTClassicVideoQuality: https://github.com/PoomSmart/YTClassicVideoQuality
%hook YTVideoQualitySwitchControllerFactory
- (id)videoQualitySwitchControllerWithParentResponder:(id)responder {
    Class originalClass = %c(YTVideoQualitySwitchOriginalController);
    return originalClass ? [[originalClass alloc] initWithParentResponder:responder] : %orig;
}
%end

// A/B flags
%hook YTColdConfig 
- (BOOL)respectDeviceCaptionSetting { return NO; } // YouRememberCaption: https://poomsmart.github.io/repo/depictions/youremembercaption.html
- (BOOL)isLandscapeEngagementPanelSwipeRightToDismissEnabled { return YES; } // Swipe right to dismiss the right panel in fullscreen mode
- (BOOL)mainAppCoreClientIosTransientVisualGlitchInPivotBarFix { return NO; } // Fix uYou's label glitching - qnblackcat/uYouPlus#552
%end

// Hide Upgrade Dialog
%hook YTGlobalConfig
- (BOOL)shouldBlockUpgradeDialog { return YES;}
- (BOOL)shouldForceUpgrade { return NO;}
- (BOOL)shouldShowUpgrade { return NO;}
- (BOOL)shouldShowUpgradeDialog { return NO;}
%end

// Disable Autoplay Settings Section - @qnblackcat
%hook YTSettingsSectionItemManager
- (void)updateAutoplaySectionWithEntry:(id)arg1 {}
%end

%group gDisableWifiRelatedSettings
%hook YTSettingsSectionItemManager
- (void)updateNotificationSectionWithEntry:(id)arg1 {} // Notifications
- (void)updateHistorySectionWithEntry:(id)arg1 {} // History
- (void)updatePrivacySectionWithEntry:(id)arg1 {} // Privacy
- (void)updateHistoryAndPrivacySectionWithEntry:(id)arg1 {} // History & Privacy
- (void)updateLiveChatSectionWithEntry:(id)arg1 {} // Live chat
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

// YTShortsProgress - @PoomSmart - https://github.com/PoomSmart/YTShortsProgress
%hook YTReelPlayerViewController
- (BOOL)shouldEnablePlayerBar { return YES; }
- (BOOL)shouldAlwaysEnablePlayerBar { return YES; }
- (BOOL)shouldEnablePlayerBarOnlyOnPause { return NO; }
%end

%hook YTReelPlayerViewControllerSub
- (BOOL)shouldEnablePlayerBar { return YES; }
- (BOOL)shouldAlwaysEnablePlayerBar { return YES; }
- (BOOL)shouldEnablePlayerBarOnlyOnPause { return NO; }
%end

%hook YTColdConfig
- (BOOL)iosEnableVideoPlayerScrubber { return YES; }
- (BOOL)mobileShortsTabInlined { return YES; }
%end

%hook YTHotConfig
- (BOOL)enablePlayerBarForVerticalVideoWhenControlsHiddenInFullscreen { return YES; }
%end

// YTNoModernUI - arichorn
%group gYTNoModernUI
%hook YTColdConfig
// Disable Modern Content - YTNoModernUI
- (BOOL)creatorClientConfigEnableStudioModernizedMdeThumbnailPickerForClient { return NO; }
- (BOOL)cxClientEnableModernizedActionSheet { return NO; }
- (BOOL)enableClientShortsSheetsModernization { return NO; }
- (BOOL)enableTimestampModernizationForNative { return NO; }
- (BOOL)mainAppCoreClientIosEnableModernOssPage { return NO; }
- (BOOL)uiSystemsClientGlobalConfigEnableModernButtonsForNative { return NO; }
- (BOOL)uiSystemsClientGlobalConfigEnableModernButtonsForNativeLongTail { return NO; }
- (BOOL)uiSystemsClientGlobalConfigEnableModernTabsForNative { return NO; }
- (BOOL)uiSystemsClientGlobalConfigIosEnableSnackbarModernization { return NO; }
// Disable Rounded Content - YTNoModernUI
- (BOOL)iosEnableRoundedSearchBar { return NO; }
- (BOOL)enableIosRoundedSearchBar { return NO; }
- (BOOL)iosDownloadsPageRoundedThumbs { return NO; }
- (BOOL)iosRoundedSearchBarSuggestZeroPadding { return NO; }
- (BOOL)uiSystemsClientGlobalConfigEnableRoundedThumbnailsForNative { return NO; }
- (BOOL)uiSystemsClientGlobalConfigEnableRoundedThumbnailsForNativeLongTail { return NO; }
- (BOOL)uiSystemsClientGlobalConfigEnableRoundedTimestampForNative { return NO; }
- (BOOL)uiSystemsClientGlobalConfigEnableRoundedDialogForNative { return NO; }
// Disable Darker Dark Mode - YTNoModernUI
- (BOOL)enableDarkerDarkMode { return NO; }
- (BOOL)useDarkerPaletteBgColorForElements { return NO; }
- (BOOL)useDarkerPaletteTextColorForElements { return NO; }
- (BOOL)modernizeElementsTextColor { return NO; }
- (BOOL)modernizeElementsBgColor { return NO; }
- (BOOL)modernizeCollectionLockups { return NO; }
- (BOOL)uiSystemsClientGlobalConfigUseDarkerPaletteTextColorForNative { return NO; }
- (BOOL)uiSystemsClientGlobalConfigUseDarkerPaletteBgColorForNative { return NO; }
// Disable Ambient Mode
- (BOOL)disableCinematicForLowPowerMode { return NO; }
- (BOOL)enableCinematicContainer { return NO; }
- (BOOL)enableCinematicContainerOnClient { return NO; }
- (BOOL)enableCinematicContainerOnTablet { return NO; }
- (BOOL)iosCinematicContainerClientImprovement { return NO; }
- (BOOL)iosEnableGhostCardInlineTitleCinematicContainerFix { return NO; }
- (BOOL)mainAppCoreClientEnableClientCinematicPlaylists { return NO; }
- (BOOL)mainAppCoreClientEnableClientCinematicPlaylistsPostMvp { return NO; }
- (BOOL)mainAppCoreClientEnableClientCinematicTablets { return NO; }
// 16.42.3 Styled YouTube Channel Page Interface - YTNoModernUI
- (BOOL)channelsClientConfigIosChannelNavRestructuring { return NO; }
%end
%end

// Hide YouTube Logo
%group gHideYouTubeLogo
%hook YTHeaderLogoController
- (YTHeaderLogoController *)init {
    return NULL;
}
%end
%end

// Hide YouTube Slim Status Bar
%group gHideYouTubeSlimStatusBar
%hook YTSlimStatusBarView
- (YTSlimStatusBarView *)init {
    return NULL;
}
%end
%end

// Hide YouTube Heatwaves in Video Player (YouTube v17.19.2-present) - @level3tjg - https://www.reddit.com/r/jailbreak/comments/v29yvk/
%group gHideHeatwaves
%hook YTInlinePlayerBarContainerView
- (BOOL)canShowHeatwave { return NO; }
%end
%end

%group gHideuYouTab
%hook YTPivotBarView
- (void)setRenderer:(YTIPivotBarRenderer *)renderer {
    NSMutableArray <YTIPivotBarSupportedRenderers *> *items = [renderer itemsArray];

    NSUInteger index = [items indexOfObjectPassingTest:^BOOL(YTIPivotBarSupportedRenderers *renderers, NSUInteger idx, BOOL *stop) {
        return [[[renderers pivotBarItemRenderer] pivotIdentifier] isEqualToString:@"com.miro.uyou"];
    }];
    if (index != NSNotFound) [items removeObjectAtIndex:index];

    %orig;
}
%end
%end

# pragma mark - Hide Notification Button && SponsorBlock Button
%hook YTRightNavigationButtons
- (void)layoutSubviews {
    %orig;
    if (IsEnabled(@"hideNotificationButton_enabled")) {
        self.notificationButton.hidden = YES;
    }
    if (IsEnabled(@"hideSponsorBlockButton_enabled")) { 
        self.sponsorBlockButton.hidden = YES;
    }
}
%end

// YTNoPaidPromo: https://github.com/PoomSmart/YTNoPaidPromo
%hook YTMainAppVideoPlayerOverlayViewController
- (void)setPaidContentWithPlayerData:(id)data {
    if (IsEnabled(@"hidePaidPromotionCard_enabled")) {}
    else { return %orig; }
}
- (void)playerOverlayProvider:(YTPlayerOverlayProvider *)provider didInsertPlayerOverlay:(YTPlayerOverlay *)overlay {
    if ([[overlay overlayIdentifier] isEqualToString:@"player_overlay_paid_content"] && IsEnabled(@"hidePaidPromotionCard_enabled")) return;
    %orig;
}
%end

%hook YTInlineMutedPlaybackPlayerOverlayViewController
- (void)setPaidContentWithPlayerData:(id)data {
    if (IsEnabled(@"hidePaidPromotionCard_enabled")) {}
    else { return %orig; }
}
%end

// YTReExplore: https://github.com/PoomSmart/YTReExplore/
%group gReExplore
static void replaceTab(YTIGuideResponse *response) {
    NSMutableArray <YTIGuideResponseSupportedRenderers *> *renderers = [response itemsArray];
    for (YTIGuideResponseSupportedRenderers *guideRenderers in renderers) {
        YTIPivotBarRenderer *pivotBarRenderer = [guideRenderers pivotBarRenderer];
        NSMutableArray <YTIPivotBarSupportedRenderers *> *items = [pivotBarRenderer itemsArray];
        NSUInteger shortIndex = [items indexOfObjectPassingTest:^BOOL(YTIPivotBarSupportedRenderers *renderers, NSUInteger idx, BOOL *stop) {
            return [[[renderers pivotBarItemRenderer] pivotIdentifier] isEqualToString:@"FEshorts"];
        }];
        if (shortIndex != NSNotFound) {
            [items removeObjectAtIndex:shortIndex];
            NSUInteger exploreIndex = [items indexOfObjectPassingTest:^BOOL(YTIPivotBarSupportedRenderers *renderers, NSUInteger idx, BOOL *stop) {
                return [[[renderers pivotBarItemRenderer] pivotIdentifier] isEqualToString:[%c(YTIBrowseRequest) browseIDForExploreTab]];
            }];
            if (exploreIndex == NSNotFound) {
                YTIPivotBarSupportedRenderers *exploreTab = [%c(YTIPivotBarRenderer) pivotSupportedRenderersWithBrowseId:[%c(YTIBrowseRequest) browseIDForExploreTab] title:@"Explore" iconType:292];
                [items insertObject:exploreTab atIndex:1];
            }
            break;
        }
    }
}
%hook YTGuideServiceCoordinator
- (void)handleResponse:(YTIGuideResponse *)response withCompletion:(id)completion {
    replaceTab(response);
    %orig(response, completion);
}
- (void)handleResponse:(YTIGuideResponse *)response error:(id)error completion:(id)completion {
    replaceTab(response);
    %orig(response, error, completion);
}
%end
%end

// BigYTMiniPlayer: https://github.com/Galactic-Dev/BigYTMiniPlayer
%group Main
%hook YTWatchMiniBarView
- (void)setWatchMiniPlayerLayout:(int)arg1 {
    %orig(1);
}
- (int)watchMiniPlayerLayout {
    return 1;
}
- (void)layoutSubviews {
    %orig;
    self.frame = CGRectMake(([UIScreen mainScreen].bounds.size.width - self.frame.size.width), self.frame.origin.y, self.frame.size.width, self.frame.size.height);
}
%end

%hook YTMainAppVideoPlayerOverlayView
- (BOOL)isUserInteractionEnabled {
    if([[self _viewControllerForAncestor].parentViewController.parentViewController isKindOfClass:%c(YTWatchMiniBarViewController)]) {
        return NO;
    }
        return %orig;
}
%end
%end

// DontEatMyContent - @therealFoxster: https://github.com/therealFoxster/DontEatMyContent
static double videoAspectRatio = 16/9;
static bool zoomedToFill = false;
static bool engagementPanelIsVisible = false, removeEngagementPanelViewControllerWithIdentifierCalled = false;

static MLHAMSBDLSampleBufferRenderingView *renderingView;
static NSLayoutConstraint *widthConstraint, *heightConstraint, *centerXConstraint, *centerYConstraint;

%group gDontEatMyContent

// Retrieve video aspect ratio 
%hook YTPlayerView
- (void)setAspectRatio:(CGFloat)aspectRatio {
    %orig(aspectRatio);
    videoAspectRatio = aspectRatio;
}
%end

%hook YTPlayerViewController
- (void)viewDidAppear:(BOOL)animated {
    YTPlayerView *playerView = [self playerView];
    UIView *renderingViewContainer = MSHookIvar<UIView *>(playerView, "_renderingViewContainer");
    renderingView = [playerView renderingView];

    // Making renderingView a bit larger since constraining to safe area leaves a gap between the notch and video
    CGFloat constant = 22.0; // Tested on iPhone 13 mini & 14 Pro Max

    widthConstraint = [renderingView.widthAnchor constraintEqualToAnchor:renderingViewContainer.safeAreaLayoutGuide.widthAnchor constant:constant];
    heightConstraint = [renderingView.heightAnchor constraintEqualToAnchor:renderingViewContainer.safeAreaLayoutGuide.heightAnchor constant:constant];
    centerXConstraint = [renderingView.centerXAnchor constraintEqualToAnchor:renderingViewContainer.centerXAnchor];
    centerYConstraint = [renderingView.centerYAnchor constraintEqualToAnchor:renderingViewContainer.centerYAnchor];
    
    // playerView.backgroundColor = [UIColor blueColor];
    // renderingViewContainer.backgroundColor = [UIColor greenColor];
    // renderingView.backgroundColor = [UIColor redColor];

    YTMainAppVideoPlayerOverlayViewController *activeVideoPlayerOverlay = [self activeVideoPlayerOverlay];

    // Must check class since YTInlineMutedPlaybackPlayerOverlayViewController doesn't have -(BOOL)isFullscreen
    if ([NSStringFromClass([activeVideoPlayerOverlay class]) isEqualToString:@"YTMainAppVideoPlayerOverlayViewController"] // isKindOfClass doesn't work for some reason
    && [activeVideoPlayerOverlay isFullscreen]) {
        if (!zoomedToFill && !engagementPanelIsVisible) DEMC_activate();
    } else {
        DEMC_centerRenderingView();
    }

    %orig(animated);
}
- (void)didPressToggleFullscreen {
    %orig;
    if (![[self activeVideoPlayerOverlay] isFullscreen]) { // Entering full screen
        if (!zoomedToFill && !engagementPanelIsVisible) DEMC_activate();
    } else { // Exiting full screen
        DEMC_deactivate();
    }
    
    %orig;
}
- (void)didSwipeToEnterFullscreen {
    %orig; 
    if (!zoomedToFill && !engagementPanelIsVisible) DEMC_activate();
}
- (void)didSwipeToExitFullscreen { 
    %orig; 
    DEMC_deactivate(); 
}
// New video played
-(void)playbackController:(id)playbackController didActivateVideo:(id)video withPlaybackData:(id)playbackData {
    %orig(playbackController, video, playbackData);
    if ([[self activeVideoPlayerOverlay] isFullscreen]) // New video played while in full screen (landscape)
        // Activate since new videos played in full screen aren't zoomed-to-fill by default
        // (i.e. the notch/Dynamic Island will cut into content when playing a new video in full screen)
        DEMC_activate(); 
    engagementPanelIsVisible = false;
    removeEngagementPanelViewControllerWithIdentifierCalled = false;
}
%end

// Pinch to zoom
%hook YTVideoFreeZoomOverlayView
- (void)didRecognizePinch:(UIPinchGestureRecognizer *)pinchGestureRecognizer {
    DEMC_deactivate();
    %orig(pinchGestureRecognizer);
}
// Detect zoom to fill
- (void)showLabelForSnapState:(NSInteger)snapState {
    if (snapState == 0) { // Original
        zoomedToFill = false;
        DEMC_activate();
    } else if (snapState == 1) { // Zoomed to fill
        zoomedToFill = true;
        // No need to deactivate constraints as it's already done in -(void)didRecognizePinch:(UIPinchGestureRecognizer *)
    }
    %orig(snapState);
}
%end

// Mini bar dismiss
%hook YTWatchMiniBarViewController
- (void)dismissMiniBarWithVelocity:(CGFloat)velocity gestureType:(int)gestureType {
    %orig(velocity, gestureType);
    zoomedToFill = false; // Setting to false since YouTube undoes zoom-to-fill when mini bar is dismissed
}
- (void)dismissMiniBarWithVelocity:(CGFloat)velocity gestureType:(int)gestureType skipShouldDismissCheck:(BOOL)skipShouldDismissCheck {
    %orig(velocity, gestureType, skipShouldDismissCheck);
    zoomedToFill = false;
}
%end

%hook YTMainAppEngagementPanelViewController
// Engagement panel (comment, description, etc.) about to show up
- (void)viewWillAppear:(BOOL)animated {
    if ([self isPeekingSupported]) {
        // Shorts (only Shorts support peeking, I think)
    } else {
        // Everything else
        engagementPanelIsVisible = true;
        if ([self isLandscapeEngagementPanel]) {
            DEMC_deactivate();
        }
    }
    %orig(animated);
}
// Engagement panel about to dismiss
// - (void)viewDidDisappear:(BOOL)animated { %orig; %log; } // Called too late & isn't reliable so sometimes constraints aren't activated even when engagement panel is closed
%end

%hook YTEngagementPanelContainerViewController
// Engagement panel about to dismiss
- (void)notifyEngagementPanelContainerControllerWillHideFinalPanel { // Called in time but crashes if plays new video while in full screen causing engagement panel dismissal
    // Must check if engagement panel was dismissed because new video played
    // (i.e. if -(void)removeEngagementPanelViewControllerWithIdentifier:(id) was called prior)
    if (![self isPeekingSupported] && !removeEngagementPanelViewControllerWithIdentifierCalled) {
        engagementPanelIsVisible = false;
        if ([self isLandscapeEngagementPanel] && !zoomedToFill) {
            DEMC_activate();
        }
    }
    %orig;
}
- (void)removeEngagementPanelViewControllerWithIdentifier:(id)identifier {
    // Usually called when engagement panel is open & new video is played or mini bar is dismissed
    removeEngagementPanelViewControllerWithIdentifierCalled = true;
    %orig(identifier);
}
%end

%end// group gDontEatMyContent

BOOL DEMC_deviceIsSupported() {
    // Get device model identifier (e.g. iPhone14,4)
    // https://stackoverflow.com/a/11197770/19227228
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *deviceModelID = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
    
    NSArray *unsupportedModelIDs = DEMC_UNSUPPORTED_DEVICES;
    for (NSString *identifier in unsupportedModelIDs) {
        if ([deviceModelID isEqualToString:identifier]) {
            return NO;
        }
    }

    if ([deviceModelID containsString:@"iPhone"]) {
        if ([deviceModelID isEqualToString:@"iPhone13,1"]) {
            // iPhone 12 mini
            return YES; 
        } 
        NSString *modelNumber = [[deviceModelID stringByReplacingOccurrencesOfString:@"iPhone" withString:@""] stringByReplacingOccurrencesOfString:@"," withString:@"."];
        if ([modelNumber floatValue] >= 14.0) {
            // iPhone 13 series and newer
            return YES;
        } else return NO;
    } else return NO;
}

void DEMC_activate() {
    if (videoAspectRatio < DEMC_THRESHOLD) {
        DEMC_deactivate();
        return;
    }
    // NSLog(@"activate");
    DEMC_centerRenderingView();
    renderingView.translatesAutoresizingMaskIntoConstraints = NO;
    widthConstraint.active = YES;
    heightConstraint.active = YES;
}

void DEMC_deactivate() {
    // NSLog(@"deactivate");
    DEMC_centerRenderingView();
    renderingView.translatesAutoresizingMaskIntoConstraints = YES;
    widthConstraint.active = NO;
    heightConstraint.active = NO;
}

void DEMC_centerRenderingView() {
    centerXConstraint.active = YES;
    centerYConstraint.active = YES;
}

// YTSpeed - https://github.com/Lyvendia/YTSpeed
%hook YTVarispeedSwitchController
- (id)init {
	id result = %orig;

	const int size = 16;
	float speeds[] = {0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0, 3.25, 3.5, 3.75, 4.0};
	id varispeedSwitchControllerOptions[size];

	for (int i = 0; i < size; ++i) {
		id title = [NSString stringWithFormat:@"%.2fx", speeds[i]];
		varispeedSwitchControllerOptions[i] = [[%c(YTVarispeedSwitchControllerOption) alloc] initWithTitle:title rate:speeds[i]];
	}

	NSUInteger count = sizeof(varispeedSwitchControllerOptions) / sizeof(id);
	NSArray *varispeedArray = [NSArray arrayWithObjects:varispeedSwitchControllerOptions count:count];
	MSHookIvar<NSArray *>(self, "_options") = varispeedArray;

	return result;
}
%end

%hook MLHAMQueuePlayer
- (void)setRate:(float)rate {
    MSHookIvar<float>(self, "_rate") = rate;
	MSHookIvar<float>(self, "_preferredRate") = rate;

	id player = MSHookIvar<HAMPlayerInternal *>(self, "_player");
	[player setRate: rate];

	id stickySettings = MSHookIvar<MLPlayerStickySettings *>(self, "_stickySettings");
	[stickySettings setRate: rate];

	[self.playerEventCenter broadcastRateChange: rate];

	YTSingleVideoController *singleVideoController = self.delegate;
	[singleVideoController playerRateDidChange: rate];
}
%end 

%hook YTPlayerViewController
%property float playbackRate;
- (void)singleVideo:(id)video playbackRateDidChange:(float)rate {
	%orig;
}
%end

# pragma mark - uYouPlus
// Video Player Options
// Skips content warning before playing *some videos - @PoomSmart
%hook YTPlayabilityResolutionUserActionUIController
- (void)showConfirmAlert { [self confirmAlertDidPressConfirm]; }
%end

// Disable snap to chapter
%hook YTSegmentableInlinePlayerBarView
- (void)didMoveToWindow {
    %orig;
    if (IsEnabled(@"snapToChapter_enabled")) {
        self.enableSnapToChapter = NO;
    }
}
%end

// Disable Pinch to zoom
%hook YTColdConfig
- (BOOL)videoZoomFreeZoomEnabledGlobalConfig {
    return IsEnabled(@"pinchToZoom_enabled") ? NO : %orig;
}
%end

// YTStockVolumeHUD - https://github.com/lilacvibes/YTStockVolumeHUD
%group gStockVolumeHUD
%hook YTVolumeBarView
- (void)volumeChanged:(id)arg1 {
        %orig(nil);
}
%end

%hook UIApplication 
- (void)setSystemVolumeHUDEnabled:(BOOL)arg1 forAudioCategory:(id)arg2 {
        %orig(true, arg2);
}
%end
%end

%hook YTDoubleTapToSeekController
- (void)enableDoubleTapToSeek:(BOOL)arg1 {
    return IsEnabled(@"tapToSkip_disabled") ? %orig(NO) : %orig;
}
%end

// Video Controls Overlay Options
// Hide CC / Autoplay switch
%hook YTMainAppControlsOverlayView
- (void)setClosedCaptionsOrSubtitlesButtonAvailable:(BOOL)arg1 { // hide CC button
    return IsEnabled(@"hideCC_enabled") ? %orig(NO) : %orig;
}
- (void)setAutoplaySwitchButtonRenderer:(id)arg1 { // hide Autoplay
    if (IsEnabled(@"hideAutoplaySwitch_enabled")) {}
    else { return %orig; }
}
%end

// Hide HUD Messages
%hook YTHUDMessageView
- (id)initWithMessage:(id)arg1 dismissHandler:(id)arg2 {
    return IsEnabled(@"hideHUD_enabled") ? nil : %orig;
}
%end

// Hide Watermark
%hook YTAnnotationsViewController
- (void)loadFeaturedChannelWatermark {
    if (IsEnabled(@"hideChannelWatermark_enabled")) {}
    else { return %orig; }
}
%end

// Hide Next & Previous button
%group gHidePreviousAndNextButton
%hook YTColdConfig
- (BOOL)removeNextPaddleForSingletonVideos { return YES; }
- (BOOL)removePreviousPaddleForSingletonVideos { return YES; }
%end

// %hook YTMainAppControlsOverlayView // this is only used for v16.42.3 (incompatible with YouTube v17.22.3-newer)
// - (void)layoutSubviews { // hide Next & Previous legacy buttons
//     %orig;
//     if (IsEnabled(@"hidePreviousAndNextButton_enabled")) { 
//    	      MSHookIvar<YTMainAppControlsOverlayView *>(self, "_nextButton").hidden = YES;
//         MSHookIvar<YTMainAppControlsOverlayView *>(self, "_previousButton").hidden = YES;
//        MSHookIvar<YTTransportControlsButtonView *>(self, "_nextButtonView").hidden = YES;
//    MSHookIvar<YTTransportControlsButtonView *>(self, "_previousButtonView").hidden = YES;
//     }
// }
// %end
%end

// Replace Next & Previous button with Fast forward & Rewind button
%group gReplacePreviousAndNextButton
%hook YTColdConfig
- (BOOL)replaceNextPaddleWithFastForwardButtonForSingletonVods { return YES; }
- (BOOL)replacePreviousPaddleWithRewindButtonForSingletonVods { return YES; }
%end
%end

%group gHideOverlayDarkBackground
%hook YTMainAppVideoPlayerOverlayView
- (void)setBackgroundVisible:(BOOL)arg1 {
    %orig(NO);
}
%end
%end

%group gHideVideoPlayerShadowOverlayButtons
%hook YTMainAppControlsOverlayView
- (void)layoutSubviews {
	%orig();
    MSHookIvar<YTTransportControlsButtonView *>(self, "_previousButtonView").backgroundColor = nil;
    MSHookIvar<YTTransportControlsButtonView *>(self, "_nextButtonView").backgroundColor = nil;
    	MSHookIvar<YTPlaybackButton *>(self, "_playPauseButton").backgroundColor = nil;
}
%end
%end

// Bring back the red progress bar
%hook YTColdConfig
- (BOOL)segmentablePlayerBarUpdateColors {
    return IsEnabled(@"redProgressBar_enabled") ? NO : %orig;
}
%end

// Disable the right panel in fullscreen mode
%hook YTColdConfig
- (BOOL)isLandscapeEngagementPanelEnabled {
    return IsEnabled(@"hideRightPanel_enabled") ? NO : %orig;
}
%end

// Shorts Controls Overlay Options
%hook YTReelWatchPlaybackOverlayView
- (void)setNativePivotButton:(id)arg1 {
    if (IsEnabled(@"hideShortsChannelAvatar_enabled")) {}
    else { return %orig; }
}
- (void)setReelLikeButton:(id)arg1 {
    if (IsEnabled(@"hideShortsLikeButton_enabled")) {}
    else { return %orig; }
}
- (void)setReelDislikeButton:(id)arg1 {
    if (IsEnabled(@"hideShortsDislikeButton_enabled")) {}
    else { return %orig; }
}
- (void)setViewCommentButton:(id)arg1 {
    if (IsEnabled(@"hideShortsCommentButton_enabled")) {}
    else { return %orig; }
}
- (void)setRemixButton:(id)arg1 {
    if (IsEnabled(@"hideShortsRemixButton_enabled")) {}
    else { return %orig; }
}
- (void)setShareButton:(id)arg1 {
    if (IsEnabled(@"hideShortsShareButton_enabled")) {}
    else { return %orig; }
}
%end

%hook YTHotConfig
- (BOOL)iosEnableShortsPlayerSplitViewController { 
    return IsEnabled(@"hideuYouShortsDownloadButton_enabled") ? YES : NO;
}
%end

%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    if ((IsEnabled(@"hideBuySuperThanks_enabled")) && ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.suggested_action"])) { 
        self.hidden = YES; 
    }
}
%end

%hook YTReelWatchRootViewController
- (void)setPausedStateCarouselView {
    if (IsEnabled(@"hideSubcriptions_enabled")) {}
    else { return %orig; }
}
%end

%hook YTShortsStartupCoordinator
- (id)evaluateResumeToShorts { 
    return IsEnabled(@"disableResumeToShorts") ? nil : %orig;
}
%end

// Theme Options
// Old dark theme (gray)
%group gOldDarkTheme
%hook YTColdConfig
- (BOOL)uiSystemsClientGlobalConfigUseDarkerPaletteBgColorForNative { return NO; }
- (BOOL)uiSystemsClientGlobalConfigUseDarkerPaletteTextColorForNative { return NO; }
- (BOOL)enableCinematicContainerOnClient { return NO; }
%end

%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    if ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.comment_composer"]) { self.backgroundColor = [UIColor clearColor]; }
    if ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.video_list_entry"]) { self.backgroundColor = [UIColor clearColor]; }
}
%end

%hook ASCollectionView
- (void)didMoveToWindow {
    %orig;
    self.superview.backgroundColor = [UIColor colorWithRed:0.129 green:0.129 blue:0.129 alpha:1.0];
}
%end

%hook YTFullscreenEngagementOverlayView
- (void)didMoveToWindow {
    %orig;
    self.subviews[0].backgroundColor = [UIColor clearColor];
}
%end

%hook YTRelatedVideosView
- (void)didMoveToWindow {
    %orig;
    self.subviews[0].backgroundColor = [UIColor clearColor];
}
%end
%end

// OLED dark mode by BandarHL
UIColor* raisedColor = [UIColor colorWithRed:0.035 green:0.035 blue:0.035 alpha:1.0];
%group gOLED
%hook YTCommonColorPalette
- (UIColor *)brandBackgroundSolid {
    return self.pageStyle == 1 ? [UIColor blackColor] : %orig;
}
- (UIColor *)brandBackgroundPrimary {
    return self.pageStyle == 1 ? [UIColor blackColor] : %orig;
}
- (UIColor *)brandBackgroundSecondary {
    return self.pageStyle == 1 ? [[UIColor blackColor] colorWithAlphaComponent:0.9] : %orig;
}
- (UIColor *)raisedBackground {
    return self.pageStyle == 1 ? [UIColor blackColor] : %orig;
}
- (UIColor *)staticBrandBlack {
    return self.pageStyle == 1 ? [UIColor blackColor] : %orig;
}
- (UIColor *)generalBackgroundA {
    return self.pageStyle == 1 ? [UIColor blackColor] : %orig;
}
%end

// Explore
%hook ASScrollView 
- (void)didMoveToWindow {
    %orig;
    if (isDarkMode()) {
        self.backgroundColor = [UIColor clearColor];
    }
}
%end

// Your videos
%hook ASCollectionView
- (void)didMoveToWindow {
    %orig;
    if (isDarkMode() && [self.nextResponder isKindOfClass:%c(_ASDisplayView)]) {
        self.superview.backgroundColor = [UIColor blackColor];
    }
}
%end

// Sub menu?
%hook ELMView
- (void)didMoveToWindow {
    %orig;
    if (isDarkMode()) {
        self.subviews[0].backgroundColor = [UIColor clearColor];
    }
}
%end

// iSponsorBlock
%hook SponsorBlockSettingsController
- (void)viewDidLoad {
    if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        %orig;
        self.tableView.backgroundColor = [UIColor blackColor];
    } else { return %orig; }
}
%end

%hook SponsorBlockViewController
- (void)viewDidLoad {
    if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        %orig;
        self.view.backgroundColor = [UIColor blackColor];
    } else { return %orig; }
}
%end

// Search View
%hook YTSearchBarView 
- (void)setBackgroundColor:(UIColor *)color {
    return isDarkMode() ? %orig([UIColor blackColor]) : %orig;
}
%end

// History Search view
%hook YTSearchBoxView 
- (void)setBackgroundColor:(UIColor *)color {
    return isDarkMode() ? %orig([UIColor blackColor]) : %orig;

}
%end

// Comment view
%hook YTCommentView
- (void)setBackgroundColor:(UIColor *)color {
    return isDarkMode() ? %orig([UIColor blackColor]) : %orig;
}
%end

%hook YTCreateCommentAccessoryView
- (void)setBackgroundColor:(UIColor *)color {
    return isDarkMode() ? %orig([UIColor blackColor]) : %orig;
}
%end

%hook YTCreateCommentTextView
- (void)setBackgroundColor:(UIColor *)color {
    return isDarkMode() ? %orig([UIColor blackColor]) : %orig;
}
- (void)setTextColor:(UIColor *)color { // fix black text in #Shorts video's comment
    return isDarkMode() ? %orig([UIColor whiteColor]) : %orig;
}
%end

%hook YTCommentDetailHeaderCell
- (void)didMoveToWindow {
    %orig;
    if (isDarkMode()) {
        self.subviews[2].backgroundColor = [UIColor blackColor];
    }
}
%end

%hook YTFormattedStringLabel  // YT is werid...
- (void)setBackgroundColor:(UIColor *)color {
    return isDarkMode() ? %orig([UIColor clearColor]) : %orig;
}
%end

// Live chat comment
%hook YCHLiveChatActionPanelView 
- (void)setBackgroundColor:(UIColor *)color {
    return isDarkMode() ? %orig([UIColor blackColor]) : %orig;
}
%end

%hook YTEmojiTextView
- (void)setBackgroundColor:(UIColor *)color {
    return isDarkMode() ? %orig([UIColor blackColor]) : %orig;
}
%end

%hook YCHLiveChatView
- (void)didMoveToWindow {
    %orig;
    if (isDarkMode()) {
        self.subviews[1].backgroundColor = [UIColor blackColor];
    }
}
%end

%hook YTCollectionView 
- (void)setBackgroundColor:(UIColor *)color { 
    return isDarkMode() ? %orig([UIColor blackColor]) : %orig;
}
%end

//
%hook YTBackstageCreateRepostDetailView
- (void)setBackgroundColor:(UIColor *)color {
    return isDarkMode() ? %orig([UIColor blackColor]) : %orig;
}
%end

// Others
%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    if (isDarkMode()) {
        if ([self.nextResponder isKindOfClass:%c(ASScrollView)]) self.backgroundColor = [UIColor clearColor];
        if ([self.accessibilityIdentifier isEqualToString:@"eml.cvr"]) self.backgroundColor = [UIColor blackColor];
        if ([self.accessibilityIdentifier isEqualToString:@"eml.live_chat_text_message"]) self.backgroundColor = [UIColor blackColor];
        if ([self.accessibilityIdentifier isEqualToString:@"rich_header"]) self.backgroundColor = [UIColor blackColor];
        if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment_cell"]) self.backgroundColor = [UIColor blackColor];
        if ([self.accessibilityIdentifier isEqualToString:@"id.ui.cancel.button"]) self.superview.backgroundColor = [UIColor clearColor];
        if ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.comment_composer"]) self.backgroundColor = [UIColor blackColor];
        if ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.video_list_entry"]) self.backgroundColor = [UIColor blackColor];
        if ([self.accessibilityIdentifier isEqualToString:@"id.comment.guidelines_text"]) self.superview.backgroundColor = [UIColor blackColor];
        if ([self.accessibilityIdentifier isEqualToString:@"id.comment.channel_guidelines_bottom_sheet_container"]) self.backgroundColor = [UIColor blackColor];
        if ([self.accessibilityIdentifier isEqualToString:@"id.comment.channel_guidelines_entry_banner_container"]) self.backgroundColor = [UIColor blackColor];
	if ([self.accessibilityIdentifier isEqualToString:@"id.comment.comment_group_detail_container"]) { self.backgroundColor = [UIColor clearColor]; }
    }
}
%end

// Open link with...
%hook ASWAppSwitchingSheetHeaderView
- (void)setBackgroundColor:(UIColor *)color {
    return isDarkMode() ? %orig(raisedColor) : %orig;
}
%end

%hook ASWAppSwitchingSheetFooterView
- (void)setBackgroundColor:(UIColor *)color {
    return isDarkMode() ? %orig(raisedColor) : %orig;
}
%end

%hook ASWAppSwitcherCollectionViewCell
- (void)didMoveToWindow {
    %orig;
    if (isDarkMode()) {
        self.backgroundColor = raisedColor;
        self.subviews[1].backgroundColor = raisedColor;
        self.superview.backgroundColor = raisedColor;
    }
}
%end

// Incompatibility with the new YT Dark theme
%hook YTColdConfig
- (BOOL)uiSystemsClientGlobalConfigUseDarkerPaletteBgColorForNative { return NO; }
%end
%end

%group gLowContrastMode // Low Contrast Mode v1.2.2 (Compatible with only v15.02.1-present)
%hook UIColor
+ (UIColor *)whiteColor { // Dark Theme Color
         return [UIColor colorWithRed: 0.56 green: 0.56 blue: 0.56 alpha: 1.00];
}
+ (UIColor *)textColor {  // Light Theme Color
         return [UIColor colorWithRed: 0.56 green: 0.56 blue: 0.56 alpha: 1.00];
}
+ (UIColor *)dynamicLabelColor {
         return [UIColor colorWithRed: 0.56 green: 0.56 blue: 0.56 alpha: 1.00];
}
%end

%hook YTColorPalette // Changes Texts & Icons in YouTube Bottom Bar + Text Icons under Video Player
- (UIColor *)textPrimary {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
    }
        return [UIColor colorWithRed: 0.38 green: 0.38 blue: 0.38 alpha: 1.00]; // Light Theme
}
- (UIColor *)textSecondary {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
    }
        return [UIColor colorWithRed: 0.38 green: 0.38 blue: 0.38 alpha: 1.00]; // Light Theme
}
%end

%hook YTCommonColorPalette // Changes Texts & Icons in YouTube Bottom Bar (Doesn't change Texts & Icons under the video player)
- (UIColor *)textPrimary {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
    }
        return [UIColor colorWithRed: 0.38 green: 0.38 blue: 0.38 alpha: 1.00]; // Light Theme
}
- (UIColor *)textSecondary {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
    }
        return [UIColor colorWithRed: 0.38 green: 0.38 blue: 0.38 alpha: 1.00]; // Light Theme
}
- (UIColor *)badgeChipBackground {
    if (self.pageStyle == 1) {
        return [UIColor blackColor];
    }
        return [UIColor blackColor];
}
- (UIColor *)buttonChipBackgroundHover {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
    }
        return [UIColor colorWithRed: 0.38 green: 0.38 blue: 0.38 alpha: 1.00]; // Light Theme
}
- (UIColor *)overlayButtonPrimary {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
    }
        return [UIColor colorWithRed: 0.38 green: 0.38 blue: 0.38 alpha: 1.00]; // Light Theme
}
- (UIColor *)overlayButtonSecondary {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
    }
        return [UIColor colorWithRed: 0.38 green: 0.38 blue: 0.38 alpha: 1.00]; // Light Theme
}
- (UIColor *)staticBrandWhite {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
    }
        return [UIColor colorWithRed: 0.38 green: 0.38 blue: 0.38 alpha: 1.00]; // Light Theme
}
- (UIColor *)staticBrandBlack {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
    }
        return [UIColor colorWithRed: 0.38 green: 0.38 blue: 0.38 alpha: 1.00]; // Light Theme
}
- (UIColor *)brandIconActive {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
    }
        return [UIColor colorWithRed: 0.38 green: 0.38 blue: 0.38 alpha: 1.00]; // Light Theme
}
- (UIColor *)brandIconInactive {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
    }
        return [UIColor colorWithRed: 0.38 green: 0.38 blue: 0.38 alpha: 1.00]; // Light Theme
}
- (UIColor *)brandButtonBackground {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
    }
        return [UIColor colorWithRed: 0.38 green: 0.38 blue: 0.38 alpha: 1.00]; // Light Theme
}
%end

%hook YTCollectionView  // Changes Live Chat Texts
 - (void)setTintColor:(UIColor *)color { 
     return isDarkMode() ? %orig([UIColor whiteColor]) : %orig;
 }
 %end

%hook YTQTMButton // Changes Tweak Icons/Texts/Images
- (UIColor *)whiteColor {
         return [UIColor whiteColor];
}
- (UIColor *)sponsorBlockButton {
         return [UIColor whiteColor];
}
%end

%hook ELMAnimatedVectorView // Changes the Like Button Animation Color. 
- (UIColor *)_ASDisplayView {
         return [UIColor whiteColor];
}
- (UIColor *)ELMAnimatedVectorView {
         return [UIColor whiteColor];
}
%end

%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    // LCM Button Elements
    if ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.chip.primary_tap_container"]) self.backgroundColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.compact_subscribe_button"]) self.backgroundColor = [UIColor whiteColor];
    // LCM Icon & Text Elements
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.like.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.dislike.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.share.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.add_to.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.comment.author_container"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.comment.content.label"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.add_to.offline.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comments_entry_point_teaser"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment.like.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment.dislike.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment.reply.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.backstage.dislike_button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.backstage.comment_button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.live_chat_text_message"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.metadata"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.overflow_button"]) self.tintColor = [UIColor whiteColor];
}
%end
%end

%group gRedContrastMode // Red Contrast Mode
%hook UIColor
+ (UIColor *)whiteColor {
         return [UIColor colorWithRed: 0.97 green: 0.15 blue: 0.15 alpha: 1.00];
}
+ (UIColor *)textColor {
         return [UIColor colorWithRed: 0.97 green: 0.15 blue: 0.15 alpha: 1.00];
}
+ (UIColor *)dynamicLabelColor {
         return [UIColor colorWithRed: 0.97 green: 0.15 blue: 0.15 alpha: 1.00];
}
%end

%hook YTColorPalette
- (UIColor *)textPrimary {
     if (self.pageStyle == 1) {
         return [UIColor whiteColor]; // Dark Theme
     }
         return [UIColor colorWithRed: 0.97 green: 0.15 blue: 0.15 alpha: 1.00]; // Light Theme
 }
- (UIColor *)textSecondary {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
     }
        return [UIColor colorWithRed: 0.97 green: 0.15 blue: 0.15 alpha: 1.00]; // Light Theme
 }
%end

%hook YTCommonColorPalette
- (UIColor *)textPrimary {
     if (self.pageStyle == 1) {
         return [UIColor whiteColor]; // Dark Theme
     }
         return [UIColor colorWithRed: 0.97 green: 0.15 blue: 0.15 alpha: 1.00]; // Light Theme
 }
- (UIColor *)textSecondary {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
     }
        return [UIColor colorWithRed: 0.97 green: 0.15 blue: 0.15 alpha: 1.00]; // Light Theme
 }
%end

%hook YTQTMButton // Changes Tweak Icons/Texts/Images
- (UIColor *)whiteColor {
         return [UIColor whiteColor];
}
- (UIColor *)sponsorBlockButton {
         return [UIColor whiteColor];
}
%end

%hook ELMAnimatedVectorView // Changes the Like Button Animation Color. 
- (UIColor *)_ASDisplayView {
         return [UIColor whiteColor];
}
%end

%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    // LCM Button Elements
    if ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.chip.primary_tap_container"]) self.backgroundColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.compact_subscribe_button"]) self.backgroundColor = [UIColor whiteColor];
    // LCM Icon & Text Elements
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.like.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.dislike.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.share.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.add_to.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.comment.author_container"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.comment.content.label"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.add_to.offline.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comments_entry_point_teaser"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment.like.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment.dislike.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment.reply.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.backstage.dislike_button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.backstage.comment_button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.live_chat_text_message"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.metadata"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.overflow_button"]) self.tintColor = [UIColor whiteColor];
}
%end
%end

%group gBlueContrastMode // Blue Contrast Mode
%hook UIColor
+ (UIColor *)whiteColor {
         return [UIColor colorWithRed: 0.04 green: 0.47 blue: 0.72 alpha: 1.00];
}
+ (UIColor *)textColor {
         return [UIColor colorWithRed: 0.04 green: 0.47 blue: 0.72 alpha: 1.00];
}
+ (UIColor *)dynamicLabelColor {
         return [UIColor colorWithRed: 0.04 green: 0.47 blue: 0.72 alpha: 1.00];
}
%end

%hook YTColorPalette
- (UIColor *)textPrimary {
     if (self.pageStyle == 1) {
         return [UIColor whiteColor]; // Dark Theme
     }
         return [UIColor colorWithRed: 0.04 green: 0.41 blue: 0.62 alpha: 1.00]; // Light Theme
 }
- (UIColor *)textSecondary {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
     }
        return [UIColor colorWithRed: 0.04 green: 0.41 blue: 0.62 alpha: 1.00]; // Light Theme
 }
%end

%hook YTCommonColorPalette
- (UIColor *)textPrimary {
     if (self.pageStyle == 1) {
         return [UIColor whiteColor]; // Dark Theme
     }
         return [UIColor colorWithRed: 0.04 green: 0.41 blue: 0.62 alpha: 1.00]; // Light Theme
 }
- (UIColor *)textSecondary {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
     }
        return [UIColor colorWithRed: 0.04 green: 0.41 blue: 0.62 alpha: 1.00]; // Light Theme
 }
%end

%hook YTQTMButton // Changes Tweak Icons/Texts/Images
- (UIColor *)whiteColor {
         return [UIColor whiteColor];
}
- (UIColor *)sponsorBlockButton {
         return [UIColor whiteColor];
}
%end

%hook ELMAnimatedVectorView // Changes the Like Button Animation Color. 
- (UIColor *)_ASDisplayView {
         return [UIColor whiteColor];
}
%end

%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    // LCM Button Elements
    if ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.chip.primary_tap_container"]) self.backgroundColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.compact_subscribe_button"]) self.backgroundColor = [UIColor whiteColor];
    // LCM Icon & Text Elements
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.like.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.dislike.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.share.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.add_to.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.comment.author_container"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.comment.content.label"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.add_to.offline.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comments_entry_point_teaser"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment.like.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment.dislike.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment.reply.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.backstage.dislike_button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.backstage.comment_button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.live_chat_text_message"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.metadata"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.overflow_button"]) self.tintColor = [UIColor whiteColor];
}
%end
%end

%group gGreenContrastMode // Green Contrast Mode
%hook UIColor
+ (UIColor *)whiteColor {
         return [UIColor colorWithRed: 0.01 green: 0.66 blue: 0.18 alpha: 1.00];
}
+ (UIColor *)textColor {
         return [UIColor colorWithRed: 0.01 green: 0.66 blue: 0.18 alpha: 1.00];
}
+ (UIColor *)dynamicLabelColor {
         return [UIColor colorWithRed: 0.01 green: 0.66 blue: 0.18 alpha: 1.00];
}
%end

%hook YTColorPalette
- (UIColor *)textPrimary {
     if (self.pageStyle == 1) {
         return [UIColor whiteColor]; // Dark Theme
     }
         return [UIColor colorWithRed: 0.00 green: 0.50 blue: 0.13 alpha: 1.00]; // Light Theme
 }
- (UIColor *)textSecondary {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
     }
        return [UIColor colorWithRed: 0.00 green: 0.50 blue: 0.13 alpha: 1.00]; // Light Theme
 }
%end

%hook YTCommonColorPalette
- (UIColor *)textPrimary {
     if (self.pageStyle == 1) {
         return [UIColor whiteColor]; // Dark Theme
     }
         return [UIColor colorWithRed: 0.00 green: 0.50 blue: 0.13 alpha: 1.00]; // Light Theme
 }
- (UIColor *)textSecondary {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
     }
        return [UIColor colorWithRed: 0.00 green: 0.50 blue: 0.13 alpha: 1.00]; // Light Theme
 }
%end

%hook YTQTMButton // Changes Tweak Icons/Texts/Images
- (UIColor *)whiteColor {
         return [UIColor whiteColor];
}
- (UIColor *)sponsorBlockButton {
         return [UIColor whiteColor];
}
%end

%hook ELMAnimatedVectorView // Changes the Like Button Animation Color. 
- (UIColor *)_ASDisplayView {
         return [UIColor whiteColor];
}
%end

%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    // LCM Button Elements
    if ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.chip.primary_tap_container"]) self.backgroundColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.compact_subscribe_button"]) self.backgroundColor = [UIColor whiteColor];
    // LCM Icon & Text Elements
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.like.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.dislike.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.share.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.add_to.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.comment.author_container"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.comment.content.label"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.add_to.offline.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comments_entry_point_teaser"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment.like.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment.dislike.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment.reply.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.backstage.dislike_button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.backstage.comment_button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.live_chat_text_message"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.metadata"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.overflow_button"]) self.tintColor = [UIColor whiteColor];
}
%end
%end

%group gYellowContrastMode // Yellow Contrast Mode
%hook UIColor
+ (UIColor *)whiteColor {
         return [UIColor colorWithRed: 0.89 green: 0.82 blue: 0.20 alpha: 1.00];
}
+ (UIColor *)textColor {
         return [UIColor colorWithRed: 0.89 green: 0.82 blue: 0.20 alpha: 1.00];
}
+ (UIColor *)dynamicLabelColor {
         return [UIColor colorWithRed: 0.89 green: 0.82 blue: 0.20 alpha: 1.00];
}
%end

%hook YTColorPalette
- (UIColor *)textPrimary {
     if (self.pageStyle == 1) {
         return [UIColor whiteColor]; // Dark Theme
     }
         return [UIColor colorWithRed: 0.77 green: 0.71 blue: 0.14 alpha: 1.00]; // Light Theme
 }
- (UIColor *)textSecondary {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
     }
        return [UIColor colorWithRed: 0.77 green: 0.71 blue: 0.14 alpha: 1.00]; // Light Theme
 }
%end

%hook YTCommonColorPalette
- (UIColor *)textPrimary {
     if (self.pageStyle == 1) {
         return [UIColor whiteColor]; // Dark Theme
     }
         return [UIColor colorWithRed: 0.77 green: 0.71 blue: 0.14 alpha: 1.00]; // Light Theme
 }
- (UIColor *)textSecondary {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
     }
        return [UIColor colorWithRed: 0.77 green: 0.71 blue: 0.14 alpha: 1.00]; // Light Theme
 }
%end

%hook YTQTMButton // Changes Tweak Icons/Texts/Images
- (UIColor *)whiteColor {
         return [UIColor whiteColor];
}
- (UIColor *)sponsorBlockButton {
         return [UIColor whiteColor];
}
%end

%hook ELMAnimatedVectorView // Changes the Like Button Animation Color. 
- (UIColor *)_ASDisplayView {
         return [UIColor whiteColor];
}
%end

%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    // LCM Button Elements
    if ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.chip.primary_tap_container"]) self.backgroundColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.compact_subscribe_button"]) self.backgroundColor = [UIColor whiteColor];
    // LCM Icon & Text Elements
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.like.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.dislike.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.share.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.add_to.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.comment.author_container"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.comment.content.label"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.add_to.offline.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comments_entry_point_teaser"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment.like.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment.dislike.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment.reply.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.backstage.dislike_button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.backstage.comment_button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.live_chat_text_message"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.metadata"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.overflow_button"]) self.tintColor = [UIColor whiteColor];
}
%end
%end

%group gOrangeContrastMode // Orange Contrast Mode
%hook UIColor
+ (UIColor *)whiteColor {
         return [UIColor colorWithRed: 0.73 green: 0.45 blue: 0.05 alpha: 1.00];
}
+ (UIColor *)textColor {
         return [UIColor colorWithRed: 0.73 green: 0.45 blue: 0.05 alpha: 1.00];
}
+ (UIColor *)dynamicLabelColor {
         return [UIColor colorWithRed: 0.73 green: 0.45 blue: 0.05 alpha: 1.00];
}
%end

%hook YTColorPalette
- (UIColor *)textPrimary {
     if (self.pageStyle == 1) {
         return [UIColor whiteColor]; // Dark Theme
     }
         return [UIColor colorWithRed: 0.80 green: 0.49 blue: 0.05 alpha: 1.00]; // Light Theme
 }
- (UIColor *)textSecondary {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
     }
        return [UIColor colorWithRed: 0.80 green: 0.49 blue: 0.05 alpha: 1.00]; // Light Theme
 }
%end

%hook YTCommonColorPalette
- (UIColor *)textPrimary {
     if (self.pageStyle == 1) {
         return [UIColor whiteColor]; // Dark Theme
     }
         return [UIColor colorWithRed: 0.80 green: 0.49 blue: 0.05 alpha: 1.00]; // Light Theme
 }
- (UIColor *)textSecondary {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
     }
        return [UIColor colorWithRed: 0.80 green: 0.49 blue: 0.05 alpha: 1.00]; // Light Theme
 }
%end

%hook YTQTMButton // Changes Tweak Icons/Texts/Images
- (UIColor *)whiteColor {
         return [UIColor whiteColor];
}
- (UIColor *)sponsorBlockButton {
         return [UIColor whiteColor];
}
%end

%hook ELMAnimatedVectorView // Changes the Like Button Animation Color. 
- (UIColor *)_ASDisplayView {
         return [UIColor whiteColor];
}
%end

%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    // LCM Button Elements
    if ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.chip.primary_tap_container"]) self.backgroundColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.compact_subscribe_button"]) self.backgroundColor = [UIColor whiteColor];
    // LCM Icon & Text Elements
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.like.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.dislike.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.share.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.add_to.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.comment.author_container"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.comment.content.label"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.add_to.offline.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comments_entry_point_teaser"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment.like.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment.dislike.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment.reply.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.backstage.dislike_button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.backstage.comment_button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.live_chat_text_message"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.metadata"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.overflow_button"]) self.tintColor = [UIColor whiteColor];
}
%end
%end

%group gPurpleContrastMode // Purple Contrast Mode
%hook UIColor
+ (UIColor *)whiteColor {
         return [UIColor colorWithRed: 0.62 green: 0.01 blue: 0.73 alpha: 1.00];
}
+ (UIColor *)textColor {
         return [UIColor colorWithRed: 0.62 green: 0.01 blue: 0.73 alpha: 1.00];
}
+ (UIColor *)dynamicLabelColor {
         return [UIColor colorWithRed: 0.62 green: 0.01 blue: 0.73 alpha: 1.00];
}
%end

%hook YTColorPalette
- (UIColor *)textPrimary {
     if (self.pageStyle == 1) {
         return [UIColor whiteColor]; // Dark Theme
     }
         return [UIColor colorWithRed: 0.44 green: 0.00 blue: 0.52 alpha: 1.00]; // Light Theme
 }
- (UIColor *)textSecondary {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
     }
        return [UIColor colorWithRed: 0.44 green: 0.00 blue: 0.52 alpha: 1.00]; // Light Theme
 }
%end

%hook YTCommonColorPalette
- (UIColor *)textPrimary {
     if (self.pageStyle == 1) {
         return [UIColor whiteColor]; // Dark Theme
     }
         return [UIColor colorWithRed: 0.44 green: 0.00 blue: 0.52 alpha: 1.00]; // Light Theme
 }
- (UIColor *)textSecondary {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
     }
        return [UIColor colorWithRed: 0.44 green: 0.00 blue: 0.52 alpha: 1.00]; // Light Theme
 }
%end

%hook YTQTMButton // Changes Tweak Icons/Texts/Images
- (UIColor *)whiteColor {
         return [UIColor whiteColor];
}
- (UIColor *)sponsorBlockButton {
         return [UIColor whiteColor];
}
%end

%hook ELMAnimatedVectorView // Changes the Like Button Animation Color. 
- (UIColor *)_ASDisplayView {
         return [UIColor whiteColor];
}
%end

%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    // LCM Button Elements
    if ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.chip.primary_tap_container"]) self.backgroundColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.compact_subscribe_button"]) self.backgroundColor = [UIColor whiteColor];
    // LCM Icon & Text Elements
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.like.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.dislike.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.share.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.add_to.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.comment.author_container"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.comment.content.label"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.add_to.offline.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comments_entry_point_teaser"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment.like.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment.dislike.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment.reply.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.backstage.dislike_button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.backstage.comment_button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.live_chat_text_message"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.metadata"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.overflow_button"]) self.tintColor = [UIColor whiteColor];
}
%end
%end

%group gPinkContrastMode // Pink Contrast Mode
%hook UIColor
+ (UIColor *)whiteColor {
         return [UIColor colorWithRed: 1.00 green: 0.57 blue: 0.94 alpha: 1.00];
}
+ (UIColor *)textColor {
         return [UIColor colorWithRed: 1.00 green: 0.57 blue: 0.94 alpha: 1.00];
}
+ (UIColor *)dynamicLabelColor {
         return [UIColor colorWithRed: 1.00 green: 0.57 blue: 0.94 alpha: 1.00];
}
%end

%hook YTColorPalette
- (UIColor *)textPrimary {
     if (self.pageStyle == 1) {
         return [UIColor whiteColor]; // Dark Theme
     }
         return [UIColor colorWithRed: 0.75 green: 0.42 blue: 0.71 alpha: 1.00]; // Light Theme
 }
- (UIColor *)textSecondary {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
     }
        return [UIColor colorWithRed: 0.75 green: 0.42 blue: 0.71 alpha: 1.00]; // Light Theme
 }
%end

%hook YTCommonColorPalette
- (UIColor *)textPrimary {
     if (self.pageStyle == 1) {
         return [UIColor whiteColor]; // Dark Theme
     }
         return [UIColor colorWithRed: 0.75 green: 0.42 blue: 0.71 alpha: 1.00]; // Light Theme
 }
- (UIColor *)textSecondary {
    if (self.pageStyle == 1) {
        return [UIColor whiteColor]; // Dark Theme
     }
        return [UIColor colorWithRed: 0.75 green: 0.42 blue: 0.71 alpha: 1.00]; // Light Theme
 }
%end

%hook YTQTMButton // Changes Tweak Icons/Texts/Images
- (UIColor *)whiteColor {
         return [UIColor whiteColor];
}
- (UIColor *)sponsorBlockButton {
         return [UIColor whiteColor];
}
%end

%hook ELMAnimatedVectorView // Changes the Like Button Animation Color. 
- (UIColor *)_ASDisplayView {
         return [UIColor whiteColor];
}
%end

%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    // LCM Button Elements
    if ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.chip.primary_tap_container"]) self.backgroundColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.compact_subscribe_button"]) self.backgroundColor = [UIColor whiteColor];
    // LCM Icon & Text Elements
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.like.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.dislike.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.share.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.add_to.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.comment.author_container"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.comment.content.label"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.add_to.offline.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comments_entry_point_teaser"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment.like.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment.dislike.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment.reply.button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.backstage.dislike_button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"id.ui.backstage.comment_button"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.live_chat_text_message"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.metadata"]) self.tintColor = [UIColor whiteColor];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.overflow_button"]) self.tintColor = [UIColor whiteColor];
}
%end
%end

// OLED keyboard by @ichitaso <3 - http://gist.github.com/ichitaso/935100fd53a26f18a9060f7195a1be0e
%group gOLEDKB 
%hook UIPredictionViewController
- (void)loadView {
    %orig;
    [self.view setBackgroundColor:[UIColor blackColor]];
}
%end

%hook UICandidateViewController
- (void)loadView {
    %orig;
    [self.view setBackgroundColor:[UIColor blackColor]];
}
%end

%hook UIKeyboardDockView
- (void)didMoveToWindow {
    %orig;
    self.backgroundColor = [UIColor blackColor];
}
%end

%hook UIKeyboardLayoutStar 
- (void)didMoveToWindow {
    %orig;
    self.backgroundColor = [UIColor blackColor];
}
%end

%hook UIKBRenderConfig // Prediction text color
- (void)setLightKeyboard:(BOOL)arg1 { %orig(NO); }
%end
%end

// Miscellaneous
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

// Won't Work Yet - Bump uYou Version
// %hook _UITableViewHeaderFooterViewLabel
// - (void)setNeedsLayout
// NSString "uYou v2.1" = "uYou v2.3~1";
// %end

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
// %hook YTChipCloudCell // 
// - (void)didMoveToWindow {
//     %orig;
//     self.hidden = YES;
// }
// %end
%end

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
    return NO;
} 
%end
%hook UIKBRenderer
- (long long)assetIdiom {
    return NO;
} 
%end
%end

// YT startup animation
%hook YTColdConfig
- (BOOL)mainAppCoreClientIosEnableStartupAnimation {
    return IsEnabled(@"ytStartupAnimation_enabled") ? YES : NO;
}
%end

# pragma mark - ctor
%ctor {
    // Load uYou first so its functions are available for hooks.
    dlopen([[NSString stringWithFormat:@"%@/Frameworks/uYou.dylib", [[NSBundle mainBundle] bundlePath]] UTF8String], RTLD_LAZY);

    %init;
    if (@available(iOS 16, *)) {
        %init(iOS16);
    }
    if (IsEnabled(@"reExplore_enabled")) {
        %init(gReExplore);
    }
    if (IsEnabled(@"bigYTMiniPlayer_enabled") && (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad)) {
        %init(Main);
    }
    if (IsEnabled(@"dontEatMyContent_enabled") && DEMC_deviceIsSupported()) {
        %init(gDontEatMyContent);
    }
    if (IsEnabled(@"hidePreviousAndNextButton_enabled")) {
        %init(gHidePreviousAndNextButton);
    }
    if (IsEnabled(@"replacePreviousAndNextButton_enabled")) {
        %init(gReplacePreviousAndNextButton);
    }
    if (IsEnabled(@"hideOverlayDarkBackground_enabled")) {
        %init(gHideOverlayDarkBackground);
    }
    if (IsEnabled(@"hideVideoPlayerShadowOverlayButtons_enabled")) {
        %init(gHideVideoPlayerShadowOverlayButtons);
    }
    if (IsEnabled(@"disableWifiRelatedSettings_enabled")) {
        %init(gDisableWifiRelatedSettings);
    }
    if (oldDarkTheme()) {
        %init(gOldDarkTheme)
    }
    if (oledDarkTheme()) {
         %init(gOLED)
    }
    if (IsEnabled(@"oledKeyBoard_enabled")) {
        %init(gOLEDKB);
    }
    if (IsEnabled(@"disableHints_enabled")) {
        %init(gDisableHints);
    }
    if (IsEnabled(@"hideChipBar_enabled")) {
        %init(gHideChipBar);
    }
    if (IsEnabled(@"iPhoneLayout_enabled") && (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad)) {
        %init(giPhoneLayout);
    }  
    if (IsEnabled(@"stockVolumeHUD_enabled")) {
        %init(gStockVolumeHUD);
    }
    if (IsEnabled(@"hideYouTubeSlimStatusBar_enabled")) {
        %init(gHideYouTubeSlimStatusBar);
    }
    if (IsEnabled(@"hideYouTubeLogo_enabled")) {
        %init(gHideYouTubeLogo);
    }
    if (IsEnabled(@"hideuYouTab_enabled")) {
        %init(gHideuYouTab);
    }
    if (IsEnabled(@"hideHeatwaves_enabled")) {
        %init(gHideHeatwaves);
    }
    if (IsEnabled(@"ytNoModernUI_enabled")) {
        %init(gYTNoModernUI);
    }
    if (defaultContrastMode()) {
        %init(gLowContrastMode);
    }
    if (redContrastMode()) {
        %init(gRedContrastMode);
    }
    if (blueContrastMode()) {
        %init(gBlueContrastMode);
    }
    if (greenContrastMode()) {
        %init(gGreenContrastMode);
    }
    if (yellowContrastMode()) {
        %init(gYellowContrastMode);
    }
    if (orangeContrastMode()) {
        %init(gOrangeContrastMode);
    }
    if (purpleContrastMode()) {
        %init(gPurpleContrastMode);
    }
    if (pinkContrastMode()) {
        %init(gPinkContrastMode);
    }

    // Disable updates
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"automaticallyCheckForUpdates"];
 
    // Disable broken options of uYou
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"removeYouTubeAds"]; // Remove YouTube Ads Disabled - Reason was due because it stopped working.
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"disableAgeRestriction"]; // Disable Age Restriction Disabled - Reason is the same as above.
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"showedWelcomeVC"]; // uYou Welcome Screen Disabled - Reason is because you can't hide the prompt in iOS 16.1-present.
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"removeShortsSection"]; // Remove Shorts Section Disabled - reason was due to not being consistent enough.
    
    // Change the default value of some options
    NSArray *allKeys = [[[NSUserDefaults standardUserDefaults] dictionaryRepresentation] allKeys];
    if (![allKeys containsObject:@"relatedVideosAtTheEndOfYTVideos"]) { 
       [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"relatedVideosAtTheEndOfYTVideos"]; 
    }
    if (![allKeys containsObject:@"uYouButtonVideoControlsOverlay"]) { 
       [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"uYouButtonVideoControlsOverlay"]; 
    }
    if (![allKeys containsObject:@"uYouPiPButtonVideoControlsOverlay"]) { 
       [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"uYouPiPButtonVideoControlsOverlay"]; 
    }
    if (![allKeys containsObject:@"RYD-ENABLED"]) { 
       [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"RYD-ENABLED"]; 
    }
    if (![allKeys containsObject:@"YouPiPEnabled"]) { 
       [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"YouPiPEnabled"]; 
    }
}
