#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static NSString * const kUYOUCrashSummaryKey = @"uYouLastCrashSummary";

static NSString *uYouCrashBuildReport(NSException *exception) {
    NSArray<NSString *> *frames = exception.callStackSymbols ?: @[];
    NSUInteger frameCount = MIN((NSUInteger)16, frames.count);
    NSString *frameText = [[frames subarrayWithRange:NSMakeRange(0, frameCount)] componentsJoinedByString:@"\n"];
    NSString *appVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] ?: @"?";
    return [NSString stringWithFormat:
        @"[uYouEnhanced crash report]\n"
         "YouTube %@ / iOS %@\n"
         "Exception: %@\n"
         "Reason: %@\n"
         "UserInfo: %@\n"
         "\nTop frames:\n%@\n",
        appVersion, [UIDevice currentDevice].systemVersion,
        exception.name, exception.reason, exception.userInfo, frameText];
}

static void uYouCrashUncaughtExceptionHandler(NSException *exception) {
    NSString *report = uYouCrashBuildReport(exception);

    @try {
        UIPasteboard.generalPasteboard.string = report;
    } @catch (...) {}

    @try {
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"uYouCrash.log"];
        [report writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch (...) {}

    @try {
        [[NSUserDefaults standardUserDefaults] setObject:report forKey:kUYOUCrashSummaryKey];
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
    } @catch (...) {}

    NSLog(@"[uYouCrash] %@", report);
}

%ctor {
    NSSetUncaughtExceptionHandler(&uYouCrashUncaughtExceptionHandler);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSSetUncaughtExceptionHandler(&uYouCrashUncaughtExceptionHandler);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSSetUncaughtExceptionHandler(&uYouCrashUncaughtExceptionHandler);
    });

    NSString *lastCrash = [[NSUserDefaults standardUserDefaults] stringForKey:kUYOUCrashSummaryKey];
    if (lastCrash) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try {
                UIPasteboard.generalPasteboard.string =
                    [NSString stringWithFormat:@"[uYouEnhanced crash report]\n%@", lastCrash];
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:kUYOUCrashSummaryKey];
                CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
            } @catch (...) {}
        });
    }
}
