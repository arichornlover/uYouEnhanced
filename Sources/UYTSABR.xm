// UYTSABR.xm — Vendored SABR engine from YouMod 2.0.0's SABRDownload.x
// Credit: @Tonwalter888 / YouMod — https://github.com/Tonwalter888/YouMod
// Adapted for uYouEnhanced: always-on fallback for YouTube 21.29+ (-1002).
// Original header: SABRDownload.x — On-device SABR download (opt-in, behind the SABRDownload toggle).
//
// Modern YouTube (21.29) ships no direct stream URL; media flows via SABR (server-
// driven adaptive bitrate) over the UMP byte protocol. This downloads on-device by
// CAPTURING the app's own live, fully-signed `videoplayback` request (which already
// carries the session's auth / PoToken in its URL) and REPLAYING a modified copy of
// it — selecting the mp4 itags we want, then reading the returned UMP media parts to
// disk — instead of reconstructing a SABR session from scratch. The two elementary
// files are handed to YouMod's existing muxer for the final mp4.
//
// Additive: gated on SABR_ENABLED(), off by default. Touches none of the existing
// (direct / server) download paths.
//
// Protocol field numbers follow LuanRT/googlevideo (cross-checked against
// coletdjnz/yt-dlp-ytse and Epic0001/YTKACE) but are pinned to what YouTube 21.29
// actually sends; see docs/specs/2026-07-29-sabr-ondevice-download-final.md. They are
// version-sensitive — every wire field is a named constant below so a YouTube update
// can be re-mapped in one place.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// uYouEnhanced: SABR is always enabled as a fallback for YouTube 21.29+
// where innertube returns -1002 (unsupported URL). The capture hook runs
// unconditionally so we always have a signed videoplayback request ready.
// Original YouMod gate was: (INTFORVAL(DownloadMethod) == DownloadMethodOnDevice)
#define SABR_ENABLED() (1)

// Forward declarations for YouTube classes (Headers.h not available in uYouEnhanced)
@interface HAMDataLoadRequest : NSObject
- (NSURLRequest *)buildURLRequest;
- (NSData *)HTTPBody;
@property (nonatomic, readonly) NSURL *URL;
@property (nonatomic, readonly) NSDictionary *allHTTPHeaderFields;
@property (nonatomic, readonly) NSString *HTTPMethod;
@end

// Minimal stubs for YouMod macros used in SABRDownload.x
#ifndef INTFORVAL
#define INTFORVAL(x) (0)
#endif
#ifndef DownloadMethod
#define DownloadMethod @"DownloadMethod"
#endif
#ifndef DownloadMethodOnDevice
#define DownloadMethodOnDevice 2
#endif

// Serial queue guarding all shared engine state (capture globals, per-download
// bookkeeping). Capture hooks and network completions fire on arbitrary threads and
// hop here before touching shared state.
static dispatch_queue_t SABRQueue(void) {
    static dispatch_queue_t q; static dispatch_once_t o;
    dispatch_once(&o, ^{ q = dispatch_queue_create("youmod.sabr", DISPATCH_QUEUE_SERIAL); });
    return q;
}

#pragma mark - UMP parser

// UMP varint: leading 1-bits of the first byte give total byte count (1..5).
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

// UMP part type IDs (LuanRT/googlevideo ump_part_id.proto).
typedef NS_ENUM(NSInteger, SABRPartType) {
    SABRPartMediaHeader      = 20,
    SABRPartMedia            = 21,
    SABRPartMediaEnd         = 22,
    SABRPartNextRequestPolicy = 35,
    SABRPartFormatInit       = 42, // FORMAT_INITIALIZATION_METADATA
    SABRPartRedirect         = 43, // SABR_REDIRECT (new URL)
    SABRPartError            = 44, // SABR_ERROR
    SABRPartReload           = 46, // RELOAD_PLAYER_RESPONSE
    SABRPartContextUpdate    = 57, // SABR_CONTEXT_UPDATE
    SABRPartStreamProtection = 58, // STREAM_PROTECTION_STATUS
};

// SABR_REDIRECT (part 43) payload: #1 = the replacement videoplayback URL (string).
static const uint64_t kSABRRedirectURL = 1;

// Parse a UMP stream, invoking `handler` per part with (type, payload). Returns
// bytes consumed. Payload for MEDIA parts still includes the leading headerId
// varint (caller strips it).
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

// VideoPlaybackAbrRequest top-level fields.
static const uint64_t kSABRReqClientAbrState  = 1;  // keep verbatim; only #28 player_time overridden
static const uint64_t kSABRReqSelectedFormats = 2;  // "initialized" echo list (empty until init metadata arrives)
static const uint64_t kSABRReqBufferedRanges  = 3;  // what we already hold (drives advancement)
static const uint64_t kSABRReqPlayerTimeMs    = 4;  // top-level player time
static const uint64_t kSABRReqUstreamerConfig = 5;  // ustreamer/policy blob; also carries the available-format list
static const uint64_t kSABRReqPreferredAudio  = 16; // preferred_audio_format_ids — the AUDIO download target
static const uint64_t kSABRReqPreferredVideo  = 17; // preferred_video_format_ids — the VIDEO download target
// (#19 streamer_context is kept verbatim via the copy-everything-else path.)

static const uint64_t kSABRAbrStatePlayerTimeMs = 28; // ClientAbrState.player_time_ms

// #5 -> #1 -> #6 repeated FormatId = the full available-format list (source of lastModified + xtags).
static const uint64_t kSABRAvailInner = 1; // #5.#1
static const uint64_t kSABRAvailList  = 6; // #5.#1.#6 repeated FormatId

// FormatId { #1 itag, #2 last_modified, #3 xtags }.
static const uint64_t kSABRFmtItag    = 1;
static const uint64_t kSABRFmtLastMod = 2;
static const uint64_t kSABRFmtXtags   = 3;

// BufferedRange { #1 formatId, #2 start_time_ms, #3 duration_ms, #4 start_segment_index,
//                 #5 end_segment_index, #6 TimeRange } ; TimeRange { #1 start, #2 duration, #3 timescale }.
static const uint64_t kSABRBufFormatId   = 1;
static const uint64_t kSABRBufStartMs     = 2;
static const uint64_t kSABRBufDurationMs  = 3;
static const uint64_t kSABRBufStartSeg    = 4;
static const uint64_t kSABRBufEndSeg      = 5;
static const uint64_t kSABRBufTimeRange   = 6;
static const uint64_t kSABRTimeRangeStart = 1;
static const uint64_t kSABRTimeRangeDur   = 2;
static const uint64_t kSABRTimeRangeScale = 3;
static const uint64_t kSABRMsPerSecond    = 1000; // ms timebase (also the timescale we emit)

// MediaHeader (UMP part 20) fields. On 21.29 the scalar start/duration (#11/#12) are
// absent and their values come from the #15 TimeRange instead.
static const uint64_t kSABRHdrHeaderId      = 1;
static const uint64_t kSABRHdrItag          = 3;
static const uint64_t kSABRHdrIsInit        = 8;
static const uint64_t kSABRHdrSequence      = 9;
static const uint64_t kSABRHdrStartMs       = 11; // segment start (ms), scalar — when present
static const uint64_t kSABRHdrDurationMs    = 12; // segment duration (ms), scalar — when present
static const uint64_t kSABRHdrFormatId      = 13; // fallback FormatId (has itag/xtags)
static const uint64_t kSABRHdrContentLength = 14;
static const uint64_t kSABRHdrTimeRange     = 15; // TimeRange { startTicks, durationTicks, timescale }
static const uint64_t kSABRTRStartTicks     = 1;
static const uint64_t kSABRTRDurationTicks  = 2;
static const uint64_t kSABRTRTimescale      = 3;

// FormatInitializationMetadata (UMP part 42) — a track's total length. #1 is the
// video_id string; the FormatId is at #2.
static const uint64_t kSABRInitFormatId     = 2; // FormatId { itag, lastModified, xtags }
static const uint64_t kSABRInitEndTimeMs    = 3; // total duration ms
static const uint64_t kSABRInitEndSegment   = 4; // last segment index

// Cap on request round-trips per download (safety backstop, never hit in practice).
static const int kSABRMaxRequests = 400;
// Bail after this many CONSECUTIVE rounds with no new media (a policy-only round is
// normal; a run of them means the download is genuinely stuck).
static const int kSABRMaxEmptyRounds = 4;

#pragma mark - Protobuf helpers (base-128 varint; distinct from the UMP varint above)

// Protobuf wire types (low 3 bits of a field key).
static const int kProtoWireVarint          = 0;
static const int kProtoWire64Bit           = 1;
static const int kProtoWireLengthDelimited = 2;
static const int kProtoWire32Bit           = 5;

// Read a base-128 varint. Returns bytes consumed (0 on malformed/truncated input).
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

// Walk ONE level of a protobuf message. handler receives each field's number, wire
// type, the byte span of the whole field (tag..end), and its payload span. Return NO
// from handler to stop early. Returns YES only if the buffer parsed cleanly
// end-to-end (a malformed field aborts with NO).
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

// Read one varint field's value from a message (first match). Returns whether found.
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

// Return a copy of `msg` with varint `field` set to `value` (replacing an existing
// one in place, or appended if absent). Non-target fields are copied byte-for-byte.
static NSData *SABRSetVarintField(NSData *msg, uint64_t field, uint64_t value) {
    const uint8_t *b = (const uint8_t *)msg.bytes;
    NSMutableData *out = [NSMutableData data];
    __block BOOL replaced = NO;
    BOOL ok = SABRIterateTopLevel(msg, ^BOOL(uint64_t f, int w, NSUInteger fs, NSUInteger fe, NSUInteger ps, NSUInteger pl) {
        if (f == field && w == kProtoWireVarint) { SABRAppendVarintField(out, field, value); replaced = YES; }
        else [out appendBytes:b + fs length:fe - fs];
        return YES;
    });
    if (!ok) return [msg copy]; // don't corrupt a body we can't parse
    if (!replaced) SABRAppendVarintField(out, field, value);
    return out;
}

#pragma mark - Available formats (#5) → {lastModified, xtags} for a chosen itag

// A resolved download target: itag + the lastModified/xtags copied verbatim from #5.
@interface YMSABRFormat : NSObject
@property (nonatomic, assign) uint64_t itag;
@property (nonatomic, assign) uint64_t lastModified;
@property (nonatomic, strong) NSData *xtags;   // may be empty; always emitted (matches the real client)
@property (nonatomic, assign) BOOL found;
@end
@implementation YMSABRFormat @end

// Parse a FormatId message → {itag, lastModified, xtags}.
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

// Resolve a download target for `itag` from the available-format list (#5.#1.#6).
// Some itags appear twice — a plain entry and an xtags-tagged variant (distinct
// formats, not versions). We prefer the xtags variant because that's what the app
// itself selects (our capture played 251 with xtags), and we copy {itag,
// lastModified, xtags} as one consistent triple so server-side matching lines up.
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
                    // Keep the first match, but upgrade to an entry that carries xtags.
                    if (!result.found || (result.xtags.length == 0 && fmt.xtags.length > 0)) {
                        result.itag = fmt.itag; result.lastModified = fmt.lastModified;
                        result.xtags = fmt.xtags; result.found = YES;
                    }
                }
                return YES;
            });
            return YES;
        });
        return NO; // only the first #5
    });
    return result;
}

// Encode a FormatId submessage { #1 itag, #2 lastModified, #3 xtags }. xtags is
// always emitted (empty string if none) — matches YTKACE / the real client.
static NSData *SABREncodeFormatId(YMSABRFormat *fmt) {
    NSMutableData *d = [NSMutableData data];
    SABRAppendVarintField(d, kSABRFmtItag, fmt.itag);
    SABRAppendVarintField(d, kSABRFmtLastMod, fmt.lastModified);
    SABRAppendBytesField(d, kSABRFmtXtags, fmt.xtags ?: [NSData data]);
    return d;
}

// Encode a BufferedRange reporting the REAL extent just received for a track:
// segments [startSeg..endSeg] spanning [startMs, startMs+durationMs). Reporting the
// true extent (not player_time) is essential — overstating it makes the server think
// the track is fully buffered and stop sending its remaining segments.
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

// Decoded MEDIA_HEADER (UMP part 20): maps a headerId to a format + segment.
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

// Convert a TimeRange tick count to milliseconds (rounded).
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
        else if (f == kSABRHdrFormatId && w == kProtoWireLengthDelimited && h.itag == 0) { // fallback itag from nested FormatId
            YMSABRFormat *fmt = SABRParseFormatId([msg subdataWithRange:NSMakeRange(ps, pl)]);
            if (fmt.itag) h.itag = fmt.itag;
        }
        else if (f == kSABRHdrTimeRange && w == kProtoWireLengthDelimited) { // TimeRange — the start/duration source on 21.29
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

// FORMAT_INITIALIZATION_METADATA (part 42): the authoritative end-of-track marker.
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

// Accumulates one track's media (keyed by ITAG, not headerId — the init segment and
// media segments of a track arrive under different headerIds). Written to `fileURL`.
@interface YMSABRTrack : NSObject
@property (nonatomic, strong) YMSABRFormat *format;
@property (nonatomic, strong) NSURL *fileURL;
@property (nonatomic, strong) NSFileHandle *handle;
@property (nonatomic, assign) uint64_t downloadedMs;   // real total downloaded duration (sum of segment durations)
@property (nonatomic, assign) uint64_t lastSequence;   // highest segment index written
// Per-round window of NEW segments (for the buffered_range we report each round —
// the reference sends a delta window, not a cumulative 0..N range).
@property (nonatomic, assign) uint64_t roundStartMs;
@property (nonatomic, assign) uint64_t roundDurationMs;
@property (nonatomic, assign) uint64_t roundFirstSeq;
@property (nonatomic, assign) uint64_t roundLastSeq;
@property (nonatomic, assign) BOOL roundHasMedia;
@property (nonatomic, assign) uint64_t endSegment;     // from FORMAT_INIT (0 = unknown)
@property (nonatomic, assign) uint64_t endTimeMs;      // from FORMAT_INIT (0 = unknown)
@property (nonatomic, assign) BOOL initWritten;
@property (nonatomic, assign) BOOL complete;
@property (nonatomic, assign) unsigned long long bytesWritten;
@end
@implementation YMSABRTrack @end

#pragma mark - Capture layer (permanent): the app's live signed videoplayback request

// Captured request material — tracks the MOST-RECENT videoplayback request, i.e. the
// currently watched video, so switching videos re-captures the new one. Capturing
// mid-playback is safe: the engine rebuilds the buffered ranges (#3) and selected
// formats from scratch and never depends on the captured body's own ranges.
// Touched only on SABRQueue.
static NSURL *gCapURL;
static NSData *gCapPlainBody;      // pre-Brotli body (from -HTTPBody)
static NSDictionary *gCapHeaders;
static NSTimeInterval gCapExpire;  // from the URL's expire= param
static BOOL gSABRCancel;           // set to abort the active download loop (touched on SABRQueue)

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
                // Most-recent-wins: always track the latest videoplayback request (the
                // current video), so switching videos captures the new one.
                gCapURL = url; gCapPlainBody = plainCopy; gCapHeaders = hdrs; gCapExpire = SABRExpireFromURL(url);
            });
        }
    } @catch (id ex) {}
    return r;
}
%end

#pragma mark - Request builder

// Build one request body targeting `videoFmt` + `audioFmt`:
//   #16 = preferred audio FormatId, #17 = preferred video FormatId (the real
//         download targets — sent every request).
//   #2  = the "initialized" echo list (empty until formats initialize).
//   #3  = buffered ranges we already hold (empty = stream from start).
//   #1.#28 + #4 = player_time_ms (advances the stream).
//   #1 / #5 / #19 kept byte-for-byte (auth/session/config stay intact).
// `bufferedRanges` / `selectedFormats` are pre-encoded FormatId/BufferedRange
// submessages (nil/empty on the first request).
static NSData *SABRBuildRequestBody(NSData *orig, YMSABRFormat *videoFmt, YMSABRFormat *audioFmt,
                                    uint64_t playerTimeMs, NSArray<NSData *> *bufferedRanges,
                                    NSArray<NSData *> *selectedFormats) {
    const uint8_t *b = (const uint8_t *)orig.bytes;
    NSMutableData *out = [NSMutableData data];
    BOOL parsed = SABRIterateTopLevel(orig, ^BOOL(uint64_t field, int wire, NSUInteger fs, NSUInteger fe, NSUInteger ps, NSUInteger pl) {
        // Drop the fields we rebuild; copy everything else verbatim.
        if (field == kSABRReqSelectedFormats || field == kSABRReqBufferedRanges ||
            field == kSABRReqPreferredAudio || field == kSABRReqPreferredVideo ||
            field == kSABRReqPlayerTimeMs) return YES;
        if (field == kSABRReqClientAbrState && wire == 2) {
            // Override player_time_ms (#28) inside the ClientAbrState, keep the rest.
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

// One network round-trip: POST `body` uncompressed to the captured signed URL,
// return the raw UMP response. Called ON SABRQueue (it reads gCapHeaders); the
// NSURLSession completion runs on an arbitrary queue, so the caller's completion
// block must hop back to SABRQueue before touching shared state.
static void SABRPostOnce(NSURL *url, NSData *body, void (^completion)(NSData *data, NSHTTPURLResponse *http, NSError *err)) {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.HTTPBody = body;
    [gCapHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
        if ([k caseInsensitiveCompare:@"Content-Encoding"] == NSOrderedSame) return; // no Brotli
        if ([k caseInsensitiveCompare:@"Content-Length"] == NSOrderedSame) return;   // session sets it
        [req setValue:v forHTTPHeaderField:k];
    }];
    NSURLSession *s = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
    [[s dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        completion(data, [resp isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)resp : nil, err);
    }] resume];
}

// Parse one UMP response, routing media to whichever track (by itag) it belongs to.
// Writes init segments (once) + media segments, updates each track's lastSequence,
// downloaded duration, per-round window, and FORMAT_INIT markers, and reports any
// redirect URL / reload flag via out-params.
static void SABRIngestResponse(NSData *data, NSDictionary<NSNumber *, YMSABRTrack *> *tracks,
                               NSString **redirectURL, BOOL *reload) {
    NSMutableDictionary<NSNumber *, YMSABRMediaHeader *> *headers = [NSMutableDictionary dictionary]; // headerId -> header
    __block NSString *redirect = nil; __block BOOL sawReload = NO;

    // Reset each track's per-round window; it's rebuilt from the real headers below.
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
            if (!track) return; // media for a format we're not collecting
            if (h.isInit) {
                if (!track.initWritten) { [track.handle writeData:[NSData dataWithBytes:payload + hc length:size - hc]]; track.bytesWritten += size - hc; track.initWritten = YES; }
                return;
            }
            // A segment can arrive more than once (same sequence, different headerId)
            // when pacing changes; only sequences beyond the high-water mark are new.
            // Writing a duplicate would corrupt the elementary stream.
            if (h.sequence <= track.lastSequence) return;
            [track.handle writeData:[NSData dataWithBytes:payload + hc length:size - hc]];
            track.bytesWritten += size - hc;
        } else if (type == SABRPartMediaEnd && size > 0) {
            YMSABRMediaHeader *h = headers[@(payload[0])];
            YMSABRTrack *track = h ? tracks[@(h.itag)] : nil;
            if (!track || h.isInit) return;
            if (h.sequence <= track.lastSequence) return; // duplicate segment: don't double-count
            track.lastSequence = h.sequence;
            track.downloadedMs += h.durationMs;           // real total from #15-derived duration
            // Extend this round's contiguous window with the segment's real timing.
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
                // -copy detaches from the transient no-copy payload.
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

// A track is complete once it has reached its last segment (authoritative), or its
// real downloaded duration has reached the total (belt-and-suspenders).
static BOOL SABRTrackDone(YMSABRTrack *track) {
    if (!track.endSegment && !track.endTimeMs) return NO;        // no markers yet → not done
    if (track.endSegment && track.lastSequence >= track.endSegment) return YES;
    if (track.endTimeMs && track.downloadedMs + 500 >= track.endTimeMs) return YES;
    return NO;
}

// Open a fresh unique temp file for a track (unique per download so a stale or
// concurrent run can't collide/overwrite).
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

// Orchestrator: download the video itag + audio itag together (both requested every
// round; media routed to a file per track by itag) until every track reaches its
// last segment, then call `completion(videoURL, audioURL, err)` on the main queue.
// Pass videoItag == 0 for an audio-only download (videoURL is then nil).
// NB: named SABRRunDownload, not SABRDownload — the latter is a settings-key macro.
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
        // Ordered [video?, audio]; `mainTrack` (first = video when present, else audio)
        // drives player_time, matching the reference's "drive off the main format".
        NSArray<YMSABRTrack *> *trackList = wantVideo ? @[videoTrack, audioTrack] : @[audioTrack];
        YMSABRTrack *mainTrack = trackList.firstObject;
        NSMutableDictionary<NSNumber *, YMSABRTrack *> *tracks = [NSMutableDictionary dictionary];
        for (YMSABRTrack *t in trackList) tracks[@(t.format.itag)] = t;

        __block int requestCount = 0;
        __block int emptyRounds = 0;   // consecutive rounds with no new media (SABR may send policy-only rounds)
        __block BOOL finished = NO;
        __block NSURL *currentURL = gCapURL;
        // Recursive loop across async network callbacks: hold the block in a heap box
        // and recurse through it (a direct capture is an ARC retain-cycle error);
        // `finish` empties the box to free the loop.
        NSMutableArray *box = [NSMutableArray arrayWithObject:[NSNull null]];
        void (^callRound)(void) = ^{ id r = box.firstObject; if (r && r != [NSNull null]) ((void (^)(void))r)(); };
        void (^finish)(NSString *) = ^(NSString *err) {
            if (finished) return;   // idempotent: never double-close / double-complete
            finished = YES;
            [box removeAllObjects];
            for (YMSABRTrack *t in trackList) [t.handle closeFile];
            if (err) { // failed/cancelled → don't leave partial files behind
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

            // Each requested format stays in its preferred field (#16/#17) for the whole
            // session; a finished track is silenced only by its buffered_ranges (which
            // tell the server it is fully buffered). Removing a completed format from
            // #16/#17 instead would change the request shape and stall the other track.
            NSMutableArray<NSData *> *buffered = [NSMutableArray array];
            NSMutableArray<NSData *> *selected = [NSMutableArray array];
            // Report each track's REAL per-round window (the delta of segments received
            // last round: real start/duration/first/last from #15 time_range), as the
            // reference does — never player_time. Overstating a track's buffered extent
            // makes the server treat it as complete and stop sending its tail segments.
            for (YMSABRTrack *t in trackList) {
                if (t.roundHasMedia) {
                    [buffered addObject:SABREncodeBufferedRange(t.format, t.roundFirstSeq, t.roundLastSeq, t.roundStartMs, t.roundDurationMs)];
                }
                if (t.lastSequence > 0) [selected addObject:SABREncodeFormatId(t.format)];
            }
            // Drive player_time off the main track's real downloaded total (video when
            // present, else audio). The playhead stays at/ahead of each track's buffered
            // edge and pulls the remaining segments forward.
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
                    // Stall guard keys off SEQUENCE advancement, not raw bytes: a request
                    // that can't make progress still returns the same segment (nonzero
                    // bytes, no new sequence), so a bytes check would never trip. Bail
                    // after several CONSECUTIVE rounds where no INCOMPLETE track advanced.
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

// Download the chosen mp4 video itag + m4a audio itag on-device via SABR, producing
// two elementary files. `progress` (0..1) and `completion` are always delivered on
// the main queue. The caller hands the two files to its existing muxer.
@interface YMSABR : NSObject
+ (void)downloadVideoItag:(int)videoItag audioItag:(int)audioItag
                 progress:(void (^)(float fraction, unsigned long long bytesDownloaded, BOOL isAudio))progress
               completion:(void (^)(NSURL *videoURL, NSURL *audioURL, NSString *err))completion;
+ (void)downloadAudioItag:(int)audioItag
                 progress:(void (^)(float fraction, unsigned long long bytesDownloaded))progress
               completion:(void (^)(NSURL *audioURL, NSString *err))completion;
+ (void)cancelCurrent;
@end

@implementation YMSABR
+ (void)downloadVideoItag:(int)videoItag audioItag:(int)audioItag
                 progress:(void (^)(float fraction, unsigned long long bytesDownloaded, BOOL isAudio))progress
               completion:(void (^)(NSURL *videoURL, NSURL *audioURL, NSString *err))completion {
    SABRRunDownload((uint64_t)videoItag, (uint64_t)audioItag,
        ^(float f, unsigned long long bytes, BOOL isAudio) { if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(f, bytes, isAudio); }); },
        completion); // SABRRunDownload already delivers completion on the main queue
}
+ (void)downloadAudioItag:(int)audioItag
                 progress:(void (^)(float fraction, unsigned long long bytesDownloaded))progress
               completion:(void (^)(NSURL *audioURL, NSString *err))completion {
    // videoItag 0 → audio-only; deliver just the audio file.
    SABRRunDownload(0, (uint64_t)audioItag,
        ^(float f, unsigned long long bytes, BOOL isAudio) { if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(f, bytes); }); },
        ^(NSURL *videoURL, NSURL *audioURL, NSString *err) { completion(audioURL, err); });
}
+ (void)cancelCurrent {
    dispatch_async(SABRQueue(), ^{ gSABRCancel = YES; }); // loop aborts at its next round
}
@end

#pragma mark - uYouEnhanced fallback helpers

BOOL UYTSABRHasValidCapture(void) {
    __block BOOL valid = NO;
    dispatch_sync(SABRQueue(), ^{
        valid = (gCapURL != nil && gCapPlainBody.length > 0 && gCapExpire > 0);
        if (valid) {
            NSTimeInterval now = [NSDate date].timeIntervalSince1970;
            valid = (gCapExpire > now + 60); // 60s buffer
        }
    });
    return valid;
}

// Fallback entry for uYou pipeline: download best mp4+m4a for videoID via SABR,
// then mux with FFmpegKitNext and finalize via uYou's DB. Called when innertube
// returns -1002 / empty URLs on YouTube 21.29+.
// If audioOnly is YES, only downloads audio (for audio-only Shorts downloads).
void UYTSABRFallbackDownloadForVideoID(NSString *videoID,
                                      NSString * _Nullable title,
                                      BOOL audioOnly,
                                      void (^completion)(BOOL success, NSString * _Nullable error)) {
    // Pick best available itags from captured body's available-format list.
    // We resolve 137 (1080p mp4) + 140 (m4a) as defaults, falling back to
    // whatever the capture actually advertises.
    dispatch_async(SABRQueue(), ^{
        if (!gCapURL || !gCapPlainBody.length) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, @"No SABR capture yet — play the video for a few seconds first.");
            });
            return;
        }
        // Try preferred itags in order; pick first found.
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
        // If audioOnly, ignore videoItag even if found.
        if (audioOnly) {
            videoItag = 0;
        }
        // If only one side found, do audio-only or video-only.
        dispatch_async(dispatch_get_main_queue(), ^{
            // Hand off to YMSABR on main queue (it hops to SABRQueue internally)
            if (videoItag != 0 && audioItag != 0) {
                [YMSABR downloadVideoItag:videoItag audioItag:audioItag progress:^(float f, unsigned long long bytes, BOOL isAudio) {
                    // Progress is handled by caller if needed
                } completion:^(NSURL *videoURL, NSURL *audioURL, NSString *err) {
                    if (err || !videoURL || !audioURL) {
                        completion(NO, err ?: @"SABR download failed");
                        return;
                    }
                    // Mux with FFmpegKitNext (UYTMediaKit) into final mp4.
                    // This mirrors YouMod's Download.x mergeVideoURL:audioURL: flow but
                    // uses FFmpegKitNext instead of AVFoundation for webm/VP9 safety.
                    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
                    NSString *outDir = [docs stringByAppendingPathComponent:@"uYouDownloads"];
                    [[NSFileManager defaultManager] createDirectoryAtPath:outDir withIntermediateDirectories:YES attributes:nil error:nil];
                    NSString *safeTitle = title.length ? title : videoID;
                    // Sanitize filename (YouMod: YouModSanitizedFileName)
                    NSCharacterSet *invalid = [NSCharacterSet characterSetWithCharactersInString:@"/\\?%*|\"<>:"];
                    safeTitle = [[safeTitle componentsSeparatedByCharactersInSet:invalid] componentsJoinedByString:@" "];
                    safeTitle = [safeTitle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if (safeTitle.length > 120) safeTitle = [safeTitle substringToIndex:120];
                    if (!safeTitle.length) safeTitle = videoID;
                    NSString *outPath = [outDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4", safeTitle]];
                    // Ensure unique filename
                    NSUInteger idx = 2;
                    while ([[NSFileManager defaultManager] fileExistsAtPath:outPath]) {
                        outPath = [outDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %lu.mp4", safeTitle, (unsigned long)idx++]];
                    }
                    BOOL muxed = NO;
                    @try {
                        // UYTMediaKit is available via DownloadPipeline.h chain; use runtime check
                        Class kit = NSClassFromString(@"FFmpegKit");
                        if (!kit) kit = NSClassFromString(@"MobileFFmpeg");
                        if (kit) {
                            // Use UYTMediaKit smart remux (handles webm→mp4 transcoding)
                            extern BOOL UYTFFSmartRemuxToMP4(NSString *, NSString *, NSString *);
                            muxed = UYTFFSmartRemuxToMP4(videoURL.path, audioURL.path, outPath);
                        }
                    } @catch (NSException *e) {}
                    if (!muxed) {
                        // Fallback: just keep files as-is and report via NSUserDefaults
                        [[NSUserDefaults standardUserDefaults] setObject:videoURL.path forKey:@"UYTSABRVideoPath"];
                        [[NSUserDefaults standardUserDefaults] setObject:audioURL.path forKey:@"UYTSABRAudioPath"];
                    } else {
                        [[NSUserDefaults standardUserDefaults] setObject:outPath forKey:@"UYTSABRVideoPath"];
                        [[NSUserDefaults standardUserDefaults] setObject:outPath forKey:@"UYTSABRAudioPath"];
                        // Clean up elementary files after successful mux
                        [[NSFileManager defaultManager] removeItemAtPath:videoURL.path error:nil];
                        [[NSFileManager defaultManager] removeItemAtPath:audioURL.path error:nil];
                    }
                    [[NSUserDefaults standardUserDefaults] setObject:videoID forKey:@"UYTSABRVideoID"];
                    completion(YES, nil);
                }];
            } else if (audioItag != 0) {
                [YMSABR downloadAudioItag:audioItag progress:^(float f, unsigned long long bytes) {
                } completion:^(NSURL *audioURL, NSString *err) {
                    if (err || !audioURL) {
                        completion(NO, err ?: @"SABR audio download failed");
                        return;
                    }
                    // Remux fragmented mp4 audio to clean m4a (YouMod: exportSABRAudioURL)
                    // For now, just stash the elementary file; uYouPatches will handle conversion
                    [[NSUserDefaults standardUserDefaults] setObject:audioURL.path forKey:@"UYTSABRAudioPath"];
                    [[NSUserDefaults standardUserDefaults] setObject:videoID forKey:@"UYTSABRVideoID"];
                    completion(YES, nil);
                }];
            } else {
                completion(NO, @"No audio itag available for SABR fallback.");
            }
        });
    });
}
