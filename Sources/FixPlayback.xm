// Playback recovery for videos stopping after ~60 seconds (#896).
// Adapted from Tonwalter888/YouMod FixPlaybackIssues.x,
// originally from Mark02-2012/YTPlaybackFix.

#import "uYouPlus.h"

#import <YouTubeHeader/YTMainAppVideoPlayerOverlayViewController.h>
#import <YouTubeHeader/YTPlayerViewController.h>
#import <YouTubeHeader/YTWatchController.h>

// -reload exists at runtime but isn't declared in YouTubeHeader.
@interface YTWatchController (uYouFixPlayback)
- (void)reload;
@end

%group gFixPlayback

%hook YTMainAppVideoPlayerOverlayViewController
- (void)handleError:(NSError *)error {
    if (error && [error.domain isEqualToString:@"com.google.ios.youtube.ErrorDomain.playback"] && error.code == 14) {
        YTPlayerViewController *playerViewController = (YTPlayerViewController *)self.parentViewController;
        if (![playerViewController.UIDelegate isKindOfClass:%c(YTWatchController)]) return;
        YTWatchController *watchController = (YTWatchController *)playerViewController.UIDelegate;
        dispatch_async(dispatch_get_main_queue(), ^{
            [watchController reload];
        });
        return;
    }
    %orig;
}
%end

%end // gFixPlayback

%ctor {
    if (!IS_ENABLED(kFixPlaybackIssues)) return;
    %init(gFixPlayback);
}