
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "DownloadPipeline.h"
#import "UYTFileSize.h"
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
static NSString * const UYTFallbackAppVersion = @"20.10.4"; // never reuse as an ANDROID clientVersion (HTTP 400 -> -1002, #1010)

static NSString *UYTAppVersion(void) {
    static NSString *cached = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *v = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        if (!v.length) v = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
        cached = v.length ? v : UYTFallbackAppVersion;
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

#import "UYTLog.h"
#import "YTSigDecipher.h"

@implementation UYTStreamFormat
@end

// hasVideo/hasAudio come from WHICH LIST the format arrived in, not a
// qualityLabel probe (raw adaptiveFormats have none - the old test misflagged
// video-only formats, so the audio slot could get the whole video).
static UYTStreamFormat *UYTStreamFormatFromDict(NSDictionary *f, NSString *url, BOOL fromMuxedList) {
    UYTStreamFormat *sf = [[UYTStreamFormat alloc] init];
    sf.url = url;
    sf.itag = [f[@"itag"] integerValue];
    sf.mimeType = f[@"mimeType"];
    sf.bitrate = [f[@"bitrate"] longLongValue];
    sf.qualityLabel = f[@"qualityLabel"];
    NSString *m = (sf.mimeType ?: @"").lowercaseString;
    if (fromMuxedList) {
        sf.hasVideo = YES;
        sf.hasAudio = YES;
    } else if ([m hasPrefix:@"audio/"]) {
        sf.hasVideo = NO;
        sf.hasAudio = YES;
    } else {
        sf.hasVideo = YES;
        sf.hasAudio = NO;
    }
    return sf;
}

static NSInteger UYTFormatContainerRank(UYTStreamFormat *f);
static NSInteger UYTFormatCodecRank(UYTStreamFormat *f);
static BOOL UYTFormatIsBetter(UYTStreamFormat *candidate, UYTStreamFormat *current);
static NSString *UYTFormatDesc(UYTStreamFormat *f);

@implementation UYTDownloadPipeline

// ============================================================================
// Innertube client table
// ============================================================================
// One record per client keeps clientName + clientVersion + User-Agent a
// self-consistent triple (a mismatched triple answers HTTP 400).

static NSArray<NSDictionary *> *UYTClientProfiles(void) {
    static NSArray *profiles = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *iosVersion = UYTAppVersion();
        NSString *iosUA = [NSString stringWithFormat:
            @"com.google.ios.youtube/%@ (%@; U; CPU iPhone OS %@ like Mac OS X; en_US)",
            iosVersion, UYTIOSModel(),
            [UYTIOSVersion() stringByReplacingOccurrencesOfString:@"." withString:@"_"]];

        // Ordered best -> worst. Rotation walks this list in this order.
        NSArray *rows = @[
            // 0 - the running app's own identity. Only client guaranteed to
            //     match the installed binary, so it goes first.
            @{@"name": @"IOS", @"version": iosVersion, @"ua": iosUA,
              @"make": @"Apple", @"model": UYTIOSModel(),
              @"osName": @"iPhone", @"osVersion": UYTIOSVersion()},

            // 1 - current Android release. Version MUST be an Android version.
            @{@"name": @"ANDROID", @"version": @"20.10.38",
              @"ua": @"com.google.android.youtube/20.10.38 (Linux; U; Android 15; SM-S928B Build/BP1A.250305.009; en_US)",
              @"make": @"samsung", @"model": @"SM-S928B",
              @"osName": @"Android", @"osVersion": @"15"},

            // 2 - older Android release, throttled on a different schedule.
            @{@"name": @"ANDROID", @"version": @"19.09.39",
              @"ua": @"com.google.android.youtube/19.09.39 (Linux; U; Android 14; SM-S928B Build/UP1A.231005.007; en_US)",
              @"make": @"samsung", @"model": @"SM-S928B",
              @"osName": @"Android", @"osVersion": @"14"},

            // 3 - Android VR is a separate client with its own format ladder,
            //     so it still works when ANDROID starts returning 400.
            @{@"name": @"ANDROID_VR", @"version": @"1.60.19",
              @"ua": @"com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12; SM-G991B Build/SQ3A.220605.009.A1; en_US)",
              @"make": @"samsung", @"model": @"SM-G991B",
              @"osName": @"Android", @"osVersion": @"12"},

            // 4 - Android test harness. Rarely rate-limited: a good backstop
            //     when every real client has started 400ing.
            @{@"name": @"ANDROID_TESTSUITE", @"version": @"1.9",
              @"ua": @"com.google.android.youtube/1.9 (Linux; U; Android 14; Pixel 7 Build/UQ1A.240105.004; en_US)",
              @"make": @"Google", @"model": @"Pixel 7",
              @"osName": @"Android", @"osVersion": @"14"},

            // 5 - TV web player. hls/m3u8 heavy, so it still returns something
            //     useful when the mobile clients are gated behind a PO token.
            @{@"name": @"TVHTML5_SIMPLY_EMBEDDED_PLAYER", @"version": @"2.0",
              @"ua": @"Mozilla/5.0 (PlayStation; PlayStation 4/12.00) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15",
              @"make": @"Sony", @"model": @"PlayStation 4",
              @"osName": @"PlayStation", @"osVersion": @"12.00"},

            // 6 - mobile web. Most likely to need a PO token, hence last.
            @{@"name": @"MWEB", @"version": iosVersion, @"ua": iosUA,
              @"make": @"Apple", @"model": UYTIOSModel(),
              @"osName": @"iPhone", @"osVersion": UYTIOSVersion()},
        ];

        NSMutableArray *built = [NSMutableArray arrayWithCapacity:rows.count];
        for (NSDictionary *r in rows) {
            [built addObject:@{
                @"name": r[@"name"],
                @"version": r[@"version"],
                @"userAgent": r[@"ua"],
                @"context": @{
                    @"context": @{@"client": @{
                        @"clientName": r[@"name"],
                        @"clientVersion": r[@"version"],
                        @"deviceMake": r[@"make"],
                        @"deviceModel": r[@"model"],
                        @"osName": r[@"osName"],
                        @"osVersion": r[@"osVersion"],
                        @"hl": @"en",
                        @"timeZone": @"UTC",
                        @"utcOffsetMinutes": @0
                    }},
                    @"contentCheckOk": @YES,
                    @"racyCheckOk": @YES
                }
            }];
        }
        profiles = built;
    });
    return profiles;
}

// ============================================================================
// Per-client health
// ============================================================================
// A 400/403 kills a client for a while; remember and skip it so retries rotate
// onto a working client instead of re-paying the same doomed round-trip.

static const NSTimeInterval UYTClientCooldown = 120.0;

static NSMutableDictionary<NSNumber *, NSNumber *> *UYTClientStrikes; // idx -> strikes
static NSMutableDictionary<NSNumber *, NSDate *> *UYTClientRetryAfter; // idx -> date
static NSObject *UYTClientHealthLock;
static int UYTLastGoodClient = 0;

static void UYTEnsureClientHealth(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UYTClientStrikes = [NSMutableDictionary dictionary];
        UYTClientRetryAfter = [NSMutableDictionary dictionary];
        UYTClientHealthLock = [NSObject new];
    });
}

static void UYTPenalizeClient(int idx, NSInteger weight) {
    UYTEnsureClientHealth();
    @synchronized(UYTClientHealthLock) {
        NSNumber *k = @(idx);
        NSInteger strikes = UYTClientStrikes[k].integerValue + weight;
        UYTClientStrikes[k] = @(strikes);
        // Exponential backoff, capped at 4 strikes: a transient blip recovers
        // in ~2 min, a client YouTube retired is only re-probed every ~16 min.
        NSInteger shift = strikes - 1;
        if (shift < 0) shift = 0;
        if (shift > 3) shift = 3;
        UYTClientRetryAfter[k] = [NSDate dateWithTimeIntervalSinceNow:UYTClientCooldown * (1 << shift)];
    }
}

static void UYTRewardClient(int idx) {
    UYTEnsureClientHealth();
    @synchronized(UYTClientHealthLock) {
        [UYTClientStrikes removeObjectForKey:@(idx)];
        [UYTClientRetryAfter removeObjectForKey:@(idx)];
        UYTLastGoodClient = idx;
    }
}

static int UYTLastGoodClientIndex(void) {
    UYTEnsureClientHealth();
    @synchronized(UYTClientHealthLock) {
        return UYTLastGoodClient;
    }
}

static BOOL UYTClientInCooldown(int idx) {
    UYTEnsureClientHealth();
    @synchronized(UYTClientHealthLock) {
        NSNumber *k = @(idx);
        NSDate *retry = UYTClientRetryAfter[k];
        if (!retry) return NO;
        if ([retry timeIntervalSinceNow] <= 0) {
            // Cooldown expired: forget the strikes so a recovered client
            // starts from a clean slate.
            [UYTClientRetryAfter removeObjectForKey:k];
            [UYTClientStrikes removeObjectForKey:k];
            return NO;
        }
        return YES;
    }
}

// Rotation order: the client that worked last goes first, then every client
// that is not in cooldown, then - only when nothing else is left - the ones
// still cooling down. Degraded clients are kept, just pushed to the back.
static NSArray<NSNumber *> *UYTClientOrder(void) {
    NSInteger count = (NSInteger)UYTClientProfiles().count;
    NSMutableArray<NSNumber *> *ready = [NSMutableArray array];
    NSMutableArray<NSNumber *> *cooling = [NSMutableArray array];

    int lastGood = UYTLastGoodClientIndex();
    if (lastGood >= 0 && lastGood < count) [ready addObject:@(lastGood)];
    for (NSInteger i = 0; i < count; i++) {
        if (i == lastGood) continue;
        if (UYTClientInCooldown((int)i)) [cooling addObject:@(i)];
        else [ready addObject:@(i)];
    }
    [ready addObjectsFromArray:cooling];
    return ready;
}

+ (NSDictionary *)clientProfileForIndex:(int)idx {
    NSArray *profiles = UYTClientProfiles();
    return profiles[idx >= 0 && idx < (int)profiles.count ? idx : 0];
}

+ (NSDictionary *)clientContextForIndex:(int)idx {
    return [self clientProfileForIndex:idx][@"context"];
}

+ (NSString *)userAgentForClientIndex:(int)idx {
    return [self clientProfileForIndex:idx][@"userAgent"];
}

+ (NSString *)clientNameForIndex:(int)idx {
    NSString *n = [self clientProfileForIndex:idx][@"name"];
    return n.length ? n : @"?";
}

// Innertube reports *why* it refused in the body; surface it for the log.
+ (NSString *)hintFromResponseData:(NSData *)data {
    if (!data.length) return @"empty body";
    @try {
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json isKindOfClass:[NSDictionary class]]) return @"unparseable body";
        id play = ((NSDictionary *)json)[@"playabilityStatus"];
        if ([play isKindOfClass:[NSDictionary class]]) {
            NSString *status = ((NSDictionary *)play)[@"status"];
            NSString *reason = ((NSDictionary *)play)[@"reason"];
            if (status.length) return reason.length
                ? [NSString stringWithFormat:@"%@ (%@)", status, reason] : status;
        }
        id errors = nil;
        id top = ((NSDictionary *)json)[@"error"];
        if ([top isKindOfClass:[NSDictionary class]]) errors = ((NSDictionary *)top)[@"errors"];
        if ([errors isKindOfClass:[NSArray class]] && ((NSArray *)errors).count) {
            id msg = ((NSDictionary *)((NSArray *)errors).firstObject)[@"message"];
            if ([msg isKindOfClass:[NSString class]]) return msg;
        }
        return @"no streamingData";
    } @catch (NSException *e) {
        return @"unparseable body";
    }
}

+ (void)tryClient:(int)idx
          onVideo:(NSString *)videoID
         progress:(void (^)(double frac, unsigned long long bytes))progress
       completion:(void (^)(NSArray<UYTStreamFormat *> *formats, NSError *error))completion {
    NSString *clientName = [self clientNameForIndex:idx];
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
            NSInteger status = [resp isKindOfClass:[NSHTTPURLResponse class]]
                ? (NSInteger)((NSHTTPURLResponse *)resp).statusCode : 200;

            if (err || !data) {
                UYTPenalizeClient(idx, 1);
                UYTDebugErr(@"fetch %@ (client %d) network error for %@: %@", clientName, idx, videoID,
                            err.localizedDescription ?: @"empty response");
                completion(@[], err ?: [NSError errorWithDomain:@"UYTDownload" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"empty response"}]);
                return;
            }

            // 400/403 = Innertube refused the client triple: penalise hard.
            if (status == 400 || status == 401 || status == 403) {
                UYTPenalizeClient(idx, 2);
                UYTDebugErr(@"fetch %@ (client %d) REJECTED HTTP %ld for %@: %@", clientName, idx,
                            (long)status, videoID, [self hintFromResponseData:data]);
                completion(@[], [NSError errorWithDomain:@"UYTDownload" code:-1002 userInfo:@{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Innertube rejected %@ (HTTP %ld)", clientName, (long)status],
                    @"UYTHTTPStatus": @(status),
                    @"UYTClientName": clientName
                }]);
                return;
            }

            if (status >= 500) {
                // Server-side: penalise softly, these often recover on their own.
                UYTPenalizeClient(idx, 1);
                UYTDebugErr(@"fetch %@ (client %d) server error HTTP %ld for %@", clientName, idx,
                            (long)status, videoID);
                completion(@[], [NSError errorWithDomain:@"UYTDownload" code:-1 userInfo:@{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Innertube HTTP %ld", (long)status],
                    @"UYTHTTPStatus": @(status),
                    @"UYTClientName": clientName
                }]);
                return;
            }
            NSMutableArray *out = [NSMutableArray array];
            NSMutableArray<NSDictionary *> *ciphered = [NSMutableArray array];
            NSMutableArray<NSNumber *> *cipheredIsMuxed = [NSMutableArray array];
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (json) {
                NSArray *streams = json[@"streamingData"][@"adaptiveFormats"];
                NSArray *muxed = json[@"streamingData"][@"formats"];
                NSArray *lists[2] = {streams ?: @[], muxed ?: @[]};
                for (int li = 0; li < 2; li++) {
                    for (NSDictionary *f in lists[li]) {
                        NSString *u = f[@"url"];
                        if (u) {
                            [out addObject:UYTStreamFormatFromDict(f, u, li == 1)];
                            continue;
                        }
                        NSString *cipher = f[@"signatureCipher"] ?: f[@"cipher"];
                        if (cipher) {
                            [ciphered addObject:f];
                            [cipheredIsMuxed addObject:@(li == 1)];
                        }
                    }
                }
            }
            if (!out.count && !ciphered.count) {
                // A 200 with no streamingData is a dead client too; rotate it.
                UYTPenalizeClient(idx, 1);
                UYTDebugErr(@"fetch %@ (client %d) no usable URLs for %@: %@", clientName, idx, videoID,
                            [self hintFromResponseData:data]);
                completion(@[], [NSError errorWithDomain:@"UYTDownload" code:-1002 userInfo:@{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@ returned no playable formats", clientName],
                    @"UYTHTTPStatus": @(status),
                    @"UYTClientName": clientName
                }]);
                return;
            }
            if (!ciphered.count) {
                UYTDebugInfo(@"fetch %@ (client %d) OK: %lu formats for %@", clientName, idx,
                             (unsigned long)out.count, videoID);
                completion(out, nil);
                return;
            }
            UYTDebugInfo(@"[UYTPipeline] client %d (%@): %lu direct + %lu ciphered for %@", idx,
                         clientName, (unsigned long)out.count, (unsigned long)ciphered.count, videoID);
            [UYTSigDecipher playerContextForVideoID:videoID completion:^(UYTPlayerJSContext *player, NSError *sigErr) {
                if (!player) {
                    UYTDebugErr(@"[UYTPipeline] decipher unavailable for %@ (%@)", videoID,
                                sigErr.localizedDescription ?: @"no player context");
                    // NOT penalising here: decipher failure is client-independent.
                    if (out.count) {
                        completion(out, nil);
                    } else {
                        completion(@[], sigErr ?: [NSError errorWithDomain:@"UYTDownload" code:-1002 userInfo:@{
                            NSLocalizedDescriptionKey: @"signature decipher unavailable",
                            @"UYTClientName": clientName
                        }]);
                    }
                    return;
                }
                NSUInteger deciphered = 0;
                for (NSUInteger ci = 0; ci < ciphered.count; ci++) {
                    NSDictionary *f = ciphered[ci];
                    BOOL isMuxed = ci < cipheredIsMuxed.count ? [cipheredIsMuxed[ci] boolValue] : NO;
                    NSString *cipher = f[@"signatureCipher"] ?: f[@"cipher"];
                    NSString *resolved = [UYTSigDecipher resolveURLFromSignatureCipher:cipher usingPlayer:player];
                    if (!resolved.length) continue;
                    [out addObject:UYTStreamFormatFromDict(f, resolved, isMuxed)];
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

// order is snapshotted per download: each client is tried at most once.
+ (void)attempt:(NSUInteger)n
          order:(NSArray<NSNumber *> *)order
        onVideo:(NSString *)videoID
       progress:(void (^)(double frac, unsigned long long bytes))progress
     completion:(void (^)(NSArray<UYTStreamFormat *> *formats, NSError *error))completion
     lastError:(NSError *)lastError {
    if (n >= order.count) {
        NSString *tried = [order componentsJoinedByString:@", "];
        UYTDebugErr(@"all %lu clients failed for %@ (tried indices: %@; last: %@)",
                    (unsigned long)order.count, videoID, tried,
                    lastError.localizedDescription ?: @"no formats");
        completion(@[], lastError ?: [NSError errorWithDomain:@"UYTDownload" code:-1 userInfo:@{
            NSLocalizedDescriptionKey: @"no client produced formats"
        }]);
        return;
    }
    int idx = order[n].intValue;
    [self tryClient:idx onVideo:videoID progress:progress completion:^(NSArray<UYTStreamFormat *> *formats, NSError *error) {
        if (formats.count) {
            // This client works: clear its strikes so the next download starts
            // from it first and the cooldown budget is released.
            UYTRewardClient(idx);
            UYTDebugInfo(@"[UYTPipeline] %@ (client %d) served %@ with %lu formats",
                         [self clientNameForIndex:idx], idx, videoID, (unsigned long)formats.count);
            completion(formats, nil);
        } else {
            [self attempt:(n + 1) order:order onVideo:videoID progress:progress
                completion:completion lastError:error ?: lastError];
        }
    }];
}

+ (void)fetchFormatsForVideoID:(NSString *)videoID
                     isShorts:(BOOL)isShorts
                     progress:(void (^)(double frac, unsigned long long bytes))progress
                   completion:(void (^)(NSArray<UYTStreamFormat *> *, NSError *))completion {
    (void)isShorts;
    // Order is recomputed per call, so a retry lands on a different client.
    NSArray<NSNumber *> *order = UYTClientOrder();
    UYTDebugInfo(@"[UYTPipeline] resolving %@ via clients: %@", videoID,
                 [order componentsJoinedByString:@", "]);
    [self attempt:0 order:order onVideo:videoID progress:progress completion:completion lastError:nil];
}

+ (void)fetchFormatsForVideoID:(NSString *)videoID
                    completion:(void (^)(NSArray<UYTStreamFormat *> *, NSError *))completion {
    [self fetchFormatsForVideoID:videoID isShorts:NO progress:nil completion:completion];
}

+ (UYTStreamFormat *)bestMuxedFormat:(NSArray<UYTStreamFormat *> *)formats {
    UYTStreamFormat *best = nil;
    for (UYTStreamFormat *f in formats)
        if (f.hasVideo && f.hasAudio && UYTFormatIsBetter(f, best)) best = f;
    return best;
}

+ (UYTStreamFormat *)bestAudioFormat:(NSArray<UYTStreamFormat *> *)formats {
    UYTStreamFormat *best = nil;
    for (UYTStreamFormat *f in formats)
        if (f.hasAudio && !f.hasVideo && UYTFormatIsBetter(f, best)) best = f;
    return best;
}

+ (UYTStreamFormat *)bestVideoFormat:(NSArray<UYTStreamFormat *> *)formats {
    UYTStreamFormat *best = nil;
    for (UYTStreamFormat *f in formats)
        if (f.hasVideo && !f.hasAudio && UYTFormatIsBetter(f, best)) best = f;
    return best;
}

+ (UYTStreamFormat *)bestVideoFormat:(NSArray<UYTStreamFormat *> *)formats
                       qualityLabel:(NSString *)qualityLabel {
    if (!qualityLabel.length) return [self bestVideoFormat:formats];
    UYTStreamFormat *best = nil;
    for (UYTStreamFormat *f in formats) {
        if (!f.hasVideo || f.hasAudio) continue;
        NSString *ql = f.qualityLabel.length ? f.qualityLabel
            : [NSString stringWithFormat:@"%ldp", (long)f.itag];
        if ([ql isEqualToString:qualityLabel] && UYTFormatIsBetter(f, best)) best = f;
    }
    return best ?: [self bestVideoFormat:formats];
}

// mp4 (avc1+mp4a) is stream-copyable; webm forces a transcode that kept
// failing with ffmpeg rc=1, so rank mp4/avc1 first and fall back to webm.
static NSInteger UYTFormatContainerRank(UYTStreamFormat *f) {
     if (f.containerRank >= 0) return f.containerRank;
     NSString *m = f.mimeType.lowercaseString ?: @"";
     NSInteger r = 3;
     if ([m hasPrefix:@"video/mp4"] || [m hasPrefix:@"audio/mp4"]) r = 0;
     else if ([m hasPrefix:@"audio/"]) r = 1;
     else if ([m hasPrefix:@"video/webm"] || [m hasPrefix:@"audio/webm"]) r = 2;
     f.containerRank = r;
     return r;
 }

 static NSInteger UYTFormatCodecRank(UYTStreamFormat *f) {
     if (f.codecRank >= 0) return f.codecRank;
     NSString *m = f.mimeType.lowercaseString ?: @"";
     NSInteger r = 2;
     if (f.hasVideo) {
         if ([m containsString:@"avc1"]) r = 0;
         else if ([m containsString:@"hev1"] || [m containsString:@"hvc1"]) r = 1;
         else if ([m containsString:@"av01"]) r = 2;
         else if ([m containsString:@"vp9"] || [m containsString:@"vp09"]) r = 3;
         else r = 4;
     } else if ([m containsString:@"mp4a"]) r = 0;
     else if ([m containsString:@"opus"]) r = 1;
     else r = 2;
     f.codecRank = r;
     return r;
 }

 static BOOL UYTFormatIsBetter(UYTStreamFormat *candidate, UYTStreamFormat *current) {
    if (!current) return YES;
    NSInteger cc = UYTFormatContainerRank(candidate), cu = UYTFormatContainerRank(current);
    if (cc != cu) return cc < cu;
    NSInteger kc = UYTFormatCodecRank(candidate), ku = UYTFormatCodecRank(current);
    if (kc != ku) return kc < ku;
    return candidate.bitrate > current.bitrate;
}

static NSString *UYTFormatDesc(UYTStreamFormat *f) {
    if (!f) return @"nil";
    return [NSString stringWithFormat:@"itag=%ld %@ %@ %lldkbps", (long)f.itag,
            f.qualityLabel.length ? f.qualityLabel : @"-", f.mimeType ?: @"-", f.bitrate / 1000];
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
            UYTDebugInfo(@"[UYTPipeline] refresh pick for %@: muxed=%@ audio=%@ video=%@", vid,
                         UYTFormatDesc(muxed), UYTFormatDesc(audio), UYTFormatDesc(video));
            if (UYTIsAudioOnly(vid)) {
                UYTStoreResolvedURLs(vid, nil, audio.url, nil);
            } else {
                UYTStoreResolvedURLs(vid, muxed.url, audio.url, video.url);
            }
            if (audio.mimeType.length) UYTResolvedEntrySet(vid, @"audioMime", audio.mimeType);
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

void UYTRegisterRemoteURLForVideoID(NSString *vid, NSString *url) {
    @try {
        if (vid.length && url.length) {
            UYTResolvedEntrySet(vid, @"remote", url);
        }
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
            if (UYTIsAudioOnly(vid)) return nil;
        }
        NSString *videoURL = UYTResolvedVideoURL(vid);
        if (videoURL.length) return videoURL;
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

// Did the refresh pick an MP4-class audio stream (itag 140 mp4a, or an already
// staged .m4a)? If so the audio leg should be named .m4a, not uYou's default
// .webm - AVFoundation chokes on the fake .webm extension later.
static BOOL UYTResolvedAudioIsMP4(NSString *vid) {
    @try {
        if (!vid.length) return NO;
        if (UYTStagedCanonicalPathFor(vid, @"m4a").length) return YES;
        NSDictionary *entry = UYTResolvedEntrySnapshot(vid);
        if (!entry) return NO;
        id mime = entry[@"audioMime"];
        if ([mime isKindOfClass:[NSString class]]) {
            NSString *m = [mime lowercaseString];
            if ([m hasPrefix:@"audio/mp4"]) return YES;
            if ([m containsString:@"mp4a"]) return YES;
            return NO;
        }
        id audio = entry[@"audio"];
        if ([audio isKindOfClass:[NSString class]] && [audio hasPrefix:@"file://"]) return YES;
        return NO;
    } @catch (NSException *e) {
        return NO;
    }
}

// Audio-only requests must never be swapped onto a muxed/video stream, or the
// audio file silently becomes the whole video and conversion fails downstream.
NSString *UYTAudioOnlyURL(NSString *vid) {
    @try {
        if (!vid.length) return nil;
        NSString *stagedAudio = UYTStagedCanonicalPathFor(vid, @"m4a");
        if (stagedAudio.length) return UYTFileURLString(stagedAudio);
        NSDictionary *entry = UYTResolvedEntrySnapshot(vid);
        if (!entry) return nil;
        id audio = entry[@"audio"];
        if ([audio isKindOfClass:[NSString class]] && [audio length]) return audio;
        return nil;
    } @catch (NSException *e) {
        return nil;
    }
}

static NSString *UYTGetResolvedURL(NSString *vid) {
    if (UYTIsAudioOnly(vid)) {
        NSString *audioOnlyURL = UYTAudioOnlyURL(vid);
        if (audioOnlyURL.length) return audioOnlyURL;
        UYTDebugWarn(@"[UYTPipeline] audio-only %@ has no audio URL - refusing muxed/video", vid);
        return nil;
    }
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
                    static NSArray *UYTProgressKeys = nil;
                    static dispatch_once_t once;
                    dispatch_once(&once, ^{
                        UYTProgressKeys = @[@"progress", @"progressValue", @"downloadProgress"];
                    });
                    for (NSString *k in UYTProgressKeys) UYTSafeSetValue(item, k, frac);
                    static NSArray *UYTBytesKeys = nil;
                    static dispatch_once_t once2;
                    dispatch_once(&once2, ^{
                        UYTBytesKeys = @[@"bytesDownloaded", @"downloadedBytes"];
                    });
                    for (NSString *k in UYTBytesKeys) UYTSafeSetValue(item, k, bytes);
                    break;
                }
            } @catch (NSException *e) {}
        });
    } @catch (NSException *e) {}
}

void UYTWriteFinalDownloadProgress(id item, NSString *filePath) {
    @try {
        if (!item) return;
        NSNumber *size = @(UYTSizeOfFile(filePath));
        static NSArray *UYTProgressKeys = nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            UYTProgressKeys = @[@"progress", @"progressValue", @"downloadProgress"];
        });
        for (NSString *k in UYTProgressKeys) UYTSafeSetValue(item, k, @1.0);
        static NSArray *UYTBytesKeys = nil;
        static dispatch_once_t once2;
        dispatch_once(&once2, ^{
            UYTBytesKeys = @[@"bytesDownloaded", @"downloadedBytes", @"size"];
        });
        for (NSString *k in UYTBytesKeys) UYTSafeSetValue(item, k, size);
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

// uYou makes TWO DownloadItems per video download (…_Audio and …_Video) sharing
// the same videoID, so the resolved-store audio-only flag can't tell them apart.
// Record which leg this item is so setRemoteURL: routes the audio leg to the
// AUDIO stream and the video leg to the muxed/video stream (otherwise the audio
// file gets the whole video and -map 0:a:0 matches no streams).
static void *UYTDownloadItemAudioLegKey = &UYTDownloadItemAudioLegKey;

- (id)initWithVideoID:(id)videoID
             uYouItem:(id)uYouItem
           downloadID:(id)downloadID
                  url:(id)url
             filePath:(id)filePath
           cachedPath:(id)cachedPath
                 type:(int)type {

    BOOL audioLeg = NO;
    @try {
        NSString *base = [downloadID respondsToSelector:@selector(hasSuffix:)]
                       ? (NSString *)downloadID : [downloadID description] ?: @"";
        NSString *path = [filePath respondsToSelector:@selector(hasSuffix:)]
                       ? (NSString *)filePath : [filePath description] ?: @"";
        if ([base rangeOfString:@"Video"].location != NSNotFound ||
            [path rangeOfString:@"Video"].location != NSNotFound) {
            audioLeg = NO;
        } else if ([base rangeOfString:@"Audio"].location != NSNotFound ||
                   [path rangeOfString:@"Audio"].location != NSNotFound) {
            audioLeg = YES;
        }
        objc_setAssociatedObject(self, UYTDownloadItemAudioLegKey, @(audioLeg),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UYTDebugInfo(@"[UYTPipeline] DownloadItem init vid=%@ downloadID=%@ file=%@ cached=%@ title=%@ leg=%@",
                     videoID, downloadID, filePath, cachedPath, [uYouItem valueForKey:@"title"],
                     audioLeg ? @"AUDIO" : @"VIDEO");
    } @catch (NSException *e) {
        UYTDebugInfo(@"[UYTPipeline] DownloadItem init vid=%@ (detail lookup failed: %@)", videoID, e.reason ?: e);
    }

    id result = %orig(videoID, uYouItem, downloadID, url, filePath, cachedPath, type);

    @try {
        // Give the audio leg its true extension when the stream is MP4 (itag
        // 140-class). uYou hardcodes .webm for every audio leg; a .webm-named
        // MP4 file is what defeats AVFoundation's native addMetadata/merge
        // (and forced the flaky webm->m4a ffmpeg detour) later.
        if (audioLeg && UYTResolvedAudioIsMP4([videoID description])) {
            NSString *fp = [self filePath];
            if (fp.pathExtension.length && [fp.pathExtension.lowercaseString isEqualToString:@"webm"]) {
                NSString *np = [[fp stringByDeletingPathExtension] stringByAppendingPathExtension:@"m4a"];
                [self setValue:np forKey:@"filePath"];
                NSString *cp = [self valueForKey:@"cachedPath"];
                if (cp.pathExtension.length && [cp.pathExtension.lowercaseString isEqualToString:@"webm"]) {
                    [self setValue:[[cp stringByDeletingPathExtension] stringByAppendingPathExtension:@"m4a"] forKey:@"cachedPath"];
                }
                UYTDebugInfo(@"[UYTPipeline] audio leg renamed to %@ (mp4a stream, no webm dance)", np);
            }
        }
    } @catch (NSException *e) {
        UYTDebugInfo(@"[UYTPipeline] audio-leg rename skipped: %@", e.reason ?: e);
    }

    return result;
}

- (void)setRemoteURL:(NSURL *)url {
    NSString *vid = self.videoID ?: @"";
    if (!vid.length) {
        %orig;
        return;
    }

    // The audio leg and audio-only requests take the audio stream; only the
    // video leg/muxed requests may take the muxed/video stream.
    NSNumber *leg = objc_getAssociatedObject(self, UYTDownloadItemAudioLegKey);
    BOOL isAudioLeg = [leg isKindOfClass:[NSNumber class]] && leg.boolValue;
    BOOL audioOnly = UYTIsAudioOnly(vid);
    if (url.absoluteString.length) UYTRegisterRemoteURLForVideoID(vid, url.absoluteString);

    NSString *working = (isAudioLeg || audioOnly) ? UYTAudioOnlyURL(vid) : UYTGetResolvedURL(vid);
    if (working.length) {
        NSURL *fixed = [NSURL URLWithString:working];
        if (fixed) {
            UYTRegisterRemoteURLForVideoID(vid, working);
            if (isAudioLeg || audioOnly) {
                UYTDebugInfo(@"[UYTPipeline] audio leg %@ -> audio stream %@", vid, working);
            } else {
                UYTDebugInfo(@"[UYTPipeline] swapped broken task URL -> cached innertube URL for %@", vid);
            }
            %orig(fixed);
            return;
        }
    }

    if (isAudioLeg || audioOnly) {
        // Refuse uYou's URL here (recreates the audio-is-really-the-video bug);
        // the stall watchdog still finalizes the item instead of hanging.
        UYTDebugErr(@"[UYTPipeline] %@ %@ has no audio stream - refusing %@",
                    isAudioLeg ? @"audio leg" : @"audio-only request", vid,
                    url.path.length ? url.path : @"(nil)");
        return;
    }

    %orig;
}
%end

%ctor {
    %init;
}

