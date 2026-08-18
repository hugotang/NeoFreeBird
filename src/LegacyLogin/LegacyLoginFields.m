//
//  LegacyLoginFields.m
//  NeoFreeBird
//

#import "LegacyLoginFields.h"

#import <objc/runtime.h>

#import "Core/BHTBundle.h"
#import "RuntimeSubclass.h"

SUBCLASS(LegacyLoginForm, TFNLegacyForm)

// Points back at the fields object that owns the form, so it must not be retained.
static const void* const kFields = &kFields;

static NSString* AppString(NSString* key) {
    return [[BHTBundle sharedBundle] localizedTwitterStringForKey:key];
}

@interface LegacyLoginFields ()
@property (nonatomic, readwrite) TFNLegacyForm* form;
@property (nonatomic, readwrite) TFNLegacyFormField* identifierField;
@property (nonatomic, readwrite) TFNLegacyFormField* passwordField;
@property (nonatomic) T1AuthenticationFormTogglePasswordTextView* togglePasswordView;
@property (nonatomic) NSArray* headerItems;
@end

@implementation LegacyLoginFields

+ (instancetype)fields {
    Class fieldClass = objc_getClass("TFNLegacyFormField");
    if (LegacyLoginForm == Nil || fieldClass == Nil) {
        return nil;
    }

    LegacyLoginFields* fields = [self new];
    fields.form = [LegacyLoginForm new];
    objc_setAssociatedObject(fields.form, kFields, fields, OBJC_ASSOCIATION_ASSIGN);

    fields.identifierField =
        [fieldClass formFieldWithTitle:nil
                              hintText:AppString(@"PHONE_OR_EMAIL_OR_USERNAME_LABEL")
                             userInput:nil];
    [fields.identifierField setCanClearUserInput:YES];
    [fields.identifierField setIndicatesValidity:NO];
    [fields.identifierField setTextContentType:UITextContentTypeUsername];

    fields.passwordField = [fieldClass formFieldWithTitle:nil
                                                 hintText:AppString(@"PASSWORD_LABEL")
                                                userInput:nil];
    [fields.passwordField setIndicatesValidity:NO];
    [fields.passwordField setTextContentType:UITextContentTypePassword];
    [fields.passwordField setSecurityLevel:2];
    [fields.passwordField addFormFieldDependency:fields.identifierField];

    [fields buildTogglePasswordView];

    return fields;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (NSString*)identifier {
    return self.identifierField.userInput;
}

- (void)setIdentifier:(NSString*)identifier {
    [self.identifierField updateUserInput:identifier];
}

- (NSArray*)headerItems {
    if (!_headerItems) {
        id<TFNTwitterOnboardingFeature> onboarding =
            [[objc_getClass("TFNTwitter") sharedTwitter] onboardingFeature];
        _headerItems = [onboarding legacyHeaderDataItemsForTitle:AppString(@"LOG_IN_TITLE")
                                                        subtitle:nil]
                           ?: @[];
    }

    return _headerItems;
}

- (NSArray<NSArray*>*)sections {
    NSMutableArray* items = [self.headerItems mutableCopy];
    [items addObject:self.identifierField];
    [items addObject:self.passwordField];
    if (self.togglePasswordView) {
        [items addObject:self.togglePasswordView];
    }

    return @[ items ];
}

- (BOOL)isSubmittable {
    return self.identifierField.userInput.length != 0 && self.passwordField.userInput.length != 0;
}

#pragma mark - Show and hide the password

- (void)buildTogglePasswordView {
    Class toggleClass = objc_getClass("T1AuthenticationFormTogglePasswordTextView");
    NSString* textDidChange = NFBAppConstant("TFNLegacyFormTextFieldTextDidChangeNotification");
    if (toggleClass == Nil || !textDidChange ||
        !NFBAppConstant("TFNLegacyFormTextFieldSecureTextEntryDidChangeNotification")) {
        return;
    }

    self.togglePasswordView = [[toggleClass alloc] initWithPasswordLength:0];
    [self.togglePasswordView setHorizontalAlignment:2];
    [self.togglePasswordView setDelegate:self];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(passwordTextDidChange:)
                                               name:textDidChange
                                             object:self.passwordField];
}

- (void)passwordTextDidChange:(NSNotification*)notification {
    [self.togglePasswordView showOrHideForPasswordField:self.passwordField];
}

// The app's toggle view still listens for this; nothing in 12.11 posts it.
- (void)attributedTextView:(TFNAttributedTextView*)view didTapRange:(id)range rect:(CGRect)rect {
    NSString* name = NFBAppConstant("TFNLegacyFormTextFieldSecureTextEntryDidChangeNotification");
    NSString* key = NFBAppConstant("TFNLegacyFormTextFieldSecureTextEntryNewValueKey");
    if (!name || !key) {
        return;
    }

    // togglePasswordType 0 is the "Reveal password" link, i.e. a secure field.
    BOOL secure = self.togglePasswordView.togglePasswordType != 0;
    [NSNotificationCenter.defaultCenter postNotificationName:name
                                                      object:nil
                                                    userInfo:@{key : @(secure)}];
}

@end

static LegacyLoginFields* fieldsForForm(id form) { return objc_getAssociatedObject(form, kFields); }

SUBCLASS_METHOD(LegacyLoginForm, sections, sections, "@@:", NSArray*) {
    return [fieldsForForm(self) sections];
}

SUBCLASS_METHOD(LegacyLoginForm, isSubmittable, isSubmittable, "B@:", BOOL) {
    return [fieldsForForm(self) isSubmittable];
}
