// DownloadPipeline.xm — stream fetcher for YouTube 21.14.4+ (iOS 16–26).
// Pre-fetches working stream URLs via innertube, then swaps them into uYou's
// native download flow so progress bars, DB, and queue all work natively.
// Conversion/remux handled by FFmpegKitNext (UYTMediaKit).

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

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

// Helper: gather YouTube cookies from the shared jar so innertube requests
// carry the session's auth / VISITOR_INFO / __Secure-* values.
static NSString *UYTYouTubeCookiesString(void) {
    NSMutableArray *cookieStrings = [NSMutableArray array];
    for (NSHTTPCookie *cookie in [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies]) {
        if ([cookie.domain containsString:@"youtube.com"]) {
            [cookieStrings addObject:[NSString stringWithFormat:@"%@=%@",
                                      cookie.name, cookie.value]];
        }
    }
    return [cookieStrings componentsJoinedByString:@"; "];
}

// Internal: perform a single innertube fetch with the given client context.
+ (void)fetchWithClient:(NSDictionary *)clientCtx
              videoID:(NSString *)videoID
           completion:(void (^)(NSArray<UYTStreamFormat *> *, NSError *))completion {
    NSMutableDictionary *body = [clientCtx mutableCopy];
    body[@"videoId"] = videoID;
    body[@"playbackContext"] = @{@"contentPlaybackContext": @{@"html5Preference": @"HTML5_PREF_WANTS"}};

    NSString *clientName = clientCtx[@"context"][@"client"][@"clientName"] ?: @"IOS";
    NSString *sysVer = [[UIDevice currentDevice].systemVersion stringByReplacingOccurrencesOfString:@"." withString:@"_"] ?: @"18_5_0";
    NSString *ua = [NSString stringWithFormat:@"com.google.ios.youtube/%@ (iPhone16,2; U; CPU iOS %@ like Mac OS X; en_US)",
                     UYTClientVersion, sysVer];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:UYTInnertubeURL]];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:ua forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"https://www.youtube.com" forHTTPHeaderField:@"Origin"];
    [req setValue:@"https://www.youtube.com/" forHTTPHeaderField:@"Referer"];
    // Carry session cookies so the server recognises the logged-in user.
    NSString *cookies = UYTYouTubeCookiesString();
    if (cookies.length > 0) [req setValue:cookies forHTTPHeaderField:@"Cookie"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)resp;
            if (err || !data || http.statusCode == 403) {
                NSString *msg = [NSString stringWithFormat:@"client=%@ status=%ld",
                                 clientName, (long)http.statusCode];
                // Post notification for SABR fallback (includes videoID for capture correlation)
                if (http.statusCode == 403) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[NSNotificationCenter defaultCenter] postNotificationName:@"UYTPipeline403Error"
                                                                          object:nil
                                                                        userInfo:@{@"videoID": videoID, @"client": clientName}];
                    });
                }
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
            NSMutableSet *seenQualityLabels = [NSMutableSet set];
            
            // Process adaptive streams FIRST (separate video-only and audio-only).
            // These are preferred because they allow flexible quality selection.
            for (NSDictionary *f in streams ?: @[]) {
                NSString *u = f[@"url"];
                if (!u) continue;
                UYTStreamFormat *sf = [[UYTStreamFormat alloc] init];
                sf.url = u;
                sf.itag = [f[@"itag"] integerValue];
                sf.mimeType = f[@"mimeType"];
                sf.bitrate = [f[@"bitrate"] longLongValue];
                sf.qualityLabel = f[@"qualityLabel"];
                sf.hasVideo = [sf.mimeType hasPrefix:@"video"];
                sf.hasAudio = [sf.mimeType hasPrefix:@"audio"];
                // Track quality labels we've seen to deduplicate later
                if (sf.qualityLabel.length > 0) {
                    [seenQualityLabels addObject:sf.qualityLabel];
                }
                [out addObject:sf];
            }
            
            // Process muxed streams (they have both video+audio combined).
            // Only add muxed formats for quality labels NOT already covered by adaptive.
            // This prevents duplicate entries in the quality picker (e.g., 480p showing 3 times).
            for (NSDictionary *f in muxed ?: @[]) {
                NSString *u = f[@"url"];
                if (!u) continue;
                NSString *qualityLabel = f[@"qualityLabel"];
                // Skip if we already have an adaptive format for this quality
                if (qualityLabel.length > 0 && [seenQualityLabels containsObject:qualityLabel]) {
                    continue;
                }
                UYTStreamFormat *sf = [[UYTStreamFormat alloc] init];
                sf.url = u;
                sf.itag = [f[@"itag"] integerValue];
                sf.mimeType = f[@"mimeType"];
                sf.bitrate = [f[@"bitrate"] longLongValue];
                sf.qualityLabel = qualityLabel;
                // Muxed streams always have both video and audio.
                sf.hasVideo = YES;
                sf.hasAudio = YES;
                [out addObject:sf];
            }
            completion(out, nil);
        }];
    [task resume];
}

// Fetch stream formats with automatic fallback chain:
// IOS → IOS_MUSIC → IOS_CREATOR → WEB
// IOS may get 403'd by PO-token enforcement. IOS_MUSIC / IOS_CREATOR are
// more permissive; WEB is the last resort (no PO-token needed but streams
// may be lower quality).
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

            // IOS_MUSIC failed — try IOS_CREATOR (YouTube Creator iOS client).
            NSLog(@"[UYTPipeline] IOS_MUSIC failed (%@), trying IOS_CREATOR", err2.localizedDescription);
            NSDictionary *creatorCtx = [self clientContextForClient:@"IOS_CREATOR" osVersion:@"19.45.4" deviceModel:@"iPhone16,2"];
            [self fetchWithClient:creatorCtx videoID:videoID completion:^(NSArray<UYTStreamFormat *> *fmts3, NSError *err3) {
                if (fmts3.count > 0) { completion(fmts3, nil); return; }

                // IOS_CREATOR failed — try WEB client as last resort.
                NSLog(@"[UYTPipeline] IOS_CREATOR failed (%@), trying WEB", err3.localizedDescription);
                NSMutableDictionary *webCtx = [[self clientContextForClient:@"WEB" osVersion:@"2.20250825.01.00" deviceModel:nil] mutableCopy];
                webCtx[@"context"][@"client"][@"hl"] = @"en";
                [self fetchWithClient:webCtx videoID:videoID completion:^(NSArray<UYTStreamFormat *> *fmts4, NSError *err4) {
                    if (fmts4.count > 0) { completion(fmts4, nil); return; }
                    NSLog(@"[UYTPipeline] all clients failed for %@", videoID);
                    completion(@[], err4 ?: err3 ?: err2 ?: err);
                }];
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

+ (UYTStreamFormat *)bestVideoFormat:(NSArray<UYTStreamFormat *> *)formats {
    // Adaptive video-only streams. Prefer mp4 (H.264) over webm (VP9/AV1)
    // so the merge step doesn't need to re-encode.
    UYTStreamFormat *bestMp4 = nil;
    UYTStreamFormat *bestOther = nil;
    for (UYTStreamFormat *f in formats) {
        if (!f.hasVideo || f.hasAudio) continue;
        if ([f.mimeType containsString:@"mp4"]) {
            if (!bestMp4 || f.bitrate > bestMp4.bitrate) bestMp4 = f;
        } else {
            if (!bestOther || f.bitrate > bestOther.bitrate) bestOther = f;
        }
    }
    return bestMp4 ?: bestOther;
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

static void UYTStoreResolvedURLs(NSString *vid, NSString *muxedURL, NSString *audioURL, NSString *videoURL) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UYTResolvedURLs = [NSMutableDictionary dictionary];
    });
    if (!vid.length) return;
    NSMutableDictionary *entry = [UYTResolvedURLs[vid] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (muxedURL.length) entry[@"muxed"] = muxedURL;
    if (audioURL.length) entry[@"audio"] = audioURL;
    if (videoURL.length) entry[@"video"] = videoURL;
    UYTResolvedURLs[vid] = entry;
}

static NSString *UYTResolvedURLForVideo(NSString *vid, BOOL audio) {
    NSDictionary *entry = UYTResolvedURLs[vid];
    return entry[audio ? @"audio" : @"muxed"] ?: nil;
}

static NSString *UYTResolvedVideoURL(NSString *vid) {
    NSDictionary *entry = UYTResolvedURLs[vid];
    // Prefer the dedicated video-only stream for adaptive downloads.
    return entry[@"video"] ?: entry[@"muxed"];
}

@interface DownloadsManager : NSObject
+ (instancetype)sharedInstance;
@end

@interface DownloadItem : NSObject
@property (nonatomic, strong) NSString *videoID;
- (void)setRemoteURL:(NSURL *)url;
@end

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

    NSString *working = nil;
    if (wantsAudio) {
        // Audio-only item (.m4a, .mp3) — use the dedicated audio stream.
        // Do NOT fall back to the muxed URL: for lower qualities (240p, 144p)
        // the muxed stream IS a video file, which would produce a black-screen
        // "audio" file. If no audio-only stream exists, we still use the muxed
        // URL but mark it for audio extraction in the merge phase.
        working = UYTResolvedURLForVideo(vid, YES);
        if (!working.length) {
            // No adaptive audio stream — check if muxed exists for audio extraction
            working = UYTResolvedURLForVideo(vid, NO);
            if (working.length) {
                // Mark this item as needing audio extraction from muxed
                @try { [self setValue:@YES forKey:@"uYouNeedsAudioExtraction"]; } @catch (NSException *e) {}
                NSLog(@"[UYTPipeline] audio-only download for %@: using muxed URL with extraction flag", vid);
            }
        }
    } else {
        // Video item (.mp4) — use the dedicated video-only stream for
        // adaptive downloads. Falls back to muxed URL for lower-quality
        // muxed-only downloads.
        working = UYTResolvedVideoURL(vid);
    }

    if (working.length) {
        NSURL *fixed = [NSURL URLWithString:working];
        if (fixed) {
            NSLog(@"[UYTPipeline] swapped broken URL -> %@ URL for %@",
                  wantsAudio ? @"audio" : @"video", vid);
            %orig(fixed);
            return;
        }
    }
    %orig;
}
%end
// Ensure download data tasks always carry Origin + Referer + Cookie.
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    NSMutableURLRequest *mutableReq = [request isKindOfClass:[NSMutableURLRequest class]]
        ? (NSMutableURLRequest *)request
        : [request mutableCopy];
    NSString *host = mutableReq.URL.host ?: @"";
    if ([host containsString:@"googlevideo.com"]) {
        if (![mutableReq valueForHTTPHeaderField:@"Origin"])
            [mutableReq setValue:@"https://www.youtube.com" forHTTPHeaderField:@"Origin"];
        if (![mutableReq valueForHTTPHeaderField:@"Referer"])
            [mutableReq setValue:@"https://www.youtube.com/" forHTTPHeaderField:@"Referer"];
        // Carry session cookies for authenticated streams.
        if (![mutableReq valueForHTTPHeaderField:@"Cookie"]) {
            NSString *cookies = UYTYouTubeCookiesString();
            if (cookies.length > 0)
                [mutableReq setValue:cookies forHTTPHeaderField:@"Cookie"];
        }
    }
    return %orig(mutableReq, completionHandler);
}
%end

// SABR Download Fallback (@Tonwalter888 - YouMod 2.0.0's SABRDownload.x)
// When innertube API fails with 403 (PO-token enforcement), we fall back to
// capturing the app's own live, fully-signed `videoplayback` request and
// replaying it with our desired format selection. This bypasses PO-token
// checks because the request already carries the session's auth/PoToken.
// Credit: YouMod (https://github.com/Tonwalter888/YouMod) for the SABR
// on-device download approach and UMP protocol implementation.
//
// This is a simplified implementation focusing on the capture + replay concept.
// Full SABR protocol (UMP parsing, buffered ranges, etc.) is complex and
// version-sensitive; this captures the core idea: reuse the app's signed URL.

// UMP part type IDs (from LuanRT/googlevideo ump_part_id.proto)
typedef NS_ENUM(NSInteger, UYTUMPPartType) {
    UYTUMPPartMediaHeader      = 20,
    UYTUMPPartMedia            = 21,
    UYTUMPPartMediaEnd         = 22,
    UYTUMPPartFormatInit       = 42, // FORMAT_INITIALIZATION_METADATA
    UYTUMPPartRedirect         = 43, // SABR_REDIRECT (new URL)
    UYTUMPPartError            = 44, // SABR_ERROR
    UYTUMPPartReload           = 46, // RELOAD_PLAYER_RESPONSE
};

// Captured videoplayback request state
static NSURL *UYTCapturedVideoPlaybackURL = nil;
static NSData *UYTCapturedRequestBody = nil;
static NSDictionary *UYTCapturedRequestHeaders = nil;
static NSTimeInterval UYTCapturedURLExpiration = 0;
static dispatch_queue_t UYTSABRQueue = nil;

static dispatch_queue_t UYTGetSABRQueue(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UYTSABRQueue = dispatch_queue_create("com.uyouenhanced.sabr", DISPATCH_QUEUE_SERIAL);
    });
    return UYTSABRQueue;
}

// Extract expiration time from videoplayback URL
static NSTimeInterval UYTExtractExpirationFromURL(NSURL *url) {
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"expire"]) {
            return [item.value doubleValue];
        }
    }
    return 0;
}

// Check if captured URL is still valid
static BOOL UYTIsCapturedURLValid(void) {
    return UYTCapturedVideoPlaybackURL && UYTCapturedRequestBody && UYTCapturedRequestHeaders &&
           UYTCapturedURLExpiration > [NSDate date].timeIntervalSince1970 + 60; // 60s buffer
}

// Hook to capture the app's live signed videoplayback request
%hook HAMDataLoadRequest
- (NSURLRequest *)buildURLRequest {
    NSURLRequest *request = %orig;
    @try {
        NSString *host = request.URL.host ?: @"";
        NSString *path = request.URL.path ?: @"";
        if ([host containsString:@"googlevideo"] && [path containsString:@"videoplayback"] &&
            [request.HTTPMethod isEqualToString:@"POST"]) {
            NSData *body = request.HTTPBody;
            if (body && body.length > 0) {
                dispatch_async(UYTGetSABRQueue(), ^{
                    // Most-recent-wins: always track the latest videoplayback request
                    UYTCapturedVideoPlaybackURL = request.URL;
                    UYTCapturedRequestBody = [body copy];
                    UYTCapturedRequestHeaders = [request.allHTTPHeaderFields mutableCopy] ?: [NSMutableDictionary dictionary];
                    UYTCapturedURLExpiration = UYTExtractExpirationFromURL(request.URL);
                    NSLog(@"[UYTSABR] Captured signed videoplayback request (expires in %.0fs)",
                          UYTCapturedURLExpiration - [NSDate date].timeIntervalSince1970);
                });
            }
        }
    } @catch (NSException *e) {}
    return request;
}
%end

// SABR download entry point - called when innertube fails
// This is a simplified version; full SABR requires UMP protocol handling
static void UYTAttemptSABRDownload(NSString *videoID, NSInteger videoItag, NSInteger audioItag,
                                   void (^completion)(NSURL *videoURL, NSURL *audioURL, NSError *error)) {
    dispatch_async(UYTGetSABRQueue(), ^{
        if (!UYTIsCapturedURLValid()) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, nil, [NSError errorWithDomain:@"UYTSABR" code:-1
                    userInfo:@{NSLocalizedDescriptionKey: @"No valid captured videoplayback request. Play the video first."}]); 
            });
            return;
        }

        // Build modified request body with our desired format selection
        // This is a simplified version - full implementation requires UMP protobuf parsing
        // like YouMod's SABRDownload.x does. For now, we modify the itag parameters directly.
        
        NSMutableData *modifiedBody = [UYTCapturedRequestBody mutableCopy];
        NSString *bodyStr = [[NSString alloc] initWithData:modifiedBody encoding:NSUTF8StringEncoding];
        
        // Try to replace itag parameters in the request body
        // The body is typically form-encoded or protobuf; this is a best-effort approach
        if (bodyStr && bodyStr.length > 0) {
            // Replace video itag (typically 'itag' or 'v_itag' parameter)
            bodyStr = [bodyStr stringByReplacingOccurrencesOfString:@"itag=" withString:[NSString stringWithFormat:@"itag=%ld", (long)videoItag]];
            // Note: This is simplified. Real SABR requires proper UMP FormatId encoding.
        }
        
        NSData *newBodyData = [bodyStr dataUsingEncoding:NSUTF8StringEncoding];
        if (newBodyData) modifiedBody = [newBodyData mutableCopy];

        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:UYTCapturedVideoPlaybackURL];
        req.HTTPMethod = @"POST";
        req.HTTPBody = modifiedBody;
        [UYTCapturedRequestHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
            if (!([k caseInsensitiveCompare:@"Content-Encoding"] == NSOrderedSame)) { // Don't copy Brotli encoding
                [req setValue:v forHTTPHeaderField:k];
            }
        }];
        // Ensure no Content-Encoding (we send uncompressed)
        [req setValue:@"" forHTTPHeaderField:@"Content-Encoding"];

        NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
        [[session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            dispatch_async(UYTGetSABRQueue(), ^{
                if (err || !data) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(nil, nil, err ?: [NSError errorWithDomain:@"UYTSABR" code:-2
                            userInfo:@{NSLocalizedDescriptionKey: @"SABR download request failed"}]); 
                    });
                    return;
                }
                NSHTTPURLResponse *http = (NSHTTPURLResponse *)resp;
                if (http.statusCode != 200 || !data.length) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(nil, nil, [NSError errorWithDomain:@"UYTSABR" code:http.statusCode
                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld", (long)http.statusCode]}]); 
                    });
                    return;
                }

                // Parse UMP response - simplified: just save the raw data
                // Full implementation would parse UMP parts and write media segments
                // For now, we save the response as-is and let the existing pipeline handle it
                NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
                NSString *sabrDir = [docs stringByAppendingPathComponent:@"uYouDownloads/SABR"];
                [[NSFileManager defaultManager] createDirectoryAtPath:sabrDir withIntermediateDirectories:YES attributes:nil error:nil];
                
                // This is a placeholder - real SABR implementation needed
                // For now, we return an error to fall back to other methods
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, nil, [NSError errorWithDomain:@"UYTSABR" code:-3
                        userInfo:@{NSLocalizedDescriptionKey: @"SABR download not fully implemented - requires UMP parsing (see YouMod SABRDownload.x)"}]); 
                });
            });
        }] resume];
    });
}
    %init;
    [[NSNotificationCenter defaultCenter] addObserverForName:@"UYTPipeline403Error" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        NSString *vid = note.userInfo[@"videoID"];
        NSInteger videoItag = [note.userInfo[@"videoItag"] integerValue];
        NSInteger audioItag = [note.userInfo[@"audioItag"] integerValue];
        if (vid.length > 0 && videoItag > 0 && audioItag > 0) {
            NSLog(@"[UYTSABR] Pipeline 403 for %@, attempting SABR fallback", vid);
            UYTAttemptSABRDownload(vid, videoItag, audioItag, ^(NSURL *videoURL, NSURL *audioURL, NSError *error) {
                if (!error && videoURL && audioURL) {
                    NSLog(@"[UYTSABR] SABR download succeeded for %@", vid);
                    // TODO: Integrate with uYou's download queue
                } else {
                    NSLog(@"[UYTSABR] SABR fallback failed: %@", error.localizedDescription);
                }
            });
        }
    }];
}
