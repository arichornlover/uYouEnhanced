
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

void UYTLogInstall(void);

void UYTDebugInfo(NSString *format, ...) __attribute__((format(NSString, 1, 2)));
void UYTDebugWarn(NSString *format, ...) __attribute__((format(NSString, 1, 2)));
void UYTDebugErr(NSString *format, ...) __attribute__((format(NSString, 1, 2)));

void UYTDebugCaptureLine(NSString *raw);

NSUInteger UYTDebugLineCount(void);
NSUInteger UYTDebugErrorCount(void);
NSString *UYTDebugErrors(void);
NSString *UYTDebugLogText(NSUInteger lastLines);
NSString *UYTDebugFullReport(void);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END