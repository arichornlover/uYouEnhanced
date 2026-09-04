// DownloadPipeline.xm — stream fetcher for YouTube 21.14.4+ (iOS 16–26).
// Pre-fetches working stream URLs via innertube, then swaps them into uYou's
// native download flow so progress bars, DB, and queue all work natively.
// Conversion/remux handled by FFmpegKitNext (UYTMediaKit).
// SABR primary for YouTube 21.29+ (-1002) via vendored YouMod SABRDownload.x
// (UYTSABR.xm — credit: @Tonwalter888 / YouMod 2.0.0).
// Innertube fallback for older versions.

#import "DownloadPipeline.h"
#import "UYTSABR.h"
#import <UIKit/UIKit.h>

static NSString * const UYTInnertubeURL = @"https://www.youtube.com/youtubei/v1/player?key=AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc";

// Client versions are deliberately DOWNGRADED from the app's own version.
// Sending the current app version (21.14.4) to innertube triggers 403
// "forbidden" because the server applies stricter PO-token / bot checks to
// newer clients. Older, well-known client versions (19.45.x era) are served
// direct stream URLs without the extra server-side checks, so downloads work.
// Each client type gets its own realistic version string.
static NSString * const UYTClientVersionIOS        = @"19.45.1";   // iOS app
static NSString * const UYTClientVersionIOSMusic   = @"6.33.1";    // YouTube Music iOS
static NSString * const UYTClientVersionIOSCreator = @"19.45.4";   // YouTube Studio iOS
static NSString * const UYTClientVersionWeb        = @"2.20250825.01.00"; // WEB

// YouTube 21.29+ is the version where SABR became mandatory (no direct stream URLs)
static NSString * const UYTSABRMinimumVersion = @"21.29.0";

static BOOL UYTIsYouTubeVersion2129OrNewer(void) {
    Class versionUtils = %c(YTVersionUtils);
    if (!versionUtils) return NO;
    NSString *appVersion = [versionUtils performSelector:@selector(appVersion)];
    if (!appVersion) return NO;
    return [appVersion compare:UYTSABRMinimumVersion options:NSNumericSearch] != NSOrderedAscending;
}

@implementation UYTStreamFormat
@end

@implementation UYTDownloadPipeline

// Build an innertube request body for the given client type. IOS is preferred
// but may get 403'd by PO-token enforcement; IOS_MUSIC is the fallback.
+ (NSDictionary *)clientContextForClient:(NSString *)clientName
                              osVersion:(NSString *)osVer
                          deviceModel:(NSString *)model {
    // Pick a realistic, downgraded client version per client type.
    NSString *clientVersion = UYTClientVersionIOS;
    if ([clientName isEqualToString:@"IOS_MUSIC"]) clientVersion = UYTClientVersionIOSMusic;
    else if ([clientName isEqualToString:@"IOS_CREATOR"]) clientVersion = UYTClientVersionIOSCreator;
    else if ([clientName isEqualToString:@"WEB"]) clientVersion = UYTClientVersionWeb;

    return @{@"context": @{@"client": @{
        @"clientName": clientName,
        @"clientVersion": clientVersion,
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
    NSString *clientVersion = clientCtx[@"context"][@"client"][@"clientVersion"] ?: UYTClientVersionIOS;
    NSString *sysVer = [[UIDevice currentDevice].systemVersion stringByReplacingOccurrencesOfString:@"." withString:@"_"] ?: @"18_5_0";
    NSString *ua = [NSString stringWithFormat:@"com.google.ios.youtube/%@ (iPhone16,2; U; CPU iOS %@ like Mac OS X; en_US)",
                     clientVersion, sysVer];

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

// Fetch stream formats with version-aware strategy:
// - YouTube 21.29+: SABR primary (innertube returns -1002), innertube fallback
// - Older versions: innertube primary (IOS -> IOS_MUSIC -> IOS_CREATOR -> WEB), SABR fallback
// For Shorts, SABR only downloads audio (video downloaded via innertube if available)
+ (void)fetchFormatsForVideoID:(NSString *)videoID
                    isShorts:(BOOL)isShorts
                    completion:(void (^)(NSArray<UYTStreamFormat *> *, NSError *))completion {
    BOOL is2129OrNewer = UYTIsYouTubeVersion2129OrNewer();
    
    if (is2129OrNewer) {
        NSLog(@"[UYTPipeline] YouTube 21.29+ detected — trying SABR primary for %@", videoID);
        
        // Try SABR first for 21.29+. If SABR has a valid capture, it owns the
        // completion (success OR failure) — we must NOT fall through to the
        // innertube chain below, or completion would fire twice.
        if (UYTSABRHasValidCapture()) {
            // For Shorts, only use SABR for audio (skip video to avoid unwanted downloads)
            BOOL audioOnlyForShorts = isShorts;
            UYTSABRFallbackDownloadForVideoID(videoID, nil, audioOnlyForShorts, ^(BOOL success, NSString *errMsg) {
                if (success) {
                    // SABR produced elementary files; re-resolve URLs from stashed paths
                    NSString *vPath = [[NSUserDefaults standardUserDefaults] stringForKey:@"UYTSABRVideoPath"];
                    NSString *aPath = [[NSUserDefaults standardUserDefaults] stringForKey:@"UYTSABRAudioPath"];
                    if (vPath.length || aPath.length) {
                        // Stash as file:// URLs so DownloadItem swap can pick them up
                        NSString *vURL = vPath.length ? [NSURL fileURLWithPath:vPath].absoluteString : nil;
                        NSString *aURL = aPath.length ? [NSURL fileURLWithPath:aPath].absoluteString : nil;
                        UYTStoreResolvedURLs(videoID, vURL, aURL, vURL);
                        // Build synthetic formats so caller can proceed
                        NSMutableArray *sabrFormats = [NSMutableArray array];
                        if (vURL) {
                            UYTStreamFormat *vf = [[UYTStreamFormat alloc] init];
                            vf.url = vURL; vf.itag = 137; vf.mimeType = @"video/mp4"; vf.hasVideo = YES; vf.hasAudio = NO; vf.qualityLabel = @"1080p";
                            [sabrFormats addObject:vf];
                        }
                        if (aURL) {
                            UYTStreamFormat *af = [[UYTStreamFormat alloc] init];
                            af.url = aURL; af.itag = 140; af.mimeType = @"audio/mp4"; af.hasVideo = NO; af.hasAudio = YES;
                            [sabrFormats addObject:af];
                        }
                        completion(sabrFormats, nil);
                        return;
                    }
                }
                // SABR failed — fall back to innertube chain (single completion).
                NSLog(@"[UYTPipeline] SABR primary failed for %@: %@ — falling back to innertube", videoID, errMsg);
                [self runInnertubeFallbackChainForVideoID:videoID completion:completion];
            });
            // SABR owns the completion from here — do NOT fall through.
            return;
        } else {
            NSLog(@"[UYTPipeline] YouTube 21.29+ but no SABR capture yet — using innertube fallback");
        }
    }
    
    // Innertube fallback chain: IOS -> IOS_MUSIC -> IOS_CREATOR -> WEB
    [self runInnertubeFallbackChainForVideoID:videoID completion:completion];
}

// Innertube fallback chain: IOS -> IOS_MUSIC -> IOS_CREATOR -> WEB.
// Extracted so both the 21.29+ SABR-failure path and the older-version path
// share one implementation and guarantee exactly ONE completion call.
+ (void)runInnertubeFallbackChainForVideoID:(NSString *)videoID
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
                    NSLog(@"[UYTPipeline] all innertube clients failed for %@", videoID);
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

void UYTStoreResolvedURLs(NSString *vid, NSString *muxedURL, NSString *audioURL, NSString *videoURL) {
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

NSString *UYTResolvedURLForVideo(NSString *vid, BOOL audio) {
    NSDictionary *entry = UYTResolvedURLs[vid];
    return entry[audio ? @"audio" : @"muxed"] ?: nil;
}

NSString *UYTResolvedVideoURL(NSString *vid) {
    NSDictionary *entry = UYTResolvedURLs[vid];
    // Prefer the dedicated video-only stream for adaptive downloads.
    return entry[@"video"] ?: entry[@"muxed"];
}

void UYTMarkAudioOnly(NSString *vid, BOOL audioOnly) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (!UYTResolvedURLs) UYTResolvedURLs = [NSMutableDictionary dictionary];
    });
    if (!vid.length) return;
    NSMutableDictionary *entry = [UYTResolvedURLs[vid] mutableCopy] ?: [NSMutableDictionary dictionary];
    entry[@"audioOnly"] = @(audioOnly);
    UYTResolvedURLs[vid] = entry;
}

BOOL UYTIsAudioOnly(NSString *vid) {
    NSDictionary *entry = UYTResolvedURLs[vid];
    return [entry[@"audioOnly"] boolValue];
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

    // Shorts audio-only: even though uYou creates a video item (.mp4), the user
    // asked for audio only — force the audio stream so no video is downloaded.
    if (UYTIsAudioOnly(vid)) wantsAudio = YES;

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
// Ensure download data tasks always carry Origin + Referer + Cookie + ratebypass.
// Adapted from YouMod's Download.x (YouModApplyDownloadHeaders / YouModURLStringBypassingThrottle).
// Credit: @Tonwalter888 / YouMod — https://github.com/Tonwalter888/YouMod
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
        // Bypass throttling (YouMod: YouModURLStringBypassingThrottle)
        // Adds ratebypass=yes and strips &n= param if present.
        NSURL *url = mutableReq.URL;
        if (url) {
            NSURLComponents *comps = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
            if (comps) {
                NSMutableArray *filtered = [NSMutableArray array];
                BOOL hasRateBypass = NO;
                for (NSURLQueryItem *item in comps.queryItems ?: @[]) {
                    if ([item.name isEqualToString:@"n"]) continue; // strip throttling param
                    if ([item.name isEqualToString:@"ratebypass"]) hasRateBypass = YES;
                    [filtered addObject:item];
                }
                if (!hasRateBypass) {
                    [filtered addObject:[NSURLQueryItem queryItemWithName:@"ratebypass" value:@"yes"]];
                }
                comps.queryItems = filtered;
                NSURL *newURL = comps.URL;
                if (newURL) mutableReq.URL = newURL;
            }
        }
        // Ensure CPN for tracking (YouMod: YouModURLStringWithCPN)
        // Only if not already present — YTDataUtils may not be available on all versions
        if (![mutableReq.URL.absoluteString containsString:@"cpn="]) {
            @try {
                Class YTDataUtils = NSClassFromString(@"YTDataUtils");
                if (YTDataUtils && [YTDataUtils respondsToSelector:@selector(generateClientSideNonce)]) {
                    NSString *cpn = [YTDataUtils performSelector:@selector(generateClientSideNonce)];
                    if (cpn.length) {
                        NSURLComponents *comps = [NSURLComponents componentsWithURL:mutableReq.URL resolvingAgainstBaseURL:NO];
                        NSMutableArray *items = [comps.queryItems mutableCopy] ?: [NSMutableArray array];
                        [items addObject:[NSURLQueryItem queryItemWithName:@"cpn" value:cpn]];
                        comps.queryItems = items;
                        NSURL *newURL = comps.URL;
                        if (newURL) mutableReq.URL = newURL;
                    }
                }
            } @catch (NSException *e) {}
        }
        if (![mutableReq valueForHTTPHeaderField:@"Accept-Encoding"])
            [mutableReq setValue:@"identity" forHTTPHeaderField:@"Accept-Encoding"];
    }
    return %orig(mutableReq, completionHandler);
}
%end

// NOTE: Full SABR engine is in Sources/UYTSABR.xm (vendored from
// YouMod's SABRDownload.x — credit: @Tonwalter888 / YouMod 2.0.0).
// That file provides the capture hook (HAMDataLoadRequest) and the
// UMP/SABR download engine (YMSABR). This file only needs to trigger
// the fallback when innertube fails on YouTube 21.29+ (-1002).

%ctor {
    %init;
}
