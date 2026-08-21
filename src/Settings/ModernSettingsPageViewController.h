//
//  ModernSettingsPageViewController.h
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Headers/TFNHeaders.h"

@interface ModernSettingsPageViewController : TFNItemsDataViewController

@property (nonatomic, strong) TFNTwitterAccount* account;

- (instancetype)initWithAccount:(TFNTwitterAccount*)account;

// Data-only pages are created directly with their registry key; pages with
// custom behaviour subclass this and override -pageKey instead.
- (instancetype)initWithAccount:(TFNTwitterAccount*)account pageKey:(NSString*)pageKey;

// Identifies the page's entry in the BHTSettings registry
- (NSString*)pageKey;

// Called after a toggle has been written, for pages that apply it immediately
- (void)settingDidChange:(NSString*)key;

// The right-hand value of a button row, by default the preference named by the
// entry's prefKeyForSubtitle
- (NSString*)subtitleForEntry:(NSDictionary*)entry;

@end
