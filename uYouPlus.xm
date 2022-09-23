#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <sys/utsname.h>
#import "Header.h"
#import "Tweaks/YouTubeHeader/YTVideoQualitySwitchOriginalController.h"
#import "Tweaks/YouTubeHeader/YTPlayerView.h"
#import "Tweaks/YouTubeHeader/YTPlayerViewController.h"
#import "Tweaks/YouTubeHeader/YTWatchController.h"
#import "Tweaks/YouTubeHeader/YTIGuideResponse.h"
#import "Tweaks/YouTubeHeader/YTIGuideResponseSupportedRenderers.h"
#import "Tweaks/YouTubeHeader/YTIPivotBarSupportedRenderers.h"
#import "Tweaks/YouTubeHeader/YTIPivotBarRenderer.h"
#import "Tweaks/YouTubeHeader/YTIBrowseRequest.h"
#import "Tweaks/YouTubeHeader/YTCommonColorPalette.h"
#import "Tweaks/YouTubeHeader/ASCollectionView.h"
#import "Tweaks/YouTubeHeader/YTMainAppVideoPlayerOverlayView.h"
#import "Tweaks/YouTubeHeader/YTPlayerOverlay.h"
#import "Tweaks/YouTubeHeader/YTPlayerOverlayProvider.h"
#import "Tweaks/YouTubeHeader/YTReelWatchPlaybackOverlayView.h"
#import "Tweaks/YouTubeHeader/YTReelPlayerBottomButton.h"

// Tweak's bundle for Localizations support - @PoomSmart - https://github.com/PoomSmart/YouPiP/commit/aea2473f64c75d73cab713e1e2d5d0a77675024f
NSBundle *uYouPlusBundle() {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
 	dispatch_once(&onceToken, ^{
        NSString *tweakBundlePath = [[NSBundle mainBundle] pathForResource:@"uYouPlus" ofType:@"bundle"];
        bundle = [NSBundle bundleWithPath:tweakBundlePath];
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
BOOL hideHUD() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"hideHUD_enabled"];
}
BOOL oled() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"oled_enabled"];
}
BOOL oledKB() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"oledKeyBoard_enabled"];
}
BOOL isDarkMode() {
    return ([[NSUserDefaults standardUserDefaults] integerForKey:@"page_style"] == 1);
}
BOOL autoFullScreen() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"autoFull_enabled"];
}
BOOL hideHoverCard() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"hideHoverCards_enabled"];
}
BOOL reExplore() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"reExplore_enabled"];
}
BOOL bigYTMiniPlayer() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"bigYTMiniPlayer_enabled"];
}
BOOL hideCC() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"hideCC_enabled"];
}
BOOL hideAutoplaySwitch() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"hideAutoplaySwitch_enabled"];
}
BOOL hidePreviousAndNextButton() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"hidePreviousAndNextButton_enabled"];
}
BOOL castConfirm() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"castConfirm_enabled"];
}
BOOL ytMiniPlayer() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"ytMiniPlayer_enabled"];
}
BOOL hidePaidPromotionCard() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"hidePaidPromotionCard_enabled"];
}
BOOL fixGoogleSignIn() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"fixGoogleSignIn_enabled"];
}
BOOL replacePreviousAndNextButton() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"replacePreviousAndNextButton_enabled"];
}
BOOL dontEatMyContent() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"dontEatMyContent_enabled"];
}
BOOL ytDisableHighContrastUI() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"ytDisableHighContrastUI_enabled"];
}
BOOL BlueUI() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"BlueUI_enabled"];
}
BOOL RedUI() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"RedUI_enabled"];
}
BOOL OrangeUI() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"OrangeUI_enabled"];
}
BOOL PinkUI() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"PinkUI_enabled"];
}
BOOL PurpleUI() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"PurpleUI_enabled"];
}
BOOL GreenUI() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"GreenUI_enabled"];
}

# pragma mark - Tweaks
// Enable Reorder videos from playlist while on the Watch page - @PoomSmart
%hook YTIPlaylistPanelVideoRenderer 
%new 
- (BOOL)canReorder { return YES; }
%end

// Skips content warning before playing *some videos - @PoomSmart
%hook YTPlayabilityResolutionUserActionUIController
- (void)showConfirmAlert { [self confirmAlertDidPressConfirm]; }
%end

// YTMiniPlayerEnabler: https://github.com/level3tjg/YTMiniplayerEnabler/
%hook YTWatchMiniBarViewController
- (void)updateMiniBarPlayerStateFromRenderer {
    if (ytMiniPlayer()) {}
    else { return %orig; }
}
%end

// Hide CC / Autoplay switch
%hook YTMainAppControlsOverlayView
- (void)setClosedCaptionsOrSubtitlesButtonAvailable:(BOOL)arg1 { // hide CC button
    if (hideCC()) { return %orig(NO); }   
    else { return %orig; }
}
- (void)setAutoplaySwitchButtonRenderer:(id)arg1 { // hide Autoplay
    if (hideAutoplaySwitch()) {}
    else { return %orig; }
}
%end

// Hide Next & Previous button
%group gHidePreviousAndNextButton
%hook YTColdConfig
- (BOOL)removeNextPaddleForSingletonVideos { return YES; }
- (BOOL)removePreviousPaddleForSingletonVideos { return YES; }
%end
%end

// Replace Next & Previous button with Fast forward & Rewind button
%group gReplacePreviousAndNextButton
%hook YTColdConfig
- (BOOL)replaceNextPaddleWithFastForwardButtonForSingletonVods { return YES; }
- (BOOL)replacePreviousPaddleWithRewindButtonForSingletonVods { return YES; }
%end
%end

// Hide HUD Messages
%hook YTHUDMessageView
- (id)initWithMessage:(id)arg1 dismissHandler:(id)arg2 {
    return hideHUD() ? nil : %orig;
}
%end

// Hide Update Dialog: https://github.com/PoomSmart/YouTubeHeader/blob/main/YTGlobalConfig.h
%hook YTGlobalConfig
- (BOOL)shouldBlockUpgradeDialog { return YES;}
%end

// YTAutoFullScreen: https://github.com/PoomSmart/YTAutoFullScreen/
%hook YTPlayerViewController
- (void)loadWithPlayerTransition:(id)arg1 playbackConfig:(id)arg2 {
    %orig;
    if (autoFullScreen())
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
    if (hideHoverCard())
        hidden = YES;
    %orig;
}
%end
 
//YTCastConfirm: https://github.com/JamieBerghmans/YTCastConfirm
%hook MDXPlaybackRouteButtonController
- (void)didPressButton:(id)arg1 {
    if (castConfirm()) {
        UIAlertController* alertController = [%c(UIAlertController) alertControllerWithTitle:LOC(@"CASTING")
                                message:LOC(@"MSG_ARE_YOU_SURE")
                                preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* defaultAction = [%c(UIAlertAction) actionWithTitle:LOC(@"MSG_YES") style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
            %orig;
        }];

        UIAlertAction* noButton = [%c(UIAlertAction)
                                actionWithTitle:LOC(@"MSG_CANCEL")
                                style:UIAlertActionStyleDefault
                                handler: ^(UIAlertAction * action) {
            return;
        }];

        [alertController addAction:defaultAction];
        [alertController addAction:noButton];
        
        id rootViewController = [%c(UIApplication) sharedApplication].delegate.window.rootViewController;
        if ([rootViewController isKindOfClass:[%c(UINavigationController) class]]) {
            rootViewController = ((UINavigationController *)rootViewController).viewControllers.firstObject;
        }
        if ([rootViewController isKindOfClass:[%c(UITabBarController) class]]) {
            rootViewController = ((UITabBarController *)rootViewController).selectedViewController;
        }
        if ([rootViewController presentedViewController] != nil) {
            rootViewController = [rootViewController presentedViewController];
        }
        [rootViewController presentViewController:alertController animated:YES completion:nil];
	} else { return %orig; }
}
%end

// Workaround for MiRO92/uYou-for-YouTube#12, qnblackcat/uYouPlus#263
%hook YTDataUtils
+ (NSMutableDictionary *)spamSignalsDictionary {
    return nil;
}
%end

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

// YTClassicVideoQuality: https://github.com/PoomSmart/YTClassicVideoQuality
%hook YTVideoQualitySwitchControllerFactory
- (id)videoQualitySwitchControllerWithParentResponder:(id)responder {
    Class originalClass = %c(YTVideoQualitySwitchOriginalController);
    return originalClass ? [[originalClass alloc] initWithParentResponder:responder] : %orig;
}
%end

// YTNoCheckLocalNetwork: https://poomsmart.github.io/repo/depictions/ytnochecklocalnetwork.html
%hook YTHotConfig
- (BOOL)isPromptForLocalNetworkPermissionsEnabled { return NO; }
%end

// YouRememberCaption: https://poomsmart.github.io/repo/depictions/youremembercaption.html
%hook YTColdConfig
- (BOOL)respectDeviceCaptionSetting { return NO; }
- (BOOL)isLandscapeEngagementPanelSwipeRightToDismissEnabled { return YES; }
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

// Enable Shorts scroll bar - @PoomSmart
%hook YTReelPlayerViewController
- (BOOL)shouldAlwaysEnablePlayerBar { return YES; }
%end

%hook YTInlinePlayerBarContainerView
- (void)setUserInteractionEnabled:(BOOL)enabled { %orig(YES); }
%end

// Hide YouTube Heatwave in Video Player (YouTube 17.19.2 or newer) - @level3tjg - https://www.reddit.com/r/jailbreak/comments/v29yvk/
%hook YTInlinePlayerBarContainerView
- (BOOL)canShowHeatwave { return NO;}
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
- (void)didTapOverflowButton:(id)sender {
}
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

// Prevent uYou player bar from showing when not playing downloaded media
%hook PlayerManager
- (void)pause {
    if (isnan([self progress]))
        return;
    %orig;
}
%end

// Hide YouTube Shorts banner in Home page? - @MiRO92 - YTNoShorts: https://github.com/MiRO92/YTNoShorts
%hook YTAsyncCollectionView
- (id)cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = %orig;
    if ([cell isKindOfClass:NSClassFromString(@"_ASCollectionViewCell")]) {
        _ASCollectionViewCell *cell = %orig;
        if ([cell respondsToSelector:@selector(node)]) {
            if ([[[cell node] accessibilityIdentifier] isEqualToString:@"statement_banner.view"]) { [self removeShortsAndFeaturesAdsAtIndexPath:indexPath]; }
            if ([[[cell node] accessibilityIdentifier] isEqualToString:@"compact.view"]) { [self removeShortsAndFeaturesAdsAtIndexPath:indexPath]; }
        }
    }
    return %orig;
}

%new
- (void)removeShortsAndFeaturesAdsAtIndexPath:(NSIndexPath *)indexPath {
        [self deleteItemsAtIndexPaths:[NSArray arrayWithObject:indexPath]];
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

// YTNoPaidPromo: https://github.com/PoomSmart/YTNoPaidPromo
%hook YTMainAppVideoPlayerOverlayViewController
- (void)setPaidContentWithPlayerData:(id)data {
    if (hidePaidPromotionCard()) {}
    else { return %orig; }
}
- (void)playerOverlayProvider:(YTPlayerOverlayProvider *)provider didInsertPlayerOverlay:(YTPlayerOverlay *)overlay {
    if ([[overlay overlayIdentifier] isEqualToString:@"player_overlay_paid_content"] && hidePaidPromotionCard()) return;
    %orig;
}
%end

%hook YTInlineMutedPlaybackPlayerOverlayViewController
- (void)setPaidContentWithPlayerData:(id)data {
    if (hidePaidPromotionCard()) {}
    else { return %orig; }
}
%end

# pragma mark - IAmYouTube - https://github.com/PoomSmart/IAmYouTube/
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
%end

// Fix "Google couldn't confirm this attempt to sign in is safe. If you think this is a mistake, you can close and try again to sign in" - qnblackcat/uYouPlus#420
// Thanks to @AhmedBafkir and @kkirby - https://github.com/qnblackcat/uYouPlus/discussions/447#discussioncomment-3672881
%group gFixGoogleSignIn
%hook SSORPCService
+ (id)URLFromURL:(id)arg1 withAdditionalFragmentParameters:(NSDictionary *)arg2 {
    NSURL *orig = %orig;
    NSURLComponents *urlComponents = [[NSURLComponents alloc] initWithURL:orig resolvingAgainstBaseURL:NO];
    NSMutableArray *newQueryItems = [urlComponents.queryItems mutableCopy];
    for (NSURLQueryItem *queryItem in urlComponents.queryItems) {
        if ([queryItem.name isEqualToString:@"system_version"]
         || [queryItem.name isEqualToString:@"app_version"]
         || [queryItem.name isEqualToString:@"kdlc"]
         || [queryItem.name isEqualToString:@"kss"]
         || [queryItem.name isEqualToString:@"lib_ver"]
         || [queryItem.name isEqualToString:@"device_model"]) {
            [newQueryItems removeObject:queryItem];
        }
    }
    urlComponents.queryItems = [newQueryItems copy];
    return urlComponents.URL;
}
%end
%end

// Fix "You can't sign in to this app because Google can't confirm that it's safe" warning when signing in. by julioverne & PoomSmart
// https://gist.github.com/PoomSmart/ef5b172fd4c5371764e027bea2613f93
// https://github.com/qnblackcat/uYouPlus/pull/398
/*
%group gDevice_challenge_request_hack
%hook SSOService
+ (id)fetcherWithRequest:(NSMutableURLRequest *)request configuration:(id)configuration {
    if ([request isKindOfClass:[NSMutableURLRequest class]] && request.HTTPBody) {
        NSError *error = nil;
        NSMutableDictionary *body = [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:NSJSONReadingMutableContainers error:&error];
        if (!error && [body isKindOfClass:[NSMutableDictionary class]]) {
            [body removeObjectForKey:@"device_challenge_request"];
            request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:kNilOptions error:&error];
        }
    }
    return %orig;
}
%end
%end
*/

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

# pragma mark - OLED dark mode by BandarHL
UIColor* raisedColor = [UIColor colorWithRed:0.035 green:0.035 blue:0.035 alpha:1.0];
%group gOLED
%hook YTCommonColorPalette
- (UIColor *)brandBackgroundSolid {
    if (self.pageStyle == 1) {
        return [UIColor blackColor];
    }
        return %orig;
}
- (UIColor *)brandBackgroundPrimary {
    if (self.pageStyle == 1) {
        return [UIColor blackColor];
    }
        return %orig;
}
- (UIColor *)brandBackgroundSecondary {
    if (self.pageStyle == 1) {
        return [[UIColor blackColor] colorWithAlphaComponent:0.9];
    }
        return %orig;
}
- (UIColor *)raisedBackground {
    if (self.pageStyle == 1) {
        return [UIColor blackColor];
    }
        return %orig;
}
- (UIColor *)staticBrandBlack {
    if (self.pageStyle == 1) {
        return [UIColor blackColor];
    }
        return %orig;
}
- (UIColor *)generalBackgroundA {
    if (self.pageStyle == 1) {
        return [UIColor blackColor];
    }
        return %orig;
}
%end

// Account view controller
%hook YTAccountPanelBodyViewController
- (UIColor *)backgroundColor:(NSInteger)pageStyle {
    if (pageStyle == 1) { 
        return [UIColor blackColor]; 
    }
        return %orig;
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
    if (isDarkMode()) {
        return %orig([UIColor blackColor]);
    }
        return %orig;
}
%end

// History Search view
%hook YTSearchBoxView 
- (void)setBackgroundColor:(UIColor *)color { 
    if (isDarkMode()) {
        return %orig([UIColor blackColor]);
    }
        return %orig;
}
%end

// Comment view
%hook YTCommentView
- (void)setBackgroundColor:(UIColor *)color { 
    if (isDarkMode()) {
        return %orig([UIColor blackColor]);
    }
        return %orig;
}
%end

%hook YTCreateCommentAccessoryView
- (void)setBackgroundColor:(UIColor *)color { 
    if (isDarkMode()) {
        return %orig([UIColor blackColor]);
    }
        return %orig;
}
%end

%hook YTCreateCommentTextView
- (void)setBackgroundColor:(UIColor *)color { 
    if (isDarkMode()) {
        return %orig([UIColor blackColor]);
    }
        return %orig;
}
- (void)setTextColor:(UIColor *)color { // fix black text in #Shorts video's comment
    if (isDarkMode()) { 
        return %orig([UIColor whiteColor]); 
    }
        return %orig;
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
    if (isDarkMode()) {
        return %orig([UIColor clearColor]);
    }
        return %orig;
}
%end

// Live chat comment
%hook YCHLiveChatActionPanelView 
- (void)setBackgroundColor:(UIColor *)color {
    if (isDarkMode()) {
        return %orig([UIColor blackColor]);
    }
        return %orig;
}
%end

%hook YTEmojiTextView
- (void)setBackgroundColor:(UIColor *)color {
    if (isDarkMode()) {
        return %orig([UIColor blackColor]);
    }
        return %orig;
}
%end

// Others
%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    if (isDarkMode()) {
        if ([self.nextResponder isKindOfClass:%c(ASScrollView)]) { self.backgroundColor = [UIColor clearColor]; }
        if ([self.accessibilityIdentifier isEqualToString:@"eml.cvr"]) { self.backgroundColor = [UIColor blackColor]; }
        if ([self.accessibilityIdentifier isEqualToString:@"rich_header"]) { self.backgroundColor = [UIColor blackColor]; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment_cell"]) { self.backgroundColor = [UIColor blackColor]; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.ui.cancel.button"]) { self.superview.backgroundColor = [UIColor clearColor]; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.comment_composer"]) { self.backgroundColor = [UIColor blackColor]; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.video_list_entry"]) { self.backgroundColor = [UIColor blackColor]; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.comment.guidelines_text"]) { self.superview.backgroundColor = [UIColor blackColor]; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.comment.channel_guidelines_bottom_sheet_container"]) { self.backgroundColor = [UIColor blackColor]; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.comment.channel_guidelines_entry_banner_container"]) { self.backgroundColor = [UIColor blackColor]; }
    }
}
%end

// Open link with...
%hook ASWAppSwitchingSheetHeaderView
- (void)setBackgroundColor:(UIColor *)color {
    if (isDarkMode()) {
        return %orig(raisedColor);
    }
        return %orig;
}
%end

%hook ASWAppSwitchingSheetFooterView
- (void)setBackgroundColor:(UIColor *)color {
    if (isDarkMode()) {
        return %orig(raisedColor);
    }
        return %orig;
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
%end

# pragma mark - OLED keyboard by @ichitaso <3 - http://gist.github.com/ichitaso/935100fd53a26f18a9060f7195a1be0e
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

%group gDontEatMyContent
%hook YTPlayerViewController

- (void)viewDidAppear:(BOOL)animated {
    YTPlayerView *playerView = [self playerView];
    UIView *renderingViewContainer = MSHookIvar<UIView *>(playerView, "_renderingViewContainer");
    renderingView = [playerView renderingView];

    CGFloat constant = 23; // Make renderingView a bit larger since safe area has sizeable margins from the notch and side borders; tested on iPhone 13 mini

    widthConstraint = [renderingView.widthAnchor constraintEqualToAnchor:renderingViewContainer.safeAreaLayoutGuide.widthAnchor constant:constant];
    heightConstraint = [renderingView.heightAnchor constraintEqualToAnchor:renderingViewContainer.safeAreaLayoutGuide.heightAnchor constant:constant];
    centerXConstraint = [renderingView.centerXAnchor constraintEqualToAnchor:renderingViewContainer.centerXAnchor];
    centerYConstraint = [renderingView.centerYAnchor constraintEqualToAnchor:renderingViewContainer.centerYAnchor];
    
    // playerView.backgroundColor = [UIColor greenColor];
    // renderingViewContainer.backgroundColor = [UIColor redColor];
    // renderingView.backgroundColor = [UIColor blueColor];

    YTMainAppVideoPlayerOverlayViewController *activeVideoPlayerOverlay = [self activeVideoPlayerOverlay];

    // Must check class since YTInlineMutedPlaybackPlayerOverlayViewController doesn't have -(BOOL)isFullscreen
    if ([NSStringFromClass([activeVideoPlayerOverlay class]) isEqualToString:@"YTMainAppVideoPlayerOverlayViewController"] && [activeVideoPlayerOverlay isFullscreen]) {
        activate();
    } else {
        center();
    }
    %orig(animated);
}
- (void)didPressToggleFullscreen {  
    YTMainAppVideoPlayerOverlayViewController *activeVideoPlayerOverlay = [self activeVideoPlayerOverlay];
    
    if (![activeVideoPlayerOverlay isFullscreen]) // Entering fullscreen
        activate();
    else // Exiting fullscreen
        deactivate();
    
    %orig;
}
- (void)didSwipeToEnterFullscreen { 
    %orig; activate(); 
}
- (void)didSwipeToExitFullscreen { 
    %orig; deactivate();
}
- (void)singleVideo:(id)arg1 aspectRatioDidChange:(CGFloat)arg2 {
    aspectRatio = arg2;
    if (aspectRatio == 0.0) { 
        // App backgrounded
    } else if (aspectRatio < THRESHOLD) {
        deactivate();
    } else {
        activate();
    }
    %orig(arg1, arg2);
}
%end

%hook YTVideoZoomOverlayView
- (void)didRecognizePinch:(UIPinchGestureRecognizer *)pinchGestureRecognizer {
    // %log((CGFloat) [pinchGestureRecognizer scale], (CGFloat) [pinchGestureRecognizer velocity]);
    if ([pinchGestureRecognizer velocity] <= 0.0) { // >>Zoom out<<
        zoomedToFill = false;
        activate();
    } else if ([pinchGestureRecognizer velocity] > 0.0) { // <<Zoom in>>
        zoomedToFill = true;
        deactivate();
    }

    %orig(pinchGestureRecognizer);
}
- (void)flashAndHideSnapIndicator {}

// https://github.com/lgariv/UniZoom/blob/master/Tweak.xm
- (void)setSnapIndicatorVisible:(bool)arg1 {
    %orig(NO);
}
%end
%end

%group gYTDisableHighContrastUI
%hook YTCommonColorPalette
- (UIColor *)textPrimary {
     if (self.pageStyle == 1) {
         return [UIColor colorWithRed: 0.56 green: 0.56 blue: 0.56 alpha: 1.00];
     }
         return [UIColor colorWithRed: 0.38 green: 0.38 blue: 0.38 alpha: 1.00];
 }
- (UIColor *)textSecondary {
    if (self.pageStyle == 1) {
        return [UIColor colorWithRed: 0.56 green: 0.56 blue: 0.56 alpha: 1.00];
     }
        return [UIColor colorWithRed: 0.38 green: 0.38 blue: 0.38 alpha: 1.00];
 }
%end
%end

%group gBlueUI
%hook YTCommonColorPalette
- (UIColor *)textPrimary {
     if (self.pageStyle == 1) {
         return [UIColor colorWithRed: 0.26 green: 0.43 blue: 0.48 alpha: 1.00];
     }
         return [UIColor colorWithRed: 0.36 green: 0.56 blue: 0.62 alpha: 1.00];
 }
- (UIColor *)textSecondary {
    if (self.pageStyle == 1) {
        return [UIColor colorWithRed: 0.26 green: 0.43 blue: 0.48 alpha: 1.00];
     }
        return [UIColor colorWithRed: 0.36 green: 0.56 blue: 0.62 alpha: 1.00];
 }
%end
%end

%group gRedUI
%hook YTCommonColorPalette
- (UIColor *)textPrimary {
     if (self.pageStyle == 1) {
         return [UIColor colorWithRed: 1.00 green: 0.31 blue: 0.27 alpha: 1.00];
     }
         return [UIColor colorWithRed: 0.84 green: 0.25 blue: 0.23 alpha: 1.00];
 }
- (UIColor *)textSecondary {
    if (self.pageStyle == 1) {
        return [UIColor colorWithRed: 1.00 green: 0.31 blue: 0.27 alpha: 1.00];
     }
        return [UIColor colorWithRed: 0.84 green: 0.25 blue: 0.23 alpha: 1.00];
 }
%end
%end

%group gOrangeUI
%hook YTCommonColorPalette
- (UIColor *)textPrimary {
     if (self.pageStyle == 1) {
         return [UIColor colorWithRed: 0.73 green: 0.45 blue: 0.05 alpha: 1.00];
     }
         return [UIColor colorWithRed: 0.80 green: 0.49 blue: 0.05 alpha: 1.00];
 }
- (UIColor *)textSecondary {
    if (self.pageStyle == 1) {
        return [UIColor colorWithRed: 0.73 green: 0.45 blue: 0.05 alpha: 1.00];
     }
        return [UIColor colorWithRed: 0.80 green: 0.49 blue: 0.05 alpha: 1.00];
 }
%end
%end

%group gPinkUI
%hook YTCommonColorPalette
- (UIColor *)textPrimary {
     if (self.pageStyle == 1) {
         return [UIColor colorWithRed: 0.74 green: 0.02 blue: 0.46 alpha: 1.00];
     }
         return [UIColor colorWithRed: 0.81 green: 0.56 blue: 0.71 alpha: 1.00];
 }
- (UIColor *)textSecondary {
    if (self.pageStyle == 1) {
        return [UIColor colorWithRed: 0.74 green: 0.02 blue: 0.46 alpha: 1.00];
     }
        return [UIColor colorWithRed: 0.81 green: 0.56 blue: 0.71 alpha: 1.00];
 }
%end
%end

%group gPurpleUI
%hook YTCommonColorPalette
- (UIColor *)textPrimary {
     if (self.pageStyle == 1) {
         return [UIColor colorWithRed: 0.62 green: 0.01 blue: 0.73 alpha: 1.00];
     }
         return [UIColor colorWithRed: 0.44 green: 0.00 blue: 0.52 alpha: 1.00];
 }
- (UIColor *)textSecondary {
    if (self.pageStyle == 1) {
        return [UIColor colorWithRed: 0.62 green: 0.01 blue: 0.73 alpha: 1.00];
     }
        return [UIColor colorWithRed: 0.44 green: 0.00 blue: 0.52 alpha: 1.00];
 }
%end
%end

%group gGreenUI
%hook YTCommonColorPalette
- (UIColor *)textPrimary {
     if (self.pageStyle == 1) {
         return [UIColor colorWithRed: 0.01 green: 0.66 blue: 0.18 alpha: 1.00];
     }
         return [UIColor colorWithRed: 0.00 green: 0.50 blue: 0.13 alpha: 1.00];
 }
- (UIColor *)textSecondary {
    if (self.pageStyle == 1) {
        return [UIColor colorWithRed: 0.01 green: 0.66 blue: 0.18 alpha: 1.00];
     }
        return [UIColor colorWithRed: 0.00 green: 0.50 blue: 0.13 alpha: 1.00];
 }
%end
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

# pragma mark - ctor
%ctor {
    %init;
    if (![[[[NSUserDefaults standardUserDefaults] dictionaryRepresentation] allKeys] containsObject:@"relatedVideosAtTheEndOfYTVideos"]) { 
       [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"relatedVideosAtTheEndOfYTVideos"]; 
    }
    if (oled()) {
       %init(gOLED);
    }
    if (oledKB()) {
       %init(gOLEDKB);
    }
    if (reExplore()) {
       %init(gReExplore);
    }
    if (bigYTMiniPlayer() && (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad)) {
       %init(Main);
    }
    if (hidePreviousAndNextButton()) {
       %init(gHidePreviousAndNextButton);
    }
    if (replacePreviousAndNextButton()) {
       %init(gReplacePreviousAndNextButton);
    }
    if (dontEatMyContent()) {
        %init(gDontEatMyContent);
    }
    if (@available(iOS 16, *)) {
       %init(iOS16);
    }
    if (!fixGoogleSignIn()) {
       %init(gFixGoogleSignIn);
    }
    if (ytDisableHighContrastUI()) {
       %init(gYTDisableHighContrastUI);
    }
    if (BlueUI()) {
       %init(gBlueUI);
    }
    if (RedUI()) {
       %init(gRedUI);
    }
    if (OrangeUI()) {
       %init(gOrangeUI);
    }
    if (PinkUI()) {
       %init(gPinkUI);
    }
    if (PurpleUI()) {
       %init(gPurpleUI);
    }
    if (GreenUI()) {
       %init(gGreenUI);
    }
}
