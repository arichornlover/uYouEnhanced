
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface YMSABR : NSObject
+ (void)downloadVideoItag:(int)videoItag audioItag:(int)audioItag
                 progress:(void (^)(float fraction, unsigned long long bytesDownloaded, BOOL isAudio))progress
               completion:(void (^)(NSURL * _Nullable videoURL, NSURL * _Nullable audioURL, NSString * _Nullable err))completion;

+ (void)downloadAudioItag:(int)audioItag
                 progress:(void (^)(float fraction, unsigned long long bytesDownloaded))progress
               completion:(void (^)(NSURL * _Nullable audioURL, NSString * _Nullable err))completion;

+ (void)cancelCurrent;
@end

BOOL UYTSABRHasValidCapture(void);

BOOL UYTSABRHasValidCaptureForVideoID(NSString * _Nullable videoID);

BOOL UYTSABRIsDownloadActive(NSString * _Nullable videoID);

void UYTSABRFallbackDownloadForVideoID(NSString *videoID,
                                      NSString * _Nullable title,
                                      BOOL audioOnly,
                                      void (^_Nullable progress)(double fractionComplete, unsigned long long bytesDownloaded),
                                      void (^completion)(BOOL success, NSString * _Nullable error));

NS_ASSUME_NONNULL_END

