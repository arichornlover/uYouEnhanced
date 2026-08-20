#import "uYouPlus.h"

// YTHidePlayerButtons 1.1.0 - v20.02.3+ - made by @aricloverEXTRA
// Updated for modern YouTube v20+ with renderer-based identifiers
%group gHidePlayerButtons
static NSDictionary<NSString *, NSString *> *HideToggleMap(void) {
    static NSDictionary<NSString *, NSString *> *map = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            // Modern YouTube v20+ renderer-based identifiers
            @"id.video.share.button": @"hideShareButton_enabled",
            @"id.video.share.button.wrapper": @"hideShareButton_enabled",
            @"id.ui.add_to.offline.button": @"hideDownloadButton_enabled",
            @"id.video.remix.button": @"hideRemixButton_enabled",
            @"id.video.remix.button.wrapper": @"hideRemixButton_enabled",
            @"clip_button.eml": @"hideClipButton_enabled",
            @"id.ui.carousel_header": @"hideCommentSection_enabled",
            @"id.video.thanks.button": @"hideThanksButton_enabled",
            @"id.video.save_to.playlist.button": @"hideSaveToPlaylistButton_enabled",
            @"id.video.report.button": @"hideReportButton_enabled",
            @"id.video.connect.button": @"hideConnectButton_enabled",
            // Modern YouTube v20+ action bar identifiers (protobuf-based)
            @"slim_video_action_bar_share": @"hideShareButton_enabled",
            @"slim_video_action_bar_download": @"hideDownloadButton_enabled",
            @"slim_video_action_bar_remix": @"hideRemixButton_enabled",
            @"slim_video_action_bar_thanks": @"hideThanksButton_enabled",
            @"slim_video_action_bar_clip": @"hideClipButton_enabled",
            // Legacy fallback labels
            @"Like": @"hideLikeButton_enabled",
            @"Dislike": @"hideDislikeButton_enabled",
            @"Share": @"hideShareButton_enabled",
            @"Ask": @"hideAskButton_enabled",
            @"Download": @"hideDownloadButton_enabled",
            @"Hype": @"hideHypeButton_enabled",
            @"Thanks": @"hideThanksButton_enabled",
            @"Remix": @"hideRemixButton_enabled",
            @"Clip": @"hideClipButton_enabled",
            @"Save to playlist": @"hideSaveToPlaylistButton_enabled",
            @"Report": @"hideReportButton_enabled",
            @"connect account": @"hideConnectButton_enabled"
        };
    });
    return map;
}
static BOOL shouldHideForKey(NSString *key) {
    if (!key) return NO;
    NSString *pref = HideToggleMap()[key];
    if (!pref) return NO;
    return IS_ENABLED(pref);
}
static void safeHideView(id view) {
    if (!view) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            if ([view respondsToSelector:@selector(setHidden:)]) {
                [view setHidden:YES];
                return;
            }
            if ([view isKindOfClass:[UIView class]]) {
                ((UIView *)view).hidden = YES;
                return;
            }
        } @catch (NSException *ex) {
            NSLog(@"[HidePlayerButtons] safeHideView exception: %@", ex);
        }
    });
}
static BOOL inspectAndHideIfMatch(id view) {
    if (!view) return NO;
    @try {
        NSString *accId = nil;
        if ([view respondsToSelector:@selector(accessibilityIdentifier)]) {
            @try { accId = [view accessibilityIdentifier]; } @catch (NSException *e) { accId = nil; }
            if (accId && shouldHideForKey(accId)) {
                safeHideView(view);
                return YES;
            }
        }
        NSString *accLabel = nil;
        if ([view respondsToSelector:@selector(accessibilityLabel)]) {
            @try { accLabel = [view accessibilityLabel]; } @catch (NSException *e) { accLabel = nil; }
            if (accLabel && shouldHideForKey(accLabel)) {
                safeHideView(view);
                return YES;
            }
        }
        NSString *desc = nil;
        @try { desc = [[view description] copy]; } @catch (NSException *e) { desc = nil; }
        if (desc) {
            for (NSString *key in HideToggleMap().allKeys) {
                if ([desc containsString:key] && shouldHideForKey(key)) {
                    safeHideView(view);
                    return YES;
                }
            }
        }
    } @catch (NSException *ex) {
        NSLog(@"[HidePlayerButtons] inspectAndHideIfMatch exception: %@", ex);
    }
    return NO;
}
static void traverseAndHideViews(UIView *root) {
    if (!root) return;
    @try {
        inspectAndHideIfMatch(root);
        NSArray<UIView *> *subs = nil;
        @try { subs = root.subviews; } @catch (NSException *e) { subs = nil; }
        if (subs && subs.count) {
            for (UIView *sv in subs) {
                if ([sv isKindOfClass:[UIView class]]) {
                    traverseAndHideViews(sv);
                }
            }
        }
    } @catch (NSException *ex) {
        NSLog(@"[HidePlayerButtons] traverseAndHideViews exception: %@", ex);
    }
}
static void hideButtonsInActionBarIfNeeded(id collectionView) {
    if (!collectionView) return;
    @try {
        // Ensure the collectionView has accessibilityIdentifier and we only operate on the action bar
        NSString *accId = nil;
        if ([collectionView respondsToSelector:@selector(accessibilityIdentifier)]) {
            @try { accId = [collectionView accessibilityIdentifier]; } @catch (NSException *e) { accId = nil; }
        }
        if (!accId) return;
        if (![accId isEqualToString:@"id.video.scrollable_action_bar"]) return;
        NSArray *cells = nil;
        if ([collectionView respondsToSelector:@selector(visibleCells)]) {
            @try { cells = [collectionView visibleCells]; } @catch (NSException *e) { cells = nil; }
        }
        if (!cells || cells.count == 0) {
            @try { cells = [collectionView subviews]; } @catch (NSException *e) { cells = nil; }
        }
        if (!cells || cells.count == 0) return;
        for (id cell in cells) {
            if ([cell isKindOfClass:[UIView class]]) {
                traverseAndHideViews((UIView *)cell);
            } else {
                @try {
                    if ([cell respondsToSelector:@selector(view)]) {
                        id view = [cell performSelector:@selector(view)];
                        if ([view isKindOfClass:[UIView class]]) {
                            traverseAndHideViews((UIView *)view);
                        }
                    } else if ([cell respondsToSelector:@selector(node)]) {
                        NSString *desc = nil;
                        @try { desc = [cell description]; } @catch (NSException *e) { desc = nil; }
                        if (desc) {
                            // Not ideal to act on description, but we keep this non-destructive: only log for debugging
                        }
                    }
                } @catch (NSException *ex) {
                    NSLog(@"[HidePlayerButtons] Exception handling non-UIView cell: %@", ex);
                }
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"[HidePlayerButtons] hideButtonsInActionBarIfNeeded exception: %@", exception);
    }
}
%hook ASCollectionView
- (id)nodeForItemAtIndexPath:(NSIndexPath *)indexPath {
    id node = %orig;
    id weakSelf = (id)self;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            hideButtonsInActionBarIfNeeded(weakSelf);
        } @catch (NSException *e) {
            NSLog(@"[HidePlayerButtons] async hide exception: %@", e);
        }
    });
    return node;
}
- (void)nodesDidRelayout:(NSArray *)nodes {
    %orig;
    id weakSelf = (id)self;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            hideButtonsInActionBarIfNeeded(weakSelf);
        } @catch (NSException *e) {
            NSLog(@"[HidePlayerButtons] relayout hide exception: %@", e);
        }
    });
}
%end
%end

%ctor {
    %init(gHidePlayerButtons);
}
