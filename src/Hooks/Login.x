//
//  Login.x
//  NeoFreeBird
//
//  Replaces the app's sign-in screens with the native legacy xAuth form
//  (src/LegacyLogin), presented as a modal sheet or the signed-out root.
//

#import "HookHelpers.h"

#import "LegacyLogin/LegacyLoginScreen.h"

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
    if (!presentSignIn(self, username)) {
        %orig;
        return;
    }

    if (completion) {
        completion();
    }
}

- (void)makeOnboardingViewControllerWithCompletion:(void (^)(UIViewController*))completion {
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
    if (!presentSignIn(self, nil)) {
        %orig;
    }
}

%end
