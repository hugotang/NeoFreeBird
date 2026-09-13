//
//  LegacyLoginScreen.h
//  NeoFreeBird
//
//  The native legacy sign-in form, wrapped in a navigation controller.
//

#import <UIKit/UIKit.h>

// Uses the host app's sign-in entry point, bypassing our legacy form hooks.
BOOL NFBPresentBuiltInLogin(NSString* identifier);

@interface LegacyLoginScreen : NSObject

// Wrapped in a TFNNavigationController; nil when the app lacks a piece.
+ (UIViewController*)signInViewControllerWithIdentifier:(NSString*)identifier;

@end
