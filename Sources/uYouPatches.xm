#import "UYTFileSize.h"
#import "uYouPlus.h"
#import "uYouPatches.h"
#import "UYTMediaKit.h"
#import "DownloadPipeline.h"
#import "UYTLog.h"
#import "UYTSABR.h"
#import <YouTubeHeader/YTUIUtils.h>
#import <objc/runtime.h>
#import <sqlite3.h>
#include <string.h>

# pragma mark - uYou Patches

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

%group gYouFixes

%hook UIViewController
- (UITraitCollection *)traitCollection {
    @try {
        return %orig;
    } @catch(NSException *e) {
        return [UITraitCollection currentTraitCollection];
    }
}
%end

%hook PlayerManager
- (void)pause {
    if (isnan([self progress]))
        return;
    %orig;
}
%end

%hook ArtworkImageView
- (id)imageView {
    UIImageView *imageView = %orig;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    UIView *artworkImageView = imageView.superview;
    if (artworkImageView != nil && !artworkImageView.translatesAutoresizingMaskIntoConstraints) {
        [artworkImageView.leftAnchor constraintEqualToAnchor:artworkImageView.superview.leftAnchor constant:16].active = YES;
        [artworkImageView.rightAnchor constraintEqualToAnchor:artworkImageView.superview.rightAnchor constant:-16].active = YES;
    }
    return imageView;
}
%end

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
                    if (i == selectedTabIndex) {}
                    else [tabLabel setTextColor:[UILabel _defaultColor]];
                    i++;
                }
            }
        }
    }
    } @catch (NSException *e) {
        UYTDebugWarn(@"[uYouPatches] refreshUYouAppearance failed: %@", e);
    }
}
%hook UIViewController
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{ refreshUYouAppearance(); });
}
%end

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

%hook SSBouncyButton
- (void)beginShrinkAnimation {}
- (void)beginEnlargeAnimation {}
%end

%hook GOODialogView
- (id)imageView {
    UIImageView *imageView = %orig;
    UILabel *dialogTitleLabel = nil;
    @try { dialogTitleLabel = [self valueForKey:@"titleLabel"]; } @catch (NSException *e) {}
    if ([dialogTitleLabel.text containsString:@"uYou\n"]) {
        NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"uYouBundle" ofType:@"bundle"];
        NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
        NSString *iconPath = [bundle pathForResource:@"icon_clipped" ofType:@"png"];
        UIImage *icon = [UIImage imageWithContentsOfFile:iconPath];
        [imageView setImage:icon];
        CGSize size = CGSizeMake(30, 30);
        UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
        [icon drawInRect:CGRectMake(0, 0, size.width, size.height)];
        UIImage *resizedImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        [imageView setImage:resizedImage];
    }
    return imageView;
}
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

%end

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
            UYTDebugWarn(@"[uYouPatches] varispeedController fallback failed: %@", e);
        }
    }
    return controller;
}
%end
%end

%group gYouDownloadFixes

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

static BOOL UYTFinalizeItem(id item, NSString *reason);

static NSMutableDictionary<NSString *, NSString *> *UYTURLVideoIDs;

static void UYTRegisterVideoIDForURL(NSString *vid, NSString *url) {
    if (!vid.length || !url.length) return;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UYTURLVideoIDs = [NSMutableDictionary dictionary];
    });
    @synchronized(UYTURLVideoIDs) {
        UYTURLVideoIDs[url] = vid;
    }
}

void UYTRegisterRemoteURLForVideoID(NSString *vid, NSString *url) {
    UYTRegisterVideoIDForURL(vid, url);
}

static NSString *UYTVideoIDForRequestURL(NSURL *url) {
    NSString *turl = url.absoluteString;
    if (!turl.length) return nil;
    @synchronized(UYTURLVideoIDs) {
        NSString *exact = UYTURLVideoIDs[turl];
        if (exact) return exact;
        for (NSString *reg in UYTURLVideoIDs) {
            if (!reg.length) continue;
            if ([turl hasPrefix:reg] || [reg hasPrefix:turl]) {
                return UYTURLVideoIDs[reg];
            }
        }
    }
    return nil;
}

static id UYTDownloadItemForVideoID(NSString *vid) {
    if (!vid.length) return nil;
    @try {
        Class managerClass = %c(DownloadsManager);
        id manager = [managerClass sharedInstance];
        if (!manager) return nil;
        for (NSString *key in @[@"downloadItemsArray", @"allDownloadItems", @"activeDownloadItems", @"downloads", @"downloadList"]) {
            id queue = nil;
            @try { queue = [manager valueForKey:key]; if (queue) break; } @catch (NSException *e) {}
            if ([queue isKindOfClass:[NSArray class]]) {
                for (id item in (NSArray *)queue) {
                    NSString *iv = nil;
                    @try { iv = [item respondsToSelector:@selector(videoID)] ? [item videoID] : [item valueForKey:@"videoID"]; } @catch (NSException *e) {}
                    if ([iv isKindOfClass:[NSString class]] && [iv isEqualToString:vid]) return item;
                }
            }
        }
    } @catch (NSException *e) {}
    return nil;
}

static void UYTSABRRecoverItemForVideo(NSString *vid, BOOL audioOnly) {
    if (!vid.length) return;
    BOOL active = NO;
    @try { active = UYTSABRIsDownloadActive(vid); } @catch (NSException *e) {}
    if (active) return;
    UYTDebugWarn(@"[uYouPatches] rerouting %@ to SABR capture (audioOnly=%d)", vid, audioOnly);
    UYTSABRFallbackDownloadForVideoID(vid, nil, audioOnly, ^(double frac, unsigned long long bytes) {
        @try { UYTDriveDownloadItemProgressForVideoID(vid, frac, bytes); } @catch (NSException *e) {}
    }, ^(BOOL ok, NSString *err) {
        id item = UYTDownloadItemForVideoID(vid);
        if (ok) {
            @try {
                NSString *resolved = UYTResolvedVideoURL(vid);
                if (!resolved.length) resolved = UYTResolvedURLForVideo(vid, YES);
                NSString *fp = resolved.length ? [NSURL URLWithString:resolved].path : nil;
                if (!fp.length && item) {
                    id ui = [item respondsToSelector:@selector(uYouItem)] ? [item uYouItem] : item;
                    if ([ui respondsToSelector:@selector(filePath)]) fp = [ui filePath];
                }
                if (fp.length) @try { UYTWriteFinalDownloadProgress(item, fp); } @catch (NSException *e) {}
            } @catch (NSException *e) {}
            if (item) UYTFinalizeItem(item, @"SABR 403/URL recovery");
        } else {
            UYTDebugWarn(@"[uYouPatches] SABR recovery failed for %@ (%@)", vid, err ?: @"?");
            if (item) UYTFinalizeItem(item, @"sabr-fail best-effort");
        }
    });
}

%hook AFURLSessionManager
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    UYTRecordTaskBytes(@(downloadTask.taskIdentifier), totalBytesWritten, totalBytesExpectedToWrite);
    %orig;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error && UYTTaskWroteEverything(task)) {
        UYTDebugWarn(@"[uYouPatches] transfer hit 100%% but errored (%@ code %ld) - completing as success",
                  error.domain ?: @"?", (long)error.code);
        [UYTTaskByteCounts removeObjectForKey:@(task.taskIdentifier)];
        %orig(session, task, nil);
        return;
    }
    @try {
        if (error) {
            NSString *vid = UYTVideoIDForRequestURL(task.currentRequest.URL ?: task.originalRequest.URL);
            long code = (long)error.code;
            if (vid.length && (code == -1011 || code == -1100 || code == -1002 || code == -1004) && UYTSABRHasValidCaptureForVideoID(vid)) {
                UYTDebugWarn(@"[uYouPatches] task %ld errored (%ld) for %@ - SABR reroute", (long)task.taskIdentifier, code, vid);
                UYTSABRRecoverItemForVideo(vid, UYTIsAudioOnly(vid));
                [UYTTaskByteCounts removeObjectForKey:@(task.taskIdentifier)];
                return;
            }
        }
    } @catch (NSException *e) {
        UYTDebugWarn(@"[uYouPatches] SABR reroute check failed: %@", e);
    }
    if (!error && task) [UYTTaskByteCounts removeObjectForKey:@(task.taskIdentifier)];
    %orig;
}
%end

static BOOL uYouDownloadIsActive = NO;
static NSInteger uYouActiveDownloadCount = 0;

static BOOL uYouConvertWebmAudioToM4a(NSString *webmPath, NSString *m4aPath) {
    if (!webmPath || !m4aPath) return NO;

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:webmPath]) return NO;

    if ([fm fileExistsAtPath:m4aPath]) {
        [fm removeItemAtPath:m4aPath error:nil];
    }

    @try {
        if (UYTFFActiveBackend() == UYTFFBackendNone) {
            UYTDebugWarn(@"[uYouPatches] no ffmpeg backend available; skipping conversion");
            return NO;
        }
        BOOL ok = UYTFFConvertWebmAudioToM4a(webmPath, m4aPath);

        if (ok && [fm fileExistsAtPath:m4aPath]) {
            unsigned long long fileSize = UYTSizeOfFile(m4aPath);
            if (fileSize > 0) {
                UYTDebugInfo(@"[uYouPatches] WebM->M4A conversion succeeded: %@ (%llu bytes)", m4aPath, fileSize);
                return YES;
            }
        }

        UYTDebugWarn(@"[uYouPatches] WebM→M4A conversion failed (backend %ld)", (long)UYTFFActiveBackend());
    } @catch (NSException *e) {
        UYTDebugWarn(@"[uYouPatches] WebM->M4A conversion exception: %@", e);
    }

    return NO;
}

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
    return UYTFileLooksLikeWebm(path);
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

static BOOL UYTAudioStillWebm(id item) {
    @try {
        return UYTPathIsWebm(UYTAudioPathForItem(UYTResolveUYouItem(item)));
    } @catch (NSException *e) {
        return NO;
    }
}

static BOOL UYTItemIsAudioOnly(id item) {
    @try {
        id ui = UYTResolveUYouItem(item);
        if (!ui) return NO;
        NSString *vid = [ui respondsToSelector:@selector(videoID)] ? [ui videoID] : nil;
        if (vid.length && UYTIsAudioOnly(vid)) return YES;
        NSString *videoPath = nil;
        if ([ui respondsToSelector:@selector(tmpVideoPath)]) videoPath = [ui tmpVideoPath];
        if (!videoPath.length && [ui respondsToSelector:@selector(cachedVideoPath)]) videoPath = [ui cachedVideoPath];
        NSString *audioPath = UYTAudioPathForItem(ui);
        NSFileManager *fm = [NSFileManager defaultManager];
        BOOL hasVideo = videoPath.length && [fm fileExistsAtPath:videoPath];
        BOOL hasAudio = audioPath.length && [fm fileExistsAtPath:audioPath];
        return hasAudio && !hasVideo;
    } @catch (NSException *e) {
        return NO;
    }
}

static BOOL UYTPointItemAtConvertedMedia(id uyouItem, NSString *formatKey, NSString *formatValue,
                                         NSString *pathKey, NSString *sourcePath,
                                         NSString *convertedPath, NSString *label) {
    @try {
        if (!uyouItem) return NO;
        if (!convertedPath.length || ![[NSFileManager defaultManager] fileExistsAtPath:convertedPath]) {
            UYTDebugWarn(@"[uYouPatches] %@: converted file missing at %@ - keeping source", label,
                         convertedPath.length ? convertedPath : @"nil");
            return NO;
        }
        [uyouItem setValue:formatValue forKey:formatKey];
        NSString *now = [uyouItem valueForKey:pathKey];
        if (![now isEqualToString:convertedPath]) {
            UYTDebugWarn(@"[uYouPatches] %@: %@ is %@ after naming %@, expected %@ - merge would hang",
                         label, pathKey, now ?: @"nil", formatValue, convertedPath);
            return NO;
        }
        if (sourcePath.length && ![sourcePath isEqualToString:convertedPath]) {
            [[NSFileManager defaultManager] removeItemAtPath:sourcePath error:nil];
        }
        UYTDebugInfo(@"[uYouPatches] %@: item now points at %@ (%@)", label, convertedPath, formatValue);
        return YES;
    } @catch (NSException *e) {
        UYTDebugWarn(@"[uYouPatches] %@: could not point item at converted media: %@", label, e);
        return NO;
    }
}

static BOOL UYTPointItemAtConvertedAudio(id uyouItem, NSString *webmPath, NSString *m4aPath) {
    return UYTPointItemAtConvertedMedia(uyouItem, @"audioFormat", @"m4a", @"tmpAudioPath",
                                        webmPath, m4aPath, @"audio");
}

static BOOL UYTEnsureMergeableAudio(id item, NSString *phase) {    @try {
        id ui = UYTResolveUYouItem(item);
        NSString *audioPath = UYTAudioPathForItem(ui);
        if (!audioPath.length) return YES;
        UYTDebugInfo(@"[uYouPatches] %@: audio=%@ (.%@)", phase, audioPath.lastPathComponent, audioPath.pathExtension);
        if (!UYTPathIsWebm(audioPath)) return YES;

        NSString *m4aPath = [[audioPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"m4a"];
        if (uYouConvertWebmAudioToM4a(audioPath, m4aPath)) {
            if (!UYTPointItemAtConvertedAudio(ui, audioPath, m4aPath)) {
                UYTDebugWarn(@"[uYouPatches] %@: conversion done but could not point item at m4a — merge may hang", phase);
                return NO;
            }
            UYTDebugInfo(@"[uYouPatches] %@: webm→m4a conversion done", phase);
            return YES;
        }
        UYTDebugWarn(@"[uYouPatches] %@: webm→m4a conversion FAILED — merge would hang", phase);
        return NO;
    } @catch (NSException *e) {
        UYTDebugWarn(@"[uYouPatches] %@: pre-conversion exception: %@", phase, e);
        return NO;
    }
}

static BOOL uYouConvertWebmVideoToMp4(NSString *webmPath, NSString *mp4Path) {
    @try {
        if (UYTFFActiveBackend() == UYTFFBackendNone) return NO;
        return UYTFFConvertWebmVideoToMp4(webmPath, mp4Path);
    } @catch (NSException *e) {
        return NO;
    }
}

static BOOL UYTEnsureMergeableVideo(id item, NSString *phase) {
    @try {
        id ui = UYTResolveUYouItem(item);
        if (!ui) return NO;
        NSString *videoPath = nil;
        if ([ui respondsToSelector:@selector(tmpVideoPath)]) videoPath = [ui tmpVideoPath];
        if (!videoPath.length && [ui respondsToSelector:@selector(cachedVideoPath)]) videoPath = [ui cachedVideoPath];
        if (!videoPath.length) return YES;
        UYTDebugInfo(@"[uYouPatches] %@: video=%@ (.%@)", phase, videoPath.lastPathComponent, videoPath.pathExtension);
        if (!UYTPathIsWebm(videoPath)) return YES;

        NSString *mp4Path = [[videoPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"mp4"];
        if (uYouConvertWebmVideoToMp4(videoPath, mp4Path)) {
            if (!UYTPointItemAtConvertedMedia(ui, @"videoFormat", @"mp4", @"tmpVideoPath",
                                              videoPath, mp4Path, [NSString stringWithFormat:@"%@ video", phase])) {
                UYTDebugWarn(@"[uYouPatches] %@: conversion done but could not point item at mp4 - merge may hang", phase);
                return NO;
            }
            UYTDebugInfo(@"[uYouPatches] %@: webm→mp4 video conversion done", phase);
            return YES;
        }
        UYTDebugWarn(@"[uYouPatches] %@: webm→mp4 video conversion FAILED", phase);
        return NO;
    } @catch (NSException *e) {
        UYTDebugWarn(@"[uYouPatches] %@: pre-video-conversion exception: %@", phase, e);
        return NO;
    }
}

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

        UYTDebugInfo(@"[uYouPatches] %@: remux started (%@ + %@)", phase,
                  videoPath.lastPathComponent, audioPath.lastPathComponent);

        BOOL ok = UYTFFSmartRemuxToMP4(videoPath, audioPath, tmpOut);

        NSDictionary *attrs = [fm attributesOfItemAtPath:tmpOut error:nil];
        if (ok && UYTSizeOfAttrs(attrs) > 0) {
            if ([fm fileExistsAtPath:finalPath]) [fm removeItemAtPath:finalPath error:nil];
            NSError *moveErr = nil;
            if ([fm moveItemAtPath:tmpOut toPath:finalPath error:&moveErr]) {
                UYTDebugWarn(@"[uYouPatches] %@: remux OK -> %@", phase, finalPath.lastPathComponent);
                return YES;
            }
            UYTDebugWarn(@"[uYouPatches] %@: remux move failed: %@", phase, moveErr);
        } else {
            UYTDebugWarn(@"[uYouPatches] %@: remux failed (backend %ld)", phase, (long)UYTFFActiveBackend());
            [fm removeItemAtPath:tmpOut error:nil];
        }
    } @catch (NSException *e) {
        UYTDebugWarn(@"[uYouPatches] %@: remux exception: %@", phase, e);
    }
    return NO;
}

static NSDictionary *UYTBestAvailableSource(id ui) {
    if (!ui) return nil;
    NSFileManager *fm = [NSFileManager defaultManager];

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
        if (!attrs) return;
        unsigned long long sz = UYTSizeOfAttrs(attrs);
        if (sz == 0) return;
        if (!UYTPathIsWebm(path) && sz > bestNonWebmSize) {
            bestNonWebmSize = sz;
            bestNonWebm = @{@"path": path, @"label": label};
        }
        if (sz > bestAnySize) {
            bestAnySize = sz;
            bestAny = @{@"path": path, @"label": label};
        }
    };

    NSString *vid = [ui respondsToSelector:@selector(videoID)] ? [ui videoID] : nil;
    if (vid.length) {
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
        checkPath([docs stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"Downloaded/%@.mp4", vid]],
                  @"muxed pipeline file");
        checkPath([docs stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"Downloaded/%@.m4a", vid]],
                  @"sabr audio pipeline file");
    }

    checkPath(resolvePath(ui, @selector(tmpVideoPath)), @"tmp video stream");
    checkPath(resolvePath(ui, @selector(cachedVideoPath)), @"cached video stream");
    checkPath(resolvePath(ui, @selector(tmpAudioPath)), @"tmp audio stream");
    checkPath(resolvePath(ui, @selector(cachedAudioPath)), @"cached audio stream");

    return bestNonWebm ?: bestAny;
}

static BOOL UYTForceCompleteItem(id ui, NSString *reason) {
    @try {
        if (![ui respondsToSelector:@selector(filePath)]) return NO;
        NSString *filePath = [ui filePath];
        if (!filePath.length) return NO;

        NSFileManager *fm = [NSFileManager defaultManager];

        NSDictionary *finalAttrs = [fm attributesOfItemAtPath:filePath error:nil];
        unsigned long long finalSize = UYTSizeOfAttrs(finalAttrs);
        if (finalSize > 0) {
            UYTDebugWarn(@"[uYouPatches] force-complete (%@): final file already exists (%llu bytes) - keeping",
                      reason, finalSize);
            return YES;
        }

        NSDictionary *best = UYTBestAvailableSource(ui);
        if (!best) {
            UYTDebugWarn(@"[uYouPatches] force-complete (%@): no usable source file yet", reason);
            return NO;
        }

        if ([fm fileExistsAtPath:filePath]) [fm removeItemAtPath:filePath error:nil];
        NSError *err = nil;
        BOOL ok = [fm moveItemAtPath:best[@"path"] toPath:filePath error:&err];
        if (!ok) ok = [fm copyItemAtPath:best[@"path"] toPath:filePath error:&err];
        if (!ok) {
            UYTDebugWarn(@"[uYouPatches] force-complete (%@): move failed: %@", reason, err);
            return NO;
        }
        UYTDebugWarn(@"[uYouPatches] force-complete (%@): promoted %@ -> %@", reason, best[@"label"], filePath);
        return YES;
    } @catch (NSException *e) {
        UYTDebugWarn(@"[uYouPatches] force-complete (%@) exception: %@", reason, e);
        return NO;
    }
}

static void UYTPostCompletionNotifications(id item) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"downloadDidCompleteNotification" object:item];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"conversionDidCompleteNotification" object:item];
    });
}

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
            UYTDebugWarn(@"[uYouPatches] finalize: cannot open uyoudb.sqlite");
            return;
        }

        sqlite3_exec(db,
            "CREATE TABLE IF NOT EXISTS downloads ("
            "id TEXT PRIMARY KEY, videoID TEXT, title TEXT, channel TEXT, channelURL TEXT, "
            "qualityLabel TEXT, typeAndQuality TEXT, size TEXT, duration TEXT, "
            "type TEXT, path TEXT, lyrics TEXT, timestamp DATETIME)",
            NULL, NULL, NULL);

        unsigned long long fileSize = UYTSizeOfFile(filePath);
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
                UYTDebugWarn(@"[uYouPatches] finalize: DB insert failed: %s", sqlite3_errmsg(db));
            } else {
                UYTDebugInfo(@"[uYouPatches] finalize: DB row written for %@", vid);
            }
            sqlite3_finalize(stmt);
        }
        sqlite3_close(db);
    } @catch (NSException *e) {
        UYTDebugWarn(@"[uYouPatches] finalize: DB insert exception: %@", e);
    }
}

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
        if (doomed.count) UYTDebugInfo(@"[uYouPatches] finalize: purged %lu downloading queue row(s)", (unsigned long)doomed.count);
        sqlite3_close(db);
    } @catch (NSException *e) {}
}

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
        UYTDebugWarn(@"[uYouPatches] finalize (%@): item fully completed", reason);
        return YES;
    } @catch (NSException *e) {
        UYTDebugWarn(@"[uYouPatches] finalize (%@) exception: %@", reason, e);
        return NO;
    }
}

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
    if (finished || UYTSizeOfAttrs(attrs) > 0) return;

        UYTDebugErr(@"[uYouPatches] stall watchdog: download stalled (polls left %ld, vid: %@)",
                    (long)pollsLeft, [ui respondsToSelector:@selector(videoID)] ? [ui videoID] : @"?");

        NSDictionary *best = UYTBestAvailableSource(ui);
        if (!best) {
            UYTScheduleStallCheck(item, 5.0, pollsLeft - 1, lastSizes);
            return;
        }

        NSString *bestPath = best[@"path"];
        unsigned long long bestSize = UYTSizeOfFile(bestPath);
        NSNumber *prevSize = lastSizes[bestPath];
        lastSizes[bestPath] = @(bestSize);
        BOOL stillGrowing = prevSize && bestSize > prevSize.unsignedLongLongValue;
        if (stillGrowing && pollsLeft > 1) {
            UYTDebugInfo(@"[uYouPatches] stall recovery deferred - %@ is still growing (%llu bytes)",
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

static NSString *UYTNonEmptyID(id value) {
    if (![value isKindOfClass:[NSString class]]) return nil;
    NSString *s = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!s.length) return nil;
    if ([s hasPrefix:@"("] && [s hasSuffix:@")"]) return nil;
    return s;
}

static NSString *UYTResolveVideoID(id param, id item) {
    NSString *vid = UYTNonEmptyID(param);
    if (vid) return vid;
    for (NSString *key in @[@"videoID", @"videoId", @"video_id", @"identifier"]) {
        @try {
            if (![item respondsToSelector:NSSelectorFromString(key)]) continue;
            NSString *found = UYTNonEmptyID([item valueForKey:key]);
            if (found) {
                UYTDebugWarn(@"[uYouPatches] videoID arg was empty; recovered %@ from item.%@", found, key);
                return found;
            }
        } @catch (NSException *e) {}
    }
    return nil;
}

%hook DownloadsManager
- (void)getLinksLocallyPlayerItem:(id)item videoID:(id)videoID sourceView:(id)sourceView isShorts:(BOOL)isShorts {
    NSString *vid = UYTResolveVideoID(videoID, item);
    if (!vid.length) {
        UYTDebugErr(@"[uYouPatches] download requested with no resolvable videoID (arg=%@, item=%@) - skipping pipeline, handing off to uYou",
                    UYTNonEmptyID(videoID) ?: @"empty", NSStringFromClass([item class]));
        %orig;
        return;
    }
    UYTDebugInfo(@"[uYouPatches] download requested (vid: %@, shorts: %@)", vid, isShorts ? @"YES" : @"NO");

    NSString *requestedQuality = [[NSUserDefaults standardUserDefaults] stringForKey:@"UYTRequestedQuality"];
    BOOL requestedAudioOnly = [[NSUserDefaults standardUserDefaults] boolForKey:@"UYTRequestedAudioOnly"];

    [UYTDownloadPipeline fetchFormatsForVideoID:vid isShorts:isShorts progress:^(double frac, unsigned long long bytes) {
        @try {
            UYTDriveDownloadItemProgressForVideoID(vid, frac, bytes);
        } @catch (NSException *e) {}
    } completion:^(NSArray<UYTStreamFormat *> *formats, NSError *error) {
        if (!formats.count) {
            UYTDebugErr(@"getLinks: no formats for %@ (%@)", vid, error.localizedDescription ?: @"none");
        } else {
            UYTDebugInfo(@"getLinks: %lu formats for %@ (audioOnly=%d, quality=%@)",
                         (unsigned long)formats.count, vid, requestedAudioOnly,
                         requestedQuality.length ? requestedQuality : @"default");
        }
        UYTStreamFormat *muxed = [UYTDownloadPipeline bestMuxedFormat:formats];
        UYTStreamFormat *audio = [UYTDownloadPipeline bestAudioFormat:formats];
        UYTStreamFormat *video = [UYTDownloadPipeline bestVideoFormat:formats];

        if (requestedQuality.length) {
            UYTStreamFormat *picked = [UYTDownloadPipeline bestVideoFormat:formats
                                                              qualityLabel:requestedQuality];
            if (picked) video = picked;
        }

        if (requestedAudioOnly) {
            video = nil;
            muxed = nil;
        }

        UYTStoreResolvedURLs(vid, muxed.url, audio.url, video.url);
        UYTMarkAudioOnly(vid, requestedAudioOnly);
        UYTDebugInfo(@"[UYTPipeline] cached URLs for %@ (muxed=%@, audio=%@, video=%@, audioOnly=%d)",
              vid,
              muxed.mimeType.length ? muxed.mimeType : @"none",
              audio.mimeType.length ? audio.mimeType : @"none",
              video.mimeType.length ? video.mimeType : @"none",
              requestedAudioOnly);

        UYTRegisterVideoIDForURL(vid, video.url);
        UYTRegisterVideoIDForURL(vid, audio.url);
        UYTRegisterVideoIDForURL(vid, muxed.url);
        @try {
            NSString *original = [item respondsToSelector:@selector(remoteURL)] ?
                [item remoteURL] : [item valueForKey:@"remoteURL"];
            if ([original isKindOfClass:[NSString class]]) UYTRegisterVideoIDForURL(vid, original);
        } @catch (NSException *e) {}

        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"UYTRequestedQuality"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"UYTRequestedAudioOnly"];

        dispatch_async(dispatch_get_main_queue(), ^{
            %orig;
            UYTArmStallWatchdog(item, 300.0);
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

%hook DownloadItem
- (void)createDownloadTask {
    @try {
        NSString *vid = UYTNonEmptyID(self.videoID);

        if (vid.length) {
            NSString *resolved = UYTResolvedVideoURL(vid);
            if (!resolved.length) resolved = UYTResolvedURLForVideo(vid, YES);
            if (resolved.length && [resolved hasPrefix:@"file://"]) {
                id ui = UYTResolveUYouItem(self);
                if (ui) {
                    UYTDebugInfo(@"createDownloadTask: file:// ready for %@ — finalizing w/o network task", vid);
                    NSString *filePath = [NSURL URLWithString:resolved].path;
                    if (!filePath.length) filePath = ui ? (([ui respondsToSelector:@selector(filePath)]) ? [ui filePath] : nil) : nil;
                    @try { UYTWriteFinalDownloadProgress(self, filePath); } @catch (NSException *e) {}
                    if (UYTFinalizeItem(self, @"SABR on-device")) return;
                }
            }
        }

        if (vid.length && UYTSABRIsDownloadActive(vid)) {
            UYTDebugWarn(@"[uYouPatches] skipping uYou's createDownloadTask for %@ - SABR is driving this download", vid);
            return;
        }
    } @catch (NSException *e) {
        UYTDebugWarn(@"[uYouPatches] createDownloadTask SABR shortcut failed: %@", e);
    }
    %orig;
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    @try {
        if (error) {
            NSString *vid = self.videoID ?: @"";
            long code = (long)error.code;
            if (vid.length && (code == -1011 || code == -1100 || code == -1002 || code == -1004)) {
                if (UYTSABRHasValidCaptureForVideoID(vid)) {
                    UYTDebugWarn(@"[uYouPatches] task error (%ld) for %@ - rerouting to SABR capture", code, vid);
                    UYTSABRRecoverItemForVideo(vid, UYTIsAudioOnly(vid));
                    return;
                }
                static char retryKey;
                if (![objc_getAssociatedObject(self, &retryKey) boolValue]) {
                    objc_setAssociatedObject(self, &retryKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    UYTDebugWarn(@"[uYouPatches] task error (%ld) for %@ - refetching fresh URLs", code, vid);
                    __block NSArray<UYTStreamFormat *> *freshFormats = nil;
                    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
                    [UYTDownloadPipeline fetchFormatsForVideoID:vid isShorts:NO progress:nil completion:^(NSArray<UYTStreamFormat *> *formats, NSError *fetchErr) {
                        freshFormats = formats;
                        dispatch_semaphore_signal(sem);
                    }];
                    long waited = dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)));
                    if (waited == 0 && freshFormats.count) {
                        UYTStreamFormat *muxed = [UYTDownloadPipeline bestMuxedFormat:freshFormats];
                        UYTStreamFormat *audio = [UYTDownloadPipeline bestAudioFormat:freshFormats];
                        UYTStreamFormat *video = [UYTDownloadPipeline bestVideoFormat:freshFormats];
                        UYTStoreResolvedURLs(vid, muxed.url, audio.url, video.url);
                        UYTRegisterVideoIDForURL(vid, video.url);
                        UYTRegisterVideoIDForURL(vid, audio.url);
                        UYTRegisterVideoIDForURL(vid, muxed.url);
                        NSString *fresh = UYTResolvedVideoURL(vid);
                        if (fresh.length) {
                            UYTDebugWarn(@"[uYouPatches] restarting %@ on a fresh URL after (%ld)", vid, code);
                            UYTDebugErr(@"restarting %@ on fresh URL after %ld — new task armed", vid, code);
                            [self setRemoteURL:[NSURL URLWithString:fresh]];
                            [self createDownloadTask];
                            return;
                        }
                    } else {
                        UYTDebugWarn(@"[uYouPatches] no fresh URLs for %@ after (%ld) — reporting to uYou", vid, code);
                        UYTDebugErr(@"no fresh URLs for %@ after %ld — giving up, will show -1011", vid, code);
                    }
                }
            }
        }
    } @catch (NSException *e) {
        UYTDebugWarn(@"[uYouPatches] URLSession didComplete reroute failed: %@", e);
    }
    %orig;
}
%end

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

%hook DownloadsManager
- (void)addMetadataToAudioForDownloadItem:(id)item {
    UYTDebugInfo(@"[uYouPatches] addMetadata entered");
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"uYouConversionStarted" object:item];
    });

    BOOL needsAudioExtraction = NO;
    @try {
        needsAudioExtraction = [[item valueForKey:@"uYouNeedsAudioExtraction"] boolValue];
    } @catch (NSException *e) {}

    id ui = UYTResolveUYouItem(item);
    if (!needsAudioExtraction && ui) {
        NSString *extractionVid = [ui respondsToSelector:@selector(videoID)] ? [ui videoID] : nil;
        if (extractionVid.length && UYTIsAudioOnly(extractionVid)) {
            needsAudioExtraction = YES;
            UYTDebugInfo(@"[uYouPatches] audio-only request for %@ - checking muxed source for extraction", extractionVid);
        }
    }

    if (needsAudioExtraction) {
        UYTDebugInfo(@"[uYouPatches] Audio-only download needs extraction from muxed video");
        if (ui) {
            NSString *videoPath = nil;
            if ([ui respondsToSelector:@selector(tmpVideoPath)]) videoPath = [ui tmpVideoPath];
            if (!videoPath.length && [ui respondsToSelector:@selector(cachedVideoPath)]) videoPath = [ui cachedVideoPath];
            NSString *finalPath = [ui respondsToSelector:@selector(filePath)] ? [ui filePath] : nil;

            if (videoPath.length && finalPath.length) {
                NSString *tmpAudio = [finalPath stringByAppendingString:@".extracted.m4a"];
                [[NSFileManager defaultManager] removeItemAtPath:tmpAudio error:nil];

                if (UYTFFActiveBackend() != UYTFFBackendNone) {
                    BOOL ok = UYTFFConvertWebmAudioToM4a(videoPath, tmpAudio);
                    if (ok && [[NSFileManager defaultManager] fileExistsAtPath:tmpAudio]) {
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:tmpAudio error:nil];
        if (UYTSizeOfAttrs(attrs) > 0) {
                            [[NSFileManager defaultManager] removeItemAtPath:finalPath error:nil];
                            [[NSFileManager defaultManager] moveItemAtPath:tmpAudio toPath:finalPath error:nil];
                            UYTDebugInfo(@"[uYouPatches] Extracted audio from muxed video for %@", finalPath);
                            if (UYTFinalizeItem(item, @"audio extracted from muxed")) return;
                            UYTArmStallWatchdog(item, 30.0);
                            return;
                        }
                    }
                    UYTDebugWarn(@"[uYouPatches] audio extraction from muxed video failed for %@", videoPath.lastPathComponent);
                    [[NSFileManager defaultManager] removeItemAtPath:tmpAudio error:nil];
                }
            }
        }
    }

    if (!UYTEnsureMergeableAudio(item, @"addMetadata")) {
        if (UYTFinalizeItem(item, @"no-merge fallback")) return;
        UYTArmStallWatchdog(item, 45.0);
        return;
    }

    if (UYTAudioStillWebm(item)) {
        UYTDebugWarn(@"[uYouPatches] Audio still WebM after conversion - skipping merge to avoid infinite hang");
        if (UYTFinalizeItem(item, @"still-webm skip")) return;
        UYTArmStallWatchdog(item, 45.0);
        return;
    }

    UYTArmStallWatchdog(item, 30.0);
    @try {
        %orig;
    } @catch (NSException *e) {
        UYTDebugWarn(@"[uYouPatches] addMetadataToAudio failed: %@ for item: %@", e, item);
        if (!UYTFinalizeItem(item, @"metadata exception recovery")) {
            UYTArmStallWatchdog(item, 45.0);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"uYouDownloadMetadataFailed" object:nil];
        });
    }
}
%end

%hook DownloadsManager
- (void)mergeAudioWithMP4VideoForDownloadItem:(id)item {
    UYTDebugInfo(@"[uYouPatches] mergeAudioWithMP4Video entered");
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"uYouConversionStarted" object:item];
    });
    UYTDebugInfo(@"merge hook: mergeAudioWithMP4Video entered");

    if (UYTItemIsAudioOnly(item)) {
        UYTDebugInfo(@"[uYouPatches] audio-only item — finalizing without merge");
        if (UYTFinalizeItem(item, @"audio-only no-merge")) return;
        UYTArmStallWatchdog(item, 45.0);
        return;
    }

    if (!UYTEnsureMergeableAudio(item, @"mergeMP4")) {
        if (UYTFinalizeItem(item, @"no-merge fallback")) return;
        UYTArmStallWatchdog(item, 45.0);
        return;
    }

    if (!UYTEnsureMergeableVideo(item, @"mergeMP4")) {
        UYTDebugWarn(@"[uYouPatches] mergeAudioWithMP4Video: video not pre-mergeable — continuing (best-effort below)");
    }

    id ui = UYTResolveUYouItem(item);
    if (UYTRemuxWithFFmpeg(ui, @"mergeMP4")) {
        if (UYTFinalizeItem(item, @"ffmpeg remux")) return;
        UYTArmStallWatchdog(item, 45.0);
        return;
    }

    NSString *vid = [ui respondsToSelector:@selector(videoID)] ? [ui videoID] : nil;
    @try {
        if (vid.length && UYTSABRHasValidCaptureForVideoID(vid)) {
            UYTSABRRecoverItemForVideo(vid, UYTIsAudioOnly(vid));
            return;
        }
    } @catch (NSException *e) {}

    if (UYTFinalizeItem(item, @"no-merge fallback")) return;
    UYTArmStallWatchdog(item, 45.0);
}

- (void)mergeAudioWithVideoForDownloadItem:(id)item {
    UYTDebugInfo(@"[uYouPatches] mergeAudioWithVideo entered");
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"uYouConversionStarted" object:item];
    });
    UYTDebugInfo(@"merge hook: mergeAudioWithVideo entered");

    if (UYTItemIsAudioOnly(item)) {
        UYTDebugInfo(@"[uYouPatches] audio-only item — finalizing without merge");
        if (UYTFinalizeItem(item, @"audio-only no-merge")) return;
        UYTArmStallWatchdog(item, 45.0);
        return;
    }

    if (!UYTEnsureMergeableAudio(item, @"mergeAudio")) {
        if (UYTFinalizeItem(item, @"no-merge fallback")) return;
        UYTArmStallWatchdog(item, 45.0);
        return;
    }

    if (!UYTEnsureMergeableVideo(item, @"mergeAudio")) {
        UYTDebugWarn(@"[uYouPatches] mergeAudioWithVideo: video not pre-mergeable — continuing (best-effort below)");
    }

    id ui = UYTResolveUYouItem(item);
    if (UYTRemuxWithFFmpeg(ui, @"mergeAudio")) {
        if (UYTFinalizeItem(item, @"ffmpeg remux")) return;
        UYTArmStallWatchdog(item, 45.0);
        return;
    }

    NSString *vid = [ui respondsToSelector:@selector(videoID)] ? [ui videoID] : nil;
    @try {
        if (vid.length && UYTSABRHasValidCaptureForVideoID(vid)) {
            UYTSABRRecoverItemForVideo(vid, UYTIsAudioOnly(vid));
            return;
        }
    } @catch (NSException *e) {}

    if (UYTFinalizeItem(item, @"no-merge fallback")) return;
    UYTArmStallWatchdog(item, 45.0);
}
%end

%hook NSFileManager
- (BOOL)moveItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath error:(NSError **)error {
    BOOL result = %orig;

    if (!result && error && *error) {
        if ([*error code] == NSFileWriteNoPermissionError ||
            [*error code] == NSFileWriteFileExistsError ||
            [*error domain] == NSPOSIXErrorDomain) {

            NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
            NSString *fallbackName = [dstPath lastPathComponent];
            NSString *fallbackPath = [docsDir stringByAppendingPathComponent:@"Downloaded"];
            fallbackPath = [fallbackPath stringByAppendingPathComponent:fallbackName];

            [[NSFileManager defaultManager] createDirectoryAtPath:[fallbackPath stringByDeletingLastPathComponent]
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:nil];

            NSError *fallbackError = nil;
            result = [self moveItemAtPath:srcPath toPath:fallbackPath error:&fallbackError];
            if (result) {
                UYTDebugInfo(@"[uYouPatches] File moved to Documents fallback: %@", fallbackPath);
            } else {
                result = [self copyItemAtPath:srcPath toPath:fallbackPath error:&fallbackError];
                if (result) {
                    UYTDebugInfo(@"[uYouPatches] File copied to Documents fallback: %@", fallbackPath);
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

%end

%group gYouSpeedFixes

static float uYouSavedPlaybackRate = 0.0f;

%hook YTMainAppVideoPlayerOverlayViewController
- (void)setPlaybackRate:(CGFloat)rate {
    %orig(rate);

    if (rate != 1.0f) {
        uYouSavedPlaybackRate = rate;
        [[NSUserDefaults standardUserDefaults] setFloat:rate forKey:@"uYouSavedPlaybackRate"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (CGFloat)currentPlaybackRate {
    CGFloat rate = %orig;

    if (rate == 1.0f && uYouSavedPlaybackRate > 0.0f && uYouSavedPlaybackRate != 1.0f) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try {
                [self setPlaybackRate:uYouSavedPlaybackRate];
            } @catch (NSException *e) {
                UYTDebugWarn(@"[uYouPatches] Failed to restore playback rate: %@", e);
            }
        });
    }

    return rate;
}
%end

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

    float savedRate = [[NSUserDefaults standardUserDefaults] floatForKey:@"uYouSavedPlaybackRate"];
    if (savedRate > 0.0f && savedRate != 1.0f) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try {
                [self setPlaybackRate:savedRate];
            } @catch (NSException *e) {
                UYTDebugWarn(@"[uYouPatches] Failed to restore playback rate on appear: %@", e);
            }
        });
    }
}
%end

%hook HAMPlayerInternal
- (void)setRate:(float)rate {
    if (rate == 1.0f && uYouSavedPlaybackRate > 0.0f && uYouSavedPlaybackRate != 1.0f) {
        float currentRate = [self rate];
        if (currentRate > 0.0f && currentRate != 1.0f) {
            %orig(uYouSavedPlaybackRate);
            return;
        }
    }
    %orig(rate);
}
%end

%end

%group gYouFullscreenFixes

%hook YTFullScreenEngagementOverlayController
- (BOOL)isEnabled {
    if (IS_ENABLED(@"noSuggestedVideo_enabled")) {
        return NO;
    }

    return IS_ENABLED(@"repeatVideo") ? NO : %orig;
}
%end

%hook YTFullScreenEngagementOverlayView
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
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

%end

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
            UYTDebugWarn(@"[uYouPatches] Reorder Tabs Notifications injection failed: %@", e);
        }
    }
    return %orig;
}
%end
%end

#pragma mark - Reels Download Button

static const char UYTReelsShortsKey = 0;

static UIViewController *UYTReelsPresenterForHost(UIView *host) {
    if (![host isKindOfClass:[UIView class]]) return nil;
    UIResponder *chain = host;
    while (chain) {
        @try {
            if ([chain isKindOfClass:[UIViewController class]]) return (UIViewController *)chain;
        } @catch (NSException *e) {}
        chain = [chain nextResponder];
    }
    return nil;
}

static void UYTReelsPresentAlertFromView(UIView *host, NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            UIViewController *presenter = UYTReelsPresenterForHost(host);
            if (!presenter) {
                UYTDebugWarn(@"[uYouPatches] Reels download: no presenter for alert");
                return;
            }
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [presenter presentViewController:alert animated:YES completion:nil];
        } @catch (NSException *e) {
            UYTDebugErr(@"uYouPatches Reels alert failed: %@", e);
        }
    });
}

static NSString *UYTReelsCurrentVideoIDFromView(UIView *host) {
    UIResponder *chain = host;
    while (chain) {
        @try {
            if ([chain respondsToSelector:@selector(currentVideoID)]) {
                id value = [chain performSelector:@selector(currentVideoID)];
                if ([value isKindOfClass:[NSString class]] && [(NSString *)value length]) return value;
            }
        } @catch (NSException *e) {}
        chain = [chain nextResponder];
    }
    return nil;
}

static void UYTReelsRunDownload(UIView *host, NSString *videoID, NSString *requestedQuality, BOOL audioOnly) {
    UYTDebugInfo(@"reel download start — vid: %@, quality: %@, audioOnly: %d", videoID,
                 requestedQuality.length ? requestedQuality : @"muxed-default", audioOnly);
    if (requestedQuality.length) {
        [[NSUserDefaults standardUserDefaults] setObject:requestedQuality forKey:@"UYTRequestedQuality"];
    }
    if (audioOnly) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"UYTRequestedAudioOnly"];
    }
    @try {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"UYTRequestedQuality"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"UYTRequestedAudioOnly"];
    } @catch (NSException *e) {}
    @try {
        UYTSABRFallbackDownloadForVideoID(videoID, nil, audioOnly, ^(double frac, unsigned long long bytes) {
            @try { UYTDriveDownloadItemProgressForVideoID(videoID, frac, bytes); } @catch (NSException *e) {}
        }, ^(BOOL ok, NSString *err) {
            @try {
                if (ok) {
                    UYTDebugInfo(@"reel SABR completed: %@", videoID);
                    UYTReelsPresentAlertFromView(host, @"Download complete", @"Saved to the uYouDownloads folder.");
                } else {
                    UYTDebugErr(@"reel SABR failed: %@ (%@)", videoID, err.length ? err : @"no capture");
                    UYTReelsPresentAlertFromView(host, @"Download failed", err.length ? err : @"SABR capture unavailable - play the video for a few seconds first.");
                }
            } @catch (NSException *e) {
                UYTDebugErr(@"uYouPatches reel alert failed: %@", e);
            }
        });
    } @catch (NSException *e) {
        UYTDebugErr(@"uYouPatches reel SABR start failed: %@", e);
        UYTDebugErr(@"reel SABR start threw: %@", e);
    }
}

static void UYTReelsPresentQualityMenuFromView(UIView *host, NSString *videoID, NSArray<UYTStreamFormat *> *formats, NSError *error) {
    if (!formats.count) {
        UYTReelsRunDownload(host, videoID, nil, NO);
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            UIViewController *presenter = UYTReelsPresenterForHost(host);
            if (!presenter) return;
            UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"uYou Download" message:videoID preferredStyle:UIAlertControllerStyleActionSheet];
            NSMutableArray<NSString *> *seen = [NSMutableArray array];

            UYTStreamFormat *muxed = [UYTDownloadPipeline bestMuxedFormat:formats];
            if (muxed.qualityLabel.length) {
                [seen addObject:muxed.qualityLabel];
                [sheet addAction:[UIAlertAction actionWithTitle:muxed.qualityLabel style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                    UYTReelsRunDownload(host, videoID, muxed.qualityLabel, NO);
                }]];
            }
            for (UYTStreamFormat *f in formats) {
                if (!f.hasVideo || f.hasAudio) continue;
                NSString *ql = f.qualityLabel.length ? f.qualityLabel : [NSString stringWithFormat:@"%ldp", (long)f.itag];
                if ([seen containsObject:ql]) continue;
                [seen addObject:ql];
                [sheet addAction:[UIAlertAction actionWithTitle:ql style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                    UYTReelsRunDownload(host, videoID, ql, NO);
                }]];
            }
            if ([UYTDownloadPipeline bestAudioFormat:formats]) {
                [sheet addAction:[UIAlertAction actionWithTitle:@"Audio only" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                    UYTReelsRunDownload(host, videoID, nil, YES);
                }]];
            }
            if (sheet.actions.count == 0) {
                UYTReelsPresentAlertFromView(host, @"uYou Download", @"No playable formats found for this video.");
                return;
            }
            [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [presenter presentViewController:sheet animated:YES completion:nil];
        } @catch (NSException *e) {
            UYTDebugErr(@"uYouPatches reel menu failed: %@", e);
        }
    });
}

static void UYTReelsHandleDownloadTapFromView(UIView *host, UIButton *sender) {
    (void)sender;
    NSString *videoID = UYTReelsCurrentVideoIDFromView(host);
    if (!videoID.length) {
        UYTDebugWarn(@"uYouPatches Reels download tap with no currentVideoID");
        UYTReelsPresentAlertFromView(host, @"uYou Download", @"Open a video before downloading.");
        return;
    }
    NSNumber *shortsBox = objc_getAssociatedObject(host, &UYTReelsShortsKey);
    BOOL isShorts = shortsBox ? shortsBox.boolValue : YES;
    UYTDebugInfo(@"uYouPatches Reels download requested (vid: %@, shorts: %@)", videoID, isShorts ? @"YES" : @"NO");

    [UYTDownloadPipeline fetchFormatsForVideoID:videoID isShorts:isShorts progress:nil completion:^(NSArray<UYTStreamFormat *> *formats, NSError *error) {
        @try {
            if (formats.count) {
                UYTStreamFormat *muxed = [UYTDownloadPipeline bestMuxedFormat:formats];
                UYTStreamFormat *audio = [UYTDownloadPipeline bestAudioFormat:formats];
                UYTStreamFormat *video = [UYTDownloadPipeline bestVideoFormat:formats];
                UYTStoreResolvedURLs(videoID, muxed.url, audio.url, video.url);
                UYTRegisterVideoIDForURL(videoID, video.url);
                UYTRegisterVideoIDForURL(videoID, audio.url);
                UYTRegisterVideoIDForURL(videoID, muxed.url);
                UYTDebugInfo(@"uYouPatches cached innertube URLs for %@ (muxed=%ld, audio=%ld, video=%ld)",
                      videoID, (long)muxed.itag, (long)audio.itag, (long)video.itag);
            } else {
                UYTDebugWarn(@"uYouPatches new pipeline had no formats for %@, falling back to SABR capture (%@)",
                      videoID, error.localizedDescription ?: @"none");
            }
        } @catch (NSException *e) {
            UYTDebugErr(@"uYouPatches reel pipeliner blocked: %@", e);
        }
        UYTReelsPresentQualityMenuFromView(host, videoID, formats, error);
    }];
}

@interface YTReelHeaderView : NSObject
- (void)uYou;
- (void)setUYouButton:(id)button;
- (id)uYouButton;
@end

static const char UYTReelsTargetKey = 0;

@interface UYTReelsDownloadTarget : NSObject
@property (nonatomic, weak) UIView *host;
@end

@implementation UYTReelsDownloadTarget
- (void)uYouDownloadButtonTapped:(id)sender {
    UIView *host = self.host;
    if (!host) return;
    @try { UYTReelsHandleDownloadTapFromView(host, (UIButton *)sender); } @catch (NSException *e) {}
}
@end

static UYTReelsDownloadTarget *UYTReelsTargetForHeader(UIView *header) {
    UYTReelsDownloadTarget *target = objc_getAssociatedObject(header, &UYTReelsTargetKey);
    if (![target isKindOfClass:[UYTReelsDownloadTarget class]]) {
        target = [UYTReelsDownloadTarget new];
        target.host = header;
        objc_setAssociatedObject(header, &UYTReelsTargetKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return target;
}

static void UYTReelsBindVendedButton(YTReelHeaderView *headerView) {
    UIView *header = (UIView *)headerView;
    if (!headerView || ![headerView respondsToSelector:@selector(uYouButton)]) return;
    id button = [headerView uYouButton];
    if (![button isKindOfClass:[UIView class]]) return;
    objc_setAssociatedObject(header, &UYTReelsShortsKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if ([button isKindOfClass:[UIButton class]]) {
        UIButton *b = (UIButton *)button;
        UYTReelsDownloadTarget *target = UYTReelsTargetForHeader(header);
        [b removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        @try {
            if ([b respondsToSelector:@selector(setShowsMenuAsPrimaryAction:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [b performSelector:@selector(setShowsMenuAsPrimaryAction:) withObject:@NO];
#pragma clang diagnostic pop
            }
            if ([b respondsToSelector:@selector(setMenu:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [b performSelector:@selector(setMenu:) withObject:nil];
#pragma clang diagnostic pop
            }
        } @catch (NSException *e) {}
        [b addTarget:target action:@selector(uYouDownloadButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    }
    [header bringSubviewToFront:button];
}

%group gReelHeaderDownloadButton

%hook YTReelHeaderView

- (void)uYou {
    %orig;
    @try { UYTReelsBindVendedButton(self); } @catch (NSException *e) {}
}

- (void)setUYouButton:(id)button {
    %orig(button);
    @try { UYTReelsBindVendedButton(self); } @catch (NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try { UYTReelsBindVendedButton(self); } @catch (NSException *e) {}
}
%end
%end

#pragma mark - Constructor

%ctor {
    float savedRate = [[NSUserDefaults standardUserDefaults] floatForKey:@"uYouSavedPlaybackRate"];
    if (savedRate > 0.0f) {
        uYouSavedPlaybackRate = savedRate;
    }

    %init(gYouFixes);

    %init(gReelHeaderDownloadButton);

    if (%c(settingsReorderTable)) {
        %init(gReorderTabsIntegration);
    }

    Class playerVCClass = %c(YTPlayerViewController);
    if (playerVCClass && [playerVCClass instancesRespondToSelector:@selector(varispeedController)]) {
        %init(gVarispeedFallbackFix);
    }

    if (IS_ENABLED(kReplaceYTDownloadWithuYou)) {
        %init(gYouDownloadFixes);
    }

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
        UYTDebugWarn(@"[uYouPatches] Skipping gYouSpeedFixes: playback-rate selectors missing on this YouTube build");
    }

    %init(gYouFullscreenFixes);
}

