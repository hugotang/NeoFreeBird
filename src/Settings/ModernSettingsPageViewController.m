//
//  ModernSettingsPageViewController.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Settings/ModernSettingsPageViewController.h"
#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"
#import "Headers/TWHeaders.h"

// Twitter's own accent picker, as used by T1DisplaySettingsViewController: a
// state-free item that reads and writes the accent itself.
static const char* const kAccentPickerItemClass = "_TtC14T1TwitterSwift20ColorThemePickerItem";
static const char* const kAccentPickerAdapterClass =
    "_TtC14T1TwitterSwift27ColorThemePickerItemAdapter";

@interface ModernSettingsPageViewController ()
@property (nonatomic, copy) NSString* registryPageKey;
@end

@implementation ModernSettingsPageViewController

#pragma mark - Lifecycle

- (instancetype)initWithAccount:(TFNTwitterAccount*)account {
    return [self initWithAccount:account pageKey:nil];
}

- (instancetype)initWithAccount:(TFNTwitterAccount*)account pageKey:(NSString*)pageKey {
    if ((self = [super initWithCollectionViewLayout:nil])) {
        self.account = account;
        self.registryPageKey = pageKey;
        [self useDataViewAdapter:[[objc_getClass("TFNSettingsDescriptionItemTableRowAdapter") alloc] init]
                 forItemsOfClass:objc_getClass("TFNSettingsDescriptionItem")];

        Class accentPickerClass = objc_getClass(kAccentPickerItemClass);
        Class accentPickerAdapterClass = objc_getClass(kAccentPickerAdapterClass);
        if (accentPickerClass && accentPickerAdapterClass) {
            [self useDataViewAdapter:[[accentPickerAdapterClass alloc] init]
                     forItemsOfClass:accentPickerClass];
        }

        [self setNeedsUpdate:NO];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNav];
}

- (void)setupNav {
    NSString* title = [[BHTBundle sharedBundle]
        localizedStringForKey:[BHTSettings titleKeyForPage:[self pageKey]]];
    if (self.account) {
        self.navigationItem.titleView =
            [objc_getClass("TFNTitleView") titleViewWithTitle:title
                                                     subtitle:self.account.displayUsername];
    } else {
        self.title = title;
    }
}

#pragma mark - Page Registry

- (NSString*)pageKey {
    return self.registryPageKey;
}

- (NSArray<NSDictionary*>*)entries {
    return [BHTSettings settingsForPage:[self pageKey]];
}

// Title key defaults to KEY_TITLE; an explicit titleKey takes precedence.
- (NSString*)localizedTitleForEntry:(NSDictionary*)entry {
    NSString* titleKey = entry[@"titleKey"];
    if (!titleKey) {
        titleKey = [NSString stringWithFormat:@"%@_TITLE", [entry[@"key"] uppercaseString]];
    }
    return [[BHTBundle sharedBundle] localizedStringForKey:titleKey];
}

// The bundle returns the key itself when no string exists, which counts as no detail.
- (NSString*)localizedDetailForKey:(NSString*)key {
    NSString* detailKey = [NSString stringWithFormat:@"%@_DETAIL", [key uppercaseString]];
    NSString* detail = [[BHTBundle sharedBundle] localizedStringForKey:detailKey];
    return [detail isEqualToString:detailKey] ? @"" : detail;
}

// Localized at render time; the registry can't call localizedStringForKey
// without re-entering the settings lookup.
- (NSString*)defaultSubtitleForEntry:(NSDictionary*)entry {
    NSString* subtitleDefaultKey = entry[@"subtitleDefaultKey"];
    if (subtitleDefaultKey) {
        return [[BHTBundle sharedBundle] localizedStringForKey:subtitleDefaultKey];
    }
    return entry[@"subtitleDefault"];
}

- (NSString*)subtitleForEntry:(NSDictionary*)entry {
    NSString* prefKey = entry[@"prefKeyForSubtitle"];
    if (!prefKey) {
        return nil;
    }
    return [[NSUserDefaults standardUserDefaults] objectForKey:prefKey]
               ?: [self defaultSubtitleForEntry:entry];
}

#pragma mark - Items

- (void)update:(BOOL)animated {
    [super update:animated];

    NSMutableArray* rows = [NSMutableArray array];
    for (NSDictionary* entry in [self entries]) {
        NSString* parentKey = entry[@"parentKey"];
        if (parentKey && ![BHTSettings boolForKey:parentKey]) {
            continue;
        }
        [rows addObjectsFromArray:[self itemsForEntry:entry]];
    }

    NSArray* sections = [self updatedSections:@[rows] forStyle:0];
    if (animated) {
        [self updateSections:sections];
    } else {
        self.sections = sections;
    }
}

- (NSArray*)itemsForEntry:(NSDictionary*)entry {
    NSString* type = entry[@"type"];
    if ([type isEqualToString:@"button"] || [type isEqualToString:@"compactButton"]) {
        return @[[self buttonItemForEntry:entry]];
    }

    if ([type isEqualToString:@"accentPicker"]) {
        return [self accentPickerItemsForEntry:entry];
    }

    NSMutableArray* items = [NSMutableArray arrayWithObject:[self toggleItemForEntry:entry]];
    NSString* detail = [self localizedDetailForKey:entry[@"key"]];
    if (detail.length > 0) {
        [items addObject:[[objc_getClass("TFNSettingsDescriptionItem") alloc]
                             initForNoActionWithText:detail]];
    }
    return items;
}

- (id)toggleItemForEntry:(NSDictionary*)entry {
    NSString* key = entry[@"key"];
    __weak typeof(self) weakSelf = self;
    TFNBooleanItem* item = [[objc_getClass("TFNBooleanItem") alloc]
        initWithStyle:0
                 text:[self localizedTitleForEntry:entry]
                value:[BHTSettings boolForKey:key]
         updateAction:^(TFNDataViewItemArgs* args) {
             BOOL value = [(TFNBooleanItem*)args.item value];
             [[NSUserDefaults standardUserDefaults] setBool:value forKey:key];
             [weakSelf settingDidChange:key];
         }];

    return [item tfn_withMultipleLines:YES];
}

- (NSArray*)accentPickerItemsForEntry:(NSDictionary*)entry {
    Class accentPickerClass = objc_getClass(kAccentPickerItemClass);
    if (!accentPickerClass) {
        return @[];
    }

    id picker = [[accentPickerClass alloc] init];
    if (!entry[@"titleKey"]) {
        return @[picker];
    }

    return @[[[self localizedTitleForEntry:entry] tfn_asNextSectionHeader], picker];
}

- (id)buttonItemForEntry:(NSDictionary*)entry {
    T1SubtitledSettingsItem* item = [[objc_getClass("T1SubtitledSettingsItem") alloc] init];
    item.title = [self localizedTitleForEntry:entry];
    item.subtitle = [self subtitleForEntry:entry];

    __weak typeof(self) weakSelf = self;
    item.didSelectRowAtIndexPathBlock =
        ^(TFNGenericItem* selectedItem, TFNItemsDataViewController* controller,
          UITableView* tableView, NSIndexPath* indexPath) {
            [tableView deselectRowAtIndexPath:indexPath animated:YES];
            [weakSelf performActionForEntry:entry];
        };
    return item;
}

#pragma mark - Actions

- (void)performActionForEntry:(NSDictionary*)entry {
    NSString* actionName = entry[@"action"];
    if (!actionName) {
        return;
    }

    SEL action = NSSelectorFromString(actionName);
    if (![self respondsToSelector:action]) {
        return;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [self performSelector:action
               withObject:entry];
#pragma clang diagnostic pop
}

// Children are only listed while their parent is on, so a parent's change
// rebuilds the page and the rows animate in or out.
- (void)settingDidChange:(NSString*)key {
    for (NSDictionary* entry in [self entries]) {
        if ([entry[@"parentKey"] isEqualToString:key]) {
            [self setNeedsUpdate:YES];
            return;
        }
    }
}

@end
