//
//  ModernSettingsViewController.m
//  NeoFreeBird
//
//  Created by BandarHelal on 25/11/2021.
//

#import "Settings/ModernSettingsViewController.h"
#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"
#import "Settings/ModernSettingsPageViewController.h"
#import "Settings/ModernSettingsPlaceholderViewController.h"
#import "Settings/Pages/AppearanceSettingsViewController.h"
#import "Settings/Pages/DebugSettingsViewController.h"
#import "Settings/Pages/ProfilesSettingsViewController.h"
#import "Settings/Pages/TimelinesSettingsViewController.h"
#import "Settings/Pages/TweetsSettingsViewController.h"
#import "Settings/Pages/WebSettingsViewController.h"

static const CGFloat NFBProfileRowHeight = 64;
static const CGFloat NFBProfileAvatarSize = 40;

@interface ModernSettingsViewController ()
@property (nonatomic, strong) TFNTwitterAccount* account;
@end

@implementation ModernSettingsViewController

#pragma mark - Lifecycle

- (instancetype)initWithAccount:(TFNTwitterAccount*)account {
    if ((self = [super initWithCollectionViewLayout:nil])) {
        _account = account;
        [self useDataViewAdapter:[[objc_getClass("TFNSettingsIconNavigationItemAdapter") alloc] init]
                 forItemsOfClass:objc_getClass("TFNSettingsNavigationItem")];
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
    NSString* title = [[BHTBundle sharedBundle] localizedStringForKey:@"NFB_SETTINGS_TITLE"];
    if (self.account) {
        self.navigationItem.titleView =
            [objc_getClass("TFNTitleView") titleViewWithTitle:title
                                                     subtitle:self.account.displayUsername];
    } else {
        self.title = title;
    }
}

#pragma mark - Sections

- (void)update:(BOOL)animated {
    [super update:animated];

    NSArray* sections = @[
        [self pageItems],
        [self profileSectionWithHeaderKey:@"DEVELOPER_SECTION_HEADER_TITLE"
                                 profiles:[self developerProfiles]],
        [self profileSectionWithHeaderKey:@"COOL_KIDS_SECTION_HEADER_TITLE"
                                 profiles:[self coolKidsProfiles]],
        [self profileSectionWithHeaderKey:@"SPECIAL_THANKS_SECTION_HEADER_TITLE"
                                 profiles:[self specialThanksProfiles]],
        [self profileSectionWithHeaderKey:@"FOLLOW_OFFICIAL_PAGE_SECTION_HEADER_TITLE"
                                 profiles:[self officialPageProfiles]],
        @[[self versionItem]]
    ];

    self.sections = [self updatedSections:sections forStyle:0];
}

- (id)versionItem {
    NSString* version = @TWEAK_NAME_STRING " v" TWEAK_VERSION_STRING " (" TWEAK_COMMIT_STRING ")";
    return [[objc_getClass("TFNSettingsDescriptionItem") alloc] initForNoActionWithText:version];
}

#pragma mark - Pages

// Titles, subtitles and settings all come from the registry, so a page only
// needs its key, its icon and the controller that presents it.
- (TFNSettingsNavigationItem*)itemForPage:(NSString*)pageKey
                                     icon:(NSString*)iconName
                          controllerClass:(Class)controllerClass {
    BHTBundle* bundle = [BHTBundle sharedBundle];
    TFNTwitterAccount* account = self.account;
    return [[objc_getClass("TFNSettingsNavigationItem") alloc]
            initWithTitle:[bundle localizedStringForKey:[BHTSettings titleKeyForPage:pageKey]]
                   detail:[bundle localizedStringForKey:[BHTSettings subtitleKeyForPage:pageKey]]
                 iconName:iconName
        controllerFactory:^UIViewController* {
            if (controllerClass) {
                return [[controllerClass alloc] initWithAccount:account];
            }
            return [[ModernSettingsPageViewController alloc] initWithAccount:account
                                                                     pageKey:pageKey];
        }];
}

- (TFNSettingsNavigationItem*)itemForPage:(NSString*)pageKey icon:(NSString*)iconName {
    return [self itemForPage:pageKey icon:iconName controllerClass:nil];
}

- (NSArray*)pageItems {
    TFNTwitterAccount* account = self.account;
    BHTBundle* bundle = [BHTBundle sharedBundle];

    TFNSettingsNavigationItem* presets = [[objc_getClass("TFNSettingsNavigationItem") alloc]
            initWithTitle:[bundle localizedStringForKey:@"MODERN_SETTINGS_PRESETS_TITLE"]
                   detail:[bundle localizedStringForKey:@"MODERN_SETTINGS_PRESETS_SUBTITLE"]
                 iconName:@"receipt_checkmark_stroke"
        controllerFactory:^UIViewController* {
            return [[ModernSettingsPlaceholderViewController alloc]
                initWithAccount:account
                       titleKey:@"MODERN_SETTINGS_PRESETS_TITLE"];
        }];

    return @[
        [self itemForPage:@"general"
                     icon:@"settings_stroke"],
        [self itemForPage:@"appearance"
                       icon:@"paintbrush_stroke"
            controllerClass:[AppearanceSettingsViewController class]],
        [self itemForPage:@"grok"
                     icon:@"grok_icon_stroke"],
        [self itemForPage:@"timelines"
                       icon:@"home_stroke"
            controllerClass:[TimelinesSettingsViewController class]],
        [self itemForPage:@"tweets"
                       icon:@"quill"
            controllerClass:[TweetsSettingsViewController class]],
        [self itemForPage:@"media_downloads"
                     icon:@"media_tab_stroke"],
        [self itemForPage:@"profiles"
                       icon:@"account"
            controllerClass:[ProfilesSettingsViewController class]],
        [self itemForPage:@"search"
                     icon:@"search_stroke"],
        [self itemForPage:@"web"
                       icon:@"globe_stroke"
            controllerClass:[WebSettingsViewController class]],
        [self itemForPage:@"branding"
                     icon:@"hash_stroke"],
        presets,
        [self itemForPage:@"debug"
                       icon:@"code"
            controllerClass:[DebugSettingsViewController class]]
    ];
}

#pragma mark - Profiles

- (NSArray<NSDictionary*>*)developerProfiles {
    return @[
        @{
            @"title": @"aridan",
            @"username": @"actuallyaridan",
            @"avatarURL": @"https://unavatar.io/x/actuallyaridan?fallback=https://neofreebird.com/"
                          @"images/actuallyaridan.png",
            @"userID": @"1351218086649720837"
        },
        @{
            @"title": @"Thea 🐾",
            @"username": @"nyaathea",
            @"avatarURL": @"https://unavatar.io/github/nyathea?fallback=https://neofreebird.com/images/"
                          @"theameoww.png",
            @"userID": @"1541742676009226241"
        },
        @{
            @"title": @"timi2506",
            @"username": @"timi2506",
            @"avatarURL": @"https://unavatar.io/github/timi2506?fallback=https://neofreebird.com/images/"
                          @"timi2506.png",
            @"userID": @"1684856685486063616"
        }
    ];
}

- (NSArray<NSDictionary*>*)coolKidsProfiles {
    return @[
        @{
            @"title": @"Eevee",
            @"username": @"whoeevee1",
            @"avatarURL": @"https://unavatar.io/github/whoeevee?fallback=https://neofreebird.com/images/"
                          @"whoeevee.png",
            @"userID": @"1547956497342115844"
        },
        @{
            @"title": @"zxcvbn",
            @"username": @"zxxvbn0",
            @"avatarURL":
                @"https://unavatar.io/x/zxxvbn0?fallback=https://neofreebird.com/images/zxxvbn0.png",
            @"userID": @"1678444396717514760"
        }
    ];
}

- (NSArray<NSDictionary*>*)specialThanksProfiles {
    return @[
        @{
            @"title": @"BandarHelal",
            @"username": @"BandarHL",
            @"avatarURL":
                @"https://unavatar.io/x/BandarHL?fallback=https://neofreebird.com/images/BandarHL.png",
            @"userID": @"827842200708853762"
        },
        @{
            @"title": @"YouGottaBillieve",
            @"username": @"ugottabillieve",
            @"avatarURL": @"https://unavatar.io/x/ugottabillieve?fallback=https://neofreebird.com/"
                          @"images/ugottabillieve.png",
            @"userID": @"1616194182187732992"
        }
    ];
}

- (NSArray<NSDictionary*>*)officialPageProfiles {
    return @[@{
        @"title": @"NeoFreeBird",
        @"username": @"NeoFreeBird",
        @"avatarURL": @"https://unavatar.io/x/NeoFreeBird?fallback=https://neofreebird.com/images/"
                      @"NeoFreeBird.png",
        @"userID": @"1878595268255297537"
    }];
}

- (NSArray*)profileSectionWithHeaderKey:(NSString*)headerKey
                               profiles:(NSArray<NSDictionary*>*)profiles {
    NSMutableArray* section = [NSMutableArray array];
    [section addObject:[[[BHTBundle sharedBundle] localizedStringForKey:headerKey]
                           tfn_asNextSectionHeader]];
    for (NSDictionary* profile in profiles) {
        [section addObject:[self itemForProfile:profile]];
    }
    return section;
}

- (TFNGenericItem*)itemForProfile:(NSDictionary*)profile {
    TFNGenericItem* item = [[objc_getClass("TFNGenericItem") alloc] init];
    __weak typeof(self) weakSelf = self;

    item.cellForRowAtIndexPathBlock =
        ^UITableViewCell*(TFNGenericItem* profileItem, TFNItemsDataViewController* controller,
                          UITableView* tableView, NSIndexPath* indexPath) {
            UIImage* avatar = [weakSelf avatarForProfile:profile
                                             atIndexPath:indexPath
                                            inController:controller];
            return [objc_getClass("TFNTextCell")
                iconCellForTableView:tableView
                           indexPath:indexPath
                            withText:profile[@"title"]
                          detailText:[@"@" stringByAppendingString:profile[@"username"]]
                                icon:avatar
                       accessoryType:UITableViewCellAccessoryDisclosureIndicator];
        };

    item.heightForRowAtIndexPathBlock =
        ^CGFloat(TFNGenericItem* profileItem, TFNItemsDataViewController* controller,
                 UITableView* tableView, NSIndexPath* indexPath) {
            return NFBProfileRowHeight;
        };

    item.didSelectRowAtIndexPathBlock =
        ^(TFNGenericItem* profileItem, TFNItemsDataViewController* controller,
          UITableView* tableView, NSIndexPath* indexPath) {
            [tableView deselectRowAtIndexPath:indexPath animated:YES];
            [weakSelf openProfileWithUserID:profile[@"userID"]];
        };

    return item;
}

- (void)openProfileWithUserID:(NSString*)userID {
    if (!userID.length) {
        return;
    }
    NSString* profileURL = [NSString stringWithFormat:@"twitter://user?id=%@", userID];
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:profileURL]
                                       options:@{}
                             completionHandler:nil];
}

#pragma mark - Avatars

+ (NSCache<NSString*, UIImage*>*)avatarCache {
    static NSCache<NSString*, UIImage*>* cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
    });
    return cache;
}

// TFNTextCell draws its icon at the image's own size and doesn't clip it, so
// the avatar is masked to a circle while it is scaled down.
+ (UIImage*)roundedAvatarFromImage:(UIImage*)image {
    CGRect bounds = CGRectMake(0, 0, NFBProfileAvatarSize, NFBProfileAvatarSize);
    UIGraphicsImageRenderer* renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:bounds];
    UIImage* rounded = [renderer imageWithActions:^(UIGraphicsImageRendererContext* context) {
        [[UIBezierPath bezierPathWithOvalInRect:bounds] addClip];
        [image drawInRect:bounds];
    }];
    return [rounded imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

- (UIImage*)avatarForProfile:(NSDictionary*)profile
                 atIndexPath:(NSIndexPath*)indexPath
                inController:(TFNItemsDataViewController*)controller {
    NSString* avatarURL = profile[@"avatarURL"];
    UIImage* cached = [[self.class avatarCache] objectForKey:avatarURL];
    if (cached) {
        return cached;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData* data = [NSData dataWithContentsOfURL:[NSURL URLWithString:avatarURL]];
        UIImage* image = [UIImage imageWithData:data];
        if (!image) {
            return;
        }
        UIImage* avatar = [self.class roundedAvatarFromImage:image];
        [[self.class avatarCache] setObject:avatar forKey:avatarURL];
        dispatch_async(dispatch_get_main_queue(), ^{
            [controller reloadCellsForItemsAtIndexPaths:@[indexPath]
                                       withRowAnimation:UITableViewRowAnimationNone];
        });
    });

    UIImageSymbolConfiguration* configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:NFBProfileAvatarSize];
    return [UIImage systemImageNamed:@"person.crop.circle.fill" withConfiguration:configuration];
}

@end
