#import "uYouPlus.h"
#import "uYouPatches.h"
#import "UYTMediaKit.h"
#import "DownloadPipeline.h"
#import <AVFoundation/AVFoundation.h>

// ---------------------------------------------------------------------------
// UYTLog compat
// ---------------------------------------------------------------------------
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
// Fixes below carry the issue number they address in the comment above them.

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

// uYou Download Fixes (#948, #70, #520, #241, #814, #813, #735)

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

// --- WebM Audio Format Fix (#771, #465, #814) ---
static BOOL uYouConvertWebmAudioToM4a(NSString *webmPath, NSString *m4aPath) {
    if (!webmPath || !m4aPath) return NO;

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:webmPath]) return NO;
    if ([webmPath isEqualToString:m4aPath]) return NO;

    if (!UYTFFConvertWebmAudioToM4a(webmPath, m4aPath)) {
        UYTPatchWarn(@"[uYouPatches] WebM to M4A conversion failed: %@", webmPath);
        return NO;
    }

    AVURLAsset *check = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:m4aPath] options:nil];
    AVAssetTrack *audioTrack = [[check tracksWithMediaType:AVMediaTypeAudio] firstObject];
    unsigned long long fileSize = [[fm attributesOfItemAtPath:m4aPath error:nil] fileSize];
    if (audioTrack && CMTimeCompare(check.duration, kCMTimeZero) > 0) {
        UYTPatchInfo(@"[uYouPatches] WebM->M4A conversion succeeded: %@ (%llu bytes, %.1fs)",
                     m4aPath, fileSize, CMTimeGetSeconds(check.duration));
        return YES;
    }
    UYTPatchWarn(@"[uYouPatches] WebM->M4A output exists but has no valid audio track/duration: %@", m4aPath);
    [fm removeItemAtPath:m4aPath error:nil];
    return NO;
}

// Point uYouItem's tmpAudioPath at the converted m4a via audioFormat (#1010:
// tmpAudioPath has no setter, so KVC on it throws NSUnknownKeyException).
static BOOL UYTPointItemAtConvertedAudio(id uyouItem, NSString *webmPath, NSString *m4aPath) {
    @try {
        [uyouItem setValue:@"m4a" forKey:@"audioFormat"];
        NSString *now = [uyouItem valueForKey:@"tmpAudioPath"];
        if (![now isEqualToString:m4aPath]) {
            UYTPatchWarn(@"[uYouPatches] tmpAudioPath is %@ after conversion, expected %@", now, m4aPath);
            return NO;
        }
        [[NSFileManager defaultManager] removeItemAtPath:webmPath error:nil];
        UYTPatchInfo(@"[uYouPatches] item now points at converted audio %@", m4aPath);
        return YES;
    } @catch (NSException *e) {
        UYTPatchWarn(@"[uYouPatches] could not point item at converted audio: %@", e);
        return NO;
    }
}

// Post-conversion check: is the item's audio still WebM? If yes, calling
// %orig would hang forever inside AVAssetExportSession (it never completes
// an mp4+webm merge and never throws), so callers must skip the merge.
// Content-sniffed via magic bytes (UYTFileLooksLikeWebm) rather than by
// extension alone, so a lying file name cannot walk into the hang.
static BOOL UYTAudioStillWebm(id item) {
    @try {
        uYouItem *uyouItem = [item valueForKey:@"uYouItem"];
        if (!uyouItem) return NO;
        NSString *audioPath = [uyouItem valueForKey:@"tmpAudioPath"] ?: [uyouItem valueForKey:@"cachedAudioPath"];
        if (!audioPath) return NO;
        return UYTFileLooksLikeWebm(audioPath);
    } @catch (NSException *e) {
        return NO;
    }
}

// Finish the download gracefully instead of hanging. Prefers our pipeline's
// muxed mp4 (video+audio) when available; otherwise falls back to uYou's
// cached video-only stream.
static void UYTFallbackToVideoOnly(id item) {
    @try {
        uYouItem *uyouItem = [item valueForKey:@"uYouItem"];
        if (!uyouItem) return;
        NSString *filePath = [uyouItem filePath];
        if (!filePath) return;

        NSString *src = nil;
        BOOL usedMuxed = NO;
        NSString *vid = nil;
        if ([uyouItem respondsToSelector:@selector(videoID)]) {
            vid = [uyouItem valueForKey:@"videoID"];
        }
        NSFileManager *fm = [NSFileManager defaultManager];

        // 1) Preferred: the muxed mp4 our modern pipeline downloaded (has audio).
        if (vid.length) {
            NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
            NSString *muxed = [docs stringByAppendingPathComponent:[NSString stringWithFormat:@"uYouDownloads/%@.mp4", vid]];
            if ([fm fileExistsAtPath:muxed]) {
                src = muxed;
                usedMuxed = YES;
            }
        }
        // 2) Otherwise: uYou's cached video-only stream (silent, but playable).
        NSString *cachedVideoPath = [uyouItem cachedVideoPath];
        if (!src && cachedVideoPath && [fm fileExistsAtPath:cachedVideoPath]) src = cachedVideoPath;
        // 3) The video-only leg file of THIS item (…_Video.mp4 already on disk).
        @try {
            NSString *itemPath = [item respondsToSelector:@selector(filePath)] ? [item filePath] : nil;
            if (!src && itemPath.length &&
                [itemPath.pathExtension.lowercaseString isEqualToString:@"mp4"] &&
                [itemPath rangeOfString:@"_Video"].location != NSNotFound &&
                [fm fileExistsAtPath:itemPath]) {
                src = itemPath;
            }
        } @catch (NSException *e) {}

        if (src) {
            if ([fm fileExistsAtPath:filePath]) [fm removeItemAtPath:filePath error:nil];
            NSError *err = nil;
            BOOL ok = [fm moveItemAtPath:src toPath:filePath error:&err];
            if (!ok) ok = [fm copyItemAtPath:src toPath:filePath error:&err];
            UYTPatchWarn(@"[uYouPatches] Completed without merge (%@): %@",
                         usedMuxed ? @"muxed pipeline file" : @"video-only stream", filePath);
        }
    } @catch (NSException *e) {
        UYTPatchWarn(@"[uYouPatches] no-merge fallback failed: %@", e);
    }
}

// AVAssetExportSession silent-hang family (#452/#241/#520/#830/#676).
static void UYTArmStallWatchdog(id item, NSTimeInterval seconds) {
    __weak id weakItem = item;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        id strongItem = weakItem;
        if (!strongItem) return;
        @try {
            uYouItem *ui = [strongItem valueForKey:@"uYouItem"];
            if (!ui) return;
            NSString *filePath = [ui filePath];
            if (!filePath.length) return;

            NSFileManager *fm = [NSFileManager defaultManager];

            BOOL finished = NO;
            if ([ui respondsToSelector:@selector(isDownloadFinished)]) {
                finished = [ui isDownloadFinished];
            }
            if (!finished) {
                NSDictionary *attrs = [fm attributesOfItemAtPath:filePath error:nil];
                finished = (attrs && [attrs fileSize] > 0);
            }
            if (finished) return; // completed normally

            UYTPatchWarn(@"[uYouPatches] download stalled >%.0fs - forcing completion", seconds);

            NSMutableArray<NSString *> *candidates = [NSMutableArray array];
            NSString *vid = nil;
            if ([ui respondsToSelector:@selector(videoID)]) vid = [ui valueForKey:@"videoID"];
            if (vid.length) {
                NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
                [candidates addObject:[docs stringByAppendingPathComponent:[NSString stringWithFormat:@"uYouDownloads/%@.mp4", vid]]];
            }
            // Converted/downloaded audio (skip raw webm - unplayable natively)
            for (NSString *key in @[@"tmpAudioPath", @"cachedAudioPath"]) {
                NSString *p = [ui valueForKey:key];
                if (p.length && ![p.pathExtension.lowercaseString isEqualToString:@"webm"]) [candidates addObject:p];
            }
            NSString *cv = [ui cachedVideoPath];
            if (cv.length) [candidates addObject:cv];
            // The video-only leg of THIS item (…_Video.mp4 already on disk).
            @try {
                NSString *itemPath = [strongItem respondsToSelector:@selector(filePath)] ? [strongItem filePath] : nil;
                if (itemPath.length &&
                    [itemPath.pathExtension.lowercaseString isEqualToString:@"mp4"] &&
                    [itemPath rangeOfString:@"_Video"].location != NSNotFound &&
                    [fm fileExistsAtPath:itemPath]) {
                    [candidates addObject:itemPath];
                }
            } @catch (NSException *e) {}

            for (NSString *cand in candidates) {
                if (![fm fileExistsAtPath:cand]) continue;
                if ([fm fileExistsAtPath:filePath]) [fm removeItemAtPath:filePath error:nil];
                NSError *err = nil;
                BOOL ok = [fm moveItemAtPath:cand toPath:filePath error:&err];
                if (!ok) ok = [fm copyItemAtPath:cand toPath:filePath error:&err];
                if (ok) {
                    UYTPatchWarn(@"[uYouPatches] forced completion via %@", cand);
                    // Mimic uYou's native completion: it posts download/conversion
                    // notifications so cells + lists refresh. Object = the item.
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[NSNotificationCenter defaultCenter]
                            postNotificationName:@"downloadDidCompleteNotification" object:strongItem];
                        [[NSNotificationCenter defaultCenter]
                            postNotificationName:@"conversionDidCompleteNotification" object:strongItem];
                    });
                    return;
                }
            }
        } @catch (NSException *e) {}
    });
}

%hook DownloadsManager
- (void)getLinksLocallyPlayerItem:(id)item videoID:(id)videoID sourceView:(id)sourceView isShorts:(BOOL)isShorts {
    // Prefetch working stream URLs (#1010): setRemoteURL: in DownloadPipeline.xm
    // swaps any broken URL for the resolved one. Best case fixes the HTTP 400
    // dead end; worst case uYou keeps its own URL.
    if (videoID) {
        @try {
            NSString *vid = [NSString stringWithFormat:@"%@", videoID];
            if (vid.length) UYTRefreshResolvedURLsForVideo(vid);
        } @catch (NSException *e) {
            UYTPatchWarn(@"[uYouPatches] resolved-URL refresh failed: %@", e);
        }
    }
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

// --- uYou's own converter ("Conversion failed with code %d") ---
// uYou.dylib's bundled old MobileFFmpeg can't decode webm/opus, so log calls
// so a report shows what the converter was handed before it fails with rc != 0.
%hook DownloadsManager
- (int)convertVideo:(id)video toAudio:(id)audio {
    @try {
        NSString *videoDesc = video ? [NSString stringWithFormat:@"%@ (%@)", NSStringFromClass([video class]), video] : @"(nil)";
        NSString *audioDesc = audio ? [NSString stringWithFormat:@"%@ (%@)", NSStringFromClass([audio class]), audio] : @"(nil)";
        UYTPatchInfo(@"[uYouPatches] convertVideo:toAudio: called video=%@ audio=%@", videoDesc, audioDesc);
    } @catch (NSException *e) {
        UYTPatchWarn(@"[uYouPatches] convertVideo:toAudio: arg description failed: %@", e);
    }
    int rc = %orig;
    @try {
        UYTPatchInfo(@"[uYouPatches] convertVideo:toAudio: rc=%d", rc);
    } @catch (NSException *e) {}
    return rc;
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
// AddMetadata can throw on corrupt/webm audio; convert to m4a first, point the
// item at it via audioFormat (#1010), skip the merge if still WebM, watchdog it.
%hook DownloadsManager
- (void)addMetadataToAudioForDownloadItem:(id)item {
    @try {
        id ui = [item valueForKey:@"uYouItem"];
        UYTDebugInfo(@"[uYouPatches] addMetadata entered file=%@ audio=%@",
                     [item valueForKey:@"filePath"],
                     ui ? [ui valueForKey:@"tmpAudioPath"] : nil);
    } @catch (NSException *e) {}
    // Pre-fix: convert webm audio to m4a if needed (#771, #465, #1010)
    @try {
        uYouItem *uyouItem = [item valueForKey:@"uYouItem"];
        if (uyouItem) {
            NSString *audioPath = [uyouItem valueForKey:@"tmpAudioPath"];
            if (!audioPath) audioPath = [uyouItem valueForKey:@"cachedAudioPath"];
            if (audioPath && [[audioPath pathExtension] isEqualToString:@"webm"]) {
                NSString *m4aPath = [[audioPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"m4a"];
                if (uYouConvertWebmAudioToM4a(audioPath, m4aPath)) {
                    UYTPointItemAtConvertedAudio(uyouItem, audioPath, m4aPath);
                }
            }
        }
    } @catch (NSException *e) {
        UYTPatchWarn(@"[uYouPatches] WebM pre-conversion in addMetadata failed: %@", e);
    }

    // Anti-hang guard: %orig would sit inside AVAssetExportSession forever
    // if the audio is still WebM - finish without metadata instead.
    if (UYTAudioStillWebm(item)) {
        UYTPatchWarn(@"[uYouPatches] Audio still WebM after conversion - skipping merge to avoid infinite hang");
        UYTFallbackToVideoOnly(item);
        return;
    }

    UYTArmStallWatchdog(item, 30.0);
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

// --- Audio/Video Merge with WebM Audio Fix (#1010, #241, #771, #465, #814) ---
// AVAssetExportSession can't merge mp4 + webm (hangs forever); convert to m4a,
// point the item at it via audioFormat, skip if still WebM, watchdog it.
%hook DownloadsManager
- (void)mergeAudioWithMP4VideoForDownloadItem:(id)item {
    @try {
        id ui = [item valueForKey:@"uYouItem"];
        UYTDebugInfo(@"[uYouPatches] mergeMP4 entered file=%@ audio=%@ video=%@",
                     [item valueForKey:@"filePath"],
                     ui ? [ui valueForKey:@"tmpAudioPath"] : nil,
                     ui ? [ui valueForKey:@"tmpVideoPath"] : nil);
    } @catch (NSException *e) {}
    // Pre-fix: convert webm audio to m4a before the merge (#771, #465, #1010)
    @try {
        uYouItem *uyouItem = [item valueForKey:@"uYouItem"];
        if (uyouItem) {
            NSString *audioPath = [uyouItem valueForKey:@"tmpAudioPath"];
            if (!audioPath) audioPath = [uyouItem valueForKey:@"cachedAudioPath"];
            if (audioPath && [[audioPath pathExtension] isEqualToString:@"webm"]) {
                NSString *m4aPath = [[audioPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"m4a"];
                if (uYouConvertWebmAudioToM4a(audioPath, m4aPath)) {
                    if (UYTPointItemAtConvertedAudio(uyouItem, audioPath, m4aPath)) {
                        UYTPatchInfo(@"[uYouPatches] Converted webm audio to m4a for merge: %@", m4aPath);
                    }
                } else {
                    UYTPatchWarn(@"[uYouPatches] WebM to M4A conversion failed, merge may hang: %@", audioPath);
                }
            }
        }
    } @catch (NSException *e) {
        UYTPatchWarn(@"[uYouPatches] WebM pre-conversion in mergeMP4 failed: %@", e);
    }

    // Anti-hang (#452/#520/#830 family): if the audio is still WebM the merge
    // would sit at "Converting 0%" forever - finish video-only instead.
    if (UYTAudioStillWebm(item)) {
        UYTPatchWarn(@"[uYouPatches] Audio still WebM after conversion - skipping merge to avoid infinite hang");
        UYTFallbackToVideoOnly(item);
        return;
    }

    // Generic stall watchdog (covers non-webm hangs too).
    UYTArmStallWatchdog(item, 45.0);

    @try {
        %orig;
    } @catch (NSException *e) {
        UYTPatchWarn(@"[uYouPatches] mergeAudioWithMP4Video failed: %@ for item: %@", e, item);
        // Fall back: use the video file as-is (without merged audio)
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
        id ui = [item valueForKey:@"uYouItem"];
        UYTDebugInfo(@"[uYouPatches] mergeAV entered file=%@ audio=%@ video=%@",
                     [item valueForKey:@"filePath"],
                     ui ? [ui valueForKey:@"tmpAudioPath"] : nil,
                     ui ? [ui valueForKey:@"tmpVideoPath"] : nil);
    } @catch (NSException *e) {}
    // Pre-fix: convert webm audio to m4a before the merge (#771, #465, #1010)
    @try {
        uYouItem *uyouItem = [item valueForKey:@"uYouItem"];
        if (uyouItem) {
            NSString *audioPath = [uyouItem valueForKey:@"tmpAudioPath"];
            if (!audioPath) audioPath = [uyouItem valueForKey:@"cachedAudioPath"];
            if (audioPath && [[audioPath pathExtension] isEqualToString:@"webm"]) {
                NSString *m4aPath = [[audioPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"m4a"];
                if (uYouConvertWebmAudioToM4a(audioPath, m4aPath)) {
                    if (UYTPointItemAtConvertedAudio(uyouItem, audioPath, m4aPath)) {
                        UYTPatchInfo(@"[uYouPatches] Converted webm audio to m4a for merge: %@", m4aPath);
                    }
                } else {
                    UYTPatchWarn(@"[uYouPatches] WebM to M4A conversion failed, merge may hang: %@", audioPath);
                }
            }
        }
    } @catch (NSException *e) {
        UYTPatchWarn(@"[uYouPatches] WebM pre-conversion in mergeAudio failed: %@", e);
    }

    // Anti-hang guard (same as above) for the generic audio+video merge path.
    if (UYTAudioStillWebm(item)) {
        UYTPatchWarn(@"[uYouPatches] Audio still WebM after conversion - skipping merge to avoid infinite hang");
        UYTFallbackToVideoOnly(item);
        return;
    }

    // Generic stall watchdog.
    UYTArmStallWatchdog(item, 45.0);

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

    // Rate 1.0 with a saved non-1.0 rate means the system reset it; re-apply.
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
%hook HAMPlayerInternal
- (void)setRate:(float)rate {
    if (rate == 1.0f && uYouSavedPlaybackRate > 0.0f && uYouSavedPlaybackRate != 1.0f) {
        // Only block the reset if the player is actively playing (not pausing/resuming)
        float currentRate = [self rate];
        if (currentRate > 0.0f && currentRate != 1.0f) {
            %orig(uYouSavedPlaybackRate);
            return;
        }
    }
    %orig(rate);
}
%end

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

    // Always on: downloads flow through these hooks regardless of the
    // kReplaceYTDownloadWithuYou toggle (that toggle only reroutes the button).
    UYTPatchInfo(@"[uYouPatches] arming gYouDownloadFixes (toggle=%d)", (int)IS_ENABLED(kReplaceYTDownloadWithuYou));
    %init(gYouDownloadFixes);

    // Speed fixes: only register when EVERY hooked selector exists on this
    // YouTube build, or respondsToSelector: lies and the next caller SIGABRTs.
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