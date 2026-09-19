#import "BigYTMiniPlayer.h"

%group BigYTMiniPlayer // https://github.com/Galactic-Dev/BigYTMiniPlayer

// v16–v20 backwards compat: YTWatchMiniBarView / YTWatchMiniBarViewController remained
// until v21, where the mini bar was switched to YTNGWatchMiniBarView and
// YTWatchFloatingMiniplayerViewController (see BigYTMiniPlayerModern below).
%hook YTWatchMiniBarView
- (void)setWatchMiniPlayerLayout:(NSInteger)arg1 {
    %orig(
        1
    );
}
- (NSInteger)watchMiniPlayerLayout {
    return 1;
}
- (void)layoutSubviews {
    %orig;
    self.frame = CGRectMake(([UIScreen mainScreen].bounds.size.width - self.frame.size.width), self.frame.origin.y, self.frame.size.width, self.frame.size.height);
}
%end

%hook YTMainAppVideoPlayerOverlayView
- (BOOL)isUserInteractionEnabled {
    if([[self _viewControllerForAncestor].parentViewController.parentViewController isKindOfClass:%c(YTWatchMiniBarViewController)]) {
        return NO;
    }
    return %orig;
}
%end
%end

// v21.xx.x+ modern version of BigYTMiniPlayer.
// YouTube replaced YTWatchMiniBarView with YTNGWatchMiniBarView (same
// watchMiniPlayerLayout property) and added the floating mini player
// (YTWatchFloatingMiniplayerViewController). The old hooks below were hooked
// against classes that no longer exist, so the feature silently did nothing.
%group BigYTMiniPlayerModern

%hook YTNGWatchMiniBarView
- (void)setWatchMiniPlayerLayout:(NSInteger)layout {
    if (IS_ENABLED(kBigYTMiniPlayer)) {
        layout = 1;
    }

    %orig(layout);
}
- (NSInteger)watchMiniPlayerLayout {
    if (IS_ENABLED(kBigYTMiniPlayer)) {
        return 1;
    }

    return %orig;
}
%end

// Floating mini player: scale the pill up so it is actually "big" on v21+.
// Transform is reapplied on every layout so YouTube's animations cannot
// permanently reset it, and it never fights Auto Layout frames.
%hook YTWatchFloatingMiniplayerViewController
- (void)viewDidLayoutSubviews {
    %orig;

    if (IS_ENABLED(kBigYTMiniPlayer)) {
        CGAffineTransform desired = CGAffineTransformMakeScale(1.15f, 1.15f);
        if (!CGAffineTransformEqualToTransform(self.view.transform, desired)) {
            self.view.transform = desired;
        }
    }
}
%end

// Prevent touches inside the enlarged mini bar from falling through to the
// player overlay underneath. Checks the live ancestor chain so it works for
// both the classic watch mini bar and the floating mini player.
%hook YTMainAppVideoPlayerOverlayView
- (BOOL)isUserInteractionEnabled {
    if (IS_ENABLED(kBigYTMiniPlayer)) {
        UIViewController *node = (UIViewController *)[self _viewControllerForAncestor];
        while (node) {
            if ([node isKindOfClass:%c(YTWatchMiniBarViewController)] ||
                [node isKindOfClass:%c(YTWatchFloatingMiniplayerViewController)]) {
                return NO;
            }
            node = node.parentViewController;
        }
    }

    return %orig;
}
%end
%end

static BOOL UYTAppVersionAtLeast(NSString *minVersion) {
    Class versionUtils = %c(YTVersionUtils);
    if (!versionUtils) {
        return NO;
    }

    NSString *appVersion = [versionUtils performSelector:@selector(appVersion)];
    return appVersion != nil && [appVersion compare:minVersion options:NSNumericSearch] != NSOrderedAscending;
}

%ctor {
    if (IS_ENABLED(kBigYTMiniPlayer) && (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad)) {
        if (UYTAppVersionAtLeast(@"21.0.0")) {
            %init(BigYTMiniPlayerModern);
        } else {
            %init(BigYTMiniPlayer);
        }
    }
}