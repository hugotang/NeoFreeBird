//
//  Ads.x
//  NeoFreeBird
//

#import "HookHelpers.h"

static BOOL HidePromotedContent(void) {
    return [BHTSettings boolForKey:@"hide_promoted"];
}

// Timeline items are removed from the section data before it reaches the data
// view controller, so no empty cells or gaps are left behind. This covers every
// timeline surface (home, profile, search, conversations) regardless of whether
// it renders through a table view or the newer diffable collection view path.

// The promoted state of a status item is only reachable through its Swift-side
// `status` stored property, which is still registered as an ObjC ivar.
static BOOL StatusItemIsPromoted(id item) {
    Ivar statusIvar = class_getInstanceVariable([item class], "status");
    if (!statusIvar) {
        return NO;
    }

    TFNTwitterStatus* status = object_getIvar(item, statusIvar);
    return [status respondsToSelector:@selector(isPromoted)] && status.isPromoted;
}

// Promoted trends and event summary heroes (the image ads at the top of
// explore) carry their promotion in the Swift-side `promotedContent` stored
// property, which isn't always reflected in the scribe item.
static BOOL ItemHasPromotedContent(id item) {
    Ivar promotedIvar =
        class_getInstanceVariable([item class], "promotedContent");
    return promotedIvar && object_getIvar(item, promotedIvar) != nil;
}

static BOOL ScribeItemIsPromoted(id item) {
    if (![item respondsToSelector:@selector(scribeItem)]) {
        return NO;
    }

    NSDictionary* scribeItem = [item performSelector:@selector(scribeItem)];
    return [scribeItem isKindOfClass:[NSDictionary class]] &&
           scribeItem[@"promoted_id"] != nil;
}

static BOOL ShouldHideItem(id item, NSString* location) {
    item = unwrapDataViewItem(item);
    NSString* className = NSStringFromClass([item classForCoder]);

    if ([BHTSettings boolForKey:@"hide_promoted"]) {
        if ([item
                isKindOfClass:objc_getClass("T1URTTimelineStatusItemViewModel")] &&
            StatusItemIsPromoted(item)) {
            return YES;
        }

        if ([className
                isEqualToString:@"TwitterURT.URTTimelineGoogleNativeAdViewModel"]) {
            return YES;
        }

        if (([className isEqualToString:@"TwitterURT.URTTimelineTrendViewModel"] ||
             [className
                 isEqualToString:@"TwitterURT.URTTimelineEventSummaryViewModel"]) &&
            (ScribeItemIsPromoted(item) || ItemHasPromotedContent(item))) {
            return YES;
        }
    }

    if ([BHTSettings boolForKey:@"hide_premium_offer"]) {
        if ([item isKindOfClass:objc_getClass(
                                   "T1URTTimelineMessageItemViewModel")]) {
            return YES;
        }
    }

    if ([BHTSettings boolForKey:@"hide_trend_videos"] &&
        [location isEqualToString:@"OTHER"]) {
        if ([className
                isEqualToString:@"T1TwitterSwift.URTTimelineCarouselViewModel"]) {
            return YES;
        }
    }

    return NO;
}

static NSArray* FilteredSections(TFNItemsDataViewController* dataViewController,
                                 NSArray* sections) {
    if (!([BHTSettings boolForKey:@"hide_promoted"] ||
          [BHTSettings boolForKey:@"hide_premium_offer"] ||
          [BHTSettings boolForKey:@"hide_trend_videos"])) {
        return sections;
    }

    NSString* location =
        [dataViewController respondsToSelector:@selector(adDisplayLocation)]
            ? dataViewController.adDisplayLocation
            : nil;

    BOOL modified = NO;
    NSMutableArray* filteredSections =
        [NSMutableArray arrayWithCapacity:sections.count];

    for (id section in sections) {
        if (![section isKindOfClass:[NSArray class]]) {
            [filteredSections addObject:section];
            continue;
        }

        NSArray* items = section;
        NSUInteger count = items.count;
        NSMutableIndexSet* removed = [NSMutableIndexSet indexSet];

        for (NSUInteger i = 0; i < count; i++) {
            if (ShouldHideItem(items[i], location)) {
                [removed addIndex:i];
            }
        }

        if (removed.count == 0) {
            [filteredSections addObject:section];
            continue;
        }

        MarkEmptiedModuleChrome(items, removed);

        NSMutableArray* keptItems = [items mutableCopy];
        [keptItems removeObjectsAtIndexes:removed];
        modified = YES;

        if (keptItems.count > 0) {
            [filteredSections addObject:keptItems];
        }
    }

    return modified ? filteredSections : sections;
}

%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections
    restoreScrollPosition:(BOOL)restoreScrollPosition {
    %orig(FilteredSections(self, sections), restoreScrollPosition);
}

- (void)updateSections:(NSArray*)sections
    reconfigureItemIdentifiers:(NSArray*)identifiers
              withRowAnimation:(long long)animation
                    completion:(id)completion {
    %orig(FilteredSections(self, sections), identifiers, animation,
              completion);
}

%end

%hook TFNTwitterStatus

- (_Bool)isCardHidden {
    return (HidePromotedContent() && [self isPromoted])
               ? true
               : %orig;
}

// Preroll metadata is attached to an otherwise ordinary status, so it never
// reaches the promoted-status section filter. Hide it at the model boundary
// before the inline player can turn it into a dynamic video ad.
- (BOOL)allowDynamicAd {
    return HidePromotedContent() ? NO : %orig;
}

- (BOOL)isPrerollContent {
    return HidePromotedContent() ? NO : %orig;
}

- (id)prerollContent {
    return HidePromotedContent() ? nil : %orig;
}

%end

// Dynamic ads are prefetched before the inline player is built. The account
// gate above normally stops this path, but keep the prefetcher closed too so
// already-created observers cannot hydrate a later ad playlist item.
%hook T1StatusDynamicAdsPrefetcher

- (void)fetchMediasForStatuses:(id)statuses {
    if (HidePromotedContent()) {
        return;
    }

    %orig(statuses);
}

%end

// These view models forward their ad decision to a status/core model. Keep the
// forwarding layers closed too, covering translated and composed status paths.
%hook T1CompositionStatusViewModel

- (BOOL)allowDynamicAd {
    return HidePromotedContent() ? NO : %orig;
}

- (BOOL)isPrerollContent {
    return HidePromotedContent() ? NO : %orig;
}

%end

%hook T1TranslatedStatusViewModel

- (BOOL)allowDynamicAd {
    return HidePromotedContent() ? NO : %orig;
}

- (BOOL)isPrerollContent {
    return HidePromotedContent() ? NO : %orig;
}

%end

// Jetfuel stores the decision and the server-provided preroll object on the
// player session source. Clearing both prevents already-hydrated metadata from
// being reintroduced after the request-level feature switch is disabled.
%hook _TtC14T1TwitterSwift34JetfuelTAVVideoPlayerSessionSource

- (BOOL)allowDynamicAd {
    return HidePromotedContent() ? NO : %orig;
}

- (void)setAllowDynamicAd:(BOOL)allowDynamicAd {
    %orig(HidePromotedContent() ? NO : allowDynamicAd);
}

- (id)prerollContent {
    return HidePromotedContent() ? nil : %orig;
}

- (void)setPrerollContent:(id)prerollContent {
    %orig(HidePromotedContent() ? nil : prerollContent);
}

%end

// The two public TVP initializers are used by the inline video builders. Force
// their ad flag off as a final creation-time guard for callers that bypass the
// status view models.
%hook TVPSessionConfiguration

- (id)initWithAccountID:(id)accountID
            autoplaying:(BOOL)autoplaying
         allowDynamicAd:(BOOL)allowDynamicAd
  forceHighestQualityAudio:(BOOL)forceHighestQualityAudio {
    return %orig(accountID, autoplaying,
                 HidePromotedContent() ? NO : allowDynamicAd,
                 forceHighestQualityAudio);
}

- (id)initWithAccountID:(id)accountID
            autoplaying:(BOOL)autoplaying
         allowDynamicAd:(BOOL)allowDynamicAd
     adDisplayLocation:(NSInteger)adDisplayLocation
  forceHighestQualityAudio:(BOOL)forceHighestQualityAudio
       outputViewFactory:(id)outputViewFactory {
    return %orig(accountID, autoplaying,
                 HidePromotedContent() ? NO : allowDynamicAd,
                 adDisplayLocation, forceHighestQualityAudio,
                 outputViewFactory);
}

%end

// Amplify owns a separate ad control bar for some video playlist items. It can
// be instantiated from hydrated metadata without going through T1InlineMediaView.
%hook T1AmplifyAdControlBar

- (id)initWithTAVPlayerView:(id)playerView
                  tavPlayer:(id)player
                     account:(id)account
                   mediaInfo:(id)mediaInfo {
    id result = %orig(playerView, player, account, mediaInfo);
    if (HidePromotedContent() && result) {
        [result setValue:nil forKey:@"adViewModel"];
        [result setValue:@NO forKey:@"shouldRenderAdByAdvertiser"];

        UIView* pip = [result valueForKey:@"adPIP"];
        [pip removeFromSuperview];
        [result setValue:nil forKey:@"adPIP"];
        [(UIView*)[result valueForKey:@"durationPillView"] setHidden:YES];
        [(UIView*)[result valueForKey:@"skipAdButton"] setHidden:YES];
        [(UIView*)[result valueForKey:@"skipCountdownLabel"] setHidden:YES];
    }
    return result;
}

- (id)adViewModel {
    return HidePromotedContent() ? nil : %orig;
}

- (void)setAdViewModel:(id)adViewModel {
    %orig(HidePromotedContent() ? nil : adViewModel);
}

- (BOOL)shouldRenderAdByAdvertiser {
    return HidePromotedContent() ? NO : %orig;
}

- (void)setShouldRenderAdByAdvertiser:(BOOL)shouldRender {
    %orig(HidePromotedContent() ? NO : shouldRender);
}

- (void)updateWithCurrentPlaybackState:(id)state {
    if (HidePromotedContent()) {
        return;
    }

    %orig(state);
}

%end

// If an ad object was hydrated before the setting changed, keep the inline
// player from recreating its CTA, advertiser pill, or skip countdown.
%hook T1InlineMediaView

- (id)adViewModel {
    return HidePromotedContent() ? nil : %orig;
}

- (void)setCtaModel:(id)ctaModel {
    %orig(HidePromotedContent() ? nil : ctaModel);
}

- (BOOL)_t1_prerollAdHasCTAForState:(id)state {
    return HidePromotedContent() ? NO : %orig(state);
}

- (void)_t1_handleAdPrerollTransitionForState:(id)state {
    if (HidePromotedContent()) {
        return;
    }

    %orig(state);
}

- (BOOL)_t1_shouldRenderAdByAdvertiserNameWithPlaylistItem:(id)item {
    return HidePromotedContent() ? NO : %orig(item);
}

%end
