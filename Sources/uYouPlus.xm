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
        case 1:  // Bold outline style (2024+)
            imageName = isSelected ? @"notifications_selected" : @"notifications_unselected";
            iconColor = [%c(YTColor) white1];
            break;
        case 2:  // Thin outline style (2020+)
            imageName = isSelected ? @"notifications_selected" : @"notifications_24pt";
            iconColor = [%c(YTColor) white1];
            break;
        case 3:  // Filled style (2018+)
            imageName = @"notifications_selected";
            iconColor = isSelected ? [%c(YTColor) white1] : [UIColor grayColor];
            break;
        case 4:  // Inbox style (2014+)
            imageName = @"inbox_selected";
            iconColor = isSelected ? [%c(YTColor) white1] : [UIColor grayColor];
            break;
        default:  // Default style (2025+)
            imageName = isSelected ? @"notifications_selected_2025" : @"notifications_unselected_2025";
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

// YTHidePlayerButtons 1.0.1 - v20.02.3+ - made by @aricloverEXTRA
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
- (void)decorateContext:(id)context {
    %orig(nil);
}
%end

%hook YTAccountScopedAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context {
    %orig(nil);
}
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

// uYou AdBlock Workaround (Note: disables uYou's "Remove YouTube Ads" YouTube-X Option) - @PoomSmart, @arichornlover & @Dodieboy
%group uYouAdBlockingWorkaround
// Workaround: uYou 3.0.3 Adblock fix
%hook YTHotConfig
- (BOOL)disableAfmaIdfaCollection { return NO; }
%end
%hook YTIPlayerResponse
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
%hook YTLocalPlaybackController
- (id)createAdsPlaybackCoordinator { return nil; }
%end
%hook MDXSession
- (void)adPlaying:(id)ad {}
%end
%hook MDXSessionImpl
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
static BOOL isProductList(YTICommand *command) {
    if ([command respondsToSelector:@selector(yt_showEngagementPanelEndpoint)]) {
        YTIShowEngagementPanelEndpoint *endpoint = [command yt_showEngagementPanelEndpoint];
        return [endpoint.identifier.tag isEqualToString:@"PAproduct_list"];
    }
    return NO;
}
%hook YTWatchNextResponseViewController
- (void)loadWithModel:(YTIWatchNextResponse *)model {
    YTICommand *onUiReady = model.onUiReady;
    if ([onUiReady respondsToSelector:@selector(yt_commandExecutorCommand)]) {
        YTICommandExecutorCommand *commandExecutorCommand = [onUiReady yt_commandExecutorCommand];
        NSMutableArray <YTICommand *> *commandsArray = commandExecutorCommand.commandsArray;
        [commandsArray removeObjectsAtIndexes:[commandsArray indexesOfObjectsPassingTest:^BOOL(YTICommand *command, NSUInteger idx, BOOL *stop) {
            return isProductList(command);
        }]];
    }
    if (isProductList(onUiReady))
        model.onUiReady = nil;
    %orig;
}
%end
%hook YTMainAppVideoPlayerOverlayViewController
- (void)playerOverlayProvider:(YTPlayerOverlayProvider *)provider didInsertPlayerOverlay:(YTPlayerOverlay *)overlay {
    if ([[overlay overlayIdentifier] isEqualToString:@"player_overlay_product_in_video"]) return;
    %orig;
}
%end
NSString *getAdString(NSString *description) {
    for (NSString *str in @[
        @"brand_promo",
        @"brand_video_shelf",
        @"carousel_footered_layout",
        @"carousel_headered_layout",
        @"eml.expandable_metadata",
        @"feed_ad_metadata",
        @"full_width_portrait_image_layout",
        @"full_width_square_image_layout",
        @"grid_ads_image_layout",
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

// Settings Menu with Blur Style - @arichornlover
// %group gSettingsStyle
// %hook YTWrapperSplitView
// - (void)viewDidLoad {
//     [super viewDidLoad];
//     UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
//     UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
//     blurView.frame = self.view.bounds;
//     blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
//     [self.view addSubview:blurView];
//     [self.view sendSubviewToBack:blurView];
//     // Apply dark theme if pageStyle is set to dark
//     if ([[NSUserDefaults standardUserDefaults] integerForKey:@"page_style"] == 1) {
//         self.view.backgroundColor = [UIColor blackColor];
//     }
// }
// %end
// %end

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
- (BOOL)respectDeviceCaptionSetting { return NO; } // YouRememberCaption: https://poomsmart.github.io/repo/depictions/youremembercaption.html - deprecated flag ⚠️
- (BOOL)isLandscapeEngagementPanelSwipeRightToDismissEnabled { return YES; } // Swipe right to dismiss the right panel in fullscreen mode - deprecated flag ⚠️
- (BOOL)enableModularPlayerBarController { return NO; } // fixes some of the iSponorBlock problems
- (BOOL)mainAppCoreClientEnableCairoSettings { return IS_ENABLED(@"newSettingsUI_enabled"); } // New grouped settings UI
- (BOOL)enableIosFloatingMiniplayer { return IS_ENABLED(@"floatingMiniplayer_enabled"); } // Floating Miniplayer
- (BOOL)enableIosFloatingMiniplayerSwipeUpToExpand { return IS_ENABLED(@"floatingMiniplayer_enabled"); } // Floating Miniplayer - deprecated flag ⚠️
- (BOOL)enableIosFloatingMiniplayerRepositioning { return IS_ENABLED(@"floatingMiniplayer2_enabled"); } // Floating Miniplayer (Repositioning Support, Removes Swiping Up Gesture) - deprecated fla[...]
%end

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
- (BOOL)isPremiumLogo { return IS_ENABLED(kYTPremiumLogo) ? YES : %orig; }
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
- (BOOL)isPremiumLogo { return IS_ENABLED(kYTPremiumLogo) ? YES : %orig; }
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

