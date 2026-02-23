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

// Helper to get active contrast color
static inline UIColor *activeContrastColor() {
    return customContrastMode() && lcmHexColor ? lcmHexColor : kLowContrastColor;
}

// Helper to check if dark mode is enabled
static inline BOOL isDarkMode() {
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
}

// Low Contrast Mode v1.8.0 (Compatible with YouTube v19.21.2-v20.44.2)
%group gContrastModeShared

%hook UIColor
+ (UIColor *)colorNamed:(NSString *)name {
    NSArray<NSString *> *targetColors = @[
        @"whiteColor", @"lightTextColor", @"lightGrayColor", @"ychGrey7",
        @"skt_chipBackgroundColor", @"placeholderTextColor", @"systemLightGrayColor",
        @"systemExtraLightGrayColor", @"labelColor", @"secondaryLabelColor",
        @"tertiaryLabelColor", @"quaternaryLabelColor"
    ];
    return [targetColors containsObject:name] ? activeContrastColor() : %orig;
}

+ (UIColor *)whiteColor { return activeContrastColor(); }
+ (UIColor *)lightTextColor { return activeContrastColor(); }
+ (UIColor *)lightGrayColor { return activeContrastColor(); }
%end

%hook YTCommonColorPalette
+ (id)darkPalette {
    id palette = %orig;
    if (isDarkMode()) {
        UIColor *contrastColor = activeContrastColor();
        [palette setValue:contrastColor forKey:@"textPrimary"];
        [palette setValue:contrastColor forKey:@"textSecondary"];
        [palette setValue:contrastColor forKey:@"overlayTextPrimary"];
        [palette setValue:contrastColor forKey:@"overlayTextSecondary"];
        [palette setValue:contrastColor forKey:@"iconActive"];
        [palette setValue:contrastColor forKey:@"iconActiveOther"];
        [palette setValue:contrastColor forKey:@"brandIconActive"];
        [palette setValue:contrastColor forKey:@"staticBrandWhite"];
        [palette setValue:contrastColor forKey:@"overlayIconActiveOther"];
        [palette setValue:[contrastColor colorWithAlphaComponent:0.7] forKey:@"overlayIconInactive"];
        [palette setValue:[contrastColor colorWithAlphaComponent:0.3] forKey:@"overlayIconDisabled"];
        [palette setValue:[contrastColor colorWithAlphaComponent:0.2] forKey:@"overlayFilledButtonActive"];
    }
    return palette;
}

+ (id)lightPalette {
    return %orig;
}

- (UIColor *)textPrimary {
    return isDarkMode() ? activeContrastColor() : %orig;
}
- (UIColor *)textSecondary {
    return isDarkMode() ? activeContrastColor() : %orig;
}
- (UIColor *)overlayTextPrimary {
    return isDarkMode() ? activeContrastColor() : %orig;
}
- (UIColor *)overlayTextSecondary {
    return isDarkMode() ? activeContrastColor() : %orig;
}
- (UIColor *)iconActive {
    return isDarkMode() ? activeContrastColor() : %orig;
}
- (UIColor *)iconActiveOther {
    return isDarkMode() ? activeContrastColor() : %orig;
}
- (UIColor *)brandIconActive {
    return isDarkMode() ? activeContrastColor() : %orig;
}
- (UIColor *)staticBrandWhite {
    return isDarkMode() ? activeContrastColor() : %orig;
}
- (UIColor *)overlayIconActiveOther {
    return isDarkMode() ? activeContrastColor() : %orig;
}
- (UIColor *)overlayIconInactive {
    return isDarkMode() ? [activeContrastColor() colorWithAlphaComponent:0.7] : %orig;
}
- (UIColor *)overlayIconDisabled {
    return isDarkMode() ? [activeContrastColor() colorWithAlphaComponent:0.3] : %orig;
}
- (UIColor *)overlayFilledButtonActive {
    return isDarkMode() ? [activeContrastColor() colorWithAlphaComponent:0.2] : %orig;
}
%end

%hook YTColor
+ (BOOL)darkerPaletteTextColorEnabled { return NO; }
+ (UIColor *)white1 { return activeContrastColor(); }
+ (UIColor *)white2 { return activeContrastColor(); }
+ (UIColor *)white3 { return activeContrastColor(); }
+ (UIColor *)white4 { return activeContrastColor(); }
+ (UIColor *)white5 { return activeContrastColor(); }
+ (UIColor *)grey1 { return activeContrastColor(); }
+ (UIColor *)grey2 { return activeContrastColor(); }
%end

%hook _ASDisplayView
- (void)layoutSubviews {
    %orig;
    if (isDarkMode()) {
        NSArray<NSString *> *targetLabels = @[@"connect account", @"Thanks", @"Save to playlist", @"Report", @"Share", @"Like", @"Dislike"];
        UIColor *contrastColor = activeContrastColor();
        for (UIView *subview in self.subviews) {
            if ([targetLabels containsObject:subview.accessibilityLabel]) {
                subview.backgroundColor = contrastColor;
                if ([subview isKindOfClass:[UILabel class]]) {
                    ((UILabel *)subview).textColor = [UIColor blackColor];
                }
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
    if (isDarkMode()) {
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
    if (isDarkMode()) {
        [[UILabel appearance] setTextColor:kDefaultTextColor];
    }
}
- (void)setTextColor:(UIColor *)textColor {
    %orig(isDarkMode() ? kDefaultTextColor : textColor);
}
%end

%hook UITextField
- (void)setTextColor:(UIColor *)textColor {
    %orig(isDarkMode() ? kDefaultTextColor : textColor);
}
%end

%hook UITextView
- (void)setTextColor:(UIColor *)textColor {
    %orig(isDarkMode() ? kDefaultTextColor : textColor);
}
%end

%hook UISearchBar
- (void)setTextColor:(UIColor *)textColor {
    %orig(isDarkMode() ? kDefaultTextColor : textColor);
}
%end

%hook UISegmentedControl
- (void)setTitleTextAttributes:(NSDictionary *)attributes forState:(UIControlState)state {
    if (isDarkMode()) {
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
    %orig(isDarkMode() ? kDefaultTextColor : color, state);
}
%end

%hook UIBarButtonItem
- (void)setTitleTextAttributes:(NSDictionary *)attributes forState:(UIControlState)state {
    if (isDarkMode()) {
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
    if (isDarkMode()) {
        NSMutableDictionary *modifiedAttributes = [NSMutableDictionary dictionaryWithDictionary:attrs];
        modifiedAttributes[NSForegroundColorAttributeName] = kDefaultTextColor;
        return %orig(str, modifiedAttributes);
    }
    return %orig;
}
%end

%hook CATextLayer
- (void)setTextColor:(CGColorRef)textColor {
    %orig(isDarkMode() ? kDefaultTextColor.CGColor : textColor);
}
%end

%hook ASTextNode
- (NSAttributedString *)attributedString {
    NSAttributedString *original = %orig;
    if (isDarkMode()) {
        NSMutableAttributedString *modified = [original mutableCopy];
        [modified addAttribute:NSForegroundColorAttributeName value:kDefaultTextColor range:NSMakeRange(0, modified.length)];
        return modified;
    }
    return original;
}
%end

%hook ASTextFieldNode
- (void)setTextColor:(UIColor *)textColor {
    %orig(isDarkMode() ? kDefaultTextColor : textColor);
}
%end

%hook ASTextView
- (void)setTextColor:(UIColor *)textColor {
    %orig(isDarkMode() ? kDefaultTextColor : textColor);
}
%end

%hook ASButtonNode
- (void)setTextColor:(UIColor *)textColor {
    %orig(isDarkMode() ? kDefaultTextColor : textColor);
}
%end

%hook UIControl
- (UIColor *)backgroundColor {
    return isDarkMode() ? [UIColor blackColor] : %orig;
}
%end

%end

// Constructor
%ctor {
    %init;
    if (lowContrastMode() || customContrastMode()) {
        %init(gContrastModeShared);
        if (customContrastMode()) {
            NSData *colorData = [[NSUserDefaults standardUserDefaults] objectForKey:@"kCustomUIColor"];
            if (colorData) {
                NSError *error = nil;
                NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:colorData error:&error];
                if (!error) {
                    [unarchiver setRequiresSecureCoding:NO];
                    lcmHexColor = [unarchiver decodeObjectForKey:NSKeyedArchiveRootObjectKey];
                }
            }
        }
    }
}
