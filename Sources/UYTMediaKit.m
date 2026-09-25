#import "UYTMediaKit.h"
#import "UYTLog.h"
#import <dlfcn.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSInteger UYTFFCachedBackend = -1;

static void UYTFFProbe(void) {
    if (UYTFFCachedBackend != -1 && UYTFFCachedBackend != UYTFFBackendNone) return;

    const char *libs[] = {
        "libavutil", "libswresample", "libavcodec",
        "libavformat", "libavdevice", "libavfilter", "libswscale",
    };
    for (int i = 0; i < sizeof(libs) / sizeof(libs[0]); i++) {
        char path[256];
        snprintf(path, sizeof(path),
                 "@executable_path/Frameworks/%s.framework/%s", libs[i], libs[i]);
        dlopen(path, RTLD_LAZY | RTLD_GLOBAL);
    }
    dlopen("@executable_path/Frameworks/ffmpegkit.framework/ffmpegkit",
           RTLD_LAZY | RTLD_GLOBAL);

    if (objc_getClass("FFmpegKit")) UYTFFCachedBackend = UYTFFBackendKitNext;
    else if (objc_getClass("MobileFFmpeg")) UYTFFCachedBackend = UYTFFBackendMobile;
    else UYTFFCachedBackend = UYTFFBackendNone;
}

NSInteger UYTFFActiveBackend(void) {
    UYTFFProbe();
    return UYTFFCachedBackend;
}

BOOL UYTFFRun(NSArray<NSString *> *arguments) {
    UYTFFProbe();

    Class kitClass = Nil;
    BOOL isKitNext = (UYTFFCachedBackend == UYTFFBackendKitNext);
    if (UYTFFCachedBackend == UYTFFBackendNone) return NO;
    kitClass = objc_getClass(isKitNext ? "FFmpegKit" : "MobileFFmpeg");
    if (!kitClass) return NO;

    @try {
        if (isKitNext) {
            id session = ((id (*)(id, SEL, NSArray *))objc_msgSend)(
                kitClass, @selector(executeWithArguments:), arguments);
            if (!session) return NO;

            if ([session respondsToSelector:@selector(getReturnCode)]) {
                id rc = ((id (*)(id, SEL))objc_msgSend)(session, @selector(getReturnCode));
                if ([rc respondsToSelector:@selector(isSuccess)]) {
                    return ((BOOL (*)(id, SEL))objc_msgSend)(rc, @selector(isSuccess));
                }
                if ([rc respondsToSelector:@selector(getIntValue)]) {
                    return ((long (*)(id, SEL))objc_msgSend)(rc, @selector(getIntValue)) == 0;
                }
                if ([rc respondsToSelector:@selector(intValue)]) {
                    return [rc intValue] == 0;
                }
                return NO;
            }
            if ([session respondsToSelector:@selector(getState)]) {
                NSString *state = [NSString stringWithFormat:@"%@",
                    ((id (*)(id, SEL))objc_msgSend)(session, @selector(getState))];
                return [state containsString:@"COMPLETED"];
            }
            return NO;
        }

        int rc = ((int (*)(id, SEL, NSArray *))objc_msgSend)(
            kitClass, @selector(executeWithArguments:), arguments);
        return rc == 0;
    } @catch (NSException *e) {
        UYTDebugErr(@"UYTMediaKit command failed (%@): %@", arguments.firstObject ?: @"", e);
        return NO;
    }
}

BOOL UYTFFConvertWebmAudioToM4a(NSString *webmPath, NSString *m4aPath) {
    return UYTFFRun(@[
        @"-i", webmPath,
        @"-vn",
        @"-acodec", @"aac",
        @"-strict", @"-2",
        @"-y",
        m4aPath,
    ]);
}

BOOL UYTFFRemuxVideoAudioToMP4(NSString *videoPath, NSString *audioPath, NSString *outputPath) {
    return UYTFFRun(@[
        @"-i", videoPath,
        @"-i", audioPath,
        @"-c", @"copy",
        @"-strict", @"-2",
        @"-movflags", @"+faststart",
        @"-y",
        outputPath,
    ]);
}

static BOOL uytPathIsWebm(NSString *path) {
    return path.length > 0 && [path.pathExtension.lowercaseString isEqualToString:@"webm"];
}

BOOL UYTFFConvertWebmVideoToMp4(NSString *webmPath, NSString *mp4Path) {
    if (!webmPath.length || !mp4Path.length) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:webmPath]) return NO;
    if ([fm fileExistsAtPath:mp4Path]) [fm removeItemAtPath:mp4Path error:nil];

    BOOL ok = UYTFFRun(@[
        @"-i", webmPath,
        @"-c:v", @"libx264",
        @"-preset", @"medium",
        @"-crf", @"22",
        @"-pix_fmt", @"yuv420p",
        @"-c:a", @"copy",
        @"-movflags", @"+faststart",
        @"-y",
        mp4Path,
    ]);
    if (ok && [fm fileExistsAtPath:mp4Path]) {
        unsigned long long sz = [[fm attributesOfItemAtPath:mp4Path error:nil] fileSize];
        if (sz > 0) return YES;
    }
    if ([fm fileExistsAtPath:mp4Path]) [fm removeItemAtPath:mp4Path error:nil];

    ok = UYTFFRun(@[
        @"-i", webmPath,
        @"-c:v", @"h264_videotoolbox",
        @"-b:v", @"8M",
        @"-pix_fmt", @"yuv420p",
        @"-c:a", @"copy",
        @"-movflags", @"+faststart",
        @"-y",
        mp4Path,
    ]);
    if (ok && [fm fileExistsAtPath:mp4Path]) {
        unsigned long long sz = [[fm attributesOfItemAtPath:mp4Path error:nil] fileSize];
        if (sz > 0) return YES;
    }
    if ([fm fileExistsAtPath:mp4Path]) [fm removeItemAtPath:mp4Path error:nil];
    return NO;
}

BOOL UYTFFSmartRemuxToMP4(NSString *videoPath, NSString *audioPath, NSString *outputPath) {
    if (!videoPath.length || !audioPath.length || !outputPath.length) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:videoPath] || ![fm fileExistsAtPath:audioPath]) return NO;
    if ([fm fileExistsAtPath:outputPath]) [fm removeItemAtPath:outputPath error:nil];

    BOOL videoIsWebm = uytPathIsWebm(videoPath);
    BOOL audioIsWebm = uytPathIsWebm(audioPath);

    if (!videoIsWebm && !audioIsWebm) {
        return UYTFFRemuxVideoAudioToMP4(videoPath, audioPath, outputPath);
    }

    NSString *tmpVideo = videoPath;
    NSString *tmpAudio = audioPath;
    BOOL cleanupVideo = NO;
    BOOL cleanupAudio = NO;

    if (videoIsWebm) {
        NSString *tmpVideoPath = [outputPath stringByAppendingString:@".vt.mp4"];
        BOOL converted = UYTFFConvertWebmVideoToMp4(videoPath, tmpVideoPath);
        if (!converted || ![fm fileExistsAtPath:tmpVideoPath]) {
            if ([fm fileExistsAtPath:tmpVideoPath]) [fm removeItemAtPath:tmpVideoPath error:nil];
            return NO;
        }
        tmpVideo = tmpVideoPath;
        cleanupVideo = YES;
    }

    if (audioIsWebm) {
        NSString *tmpAudioPath = [outputPath stringByAppendingString:@".at.m4a"];
        BOOL converted = UYTFFConvertWebmAudioToM4a(audioPath, tmpAudioPath);
        if (!converted || ![fm fileExistsAtPath:tmpAudioPath]) {
            if ([fm fileExistsAtPath:tmpAudioPath]) [fm removeItemAtPath:tmpAudioPath error:nil];
            if (cleanupVideo && [fm fileExistsAtPath:tmpVideo]) [fm removeItemAtPath:tmpVideo error:nil];
            return NO;
        }
        tmpAudio = tmpAudioPath;
        cleanupAudio = YES;
    }

    BOOL ok = UYTFFRemuxVideoAudioToMP4(tmpVideo, tmpAudio, outputPath);

    if (cleanupVideo && [fm fileExistsAtPath:tmpVideo]) [fm removeItemAtPath:tmpVideo error:nil];
    if (cleanupAudio && [fm fileExistsAtPath:tmpAudio]) [fm removeItemAtPath:tmpAudio error:nil];

    return ok;
}

