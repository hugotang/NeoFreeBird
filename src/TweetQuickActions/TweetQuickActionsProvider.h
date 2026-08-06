#import <Foundation/Foundation.h>

@class TFNActionItem;

NS_ASSUME_NONNULL_BEGIN

@interface TweetQuickActionsProvider : NSObject
- (TFNActionItem* _Nullable)actionItemForStatus:(id _Nullable)status
                                      entityURL:(id _Nullable)entityURL;
@end

NS_ASSUME_NONNULL_END
