#import "BHTTwitter128Compatibility.h"

#import "../BHTManager.h"

#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

typedef void (*BHTVoidMethodIMP)(id, SEL);
typedef BOOL (*BHTBoolMethodIMP)(id, SEL);

static BHTVoidMethodIMP BHTOriginalConfigureFleetsHelper;
static BHTBoolMethodIMP BHTOriginalShouldShowFleetLine;

static const char *const BHTGrokPremiumGetterSymbols[] = {
    "_$s4Grok0A13FeatureAccessC13isPremiumUserSbvg",
    "_$s4Grok0A8RootViewV0C5ModelC13isPremiumUserSbvg",
};

enum {
    BHTGrokPremiumGetterCount = sizeof(BHTGrokPremiumGetterSymbols) /
        sizeof(BHTGrokPremiumGetterSymbols[0]),
};

static void *BHTOriginalGrokPremiumGetters[BHTGrokPremiumGetterCount];

static BOOL BHTAlwaysPremiumUser(void) {
    return YES;
}

static void BHTConfigureFleetsHelper(id self, SEL selector) {
    if (![BHTManager hideSpacesBar]) {
        if (BHTOriginalConfigureFleetsHelper) {
            BHTOriginalConfigureFleetsHelper(self, selector);
        }
        return;
    }

    SEL removeSelector = NSSelectorFromString(@"_t1_removeFleetLineView");
    if ([self respondsToSelector:removeSelector]) {
        ((void (*)(id, SEL))objc_msgSend)(self, removeSelector);
    }
}

static BOOL BHTShouldShowFleetLine(id self, SEL selector) {
    if ([BHTManager hideSpacesBar]) {
        return NO;
    }

    return BHTOriginalShouldShowFleetLine
        ? BHTOriginalShouldShowFleetLine(self, selector)
        : YES;
}

static void BHTInstallGrokPremiumHooks(void) {
    for (size_t index = 0; index < BHTGrokPremiumGetterCount; index++) {
        void *getter = MSFindSymbol(NULL, BHTGrokPremiumGetterSymbols[index]);
        if (getter) {
            MSHookFunction(getter, (void *)&BHTAlwaysPremiumUser,
                &BHTOriginalGrokPremiumGetters[index]);
        }
    }
}

static void BHTInstallFleetLineHooks(void) {
    Class fleetLineController = objc_getClass("T1FleetLineHeaderController");
    if (!fleetLineController) {
        return;
    }

    SEL configureSelector = NSSelectorFromString(@"_t1_configureFleets_helper");
    if (class_getInstanceMethod(fleetLineController, configureSelector)) {
        MSHookMessageEx(fleetLineController, configureSelector,
            (IMP)&BHTConfigureFleetsHelper,
            (IMP *)&BHTOriginalConfigureFleetsHelper);
    }

    SEL visibilitySelector = NSSelectorFromString(@"_t1_shouldShowFleetLine");
    if (class_getInstanceMethod(fleetLineController, visibilitySelector)) {
        MSHookMessageEx(fleetLineController, visibilitySelector,
            (IMP)&BHTShouldShowFleetLine,
            (IMP *)&BHTOriginalShouldShowFleetLine);
    }
}

void BHTInstallTwitter128Compatibility(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        BHTInstallGrokPremiumHooks();
        BHTInstallFleetLineHooks();
    });
}
