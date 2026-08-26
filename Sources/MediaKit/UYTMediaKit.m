#import "UYTMediaKit.h"
#import <dlfcn.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSInteger UYTFFCachedBackend = -1; // -1 = not probed yet

static void UYTFFProbe(void) {
    if (UYTFFCachedBackend != -1) return;

    // ffmpegkit.framework hard-links every av*/sw* library, and its install
    // names use @rpath which the host app may not resolve. Preload each
    // dependency by explicit path (dependencies first) so the shell loads.
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

            // ReturnCode object with -isSuccess, or a plain numeric exit code.
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
            // Older wrapper shape: session state string.
            if ([session respondsToSelector:@selector(getState)]) {
                NSString *state = [NSString stringWithFormat:@"%@",
                    ((id (*)(id, SEL))objc_msgSend)(session, @selector(getState))];
                return [state containsString:@"COMPLETED"];
            }
            return NO;
        }

        // MobileFFmpeg: class method returning the int exit code.
        int rc = ((int (*)(id, SEL, NSArray *))objc_msgSend)(
            kitClass, @selector(executeWithArguments:), arguments);
        return rc == 0;
    } @catch (NSException *e) {
        NSLog(@"[UYTMediaKit] command failed (%@): %@", arguments.firstObject ?: @"", e);
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
