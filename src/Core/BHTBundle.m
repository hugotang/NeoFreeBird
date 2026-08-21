//
//  BHTBundle.m
//  BHTwitter
//
//  Created by BandarHelal on 07/08/2022.
//

#import "BHTBundle.h"

@interface BHTBundle ()
@property (nonatomic, strong) NSBundle* mainBundle;
@property (nonatomic, strong) NSBundle* stringsBundle;
@end

@implementation BHTBundle
+ (instancetype)sharedBundle {
    static BHTBundle* sharedBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSFileManager* fileManager = [NSFileManager defaultManager];
        NSURL* bundlePath = nil;
        NSString* name = @TWEAK_NAME_STRING;

        for (NSString* prefix in @[ @"", @"/var/jb" ]) {
            NSString* path = [NSString
                stringWithFormat:@"%@/Library/Application Support/%@/%@.bundle",
                                 prefix, name, name];
            if ([fileManager fileExistsAtPath:path]) {
                bundlePath = [NSURL fileURLWithPath:path];
                break;
            }
        }

        if (!bundlePath) {
            bundlePath = [[NSBundle mainBundle] URLForResource:name
                                                 withExtension:@"bundle"];
        }

        sharedBundle = [[self alloc] initWithBundlePath:bundlePath];
    });
    return sharedBundle;
}
- (instancetype)initWithBundlePath:(NSURL*)bundlePath {
    if (self = [super init]) {
        self.mainBundle = [NSBundle bundleWithPath:[bundlePath path]];

        NSURL* strings =
            [self.mainBundle URLForResource:@TWEAK_STRINGS_BUNDLE_STRING
                              withExtension:@"bundle"];
        self.stringsBundle =
            strings ? [NSBundle bundleWithURL:strings] : self.mainBundle;
    }

    return self;
}

- (NSString*)localizedStringForKey:(NSString*)key {
    return [self.stringsBundle localizedStringForKey:key value:key table:nil];
}

// Fetches one of Twitter's own strings, reusing the app's translations for
// every language. These flow through the terminology rename hook like any app
// string.
- (NSString*)localizedTwitterStringForKey:(NSString*)key {
    static NSBundle* twitterBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString* path =
            [[NSBundle mainBundle] pathForResource:@"Localization_Localization"
                                            ofType:@"bundle"];
        twitterBundle =
            path ? [NSBundle bundleWithPath:path] : [NSBundle mainBundle];
    });
    return [twitterBundle localizedStringForKey:key value:key table:nil];
}
- (NSURL*)pathForFile:(NSString*)fileName {
    return [self.mainBundle URLForResource:fileName withExtension:nil];
}
@end
