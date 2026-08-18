//
//  BHTWebRequest.h
//  NeoFreeBird
//
//  Re-signs a native API request so x.com's web endpoints accept it.
//

#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString* const BHTWebBearer;

@interface BHTWebRequest : NSObject

// NO when the account has no web session, leaving the request untouched. The
// block runs on an arbitrary queue.
+ (void)asWebsite:(NSMutableURLRequest*)request
     forAccountID:(NSString*)accountID
       completion:(void (^)(BOOL asWebsite))completion;

@end
