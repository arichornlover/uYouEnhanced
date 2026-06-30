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
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;

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

    UIButton *backBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [backBtn setImage:[UIImage customBackButtonImage] forState:UIControlStateNormal];
    [backBtn addTarget:self action:@selector(back) forControlEvents:UIControlEventTouchUpInside];
    UIBarButtonItem *customBack = [[UIBarButtonItem alloc] initWithCustomView:backBtn];
    self.navigationItem.leftBarButtonItem = customBack;

    // Load icons
    NSMutableSet<NSString *> *iconNames = [NSMutableSet set];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *bundlePath = BundlePath();
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];

    NSString *iconsDir = [bundle.bundlePath stringByAppendingPathComponent:@"AppIcons"];
    if ([fm fileExistsAtPath:iconsDir]) {
        for (NSString *entry in [fm contentsOfDirectoryAtPath:iconsDir error:nil]) {
            NSString *full = [iconsDir stringByAppendingPathComponent:entry];
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:full isDirectory:&isDir]) {
                [iconNames addObject:entry];
            } else if ([entry.pathExtension.lowercaseString isEqualToString:@"png"]) {
                [iconNames addObject:[entry stringByDeletingPathExtension]];
            }
        }
    }

    NSString *supportDir = @"/Library/Application Support/uYouEnhanced/AppIcons";
    if ([fm fileExistsAtPath:supportDir]) {
        for (NSString *entry in [fm contentsOfDirectoryAtPath:supportDir error:nil]) {
            NSString *full = [supportDir stringByAppendingPathComponent:entry];
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:full isDirectory:&isDir]) {
                [iconNames addObject:entry];
            } else if ([entry.pathExtension.lowercaseString isEqualToString:@"png"]) {
                [iconNames addObject:[entry stringByDeletingPathExtension]];
            }
        }
    }

    self.appIcons = [[iconNames allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kPrefDomain]] ?: @{};
    NSString *saved = prefs[kPrefIconName];
    if (saved) {
        NSInteger idx = [self.appIcons indexOfObject:saved];
        if (idx != NSNotFound) self.selectedIconIndex = idx;
    }

    if (self.appIcons.count == 0) {
        UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectInset(self.view.bounds, 20, 20)];
        lbl.text = @"No custom icons found.\nPlace PNGs or folders in:\n• uYouPlus.bundle/AppIcons/\n• /Library/Application Support/uYouEnhanced/AppIcons/";
        lbl.numberOfLines = 0;
        lbl.textAlignment = NSTextAlignmentCenter;
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
    NSArray<NSString *> *candidates = @[@"AppIcon60x60@3x.png", @"Icon@3x.png", @"Icon.png"];

    NSString *bundlePath = BundlePath();
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    NSString *supportBase = @"/Library/Application Support/uYouEnhanced/AppIcons";
    NSFileManager *fm = [NSFileManager defaultManager];

    for (NSString *c in candidates) {
        NSString *path = [bundle.bundlePath stringByAppendingPathComponent:[NSString stringWithFormat:@"AppIcons/%@/%@", iconName, c]];
        if ([fm fileExistsAtPath:path]) {
            preview = [UIImage imageWithContentsOfFile:path];
            break;
        }
        path = [supportBase stringByAppendingPathComponent:[NSString stringWithFormat:@"%@/%@", iconName, c]];
        if ([fm fileExistsAtPath:path]) {
            preview = [UIImage imageWithContentsOfFile:path];
            break;
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

    NSString *prefsPath = [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kPrefDomain];
    NSMutableDictionary *prefs = [[NSMutableDictionary alloc] initWithContentsOfFile:prefsPath] ?: [NSMutableDictionary dictionary];

    if (indexPath.row == 0) {
        self.selectedIconIndex = -1;
        prefs[kPrefEnableIconOverride] = @NO;
        [prefs writeToFile:prefsPath atomically:YES];
        notify_post([kPrefNotifyName UTF8String]);
        [self.tableView reloadData];
        [self showAlertWithTitle:@"Success" message:@"Icon reset requested."];
        return;
    }

    self.selectedIconIndex = indexPath.row - 1;
    NSString *iconName = self.appIcons[self.selectedIconIndex];

    prefs[kPrefEnableIconOverride] = @YES;
    prefs[kPrefIconName] = iconName;

    [prefs writeToFile:prefsPath atomically:YES];
    notify_post([kPrefNotifyName UTF8String]);
    [self.tableView reloadData];
    [self showAlertWithTitle:@"Success" message:@"Icon change requested."];
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
