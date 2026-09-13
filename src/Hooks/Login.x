//
//  Login.x
//  NeoFreeBird
//
//  Replaces the app's sign-in screens with the native legacy xAuth form
//  (src/LegacyLogin), presented as a modal sheet or the signed-out root.
//

#import "HookHelpers.h"

#import "LegacyLogin/LegacyLoginScreen.h"

// Keep asynchronous onboarding callbacks on the app's own flow after the user
// chooses it. The legacy form is available again on the next app launch.
static BOOL useBuiltInLogin = NO;

BOOL NFBPresentBuiltInLogin(NSString* identifier) {
    Class hostClass = objc_getClass("T1HostViewController");
    if (![hostClass respondsToSelector:@selector(sharedHostViewController)]) {
        return NO;
    }
    id host = [hostClass sharedHostViewController];
    SEL signIn = @selector(_signInToAccountWithUsername:completion:);
    if (![host respondsToSelector:signIn]) {
        return NO;
    }

    useBuiltInLogin = YES;
    // The host owns presentation, account registration and verification. Only
    // prefill the identifier; the app collects the password in its own flow.
    ((void (*)(id, SEL, id, id))objc_msgSend)(host, signIn, identifier, ^{});
    return YES;
}

static BOOL presentSignIn(UIViewController* presenter, NSString* username) {
    UIViewController* screen = [LegacyLoginScreen signInViewControllerWithIdentifier:username];
    Class sheets = objc_getClass("TFNModalSheetViewController");
    if (!screen || sheets == Nil) {
        return NO;
    }

    TFNModalSheetViewController* sheet = [[sheets alloc] initWithModalContentViewController:screen];
    [sheet setPreferredPresentationStyle:2];
    [sheet setAllowCenteredPresentationWithoutSource:YES];
    [sheet tfn_presentFromViewController:presenter animated:YES];

    return YES;
}

%hook T1HostViewController

- (void)_signInToAccountWithUsername:(NSString*)username completion:(void (^)(void))completion {
    if (useBuiltInLogin || !presentSignIn(self, username)) {
        %orig;
        return;
    }

    if (completion) {
        completion();
    }
}

- (void)makeOnboardingViewControllerWithCompletion:(void (^)(UIViewController*))completion {
    if (useBuiltInLogin) {
        %orig;
        return;
    }
    UIViewController* screen = [LegacyLoginScreen signInViewControllerWithIdentifier:nil];
    if (!screen || !completion) {
        %orig;
        return;
    }

    completion(screen);
}

%end

%hook T1AccountsViewController

- (void)private_startLoginFlowWithSender:(id)sender {
    if (useBuiltInLogin || !presentSignIn(self, nil)) {
        %orig;
    }
}

%end
