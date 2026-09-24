// DownloadPipeline.h — shared declarations for DownloadPipeline.xm
// Allows uYouPatches.xm to call pipeline functions

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UYTStreamFormat : NSObject
@property (nonatomic, copy) NSString *url;
@property (nonatomic, assign) NSInteger itag;
@property (nonatomic, copy) NSString *mimeType;
@property (nonatomic, assign) BOOL hasVideo;
@property (nonatomic, assign) BOOL hasAudio;
@property (nonatomic, assign) long long bitrate;
@property (nonatomic, copy) NSString *qualityLabel;
@end

@interface UYTDownloadPipeline : NSObject
+ (void)fetchFormatsForVideoID:(NSString *)videoID
                    isShorts:(BOOL)isShorts
                    progress:(void (^_Nullable)(double fractionComplete, unsigned long long bytesDownloaded))progress
                    completion:(void (^)(NSArray<UYTStreamFormat *> * _Nullable formats, NSError * _Nullable error))completion;
+ (nullable UYTStreamFormat *)bestMuxedFormat:(NSArray<UYTStreamFormat *> * _Nullable)formats;
+ (nullable UYTStreamFormat *)bestAudioFormat:(NSArray<UYTStreamFormat *> * _Nullable)formats;
+ (nullable UYTStreamFormat *)bestVideoFormat:(NSArray<UYTStreamFormat *> * _Nullable)formats;
@end

// Drive uYou's own DownloadItem UI off SABR's live (fraction, bytes) signal.
// All real uYou key access is KVC + @try-guarded, so unknown names no-op.
void UYTDriveDownloadItemProgressForVideoID(NSString * _Nullable vid, double fractionComplete, unsigned long long bytesDownloaded);
// Write accurate final values (100% + real file size) on the item once the
// file actually exists on disk.
void UYTWriteFinalDownloadProgress(id _Nullable item, NSString * _Nullable filePath);

// Shared URL storage functions
void UYTStoreResolvedURLs(NSString * _Nullable vid, NSString * _Nullable muxedURL, NSString * _Nullable audioURL, NSString * _Nullable videoURL);
NSString * _Nullable UYTResolvedURLForVideo(NSString * _Nullable vid, BOOL audio);
NSString * _Nullable UYTResolvedVideoURL(NSString * _Nullable vid);

// Audio-only marker for a video ID (used for Shorts audio-only downloads).
// Stored alongside the resolved URLs so the DownloadItem swap can force the
// audio stream even though uYou creates a video (.mp4) item.
void UYTMarkAudioOnly(NSString * _Nullable vid, BOOL audioOnly);
BOOL UYTIsAudioOnly(NSString * _Nullable vid);

// Register a task URL for a videoID so a failed URLSession task (403/broken
// URL) can be mapped back to its video and rerouted to SABR. Backed by
// uYouPatches' URL→videoID registry.
void UYTRegisterRemoteURLForVideoID(NSString * _Nullable vid, NSString * _Nullable url);

NS_ASSUME_NONNULL_END