//
//  ImmersivePlayer.x
//  NeoFreeBird
//

#import "HookHelpers.h"
#import <string.h>

// MARK: - Immersive Player Timestamp

static const uint8_t* immersiveCardStateMetadata(void) {
    static const uint8_t* metadata;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const void* (*getType)(const char*, size_t, const void*,
                               const void* const*) =
            dlsym(RTLD_DEFAULT, "swift_getTypeByMangledNameInEnvironment");
        if (getType) {
            const char* mangledName = "14T1TwitterSwift18ImmersiveCardStateV";
            metadata = getType(mangledName, strlen(mangledName), NULL, NULL);
        }
    });
    return metadata;
}

static const uint8_t* immersiveCardStateDescriptor(void) {
    const uint8_t* metadata = immersiveCardStateMetadata();
    return metadata ? *(const uint8_t* const*)(metadata + 8) : NULL;
}

// Swift field records contain relative pointers to their reflection names.
// Resolve by name because 12.14 inserted a state field before these flags,
// shifting their declaration indexes from the 12.3 layout.
static BOOL cardStateFieldIndexNamed(const char* fieldName,
                                     uint32_t* outIndex) {
    const uint8_t* descriptor = immersiveCardStateDescriptor();
    if (!descriptor || !fieldName || !outIndex) {
        return NO;
    }

    uint32_t numFields = *(const uint32_t*)(descriptor + 20);
    const int32_t* fieldDescriptorOffset =
        (const int32_t*)(descriptor + 16);
    if (numFields == 0 || numFields > 256 ||
        *fieldDescriptorOffset == 0) {
        return NO;
    }

    const uint8_t* fieldDescriptor =
        (const uint8_t*)fieldDescriptorOffset + *fieldDescriptorOffset;
    uint16_t recordSize = *(const uint16_t*)(fieldDescriptor + 10);
    uint32_t recordCount = *(const uint32_t*)(fieldDescriptor + 12);
    if (recordSize < 12 || recordSize > 64 || recordCount != numFields) {
        return NO;
    }

    for (uint32_t index = 0; index < recordCount; index++) {
        const uint8_t* record = fieldDescriptor + 16 + index * recordSize;
        const int32_t* nameOffset = (const int32_t*)(record + 8);
        if (*nameOffset == 0) {
            continue;
        }

        const char* name = (const char*)nameOffset + *nameOffset;
        if (strcmp(name, fieldName) == 0) {
            *outIndex = index;
            return YES;
        }
    }

    return NO;
}

static BOOL cardStateVisibilityFieldIndexes(uint32_t* outPanningIndex,
                                            uint32_t* outChromeFadedIndex) {
    static dispatch_once_t onceToken;
    static BOOL resolved;
    static uint32_t panningIndex;
    static uint32_t chromeFadedIndex;
    dispatch_once(&onceToken, ^{
        resolved =
            cardStateFieldIndexNamed("isPanningBetweenCards", &panningIndex) &&
            cardStateFieldIndexNamed("isChromeFadedOutWhilePanning",
                                     &chromeFadedIndex);
    });

    if (!resolved) {
        return NO;
    }

    *outPanningIndex = panningIndex;
    *outChromeFadedIndex = chromeFadedIndex;
    return YES;
}

// Reads a Bool field through the struct's field offset vector, the same way the
// app's own compiled accesses do, so byte offsets never have to be hardcoded.
static BOOL cardStateBoolField(const uint8_t* state,
                               uint32_t fieldIndex,
                               BOOL* outValue) {
    const uint8_t* metadata = immersiveCardStateMetadata();
    const uint8_t* descriptor = immersiveCardStateDescriptor();
    if (!metadata || !descriptor) {
        return NO;
    }

    uint32_t numFields = *(const uint32_t*)(descriptor + 20);
    uint32_t offsetVectorOffset = *(const uint32_t*)(descriptor + 24);
    if (fieldIndex >= numFields || offsetVectorOffset == 0) {
        return NO;
    }

    const int32_t* fieldOffsets =
        (const int32_t*)(metadata + offsetVectorOffset * sizeof(void*));
    *outValue = state[fieldOffsets[fieldIndex]] & 1;
    return YES;
}

// displayMode is a Swift enum stored as an 8-byte case index followed by a
// discriminator tag (0 = the repliesPanning payload case, 1 = an empty case).
// Empty cases: regular = 0, repliesOpen = 1, repliesCompletelyOpen = 2,
// controlsHidden = 3, scrubbing = 4, statusExpanded = 5.
static BOOL progressLabelAlphaFromState(id pluginView, CGFloat* outAlpha) {
    Ivar stateIvar = class_getInstanceVariable([pluginView class], "state");
    if (!stateIvar) {
        return NO;
    }

    uint8_t* state =
        (uint8_t*)(__bridge void*)pluginView + ivar_getOffset(stateIvar);
    uint64_t displayModeCase = *(uint64_t*)state;
    uint8_t displayModeTag = state[8];

    BOOL visible =
        displayModeTag == 1 && (displayModeCase < 1 || displayModeCase > 3);

    uint32_t panningIndex = 0;
    uint32_t chromeFadedIndex = 0;
    if (visible && cardStateVisibilityFieldIndexes(&panningIndex,
                                                   &chromeFadedIndex)) {
        BOOL panning = NO, chromeFaded = NO;
        if (cardStateBoolField(state, panningIndex, &panning) &&
            panning) {
            visible = NO;
        } else if (cardStateBoolField(state, chromeFadedIndex,
                                      &chromeFaded) &&
                   chromeFaded) {
            visible = NO;
        }
    }

    *outAlpha = visible ? 1.0 : 0.0;
    return YES;
}

%hook _TtC14T1TwitterSwift32ImmersiveProgressLabelPluginView

- (void)setAlpha:(CGFloat)alpha {
    if ([BHTSettings boolForKey:@"restore_video_timestamp"]) {
        CGFloat stateAlpha;
        if (progressLabelAlphaFromState(self, &stateAlpha)) {
            alpha = stateAlpha;
        }
    }

    %orig(alpha);
}

%end

// MARK: - Disable Immersive Feed Scrolling

// The card pan drives vertical paging between videos; blocking it lets the
// swipe-down dismiss gesture take over.
static BOOL isImmersiveCardPan(id viewController,
                               UIGestureRecognizer* gesture) {
    Ivar panIvar =
        class_getInstanceVariable([viewController class], "panRecognizer");
    return panIvar && object_getIvar(viewController, panIvar) == gesture;
}

%hook T1ImmersiveViewController

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer*)gesture {
    if ([BHTSettings boolForKey:@"disable_immersive_scroll"] &&
        isImmersiveCardPan(self, gesture)) {
        return NO;
    }

    return %orig;
}

%end

%hook T1ImmersiveViewControllerV2

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer*)gesture {
    if ([BHTSettings boolForKey:@"disable_immersive_scroll"] &&
        isImmersiveCardPan(self, gesture)) {
        return NO;
    }

    return %orig;
}

%end
