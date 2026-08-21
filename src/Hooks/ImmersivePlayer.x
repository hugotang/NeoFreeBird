//
//  ImmersivePlayer.x
//  NeoFreeBird
//

#import "HookHelpers.h"

// MARK: - Immersive Player Timestamp

// The progress label is native-visible only for landscape video; the hook
// below re-applies Twitter's own visibility rule minus that orientation gate.
// Field offsets and enum tags are resolved by name (Core/SwiftMetadata.h), so
// a reshuffled layout in an app update fails closed (the feature no-ops)
// instead of misreading state.

typedef struct {
    int32_t displayModeOffset;
    int32_t isDismissingOffset;
    int32_t isChromeFadedOffset;
    const void* optionalStateMetadata;
    const void* displayModeMetadata;
    SwiftEnumTagGetter optionalStateEnumTag;
    SwiftEnumTagGetter displayModeEnumTag;
    unsigned tagRegular;
    unsigned tagScrubbing;
    unsigned tagStatusExpanded;
    BOOL valid;
} CardStateLayout;

static const CardStateLayout* cardStateLayout(void) {
    static CardStateLayout layout;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const void* stateMetadata = SwiftTypeMetadataForMangledName(
            "14T1TwitterSwift18ImmersiveCardStateV");
        const void* optionalMetadata = SwiftTypeMetadataForMangledName(
            "14T1TwitterSwift18ImmersiveCardStateVSg");
        const void* modeMetadata = SwiftTypeMetadataForMangledName(
            "14T1TwitterSwift20ImmersiveDisplayModeO");
        if (!stateMetadata || !optionalMetadata || !modeMetadata) {
            NSLog(@"[NeoFreeBird] immersive card state types missing; video "
                  @"timestamp restore disabled");
            return;
        }

        layout.displayModeOffset =
            SwiftFieldOffsetForName(stateMetadata, "displayMode");
        layout.isDismissingOffset =
            SwiftFieldOffsetForName(stateMetadata, "isDismissing");
        layout.isChromeFadedOffset =
            SwiftFieldOffsetForName(stateMetadata, "isChromeFadedOutWhilePanning");

        int regular = SwiftEnumTagForCase(modeMetadata, "regular");
        int scrubbing = SwiftEnumTagForCase(modeMetadata, "scrubbing");
        int statusExpanded = SwiftEnumTagForCase(modeMetadata, "statusExpanded");

        layout.optionalStateMetadata = optionalMetadata;
        layout.displayModeMetadata = modeMetadata;
        layout.optionalStateEnumTag =
            SwiftEnumTagGetterForMetadata(optionalMetadata);
        layout.displayModeEnumTag = SwiftEnumTagGetterForMetadata(modeMetadata);

        if (layout.displayModeOffset < 0 || layout.isDismissingOffset < 0 ||
            layout.isChromeFadedOffset < 0 || regular < 0 || scrubbing < 0 ||
            statusExpanded < 0 || !layout.optionalStateEnumTag ||
            !layout.displayModeEnumTag) {
            NSLog(@"[NeoFreeBird] immersive card state layout lookup failed; "
                  @"video timestamp restore disabled");
            return;
        }

        layout.tagRegular = (unsigned)regular;
        layout.tagScrubbing = (unsigned)scrubbing;
        layout.tagStatusExpanded = (unsigned)statusExpanded;
        layout.valid = YES;
    });
    return layout.valid ? &layout : NULL;
}

static BOOL restoredProgressLabelAlpha(id pluginView, CGFloat* outAlpha) {
    const CardStateLayout* layout = cardStateLayout();
    if (!layout) {
        return NO;
    }

    Ivar stateIvar = class_getInstanceVariable([pluginView class], "state");
    if (!stateIvar) {
        return NO;
    }
    const uint8_t* state =
        (const uint8_t*)(__bridge void*)pluginView + ivar_getOffset(stateIvar);

    // The ivar is Optional<ImmersiveCardState>; tag 0 is .some.
    if (layout->optionalStateEnumTag(state, layout->optionalStateMetadata) != 0) {
        return NO;
    }

    unsigned mode = layout->displayModeEnumTag(
        state + layout->displayModeOffset, layout->displayModeMetadata);
    BOOL visible = (mode == layout->tagRegular ||
                    mode == layout->tagScrubbing ||
                    mode == layout->tagStatusExpanded) &&
                   !(state[layout->isDismissingOffset] & 1);

    if (!visible) {
        *outAlpha = 0.0;
    } else if (state[layout->isChromeFadedOffset] & 1) {
        *outAlpha = 0.4;
    } else {
        *outAlpha = 1.0;
    }
    return YES;
}

%hook _TtC14T1TwitterSwift32ImmersiveProgressLabelPluginView

- (void)setAlpha:(CGFloat)alpha {
    if (alpha == 0.0 && [BHTSettings boolForKey:@"restore_video_timestamp"]) {
        CGFloat restored;
        if (restoredProgressLabelAlpha(self, &restored)) {
            alpha = restored;
        }
    }

    %orig(alpha);
}

%end

// MARK: - Disable Immersive Feed Scrolling

%hook T1ImmersiveViewController

// The card pan drives vertical paging between videos; blocking it lets the
// swipe-down dismiss gesture take over. The pan is a Swift lazy stored
// property, so its ivar is name-mangled.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer*)gesture {
    if ([BHTSettings boolForKey:@"disable_immersive_scroll"]) {
        Ivar panIvar = class_getInstanceVariable(
            object_getClass(self), "$__lazy_storage_$_panRecognizer");
        if (panIvar && object_getIvar(self, panIvar) == gesture) {
            return NO;
        }
    }

    return %orig;
}

%end
