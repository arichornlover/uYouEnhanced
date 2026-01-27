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

@interface AppIconOptionsController () <UITableViewDataSource, UITableViewDelegate>
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

    NSMutableSet<NSString *> *iconNames = [NSMutableSet set];

    NSString *bundlePath = BundlePath();
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];

    if (bundle) {
        NSString *appIconsDir = [bundle.bundlePath stringByAppendingPathComponent:@"AppIcons"];
        BOOL isDir = NO;

        if ([[NSFileManager defaultManager] fileExistsAtPath:appIconsDir isDirectory:&isDir] && isDir) {
            NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:appIconsDir error:nil] ?: @[];
            for (NSString *entry in contents) {
                NSString *full = [appIconsDir stringByAppendingPathComponent:entry];
                BOOL entryIsDir = NO;
                if ([[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&entryIsDir] && entryIsDir) {
                    [iconNames addObject:entry];
                }
            }
        }
    }

    NSString *supportBase = @"/Library/Application Support/uYouEnhanced/AppIcons";
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL supportIsDir = NO;

    if ([fm fileExistsAtPath:supportBase isDirectory:&supportIsDir] && supportIsDir) {
        NSArray *dirs = [fm contentsOfDirectoryAtPath:supportBase error:nil] ?: @[];
        for (NSString *d in dirs) {
            NSString *full = [supportBase stringByAppendingPathComponent:d];
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:full isDirectory:&isDir] && isDir) {
                [iconNames addObject:d];
            }
        }
    }

    self.appIcons = [[iconNames allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kPrefDomain]] ?: @{};
    NSString *savedIcon = prefs[kPrefIconName];

    if (savedIcon) {
        NSInteger idx = [self.appIcons indexOfObject:savedIcon];
        if (idx != NSNotFound) self.selectedIconIndex = idx;
    }

    if (self.appIcons.count == 0) {
        UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectInset(self.view.bounds, 20, 20)];
        lbl.text = @"No custom icons found. Place icon folders in the tweak bundle under AppIcons/ or in /Library/Application Support/uYouEnhanced/AppIcons/";
        lbl.numberOfLines = 0;
        lbl.textAlignment = NSTextAlignmentCenter;
        lbl.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:lbl];
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

    UIImage *preview = nil;
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

    BOOL foundCandidate = NO;

    for (NSString *c in candidates) {
        if (bundle) {
            NSString *dir = [bundle.bundlePath stringByAppendingPathComponent:[NSString stringWithFormat:@"AppIcons/%@", iconName]];
            NSString *imagePath = [dir stringByAppendingPathComponent:c];

            if ([fm fileExistsAtPath:imagePath]) {
                preview = [UIImage imageWithContentsOfFile:imagePath];
                foundCandidate = YES;
                break;
            }
        }

        NSString *supportIconPath = [supportBase stringByAppendingPathComponent:[iconName stringByAppendingPathComponent:c]];
        if ([fm fileExistsAtPath:supportIconPath]) {
            preview = [UIImage imageWithContentsOfFile:supportIconPath];
            foundCandidate = YES;
            break;
        }
    }

    if (!foundCandidate) {
        NSString *dir = [bundle.bundlePath stringByAppendingPathComponent:[NSString stringWithFormat:@"AppIcons/%@", iconName]];
        NSArray *files = [fm contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *file in files) {
            if ([[file.pathExtension lowercaseString] isEqualToString:@"png"]) {
                NSString *path = [dir stringByAppendingPathComponent:file];
                preview = [UIImage imageWithContentsOfFile:path];
                break;
            }
        }
    }

    cell.imageView.image = preview;
    cell.imageView.layer.cornerRadius = 12.0;
    cell.imageView.clipsToBounds = YES;
    cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
    cell.accessoryType = ((indexPath.row - 1) == self.selectedIconIndex) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;

    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tv deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row == 0) {
        self.selectedIconIndex = -1;
        NSMutableDictionary *prefs = [[NSMutableDictionary alloc] initWithContentsOfFile:[NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kPrefDomain]] ?: [NSMutableDictionary dictionary];
        prefs[kPrefEnableIconOverride] = @NO;
        [prefs writeToFile:[NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kPrefDomain] atomically:YES];
        notify_post([kPrefNotifyName UTF8String]);
        [self.tableView reloadData];
        [self showAlertWithTitle:@"Requested" message:@"Icon reset requested."];
        return;
    }

    self.selectedIconIndex = indexPath.row - 1;
    NSString *iconName = self.appIcons[self.selectedIconIndex];

    NSMutableDictionary *prefs = [[NSMutableDictionary alloc] initWithContentsOfFile:[NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kPrefDomain]] ?: [NSMutableDictionary dictionary];
    prefs[kPrefEnableIconOverride] = @YES;
    prefs[kPrefIconName] = iconName;

    BOOL ok = [prefs writeToFile:[NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kPrefDomain] atomically:YES];
    if (!ok) {
        [self showAlertWithTitle:@"Error" message:@"Failed to save preference"];
        return;
    }

    notify_post([kPrefNotifyName UTF8String]);
    [self.tableView reloadData];
    [self showAlertWithTitle:@"Requested" message:@"Icon change requested."];
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
