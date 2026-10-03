#import "uYouPlus.h"
#import "UYTLog.h"

@interface YTPivotBarItemView : UIView
@end

UIImage *resizeImage(UIImage *image, CGSize newSize) {
    UIGraphicsBeginImageContextWithOptions(newSize, NO, 0.0);
    [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    UIImage *resizedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return resizedImage;
}

static int getNotificationIconStyle() {
    return [[NSUserDefaults standardUserDefaults] integerForKey:@"notificationIconStyle"];
}

static NSInteger _notificationsBadgeCount = 0;

%group gShowNotificationsTab
%hook YTAppPivotBarItemStyle
- (UIImage *)pivotBarItemIconImageWithIconType:(int)type color:(UIColor *)color useNewIcons:(BOOL)isNew selected:(BOOL)isSelected {
    NSString *imageName;
    UIColor *iconColor;
    switch (getNotificationIconStyle()) {
        case 1:
            imageName = isSelected ? @"notifications_selected" : @"notifications_unselected";
            iconColor = [%c(YTColor) white1];
            break;
        case 2:
            imageName = isSelected ? @"notifications_selected" : @"notifications_24pt";
            iconColor = [%c(YTColor) white1];
            break;
        case 3:
            imageName = @"notifications_selected";
            iconColor = isSelected ? [%c(YTColor) white1] : [UIColor grayColor];
            break;
        case 4:
            imageName = @"inbox_selected";
            iconColor = isSelected ? [%c(YTColor) white1] : [UIColor grayColor];
            break;
        default:
            imageName = isSelected ? @"notifications_selected_2025" : @"notifications_unselected_2025";
            iconColor = [%c(YTColor) white1];
            break;
    }
    NSString *imagePath = [tweakBundle pathForResource:imageName ofType:@"png" inDirectory:@"UI"];
    UIImage *image = [UIImage imageWithContentsOfFile:imagePath];
    CGSize newSize = CGSizeMake(24, 24);
    image = resizeImage(image, newSize);
    image = [%c(QTMIcon) tintImage:image color:iconColor];
    return type == YT_NOTIFICATIONS ? image : %orig;
}
%end
%hook YTPivotBarView
- (void)setRenderer:(YTIPivotBarRenderer *)renderer {
    @try {
	@try {
	    for (YTIPivotBarSupportedRenderers *item in renderer.itemsArray) {
		if (item.pivotBarItemRenderer) {
		    @try {
			id badgeData = [item.pivotBarItemRenderer valueForKey:@"notificationCount"];
			if (badgeData && [badgeData respondsToSelector:@selector(integerValue)]) {
			    NSInteger count = [badgeData integerValue];
			    if (count > _notificationsBadgeCount) {
				_notificationsBadgeCount = count;
			    }
			}
		    } @catch (NSException *e2) {}
		}
	    }
	} @catch (NSException *e1) {}

	YTIBrowseEndpoint *endPoint = [[%c(YTIBrowseEndpoint) alloc] init];
	[endPoint setBrowseId:@"FEnotifications_inbox"];
	YTICommand *command = [[%c(YTICommand) alloc] init];
	[command setBrowseEndpoint:endPoint];

	YTIPivotBarItemRenderer *itemBar = [[%c(YTIPivotBarItemRenderer) alloc] init];
	[itemBar setPivotIdentifier:@"FEnotifications_inbox"];
	YTIIcon *icon = [itemBar icon];
	@try { [icon setIconType:YT_NOTIFICATIONS]; } @catch (NSException *e) {}
	[itemBar setNavigationEndpoint:command];

	YTIFormattedString *formatString;
	if (getNotificationIconStyle() == 3) {
		formatString = [%c(YTIFormattedString) formattedStringWithString:@"Inbox"];
	} else {
		formatString = [%c(YTIFormattedString) formattedStringWithString:@"Notifications"];
	}
	[itemBar setTitle:formatString];

	YTIPivotBarSupportedRenderers *barSupport = [[%c(YTIPivotBarSupportedRenderers) alloc] init];
	[barSupport setPivotBarItemRenderer:itemBar];

        NSInteger preferred = [[NSUserDefaults standardUserDefaults] integerForKey:@"FENotificationsTabIndex"];
        NSUInteger insertIndex = renderer.itemsArray.count;
        if (preferred >= 0 && (NSUInteger)preferred < renderer.itemsArray.count) {
            insertIndex = (NSUInteger)preferred;
        }
        [renderer.itemsArray insertObject:barSupport atIndex:insertIndex];
    } @catch (NSException *exception) {
        UYTDebugErr(@"NotificationsTab error setting renderer: %@", exception.reason);
    }
    %orig(
        renderer
    );
}
%end
%hook YTBrowseViewController
- (void)viewDidLoad {
    %orig;
    YTICommand *navEndpoint = nil;
    for (NSString *key in @[@"navigationEndpoint", @"navEndpoint", @"_navEndpoint"]) {
        @try {
            id value = [self valueForKey:key];
            if ([value isKindOfClass:[%c(YTICommand) class]]) { navEndpoint = value; break; }
        } @catch (NSException *e) {}
    }
    if ([navEndpoint.browseEndpoint.browseId isEqualToString:@"FEnotifications_inbox"]) {
        @try {
            UIViewController *notificationsViewController = [[UIViewController alloc] init];
            [self addChildViewController:notificationsViewController];
            [notificationsViewController.view setFrame:CGRectMake(0.0f, 0.0f, self.view.frame.size.width, self.view.frame.size.height)];
            [self.view addSubview:notificationsViewController.view];
            [self.view endEditing:YES];
            [notificationsViewController didMoveToParentViewController:self];
        } @catch (NSException *exception) {
            UYTDebugErr(@"NotificationsTab cannot show notifications view controller: %@", exception.reason);
        }
    }
}
%end

%hook YTPivotBarItemView
- (void)layoutSubviews {
    %orig;
    if (!IS_ENABLED(kShowNotificationsTab)) return;

    @try {
        NSString *pivotId = nil;
        id item = nil;
        @try { item = [self valueForKey:@"renderer"]; } @catch (NSException *e) {}
        if (item && [item respondsToSelector:@selector(pivotIdentifier)]) {
            pivotId = [item pivotIdentifier];
        }
        BOOL isNotificationsItem = [pivotId isEqualToString:@"FEnotifications_inbox"];

        if (!isNotificationsItem || _notificationsBadgeCount <= 0) {
            for (UIView *subview in self.subviews) {
                if (subview.tag == 9999) {
                    [subview removeFromSuperview];
                }
            }
            return;
        }

        UILabel *badgeLabel = nil;
        for (UIView *subview in self.subviews) {
            if (subview.tag == 9999) {
                badgeLabel = (UILabel *)subview;
                break;
            }
        }

        if (!badgeLabel) {
            badgeLabel = [[UILabel alloc] init];
            badgeLabel.tag = 9999;
            badgeLabel.textColor = [UIColor whiteColor];
            badgeLabel.backgroundColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:1.0];
            badgeLabel.font = [UIFont boldSystemFontOfSize:10];
            badgeLabel.textAlignment = NSTextAlignmentCenter;
            badgeLabel.clipsToBounds = YES;
            [self addSubview:badgeLabel];
        }

        NSString *badgeText;
        if (_notificationsBadgeCount > 99) {
            badgeText = @"99+";
        } else {
            badgeText = [NSString stringWithFormat:@"%ld", (long)_notificationsBadgeCount];
        }
        badgeLabel.text = badgeText;

        NSDictionary *attrs = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:10]};
        CGSize textSize = [badgeText sizeWithAttributes:attrs];
        CGFloat badgeWidth = MAX(textSize.width + 8, 18);
        CGFloat badgeHeight = 16;

        badgeLabel.frame = CGRectMake(
            self.bounds.size.width - badgeWidth / 2,
            -badgeHeight / 2,
            badgeWidth,
            badgeHeight
        );
        badgeLabel.layer.cornerRadius = badgeHeight / 2;
    } @catch (NSException *e) {
        UYTDebugErr(@"NotificationsTab badge error: %@", e);
    }
}
%end
%end

%ctor {
    if (IS_ENABLED(kShowNotificationsTab)) {
        %init(gShowNotificationsTab);
    }
}

