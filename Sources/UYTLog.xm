// UYTLog.xm — in-app debug logging for uYouEnhanced.
//
// Two capture paths:
//   1. UYTDebugInfo/Warn/Err — call sites that matter (DownloadPipeline fetches,
//      403 reroutes, retries, merges, watchdog). Always captured.
//   2. A stderr tee — everything NSLog/HBLog/fprintf(stderr) writes goes into
//      the same ring + file (and is still forwarded to the real stderr), so
//      uYou's own errors show up too.
//
// The Settings > "uYouEnhanced Debug Logs" cell copies UYTDebugFullReport() to
// the clipboard; the report header carries device/tweak/bundle info so sent
// logs are self-describing.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <unistd.h>
#import <stdio.h>
#import <sys/types.h>
#import <pthread.h>
#import "UYTLog.h"

static NSMutableArray<NSString *> *UYTLogRing;
static NSObject *UYTLogLock;
static NSString *UYTLogFile;
static int UYTOrigStderr = -1;
static const NSUInteger UYTLogRingCap = 2000;

static NSString *UYTDocDir(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths firstObject] ?: NSTemporaryDirectory();
}

static NSString *UYTNowStamp(void) {
    static NSDateFormatter *df;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        df = [NSDateFormatter new];
        df.dateFormat = @"HH:mm:ss.SSS";
    });
    return [df stringFromDate:[NSDate date]];
}

static void UYTRotateLogFile(void) {
    if (!UYTLogFile) return;
    @try {
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:UYTLogFile error:nil];
        if (attrs && [attrs fileSize] > 1024 * 1024) {
            NSString *old = [UYTLogFile stringByAppendingString:@".old"];
            [[NSFileManager defaultManager] removeItemAtPath:old error:nil];
            [[NSFileManager defaultManager] moveItemAtPath:UYTLogFile toPath:old error:nil];
        }
    } @catch (NSException *e) {}
}

static void UYTDebugWriteLine(NSString *line) {
    if (!line.length) return;
    @synchronized (UYTLogLock) {
        if (UYTLogRing.count >= UYTLogRingCap) {
            [UYTLogRing removeObjectsInRange:NSMakeRange(0, UYTLogRing.count - UYTLogRingCap + 1)];
        }
        [UYTLogRing addObject:line];
        if (UYTLogFile.length) {
            @try {
                NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:UYTLogFile];
                if (!fh) {
                    [[NSFileManager defaultManager] createFileAtPath:UYTLogFile contents:nil attributes:nil];
                    fh = [NSFileHandle fileHandleForWritingAtPath:UYTLogFile];
                }
                if (fh) {
                    [fh seekToEndOfFile];
                    [fh writeData:[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
                    [fh closeFile];
                }
            } @catch (NSException *e) {}
        }
    }
}

void UYTDebugCaptureLine(NSString *raw) {
    if (!raw.length) return;
    UYTDebugWriteLine([@"[LOG] " stringByAppendingString:raw]);
    if (UYTOrigStderr >= 0) {
        @try { dprintf(UYTOrigStderr, "%s\n", raw.UTF8String); } @catch (NSException *e) {}
    }
}

void UYTDebugInfo(NSString *format, ...) {
    va_list ap; va_start(ap, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);
    UYTDebugWriteLine([NSString stringWithFormat:@"[UYT-I] %@ %@", UYTNowStamp(), msg]);
}

void UYTDebugWarn(NSString *format, ...) {
    va_list ap; va_start(ap, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);
    UYTDebugWriteLine([NSString stringWithFormat:@"[UYT-W] %@ %@", UYTNowStamp(), msg]);
}

void UYTDebugErr(NSString *format, ...) {
    va_list ap; va_start(ap, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);
    UYTDebugWriteLine([NSString stringWithFormat:@"[UYT-E] %@ %@", UYTNowStamp(), msg]);
}

static BOOL UYTLineIsFailure(NSString *line) {
    NSString *lc = line.lowercaseString;
    static NSArray<NSString *> *words = @[
        @"error", @"fail", @"403", @"400", @"401", @"exception", @"throw",
        @"stall", @"timeout", @"crash", @"refetch", @"reroute", @"retry",
        @"forbidden", @"denied", @"stuck", @"hung", @"unrecognized selector",
        @"cannot", @"unable", @"abort", @"zero-byte"
    ];
    for (NSString *w in words) {
        if ([lc containsString:w]) return YES;
    }
    return NO;
}

NSUInteger UYTDebugErrorCount(void) {
    @synchronized (UYTLogLock) {
        NSUInteger c = 0;
        for (NSString *l in UYTLogRing) {
            if (UYTLineIsFailure(l)) c++;
        }
        return c;
    }
}

NSString *UYTDebugErrorsText(void) {
    NSMutableArray *errs = [NSMutableArray array];
    @synchronized (UYTLogLock) {
        for (NSString *l in UYTLogRing) {
            if (UYTLineIsFailure(l)) [errs addObject:l];
        }
    }
    return [errs componentsJoinedByString:@"\n"] ?: @"(none)";
}

NSString *UYTDebugLogText(NSUInteger lastLines) {
    @synchronized (UYTLogLock) {
        if (!UYTLogRing.count) return @"(no entries)";
        NSUInteger n = MIN(lastLines, UYTLogRing.count);
        NSRange r = NSMakeRange(UYTLogRing.count - n, n);
        return [[UYTLogRing subarrayWithRange:r] componentsJoinedByString:@"\n"];
    }
}

static void UYTHandleUncaught(NSException *exception) {
    @autoreleasepool {
        UYTDebugWriteLine([NSString stringWithFormat:
            @"[UYT-E] UNCAUGHT EXCEPTION: %@\nReason: %@\n%@",
            exception.name ?: @"?", exception.reason ?: @"?",
            [exception.callStackSymbols componentsJoinedByString:@"\n"]]);
    }
}

static void *UYTStderrReaderMain(void *ctx) {
    @autoreleasepool {
        int fd = (int)(intptr_t)ctx;
        char buf[2048];
        ssize_t n;
        NSMutableString *acc = [NSMutableString string];
        while ((n = read(fd, buf, sizeof(buf))) > 0) {
            NSString *chunk = [[NSString alloc] initWithBytes:buf length:(NSUInteger)n encoding:NSUTF8StringEncoding];
            if (chunk) [acc appendString:chunk];
            NSRange eol;
            while ((eol = [acc rangeOfString:@"\n"]).location != NSNotFound) {
                NSString *line = [acc substringToIndex:eol.location];
                [acc deleteCharactersInRange:NSMakeRange(0, eol.location + 1)];
                if ([line hasSuffix:@"\r"]) line = [line substringToIndex:line.length - 1];
                UYTDebugCaptureLine(line);
            }
        }
    }
    return NULL;
}

void UYTLogInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UYTLogLock = [NSObject new];
        UYTLogRing = [NSMutableArray array];
        UYTLogFile = [UYTDocDir() stringByAppendingPathComponent:@"uYouEnhanced-Debug.log"];
        UYTRotateLogFile();

        NSDateFormatter *df = [NSDateFormatter new];
        df.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        NSString *stamp = [df stringFromDate:[NSDate date]];
#ifdef TWEAK_VERSION
        UYTDebugWriteLine([NSString stringWithFormat:@"== uYouEnhanced session %@ (tweak %s) ==", stamp, TWEAK_VERSION]);
#else
        UYTDebugWriteLine([NSString stringWithFormat:@"== uYouEnhanced session %@ ==", stamp]);
#endif

        int fds[2];
        if (pipe(fds) == 0) {
            int orig = dup(STDERR_FILENO);
            if (orig >= 0) {
                UYTOrigStderr = orig;
                dup2(fds[1], STDERR_FILENO);
                close(fds[1]);
                pthread_t th;
                if (pthread_create(&th, NULL, UYTStderrReaderMain, (void *)(intptr_t)fds[0]) == 0) {
                    pthread_detach(th);
                } else {
                    close(fds[0]);
                }
            } else {
                close(fds[0]);
                close(fds[1]);
            }
        }

        NSSetUncaughtExceptionHandler(&UYTHandleUncaught);
    });
}

NSString *UYTDebugFullReport(void) {
    NSMutableString *s = [NSMutableString string];
    [s appendString:@"===== uYouEnhanced Debug Report =====\n"];
#ifdef TWEAK_VERSION
    [s appendFormat:@"tweak: %s\n", TWEAK_VERSION];
#endif
    [s appendFormat:@"device: %@ / %@\n", UIDevice.currentDevice.model ?: @"?", UIDevice.currentDevice.systemVersion ?: @"?"];
    [s appendFormat:@"bundle: %@ v%@\n",
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"] ?: @"?",
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?"];
    [s appendString:@"\n---- ERRORS / FAILURES ----\n"];
    [s appendString:UYTDebugErrorsText()];
    [s appendString:@"\n\n---- LAST 300 LINES ----\n"];
    [s appendString:UYTDebugLogText(300)];

    NSString *selPath = [UYTDocDir() stringByAppendingPathComponent:@"uYouUnrecognizedSelector.log"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:selPath]) {
        [s appendString:@"\n\n---- UNRECOGNIZED SELECTORS (Shorts crash evidence) ----\n"];
        [s appendString:[NSString stringWithContentsOfFile:selPath encoding:NSUTF8StringEncoding error:nil] ?: @"(unreadable)"];
    }
    [s appendString:@"\n===== END =====\n"];
    return s;
}

%ctor {
    UYTLogInstall();
}