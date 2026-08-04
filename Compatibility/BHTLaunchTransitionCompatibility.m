#import "BHTLaunchTransitionCompatibility.h"

#import <objc/runtime.h>
#import <substrate.h>

typedef id (*BHTLaunchTransitionProviderIMP)(id, SEL);

static BHTLaunchTransitionProviderIMP BHTOriginalLaunchTransitionProvider;

static id BHTLaunchTransitionProvider(id self, SEL selector) {
    Class transitionClass = NSClassFromString(@"T1AppLaunchTransition");
    if (transitionClass) {
        return [[transitionClass alloc] init];
    }

    return BHTOriginalLaunchTransitionProvider
        ? BHTOriginalLaunchTransitionProvider(self, selector)
        : nil;
}

void BHTInstallLaunchTransitionCompatibility(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class appDelegateClass = objc_getClass("T1AppDelegate");
        Class transitionClass = NSClassFromString(@"T1AppLaunchTransition");
        SEL selector = NSSelectorFromString(@"launchTransitionProvider");
        if (!appDelegateClass || !transitionClass ||
            !class_getClassMethod(appDelegateClass, selector)) {
            return;
        }

        Class metaClass = object_getClass(appDelegateClass);
        MSHookMessageEx(metaClass, selector,
            (IMP)&BHTLaunchTransitionProvider,
            (IMP *)&BHTOriginalLaunchTransitionProvider);
    });
}
