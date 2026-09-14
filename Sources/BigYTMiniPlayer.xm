#import "BigYTMiniPlayer.h"

%group BigYTMiniPlayer // https://github.com/Galactic-Dev/BigYTMiniPlayer

// BigYTMiniPlayer BACKWARDS COMPATIBILITY
// (YouTube v16.xx.x+ - No clue of the actual compat, these classes are very old.)
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

// MODERNIZED HOOKS (YouTube v21.xx.x+)
// In v21.xx.x+, the mini player was decomposed into a new class family:
// 
// NOTE: There is no single drop-in successor for YTWatchMiniBarView.
// The mini player was decomposed into a new class family with no single
// drop-in successor. These hooks target the new class hierarchy.
// 
// TODO: Reverse-engineer the new class hierarchy to implement proper
// Big YouTube Mini Player functionality for v21.xx.x+.
// Current implementation keeps old hooks for backwards compat (v20.xx.x - v21.xx.x)
// and adds placeholder hooks for new classes that can be implemented
// once the new hierarchy is fully reverse-engineered.

%group BigYTMiniPlayerModern

// YTWatchMiniBarVisibilityController - manages mini player visibility
%hook YTWatchMiniBarVisibilityController
- (void)setMiniBarHidden:(BOOL)hidden animated:(BOOL)animated {
    if (IS_ENABLED(kBigYTMiniPlayer)) {
        // Force mini bar to be visible when enabled
        %orig(NO, animated);
    } else {
        %orig;
    }
}
%end

// YTWatchMiniBarButtonView - the mini player button
%hook YTWatchMiniBarButtonView
- (void)layoutSubviews {
    %orig;
    if (IS_ENABLED(kBigYTMiniPlayer)) {
        // Custom layout for big mini player button
        self.frame = CGRectMake(([UIScreen mainScreen].bounds.size.width - self.frame.size.width), self.frame.origin.y, self.frame.size.width, self.frame.size.height);
    }
}
%end

// YTPlaylistMiniBarView - playlist mini bar view
%hook YTPlaylistMiniBarView
- (void)layoutSubviews {
    %orig;
    if (IS_ENABLED(kBigYTMiniPlayer)) {
        self.frame = CGRectMake(([UIScreen mainScreen].bounds.size.width - self.frame.size.width), self.frame.origin.y, self.frame.size.width, self.frame.size.height);
    }
}
%end

// YTMainAppVideoPlayerOverlayView - disable interaction when mini player is shown
%hook YTMainAppVideoPlayerOverlayView
- (BOOL)isUserInteractionEnabled {
    // Check for both old and new mini player controllers
    id ancestor = [self _viewControllerForAncestor];
    if (ancestor) {
        id parent = ancestor.parentViewController;
        if (parent) {
            id grandparent = parent.parentViewController;
            if (grandparent) {
                // Check old class
                if ([grandparent isKindOfClass:%c(YTWatchMiniBarViewController)]) {
                    return NO;
                }
                // Check new classes
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

%end // BigYTMiniPlayerModern

%ctor {
    // Backwards compat (v16.xx.x+)
    if (IS_ENABLED(kBigYTMiniPlayer) && (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad)) {
        %init(BigYTMiniPlayer);
    }
    
    // Modern hooks (v20.xx.x - v21.xx.x)
    if (IS_ENABLED(kBigYTMiniPlayer) && (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad)) {
        %init(BigYTMiniPlayerModern);
    }
}