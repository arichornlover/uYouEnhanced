
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

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

static NSString *UYTAppVersion(void) {
    static NSString *cached = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *v = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        if (!v.length) v = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
        cached = v.length ? v : UYTClientVersion;
    });
    return cached;
}

static NSString *UYTIOSVersion(void) {
    static NSString *cached = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cached = [[UIDevice currentDevice] systemVersion] ?: @"0.0";
    });
    return cached;
}

static NSString *UYTIOSModel(void) {
    static NSString *cached = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cached = [[UIDevice currentDevice] model] ?: @"iPhone";
    });
    return cached;
}

void UYTRegisterRemoteURLForVideoID(NSString * _Nullable vid, NSString * _Nullable url);
void UYTStoreResolvedURLs(NSString * _Nullable vid, NSString * _Nullable muxedURL, NSString * _Nullable audioURL, NSString * _Nullable videoURL);
#import "UYTLog.h"
#import "YTSigDecipher.h"

@interface UYTStreamFormat : NSObject
@property (nonatomic, copy) NSString *url;
@property (nonatomic, assign) NSInteger itag;
@property (nonatomic, copy) NSString *mimeType;
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

static int UYTLastGoodClient = 2;

+ (NSDictionary *)clientContextForIndex:(int)idx {
    if (idx <= 0) {
        return @{@"context": @{@"client": @{
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
        return @{@"context": @{@"client": @{
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
    return @{@"context": @{@"client": @{
        @"clientName": @"IOS",
        @"clientVersion": UYTAppVersion(),
        @"deviceMake": @"Apple",
        @"deviceModel": UYTIOSModel(),
        @"osName": @"iPhone",
        @"osVersion": UYTIOSVersion(),
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
    return [NSString stringWithFormat:@"com.google.ios.youtube/%@ (%@; U; CPU iPhone OS %@ like Mac OS X; en_US)",
            UYTAppVersion(), UYTIOSModel(), [UYTIOSVersion() stringByReplacingOccurrencesOfString:@"." withString:@"_"]];
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
                        NSString *cipher = f[@"signatureCipher"] ?: f[@"cipher"];
                        if (cipher) [ciphered addObject:f];
                    }
                }
            }
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
    (void)isShorts;
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

static void UYTSafeSetValue(id obj, NSString *key, id value) {
    if (!obj || !key.length) return;
    @try { [obj setValue:value forKey:key]; } @catch (NSException *e) {}
}

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

%hook DownloadItem

- (id)initWithVideoID:(id)videoID
             uYouItem:(id)uYouItem
           downloadID:(id)downloadID
                  url:(id)url
             filePath:(id)filePath
           cachedPath:(id)cachedPath
                 type:(int)type {

    @try {
        UYTDebugInfo(@"[UYTPipeline] DownloadItem init vid=%@ downloadID=%@ file=%@ cached=%@ title=%@",
                     videoID, downloadID, filePath, cachedPath, [uYouItem valueForKey:@"title"]);
    } @catch (NSException *e) {
        UYTDebugInfo(@"[UYTPipeline] DownloadItem init vid=%@ (detail lookup failed: %@)", videoID, e.reason ?: e);
    }

    return %orig(videoID, uYouItem, downloadID, url, filePath, cachedPath, type);
}

- (void)setRemoteURL:(NSURL *)url {
    NSString *vid = self.videoID ?: @"";
    if (url.absoluteString.length) UYTRegisterRemoteURLForVideoID(vid, url.absoluteString);
    NSString *working = UYTGetResolvedURL(vid);
    if (working.length) {
        UYTRegisterRemoteURLForVideoID(vid, working);
        NSURL *fixed = [NSURL URLWithString:working];
        if (fixed) {
            UYTDebugInfo(@"[UYTPipeline] swapped broken task URL -> cached innertube URL for %@", vid);
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

