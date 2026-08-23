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
