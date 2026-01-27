#import <UIKit/UIKit.h>

@interface AppIconOptionsController : UIViewController

@property (strong, nonatomic) UIButton *backButton;

@end

@interface UIImage (CustomImages)

+ (UIImage *)customBackButtonImage;

@end
