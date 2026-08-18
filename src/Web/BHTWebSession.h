//
//  BHTWebSession.h
//  NeoFreeBird
//
//  Per-account web credentials, minted from the account's own
//  authenticate_web_view exchange and cached for reuse.
//

#import <Foundation/Foundation.h>

@interface BHTWebCredentials : NSObject

@property (nonatomic, readonly, copy) NSString* cookieHeader;
@property (nonatomic, readonly, copy) NSString* csrfToken;

@end

@interface BHTWebSession : NSObject

+ (void)warm;

// The block runs on an arbitrary queue, with nil when the account has no web
// session; one is minted when there is none, so it can take seconds.
+ (void)credentialsForAccountID:(NSString*)accountID
                     completion:(void (^)(BHTWebCredentials* credentials))completion;

// A synchronous read of the cache alone; nil until a session has been minted.
+ (BHTWebCredentials*)cachedCredentialsForAccountID:(NSString*)accountID;

+ (void)forgetAccountID:(NSString*)accountID;

@end
