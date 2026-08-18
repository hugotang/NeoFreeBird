//
//  LegacyLoginFlow.m
//  NeoFreeBird
//
//  Password login (no reset), matching the app's built-in xAuth sign-in:
//    1. xauth_password -> OAuth token directly, or a 2FA challenge.
//    2. On 2FA, present the app's T1LoginChallengeFactory web challenge.
//    3. Add the account.
//

#import "LegacyLoginFlow.h"

#import <dlfcn.h>
#import <objc/runtime.h>

#import "Core/BHTBundle.h"
#import "Headers/Login.h"
#import "RuntimeSubclass.h"

// The API's own codes for too many attempts.
static const NSInteger LegacyLoginRateLimitCodes[] = {243, 245, 246};

static NSString* AppString(NSString* key) {
    return [[BHTBundle sharedBundle] localizedTwitterStringForKey:key];
}

static NSString* TweakString(NSString* key) {
    return [[BHTBundle sharedBundle] localizedStringForKey:key];
}

static NSArray<TFNTwitterAccount*>* LegacyLoginAccounts(void) {
    TFNTwitter* twitter = [objc_getClass("TFNTwitter") sharedTwitter];
    return twitter.accountService.accounts;
}

static NSString* LegacyLoginGuestAccountID(void) {
    return NFBAppConstant("TFSTwitterAPIGuestAccountID");
}

static TFNTwitterAccount* LegacyLoginAccountForUsername(NSString* username) {
    NSArray* accounts = LegacyLoginAccounts();
    id (*search)(NSArray*, NSString*) = dlsym(RTLD_DEFAULT, "TFNSearchAccountsForUsername");

    return username.length && accounts.count && search ? search(accounts, username) : nil;
}

static TFNTwitterAccount* LegacyLoginAccountForUserID(long long userID) {
    NSArray* accounts = LegacyLoginAccounts();
    id (*search)(NSArray*, long long) = dlsym(RTLD_DEFAULT, "TFNSearchAccountsForUserID");

    return userID && accounts.count && search ? search(accounts, userID) : nil;
}

static NSString* LegacyLoginCountryCodeForIdentifier(NSString* identifier) {
    static NSRegularExpression* phone;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        phone = [NSRegularExpression regularExpressionWithPattern:@"^\\+?[0-9\\-\\.\\(\\)\\s]{7,1000}$"
                                                          options:0
                                                            error:nil];
    });

    if (identifier.length == 0 ||
        [phone numberOfMatchesInString:identifier
                               options:0
                                 range:NSMakeRange(0, identifier.length)] == 0) {
        return nil;
    }

    TNUCommunicationAgent* agent = [objc_getClass("TNUCommunicationAgent") sharedInstance];
    return agent.currentCarrierInfo.isoCountryCode.uppercaseString;
}

static NSString* LegacyLoginMessageForError(NSError* error) {
    NSInteger (*APIErrorCode)(NSError*) =
        dlsym(RTLD_DEFAULT, "TFSTwitterAPICommandErrorGetAPIErrorCode");
    NSInteger code = APIErrorCode ? APIErrorCode(error) : 0;

    if (code == 0) {
        return [error tfs_isNotConnectedToInternetError]
                   ? AppString(@"CONNECTION_ERROR_GENERAL_MESSAGE")
                   : AppString(@"LOGIN_GENERIC_ERROR_MESSAGE");
    }

    for (NSUInteger index = 0; index < sizeof(LegacyLoginRateLimitCodes) / sizeof(NSInteger);
         index++) {
        if (code == LegacyLoginRateLimitCodes[index]) {
            return AppString(@"RATE_LIMIT_EXEEDED_ERROR");
        }
    }

    return AppString(@"SECURITY_SETTINGS_INCORRECT_PASSWORD_MESSAGE");
}

@interface LegacyLoginFlow ()
// The flow is passed as the command's authTokenStorage, so it answers these.
@property (nonatomic, copy) NSString* authTimelineToken;
@property (nonatomic, copy) NSString* identifier;
// Presenting a challenge does not retain it.
@property (nonatomic) id<T1LoginChallenge> challenge;
@end

@implementation LegacyLoginFlow

+ (instancetype)flow {
    BOOL ready = objc_getClass("TFSTwitterAPIXAuthPasswordCommand") != Nil &&
                 objc_getClass("TFSTwitterXAuthPasswordResponseBuilder") != Nil &&
                 objc_getClass("TFSTwitterServiceRunner") != Nil &&
                 objc_getClass("TNUServiceHTTPConfiguration") != Nil &&
                 objc_getClass("TFNTwitterAccount") != Nil &&
                 objc_getClass("T1AccountController") != Nil && LegacyLoginGuestAccountID() != nil;

    return ready ? [self new] : nil;
}

- (void)signInWithIdentifier:(NSString*)identifier
                    password:(NSString*)password
                   uiMetrics:(NSString*)uiMetrics {
    if ([LegacyLoginAccountForUsername(identifier) isOwner]) {
        [self.delegate loginFlow:self didFailWithMessage:TweakString(@"LOGIN_ACCOUNT_EXISTS")];
        return;
    }

    self.identifier = identifier;

    id context = [objc_getClass("TFSTwitterServiceRunner") APICommandContext];
    id configuration =
        [objc_getClass("TNUServiceHTTPConfiguration") configurationForForegroundRetriableRequest];

    __weak typeof(self) weakSelf = self;
    id command = [[objc_getClass("TFSTwitterAPIXAuthPasswordCommand") alloc]
                      initWithContext:context
                            accountID:LegacyLoginGuestAccountID()
                          authContext:nil
                           identifier:identifier
                             password:password
                       simCountryCode:LegacyLoginCountryCodeForIdentifier(identifier)
             httpRequestConfiguration:configuration
        supportOneFactorAuthorization:NO
                     knownDeviceToken:[objc_getClass("TFNTwitterAccount") knownDeviceToken]
                            uiMetrics:uiMetrics
                     authTokenStorage:self
                               source:0
                 responseModelBuilder:[objc_getClass("TFSTwitterXAuthPasswordResponseBuilder") new]
                      completionBlock:^(BOOL success, id response, NSError* error) {
                          [weakSelf handleSuccess:success response:response error:error];
                      }];

    [objc_getClass("TFSTwitterServiceRunner") startAPICommand:command];
}

- (void)handleSuccess:(BOOL)success
             response:(TFSTwitterXAuthPasswordResponse*)response
                error:(NSError*)error {
    if (!success) {
        [self.delegate loginFlow:self didFailWithMessage:LegacyLoginMessageForError(error)];
    } else if (response.token.length && response.tokenSecret.length) {
        [self finishWithResponse:response];
    } else {
        [self challengeForResponse:response];
    }
}

- (void)finishWithResponse:(TFSTwitterXAuthPasswordResponse*)response {
    if (response.knownDeviceToken.length) {
        [objc_getClass("TFNTwitterAccount") setKnownDeviceToken:response.knownDeviceToken];
    }

    TFNTwitterAccount* existing = LegacyLoginAccountForUserID(response.userId)
                                      ?: LegacyLoginAccountForUsername(response.screenName);
    if ([existing isOwner]) {
        [self.delegate loginFlow:self didFailWithMessage:TweakString(@"LOGIN_ACCOUNT_EXISTS")];
        return;
    }

    TFNTwitterAccount* account =
        [[objc_getClass("TFNTwitterAccount") alloc] initWithUsername:response.screenName
                                                              userID:response.userId];
    [account updateUserInfoAndCredentialsWithToken:response.token
                                            secret:response.tokenSecret
                                          username:response.screenName];

    [self addAccount:account];
}

- (void)addAccount:(TFNTwitterAccount*)account {
    [[objc_getClass("T1AccountController") defaultController] addAccount:account];
    [self.delegate loginFlowDidAddAccount:self];

    // Adding the account does not move the app off the signed-out root, so the
    // host is told to view it.
    Class hostClass = objc_getClass("T1HostViewController");
    id host = [hostClass respondsToSelector:@selector(sharedHostViewController)]
                  ? ((id (*)(id, SEL))objc_msgSend)(hostClass, @selector(sharedHostViewController))
                  : nil;
    if ([host respondsToSelector:@selector(viewAccount:animated:)]) {
        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(host, @selector(viewAccount:animated:), account,
                                                    YES);
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [account saveOAuthCredentialWithCompletionBlock:nil];
    });
}

- (void)challengeForResponse:(TFSTwitterXAuthPasswordResponse*)response {
    UIViewController* presenter = [self.delegate viewControllerToPresentFromForLoginFlow:self];
    Class factory = objc_getClass("T1LoginChallengeFactory");
    if (factory == Nil || !presenter || response.loginVerificationRequestId.length == 0 ||
        response.challengeURLString.length == 0) {
        [self.delegate loginFlow:self didFailWithMessage:AppString(@"LOGIN_GENERIC_ERROR_MESSAGE")];
        return;
    }

    BOOL securityKeys = [objc_getClass("TPSDeviceFeatureSwitches") isSecurityKeyAuthEnabled];
    self.challenge = [factory loginChallengeWithMode:securityKeys ? 1 : 0
                                           loginType:response.loginVerificationRequestType
                                           requestID:response.loginVerificationRequestId
                                                user:self.identifier
                                              userID:response.loginVerificationUserId
                                           URLString:response.challengeURLString
                                          loginCause:0];

    if (!self.challenge) {
        [self.delegate loginFlow:self didFailWithMessage:AppString(@"LOGIN_GENERIC_ERROR_MESSAGE")];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self.challenge setDidAddAccountBlock:^(id controller, TFNTwitterAccount* account) {
        if (account) {
            [weakSelf addAccount:account];
        }
    }];

    [self.delegate loginFlowDidPresentChallenge:self];
    [self.challenge presentLoginChallengeFromViewController:presenter animated:YES completion:nil];
}

@end
