// DownloadPipeline.xm — modern stream fetcher for YouTube 21.14.4+ (iOS 16–26).
// Design doc: Docs/DownloadPipeline.md
// Phase 1 scaffold: innertube player request + format selection.

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <MediaPlayer/MediaPlayer.h>
#import "YTSigDecipher.h"
#import "UYTSABR.h"
#import "UYTDownloadsDB.h"
#import "UYTLog.h"

@interface DownloadsManager : NSObject
+ (instancetype)sharedInstance;
- (NSMutableArray *)downloadItemsArray;
- (void)setDownloadingItems;
@end

@interface AFHTTPSessionManager : NSObject
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request
                                             progress:(void (^)(NSProgress *progress))progressPtr
                                          destination:(NSURL *(^)(NSURL *targetPath, NSURLResponse *response))destination
                                    completionHandler:(void (^)(NSURLResponse *response, NSURL *filePath, NSError *error))completionHandler;
@end

@interface DownloadItem : NSObject
@property (nonatomic, strong) NSString *videoID;
@property (nonatomic, strong) NSString *filePath;
- (void)setRemoteURL:(NSURL *)url;
- (void)createDownloadTask;
@end

@interface DownloadingCell : UITableViewCell
- (void)updateProgressForInfoButton:(id)button downloadItem:(id)downloadItem;
@end

// Marks DownloadItems whose download SABR is driving (no NSURLSession task).
static char kUYTSABRDrivenKey;

// uYou's own completion path removes a finished download from
// DownloadsManager.downloadItemsArray (what the Downloading tab lists) and
// refreshes that tab; SABR downloads bypass that path, so the finished row
// stayed there (confirmed on-device). Do it ourselves. Method and
// notification names confirmed via otool/strings on uYou.dylib.
static void UYTRemoveFromDownloading(id uyouItem, NSString *vid) {
    @try {
        DownloadsManager *mgr = [%c(DownloadsManager) sharedInstance];
        NSMutableArray *items = [mgr downloadItemsArray];
        NSIndexSet *hits = [items indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
            if (obj == uyouItem) return YES;
            id owner = nil;
            @try { owner = [obj valueForKey:@"uYouItem"]; } @catch (NSException *e) {}
            return owner == uyouItem;
        }];
        NSUInteger before = items.count;
        if (hits.count) {
            [items removeObjectsAtIndexes:hits];
            [mgr setDownloadingItems];
        }
        UYTLog(@"[UYTPipeline] removed %lu finished item(s) for %@ from Downloading (%lu -> %lu)",
              (unsigned long)hits.count, vid, (unsigned long)before, (unsigned long)items.count);
    } @catch (NSException *e) {
        UYTLog(@"[UYTPipeline] could not remove %@ from Downloading: %@", vid, e);
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"reloadDownloadingVCNotification" object:nil];
}

// uYou's player loads a downloaded item's artwork from uYouItem.thumbnailPath
// (its own downloads save it next to the media). SABR downloads never wrote
// one, and playing them crashed in -[MPMediaItemArtwork initWithImage:] with
// a nil image (confirmed via on-device .ips crash report). Write it here.
static void UYTSaveThumbnail(id uyouItem, NSString *vid) {
    NSString *thumbPath = nil;
    UIImage *image = nil;
    @try {
        thumbPath = [uyouItem valueForKey:@"thumbnailPath"];
        image = [uyouItem valueForKey:@"image"];
    } @catch (NSException *e) {}
    if (!thumbPath.length) { UYTLog(@"[UYTPipeline] no thumbnailPath for %@", vid); return; }
    if ([[NSFileManager defaultManager] fileExistsAtPath:thumbPath]) return;
    BOOL jpeg = [@[@"jpg", @"jpeg"] containsObject:thumbPath.pathExtension.lowercaseString];
    void (^write)(UIImage *) = ^(UIImage *img) {
        NSData *data = jpeg ? UIImageJPEGRepresentation(img, 0.9) : UIImagePNGRepresentation(img);
        [[NSFileManager defaultManager] createDirectoryAtPath:thumbPath.stringByDeletingLastPathComponent
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        BOOL ok = [data writeToFile:thumbPath atomically:YES];
        UYTLog(@"[UYTPipeline] thumbnail for %@ written=%d at %@", vid, ok, thumbPath);
    };
    if ([image isKindOfClass:[UIImage class]]) { write(image); return; }
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://i.ytimg.com/vi/%@/hqdefault.jpg", vid]];
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        UIImage *img = data ? [UIImage imageWithData:data] : nil;
        if (img) write(img);
        else UYTLog(@"[UYTPipeline] thumbnail fetch failed for %@: %@", vid, err);
    }] resume];
}

static NSString * const UYTInnertubeURL = @"https://www.youtube.com/youtubei/v1/player?key=AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc";
static NSString * const UYTClientVersion = @"19.45.1";

@interface UYTStreamFormat : NSObject
@property (nonatomic, copy) NSString *url;
@property (nonatomic, assign) NSInteger itag;
@property (nonatomic, copy) NSString *mimeType;   // e.g. "video/mp4"
@property (nonatomic, assign) BOOL hasVideo;
@property (nonatomic, assign) BOOL hasAudio;
@property (nonatomic, assign) long long bitrate;
@property (nonatomic, copy) NSString *qualityLabel;
@end

@implementation UYTStreamFormat
@end

@interface UYTDownloadPipeline : NSObject
+ (void)fetchFormatsForVideoID:(NSString *)videoID
                    completion:(void (^)(NSArray<UYTStreamFormat *> *formats, NSError *error))completion;
+ (UYTStreamFormat *)streamFormatFromDict:(NSDictionary *)f url:(NSString *)url;
+ (UYTStreamFormat *)bestMuxedFormat:(NSArray<UYTStreamFormat *> *)formats;
+ (UYTStreamFormat *)bestAudioFormat:(NSArray<UYTStreamFormat *> *)formats;
@end

@implementation UYTDownloadPipeline

+ (NSDictionary *)clientContext {
    return @{@"context": @{@"client": @{
        @"clientName": @"IOS",
        @"clientVersion": UYTClientVersion,
        @"deviceMake": @"Apple",
        @"deviceModel": @"iPhone16,2",
        @"osName": @"iOS",
        @"osVersion": @"18.5.0.22F76",
        @"hl": @"en",
        @"timeZone": @"UTC",
        @"utcOffsetMinutes": @0
    }},
    @"contentCheckOk": @YES,
    @"racyCheckOk": @YES};
}

+ (void)fetchFormatsForVideoID:(NSString *)videoID
                    completion:(void (^)(NSArray<UYTStreamFormat *> *, NSError *))completion {
    NSMutableDictionary *body = [[self clientContext] mutableCopy];
    body[@"videoId"] = videoID;
    body[@"playbackContext"] = @{@"contentPlaybackContext": @{@"html5Preference": @"HTML5_PREF_WANTS"}};

    NSURL *url = [NSURL URLWithString:UYTInnertubeURL];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"com.google.ios.youtube/19.45.1 (iPhone16,2; U; CPU iOS 18_5_0 like Mac OS X;)" forHTTPHeaderField:@"User-Agent"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            if (err || !data) {
                completion(@[], err ?: [NSError errorWithDomain:@"UYTDownload" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"empty response"}]);
                return;
            }
            NSError *jsonErr = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
            if (!json) {
                completion(@[], jsonErr);
                return;
            }
            NSArray *streams = json[@"streamingData"][@"adaptiveFormats"];
            NSArray *muxed = json[@"streamingData"][@"formats"];
            NSMutableArray<UYTStreamFormat *> *out = [NSMutableArray array];
            NSMutableArray<NSDictionary *> *ciphered = [NSMutableArray array];
            for (NSArray *list in @[streams ?: @[], muxed ?: @[]]) {
                for (NSDictionary *f in list) {
                    NSString *u = f[@"url"];
                    if (u) {
                        [out addObject:[self streamFormatFromDict:f url:u]];
                        continue;
                    }
                    // No plain url: YouTube gated this format behind a
                    // signatureCipher. Resolve those as a batch below instead
                    // of dropping them (was: `continue` - silently discarded
                    // every format whenever ALL of them were ciphered, which
                    // left `out` empty and produced NSURLErrorUnsupportedURL
                    // (-1002) downstream once uYou's own broken native
                    // extraction was the only thing left to fall back to).
                    NSString *cipher = f[@"signatureCipher"] ?: f[@"cipher"];
                    if (cipher) [ciphered addObject:f];
                }
            }

            if (ciphered.count == 0) {
                completion(out, nil);
                return;
            }

            [UYTSigDecipher playerContextForVideoID:videoID completion:^(UYTPlayerJSContext *player, NSError *sigErr) {
                if (!player) {
                    UYTLog(@"[UYTPipeline] signature decipher unavailable for %@ (%@); %lu ciphered format(s) dropped",
                          videoID, sigErr.localizedDescription, (unsigned long)ciphered.count);
                    completion(out, nil);
                    return;
                }
                NSUInteger deciphered = 0;
                for (NSDictionary *f in ciphered) {
                    NSString *cipher = f[@"signatureCipher"] ?: f[@"cipher"];
                    NSString *resolved = [UYTSigDecipher resolveURLFromSignatureCipher:cipher usingPlayer:player];
                    if (resolved) {
                        [out addObject:[self streamFormatFromDict:f url:resolved]];
                        deciphered++;
                    }
                }
                UYTLog(@"[UYTPipeline] deciphered %lu/%lu ciphered format(s) for %@",
                      (unsigned long)deciphered, (unsigned long)ciphered.count, videoID);
                completion(out, nil);
            }];
        }];
    [task resume];
}

+ (UYTStreamFormat *)streamFormatFromDict:(NSDictionary *)f url:(NSString *)url {
    UYTStreamFormat *sf = [[UYTStreamFormat alloc] init];
    sf.url = url;
    sf.itag = [f[@"itag"] integerValue];
    sf.mimeType = f[@"mimeType"];
    sf.bitrate = [f[@"bitrate"] longLongValue];
    sf.qualityLabel = f[@"qualityLabel"];
    sf.hasVideo = [sf.mimeType hasPrefix:@"video"];
    sf.hasAudio = [sf.mimeType hasPrefix:@"audio"] || ([sf.mimeType hasPrefix:@"video"] && ![f objectForKey:@"qualityLabel"]);
    return sf;
}

+ (UYTStreamFormat *)bestMuxedFormat:(NSArray<UYTStreamFormat *> *)formats {
    UYTStreamFormat *best = nil;
    for (UYTStreamFormat *f in formats)
        if (f.hasVideo && f.hasAudio && (!best || f.bitrate > best.bitrate)) best = f;
    return best;
}

+ (UYTStreamFormat *)bestAudioFormat:(NSArray<UYTStreamFormat *> *)formats {
    UYTStreamFormat *best = nil;
    for (UYTStreamFormat *f in formats)
        if (f.hasAudio && !f.hasVideo && [f.mimeType containsString:@"mp4"]
            && (!best || f.bitrate > best.bitrate)) best = f;
    return best;
}

@end

// --- Wiring: fix uYou's stream URLs at the DownloadItem level ---------------

// Store resolved URLs keyed by videoID so the DownloadItem hook can swap them.
static NSMutableDictionary<NSString *, NSString *> *UYTResolvedURLs;

static void UYTStoreResolvedURL(NSString *vid, NSString *url) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UYTResolvedURLs = [NSMutableDictionary dictionary];
    });
    if (vid.length && url.length) UYTResolvedURLs[vid] = url;
}

static NSString *UYTGetResolvedURL(NSString *vid) {
    return UYTResolvedURLs[vid] ?: nil;
}

// --- DB integration (reserved for future use) --------------------------------
// With the URL-swap approach, uYou's native flow handles DB insertion when
// given valid stream URLs. This section is kept for reference but the
// standalone insert function was removed to fix -Wunused-function.
// Schema for future re-use:
//   CREATE TABLE IF NOT EXISTS downloads (id TEXT PRIMARY KEY, videoID TEXT,
//   title TEXT, channel TEXT, channelURL TEXT, qualityLabel TEXT,
//   typeAndQuality TEXT, size TEXT, duration TEXT, type TEXT, path TEXT,
//   lyrics TEXT, timestamp DATETIME)
//   DB path: Documents/uyoudb.sqlite (or AppGroup/uyoudb.sqlite)

%hook DownloadsManager
- (void)getLinksLocallyPlayerItem:(id)item videoID:(id)videoID sourceView:(id)sourceView isShorts:(BOOL)isShorts {
    NSString *vid = [NSString stringWithFormat:@"%@", videoID];

    // Pre-fetch working stream URLs via innertube BEFORE %orig runs.
    [UYTDownloadPipeline fetchFormatsForVideoID:vid completion:^(NSArray<UYTStreamFormat *> *formats, NSError *error) {
        if (error || formats.count == 0) {
            UYTLog(@"[UYTPipeline] no formats for %@ (%@)", vid, error.localizedDescription);
            // Modern YouTube (21.29.3+) returns no stream URL at all - plain
            // or signatureCipher - for this client context; innertube alone
            // can't get us anything. The actual SABR fallback trigger and
            // completion handling lives in DownloadItem -setRemoteURL: below,
            // where we have a reference to the specific DownloadItem to drive
            // to completion - triggering it here was a dead end: %orig's own
            // broken native flow fails with NSURLErrorUnsupportedURL (-1002)
            // near-instantly (confirmed on-device: error shown before this
            // method's own 1.5s %orig delay even elapses), long before SABR
            // (confirmed ~48s for a real download) has anything to hand back,
            // and nothing here has a way to signal a DownloadItem that
            // doesn't exist yet.
            return;
        }
        UYTStreamFormat *best = [UYTDownloadPipeline bestMuxedFormat:formats];
        if (best.url.length) {
            UYTStoreResolvedURL(vid, best.url);
            UYTLog(@"[UYTPipeline] cached working URL for %@ (itag=%ld)", vid, (long)best.itag);
        }
    }];

    // Give the async fetch a moment, then let %orig proceed — the DownloadItem
    // hook below will swap any broken URL with our cached working one.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        %orig;
    });
}
%end

// Intercept DownloadItem URL assignment — swap broken extraction URLs with
// our working innertube-fetched ones so uYou's native download flow functions.
%hook DownloadItem
- (void)setRemoteURL:(NSURL *)url {
    NSString *vid = self.videoID ?: @"";
    NSString *working = UYTGetResolvedURL(vid);
    if (working.length) {
        NSURL *fixed = [NSURL URLWithString:working];
        if (fixed) {
            UYTLog(@"[UYTPipeline] swapped broken URL -> working innertube URL for %@", vid);
            %orig(fixed);
            return;
        }
    }

    // No working innertube URL for this video (modern YouTube returns none
    // at all for our client context - see getLinksLocallyPlayerItem: above).
    // Calling %orig(url) here hands uYou's native flow whatever broken URL
    // it extracted itself, which fails almost instantly with
    // NSURLErrorUnsupportedURL (-1002) - confirmed on-device, the error
    // shows before SABR (which takes ~48s for a real download) could ever
    // hand anything back. Skip %orig entirely in that case and drive THIS
    // SAME DownloadItem to completion ourselves once SABR finishes, instead
    // of relying on the merge-hook watchdog (uYouPatches.xm) that never gets
    // armed because the flow never reaches the merge stage without a
    // successful initial download.
    if (UYTSABRHasValidCapture()) {
        UYTLog(@"[UYTPipeline] no working URL for %@, driving via SABR instead of uYou's native flow", vid);
        objc_setAssociatedObject(self, &kUYTSABRDrivenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak DownloadItem *weakSelf = self;
        // uyouItem was already created by uYou's own earlier flow (before we
        // intercept here) with real metadata from the YouTube page - grab it
        // via KVC since this file's own minimal DownloadItem interface
        // doesn't declare a typed uYouItem property.
        id uyouItem = nil;
        @try { uyouItem = [self valueForKey:@"uYouItem"]; } @catch (NSException *e) {}
        NSString *title = nil, *channel = nil, *channelURL = nil, *qualityLabel = nil, *typeAndQuality = nil;
        NSString *targetPath = nil, *dbPathValue = nil, *rowID = nil, *typeValue = nil;
        @try {
            title = [uyouItem valueForKey:@"title"];
            channel = [uyouItem valueForKey:@"channel"];
            channelURL = [uyouItem valueForKey:@"channelURL"];
            qualityLabel = [uyouItem valueForKey:@"qualityLabel"];
            typeAndQuality = [uyouItem valueForKey:@"typeAndQuality"];
            // Use uYou's own values for where the file lives and how the DB
            // row is keyed/typed (confirmed via otool class-dump of uYouItem):
            // filePath is where uYou's player/share look for the file, type is
            // the int its tabs filter on (`type` LIKE '%lu'), and
            // downloadIdentifier is unique per download.
            targetPath = [uyouItem valueForKey:@"filePath"];
            dbPathValue = [uyouItem valueForKey:@"path"];
            rowID = [uyouItem valueForKey:@"downloadIdentifier"];
            typeValue = [[uyouItem valueForKey:@"type"] stringValue];
        } @catch (NSException *e) {}
        BOOL audioOnly = [[targetPath.pathExtension lowercaseString] isEqualToString:@"m4a"];
        UYTLog(@"[UYTPipeline] uYouItem for %@: filePath=%@ path=%@ id=%@ type=%@ audioOnly=%d",
              vid, targetPath, dbPathValue, rowID, typeValue, audioOnly);
        // Everything uYouItem computes about where its files live, so a
        // playback failure for one format (mp4 vs webm) can be traced to the
        // exact path uYou expects vs. where we put the file.
        for (NSString *key in @[@"isMP4", @"videoFormat", @"audioFormat", @"quality", @"cachedVideoPath",
                                @"cachedAudioPath", @"tmpVideoPath", @"tmpAudioPath", @"tmpMP4Path",
                                @"tmpMKVPath", @"thumbnailPath", @"videoURL", @"audioURL"]) {
            id v = nil;
            @try { v = [uyouItem valueForKey:key]; } @catch (NSException *e) { v = @"<no such key>"; }
            UYTLog(@"[UYTPipeline]   uYouItem.%@ = %@", key, v);
        }

        // Reuse uYou's OWN progress plumbing instead of building custom UI.
        // An earlier attempt here set a `downloadProgress` NSProgress
        // property that doesn't actually exist on this class - it silently
        // no-op'd through the @try/@catch around setValue:forKey:, which is
        // why the UI never moved. Confirmed via otool -ov class-dump of the
        // real uYou.dylib in this build what DownloadItem actually has:
        //   float     progress          (0.0-1.0)
        //   NSString *totalSize         (pre-formatted, e.g. "45.2 MB")
        //   NSString *downloadedSize    (pre-formatted)
        //   NSString *speed             (pre-formatted, e.g. "1.2 MB/s")
        //   int       remainingTime     (seconds)
        // DownloadingCell/DownloadingInfoButton read these directly and
        // refresh off a "downloadProgressChangedNotification" post - same
        // notification name confirmed via strings, reused as-is.
        NSDate *sabrStartDate = [NSDate date];
        NSByteCountFormatter *sabrByteFmt = [NSByteCountFormatter new];
        sabrByteFmt.countStyle = NSByteCountFormatterCountStyleFile;

        UYTSABRFallbackDownloadForVideoID(vid, audioOnly, ^(double frac, unsigned long long bytesDownloaded) {
            DownloadItem *progressSelf = weakSelf;
            if (!progressSelf) return;
            NSTimeInterval elapsed = -[sabrStartDate timeIntervalSinceNow];
            // SABR gives no upfront Content-Length - estimate a moving total
            // from bytes-so-far/fraction-so-far, same technique most download
            // UIs use when the real total isn't known ahead of time.
            NSString *downloadedStr = [sabrByteFmt stringFromByteCount:(long long)bytesDownloaded];
            NSString *totalStr = (frac > 0.02) ? [sabrByteFmt stringFromByteCount:(long long)(bytesDownloaded / frac)] : nil;
            double bytesPerSec = (elapsed > 0.5) ? (double)bytesDownloaded / elapsed : 0;
            NSString *speedStr = (bytesPerSec > 0) ? [NSString stringWithFormat:@"%@/s", [sabrByteFmt stringFromByteCount:(long long)bytesPerSec]] : nil;
            int remaining = (frac > 0.02 && elapsed > 0.5) ? (int)(elapsed / frac * (1.0 - frac)) : 0;
            @try {
                [progressSelf setValue:@(frac) forKey:@"progress"];
                if (downloadedStr) [progressSelf setValue:downloadedStr forKey:@"downloadedSize"];
                if (totalStr) [progressSelf setValue:totalStr forKey:@"totalSize"];
                if (speedStr) [progressSelf setValue:speedStr forKey:@"speed"];
                [progressSelf setValue:@(remaining) forKey:@"remainingTime"];
            } @catch (NSException *e) {}
            [[NSNotificationCenter defaultCenter] postNotificationName:@"downloadProgressChangedNotification" object:progressSelf];
        }, ^(BOOL success, NSString *sabrErr) {
            UYTLog(@"[UYTPipeline] SABR fallback for %@: %@", vid, success ? @"succeeded" : sabrErr);
            if (!success) return;
            DownloadItem *strongSelf = weakSelf;
            if (!strongSelf) {
                UYTLog(@"[UYTPipeline] DownloadItem for %@ deallocated before SABR finished", vid);
                return;
            }
            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *sabrOut = UYTSABROutputPathForVideoID(vid, audioOnly);
            NSString *sabrPath = targetPath.length ? targetPath : sabrOut;
            // Several DownloadItems (uYou's audio + video items) share one
            // uYouItem and each get this callback - only the first finds the
            // SABR output still there to move; the rest see it already placed.
            if (![sabrPath isEqualToString:sabrOut] && [fm fileExistsAtPath:sabrOut]) {
                [fm createDirectoryAtPath:[sabrPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
                [fm removeItemAtPath:sabrPath error:nil];
                NSError *mvErr = nil;
                if (![fm moveItemAtPath:sabrOut toPath:sabrPath error:&mvErr]) {
                    UYTLog(@"[UYTPipeline] could not move SABR file into uYou's filePath %@: %@", sabrPath, mvErr);
                    sabrPath = sabrOut;
                }
            }
            UYTLog(@"[UYTPipeline] final file for %@ at %@ exists=%d", vid, sabrPath, [fm fileExistsAtPath:sabrPath]);

            NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:sabrPath error:nil];
            unsigned long long fileSize = [attrs[NSFileSize] unsignedLongLongValue];
            NSTimeInterval duration = 0;
            @try {
                AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:sabrPath] options:nil];
                duration = CMTimeGetSeconds(asset.duration);
                if (isnan(duration) || isinf(duration)) duration = 0;
            } @catch (NSException *e) {}

            // uYou's own "Downloaded" tab reads from uyoudb.sqlite, not the
            // filesystem - without this row the file exists but the app has
            // no idea it's there. Schema/INSERT confirmed via strings on the
            // real uYou.dylib binary (see UYTDownloadsDB.h).
            UYTDownloadsDBInsertCompleted(rowID, vid, title, channel, channelURL, qualityLabel, typeAndQuality,
                                           fileSize, duration, typeValue,
                                           dbPathValue.length ? dbPathValue : sabrPath.lastPathComponent);

            UYTSaveThumbnail(uyouItem, vid);

            dispatch_async(dispatch_get_main_queue(), ^{
                strongSelf.filePath = sabrPath;
                @try {
                    [strongSelf setValue:@1.0f forKey:@"progress"];
                    [strongSelf setValue:[sabrByteFmt stringFromByteCount:(long long)fileSize] forKey:@"totalSize"];
                    [strongSelf setValue:[sabrByteFmt stringFromByteCount:(long long)fileSize] forKey:@"downloadedSize"];
                    [strongSelf setValue:@0 forKey:@"remainingTime"];
                } @catch (NSException *e) {}
                [[NSNotificationCenter defaultCenter] postNotificationName:@"downloadProgressChangedNotification" object:strongSelf];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"downloadDidCompleteNotification" object:strongSelf];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"conversionDidCompleteNotification" object:strongSelf];
                UYTRemoveFromDownloading(uyouItem, vid);
            });
        });
        return; // do NOT call %orig - that's what produces the instant -1002
    }

    UYTLog(@"[UYTPipeline] no working URL and no SABR capture for %@ - falling through to uYou's native flow (will likely fail)", vid);
    %orig;
}

// uYou's caller invokes createDownloadTask right after setRemoteURL:,
// independently of whatever setRemoteURL: itself decided to do. When we
// drove a video via SABR above, self.remoteURL was never set (we skipped
// %orig entirely), so %orig here would build an NSURLRequest from a nil
// URL and fail near-instantly with NSURLErrorUnsupportedURL (-1002) - a
// SEPARATE failure from anything setRemoteURL: does, running in parallel
// with our still-in-progress SABR download (confirmed on-device: the
// progress bar we drive via UYTSABRFallbackDownloadForVideoID's progress
// callback DOES tick upward briefly, then the row shows -1002 anyway and
// nothing ever completes - exactly what a competing, instantly-failing
// native download task racing our real one would look like).
- (void)createDownloadTask {
    NSString *vid = self.videoID ?: @"";
    id currentRemoteURL = nil;
    @try { currentRemoteURL = [self valueForKey:@"remoteURL"]; } @catch (NSException *e) {}
    if (!currentRemoteURL && UYTSABRHasValidCapture()) {
        UYTLog(@"[UYTPipeline] skipping uYou's own createDownloadTask for %@ - remoteURL is nil (SABR is already driving this download)", vid);
        return;
    }
    %orig;
}
%end

// The percentage label follows the `progress` we set on DownloadItem, but
// the UIProgressView next to it stays put for SABR downloads (confirmed
// on-device) - uYou evidently drives the bar from its own NSURLSession task,
// which SABR downloads don't have. After uYou refreshes an info button,
// push the item's progress into that button's bar ourselves.
%hook DownloadingCell
- (void)updateProgressForInfoButton:(id)button downloadItem:(id)downloadItem {
    %orig;
    if (!downloadItem || !objc_getAssociatedObject(downloadItem, &kUYTSABRDrivenKey)) return;
    @try {
        float p = [[downloadItem valueForKey:@"progress"] floatValue];
        UIProgressView *bar = [button valueForKey:@"progressBar"];
        if ([bar isKindOfClass:[UIProgressView class]]) [bar setProgress:p animated:YES];
    } @catch (NSException *e) {}
}
%end

// Belt-and-braces for the same crash: a nil image here throws
// NSInvalidArgumentException and takes the whole app down. Substitute a
// blank image so a missing thumbnail can only ever cost the artwork.
%hook MPMediaItemArtwork
- (id)initWithImage:(UIImage *)image {
    if (!image) {
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1, 1)];
        image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {}];
    }
    return %orig(image);
}
%end

%ctor {
    %init;
}

