#import "AppIconOptionsController.h"
#import <notify.h>

static NSString *const kPrefDomain = @"com.arichornlover.uYouEnhanced";
static NSString *const kPrefEnableIconOverride = @"appIconCustomization_enabled";
static NSString *const kPrefIconName = @"customAppIcon_name";
static NSString *const kPrefNotifyName = @"com.arichornlover.uYouEnhanced.prefschanged";

static NSString *BundlePath(void) {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"uYouPlus" ofType:@"bundle"];
    if (path) return path;
    return @"/Library/Application Support/uYouEnhanced";
}

static NSString *GetPrefsPath(void) {
    // Use standard preferences directory
    return [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kPrefDomain];
}

static BOOL EnsurePrefsDirectoryExists(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *prefsDir = @"/var/mobile/Library/Preferences";
    NSError *error = nil;
    
    if (![fm fileExistsAtPath:prefsDir]) {
        if (![fm createDirectoryAtPath:prefsDir withIntermediateDirectories:YES attributes:nil error:&error]) {
            NSLog(@"[uYouEnhanced] Failed to create preferences directory: %@", error);
            return NO;
        }
    }
    return YES;
}

@interface AppIconOptionsController ()

@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) NSArray<NSString *> *appIcons;
@property (assign, nonatomic) NSInteger selectedIconIndex;

@end

@implementation UIImage (CustomImages)

+ (UIImage *)customBackButtonImage {
    NSBundle *bundle = [NSBundle bundleWithPath:BundlePath()];
    return [UIImage imageNamed:@"Back.png" inBundle:bundle compatibleWithTraitCollection:nil];
}

@end

@implementation AppIconOptionsController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Change App Icon";
    self.selectedIconIndex = -1;
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;

    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0;
    }

    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];

    self.navigationItem.hidesBackButton = YES;
    if (@available(iOS 14.0, *)) {
        self.navigationItem.backButtonDisplayMode = UINavigationItemBackButtonDisplayModeMinimal;
    }

    self.backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.backButton setImage:[UIImage customBackButtonImage] forState:UIControlStateNormal];
    [self.backButton addTarget:self action:@selector(back) forControlEvents:UIControlEventTouchUpInside];

    UIBarButtonItem *customBackButton = [[UIBarButtonItem alloc] initWithCustomView:self.backButton];
    self.navigationItem.leftBarButtonItem = customBackButton;

    [self loadAppIcons];
    [self loadSavedIconPreference];
}

- (void)loadAppIcons {
    NSMutableSet<NSString *> *iconNames = [NSMutableSet set];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *bundlePath = BundlePath();
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];

    if (bundle) {
        NSString *appIconsDir = [bundle.bundlePath stringByAppendingPathComponent:@"AppIcons"];
        [self scanIconsInDirectory:appIconsDir fileManager:fm iconNames:iconNames];
    }

    NSString *supportBase = @"/Library/Application Support/uYouEnhanced/AppIcons";
    [self scanIconsInDirectory:supportBase fileManager:fm iconNames:iconNames];

    self.appIcons = [[iconNames allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    if (self.appIcons.count == 0) {
        UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectInset(self.view.bounds, 20, 20)];
        lbl.text = @"No custom icons found. Place PNGs or icon folders in uYouPlus.bundle/AppIcons/ or /Library/Application Support/uYouEnhanced/AppIcons/";
        lbl.numberOfLines = 0;
        lbl.textAlignment = NSTextAlignmentCenter;
        lbl.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:lbl];
    }
}

- (void)scanIconsInDirectory:(NSString *)dirPath fileManager:(NSFileManager *)fm iconNames:(NSMutableSet *)iconNames {
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:dirPath isDirectory:&isDir] || !isDir) {
        return;
    }

    NSError *error = nil;
    NSArray *contents = [fm contentsOfDirectoryAtPath:dirPath error:&error];
    if (error) {
        NSLog(@"[uYouEnhanced] Error scanning directory %@: %@", dirPath, error);
        return;
    }

    for (NSString *entry in contents) {
        NSString *full = [dirPath stringByAppendingPathComponent:entry];
        BOOL entryIsDir = NO;
        if ([fm fileExistsAtPath:full isDirectory:&entryIsDir]) {
            if (entryIsDir) {
                [iconNames addObject:entry];
            } else {
                NSString *ext = entry.pathExtension.lowercaseString;
                if ([ext isEqualToString:@"png"]) {
                    NSString *name = [entry stringByDeletingPathExtension];
                    if (name.length > 0) {
                        [iconNames addObject:name];
                    }
                }
            }
        }
    }
}

- (void)loadSavedIconPreference {
    NSString *prefsPath = GetPrefsPath();
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:prefsPath];
    NSString *savedIcon = prefs[kPrefIconName];

    if (savedIcon) {
        NSInteger idx = [self.appIcons indexOfObject:savedIcon];
        if (idx != NSNotFound) {
            self.selectedIconIndex = idx;
        }
    } else {
        self.selectedIconIndex = -1;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.appIcons.count + 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 80.0;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"AppIconCell";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:CellId];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];

    if (indexPath.row == 0) {
        cell.textLabel.text = @"Reset to default";
        cell.detailTextLabel.text = @"Restore the original app icon";
        cell.imageView.image = nil;
        cell.accessoryType = (self.selectedIconIndex == -1) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        return cell;
    }

    NSString *iconName = self.appIcons[indexPath.row - 1];
    cell.textLabel.text = iconName;
    cell.detailTextLabel.text = @"Tap to apply this icon";

    UIImage *preview = [self loadIconPreviewForName:iconName];
    
    if (preview) {
        cell.imageView.image = preview;
        cell.imageView.layer.cornerRadius = 12.0;
        cell.imageView.clipsToBounds = YES;
        cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
    }

    cell.accessoryType = ((indexPath.row - 1) == self.selectedIconIndex) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;

    return cell;
}

- (UIImage *)loadIconPreviewForName:(NSString *)iconName {
    NSArray<NSString *> *candidates = @[
        @"AppIcon60x60@3x.png",
        @"AppIcon60x60@2x.png",
        @"Icon@3x.png",
        @"Icon@2x.png",
        @"Icon.png"
    ];

    NSString *bundlePath = BundlePath();
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    NSString *supportBase = @"/Library/Application Support/uYouEnhanced/AppIcons";
    NSFileManager *fm = [NSFileManager defaultManager];

    if (bundle) {
        UIImage *image = [self loadIconFromDirectory:[bundle.bundlePath stringByAppendingPathComponent:[NSString stringWithFormat:@"AppIcons/%@", iconName]]
                                          candidates:candidates
                                         fileManager:fm];
        if (image) return image;
    }

    UIImage *image = [self loadIconFromDirectory:[supportBase stringByAppendingPathComponent:iconName]
                                      candidates:candidates
                                     fileManager:fm];
    return image;
}

- (UIImage *)loadIconFromDirectory:(NSString *)dir candidates:(NSArray *)candidates fileManager:(NSFileManager *)fm {
    BOOL isDir = NO;
    
    if (![fm fileExistsAtPath:dir isDirectory:&isDir]) {
        return nil;
    }

    if (isDir) {
        for (NSString *candidate in candidates) {
            NSString *imagePath = [dir stringByAppendingPathComponent:candidate];
            if ([fm fileExistsAtPath:imagePath]) {
                return [UIImage imageWithContentsOfFile:imagePath];
            }
        }

        NSError *error = nil;
        NSArray *files = [fm contentsOfDirectoryAtPath:dir error:&error];
        for (NSString *file in files) {
            if ([file.pathExtension.lowercaseString isEqualToString:@"png"]) {
                NSString *path = [dir stringByAppendingPathComponent:file];
                UIImage *image = [UIImage imageWithContentsOfFile:path];
                if (image) return image;
            }
        }
    } else {
        NSString *pngPath = [NSString stringWithFormat:@"%@.png", dir];
        if ([fm fileExistsAtPath:pngPath]) {
            return [UIImage imageWithContentsOfFile:pngPath];
        }
    }

    return nil;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tv deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row == 0) {
        [self resetIconPreference];
        return;
    }

    NSString *iconName = self.appIcons[indexPath.row - 1];
    [self setIconPreference:iconName];
}

- (void)resetIconPreference {
    NSString *prefsPath = GetPrefsPath();
    NSMutableDictionary *prefs = [[NSMutableDictionary alloc] initWithContentsOfFile:prefsPath] ?: [NSMutableDictionary dictionary];

    self.selectedIconIndex = -1;
    prefs[kPrefEnableIconOverride] = @NO;
    [prefs removeObjectForKey:kPrefIconName];

    if ([self savePreferences:prefs toPath:prefsPath]) {
        notify_post([kPrefNotifyName UTF8String]);
        [self.tableView reloadData];
        [self showAlertWithTitle:@"Requested" message:@"Icon reset requested."];
    } else {
        [self showAlertWithTitle:@"Error" message:@"Failed to save preference"];
    }
}

- (void)setIconPreference:(NSString *)iconName {
    NSString *prefsPath = GetPrefsPath();
    NSMutableDictionary *prefs = [[NSMutableDictionary alloc] initWithContentsOfFile:prefsPath] ?: [NSMutableDictionary dictionary];

    NSInteger idx = [self.appIcons indexOfObject:iconName];
    if (idx == NSNotFound) {
        [self showAlertWithTitle:@"Error" message:@"Selected icon not found"];
        return;
    }

    self.selectedIconIndex = idx;
    prefs[kPrefEnableIconOverride] = @YES;
    prefs[kPrefIconName] = iconName;

    if ([self savePreferences:prefs toPath:prefsPath]) {
        notify_post([kPrefNotifyName UTF8String]);
        [self.tableView reloadData];
        [self showAlertWithTitle:@"Requested" message:@"Icon change requested."];
    } else {
        [self showAlertWithTitle:@"Error" message:@"Failed to save preference"];
    }
}

- (BOOL)savePreferences:(NSDictionary *)prefs toPath:(NSString *)path {
    // Ensure preferences directory exists
    if (!EnsurePrefsDirectoryExists()) {
        NSLog(@"[uYouEnhanced] Could not ensure preferences directory exists");
        return NO;
    }

    NSFileManager *fm = [NSFileManager defaultManager];

    // Write preferences atomically
    BOOL success = [prefs writeToFile:path atomically:YES];
    
    if (!success) {
        NSLog(@"[uYouEnhanced] Failed to write preferences to %@", path);
        return NO;
    }

    // Verify file was actually written
    if (![fm fileExistsAtPath:path]) {
        NSLog(@"[uYouEnhanced] Preferences file does not exist after write: %@", path);
        return NO;
    }

    NSLog(@"[uYouEnhanced] Successfully saved preferences to %@", path);
    return YES;
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *ok = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:ok];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)back {
    [self.navigationController popViewControllerAnimated:YES];
}

@end
