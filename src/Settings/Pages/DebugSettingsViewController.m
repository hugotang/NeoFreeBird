//
//  DebugSettingsViewController.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Settings/Pages/DebugSettingsViewController.h"
#import "Core/BHTSettings.h"
#import "Headers/TWHeaders.h"

@implementation DebugSettingsViewController

- (NSString*)pageKey {
    return @"debug";
}

- (void)settingDidChange:(NSString*)key {
    [super settingDidChange:key];
    if ([key isEqualToString:@"flex_twitter"]) {
        if ([BHTSettings boolForKey:key]) {
            [[objc_getClass("FLEXManager") sharedManager] showExplorer];
        } else {
            [[objc_getClass("FLEXManager") sharedManager] hideExplorer];
        }
    }
}

@end
