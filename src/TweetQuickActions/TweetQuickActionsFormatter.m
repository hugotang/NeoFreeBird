#import "TweetQuickActionsFormatter.h"
#import "Core/BHTShareURL.h"

@implementation BHTTweetQuickActionsFormatter

+ (NSString*)normalizedTextFromValue:(id)value {
    NSString* text = nil;
    if ([value isKindOfClass:NSString.class]) {
        text = value;
    } else if ([value isKindOfClass:NSAttributedString.class]) {
        text = [value string];
    }
    text = [text stringByTrimmingCharactersInSet:
                     NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return text.length > 0 ? text : nil;
}

+ (NSString*)authorWithName:(NSString*)name handle:(NSString*)handle {
    NSString* cleanName = [self normalizedTextFromValue:name];
    NSString* cleanHandle = BHTNormalizedTwitterHandle(handle);
    if (cleanName && cleanHandle) {
        return [NSString stringWithFormat:@"%@ (@%@)", cleanName, cleanHandle];
    }
    if (cleanHandle) {
        return [@"@" stringByAppendingString:cleanHandle];
    }
    return cleanName;
}

+ (NSString*)escapedMarkdownLabel:(NSString*)label {
    NSString* escaped = [label stringByReplacingOccurrencesOfString:@"\\"
                                                         withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"["
                                                 withString:@"\\["];
    return [escaped stringByReplacingOccurrencesOfString:@"]"
                                              withString:@"\\]"];
}

+ (NSString*)markdownWithText:(NSString*)text
                       author:(NSString*)author
                    URLString:(NSString*)URLString {
    NSString* body = [self normalizedTextFromValue:text];
    NSString* label = [self normalizedTextFromValue:author];
    NSString* link = [self normalizedTextFromValue:URLString];

    NSString* quote = nil;
    if (body) {
        NSMutableArray<NSString*>* lines = [NSMutableArray array];
        for (NSString* line in [body componentsSeparatedByString:@"\n"]) {
            [lines addObject:line.length > 0
                                 ? [NSString stringWithFormat:@"> %@", line]
                                 : @">"];
        }
        quote = [lines componentsJoinedByString:@"\n"];
    }

    NSString* attribution = nil;
    if (label && link) {
        attribution = [NSString
            stringWithFormat:@"— [%@](%@)", [self escapedMarkdownLabel:label], link];
    } else if (label) {
        attribution = [@"— " stringByAppendingString:label];
    } else if (link) {
        attribution = [@"— " stringByAppendingString:link];
    }

    if (quote && attribution) {
        return [NSString stringWithFormat:@"%@\n\n%@", quote, attribution];
    }
    return quote ?: attribution;
}

@end
