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

// Notifications Tab appearance
UIImage *resizeImage(UIImage *image, CGSize newSize) {
    UIGraphicsBeginImageContextWithOptions(newSize, NO, 0.0);
    [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    UIImage *resizedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return resizedImage;
}

static int getNotificationIconStyle() {
    return [[NSUserDefaults standardUserDefaults] integerForKey:@"notificationIconStyle"];
}

// Notifications Tab - @arichornlover & @dayanch96
%group gShowNotificationsTab
%hook YTAppPivotBarItemStyle
- (UIImage *)pivotBarItemIconImageWithIconType:(int)type color:(UIColor *)color useNewIcons:(BOOL)isNew selected:(BOOL)isSelected {
    NSString *imageName;
    UIColor *iconColor;
    switch (getNotificationIconStyle()) {
        case 1:  // Thin outline style (2020+)
            imageName = isSelected ? @"notifications_selected" : @"notifications_24pt";
            iconColor = [%c(YTColor) white1];
            break;
        case 2:  // Filled style (2018+)
            imageName = @"notifications_selected";
            iconColor = isSelected ? [%c(YTColor) white1] : [UIColor grayColor];
            break;
        case 3:  // Inbox style (2014+)
            imageName = @"inbox_selected";
            iconColor = isSelected ? [%c(YTColor) white1] : [UIColor grayColor];
            break;
        default:  // Default style
            imageName = isSelected ? @"notifications_selected" : @"notifications_unselected";
            iconColor = [%c(YTColor) white1];
            break;
    }
    NSString *imagePath = [tweakBundle pathForResource:imageName ofType:@"png" inDirectory:@"UI"];
    UIImage *image = [UIImage imageWithContentsOfFile:imagePath];
    CGSize newSize = CGSizeMake(24, 24);
    image = resizeImage(image, newSize);
    image = [%c(QTMIcon) tintImage:image color:iconColor];
    return type == YT_NOTIFICATIONS ? image : %orig;
}
%end
%hook YTPivotBarView
- (void)setRenderer:(YTIPivotBarRenderer *)renderer {
    @try {
	YTIBrowseEndpoint *endPoint = [[%c(YTIBrowseEndpoint) alloc] init];
	[endPoint setBrowseId:@"FEnotifications_inbox"];
	YTICommand *command = [[%c(YTICommand) alloc] init];
	[command setBrowseEndpoint:endPoint];

	YTIPivotBarItemRenderer *itemBar = [[%c(YTIPivotBarItemRenderer) alloc] init];
	[itemBar setPivotIdentifier:@"FEnotifications_inbox"];
	YTIIcon *icon = [itemBar icon];
	[icon setIconType:YT_NOTIFICATIONS];
	[itemBar setNavigationEndpoint:command];

	YTIFormattedString *formatString;
	if (getNotificationIconStyle() == 3) {
		formatString = [%c(YTIFormattedString) formattedStringWithString:@"Inbox"];
	} else {
		formatString = [%c(YTIFormattedString) formattedStringWithString:@"Notifications"];
	}
	[itemBar setTitle:formatString];

	YTIPivotBarSupportedRenderers *barSupport = [[%c(YTIPivotBarSupportedRenderers) alloc] init];
	[barSupport setPivotBarItemRenderer:itemBar];

        [renderer.itemsArray addObject:barSupport];
    } @catch (NSException *exception) {
        NSLog(@"Error setting renderer: %@", exception.reason);
    }
    %orig(renderer);
}
%end
%hook YTBrowseViewController
- (void)viewDidLoad {
    %orig;
    @try {
        YTICommand *navEndpoint = [self valueForKey:@"_navEndpoint"];
        if ([navEndpoint.browseEndpoint.browseId isEqualToString:@"FEnotifications_inbox"]) {
            UIViewController *notificationsViewController = [[UIViewController alloc] init];
            [self addChildViewController:notificationsViewController];
            // FIXME: View issues
            [notificationsViewController.view setFrame:CGRectMake(0.0f, 0.0f, self.view.frame.size.width, self.view.frame.size.height)];
            [self.view addSubview:notificationsViewController.view];
            [self.view endEditing:YES];
            [notificationsViewController didMoveToParentViewController:self];
        }
    } @catch (NSException *exception) {
        NSLog(@"Cannot show notifications view controller: %@", exception.reason);
    }
}
%end
%end

// YTHidePlayerButtons 1.0.0 - made by @aricloverEXTRA
static NSDictionary<NSString *, NSString *> *HideToggleMap(void) {
    static NSDictionary<NSString *, NSString *> *map = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            // identifiers
            @"id.video.share.button": @"hideShareButton_enabled",
            @"id.ui.add_to.offline.button": @"hideDownloadButton_enabled",
            @"id.video.remix.button": @"hideRemixButton_enabled",
            @"clip_button.eml": @"hideClipButton_enabled",
            @"id.ui.carousel_header": @"hideCommentSection_enabled",
            // fallbacks
            @"Like": @"hideLikeButton_enabled", // unidentified identifier
            @"Dislike": @"hideDislikeButton_enabled", // unidentified identifier
            @"Share": @"hideShareButton_enabled", // Share Button
            @"Ask": @"hideAskButton_enabled", // unidentified identifier
            @"Download": @"hideDownloadButton_enabled", // Download Button
            @"Hype": @"hideHypeButton_enabled", // unidentified identifier
            @"Thanks": @"hideThanksButton_enabled", // unidentified identifier
            @"Remix": @"hideRemixButton_enabled", // Remix Button
            @"Clip": @"hideClipButton_enabled", // Clip Button
            @"Save to playlist": @"hideSaveToPlaylistButton_enabled", // unidentified identifier
            @"Report": @"hideReportButton_enabled", // unidentified identifier
            @"connect account": @"hideConnectButton_enabled" // unidentified identifier
        };
    });
    return map;
}
static BOOL shouldHideForKey(NSString *key) {
    if (!key) return NO;
    NSString *pref = HideToggleMap()[key];
    if (!pref) return NO;
    return IS_ENABLED(pref);
}
static void safeHideView(id view) {
    if (!view) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            if ([view respondsToSelector:@selector(setHidden:)]) {
                [view setHidden:YES];
                return;
            }
            if ([view isKindOfClass:[UIView class]]) {
                ((UIView *)view).hidden = YES;
                return;
            }
        } @catch (NSException *ex) {
            NSLog(@"[HidePlayerButtons] safeHideView exception: %@", ex);
        }
    });
}
static BOOL inspectAndHideIfMatch(id view) {
    if (!view) return NO;
    @try {
        NSString *accId = nil;
        if ([view respondsToSelector:@selector(accessibilityIdentifier)]) {
            @try { accId = [view accessibilityIdentifier]; } @catch (NSException *e) { accId = nil; }
            if (accId && shouldHideForKey(accId)) {
                safeHideView(view);
                return YES;
            }
        }
        NSString *accLabel = nil;
        if ([view respondsToSelector:@selector(accessibilityLabel)]) {
            @try { accLabel = [view accessibilityLabel]; } @catch (NSException *e) { accLabel = nil; }
            if (accLabel && shouldHideForKey(accLabel)) {
                safeHideView(view);
                return YES;
            }
        }
        NSString *desc = nil;
        @try { desc = [[view description] copy]; } @catch (NSException *e) { desc = nil; }
        if (desc) {
            for (NSString *key in HideToggleMap().allKeys) {
                if ([desc containsString:key] && shouldHideForKey(key)) {
                    safeHideView(view);
                    return YES;
                }
            }
        }
    } @catch (NSException *ex) {
        NSLog(@"[HidePlayerButtons] inspectAndHideIfMatch exception: %@", ex);
    }
    return NO;
}
static void traverseAndHideViews(UIView *root) {
    if (!root) return;
    @try {
        inspectAndHideIfMatch(root);
        NSArray<UIView *> *subs = nil;
        @try { subs = root.subviews; } @catch (NSException *e) { subs = nil; }
        if (subs && subs.count) {
            for (UIView *sv in subs) {
                if ([sv isKindOfClass:[UIView class]]) {
                    traverseAndHideViews(sv);
                }
            }
        }
    } @catch (NSException *ex) {
        NSLog(@"[HidePlayerButtons] traverseAndHideViews exception: %@", ex);
    }
}
static void hideButtonsInActionBarIfNeeded(id collectionView) {
    if (!collectionView) return;
    @try {
        // Ensure the collectionView has accessibilityIdentifier and we only operate on the action bar
        NSString *accId = nil;
        if ([collectionView respondsToSelector:@selector(accessibilityIdentifier)]) {
            @try { accId = [collectionView accessibilityIdentifier]; } @catch (NSException *e) { accId = nil; }
        }
        if (!accId) return;
        if (![accId isEqualToString:@"id.video.scrollable_action_bar"]) return;
        NSArray *cells = nil;
        if ([collectionView respondsToSelector:@selector(visibleCells)]) {
            @try { cells = [collectionView visibleCells]; } @catch (NSException *e) { cells = nil; }
        }
        if (!cells || cells.count == 0) {
            @try { cells = [collectionView subviews]; } @catch (NSException *e) { cells = nil; }
        }
        if (!cells || cells.count == 0) return;
        for (id cell in cells) {
            if ([cell isKindOfClass:[UIView class]]) {
                traverseAndHideViews((UIView *)cell);
            } else {
                @try {
                    if ([cell respondsToSelector:@selector(view)]) {
                        id view = [cell performSelector:@selector(view)];
                        if ([view isKindOfClass:[UIView class]]) {
                            traverseAndHideViews((UIView *)view);
                        }
                    } else if ([cell respondsToSelector:@selector(node)]) {
                        NSString *desc = nil;
                        @try { desc = [cell description]; } @catch (NSException *e) { desc = nil; }
                        if (desc) {
                            // Not ideal to act on description, but we keep this non-destructive: only log for debugging
                            // Uncomment logging for debug builds if needed.
                            // NSLog(@"[HidePlayerButtons] Non-UIView cell description: %@", desc);
                        }
                    }
                } @catch (NSException *ex) {
                    NSLog(@"[HidePlayerButtons] Exception handling non-UIView cell: %@", ex);
                }
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"[HidePlayerButtons] hideButtonsInActionBarIfNeeded exception: %@", exception);
    }
}
%hook ASCollectionView
- (id)nodeForItemAtIndexPath:(NSIndexPath *)indexPath {
    id node = %orig;
    id weakSelf = (id)self;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            hideButtonsInActionBarIfNeeded(weakSelf);
        } @catch (NSException *e) {
            NSLog(@"[HidePlayerButtons] async hide exception: %@", e);
        }
    });
    return node;
}
- (void)nodesDidRelayout:(NSArray *)nodes {
    %orig;
    id weakSelf = (id)self;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            hideButtonsInActionBarIfNeeded(weakSelf);
        } @catch (NSException *e) {
            NSLog(@"[HidePlayerButtons] relayout hide exception: %@", e);
        }
    });
}
%end

// Replace YouTube's download with uYou's
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
            ELMPBIdentifierProperties *identifierProperties = [properties firstSubmessage];
            // 19.30.2
            if ([identifierProperties respondsToSelector:@selector(identifier)]) {
                NSString *identifier = [identifierProperties identifier];
                if ([identifier containsString:@"offline_upsell_dialog"]) {
                    if ([controlsOverlayView respondsToSelector:@selector(uYou)]) {
                        [controlsOverlayView uYou];
                    }
                    return;
                }
            }
            // 19.20.2
            NSString *description = [identifierProperties description];
            if ([description containsString:@"offline_upsell_dialog"]) {
                if ([controlsOverlayView respondsToSelector:@selector(uYou)]) {
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

// Fixes uYou crash when trying to play video (#1422)
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

// Enable Alternate Icons - @arichornlover
%hook UIApplication
- (BOOL)supportsAlternateIcons {
    return YES;
}
%end

// uYou AdBlock Workaround LITE (This Version will only remove ads from only Videos/Shorts!) - @PoomSmart
%group uYouAdBlockingWorkaroundLite
%hook YTHotConfig
- (BOOL)disableAfmaIdfaCollection { return NO; }
%end

%hook YTIPlayerResponse
- (BOOL)isMonetized { return NO; }
%new(@@:)
- (NSMutableArray *)playerAdsArray {
    return [NSMutableArray array];
}
%new(@@:)
- (NSMutableArray *)adSlotsArray {
    return [NSMutableArray array];
}
%end

%hook YTIClientMdxGlobalConfig
%new(B@:)
- (BOOL)enableSkippableAd { return YES; }
%end

%hook YTHotConfig
- (BOOL)clientInfraClientConfigIosEnableFillingEncodedHacksInnertubeContext { return NO; }
%end

%hook YTAdShieldUtils
+ (id)spamSignalsDictionary { return @{}; }
+ (id)spamSignalsDictionaryWithoutIDFA { return @{}; }
%end

%hook YTDataUtils
+ (id)spamSignalsDictionary { return @{ @"ms": @"" }; }
+ (id)spamSignalsDictionaryWithoutIDFA { return @{}; }
%end

%hook YTAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context { %orig(nil); }
%end

%hook YTAccountScopedAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context { %orig(nil); }
%end

%hook YTLocalPlaybackController
- (id)createAdsPlaybackCoordinator { return nil; }
%end

%hook MDXSession
- (void)adPlaying:(id)ad {}
%end

%hook YTReelInfinitePlaybackDataSource
- (YTReelModel *)makeContentModelForEntry:(id)entry {
    YTReelModel *model = %orig;
    if ([model respondsToSelector:@selector(videoType)] && model.videoType == 3)
        return nil;
    return model;
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
%new(@@:)
- (NSMutableArray *)playerAdsArray {
    return [NSMutableArray array];
}
%new(@@:)
- (NSMutableArray *)adSlotsArray {
    return [NSMutableArray array];
}
%end
%hook YTIClientMdxGlobalConfig
%new(B@:)
- (BOOL)enableSkippableAd { return YES; }
%end
%hook YTHotConfig
- (BOOL)clientInfraClientConfigIosEnableFillingEncodedHacksInnertubeContext { return NO; }
%end
%hook YTAdShieldUtils
+ (id)spamSignalsDictionary { return @{}; }
+ (id)spamSignalsDictionaryWithoutIDFA { return @{}; }
%end
%hook YTDataUtils
+ (id)spamSignalsDictionary { return @{ @"ms": @"" }; }
+ (id)spamSignalsDictionaryWithoutIDFA { return @{}; }
%end
%hook YTAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context { %orig(nil); }
%end
%hook YTAccountScopedAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context { %orig(nil); }
%end
%hook YTLocalPlaybackController
- (id)createAdsPlaybackCoordinator { return nil; }
%end
%hook MDXSession
- (void)adPlaying:(id)ad {}
%end
%hook YTReelDataSource
- (YTReelModel *)makeContentModelForEntry:(id)entry {
    YTReelModel *model = %orig;
    if ([model respondsToSelector:@selector(videoType)] && model.videoType == 3)
        return nil;
    return model;
}
%end
%hook YTReelInfinitePlaybackDataSource
- (YTReelModel *)makeContentModelForEntry:(id)entry {
    YTReelModel *model = %orig;
    if ([model respondsToSelector:@selector(videoType)] && model.videoType == 3)
        return nil;
    return model;
}
- (void)setReels:(NSMutableOrderedSet <YTReelModel *> *)reels {
    [reels removeObjectsAtIndexes:[reels indexesOfObjectsPassingTest:^BOOL(YTReelModel *obj, NSUInteger idx, BOOL *stop) {
        return [obj respondsToSelector:@selector(videoType)] ? obj.videoType == 3 : NO;
    }]];
    %orig;
}
%end
NSString *getAdString(NSString *description) {
    for (NSString *str in @[        @"brand_promo",
        @"carousel_footered_layout",
        @"carousel_headered_layout",
        @"eml.expandable_metadata",
        @"feed_ad_metadata",
        @"full_width_portrait_image_layout",
        @"full_width_square_image_layout",
        @"landscape_image_wide_button_layout",
        @"post_shelf",
        @"product_carousel",
        @"product_engagement_panel",
        @"product_item",
        @"shopping_carousel",
        @"shopping_item_card_list",
        @"statement_banner",
        @"square_image_layout",
        @"text_image_button_layout",
        @"text_search_ad",
        @"video_display_full_layout",
        @"video_display_full_buttoned_layout"
    ]) 
        if ([description containsString:str]) return str;

    return nil;
}
static BOOL isAdRenderer(YTIElementRenderer *elementRenderer, int kind) {
    if ([elementRenderer respondsToSelector:@selector(hasCompatibilityOptions)] && elementRenderer.hasCompatibilityOptions && elementRenderer.compatibilityOptions.hasAdLoggingData) {
        HBLogDebug(@"YTX adLogging %d %@", kind, elementRenderer);
        return YES;
    }
    NSString *description = [elementRenderer description];
    NSString *adString = getAdString(description);
    if (adString) {
        HBLogDebug(@"YTX getAdString %d %@ %@", kind, adString, elementRenderer);
        return YES;
    }
    return NO;
}
static NSMutableArray <YTIItemSectionRenderer *> *filteredArray(NSArray <YTIItemSectionRenderer *> *array) {
    NSMutableArray <YTIItemSectionRenderer *> *newArray = [array mutableCopy];
    NSIndexSet *removeIndexes = [newArray indexesOfObjectsPassingTest:^BOOL(YTIItemSectionRenderer *sectionRenderer, NSUInteger idx, BOOL *stop) {
        if ([sectionRenderer isKindOfClass:%c(YTIShelfRenderer)]) {
            YTIShelfSupportedRenderers *content = ((YTIShelfRenderer *)sectionRenderer).content;
            YTIHorizontalListRenderer *horizontalListRenderer = content.horizontalListRenderer;
            NSMutableArray <YTIHorizontalListSupportedRenderers *> *itemsArray = horizontalListRenderer.itemsArray;
            NSIndexSet *removeItemsArrayIndexes = [itemsArray indexesOfObjectsPassingTest:^BOOL(YTIHorizontalListSupportedRenderers *horizontalListSupportedRenderers, NSUInteger idx2, BOOL *stop2) {
                YTIElementRenderer *elementRenderer = horizontalListSupportedRenderers.elementRenderer;
                return isAdRenderer(elementRenderer, 4);
            }];
            [itemsArray removeObjectsAtIndexes:removeItemsArrayIndexes];
        }
        if (![sectionRenderer isKindOfClass:%c(YTIItemSectionRenderer)])
            return NO;
        NSMutableArray <YTIItemSectionSupportedRenderers *> *contentsArray = sectionRenderer.contentsArray;
        if (contentsArray.count > 1) {
            NSIndexSet *removeContentsArrayIndexes = [contentsArray indexesOfObjectsPassingTest:^BOOL(YTIItemSectionSupportedRenderers *sectionSupportedRenderers, NSUInteger idx2, BOOL *stop2) {
                YTIElementRenderer *elementRenderer = sectionSupportedRenderers.elementRenderer;
                return isAdRenderer(elementRenderer, 3);
            }];
            [contentsArray removeObjectsAtIndexes:removeContentsArrayIndexes];
        }
        YTIItemSectionSupportedRenderers *firstObject = [contentsArray firstObject];
        YTIElementRenderer *elementRenderer = firstObject.elementRenderer;
        return isAdRenderer(elementRenderer, 2);
    }];
    [newArray removeObjectsAtIndexes:removeIndexes];
    return newArray;
}
%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    if (([self.accessibilityIdentifier isEqualToString:@"eml.expandable_metadata.vpp"]))
        [self removeFromSuperview];
}
%end
%hook YTInnerTubeCollectionViewController
- (void)displaySectionsWithReloadingSectionControllerByRenderer:(id)renderer {
    NSMutableArray *sectionRenderers = [self valueForKey:@"_sectionRenderers"];
    [self setValue:filteredArray(sectionRenderers) forKey:@"_sectionRenderers"];
    %orig;
}
- (void)addSectionsFromArray:(NSArray <YTIItemSectionRenderer *> *)array {
    %orig(filteredArray(array));
}
%end
%end

/*
// Settings Menu with Blur Style - @arichornlover
%group gSettingsStyle
%hook YTWrapperSplitView
- (void)viewDidLoad {
    [super viewDidLoad];
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.frame = self.view.bounds;
    blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:blurView];
    [self.view sendSubviewToBack:blurView];
    // Apply dark theme if pageStyle is set to dark
    if ([[NSUserDefaults standardUserDefaults] integerForKey:@"page_style"] == 1) {
        self.view.backgroundColor = [UIColor blackColor];
    }
}
%end
%end
*/

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

// Center YouTube Logo - @arichornlover
%group gCenterYouTubeLogo 
%hook YTNavigationBarTitleView
- (void)setShouldCenterNavBarTitleView:(BOOL)center {
    center = YES;
    %orig(center);
    [self alignCustomViewToCenterOfWindow];
}
- (BOOL)shouldCenterNavBarTitleView {
    return YES;
}
%end
%end

// YTMiniPlayerEnabler: https://github.com/level3tjg/YTMiniplayerEnabler/
%hook YTWatchMiniBarViewController
- (void)updateMiniBarPlayerStateFromRenderer {
    if (IS_ENABLED(kYTMiniPlayer)) {}
    else { return %orig; }
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
%hook YTHeaderLogoControllerImpl // originally was "YTHeaderLogoController"
- (void)setTopbarLogoRenderer:(YTITopbarLogoRenderer *)renderer {
    // Modify the type of the icon before setting the renderer
    YTIIcon *icon = renderer.iconImage;
    if (icon) {
        icon.iconType = YT_PREMIUM_LOGO; // magic number (537) for Premium icon, hopefully it doesnt change. 158 (YT_DEFAULT_LOGO) is default logo.
        }
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
                        icon.iconType = YT_PREMIUM_STANDALONE; // Magic number (741) for premium icon
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
            newItemSectionSupportedRenderers.compactListItemRenderer.thumbnail.iconThumbnailRenderer.icon.iconType = YT_DOWNLOADS_OUTLINE; // original icon number was 147
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
    if (IS_ENABLED(kHidePaidPromotionCard)) {}
    else { return %orig; }
}
- (void)playerOverlayProvider:(YTPlayerOverlayProvider *)provider didInsertPlayerOverlay:(YTPlayerOverlay *)overlay {
    if ([[overlay overlayIdentifier] isEqualToString:@"player_overlay_paid_content"] && IS_ENABLED(kHidePaidPromotionCard)) return;
    %orig;
}
%end

%hook YTInlineMutedPlaybackPlayerOverlayViewController
- (void)setPaidContentWithPlayerData:(id)data {
    if (IS_ENABLED(kHidePaidPromotionCard)) {}
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

// Disable Rounded Hints with no Rounded Corners - @arichornlover
%group gDisableRoundedHints
%hook YTBubbleHintView // Disable Modern/Rounded Hints
+ (BOOL)modernRoundedCornersEnabled { return NO; }
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
    if (IS_ENABLED(kHideiSponsorBlockButton)) { 
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

%hook YTColdConfig
- (BOOL)speedMasterArm2FastForwardWithoutSeekBySliding {
    return IS_ENABLED(kSlideToSeek) ? NO : %orig;
}
%end

// Disable double tap to seek
%hook YTDoubleTapToSeekController
- (void)enableDoubleTapToSeek:(BOOL)arg1 {
    return IS_ENABLED(kDoubleTapToSeek) ? %orig(NO) : %orig;
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

// Video Controls Overlay Options
// Hide CC / Hide Autoplay switch / Hide YTMusic Button / Enable Share Button / Enable Save to Playlist Button
%hook YTMainAppControlsOverlayView
- (void)setClosedCaptionsOrSubtitlesButtonAvailable:(BOOL)arg1 { // hide CC button
    return IS_ENABLED(kHideCC) ? %orig(NO) : %orig;
}
- (void)setAutoplaySwitchButtonRenderer:(id)arg1 { // hide Autoplay
    if (IS_ENABLED(kHideAutoplaySwitch)) {}
    else { return %orig; }
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

/*
// LEGACY VERSION ⚠️
// Hide Fullscreen Button - @arichornlover - PoomSmart's 1.2.0+ Versions of the *YouQuality* tweak makes the button invisible when enabling this
%hook YTInlinePlayerBarContainerView
- (void)layoutSubviews {
    %orig; 
    if (IS_ENABLED(kDisableFullscreenButton)) {
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
*/

// NEW VERSION
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

// Hide HUD Messages
%hook YTHUDMessageView
- (id)initWithMessage:(id)arg1 dismissHandler:(id)arg2 {
    return IS_ENABLED(kHideHUD) ? nil : %orig;
}
%end

// Hide Channel Watermark
%hook YTColdConfig
- (BOOL)iosEnableFeaturedChannelWatermarkOverlayFix {
    return IS_ENABLED(kHideChannelWatermark) ? NO : %orig;
}
%end
%hook YTAnnotationsViewController
- (void)loadFeaturedChannelWatermark {
    if (IS_ENABLED(kHideChannelWatermark)) {}
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

// Hide Video Title when in Fullscreen - @arichornlover
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

// Disable the right panel in fullscreen mode
%hook YTColdConfig
- (BOOL)isLandscapeEngagementPanelEnabled {
    return IS_ENABLED(kHideRightPanel) ? NO : %orig;
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

// Hide Shorts Cells - for uYou 3.0.4+ (PoomSmart/YTUnShorts)
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
    if (IS_ENABLED(kHideSubscriptions)) {}
    else { return %orig; }
}
%end

/* DISABLED DUE TO CONFLICTS
// Hide Community Posts - @michael-winay, @arichornlover, @iCrazeiOS @PoomSmart & @Dayanch96
%hook YTIElementRenderer
- (NSData *)elementData {
    NSString *description = [self description];
    if (IS_ENABLED(kHideCommunityPosts)) {
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
- (void)setBackgroundColor:(UIColor *)color {
    NSString *description = [self description];
    if ([description containsString:@"eml.compact_subscribe_button"]) {
        if (IS_ENABLED(@"kRedSubscribeButton")) {
            color = [UIColor redColor];
        }
    }
    // Hide the Button Containers under the Video Player - 17.33.2 and up - @arichornlover
    if (IS_ENABLED(kHideButtonContainers)) {
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

// YT startup animation
%hook YTColdConfig
- (BOOL)mainAppCoreClientIosEnableStartupAnimation {
    return IS_ENABLED(kYTStartupAnimation) ? YES : NO;
}
%end

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

// Hide "Play next in queue" - qnblackcat/uYouPlus#1138
%hook YTMenuItemVisibilityHandler
- (BOOL)shouldShowServiceItemRenderer:(YTIMenuConditionalServiceItemRenderer *)renderer {
    return IS_ENABLED(kHidePlayNextInQueue) && renderer.icon.iconType == YT_QUEUE_PLAY_NEXT ? NO : %orig;
}
%end

%hook YTMenuItemVisibilityHandlerImpl
- (BOOL)shouldShowServiceItemRenderer:(YTIMenuConditionalServiceItemRenderer *)renderer {
    return IS_ENABLED(kHidePlayNextInQueue) && renderer.icon.iconType == YT_QUEUE_PLAY_NEXT ? NO : %orig;
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
/*
    if (IS_ENABLED(kSettingsStyle_enabled)) {
        %init(gSettingsStyle);
    }
*/
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
    if (IS_ENABLED(kShowNotificationsTab)) {
        %init(gShowNotificationsTab);
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
    if (IS_ENABLED(kDisableRoundedHints)) {
        %init(gDisableRoundedHints);
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
    if (IS_ENABLED(kYouTabFakePremium)) {
        %init(gFakePremium);
    }
    if (IS_ENABLED(kDisablePullToFull)) {
        %init(gDisablePullToFull);
    }
    if (IS_ENABLED(kAdBlockWorkaroundLite)) {
        %init(uYouAdBlockingWorkaroundLite);
    }
    if (IS_ENABLED(kAdBlockWorkaround)) {
        %init(uYouAdBlockingWorkaround);
    }
    if (IS_ENABLED(kHideHomeTab)) {
        %init(gHideHomeTab);
    }
    if (IS_ENABLED(kAutoHideHomeBar)) {
        %init(gAutoHideHomeBar);
    }
    if (IS_ENABLED(kHideDoubleTapToSeekOverlay)) {
        %init(gHideDoubleTapToSeekOverlay);
    }
    if (IS_ENABLED(kShortsQualityPicker)) {
        %init(gShortsQualityPicker);
    }
    if (IS_ENABLED(kFixCasting)) {
        %init(gFixCasting);
    }

    // YTNoModernUI - @arichornlover
    BOOL ytNoModernUIEnabled = IS_ENABLED(kYTNoModernUI);
    if (ytNoModernUIEnabled) {
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        [userDefaults setBool:NO forKey:kEnableVersionSpoofer];
    } else {
        BOOL enableVersionSpooferEnabled = IS_ENABLED(kEnableVersionSpoofer);

        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        [userDefaults setBool:enableVersionSpooferEnabled forKey:kEnableVersionSpoofer];
    }
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setBool:ytNoModernUIEnabled ? ytNoModernUIEnabled : [userDefaults boolForKey:kDisableModernButtons] forKey:kDisableModernButtons];
    [userDefaults setBool:ytNoModernUIEnabled ? ytNoModernUIEnabled : [userDefaults boolForKey:kDisableRoundedHints] forKey:kDisableRoundedHints];
    [userDefaults setBool:ytNoModernUIEnabled ? ytNoModernUIEnabled : [userDefaults boolForKey:kDisableModernFlags] forKey:kDisableModernFlags];
    [userDefaults setBool:ytNoModernUIEnabled ? ytNoModernUIEnabled : [userDefaults boolForKey:kDisableAmbientMode] forKey:kDisableAmbientMode];
    [userDefaults setBool:ytNoModernUIEnabled ? ytNoModernUIEnabled : [userDefaults boolForKey:kRedProgressBar] forKey:kRedProgressBar];

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
