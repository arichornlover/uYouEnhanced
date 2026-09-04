// UYTMediaKit — ffmpeg backend abstraction for the download pipeline.
//
// Backend priority:
//   1. FFmpegKitNext  (ffmpegkit.framework embedded in the app — dlopen'd)
//   2. MobileFFmpeg   (legacy copy inside uYou.dylib)
//   3. none           (callers fall back to uYou's stock behavior)
//
// All calls are synchronous and safe from background queues.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// UYTMediaKit.m compiles as Objective-C (unmangled C symbols), while .xm
// callers compile as Objective-C++ (mangled symbols). extern "C" makes both
// sides agree on the symbol names.
#ifdef __cplusplus
extern "C" {
#endif

typedef NS_ENUM(NSInteger, UYTFFBackend) {
    UYTFFBackendNone = 0,
    UYTFFBackendKitNext,
    UYTFFBackendMobile,
};

/// Which backend will run commands (probes lazily, result cached).
NSInteger UYTFFActiveBackend(void);

/// Run an ffmpeg command. Returns YES when the exit code is 0.
BOOL UYTFFRun(NSArray<NSString *> *arguments);

/// Convert a .webm audio track to .m4a (AAC).
BOOL UYTFFConvertWebmAudioToM4a(NSString *webmPath, NSString *m4aPath);

/// Stream-copy remux video+audio into an mp4 at outputPath.
BOOL UYTFFRemuxVideoAudioToMP4(NSString *videoPath, NSString *audioPath, NSString *outputPath);

/// Re-encode a .webm (VP9/Opus) video to .mp4 (H.264/AAC) at outputPath.
/// Uses libx264 with ultrafast preset for speed; falls back to VideoToolbox
/// if libx264 is unavailable.  Returns YES on success.
BOOL UYTFFConvertWebmVideoToMp4(NSString *webmPath, NSString *mp4Path);

/// Remux video+audio into mp4, re-encoding the video track to H.264 when the
/// source is webm/VP9 (which can't be stream-copied into an mp4 container).
/// Falls back to plain stream-copy when the video is already H.264.
BOOL UYTFFSmartRemuxToMP4(NSString *videoPath, NSString *audioPath, NSString *outputPath);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
