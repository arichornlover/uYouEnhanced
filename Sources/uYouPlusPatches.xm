#import "uYouPlusPatches.h"
#import "uYouPatches.h"
#import <fcntl.h>
#import <unistd.h>

#define YT_BUNDLE_ID @"com.google.ios.youtube"
#define YT_NAME @"YouTube"

// Declared for the Dynamic Island fix (gDynamicIslandFix below) — logos only
// emits a forward @class for hooked classes, which isn't enough to message
// defaultCenter]/setNowPlayingInfo: from the didBecomeActive observer.
@interface MPNowPlayingInfoCenter : NSObject
@property (nonatomic, copy) NSDictionary *nowPlayingInfo;
+ (MPNowPlayingInfoCenter *)defaultCenter;
@end

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

// IAmYouTube (https://github.com/PoomSmart/IAmYouTube) — identity spoofing
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

// Spoof App Store presence so analytics / crash reporting don't flag sideloaded builds.
%hook APMAEU
+ (BOOL)isFAS { return YES; }
%end

%hook GULAppEnvironmentUtil
+ (BOOL)isFromAppStore { return YES; }
%end

// SSO / Google sign-in identity
%hook SSOClientLogin
+ (NSString *)defaultSourceString { return YT_BUNDLE_ID; }
%end

%hook SSOConfiguration
- (id)initWithClientID:(id)clientID supportedAccountServices:(id)supportedAccountServices {
    self = %orig;
    [self setValue:YT_NAME forKey:@"_shortAppName"];
    [self setValue:YT_BUNDLE_ID forKey:@"_applicationIdentifier"];
    return self;
}
%end

// Disable encoded hacks in innertube context (prevents certain telemetry from
// leaking the real bundle ID).
%hook YTHotConfig
- (BOOL)clientInfraClientConfigIosEnableFillingEncodedHacksInnertubeContext { return NO; }
%end

// Keychain access group — redirect all keychain operations to the sideloaded
// app's actual access group so sign-in tokens persist across restarts.
%hook SSOKeychainHelper
+ (id)accessGroup { return uYouAccessGroupID(); }
+ (id)sharedAccessGroup { return uYouAccessGroupID(); }
%end

%hook SSOFolsomKeychainUtils
- (id)sharedAccessGroup { return uYouAccessGroupID(); }
%end

%hook GULKeychainStorage
- (void)getObjectForKey:(id)key objectClass:(Class)objectClass accessGroup:(id)accessGroup completionHandler:(id)handler {
    accessGroup = uYouAccessGroupID();
    %orig(key, objectClass, accessGroup, handler);
}
- (void)setObject:(id)object forKey:(id)key accessGroup:(id)accessGroup completionHandler:(id)handler {
    accessGroup = uYouAccessGroupID();
    %orig(object, key, accessGroup, handler);
}
- (void)removeObjectForKey:(id)key accessGroup:(id)accessGroup completionHandler:(id)handler {
    accessGroup = uYouAccessGroupID();
    %orig(key, accessGroup, handler);
}
- (void)getObjectFromKeychainForKey:(id)key objectClass:(Class)objectClass accessGroup:(id)accessGroup completionHandler:(id)handler {
    accessGroup = uYouAccessGroupID();
    %orig(key, objectClass, accessGroup, handler);
}
- (id)keychainQueryWithKey:(id)key accessGroup:(id)accessGroup {
    accessGroup = uYouAccessGroupID();
    return %orig(key, accessGroup);
}
%end

%hook GNPEncryptionConfiguration
- (id)initWithKeychainAccessGroup:(id)arg {
    arg = uYouAccessGroupID();
    return %orig(arg);
}
- (id)keychainAccessGroup { return uYouAccessGroupID(); }
%end

%hook FIRInstallationsStore
- (id)initWithSecureStorage:(id)arg1 accessGroup:(id)arg2 {
    arg2 = uYouAccessGroupID();
    return %orig(arg1, arg2);
}
- (id)accessGroup { return uYouAccessGroupID(); }
%end

%hook CHMConfiguration
- (void)setKeychainAccessGroup:(id)arg {
    arg = uYouAccessGroupID();
    %orig(arg);
}
- (id)keychainAccessGroup { return uYouAccessGroupID(); }
%end

%end // gSideloadingPatches

// Dynamic Island suppression while in-app (#69, #358, #823)
// Sideloaded builds using the official bundle ID lack Apple's media
// entitlements, so iOS renders the Dynamic Island the moment any Now Playing
// info is published — even while the app is frontmost. This is a signing/
// environment artifact (not a uYou bug), hence it lives with the other
// sideloading patches. Drop Now Playing updates while the app is ACTIVE;
// background playback / PiP still publish normally once the app leaves the
// foreground, so lock-screen controls and the island keep working outside.
%group gDynamicIslandFix
%hook MPNowPlayingInfoCenter
- (void)setNowPlayingInfo:(NSDictionary *)info {
    // Clearing is always allowed; fresh publications are blocked in-app so
    // the island can't expand while you're inside YouTube.
    UIApplication *app = [UIApplication sharedApplication];
    BOOL isActive = (app != nil && app.applicationState == UIApplicationStateActive);
    if (info != nil && isActive) {
        return;
    }
    %orig;
}
%end
%end

static BOOL UYTIsJailbroken(void) {
    static BOOL result = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        result = ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"]) ||
                 ([[NSFileManager defaultManager] fileExistsAtPath:@"/.bootstrapped"]) ||
                 (objc_getClass("LSApplicationWorkspace") != NULL && access("/Applications", F_OK) == 0);
    });
    return result;
}

%ctor {
    %init;
    %init(gPatches);
    %init(gSideloadingPatches);
    // Opt-IN only: the Dynamic Island fix is OFF by default and is installed
    // solely when the user enables "Enable Dynamic Island Fix" in settings
    // (and on non-jailbroken devices, where the official bundle lacks media
    // entitlements). Nothing runs unless explicitly requested.
    BOOL diFixEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kEnableDynamicIslandFix];
    if (!UYTIsJailbroken() && diFixEnabled) {
        %init(gDynamicIslandFix);

        // Returning to the app: clear any stale Now Playing session so an
        // already-expanded island collapses instead of lingering in-app.
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil queue:[NSOperationQueue mainQueue]
                   usingBlock:^(NSNotification *note) {
            @try {
                [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
            } @catch (NSException *e) {}
        }];
    }

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
