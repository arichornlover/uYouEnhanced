#import "uYouPlusPatches.h"

#define YT_BUNDLE_ID @"com.google.ios.youtube"
#define YT_NAME @"YouTube"

# pragma mark - YouTube patches

static NSString *accessGroupID() {
    NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys:
                           (__bridge NSString *)kSecClassGenericPassword, (__bridge NSString *)kSecClass,
                           @"bundleSeedID", kSecAttrAccount,
                           @"", kSecAttrService,
                           (id)kCFBooleanTrue, kSecReturnAttributes,
                           nil];
    CFDictionaryRef result = nil;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
    if (status == errSecItemNotFound) {
        status = SecItemAdd((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
        if (status != errSecSuccess) {
            return nil;
        }
    }
    NSString *accessGroup = [(__bridge NSDictionary *)result objectForKey:(__bridge NSString *)kSecAttrAccessGroup];
    return accessGroup;
}

// Fix Google Sign in Patch
%group gGoogleSignInPatch
%hook NSBundle
+ (NSBundle *)bundleWithIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:YT_BUNDLE_ID])
        return NSBundle.mainBundle;
    return %orig(identifier);
}
- (NSString *)bundleIdentifier {
    return [self isEqual:NSBundle.mainBundle] ? YT_BUNDLE_ID : %orig;
}
- (NSDictionary *)infoDictionary {
    NSDictionary *dict = %orig;
    if (![self isEqual:NSBundle.mainBundle])
        return %orig;
    NSMutableDictionary *info = [dict mutableCopy];
    if (info[@"CFBundleIdentifier"]) info[@"CFBundleIdentifier"] = YT_BUNDLE_ID;
    if (info[@"CFBundleDisplayName"]) info[@"CFBundleDisplayName"] = YT_NAME;
    if (info[@"CFBundleName"]) info[@"CFBundleName"] = YT_NAME;
    return info;
}
- (id)objectForInfoDictionaryKey:(NSString *)key {
    if (![self isEqual:NSBundle.mainBundle])
        return %orig;
    if ([key isEqualToString:@"CFBundleIdentifier"])
        return YT_BUNDLE_ID;
    if ([key isEqualToString:@"CFBundleDisplayName"] || [key isEqualToString:@"CFBundleName"])
        return YT_NAME;
    return %orig;
}
%end
%end

// Workaround for MiRO92/uYou-for-YouTube#12, qnblackcat/uYouPlus#263
%hook YTDataUtils
+ (NSMutableDictionary *)spamSignalsDictionary {
    return nil;
}
+ (NSMutableDictionary *)spamSignalsDictionaryWithoutIDFA {
    return nil;
}
%end

%hook YTHotConfig
- (BOOL)disableAfmaIdfaCollection { return NO; }
%end

// https://github.com/PoomSmart/YouTube-X/blob/1e62b68e9027fcb849a75f54a402a530385f2a51/Tweak.x#L27
// %hook YTAdsInnerTubeContextDecorator
// - (void)decorateContext:(id)context {}
// %end

# pragma mark - uYou patches

// Workaround for qnblackcat/uYouPlus#10
%hook UIViewController
- (UITraitCollection *)traitCollection {
    @try {
        return %orig;
    } @catch(NSException *e) {
        return [UITraitCollection currentTraitCollection];
    }
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

// YouTube Native Share 0.2.7 - https://github.com/jkhsjdhjs/youtube-native-share - @jkhsjdhjs
typedef NS_ENUM(NSInteger, ShareEntityType) {
    ShareEntityFieldVideo     = 1,
    ShareEntityFieldPlaylist  = 2,
    ShareEntityFieldChannel   = 3,
    ShareEntityFieldPost      = 6,
    ShareEntityFieldClip      = 8,
    ShareEntityFieldShortFlag = 10
};

static inline NSString *extractIdWithFormat(GPBUnknownFields *fields, NSInteger fieldNumber, NSString *format) {
    NSArray<GPBUnknownField *> *fieldArray = [fields fields:fieldNumber];
    if ([fieldArray count] != 1)
        return nil;
    NSString *value = [[NSString alloc] initWithData:[fieldArray firstObject].lengthDelimited encoding:NSUTF8StringEncoding];
    return [NSString stringWithFormat:format, value];
}

static NSString *extractUrlFromFields(GPBUnknownFields *fields) {
    NSString *shareUrl;

    NSArray<GPBUnknownField *> *shareEntityClip = [fields fields:ShareEntityFieldClip];
    if ([shareEntityClip count] == 1) {
        GPBMessage *clipMessage = [%c(GPBMessage) parseFromData:[shareEntityClip firstObject].lengthDelimited error:nil];
        shareUrl = extractIdWithFormat([[%c(GPBUnknownFields) alloc] initFromMessage:clipMessage], 1, @"https://youtube.com/clip/%@");
    }

    if (!shareUrl)
        shareUrl = extractIdWithFormat(fields, ShareEntityFieldChannel, @"https://youtube.com/channel/%@");

    if (!shareUrl)
        shareUrl = extractIdWithFormat(fields, ShareEntityFieldPost, @"https://youtube.com/post/%@");

    if (!shareUrl) {
        shareUrl = extractIdWithFormat(fields, ShareEntityFieldPlaylist, @"%@");
        if (shareUrl) {
            if (![shareUrl hasPrefix:@"PL"] && ![shareUrl hasPrefix:@"FL"])
                shareUrl = [shareUrl stringByAppendingString:@"&playnext=1"];
            shareUrl = [@"https://youtube.com/playlist?list=" stringByAppendingString:shareUrl];
        }
    }

    if (!shareUrl) {
        NSString *format = ([fields fields:ShareEntityFieldShortFlag].count > 0) ? @"https://youtube.com/shorts/%@" : @"https://youtube.com/watch?v=%@";
        shareUrl = extractIdWithFormat(fields, ShareEntityFieldVideo, format);
    }

    return shareUrl;
}

static NSString *extractUrlFromDescription(NSString *desc) {
    NSRegularExpression *regex;
    NSTextCheckingResult *match;

    regex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"\\b%ld: \"([^\"]+)\"", (long)ShareEntityFieldChannel] options:0 error:nil];
    match = [regex firstMatchInString:desc options:0 range:NSMakeRange(0, desc.length)];
    if (match) return [NSString stringWithFormat:@"https://youtube.com/channel/%@", [desc substringWithRange:[match rangeAtIndex:1]]];

    regex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"\\b%ld: \"([^\"]+)\"", (long)ShareEntityFieldPost] options:0 error:nil];
    match = [regex firstMatchInString:desc options:0 range:NSMakeRange(0, desc.length)];
    if (match) return [NSString stringWithFormat:@"https://youtube.com/post/%@", [desc substringWithRange:[match rangeAtIndex:1]]];

    regex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"\\b%ld: \"([^\"]+)\"", (long)ShareEntityFieldPlaylist] options:0 error:nil];
    match = [regex firstMatchInString:desc options:0 range:NSMakeRange(0, desc.length)];
    if (match) {
        NSString *playlistId = [desc substringWithRange:[match rangeAtIndex:1]];
        if (![playlistId hasPrefix:@"PL"] && ![playlistId hasPrefix:@"FL"])
            playlistId = [playlistId stringByAppendingString:@"&playnext=1"];
        return [NSString stringWithFormat:@"https://youtube.com/playlist?list=%@", playlistId];
    }

    regex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"\\b%ld: \"([^\"]+)\"", (long)ShareEntityFieldVideo] options:0 error:nil];
    match = [regex firstMatchInString:desc options:0 range:NSMakeRange(0, desc.length)];
    if (match) return [NSString stringWithFormat:@"https://youtube.com/watch?v=%@", [desc substringWithRange:[match rangeAtIndex:1]]];

    return nil;
}

static BOOL showNativeShareSheet(NSString *serializedShareEntity, UIView *sourceView) {
    GPBMessage *shareEntity = [%c(GPBMessage) deserializeFromString:serializedShareEntity];
    if (!shareEntity) return NO;

    NSString *shareUrl;
    GPBUnknownFields *fields = [[%c(GPBUnknownFields) alloc] initFromMessage:shareEntity];

    if (fields && [fields count] > 0)
        shareUrl = extractUrlFromFields(fields);
    else
        shareUrl = extractUrlFromDescription([shareEntity description]);

    if (!shareUrl) return NO;

    UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[shareUrl] applicationActivities:nil];
    activityViewController.excludedActivityTypes = @[UIActivityTypeAssignToContact, UIActivityTypePrint];

    UIViewController *topViewController = [%c(YTUIUtils) topViewControllerForPresenting];
    if (activityViewController.popoverPresentationController) {
        if (sourceView) {
            activityViewController.popoverPresentationController.sourceView = sourceView;
            activityViewController.popoverPresentationController.sourceRect = [sourceView convertRect:sourceView.bounds toView:topViewController.view];
        } else {
            activityViewController.popoverPresentationController.sourceView = topViewController.view;
            CGFloat w = [UIScreen mainScreen].bounds.size.width;
            CGFloat h = [UIScreen mainScreen].bounds.size.height;
            activityViewController.popoverPresentationController.sourceRect = CGRectMake(w / 2.0, h, 0, 0);
        }
    }
    [topViewController presentViewController:activityViewController animated:YES completion:nil];
    return YES;
}

%hook ELMPBShowActionSheetCommand
- (void)executeWithCommandContext:(ELMCommandContext *)context handler:(id)handler {
    NSString *desc = [self description];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"serialized_share_entity: \"([^\"]+)\"" options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:desc options:0 range:NSMakeRange(0, desc.length)];
    if (!match) return %orig;

    NSString *serializedShareEntity = [desc substringWithRange:[match rangeAtIndex:1]];
    UIView *fromView;
    if ([context.context respondsToSelector:@selector(fromView)])
        fromView = context.context.fromView;

    if (!showNativeShareSheet(serializedShareEntity, fromView))
        return %orig;
}
%end

%hook YTShareEntityEndpointCommandHandler
- (void)executeWithCommand:(YTICommand *)command entry:(id)entry fromView:(UIView *)fromView sender:(id)sender {
    NSString *desc = [command description];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"serialized_share_entity: \"([^\"]+)\"" options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:desc options:0 range:NSMakeRange(0, desc.length)];
    if (!match) return %orig;

    NSString *serializedShareEntity = [desc substringWithRange:[match rangeAtIndex:1]];
    if (!showNativeShareSheet(serializedShareEntity, fromView))
        return %orig;
}
%end
// %end

//

// iOS 16 uYou crash fix - @level3tjg: https://github.com/qnblackcat/uYouPlus/pull/224
// %group iOS16
// %hook OBPrivacyLinkButton
// %new
// - (instancetype)initWithCaption:(NSString *)caption
//                      buttonText:(NSString *)buttonText
//                           image:(UIImage *)image
//                       imageSize:(CGSize)imageSize
//                    useLargeIcon:(BOOL)useLargeIcon {
//   return [self initWithCaption:caption
//                     buttonText:buttonText
//                          image:image
//                      imageSize:imageSize
//                   useLargeIcon:useLargeIcon
//                displayLanguage:[NSLocale currentLocale].languageCode];
// }
// %end
// %end

// Fix uYou playback speed crashes YT v18.49.3+, see https://github.com/iCrazeiOS/uYouCrashFix
// %hook YTPlayerViewController
// %new
// -(float)currentPlaybackRateForVarispeedSwitchController:(id)arg1 {
// 	return [[self activeVideo] playbackRate];
// }

// %new
// -(void)varispeedSwitchController:(id)arg1 didSelectRate:(float)arg2 {
// 	[[self activeVideo] setPlaybackRate:arg2];
// }
// %end

// Fix streched artwork in uYou's player view - https://github.com/MiRO92/uYou-for-YouTube/issues/287
%hook ArtworkImageView
- (id)imageView {
    UIImageView * imageView = %orig;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    // Make artwork a bit bigger
    UIView *artworkImageView = imageView.superview;
    if (artworkImageView != nil && !artworkImageView.translatesAutoresizingMaskIntoConstraints) {
        [artworkImageView.leftAnchor constraintEqualToAnchor:artworkImageView.superview.leftAnchor constant:16].active = YES;
        [artworkImageView.rightAnchor constraintEqualToAnchor:artworkImageView.superview.rightAnchor constant:-16].active = YES;
    }
    return imageView;
}
%end

// Fix navigation bar showing a lighter grey with default dark mode - https://github.com/therealFoxster/uYouPlus/commit/8db8197
%hook YTCommonColorPalette
- (UIColor *)brandBackgroundSolid {
    return self.pageStyle == 1 ? [UIColor colorWithRed:0.05882352941176471 green:0.05882352941176471 blue:0.05882352941176471 alpha:1.0] : %orig;
}
%end

// Fix uYou's appearance not updating if the app is backgrounded
static DownloadsPagerVC *downloadsPagerVC;
static NSUInteger selectedTabIndex;
%hook DownloadsPagerVC
- (id)init {
    downloadsPagerVC = %orig;
    return downloadsPagerVC;
}
- (void)viewPager:(id)viewPager didChangeTabToIndex:(NSUInteger)arg1 fromTabIndex:(NSUInteger)arg2 {
    %orig; selectedTabIndex = arg1;
}
%end
static void refreshUYouAppearance() {
    if (!downloadsPagerVC) return;
    // View pager
    [downloadsPagerVC updatePageStyles];
    // Views
    for (UIViewController *vc in [downloadsPagerVC viewControllers]) {
        if ([vc isKindOfClass:%c(DownloadingVC)]) {
            // `Downloading` view
            [(DownloadingVC *)vc updatePageStyles];
            for (UITableViewCell *cell in [(DownloadingVC *)vc tableView].visibleCells)
                if ([cell isKindOfClass:%c(DownloadingCell)])
                    [(DownloadingCell *)cell updatePageStyles];
        }
        else if ([vc isKindOfClass:%c(DownloadedVC)]) {
            // `All`, `Audios`, `Videos`, `Shorts` views
            [(DownloadedVC *)vc updatePageStyles];
            for (UITableViewCell *cell in [(DownloadedVC *)vc tableView].visibleCells)
                if ([cell isKindOfClass:%c(DownloadedCell)])
                    [(DownloadedCell *)cell updatePageStyles];
        }
    }
    // View pager tabs
    for (UIView *subview in [downloadsPagerVC view].subviews) {
        if ([subview isKindOfClass:[UIScrollView class]]) {
            UIScrollView *tabs = (UIScrollView *)subview;
            NSUInteger i = 0;
            for (UIView *item in tabs.subviews) {
                if ([item isKindOfClass:[UILabel class]]) {
                    // Tab label
                    UILabel *tabLabel = (UILabel *)item;
                    if (i == selectedTabIndex) {} // Selected tab should be excluded
                    else [tabLabel setTextColor:[UILabel _defaultColor]];
                    i++;
                }
            }
        }
    }
}
%hook UIViewController
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        refreshUYouAppearance();
    });
}
%end

// Prevent uYou's playback from colliding with YouTube's
%hook PlayerVC
- (void)close {
    %orig;
    [[%c(PlayerManager) sharedInstance] setSource:nil];
}
%end
%hook HAMPlayerInternal
- (void)play {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[%c(PlayerManager) sharedInstance] pause];
    });
    %orig;
}
%end

// Temporarily disable uYou's bouncy animation cause it's buggy
%hook SSBouncyButton
- (void)beginShrinkAnimation {}
- (void)beginEnlargeAnimation {}
%end

%hook GOODialogView
- (id)imageView {
    UIImageView *imageView = %orig;

    if ([[self titleLabel].text containsString:@"uYou\n"]) {
        // // Invert uYou logo in download dialog if dark mode is enabled
        // if ([[NSUserDefaults standardUserDefaults] integerForKey:@"page_style"] == 0)
        //     return imageView;
        // // https://gist.github.com/coryalder/3113a43734f5e0e4b497
        // UIImage *image = [imageView image];
        // CIImage *ciImage = [[CIImage alloc] initWithImage:image];
        // CIFilter *filter = [CIFilter filterWithName:@"CIColorInvert"];
        // [filter setDefaults];
        // [filter setValue:ciImage forKey:kCIInputImageKey];
        // CIContext *context = [CIContext contextWithOptions:nil];
        // CIImage *output = [filter outputImage];
        // CGImageRef cgImage = [context createCGImage:output fromRect:[output extent]];
        // UIImage *icon = [UIImage imageWithCGImage:cgImage];
        // CGImageRelease(cgImage);

        // Load icon_clipped.png from uYouBundle.bundle
        NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"uYouBundle" ofType:@"bundle"];
        NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
        NSString *iconPath = [bundle pathForResource:@"icon_clipped" ofType:@"png"];
        UIImage *icon = [UIImage imageWithContentsOfFile:iconPath];
        [imageView setImage:icon];

        // Resize image to 30x30
        // https://stackoverflow.com/a/2658801/19227228
        CGSize size = CGSizeMake(30, 30);
        UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
        [icon drawInRect:CGRectMake(0, 0, size.width, size.height)];
        UIImage *resizedImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        [imageView setImage:resizedImage];
    }

    return imageView;
}
// Increase space between uYou label and video title
- (id)titleLabel {
    UILabel *titleLabel = %orig;
    if ([titleLabel.text containsString:@"uYou\n"] &&
        ![titleLabel.text containsString:@"uYou\n\n"]
    ) {
        NSString *text = [titleLabel.text stringByReplacingOccurrencesOfString:@"uYou\n" withString:@"uYou\n\n"];
        [titleLabel setText:text];
    }
    return titleLabel;
}
%end

%hook YTPlayerViewController
 
 - (id)varispeedController {
     id controller = %orig;
     if (controller == nil && [self respondsToSelector:@selector(overlayManager)])
         controller = [self.overlayManager varispeedController];
     return controller;
 }
 
 %end

// Sideloading
%hook SSOKeychainHelper
+ (id)accessGroup { return accessGroupID(); }
+ (id)sharedAccessGroup { return accessGroupID(); }
%end

%hook SSOFolsomKeychainUtils
- (id)sharedAccessGroup { return accessGroupID(); }
%end

%hook GULKeychainStorage
- (void)getObjectForKey:(id)key objectClass:(Class)objectClass accessGroup:(id)accessGroup completionHandler:(id)handler {
    accessGroup = accessGroupID();
    %orig(key, objectClass, accessGroup, handler);
}
- (void)setObject:(id)object forKey:(id)key accessGroup:(id)accessGroup completionHandler:(id)handler {
    accessGroup = accessGroupID();
    %orig(object, key, accessGroup, handler);
}
- (void)removeObjectForKey:(id)key accessGroup:(id)accessGroup completionHandler:(id)handler {
    accessGroup = accessGroupID();
    %orig(key, accessGroup, handler);
}
- (void)getObjectFromKeychainForKey:(id)key objectClass:(Class)objectClass accessGroup:(id)accessGroup completionHandler:(id)handler {
    accessGroup = accessGroupID();
    %orig(key, objectClass, accessGroup, handler);
}
- (id)keychainQueryWithKey:(id)key accessGroup:(id)accessGroup {
    accessGroup = accessGroupID();
    return %orig(key, accessGroup);
}
%end

%hook GNPEncryptionConfiguration
- (id)initWithKeychainAccessGroup:(id)arg {
    arg = accessGroupID();
    return %orig(arg);
}
- (id)keychainAccessGroup { return accessGroupID(); }
%end

%hook FIRInstallationsStore
- (id)initWithSecureStorage:(id)arg1 accessGroup:(id)arg2 {
    arg2 = accessGroupID();
    return %orig(arg1, arg2);
}
- (id)accessGroup { return accessGroupID(); }
%end

%hook CHMConfiguration
- (void)setKeychainAccessGroup:(id)arg {
    arg = accessGroupID();
    %orig(arg);
}
- (id)keychainAccessGroup { return accessGroupID(); }
%end

%ctor {
    %init;
    if (IS_ENABLED(kGoogleSignInPatch)) {
        %init(gGoogleSignInPatch);
    }
/*
    if (IS_ENABLED(kYouTubeNativeShare)) {
        %init(gYouTubeNativeShare);
    }
*/
    // if (@available(iOS 16, *)) {
    //     %init(iOS16);
    // }

    // Disable broken options
    
    // Disable uYou's auto updates
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"automaticallyCheckForUpdates"];

    // Disable uYou's welcome screen (fix #1147)
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"showedWelcomeVC"];
 
    // Disable uYou's disable age restriction
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"disableAgeRestriction"];

    // Disable uYou's playback speed controls (prevent crash on video playback https://github.com/therealFoxster/uYouPlus/issues/2#issuecomment-1894912963)
    // [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"showPlaybackRate"];
}
