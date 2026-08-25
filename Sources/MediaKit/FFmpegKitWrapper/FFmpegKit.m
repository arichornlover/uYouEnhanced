/*
 * Copyright (c) 2018-2022, 2026 Taner Sener
 *
 * This file is part of FFmpegKitNext.
 *
 * FFmpegKitNext is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * FFmpegKitNext is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General License for more details.
 *
 * You should have received a copy of the GNU Lesser General License
 * along with FFmpegKitNext. If not, see <http://www.gnu.org/licenses/>.
 */

#import "fftools/ffmpeg.h"
#import "ArchDetect.h"
#import "AtomicLong.h"
#import "FFmpegKit.h"
#import "FFmpegKitConfig.h"
#import "Packages.h"

@implementation FFmpegKit

+ (void)initialize {
    [FFmpegKitConfig class];

    #if TARGET_OS_MACCATALYST
        NSString* osType = @"maccatalyst";
    #elif TARGET_OS_VISION
        NSString* osType = @"visionos";
    #elif TARGET_OS_TV
        NSString* osType = @"tvos";
    #elif TARGET_OS_IOS
        NSString* osType = @"ios";
    #elif TARGET_OS_MAC
        NSString* osType = @"macos";
    #endif

    NSString* packageName = [Packages getPackageName];
    NSString* packageNamePart = [packageName length] > 0 ? [NSString stringWithFormat:@"%@-", packageName] : @"";

    NSLog(@"Loaded ffmpeg-kit-next-%@%@-%@-%@%@-%@.\n", packageNamePart,
          [ArchDetect getArch], [FFmpegKitConfig getVersion], osType,
          [ArchDetect getMinSdk], [FFmpegKitConfig getBuildDate]);
}

+ (FFmpegSession *)executeWithArguments:(NSArray *)arguments {
    FFmpegSession *session = [FFmpegSession create:arguments];
    [FFmpegKitConfig ffmpegExecute:session];
    return session;
}

+ (FFmpegSession *)executeWithArgumentsAsync:(NSArray *)arguments
                        withCompleteCallback:
                            (FFmpegSessionCompleteCallback)completeCallback {
    FFmpegSession *session = [FFmpegSession create:arguments
                              withCompleteCallback:completeCallback];
    [FFmpegKitConfig asyncFFmpegExecute:session];
    return session;
}

+ (FFmpegSession *)
    executeWithArgumentsAsync:(NSArray *)arguments
         withCompleteCallback:(FFmpegSessionCompleteCallback)completeCallback
              withLogCallback:(LogCallback)logCallback
       withStatisticsCallback:(StatisticsCallback)statisticsCallback {
    FFmpegSession *session = [FFmpegSession create:arguments
                              withCompleteCallback:completeCallback
                                   withLogCallback:logCallback
                            withStatisticsCallback:statisticsCallback];
    [FFmpegKitConfig asyncFFmpegExecute:session];
    return session;
}

+ (FFmpegSession *)executeWithArgumentsAsync:(NSArray *)arguments
                        withCompleteCallback:
                            (FFmpegSessionCompleteCallback)completeCallback
                             onDispatchQueue:(dispatch_queue_t)queue {
    FFmpegSession *session = [FFmpegSession create:arguments
                              withCompleteCallback:completeCallback];
    [FFmpegKitConfig asyncFFmpegExecute:session onDispatchQueue:queue];
    return session;
}

+ (FFmpegSession *)
    executeWithArgumentsAsync:(NSArray *)arguments
         withCompleteCallback:(FFmpegSessionCompleteCallback)completeCallback
              withLogCallback:(LogCallback)logCallback
       withStatisticsCallback:(StatisticsCallback)statisticsCallback
              onDispatchQueue:(dispatch_queue_t)queue {
    FFmpegSession *session = [FFmpegSession create:arguments
                              withCompleteCallback:completeCallback
                                   withLogCallback:logCallback
                            withStatisticsCallback:statisticsCallback];
    [FFmpegKitConfig asyncFFmpegExecute:session onDispatchQueue:queue];
    return session;
}

+ (FFmpegSession *)execute:(NSString *)command {
    FFmpegSession *session =
        [FFmpegSession create:[FFmpegKitConfig parseArguments:command]];
    [FFmpegKitConfig ffmpegExecute:session];
    return session;
}

+ (FFmpegSession *)executeAsync:(NSString *)command
           withCompleteCallback:
               (FFmpegSessionCompleteCallback)completeCallback {
    FFmpegSession *session =
        [FFmpegSession create:[FFmpegKitConfig parseArguments:command]
            withCompleteCallback:completeCallback];
    [FFmpegKitConfig asyncFFmpegExecute:session];
    return session;
}

+ (FFmpegSession *)executeAsync:(NSString *)command
           withCompleteCallback:(FFmpegSessionCompleteCallback)completeCallback
                withLogCallback:(LogCallback)logCallback
         withStatisticsCallback:(StatisticsCallback)statisticsCallback {
    FFmpegSession *session =
        [FFmpegSession create:[FFmpegKitConfig parseArguments:command]
              withCompleteCallback:completeCallback
                   withLogCallback:logCallback
            withStatisticsCallback:statisticsCallback];
    [FFmpegKitConfig asyncFFmpegExecute:session];
    return session;
}

+ (FFmpegSession *)executeAsync:(NSString *)command
           withCompleteCallback:(FFmpegSessionCompleteCallback)completeCallback
                onDispatchQueue:(dispatch_queue_t)queue {
    FFmpegSession *session =
        [FFmpegSession create:[FFmpegKitConfig parseArguments:command]
            withCompleteCallback:completeCallback];
    [FFmpegKitConfig asyncFFmpegExecute:session onDispatchQueue:queue];
    return session;
}

+ (FFmpegSession *)executeAsync:(NSString *)command
           withCompleteCallback:(FFmpegSessionCompleteCallback)completeCallback
                withLogCallback:(LogCallback)logCallback
         withStatisticsCallback:(StatisticsCallback)statisticsCallback
                onDispatchQueue:(dispatch_queue_t)queue {
    FFmpegSession *session =
        [FFmpegSession create:[FFmpegKitConfig parseArguments:command]
              withCompleteCallback:completeCallback
                   withLogCallback:logCallback
            withStatisticsCallback:statisticsCallback];
    [FFmpegKitConfig asyncFFmpegExecute:session onDispatchQueue:queue];
    return session;
}

+ (void)cancel {

    /*
     * ZERO (0) IS A SPECIAL SESSION ID
     * WHEN IT IS PASSED TO THIS METHOD, A SIGINT IS GENERATED WHICH CANCELS ALL
     * ONGOING SESSIONS
     */
    cancel_operation(0);
}

+ (void)cancel:(long)sessionId {
    cancel_operation(sessionId);
}

+ (NSArray *)listSessions {
    return [FFmpegKitConfig getFFmpegSessions];
}

@end
