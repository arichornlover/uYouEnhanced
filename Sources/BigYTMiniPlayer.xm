#import "BigYTMiniPlayer.h"

%group BigYTMiniPlayer // https://github.com/Galactic-Dev/BigYTMiniPlayer

// v16.xx.x+ backwards compat: YTWatchMiniBarView / YTWatchMiniBarViewController removed in v21.xx.x
// Logos safely no-ops %hook on missing classes, so these stay inert on newer versions.
%hook YTWatchMiniBarView
- (void)setWatchMiniPlayerLayout:(int)arg1 {
    %orig(1);
}
- (int)watchMiniPlayerLayout {
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

// v21.xx.x+ modern version of BigYTMiniPlayer
%group BigYTMiniPlayerModern

%hook YTWatchMiniBarVisibilityController
- (void)setMiniBarHidden:(BOOL)hidden animated:(BOOL)animated {
    if (IS_ENABLED(kBigYTMiniPlayer)) {
        %orig(NO, animated);
    } else {
        %orig;
    }
}
%end

%hook YTWatchMiniBarButtonView
- (void)layoutSubviews {
    %orig;
    if (IS_ENABLED(kBigYTMiniPlayer)) {
        self.frame = CGRectMake(([UIScreen mainScreen].bounds.size.width - self.frame.size.width), self.frame.origin.y, self.frame.size.width, self.frame.size.height);
    }
}
%end

%hook YTPlaylistMiniBarView
- (void)layoutSubviews {
    %orig;
    if (IS_ENABLED(kBigYTMiniPlayer)) {
        self.frame = CGRectMake(([UIScreen mainScreen].bounds.size.width - self.frame.size.width), self.frame.origin.y, self.frame.size.width, self.frame.size.height);
    }
}
%end

%hook YTMainAppVideoPlayerOverlayView
- (BOOL)isUserInteractionEnabled {
    id ancestor = [self _viewControllerForAncestor];
    if (ancestor) {
        id parent = ancestor.parentViewController;
        if (parent) {
            id grandparent = parent.parentViewController;
            if (grandparent) {
                if ([grandparent isKindOfClass:%c(YTWatchMiniBarViewController)]) {
                    return NO;
                }
                if ([grandparent isKindOfClass:%c(YTWatchMiniBarVisibilityController)] ||
                    [grandparent isKindOfClass:%c(YTPlaylistMiniBarViewController)]) {
                    return NO;
                }
            }
        }
    }
    return %orig;
}
%end
%end

%ctor {
    // v16.xx.x+ backwards compat
    if (IS_ENABLED(kBigYTMiniPlayer) && (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad)) {
        %init(BigYTMiniPlayer);
    }
    // v21.xx.x+ modern
    if (IS_ENABLED(kBigYTMiniPlayer) && (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad)) {
        %init(BigYTMiniPlayerModern);
    }
}
