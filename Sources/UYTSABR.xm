
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "UYTMediaKit.h"
#import "UYTSABR.h"

#define SABR_ENABLED() (1)

@interface HAMDataLoadRequest : NSObject
- (NSURLRequest *)buildURLRequest;
- (NSData *)HTTPBody;
@property (nonatomic, readonly) NSURL *URL;
@property (nonatomic, readonly) NSDictionary *allHTTPHeaderFields;
@property (nonatomic, readonly) NSString *HTTPMethod;
@end

#ifndef INTFORVAL
#define INTFORVAL(x) (0)
#endif
#ifndef DownloadMethod
#define DownloadMethod @"DownloadMethod"
#endif
#ifndef DownloadMethodOnDevice
#define DownloadMethodOnDevice 2
#endif

static void *SABRQueueKey = &SABRQueueKey;

static dispatch_queue_t SABRQueue(void) {
    static dispatch_queue_t q; static dispatch_once_t o;
    dispatch_once(&o, ^{
        q = dispatch_queue_create("youmod.sabr", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(q, SABRQueueKey, SABRQueueKey, NULL);
    });
    return q;
}

static BOOL SABROnQueue(void) {
    return dispatch_get_specific(SABRQueueKey) == SABRQueueKey;
}

#pragma mark - UMP parser

static NSUInteger SABRReadUMPVarint(const uint8_t *b, NSUInteger len, NSUInteger pos, uint64_t *out) {
    if (pos >= len) return 0;
    uint8_t pfx = b[pos]; int size = 1;
    if (pfx >= 0xF0) size = 5; else if (pfx >= 0xE0) size = 4; else if (pfx >= 0xC0) size = 3; else if (pfx >= 0x80) size = 2;
    if (pos + size > len) return 0;
    uint64_t r = 0; int sh = 0;
    if (size != 5) { sh = 8 - size; r = pfx & ((1u << sh) - 1); }
    for (int i = 1; i < size; i++) { r |= ((uint64_t)b[pos + i]) << sh; sh += 8; }
    *out = r; return (NSUInteger)size;
}

typedef NS_ENUM(NSInteger, SABRPartType) {
    SABRPartMediaHeader      = 20,
    SABRPartMedia            = 21,
    SABRPartMediaEnd         = 22,
    SABRPartNextRequestPolicy = 35,
    SABRPartFormatInit       = 42,
    SABRPartRedirect         = 43,
    SABRPartError            = 44,
    SABRPartReload           = 46,
    SABRPartContextUpdate    = 57,
    SABRPartStreamProtection = 58,
};

static const uint64_t kSABRRedirectURL = 1;

static NSUInteger SABRParseUMP(NSData *data, void (^handler)(uint64_t type, const uint8_t *payload, NSUInteger size)) {
    const uint8_t *b = (const uint8_t *)data.bytes; NSUInteger len = data.length, pos = 0;
    while (pos < len) {
        uint64_t type = 0, size = 0;
        NSUInteger c1 = SABRReadUMPVarint(b, len, pos, &type); if (!c1) break; pos += c1;
        NSUInteger c2 = SABRReadUMPVarint(b, len, pos, &size); if (!c2) break; pos += c2;
        if (pos + size > len) break;
        if (handler) handler(type, b + pos, (NSUInteger)size);
        pos += (NSUInteger)size;
    }
    return pos;
}

#pragma mark - SABR protobuf field map

static const uint64_t kSABRReqClientAbrState  = 1;
static const uint64_t kSABRReqSelectedFormats = 2;
static const uint64_t kSABRReqBufferedRanges  = 3;
static const uint64_t kSABRReqPlayerTimeMs    = 4;
static const uint64_t kSABRReqUstreamerConfig = 5;
static const uint64_t kSABRReqPreferredAudio  = 16;
static const uint64_t kSABRReqPreferredVideo  = 17;

static const uint64_t kSABRAbrStatePlayerTimeMs = 28;

static const uint64_t kSABRAvailInner = 1;
static const uint64_t kSABRAvailList  = 6;

static const uint64_t kSABRFmtItag    = 1;
static const uint64_t kSABRFmtLastMod = 2;
static const uint64_t kSABRFmtXtags   = 3;

static const uint64_t kSABRBufFormatId   = 1;
static const uint64_t kSABRBufStartMs     = 2;
static const uint64_t kSABRBufDurationMs  = 3;
static const uint64_t kSABRBufStartSeg    = 4;
static const uint64_t kSABRBufEndSeg      = 5;
static const uint64_t kSABRBufTimeRange   = 6;
static const uint64_t kSABRTimeRangeStart = 1;
static const uint64_t kSABRTimeRangeDur   = 2;
static const uint64_t kSABRTimeRangeScale = 3;
static const uint64_t kSABRMsPerSecond    = 1000;

static const uint64_t kSABRHdrHeaderId      = 1;
static const uint64_t kSABRHdrItag          = 3;
static const uint64_t kSABRHdrIsInit        = 8;
static const uint64_t kSABRHdrSequence      = 9;
static const uint64_t kSABRHdrStartMs       = 11;
static const uint64_t kSABRHdrDurationMs    = 12;
static const uint64_t kSABRHdrFormatId      = 13;
static const uint64_t kSABRHdrContentLength = 14;
static const uint64_t kSABRHdrTimeRange     = 15;
static const uint64_t kSABRTRStartTicks     = 1;
static const uint64_t kSABRTRDurationTicks  = 2;
static const uint64_t kSABRTRTimescale      = 3;

static const uint64_t kSABRInitFormatId     = 2;
static const uint64_t kSABRInitEndTimeMs    = 3;
static const uint64_t kSABRInitEndSegment   = 4;

static const int kSABRMaxRequests = 400;
static const int kSABRMaxEmptyRounds = 4;

#pragma mark - Protobuf helpers (base-128 varint; distinct from the UMP varint above)

static const int kProtoWireVarint          = 0;
static const int kProtoWire64Bit           = 1;
static const int kProtoWireLengthDelimited = 2;
static const int kProtoWire32Bit           = 5;

static NSUInteger SABRReadProtoVarint(const uint8_t *b, NSUInteger len, NSUInteger pos, uint64_t *out) {
    uint64_t v = 0; int sh = 0; NSUInteger start = pos;
    while (pos < len) {
        uint8_t by = b[pos++];
        v |= ((uint64_t)(by & 0x7f)) << sh;
        if (!(by & 0x80)) { if (out) *out = v; return pos - start; }
        sh += 7; if (sh >= 64) return 0;
    }
    return 0;
}

static void SABRAppendProtoVarint(NSMutableData *d, uint64_t v) {
    uint8_t buf[10]; int n = 0;
    do { uint8_t by = v & 0x7f; v >>= 7; if (v) by |= 0x80; buf[n++] = by; } while (v);
    [d appendBytes:buf length:n];
}
static void SABRAppendVarintField(NSMutableData *d, uint64_t field, uint64_t v) {
    SABRAppendProtoVarint(d, (field << 3) | 0); SABRAppendProtoVarint(d, v);
}
static void SABRAppendBytesField(NSMutableData *d, uint64_t field, NSData *bytes) {
    SABRAppendProtoVarint(d, (field << 3) | 2); SABRAppendProtoVarint(d, bytes.length); [d appendData:bytes];
}

static BOOL SABRIterateTopLevel(NSData *data, BOOL (^handler)(uint64_t field, int wire, NSUInteger fieldStart, NSUInteger fieldEnd, NSUInteger payloadStart, NSUInteger payloadLen)) {
    const uint8_t *b = (const uint8_t *)data.bytes; NSUInteger len = data.length, pos = 0;
    while (pos < len) {
        NSUInteger fieldStart = pos;
        uint64_t key = 0; NSUInteger kc = SABRReadProtoVarint(b, len, pos, &key); if (!kc) return NO; pos += kc;
        uint64_t field = key >> 3; int wire = key & 0x7;
        NSUInteger payloadStart = pos, payloadLen = 0;
        if (wire == kProtoWireVarint) { uint64_t v; NSUInteger c = SABRReadProtoVarint(b, len, pos, &v); if (!c) return NO; payloadLen = c; pos += c; }
        else if (wire == kProtoWire64Bit) { if (pos + 8 > len) return NO; payloadLen = 8; pos += 8; }
        else if (wire == kProtoWireLengthDelimited) { uint64_t l; NSUInteger c = SABRReadProtoVarint(b, len, pos, &l); if (!c || pos + c + l > len) return NO; payloadStart = pos + c; payloadLen = (NSUInteger)l; pos += c + l; }
        else if (wire == kProtoWire32Bit) { if (pos + 4 > len) return NO; payloadLen = 4; pos += 4; }
        else return NO;
        if (handler && !handler(field, wire, fieldStart, pos, payloadStart, payloadLen)) return YES;
    }
    return YES;
}

static BOOL SABRReadVarintField(NSData *msg, uint64_t field, uint64_t *out) {
    const uint8_t *b = (const uint8_t *)msg.bytes; NSUInteger len = msg.length;
    __block BOOL got = NO; __block uint64_t val = 0;
    SABRIterateTopLevel(msg, ^BOOL(uint64_t f, int w, NSUInteger fs, NSUInteger fe, NSUInteger ps, NSUInteger pl) {
        if (f == field && w == kProtoWireVarint) { uint64_t v = 0; if (SABRReadProtoVarint(b, len, ps, &v)) { val = v; got = YES; return NO; } }
        return YES;
    });
    if (got && out) *out = val;
    return got;
}

static NSData *SABRSetVarintField(NSData *msg, uint64_t field, uint64_t value) {
    const uint8_t *b = (const uint8_t *)msg.bytes;
    NSMutableData *out = [NSMutableData data];
    __block BOOL replaced = NO;
    BOOL ok = SABRIterateTopLevel(msg, ^BOOL(uint64_t f, int w, NSUInteger fs, NSUInteger fe, NSUInteger ps, NSUInteger pl) {
        if (f == field && w == kProtoWireVarint) { SABRAppendVarintField(out, field, value); replaced = YES; }
        else [out appendBytes:b + fs length:fe - fs];
        return YES;
    });
    if (!ok) return [msg copy];
    if (!replaced) SABRAppendVarintField(out, field, value);
    return out;
}

#pragma mark - Available formats (#5) → {lastModified, xtags} for a chosen itag

@interface YMSABRFormat : NSObject
@property (nonatomic, assign) uint64_t itag;
@property (nonatomic, assign) uint64_t lastModified;
@property (nonatomic, strong) NSData *xtags;
@property (nonatomic, assign) BOOL found;
@end
@implementation YMSABRFormat @end

static YMSABRFormat *SABRParseFormatId(NSData *fmt) {
    YMSABRFormat *r = [YMSABRFormat new]; r.xtags = [NSData data];
    const uint8_t *b = (const uint8_t *)fmt.bytes; NSUInteger len = fmt.length;
    SABRIterateTopLevel(fmt, ^BOOL(uint64_t f, int w, NSUInteger fs, NSUInteger fe, NSUInteger ps, NSUInteger pl) {
        if (f == kSABRFmtItag && w == kProtoWireVarint)    { uint64_t v = 0; if (SABRReadProtoVarint(b, len, ps, &v)) r.itag = v; }
        else if (f == kSABRFmtLastMod && w == kProtoWireVarint) { uint64_t v = 0; if (SABRReadProtoVarint(b, len, ps, &v)) r.lastModified = v; }
        else if (f == kSABRFmtXtags && w == kProtoWireLengthDelimited)   { r.xtags = [fmt subdataWithRange:NSMakeRange(ps, pl)]; }
        return YES;
    });
    return r;
}

static YMSABRFormat *SABRResolveFormat(NSData *body, uint64_t itag) {
    YMSABRFormat *result = [YMSABRFormat new];
    SABRIterateTopLevel(body, ^BOOL(uint64_t f5, int w5, NSUInteger fs, NSUInteger fe, NSUInteger ps5, NSUInteger pl5) {
        if (f5 != kSABRReqUstreamerConfig || w5 != kProtoWireLengthDelimited) return YES;
        NSData *avail = [body subdataWithRange:NSMakeRange(ps5, pl5)];
        SABRIterateTopLevel(avail, ^BOOL(uint64_t f1, int w1, NSUInteger fs1, NSUInteger fe1, NSUInteger ps1, NSUInteger pl1) {
            if (f1 != kSABRAvailInner || w1 != kProtoWireLengthDelimited) return YES;
            NSData *inner = [avail subdataWithRange:NSMakeRange(ps1, pl1)];
            SABRIterateTopLevel(inner, ^BOOL(uint64_t f6, int w6, NSUInteger fs6, NSUInteger fe6, NSUInteger ps6, NSUInteger pl6) {
                if (f6 != kSABRAvailList || w6 != kProtoWireLengthDelimited) return YES;
                YMSABRFormat *fmt = SABRParseFormatId([inner subdataWithRange:NSMakeRange(ps6, pl6)]);
                if (fmt.itag == itag) {
                    if (!result.found || (result.xtags.length == 0 && fmt.xtags.length > 0)) {
                        result.itag = fmt.itag; result.lastModified = fmt.lastModified;
                        result.xtags = fmt.xtags; result.found = YES;
                    }
                }
                return YES;
            });
            return YES;
        });
        return NO;
    });
    return result;
}

static NSData *SABREncodeFormatId(YMSABRFormat *fmt) {
    NSMutableData *d = [NSMutableData data];
    SABRAppendVarintField(d, kSABRFmtItag, fmt.itag);
    SABRAppendVarintField(d, kSABRFmtLastMod, fmt.lastModified);
    SABRAppendBytesField(d, kSABRFmtXtags, fmt.xtags ?: [NSData data]);
    return d;
}

static NSData *SABREncodeBufferedRange(YMSABRFormat *fmt, uint64_t startSeg, uint64_t endSeg, uint64_t startMs, uint64_t durationMs) {
    NSMutableData *tr = [NSMutableData data];
    SABRAppendVarintField(tr, kSABRTimeRangeStart, startMs);
    SABRAppendVarintField(tr, kSABRTimeRangeDur, durationMs);
    SABRAppendVarintField(tr, kSABRTimeRangeScale, kSABRMsPerSecond);

    NSMutableData *br = [NSMutableData data];
    SABRAppendBytesField(br, kSABRBufFormatId, SABREncodeFormatId(fmt));
    SABRAppendVarintField(br, kSABRBufStartMs, startMs);
    SABRAppendVarintField(br, kSABRBufDurationMs, durationMs);
    SABRAppendVarintField(br, kSABRBufStartSeg, startSeg);
    SABRAppendVarintField(br, kSABRBufEndSeg, endSeg);
    SABRAppendBytesField(br, kSABRBufTimeRange, tr);
    return br;
}

#pragma mark - Response part decoders (MEDIA_HEADER / FORMAT_INIT)

@interface YMSABRMediaHeader : NSObject
@property (nonatomic, assign) uint64_t headerId;
@property (nonatomic, assign) uint64_t itag;
@property (nonatomic, assign) uint64_t sequence;
@property (nonatomic, assign) uint64_t startMs;
@property (nonatomic, assign) uint64_t durationMs;
@property (nonatomic, assign) uint64_t contentLength;
@property (nonatomic, assign) BOOL isInit;
@end
@implementation YMSABRMediaHeader @end

static uint64_t SABRTicksToMs(uint64_t ticks, uint64_t timescale) {
    if (timescale == 0) return 0;
    return (uint64_t)(((double)ticks / (double)timescale) * (double)kSABRMsPerSecond + 0.5);
}

static YMSABRMediaHeader *SABRDecodeMediaHeader(const uint8_t *payload, NSUInteger size) {
    NSData *msg = [NSData dataWithBytesNoCopy:(void *)payload length:size freeWhenDone:NO];
    YMSABRMediaHeader *h = [YMSABRMediaHeader new];
    const uint8_t *b = (const uint8_t *)msg.bytes; NSUInteger len = msg.length;
    SABRIterateTopLevel(msg, ^BOOL(uint64_t f, int w, NSUInteger fs, NSUInteger fe, NSUInteger ps, NSUInteger pl) {
        if (f == kSABRHdrHeaderId && w == kProtoWireVarint)         { uint64_t v=0; if (SABRReadProtoVarint(b,len,ps,&v)) h.headerId = v; }
        else if (f == kSABRHdrItag && w == kProtoWireVarint)        { uint64_t v=0; if (SABRReadProtoVarint(b,len,ps,&v)) h.itag = v; }
        else if (f == kSABRHdrIsInit && w == kProtoWireVarint)      { uint64_t v=0; if (SABRReadProtoVarint(b,len,ps,&v)) h.isInit = (v != 0); }
        else if (f == kSABRHdrSequence && w == kProtoWireVarint)    { uint64_t v=0; if (SABRReadProtoVarint(b,len,ps,&v)) h.sequence = v; }
        else if (f == kSABRHdrStartMs && w == kProtoWireVarint)     { uint64_t v=0; if (SABRReadProtoVarint(b,len,ps,&v)) h.startMs = v; }
        else if (f == kSABRHdrDurationMs && w == kProtoWireVarint)  { uint64_t v=0; if (SABRReadProtoVarint(b,len,ps,&v)) h.durationMs = v; }
        else if (f == kSABRHdrContentLength && w == kProtoWireVarint){ uint64_t v=0; if (SABRReadProtoVarint(b,len,ps,&v)) h.contentLength = v; }
        else if (f == kSABRHdrFormatId && w == kProtoWireLengthDelimited && h.itag == 0) {
            YMSABRFormat *fmt = SABRParseFormatId([msg subdataWithRange:NSMakeRange(ps, pl)]);
            if (fmt.itag) h.itag = fmt.itag;
        }
        else if (f == kSABRHdrTimeRange && w == kProtoWireLengthDelimited) {
            NSData *tr = [msg subdataWithRange:NSMakeRange(ps, pl)];
            uint64_t startTicks = 0, durTicks = 0, timescale = 0;
            SABRReadVarintField(tr, kSABRTRStartTicks, &startTicks);
            SABRReadVarintField(tr, kSABRTRDurationTicks, &durTicks);
            SABRReadVarintField(tr, kSABRTRTimescale, &timescale);
            if (timescale > 0) {
                if (h.durationMs == 0 && durTicks) h.durationMs = SABRTicksToMs(durTicks, timescale);
                if (h.startMs == 0 && startTicks)  h.startMs   = SABRTicksToMs(startTicks, timescale);
            }
        }
        return YES;
    });
    return h;
}

static void SABRDecodeFormatInit(const uint8_t *payload, NSUInteger size, uint64_t *itag, uint64_t *endSeg, uint64_t *endTimeMs) {
    NSData *msg = [NSData dataWithBytesNoCopy:(void *)payload length:size freeWhenDone:NO];
    const uint8_t *b = (const uint8_t *)msg.bytes; NSUInteger len = msg.length;
    __block uint64_t it = 0;
    SABRIterateTopLevel(msg, ^BOOL(uint64_t f, int w, NSUInteger fs, NSUInteger fe, NSUInteger ps, NSUInteger pl) {
        if (f == kSABRInitFormatId && w == kProtoWireLengthDelimited)          { YMSABRFormat *fmt = SABRParseFormatId([msg subdataWithRange:NSMakeRange(ps, pl)]); if (fmt.itag) it = fmt.itag; }
        else if (f == kSABRInitEndSegment && w == kProtoWireVarint)   { uint64_t v=0; if (SABRReadProtoVarint(b,len,ps,&v) && endSeg) *endSeg = v; }
        else if (f == kSABRInitEndTimeMs && w == kProtoWireVarint)    { uint64_t v=0; if (SABRReadProtoVarint(b,len,ps,&v) && endTimeMs) *endTimeMs = v; }
        return YES;
    });
    if (itag) *itag = it;
}

#pragma mark - Per-track download state

@interface YMSABRTrack : NSObject
@property (nonatomic, strong) YMSABRFormat *format;
@property (nonatomic, strong) NSURL *fileURL;
@property (nonatomic, strong) NSFileHandle *handle;
@property (nonatomic, assign) uint64_t downloadedMs;
@property (nonatomic, assign) uint64_t lastSequence;
@property (nonatomic, assign) uint64_t roundStartMs;
@property (nonatomic, assign) uint64_t roundDurationMs;
@property (nonatomic, assign) uint64_t roundFirstSeq;
@property (nonatomic, assign) uint64_t roundLastSeq;
@property (nonatomic, assign) BOOL roundHasMedia;
@property (nonatomic, assign) uint64_t endSegment;
@property (nonatomic, assign) uint64_t endTimeMs;
@property (nonatomic, assign) BOOL initWritten;
@property (nonatomic, assign) BOOL complete;
@property (nonatomic, assign) unsigned long long bytesWritten;
@end
@implementation YMSABRTrack @end

#pragma mark - Capture layer (permanent): the app's live signed videoplayback request

static NSURL *gCapURL;
static NSData *gCapPlainBody;
static NSDictionary *gCapHeaders;
static NSTimeInterval gCapExpire;
static NSString *gCapVideoID;
static BOOL gSABRCancel;

static NSString *SABRCurrentVideoID(void) {
    @try {
        Class pm = NSClassFromString(@"PlayerManager");
        if (pm && [pm respondsToSelector:@selector(sharedInstance)]) {
            id mgr = [pm performSelector:@selector(sharedInstance)];
            if ([mgr respondsToSelector:@selector(currentVideo)]) {
                id cur = [mgr performSelector:@selector(currentVideo)];
                if ([cur respondsToSelector:@selector(videoID)])
                    return [cur performSelector:@selector(videoID)];
            }
        }
    } @catch (id e) {}
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"playerVideoID"];
}

static NSTimeInterval SABRExpireFromURL(NSURL *url) {
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems)
        if ([item.name isEqualToString:@"expire"]) return item.value.doubleValue;
    return 0;
}

%hook HAMDataLoadRequest
- (NSURLRequest *)buildURLRequest {
    NSURLRequest *r = %orig;
    if (!SABR_ENABLED()) return r;
    @try {
        NSString *host = r.URL.host ?: @""; NSString *path = r.URL.path ?: @"";
        if ([host containsString:@"googlevideo"] && [path containsString:@"videoplayback"] &&
            [r.HTTPMethod isEqualToString:@"POST"]) {
            id me = self;
            NSData *plain = nil; @try { plain = [me HTTPBody]; } @catch (id ex) {}
            NSURL *url = r.URL;
            NSData *plainCopy = [plain copy];
            NSMutableDictionary *hdrs = [r.allHTTPHeaderFields mutableCopy] ?: [NSMutableDictionary dictionary];
            dispatch_async(SABRQueue(), ^{
                gCapURL = url; gCapPlainBody = plainCopy; gCapHeaders = hdrs; gCapExpire = SABRExpireFromURL(url);
                gCapVideoID = [SABRCurrentVideoID() copy];
            });
        }
    } @catch (id ex) {}
    return r;
}
%end

#pragma mark - Request builder

static NSData *SABRBuildRequestBody(NSData *orig, YMSABRFormat *videoFmt, YMSABRFormat *audioFmt,
                                    uint64_t playerTimeMs, NSArray<NSData *> *bufferedRanges,
                                    NSArray<NSData *> *selectedFormats) {
    const uint8_t *b = (const uint8_t *)orig.bytes;
    NSMutableData *out = [NSMutableData data];
    BOOL parsed = SABRIterateTopLevel(orig, ^BOOL(uint64_t field, int wire, NSUInteger fs, NSUInteger fe, NSUInteger ps, NSUInteger pl) {
        if (field == kSABRReqSelectedFormats || field == kSABRReqBufferedRanges ||
            field == kSABRReqPreferredAudio || field == kSABRReqPreferredVideo ||
            field == kSABRReqPlayerTimeMs) return YES;
        if (field == kSABRReqClientAbrState && wire == 2) {
            NSData *state = SABRSetVarintField([orig subdataWithRange:NSMakeRange(ps, pl)], kSABRAbrStatePlayerTimeMs, playerTimeMs);
            SABRAppendBytesField(out, kSABRReqClientAbrState, state);
            return YES;
        }
        [out appendBytes:b + fs length:fe - fs];
        return YES;
    });
    if (!parsed) return nil;

    SABRAppendVarintField(out, kSABRReqPlayerTimeMs, playerTimeMs);
    if (audioFmt) SABRAppendBytesField(out, kSABRReqPreferredAudio, SABREncodeFormatId(audioFmt));
    if (videoFmt) SABRAppendBytesField(out, kSABRReqPreferredVideo, SABREncodeFormatId(videoFmt));
    for (NSData *sel in selectedFormats) SABRAppendBytesField(out, kSABRReqSelectedFormats, sel);
    for (NSData *br in bufferedRanges)    SABRAppendBytesField(out, kSABRReqBufferedRanges, br);
    return out;
}

#pragma mark - Download engine (permanent)

static void SABRPostOnce(NSURL *url, NSData *body, void (^completion)(NSData *data, NSHTTPURLResponse *http, NSError *err)) {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.HTTPBody = body;
    [gCapHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
        if ([k caseInsensitiveCompare:@"Content-Encoding"] == NSOrderedSame) return;
        if ([k caseInsensitiveCompare:@"Content-Length"] == NSOrderedSame) return;
        [req setValue:v forHTTPHeaderField:k];
    }];
    NSURLSession *s = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
    [[s dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        completion(data, [resp isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)resp : nil, err);
    }] resume];
}

static void SABRIngestResponse(NSData *data, NSDictionary<NSNumber *, YMSABRTrack *> *tracks,
                               NSString **redirectURL, BOOL *reload) {
    NSMutableDictionary<NSNumber *, YMSABRMediaHeader *> *headers = [NSMutableDictionary dictionary];
    __block NSString *redirect = nil; __block BOOL sawReload = NO;

    for (NSNumber *itag in tracks) {
        YMSABRTrack *t = tracks[itag];
        t.roundHasMedia = NO; t.roundStartMs = 0; t.roundDurationMs = 0; t.roundFirstSeq = 0; t.roundLastSeq = 0;
    }

    SABRParseUMP(data, ^(uint64_t type, const uint8_t *payload, NSUInteger size) {
        if (type == SABRPartMediaHeader) {
            YMSABRMediaHeader *h = SABRDecodeMediaHeader(payload, size);
            headers[@(h.headerId)] = h;
        } else if (type == SABRPartMedia && size > 0) {
            uint64_t hid = 0; NSUInteger hc = SABRReadUMPVarint(payload, size, 0, &hid);
            if (hc == 0 || hc > size) return;
            YMSABRMediaHeader *h = headers[@(hid)];
            YMSABRTrack *track = h ? tracks[@(h.itag)] : nil;
            if (!track) return;
            if (h.isInit) {
                if (!track.initWritten) { [track.handle writeData:[NSData dataWithBytes:payload + hc length:size - hc]]; track.bytesWritten += size - hc; track.initWritten = YES; }
                return;
            }
            if (h.sequence <= track.lastSequence) return;
            [track.handle writeData:[NSData dataWithBytes:payload + hc length:size - hc]];
            track.bytesWritten += size - hc;
        } else if (type == SABRPartMediaEnd && size > 0) {
            YMSABRMediaHeader *h = headers[@(payload[0])];
            YMSABRTrack *track = h ? tracks[@(h.itag)] : nil;
            if (!track || h.isInit) return;
            if (h.sequence <= track.lastSequence) return;
            track.lastSequence = h.sequence;
            track.downloadedMs += h.durationMs;
            if (!track.roundHasMedia) { track.roundHasMedia = YES; track.roundStartMs = h.startMs; track.roundFirstSeq = h.sequence; }
            track.roundDurationMs += h.durationMs;
            track.roundLastSeq = h.sequence;
        } else if (type == SABRPartFormatInit) {
            uint64_t it = 0, endSeg = 0, endMs = 0;
            SABRDecodeFormatInit(payload, size, &it, &endSeg, &endMs);
            YMSABRTrack *track = tracks[@(it)];
            if (track) { if (endSeg) track.endSegment = endSeg; if (endMs) track.endTimeMs = endMs; }
        } else if (type == SABRPartRedirect) {
            NSData *msg = [NSData dataWithBytesNoCopy:(void *)payload length:size freeWhenDone:NO];
            SABRIterateTopLevel(msg, ^BOOL(uint64_t f, int w, NSUInteger fs, NSUInteger fe, NSUInteger ps, NSUInteger pl) {
                if (f == kSABRRedirectURL && w == kProtoWireLengthDelimited) redirect = [[[NSString alloc] initWithData:[msg subdataWithRange:NSMakeRange(ps, pl)] encoding:NSUTF8StringEncoding] copy];
                return NO;
            });
        } else if (type == SABRPartReload) {
            sawReload = YES;
        }
    });

    if (redirectURL) *redirectURL = redirect;
    if (reload) *reload = sawReload;
}

static BOOL SABRTrackDone(YMSABRTrack *track) {
    if (!track.endSegment && !track.endTimeMs) return NO;
    if (track.endSegment && track.lastSequence >= track.endSegment) return YES;
    if (track.endTimeMs && track.downloadedMs + 500 >= track.endTimeMs) return YES;
    return NO;
}

static YMSABRTrack *SABRMakeTrack(YMSABRFormat *fmt, NSString *ext) {
    NSString *name = [NSString stringWithFormat:@"sabr_%llu_%@.%@", fmt.itag, [NSUUID UUID].UUIDString, ext];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
    YMSABRTrack *t = [YMSABRTrack new];
    t.format = fmt;
    t.fileURL = [NSURL fileURLWithPath:path];
    t.handle = [NSFileHandle fileHandleForWritingAtPath:path];
    return t;
}

static void SABRRunDownload(uint64_t videoItag, uint64_t audioItag,
                            void (^progress)(float fraction, unsigned long long bytesDownloaded, BOOL isAudio),
                            void (^completion)(NSURL *videoURL, NSURL *audioURL, NSString *err)) {
    dispatch_async(SABRQueue(), ^{
        if (!gCapURL || !gCapPlainBody.length) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil, @"No request captured yet — play the video for a few seconds first."); });
            return;
        }
        BOOL wantVideo = videoItag != 0;
        YMSABRFormat *videoFmt = wantVideo ? SABRResolveFormat(gCapPlainBody, videoItag) : nil;
        YMSABRFormat *audioFmt = SABRResolveFormat(gCapPlainBody, audioItag);
        if ((wantVideo && !videoFmt.found) || !audioFmt.found) {
            NSString *videoState = !wantVideo ? @"n/a" : (videoFmt.found ? @"ok" : @"missing");
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil, [NSString stringWithFormat:@"format not available (video %llu:%@, audio %llu:%@)", videoItag, videoState, audioItag, audioFmt.found?@"ok":@"missing"]); });
            return;
        }

        gSABRCancel = NO;
        YMSABRTrack *videoTrack = wantVideo ? SABRMakeTrack(videoFmt, @"mp4") : nil;
        YMSABRTrack *audioTrack = SABRMakeTrack(audioFmt, @"m4a");
        NSArray<YMSABRTrack *> *trackList = wantVideo ? @[videoTrack, audioTrack] : @[audioTrack];
        YMSABRTrack *mainTrack = trackList.firstObject;
        NSMutableDictionary<NSNumber *, YMSABRTrack *> *tracks = [NSMutableDictionary dictionary];
        for (YMSABRTrack *t in trackList) tracks[@(t.format.itag)] = t;

        __block int requestCount = 0;
        __block int emptyRounds = 0;
        __block BOOL finished = NO;
        __block NSURL *currentURL = gCapURL;
        NSMutableArray *box = [NSMutableArray arrayWithObject:[NSNull null]];
        void (^callRound)(void) = ^{ id r = box.firstObject; if (r && r != [NSNull null]) ((void (^)(void))r)(); };
        void (^finish)(NSString *) = ^(NSString *err) {
            if (finished) return;
            finished = YES;
            [box removeAllObjects];
            for (YMSABRTrack *t in trackList) [t.handle closeFile];
            if (err) {
                for (YMSABRTrack *t in trackList) [[NSFileManager defaultManager] removeItemAtURL:t.fileURL error:nil];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (err) completion(nil, nil, err);
                else completion(videoTrack.fileURL, audioTrack.fileURL, nil);
            });
        };
        void (^round)(void) = ^{
            if (gSABRCancel) { finish(@"cancelled"); return; }
            if (requestCount++ >= kSABRMaxRequests) { finish(@"exceeded request cap"); return; }

            NSMutableArray<NSData *> *buffered = [NSMutableArray array];
            NSMutableArray<NSData *> *selected = [NSMutableArray array];
            for (YMSABRTrack *t in trackList) {
                if (t.roundHasMedia) {
                    [buffered addObject:SABREncodeBufferedRange(t.format, t.roundFirstSeq, t.roundLastSeq, t.roundStartMs, t.roundDurationMs)];
                }
                if (t.lastSequence > 0) [selected addObject:SABREncodeFormatId(t.format)];
            }
            uint64_t driveTime = mainTrack.downloadedMs;
            NSData *body = SABRBuildRequestBody(gCapPlainBody, videoFmt, audioFmt, driveTime, buffered, selected);
            if (!body) { finish(@"failed to build request body"); return; }

            SABRPostOnce(currentURL, body, ^(NSData *data, NSHTTPURLResponse *http, NSError *err) {
                dispatch_async(SABRQueue(), ^{
                    if (err || !http) { finish([NSString stringWithFormat:@"network error: %@", err.localizedDescription ?: @"no response"]); return; }
                    if (http.statusCode != 200 || !data.length) { finish([NSString stringWithFormat:@"HTTP %ld (%lu bytes)", (long)http.statusCode, (unsigned long)data.length]); return; }

                    NSMutableDictionary<NSNumber *, NSNumber *> *beforeSeq = [NSMutableDictionary dictionary];
                    for (YMSABRTrack *t in trackList) beforeSeq[@(t.format.itag)] = @(t.lastSequence);
                    NSString *redirect = nil; BOOL reload = NO;
                    SABRIngestResponse(data, tracks, &redirect, &reload);

                    if (reload) { finish(@"session expired (RELOAD) — replay the video and try again"); return; }
                    if (redirect.length) currentURL = [NSURL URLWithString:redirect] ?: currentURL;

                    BOOL allDone = YES; float fracSum = 0; unsigned long long bytesTotal = 0;
                    for (YMSABRTrack *t in trackList) {
                        t.complete = SABRTrackDone(t);
                        if (!t.complete) allDone = NO;
                        fracSum += t.endTimeMs ? MIN(1.0f, (float)t.downloadedMs / (float)t.endTimeMs) : 0;
                        bytesTotal += t.bytesWritten;
                    }
                    BOOL isAudio = (videoTrack != nil && videoTrack.complete && audioTrack != nil && !audioTrack.complete);
                    if (progress) progress(fracSum / (float)trackList.count, bytesTotal, isAudio);
                    if (allDone) { finish(nil); return; }
                    BOOL advanced = NO;
                    for (YMSABRTrack *t in trackList)
                        if (!t.complete && t.lastSequence > beforeSeq[@(t.format.itag)].unsignedLongLongValue) advanced = YES;
                    emptyRounds = advanced ? 0 : (emptyRounds + 1);
                    if (emptyRounds >= kSABRMaxEmptyRounds) { finish(@"stalled — no forward progress for several rounds"); return; }
                    callRound();
                });
            });
        };
        box[0] = round;
        round();
    });
}

#pragma mark - Public entry (called from Download.x)

@implementation YMSABR
+ (void)downloadVideoItag:(int)videoItag audioItag:(int)audioItag
                 progress:(void (^)(float fraction, unsigned long long bytesDownloaded, BOOL isAudio))progress
               completion:(void (^)(NSURL *videoURL, NSURL *audioURL, NSString *err))completion {
    SABRRunDownload((uint64_t)videoItag, (uint64_t)audioItag,
        ^(float f, unsigned long long bytes, BOOL isAudio) { if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(f, bytes, isAudio); }); },
        completion);
}
+ (void)downloadAudioItag:(int)audioItag
                 progress:(void (^)(float fraction, unsigned long long bytesDownloaded))progress
               completion:(void (^)(NSURL *audioURL, NSString *err))completion {
    SABRRunDownload(0, (uint64_t)audioItag,
        ^(float f, unsigned long long bytes, BOOL isAudio) { if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(f, bytes); }); },
        ^(NSURL *videoURL, NSURL *audioURL, NSString *err) { completion(audioURL, err); });
}
+ (void)cancelCurrent {
    dispatch_async(SABRQueue(), ^{ gSABRCancel = YES; });
}
@end

#pragma mark - uYouEnhanced fallback helpers

BOOL UYTSABRHasValidCapture(void) {
    return UYTSABRHasValidCaptureForVideoID(nil);
}

BOOL UYTSABRHasValidCaptureForVideoID(NSString *videoID) {
    __block BOOL valid = NO;
    void (^evaluate)(void) = ^{
        if (gCapURL == nil || gCapPlainBody.length == 0 || gCapExpire <= 0) return;
        NSTimeInterval now = [NSDate date].timeIntervalSince1970;
        if (gCapExpire < now + 60) return;
        valid = YES;
        if (videoID.length && gCapVideoID.length) {
            if (![gCapVideoID isEqualToString:videoID]) valid = NO;
        }
    };
    if (SABROnQueue()) {
        evaluate();
    } else {
        dispatch_sync(SABRQueue(), evaluate);
    }
    return valid;
}

static NSMutableSet *gSABRInFlightVideoIDs;

BOOL UYTSABRIsDownloadActive(NSString *videoID) {
    if (!videoID.length) return NO;
    __block BOOL active = NO;
    void (^check)(void) = ^{
        if (gSABRInFlightVideoIDs) active = [gSABRInFlightVideoIDs containsObject:videoID];
    };
    if (SABROnQueue()) {
        check();
    } else {
        dispatch_sync(SABRQueue(), check);
    }
    return active;
}

void UYTSABRFallbackDownloadForVideoID(NSString *videoID,
                                      NSString * _Nullable title,
                                      BOOL audioOnly,
                                      void (^_Nullable progress)(double fractionComplete, unsigned long long bytesDownloaded),
                                      void (^done)(BOOL success, NSString * _Nullable error)) {
    dispatch_async(SABRQueue(), ^{
        if (!gSABRInFlightVideoIDs) gSABRInFlightVideoIDs = [NSMutableSet set];
        [gSABRInFlightVideoIDs addObject:videoID];
        void (^completion)(BOOL success, NSString * _Nullable error) = ^(BOOL success, NSString * _Nullable error) {
            dispatch_async(SABRQueue(), ^{
                if (gSABRInFlightVideoIDs) [gSABRInFlightVideoIDs removeObject:videoID];
            });
            if (done) done(success, error);
        };
        if (!gCapURL || !gCapPlainBody.length) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, @"No SABR capture yet — play the video for a few seconds first.");
            });
            return;
        }
        int videoItag = 0;
        int audioItag = 0;
        int videoCandidates[] = {137, 136, 135, 134, 133, 160, 0};
        int audioCandidates[] = {140, 139, 141, 0};
        for (int i = 0; videoCandidates[i] != 0; i++) {
            YMSABRFormat *fmt = SABRResolveFormat(gCapPlainBody, (uint64_t)videoCandidates[i]);
            if (fmt.found) { videoItag = videoCandidates[i]; break; }
        }
        for (int i = 0; audioCandidates[i] != 0; i++) {
            YMSABRFormat *fmt = SABRResolveFormat(gCapPlainBody, (uint64_t)audioCandidates[i]);
            if (fmt.found) { audioItag = audioCandidates[i]; break; }
        }
        if (videoItag == 0 && audioItag == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, @"No compatible mp4/m4a itags in SABR capture.");
            });
            return;
        }
        if (audioOnly) {
            videoItag = 0;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (videoItag != 0 && audioItag != 0) {
                [YMSABR downloadVideoItag:videoItag audioItag:audioItag progress:^(float f, unsigned long long bytes, BOOL isAudio) {
                    if (progress) progress((double)f, bytes);
                } completion:^(NSURL *videoURL, NSURL *audioURL, NSString *err) {
                    if (err || !videoURL || !audioURL) {
                        completion(NO, err ?: @"SABR download failed");
                        return;
                    }
                    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
                    NSString *outDir = [docs stringByAppendingPathComponent:@"Downloaded"];
                    [[NSFileManager defaultManager] createDirectoryAtPath:outDir withIntermediateDirectories:YES attributes:nil error:nil];
                    NSString *safeTitle = title.length ? title : videoID;
                    NSCharacterSet *invalid = [NSCharacterSet characterSetWithCharactersInString:@"/\\?%*|\"<>:"];
                    safeTitle = [[safeTitle componentsSeparatedByCharactersInSet:invalid] componentsJoinedByString:@" "];
                    safeTitle = [safeTitle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if (safeTitle.length > 120) safeTitle = [safeTitle substringToIndex:120];
                    if (!safeTitle.length) safeTitle = videoID;
                    NSString *outPath = [outDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4", safeTitle]];
                    NSUInteger idx = 2;
                    while ([[NSFileManager defaultManager] fileExistsAtPath:outPath]) {
                        outPath = [outDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %lu.mp4", safeTitle, (unsigned long)idx++]];
                    }
                    BOOL muxed = NO;
                    @try {
                        // Ask the loader, do not peek for the ObjC class: FFmpegKitNext
                        // is dlopen'd lazily from our own bundle, so the class is absent
                        // on a cold launch until something triggers the probe.
                        if (UYTFFActiveBackend() != UYTFFBackendNone) {
                            muxed = UYTFFSmartRemuxToMP4(videoURL.path, audioURL.path, outPath);
                        }
                    } @catch (NSException *e) {}
                    if (!muxed) {
                        [[NSUserDefaults standardUserDefaults] setObject:videoURL.path forKey:@"UYTSABRVideoPath"];
                        [[NSUserDefaults standardUserDefaults] setObject:audioURL.path forKey:@"UYTSABRAudioPath"];
                    } else {
                        [[NSUserDefaults standardUserDefaults] setObject:outPath forKey:@"UYTSABRVideoPath"];
                        [[NSUserDefaults standardUserDefaults] setObject:outPath forKey:@"UYTSABRAudioPath"];
                        [[NSFileManager defaultManager] removeItemAtPath:videoURL.path error:nil];
                        [[NSFileManager defaultManager] removeItemAtPath:audioURL.path error:nil];
                    }
                    NSString *canonPath = [outDir stringByAppendingPathComponent:
                                           [NSString stringWithFormat:@"%@.mp4", videoID]];
                    NSString *produced = muxed ? outPath : videoURL.path;
                    if (produced.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:produced]) {
                        [[NSFileManager defaultManager] removeItemAtPath:canonPath error:nil];
                        [[NSFileManager defaultManager] copyItemAtPath:produced toPath:canonPath error:nil];
                    }
                    [[NSUserDefaults standardUserDefaults] setObject:videoID forKey:@"UYTSABRVideoID"];
                    completion(YES, nil);
                }];
            } else if (audioItag != 0) {
                [YMSABR downloadAudioItag:audioItag progress:^(float f, unsigned long long bytes) {
                    if (progress) progress((double)f, bytes);
                } completion:^(NSURL *audioURL, NSString *err) {
                    if (err || !audioURL) {
                        completion(NO, err ?: @"SABR audio download failed");
                        return;
                    }
                    [[NSUserDefaults standardUserDefaults] setObject:audioURL.path forKey:@"UYTSABRAudioPath"];
                    NSString *docs2 = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
                    NSString *outDir2 = [docs2 stringByAppendingPathComponent:@"Downloaded"];
                    [[NSFileManager defaultManager] createDirectoryAtPath:outDir2 withIntermediateDirectories:YES attributes:nil error:nil];
                    NSString *canonAudio = [outDir2 stringByAppendingPathComponent:
                                            [NSString stringWithFormat:@"%@.m4a", videoID]];
                    if ([[NSFileManager defaultManager] fileExistsAtPath:audioURL.path]) {
                        [[NSFileManager defaultManager] removeItemAtPath:canonAudio error:nil];
                        [[NSFileManager defaultManager] copyItemAtPath:audioURL.path toPath:canonAudio error:nil];
                    }
                    [[NSUserDefaults standardUserDefaults] setObject:videoID forKey:@"UYTSABRVideoID"];
                    completion(YES, nil);
                }];
            } else {
                completion(NO, @"No audio itag available for SABR fallback.");
            }
        });
    });
}

