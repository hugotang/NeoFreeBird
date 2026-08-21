//
//  HideUI.x
//  NeoFreeBird
//

#import "HookHelpers.h"

// MARK: - Hide Blue verified checkmark

static BOOL IsHiddenBlueCheckmark(NSString* imageName) {
    return [imageName isEqualToString:@"verified"] &&
           [BHTSettings boolForKey:@"hide_blue_verified"];
}

%hook UIImage

+ (id)_tfn_vectorImageDocumentNamed:(NSString*)name {
    return IsHiddenBlueCheckmark(name) ? nil : %orig;
}

%end

// MARK: - No search history

// Every recent-search write funnels through _tse_setRecentSearch: and every
// read through recentSearches; the separate saved-searches feature stays
// untouched.

%hook TTSRecentSearchesDatastore

- (void)_tse_setRecentSearch:(__unsafe_unretained id)item {
    if (![BHTSettings boolForKey:@"no_history"]) {
        %orig;
    }
}

- (NSArray*)recentSearches {
    return [BHTSettings boolForKey:@"no_history"] ? @[] : %orig;
}

%end

// MARK: - Hide trending content on the Explore tab

// Trending content lives in the child URT chrome view controller, whose
// property has no ObjC getter in 12.3, so find it among the children. The page
// tab strip arrives separately through tfn_navigationBarAccessoryView.

%hook _TtC14T1TwitterSwift28GuideContainerViewController

- (void)viewDidLoad {
    %orig;

    if ([BHTSettings boolForKey:@"hide_trends"]) {
        for (UIViewController* child in
             [(UIViewController*)self childViewControllers]) {
            if ([child isKindOfClass:
                           %c(_TtC14T1TwitterSwift23URTChromeViewController)]) {
                child.view.hidden = YES;
            }
        }
    }
}

- (UIView*)tfn_navigationBarAccessoryView {
    return [BHTSettings boolForKey:@"hide_trends"] ? nil : %orig;
}

%end

// MARK: - No Subscribe button

// Every Subscribe surface — the profile button provider (and its answers that
// demote or hide the Follow button) and the tweet author row — shows only when
// the relationship's eligible state is 1, so reporting "not eligible" (2) is
// enough to keep the plain Follow button everywhere. Relationships that are
// actively super-following stay genuine, so a real subscription keeps its
// Subscribed button and subscriber timeline.

%hook TFSTwitterRelationship

- (NSInteger)superFollowEligibleState {
    if ([BHTSettings boolForKey:@"restore_follow_button"] &&
        self.superFollowingState != 1) {
        return 2;
    }
    return %orig;
}

%end

// MARK: - Hide Follow button on Tweets

// The conversation focal tweet and the immersive player both render their
// author row through TTAStatusAuthorView, so forcing the flag here covers every
// surface.

%hook TTAStatusAuthorView

- (void)setFollowControlHidden:(BOOL)hidden {
    %orig([BHTSettings boolForKey:@"hide_follow_button"] ? YES : hidden);
}

%end

// MARK: - Hide inline action buttons

%hook TTAStatusInlineActionsView

+ (NSArray*)_t1_inlineActionViewClassesForViewModel:(id)arg1
                                            options:(NSUInteger)arg2
                                        displayType:(NSUInteger)arg3
                                            account:(id)arg4 {
    NSArray* origClasses = %orig;
    if (![origClasses isKindOfClass:NSArray.class]) {
        return origClasses;
    }

    NSMutableArray* newClasses = [origClasses mutableCopy];

    Class analyticsButtonClass = %c(TTAStatusInlineAnalyticsButton);
    if (analyticsButtonClass && [BHTSettings boolForKey:@"hide_view_count"]) {
        [newClasses removeObject:analyticsButtonClass];
    }

    Class bookmarkButtonClass = %c(TTAStatusInlineBookmarkButton);
    if (bookmarkButtonClass && [BHTSettings boolForKey:@"hide_bookmark_button"]) {
        [newClasses removeObject:bookmarkButtonClass];
    }

    Class downvoteButtonClass = %c(TTAStatusInlineDownvoteButton);
    if (downvoteButtonClass && [BHTSettings boolForKey:@"hide_downvote_button"]) {
        [newClasses removeObject:downvoteButtonClass];
    }

    return [newClasses copy];
}

%end
