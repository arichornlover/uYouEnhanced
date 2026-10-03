#import "AppIconOptionsController.h"
#import "uYouPlus.h"
#import "UYTLog.h"
#import <notify.h>

static NSString *const kPrefDomain = @"com.arichornlover.uYouEnhanced";
static NSString *const kPrefEnableIconOverride = @"appIconCustomization_enabled";
static NSString *const kPrefIconName = @"customAppIcon_name";
static NSString *const kPrefNotifyName = @"com.arichornlover.uYouEnhanced.prefschanged";

static UIFont *YTFont(CGFloat size, NSString *weight) {
    UIFont *font = [UIFont fontWithName:[NSString stringWithFormat:@"YTSans-%@", weight] size:size];
    if (font) return font;
    UIFontWeight sysWeight = UIFontWeightRegular;
    if ([weight isEqualToString:@"Bold"]) sysWeight = UIFontWeightBold;
    else if ([weight isEqualToString:@"Medium"]) sysWeight = UIFontWeightMedium;
    else if ([weight isEqualToString:@"Semibold"]) sysWeight = UIFontWeightSemibold;
    return [UIFont systemFontOfSize:size weight:sysWeight];
}
static UIImage *YTDefaultAppIcon(void) {
    NSDictionary *mainInfo = [[NSBundle mainBundle] infoDictionary];
    NSDictionary *primary = mainInfo[@"CFBundleIcons"][@"CFBundlePrimaryIcon"];
    NSArray *files = primary[@"CFBundleIconFiles"];
    for (NSString *name in files) {
        for (NSString *suffix in @[@"", @"@2x", @"@3x"]) {
            UIImage *img = [UIImage imageNamed:[name stringByAppendingString:suffix]];
            if (img) return img;
        }
    }
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"uYouPlus" ofType:@"bundle"];
    NSBundle *bundle = bundlePath ? [NSBundle bundleWithPath:bundlePath] : [NSBundle mainBundle];
    UIImage *logo = [UIImage imageNamed:@"youtube_logo.png" inBundle:bundle compatibleWithTraitCollection:nil];
    if (logo) return logo;
    return [UIImage systemImageNamed:@"play.rectangle.fill"];
}

static NSString *UYTIconFilePath(NSString *name) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"uYouPlus" ofType:@"bundle"];
    if (bundlePath.length) {
        NSString *inBundle = [[[bundlePath stringByAppendingPathComponent:@"AppIcons"] stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"png"];
        if ([fm fileExistsAtPath:inBundle]) return inBundle;
    }
    NSString *fallback = [[@"/Library/Application Support/uYouEnhanced/AppIcons" stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"png"];
    if ([fm fileExistsAtPath:fallback]) return fallback;
    return nil;
}

static BOOL UYTIconSpecOK(NSString *name, NSString **reasonOut) {
    NSString *path = UYTIconFilePath(name);
    if (!path) {
        if (reasonOut) *reasonOut = @"no PNG found in uYouPlus.bundle/AppIcons";
        return NO;
    }
    CGImageRef cg = [UIImage imageWithContentsOfFile:path].CGImage;
    if (!cg) {
        if (reasonOut) *reasonOut = @"PNG is unreadable";
        return NO;
    }
    size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
    if (w != 1024 || h != 1024) {
        if (reasonOut) *reasonOut = [NSString stringWithFormat:@"%zux%zu px, iOS requires exactly 1024x1024", w, h];
        return NO;
    }
    CGImageAlphaInfo alpha = CGImageGetAlphaInfo(cg);
    if (alpha != kCGImageAlphaNone && alpha != kCGImageAlphaNoneSkipFirst && alpha != kCGImageAlphaNoneSkipLast) {
        if (reasonOut) *reasonOut = [NSString stringWithFormat:@"alpha channel %d, iOS requires an opaque icon", (int)alpha];
        return NO;
    }
    return YES;
}

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
    self.title = LOC(@"CHANGE_APP_ICON");
    self.view.backgroundColor = [self ytBackgroundColor];

    [self.navigationController.navigationBar setTitleTextAttributes:@{
        NSFontAttributeName: YTFont(22, @"Bold"),
        NSForegroundColorAttributeName: [UIColor labelColor]
    }];

    NSDictionary *mainInfo = [[NSBundle mainBundle] infoDictionary];
    NSDictionary *iconsDict = mainInfo[@"CFBundleIcons"];
    NSDictionary *altDict = [iconsDict objectForKey:@"CFBundleAlternateIcons"];
    NSDictionary *altDictPad = [mainInfo[@"CFBundleIcons~ipad"] objectForKey:@"CFBundleAlternateIcons"];
    NSMutableSet *registered = [NSMutableSet set];
    for (NSString *k in altDict) [registered addObject:k];
    for (NSString *k in altDictPad) [registered addObject:k];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"uYouPlus" ofType:@"bundle"];
    NSMutableArray *iconDirs = [NSMutableArray array];
    if (bundlePath.length) [iconDirs addObject:[bundlePath stringByAppendingPathComponent:@"AppIcons"]];
    [iconDirs addObject:@"/Library/Application Support/uYouEnhanced/AppIcons"];
    NSMutableSet *candidates = [registered mutableCopy];
    for (NSString *dir in iconDirs)
        for (NSString *f in [fm contentsOfDirectoryAtPath:dir error:nil] ?: @[])
            if ([f.pathExtension.lowercaseString isEqualToString:@"png"]) [candidates addObject:[f stringByDeletingPathExtension]];

    NSMutableSet *kept = [NSMutableSet set];
    NSMutableDictionary *drops = [NSMutableDictionary dictionary];
    for (NSString *k in candidates) {
        NSString *reason = nil;
        if (![registered containsObject:k])
            reason = @"not declared in the main bundle CFBundleAlternateIcons";
        else if (!UYTIconSpecOK(k, &reason)) { }
        if (reason.length) drops[reason] = @([drops[reason] integerValue] + 1);
        else [kept addObject:k];
    }
    NSUInteger scannedBeforePrune = [candidates count];
    NSUInteger keptCount = [kept count];
    for (NSString *bucket in drops)
        UYTDebugWarn(@"[uYouEnhanced] AppIcon prune: dropped %@ -> %@", drops[bucket], bucket);
    UYTDebugInfo(@"[uYouEnhanced] AppIcon picker: %lu candidates, %lu usable (dropped %lu that iOS rejects with OSStatus -54)",
                 (unsigned long)scannedBeforePrune, (unsigned long)keptCount,
                 (unsigned long)(scannedBeforePrune - keptCount));
    if (keptCount == 0 && scannedBeforePrune)
        UYTDebugErr(@"[uYouEnhanced] AppIcon: nothing usable. iOS only accepts alternate icons declared in the main app Info.plist CFBundleAlternateIcons, as 1024x1024 opaque PNGs inside the main bundle.");
    NSArray *alternateAll = [kept allObjects];
    self.appIcons = [alternateAll sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kPrefDomain]] ?: @{};
    NSString *saved = prefs[kPrefIconName];
    self.selectedIconIndex = saved ? [self.appIcons indexOfObject:saved] : -1;

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 16;
    layout.minimumLineSpacing = 28;
    layout.sectionInset = UIEdgeInsetsMake(20, 20, 28, 20);

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
    NSUInteger columns = MAX(3, MIN(6, (NSUInteger)(width / 140.0)));
    CGFloat spacing = layout.minimumInteritemSpacing * (columns - 1);
    CGFloat side = floorf((width - spacing) / columns);
    CGSize newSize = CGSizeMake(side, side + 34);
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

    CGFloat tileSize = cell.contentView.bounds.size.width;
    UIView *tileView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tileSize, tileSize)];
    tileView.backgroundColor = [self ytTileColor];
    tileView.layer.cornerRadius = 20;
    tileView.layer.cornerCurve = kCACornerCurveContinuous;
    tileView.clipsToBounds = YES;
    [cell.contentView addSubview:tileView];

    UIImageView *preview = [[UIImageView alloc] initWithFrame:CGRectMake(16, 16, tileSize - 32, tileSize - 32)];
    preview.contentMode = UIViewContentModeScaleAspectFill;
    preview.clipsToBounds = YES;
    preview.layer.cornerRadius = 14;
    preview.layer.cornerCurve = kCACornerCurveContinuous;

    UIImage *img = nil;
    if (isDefault) {
        img = YTDefaultAppIcon();
    } else {
        NSString *path = UYTIconFilePath(name);
        UIImage *full = path ? [UIImage imageWithContentsOfFile:path] : nil;
        if (full) {
            CGSize box = CGSizeMake(tileSize - 32, tileSize - 32);
            UIGraphicsBeginImageContextWithOptions(box, NO, 1.0);
            [[UIColor blackColor] setFill];
            UIRectFill(CGRectMake(0, 0, box.width, box.height));
            [full drawInRect:CGRectMake(0, 0, box.width, box.height)];
            img = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
        }
    }
    preview.image = img ?: [UIImage systemImageNamed:@"photo"];
    preview.tintColor = [UIColor secondaryLabelColor];
    [tileView addSubview:preview];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, tileSize + 8, cell.contentView.bounds.size.width, 20)];
    label.text = isDefault ? LOC(@"DEFAULT") : name;
    label.font = YTFont(13, @"Medium");
    label.textColor = [UIColor labelColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.7;
    [cell.contentView addSubview:label];

    if (selected) {
        UIView *badge = [[UIView alloc] initWithFrame:CGRectMake(tileSize - 30, 10, 22, 22)];
        badge.backgroundColor = [UIColor systemBlueColor];
        badge.layer.cornerRadius = 11;
        [tileView addSubview:badge];
        UIImageView *check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIFontWeightBold]]];
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
    NSString *iconName = nil;
    if (!isDefault) {
        NSUInteger iconIndex = indexPath.item - 1;
        if (iconIndex >= self.appIcons.count) {
            UYTDebugErr(@"[uYouEnhanced] icon tap out of range (cell %lu, %lu icons) - ignoring",
                        (unsigned long)indexPath.item, (unsigned long)self.appIcons.count);
            return;
        }
        iconName = self.appIcons[iconIndex];
        if (!iconName.length) {
            UYTDebugErr(@"[uYouEnhanced] icon list has an empty name at index %lu - ignoring", (unsigned long)iconIndex);
            return;
        }
    }

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
            BOOL resetting = (iconName.length == 0);
            NSString *label = resetting ? @"<default>" : iconName;
            UYTDebugInfo(@"[uYouEnhanced] applying alternate icon %@", label);
            [[UIApplication sharedApplication] setAlternateIconName:iconName completionHandler:^(NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (error) {
                        UYTDebugWarn(@"[uYouEnhanced] icon '%@' rejected (OSStatus %ld): %@", label, (long)error.code, error.localizedDescription);
                        [self showAlertWithTitle:LOC(@"FAILED") message:error.localizedDescription];
                    } else {
                        UYTDebugInfo(@"[uYouEnhanced] alternate icon applied: %@", label);
                    }
                });
            }];
        } else {
            UYTDebugErr(@"[uYouEnhanced] setAlternateIconName:completionHandler: unavailable - icon not applied");
        }
    }
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"OK") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)back {
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - YouTube theme support

- (UIColor *)ytBackgroundColor {
    if (APP_THEME_IDX == 2) return [UIColor blackColor];
    return [UIColor systemGroupedBackgroundColor];
}

- (UIColor *)ytTileColor {
    if (APP_THEME_IDX == 2) return [UIColor colorWithWhite:0.13 alpha:1.0];
    return [UIColor secondarySystemGroupedBackgroundColor];
}

@end

