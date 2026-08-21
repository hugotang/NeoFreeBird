//
//  ProfilesSettingsViewController.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Settings/Pages/ProfilesSettingsViewController.h"
#import "Core/BHTBundle.h"
#import "Headers/TWHeaders.h"

extern void applySquareAvatarsSetting(void);

@implementation ProfilesSettingsViewController

- (NSString*)pageKey {
    return @"profiles";
}

- (void)settingDidChange:(NSString*)key {
    [super settingDidChange:key];
    if ([key isEqualToString:@"square_avatars"]) {
        applySquareAvatarsSetting();
    }
}

@end
