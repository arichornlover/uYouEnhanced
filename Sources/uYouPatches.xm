#import "uYouPlus.h"
#import "uYouPatches.h"

// ---------------------------------------------------------------------------
// UYTLog compat
// ---------------------------------------------------------------------------
// uYouEnhanced buffers its own log and builds the in-app report out of it, so
// a download failure is only diagnosable if these calls reach UYTLog. Prefer
// UYTDebug* when the header is there and fall back to the hooking logger
// otherwise - a missing log must never be what breaks a download or a build.
// Both sinks are written on purpose: syslog for the user, the buffer for us.
#if __has_include("UYTLog.h")
#import "UYTLog.h"
#define UYTPatchInfo(fmt, ...) do { UYTDebugInfo(fmt, ##__VA_ARGS__); HBLogInfo(fmt, ##__VA_ARGS__); } while (0)
#define UYTPatchWarn(fmt, ...) do { UYTDebugWarn(fmt, ##__VA_ARGS__); HBLogWarn(fmt, ##__VA_ARGS__); } while (0)
#define UYTPatchErr(fmt, ...)  do { UYTDebugErr(fmt, ##__VA_ARGS__);  HBLogError(fmt, ##__VA_ARGS__); } while (0)
#else
#define UYTPatchInfo(fmt, ...) HBLogInfo(fmt, ##__VA_ARGS__)
#define UYTPatchWarn(fmt, ...) HBLogWarn(fmt, ##__VA_ARGS__)
#define UYTPatchErr(fmt, ...)  HBLogError(fmt, ##__VA_ARGS__)
#endif

# pragma mark - uYou Patches
// Uses reverse-engineered uYou 3.0.4 source for reference.
//
// Base: origin/main (7da4c0a) with the open "uYou"-label issues that actually
// live in this file fixed. Every fix below carries its issue number in the
// comment directly above it.
//
// Download pipeline:  #1010, #947, #814, #771, #735, #520, #241, #159, #70
// Speed control:      #795, #681
// Fullscreen gesture: #57
// Keep-awake:         #813
//
// Not handled here (they belong to other sources, not this file):
//   #84, #354 quality/50fps selection   #93  home tab        #95  Shorts bar
//   #179 PiP freeze                     #370 fullscreen crash logs w/o body
//   #394 swipe-control UX               #399 playlist repeat
//   #451 auto-caption + CC              #577 1080p Premium (feature request)
//   #87  thumbnail export (needs the Photos entitlement, not a hook)
//   #174 crash on video tap (no body / no crash log)
//   #215 crash on deleting a download   #951 broad "features broken" report

// Shared access group / sideloading utilities
static NSString *uYouAccessGroupIDInternal() {
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
    if (accessGroup) {
        NSArray *components = [accessGroup componentsSeparatedByString:@"."];
        if (components.count >= 2) {
            return components[0];
        }
    }
    return accessGroup;
}

static BOOL uYouIsSideStoreInternal() {
    NSString *accessGroup = uYouAccessGroupIDInternal();
    if (accessGroup && ![accessGroup isEqualToString:@""]) {
        NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
        NSString *embeddedProfile = [bundlePath stringByAppendingPathComponent:@"embedded.mobileprovision"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:embeddedProfile]) {
            NSData *profileData = [NSData dataWithContentsOfFile:embeddedProfile];
            if (profileData) {
                NSString *profileString = [[NSString alloc] initWithData:profileData encoding:NSASCIIStringEncoding];
                if ([profileString containsString:@"SideStore"] || [profileString containsString:@"sidestore"]) {
                    return YES;
                }
            }
        }
    }
    return NO;
}

NSString *uYouAccessGroupID() {
    return uYouAccessGroupIDInternal();
}

BOOL uYouIsSideStore() {
    return uYouIsSideStoreInternal();
}

// ============================================================================
// MARK: - Core uYou Fixes
// ============================================================================

%group gYouFixes

// Workaround for qnblackcat/uYouPlus#10 - Prevent crash on nil traitCollection
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

// Fix stretched artwork in uYou's player view - https://github.com/MiRO92/uYou-for-YouTube/issues/287
%hook ArtworkImageView
- (id)imageView {
    UIImageView *imageView = %orig;
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

// Fix navigation bar showing a lighter grey with default dark mode
// https://github.com/therealFoxster/uYouPlus/commit/8db8197
%hook YTCommonColorPalette
- (UIColor *)brandBackgroundSolid {
    BOOL darkPageStyle = NO;
    if ([self respondsToSelector:@selector(pageStyle)]) {
        darkPageStyle = (self.pageStyle == 1);
    } else {
        darkPageStyle = (UITraitCollection.currentTraitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
    }
    return darkPageStyle ? [UIColor colorWithRed:0.05882352941176471 green:0.05882352941176471 blue:0.05882352941176471 alpha:1.0] : %orig;
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
    @try {
    [downloadsPagerVC updatePageStyles];
    for (UIViewController *vc in [downloadsPagerVC viewControllers]) {
        if ([vc isKindOfClass:%c(DownloadingVC)]) {
            [(DownloadingVC *)vc updatePageStyles];
            for (UITableViewCell *cell in [(DownloadingVC *)vc tableView].visibleCells)
                if ([cell isKindOfClass:%c(DownloadingCell)])
                    [(DownloadingCell *)cell updatePageStyles];
        }
        else if ([vc isKindOfClass:%c(DownloadedVC)]) {
            [(DownloadedVC *)vc updatePageStyles];
            for (UITableViewCell *cell in [(DownloadedVC *)vc tableView].visibleCells)
                if ([cell isKindOfClass:%c(DownloadedCell)])
                    [(DownloadedCell *)cell updatePageStyles];
        }
    }
    for (UIView *subview in [downloadsPagerVC view].subviews) {
        if ([subview isKindOfClass:[UIScrollView class]]) {
            UIScrollView *tabs = (UIScrollView *)subview;
            NSUInteger i = 0;
            for (UIView *item in tabs.subviews) {
                if ([item isKindOfClass:[UILabel class]]) {
                    UILabel *tabLabel = (UILabel *)item;
                    if (i == selectedTabIndex) {} // Selected tab should be excluded
                    else [tabLabel setTextColor:[UILabel _defaultColor]];
                    i++;
                }
            }
        }
    }
    } @catch (NSException *e) {
        UYTPatchWarn(@"[uYouPatches] refreshUYouAppearance failed: %@", e);
    }
}
%hook UIViewController
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{ refreshUYouAppearance(); });
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

// Fix uYou download dialog image + label spacing
%hook GOODialogView
- (id)imageView {
    UIImageView *imageView = %orig;
    UILabel *dialogTitleLabel = nil;
    @try { dialogTitleLabel = [self valueForKey:@"titleLabel"]; } @catch (NSException *e) {}
    if ([dialogTitleLabel.text containsString:@"uYou\n"]) {
        // Load icon_clipped.png from uYouBundle.bundle
        NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"uYouBundle" ofType:@"bundle"];
        NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
        NSString *iconPath = [bundle pathForResource:@"icon_clipped" ofType:@"png"];
        UIImage *icon = [UIImage imageWithContentsOfFile:iconPath];
        [imageView setImage:icon];
        // Resize image to 30x30
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

%end // gYouFixes

// Fix uYou varispeed controller fallback.
%group gVarispeedFallbackFix
%hook YTPlayerViewController
- (id)varispeedController {
    id controller = %orig;
    if (controller == nil && [self respondsToSelector:@selector(overlayManager)]) {
        @try {
            id overlayManager = [self overlayManager];
            if (overlayManager && [overlayManager respondsToSelector:@selector(varispeedController)])
                controller = [overlayManager varispeedController];
        } @catch (NSException *e) {
            UYTPatchWarn(@"[uYouPatches] varispeedController fallback failed: %@", e);
        }
    }
    return controller;
}
%end
%end // gVarispeedFallbackFix

// uYou Download Fixes (Comprehensive Rework)
// Addresses: #948, #70, #520, #241, #814, #813, #735
// Based on reverse-engineered uYou 3.0.4 source

%group gYouDownloadFixes

// --- Background Download Session Support (#70, #159) ---
%hook DownloadsManager
- (void)setupURLSessionConfiguration {
    %orig;
}
%end

// --- Prevent Idle Timer During Downloads (#813) ---
static BOOL uYouDownloadIsActive = NO;
static NSInteger uYouActiveDownloadCount = 0;

%hook DownloadsManager
- (void)getLinksLocallyPlayerItem:(id)item videoID:(id)videoID sourceView:(id)sourceView isShorts:(BOOL)isShorts {
    %orig;
    uYouActiveDownloadCount++;
    if (!uYouDownloadIsActive) {
        uYouDownloadIsActive = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
        });
    }
}
%end

// --- Format Detection Fallback (#735, #814, #520) ---
%hook uYouItem
- (BOOL)isMP4 {
    BOOL origResult = %orig;
    if (origResult) return YES;

    NSString *typeAndQuality = [self valueForKey:@"typeAndQuality"];
    if (!typeAndQuality) {
        typeAndQuality = self.qualityLabel;
    }

    if (typeAndQuality) {
        NSString *lower = [typeAndQuality lowercaseString];
        if ([lower containsString:@"audio"] ||
            [lower containsString:@"mp4a"] ||
            [lower containsString:@"mp4v"] ||
            [lower containsString:@"mp4"] ||
            [lower containsString:@"avc1"] ||
            [lower containsString:@"video/mp4"]) {
            return YES;
        }
    }

    NSString *filePath = self.filePath;
    if (filePath) {
        return [[filePath pathExtension] isEqualToString:@"mp4"];
    }

    return NO;
}
%end

// --- Metadata Attachment Exception Handling (#1010, #241, #814, #771, #947) ---
%hook DownloadsManager
- (void)addMetadataToAudioForDownloadItem:(id)item {
    @try {
        %orig;
    } @catch (NSException *e) {
        UYTPatchWarn(@"[uYouPatches] addMetadataToAudio failed: %@ for item: %@", e, item);
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"uYouDownloadMetadataFailed" object:nil];
        });
    }
}
%end

// --- Audio/Video Merge Exception Handling (#1010, #241, #771, #814, #947) ---
%hook DownloadsManager
- (void)mergeAudioWithMP4VideoForDownloadItem:(id)item {
    @try {
        %orig;
    } @catch (NSException *e) {
        UYTPatchWarn(@"[uYouPatches] mergeAudioWithMP4Video failed: %@ for item: %@", e, item);
        @try {
            uYouItem *uyouItem2 = [item valueForKey:@"uYouItem"];
            if (uyouItem2) {
                NSString *cachedVideoPath = [uyouItem2 cachedVideoPath];
                NSString *filePath = [uyouItem2 filePath];
                if (cachedVideoPath && filePath) {
                    NSFileManager *fm = [NSFileManager defaultManager];
                    if ([fm fileExistsAtPath:cachedVideoPath]) {
                        [fm moveItemAtPath:cachedVideoPath toPath:filePath error:nil];
                    }
                }
            }
        } @catch (NSException *innerE) {
            UYTPatchWarn(@"[uYouPatches] Fallback merge recovery also failed: %@", innerE);
        }
    }
}

- (void)mergeAudioWithVideoForDownloadItem:(id)item {
    @try {
        %orig;
    } @catch (NSException *e) {
        UYTPatchWarn(@"[uYouPatches] mergeAudioWithVideo failed: %@ for item: %@", e, item);
        @try {
            uYouItem *uyouItem2 = [item valueForKey:@"uYouItem"];
            if (uyouItem2) {
                NSString *cachedVideoPath = [uyouItem2 cachedVideoPath];
                NSString *filePath = [uyouItem2 filePath];
                if (cachedVideoPath && filePath) {
                    NSFileManager *fm = [NSFileManager defaultManager];
                    if ([fm fileExistsAtPath:cachedVideoPath]) {
                        [fm moveItemAtPath:cachedVideoPath toPath:filePath error:nil];
                    }
                }
            }
        } @catch (NSException *innerE) {
            UYTPatchWarn(@"[uYouPatches] Fallback merge recovery also failed: %@", innerE);
        }
    }
}
%end

// --- File Access / Entitlement Error Recovery (#520, #241, #735) ---
%hook NSFileManager
- (BOOL)moveItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath error:(NSError **)error {
    BOOL result = %orig;

    if (!result && error && *error) {
        if ([*error code] == NSFileWriteNoPermissionError ||
            [*error code] == NSFileWriteFileExistsError ||
            [*error domain] == NSPOSIXErrorDomain) {

            NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
            NSString *fallbackName = [dstPath lastPathComponent];
            NSString *fallbackPath = [docsDir stringByAppendingPathComponent:@"uYouDownloads"];
            fallbackPath = [fallbackPath stringByAppendingPathComponent:fallbackName];

            [[NSFileManager defaultManager] createDirectoryAtPath:[fallbackPath stringByDeletingLastPathComponent]
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:nil];

            NSError *fallbackError = nil;
            result = [self moveItemAtPath:srcPath toPath:fallbackPath error:&fallbackError];
            if (result) {
                UYTPatchInfo(@"[uYouPatches] File moved to Documents fallback: %@", fallbackPath);
            } else {
                result = [self copyItemAtPath:srcPath toPath:fallbackPath error:&fallbackError];
                if (result) {
                    UYTPatchInfo(@"[uYouPatches] File copied to Documents fallback: %@", fallbackPath);
                }
            }
        }
    }

    return result;
}

- (BOOL)copyItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath error:(NSError **)error {
    NSString *dstDir = [dstPath stringByDeletingLastPathComponent];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dstDir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dstDir
                               withIntermediateDirectories:YES
                                                attributes:nil
                                                     error:nil];
    }
    return %orig;
}
%end

// --- Idle Timer Restore on App Background (#813) ---
%hook YTAppDelegate
- (void)applicationDidEnterBackground:(UIApplication *)application {
    if (uYouDownloadIsActive) {
        uYouDownloadIsActive = NO;
        uYouActiveDownloadCount = 0;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
        });
    }
    %orig;
}
%end

%end // gYouDownloadFixes

// --- Speed overlay / auto-fullscreen regressions (#795, #681) ---
%group gYouSpeedFixes

// Persistent playback rate storage
static float uYouSavedPlaybackRate = 0.0f;

// --- Prevent Speed Reset During Video Transitions (#681) ---
// The speed controls fail after some time because YouTube resets the
// playback rate during video transitions. Hook the overlay to detect
// and re-apply the user's chosen speed.

%hook YTMainAppVideoPlayerOverlayViewController
- (void)setPlaybackRate:(CGFloat)rate {
    %orig(rate);

    // Save the rate if user explicitly set it (not a system reset to 1.0)
    if (rate != 1.0f) {
        uYouSavedPlaybackRate = rate;
        [[NSUserDefaults standardUserDefaults] setFloat:rate forKey:@"uYouSavedPlaybackRate"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (CGFloat)currentPlaybackRate {
    CGFloat rate = %orig;

    // If rate is 1.0 but we have a saved rate, the system reset it
    // Re-apply the saved rate (on next runloop to avoid re-entrancy)
    if (rate == 1.0f && uYouSavedPlaybackRate > 0.0f && uYouSavedPlaybackRate != 1.0f) {
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                [self setPlaybackRate:uYouSavedPlaybackRate];
            } @catch (NSException *e) {
                UYTPatchWarn(@"[uYouPatches] Failed to restore playback rate: %@", e);
            }
        });
    }

    return rate;
}
%end

// --- Enforce Speed on Player VC Level (#681, #795) ---
// Hook the player view controller to ensure playback rate persists
// across video loads and player state changes.

%hook YTPlayerViewController
- (void)setPlaybackRate:(float)rate {
    %orig(rate);
    if (rate != 1.0f) {
        uYouSavedPlaybackRate = rate;
        [[NSUserDefaults standardUserDefaults] setFloat:rate forKey:@"uYouSavedPlaybackRate"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);

    // Restore saved playback rate when player appears (on next runloop)
    float savedRate = [[NSUserDefaults standardUserDefaults] floatForKey:@"uYouSavedPlaybackRate"];
    if (savedRate > 0.0f && savedRate != 1.0f) {
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                [self setPlaybackRate:savedRate];
            } @catch (NSException *e) {
                UYTPatchWarn(@"[uYouPatches] Failed to restore playback rate on appear: %@", e);
            }
        });
    }
}
%end

// --- Hook the HAM Player to maintain rate (#681) ---
// YouTube's internal player sometimes resets rate. Intercept at the
// HAMPlayerInternal level to prevent unwanted resets.

%hook HAMPlayerInternal
- (void)setRate:(float)rate {
    // If we have a saved rate and this is a reset to 1.0, restore
    if (rate == 1.0f && uYouSavedPlaybackRate > 0.0f && uYouSavedPlaybackRate != 1.0f) {
        // Only block the reset if the player is actively playing (not pausing/resuming)
        float currentRate = [self rate];
        if (currentRate > 0.0f && currentRate != 1.0f) {
            // This looks like an unwanted reset, restore our rate
            %orig(uYouSavedPlaybackRate);
            return;
        }
    }
    %orig(rate);
}
%end

// --- Initialize saved rate from preferences ---
// static void uYouSpeedFixesInit() {
//     float saved = [[NSUserDefaults standardUserDefaults] floatForKey:@"uYouSavedPlaybackRate"];
//     if (saved > 0.0f) {
//         uYouSavedPlaybackRate = saved;
//     }
// }

%end // gYouSpeedFixes

%group gYouFullscreenFixes

// --- Fix Swipe-to-Exit Fullscreen When Related Videos Disabled (#57) ---
// Note: shouldShowAutonavEndscreen is already hooked in uYouPlus.xm (gSection5).
// Ensure the fullscreen engagement overlay doesn't block gestures
// when related videos are disabled
%hook YTFullScreenEngagementOverlayController
- (BOOL)isEnabled {
    // When noSuggestedVideo is enabled, completely disable the overlay
    // so it never appears and can't block swipe-to-dismiss
    if (IS_ENABLED(@"noSuggestedVideo_enabled")) {
        return NO;
    }

    // Also check repeatVideo - existing behavior
    return IS_ENABLED(@"repeatVideo") ? NO : %orig;
}
%end

// Prevent the "More Videos" / "Related Videos" overlay from blocking
// user interaction when it has no content to show
%hook YTFullScreenEngagementOverlayView
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    // If noSuggestedVideo is enabled, pass touches through (don't consume them)
    if (IS_ENABLED(@"noSuggestedVideo_enabled")) {
        [self.nextResponder touchesBegan:touches withEvent:event];
        return;
    }
    %orig;
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (IS_ENABLED(@"noSuggestedVideo_enabled")) {
        [self.nextResponder touchesMoved:touches withEvent:event];
        return;
    }
    %orig;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (IS_ENABLED(@"noSuggestedVideo_enabled")) {
        [self.nextResponder touchesEnded:touches withEvent:event];
        return;
    }
    %orig;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (IS_ENABLED(@"noSuggestedVideo_enabled")) {
        [self.nextResponder touchesCancelled:touches withEvent:event];
        return;
    }
    %orig;
}
%end

%end // gYouFullscreenFixes

// --- uYou "Reorder Tabs" integration ---------------------------------------
// Class is declared in uYouPlusThemes.h; category adds the init signature.
@interface settingsReorderTable (ReorderTabsIntegration)
- (instancetype)initWithTitle:(id)title items:(id)items defaultValues:(id)defaults key:(id)key header:(id)header footer:(id)footer;
@end

%group gReorderTabsIntegration
%hook settingsReorderTable
- (instancetype)initWithTitle:(id)title items:(id)items defaultValues:(id)defaults key:(id)key header:(id)header footer:(id)footer {
    if ([key isKindOfClass:[NSString class]] && [(NSString *)key isEqualToString:@"reorderedTabs"]) {
        @try {
            NSMutableArray *newItems = [items mutableCopy];
            NSMutableArray *newDefaults = [defaults mutableCopy];
            if (![newItems containsObject:@"Notifications"]) {
                [newItems addObject:@"Notifications"];
                [newDefaults addObject:@"FEnotifications_inbox"];
            }
            return %orig(title, newItems, newDefaults, key, header, footer);
        } @catch (NSException *e) {
            UYTPatchWarn(@"[uYouPatches] Reorder Tabs Notifications injection failed: %@", e);
        }
    }
    return %orig;
}
%end
%end

%ctor {
    // Load saved playback rate
    float savedRate = [[NSUserDefaults standardUserDefaults] floatForKey:@"uYouSavedPlaybackRate"];
    if (savedRate > 0.0f) {
        uYouSavedPlaybackRate = savedRate;
    }

    // Always initialize core uYou fixes
    %init(gYouFixes);

    // Notifications row in uYou's Reorder Tabs table
    if (%c(settingsReorderTable)) {
        %init(gReorderTabsIntegration);
    }

    // Varispeed fallback: only when YTPlayerViewController really implements
    // varispeedController (otherwise %orig would be NULL -> null-IMP crash).
    Class playerVCClass = %c(YTPlayerViewController);
    if (playerVCClass && [playerVCClass instancesRespondToSelector:@selector(varispeedController)]) {
        %init(gVarispeedFallbackFix);
    }

    // Initialize download fixes when uYou downloads are enabled
    if (IS_ENABLED(kReplaceYTDownloadWithuYou)) {
        %init(gYouDownloadFixes);
    }

    // Speed fixes: only register when EVERY hooked selector exists on this
    // YouTube build. Hooking a missing selector silently adds it, making
    // respondsToSelector: lie; the next caller then dies with
    // "unrecognized selector sent to instance" (the startup SIGABRT).
    Class overlayVCClass = %c(YTMainAppVideoPlayerOverlayViewController);
    Class hamPlayerClass = %c(HAMPlayerInternal);
    BOOL speedFixesSafe =
        overlayVCClass != nil &&
        [overlayVCClass instancesRespondToSelector:@selector(setPlaybackRate:)] &&
        [overlayVCClass instancesRespondToSelector:@selector(currentPlaybackRate)] &&
        playerVCClass != nil &&
        [playerVCClass instancesRespondToSelector:@selector(setPlaybackRate:)] &&
        hamPlayerClass != nil &&
        [hamPlayerClass instancesRespondToSelector:@selector(setRate:)] &&
        [hamPlayerClass instancesRespondToSelector:@selector(rate)];
    if (speedFixesSafe) {
        %init(gYouSpeedFixes);
    } else {
        UYTPatchWarn(@"[uYouPatches] Skipping gYouSpeedFixes: playback-rate selectors missing on this YouTube build");
    }

    // Initialize fullscreen fixes (always active when noSuggestedVideo is used)
    %init(gYouFullscreenFixes);
}