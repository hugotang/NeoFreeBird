#import "BHTShareURL.h"

static NSString* BHTTrimmedString(NSString* value) {
    if (![value isKindOfClass:NSString.class]) {
        return nil;
    }
    NSString* trimmed =
        [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length > 0 ? trimmed : nil;
}

NSString* BHTEffectiveSharingHost(NSString* selectedHost) {
    NSString* candidate = BHTTrimmedString(selectedHost);
    if (!candidate) {
        return @"x.com";
    }

    NSURLComponents* components = [NSURLComponents componentsWithString:candidate];
    if (!components.host.length) {
        components = [NSURLComponents
            componentsWithString:[@"https://" stringByAppendingString:candidate]];
    }
    NSString* host = BHTTrimmedString(components.host.lowercaseString);
    return host ?: @"x.com";
}

NSString* BHTNormalizedTwitterHandle(NSString* handle) {
    NSString* normalized = BHTTrimmedString(handle);
    while ([normalized hasPrefix:@"@"]) {
        normalized = [normalized substringFromIndex:1];
    }
    normalized = BHTTrimmedString(normalized);
    return normalized.length > 0 ? normalized : nil;
}

NSString* BHTCleanShareURLString(NSString* urlString,
                                 NSString* selectedHost,
                                 BOOL removeFragment) {
    NSString* source = BHTTrimmedString(urlString);
    if (!source) {
        return nil;
    }

    NSURLComponents* components = [NSURLComponents componentsWithString:source];
    if (!components || !components.host.length) {
        return source;
    }

    NSMutableArray<NSURLQueryItem*>* safeItems = [NSMutableArray array];
    for (NSURLQueryItem* item in components.queryItems ?: @[]) {
        if (![item.name isEqualToString:@"s"] &&
            ![item.name isEqualToString:@"t"]) {
            [safeItems addObject:item];
        }
    }
    components.queryItems = safeItems.count > 0 ? safeItems : nil;
    if (selectedHost.length > 0) {
        components.host = BHTEffectiveSharingHost(selectedHost);
    }
    if (removeFragment) {
        components.fragment = nil;
    }
    return components.URL.absoluteString ?: source;
}

NSString* BHTCanonicalTweetURLString(NSString* handle,
                                     long long statusID,
                                     NSString* selectedHost) {
    NSString* normalized = BHTNormalizedTwitterHandle(handle);
    if (!normalized || statusID <= 0) {
        return nil;
    }
    return [NSString stringWithFormat:@"https://%@/%@/status/%lld",
                                      BHTEffectiveSharingHost(selectedHost),
                                      normalized, statusID];
}

static NSArray<NSString*>* BHTTweetURLPathComponents(NSString* urlString) {
    NSURLComponents* components = [NSURLComponents componentsWithString:urlString];
    NSString* scheme = components.scheme.lowercaseString;
    if (!components.host.length ||
        (![scheme isEqualToString:@"https"] &&
         ![scheme isEqualToString:@"http"])) {
        return @[];
    }
    NSMutableArray<NSString*>* path = [NSMutableArray array];
    for (NSString* component in components.path.pathComponents ?: @[]) {
        if (component.length > 0 && ![component isEqualToString:@"/"]) {
            [path addObject:component];
        }
    }
    return path;
}

NSString* BHTTweetHandleFromURLString(NSString* urlString) {
    NSArray<NSString*>* path = BHTTweetURLPathComponents(urlString);
    NSUInteger statusIndex = [path indexOfObject:@"status"];
    if (statusIndex == NSNotFound || statusIndex == 0) {
        return nil;
    }
    NSString* handle = BHTNormalizedTwitterHandle(path[statusIndex - 1]);
    if ([handle isEqualToString:@"web"] || [handle isEqualToString:@"i"]) {
        return nil;
    }
    return handle;
}

long long BHTTweetStatusIDFromURLString(NSString* urlString) {
    NSArray<NSString*>* path = BHTTweetURLPathComponents(urlString);
    NSUInteger statusIndex = [path indexOfObject:@"status"];
    if (statusIndex == NSNotFound || statusIndex + 1 >= path.count) {
        return 0;
    }
    NSString* value = path[statusIndex + 1];
    if (value.length == 0 ||
        [value rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet]
                .location != NSNotFound) {
        return 0;
    }
    return value.longLongValue > 0 ? value.longLongValue : 0;
}
