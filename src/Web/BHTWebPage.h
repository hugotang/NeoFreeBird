//
//  BHTWebPage.h
//  NeoFreeBird
//
//  An offscreen web client that mints the x-client-transaction-id the web
//  GraphQL endpoints expect, by running TransactionID.js against x.com.
//

#import <Foundation/Foundation.h>

@interface BHTWebPage : NSObject

// The block runs on the main queue, with nil when no token could be made.
+ (void)tokenForPath:(NSString*)path
              method:(NSString*)method
          completion:(void (^)(NSString* token))completion;

// nil until a page has first loaded.
+ (NSString*)userAgent;

@end
