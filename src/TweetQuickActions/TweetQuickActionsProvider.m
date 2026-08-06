#import "TweetQuickActionsProvider.h"
#import "Core/BHTShareURL.h"
#import "Hooks/HookHelpers.h"
#import "TweetQuickActionsFormatter.h"

@interface BHTTweetQuickActionsContext : NSObject
@property (nonatomic, copy, readonly) NSString* text;
@property (nonatomic, copy, readonly) NSString* displayName;
@property (nonatomic, copy, readonly) NSString* handle;
@property (nonatomic, assign, readonly) long long statusID;
@property (nonatomic, copy, readonly) NSString* author;
@property (nonatomic, copy, readonly) NSString* URLString;
@property (nonatomic, copy, readonly) NSString* markdown;
- (instancetype)initWithText:(NSString*)text
                 displayName:(NSString*)displayName
                      handle:(NSString*)handle
                    statusID:(long long)statusID
                      author:(NSString*)author
                   URLString:(NSString*)URLString
                    markdown:(NSString*)markdown;
@end

@implementation BHTTweetQuickActionsContext
- (instancetype)initWithText:(NSString*)text
                 displayName:(NSString*)displayName
                      handle:(NSString*)handle
                    statusID:(long long)statusID
                      author:(NSString*)author
                   URLString:(NSString*)URLString
                    markdown:(NSString*)markdown {
    self = [super init];
    if (self) {
        _text = [text copy];
        _displayName = [displayName copy];
        _handle = [handle copy];
        _statusID = statusID;
        _author = [author copy];
        _URLString = [URLString copy];
        _markdown = [markdown copy];
    }
    return self;
}
@end

@interface TweetQuickActionsProvider ()
@property (nonatomic, strong) TFNHUD* hud;
@end

static id BHTQuickObjectGetter(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) {
        return nil;
    }
    return ((id(*)(id, SEL))objc_msgSend)(object, selector);
}

static long long BHTQuickIntegerGetter(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) {
        return 0;
    }
    return ((long long (*)(id, SEL))objc_msgSend)(object, selector);
}

static NSString* BHTQuickString(id value) {
    if ([value isKindOfClass:NSURL.class]) {
        return [(NSURL*)value absoluteString];
    }
    return [BHTTweetQuickActionsFormatter normalizedTextFromValue:value];
}

static BOOL BHTQuickIconExists(NSString* imageName) {
    if (!imageName.length ||
        ![UIImage respondsToSelector:@selector(tfn_vectorImageExistsNamed:fitsSize:size:)]) {
        return NO;
    }
    CGSize size = CGSizeZero;
    return [UIImage tfn_vectorImageExistsNamed:imageName
                                      fitsSize:CGSizeMake(16.0, 16.0)
                                          size:&size];
}

static TFNActionItem* BHTQuickActionItem(NSString* title,
                                         NSString* imageName,
                                         void (^action)(void)) {
    Class itemClass = objc_getClass("TFNActionItem");
    if (!itemClass || !title.length || !action) {
        return nil;
    }
    if (BHTQuickIconExists(imageName) &&
        [itemClass respondsToSelector:@selector(actionItemWithTitle:imageName:action:)]) {
        return [itemClass actionItemWithTitle:title imageName:imageName action:action];
    }
    if ([itemClass respondsToSelector:@selector(actionItemWithTitle:action:)]) {
        return [itemClass actionItemWithTitle:title action:action];
    }
    return nil;
}

static Class BHTQuickMenuSheetClass(void) {
    Class sheetClass = objc_getClass("TFNMenuSheetViewController");
    if (!sheetClass ||
        ![sheetClass
            instancesRespondToSelector:@selector(initWithTitle:actionItems:)] ||
        ![sheetClass
            instancesRespondToSelector:@selector(
                                           tfnPresentedCustomPresentFromViewController:
                                                                              animated:
                                                                              completion:)]) {
        return Nil;
    }
    return sheetClass;
}

@implementation TweetQuickActionsProvider

- (BHTTweetQuickActionsContext*)contextForStatus:(id)status entityURL:(id)entityURL {
    @try {
        NSString* text = BHTQuickString(
            BHTQuickObjectGetter(status, @selector(plainTextSubject)));
        NSString* displayName = BHTQuickString(
            BHTQuickObjectGetter(status, @selector(shareableAuthorName)));
        NSString* handle = BHTNormalizedTwitterHandle(BHTQuickString(
            BHTQuickObjectGetter(status, @selector(shareableAuthorHandle))));
        long long statusID = BHTQuickIntegerGetter(status, @selector(statusID));

        NSString* nativeURL = BHTQuickString(
            BHTQuickObjectGetter(status, @selector(twitterURLForCopy)));
        NSString* suppliedURL = BHTQuickString(entityURL);
        NSString* sourceURL = nativeURL ?: suppliedURL;

        long long sourceStatusID = BHTTweetStatusIDFromURLString(sourceURL);
        if (!handle) {
            handle = BHTTweetHandleFromURLString(sourceURL);
        }
        if (statusID <= 0) {
            statusID = sourceStatusID;
        }

        NSString* selectedHost =
            [NSUserDefaults.standardUserDefaults objectForKey:@"sharing_domain"];
        NSString* URLString =
            BHTCanonicalTweetURLString(handle, statusID, selectedHost);
        if (!URLString && sourceStatusID > 0) {
            URLString = BHTCleanShareURLString(
                sourceURL, BHTEffectiveSharingHost(selectedHost), YES);
        }

        NSString* author =
            [BHTTweetQuickActionsFormatter authorWithName:displayName
                                                   handle:handle];
        NSString* markdown =
            [BHTTweetQuickActionsFormatter markdownWithText:text
                                                     author:author
                                                  URLString:URLString];
        if (!text.length && !author.length && !URLString.length && !markdown.length) {
            return nil;
        }

        return [[BHTTweetQuickActionsContext alloc] initWithText:text
                                                     displayName:displayName
                                                          handle:handle
                                                        statusID:statusID
                                                          author:author
                                                       URLString:URLString
                                                        markdown:markdown];
    } @catch (__unused NSException* exception) {
        return nil;
    }
}

- (void)copyString:(NSString*)value {
    if (!value.length) {
        return;
    }
    UIPasteboard.generalPasteboard.string = value;

    UIImpactFeedbackGenerator* feedback =
        [[UIImpactFeedbackGenerator alloc]
            initWithStyle:UIImpactFeedbackStyleLight];
    [feedback prepare];
    [feedback impactOccurred];

    Class hudClass = objc_getClass("TFNHUD");
    if (!hudClass ||
        ![hudClass instancesRespondToSelector:@selector(initWithText:)]) {
        return;
    }
    TFNHUD* hud = [[hudClass alloc]
        initWithText:[[BHTBundle sharedBundle]
                         localizedStringForKey:@"TWEET_QUICK_ACTIONS_COPIED"]];
    BOOL canHideAfterDelay =
        [hud respondsToSelector:@selector(hideAfterDelay:)];
    BOOL canHide = [hud respondsToSelector:@selector(hide)];
    if (!hud || ![hud respondsToSelector:@selector(show)] ||
        (!canHideAfterDelay && !canHide)) {
        return;
    }

    self.hud = hud;
    [hud show];
    if (canHideAfterDelay) {
        [hud hideAfterDelay:0.8];
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(0.8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           [hud hide];
                       });
    }
}

- (TFNActionItem*)copyItemWithTitleKey:(NSString*)titleKey
                             imageName:(NSString*)imageName
                                 value:(NSString*)value {
    __weak TweetQuickActionsProvider* weakSelf = self;
    TFNActionItem* item = BHTQuickActionItem(
        [[BHTBundle sharedBundle] localizedStringForKey:titleKey], imageName, ^{
            [weakSelf copyString:value];
        });
    if (!value.length) {
        if ([item respondsToSelector:@selector(setDisabled:)]) {
            [item setDisabled:YES];
        } else {
            return nil;
        }
    }
    return item;
}

- (void)presentContext:(BHTTweetQuickActionsContext*)context {
    Class sheetClass = BHTQuickMenuSheetClass();
    UIViewController* presenter = topMostController();
    if (!sheetClass || !presenter) {
        return;
    }

    NSMutableArray* items = [NSMutableArray array];
    NSArray* candidates = @[
        [self copyItemWithTitleKey:@"TWEET_QUICK_ACTIONS_COPY_TEXT"
                         imageName:@"news_stroke"
                             value:context.text]
            ?: NSNull.null,
        [self copyItemWithTitleKey:@"TWEET_QUICK_ACTIONS_COPY_LINK"
                         imageName:@"link"
                             value:context.URLString]
            ?: NSNull.null,
        [self copyItemWithTitleKey:@"TWEET_QUICK_ACTIONS_COPY_AUTHOR"
                         imageName:@"account"
                             value:context.author]
            ?: NSNull.null,
        [self copyItemWithTitleKey:@"TWEET_QUICK_ACTIONS_COPY_MARKDOWN"
                         imageName:@"copy_stroke"
                             value:context.markdown]
            ?: NSNull.null,
    ];
    for (id candidate in candidates) {
        if (candidate != NSNull.null) {
            [items addObject:candidate];
        }
    }
    if (items.count == 0) {
        return;
    }

    TFNMenuSheetViewController* sheet = [[sheetClass alloc]
        initWithTitle:[[BHTBundle sharedBundle]
                          localizedStringForKey:@"TWEET_QUICK_ACTIONS_MENU_TITLE"]
          actionItems:items.copy];
    [sheet tfnPresentedCustomPresentFromViewController:presenter
                                              animated:YES
                                            completion:nil];
}

- (TFNActionItem*)actionItemForStatus:(id)status entityURL:(id)entityURL {
    if (![BHTSettings boolForKey:@"tweet_quick_actions"] ||
        !BHTQuickMenuSheetClass()) {
        return nil;
    }

    BHTTweetQuickActionsContext* context =
        [self contextForStatus:status
                     entityURL:entityURL];
    if (!context) {
        return nil;
    }

    __weak TweetQuickActionsProvider* weakSelf = self;
    return BHTQuickActionItem(
        [[BHTBundle sharedBundle]
            localizedStringForKey:@"TWEET_QUICK_ACTIONS_MENU_TITLE"],
        @"copy_stroke", ^{
            [weakSelf presentContext:context];
        });
}

@end
