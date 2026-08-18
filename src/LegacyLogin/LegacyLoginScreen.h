//
//  LegacyLoginScreen.h
//  NeoFreeBird
//
//  The native legacy sign-in form, wrapped in a navigation controller.
//

#import <UIKit/UIKit.h>

@interface LegacyLoginScreen : NSObject

// Wrapped in a TFNNavigationController; nil when the app lacks a piece.
+ (UIViewController*)signInViewControllerWithIdentifier:(NSString*)identifier;

@end
