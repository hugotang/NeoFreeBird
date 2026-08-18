//
//  BHTWebSession.m
//  NeoFreeBird
//

#import "BHTWebSession.h"

#import <objc/runtime.h>

#import "Headers/TFNHeaders.h"

static NSString* const BHTWebQueueName = @"com.nfb.web";

static NSString* const BHTWebAuthEndpoint = @"https://twitter.com/account/authenticate_web_view";
static NSString* const BHTWebRedirect = @"https://x.com/";

static const NSTimeInterval BHTWebLifetime = 6 * 60 * 60;
static const NSTimeInterval BHTWebTimeout = 15;
static const NSTimeInterval BHTWebGiveUp = 25;

@interface BHTWebCredentials ()
@property (nonatomic, copy) NSString* cookieHeader;
@property (nonatomic, copy) NSString* csrfToken;
@property (nonatomic) NSDate* minted;
@end

@implementation BHTWebCredentials
@end

#pragma mark - Minting

static BOOL isTwitterHost(NSString* host) {
    return [host isEqualToString:@"x.com"] || [host isEqualToString:@"twitter.com"] ||
           [host hasSuffix:@".x.com"] || [host hasSuffix:@".twitter.com"];
}

@interface BHTWebCookieCollector : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, copy) void (^finish)(NSDictionary<NSString*, NSString*>* cookies);
@end

@implementation BHTWebCookieCollector {
    NSMutableDictionary<NSString*, NSString*>* _cookies;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cookies = [NSMutableDictionary new];
    }

    return self;
}

- (void)takeCookiesFrom:(NSURLResponse*)response {
    if (![response isKindOfClass:NSHTTPURLResponse.class]) {
        return;
    }

    NSHTTPURLResponse* http = (NSHTTPURLResponse*)response;
    if (!isTwitterHost(http.URL.host)) {
        return;
    }

    NSArray<NSHTTPCookie*>* cookies =
        [NSHTTPCookie cookiesWithResponseHeaderFields:http.allHeaderFields forURL:http.URL];
    for (NSHTTPCookie* cookie in cookies) {
        if (cookie.value.length) {
            _cookies[cookie.name] = cookie.value;
        }
    }
}

- (NSString*)cookieHeader {
    NSMutableArray<NSString*>* pairs = [NSMutableArray array];
    for (NSString* name in _cookies) {
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", name, _cookies[name]]];
    }

    return [pairs componentsJoinedByString:@"; "];
}

- (void)deliver {
    void (^finish)(NSDictionary<NSString*, NSString*>*) = self.finish;
    self.finish = nil;
    if (finish) {
        finish(_cookies);
    }
}

// The cookies so far have to be carried forward; the signature was for the bridge alone.
- (void)URLSession:(NSURLSession*)session
                          task:(NSURLSessionTask*)task
    willPerformHTTPRedirection:(NSHTTPURLResponse*)response
                    newRequest:(NSURLRequest*)request
             completionHandler:(void (^)(NSURLRequest*))completion {
    [self takeCookiesFrom:response];

    if (!isTwitterHost(request.URL.host)) {
        completion(nil);
        return;
    }

    NSMutableURLRequest* next = [request mutableCopy];
    [next setValue:nil forHTTPHeaderField:@"Authorization"];
    [next setValue:self.cookieHeader forHTTPHeaderField:@"Cookie"];
    completion(next);
}

- (void)URLSession:(NSURLSession*)session
              dataTask:(NSURLSessionDataTask*)task
    didReceiveResponse:(NSURLResponse*)response
     completionHandler:(void (^)(NSURLSessionResponseDisposition))completion {
    [self takeCookiesFrom:response];
    completion(NSURLSessionResponseCancel);
}

- (void)URLSession:(NSURLSession*)session
                    task:(NSURLSessionTask*)task
    didCompleteWithError:(NSError*)error {
    [self deliver];
}

@end

static BHTWebCredentials* credentialsFromCookies(NSDictionary<NSString*, NSString*>* cookies) {
    NSString* csrf = cookies[@"ct0"];
    if (((NSString*)cookies[@"auth_token"]).length == 0 || csrf.length == 0) {
        return nil;
    }

    NSMutableArray<NSString*>* pairs = [NSMutableArray array];
    for (NSString* name in @[ @"auth_token", @"ct0", @"twid" ]) {
        NSString* value = cookies[name];
        if (value.length) {
            [pairs addObject:[NSString stringWithFormat:@"%@=%@", name, value]];
        }
    }

    BHTWebCredentials* credentials = [BHTWebCredentials new];
    credentials.cookieHeader = [pairs componentsJoinedByString:@"; "];
    credentials.csrfToken = csrf;
    credentials.minted = NSDate.date;

    return credentials;
}

// The exchange the app's own authenticated web views make. The signer takes a GET's query
// from parameters; one already written on the URL does not survive it.
static void mintCredentials(TFNTwitterAccount* account, void (^done)(BHTWebCredentials*)) {
    NSURL* endpoint = [NSURL URLWithString:BHTWebAuthEndpoint];
    NSURLRequest* source = endpoint ? [NSURLRequest requestWithURL:endpoint] : nil;
    NSMutableURLRequest* request =
        source ? [account authenticatedMutableURLRequestForURLRequest:source
                                                           parameters:@{@"redirect_url" : BHTWebRedirect}
                                                                error:NULL]
               : nil;
    if (!request) {
        done(nil);
        return;
    }

    request.HTTPShouldHandleCookies = NO;
    request.timeoutInterval = BHTWebTimeout;

    NSURLSessionConfiguration* configuration =
        NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.HTTPCookieStorage = nil;
    configuration.HTTPShouldSetCookies = NO;

    BHTWebCookieCollector* collector = [BHTWebCookieCollector new];
    __block NSURLSession* session = [NSURLSession sessionWithConfiguration:configuration
                                                                  delegate:collector
                                                             delegateQueue:nil];
    collector.finish = ^(NSDictionary<NSString*, NSString*>* cookies) {
        [session finishTasksAndInvalidate];
        session = nil;
        done(credentialsFromCookies(cookies));
    };

    [[session dataTaskWithRequest:request] resume];
}

#pragma mark - The store

static NSArray<TFNTwitterAccount*>* signedInAccounts(void) {
    TFNTwitter* twitter = [objc_getClass("TFNTwitter") sharedTwitter];
    return [twitter respondsToSelector:@selector(accountService)] ? twitter.accountService.accounts
                                                                  : nil;
}

@implementation BHTWebSession

+ (dispatch_queue_t)queue {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create(BHTWebQueueName.UTF8String, DISPATCH_QUEUE_SERIAL);
    });

    return queue;
}

// Both are read and written on the queue alone.
+ (NSMutableDictionary<NSString*, BHTWebCredentials*>*)established {
    static NSMutableDictionary* established;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        established = [NSMutableDictionary new];
    });

    return established;
}

+ (NSMutableDictionary<NSString*, NSMutableArray*>*)waiting {
    static NSMutableDictionary* waiting;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        waiting = [NSMutableDictionary new];
    });

    return waiting;
}

+ (TFNTwitterAccount*)accountWithID:(NSString*)accountID {
    for (TFNTwitterAccount* account in signedInAccounts()) {
        if ([account respondsToSelector:@selector(accountID)] &&
            [account.accountID isEqualToString:accountID]) {
            return account;
        }
    }

    return nil;
}

+ (void)settle:(BHTWebCredentials*)credentials forAccountID:(NSString*)accountID {
    dispatch_async(self.queue, ^{
        if (credentials) {
            self.established[accountID] = credentials;
        }

        NSArray* waiting = self.waiting[accountID];
        [self.waiting removeObjectForKey:accountID];
        for (void (^completion)(BHTWebCredentials*) in waiting) {
            completion(credentials);
        }
    });
}

+ (void)establishForAccountID:(NSString*)accountID {
    SEL signing = @selector(authenticatedMutableURLRequestForURLRequest:parameters:error:);
    TFNTwitterAccount* account = [self accountWithID:accountID];
    if (![account respondsToSelector:signing]) {
        [self settle:nil forAccountID:accountID];
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(BHTWebGiveUp * NSEC_PER_SEC)),
                   self.queue, ^{
                       if (self.waiting[accountID]) {
                           [self settle:nil forAccountID:accountID];
                       }
                   });

    mintCredentials(account, ^(BHTWebCredentials* minted) {
        [self settle:minted forAccountID:accountID];
    });
}

+ (void)credentialsForAccountID:(NSString*)accountID
                     completion:(void (^)(BHTWebCredentials*))completion {
    if (accountID.length == 0) {
        completion(nil);
        return;
    }

    dispatch_async(self.queue, ^{
        BHTWebCredentials* held = self.established[accountID];
        if (held && held.minted.timeIntervalSinceNow > -BHTWebLifetime) {
            completion(held);
            return;
        }

        [self.established removeObjectForKey:accountID];

        NSMutableArray* waiting = self.waiting[accountID];
        if (waiting) {
            [waiting addObject:[completion copy]];
            return;
        }

        self.waiting[accountID] = [NSMutableArray arrayWithObject:[completion copy]];
        [self establishForAccountID:accountID];
    });
}

+ (BHTWebCredentials*)cachedCredentialsForAccountID:(NSString*)accountID {
    if (accountID.length == 0) {
        return nil;
    }

    __block BHTWebCredentials* held = nil;
    dispatch_sync(self.queue, ^{
        BHTWebCredentials* credentials = self.established[accountID];
        if (credentials && credentials.minted.timeIntervalSinceNow > -BHTWebLifetime) {
            held = credentials;
        }
    });

    return held;
}

+ (void)forgetAccountID:(NSString*)accountID {
    if (accountID.length == 0) {
        return;
    }

    dispatch_async(self.queue, ^{
        [self.established removeObjectForKey:accountID];
    });
}

+ (void)warm {
    for (TFNTwitterAccount* account in signedInAccounts()) {
        if ([account respondsToSelector:@selector(accountID)]) {
            [self credentialsForAccountID:account.accountID
                               completion:^(BHTWebCredentials* credentials){
                               }];
        }
    }
}

@end
