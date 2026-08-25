// DownloadPipeline.xm — modern stream fetcher for YouTube 21.14.4+ (iOS 16–26).
// Design doc: Docs/DownloadPipeline.md
// Phase 1 scaffold: innertube player request + format selection.

#import <Foundation/Foundation.h>

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

    // Fetch fresh stream URLs via innertube before %orig runs.
    [UYTDownloadPipeline fetchFormatsForVideoID:vid completion:^(NSArray<UYTStreamFormat *> *formats, NSError *error) {
        if (error || formats.count == 0) {
            NSLog(@"[UYTPipeline] no formats for %@ (%@)", vid, error.localizedDescription);
            return;
        }
        UYTStreamFormat *muxed = [UYTDownloadPipeline bestMuxedFormat:formats];
        UYTStreamFormat *audio = [UYTDownloadPipeline bestAudioFormat:formats];
        UYTStoreResolvedURLs(vid, muxed.url, audio.url);
        NSLog(@"[UYTPipeline] cached URLs for %@ (muxed itag=%ld, audio itag=%ld)",
              vid, (long)muxed.itag, (long)audio.itag);
    }];

    // Give the fetch a moment, then let %orig proceed.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        %orig;
    });
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
