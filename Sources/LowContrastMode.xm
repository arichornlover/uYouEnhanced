#import "uYouPlus.h"

// Color Configuration
static UIColor *lcmHexColor = nil;
static UIColor *const kLowContrastColor = [UIColor colorWithRed:0.56 green:0.56 blue:0.56 alpha:1.0];
static UIColor *const kDefaultTextColor = [UIColor whiteColor];

// Utility Functions
static inline int contrastMode() {
    return [[NSUserDefaults standardUserDefaults] integerForKey:@"lcm"];
}

static inline BOOL lowContrastMode() {
    return IS_ENABLED(@"lowContrastMode_enabled") && contrastMode() == 0;
}

static inline BOOL customContrastMode() {
    return IS_ENABLED(@"lowContrastMode_enabled") && contrastMode() == 1;
}

// Low Contrast Mode v1.7.2 (Compatible with YouTube v19.01.1-v20.33.2)
%group gLowContrastMode
%hook UIColor
+ (UIColor *)colorNamed:(NSString *)name {
    NSArray<NSString *> *targetColors = @[
        @"whiteColor", @"lightTextColor", @"lightGrayColor", @"ychGrey7",
        @"skt_chipBackgroundColor", @"placeholderTextColor", @"systemLightGrayColor",
        @"systemExtraLightGrayColor", @"labelColor", @"secondaryLabelColor",
        @"tertiaryLabelColor", @"quaternaryLabelColor"
    ];
    return [targetColors containsObject:name] ? kLowContrastColor : %orig;
}

+ (UIColor *)whiteColor { return kLowContrastColor; }
+ (UIColor *)lightTextColor { return kLowContrastColor; }
+ (UIColor *)lightGrayColor { return kLowContrastColor; }
%end

%hook YTCommonColorPalette
+ (id)darkPalette {
    id palette = %orig;
    if (UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        [palette setValue:kLowContrastColor forKey:@"textPrimary"];
        [palette setValue:kLowContrastColor forKey:@"textSecondary"];
        [palette setValue:kLowContrastColor forKey:@"overlayTextPrimary"];
        [palette setValue:kLowContrastColor forKey:@"overlayTextSecondary"];
        [palette setValue:kLowContrastColor forKey:@"iconActive"];
        [palette setValue:kLowContrastColor forKey:@"iconActiveOther"];
        [palette setValue:kLowContrastColor forKey:@"brandIconActive"];
        [palette setValue:kLowContrastColor forKey:@"staticBrandWhite"];
        [palette setValue:kLowContrastColor forKey:@"overlayIconActiveOther"];
        [palette setValue:[kLowContrastColor colorWithAlphaComponent:0.7] forKey:@"overlayIconInactive"];
        [palette setValue:[kLowContrastColor colorWithAlphaComponent:0.3] forKey:@"overlayIconDisabled"];
        [palette setValue:[kLowContrastColor colorWithAlphaComponent:0.2] forKey:@"overlayFilledButtonActive"];
    }
    return palette;
}

+ (id)lightPalette {
    return %orig;
}

- (UIColor *)textPrimary {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kLowContrastColor : %orig;
}
- (UIColor *)textSecondary {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kLowContrastColor : %orig;
}
- (UIColor *)overlayTextPrimary {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kLowContrastColor : %orig;
}
- (UIColor *)overlayTextSecondary {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kLowContrastColor : %orig;
}
- (UIColor *)iconActive {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kLowContrastColor : %orig;
}
- (UIColor *)iconActiveOther {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kLowContrastColor : %orig;
}
- (UIColor *)brandIconActive {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kLowContrastColor : %orig;
}
- (UIColor *)staticBrandWhite {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kLowContrastColor : %orig;
}
- (UIColor *)overlayIconActiveOther {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kLowContrastColor : %orig;
}
- (UIColor *)overlayIconInactive {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? [kLowContrastColor colorWithAlphaComponent:0.7] : %orig;
}
- (UIColor *)overlayIconDisabled {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? [kLowContrastColor colorWithAlphaComponent:0.3] : %orig;
}
- (UIColor *)overlayFilledButtonActive {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? [kLowContrastColor colorWithAlphaComponent:0.2] : %orig;
}
%end

%hook YTColor
+ (BOOL)darkerPaletteTextColorEnabled { return NO; }
+ (UIColor *)white1 { return kLowContrastColor; }
+ (UIColor *)white2 { return kLowContrastColor; }
+ (UIColor *)white3 { return kLowContrastColor; }
+ (UIColor *)white4 { return kLowContrastColor; }
+ (UIColor *)white5 { return kLowContrastColor; }
+ (UIColor *)grey1 { return kLowContrastColor; }
+ (UIColor *)grey2 { return kLowContrastColor; }
%end

%hook _ASDisplayView
- (void)layoutSubviews {
    %orig;
    NSArray<NSString *> *targetLabels = @[@"connect account", @"Thanks", @"Save to playlist", @"Report", @"Share", @"Like", @"Dislike"];
    for (UIView *subview in self.subviews) {
        if ([targetLabels containsObject:subview.accessibilityLabel] && UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
            subview.backgroundColor = kLowContrastColor;
            if ([subview isKindOfClass:[UILabel class]]) {
                ((UILabel *)subview).textColor = [UIColor blackColor];
            }
        }
    }
}
%end

%hook QTMColorGroup
- (UIColor *)tint100 { return kDefaultTextColor; }
- (UIColor *)tint300 { return kDefaultTextColor; }
- (UIColor *)tint500 { return kDefaultTextColor; }
- (UIColor *)tint700 { return kDefaultTextColor; }
- (UIColor *)accent200 { return kDefaultTextColor; }
- (UIColor *)accent400 { return kDefaultTextColor; }
- (UIColor *)accentColor { return kDefaultTextColor; }
- (UIColor *)brightAccentColor { return kDefaultTextColor; }
- (UIColor *)regularColor { return kDefaultTextColor; }
- (UIColor *)darkerColor { return kDefaultTextColor; }
- (UIColor *)bodyTextColor { return kDefaultTextColor; }
- (UIColor *)lightBodyTextColor { return kDefaultTextColor; }
- (UIColor *)bodyTextColorOnRegularColor { return kDefaultTextColor; }
- (UIColor *)bodyTextColorOnLighterColor { return kDefaultTextColor; }
- (UIColor *)bodyTextColorOnDarkerColor { return kDefaultTextColor; }
- (UIColor *)bodyTextColorOnAccentColor { return kDefaultTextColor; }
- (UIColor *)buttonBackgroundColor { return kDefaultTextColor; }
- (UIColor *)Color { return kDefaultTextColor; }
%end

%hook YTQTMButton
- (void)setImage:(UIImage *)image {
    if (UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        UIImage *tintedImage = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        [self setTintColor:kDefaultTextColor];
        %orig(tintedImage);
    } else {
        %orig;
    }
}
%end

%hook UIExtendedSRGColorSpace
- (void)setTextColor:(UIColor *)textColor {
    %orig([kDefaultTextColor colorWithAlphaComponent:0.9]);
}
%end

%hook UIExtendedSRGBColorSpace
- (void)setTextColor:(UIColor *)textColor {
    %orig([kDefaultTextColor colorWithAlphaComponent:1.0]);
}
%end

%hook UIExtendedGrayColorSpace
- (void)setTextColor:(UIColor *)textColor {
    %orig([kDefaultTextColor colorWithAlphaComponent:1.0]);
}
%end

%hook VideoTitleLabel
- (void)setTextColor:(UIColor *)textColor {
    %orig(kDefaultTextColor);
}
%end

%hook UILabel
+ (void)load {
    if (@available(iOS 16.0, *)) {
        [[UILabel appearance] setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [[UILabel appearance] setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    }
    if (UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        [[UILabel appearance] setTextColor:kDefaultTextColor];
    }
}
- (void)setTextColor:(UIColor *)textColor {
    %orig(UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kDefaultTextColor : textColor);
}
%end

%hook UITextField
- (void)setTextColor:(UIColor *)textColor {
    %orig(UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kDefaultTextColor : textColor);
}
%end

%hook UITextView
- (void)setTextColor:(UIColor *)textColor {
    %orig(UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kDefaultTextColor : textColor);
}
%end

%hook UISearchBar
- (void)setTextColor:(UIColor *)textColor {
    %orig(UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kDefaultTextColor : textColor);
}
%end

%hook UISegmentedControl
- (void)setTitleTextAttributes:(NSDictionary *)attributes forState:(UIControlState)state {
    if (UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        NSMutableDictionary *modifiedAttributes = [NSMutableDictionary dictionaryWithDictionary:attributes];
        modifiedAttributes[NSForegroundColorAttributeName] = kDefaultTextColor;
        %orig(modifiedAttributes, state);
    } else {
        %orig;
    }
}
%end

%hook UIButton
- (void)setTitleColor:(UIColor *)color forState:(UIControlState)state {
    %orig(UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kDefaultTextColor : color, state);
}
%end

%hook UIBarButtonItem
- (void)setTitleTextAttributes:(NSDictionary *)attributes forState:(UIControlState)state {
    if (UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        NSMutableDictionary *modifiedAttributes = [NSMutableDictionary dictionaryWithDictionary:attributes];
        modifiedAttributes[NSForegroundColorAttributeName] = kDefaultTextColor;
        %orig(modifiedAttributes, state);
    } else {
        %orig;
    }
}
%end

%hook NSAttributedString
- (instancetype)initWithString:(NSString *)str attributes:(NSDictionary<NSAttributedStringKey, id> *)attrs {
    if (UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        NSMutableDictionary *modifiedAttributes = [NSMutableDictionary dictionaryWithDictionary:attrs];
        modifiedAttributes[NSForegroundColorAttributeName] = kDefaultTextColor;
        return %orig(str, modifiedAttributes);
    }
    return %orig;
}
%end

%hook CATextLayer
- (void)setTextColor:(CGColorRef)textColor {
    %orig(UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kDefaultTextColor.CGColor : textColor);
}
%end

%hook ASTextNode
- (NSAttributedString *)attributedString {
    NSAttributedString *original = %orig;
    if (UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        NSMutableAttributedString *modified = [original mutableCopy];
        [modified addAttribute:NSForegroundColorAttributeName value:kDefaultTextColor range:NSMakeRange(0, modified.length)];
        return modified;
    }
    return original;
}
%end

%hook ASTextFieldNode
- (void)setTextColor:(UIColor *)textColor {
    %orig(UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kDefaultTextColor : textColor);
}
%end

%hook ASTextView
- (void)setTextColor:(UIColor *)textColor {
    %orig(UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kDefaultTextColor : textColor);
}
%end

%hook ASButtonNode
- (void)setTextColor:(UIColor *)textColor {
    %orig(UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kDefaultTextColor : textColor);
}
%end

%hook UIControl
- (UIColor *)backgroundColor {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor blackColor] : %orig;
}
%end
%end

// Custom Contrast Mode
%group gCustomContrastMode
%hook UIColor
+ (UIColor *)colorNamed:(NSString *)name {
    NSArray<NSString *> *targetColors = @[
        @"whiteColor", @"lightTextColor", @"lightGrayColor", @"ychGrey7",
        @"skt_chipBackgroundColor", @"placeholderTextColor", @"systemLightGrayColor",
        @"systemExtraLightGrayColor", @"labelColor", @"secondaryLabelColor",
        @"tertiaryLabelColor", @"quaternaryLabelColor"
    ];
    return [targetColors containsObject:name] ? lcmHexColor : %orig;
}

+ (UIColor *)whiteColor { return lcmHexColor; }
+ (UIColor *)lightTextColor { return lcmHexColor; }
+ (UIColor *)lightGrayColor { return lcmHexColor; }
%end

%hook YTCommonColorPalette
+ (id)darkPalette {
    id palette = %orig;
    if (UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        [palette setValue:lcmHexColor forKey:@"textPrimary"];
        [palette setValue:lcmHexColor forKey:@"textSecondary"];
        [palette setValue:lcmHexColor forKey:@"overlayTextPrimary"];
        [palette setValue:lcmHexColor forKey:@"overlayTextSecondary"];
        [palette setValue:lcmHexColor forKey:@"iconActive"];
        [palette setValue:lcmHexColor forKey:@"iconActiveOther"];
        [palette setValue:lcmHexColor forKey:@"brandIconActive"];
        [palette setValue:lcmHexColor forKey:@"staticBrandWhite"];
        [palette setValue:lcmHexColor forKey:@"overlayIconActiveOther"];
        [palette setValue:[lcmHexColor colorWithAlphaComponent:0.7] forKey:@"overlayIconInactive"];
        [palette setValue:[lcmHexColor colorWithAlphaComponent:0.3] forKey:@"overlayIconDisabled"];
        [palette setValue:[lcmHexColor colorWithAlphaComponent:0.2] forKey:@"overlayFilledButtonActive"];
    }
    return palette;
}

+ (id)lightPalette {
    return %orig; // No changes for Light Mode
}

- (UIColor *)textPrimary {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? lcmHexColor : %orig;
}
- (UIColor *)textSecondary {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? lcmHexColor : %orig;
}
- (UIColor *)overlayTextPrimary {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? lcmHexColor : %orig;
}
- (UIColor *)overlayTextSecondary {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? lcmHexColor : %orig;
}
- (UIColor *)iconActive {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? lcmHexColor : %orig;
}
- (UIColor *)iconActiveOther {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? lcmHexColor : %orig;
}
- (UIColor *)brandIconActive {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? lcmHexColor : %orig;
}
- (UIColor *)staticBrandWhite {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? lcmHexColor : %orig;
}
- (UIColor *)overlayIconActiveOther {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? lcmHexColor : %orig;
}
- (UIColor *)overlayIconInactive {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? [lcmHexColor colorWithAlphaComponent:0.7] : %orig;
}
- (UIColor *)overlayIconDisabled {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? [lcmHexColor colorWithAlphaComponent:0.3] : %orig;
}
- (UIColor *)overlayFilledButtonActive {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? [lcmHexColor colorWithAlphaComponent:0.2] : %orig;
}
%end

%hook YTColor
+ (BOOL)darkerPaletteTextColorEnabled { return NO; }
+ (UIColor *)white1 { return lcmHexColor; }
+ (UIColor *)white2 { return lcmHexColor; }
+ (UIColor *)white3 { return lcmHexColor; }
+ (UIColor *)white4 { return lcmHexColor; }
+ (UIColor *)white5 { return lcmHexColor; }
+ (UIColor *)grey1 { return lcmHexColor; }
+ (UIColor *)grey2 { return lcmHexColor; }
%end

%hook _ASDisplayView
- (void)layoutSubviews {
    %orig;
    NSArray<NSString *> *targetLabels = @[@"connect account", @"Thanks", @"Save to playlist", @"Report", @"Share", @"Like", @"Dislike"];
    for (UIView *subview in self.subviews) {
        if ([targetLabels containsObject:subview.accessibilityLabel] && UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
            subview.backgroundColor = lcmHexColor;
            if ([subview isKindOfClass:[UILabel class]]) {
                ((UILabel *)subview).textColor = [UIColor blackColor];
            }
        }
    }
}
%end

%hook QTMColorGroup
- (UIColor *)tint100 { return kDefaultTextColor; }
- (UIColor *)tint300 { return kDefaultTextColor; }
- (UIColor *)tint500 { return kDefaultTextColor; }
- (UIColor *)tint700 { return kDefaultTextColor; }
- (UIColor *)accent200 { return kDefaultTextColor; }
- (UIColor *)accent400 { return kDefaultTextColor; }
- (UIColor *)accentColor { return kDefaultTextColor; }
- (UIColor *)brightAccentColor { return kDefaultTextColor; }
- (UIColor *)regularColor { return kDefaultTextColor; }
- (UIColor *)darkerColor { return kDefaultTextColor; }
- (UIColor *)bodyTextColor { return kDefaultTextColor; }
- (UIColor *)lightBodyTextColor { return kDefaultTextColor; }
- (UIColor *)bodyTextColorOnRegularColor { return kDefaultTextColor; }
- (UIColor *)bodyTextColorOnLighterColor { return kDefaultTextColor; }
- (UIColor *)bodyTextColorOnDarkerColor { return kDefaultTextColor; }
- (UIColor *)bodyTextColorOnAccentColor { return kDefaultTextColor; }
- (UIColor *)buttonBackgroundColor { return kDefaultTextColor; }
- (UIColor *)Color { return kDefaultTextColor; }
%end

%hook YTQTMButton
- (void)setImage:(UIImage *)image {
    if (UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        UIImage *tintedImage = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        [self setTintColor:kDefaultTextColor];
        %orig(tintedImage);
    } else {
        %orig;
    }
}
%end

%hook UIExtendedSRGColorSpace
- (void)setTextColor:(UIColor *)textColor {
    %orig([kDefaultTextColor colorWithAlphaComponent:0.9]);
}
%end

%hook UIExtendedSRGBColorSpace
- (void)setTextColor:(UIColor *)textColor {
    %orig([kDefaultTextColor colorWithAlphaComponent:1.0]);
}
%end

%hook UIExtendedGrayColorSpace
- (void)setTextColor:(UIColor *)textColor {
    %orig([kDefaultTextColor colorWithAlphaComponent:1.0]);
}
%end

%hook VideoTitleLabel
- (void)setTextColor:(UIColor *)textColor {
    %orig(kDefaultTextColor);
}
%end

%hook UILabel
+ (void)load {
    if (@available(iOS 16.0, *)) {
        [[UILabel appearance] setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [[UILabel appearance] setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    }
    if (UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        [[UILabel appearance] setTextColor:kDefaultTextColor];
    }
}
- (void)setTextColor:(UIColor *)textColor {
    %orig(UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kDefaultTextColor : textColor);
}
%end

%hook UITextField
- (void)setTextColor:(UIColor *)textColor {
    %orig(UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kDefaultTextColor : textColor);
}
%end

%hook UITextView
- (void)setTextColor:(UIColor *)textColor {
    %orig(UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kDefaultTextColor : textColor);
}
%end

%hook UISearchBar
- (void)setTextColor:(UIColor *)textColor {
    %orig(UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kDefaultTextColor : textColor);
}
%end

%hook UISegmentedControl
- (void)setTitleTextAttributes:(NSDictionary *)attributes forState:(UIControlState)state {
    if (UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        NSMutableDictionary *modifiedAttributes = [NSMutableDictionary dictionaryWithDictionary:attributes];
        modifiedAttributes[NSForegroundColorAttributeName] = kDefaultTextColor;
        %orig(modifiedAttributes, state);
    } else {
        %orig;
    }
}
%end

%hook UIButton
- (void)setTitleColor:(UIColor *)color forState:(UIControlState)state {
    %orig(UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kDefaultTextColor : color, state);
}
%end

%hook UIBarButtonItem
- (void)setTitleTextAttributes:(NSDictionary *)attributes forState:(UIControlState)state {
    if (UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        NSMutableDictionary *modifiedAttributes = [NSMutableDictionary dictionaryWithDictionary:attributes];
        modifiedAttributes[NSForegroundColorAttributeName] = kDefaultTextColor;
        %orig(modifiedAttributes, state);
    } else {
        %orig;
    }
}
%end

%hook NSAttributedString
- (instancetype)initWithString:(NSString *)str attributes:(NSDictionary<NSAttributedStringKey, id> *)attrs {
    if (UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        MutableDictionary *modifiedAttributes = [NSMutableDictionary dictionaryWithDictionary:attrs];
        modifiedAttributes[NSForegroundColorAttributeName] = kDefaultTextColor;
        return %orig(str, modifiedAttributes);
    }
    return %orig;
}
%end

%hook CATextLayer
- (void)setTextColor:(CGColorRef)textColor {
    %orig(UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kDefaultTextColor.CGColor : textColor);
}
%end

%hook ASTextNode
- (NSAttributedString *)attributedString {
    NSAttributedString *original = %orig;
    if (UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        NSMutableAttributedString *modified = [original mutableCopy];
        [modified addAttribute:NSForegroundColorAttributeName value:kDefaultTextColor range:NSMakeRange(0, modified.length)];
        return modified;
    }
    return original;
}
%end

%hook ASTextFieldNode
- (void)setTextColor:(UIColor *)textColor {
    %orig(UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kDefaultTextColor : textColor);
}
%end

%hook ASTextView
- (void)setTextColor:(UIColor *)textColor {
    %orig(UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kDefaultTextColor : textColor);
}
%end

%hook ASButtonNode
- (void)setTextColor:(UIColor *)textColor {
    %orig(UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? kDefaultTextColor : textColor);
}
%end

%hook UIControl
- (UIColor *)backgroundColor {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor blackColor] : %orig;
}
%end
%end

// Constructor
%ctor {
    %init;
    if (lowContrastMode()) {
        %init(gLowContrastMode);
    }
    if (customContrastMode()) {
        NSData *colorData = [[NSUserDefaults standardUserDefaults] objectForKey:@"kCustomUIColor"];
        if (colorData) {
            NSError *error = nil;
            NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:colorData error:&error];
            if (!error) {
                [unarchiver setRequiresSecureCoding:NO];
                lcmHexColor = [unarchiver decodeObjectForKey:NSKeyedArchiveRootObjectKey];
                if (lcmHexColor) {
                    %init(gCustomContrastMode);
                }
            }
        }
    }
}
