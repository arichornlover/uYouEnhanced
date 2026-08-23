#import "uYouPlus.h"

// Notifications Tab appearance - @arichornlover & @dayanch96

// Forward declare YTPivotBarItemView as UIView subclass so it can be used
// as a %hook receiver type (only @class forward decl from YouTubeHeader is
// insufficient for receiver usage).
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

// Badge count for the Notifications Tab
static NSInteger _notificationsBadgeCount = 0;

%group gShowNotificationsTab
%hook YTAppPivotBarItemStyle
- (UIImage *)pivotBarItemIconImageWithIconType:(int)type color:(UIColor *)color useNewIcons:(BOOL)isNew selected:(BOOL)isSelected {
    NSString *imageName;
    UIColor *iconColor;
    switch (getNotificationIconStyle()) {
        case 1:  // Bold outline style (2024+)
            imageName = isSelected ? @"notifications_selected" : @"notifications_unselected";
            iconColor = [%c(YTColor) white1];
            break;
        case 2:  // Thin outline style (2020+)
            imageName = isSelected ? @"notifications_selected" : @"notifications_24pt";
            iconColor = [%c(YTColor) white1];
            break;
        case 3:  // Filled style (2018+)
            imageName = @"notifications_selected";
            iconColor = isSelected ? [%c(YTColor) white1] : [UIColor grayColor];
            break;
        case 4:  // Inbox style (2014+)
            imageName = @"inbox_selected";
            iconColor = isSelected ? [%c(YTColor) white1] : [UIColor grayColor];
            break;
        default:  // Default style (2025+)
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
	// Try to read the notification badge count from the guide response
	// YouTube stores notification counts in the pivot bar renderer data
	@try {
	    for (YTIPivotBarSupportedRenderers *item in renderer.itemsArray) {
		if (item.pivotBarItemRenderer) {
		    @try {
			// Try to get notification count via protobuf fields
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
	[icon setIconType:YT_NOTIFICATIONS];
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

        // Position per user preference ("FENotificationsTabIndex", 0-based;
        // -1/absent = append at end). Set from uYouEnhanced settings.
        NSInteger preferred = [[NSUserDefaults standardUserDefaults] integerForKey:@"FENotificationsTabIndex"];
        NSUInteger insertIndex = renderer.itemsArray.count;
        if (preferred >= 0 && (NSUInteger)preferred < renderer.itemsArray.count) {
            insertIndex = (NSUInteger)preferred;
        }
        [renderer.itemsArray insertObject:barSupport atIndex:insertIndex];
    } @catch (NSException *exception) {
        NSLog(@"Error setting renderer: %@", exception.reason);
    }
    %orig(renderer);
}
%end
%hook YTBrowseViewController
- (void)viewDidLoad {
    %orig;
    @try {
        YTICommand *navEndpoint = [self valueForKey:@"_navEndpoint"];
        if ([navEndpoint.browseEndpoint.browseId isEqualToString:@"FEnotifications_inbox"]) {
            UIViewController *notificationsViewController = [[UIViewController alloc] init];
            [self addChildViewController:notificationsViewController];
            // FIXME: View issues
            [notificationsViewController.view setFrame:CGRectMake(0.0f, 0.0f, self.view.frame.size.width, self.view.frame.size.height)];
            [self.view addSubview:notificationsViewController.view];
            [self.view endEditing:YES];
            [notificationsViewController didMoveToParentViewController:self];
        }
    } @catch (NSException *exception) {
        NSLog(@"Cannot show notifications view controller: %@", exception.reason);
    }
}
%end

// Hook to display the notification badge count on the Notifications Tab pivot bar item
%hook YTPivotBarItemView
- (void)layoutSubviews {
    %orig;
    if (!IS_ENABLED(kShowNotificationsTab)) return;

    @try {
        // Identify this view's pivot identifier to only badge the notifications tab
        NSString *pivotId = nil;
        id item = [self valueForKey:@"_item"];
        if (item && [item respondsToSelector:@selector(pivotIdentifier)]) {
            pivotId = [item pivotIdentifier];
        }
        BOOL isNotificationsItem = [pivotId isEqualToString:@"FEnotifications_inbox"];

        // Remove existing badge from non-notifications items
        if (!isNotificationsItem || _notificationsBadgeCount <= 0) {
            for (UIView *subview in self.subviews) {
                if (subview.tag == 9999) {
                    [subview removeFromSuperview];
                }
            }
            return;
        }

        // Check if this view already has a badge (tag 9999)
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

        // Calculate badge size based on text
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
        NSLog(@"[uYouEnhanced] Badge error: %@", e);
    }
}
%end
%end

%ctor {
    if (IS_ENABLED(kShowNotificationsTab)) {
        %init(gShowNotificationsTab);
    }
}
