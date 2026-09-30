#import "UYTFileSize.h"
#import "uYouPlus.h"
#import "uYouPatches.h"
#import "UYTMediaKit.h"
#import "DownloadPipeline.h"
#import "UYTLog.h"
#import "UYTSABR.h"
#import <YouTubeHeader/YTUIUtils.h>
#import <objc/runtime.h>
#import <sqlite3.h>
#include <string.h>

// ============================================================================
// Forward Declarations for Static Functions
// ============================================================================
static void UYTArmStallWatchdog(id item, NSTimeInterval seconds);
static void UYTArmStallWatchdogForItem(id item, NSTimeInterval seconds);
static void UYTDisarmStallWatchdog(id item);
static void UYTStallCheckOptimized(id item);
static void UYTScheduleStallCheckOptimized(id item, NSTimeInterval delay);

// ============================================================================
// Macros & Constants
// ============================================================================
#define SETTINGS_KEY @"YTAmbientLight"

// Settings keys
static NSString *const kYTAmbientLightEnabled = @"YTAmbientLight_enabled";
static NSString *const kYTAmbientLightMode = @"YTAmbientLight_mode"; // 0 = Dynamic (default), 1 = Static Color, 2 = Static Image, 3 = Disabled
static NSString *const kYTAmbientLightColor = @"YTAmbientLight_color"; // Hex color string
static NSString *const kYTAmbientLightIntensity = @"YTAmbientLight_intensity"; // 0.0 - 1.0
static NSString *const kYTAmbientLightBlurRadius = @"YTAmbientLight_blurRadius"; // Blur radius for the effect
static NSString *const kYTAmbientLightUseVideoColors = @"YTAmbientLight_useVideoColors"; // Extract colors from video
static NSString *const kYTAmbientLightStaticImage = @"YTAmbientLight_staticImage"; // Path to custom image

// Helper macros
#define IS_YTAMBIENTLIGHT_ENABLED() ([[NSUserDefaults standardUserDefaults] boolForKey:kYTAmbientLightEnabled])
#define YTAMBIENTLIGHT_MODE() ([[NSUserDefaults standardUserDefaults] integerForKey:kYTAmbientLightMode])
#define YTAMBIENTLIGHT_COLOR() ([[NSUserDefaults standardUserDefaults] stringForKey:kYTAmbientLightColor])
#define YTAMBIENTLIGHT_INTENSITY() ([[NSUserDefaults standardUserDefaults] floatForKey:kYTAmbientLightIntensity])
#define YTAMBIENTLIGHT_BLUR_RADIUS() ([[NSUserDefaults standardUserDefaults] floatForKey:kYTAmbientLightBlurRadius])
#define YTAMBIENTLIGHT_USE_VIDEO_COLORS() ([[NSUserDefaults standardUserDefaults] boolForKey:kYTAmbientLightUseVideoColors])
#define YTAMBIENTLIGHT_STATIC_IMAGE() ([[NSUserDefaults standardUserDefaults] stringForKey:kYTAmbientLightStaticImage])

// ============================================================================
// UIColor from hex string
// ============================================================================
static UIColor *YTAmbientLightColorFromHex(NSString *hex) {
    if (!hex || hex.length == 0) return nil;
    NSString *cleanHex = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (cleanHex.length != 6 && cleanHex.length != 8) return nil;
    NSScanner *scanner = [NSScanner scannerWithString:cleanHex];
    unsigned long long rgbValue = 0;
    if (![scanner scanHexLongLong:&rgbValue]) return nil;
    CGFloat r, g, b, a = 1.0;
    if (cleanHex.length == 8) {
        r = ((rgbValue >> 24) & 0xFF) / 255.0;
        g = ((rgbValue >> 16) & 0xFF) / 255.0;
        b = ((rgbValue >> 8) & 0xFF) / 255.0;
        a = (rgbValue & 0xFF) / 255.0;
    } else {
        r = ((rgbValue >> 16) & 0xFF) / 255.0;
        g = ((rgbValue >> 8) & 0xFF) / 255.0;
        b = (rgbValue & 0xFF) / 255.0;
    }
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

// ============================================================================
// Generate ambient color from video thumbnail/frame
// ============================================================================
static UIColor *YTAmbientLightGenerateColorFromVideo(id playerViewController) {
    @try {
        if ([playerViewController respondsToSelector:@selector(videoView)]) {
            UIView *videoView = [playerViewController performSelector:@selector(videoView)];
            if (videoView && [videoView isKindOfClass:[UIView class]]) {
                UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 1), NO, 0.0);
                [videoView drawViewHierarchyInRect:CGRectMake(-videoView.bounds.size.width/2 + 0.5, -videoView.bounds.size.height/2 + 0.5, videoView.bounds.size.width, videoView.bounds.size.height) afterScreenUpdates:NO];
                UIImage *pixel = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
                if (pixel) {
                    CGImageRef cgImage = pixel.CGImage;
                    if (cgImage) {
                        CFDataRef data = CGDataProviderCopyData(CGImageGetDataProvider(cgImage));
                        if (data) {
                            const UInt8 *bytes = CFDataGetBytePtr(data);
                            if (bytes) {
                                CGFloat r = bytes[0] / 255.0;
                                CGFloat g = bytes[1] / 255.0;
                                CGFloat b = bytes[2] / 255.0;
                                CFRelease(data);
                                return [UIColor colorWithRed:r green:g blue:b alpha:1.0];
                            }
                            CFRelease(data);
                        }
                    }
                }
            }
        }
    } @catch (NSException *e) {}
    return nil;
}

// ============================================================================
// Blur effect view for ambient background
// ============================================================================
static UIVisualEffectView *YTAmbientLightCreateBlurView(UIColor *color, CGFloat intensity, CGFloat blurRadius) {
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    blurView.backgroundColor = [color colorWithAlphaComponent:intensity];
    blurView.clipsToBounds = YES;
    blurView.layer.cornerRadius = 0;
    return blurView;
}

// ============================================================================
// Static image view for ambient background
// ============================================================================
static UIImageView *YTAmbientLightCreateImageView(NSString *imagePath, CGFloat intensity) {
    if (!imagePath || imagePath.length == 0) return nil;
    UIImage *image = [UIImage imageWithContentsOfFile:imagePath];
    if (!image) return nil;
    UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
    imageView.contentMode = UIViewContentModeScaleAspectFill;
    imageView.alpha = intensity;
    imageView.clipsToBounds = YES;
    return imageView;
}

// ============================================================================
// Remove existing ambient subviews
// ============================================================================
static void YTAmbientLightRemoveExistingAmbientViews(UIView *container) {
    if (!container) return;
    for (UIView *subview in container.subviews) {
        if ([subview isKindOfClass:[UIVisualEffectView class]] || 
            ([subview isKindOfClass:[UIImageView class]] && subview.tag == 9999) ||
            ([subview isKindOfClass:[UIView class]] && subview.tag == 9998)) {
            [subview removeFromSuperview];
        }
    }
}

// ============================================================================
// Core function to apply ambient effect to any container view
// ============================================================================
static void YTAmbientLightApplyEffectToView(UIView *container, id playerVC) {
    if (!IS_YTAMBIENTLIGHT_ENABLED()) return;
    
    NSInteger mode = YTAMBIENTLIGHT_MODE();
    if (mode == 3) return; // Disabled
    
    // Remove existing ambient views
    YTAmbientLightRemoveExistingAmbientViews(container);
    
    UIColor *ambientColor = nil;
    BOOL useVideoColors = YTAMBIENTLIGHT_USE_VIDEO_COLORS();
    
    if (useVideoColors && playerVC) {
        ambientColor = YTAmbientLightGenerateColorFromVideo(playerVC);
    }
    
    // Fallback to custom color or default
    if (!ambientColor) {
        NSString *colorHex = YTAMBIENTLIGHT_COLOR();
        ambientColor = YTAmbientLightColorFromHex(colorHex);
        if (!ambientColor) {
            ambientColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.2 alpha:1.0]; // Default dark blue
        }
    }
    
    CGFloat intensity = YTAMBIENTLIGHT_INTENSITY();
    if (intensity <= 0) intensity = 0.6; // Default
    
    CGFloat blurRadius = YTAMBIENTLIGHT_BLUR_RADIUS();
    if (blurRadius <= 0) blurRadius = 40.0; // Default
    
    switch (mode) {
        case 0: { // Dynamic (but static - no fading)
            UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
            blurView.backgroundColor = [ambientColor colorWithAlphaComponent:intensity];
            blurView.clipsToBounds = YES;
            blurView.layer.cornerRadius = 0;
            blurView.tag = 9998;
            blurView.frame = container.bounds;
            blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [container insertSubview:blurView atIndex:0];
            break;
        }
        case 1: { // Static Color
            UIView *colorView = [[UIView alloc] initWithFrame:container.bounds];
            colorView.tag = 9998;
            colorView.backgroundColor = [ambientColor colorWithAlphaComponent:intensity];
            colorView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [container insertSubview:colorView atIndex:0];
            break;
        }
        case 2: { // Static Image
            NSString *imagePath = YTAMBIENTLIGHT_STATIC_IMAGE();
            UIImageView *imageView = nil;
            NSString *imagePath2 = YTAMBIENTLIGHT_STATIC_IMAGE();
            if (imagePath2 && imagePath2.length > 0) {
                UIImage *image = [UIImage imageWithContentsOfFile:imagePath2];
                if (image) {
                    UIImageView *iv = [[UIImageView alloc] initWithImage:image];
                    iv.contentMode = UIViewContentModeScaleAspectFill;
                    iv.alpha = intensity;
                    iv.clipsToBounds = YES;
                    imageView = iv;
                }
            }
            if (imageView) {
                imageView.tag = 9999;
                imageView.frame = container.bounds;
                imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [container insertSubview:imageView atIndex:0];
            } else {
                // Fallback to color
                UIView *colorView = [[UIView alloc] initWithFrame:container.bounds];
                colorView.tag = 9998;
                colorView.backgroundColor = [ambientColor colorWithAlphaComponent:intensity];
                colorView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [container insertSubview:colorView atIndex:0];
            }
            break;
        }
        default:
            break;
    }
}

// ============================================================================
// Find player VC from any view in hierarchy
// ============================================================================
static id YTAmbientLightFindPlayerVC(UIView *view) {
    UIResponder *responder = view.nextResponder;
    while (responder) {
        if ([responder isKindOfClass:[YTPlayerViewController class]] || 
            [responder isKindOfClass:[YTMainAppVideoPlayerOverlayViewController class]]) {
            return responder;
        }
        responder = responder.nextResponder;
    }
    return nil;
}

// ============================================================================
// Apply effect to CinematicContainerView
// ============================================================================
static void YTAmbientLightApplyToCinematicContainer(YTCinematicContainerView *container) {
    id playerVC = YTAmbientLightFindPlayerVC(container);
    YTAmbientLightApplyEffectToView(container, playerVC);
}

// ============================================================================
// Apply effect to WatchNext sidebar
// ============================================================================
static void YTAmbientLightApplyToWatchNextView(UIView *watchNextView) {
    id playerVC = YTAmbientLightFindPlayerVC(watchNextView);
    YTAmbientLightApplyEffectToView(watchNextView, playerVC);
}

// ============================================================================
// Find and apply to CinematicContainerView in hierarchy
// ============================================================================
static void YTAmbientLightFindAndApplyCinematic(UIView *view) {
    if (!view) return;
    if ([view isKindOfClass:[YTCinematicContainerView class]]) {
        YTAmbientLightApplyToCinematicContainer((YTCinematicContainerView *)view);
        return;
    }
    for (UIView *subview in view.subviews) {
        [self findAndApplyToCinematicContainer:subview];
    }
}

// ============================================================================
// Find and apply to WatchNext view in hierarchy
// ============================================================================
static void YTAmbientLightFindAndApplyWatchNext(UIView *view) {
    if (!view) return;
    
    // Check for WatchNextResultsViewController's view
    if ([view isKindOfClass:NSClassFromString(@"YTWatchNextResultsViewController")]) {
        YTAmbientLightApplyToWatchNextView(view);
        return;
    }
    
    // Check for view with watch_next accessibility identifier
    if ([view.accessibilityIdentifier isEqualToString:@"watch_next"] ||
        [view.accessibilityIdentifier isEqualToString:@"id.watch_next.view"] ||
        [view.accessibilityIdentifier hasPrefix:@"watch_next"]) {
        YTAmbientLightApplyToWatchNextView(view);
        return;
    }
    
    // Check for WatchNextResultsViewController's view property
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:NSClassFromString(@"YTWatchNextResultsViewController")]) {
            YTAmbientLightApplyToWatchNextView(subview);
            return;
        }
        // Check for collection view that might be the WatchNext results
        if ([subview isKindOfClass:[UICollectionView class]] && 
            [subview.superview isKindOfClass:NSClassFromString(@"YTWatchNextResultsViewController")]) {
            YTAmbientLightApplyToWatchNextView(subview.superview);
            return;
        }
        [self findAndApplyToWatchNextView:subview];
    }
}

// ============================================================================
// Settings observer to reapply effect when settings change
// ============================================================================
%ctor {
    NSNotificationCenter *center = [NSUserDefaults standardUserDefaults];
    [center addObserverForName:NSUserDefaultsDidChangeNotification 
                         object:nil 
                          queue:[NSOperationQueue mainQueue] 
                     usingBlock:^(NSNotification *note) {
        if (IS_YTAMBIENTLIGHT_ENABLED()) {
            UIWindow *window = [UIApplication sharedApplication].keyWindow;
            if (window) {
                for (UIView *subview in window.subviews) {
                    [self findAndApplyToCinematicContainer:subview];
                    [self findAndApplyToWatchNextView:subview];
                }
            }
        }
    }];
    
    // Initialize defaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults objectForKey:kYTAmbientLightEnabled]) {
        [defaults setBool:YES forKey:kYTAmbientLightEnabled];
    }
    if (![defaults objectForKey:kYTAmbientLightMode]) {
        [defaults setInteger:0 forKey:kYTAmbientLightMode];
    }
    if (![defaults objectForKey:kYTAmbientLightIntensity]) {
        [defaults setFloat:0.6 forKey:kYTAmbientLightIntensity];
    }
    if (![defaults objectForKey:kYTAmbientLightBlurRadius]) {
        [defaults setFloat:40.0 forKey:kYTAmbientLightBlurRadius];
    }
    if (![defaults objectForKey:kYTAmbientLightUseVideoColors]) {
        [defaults setBool:YES forKey:kYTAmbientLightUseVideoColors];
    }
}

%group gYTAmbientLight

%hook YTPlayerViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    if (IS_YTAMBIENTLIGHT_ENABLED() && YTAMBIENTLIGHT_MODE() != 3) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self findAndApplyToCinematicContainer:self.view];
            [self findAndApplyToWatchNextView:self.view];
        });
    }
}
%end

%hook YTMainAppVideoPlayerOverlayViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    if (IS_YTAMBIENTLIGHT_ENABLED() && YTAMBIENTLIGHT_MODE() != 3) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self findAndApplyToCinematicContainer:self.view];
            [self findAndApplyToWatchNextView:self.view];
        });
    }
}
%end

%hook YTWatchViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    if (IS_YTAMBIENTLIGHT_ENABLED() && YTAMBIENTLIGHT_MODE() != 3) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self findAndApplyToWatchNextView:self.view];
        });
    }
}
%end

%end