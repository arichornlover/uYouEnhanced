#import <UIKit/UIKit.h>

@interface AppIconOptionsController : UIViewController <UITableViewDataSource, UITableViewDelegate>

@property (strong, nonatomic) UIButton *backButton;

@end

@interface UIImage (CustomImages)

+ (UIImage *)customBackButtonImage;

@end
