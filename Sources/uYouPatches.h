#import "uYouPlus.h"

// Access Group / Sideloading utilities
// Shared between uYouPlusPatches.xm and uYouPatches.xm
NSString *uYouAccessGroupID();
BOOL uYouIsSideStore();

// ============================================================================
// MARK: - uYou Reverse-Engineered Class Interfaces
// From uYou 3.0.4 source (a0zhar/uYou-3.0.4-src)
// ============================================================================

@interface PlayerManager : NSObject
+ (id)sharedInstance;
- (float)progress;
- (void)setSource:(id)source;
- (void)pause;
- (void)play;
- (BOOL)isPlaying;
- (BOOL)isPaused;
@property (nonatomic, strong) NSString *playerID;
@property (nonatomic, strong) id currentVideo;
@end

@interface DownloadsManager : NSObject
+ (id)sharedInstance;
- (void)getLinksLocallyPlayerItem:(id)item videoID:(id)videoID sourceView:(id)sourceView isShorts:(BOOL)isShorts;
- (void)addMetadataToAudioForDownloadItem:(id)item;
- (void)mergeAudioWithMP4VideoForDownloadItem:(id)item;
- (void)mergeAudioWithVideoForDownloadItem:(id)item;
- (int)convertVideo:(id)video toAudio:(id)audio;
- (void)convertAsyncMkvToMp4:(id)path forUYouItem:(id)item;
- (int)ffmpegWithArguments:(id)arguments;
- (void)setupURLSessionConfiguration;
- (void)createDownloadTask;
- (void)exportVideoToCameraRollWithPath:(id)path removeFile:(BOOL)remove;
- (void)dismissHUD;
- (void)errorHUDWithMeessage:(id)message inView:(id)view delay:(double)delay;
- (id)topViewController;
- (id)session;
@property (nonatomic, strong) NSMutableDictionary *ffmpegExecutions;
@property (nonatomic, strong) id sessionManager;
@end

@interface DownloadItem : NSObject
- (id)initWithVideoID:(id)videoID uYouItem:(id)uYouItem downloadID:(id)downloadID url:(id)url filePath:(id)filePath cachedPath:(id)cachedPath type:(int)type;
- (void)createDownloadTask;
- (void)resumeDownloadTask;
- (void)cancelDownloadTask;
- (void)updateProgress;
@property (nonatomic, strong) NSString *videoID;
@property (nonatomic, strong) NSString *filePath;
@property (nonatomic, strong) NSString *cachedPath;
@property (nonatomic, strong) NSURL *remoteURL;
@property (nonatomic, strong) id uYouItem;
@property (nonatomic, strong) id downloadIdentifier;
- (BOOL)isDownloadFinished;
@end

@interface uYouItem : NSObject
- (BOOL)isMP4;
@property (nonatomic, strong) NSString *videoID;
@property (nonatomic, strong) NSString *title;
@property (nonatomic, strong) NSString *channel;
@property (nonatomic, strong) NSString *qualityLabel;
@property (nonatomic, strong) NSString *typeAndQuality;
- (NSString *)filePath;
- (NSString *)cachedAudioPath;
- (NSString *)cachedVideoPath;
- (NSString *)tmpAudioPath;
- (NSString *)tmpVideoPath;
@end

@interface RequestItem : NSObject
@property (nonatomic, strong) NSString *videoID;
@property (nonatomic, strong) NSString *playerID;
@property (nonatomic, strong) NSString *downloadQuality;
@property (nonatomic, strong) id sourceView;
@property (nonatomic, strong) id videoInfo;
@property (nonatomic, strong) NSString *title;
@end

// ============================================================================
// MARK: - YouTube Internal Class Interfaces (for patches)
// ============================================================================

@interface YTIStreamingData : NSObject
- (NSArray *)formatsArray;
- (NSArray *)adaptiveFormatsArray;
- (NSString *)hlsManifestURL;
- (NSString *)dashManifestURL;
@end

@interface YTIFormatStream : NSObject
@property (nonatomic, copy) NSString *URL;
@property (nonatomic, copy) NSString *qualityLabel;
- (BOOL)isAudio;
- (BOOL)isVideo;
@end

@interface YTPlaybackData : NSObject
- (id)video;
- (id)playerResponse;
@end

@interface YTSingleVideoController : NSObject
- (id)playbackData;
- (NSArray *)selectableVideoFormats;
@end

@interface YTPlayerResponse : NSObject
- (id)playerData;
@end

@interface YTIPlayerResponse : NSObject
@property (nonatomic, strong) id videoDetails;
@property (nonatomic, strong) YTIStreamingData *streamingData;
@end

@interface YTPlayerOverlayManager : NSObject
- (id)varispeedController;
- (void)didPressToggleFullscreen;
@property (nonatomic, assign) float currentPlaybackRate;
@end

@interface YTMainAppVideoPlayerOverlayViewController : UIViewController
@property (nonatomic, strong) id playerBarController;
- (void)setPlaybackRate:(CGFloat)rate;
- (CGFloat)currentPlaybackRate;
- (BOOL)isFullscreen;
- (CGFloat)totalTime;
- (void)updateRelatedVideos;
@end

@interface YTPlayerViewController : UIViewController
@property (nonatomic, strong) YTPlayerOverlayManager *overlayManager;
- (id)activeVideo;
- (id)activeVideoPlayerOverlay;
- (id)varispeedController;
- (CGFloat)currentVideoMediaTime;
- (CGFloat)currentVideoTotalMediaTime;
- (NSString *)currentVideoID;
@end

@interface HAMPlayerInternal : NSObject
- (void)setRate:(float)rate;
- (float)rate;
@end

@interface MLHAMQueuePlayer : NSObject
@property id playerEventCenter;
@property id delegate;
- (void)setRate:(float)rate;
- (void)internalSetRate;
@end

@interface MLPlayerStickySettings : NSObject
- (float)playbackRate;
- (void)setPlaybackRate:(float)rate;
@end

// ============================================================================
// MARK: - uYou UI Classes
// ============================================================================

@interface DownloadsPagerVC : UIViewController
- (NSArray<UIViewController *> *)viewControllers;
- (void)updatePageStyles;
@end
@interface DownloadingVC : UIViewController
- (void)updatePageStyles;
- (UITableView *)tableView;
@end
@interface DownloadingCell : UITableViewCell
- (void)updatePageStyles;
@end
@interface DownloadedVC : UIViewController
- (void)updatePageStyles;
- (UITableView *)tableView;
@end
@interface DownloadedCell : UITableViewCell
- (void)updatePageStyles;
@end
@interface UILabel (uYouEnhanced)
+ (id)_defaultColor;
@end
