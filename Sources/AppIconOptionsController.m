#import "AppIconOptionsController.h"
#import <notify.h>

static NSString *const kPrefDomain = @"com.arichornlover.uYouEnhanced";
static NSString *const kPrefEnableIconOverride = @"appIconCustomization_enabled";
static NSString *const kPrefIconName = @"customAppIcon_name";
static NSString *const kPrefNotifyName = @"com.arichornlover.uYouEnhanced.prefschanged";

@interface AppIconOptionsController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (strong, nonatomic) UICollectionView *collectionView;
@property (strong, nonatomic) NSArray<NSString *> *appIcons;
@property (assign, nonatomic) NSInteger selectedIconIndex;
@end

@implementation UIImage (CustomImages)

+ (UIImage *)customBackButtonImage {
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"uYouPlus" ofType:@"bundle"];
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath] ?: [NSBundle mainBundle];
    return [UIImage imageNamed:@"Back.png" inBundle:bundle compatibleWithTraitCollection:nil];
}

@end

@implementation AppIconOptionsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"App Icon";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    NSDictionary *mainInfo = [[NSBundle mainBundle] infoDictionary];
    NSDictionary *iconsDict = mainInfo[@"CFBundleIcons"];
    NSDictionary *altDict = [iconsDict objectForKey:@"CFBundleAlternateIcons"];
    NSDictionary *altDictPad = [mainInfo[@"CFBundleIcons~ipad"] objectForKey:@"CFBundleAlternateIcons"];
    NSMutableSet *merged = [NSMutableSet set];
    for (NSString *k in altDict) [merged addObject:k];
    for (NSString *k in altDictPad) [merged addObject:k];
    NSArray *alternate = [merged allObjects];
    if (alternate.count == 0) {
        // Fallback: scan the bundle's AppIcons folder (registration may have
        // failed in CI, but previews + prefs still function).
        NSString *iconsDir = [[[NSBundle mainBundle] pathForResource:@"uYouPlus" ofType:@"bundle"] ?: @"" stringByAppendingPathComponent:@"AppIcons"];
        for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:iconsDir error:nil])
            if ([f.pathExtension.lowercaseString isEqualToString:@"png"]) [merged addObject:[f stringByDeletingPathExtension]];
    }
    NSLog(@"[uYouEnhanced] AppIcon picker: %lu registered, %lu total", (unsigned long)alternate.count, (unsigned long)merged.count);
    NSArray *alternateAll = [merged allObjects];
    self.appIcons = [alternateAll sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kPrefDomain]] ?: @{};
    NSString *saved = prefs[kPrefIconName];
    self.selectedIconIndex = saved ? [self.appIcons indexOfObject:saved] : -1;

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 16;
    layout.minimumLineSpacing = 24;
    layout.sectionInset = UIEdgeInsetsMake(16, 16, 24, 16);

    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.backgroundColor = UIColor.clearColor;
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    [self.collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"tile"];
    [self.view addSubview:self.collectionView];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.collectionView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    UICollectionViewFlowLayout *layout = (UICollectionViewFlowLayout *)self.collectionView.collectionViewLayout;
    CGFloat width = self.collectionView.bounds.size.width - layout.sectionInset.left - layout.sectionInset.right;
    NSUInteger columns = MAX(3, MIN(6, (NSUInteger)(width / 130.0)));
    CGFloat spacing = layout.minimumInteritemSpacing * (columns - 1);
    CGFloat side = floorf((width - spacing) / columns);
    CGSize newSize = CGSizeMake(side, side + 30);
    if (!CGSizeEqualToSize(layout.itemSize, newSize)) {
        layout.itemSize = newSize;
        [layout invalidateLayout];
    }
}

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return self.appIcons.count + 1;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"tile" forIndexPath:indexPath];
    [[cell.contentView subviews] makeObjectsPerformSelector:@selector(removeFromSuperview)];

    BOOL isDefault = (indexPath.item == 0);
    NSString *name = isDefault ? nil : self.appIcons[indexPath.item - 1];
    BOOL selected = isDefault ? (self.selectedIconIndex == -1) : (indexPath.item - 1 == self.selectedIconIndex);

    UIView *tileView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, cell.contentView.bounds.size.width, cell.contentView.bounds.size.width)];
    tileView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    tileView.layer.cornerRadius = 18;
    tileView.layer.cornerCurve = kCACornerCurveContinuous;
    tileView.clipsToBounds = YES;
    [cell.contentView addSubview:tileView];

    UIImageView *preview = [[UIImageView alloc] initWithFrame:CGRectMake(14, 14, tileView.bounds.size.width - 28, tileView.bounds.size.width - 28)];
    preview.contentMode = UIViewContentModeScaleAspectFill;
    preview.clipsToBounds = YES;
    preview.layer.cornerRadius = 12;
    preview.layer.cornerCurve = kCACornerCurveContinuous;

    UIImage *img = nil;
    if (!isDefault) {
        NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"uYouPlus" ofType:@"bundle"];
        NSBundle *bundle = bundlePath ? [NSBundle bundleWithPath:bundlePath] : [NSBundle mainBundle];
        img = [UIImage imageWithContentsOfFile:[bundle.bundlePath stringByAppendingPathComponent:[NSString stringWithFormat:@"AppIcons/%@.png", name]]];
        if (!img) img = [UIImage imageWithContentsOfFile:[NSString stringWithFormat:@"/Library/Application Support/uYouEnhanced/AppIcons/%@.png", name]];
    }
    preview.image = img ?: [UIImage systemImageNamed:isDefault ? @"paintbrush" : @"photo"];
    preview.tintColor = [UIColor secondaryLabelColor];
    [tileView addSubview:preview];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, tileView.bounds.size.height + 6, cell.contentView.bounds.size.width, 18)];
    label.text = isDefault ? @"Default" : name;
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    label.textColor = [UIColor labelColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.adjustsFontSizeToFitWidth = YES;
    [cell.contentView addSubview:label];

    if (selected) {
        UIView *badge = [[UIView alloc] initWithFrame:CGRectMake(tileView.bounds.size.width - 26, 8, 20, 20)];
        badge.backgroundColor = [UIColor systemBlueColor];
        badge.layer.cornerRadius = 10;
        [tileView addSubview:badge];
        UIImageView *check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIFontWeightBold]]];
        check.tintColor = UIColor.whiteColor;
        check.frame = badge.bounds;
        check.center = badge.center;
        [tileView addSubview:check];
    }
    return cell;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [cv deselectItemAtIndexPath:indexPath animated:YES];
    BOOL isDefault = (indexPath.item == 0);
    NSString *iconName = isDefault ? nil : self.appIcons[indexPath.item - 1];

    NSString *prefsPath = [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kPrefDomain];
    NSMutableDictionary *prefs = [[NSMutableDictionary alloc] initWithContentsOfFile:prefsPath] ?: [NSMutableDictionary dictionary];
    prefs[kPrefEnableIconOverride] = @(YES);
    prefs[kPrefIconName] = iconName ?: @"";
    [prefs writeToFile:prefsPath atomically:YES];
    notify_post([kPrefNotifyName UTF8String]);

    self.selectedIconIndex = isDefault ? -1 : indexPath.item - 1;
    [cv reloadData];

    if (@available(iOS 10.3, *)) {
        if ([[UIApplication sharedApplication] respondsToSelector:@selector(setAlternateIconName:completionHandler:)]) {
            [[UIApplication sharedApplication] setAlternateIconName:isDefault ? nil : iconName completionHandler:^(NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (error) {
                        NSLog(@"[uYouEnhanced] Icon '%@' rejected: %@", iconName, error.localizedDescription);
                        [self showAlertWithTitle:@"Failed" message:error.localizedDescription];
                    } else {
                        [self showAlertWithTitle:@"Done" message:isDefault ? @"Restored the default app icon." : [NSString stringWithFormat:@"App icon changed to “%@”.", iconName]];
                    }
                });
            }];
        }
    }
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)back {
    [self.navigationController popViewControllerAnimated:YES];
}

@end
