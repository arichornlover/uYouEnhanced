#import <UIKit/UIKit.h>

@interface AppIconOptionsController : UIViewController <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>

@property (strong, nonatomic) UIButton *backButton;

@end

@interface UIImage (CustomImages)

+ (UIImage *)customBackButtonImage;

@end
