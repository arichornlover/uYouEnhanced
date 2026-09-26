#import "UYTMediaKit.h"
#import "UYTLog.h"
#import "UYTFileSize.h"
#import <dlfcn.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <string.h>

static NSInteger UYTFFCachedBackend = -1;

static NSString *UYTFFLoadFailure = nil;
static NSString *UYTFFLoadedRoot = nil;
static BOOL UYTFFProbed = NO;

static NSString *UYTFFUnavailableReason(void);

static NSArray<NSString *> *UYTFFLibraries(void) {
    return @[@"libavutil", @"libswresample", @"libswscale",
             @"libavcodec", @"libavformat", @"libavfilter", @"libavdevice"];
}

static NSString *UYTFFBinaryPath(NSString *root, NSString *name) {
    return [[root stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"framework"]]
            stringByAppendingPathComponent:name];
}

// Our own FFmpegKitNext copy is staged into uYouMedia.bundle at build time by
// tools/stage-ffmpeg.sh, so nothing here depends on whatever ffmpeg YouTube
// happens to vendor. Mirrors YouMod's resolver: ask the main bundle first (the
// Makefile embeds Bundles/*.bundle), then the jailbreak roots, so the same
// binary works jailed and rootless without taking a jbroot dependency.
static NSString *UYTMediaBundlePath(void) {
    static NSString *path = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *found = [[NSBundle mainBundle] pathForResource:@"uYouMedia" ofType:@"bundle"];
        if (!found.length) {
            for (NSString *candidate in @[@"/var/jb/Library/Application Support/uYouMedia.bundle",
                                          @"/Library/Application Support/uYouMedia.bundle"]) {
                if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) { found = candidate; break; }
            }
        }
        path = found;
    });
    return path;
}

static NSArray<NSString *> *UYTFFCandidateRoots(void) {
    NSMutableArray<NSString *> *roots = [NSMutableArray array];
    NSString *bundle = UYTMediaBundlePath();
    if (bundle.length) [roots addObject:bundle];
    // Last resort so a build that never staged our frameworks still works.
    [roots addObject:@"@executable_path/Frameworks"];
    return roots;
}

static void UYTFFProbe(void) {
    if (UYTFFProbed) return;
    UYTFFProbed = YES;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *problems = [NSMutableArray array];

    for (NSString *root in UYTFFCandidateRoots()) {
        NSString *failure = nil;
        BOOL ok = YES;
        for (NSString *library in UYTFFLibraries()) {
            NSString *binary = UYTFFBinaryPath(root, library);
            if (![fm fileExistsAtPath:binary]) {
                ok = NO;
                failure = [NSString stringWithFormat:@"missing %@", library];
                break;
            }
            if (!dlopen(binary.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL)) {
                ok = NO;
                failure = [NSString stringWithFormat:@"dlopen %@: %s", library, dlerror() ?: "unknown"];
                break;
            }
        }
        if (!ok) {
            [problems addObject:[NSString stringWithFormat:@"%@ (%@)", root, failure]];
            continue;
        }

        NSString *facade = UYTFFBinaryPath(root, @"ffmpegkit");
        if (![fm fileExistsAtPath:facade] ||
            !dlopen(facade.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL)) {
            [problems addObject:[NSString stringWithFormat:@"%@ (dlopen ffmpegkit: %s)",
                                 root, dlerror() ?: "unknown"]];
            continue;
        }

        UYTFFLoadedRoot = root;
        break;
    }

    if (objc_getClass("FFmpegKit")) UYTFFCachedBackend = UYTFFBackendKitNext;
    else if (objc_getClass("MobileFFmpeg")) UYTFFCachedBackend = UYTFFBackendMobile;
    else UYTFFCachedBackend = UYTFFBackendNone;

    if (UYTFFCachedBackend == UYTFFBackendNone) {
        UYTFFLoadFailure = problems.count ? [problems componentsJoinedByString:@"; "] : @"no ffmpeg frameworks found";
    }
}

NSInteger UYTFFActiveBackend(void) {
    UYTFFProbe();
    if (UYTFFCachedBackend == UYTFFBackendNone) {
        UYTDebugWarn(@"[uYouPatches] ffmpeg unavailable: %@", UYTFFUnavailableReason());
    } else {
        BOOL ours = ![UYTFFLoadedRoot isEqualToString:@"@executable_path/Frameworks"];
        UYTDebugInfo(@"[uYouPatches] ffmpeg backend %ld ready from %@ (%@)",
                     (long)UYTFFCachedBackend, UYTFFLoadedRoot ?: @"?",
                     ours ? @"our bundle" : @"YouTube fallback");
    }
    return UYTFFCachedBackend;
}

static NSString *UYTFFCommandLine(NSArray<NSString *> *arguments) {
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:arguments.count];
    for (NSString *arg in arguments) {
        if ([arg hasPrefix:@"-"]) [parts addObject:arg];
        else if ([arg containsString:@"/"]) [parts addObject:[NSString stringWithFormat:@"\"%@\"", arg]];
        else [parts addObject:arg];
    }
    return [parts componentsJoinedByString:@" "];
}

static NSString *UYTFFUnavailableReason(void) {
    return UYTFFLoadFailure ?: @"no ffmpeg frameworks found in any search root";
}

BOOL UYTFFRun(NSArray<NSString *> *arguments) {
    UYTFFProbe();

    NSString *command = UYTFFCommandLine(arguments);

    if (UYTFFCachedBackend == UYTFFBackendNone) {
        UYTDebugErr(@"[uYouPatches] ffmpeg backend unavailable (%@) - command dropped: %@",
                    UYTFFUnavailableReason(), command);
        return NO;
    }

    Class kitClass = objc_getClass(UYTFFCachedBackend == UYTFFBackendKitNext ? "FFmpegKit" : "MobileFFmpeg");
    if (!kitClass) {
        UYTDebugErr(@"[uYouPatches] ffmpeg class missing - command dropped: %@", command);
        return NO;
    }

    BOOL isKitNext = (UYTFFCachedBackend == UYTFFBackendKitNext);
    BOOL ok = NO;
    long rc = -1;
    id session = nil;

    @try {
        if (isKitNext) {
            session = ((id (*)(id, SEL, NSArray *))objc_msgSend)(
                kitClass, @selector(executeWithArguments:), arguments);
            if (session) {
                if ([session respondsToSelector:@selector(getReturnCode)]) {
                    id ret = ((id (*)(id, SEL))objc_msgSend)(session, @selector(getReturnCode));
                    if ([ret respondsToSelector:@selector(isSuccess)]) {
                        ok = ((BOOL (*)(id, SEL))objc_msgSend)(ret, @selector(isSuccess));
                    }
                    if ([ret respondsToSelector:@selector(getIntValue)]) {
                        rc = (long)((long (*)(id, SEL))objc_msgSend)(ret, @selector(getIntValue));
                        if (![ret respondsToSelector:@selector(isSuccess)]) {
                            ok = (rc == 0);
                        }
                    } else if (![ret respondsToSelector:@selector(isSuccess)] &&
                               [ret respondsToSelector:@selector(intValue)]) {
                        rc = (long)[ret intValue];
                        ok = (rc == 0);
                    }
                } else if ([session respondsToSelector:@selector(getState)]) {
                    NSString *state = [NSString stringWithFormat:@"%@",
                        ((id (*)(id, SEL))objc_msgSend)(session, @selector(getState))];
                    ok = [state containsString:@"COMPLETED"];
                    if (!ok) rc = -2;
                }
            }
        } else {
            rc = ((int (*)(id, SEL, NSArray *))objc_msgSend)(
                kitClass, @selector(executeWithArguments:), arguments);
            ok = (rc == 0);
        }
    } @catch (NSException *e) {
        UYTDebugErr(@"[uYouPatches] ffmpeg threw while running: %@ (%@)", command, e);
        return NO;
    }

    if (ok) {
        UYTDebugInfo(@"[uYouPatches] ffmpeg ok: %@", command);
    } else {
        NSString *detail = nil;
        if (session && [session respondsToSelector:@selector(getOutput)]) {
            id output = ((id (*)(id, SEL))objc_msgSend)(session, @selector(getOutput));
            if ([output isKindOfClass:[NSString class]] && [(NSString *)output length]) {
                NSArray<NSString *> *lines = [(NSString *)output
                    componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
                NSUInteger take = MIN((NSUInteger)8, lines.count);
                detail = [[lines subarrayWithRange:NSMakeRange(lines.count - take, take)]
                    componentsJoinedByString:@" | "];
            }
        }
        UYTDebugWarn(@"[uYouPatches] ffmpeg FAILED (rc=%ld): %@%@", rc, command,
                     detail.length ? [@" -> " stringByAppendingString:detail] : @"");
    }
    return ok;
}

static BOOL UYTOutputIsUsable(NSString *path) {
    if (!path.length) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) return NO;
    if (UYTSizeOfFile(path) > 0) return YES;
    [fm removeItemAtPath:path error:nil];
    return NO;
}

typedef NS_ENUM(NSInteger, UYTContainer) {
    UYTContainerUnknown = 0,
    UYTContainerWebm,
    UYTContainerOgg,
    UYTContainerMP4,
};

static UYTContainer UYTProbeContainer(NSString *path) {
    if (path.length < 1) return UYTContainerUnknown;
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) return UYTContainerUnknown;
    NSData *head = nil;
    @try {
        [fh seekToFileOffset:0];
        head = [fh readDataOfLength:16];
    } @catch (NSException *e) {
        head = nil;
    }
    @try { [fh closeFile]; } @catch (NSException *e) {}
    if (head.length < 4) return UYTContainerUnknown;
    const uint8_t *b = (const uint8_t *)head.bytes;
    if (b[0] == 0x1A && b[1] == 0x45 && b[2] == 0xDF && b[3] == 0xA3) return UYTContainerWebm;
    if (b[0] == 'O' && b[1] == 'g' && b[2] == 'g' && b[3] == 'S') return UYTContainerOgg;
    if (head.length >= 8 && memcmp(b + 4, "ftyp", 4) == 0) return UYTContainerMP4;
    return UYTContainerUnknown;
}

BOOL UYTFileLooksLikeWebm(NSString *path) {
    if (path.length < 1) return NO;
    UYTContainer c = UYTProbeContainer(path);
    if (c == UYTContainerWebm || c == UYTContainerOgg) return YES;
    if (c == UYTContainerMP4) return NO;
    return [path.pathExtension.lowercaseString isEqualToString:@"webm"];
}

static BOOL uytPathIsWebm(NSString *path) {
    return UYTFileLooksLikeWebm(path);
}

BOOL UYTFFConvertWebmAudioToM4a(NSString *webmPath, NSString *m4aPath) {
    if (!webmPath.length || !m4aPath.length) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:webmPath]) return NO;
    if ([fm fileExistsAtPath:m4aPath]) [fm removeItemAtPath:m4aPath error:nil];

    BOOL ok = UYTFFRun(@[
        @"-i", webmPath,
        @"-map", @"0:a:0",
        @"-vn",
        @"-c:a", @"aac",
        @"-b:a", @"160k",
        @"-ar", @"44100",
        @"-ac", @"2",
        @"-strict", @"-2",
        @"-y",
        m4aPath,
    ]);
    if (ok && UYTOutputIsUsable(m4aPath)) return YES;
    if ([fm fileExistsAtPath:m4aPath]) [fm removeItemAtPath:m4aPath error:nil];
    return NO;
}

BOOL UYTFFRemuxVideoAudioToMP4(NSString *videoPath, NSString *audioPath, NSString *outputPath) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:outputPath]) [fm removeItemAtPath:outputPath error:nil];

    BOOL ok = UYTFFRun(@[
        @"-i", videoPath,
        @"-i", audioPath,
        @"-map", @"0:v:0",
        @"-map", @"1:a:0",
        @"-c", @"copy",
        @"-strict", @"-2",
        @"-movflags", @"+faststart",
        @"-y",
        outputPath,
    ]);
    if (ok && UYTOutputIsUsable(outputPath)) return YES;
    if ([fm fileExistsAtPath:outputPath]) [fm removeItemAtPath:outputPath error:nil];

    ok = UYTFFRun(@[
        @"-i", videoPath,
        @"-i", audioPath,
        @"-map", @"0:v:0",
        @"-map", @"1:a:0",
        @"-c:v", @"copy",
        @"-c:a", @"aac",
        @"-b:a", @"160k",
        @"-ar", @"44100",
        @"-ac", @"2",
        @"-strict", @"-2",
        @"-movflags", @"+faststart",
        @"-y",
        outputPath,
    ]);
    if (ok && UYTOutputIsUsable(outputPath)) return YES;
    if ([fm fileExistsAtPath:outputPath]) [fm removeItemAtPath:outputPath error:nil];
    return NO;
}

BOOL UYTFFConvertWebmVideoToMp4(NSString *webmPath, NSString *mp4Path) {
    if (!webmPath.length || !mp4Path.length) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:webmPath]) return NO;
    if ([fm fileExistsAtPath:mp4Path]) [fm removeItemAtPath:mp4Path error:nil];

    BOOL ok = UYTFFRun(@[
        @"-i", webmPath,
        @"-map", @"0:v:0",
        @"-map", @"0:a:0?",
        @"-c:v", @"libx264",
        @"-preset", @"medium",
        @"-crf", @"22",
        @"-pix_fmt", @"yuv420p",
        @"-c:a", @"aac",
        @"-b:a", @"160k",
        @"-ar", @"44100",
        @"-ac", @"2",
        @"-strict", @"-2",
        @"-movflags", @"+faststart",
        @"-y",
        mp4Path,
    ]);
    if (ok && UYTOutputIsUsable(mp4Path)) return YES;
    if ([fm fileExistsAtPath:mp4Path]) [fm removeItemAtPath:mp4Path error:nil];

    ok = UYTFFRun(@[
        @"-i", webmPath,
        @"-map", @"0:v:0",
        @"-map", @"0:a:0?",
        @"-c:v", @"h264_videotoolbox",
        @"-b:v", @"8M",
        @"-pix_fmt", @"yuv420p",
        @"-c:a", @"aac",
        @"-b:a", @"160k",
        @"-ar", @"44100",
        @"-ac", @"2",
        @"-strict", @"-2",
        @"-movflags", @"+faststart",
        @"-y",
        mp4Path,
    ]);
    if (ok && UYTOutputIsUsable(mp4Path)) return YES;
    if ([fm fileExistsAtPath:mp4Path]) [fm removeItemAtPath:mp4Path error:nil];

    ok = UYTFFRun(@[
        @"-i", webmPath,
        @"-map", @"0:v:0",
        @"-map", @"0:a:0?",
        @"-c", @"copy",
        @"-strict", @"-2",
        @"-movflags", @"+faststart",
        @"-y",
        mp4Path,
    ]);
    if (ok && UYTOutputIsUsable(mp4Path)) return YES;
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

