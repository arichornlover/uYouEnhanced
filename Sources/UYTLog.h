// UYTLog.h — in-app debug logging for uYouEnhanced (DownloadPipeline, uYouPatches).
// Install once at load; everything since launch is kept in memory AND appended
// to Documents/uYouEnhanced-Debug.log so it survives launches/crashes.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Sets up the in-memory ring, rolling log file, stderr tee and crash handler.
// Called from the module's %ctor already; safe to call again.
void UYTLogInstall(void);

// Structured pipeline logs (levels I/W/E). Everything below hits the ring, the
// file, and (after install) the original stderr too.
void UYTDebugInfo(NSString *format, ...) __attribute__((format(NSString, 1, 2)));
void UYTDebugWarn(NSString *format, ...) __attribute__((format(NSString, 1, 2)));
void UYTDebugErr(NSString *format, ...) __attribute__((format(NSString, 1, 2)));

// Raw stderr line captured by the NSLog/HBLog tee.
void UYTDebugCaptureLine(NSString *raw);

// Report helpers for the settings button.
NSUInteger UYTDebugErrorCount(void);
NSString *UYTDebugErrorsText(void);
NSString *UYTDebugLogText(NSUInteger lastLines);
NSString *UYTDebugFullReport(void);

NS_ASSUME_NONNULL_END