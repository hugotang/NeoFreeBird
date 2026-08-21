//
//  TimelinesSettingsViewController.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Settings/Pages/TimelinesSettingsViewController.h"
#import "Headers/TWHeaders.h"

extern void applyHideCustomTimelinesSetting(void);

@implementation TimelinesSettingsViewController

- (NSString*)pageKey {
    return @"timelines";
}

- (void)settingDidChange:(NSString*)key {
    [super settingDidChange:key];
    if ([key isEqualToString:@"hide_custom_timelines"]) {
        applyHideCustomTimelinesSetting();
    }
}

@end
