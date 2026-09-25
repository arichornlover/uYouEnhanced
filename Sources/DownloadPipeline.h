
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

void UYTDriveDownloadItemProgressForVideoID(NSString * _Nullable vid, double fractionComplete, unsigned long long bytesDownloaded);
void UYTWriteFinalDownloadProgress(id _Nullable item, NSString * _Nullable filePath);

void UYTStoreResolvedURLs(NSString * _Nullable vid, NSString * _Nullable muxedURL, NSString * _Nullable audioURL, NSString * _Nullable videoURL);
NSString * _Nullable UYTResolvedURLForVideo(NSString * _Nullable vid, BOOL audio);
NSString * _Nullable UYTResolvedVideoURL(NSString * _Nullable vid);

void UYTMarkAudioOnly(NSString * _Nullable vid, BOOL audioOnly);
BOOL UYTIsAudioOnly(NSString * _Nullable vid);

void UYTRegisterRemoteURLForVideoID(NSString * _Nullable vid, NSString * _Nullable url);

void UYTRefreshResolvedURLsForVideo(NSString * _Nullable vid);

NS_ASSUME_NONNULL_END