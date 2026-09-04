// DownloadPipeline.h — shared declarations for DownloadPipeline.xm
// Allows uYouPatches.xm to call pipeline functions

#import <Foundation/Foundation.h>

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
                    completion:(void (^)(NSArray<UYTStreamFormat *> *formats, NSError *error))completion;
+ (UYTStreamFormat *)bestMuxedFormat:(NSArray<UYTStreamFormat *> *)formats;
+ (UYTStreamFormat *)bestAudioFormat:(NSArray<UYTStreamFormat *> *)formats;
+ (UYTStreamFormat *)bestVideoFormat:(NSArray<UYTStreamFormat *> *)formats;
@end

// Shared URL storage functions
void UYTStoreResolvedURLs(NSString *vid, NSString *muxedURL, NSString *audioURL, NSString *videoURL);
NSString *UYTResolvedURLForVideo(NSString *vid, BOOL audio);
NSString *UYTResolvedVideoURL(NSString *vid);

// Audio-only marker for a video ID (used for Shorts audio-only downloads).
// Stored alongside the resolved URLs so the DownloadItem swap can force the
// audio stream even though uYou creates a video (.mp4) item.
void UYTMarkAudioOnly(NSString *vid, BOOL audioOnly);
BOOL UYTIsAudioOnly(NSString *vid);