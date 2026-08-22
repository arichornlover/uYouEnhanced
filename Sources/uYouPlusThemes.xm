#import "uYouPlus.h"

#define IS_DARK_APPEARANCE_ENABLED ([[NSUserDefaults standardUserDefaults] integerForKey:@"page_style"] == 1)
#define IS_OLD_DARK_THEME_SELECTED (APP_THEME_IDX == 1)
#define IS_OLED_DARK_THEME_SELECTED (APP_THEME_IDX == 2)
#define IS_CUSTOM_DARK_THEME_SELECTED (APP_THEME_IDX == 3)

static inline BOOL themePageStyleIsDark(id palette) {
    if (palette && [palette respondsToSelector:@selector(pageStyle)]) {
        SEL sel = @selector(pageStyle);
        Method pageStyleMethod = class_getInstanceMethod(object_getClass(palette), sel);
        if (pageStyleMethod) {
            NSInteger (*pageStyleIMP)(id, SEL) = (NSInteger (*)(id, SEL))method_getImplementation(pageStyleMethod);
            return pageStyleIMP(palette, sel) == 1;
        }
    }
    return UITraitCollection.currentTraitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
}

# pragma mark - Old dark theme (lighter grey)

%group gOldDarkTheme
%hook YTCommonColorPalette
- (UIColor *)background1 {
    return themePageStyleIsDark(self) ? [UIColor colorWithRed:0.129 green:0.129 blue:0.129 alpha:1.0] : %orig;
}
- (UIColor *)background2 {
    return themePageStyleIsDark(self) ? [UIColor colorWithRed:0.129 green:0.129 blue:0.129 alpha:1.0] : %orig;
}
- (UIColor *)background3 {
    return themePageStyleIsDark(self) ? [UIColor colorWithRed:0.129 green:0.129 blue:0.129 alpha:1.0] : %orig;
}
- (UIColor *)baseBackground {
    return themePageStyleIsDark(self) ? [UIColor colorWithRed:0.129 green:0.129 blue:0.129 alpha:1.0] : %orig;
}
- (UIColor *)brandBackgroundSolid {
    return themePageStyleIsDark(self) ? [UIColor colorWithRed:0.129 green:0.129 blue:0.129 alpha:1.0] : %orig;
}
- (UIColor *)brandBackgroundPrimary {
    return themePageStyleIsDark(self) ? [UIColor colorWithRed:0.129 green:0.129 blue:0.129 alpha:1.0] : %orig;
}
- (UIColor *)brandBackgroundSecondary {
    return themePageStyleIsDark(self) ? [[UIColor colorWithRed:0.129 green:0.129 blue:0.129 alpha:1.0] colorWithAlphaComponent:0.9] : %orig;
}
- (UIColor *)raisedBackground {
    return themePageStyleIsDark(self) ? [UIColor colorWithRed:0.129 green:0.129 blue:0.129 alpha:1.0] : %orig;
}
- (UIColor *)staticBrandBlack {
    return themePageStyleIsDark(self) ? [UIColor colorWithRed:0.129 green:0.129 blue:0.129 alpha:1.0] : %orig;
}
- (UIColor *)generalBackgroundA {
    return themePageStyleIsDark(self) ? [UIColor colorWithRed:0.129 green:0.129 blue:0.129 alpha:1.0] : %orig;
}
- (UIColor *)generalBackgroundB {
    return themePageStyleIsDark(self) ? [UIColor colorWithRed:0.129 green:0.129 blue:0.129 alpha:1.0] : %orig;
}
- (UIColor *)menuBackground {
    return themePageStyleIsDark(self) ? [UIColor colorWithRed:0.129 green:0.129 blue:0.129 alpha:1.0] : %orig;
}
%end

%hook YTColdConfig
- (BOOL)uiSystemsClientGlobalConfigUseDarkerPaletteBgColorForNative { return NO; }
- (BOOL)uiSystemsClientGlobalConfigUseDarkerPaletteTextColorForNative { return NO; }
- (BOOL)enableCinematicContainerOnClient { return NO; }
%end

%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    if ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.comment_composer"]) { self.backgroundColor = [UIColor clearColor]; }
    if ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.video_list_entry"]) { self.backgroundColor = [UIColor clearColor]; }
}
%end

%hook ASCollectionView
- (void)didMoveToWindow {
    %orig;
    self.superview.backgroundColor = [UIColor colorWithRed:0.129 green:0.129 blue:0.129 alpha:1.0];
}
%end

%hook YTFullscreenEngagementOverlayView
- (void)didMoveToWindow {
    %orig;
    self.subviews[0].backgroundColor = [UIColor clearColor];
}
%end

%hook YTRelatedVideosView
- (void)didMoveToWindow {
    %orig;
    self.subviews[0].backgroundColor = [UIColor clearColor];
}
%end
%end

# pragma mark - OLED dark mode by BandarHL

UIColor* raisedColor = [UIColor colorWithRed:0.035 green:0.035 blue:0.035 alpha:1.0];

%group gOLED
%hook YTColor
+ (UIColor *)black0 {
    return [UIColor blackColor];
}
+ (UIColor *)black1 {
    return [UIColor blackColor];
}
+ (UIColor *)black2 {
    return [UIColor blackColor];
}
+ (UIColor *)black3 {
    return [UIColor blackColor];
}
+ (UIColor *)black4 {
    return [UIColor blackColor];
}
%end

%hook YTCommonColorPalette
- (UIColor *)baseBackground {
    return themePageStyleIsDark(self) ? [UIColor blackColor] : %orig;
}
- (UIColor *)brandBackgroundSolid {
    return themePageStyleIsDark(self) ? [UIColor blackColor] : %orig;
}
- (UIColor *)brandBackgroundPrimary {
    return themePageStyleIsDark(self) ? [UIColor blackColor] : %orig;
}
- (UIColor *)brandBackgroundSecondary {
    return themePageStyleIsDark(self) ? [[UIColor blackColor] colorWithAlphaComponent:0.9] : %orig;
}
- (UIColor *)raisedBackground {
    return themePageStyleIsDark(self) ? [UIColor blackColor] : %orig;
}
- (UIColor *)staticBrandBlack {
    return themePageStyleIsDark(self) ? [UIColor blackColor] : %orig;
}
- (UIColor *)generalBackgroundA {
    return themePageStyleIsDark(self) ? [UIColor blackColor] : %orig;
}
%end

// uYou settings

%hook settingsReorderTable
- (void)viewDidLayoutSubviews {
    %orig;
    self.tableView.backgroundColor = [UIColor blackColor];
}
%end

%hook FRPSelectListTable
- (void)viewDidLayoutSubviews {
    %orig;
    self.tableView.backgroundColor = [UIColor blackColor];
}
%end

%hook FRPreferences
- (void)viewDidLayoutSubviews {
    %orig;
    self.tableView.backgroundColor = [UIColor blackColor];
}
%end

%hook YTInnerTubeCollectionViewController
- (UIColor *)backgroundColor:(NSInteger)pageStyle {
    return pageStyle == 1 ? [UIColor blackColor] : %orig;
}
%end

// Explore
%hook ASScrollView 
- (void)didMoveToWindow {
    %orig;
    if (IS_DARK_APPEARANCE_ENABLED) {
        self.backgroundColor = [UIColor clearColor];
    }
}
%end

// Download sort
%hook GOODialogView
- (void)setBackgroundColor:(UIColor *)color {
    if (IS_DARK_APPEARANCE_ENABLED) {
        %orig([UIColor blackColor]);
    } else {
        %orig;
    }
}
%end

// Playlist sort
%hook ASCollectionView
- (void)didMoveToWindow {
    %orig;
    if (IS_DARK_APPEARANCE_ENABLED && [self.nextResponder isKindOfClass:%c(_ASDisplayView)]) {
        self.superview.backgroundColor = [UIColor blackColor];
        self.backgroundColor = [UIColor clearColor];
    }
}
%end

%hook UIApplication
- (void)applicationDidFinishLaunching:(UIApplication *)application {
    if (@available(iOS 14.0, *)) {
        NSArray<UIWindow *> *windows = application.windows;
        if (windows.count > 0) {
            windows[0].backgroundColor = [UIColor blackColor];
        }
    }
    %orig;
}
%end

// Others
%hook _ASDisplayView
- (void)layoutSubviews {
    %orig;
    if (IS_DARK_APPEARANCE_ENABLED) {
    UIResponder *responder = [self nextResponder];
    while (responder != nil) {
        if ([responder isKindOfClass:NSClassFromString(@"YTActionSheetDialogViewController")]) {
            self.backgroundColor = [UIColor blackColor];
        }
        if ([responder isKindOfClass:NSClassFromString(@"YTPanelLoadingStrategyViewController")]) {
            self.backgroundColor = [UIColor blackColor];
        }
        if ([responder isKindOfClass:NSClassFromString(@"YTTabHeaderElementsViewController")]) {
            self.backgroundColor = [UIColor blackColor];
        }
        if ([responder isKindOfClass:NSClassFromString(@"YTEditSheetControllerElementsContentViewController")]) {
            self.backgroundColor = [UIColor blackColor];
        }
        responder = [responder nextResponder];
      }
   }
}
- (void)didMoveToWindow {
    %orig;
    if (IS_DARK_APPEARANCE_ENABLED) {
        //
        UIResponder *responder = self.nextResponder;
        UIViewController *closestViewController = nil;

        while (responder != nil) {
            if ([responder isKindOfClass:[UIViewController class]]) {
                closestViewController = (UIViewController *)responder;
                break;
            }
            responder = responder.nextResponder;
        }

        if ([NSStringFromClass([closestViewController class]) isEqualToString:@"YTActionSheetDialogViewController"] && 
            (([NSStringFromClass([self.superview class]) isEqualToString:@"YTELMView"]) || 
            [NSStringFromClass([self.superview class]) isEqualToString:@"_ASDisplayView"] || 
            [NSStringFromClass([self.superview class]) isEqualToString:@"ELMView"])) {

            self.backgroundColor = [UIColor clearColor];
        }

        // Save video bottom
        if ([NSStringFromClass([closestViewController class]) isEqualToString:@"YTBottomSheetController"]) { self.backgroundColor = [UIColor clearColor]; } 

        //  Subcriptions header
        if ([NSStringFromClass([closestViewController class]) isEqualToString:@"YTMySubsFilterHeaderViewController"] && 
            ([NSStringFromClass([self.superview class]) isEqualToString:@"YTELMView"])) { 
            self.backgroundColor = [UIColor clearColor]; 
        }
        if ([self.accessibilityIdentifier isEqualToString:@"brand_promo.view"]) { self.backgroundColor = [UIColor blackColor]; }
        if ([self.accessibilityIdentifier isEqualToString:@"eml.topic_channel_details"]) { self.backgroundColor = [UIColor blackColor]; }
        if ([self.accessibilityIdentifier isEqualToString:@"eml.live_chat_text_message"]) { self.backgroundColor = [UIColor blackColor]; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment_cell"]) { self.backgroundColor = [UIColor blackColor]; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment_thread"]) { self.backgroundColor = [UIColor blackColor]; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.comment_composer"]) { self.backgroundColor = [UIColor blackColor]; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.filter_chip_bar"]) { self.backgroundColor = [UIColor blackColor]; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.video_list_entry"]) { self.backgroundColor = [UIColor blackColor]; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.comment.guidelines_text"]) { self.superview.backgroundColor = [UIColor blackColor]; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.comment.timed_comments_welcome"]) { self.superview.backgroundColor = self.backgroundColor = [UIColor blackColor]; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.comment.channel_guidelines_entry_banner_container"]) { self.superview.backgroundColor = self.backgroundColor = [UIColor blackColor]; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.comment.comment_group_detail_container"]) { self.backgroundColor = [UIColor clearColor]; }
    }
}
%end

// Open link with...
%hook ASWAppSwitchingSheetHeaderView
- (void)setBackgroundColor:(UIColor *)color {
    if (IS_DARK_APPEARANCE_ENABLED) {
        %orig(raisedColor);
    } else {
        %orig;
    }
}
%end

%hook ASWAppSwitchingSheetFooterView
- (void)setBackgroundColor:(UIColor *)color {
    if (IS_DARK_APPEARANCE_ENABLED) {
        %orig(raisedColor);
    } else {
        %orig;
    }
}
%end

%hook ASWAppSwitcherCollectionViewCell
- (void)didMoveToWindow {
    %orig;
    if (IS_DARK_APPEARANCE_ENABLED) {
        self.backgroundColor = raisedColor;
        self.superview.backgroundColor = raisedColor;
    }
}
%end

// Incompatibility with the new YT Dark theme
%hook YTColdConfig
- (BOOL)uiSystemsClientGlobalConfigUseDarkerPaletteBgColorForNative { return NO; }
%end
%end

# pragma mark - Custom dark mode by BandarHL

UIColor *customHexColor;

%group gCustomTheme
%hook YTCommonColorPalette
- (UIColor *)baseBackground {
    return themePageStyleIsDark(self) ? customHexColor : %orig;
}
- (UIColor *)brandBackgroundSolid {
    return themePageStyleIsDark(self) ? customHexColor : %orig;
}
- (UIColor *)brandBackgroundPrimary {
    return themePageStyleIsDark(self) ? customHexColor : %orig;
}
- (UIColor *)brandBackgroundSecondary {
    return themePageStyleIsDark(self) ? [customHexColor colorWithAlphaComponent:0.9] : %orig;
}
- (UIColor *)raisedBackground {
    return themePageStyleIsDark(self) ? customHexColor : %orig;
}
- (UIColor *)staticBrandBlack {
    return themePageStyleIsDark(self) ? customHexColor : %orig;
}
- (UIColor *)generalBackgroundA {
    return themePageStyleIsDark(self) ? customHexColor : %orig;
}
%end

%hook settingsReorderTable
- (void)viewDidLayoutSubviews {
    %orig;
    self.tableView.backgroundColor = customHexColor;
}
%end

%hook FRPSelectListTable
- (void)viewDidLayoutSubviews {
    %orig;
    self.tableView.backgroundColor = customHexColor;
}
%end

%hook FRPreferences
- (void)viewDidLayoutSubviews {
    %orig;
    self.tableView.backgroundColor = customHexColor;
}
%end

%hook YTInnerTubeCollectionViewController
- (UIColor *)backgroundColor:(NSInteger)pageStyle {
    return pageStyle == 1 ? customHexColor : %orig;
}
%end

// Explore
%hook ASScrollView 
- (void)didMoveToWindow {
    %orig;
    if (IS_DARK_APPEARANCE_ENABLED) {
        self.backgroundColor = [UIColor clearColor];
    }
}
%end

// Your videos
%hook ASCollectionView
- (void)didMoveToWindow {
    %orig;
    if (IS_DARK_APPEARANCE_ENABLED && [self.nextResponder isKindOfClass:%c(_ASDisplayView)]) {
        self.superview.backgroundColor = customHexColor;
    }
}
%end

// Sub menu?
%hook ELMView
- (void)didMoveToWindow {
    %orig;
    if (IS_DARK_APPEARANCE_ENABLED) {
        // self.subviews[0].backgroundColor = [UIColor clearColor];
    }
}
%end

// Search view
%hook YTSearchBarView
- (void)setBackgroundColor:(UIColor *)color {
    if (IS_DARK_APPEARANCE_ENABLED) {
        %orig(customHexColor);
    } else {
        %orig;
    }
}
%end

// History search view
%hook YTSearchBoxView 
- (void)setBackgroundColor:(UIColor *)color {
    if (IS_DARK_APPEARANCE_ENABLED) {
        %orig(customHexColor);
    } else {
        %orig;
    }
}
%end

// Comment view
%hook YTCommentView
- (void)setBackgroundColor:(UIColor *)color {
    if (IS_DARK_APPEARANCE_ENABLED) {
        %orig(customHexColor);
    } else {
        %orig;
    }
}
%end

%hook YTCreateCommentAccessoryView
- (void)setBackgroundColor:(UIColor *)color {
    if (IS_DARK_APPEARANCE_ENABLED) {
        %orig(customHexColor);
    } else {
        %orig;
    }
}
%end

%hook YTCreateCommentTextView
- (void)setBackgroundColor:(UIColor *)color {
    if (IS_DARK_APPEARANCE_ENABLED) {
        %orig(customHexColor);
    } else {
        %orig;
    }
}
- (void)setTextColor:(UIColor *)color { // fix black text in #Shorts video's comment
    if (IS_DARK_APPEARANCE_ENABLED) {
        %orig([UIColor whiteColor]);
    } else {
        %orig;
    }
}
%end

%hook YTCommentDetailHeaderCell
- (void)didMoveToWindow {
    %orig;
    if (IS_DARK_APPEARANCE_ENABLED) {
        // self.subviews[2].backgroundColor = customHexColor;
    }
}
%end

%hook YTFormattedStringLabel  // YT is werid...
- (void)setBackgroundColor:(UIColor *)color {
    if (IS_DARK_APPEARANCE_ENABLED) {
        %orig([UIColor clearColor]);
    } else {
        %orig;
    }
}
%end

// Live chat comment
%hook YCHLiveChatActionPanelView 
- (void)setBackgroundColor:(UIColor *)color {
    if (IS_DARK_APPEARANCE_ENABLED) {
        %orig(customHexColor);
    } else {
        %orig;
    }
}
%end

%hook YTEmojiTextView
- (void)setBackgroundColor:(UIColor *)color {
    if (IS_DARK_APPEARANCE_ENABLED) {
        %orig(customHexColor);
    } else {
        %orig;
    }
}
%end

%hook YCHLiveChatView
- (void)didMoveToWindow {
    %orig;
    if (IS_DARK_APPEARANCE_ENABLED) {
        // self.subviews[1].backgroundColor = customHexColor;
    }
}
%end

%hook YTCollectionView 
- (void)setBackgroundColor:(UIColor *)color { 
    if (IS_DARK_APPEARANCE_ENABLED) {
        %orig(customHexColor);
    } else {
        %orig;
    }
}
%end

//
%hook YTBackstageCreateRepostDetailView
- (void)setBackgroundColor:(UIColor *)color {
    if (IS_DARK_APPEARANCE_ENABLED) {
        %orig(customHexColor);
    } else {
        %orig;
    }
}
%end

%hook UIApplication
- (void)applicationDidFinishLaunching:(UIApplication *)application {
    if (@available(iOS 14.0, *)) {
        NSArray<UIWindow *> *windows = application.windows;
        if (windows.count > 0) {
            windows[0].backgroundColor = customHexColor;
        }
    }
    %orig;
}
%end

// Others
%hook _ASDisplayView
- (void)layoutSubviews {
    %orig;
    if (IS_DARK_APPEARANCE_ENABLED) {
    UIResponder *responder = [self nextResponder];
    while (responder != nil) {
        if ([responder isKindOfClass:NSClassFromString(@"YTActionSheetDialogViewController")]) {
            self.backgroundColor = customHexColor;
        }
        if ([responder isKindOfClass:NSClassFromString(@"YTPanelLoadingStrategyViewController")]) {
            self.backgroundColor = customHexColor;
        }
        if ([responder isKindOfClass:NSClassFromString(@"YTTabHeaderElementsViewController")]) {
            self.backgroundColor = customHexColor;
        }
        if ([responder isKindOfClass:NSClassFromString(@"YTEditSheetControllerElementsContentViewController")]) {
            self.backgroundColor = customHexColor;
        }
        responder = [responder nextResponder];
      }
   }
}
- (void)didMoveToWindow {
    %orig;
    if (IS_DARK_APPEARANCE_ENABLED) {
        if ([self.nextResponder isKindOfClass:%c(ASScrollView)]) { self.backgroundColor = [UIColor clearColor]; }
        if ([self.accessibilityIdentifier isEqualToString:@"brand_promo.view"]) { self.backgroundColor = customHexColor; }
        if ([self.accessibilityIdentifier isEqualToString:@"eml.cvr"]) { self.backgroundColor = customHexColor; }
        if ([self.accessibilityIdentifier isEqualToString:@"eml.topic_channel_details"]) { self.backgroundColor = customHexColor; }
        if ([self.accessibilityIdentifier isEqualToString:@"eml.live_chat_text_message"]) { self.backgroundColor = customHexColor; }
        if ([self.accessibilityIdentifier isEqualToString:@"rich_header"]) { self.backgroundColor = customHexColor; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment_cell"]) { self.backgroundColor = customHexColor; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.ui.comment_thread"]) { self.backgroundColor = customHexColor; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.ui.cancel.button"]) { self.superview.backgroundColor = [UIColor clearColor]; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.comment_composer"]) { self.backgroundColor = customHexColor; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.filter_chip_bar"]) { self.backgroundColor = customHexColor; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.elements.components.video_list_entry"]) { self.backgroundColor = customHexColor; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.comment.guidelines_text"]) { self.superview.backgroundColor = customHexColor; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.comment.timed_comments_welcome"]) { self.superview.backgroundColor = self.backgroundColor = customHexColor; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.comment.channel_guidelines_bottom_sheet_container"]) { self.backgroundColor = customHexColor; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.comment.channel_guidelines_entry_banner_container"]) { self.superview.backgroundColor = self.backgroundColor = customHexColor; }
        if ([self.accessibilityIdentifier isEqualToString:@"id.comment.comment_group_detail_container"]) { self.backgroundColor = [UIColor clearColor]; }
        if ([self.accessibilityIdentifier hasPrefix:@"id.elements.components.overflow_menu_item_"]) { self.backgroundColor = [UIColor clearColor]; }
    }
}
%end

// Open link with...
%hook ASWAppSwitchingSheetHeaderView
- (void)setBackgroundColor:(UIColor *)color {
    if (IS_DARK_APPEARANCE_ENABLED) {
        %orig(raisedColor);
    } else {
        %orig;
    }
}
%end

%hook ASWAppSwitchingSheetFooterView
- (void)setBackgroundColor:(UIColor *)color {
    if (IS_DARK_APPEARANCE_ENABLED) {
        %orig(raisedColor);
    } else {
        %orig;
    }
}
%end

%hook ASWAppSwitcherCollectionViewCell
- (void)didMoveToWindow {
    %orig;
    if (IS_DARK_APPEARANCE_ENABLED) {
        self.backgroundColor = raisedColor;
        // self.subviews[1].backgroundColor = raisedColor;
        self.superview.backgroundColor = raisedColor;
    }
}
%end

// Incompatibility with the new YT Dark theme
%hook YTColdConfig
- (BOOL)uiSystemsClientGlobalConfigUseDarkerPaletteBgColorForNative { return NO; }
%end
%end


# pragma mark - OLED keyboard

@interface UIKeyboard : UIView
+ (UIKeyboard *)activeKeyboard;
@end

@interface UIKBVisualEffectView : UIView
@property (nonatomic, copy) NSArray *backgroundEffects;
@end

static inline BOOL oledKBDarkMode(UIView *view) {
    UIResponder *responder = view;
    while (responder != nil) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return ((UIViewController *)responder).traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
        }
        responder = [responder nextResponder];
    }
    if (view.window != nil) {
        return view.window.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return UITraitCollection.currentTraitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
}

%group gOLEDKB
%hook UIKeyboard
- (void)displayLayer:(id)arg1 {
    %orig;
    self.backgroundColor = oledKBDarkMode(self) ? [UIColor blackColor] : [UIColor clearColor];
}
%end

%hook UIPredictionViewController
- (id)_currentTextSuggestions {
    UIKeyboard *keyboard = [%c(UIKeyboard) activeKeyboard];
    if (oledKBDarkMode(keyboard)) {
        [self.view setBackgroundColor:[UIColor blackColor]];
        keyboard.backgroundColor = [UIColor blackColor];
    } else {
        [self.view setBackgroundColor:[UIColor clearColor]];
        keyboard.backgroundColor = [UIColor clearColor];
    }
    return %orig;
}
%end

%hook UIKeyboardDockView
- (void)layoutSubviews {
    %orig;
    self.backgroundColor = oledKBDarkMode(self) ? [UIColor blackColor] : [UIColor clearColor];
}
%end

// Since we can't hook a private framework class from UIKit, we check the class name through the nearest available from UIKit class
%hook UIInputView
- (void)layoutSubviews {
    %orig;
    if ([self isKindOfClass:NSClassFromString(@"TUIEmojiSearchInputView")] // Emoji searching panel
     || [self isKindOfClass:NSClassFromString(@"_SFAutoFillInputView")]) { // Autofill password
        self.backgroundColor = oledKBDarkMode(self) ? [UIColor blackColor] : [UIColor clearColor];
    }
}
%end

%hook UIKBVisualEffectView
- (void)layoutSubviews {
    %orig;
    if (oledKBDarkMode(self)) {
        self.backgroundEffects = nil;
        self.backgroundColor = [UIColor blackColor];
    }
}
%end
%end

%group gOLEDCellTint
%hook UITableViewCell
- (void)_layoutSystemBackgroundView {
    %orig;
    UIView *systemBackgroundView = [self valueForKey:@"_systemBackgroundView"];
    NSString *backgroundViewKey = class_getInstanceVariable(systemBackgroundView.class, "_colorView") ? @"_colorView" : @"_backgroundView";
    ((UIView *)[systemBackgroundView valueForKey:backgroundViewKey]).backgroundColor = [UIColor blackColor];
}
- (void)_layoutSystemBackgroundView:(BOOL)arg1 {
    %orig;
    ((UIView *)[[self valueForKey:@"_systemBackgroundView"] valueForKey:@"_colorView"]).backgroundColor = [UIColor blackColor];
}
%end
%end

%group gCustomCellTint
%hook UITableViewCell
- (void)_layoutSystemBackgroundView {
    %orig;
    UIView *systemBackgroundView = [self valueForKey:@"_systemBackgroundView"];
    NSString *backgroundViewKey = class_getInstanceVariable(systemBackgroundView.class, "_colorView") ? @"_colorView" : @"_backgroundView";
    ((UIView *)[systemBackgroundView valueForKey:backgroundViewKey]).backgroundColor = customHexColor;
}
- (void)_layoutSystemBackgroundView:(BOOL)arg1 {
    %orig;
    ((UIView *)[[self valueForKey:@"_systemBackgroundView"] valueForKey:@"_colorView"]).backgroundColor = customHexColor;
}
%end
%end

%ctor {
    Class paletteClass = %c(YTCommonColorPalette);
    BOOL pageStyleAvailable = paletteClass && [paletteClass instancesRespondToSelector:@selector(pageStyle)];

    Class cellClass = %c(UITableViewCell);
    BOOL cellLayoutAPIPresent = cellClass && ([cellClass instancesRespondToSelector:@selector(_layoutSystemBackgroundView)]
                                           || [cellClass instancesRespondToSelector:@selector(_layoutSystemBackgroundView:)]);

    if (IS_OLED_DARK_THEME_SELECTED && pageStyleAvailable) {
        %init(gOLED);
        if (cellLayoutAPIPresent) {
            %init(gOLEDCellTint);
        }
    }
    if (IS_OLD_DARK_THEME_SELECTED && pageStyleAvailable) {
        %init(gOldDarkTheme)
    }
    if (IS_CUSTOM_DARK_THEME_SELECTED && pageStyleAvailable) {
        NSData *colorData = [[NSUserDefaults standardUserDefaults] objectForKey:@"kCustomThemeColor"];
        NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:colorData error:nil];
        [unarchiver setRequiresSecureCoding:NO];
        NSString *hexString = [unarchiver decodeObjectForKey:NSKeyedArchiveRootObjectKey];
        if (hexString != nil) {
            customHexColor = [unarchiver decodeObjectForKey:NSKeyedArchiveRootObjectKey];
            %init(gCustomTheme);
            if (cellLayoutAPIPresent) {
                %init(gCustomCellTint);
            }
        }
    }

    if (IS_ENABLED(@"oledKeyBoard_enabled")) {
        %init(gOLEDKB);
    }
}
