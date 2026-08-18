//
//  Login.h
//  NeoFreeBird
//
//  App classes behind the native legacy sign-in form (src/LegacyLogin, Login.x).
//  Classes the app shares elsewhere (TFNTwitterAccount, TFNTwitter, TFNHUD,
//  TFNButton, TFNNavigationController) come from TFNHeaders.h.
//

#import <UIKit/UIKit.h>

#import "TFNHeaders.h"

#pragma mark - The legacy form stack

// securityLevel 2 is secure entry; a nil title makes the hint the placeholder.
@interface TFNLegacyFormField : NSObject

+ (instancetype)formFieldWithTitle:(NSString*)title
                          hintText:(NSString*)hintText
                         userInput:(NSString*)userInput;

@property (nonatomic, copy, readonly) NSString* userInput;

- (void)updateUserInput:(NSString*)userInput;
- (void)addFormFieldDependency:(TFNLegacyFormField*)field;
- (void)setCanClearUserInput:(BOOL)canClear;
- (void)setIndicatesValidity:(BOOL)indicates;
- (void)setSecurityLevel:(NSInteger)level;
- (void)setTextContentType:(UITextContentType)type;

@end

@interface TFNLegacyForm : NSObject
// Items are dispatched to an adapter by their class.
- (NSArray<NSArray*>*)sections;
- (BOOL)isSubmittable;
- (void)sendFormDidChangeSubmittability;
@end

@interface TFNLegacyFormAppearance : NSObject
+ (instancetype)unsectionedAppearance;
@end

@interface T1OnboardingFormAppearance : TFNLegacyFormAppearance
@end

@interface TFNLegacyFormViewController : UIViewController
- (instancetype)initWithForm:(TFNLegacyForm*)form appearance:(TFNLegacyFormAppearance*)appearance;
@property (nonatomic, readonly) TFNLegacyForm* form;
@end

// Listens for a secure-entry notification that nothing in 12.11 posts.
@interface T1AuthenticationFormTogglePasswordTextView : TFNAttributedTextView
- (instancetype)initWithPasswordLength:(NSUInteger)length;
- (void)showOrHideForPasswordField:(TFNLegacyFormField*)field;
- (void)setHorizontalAlignment:(NSInteger)alignment;
- (void)setDelegate:(id)delegate;
@property (nonatomic, readonly) NSInteger togglePasswordType;
@end

#pragma mark - Chrome

@interface TFNActivityIndicatorButton : TFNButton
- (void)setActivityIndicatorVisible:(BOOL)visible;
@end

@interface TFNFormToolbarButtons : NSObject

+ (instancetype)toolbarButtonsWithTarget:(id)target
                     continueButtonLabel:(NSString*)continueLabel
                    continueButtonAction:(SEL)continueAction
                    secondaryButtonLabel:(NSString*)secondaryLabel
                   secondaryButtonAction:(SEL)secondaryAction;

@property (nonatomic, readonly) TFNActivityIndicatorButton* continueButton;

@end

@interface TFNBarButtonItem : UIBarButtonItem
+ (instancetype)moreButtonItemWithTarget:(id)target action:(SEL)action;
@end

@interface TFNModalSheetViewController : UIViewController
- (instancetype)initWithModalContentViewController:(UIViewController*)controller;
- (void)setPreferredPresentationStyle:(NSInteger)style;
- (void)setAllowCenteredPresentationWithoutSource:(BOOL)allow;
@end

@interface UIViewController (TFNToolbar)
@property (nonatomic, strong) TFNFormToolbarButtons* tfn_formToolbarButtons;
// 0 inherit, 1 hidden, 2 docked, 3 a floating pill.
- (void)tfn_setDefaultToolbarVisibility:(NSInteger)visibility;
- (void)tfn_dismissAnimated:(BOOL)animated completion:(void (^)(void))completion;
@end

@interface UIAlertController (TFNAlerts)
+ (instancetype)tfn_okAlertControllerWithTitle:(NSString*)title message:(NSString*)message;
@end

#pragma mark - Accounts

@interface T1AccountController : NSObject
+ (instancetype)defaultController;
- (void)addAccount:(TFNTwitterAccount*)account;
@end

#pragma mark - The xAuth password command

@interface TFSTwitterXAuthPasswordResponse : NSObject
@property (nonatomic, readonly) NSString* token;
@property (nonatomic, readonly) NSString* tokenSecret;
@property (nonatomic, readonly) NSString* screenName;
@property (nonatomic, readonly) long long userId;
@property (nonatomic, readonly) NSString* knownDeviceToken;
@property (nonatomic, readonly) NSString* loginVerificationRequestId;
@property (nonatomic, readonly) long long loginVerificationUserId;
@property (nonatomic, readonly) int loginVerificationRequestType;
@property (nonatomic, readonly) NSString* challengeURLString;
@end

@interface TFSTwitterXAuthPasswordResponseBuilder : NSObject
@end

@interface TNUServiceHTTPConfiguration : NSObject
+ (instancetype)configurationForForegroundRetriableRequest;
@end

// accountID is the guest sentinel, since login runs before an account exists.
@interface TFSTwitterAPIXAuthPasswordCommand : NSObject

- (instancetype)initWithContext:(id)context
                        accountID:(NSString*)accountID
                      authContext:(id)authContext
                       identifier:(NSString*)identifier
                         password:(NSString*)password
                   simCountryCode:(NSString*)simCountryCode
         httpRequestConfiguration:(TNUServiceHTTPConfiguration*)configuration
    supportOneFactorAuthorization:(BOOL)supportOneFactorAuthorization
                 knownDeviceToken:(NSString*)knownDeviceToken
                        uiMetrics:(NSString*)uiMetrics
                 authTokenStorage:(id)authTokenStorage
                           source:(unsigned long long)source
             responseModelBuilder:(id)responseModelBuilder
                  completionBlock:(void (^)(BOOL success, id response, NSError* error))completion;

@end

@interface TFSTwitterServiceRunner : NSObject
+ (id)APICommandContext;
+ (id)startAPICommand:(id)command;
@end

@interface NSError (TFSErrors)
- (BOOL)tfs_isNotConnectedToInternetError;
@end

#pragma mark - Login verification and the JS instrumentation page

@protocol T1LoginChallenge <NSObject>
- (void)setDidAddAccountBlock:(void (^)(id controller, TFNTwitterAccount* account))block;
- (void)presentLoginChallengeFromViewController:(UIViewController*)presenter
                                       animated:(BOOL)animated
                                     completion:(void (^)(void))completion;
@end

// mode is the security-key switch, not the challenge type: 0 an in-app web
// view, 1 a web authentication session.
@interface T1LoginChallengeFactory : NSObject
+ (id<T1LoginChallenge>)loginChallengeWithMode:(NSInteger)mode
                                     loginType:(NSInteger)loginType
                                     requestID:(NSString*)requestID
                                          user:(NSString*)user
                                        userID:(long long)userID
                                     URLString:(NSString*)URLString
                                    loginCause:(NSInteger)loginCause;
@end

@interface T1AccountsViewController : UIViewController
- (void)private_startLoginFlowWithSender:(id)sender;
@end

@interface T1PasswordResetViewController : UIViewController
+ (void)presentPasswordResetFromViewController:(UIViewController*)presenter
                                  withUsername:(NSString*)username
                                     urlString:(NSString*)urlString
                                    completion:(void (^)(void))completion;
@end

@interface T1UIInstrumentationWebViewController : UIViewController
- (instancetype)initWithPage:(NSString*)page;
// nil until the page has loaded.
@property (nonatomic, readonly) NSString* result;
@end

@interface TPSDeviceFeatureSwitches : NSObject
+ (BOOL)isLoginJSInstrumentationEnabled;
+ (BOOL)isSecurityKeyAuthEnabled;
@end

@interface TNLCarrierInfo : NSObject
@property (nonatomic, readonly) NSString* isoCountryCode;
@end

@interface TNUCommunicationAgent : NSObject
+ (instancetype)sharedInstance;
@property (nonatomic, readonly) TNLCarrierInfo* currentCarrierInfo;
@end
