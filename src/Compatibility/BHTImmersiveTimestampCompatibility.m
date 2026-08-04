#import "BHTImmersiveTimestampCompatibility.h"

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "Core/BHTSettings.h"

static const NSUInteger BHTTimestampMaximumVisitedViews = 100;

typedef void (*BHTLayoutSubviewsIMP)(UIView*, SEL);

static BHTLayoutSubviewsIMP BHTOriginalImmersiveCardLayoutSubviews;

static BOOL BHTLooksLikeTimestamp(NSString* text) {
    if (text.length == 0) {
        return NO;
    }

    static NSRegularExpression* expression;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString* pattern =
            @"^\\s*[0-9]{1,2}(?::[0-9]{2}){1,2}\\s*/\\s*"
             @"[0-9]{1,2}(?::[0-9]{2}){1,2}\\s*$";
        expression = [NSRegularExpression
            regularExpressionWithPattern:pattern
                                  options:0
                                    error:nil];
    });

    NSRange range = NSMakeRange(0, text.length);
    return [expression firstMatchInString:text options:0 range:range] != nil;
}

static UILabel* BHTFindTimestampLabel(UIView* rootView) {
    NSMutableArray<UIView*>* pending =
        [NSMutableArray arrayWithObject:rootView];
    NSUInteger visited = 0;

    while (pending.count > 0 &&
           visited < BHTTimestampMaximumVisitedViews) {
        UIView* view = pending.lastObject;
        [pending removeLastObject];
        visited++;

        if ([view isKindOfClass:[UILabel class]] &&
            BHTLooksLikeTimestamp(((UILabel*)view).text)) {
            return (UILabel*)view;
        }

        [pending addObjectsFromArray:view.subviews];
    }

    return nil;
}

static void BHTStyleTimestampLabel(UILabel* label) {
    label.font = [UIFont systemFontOfSize:14.0];
    label.textColor = UIColor.whiteColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.5];
    [label sizeToFit];

    CGRect frame = CGRectInset(label.frame, -2.0, -6.0);
    if (frame.size.height < 22.0) {
        CGFloat delta = 22.0 - frame.size.height;
        frame.origin.y -= delta / 2.0;
        frame.size.height = 22.0;
    }

    label.frame = frame;
    label.layer.cornerRadius = frame.size.height / 2.0;
    label.layer.masksToBounds = YES;
}

static void BHTImmersiveCardLayoutSubviews(UIView* self, SEL selector) {
    if (BHTOriginalImmersiveCardLayoutSubviews) {
        BHTOriginalImmersiveCardLayoutSubviews(self, selector);
    }

    if (![BHTSettings boolForKey:@"restore_video_timestamp"]) {
        return;
    }

    UILabel* timestampLabel = BHTFindTimestampLabel(self);
    if (timestampLabel) {
        BHTStyleTimestampLabel(timestampLabel);
    }
}

static Class BHTImmersiveCardClass(void) {
    Class cardClass = NSClassFromString(@"T1TwitterSwift.ImmersiveCardView");
    return cardClass ?:
        objc_getClass("_TtC14T1TwitterSwift17ImmersiveCardView");
}

void BHTInstallImmersiveTimestampCompatibility(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cardClass = BHTImmersiveCardClass();
        SEL selector = @selector(layoutSubviews);
        if (!cardClass || !class_getInstanceMethod(cardClass, selector)) {
            return;
        }

        MSHookMessageEx(cardClass, selector,
                        (IMP)&BHTImmersiveCardLayoutSubviews,
                        (IMP*)&BHTOriginalImmersiveCardLayoutSubviews);
    });
}
