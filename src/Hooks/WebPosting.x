//
//  WebPosting.x
//  NeoFreeBird
//
//  Reroutes native tweet posting through x.com's web GraphQL CreateTweet endpoint
//  so sideloaded / legacy sessions can post without hitting native attestation.
//
//  The seam is TFSAPISessionImplementation, the app's own request pipeline: when a
//  hydrated CreateTweet request comes through it is re-signed as a website request
//  (web-session cookies + csrf + a fresh x-client-transaction-id). If the account
//  has no web session the request is left untouched and posts natively.
//

#import "HookHelpers.h"

#import "Web/BHTWebRequest.h"
#import "Web/BHTWebSession.h"

// MARK: - Small helpers

static BOOL isCreateTweet(NSString* urlString) {
    if (urlString.length == 0) {
        return NO;
    }

    return [[NSURL URLWithString:urlString].path hasSuffix:@"/CreateTweet"];
}

static NSString* accountIDOfSession(id session) {
    static Ivar named;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        named = class_getInstanceVariable(objc_getClass("TFSAPISessionImplementation"), "_accountID");
    });

    id accountID = named ? object_getIvar(session, named) : nil;
    return [accountID isKindOfClass:NSString.class] ? accountID : nil;
}

static NSMutableURLRequest* asWebsiteRequest(NSURLRequest* native) {
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:native.URL];
    request.HTTPMethod = native.HTTPMethod;
    request.timeoutInterval = native.timeoutInterval;
    if (native.HTTPBody) {
        request.HTTPBody = native.HTTPBody;
    } else if (native.HTTPBodyStream) {
        request.HTTPBodyStream = native.HTTPBodyStream;
    }

    [request setValue:[native valueForHTTPHeaderField:@"Content-Type"]
        forHTTPHeaderField:@"content-type"];

    return request;
}

static void sendAsWebsite(NSURLRequest* native, NSString* accountID,
                          void (^completion)(id, NSError*)) {
    NSMutableURLRequest* request = asWebsiteRequest(native);
    [BHTWebRequest asWebsite:request
                forAccountID:accountID
                  completion:^(BOOL asWebsite) {
                      completion(asWebsite ? request : native, nil);
                  }];
}

// MARK: - Shared accessors

id accountForAuthenticatedWebView(void) {
    Class hostClass = %c(T1HostViewController);
    if ([hostClass respondsToSelector:@selector(sharedHostViewController)]) {
        id host = [hostClass sharedHostViewController];
        if ([host respondsToSelector:@selector(currentAccount)]) {
            id account = [host currentAccount];
            if (account) {
                return account;
            }
        }
    }
    return nil;
}

static NSString* currentAccountID(void) {
    id account = accountForAuthenticatedWebView();
    if ([account respondsToSelector:@selector(accountID)]) {
        NSString* accountID = ((NSString* (*)(id, SEL))objc_msgSend)(account, @selector(accountID));
        return [accountID isKindOfClass:NSString.class] ? accountID : nil;
    }
    return nil;
}

// The current web session's cookie header + csrf token, for read-only web GraphQL
// GETs (e.g. SourceLabels.x). nil until a session has been minted; a mint is kicked
// off on a miss so the caller's retry recovers.
NSDictionary* currentWebCredentials(void) {
    NSString* accountID = currentAccountID();
    if (accountID.length == 0) {
        return nil;
    }

    BHTWebCredentials* credentials = [BHTWebSession cachedCredentialsForAccountID:accountID];
    if (!credentials) {
        [BHTWebSession credentialsForAccountID:accountID
                                   completion:^(BHTWebCredentials* minted){
                                   }];
        return nil;
    }

    return @{@"cookie" : credentials.cookieHeader, @"csrf" : credentials.csrfToken};
}

// Warm the current accounts' web sessions ahead of the first post, called from
// AppLifecycle.x on activation.
void prewarmWebCookiesIfNeeded(void) {
    [BHTWebSession warm];
}

// MARK: - Hooks

%hook TFSAPISessionImplementation

- (void)tnl_requestOperation:(id)operation
              hydrateRequest:(TFSAPIRequest*)request
                  completion:(void (^)(id, NSError*))completion {
    NSString* endpoint =
        [request respondsToSelector:@selector(endpointURLString)] ? request.endpointURLString : nil;
    if (!isCreateTweet(endpoint)) {
        %orig;
        return;
    }

    NSString* accountID = accountIDOfSession(self);
    %orig(operation, request, ^(id hydrated, NSError* error) {
        if (error || ![hydrated isKindOfClass:NSURLRequest.class]) {
            completion(hydrated, error);
            return;
        }

        sendAsWebsite(hydrated, accountID, completion);
    });
}

// Only a request the hook above rewrote carries a CSRF token, hence that test.
- (void)tnl_requestOperation:(id)operation
         authorizeURLRequest:(NSURLRequest*)request
                  completion:(void (^)(NSString*, NSError*))completion {
    if ([request valueForHTTPHeaderField:@"x-csrf-token"].length &&
        isCreateTweet(request.URL.absoluteString)) {
        completion(BHTWebBearer, nil);
        return;
    }

    %orig;
}

// Only 401 and 403 say the session itself has stopped being accepted.
- (void)tnl_requestOperation:(id)operation didCompleteWithResponse:(TNLResponse*)response {
    %orig;

    if (![response respondsToSelector:@selector(info)]) {
        return;
    }

    NSHTTPURLResponse* http = response.info.URLResponse;
    if (![http isKindOfClass:NSHTTPURLResponse.class] || !isCreateTweet(http.URL.absoluteString)) {
        return;
    }

    if (http.statusCode == 401 || http.statusCode == 403) {
        [BHTWebSession forgetAccountID:accountIDOfSession(self)];
    }
}

%end
