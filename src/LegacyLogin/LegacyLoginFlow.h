//
//  LegacyLoginFlow.h
//  NeoFreeBird
//

#import <UIKit/UIKit.h>

@class LegacyLoginFlow;

@protocol LegacyLoginFlowDelegate <NSObject>

// Returning nil fails the sign-in rather than skipping the challenge.
- (UIViewController*)viewControllerToPresentFromForLoginFlow:(LegacyLoginFlow*)flow;

- (void)loginFlowDidAddAccount:(LegacyLoginFlow*)flow;
- (void)loginFlowDidPresentChallenge:(LegacyLoginFlow*)flow;
- (void)loginFlow:(LegacyLoginFlow*)flow didFailWithMessage:(NSString*)message;

@end

@interface LegacyLoginFlow : NSObject

@property (nonatomic, weak) id<LegacyLoginFlowDelegate> delegate;

// nil when the app is missing a class the sign-in request needs.
+ (instancetype)flow;

- (void)signInWithIdentifier:(NSString*)identifier
                    password:(NSString*)password
                   uiMetrics:(NSString*)uiMetrics;

@end
