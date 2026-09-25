
#import "uYouPlus.h"
#import "UYTLog.h"

#import <YouTubeHeader/YTIHamplayerConfig.h>
#import <YouTubeHeader/YTIHamplayerHotConfig.h>
#import <YouTubeHeader/YTHotConfig.h>
#import <YouTubeHeader/MLInnerTubePlayerConfig.h>
#import <YouTubeHeader/MLDefaultPlayerViewFactory.h>
#import <YouTubeHeader/MLPlayerPool.h>
#import <YouTubeHeader/MLPlayerPoolImpl.h>
#import <YouTubeHeader/MLVideoDecoderFactory.h>
#import <YouTubeHeader/MLVideo.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayViewController.h>
#import <YouTubeHeader/YTPlayerViewController.h>
#import <YouTubeHeader/YTWatchController.h>

@interface YTWatchController (uYouFixPlayback)
- (void)reload;
@end

@interface YTGLMediaPlayerViewFactory : NSObject
@end

#pragma mark - [1] Root cause: Android VR (Oculus Quest) client spoof

%group gFixPlaybackNetwork

static NSString *const UYTFixEndpointPlayer = @"/player";
static NSString *const UYTFixEndpointNext   = @"/next";
static NSString *const UYTFixEndpointBrowse = @"/browse";
static NSString *const UYTFixVRClientName   = @"28";
static NSString *const UYTFixVRClientVersion = @"1.65.10";
static NSString *const UYTFixVRUserAgent    = @"com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip";

static NSDictionary *UYTFixVRHeaders(NSString *visitorData) {
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    headers[@"Content-Type"] = @"application/json";
    headers[@"Accept-Language"] = @"*";
    headers[@"X-YouTube-Client-Name"] = UYTFixVRClientName;
    headers[@"X-YouTube-Client-Version"] = UYTFixVRClientVersion;
    headers[@"User-Agent"] = UYTFixVRUserAgent;
    headers[@"Origin"] = @"https://www.youtube.com";
    if (visitorData.length > 0) {
        headers[@"X-Goog-Visitor-Id"] = visitorData;
    }
    return headers;
}

static NSDictionary *UYTFixVRBody(NSDictionary *incomingBody, NSString *visitorData) {
    NSMutableDictionary *client = [NSMutableDictionary dictionary];
    client[@"clientName"] = @"ANDROID_VR";
    client[@"clientVersion"] = UYTFixVRClientVersion;
    client[@"hl"] = @"en";
    client[@"timeZone"] = @"UTC";
    client[@"utcOffsetMinutes"] = @0;
    client[@"deviceMake"] = @"Oculus";
    client[@"deviceModel"] = @"Quest 3";
    client[@"androidSdkVersion"] = @32;
    client[@"osName"] = @"Android";
    client[@"osVersion"] = @"12L";
    client[@"userAgent"] = UYTFixVRUserAgent;
    if (visitorData.length > 0) {
        client[@"visitorData"] = visitorData;
    }

    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    body[@"context"] = @{ @"client": client };

    if ([incomingBody isKindOfClass:[NSDictionary class]]) {
        NSArray *keys = @[ @"videoId", @"browseId", @"continuation", @"params" ];
        for (NSString *key in keys) {
            id value = incomingBody[key];
            if (value) body[key] = value;
        }
    }
    return body;
}

%hook NSMutableURLRequest

- (id)initWithURL:(NSURL *)URL cachePolicy:(unsigned long long)cachePolicy timeoutInterval:(double)timeoutInterval {
    self = %orig;
    if (!self || !URL) return self;

    NSString *path = URL.path;
    if (!([path containsString:UYTFixEndpointPlayer] ||
          [path containsString:UYTFixEndpointNext] ||
          [path containsString:UYTFixEndpointBrowse])) {
        return self;
    }

    if ([URL.absoluteString containsString:@"youtubei/v1/player?key=AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc"]) {
        return self;
    }

    NSString *visitorData = @"";
    if (self.HTTPBody) {
        NSDictionary *incoming = [NSJSONSerialization JSONObjectWithData:self.HTTPBody options:0 error:nil];
        if ([incoming isKindOfClass:[NSDictionary class]]) {
            NSDictionary *incomingContext = incoming[@"context"];
            NSDictionary *incomingClient = [incomingContext isKindOfClass:[NSDictionary class]] ? incomingContext[@"client"] : nil;
            if ([incomingClient isKindOfClass:[NSDictionary class]]) {
                id vd = incomingClient[@"visitorData"];
                if ([vd isKindOfClass:[NSString class]]) visitorData = vd;
            }
            NSData *rebuilt = [NSJSONSerialization dataWithJSONObject:UYTFixVRBody(incoming, visitorData) options:0 error:nil];
            if (rebuilt) {
                self.HTTPBody = rebuilt;
            }
        }
    }

    NSDictionary *headers = UYTFixVRHeaders(visitorData);
    for (NSString *headerKey in headers) {
        [self setValue:headers[headerKey] forHTTPHeaderField:headerKey];
    }

    return self;
}

%end

%end

#pragma mark - [2] Render path: force HAM render view to METAL (YTUHD / YouPiP)

%group gFixPlaybackRenderer

static void UYTFixForceRenderTypeBase(YTIHamplayerConfig *hamplayerConfig) {
    if (!hamplayerConfig) return;
    if (hamplayerConfig.renderViewType != HAMPLAYER_RENDER_VIEW_TYPE_METAL) {
        hamplayerConfig.renderViewType = HAMPLAYER_RENDER_VIEW_TYPE_METAL;
    }
}

static void UYTFixForceRenderTypeHot(YTIHamplayerHotConfig *hotConfig) {
    if (!hotConfig) return;
    if (hotConfig.renderViewType != HAMPLAYER_RENDER_VIEW_TYPE_METAL) {
        hotConfig.renderViewType = HAMPLAYER_RENDER_VIEW_TYPE_METAL;
    }
}

static void UYTFixForceRenderType(YTHotConfig *config) {
    if (!config) return;
    UYTFixForceRenderTypeHot(config.hamplayerHotConfig);
}

%hook MLPlayerPoolImpl
- (BOOL)canUsePlayerView:(id)playerView forPlayerConfig:(MLInnerTubePlayerConfig *)playerConfig {
    UYTFixForceRenderTypeBase(playerConfig.hamplayerConfig);
    return %orig;
}
%end

%hook MLPlayerPool
- (BOOL)canUsePlayerView:(id)playerView forVideo:(MLVideo *)video playerConfig:(MLInnerTubePlayerConfig *)playerConfig {
    UYTFixForceRenderTypeBase(playerConfig.hamplayerConfig);
    return %orig;
}
%end

%hook MLDefaultPlayerViewFactory
- (id)hamPlayerViewForVideo:(MLVideo *)video playerConfig:(MLInnerTubePlayerConfig *)playerConfig {
    UYTFixForceRenderType((YTHotConfig *)[self valueForKey:@"_hotConfig"]);
    UYTFixForceRenderTypeBase(playerConfig.hamplayerConfig);
    return %orig;
}
- (id)hamPlayerViewForPlayerConfig:(MLInnerTubePlayerConfig *)playerConfig {
    UYTFixForceRenderType((YTHotConfig *)[self valueForKey:@"_hotConfig"]);
    UYTFixForceRenderTypeBase(playerConfig.hamplayerConfig);
    return %orig;
}
- (BOOL)canUsePlayerView:(id)playerView forVideo:(MLVideo *)video playerConfig:(MLInnerTubePlayerConfig *)playerConfig {
    UYTFixForceRenderTypeBase(playerConfig.hamplayerConfig);
    return %orig;
}
- (BOOL)canUsePlayerView:(id)playerView forPlayerConfig:(MLInnerTubePlayerConfig *)playerConfig {
    UYTFixForceRenderTypeBase(playerConfig.hamplayerConfig);
    return %orig;
}
%end

%hook MLVideoDecoderFactory
- (void)prepareDecoderForFormatDescription:(id)formatDescription delegateQueue:(id)delegateQueue {
    UYTFixForceRenderTypeHot((YTIHamplayerHotConfig *)[self valueForKey:@"_hotConfig"]);
    %orig;
}
- (void)prepareDecoderForFormatDescription:(id)formatDescription setPixelBufferTypeOnlyIfEmpty:(BOOL)setPixelBufferTypeOnlyIfEmpty delegateQueue:(id)delegateQueue {
    UYTFixForceRenderTypeHot((YTIHamplayerHotConfig *)[self valueForKey:@"_hotConfig"]);
    %orig;
}
%end

%hook YTGLMediaPlayerViewFactory
- (BOOL)canUsePlayerView:(id)playerView forPlayerConfig:(MLInnerTubePlayerConfig *)playerConfig {
    UYTFixForceRenderTypeBase(playerConfig.hamplayerConfig);
    return %orig;
}
- (id)hamPlayerViewForPlayerConfig:(MLInnerTubePlayerConfig *)playerConfig {
    UYTFixForceRenderType((YTHotConfig *)[self valueForKey:@"_hotConfig"]);
    UYTFixForceRenderTypeBase(playerConfig.hamplayerConfig);
    return %orig;
}
%end

%end

#pragma mark - [3] Safety net: reload the watch controller on the classic playback error

%group gFixPlayback

static NSTimeInterval uytLastPlaybackReload = 0;

%hook YTMainAppVideoPlayerOverlayViewController
- (void)handleError:(NSError *)error {
    if (error && [error.domain isEqualToString:@"com.google.ios.youtube.ErrorDomain.playback"] && error.code == 14) {
        YTPlayerViewController *playerViewController = (YTPlayerViewController *)self.parentViewController;
        if (![playerViewController.UIDelegate isKindOfClass:%c(YTWatchController)]) return;
        YTWatchController *watchController = (YTWatchController *)playerViewController.UIDelegate;
        NSTimeInterval now = [[NSProcessInfo processInfo] systemUptime];
        if (now - uytLastPlaybackReload < 10.0) {
            UYTDebugWarn(@"FixPlayback: playback error 14 repeated — suppressing reload loop");
            return;
        }
        uytLastPlaybackReload = now;
        dispatch_async(dispatch_get_main_queue(), ^{
            [watchController reload];
        });
        return;
    }
    %orig;
}
%end

%end

%ctor {
    if (!IS_ENABLED(kFixPlaybackIssues)) return;
    %init(gFixPlaybackNetwork);
    %init(gFixPlaybackRenderer);
    %init(gFixPlayback);
    UYTDebugInfo(@"[uYouPlus] FixPlayback: root-cause playback fix installed (client=%s)", UYTFixVRClientName.UTF8String);
}