//
//  ModernSettingsPlaceholderViewController.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Settings/ModernSettingsPlaceholderViewController.h"
#import "Core/BHTBundle.h"
#import "Headers/TWHeaders.h"

@interface ModernSettingsPlaceholderViewController ()
@property (nonatomic, strong) TFNTwitterAccount* account;
@property (nonatomic, copy) NSString* navigationTitleKey;
@end

@implementation ModernSettingsPlaceholderViewController

- (instancetype)initWithAccount:(TFNTwitterAccount*)account titleKey:(NSString*)titleKey {
    if ((self = [super initWithCollectionViewLayout:nil])) {
        _account = account;
        _navigationTitleKey = [titleKey copy];
        [self useDataViewAdapter:[[objc_getClass("TFNSettingsDescriptionItemTableRowAdapter") alloc] init]
                 forItemsOfClass:objc_getClass("TFNSettingsDescriptionItem")];
        [self setNeedsUpdate:NO];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNav];
}

- (void)setupNav {
    NSString* titleKey =
        self.navigationTitleKey.length > 0 ? self.navigationTitleKey : @"NFB_SETTINGS_TITLE";
    NSString* title = [[BHTBundle sharedBundle] localizedStringForKey:titleKey];

    if (self.account) {
        self.navigationItem.titleView =
            [objc_getClass("TFNTitleView") titleViewWithTitle:title
                                                     subtitle:self.account.displayUsername];
    } else {
        self.title = title;
    }
}

- (void)update:(BOOL)animated {
    [super update:animated];

    BHTBundle* bundle = [BHTBundle sharedBundle];
    id header =
        [[bundle localizedStringForKey:@"MODERN_SETTINGS_PLACEHOLDER_TEXT"] tfn_asNextSectionHeader];
    id detail = [[objc_getClass("TFNSettingsDescriptionItem") alloc]
        initForNoActionWithText:[bundle
                                    localizedStringForKey:@"MODERN_SETTINGS_PLACEHOLDER_DETAIL_TEXT"]];

    self.sections = [self updatedSections:@[@[header, detail]] forStyle:0];
}

@end
