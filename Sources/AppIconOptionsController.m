#import "AppIconOptionsController.h"
#import <YouTubeHeader/YTAssetLoader.h>
#import <notify.h>

@interface AppIconOptionsController () <UITableViewDataSource, UITableViewDelegate>
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) NSArray<NSString *> *appIcons;
@property (assign, nonatomic) NSInteger selectedIconIndex;
@end

@implementation AppIconOptionsController

static NSString *const kPrefDomain = @"com.arichornlover.uYouEnhanced";
static NSString *const kPrefEnableIconOverride = @"appIconCustomization_enabled";
static NSString *const kPrefIconName = @"customAppIcon_name";
static NSString *const kPrefNotifyName = @"com.arichornlover.uYouEnhanced.prefschanged";

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Change App Icon";
    self.selectedIconIndex = -1;
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
    NSString *path = [[NSBundle mainBundle] pathForResource:@"uYouPlus" ofType:@"bundle"];
    NSBundle *bundle = [NSBundle bundleWithPath:path];
    NSArray *iconDirs = [bundle pathsForResourcesOfType:nil inDirectory:@"AppIcons"];
    NSMutableSet *iconNames = [NSMutableSet set];
    for (NSString *p in iconDirs) {
        NSString *rel = [p stringByReplacingOccurrencesOfString:[bundle bundlePath] withString:@""];
        NSRange r = [p rangeOfString:@"AppIcons/"];
        if (r.location != NSNotFound) {
            NSString *sub = [p substringFromIndex:r.location + r.length];
            NSArray *comp = [sub componentsSeparatedByString:@"/"];
            if (comp.count > 0 && comp[0].length > 0) [iconNames addObject:comp[0]];
        }
    }
    NSString *supportBase = @"/Library/Application Support/uYouEnhanced/Icons";
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:supportBase]) {
        NSArray *dirs = [fm contentsOfDirectoryAtPath:supportBase error:nil];
        for (NSString *d in dirs) {
            if (d.length > 0) [iconNames addObject:d];
        }
    }
    self.appIcons = [[iconNames allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kPrefDomain]] ?: @{};
    NSString *savedIcon = prefs[kPrefIconName];
    if (savedIcon) {
        NSInteger idx = [self.appIcons indexOfObject:savedIcon];
        if (idx != NSNotFound) self.selectedIconIndex = idx;
    }
    UIBarButtonItem *back = [[UIBarButtonItem alloc] initWithTitle:@"Back" style:UIBarButtonItemStylePlain target:self action:@selector(back)];
    self.navigationItem.leftBarButtonItem = back;
}

#pragma mark - UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.appIcons.count + 1;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 80.0;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"AppIconCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    if (indexPath.row == 0) {
        cell.textLabel.text = @"Reset to default";
        cell.imageView.image = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else {
        NSString *iconName = self.appIcons[indexPath.row - 1];
        cell.textLabel.text = iconName;
        UIImage *preview = nil;
        NSString *bundlePreviewPath = [[NSBundle mainBundle] pathForResource:@"uYouPlus" ofType:@"bundle"];
        NSBundle *bundle = [NSBundle bundleWithPath:bundlePreviewPath];
        NSArray *candidates = @[
            [NSString stringWithFormat:@"AppIcons/%@/AppIcon60x60@3x.png", iconName],
            [NSString stringWithFormat:@"AppIcons/%@/AppIcon60x60@2x.png", iconName],
            [NSString stringWithFormat:@"AppIcons/%@/Icon@3x.png", iconName],
            [NSString stringWithFormat:@"AppIcons/%@/Icon@2x.png", iconName],
            [NSString stringWithFormat:@"AppIcons/%@/Icon.png", iconName]
        ];
        for (NSString *c in candidates) {
            NSString *full = [bundle pathForResource:c ofType:nil];
            if (!full) full = [@"/Library/Application Support/uYouEnhanced/Icons" stringByAppendingPathComponent:[iconName stringByAppendingPathComponent:[c lastPathComponent]]];
            if ([[NSFileManager defaultManager] fileExistsAtPath:full]) {
                preview = [UIImage imageWithContentsOfFile:full];
                break;
            }
        }
        cell.imageView.image = preview;
        cell.imageView.layer.cornerRadius = 12.0;
        cell.imageView.clipsToBounds = YES;
        cell.accessoryType = ((indexPath.row - 1) == self.selectedIconIndex) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }
    return cell;
}

#pragma mark - UITableViewDelegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row == 0) {
        self.selectedIconIndex = -1;
        NSMutableDictionary *prefs = [[NSMutableDictionary alloc] initWithContentsOfFile:[NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kPrefDomain]] ?: [NSMutableDictionary dictionary];
        prefs[kPrefEnableIconOverride] = @NO;
        [prefs writeToFile:[NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kPrefDomain] atomically:YES];
        notify_post([kPrefNotifyName UTF8String]);
        [self.tableView reloadData];
        [self showAlertWithTitle:@"Success" message:@"Icon reset requested. SpringBoard should update."];
        return;
    }
    self.selectedIconIndex = indexPath.row - 1;
    NSString *iconName = self.appIcons[self.selectedIconIndex];
    NSMutableDictionary *prefs = [[NSMutableDictionary alloc] initWithContentsOfFile:[NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kPrefDomain]] ?: [NSMutableDictionary dictionary];
    prefs[kPrefEnableIconOverride] = @YES;
    prefs[kPrefIconName] = iconName;
    BOOL wrote = [prefs writeToFile:[NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kPrefDomain] atomically:YES];
    if (!wrote) {
        [self showAlertWithTitle:@"Error" message:@"Failed to save preference"];
        return;
    }
    notify_post([kPrefNotifyName UTF8String]);
    [self.tableView reloadData];
    [self showAlertWithTitle:@"Success" message:@"Requested icon change. SpringBoard should update."];
}

#pragma mark - UI
- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)back {
    [self.navigationController popViewControllerAnimated:YES];
}
@end
