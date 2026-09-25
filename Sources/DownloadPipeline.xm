// DownloadPipeline.xm — modern stream fetcher for YouTube 21.14.4+ (iOS 16–26).
// Design doc: Docs/DownloadPipeline.md

#import <Foundation/Foundation.h>

@interface DownloadsManager : NSObject
+ (instancetype)sharedInstance;
@end

@interface AFHTTPSessionManager : NSObject
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request
                                             progress:(void (^)(NSProgress *progress))progressPtr
                                          destination:(NSURL *(^)(NSURL *targetPath, NSURLResponse *response))destination
                                    completionHandler:(void (^)(NSURLResponse *response, NSURL *filePath, NSError *error))completionHandler;
@end

@interface DownloadItem : NSObject
@property (nonatomic, strong) NSString *videoID;
- (void)setRemoteURL:(NSURL *)url;
@end

static NSString * const UYTInnertubeURL = @"https://www.youtube.com/youtubei/v1/player?key=AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc";
static NSString * const UYTClientVersion = @"19.45.1";

// 403 reroute (#1011): uYouPatches keeps the URL→videoID map so a failed
// task can be mapped back to its video. Declared here since this file
// doesn't import DownloadPipeline.h.
void UYTRegisterRemoteURLForVideoID(NSString * _Nullable vid, NSString * _Nullable url);
void UYTStoreResolvedURLs(NSString * _Nullable vid, NSString * _Nullable muxedURL, NSString * _Nullable audioURL, NSString * _Nullable videoURL);
// Structured logging (UYTLog.h — C linkage via extern "C"). Downloaded via the
// header so call sites here match UYTLog.xm's unmangled definitions (this .xm
// is ObjC++, which would otherwise C++-mangle UYTDebug* call sites and fail to
// link against the C-linkage implementations).
#import "UYTLog.h"
#import "YTSigDecipher.h"

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

static UYTStreamFormat *UYTStreamFormatFromDict(NSDictionary *f, NSString *url) {
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

@interface UYTDownloadPipeline : NSObject
+ (void)fetchFormatsForVideoID:(NSString *)videoID
                     isShorts:(BOOL)isShorts
                     progress:(void (^)(double frac, unsigned long long bytes))progress
                   completion:(void (^)(NSArray<UYTStreamFormat *> *formats, NSError *error))completion;
+ (void)fetchFormatsForVideoID:(NSString *)videoID
                    completion:(void (^)(NSArray<UYTStreamFormat *> *formats, NSError *error))completion;
+ (UYTStreamFormat *)bestMuxedFormat:(NSArray<UYTStreamFormat *> *)formats;
+ (UYTStreamFormat *)bestAudioFormat:(NSArray<UYTStreamFormat *> *)formats;
+ (UYTStreamFormat *)bestVideoFormat:(NSArray<UYTStreamFormat *> *)formats;
@end

@implementation UYTDownloadPipeline

// yt-dlp-style client rotation (#1011): a stream 403 / empty response is often
// client-specific. Each innertube client gets its own signed URLs, so a video
// that 403s on one usually resolves on another. Start at the last good client,
// sweep the rest on failure. Order: ANDROID 19.45.1 -> ANDROID 19.09.39 ->
// IOS 19.45.1 (last resort; #1010 notes it 400s broadly but only as a fallback).
static int UYTLastGoodClient = 0;

+ (NSDictionary *)clientContextForIndex:(int)idx {
    if (idx <= 0) {
        return @{@"context": @{@"client": @{   // ANDROID 19.45.1
            @"clientName": @"ANDROID",
            @"clientVersion": UYTClientVersion,
            @"deviceMake": @"samsung",
            @"deviceModel": @"SM-S928B",
            @"osName": @"Android",
            @"osVersion": @"15",
            @"hl": @"en",
            @"timeZone": @"UTC",
            @"utcOffsetMinutes": @0
        }},
        @"contentCheckOk": @YES,
        @"racyCheckOk": @YES};
    }
    if (idx == 1) {
        return @{@"context": @{@"client": @{   // ANDROID 19.09.39 (classic)
            @"clientName": @"ANDROID",
            @"clientVersion": @"19.09.39",
            @"deviceMake": @"samsung",
            @"deviceModel": @"SM-S928B",
            @"osName": @"Android",
            @"osVersion": @"14",
            @"hl": @"en",
            @"timeZone": @"UTC",
            @"utcOffsetMinutes": @0
        }},
        @"contentCheckOk": @YES,
        @"racyCheckOk": @YES};
    }
    return @{@"context": @{@"client": @{        // IOS 19.45.1 (last resort)
        @"clientName": @"IOS",
        @"clientVersion": UYTClientVersion,
        @"deviceMake": @"Apple",
        @"deviceModel": @"iPhone15,2",
        @"osName": @"iPhone",
        @"osVersion": @"17.5.1.21F90",
        @"hl": @"en",
        @"timeZone": @"UTC",
        @"utcOffsetMinutes": @0
    }},
    @"contentCheckOk": @YES,
    @"racyCheckOk": @YES};
}

+ (NSString *)userAgentForClientIndex:(int)idx {
    if (idx <= 0) {
        return @"com.google.android.youtube/19.45.1 (Linux; U; Android 15; SM-S928B Build/BP1A.250305.009; en_US)";
    }
    if (idx == 1) {
        return @"com.google.android.youtube/19.09.39 (Linux; U; Android 14; SM-S928B Build/UP1A.231005.007; en_US)";
    }
    return @"com.google.android.youtube/19.45.1 (iPhone15,2; U; CPU iPhoneOS 17_5_1 like Mac OS X; en_US)";
}

+ (void)tryClient:(int)idx
          onVideo:(NSString *)videoID
         progress:(void (^)(double frac, unsigned long long bytes))progress
       completion:(void (^)(NSArray<UYTStreamFormat *> *formats, NSError *error))completion {
    NSMutableDictionary *body = [[self clientContextForIndex:idx] mutableCopy];
    body[@"videoId"] = videoID;
    body[@"playbackContext"] = @{@"contentPlaybackContext": @{@"html5Preference": @"HTML5_PREF_WANTS"}};

    NSURL *url = [NSURL URLWithString:UYTInnertubeURL];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[self userAgentForClientIndex:idx] forHTTPHeaderField:@"User-Agent"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    if (progress) progress(0.0, 0);
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            if (progress) progress(1.0, (unsigned long long)data.length);
            if (err || !data) {
                UYTDebugErr(@"fetch client %d net error for %@: %@", idx, videoID, err.localizedDescription ?: @"empty response");
                completion(@[], err ?: [NSError errorWithDomain:@"UYTDownload" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"empty response"}]);
                return;
            }
            NSMutableArray *out = [NSMutableArray array];
            NSMutableArray<NSDictionary *> *ciphered = [NSMutableArray array];
            NSError *jsonErr = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
            if (json) {
                NSArray *streams = json[@"streamingData"][@"adaptiveFormats"];
                NSArray *muxed = json[@"streamingData"][@"formats"];
                for (NSArray *list in @[streams ?: @[], muxed ?: @[]]) {
                    for (NSDictionary *f in list) {
                        NSString *u = f[@"url"];
                        if (u) {
                            [out addObject:UYTStreamFormatFromDict(f, u)];
                            continue;
                        }
                        // No plain url: the format is behind a signatureCipher.
                        // Queue it for the batch resolve below instead of
                        // dropping it - skipping these emptied `out` whenever
                        // every format came back ciphered, which is now the
                        // common case (the old skip -> "no direct urls").
                        NSString *cipher = f[@"signatureCipher"] ?: f[@"cipher"];
                        if (cipher) [ciphered addObject:f];
                    }
                }
            }
            // Ask innertube's error status instead of guessing on empty data,
            // so rotation keeps trying on 400s this client provokes.
            if (!out.count && !ciphered.count) {
                UYTDebugErr(@"fetch client %d no usable URLs for %@ (%@)", idx, videoID,
                            jsonErr ? jsonErr.localizedDescription : (json ? @"no direct urls" : @"bad response"));
                completion(out, json ? nil : (jsonErr ?: [NSError errorWithDomain:@"UYTDownload" code:-11 userInfo:@{NSLocalizedDescriptionKey: @"bad player response"}]));
                return;
            }
            if (!ciphered.count) {
                UYTDebugInfo(@"fetch client %d OK: %lu formats for %@", idx, (unsigned long)out.count, videoID);
                completion(out, nil);
                return;
            }
            // One player.js fetch resolves every ciphered format for this video
            // (they all share the same player version).
            UYTDebugInfo(@"[UYTPipeline] client %d: %lu direct + %lu ciphered for %@", idx,
                         (unsigned long)out.count, (unsigned long)ciphered.count, videoID);
            [UYTSigDecipher playerContextForVideoID:videoID completion:^(UYTPlayerJSContext *player, NSError *sigErr) {
                if (!player) {
                    UYTDebugErr(@"[UYTPipeline] decipher unavailable for %@ (%@)", videoID,
                                sigErr.localizedDescription ?: @"no player context");
                    if (out.count) {
                        completion(out, nil);
                    } else {
                        completion(@[], sigErr ?: [NSError errorWithDomain:@"UYTDownload" code:-1002 userInfo:@{NSLocalizedDescriptionKey: @"signature decipher unavailable"}]);
                    }
                    return;
                }
                NSUInteger deciphered = 0;
                for (NSDictionary *f in ciphered) {
                    NSString *cipher = f[@"signatureCipher"] ?: f[@"cipher"];
                    NSString *resolved = [UYTSigDecipher resolveURLFromSignatureCipher:cipher usingPlayer:player];
                    if (!resolved.length) continue;
                    [out addObject:UYTStreamFormatFromDict(f, resolved)];
                    deciphered++;
                }
                UYTDebugInfo(@"[UYTPipeline] deciphered %lu/%lu ciphered for %@", (unsigned long)deciphered,
                             (unsigned long)ciphered.count, videoID);
                if (out.count) {
                    UYTDebugInfo(@"fetch client %d OK: %lu formats for %@", idx, (unsigned long)out.count, videoID);
                    completion(out, nil);
                } else {
                    completion(@[], [NSError errorWithDomain:@"UYTDownload" code:-1002 userInfo:@{NSLocalizedDescriptionKey: @"all formats undecipherable"}]);
                }
            }];
        }];
    [task resume];
}

+ (void)attempt:(int)n first:(int)first onVideo:(NSString *)videoID
       progress:(void (^)(double frac, unsigned long long bytes))progress
     completion:(void (^)(NSArray<UYTStreamFormat *> *formats, NSError *error))completion
    lastError:(NSError *)lastError {
    if (n > 2) {
        UYTDebugErr(@"all %d clients failed for %@ (last: %@)", 3, videoID, lastError.localizedDescription ?: @"no formats");
        completion(@[], lastError ?: [NSError errorWithDomain:@"UYTDownload" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"no client produced formats"}]);
        return;
    }
    int idx = (first + n) % 3;
    [self tryClient:idx onVideo:videoID progress:progress completion:^(NSArray<UYTStreamFormat *> *formats, NSError *error) {
        if (formats.count) {
            UYTLastGoodClient = idx;
            completion(formats, nil);
        } else {
            [self attempt:(n + 1) first:first onVideo:videoID progress:progress completion:completion lastError:error ?: lastError];
        }
    }];
}

+ (void)fetchFormatsForVideoID:(NSString *)videoID
                     isShorts:(BOOL)isShorts
                     progress:(void (^)(double frac, unsigned long long bytes))progress
                   completion:(void (^)(NSArray<UYTStreamFormat *> *, NSError *))completion {
    (void)isShorts; // shorts use the same client list
    int first = UYTLastGoodClient % 3;
    [self attempt:0 first:first onVideo:videoID progress:progress completion:completion lastError:nil];
}

+ (void)fetchFormatsForVideoID:(NSString *)videoID
                    completion:(void (^)(NSArray<UYTStreamFormat *> *, NSError *))completion {
    [self fetchFormatsForVideoID:videoID isShorts:NO progress:nil completion:completion];
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

+ (UYTStreamFormat *)bestVideoFormat:(NSArray<UYTStreamFormat *> *)formats {
    UYTStreamFormat *best = nil;
    for (UYTStreamFormat *f in formats)
        if (f.hasVideo && !f.hasAudio && (!best || f.bitrate > best.bitrate)) best = f;
    return best;
}

@end

// --- Wiring: fix uYou's stream URLs at the DownloadItem level ---

// yt-dlp-style recovery (#1011): re-fetch formats (rotating clients, so a
// fresh player response hands back fresh signed URLs) and push them into the
// resolved store. A retried task then swaps in a URL that isn't 403'd yet.
void UYTRefreshResolvedURLsForVideo(NSString *vid) {
    if (!vid.length) return;
    UYTDebugInfo(@"refreshing resolved URLs for %@ (client rotation)", vid);
    [UYTDownloadPipeline fetchFormatsForVideoID:vid isShorts:NO progress:nil completion:^(NSArray<UYTStreamFormat *> *formats, NSError *error) {
        @try {
            if (!formats.count) {
                UYTDebugErr(@"refresh: still no formats for %@ (%@)", vid, error.localizedDescription ?: @"none");
                return;
            }
            UYTStreamFormat *muxed = [UYTDownloadPipeline bestMuxedFormat:formats];
            UYTStreamFormat *audio = [UYTDownloadPipeline bestAudioFormat:formats];
            UYTStreamFormat *video = [UYTDownloadPipeline bestVideoFormat:formats];
            UYTStoreResolvedURLs(vid, muxed.url, audio.url, video.url);
            UYTRegisterRemoteURLForVideoID(vid, video.url);
            UYTRegisterRemoteURLForVideoID(vid, audio.url);
            UYTRegisterRemoteURLForVideoID(vid, muxed.url);
            UYTDebugInfo(@"[UYTPipeline] refreshed resolved URLs for %@", vid);
        } @catch (NSException *e) {}
    }];
}

// Resolved URLs per videoID (muxed/audio/video + audioOnly flag). The reel
// tap and a normal download can both fire innertube fetches on seperate bg
// threads, so this dict is locked — an unlocked NSMutableDictionary here is
// a crash waiting to happen. (#995, #1011)
static NSMutableDictionary<NSString *, NSMutableDictionary *> *UYTResolvedStore;
static NSObject *UYTResolvedStoreLock;

static void UYTEnsureResolvedStoreLock(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UYTResolvedStore = [NSMutableDictionary dictionary];
        UYTResolvedStoreLock = [NSObject new];
    });
}

static NSDictionary *UYTResolvedEntrySnapshot(NSString *vid) {
    if (!vid.length) return nil;
    UYTEnsureResolvedStoreLock();
    @synchronized(UYTResolvedStoreLock) {
        return [UYTResolvedStore[vid] copy];
    }
}

static void UYTResolvedEntrySet(NSString *vid, NSString *key, id value) {
    if (!vid.length || !key.length) return;
    UYTEnsureResolvedStoreLock();
    @synchronized(UYTResolvedStoreLock) {
        NSMutableDictionary *entry = UYTResolvedStore[vid];
        if (!entry) {
            entry = [NSMutableDictionary dictionary];
            UYTResolvedStore[vid] = entry;
        }
        entry[key] = value ?: [NSNull null];
    }
}

// Staged SABR file (Downloaded/<vid>.mp4|m4a) wins once it exists — the
// https URL is then pointless and createDownloadTask finalizes from file://.
static NSString *UYTStagedCanonicalPathFor(NSString *vid, NSString *ext) {
    @try {
        if (!vid.length || !ext.length) return nil;
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
        NSString *path = [docs stringByAppendingPathComponent:[NSString stringWithFormat:@"Downloaded/%@.%@", vid, ext]];
        return [[NSFileManager defaultManager] fileExistsAtPath:path] ? path : nil;
    } @catch (NSException *e) {
        return nil;
    }
}

static NSString *UYTFileURLString(NSString *path) {
    return path.length ? [NSURL fileURLWithPath:path].absoluteString : nil;
}

void UYTStoreResolvedURLs(NSString *vid, NSString *muxedURL, NSString *audioURL, NSString *videoURL) {
    @try {
        UYTResolvedEntrySet(vid, @"muxed", muxedURL);
        UYTResolvedEntrySet(vid, @"audio", audioURL);
        UYTResolvedEntrySet(vid, @"video", videoURL);
    } @catch (NSException *e) {}
}

NSString *UYTResolvedVideoURL(NSString *vid) {
    @try {
        if (!vid.length) return nil;
        NSString *staged = UYTStagedCanonicalPathFor(vid, @"mp4");
        if (staged.length) return UYTFileURLString(staged);
        NSDictionary *entry = UYTResolvedEntrySnapshot(vid);
        if (!entry) return nil;
        NSString *muxed = entry[@"muxed"];
        if ([muxed isKindOfClass:[NSString class]] && [muxed length]) return muxed;
        NSString *video = entry[@"video"];
        if ([video isKindOfClass:[NSString class]] && [video length]) return video;
        return nil;
    } @catch (NSException *e) {
        return nil;
    }
}

NSString *UYTResolvedURLForVideo(NSString *vid, BOOL audio) {
    @try {
        if (!vid.length) return nil;
        if (audio) {
            NSString *stagedAudio = UYTStagedCanonicalPathFor(vid, @"m4a");
            if (stagedAudio.length) return UYTFileURLString(stagedAudio);
            NSDictionary *entry = UYTResolvedEntrySnapshot(vid);
            if (entry) {
                NSString *audioURL = entry[@"audio"];
                if ([audioURL isKindOfClass:[NSString class]] && [audioURL length]) return audioURL;
            }
        }
        NSString *videoURL = UYTResolvedVideoURL(vid);
        if (videoURL.length) return videoURL;
        NSDictionary *entry = UYTResolvedEntrySnapshot(vid);
        if (entry) {
            NSString *audioURL = entry[@"audio"];
            if ([audioURL isKindOfClass:[NSString class]] && [audioURL length]) return audioURL;
        }
        return nil;
    } @catch (NSException *e) {
        return nil;
    }
}

void UYTMarkAudioOnly(NSString *vid, BOOL audioOnly) {
    @try {
        UYTResolvedEntrySet(vid, @"audioOnly", @(audioOnly));
    } @catch (NSException *e) {}
}

BOOL UYTIsAudioOnly(NSString *vid) {
    @try {
        if (!vid.length) return NO;
        NSDictionary *entry = UYTResolvedEntrySnapshot(vid);
        if (!entry) return NO;
        NSNumber *flag = entry[@"audioOnly"];
        if ([flag isKindOfClass:[NSNumber class]]) return flag.boolValue;
        NSString *audio = entry[@"audio"];
        NSString *video = entry[@"video"];
        NSString *muxed = entry[@"muxed"];
        BOOL onlyAudioInfo = ([audio isKindOfClass:[NSString class]] && [audio length])
                          && !([video isKindOfClass:[NSString class]] && [video length])
                          && !([muxed isKindOfClass:[NSString class]] && [muxed length]);
        return onlyAudioInfo;
    } @catch (NSException *e) {
        return NO;
    }
}

static NSString *UYTGetResolvedURL(NSString *vid) {
    return UYTResolvedVideoURL(vid);
}

// KVC helper — real uYou key names change across versions so each write is
// guarded; unknown keys just no-op.
static void UYTSafeSetValue(id obj, NSString *key, id value) {
    if (!obj || !key.length) return;
    @try { [obj setValue:value forKey:key]; } @catch (NSException *e) {}
}

// Mirror SABR/pipeline progress onto uYou's own download list row.
void UYTDriveDownloadItemProgressForVideoID(NSString *vid, double fractionComplete, unsigned long long bytesDownloaded) {
    @try {
        if (!vid.length) return;
        NSNumber *frac = @(fractionComplete);
        NSNumber *bytes = @((unsigned long long)bytesDownloaded);
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                id manager = [%c(DownloadsManager) sharedInstance];
                if (!manager) return;
                id queue = nil;
                for (NSString *key in @[@"activeDownloadItems", @"allDownloadItems", @"downloads", @"downloadList", @"downloadingItems"]) {
                    @try { queue = [manager valueForKey:key]; if (queue) break; } @catch (NSException *e) {}
                }
                if (![queue isKindOfClass:[NSArray class]]) return;
                for (id item in (NSArray *)queue) {
                    NSString *iv = nil;
                    @try { iv = [item respondsToSelector:@selector(videoID)] ? [item videoID] : [item valueForKey:@"videoID"]; } @catch (NSException *e) {}
                    if (![iv isKindOfClass:[NSString class]] || ![iv isEqualToString:vid]) continue;
                    UYTSafeSetValue(item, @"progress", frac);
                    UYTSafeSetValue(item, @"progressValue", frac);
                    UYTSafeSetValue(item, @"downloadProgress", frac);
                    UYTSafeSetValue(item, @"bytesDownloaded", bytes);
                    UYTSafeSetValue(item, @"downloadedBytes", bytes);
                    break;
                }
            } @catch (NSException *e) {}
        });
    } @catch (NSException *e) {}
}

// Stamp final values (100% + real size) on a done item.
void UYTWriteFinalDownloadProgress(id item, NSString *filePath) {
    @try {
        if (!item) return;
        NSNumber *size = @0;
        if (filePath.length) {
            NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
            if (attrs) size = @([attrs fileSize]);
        }
        UYTSafeSetValue(item, @"progress", @1.0);
        UYTSafeSetValue(item, @"progressValue", @1.0);
        UYTSafeSetValue(item, @"downloadProgress", @1.0);
        UYTSafeSetValue(item, @"bytesDownloaded", size);
        UYTSafeSetValue(item, @"downloadedBytes", size);
        UYTSafeSetValue(item, @"size", size);
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                id manager = [%c(DownloadsManager) sharedInstance];
                if (!manager) return;
                UYTSafeSetValue(manager, @"bytesDownloaded", size);
                UYTSafeSetValue(manager, @"totalBytesDownloaded", size);
            } @catch (NSException *e) {}
        });
    } @catch (NSException *e) {}
}

// --- DB integration (reserved) ---
// The URL swap lets uYou's own flow do DB inserts when given a valid URL, so
// the standalone insert func was removed (was hitting -Wunused-function).
// Keeping the old schema here for reference:
//   downloads(id TEXT PK, videoID, title, channel, channelURL, qualityLabel,
//             typeAndQuality, size, duration, type, path, lyrics, timestamp)

%hook DownloadItem

- (id)initWithVideoID:(id)videoID
             uYouItem:(id)uYouItem
           downloadID:(id)downloadID
                  url:(id)url
             filePath:(id)filePath
           cachedPath:(id)cachedPath
                 type:(int)type {

    UYTDebugInfo(@"[UYTPipeline] DownloadItem init:");
    UYTDebugInfo(@"[UYTPipeline] videoID = %@", videoID);
    UYTDebugInfo(@"[UYTPipeline] downloadID = %@", downloadID);
    UYTDebugInfo(@"[UYTPipeline] filePath = %@", filePath);
    UYTDebugInfo(@"[UYTPipeline] cachedPath = %@", cachedPath);

    @try {
        UYTDebugInfo(@"[UYTPipeline] title = %@", [uYouItem valueForKey:@"title"]);
        UYTDebugInfo(@"[UYTPipeline] uYouItem.filePath = %@", [uYouItem valueForKey:@"filePath"]);
    } @catch (NSException *e) {
        UYTDebugErr(@"[UYTPipeline] diagnostic failed: %@", e);
    }

    return %orig(videoID, uYouItem, downloadID, url, filePath, cachedPath, type);
}

- (void)setRemoteURL:(NSURL *)url {
    NSString *vid = self.videoID ?: @"";
    // Register both the original and the swap URL so a failed task (403,
    // #1011) can map back to this video — the lookup tolerates uYou's extra
    // metadata params on the URL.
    if (url.absoluteString.length) UYTRegisterRemoteURLForVideoID(vid, url.absoluteString);
    NSString *working = UYTGetResolvedURL(vid);
    if (working.length) {
        UYTRegisterRemoteURLForVideoID(vid, working);
        NSURL *fixed = [NSURL URLWithString:working];
        if (fixed) {
            UYTDebugInfo(@"URL swap for %@ (task URL -> cached resolved URL)", vid);
            UYTDebugInfo(@"[UYTPipeline] swapped broken URL -> working innertube URL for %@", vid);
            %orig(fixed);
            return;
        }
    }
    %orig;
}
%end

%ctor {
    %init;
}
