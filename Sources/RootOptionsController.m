#import "RootOptionsController.h"
#import "ColourOptionsController.h"
#import "ColourOptionsController2.h"

@interface RootOptionsController ()

@property (strong, nonatomic) UIButton *backButton;
@property (assign, nonatomic) UIUserInterfaceStyle pageStyle;

@end

@implementation RootOptionsController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"uYouEnhanced Extras Menu";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    if (@available(iOS 18.0, *)) {
        self.navigationController.navigationBar.prefersLargeTitles = YES;
    }

    [self.navigationController.navigationBar setTitleTextAttributes:@{NSFontAttributeName: [UIFont fontWithName:@"YTSans-Bold" size:22], NSForegroundColorAttributeName: [UIColor labelColor]}];

    [self setupBackButton];
    [self setupTableView];
}

- (void)setupBackButton {
    self.backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    NSBundle *backIcon = [NSBundle bundleWithPath:[[NSBundle mainBundle] pathForResource:@"uYouPlus" ofType:@"bundle"]];
    UIImage *backImage = [UIImage imageNamed:@"Back.png" inBundle:backIcon compatibleWithTraitCollection:nil];
    backImage = [self resizeImage:backImage newSize:CGSizeMake(24, 24)];
    backImage = [backImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [self.backButton setTintColor:[UIColor systemBlueColor]];
    [self.backButton setImage:backImage forState:UIControlStateNormal];
    [self.backButton addTarget:self action:@selector(back) forControlEvents:UIControlEventTouchUpInside];
    UIBarButtonItem *customBackButton = [[UIBarButtonItem alloc] initWithCustomView:self.backButton];
    self.navigationItem.leftBarButtonItem = customBackButton;
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    if (@available(iOS 18.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0;
    }
}

- (UIImage *)resizeImage:(UIImage *)image newSize:(CGSize)newSize {
    UIGraphicsBeginImageContextWithOptions(newSize, NO, [UIScreen mainScreen].scale);
    [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (section == 0) ? 2 : 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"RootTableViewCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];

    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
    }

    [self configureCell:cell atIndexPath:indexPath];
    return cell;
}

- (void)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    cell.textLabel.adjustsFontSizeToFitWidth = YES;
    cell.textLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightRegular];
    cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    BOOL isPortrait = UIDevice.currentDevice.orientation == UIDeviceOrientationPortrait;
    BOOL isPhone = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone;

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Custom Theme Color";
            cell.detailTextLabel.text = isPortrait && isPhone ? @"" : @"Go to Dark Mode settings → Custom Dark Mode";
            cell.imageView.image = [UIImage systemImageNamed:@"slider.horizontal.3"];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Custom Tint Color";
            cell.detailTextLabel.text = isPortrait && isPhone ? @"" : @"Enable LowContrastMode → Custom";
            cell.imageView.image = [UIImage systemImageNamed:@"drop.fill"];
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Clear Cache";
            cell.detailTextLabel.text = [self getCacheSize];
            cell.imageView.image = [UIImage systemImageNamed:@"trash"];
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
    }

    [self applyColorSchemeForCell:cell];
}

- (void)applyColorSchemeForCell:(UITableViewCell *)cell {
    cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.imageView.tintColor = [UIColor labelColor];
}

- (NSString *)getCacheSize {
    NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSArray *filesArray = [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:cachePath error:nil];

    unsigned long long int folderSize = 0;
    for (NSString *fileName in filesArray) {
        NSString *filePath = [cachePath stringByAppendingPathComponent:fileName];
        NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
        folderSize += [fileAttributes fileSize];
    }

    NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
    formatter.countStyle = NSByteCountFormatterCountStyleFile;

    return [formatter stringFromByteCount:folderSize];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            ColourOptionsController *vc = [[ColourOptionsController alloc] init];
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
            nav.modalPresentationStyle = UIModalPresentationFullScreen;
            [self presentViewController:nav animated:YES completion:nil];
        } else if (indexPath.row == 1) {
            ColourOptionsController2 *vc = [[ColourOptionsController2 alloc] init];
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
            nav.modalPresentationStyle = UIModalPresentationFullScreen;
            [self presentViewController:nav animated:YES completion:nil];
        }
    } else if (indexPath.section == 1 && indexPath.row == 0) {
        UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        indicator.color = [UIColor labelColor];
        [indicator startAnimating];
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        cell.accessoryView = indicator;

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
            [[NSFileManager defaultManager] removeItemAtPath:cachePath error:nil];

            dispatch_async(dispatch_get_main_queue(), ^{
                [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:1]] withRowAnimation:UITableViewRowAnimationNone];
            });
        });
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self.tableView reloadData];
}

@end

@implementation RootOptionsController (Privates)

- (void)back {
    [self.navigationController popViewControllerAnimated:YES];
}

@end
