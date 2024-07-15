#import <UIKit/UIActivityViewController.h>
#import <YouTubeHeader/YTUIUtils.h>
#import <YouTubeHeader/YTCommonUtils.h>
#import <YouTubeHeader/YTColorPalette.h>
#import <YouTubeHeader/YTCommonColorPalette.h>
#import "Tweaks/protobuf/objectivec/GPBDescriptor.h"
#import "Tweaks/protobuf/objectivec/GPBUnknownField.h"
#import "Tweaks/protobuf/objectivec/GPBUnknownFieldSet.h"
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

// YouTube Native Share Headers - https://github.com/jkhsjdhjs/youtube-native-share - @jkhsjdhjs
@interface CustomGPBMessage : GPBMessage
+ (instancetype)deserializeFromString:(NSString*)string;
@end

// @interface YTICommand : GPBMessage
// @end

@interface ELMPBCommand : GPBMessage
@end

@interface ELMPBShowActionSheetCommand : GPBMessage
@property (nonatomic, strong, readwrite) ELMPBCommand *onAppear;
@property (nonatomic, assign, readwrite) BOOL hasOnAppear;
@end

@interface ELMContext : NSObject
@property (nonatomic, strong, readwrite) UIView *fromView;
@end

@interface ELMCommandContext : NSObject
@property (nonatomic, strong, readwrite) ELMContext *context;
@end

@interface YTIUpdateShareSheetCommand
@property (nonatomic, assign, readwrite) BOOL hasSerializedShareEntity;
@property (nonatomic, copy, readwrite) NSString *serializedShareEntity;
+ (GPBExtensionDescriptor*)updateShareSheetCommand;
@end

@interface YTIInnertubeCommandExtensionRoot
+ (GPBExtensionDescriptor*)innertubeCommand;
@end

@interface YTAccountScopedCommandResponderEvent
@property (nonatomic, strong, readwrite) YTICommand *command;
@property (nonatomic, strong, readwrite) UIView *fromView;
@end

@interface YTIShareEntityEndpoint
@property (nonatomic, assign, readwrite) BOOL hasSerializedShareEntity;
@property (nonatomic, copy, readwrite) NSString *serializedShareEntity;
+ (GPBExtensionDescriptor*)shareEntityEndpoint;
@end
