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
// STATUS (post-21.14.4-3.0.5 field reports, issues #991/#992):
// The URL-swap hooks that previously lived here were REMOVED.
//   1. Field reports show downloads reach 100%, which proves uYou's own
//      stream extraction still works — swapping URLs solved nothing.
//   2. Swapping a MUXED format URL into uYou's adaptive-video slot corrupted
//      the merge input (muxed content re-merged with separate audio).
//   3. Both files hooking getLinksLocallyPlayerItem: created a double-swizzle
//      chain with an artificial 1.5s main-thread delay of uYou's extraction.
// Stall recovery now lives entirely in Sources/uYouPatches.xm (watchdogs).
// UYTDownloadPipeline below is retained for a future full pipeline bypass
// (replacing %orig outright) once device logs confirm where uYou stalls.
