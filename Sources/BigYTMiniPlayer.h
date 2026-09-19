#import "uYouPlus.h"

// Legacy mini bar classes (YTWatchMiniBarView era, up to v20).
@interface YTWatchMiniBarView : UIView
@end

// v21+ replacements.
@interface YTNGWatchMiniBarView : UIView
@property (nonatomic, assign, readwrite) NSInteger watchMiniPlayerLayout;
@end
@interface YTWatchFloatingMiniplayerViewController : UIViewController
@end