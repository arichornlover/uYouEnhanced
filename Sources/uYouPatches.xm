#import "uYouPlus.h"
#import "uYouPatches.h"

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
    // Background-session swap REMOVED: uYou uses AFHTTPSessionManager, which is
    // the delegate of its own session. Replacing the session with a plain
    // NSURLSession (delegate:nil) severed every AFNetworking callback —
    // downloads sat at "(null) | 0%" forever. The original foreground session
    // works; do not swap it out.
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
        // Use MobileFFmpeg (same as uYou's convertAsyncMkvToMp4) to convert webm to m4a
        NSArray *arguments = @[
            @"-i", webmPath,
            @"-vn",                // No video
            @"-acodec", @"aac",    // Encode to AAC for m4a compatibility
            @"-strict", @"-2",     // Allow experimental codecs
            @"-y",                 // Overwrite output
            m4aPath
        ];

        // IMPORTANT: MobileFFmpeg ships inside uYou.dylib's payload and is NOT
        // linked against this tweak. A bare [MobileFFmpeg ...] reference emits
        // _OBJC_CLASS_$_MobileFFmpeg and breaks linking; %c() resolves the
        // class at runtime from uYou's own copy instead.
        Class mobileFFmpegClass = %c(MobileFFmpeg);
        if (!mobileFFmpegClass) {
            HBLogWarn(@"[uYouPatches] MobileFFmpeg not found in app payload; skipping WebM→M4A conversion");
            return NO;
        }
        int returnCode = [mobileFFmpegClass executeWithArguments:arguments];

        if (returnCode == 0 && [fm fileExistsAtPath:m4aPath]) {
            unsigned long long fileSize = [[fm attributesOfItemAtPath:m4aPath error:nil] fileSize];
            if (fileSize > 0) {
                HBLogInfo(@"[uYouPatches] WebM→M4A conversion succeeded: %@ (%llu bytes)", m4aPath, fileSize);
                return YES;
            }
        }

        HBLogWarn(@"[uYouPatches] WebM→M4A conversion failed with return code: %d", returnCode);
    } @catch (NSException *e) {
        HBLogWarn(@"[uYouPatches] WebM→M4A conversion exception: %@", e);
    }

    return NO;
}

// Post-conversion check: is the item's audio still WebM? If yes, calling
// %orig would hang forever inside AVAssetExportSession (it never completes
// an mp4+webm merge and never throws), so callers must skip the merge.
static BOOL UYTAudioStillWebm(id item) {
    @try {
        uYouItem *uyouItem = [item valueForKey:@"uYouItem"];
        if (!uyouItem) return NO;
        NSString *audioPath = [uyouItem valueForKey:@"tmpAudioPath"] ?: [uyouItem valueForKey:@"cachedAudioPath"];
        return audioPath && [audioPath.pathExtension.lowercaseString isEqualToString:@"webm"];
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

        if (src) {
            if ([fm fileExistsAtPath:filePath]) [fm removeItemAtPath:filePath error:nil];
            NSError *err = nil;
            BOOL ok = [fm moveItemAtPath:src toPath:filePath error:&err];
            if (!ok) ok = [fm copyItemAtPath:src toPath:filePath error:&err];
            HBLogWarn(@"[uYouPatches] Completed without merge (%@): %@",
                      usedMuxed ? @"muxed pipeline file" : @"video-only stream", filePath);
        }
    } @catch (NSException *e) {
        HBLogWarn(@"[uYouPatches] no-merge fallback failed: %@", e);
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

            HBLogWarn(@"[uYouPatches] download stalled >%.0fs — forcing completion", seconds);

            NSMutableArray<NSString *> *candidates = [NSMutableArray array];
            NSString *vid = nil;
            if ([ui respondsToSelector:@selector(videoID)]) vid = [ui valueForKey:@"videoID"];
            if (vid.length) {
                NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
                [candidates addObject:[docs stringByAppendingPathComponent:[NSString stringWithFormat:@"uYouDownloads/%@.mp4", vid]]];
            }
            // Converted/downloaded audio (skip raw webm — unplayable natively)
            for (NSString *key in @[@"tmpAudioPath", @"cachedAudioPath"]) {
                NSString *p = [ui valueForKey:key];
                if (p.length && ![p.pathExtension.lowercaseString isEqualToString:@"webm"]) [candidates addObject:p];
            }
            NSString *cv = [ui cachedVideoPath];
            if (cv.length) [candidates addObject:cv];

            for (NSString *cand in candidates) {
                if (![fm fileExistsAtPath:cand]) continue;
                if ([fm fileExistsAtPath:filePath]) [fm removeItemAtPath:filePath error:nil];
                NSError *err = nil;
                BOOL ok = [fm moveItemAtPath:cand toPath:filePath error:&err];
                if (!ok) ok = [fm copyItemAtPath:cand toPath:filePath error:&err];
                if (ok) {
                    HBLogWarn(@"[uYouPatches] forced completion via %@", cand);
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
    %orig;
    // Start idle timer prevention when download setup begins
    uYouActiveDownloadCount++;
    if (!uYouDownloadIsActive) {
        uYouDownloadIsActive = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
        });
    }
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

%hook DownloadsManager
- (void)addMetadataToAudioForDownloadItem:(id)item {
    // Pre-fix: convert webm audio to m4a if needed (#771, #465)
    @try {
        uYouItem *uyouItem = [item valueForKey:@"uYouItem"];
        if (uyouItem) {
            NSString *audioPath = [uyouItem valueForKey:@"tmpAudioPath"];
            if (!audioPath) audioPath = [uyouItem valueForKey:@"cachedAudioPath"];
            if (audioPath && [[audioPath pathExtension] isEqualToString:@"webm"]) {
                NSString *m4aPath = [[audioPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"m4a"];
                if (uYouConvertWebmAudioToM4a(audioPath, m4aPath)) {
                    [uyouItem setValue:m4aPath forKey:@"tmpAudioPath"];
                }
            }
        }
    } @catch (NSException *e) {
        HBLogWarn(@"[uYouPatches] WebM pre-conversion in addMetadata failed: %@", e);
    }
    // Anti-hang guard (same as above) for the generic audio+video merge path.
    if (UYTAudioStillWebm(item)) {
        HBLogWarn(@"[uYouPatches] Audio still WebM after conversion — skipping merge to avoid infinite hang");
        UYTFallbackToVideoOnly(item);
        return;
    }

    // Stall watchdog for the metadata phase ("Adding Metadata to the M4A..."
    // stuck at 0% on audio-only downloads). If metadata writing stalls, the
    // watchdog completes the item from the converted m4a directly.
    UYTArmStallWatchdog(item, 30.0);
    @try {
        %orig;
    } @catch (NSException *e) {
        HBLogWarn(@"[uYouPatches] addMetadataToAudio failed: %@ for item: %@", e, item);

        // Metadata failed but the download itself is still valid.
        // The audio file can still be played without metadata tags.
        // Post a notification so the UI knows to update.
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
    // Pre-fix: convert webm audio to m4a before the merge (#771, #465)
    @try {
        uYouItem *uyouItem = [item valueForKey:@"uYouItem"];
        if (uyouItem) {
            NSString *audioPath = [uyouItem valueForKey:@"tmpAudioPath"];
            if (!audioPath) audioPath = [uyouItem valueForKey:@"cachedAudioPath"];
            if (audioPath && [[audioPath pathExtension] isEqualToString:@"webm"]) {
                NSString *m4aPath = [[audioPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"m4a"];
                if (uYouConvertWebmAudioToM4a(audioPath, m4aPath)) {
                    [uyouItem setValue:m4aPath forKey:@"tmpAudioPath"];
                    HBLogInfo(@"[uYouPatches] Converted webm audio to m4a for merge: %@", m4aPath);
                } else {
                    HBLogWarn(@"[uYouPatches] WebM→M4A conversion failed, merge may hang: %@", audioPath);
                }
            }
        }
    } @catch (NSException *e) {
        HBLogWarn(@"[uYouPatches] WebM pre-conversion in mergeMP4 failed: %@", e);
    }

    // Anti-hang (#452/#520/#830 family): if the audio is still WebM the merge
    // would sit at "Converting 0%" forever — finish video-only instead.
    if (UYTAudioStillWebm(item)) {
        HBLogWarn(@"[uYouPatches] Audio still WebM after conversion — skipping merge to avoid infinite hang");
        UYTFallbackToVideoOnly(item);
        return;
    }

    // Generic stall watchdog (covers non-webm hangs too).
    UYTArmStallWatchdog(item, 45.0);

    @try {
        %orig;
    } @catch (NSException *e) {
        HBLogWarn(@"[uYouPatches] mergeAudioWithMP4Video failed: %@ for item: %@", e, item);
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
            HBLogWarn(@"[uYouPatches] Fallback merge recovery also failed: %@", innerE);
        }
    }
}

- (void)mergeAudioWithVideoForDownloadItem:(id)item {
    // Pre-fix: convert webm audio to m4a before the merge (#771, #465)
    @try {
        uYouItem *uyouItem = [item valueForKey:@"uYouItem"];
        if (uyouItem) {
            NSString *audioPath = [uyouItem valueForKey:@"tmpAudioPath"];
            if (!audioPath) audioPath = [uyouItem valueForKey:@"cachedAudioPath"];
            if (audioPath && [[audioPath pathExtension] isEqualToString:@"webm"]) {
                NSString *m4aPath = [[audioPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"m4a"];
                if (uYouConvertWebmAudioToM4a(audioPath, m4aPath)) {
                    [uyouItem setValue:m4aPath forKey:@"tmpAudioPath"];
                    HBLogInfo(@"[uYouPatches] Converted webm audio to m4a for merge: %@", m4aPath);
                } else {
                    HBLogWarn(@"[uYouPatches] WebM→M4A conversion failed, merge may hang: %@", audioPath);
                }
            }
        }
    } @catch (NSException *e) {
        HBLogWarn(@"[uYouPatches] WebM pre-conversion in mergeAudio failed: %@", e);
    }

    // Anti-hang guard (same as above) for the generic audio+video merge path.
    if (UYTAudioStillWebm(item)) {
        HBLogWarn(@"[uYouPatches] Audio still WebM after conversion — skipping merge to avoid infinite hang");
        UYTFallbackToVideoOnly(item);
        return;
    }

    // Generic stall watchdog.
    UYTArmStallWatchdog(item, 45.0);

    @try {
        %orig;
    } @catch (NSException *e) {
        HBLogWarn(@"[uYouPatches] mergeAudioWithVideo failed: %@ for item: %@", e, item);
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
            HBLogWarn(@"[uYouPatches] Fallback merge recovery also failed: %@", innerE);
        }
    }
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
}
