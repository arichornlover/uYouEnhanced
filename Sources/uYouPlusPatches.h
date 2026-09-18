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
#import "uYouPatches.h"

@interface ELMPBProperties (uYouEnhanced)
- (id)firstSubmessage;
- (id)submessageAtIndex:(NSUInteger)index;
@end

@interface ELMPBIdentifierProperties (uYouEnhanced)
- (NSString *)identifier;
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
