#import "ColourOptionsController2.h"
#import "uYouPlus.h"

@interface ColourOptionsController2 ()
@end

@implementation ColourOptionsController2

- (void)loadView {
    [super loadView];

    self.title = @"Custom Tint Color";

    UIBarButtonItem *closeButton = [[UIBarButtonItem alloc] initWithTitle:@"Close" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    UIBarButtonItem *saveButton = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:UIBarButtonItemStylePlain target:self action:@selector(save)];
    self.navigationItem.rightBarButtonItems = @[closeButton, saveButton];

    UIBarButtonItem *resetButton = [[UIBarButtonItem alloc] initWithTitle:@"Reset" style:UIBarButtonItemStylePlain target:self action:@selector(reset)];
    self.navigationItem.leftBarButtonItem = resetButton;

    self.supportsAlpha = NO;
    NSData *lcmColorData = [[NSUserDefaults standardUserDefaults] objectForKey:@"kCustomUIColor"];
    if (lcmColorData) {
        NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:lcmColorData error:nil];
        [unarchiver setRequiresSecureCoding:NO];
        self.selectedColor = [unarchiver decodeObjectForKey:NSKeyedArchiveRootObjectKey];
    }
}

@end

@implementation ColourOptionsController2(Privates)

- (void)close {
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)save {
    NSData *lcmColorData = [NSKeyedArchiver archivedDataWithRootObject:self.selectedColor requiringSecureCoding:NO error:nil];
    [[NSUserDefaults standardUserDefaults] setObject:lcmColorData forKey:@"kCustomUIColor"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Color Saved" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)reset {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"kCustomUIColor"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
