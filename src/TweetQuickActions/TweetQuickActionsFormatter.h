#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BHTTweetQuickActionsFormatter : NSObject
+ (NSString* _Nullable)normalizedTextFromValue:(id _Nullable)value;
+ (NSString* _Nullable)authorWithName:(NSString* _Nullable)name
                               handle:(NSString* _Nullable)handle;
+ (NSString* _Nullable)markdownWithText:(NSString* _Nullable)text
                                  author:(NSString* _Nullable)author
                               URLString:(NSString* _Nullable)URLString;
@end

NS_ASSUME_NONNULL_END
