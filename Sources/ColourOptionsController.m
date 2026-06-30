#import "ColourOptionsController.h"
#import "uYouPlus.h"

@interface ColourOptionsController ()
@end

@implementation ColourOptionsController

- (void)loadView {
    [super loadView];

    self.title = @"Custom Theme Color";

    UIBarButtonItem *closeButton = [[UIBarButtonItem alloc] initWithTitle:@"Close" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    UIBarButtonItem *saveButton = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:UIBarButtonItemStylePlain target:self action:@selector(save)];
    self.navigationItem.rightBarButtonItems = @[closeButton, saveButton];

    UIBarButtonItem *resetButton = [[UIBarButtonItem alloc] initWithTitle:@"Reset" style:UIBarButtonItemStylePlain target:self action:@selector(reset)];
    self.navigationItem.leftBarButtonItem = resetButton;

    self.supportsAlpha = NO;
    NSData *colorData = [[NSUserDefaults standardUserDefaults] objectForKey:@"kCustomThemeColor"];
    if (colorData) {
        NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:colorData error:nil];
        [unarchiver setRequiresSecureCoding:NO];
        self.selectedColor = [unarchiver decodeObjectForKey:NSKeyedArchiveRootObjectKey];
    }

    // Better iPad scaling
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        CGFloat scale = MIN(self.view.bounds.size.width / 768.0, self.view.bounds.size.height / 1024.0);
        self.view.transform = CGAffineTransformMakeScale(scale, scale);
    }
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            CGFloat scale = MIN(size.width / 768.0, size.height / 1024.0);
            self.view.transform = CGAffineTransformMakeScale(scale, scale);
        } completion:nil];
    }
}

@end

@implementation ColourOptionsController(Privates)

- (void)close {
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)save {
    NSData *colorData = [NSKeyedArchiver archivedDataWithRootObject:self.selectedColor requiringSecureCoding:NO error:nil];
    [[NSUserDefaults standardUserDefaults] setObject:colorData forKey:@"kCustomThemeColor"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Color Saved" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)reset {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"kCustomThemeColor"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
