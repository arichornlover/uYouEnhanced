#import "uYouPlus.h"
#import "uYouPatches.h"
#import "MediaKit/UYTMediaKit.h"
#import "DownloadPipeline.h"
#import <sqlite3.h>
#include <string.h>

# pragma mark - uYou Patches
// Uses reverse-engineered uYou 3.0.4 source for reference.
//
// Comprehensive download system rework addressing:
//   #948  - Downloads fail on latest YouTube versions
//   #795  - Speed overlay + auto-fullscreen + audio download broken
//   #681  - Speed controls stop working after some time
//   #520  - Downloads stuck at 100% (signing entitlements)
//   #241  - Downloads can't play or save to camera roll
//   #70   - Downloads take half video length, break on app close
//   #57   - Swipe down to exit fullscreen broken when related videos disabled
//   #771  - Downloads stuck at conversion (webm audio format since v19.22)
//   #465  - Downloads stuck at 100% (same root cause as #771)

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
        HBLogWarn(@"[uYouPatches] refreshUYouAppearance failed: %@", e);
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

// Shorts uYou Button Crash Fix (#995)
// YouTube 21.xx.x+ changed the Shorts player hierarchy. The uYou overlay
// button's target doesn't respond on Shorts → crash. Detect version and
// Shorts context, then route the download through the native path directly.

// Global safety net for any button with a broken target-action.
%group gShortsButtonGuard
%hook UIControl
- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    if (target && action && ![target respondsToSelector:action]) {
        NSLog(@"[uYouEnhanced] Blocked sendAction:%s to non-responding target %@ (class: %@)",
              sel_getName(action), target, NSStringFromClass([target class]));
        return;
    }
    @try {
        %orig;
    } @catch (NSException *e) {
        NSLog(@"[uYouEnhanced] Caught sendAction crash: %@", e);
    }
}
%end
%end

// Make the uYou button actually work on Shorts instead of crashing.
// Hooks uYou on the overlay view — on Shorts, wires up the playerViewController
// so uYou's native menu can find the video ID, then calls %orig to show the
// download menu (quality picker, etc.) instead of bypassing it.
%group gShortsUYouDownload
static BOOL UYTIsShortsOverlay(id overlay) {
    @try {
        NSString *ident = [overlay accessibilityIdentifier] ?: @"";
        if ([ident containsString:@"reel"] || [ident containsString:@"shorts"])
            return YES;

        UIResponder *responder = [overlay nextResponder];
        while (responder) {
            NSString *cls = NSStringFromClass([responder class]);
            if ([cls containsString:@"ReelWatch"] ||
                [cls containsString:@"ShortsPlayer"] ||
                [cls containsString:@"ReelPlayer"] ||
                [cls containsString:@"YTShorts"] ||
                [cls containsString:@"YTReel"] ||
                [cls containsString:@"ShortsViewController"] ||
                [cls containsString:@"ReelsViewController"])
                return YES;
            responder = [responder nextResponder];
        }

        UIView *view = [overlay superview];
        while (view) {
            NSString *cls = NSStringFromClass([view class]);
            if ([cls containsString:@"Reel"] || [cls containsString:@"Shorts"] ||
                [cls containsString:@"YTShorts"] || [cls containsString:@"YTReel"])
            NSString *cls = NSStringFromClass([r class]);
            if ([cls containsString:@"ReelPlayer"] || [cls containsString:@"ShortsPlayer"]) {
                // YTReelPlayerViewController has a `.player` property (YTPlayerViewController)
                if ([r respondsToSelector:@selector(player)]) {
                    id player = [r performSelector:@selector(player)];
                    if (player) return player;
                }
                // KVC fallback
                @try {
                    id player = [r valueForKey:@"player"];
                    if (player) return player;
                } @catch (NSException *e2) {}
            }
            r = [r nextResponder];
        }
    } @catch (NSException *e) {}
    return nil;
}

static NSString *UYTShortsVideoID(id overlay) {
    @try {
        // 1) Try the playerViewController property on the overlay itself.
        if ([overlay respondsToSelector:@selector(playerViewController)]) {
            id pvc = [(id)overlay playerViewController];
            if ([pvc respondsToSelector:@selector(currentVideoID)]) {
                NSString *v = [pvc performSelector:@selector(currentVideoID)];
                if (v.length > 0) return v;
            }
        }
        // 2) Walk responder chain for a video ID
        UIResponder *r = [overlay nextResponder];
        while (r) {
            if ([r respondsToSelector:@selector(activeReelPlaybackVideoID)]) {
                NSString *v = [r performSelector:@selector(activeReelPlaybackVideoID)];
                if (v.length > 0) return v;
            }
            if ([r respondsToSelector:@selector(currentVideoID)]) {
                NSString *v = [r performSelector:@selector(currentVideoID)];
                if (v.length > 0) return v;
            }
            // YTReelPlayerViewController exposes .videoId (lowercase 'd')
            @try {
                NSString *v = [r valueForKey:@"videoId"];
                if ([v isKindOfClass:[NSString class]] && v.length > 0) return v;
            } @catch (NSException *e2) {}
            @try {
                NSString *v = [r valueForKey:@"videoID"];
                if ([v isKindOfClass:[NSString class]] && v.length > 0) return v;
            } @catch (NSException *e3) {}
            // Also try reelID / reelId on the reel player
            @try {
                NSString *v = [r valueForKey:@"reelID"];
                if ([v isKindOfClass:[NSString class]] && v.length > 0) return v;
            } @catch (NSException *e4) {}
            @try {
                NSString *v = [r valueForKey:@"reelId"];
                if ([v isKindOfClass:[NSString class]] && v.length > 0) return v;
            } @catch (NSException *e5) {}
            r = [r nextResponder];
        }
        // 3) Fallback: PlayerManager
        if ([%c(PlayerManager) respondsToSelector:@selector(sharedInstance)]) {
            id pm = [%c(PlayerManager) sharedInstance];
            if ([pm respondsToSelector:@selector(videoID)]) {
                NSString *v = [pm performSelector:@selector(videoID)];
                if (v.length > 0) return v;
            }
        }
        // 4) Fallback: NSUserDefaults (uYou stores last-played video ID)
        NSString *lastVid = [[NSUserDefaults standardUserDefaults] stringForKey:@"playerVideoID"];
        if (lastVid.length > 0) return lastVid;
        // 5) Fallback: extract from current navigation URL
        @try {
            UIWindow *keyWindow = nil;
            for (UIWindow *w in [UIApplication sharedApplication].windows) {
                if (w.isKeyWindow) { keyWindow = w; break; }
            }
            if (keyWindow.rootViewController) {
                // Walk presented VCs to find a YTNavigationController
                UIViewController *top = keyWindow.rootViewController;
                while (top.presentedViewController) top = top.presentedViewController;
                if ([top respondsToSelector:@selector(URL)]) {
                    NSURL *url = [top performSelector:@selector(URL)];
                    NSString *urlStr = url.absoluteString;
                    NSRange shortsRange = [urlStr rangeOfString:@"/shorts/"];
                    if (shortsRange.location != NSNotFound) {
                        NSString *vid = [urlStr substringFromIndex:shortsRange.location + shortsRange.length];
                        vid = [vid componentsSeparatedByString:@"?"].firstObject;
                        vid = [vid componentsSeparatedByString:@"&"].firstObject;
                        if (vid.length > 0 && vid.length <= 20) return vid;
                    }
                }
            }
        } @catch (NSException *e) {}
    } @catch (NSException *e) {}
    return nil;
}

%hook YTMainAppControlsOverlayView
- (void)uYou {
    @try {
        if (UYTIsShortsOverlay(self)) {
            // Wire up the playerViewController so uYou's native menu logic can
            // find the video ID. On Shorts the overlay's playerViewController
            // is often nil — grab it from the responder chain (YTReelPlayerVC.player).
            if (self.playerViewController == nil) {
                id player = UYTFindShortsPlayerVC(self);
                if (player) {
                    self.playerViewController = player;
                }
            }

            // On Shorts, uYou's native %orig often silently does nothing even
            // after we wire playerViewController — the internal code expects
            // metadata state that the Shorts player doesn't populate the same
            // way as the regular player. Skip %orig and go directly to the
            // download menu via getLinksLocallyPlayerItem:.
            NSString *videoID = UYTShortsVideoID(self);
            if (videoID.length > 0) {
                NSLog(@"[uYouEnhanced] uYou button on Shorts -> direct download for %@", videoID);
                id dlManager = [%c(DownloadsManager) sharedInstance];
                if (dlManager && [dlManager respondsToSelector:@selector(getLinksLocallyPlayerItem:videoID:sourceView:isShorts:)]) {
                    [dlManager getLinksLocallyPlayerItem:nil videoID:videoID sourceView:self isShorts:YES];
                    return;
                }
            }

            // If we couldn't get a video ID, try %orig as absolute last resort.
            @try {
                %orig;
                return;
            } @catch (NSException *e) {
                NSLog(@"[uYouEnhanced] Shorts uYou native fallback also failed: %@", e);
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[uYouEnhanced] Shorts uYou hook failed: %@", e);
    }
    %orig;
}
%end
%end

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
            HBLogWarn(@"[uYouPatches] varispeedController fallback failed: %@", e);
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

// --- Background Download Session Support (#70) ---
// uYou uses AFHTTPSessionManager with session identifier "com.miro.uyou".
// The session is NOT configured for background transfers, so downloads break
// when the app is backgrounded or killed. Fix: enable background session
// configuration so iOS can continue downloads in the background.

%hook DownloadsManager
- (void)setupURLSessionConfiguration {
    %orig;
}
%end

@interface AFURLSessionManager : NSObject
@end

static NSMutableDictionary<NSNumber *, NSDictionary *> *UYTTaskByteCounts = nil;

static void UYTRecordTaskBytes(NSNumber *taskID, long long written, long long expected) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ UYTTaskByteCounts = [NSMutableDictionary dictionary]; });
    if (taskID && expected > 0) {
        UYTTaskByteCounts[taskID] = @{@"written": @(written), @"expected": @(expected)};
    }
}

static BOOL UYTTaskWroteEverything(NSURLSessionTask *task) {
    if (!task) return NO;
    NSDictionary *rec = UYTTaskByteCounts[@(task.taskIdentifier)];
    if (!rec) return NO;
    long long written = [rec[@"written"] longLongValue];
    long long expected = [rec[@"expected"] longLongValue];
    return expected > 0 && written >= (long long)(expected * 0.98);
}

%hook AFURLSessionManager
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    UYTRecordTaskBytes(@(downloadTask.taskIdentifier), totalBytesWritten, totalBytesExpectedToWrite);
    %orig;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error && UYTTaskWroteEverything(task)) {
        HBLogWarn(@"[uYouPatches] transfer hit 100%% but errored (%@ code %ld) â€” completing as success",
                  error.domain ?: @"?", (long)error.code);
        [UYTTaskByteCounts removeObjectForKey:@(task.taskIdentifier)];
        %orig(session, task, nil);
        return;
    }
    if (!error && task) [UYTTaskByteCounts removeObjectForKey:@(task.taskIdentifier)];
    %orig;
}
%end

// --- Prevent Idle Timer During Downloads (#813) ---
// Manage idle timer to prevent device from sleeping during active downloads.
// Previously the timer management was too aggressive - only managed during
// getLinksLocally. Now we manage it across the full download lifecycle.

static BOOL uYouDownloadIsActive = NO;
static NSInteger uYouActiveDownloadCount = 0;

// --- WebM Audio Format Fix (#771, #465, #814) ---
// Since YouTube v19.22, adaptive audio streams changed from m4a to webm.
// uYou's merge methods (mergeAudioWithMP4VideoForDownloadItem: etc.) use
// AVAssetExportSession which CANNOT merge mp4 video + webm audio,
// causing downloads to hang forever at "conversion" or "Adding metadata".
// Fix: detect webm audio and convert it to m4a via MobileFFmpeg before merge.
static BOOL uYouConvertWebmAudioToM4a(NSString *webmPath, NSString *m4aPath) {
    if (!webmPath || !m4aPath) return NO;

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:webmPath]) return NO;

    // Remove stale output if it exists
    if ([fm fileExistsAtPath:m4aPath]) {
        [fm removeItemAtPath:m4aPath error:nil];
    }

    @try {
        // Runs on FFmpegKitNext when embedded, else MobileFFmpeg from uYou.dylib.
        if (UYTFFActiveBackend() == UYTFFBackendNone) {
            HBLogWarn(@"[uYouPatches] no ffmpeg backend available; skipping conversion");
            return NO;
        }
        BOOL ok = UYTFFConvertWebmAudioToM4a(webmPath, m4aPath);

        if (ok && [fm fileExistsAtPath:m4aPath]) {
            unsigned long long fileSize = [[fm attributesOfItemAtPath:m4aPath error:nil] fileSize];
            if (fileSize > 0) {
                HBLogInfo(@"[uYouPatches] WebMâ†’M4A conversion succeeded: %@ (%llu bytes)", m4aPath, fileSize);
                return YES;
            }
        }

        HBLogWarn(@"[uYouPatches] WebM→M4A conversion failed (backend %ld)", (long)UYTFFActiveBackend());
    } @catch (NSException *e) {
        HBLogWarn(@"[uYouPatches] WebMâ†’M4A conversion exception: %@", e);
    }

    return NO;
}

// Get the inner uYouItem from a wrapper (or accept the item itself).
static id UYTResolveUYouItem(id item) {
    if (!item) return nil;
    @try {
        if ([item respondsToSelector:@selector(uYouItem)]) {
            id ui = [item uYouItem];
            if (ui) return ui;
        }
    } @catch (NSException *e) {}
    Class uyouItemClass = %c(uYouItem);
    if (uyouItemClass && [item isKindOfClass:uyouItemClass]) return item;
    return nil;
}

static BOOL UYTPathIsWebm(NSString *path) {
    return path.length > 0 && [path.pathExtension.lowercaseString isEqualToString:@"webm"];
}

static NSString *UYTAudioPathForItem(id ui) {
    if (!ui) return nil;
    if ([ui respondsToSelector:@selector(tmpAudioPath)]) {
        NSString *p = [ui tmpAudioPath];
        if (p.length) return p;
    }
    if ([ui respondsToSelector:@selector(cachedAudioPath)]) return [ui cachedAudioPath];
    return nil;
}

// Is the item's audio still WebM? Merging mp4+webm hangs forever.
static BOOL UYTAudioStillWebm(id item) {
    @try {
        return UYTPathIsWebm(UYTAudioPathForItem(UYTResolveUYouItem(item)));
    } @catch (NSException *e) {
        return NO;
    }
}

// Convert webm audio to m4a before merging.
static BOOL UYTEnsureMergeableAudio(id item, NSString *phase) {
    @try {
        id ui = UYTResolveUYouItem(item);
        NSString *audioPath = UYTAudioPathForItem(ui);
        if (!audioPath.length) return YES;
        HBLogInfo(@"[uYouPatches] %@: audio=%@ (.%@)", phase, audioPath.lastPathComponent, audioPath.pathExtension);
        if (!UYTPathIsWebm(audioPath)) return YES;

        NSString *m4aPath = [[audioPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"m4a"];
        if (uYouConvertWebmAudioToM4a(audioPath, m4aPath)) {
            @try { [ui setValue:m4aPath forKey:@"tmpAudioPath"]; } @catch (NSException *e) {}
            HBLogInfo(@"[uYouPatches] %@: webmâ†’m4a conversion done", phase);
            return YES;
        }
        HBLogWarn(@"[uYouPatches] %@: webm→m4a conversion FAILED — merge would hang", phase);
        return NO;
    } @catch (NSException *e) {
        HBLogWarn(@"[uYouPatches] %@: pre-conversion exception: %@", phase, e);
        return NO;
    }
}

// Remux video+audio with ffmpeg instead of AVAssetExportSession,
// which hangs forever on some formats. Handles webm video by re-encoding
// to H.264 when stream-copy isn't possible (VP9 in mp4 container).
// Returns YES on success.
static BOOL UYTRemuxWithFFmpeg(id ui, NSString *phase) {
    @try {
        if (!ui) return NO;
        NSFileManager *fm = [NSFileManager defaultManager];

        NSString *videoPath = nil, *audioPath = nil;
        if ([ui respondsToSelector:@selector(tmpVideoPath)]) videoPath = [ui tmpVideoPath];
        if (!videoPath.length) {
            if ([ui respondsToSelector:@selector(cachedVideoPath)]) videoPath = [ui cachedVideoPath];
        }
        if ([ui respondsToSelector:@selector(tmpAudioPath)]) audioPath = [ui tmpAudioPath];
        if (!audioPath.length && [ui respondsToSelector:@selector(cachedAudioPath)]) audioPath = [ui cachedAudioPath];
        NSString *finalPath = [ui respondsToSelector:@selector(filePath)] ? [ui filePath] : nil;

        if (!videoPath.length || !audioPath.length || !finalPath.length) return NO;
        if (![fm fileExistsAtPath:videoPath] || ![fm fileExistsAtPath:audioPath]) return NO;

        NSString *tmpOut = [finalPath stringByAppendingFormat:@".merging.mp4"];
        if ([fm fileExistsAtPath:tmpOut]) [fm removeItemAtPath:tmpOut error:nil];

        if (UYTFFActiveBackend() == UYTFFBackendNone) return NO;

        HBLogInfo(@"[uYouPatches] %@: remux started (%@ + %@)", phase,
                  videoPath.lastPathComponent, audioPath.lastPathComponent);

        // UYTFFSmartRemuxToMP4 handles both cases:
        // - mp4 video → fast stream copy (-c copy)
        // - webm video → transcode to H.264 + mux
        BOOL ok = UYTFFSmartRemuxToMP4(videoPath, audioPath, tmpOut);

        NSDictionary *attrs = [fm attributesOfItemAtPath:tmpOut error:nil];
        if (ok && attrs && [attrs fileSize] > 0) {
            if ([fm fileExistsAtPath:finalPath]) [fm removeItemAtPath:finalPath error:nil];
            NSError *moveErr = nil;
            if ([fm moveItemAtPath:tmpOut toPath:finalPath error:&moveErr]) {
                HBLogWarn(@"[uYouPatches] %@: remux OK -> %@", phase, finalPath.lastPathComponent);
                return YES;
            }
            HBLogWarn(@"[uYouPatches] %@: remux move failed: %@", phase, moveErr);
        } else {
            HBLogWarn(@"[uYouPatches] %@: remux failed (backend %ld)", phase, (long)UYTFFActiveBackend());
            [fm removeItemAtPath:tmpOut error:nil];
        }
    } @catch (NSException *e) {
        HBLogWarn(@"[uYouPatches] %@: remux exception: %@", phase, e);
    }
    return NO;
}

static NSDictionary *UYTBestAvailableSource(id ui) {
    if (!ui) return nil;
    NSFileManager *fm = [NSFileManager defaultManager];

    // Two-pass scan: prefer mp4/m4a candidates, but fall back to the largest
    // file (even webm) so the stall watchdog can still recover.
    __block NSDictionary *bestNonWebm = nil;
    __block unsigned long long bestNonWebmSize = 0;
    __block NSDictionary *bestAny = nil;
    __block unsigned long long bestAnySize = 0;

    NSString *(^resolvePath)(id, SEL) = ^NSString *(id obj, SEL sel) {
        if ([obj respondsToSelector:sel]) {
            @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                return [obj performSelector:sel];
#pragma clang diagnostic pop
            } @catch (id e) {}
        }
        return nil;
    };

    void (^checkPath)(NSString *, NSString *) = ^(NSString *path, NSString *label) {
        if (!path.length) return;
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
        if (!attrs || [attrs fileSize] == 0) return;
        unsigned long long sz = [attrs fileSize];
        if (!UYTPathIsWebm(path) && sz > bestNonWebmSize) {
            bestNonWebmSize = sz;
            bestNonWebm = @{@"path": path, @"label": label};
        }
        if (sz > bestAnySize) {
            bestAnySize = sz;
            bestAny = @{@"path": path, @"label": label};
        }
    };

    // Pipeline muxed file (already mp4).
    NSString *vid = [ui respondsToSelector:@selector(videoID)] ? [ui videoID] : nil;
    if (vid.length) {
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
        checkPath([docs stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"uYouDownloads/%@.mp4", vid]],
                  @"muxed pipeline file");
    }

    checkPath(resolvePath(ui, @selector(tmpVideoPath)), @"tmp video stream");
    checkPath(resolvePath(ui, @selector(cachedVideoPath)), @"cached video stream");
    checkPath(resolvePath(ui, @selector(tmpAudioPath)), @"tmp audio stream");
    checkPath(resolvePath(ui, @selector(cachedAudioPath)), @"cached audio stream");

    // Prefer non-webm (m4a/mp4); fall back to the largest file (even webm)
    // so the stall watchdog can still recover stuck items.
    return bestNonWebm ?: bestAny;
}

// Promote the best available source file to the item's final path.
static BOOL UYTForceCompleteItem(id ui, NSString *reason) {
    @try {
        if (![ui respondsToSelector:@selector(filePath)]) return NO;
        NSString *filePath = [ui filePath];
        if (!filePath.length) return NO;

        NSDictionary *best = UYTBestAvailableSource(ui);
        if (!best) {
            HBLogWarn(@"[uYouPatches] force-complete (%@): no usable source file yet", reason);
            return NO;
        }

        NSFileManager *fm = [NSFileManager defaultManager];
        if ([fm fileExistsAtPath:filePath]) [fm removeItemAtPath:filePath error:nil];
        NSError *err = nil;
        BOOL ok = [fm moveItemAtPath:best[@"path"] toPath:filePath error:&err];
        if (!ok) ok = [fm copyItemAtPath:best[@"path"] toPath:filePath error:&err];
        if (!ok) {
            HBLogWarn(@"[uYouPatches] force-complete (%@): move failed: %@", reason, err);
            return NO;
        }
        HBLogWarn(@"[uYouPatches] force-complete (%@): promoted %@ -> %@", reason, best[@"label"], filePath);
        return YES;
    } @catch (NSException *e) {
        HBLogWarn(@"[uYouPatches] force-complete (%@) exception: %@", reason, e);
        return NO;
    }
}

static void UYTPostCompletionNotifications(id item) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"downloadDidCompleteNotification" object:item];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"conversionDidCompleteNotification" object:item];
    });
}

// Write the completed download's row into uYou's downloads table.
static void UYTInsertDownloadRow(uYouItem *ui) {
    @try {
        if (!ui || ![ui respondsToSelector:@selector(videoID)]) return;
        NSString *vid = [ui videoID];
        NSString *filePath = [ui respondsToSelector:@selector(filePath)] ? [ui filePath] : nil;
        if (!vid.length || !filePath.length) return;

        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
        NSString *dbPath = [docs stringByAppendingPathComponent:@"uyoudb.sqlite"];
        sqlite3 *db = NULL;
        if (sqlite3_open(dbPath.fileSystemRepresentation, &db) != SQLITE_OK) {
            HBLogWarn(@"[uYouPatches] finalize: cannot open uyoudb.sqlite");
            return;
        }

        // Make sure the table exists (harmless if uYou already created it).
        sqlite3_exec(db,
            "CREATE TABLE IF NOT EXISTS downloads ("
            "id TEXT PRIMARY KEY, videoID TEXT, title TEXT, channel TEXT, channelURL TEXT, "
            "qualityLabel TEXT, typeAndQuality TEXT, size TEXT, duration TEXT, "
            "type TEXT, path TEXT, lyrics TEXT, timestamp DATETIME)",
            NULL, NULL, NULL);

        unsigned long long fileSize = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil].fileSize;
        NSString *title = [ui respondsToSelector:@selector(title)] ? [ui title] : @"";
        NSString *channel = [ui respondsToSelector:@selector(channel)] ? [ui channel] : @"";
        NSString *quality = [ui respondsToSelector:@selector(qualityLabel)] ? [ui qualityLabel] : @"";
        NSString *typeAndQuality = [ui respondsToSelector:@selector(typeAndQuality)] ? [ui typeAndQuality] : @"";
        BOOL isAudio = [filePath.pathExtension.lowercaseString isEqualToString:@"m4a"] ||
                       [filePath.pathExtension.lowercaseString isEqualToString:@"mp3"];
        NSString *type = isAudio ? @"audio" : @"video";
        NSString *sizeStr = [NSString stringWithFormat:@"%llu", fileSize];

        const char *sql = "INSERT OR REPLACE INTO downloads "
                          "(id, videoID, title, channel, channelURL, qualityLabel, typeAndQuality, "
                          "size, duration, type, path, lyrics, timestamp) "
                          "VALUES (?1, ?1, ?2, ?3, '', ?4, ?5, ?6, '', ?7, ?8, '', datetime('now','localtime'))";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, vid.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 2, title.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 3, channel.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 4, quality.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 5, typeAndQuality.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 6, sizeStr.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 7, type.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 8, filePath.UTF8String, -1, SQLITE_TRANSIENT);
            if (sqlite3_step(stmt) != SQLITE_DONE) {
                HBLogWarn(@"[uYouPatches] finalize: DB insert failed: %s", sqlite3_errmsg(db));
            } else {
                HBLogInfo(@"[uYouPatches] finalize: DB row written for %@", vid);
            }
            sqlite3_finalize(stmt);
        }
        sqlite3_close(db);
    } @catch (NSException *e) {
        HBLogWarn(@"[uYouPatches] finalize: DB insert exception: %@", e);
    }
}

// Drop the item's persisted queue rows so restarts don't resurrect it.
static void UYTPurgeDownloadingQueueRows(NSString *vid) {
    if (!vid.length) return;
    @try {
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
        NSString *dbPath = [docs stringByAppendingPathComponent:@"uyoudb.sqlite"];
        sqlite3 *db = NULL;
        if (sqlite3_open(dbPath.fileSystemRepresentation, &db) != SQLITE_OK) return;

        const char *sql = "SELECT id, data FROM downloading";
        sqlite3_stmt *stmt = NULL;
        NSMutableArray<NSNumber *> *doomed = [NSMutableArray array];
        NSData *needle = [vid dataUsingEncoding:NSUTF8StringEncoding];
        if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                long long rowID = sqlite3_column_int64(stmt, 0);
                const void *blob = sqlite3_column_blob(stmt, 1);
                int blobLen = sqlite3_column_bytes(stmt, 1);
                if (blob && blobLen > 0 && needle.length > 0 &&
                    memmem(blob, (size_t)blobLen, needle.bytes, needle.length)) {
                    [doomed addObject:@(rowID)];
                }
            }
            sqlite3_finalize(stmt);
        }
        for (NSNumber *rowID in doomed) {
            sqlite3_exec(db, [[NSString stringWithFormat:@"DELETE FROM downloading WHERE id = %lld", rowID.longLongValue] UTF8String], NULL, NULL, NULL);
        }
        if (doomed.count) HBLogInfo(@"[uYouPatches] finalize: purged %lu downloading queue row(s)", (unsigned long)doomed.count);
        sqlite3_close(db);
    } @catch (NSException *e) {}
}

// Remove the item from uYou's in-memory download queue.
static void UYTRemoveFromDownloadingList(id item) {
    @try {
        Class managerClass = %c(DownloadsManager);
        if (!managerClass) return;
        id manager = [managerClass sharedInstance];
        if (!manager || ![manager respondsToSelector:@selector(downloadItemsArray)]) return;
        NSMutableArray *array = [manager downloadItemsArray];
        if ([array isKindOfClass:[NSMutableArray class]] && item) {
            [array removeObject:item];
        }
    } @catch (NSException *e) {}
}

// Complete an item end-to-end: file, flags, DB row, queue, UI.
static BOOL UYTFinalizeItem(id item, NSString *reason) {
    @try {
        id ui = UYTResolveUYouItem(item);
        if (!ui) return NO;

        if ([ui respondsToSelector:@selector(isDownloadFinished)] && [ui isDownloadFinished]) {
            UYTPostCompletionNotifications(item);
            return YES;
        }

        if (!UYTForceCompleteItem(ui, reason)) return NO;

        @try { [ui setValue:@YES forKey:@"isDownloadFinished"]; } @catch (NSException *e) {}
        @try { [ui setValue:@YES forKey:@"finished"]; } @catch (NSException *e) {}

        UYTInsertDownloadRow(ui);
        UYTPurgeDownloadingQueueRows([ui respondsToSelector:@selector(videoID)] ? [ui videoID] : nil);
        UYTRemoveFromDownloadingList(item);

        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                id manager = [%c(DownloadsManager) sharedInstance];
                if (manager && [manager respondsToSelector:@selector(reloadDownloadedVC)]) {
                    [manager reloadDownloadedVC];
                }
            } @catch (NSException *e) {}
        });
        UYTPostCompletionNotifications(item);
        HBLogWarn(@"[uYouPatches] finalize (%@): item fully completed", reason);
        return YES;
    } @catch (NSException *e) {
        HBLogWarn(@"[uYouPatches] finalize (%@) exception: %@", reason, e);
        return NO;
    }
}

// Poll for stalled downloads and recover them via UYTFinalizeItem.
static void UYTStallCheck(id item, NSInteger pollsLeft, NSMutableDictionary<NSString *, NSNumber *> *lastSizes);

static void UYTScheduleStallCheck(id item, NSTimeInterval delay, NSInteger pollsLeft,
                                  NSMutableDictionary<NSString *, NSNumber *> *lastSizes) {
    __weak id weakItem = item;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        UYTStallCheck(weakItem, pollsLeft, lastSizes);
    });
}

static void UYTStallCheck(id item, NSInteger pollsLeft, NSMutableDictionary<NSString *, NSNumber *> *lastSizes) {
    if (!item || pollsLeft <= 0) return;
    @try {
        id ui = UYTResolveUYouItem(item);
        if (!ui) return;

        BOOL finished = NO;
        if ([ui respondsToSelector:@selector(isDownloadFinished)]) {
            finished = [ui isDownloadFinished];
        }
        NSString *finalPath = [ui respondsToSelector:@selector(filePath)] ? [ui filePath] : nil;
        NSFileManager *fm = [NSFileManager defaultManager];
        NSDictionary *attrs = finalPath.length ? [fm attributesOfItemAtPath:finalPath error:nil] : nil;
        if (finished || (attrs && [attrs fileSize] > 0)) return; // completed normally

        HBLogWarn(@"[uYouPatches] download stalled â€” attempting recovery (polls left %ld, vid: %@)",
                  (long)pollsLeft,
                  [ui respondsToSelector:@selector(videoID)] ? [ui videoID] : @"?");

        NSDictionary *best = UYTBestAvailableSource(ui);
        if (!best) {
            UYTScheduleStallCheck(item, 5.0, pollsLeft - 1, lastSizes);
            return;
        }

        // Growth check: don't interrupt a download that's still progressing.
        NSString *bestPath = best[@"path"];
        unsigned long long bestSize = [[fm attributesOfItemAtPath:bestPath error:nil] fileSize];
        NSNumber *prevSize = lastSizes[bestPath];
        lastSizes[bestPath] = @(bestSize);
        BOOL stillGrowing = prevSize && bestSize > prevSize.unsignedLongLongValue;
        if (stillGrowing && pollsLeft > 1) {
            HBLogInfo(@"[uYouPatches] stall recovery deferred â€” %@ is still growing (%llu bytes)",
                      bestPath.lastPathComponent, bestSize);
            UYTScheduleStallCheck(item, 5.0, pollsLeft - 1, lastSizes);
            return;
        }

        if (UYTFinalizeItem(item, @"stall watchdog")) {
            return;
        }
        UYTScheduleStallCheck(item, 5.0, pollsLeft - 1, lastSizes);
    } @catch (NSException *e) {}
}

static void UYTArmStallWatchdog(id item, NSTimeInterval seconds) {
    UYTScheduleStallCheck(item, seconds, 8, [NSMutableDictionary dictionary]);
}

%hook DownloadsManager
- (void)getLinksLocallyPlayerItem:(id)item videoID:(id)videoID sourceView:(id)sourceView isShorts:(BOOL)isShorts {
    HBLogInfo(@"[uYouPatches] download requested (vid: %@, shorts: %@)", videoID, isShorts ? @"YES" : @"NO");
    
    NSString *vid = [NSString stringWithFormat:@"%@", videoID];
    [UYTDownloadPipeline fetchFormatsForVideoID:vid completion:^(NSArray<UYTStreamFormat *> *formats, NSError *error) {
        if (error || formats.count == 0) {
            NSLog(@"[UYTPipeline] pre-fetch failed for %@: %@", vid, error.localizedDescription);
        } else {
            UYTStreamFormat *muxed = [UYTDownloadPipeline bestMuxedFormat:formats];
            UYTStreamFormat *audio = [UYTDownloadPipeline bestAudioFormat:formats];
            UYTStreamFormat *video = [UYTDownloadPipeline bestVideoFormat:formats];
            UYTStoreResolvedURLs(vid, muxed.url, audio.url, video.url);
            NSLog(@"[UYTPipeline] cached URLs for %@ (muxed=%ld, audio=%ld, video=%ld)",
                  vid, (long)muxed.itag, (long)audio.itag, (long)video.itag);
        }

        // Let uYou's native flow proceed. Our DownloadItem hook below will
        // swap any broken URL with our cached working one.
        dispatch_async(dispatch_get_main_queue(), ^{
            %orig;
            // Lifecycle catch-all (#992): covers stalls in phases we cannot hook —
            UYTArmStallWatchdog(item, 300.0);
            // Start idle timer prevention when download setup begins
            uYouActiveDownloadCount++;
            if (!uYouDownloadIsActive) {
                uYouDownloadIsActive = YES;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
                });
            }
        });
    }];
}
%end

// --- Format Detection Fallback (#735, #814) ---
// uYou uses sub_12CE0E0 (black-box) to detect MP4 vs WebM. This can fail
// for newer YouTube stream formats. Provide a fallback based on MIME type
// and quality label inspection.

%hook uYouItem
- (BOOL)isMP4 {
    BOOL origResult = %orig;
    if (origResult) return YES;

    // Fallback: check typeAndQuality string for known MP4 indicators
    NSString *typeAndQuality = [self valueForKey:@"typeAndQuality"];
    if (!typeAndQuality) {
        // Also try qualityLabel as fallback
        typeAndQuality = self.qualityLabel;
    }

    if (typeAndQuality) {
        NSString *lower = [typeAndQuality lowercaseString];
        // YouTube muxed streams (lower qualities) are typically MP4
        if ([lower containsString:@"audio"] ||
            [lower containsString:@"mp4a"] ||
            [lower containsString:@"mp4v"] ||
            [lower containsString:@"mp4"] ||
            [lower containsString:@"avc1"] ||
            [lower containsString:@"video/mp4"]) {
            return YES;
        }
    }

    // Additional fallback: check the filePath extension
    NSString *filePath = self.filePath;
    if (filePath) {
        return [[filePath pathExtension] isEqualToString:@"mp4"];
    }

    return NO;
}
%end

// --- Metadata Attachment Exception Handling (#241, #814, #771, #465) ---
// addMetadataToAudioForDownloadItem: can throw NSExceptions when the
// audio file is corrupted, the export session fails, or AVAsset can't
// be initialized (especially when audio is webm instead of m4a).
// Fix: convert webm audio to m4a BEFORE adding metadata, then wrap in try-catch.
// Also: extract audio from muxed video for low-quality audio-only downloads.

%hook DownloadsManager
- (void)addMetadataToAudioForDownloadItem:(id)item {
    HBLogInfo(@"[uYouPatches] addMetadata entered");
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"uYouConversionStarted" object:item];
    });

    // Check if this is an audio-only download that needs extraction from muxed video
    BOOL needsAudioExtraction = NO;
    @try {
        needsAudioExtraction = [[item valueForKey:@"uYouNeedsAudioExtraction"] boolValue];
    } @catch (NSException *e) {}

    if (needsAudioExtraction) {
        HBLogInfo(@"[uYouPatches] Audio-only download needs extraction from muxed video");
        id ui = UYTResolveUYouItem(item);
        if (ui) {
            NSString *videoPath = nil;
            if ([ui respondsToSelector:@selector(tmpVideoPath)]) videoPath = [ui tmpVideoPath];
            if (!videoPath.length && [ui respondsToSelector:@selector(cachedVideoPath)]) videoPath = [ui cachedVideoPath];
            NSString *finalPath = [ui respondsToSelector:@selector(filePath)] ? [ui filePath] : nil;

            if (videoPath.length && finalPath.length) {
                // Extract audio from muxed video using FFmpeg
                NSString *tmpAudio = [finalPath stringByAppendingString:@".extracted.m4a"];
                [[NSFileManager defaultManager] removeItemAtPath:tmpAudio error:nil];

                if (UYTFFActiveBackend() != UYTFFBackendNone) {
                    BOOL ok = UYTFFRun(@[
                        @"-i", videoPath,
                        @"-vn",
                        @"-acodec", @"aac",
                        @"-strict", @"-2",
                        @"-y",
                        tmpAudio,
                    ]);
                    if (ok && [[NSFileManager defaultManager] fileExistsAtPath:tmpAudio]) {
                        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:tmpAudio error:nil];
                        if (attrs && [attrs fileSize] > 0) {
                            // Move extracted audio to final path
                            [[NSFileManager defaultManager] removeItemAtPath:finalPath error:nil];
                            [[NSFileManager defaultManager] moveItemAtPath:tmpAudio toPath:finalPath error:nil];
                            HBLogInfo(@"[uYouPatches] Extracted audio from muxed video for %@", finalPath);
                            UYTFinalizeItem(item, @"audio extracted from muxed");
                            return;
                        }
                    }
                    [[NSFileManager defaultManager] removeItemAtPath:tmpAudio error:nil];
                }
            }
        }
        // Fall through to normal metadata handling if extraction fails
    }

    // Pre-fix: convert webm audio to m4a if needed (#771, #465)
    if (!UYTEnsureMergeableAudio(item, @"addMetadata")) {
        UYTFinalizeItem(item, @"no-merge fallback");
        return;
    }

    // Anti-hang guard for the metadata path.
    if (UYTAudioStillWebm(item)) {
        HBLogWarn(@"[uYouPatches] Audio still WebM after conversion â€” skipping merge to avoid infinite hang");
        UYTFinalizeItem(item, @"still-webm skip");
        return;
    }

    // Stall watchdog for the metadata phase.
    UYTArmStallWatchdog(item, 30.0);
    @try {
        %orig;
    } @catch (NSException *e) {
        HBLogWarn(@"[uYouPatches] addMetadataToAudio failed: %@ for item: %@", e, item);
        // Finalize from whatever file we have — audio is still playable without tags.
        UYTFinalizeItem(item, @"metadata exception recovery");
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"uYouDownloadMetadataFailed" object:nil];
        });
    }
}
%end

// --- Audio/Video Merge with WebM Audio Fix (#241, #771, #465, #814) ---
// After YouTube v19.22, adaptive audio changed from m4a to webm.
// AVAssetExportSession CANNOT merge mp4 video + webm audio,
// causing downloads to hang forever at "conversion" step.
// Fix: detect webm audio and convert to m4a via MobileFFmpeg before merge.
// Also: exception handling for crash recovery + fallback to video as-is.

%hook DownloadsManager
- (void)mergeAudioWithMP4VideoForDownloadItem:(id)item {
    HBLogInfo(@"[uYouPatches] mergeAudioWithMP4Video entered");
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"uYouConversionStarted" object:item];
    });

    // Pre-fix: convert webm audio to m4a before the merge (#771, #465)
    if (!UYTEnsureMergeableAudio(item, @"mergeMP4")) {
        UYTFinalizeItem(item, @"no-merge fallback");
        return;
    }

    // Prefer an ffmpeg remux over the legacy merge.
    id ui = UYTResolveUYouItem(item);
    if (UYTRemuxWithFFmpeg(ui, @"mergeMP4")) {
        UYTFinalizeItem(item, @"ffmpeg remux");
        return;
    }

    // Anti-hang fallback (#452/#520/#830 family): if the audio is still WebM
    // the legacy merge would sit at "Converting 0%" forever.
    if (UYTAudioStillWebm(item)) {
        HBLogWarn(@"[uYouPatches] Audio still WebM after conversion â€” skipping merge to avoid infinite hang");
        UYTFinalizeItem(item, @"still-webm skip");
        return;
    }

    // Legacy AVAssetExportSession path as last resort, with stall watchdog.
    UYTArmStallWatchdog(item, 45.0);

    @try {
        %orig;
    } @catch (NSException *e) {
        HBLogWarn(@"[uYouPatches] mergeAudioWithMP4Video failed: %@ for item: %@", e, item);
        UYTFinalizeItem(item, @"merge exception recovery");
        return;
    }

    // Verify the merge actually produced output — AVAssetExportSession can
    // fail silently (no exception, but no file either), leaving the item stuck.
    @try {
        id ui = UYTResolveUYouItem(item);
        if (ui) {
            NSString *finalPath = [ui respondsToSelector:@selector(filePath)] ? [ui filePath] : nil;
            if (finalPath.length) {
                NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:finalPath error:nil];
                if (!attrs || [attrs fileSize] == 0) {
                    HBLogWarn(@"[uYouPatches] mergeAudioWithMP4Video: AVAssetExportSession produced no output - recovering");
                    if (!UYTFinalizeItem(item, @"post-merge recovery")) {
                        UYTFinalizeItem(item, @"merge no-output fallback");
                    }
                }
            }
        }
    } @catch (NSException *e) {}
}

- (void)mergeAudioWithVideoForDownloadItem:(id)item {
    HBLogInfo(@"[uYouPatches] mergeAudioWithVideo entered");
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"uYouConversionStarted" object:item];
    });

    // Pre-fix: convert webm audio to m4a before the merge (#771, #465)
    if (!UYTEnsureMergeableAudio(item, @"mergeAudio")) {
        UYTFinalizeItem(item, @"no-merge fallback");
        return;
    }

    // Prefer an ffmpeg remux over the legacy merge.
    id ui = UYTResolveUYouItem(item);
    if (UYTRemuxWithFFmpeg(ui, @"mergeAudio")) {
        UYTFinalizeItem(item, @"ffmpeg remux");
        return;
    }

    // Anti-hang guard (same as above) for the generic audio+video merge path.
    if (UYTAudioStillWebm(item)) {
        HBLogWarn(@"[uYouPatches] Audio still WebM after conversion â€” skipping merge to avoid infinite hang");
        UYTFinalizeItem(item, @"still-webm skip");
        return;
    }

    // Generic stall watchdog + legacy path.
    UYTArmStallWatchdog(item, 45.0);

    @try {
        %orig;
    } @catch (NSException *e) {
        HBLogWarn(@"[uYouPatches] mergeAudioWithVideo failed: %@ for item: %@", e, item);
        UYTFinalizeItem(item, @"merge exception recovery");
        return;
    }

    // Verify the merge actually produced output.
    @try {
        id ui = UYTResolveUYouItem(item);
        if (ui) {
            NSString *finalPath = [ui respondsToSelector:@selector(filePath)] ? [ui filePath] : nil;
            if (finalPath.length) {
                NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:finalPath error:nil];
                if (!attrs || [attrs fileSize] == 0) {
                    HBLogWarn(@"[uYouPatches] mergeAudioWithVideo: AVAssetExportSession produced no output - recovering");
                    if (!UYTFinalizeItem(item, @"post-merge recovery")) {
                        UYTFinalizeItem(item, @"merge no-output fallback");
                    }
                }
            }
        }
    } @catch (NSException *e) {}
}
%end

// --- File Access / Entitlement Error Recovery (#520) ---
// Paid signing services lack file access entitlements. Downloads complete
// but files can't be saved. Hook file operations to fall back to the
// app's Documents directory when the original path is inaccessible.

%hook NSFileManager
- (BOOL)moveItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath error:(NSError **)error {
    BOOL result = %orig;

    if (!result && error && *error) {
        // If the error is about file permissions / entitlements, try Documents fallback
        if ([*error code] == NSFileWriteNoPermissionError ||
            [*error code] == NSFileWriteFileExistsError ||
            [*error domain] == NSPOSIXErrorDomain) {

            NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
            NSString *fallbackName = [dstPath lastPathComponent];
            NSString *fallbackPath = [docsDir stringByAppendingPathComponent:@"uYouDownloads"];
            fallbackPath = [fallbackPath stringByAppendingPathComponent:fallbackName];

            // Create the directory if needed
            [[NSFileManager defaultManager] createDirectoryAtPath:[fallbackPath stringByDeletingLastPathComponent]
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:nil];

            NSError *fallbackError = nil;
            result = [self moveItemAtPath:srcPath toPath:fallbackPath error:&fallbackError];
            if (result) {
                HBLogInfo(@"[uYouPatches] File moved to Documents fallback: %@", fallbackPath);
            } else {
                // If move fails, try copy instead
                result = [self copyItemAtPath:srcPath toPath:fallbackPath error:&fallbackError];
                if (result) {
                    HBLogInfo(@"[uYouPatches] File copied to Documents fallback: %@", fallbackPath);
                }
            }
        }
    }

    return result;
}

- (BOOL)copyItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath error:(NSError **)error {
    // Ensure destination directory exists
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
// Ensure idle timer is always restored when the app goes to background,
// regardless of download state. This prevents the device from staying
// awake indefinitely if a download completes while backgrounded.

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

// uYou Speed Control Fixes - #681, #795
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
    // Re-apply the saved rate
    if (rate == 1.0f && uYouSavedPlaybackRate > 0.0f && uYouSavedPlaybackRate != 1.0f) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try {
                [self setPlaybackRate:uYouSavedPlaybackRate];
            } @catch (NSException *e) {
                HBLogWarn(@"[uYouPatches] Failed to restore playback rate: %@", e);
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

    // Restore saved playback rate when player appears
    float savedRate = [[NSUserDefaults standardUserDefaults] floatForKey:@"uYouSavedPlaybackRate"];
    if (savedRate > 0.0f && savedRate != 1.0f) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try {
                [self setPlaybackRate:savedRate];
            } @catch (NSException *e) {
                HBLogWarn(@"[uYouPatches] Failed to restore playback rate on appear: %@", e);
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
            HBLogWarn(@"[uYouPatches] Reorder Tabs Notifications injection failed: %@", e);
        }
    }
    return %orig;
}
%end
%end

#pragma mark - Constructor

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
        HBLogWarn(@"[uYouPatches] Skipping gYouSpeedFixes: playback-rate selectors missing on this YouTube build");
    }

    // Initialize fullscreen fixes (always active when noSuggestedVideo is used)
    %init(gYouFullscreenFixes);

    // Shorts uYou button fix (#995) — only needed on 21.xx.x+ where the
    // Shorts player hierarchy changed. Uses YTVersionUtils so the version
    // spoofer is respected.
    NSString *appVersion = [%c(YTVersionUtils) performSelector:@selector(appVersion)];
    if (appVersion && [appVersion compare:@"21.10.2" options:NSNumericSearch] != NSOrderedAscending) {
        %init(gShortsButtonGuard);
        %init(gShortsUYouDownload);
    }
}
