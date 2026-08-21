//
//  TweetsSettingsViewController.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Settings/Pages/TweetsSettingsViewController.h"
#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"
#import "Headers/TWHeaders.h"

@implementation TweetsSettingsViewController

- (NSString*)pageKey {
    return @"tweets";
}

// The timeout is stored as a number, so its row value is formatted rather than
// read straight from the preference.
- (NSString*)subtitleForEntry:(NSDictionary*)entry {
    if ([entry[@"key"] isEqualToString:@"undo_tweet_timeout"]) {
        return [self labelForTimeout:[BHTSettings integerForKey:@"undo_tweet_timeout"]];
    }
    return [super subtitleForEntry:entry];
}

// A timeout of 0 reads as "Off"; any positive value shows its seconds.
- (NSString*)labelForTimeout:(NSInteger)seconds {
    if (seconds <= 0) {
        return [[BHTBundle sharedBundle] localizedTwitterStringForKey:@"GENERIC_OFF_LABEL"];
    }
    NSString* format = [[BHTBundle sharedBundle]
        localizedTwitterStringForKey:@"SUBSCRIPTION_UNDO_SEND_DURATION_LABEL"];
    return [NSString stringWithFormat:format, (long)seconds];
}

// Off plus the same durations Twitter offers in its own premium undo settings.
- (void)showUndoTimeoutPicker:(NSDictionary*)sender {
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"UNDO_TWEET_TITLE"]
                         message:nil
                  preferredStyle:UIAlertControllerStyleAlert];

    for (NSNumber* seconds in @[@0, @5, @10, @20, @30, @60]) {
        [alert addAction:[UIAlertAction actionWithTitle:[self labelForTimeout:seconds.integerValue]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction* action) {
                                                    [[NSUserDefaults standardUserDefaults]
                                                        setInteger:seconds.integerValue
                                                            forKey:@"undo_tweet_timeout"];
                                                    [self setNeedsUpdate:YES];
                                                }]];
    }

    [alert addAction:[UIAlertAction
                         actionWithTitle:[[BHTBundle sharedBundle]
                                             localizedTwitterStringForKey:@"CANCEL_ACTION_LABEL"]
                                   style:UIAlertActionStyleCancel
                                 handler:nil]];

    [self presentViewController:alert animated:YES completion:nil];
}

@end
