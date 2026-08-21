#import "uYouPlusPatches.h"
#import "uYouPatches.h"

#define YT_BUNDLE_ID @"com.google.ios.youtube"
#define YT_NAME @"YouTube"

# pragma mark - YouTube patches

// Fix Google Sign in Patch - handles AltStore and SideStore bundle IDs
%group gGoogleSignInPatch
%hook NSBundle
+ (NSBundle *)bundleWithIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:YT_BUNDLE_ID])
        return NSBundle.mainBundle;
    // SideStore: also handle alternative bundle ID formats
    if (uYouIsSideStore() && [identifier hasSuffix:@".google.ios.youtube"])
        return NSBundle.mainBundle;
    return %orig(identifier);
}
- (NSString *)bundleIdentifier {
    if ([self isEqual:NSBundle.mainBundle])
        return YT_BUNDLE_ID;
    // SideStore: preserve the actual bundle ID for internal checks
    return %orig;
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

%group gPatches

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

// Workaround for issue #54 - Hide related videos at end of videos
%hook YTMainAppVideoPlayerOverlayViewController
- (void)updateRelatedVideos {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"relatedVideosAtTheEndOfYTVideos"]) {
        %orig;
    }
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

%end // gPatches

// Sideloading - Fix App Group Directory (handles both AltStore and SideStore)
%group gSideloadingPatches
%hook NSFileManager
- (NSURL *)containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
    if (groupIdentifier != nil) {
        NSArray *paths = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
        NSURL *documentsURL = [paths lastObject];
        // SideStore: use a separate AppGroup directory to avoid conflicts
        if (uYouIsSideStore()) {
            return [documentsURL URLByAppendingPathComponent:@"SideStoreAppGroup"];
        }
        return [documentsURL URLByAppendingPathComponent:@"AppGroup"];
    }
    return %orig(groupIdentifier);
}
%end

// Fixes uYou crash when trying to play video (#1422)
// NOTE: Newer YouTube builds (21.x+) may no longer implement the varispeed
// plumbing below. Every send is guarded so a missing selector degrades to a
// no-op instead of throwing "unrecognized selector sent to instance" during
// playback setup (observed as a startup SIGABRT on YT 21.14.4).
%hook YTPlayerOverlayManager
%property (nonatomic, assign) float currentPlaybackRate;

%new
- (void)setCurrentPlaybackRate:(float)rate {
    if (![self respondsToSelector:@selector(varispeedSwitchController:didSelectRate:)])
        return;
    id varispeed = [self respondsToSelector:@selector(varispeedController)] ? [self varispeedController] : nil;
    if (!varispeed)
        return;
    @try {
        [self varispeedSwitchController:varispeed didSelectRate:rate];
    } @catch (NSException *e) {
        // Swallow: this shim is best-effort compatibility for uYou.
    }
}

%new
- (void)setPlaybackRate:(float)rate {
    if (![self respondsToSelector:@selector(varispeedSwitchController:didSelectRate:)])
        return;
    id varispeed = [self respondsToSelector:@selector(varispeedController)] ? [self varispeedController] : nil;
    if (!varispeed)
        return;
    @try {
        [self varispeedSwitchController:varispeed didSelectRate:rate];
    } @catch (NSException *e) {
        // Swallow: this shim is best-effort compatibility for uYou.
    }
}
%end
%end // gSideloadingPatches

%ctor {
    %init;
    %init(gPatches);
    %init(gSideloadingPatches);
    if (IS_ENABLED(kGoogleSignInPatch)) {
        %init(gGoogleSignInPatch);
    }

    // Disable broken options

    // Disable uYou's auto updates
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"automaticallyCheckForUpdates"];

    // Disable uYou's welcome screen (fix #1147)
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"showedWelcomeVC"];

    // Disable uYou's disable age restriction
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"disableAgeRestriction"];

    // Disable uYou's playback speed controls (prevent crash on video playback)
    // [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"showPlaybackRate"];
}
