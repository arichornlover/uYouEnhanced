// DownloadPipeline.xm — stream fetcher for YouTube 21.14.4+ (iOS 16–26).
// Pre-fetches working stream URLs via innertube, then swaps them into uYou's
// native download flow so progress bars, DB, and queue all work natively.
// Conversion/remux handled by FFmpegKitNext (UYTMediaKit).

#import <Foundation/Foundation.h>

static NSString * const UYTInnertubeURL = @"https://www.youtube.com/youtubei/v1/player?key=AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc";
static NSString * const UYTClientVersion = @"21.14.4";

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
+ (UYTStreamFormat *)bestMuxedFormat:(NSArray<UYTStreamFormat *> *)formats;
+ (UYTStreamFormat *)bestAudioFormat:(NSArray<UYTStreamFormat *> *)formats;
@end

@implementation UYTDownloadPipeline

// Build an innertube request body for the given client type. IOS is preferred
// but may get 403'd by PO-token enforcement; IOS_MUSIC is the fallback.
+ (NSDictionary *)clientContextForClient:(NSString *)clientName
                              osVersion:(NSString *)osVer
                          deviceModel:(NSString *)model {
    return @{@"context": @{@"client": @{
        @"clientName": clientName,
        @"clientVersion": UYTClientVersion,
        @"deviceMake": @"Apple",
        @"deviceModel": model ?: @"iPhone16,2",
        @"osName": @"iOS",
        @"osVersion": osVer ?: @"18.5.0.22F76",
        @"hl": @"en",
        @"timeZone": @"UTC",
        @"utcOffsetMinutes": @0
    }},
    @"contentCheckOk": @YES,
    @"racyCheckOk": @YES};
}

+ (NSDictionary *)clientContext {
    return [self clientContextForClient:@"IOS" osVersion:nil deviceModel:nil];
}

// Internal: perform a single innertube fetch with the given client context.
+ (void)fetchWithClient:(NSDictionary *)clientCtx
              videoID:(NSString *)videoID
           completion:(void (^)(NSArray<UYTStreamFormat *> *, NSError *))completion {
    NSMutableDictionary *body = [clientCtx mutableCopy];
    body[@"videoId"] = videoID;
    body[@"playbackContext"] = @{@"contentPlaybackContext": @{@"html5Preference": @"HTML5_PREF_WANTS"}};

    NSString *clientName = clientCtx[@"context"][@"client"][@"clientName"] ?: @"IOS";
    NSString *ua = [NSString stringWithFormat:@"com.google.ios.youtube/%@ (iPhone16,2; U; CPU iOS 18_5_0 like Mac OS X;)",
                     UYTClientVersion];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:UYTInnertubeURL]];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:ua forHTTPHeaderField:@"User-Agent"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)resp;
            if (err || !data || http.statusCode == 403) {
                NSString *msg = [NSString stringWithFormat:@"client=%@ status=%ld",
                                 clientName, (long)http.statusCode];
                completion(@[], [NSError errorWithDomain:@"UYTDownload" code:http.statusCode
                        userInfo:@{NSLocalizedDescriptionKey: msg}]);
                return;
            }
            NSError *jsonErr = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
            if (!json) { completion(@[], jsonErr); return; }

            // Check for innertube-level errors (playability status).
            NSString *status = json[@"playabilityStatus"][@"status"];
            if (status && ![status isEqualToString:@"OK"]) {
                NSString *reason = json[@"playabilityStatus"][@"reason"] ?: status;
                completion(@[], [NSError errorWithDomain:@"UYTDownload" code:-2
                        userInfo:@{NSLocalizedDescriptionKey: reason}]);
                return;
            }

            NSArray *streams = json[@"streamingData"][@"adaptiveFormats"];
            NSArray *muxed = json[@"streamingData"][@"formats"];
            NSMutableArray *out = [NSMutableArray array];
            for (NSArray *list in @[streams ?: @[], muxed ?: @[]]) {
                for (NSDictionary *f in list) {
                    NSString *u = f[@"url"];
                    if (!u) continue;
                    UYTStreamFormat *sf = [[UYTStreamFormat alloc] init];
                    sf.url = u;
                    sf.itag = [f[@"itag"] integerValue];
                    sf.mimeType = f[@"mimeType"];
                    sf.bitrate = [f[@"bitrate"] longLongValue];
                    sf.qualityLabel = f[@"qualityLabel"];
                    sf.hasVideo = [sf.mimeType hasPrefix:@"video"];
                    sf.hasAudio = [sf.mimeType hasPrefix:@"audio"] ||
                                  ([sf.mimeType hasPrefix:@"video"] && ![f objectForKey:@"qualityLabel"]);
                    [out addObject:sf];
                }
            }
            completion(out, nil);
        }];
    [task resume];
}

// Fetch stream formats with automatic fallback: IOS → IOS_MUSIC. The IOS
// client may get 403'd by PO-token enforcement; IOS_MUSIC is more permissive.
+ (void)fetchFormatsForVideoID:(NSString *)videoID
                    completion:(void (^)(NSArray<UYTStreamFormat *> *, NSError *))completion {
    NSDictionary *iosCtx = [self clientContextForClient:@"IOS" osVersion:nil deviceModel:nil];
    [self fetchWithClient:iosCtx videoID:videoID completion:^(NSArray<UYTStreamFormat *> *fmts, NSError *err) {
        if (fmts.count > 0) { completion(fmts, nil); return; }

        // IOS failed — try IOS_MUSIC as fallback.
        NSLog(@"[UYTPipeline] IOS client failed (%@), trying IOS_MUSIC", err.localizedDescription);
        NSDictionary *musicCtx = [self clientContextForClient:@"IOS_MUSIC" osVersion:@"18.5.0" deviceModel:@"iPhone16,2"];
        [self fetchWithClient:musicCtx videoID:videoID completion:^(NSArray<UYTStreamFormat *> *fmts2, NSError *err2) {
            if (fmts2.count > 0) { completion(fmts2, nil); return; }

            // Both failed — try WEB client as last resort.
            NSLog(@"[UYTPipeline] IOS_MUSIC failed (%@), trying WEB", err2.localizedDescription);
            NSMutableDictionary *webCtx = [[self clientContextForClient:@"WEB" osVersion:@"2.20250825.01.00" deviceModel:nil] mutableCopy];
            webCtx[@"context"][@"client"][@"hl"] = @"en";
            [self fetchWithClient:webCtx videoID:videoID completion:^(NSArray<UYTStreamFormat *> *fmts3, NSError *err3) {
                if (fmts3.count > 0) { completion(fmts3, nil); return; }
                NSLog(@"[UYTPipeline] all clients failed for %@", videoID);
                completion(@[], err3 ?: err2 ?: err);
            }];
        }];
    }];
}

+ (UYTStreamFormat *)bestMuxedFormat:(NSArray<UYTStreamFormat *> *)formats {
    UYTStreamFormat *best = nil;
    for (UYTStreamFormat *f in formats)
        if (f.hasVideo && f.hasAudio && (!best || f.bitrate > best.bitrate)) best = f;
    return best;
}

+ (UYTStreamFormat *)bestAudioFormat:(NSArray<UYTStreamFormat *> *)formats {
    // Prefer m4a, but fall back to the best webm track — modern YouTube serves
    // adaptive audio mostly as webm, and uYouPatches converts it afterwards.
    UYTStreamFormat *bestM4a = nil;
    UYTStreamFormat *bestOther = nil;
    for (UYTStreamFormat *f in formats) {
        if (!f.hasAudio || f.hasVideo) continue;
        if ([f.mimeType containsString:@"mp4"]) {
            if (!bestM4a || f.bitrate > bestM4a.bitrate) bestM4a = f;
        } else {
            if (!bestOther || f.bitrate > bestOther.bitrate) bestOther = f;
        }
    }
    return bestM4a ?: bestOther;
}

@end

// --- Wiring ------------------------------------------------------------------
// The prefetch + URL swap below makes downloads start at all on YouTube 21.x:
// uYou's own extraction returns dead URLs.

// Resolved innertube URLs keyed by videoID, split by stream type so audio
// downloads get a real audio URL instead of a throttled one.
static NSMutableDictionary<NSString *, NSDictionary *> *UYTResolvedURLs;

static void UYTStoreResolvedURLs(NSString *vid, NSString *muxedURL, NSString *audioURL) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UYTResolvedURLs = [NSMutableDictionary dictionary];
    });
    if (!vid.length) return;
    NSMutableDictionary *entry = [UYTResolvedURLs[vid] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (muxedURL.length) entry[@"muxed"] = muxedURL;
    if (audioURL.length) entry[@"audio"] = audioURL;
    UYTResolvedURLs[vid] = entry;
}

static NSString *UYTResolvedURLForVideo(NSString *vid, BOOL audio) {
    NSDictionary *entry = UYTResolvedURLs[vid];
    return entry[audio ? @"audio" : @"muxed"] ?: nil;
}

@interface DownloadsManager : NSObject
+ (instancetype)sharedInstance;
@end

@interface DownloadItem : NSObject
@property (nonatomic, strong) NSString *videoID;
- (void)setRemoteURL:(NSURL *)url;
@end

%hook DownloadsManager
- (void)getLinksLocallyPlayerItem:(id)item videoID:(id)videoID sourceView:(id)sourceView isShorts:(BOOL)isShorts {
    NSString *vid = [NSString stringWithFormat:@"%@", videoID];

    // Pre-fetch working stream URLs via innertube BEFORE %orig runs.
    // The completion handler chains %orig directly — no delay, no race condition.
    [UYTDownloadPipeline fetchFormatsForVideoID:vid completion:^(NSArray<UYTStreamFormat *> *formats, NSError *error) {
        if (error || formats.count == 0) {
            NSLog(@"[UYTPipeline] pre-fetch failed for %@: %@", vid, error.localizedDescription);
        } else {
            UYTStreamFormat *muxed = [UYTDownloadPipeline bestMuxedFormat:formats];
            UYTStreamFormat *audio = [UYTDownloadPipeline bestAudioFormat:formats];
            UYTStoreResolvedURLs(vid, muxed.url, audio.url);
            NSLog(@"[UYTPipeline] cached URLs for %@ (muxed=%ld, audio=%ld)",
                  vid, (long)muxed.itag, (long)audio.itag);
        }

        // Let uYou's native flow proceed. Our DownloadItem hook below will
        // swap any broken URL with our cached working one.
        dispatch_async(dispatch_get_main_queue(), ^{
            %orig;
        });
    }];
}
%end

// Swap broken extraction URLs with working innertube ones. Audio items get the
// resolved audio stream — uYou's own audio URLs are often throttled (#161).
%hook DownloadItem
- (void)setRemoteURL:(NSURL *)url {
    NSString *vid = self.videoID ?: @"";

    BOOL wantsAudio = NO;
    @try {
        NSString *path = nil;
        if ([self respondsToSelector:@selector(filePath)]) path = [self performSelector:@selector(filePath)];
        if (path.length == 0 && [self respondsToSelector:@selector(cachedPath)]) path = [self performSelector:@selector(cachedPath)];
        NSString *ext = path.pathExtension.lowercaseString;
        wantsAudio = [ext isEqualToString:@"m4a"] || [ext isEqualToString:@"mp3"];
    } @catch (NSException *e) {}

    NSString *working = UYTResolvedURLForVideo(vid, wantsAudio);
    if (working.length == 0 && wantsAudio) {
        // No audio stream resolved — fall back to the muxed URL like before.
        working = UYTResolvedURLForVideo(vid, NO);
    }
    if (working.length) {
        NSURL *fixed = [NSURL URLWithString:working];
        if (fixed) {
            NSLog(@"[UYTPipeline] swapped broken URL -> %@ innertube URL for %@",
                  wantsAudio ? @"audio" : @"muxed", vid);
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
