#import "BHTTabBarCompatibility.h"

#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

typedef void (*BHTTabAppearanceIMP)(id, SEL, NSInteger);

static BHTTabAppearanceIMP BHTOriginalTabAppearance;

void BHTApplyCurrentThemeToTabBarController(id controller) {
    SEL tabViewsSelector = NSSelectorFromString(@"tabViews");
    if (!controller || ![controller respondsToSelector:tabViewsSelector]) {
        return;
    }

    id tabViews = ((id(*)(id, SEL))objc_msgSend)(controller, tabViewsSelector);
    if (![tabViews isKindOfClass:[NSArray class]]) {
        return;
    }

    SEL applySelector = NSSelectorFromString(@"applyCurrentThemeToIcon");
    for (id tabView in (NSArray*)tabViews) {
        if ([tabView respondsToSelector:applySelector]) {
            ((void (*)(id, SEL))objc_msgSend)(tabView, applySelector);
        }
    }
}

static void BHTUpdateTabAppearance(id self,
                                   SEL selector,
                                   NSInteger appearance) {
    if (BHTOriginalTabAppearance) {
        BHTOriginalTabAppearance(self, selector, appearance);
    }

    BHTApplyCurrentThemeToTabBarController(self);
}

void BHTInstallTabBarCompatibility(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class controllerClass = objc_getClass("T1TabBarViewController");
        SEL selector = NSSelectorFromString(@"_t1_updateAppearance:");
        if (!controllerClass ||
            !class_getInstanceMethod(controllerClass, selector)) {
            return;
        }

        MSHookMessageEx(controllerClass, selector,
                        (IMP)&BHTUpdateTabAppearance,
                        (IMP*)&BHTOriginalTabAppearance);
    });
}
