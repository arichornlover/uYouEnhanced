// DownloadPipeline.xm — modern stream fetcher for YouTube 21.14.4+ (iOS 16–26).
// Design doc: Docs/DownloadPipeline.md
// Phase 1 scaffold: innertube player request + format selection.

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

+ (NSDictionary *)clientContext {
    return @{@"context": @{@"client": @{
        @"clientName": @"ANDROID",
        @"clientVersion": @"19.45.1",
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

+ (void)fetchFormatsForVideoID:(NSString *)videoID
                     isShorts:(BOOL)isShorts
                     progress:(void (^)(double frac, unsigned long long bytes))progress
                   completion:(void (^)(NSArray<UYTStreamFormat *> *, NSError *))completion {
    // isShorts: shorts share the ANDROID innertube client below (#1010:
    // IOS/19.45.1 → HTTP 400 for 21.29+), so shorts quality/video-data fetch
    // natively without uYou's broken legacy fallback. Included for parity with
    // the public header API; the request itself is identical either way.
    (void)isShorts;
    // ANDROID innertube client (#1010: IOS/19.45.1 → HTTP 400 for 21.29+).
    // Body and UA must be a matching pair or innertube 400s the request.
    NSMutableDictionary *body = [[self clientContext] mutableCopy];
    body[@"videoId"] = videoID;
    body[@"playbackContext"] = @{@"contentPlaybackContext": @{@"html5Preference": @"HTML5_PREF_WANTS"}};

    NSURL *url = [NSURL URLWithString:UYTInnertubeURL];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"com.google.android.youtube/19.09.39 (Linux; U; Android 14; SM-S928B Build/UP1A.231005.007; en_US)"
         forHTTPHeaderField:@"User-Agent"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    if (progress) progress(0.0, 0);
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            if (progress) progress(1.0, (unsigned long long)data.length);
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
            NSMutableArray *out = [NSMutableArray array];
            for (NSArray *list in @[streams ?: @[], muxed ?: @[]]) {
                for (NSDictionary *f in list) {
                    NSString *u = f[@"url"];
                    if (!u) continue; // signatureCipher fallback handled in phase 2
                    UYTStreamFormat *sf = [[UYTStreamFormat alloc] init];
                    sf.url = u;
                    sf.itag = [f[@"itag"] integerValue];
                    sf.mimeType = f[@"mimeType"];
                    sf.bitrate = [f[@"bitrate"] longLongValue];
                    sf.qualityLabel = f[@"qualityLabel"];
                    sf.hasVideo = [sf.mimeType hasPrefix:@"video"];
                    sf.hasAudio = [sf.mimeType hasPrefix:@"audio"] || ([sf.mimeType hasPrefix:@"video"] && ![f objectForKey:@"qualityLabel"]);
                    [out addObject:sf];
                }
            }
            completion(out, nil);
        }];
    [task resume];
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

// --- Wiring: fix uYou's stream URLs at the DownloadItem level ---------------

// Shared store: per-videoID muxed/audio/video working URLs + audio-only flag.
// Backs the public API declared in DownloadPipeline.h and consumed by
// uYouPatches.xm (DownloadsManager + DownloadItem hooks, Reels button).
static NSMutableDictionary<NSString *, NSMutableDictionary *> *UYTResolvedStore;

static NSMutableDictionary *UYTResolvedEntryFor(NSString *vid) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UYTResolvedStore = [NSMutableDictionary dictionary];
    });
    if (!vid.length) return nil;
    NSMutableDictionary *entry = UYTResolvedStore[vid];
    if (!entry) {
        entry = [NSMutableDictionary dictionary];
        UYTResolvedStore[vid] = entry;
    }
    return entry;
}

// A locally staged SABR file (Downloaded/<vid>.mp4 or .m4a) is the source of
// truth once a download finished on-device — the innertube http(s) URL becomes
// irrelevant then. createDownloadTask (uYouPatches) finalizes from file://.
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
        NSMutableDictionary *entry = UYTResolvedEntryFor(vid);
        if (!entry) return;
        // Overwrite as given — nil intentionally clears (e.g. audio-only drops
        // the video stream entirely).
        entry[@"muxed"] = muxedURL ?: [NSNull null];
        entry[@"audio"] = audioURL ?: [NSNull null];
        entry[@"video"] = videoURL ?: [NSNull null];
    } @catch (NSException *e) {}
}

NSString *UYTResolvedVideoURL(NSString *vid) {
    @try {
        if (!vid.length) return nil;
        NSString *staged = UYTStagedCanonicalPathFor(vid, @"mp4");
        if (staged.length) return UYTFileURLString(staged);
        NSDictionary *entry = UYTResolvedStore[vid];
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
            NSDictionary *entry = UYTResolvedStore[vid];
            if (entry) {
                NSString *audioURL = entry[@"audio"];
                if ([audioURL isKindOfClass:[NSString class]] && [audioURL length]) return audioURL;
            }
        }
        NSString *videoURL = UYTResolvedVideoURL(vid);
        if (videoURL.length) return videoURL;
        NSDictionary *entry = UYTResolvedStore[vid];
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
        NSMutableDictionary *entry = UYTResolvedEntryFor(vid);
        if (entry) entry[@"audioOnly"] = @(audioOnly);
    } @catch (NSException *e) {}
}

BOOL UYTIsAudioOnly(NSString *vid) {
    @try {
        NSDictionary *entry = UYTResolvedStore[vid];
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

// KVC helpers — real uYou item keys change across versions, so every write is
// individually guarded and unknown keys simply no-op.
static void UYTSafeSetValue(id obj, NSString *key, id value) {
    if (!obj || !key.length) return;
    @try { [obj setValue:value forKey:key]; } @catch (NSException *e) {}
}

// Drive uYou's own DownloadItem list-row UI off the live (fraction, bytes)
// signal from the new pipeline / SABR.
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

// Write accurate final values (100% + real file size) on a completed item.
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

%hook DownloadItem

- (id)initWithVideoID:(id)videoID
             uYouItem:(id)uYouItem
           downloadID:(id)downloadID
                  url:(id)url
             filePath:(id)filePath
           cachedPath:(id)cachedPath
                 type:(int)type {

    NSLog(@"[UYTPipeline] DownloadItem init:");
    NSLog(@"[UYTPipeline] videoID = %@", videoID);
    NSLog(@"[UYTPipeline] downloadID = %@", downloadID);
    NSLog(@"[UYTPipeline] filePath = %@", filePath);
    NSLog(@"[UYTPipeline] cachedPath = %@", cachedPath);

    @try {
        NSLog(@"[UYTPipeline] title = %@", [uYouItem valueForKey:@"title"]);
        NSLog(@"[UYTPipeline] uYouItem.filePath = %@", [uYouItem valueForKey:@"filePath"]);
    } @catch (NSException *e) {
        NSLog(@"[UYTPipeline] diagnostic failed: %@", e);
    }

    return %orig(videoID, uYouItem, downloadID, url, filePath, cachedPath, type);
}

- (void)setRemoteURL:(NSURL *)url {
    NSString *vid = self.videoID ?: @"";
    NSString *working = UYTGetResolvedURL(vid);
    if (working.length) {
        NSURL *fixed = [NSURL URLWithString:working];
        if (fixed) {
            NSLog(@"[UYTPipeline] swapped broken URL -> working innertube URL for %@", vid);
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
