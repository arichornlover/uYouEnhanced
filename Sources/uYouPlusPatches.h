#import <UIKit/UIActivityViewController.h>
#import <YouTubeHeader/YTUIUtils.h>
#import <YouTubeHeader/YTCommonUtils.h>
#import <YouTubeHeader/YTColorPalette.h>
#import <YouTubeHeader/YTCommonColorPalette.h>
#import <YouTubeHeader/YTSingleVideoController.h>
#import <YouTubeHeader/ELMPBShowActionSheetCommand.h>
#import <YouTubeHeader/ELMPBProperties.h>
#import <YouTubeHeader/GOODialogView.h>
#import <YouTubeHeader/GPBDescriptor.h>
#import <YouTubeHeader/GPBUnknownField.h>
#import <YouTubeHeader/GPBUnknownFields.h>
#import "uYouPlus.h"

@interface PlayerManager : NSObject
// Prevent uYou player bar from showing when not playing downloaded media
- (float)progress;
// Prevent uYou's playback from colliding with YouTube's
- (void)setSource:(id)source;
- (void)pause;
+ (id)sharedInstance;
@end

// iOS 16 uYou crash fix - @level3tjg: https://github.com/qnblackcat/uYouPlus/pull/224
@interface OBPrivacyLinkButton : UIButton
- (instancetype)initWithCaption:(NSString *)caption
                     buttonText:(NSString *)buttonText
                          image:(UIImage *)image
                      imageSize:(CGSize)imageSize
                   useLargeIcon:(BOOL)useLargeIcon
                displayLanguage:(NSString *)displayLanguage;
@end

// uYouLocal fix
// @interface YTLocalPlaybackController : NSObject
// - (id)activeVideo;
// @end

// uYou theme fix
// @interface YTAppDelegate ()
// @property(nonatomic, strong) id downloadsVC;
// @end

// Fix uYou's appearance not updating if the app is backgrounded
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
@interface UILabel (uYou)
+ (id)_defaultColor;
@end

// YouTube Native Share 0.2.7 Headers - https://github.com/jkhsjdhjs/youtube-native-share - @jkhsjdhjs
@interface CustomGPBMessage : GPBMessage
+ (instancetype)deserializeFromString:(NSString*)string;
@end

@interface ELMContext : NSObject
@property (nonatomic, strong, readwrite) UIView *fromView;
@end

@interface ELMCommandContext : NSObject
@property (nonatomic, strong, readwrite) ELMContext *context;
@end

@interface YTShareEntityEndpointCommandHandler : NSObject
@end
