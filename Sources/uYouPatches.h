#import "uYouPlus.h"
#import <YouTubeHeader/GOODialogView.h>

// Access Group / Sideloading utilities
// Shared between uYouPlusPatches.xm and uYouPatches.xm
NSString *uYouAccessGroupID();
BOOL uYouIsSideStore();

// From uYou 3.0.4 source (a0zhar/uYou-3.0.4-src)
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
- (BOOL)isDownloadFinished;
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

// NOTE: YTIStreamingData, YTIFormatStream, YTPlaybackData, YTSingleVideoController,
// YTPlayerResponse, YTIPlayerResponse, YTPlayerOverlayManager,
// YTMainAppVideoPlayerOverlayViewController, YTPlayerViewController are already
// declared in Tweaks/YouTubeHeader/. HAMPlayerInternal and MLHAMQueuePlayer
// are already declared in Sources/uYouPlus.h. Do NOT re-declare them here.

@interface YTPlayerViewController (uYouPatches)
- (void)setPlaybackRate:(float)rate;
@end

@interface HAMPlayerInternal (uYouPatches)
- (float)rate;
@end

// Bundled inside uYou's payload; used for webm -> m4a audio conversion (#771/#465)
// NOT linked against this tweak: always call via %c(MobileFFmpeg) runtime lookup.
// A bare [MobileFFmpeg ...] reference emits _OBJC_CLASS_$_MobileFFmpeg and fails to link.
@interface MobileFFmpeg : NSObject
+ (int)executeWithArguments:(NSArray *)arguments;
@end

// Minimal declaration so touch-forwarding hooks can use UIView's nextResponder
@interface YTFullScreenEngagementOverlayView : UIView
@end

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
