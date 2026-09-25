
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

typedef NS_ENUM(NSInteger, UYTFFBackend) {
    UYTFFBackendNone = 0,
    UYTFFBackendKitNext,
    UYTFFBackendMobile,
};

NSInteger UYTFFActiveBackend(void);

BOOL UYTFFRun(NSArray<NSString *> *arguments);

BOOL UYTFFConvertWebmAudioToM4a(NSString *webmPath, NSString *m4aPath);

BOOL UYTFFRemuxVideoAudioToMP4(NSString *videoPath, NSString *audioPath, NSString *outputPath);

BOOL UYTFFConvertWebmVideoToMp4(NSString *webmPath, NSString *mp4Path);

BOOL UYTFFSmartRemuxToMP4(NSString *videoPath, NSString *audioPath, NSString *outputPath);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END

