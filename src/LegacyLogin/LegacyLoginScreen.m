//
//  LegacyLoginScreen.m
//  NeoFreeBird
//

#import "LegacyLoginScreen.h"

#import <objc/runtime.h>

#import "Core/BHTBundle.h"
#import "Core/BHTManager.h"
#import "Headers/Login.h"
#import "LegacyLoginFields.h"
#import "LegacyLoginFlow.h"
#import "RuntimeSubclass.h"

// The signed-in account, if any (WebPosting.x), for the settings gear.
extern id accountForAuthenticatedWebView(void);

SUBCLASS(LegacyLoginScreenController, TFNLegacyFormViewController)

static const void* const kScreen = &kScreen;

static NSString* AppString(NSString* key) {
    return [[BHTBundle sharedBundle] localizedTwitterStringForKey:key];
}

static NSString* TweakString(NSString* key) {
    return [[BHTBundle sharedBundle] localizedStringForKey:key];
}

@interface LegacyLoginScreen () <LegacyLoginFlowDelegate>
@property (nonatomic, weak) TFNLegacyFormViewController* controller;
@property (nonatomic) LegacyLoginFields* fields;
@property (nonatomic) LegacyLoginFlow* flow;
@property (nonatomic) T1UIInstrumentationWebViewController* instrumentation;
@property (nonatomic) TFNHUD* hud;
@end

@implementation LegacyLoginScreen

+ (UIViewController*)signInViewControllerWithIdentifier:(NSString*)identifier {
    LegacyLoginFields* fields = [LegacyLoginFields fields];
    LegacyLoginFlow* flow = [LegacyLoginFlow flow];
    Class appearances = objc_getClass("T1OnboardingFormAppearance");
    Class navigation = objc_getClass("TFNNavigationController");
    if (LegacyLoginScreenController == Nil || !fields || !flow || appearances == Nil ||
        navigation == Nil) {
        return nil;
    }

    LegacyLoginScreen* screen = [self new];
    screen.fields = fields;
    screen.flow = flow;
    flow.delegate = screen;
    fields.identifier = identifier;

    if ([objc_getClass("TPSDeviceFeatureSwitches") isLoginJSInstrumentationEnabled]) {
        screen.instrumentation = [[objc_getClass("T1UIInstrumentationWebViewController") alloc]
            initWithPage:NFBAppConstant("TFSTwitterScribePageLogin")];
    }

    TFNLegacyFormViewController* controller =
        [[LegacyLoginScreenController alloc] initWithForm:fields.form
                                              appearance:[appearances unsectionedAppearance]];
    screen.controller = controller;
    objc_setAssociatedObject(controller, kScreen, screen, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [controller tfn_setDefaultToolbarVisibility:2];

    return [[navigation alloc] initWithRootViewController:controller];
}

#pragma mark - Chrome

- (void)buildChrome {
    TFNLegacyFormViewController* controller = self.controller;
    Class barItems = objc_getClass("TFNBarButtonItem");

    controller.view.backgroundColor = [UIColor systemBackgroundColor];
    controller.navigationItem.leftBarButtonItem =
        [[barItems alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                               target:controller
                                               action:@selector(nfb_cancel)];

    UIBarButtonItem* settings =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"]
                                         style:UIBarButtonItemStylePlain
                                        target:controller
                                        action:@selector(nfb_openSettings)];
    settings.accessibilityLabel = TweakString(@"NFB_SETTINGS_TITLE");
    controller.navigationItem.rightBarButtonItem = settings;

    TFNFormToolbarButtons* toolbar = [objc_getClass("TFNFormToolbarButtons")
        toolbarButtonsWithTarget:controller
             continueButtonLabel:AppString(@"LOG_IN_ACTION_LABEL")
            continueButtonAction:@selector(submitForm)
            secondaryButtonLabel:AppString(@"FORGOT_PASSWORD_LABEL")
           secondaryButtonAction:@selector(nfb_forgotPassword)];
    controller.tfn_formToolbarButtons = toolbar;
    toolbar.continueButton.enabled = NO;

    if (self.instrumentation) {
        [controller addChildViewController:self.instrumentation];
        self.instrumentation.view.frame = controller.view.frame;
        [controller.view addSubview:self.instrumentation.view];
        [self.instrumentation didMoveToParentViewController:controller];
    }

    LegacyLoginFields* fields = self.fields;
    dispatch_async(dispatch_get_main_queue(), ^{
        toolbar.continueButton.enabled = [fields isSubmittable];
    });
}

- (void)setSubmittable:(BOOL)submittable {
    self.controller.tfn_formToolbarButtons.continueButton.enabled = submittable;
}

#pragma mark - Actions

- (void)submit {
    TFNLegacyFormViewController* controller = self.controller;
    [controller.view endEditing:YES];

    self.hud = [[objc_getClass("TFNHUD") alloc] initWithText:TweakString(@"LOGIN_SIGNING_IN")];
    [self.hud showAndBlockUserInteraction];

    [self.flow signInWithIdentifier:self.fields.identifier
                           password:self.fields.passwordField.userInput
                          uiMetrics:self.instrumentation.result];
}

- (void)cancel {
    [self.controller tfn_dismissAnimated:YES completion:nil];
}

- (void)openSettings {
    UIViewController* settings =
        [BHTManager BHTSettingsWithAccount:accountForAuthenticatedWebView()];
    if (!settings) {
        return;
    }

    UINavigationController* navigation =
        [[UINavigationController alloc] initWithRootViewController:settings];
    [self.controller presentViewController:navigation animated:YES completion:nil];
}

- (void)showPasswordReset {
    Class reset = objc_getClass("T1PasswordResetViewController");
    [reset presentPasswordResetFromViewController:self.controller
                                     withUsername:self.fields.identifier
                                        urlString:nil
                                       completion:nil];
}

#pragma mark - LegacyLoginFlowDelegate

- (UIViewController*)viewControllerToPresentFromForLoginFlow:(LegacyLoginFlow*)flow {
    return self.controller.navigationController ?: self.controller;
}

- (void)loginFlowDidAddAccount:(LegacyLoginFlow*)flow {
    [self.hud setSuccessTextAndHideAfterDelay:TweakString(@"LOGIN_SIGNED_IN")];
    self.hud = nil;

    [self.controller tfn_dismissAnimated:YES completion:nil];
}

- (void)loginFlowDidPresentChallenge:(LegacyLoginFlow*)flow {
    [self.hud hide];
    self.hud = nil;
}

- (void)loginFlow:(LegacyLoginFlow*)flow didFailWithMessage:(NSString*)message {
    [self.hud hide];
    self.hud = nil;

    UIAlertController* alert =
        [UIAlertController tfn_okAlertControllerWithTitle:AppString(@"ERROR_ALERT_TITLE")
                                                  message:message];
    [alert tfn_presentFromViewController:self.controller animated:YES];
}

@end

#pragma mark - The runtime subclass

static LegacyLoginScreen* screenFor(id controller) {
    return objc_getAssociatedObject(controller, kScreen);
}

SUBCLASS_METHOD(LegacyLoginScreenController, viewDidLoad, viewDidLoad, "v@:", void) {
    [screenFor(self) buildChrome];
    SUPER(void)(SUPER_TARGET(LegacyLoginScreenController), _cmd);
}

SUBCLASS_METHOD(LegacyLoginScreenController, addsDoneItem,
                addsDoneBarButtonButtonItemToNavigationBar, "B@:", BOOL) {
    return NO;
}

SUBCLASS_METHOD(LegacyLoginScreenController, inputRequiredBehavior, inputRequiredBehavior, "Q@:",
                NSUInteger) {
    return 1;
}

SUBCLASS_METHOD(LegacyLoginScreenController, didChangeSubmittability,
                form:didChangeSubmittability:, "v@:@B", void, id form, BOOL submittable) {
    [screenFor(self) setSubmittable:submittable];
}

SUBCLASS_METHOD(LegacyLoginScreenController, formFieldShouldReturn,
                formFieldShouldReturn:withSelectNextFieldAction:stopEditingAction:, "B@:@@?@?",
                BOOL, id field, BOOL (^selectNext)(void), void (^stopEditing)(void)) {
    BOOL advanced = SUPER(BOOL, id, id, id)(SUPER_TARGET(LegacyLoginScreenController), _cmd, field,
                                            selectNext, stopEditing);

    LegacyLoginScreen* screen = screenFor(self);
    if (!advanced && field == screen.fields.passwordField) {
        [screen submit];
    }

    return advanced;
}

SUBCLASS_METHOD(LegacyLoginScreenController, submitForm, submitForm, "v@:", void) {
    [screenFor(self) submit];
}

SUBCLASS_METHOD(LegacyLoginScreenController, cancel, nfb_cancel, "v@:", void) {
    [screenFor(self) cancel];
}

SUBCLASS_METHOD(LegacyLoginScreenController, forgotPassword, nfb_forgotPassword, "v@:", void) {
    [screenFor(self) showPasswordReset];
}

SUBCLASS_METHOD(LegacyLoginScreenController, openSettings, nfb_openSettings, "v@:", void) {
    [screenFor(self) openSettings];
}
