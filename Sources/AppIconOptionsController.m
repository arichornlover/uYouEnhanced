#import "AppIconOptionsController.h"
#import "uYouPlus.h"
#import <notify.h>

@interface AppIconOptionsController () <UITableViewDataSource, UITableViewDelegate>
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) NSArray<NSString *> *appIcons; // list of icon folder names
@property (assign, nonatomic) NSInteger selectedIconIndex;
@end

// Preference keys (must match SpringBoard-side tweak)
static NSString *const kPrefDomain = @"com.arichornlover.uYouEnhanced";
static NSString *const kPrefEnableIconOverride = @"appIconCustomization_enabled";
static NSString *const kPrefIconName = @"customAppIcon_name";
static NSString *const kPrefNotifyName = @"com.arichornlover.uYouEnhanced.prefschanged";

// Helper: path to the bundled resource bundle inside the tweak / preferences app
static NSString *BundlePath(void) {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"uYouPlus" ofType:@"bundle"];
    if (path) return path;
    // fallback to the tweak support folder if running outside the bundle (development)
    return @"/Library/Application Support/uYouEnhanced";
}

@implementation AppIconOptionsController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Change App Icon";
    self.selectedIconIndex = -1;
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    // Back button
    self.backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.backButton setTitle:@"Back" forState:UIControlStateNormal];
    [self.backButton addTarget:self action:@selector(back) forControlEvents:UIControlEventTouchUpInside];
    UIBarButtonItem *customBackButton = [[UIBarButtonItem alloc] initWithCustomView:self.backButton];
    self.navigationItem.leftBarButtonItem = customBackButton;

    // Discover available icon folders
    NSMutableSet<NSString *> *iconNames = [NSMutableSet set];

    // 1) Try bundled resources inside the tweak bundle
    NSString *bundlePath = BundlePath();
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    if (bundle) {
        // Look for directories under AppIcons/
        NSString *appIconsDir = [bundle pathForResource:@"AppIcons" ofType:nil];
        if (!appIconsDir) {
            // If pathForResource didn't return the dir, try bundle path + "/AppIcons"
            appIconsDir = [bundle.bundlePath stringByAppendingPathComponent:@"AppIcons"];
        }
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:appIconsDir isDirectory:&isDir] && isDir) {
            NSArray<NSString *> *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:appIconsDir error:nil] ?: @[];
            for (NSString *entry in contents) {
                NSString *full = [appIconsDir stringByAppendingPathComponent:entry];
                BOOL entryIsDir = NO;
                if ([[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&entryIsDir] && entryIsDir) {
                    if (entry && [entry isKindOfClass:[NSString class]] && entry.length > 0) {
                        [iconNames addObject:entry];
                    }
                }
            }
        } else {
            // If bundle returned resource file paths instead (older APIs), attempt to parse paths
            NSArray *iconDirs = [bundle pathsForResourcesOfType:nil inDirectory:@"AppIcons"];
            for (NSString *p in iconDirs) {
                if (![p isKindOfClass:[NSString class]]) continue;
                NSRange r = [p rangeOfString:@"AppIcons/"];
                if (r.location != NSNotFound) {
                    NSString *sub = [p substringFromIndex:(r.location + r.length)];
                    NSArray<NSString *> *comp = [sub componentsSeparatedByString:@"/"];
                    NSString *first = (comp.count > 0 && [comp[0] isKindOfClass:[NSString class]]) ? comp[0] : nil;
                    if (first && first.length > 0) {
                        [iconNames addObject:first];
                    }
                }
            }
        }
    }

    // 2) Also check installed support folder (/Library/Application Support/...) where package assets may be placed
    NSString *supportBase = @"/Library/Application Support/uYouEnhanced/AppIcons";
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL supportIsDir = NO;
    if ([fm fileExistsAtPath:supportBase isDirectory:&supportIsDir] && supportIsDir) {
        NSArray<NSString *> *dirs = [fm contentsOfDirectoryAtPath:supportBase error:nil] ?: @[];
        for (NSString *d in dirs) {
            if ([d isKindOfClass:[NSString class]] && d.length > 0) {
                NSString *full = [supportBase stringByAppendingPathComponent:d];
                BOOL isDir = NO;
                if ([fm fileExistsAtPath:full isDirectory:&isDir] && isDir) {
                    [iconNames addObject:d];
                }
            }
        }
    }

    // Build sorted list
    self.appIcons = [[iconNames allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    // Load saved selection if present
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kPrefDomain]] ?: @{};
    NSString *savedIcon = prefs[kPrefIconName];
    if (savedIcon && [savedIcon isKindOfClass:[NSString class]]) {
        NSInteger idx = [self.appIcons indexOfObject:savedIcon];
        if (idx != NSNotFound) self.selectedIconIndex = idx;
    }

    if (self.appIcons.count == 0) {
        // Friendly message if no icons found
        UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectInset(self.view.bounds, 20, 20)];
        lbl.text = @"No custom icons found. Place icon folders in the tweak bundle under AppIcons/ or in /Library/Application Support/uYouEnhanced/AppIcons/";
        lbl.numberOfLines = 0;
        lbl.textAlignment = NSTextAlignmentCenter;
        lbl.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:lbl];
    }
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // +1 for Reset option
    return self.appIcons.count + 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 80.0;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"AppIconCell";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:CellId];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    if (indexPath.row == 0) {
        cell.textLabel.text = @"Reset to default";
        cell.detailTextLabel.text = @"Restore the original app icon";
        cell.imageView.image = nil;
        cell.accessoryType = (self.selectedIconIndex == -1) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    } else {
        NSString *iconName = self.appIcons[indexPath.row - 1];
        cell.textLabel.text = iconName;
        cell.detailTextLabel.text = @"Tap to request SpringBoard to apply this icon";

        // Attempt preview: check bundle then support folder
        UIImage *preview = nil;
        NSArray<NSString *> *candidates = @[@"AppIcon60x60@3x.png",@"AppIcon60x60@2x.png",@"Icon@3x.png",@"Icon@2x.png",@"Icon.png"];
        NSString *bundlePath = BundlePath();
        NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
        BOOL foundCandidate = NO;

        for (NSString *c in candidates) {
            NSString *bundleCandidatePath = [NSString stringWithFormat:@"AppIcons/%@/%@", iconName, c];
            NSString *imagePath = [bundle pathForResource:c ofType:nil inDirectory:[NSString stringWithFormat:@"AppIcons/%@", iconName]];
            if (imagePath) {
                preview = [UIImage imageWithContentsOfFile:imagePath];
                foundCandidate = YES;
                NSLog(@"[DEBUG] Loaded icon preview from bundle: %@", imagePath);
                break;
            }

            // Support folder fallback
            NSString *supportIconPath = [@"/Library/Application Support/uYouEnhanced/AppIcons" stringByAppendingPathComponent:[iconName stringByAppendingPathComponent:c]];
            if ([[NSFileManager defaultManager] fileExistsAtPath:supportIconPath]) {
                preview = [UIImage imageWithContentsOfFile:supportIconPath];
                foundCandidate = YES;
                NSLog(@"[DEBUG] Loaded icon preview from support: %@", supportIconPath);
                break;
            }
        }
        if (!foundCandidate) {
            NSLog(@"[WARN] No icon preview found for %@", iconName);
        }

        cell.imageView.image = preview;
        cell.imageView.layer.cornerRadius = 12.0;
        cell.imageView.clipsToBounds = YES;
        cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
        cell.accessoryType = ((indexPath.row - 1) == self.selectedIconIndex) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }

    return cell;
}

#pragma mark - Table Delegate

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tv deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row == 0) {
        // Reset: disable override and notify SpringBoard
        self.selectedIconIndex = -1;
        NSMutableDictionary *prefs = [[NSMutableDictionary alloc] initWithContentsOfFile:[NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kPrefDomain]] ?: [NSMutableDictionary dictionary];
        prefs[kPrefEnableIconOverride] = @NO;
        [prefs writeToFile:[NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kPrefDomain] atomically:YES];
        notify_post([kPrefNotifyName UTF8String]);
        [self.tableView reloadData];
        [self showAlertWithTitle:@"Requested" message:@"Icon reset requested. SpringBoard will attempt to update."];
        return;
    }

    self.selectedIconIndex = indexPath.row - 1;
    NSString *iconName = self.appIcons[self.selectedIconIndex];

    // Persist preference
    NSMutableDictionary *prefs = [[NSMutableDictionary alloc] initWithContentsOfFile:[NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kPrefDomain]] ?: [NSMutableDictionary dictionary];
    prefs[kPrefEnableIconOverride] = @YES;
    prefs[kPrefIconName] = iconName;
    BOOL ok = [prefs writeToFile:[NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kPrefDomain] atomically:YES];
    if (!ok) {
        [self showAlertWithTitle:@"Error" message:@"Failed to save preference"];
        return;
    }

    // Notify SpringBoard to apply change
    notify_post([kPrefNotifyName UTF8String]);

    [self.tableView reloadData];
    [self showAlertWithTitle:@"Requested" message:@"Icon change requested. SpringBoard will attempt to update."];
}

#pragma mark - Utilities

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
