//
//  BHTWebRequest.m
//  NeoFreeBird
//

#import "BHTWebRequest.h"

#import "BHTWebPage.h"
#import "BHTWebSession.h"

NSString* const BHTWebBearer =
    @"Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhL"
    @"TvJu4FA33AGWWjCpTnA";

static NSString* const BHTWebOrigin = @"https://x.com";
static NSString* const BHTWebReferer = @"https://x.com/";

@implementation BHTWebRequest

+ (void)asWebsite:(NSMutableURLRequest*)request
     forAccountID:(NSString*)accountID
       completion:(void (^)(BOOL asWebsite))completion {
    NSString* path = request.URL.path;
    NSString* method = request.HTTPMethod;
    if (path.length == 0 || method.length == 0) {
        completion(NO);
        return;
    }

    [BHTWebSession
        credentialsForAccountID:accountID
                     completion:^(BHTWebCredentials* credentials) {
                         if (!credentials) {
                             completion(NO);
                             return;
                         }

                         // The cookies are written by hand, so the store must
                         // not write its own over them.
                         request.HTTPShouldHandleCookies = NO;
                         if (![request valueForHTTPHeaderField:@"content-type"]) {
                             [request setValue:@"application/json" forHTTPHeaderField:@"content-type"];
                         }
                         [request setValue:NSBundle.mainBundle.preferredLocalizations.firstObject
                                               ?: @"en"
                             forHTTPHeaderField:@"x-twitter-client-language"];
                         [request setValue:BHTWebBearer forHTTPHeaderField:@"authorization"];
                         [request setValue:@"*/*" forHTTPHeaderField:@"accept"];
                         [request setValue:BHTWebOrigin forHTTPHeaderField:@"origin"];
                         [request setValue:BHTWebReferer forHTTPHeaderField:@"referer"];
                         [request setValue:@"OAuth2Session" forHTTPHeaderField:@"x-twitter-auth-type"];
                         [request setValue:@"yes" forHTTPHeaderField:@"x-twitter-active-user"];
                         [request setValue:credentials.csrfToken forHTTPHeaderField:@"x-csrf-token"];
                         [request setValue:credentials.cookieHeader forHTTPHeaderField:@"cookie"];

                         [BHTWebPage
                             tokenForPath:path
                                   method:method
                               completion:^(NSString* token) {
                                   if (token.length) {
                                       [request setValue:token
                                           forHTTPHeaderField:@"x-client-transaction-id"];
                                   }

                                   // The token was minted on the generator's
                                   // page, so it goes out as that page's agent.
                                   [request setValue:BHTWebPage.userAgent
                                       forHTTPHeaderField:@"user-agent"];
                                   completion(YES);
                               }];
                     }];
}

@end
