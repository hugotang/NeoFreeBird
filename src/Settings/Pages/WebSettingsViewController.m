//
//  WebSettingsViewController.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Settings/Pages/WebSettingsViewController.h"
#import "Core/BHTBundle.h"
#import "Headers/TWHeaders.h"

@implementation WebSettingsViewController

- (NSString*)pageKey {
    return @"web";
}

// Reduces user input like "https://fxtwitter.com/" to a bare host, so the
// value can be assigned straight to NSURLComponents.host when rewriting.
- (NSString*)sharingDomainFromInput:(NSString*)input {
    NSString* domain =
        [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    NSRange schemeRange = [domain rangeOfString:@"://"];
    if (schemeRange.location != NSNotFound) {
        domain = [domain substringFromIndex:NSMaxRange(schemeRange)];
    }

    NSRange pathRange = [domain rangeOfString:@"/"];
    if (pathRange.location != NSNotFound) {
        domain = [domain substringToIndex:pathRange.location];
    }

    return domain;
}

- (void)showSharingDomainPrompt:(NSDictionary*)data {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSString* currentHost = [defaults objectForKey:@"sharing_domain"];

    UIAlertController* alert =
        [UIAlertController alertControllerWithTitle:[[BHTBundle sharedBundle]
                                                        localizedStringForKey:@"SHARING_DOMAIN_TITLE"]
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField* textField) {
        textField.text = currentHost;
        textField.placeholder = @"x.com";
        textField.keyboardType = UIKeyboardTypeURL;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];

    [alert addAction:[UIAlertAction
                         actionWithTitle:[[BHTBundle sharedBundle]
                                             localizedTwitterStringForKey:@"CANCEL_ACTION_LABEL"]
                                   style:UIAlertActionStyleCancel
                                 handler:nil]];

    [alert
        addAction:[UIAlertAction
                      actionWithTitle:[[BHTBundle sharedBundle]
                                          localizedTwitterStringForKey:@"SAVE_ACTION_LABEL"]
                                style:UIAlertActionStyleDefault
                              handler:^(UIAlertAction* action) {
                                  NSString* domain =
                                      [self sharingDomainFromInput:alert.textFields.firstObject.text];

                                  if (domain.length > 0) {
                                      [defaults setObject:domain forKey:@"sharing_domain"];
                                  } else {
                                      [defaults removeObjectForKey:@"sharing_domain"];
                                  }
                                  [defaults synchronize];
                                  [self setNeedsUpdate:YES];
                              }]];

    [self presentViewController:alert animated:YES completion:nil];
}

@end
