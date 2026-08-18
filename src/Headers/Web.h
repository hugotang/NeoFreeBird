//
//  Web.h
//  NeoFreeBird
//
//  App classes behind the CreateTweet reroute (WebPosting.x, BHTWeb*).
//

#import <Foundation/Foundation.h>

@interface TFSAPIRequest : NSObject
@property (nonatomic, readonly) NSString* endpointURLString;
@end

@interface TNLResponseInfo : NSObject
@property (nonatomic, readonly) NSHTTPURLResponse* URLResponse;
@end

@interface TNLResponse : NSObject
@property (nonatomic, readonly) TNLResponseInfo* info;
@end

@interface TFSAPISessionImplementation : NSObject
@end
