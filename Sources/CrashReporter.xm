// ============================================================================
// CrashReporter.xm — uYouEnhanced standalone crash reporter
//
// Split out of uYouPatches.xm so crash diagnostics live in their own file and
// can be improved without touching tweak fixes.
//
// WHY THIS DESIGN: stock iOS crash reports redact NSException reasons
// ("-[%s %s]: unrecognized selector sent to instance" with placeholder names),
// and this app can crash ~3s after launch — too fast for any alert UI. So
// delivery happens INSIDE the uncaught-exception handler, which runs BEFORE
// abort() tears the process down:
//
//   1. IN-HANDLER (primary): synchronously copy the full report to the
//      UIPasteboard while the process is still alive. Survives any crash loop.
//   2. FILE: tmp/uYouCrash.log in the app sandbox (readable via Filza/iMazing).
//   3. DEFAULTS: uYouLastCrashSummary persisted; if the in-handler pasteboard
//      write failed, the NEXT launch pushes it to the pasteboard 0.5s in
//      (still ahead of the known ~3s crash window), evicting the key only on
//      success so a failed delivery retries instead of being lost.
//
// AFTER A CRASH: open Notes (or Messages/Mail — anything with a text field)
// and PASTE. Send the result back to the build chat.
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static NSString * const kUYOUCrashSummaryKey = @"uYouLastCrashSummary";

// Build the human-readable report. Runs while crashing: keep it simple.
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

// Every step is individually @try-guarded — a failure inside the reporter
// (e.g. pasteboard daemon unavailable mid-crash) must never raise a second
// exception and skip the remaining cleanup steps.
static void uYouCrashUncaughtExceptionHandler(NSException *exception) {
    NSString *report = uYouCrashBuildReport(exception);

    // 1) Pasteboard FIRST — this is the payload the user pastes back.
    @try {
        UIPasteboard.generalPasteboard.string = report;
    } @catch (...) {}

    // 2) File copy in the app sandbox.
    @try {
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"uYouCrash.log"];
        [report writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch (...) {}

    // 3) Defaults summary — next-launch fallback if step 1 failed.
    @try {
        [[NSUserDefaults standardUserDefaults] setObject:report forKey:kUYOUCrashSummaryKey];
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
    } @catch (...) {}

    NSLog(@"[uYouCrash] %@", report); // also lands in os_log / sysdiagnose
}

%ctor {
    // Registration is instant and every %ctor finishes within ~100ms of
    // launch — far ahead of the ~3s crash window — so this file's position
    // in the link order relative to the other constructors isn't critical.
    // (Alphabetical wildcard ordering puts it among the first anyway.)
    NSSetUncaughtExceptionHandler(&uYouCrashUncaughtExceptionHandler);

    // Fallback delivery for a PREVIOUS crash whose in-handler pasteboard
    // write failed. Evicts the stored key ONLY after a successful write, so
    // a failed delivery retries next launch instead of being lost forever.
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
