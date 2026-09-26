#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

BOOL UYTDownloadsDBInsertCompleted(NSString *rowID,
                                   NSString *videoID,
                                   NSString * _Nullable title,
                                   NSString * _Nullable channel,
                                   NSString * _Nullable channelURL,
                                   NSString * _Nullable qualityLabel,
                                   NSString * _Nullable typeAndQuality,
                                   unsigned long long size,
                                   NSTimeInterval duration,
                                   NSString *type,
                                   NSString *path);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END

