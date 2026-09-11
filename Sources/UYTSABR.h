// UYTSABR.h — Public interface for vendored SABR engine (YouMod SABRDownload.x)
// Credit: @Tonwalter888 / YouMod 2.0.0 — https://github.com/Tonwalter888/YouMod
// Vendored as Sources/UYTSABR.xm, adapted for uYouEnhanced (always-on fallback for 21.29+).

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// SABR engine — downloads via captured signed videoplayback request + UMP.
// Produces elementary files (mp4 video + m4a audio) for FFmpegKitNext muxing.
@interface YMSABR : NSObject
+ (void)downloadVideoItag:(int)videoItag audioItag:(int)audioItag
                 progress:(void (^)(float fraction, unsigned long long bytesDownloaded, BOOL isAudio))progress
               completion:(void (^)(NSURL * _Nullable videoURL, NSURL * _Nullable audioURL, NSString * _Nullable err))completion;

+ (void)downloadAudioItag:(int)audioItag
                 progress:(void (^)(float fraction, unsigned long long bytesDownloaded))progress
               completion:(void (^)(NSURL * _Nullable audioURL, NSString * _Nullable err))completion;

+ (void)cancelCurrent;
@end

// Helper to check if SABR has a valid captured request (for fallback gating)
BOOL UYTSABRHasValidCapture(void);

// Fallback entry for uYou pipeline: download best mp4+m4a for videoID via SABR,
// then mux with FFmpegKitNext and finalize via uYou's DB. Called when innertube
// returns -1002 / empty URLs on YouTube 21.29+.
// If audioOnly is YES, only downloads audio (for audio-only Shorts downloads).
void UYTSABRFallbackDownloadForVideoID(NSString *videoID,
                                      NSString * _Nullable title,
                                      BOOL audioOnly,
                                      void (^completion)(BOOL success, NSString * _Nullable error));

NS_ASSUME_NONNULL_END
