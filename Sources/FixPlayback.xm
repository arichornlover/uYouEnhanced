
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

#pragma mark - [1] Root cause: client spoof. TVHTML5_SIMPLY (75) instead of the retired ANDROID_VR (28).
%group gFixPlaybackNetwork

static NSString *const UYTFixEndpointPlayer        = @"/player";
static NSString *const UYTFixEndpointNext          = @"/next";
static NSString *const UYTFixEndpointBrowse        = @"/browse";
static NSString *const UYTFixEndpointInitPlayback  = @"/initplayback";
static NSString *const UYTFixEndpointVideoPlayback = @"/videoplayback";
static NSString *const UYTFixClientName    = @"75";
static NSString *const UYTFixClientVersion = @"1.1";
static NSString *const UYTFixUserAgent     = @"Mozilla/5.0 (PS4; Leanback Shell) Gecko/20100101 Firefox/65.0 LeanbackShell/01.00.01.75 Sony PS4/ (PS4, , no, CH)";

static NSString *gUYTFixVisitorData = nil;

static NSString *UYTFixCurrentVisitorData(void) {
    @synchronized ([UIApplication class]) {
        return gUYTFixVisitorData;
    }
}

static void UYTFixRememberVisitorData(NSString *visitorData) {
    if (!visitorData.length) return;
    @synchronized ([UIApplication class]) {
        gUYTFixVisitorData = [visitorData copy];
    }
}

static BOOL UYTFixIsInnertubePath(NSString *path) {
    if (!path.length) return NO;
    NSString *p = path.lowercaseString;
    return [p containsString:UYTFixEndpointPlayer.lowercaseString] ||
           [p containsString:UYTFixEndpointNext.lowercaseString] ||
           [p containsString:UYTFixEndpointBrowse.lowercaseString] ||
           [p containsString:UYTFixEndpointInitPlayback.lowercaseString];
}

static BOOL UYTFixIsVideoPlaybackPath(NSString *path) {
    if (!path.length) return NO;
    return [path.lowercaseString containsString:UYTFixEndpointVideoPlayback.lowercaseString];
}

static NSDictionary *UYTFixClientBlueprint(NSString *visitorData) {
    NSMutableDictionary *client = [NSMutableDictionary dictionary];
    client[@"clientName"] = @"TVHTML5_SIMPLY";
    client[@"clientVersion"] = UYTFixClientVersion;
    client[@"hl"] = @"en";
    client[@"timeZone"] = @"UTC";
    client[@"utcOffsetMinutes"] = @0;
    client[@"deviceMake"] = @"Sony";
    client[@"deviceModel"] = @"PS4";
    client[@"osName"] = @"";
    client[@"osVersion"] = @"7.20260707.07.00";
    client[@"clientPlatform"] = @"GAME_CONSOLE";
    client[@"userAgent"] = UYTFixUserAgent;
    if (visitorData.length) client[@"visitorData"] = visitorData;
    return client;
}

static NSDictionary *UYTFixHeadersForVisitorData(NSString *visitorData, BOOL includeContentType) {
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    if (includeContentType) headers[@"Content-Type"] = @"application/json";
    headers[@"Accept-Language"] = @"*";
    headers[@"X-YouTube-Client-Name"] = UYTFixClientName;
    headers[@"X-YouTube-Client-Version"] = UYTFixClientVersion;
    headers[@"User-Agent"] = UYTFixUserAgent;
    headers[@"Origin"] = @"https://www.youtube.com";
    if (visitorData.length) headers[@"X-Goog-Visitor-Id"] = visitorData;
    return headers;
}

static void UYTFixApplyHeaders(NSMutableURLRequest *request, BOOL includeContentType) {
    if (!request) return;
    NSDictionary *headers = UYTFixHeadersForVisitorData(UYTFixCurrentVisitorData(), includeContentType);
    for (NSString *key in headers) {
        [request setValue:headers[key] forHTTPHeaderField:key];
    }
}

static void UYTFixApplyBody(NSMutableURLRequest *request) {
    if (!request.HTTPBody) return;
    if (!UYTFixIsInnertubePath(request.URL.path)) return;

    NSDictionary *incoming = [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:nil];
    if (![incoming isKindOfClass:[NSDictionary class]]) return;

    NSDictionary *incomingContext = incoming[@"context"];
    NSDictionary *incomingClient = [incomingContext isKindOfClass:[NSDictionary class]] ? incomingContext[@"client"] : nil;
    if ([incomingClient isKindOfClass:[NSDictionary class]]) {
        id vd = incomingClient[@"visitorData"];
        if ([vd isKindOfClass:[NSString class]]) UYTFixRememberVisitorData(vd);
    }

    NSMutableDictionary *body = [incoming mutableCopy];
    NSMutableDictionary *context = [incomingContext isKindOfClass:[NSDictionary class]] ? [incomingContext mutableCopy] : [NSMutableDictionary dictionary];
    context[@"client"] = UYTFixClientBlueprint(UYTFixCurrentVisitorData());
    body[@"context"] = context;

    NSData *rebuilt = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    if (rebuilt) request.HTTPBody = rebuilt;
}

static void UYTFixHandleRequest(NSMutableURLRequest *request) {
    if (!request.URL) return;
    NSString *path = request.URL.path;
    if (UYTFixIsInnertubePath(path)) {
        UYTFixApplyBody(request);
        UYTFixApplyHeaders(request, YES);
    } else if (UYTFixIsVideoPlaybackPath(path)) {
        UYTFixApplyHeaders(request, NO);
    }
}

@interface GTMSessionFetcher : NSObject
- (id)mutableRequestForTesting;
@end

%hook NSMutableURLRequest

- (id)initWithURL:(NSURL *)URL cachePolicy:(unsigned long long)cachePolicy timeoutInterval:(double)timeoutInterval {
    self = %orig;
    if (!self || !URL) return self;
    if ([URL.absoluteString containsString:@"youtubei/v1/player?key=AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc"]) return self;
    UYTFixHandleRequest(self);
    return self;
}

%end

%hook GTMSessionFetcher

- (id)initWithRequest:(id)request {
    if ([request isKindOfClass:[NSURLRequest class]] && request.URL) {
        NSMutableURLRequest *mutable = [request mutableCopy];
        UYTFixHandleRequest(mutable);
        request = mutable;
    }
    return %orig(request);
}

- (id)initWithRequest:(id)request configuration:(id)configuration {
    if ([request isKindOfClass:[NSURLRequest class]] && request.URL) {
        NSMutableURLRequest *mutable = [request mutableCopy];
        UYTFixHandleRequest(mutable);
        request = mutable;
    }
    return %orig(request, configuration);
}

- (void)updateMutableRequest:(id)request {
    if ([request isKindOfClass:[NSMutableURLRequest class]]) UYTFixHandleRequest(request);
    %orig(request);
}

- (void)setRequestValue:(id)value forHTTPHeaderField:(id)field {
    %orig(value, field);
    NSMutableURLRequest *request = [self mutableRequestForTesting];
    if (![request isKindOfClass:[NSMutableURLRequest class]] || !request.URL) return;
    NSString *path = request.URL.path;
    if (UYTFixIsInnertubePath(path)) UYTFixApplyHeaders(request, YES);
    else if (UYTFixIsVideoPlaybackPath(path)) UYTFixApplyHeaders(request, NO);
}

- (void)setBodyData:(id)data {
    %orig(data);
    NSMutableURLRequest *request = [self mutableRequestForTesting];
    if ([request isKindOfClass:[NSMutableURLRequest class]]) UYTFixApplyBody(request);
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
    UYTDebugInfo(@"[uYouPlus] FixPlayback: root-cause playback fix installed (client=%s %s)", UYTFixClientName.UTF8String, UYTFixClientVersion.UTF8String);
}