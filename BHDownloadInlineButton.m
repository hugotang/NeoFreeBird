//
//  BHDownloadInlineButton.m
//  NeoFreeBird, fixed for Twitter 10.94 / 10.94.1
//
//  Original author: BandarHelal at 09/04/2022
//  Modified by: actuallyaridan at 27/04/2025
//

#import "BHDownloadInlineButton.h"
#import <math.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Colours/Colours.h"
#import "BHTBundle/BHTBundle.h"

#pragma mark - Helpers
static inline UIViewController *BHTopMostController(void) {
    UIViewController *top = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

static char kHitTestEdgeInsetsKey;   // associated‑object key

// Convenience shim to invoke a superclass selector that isn’t visible at compile‑time
static void _bh_callSuperIfPossible(__unsafe_unretained id self,
                                    SEL sel,
                                    id  a1,
                                    NSUInteger a2,
                                    NSUInteger a3,
                                    BOOL a4,
                                    id  a5)
{
    struct objc_super sup = { .receiver = self, .super_class = class_getSuperclass(object_getClass(self)) };
    if (class_getInstanceMethod(sup.super_class, sel)) {
        ((void (*)(struct objc_super *, SEL, id, NSUInteger, NSUInteger, BOOL, id))objc_msgSendSuper)(&sup, sel, a1, a2, a3, a4, a5);
    }
}

static NSUInteger BHSelectorArgumentCount(SEL selector) {
    NSUInteger count = 0;
    const char *name = sel_getName(selector);
    while (*name) {
        if (*name == ':') count++;
        name++;
    }
    return count;
}

static Class kBHStyleButtonClass;

static Class BHStyleButtonClass(void) {
    return kBHStyleButtonClass;
}

static BOOL BHStyleRespondsToSelector(id target, SEL selector) {
    return target && [target respondsToSelector:selector];
}

static BOOL BHStyleBoolValue(id target, SEL selector, BOOL fallback) {
    if (BHStyleRespondsToSelector(target, selector)) {
        return ((BOOL (*)(id, SEL))objc_msgSend)(target, selector);
    }

    return fallback;
}

static double BHStyleDoubleValue(id target, SEL selector, double fallback) {
    if (BHStyleRespondsToSelector(target, selector)) {
        return ((double (*)(id, SEL))objc_msgSend)(target, selector);
    }

    return fallback;
}

static CGSize BHStyleSizeThatFits(id target, SEL selector, CGSize size, CGSize fallback) {
    if (BHStyleRespondsToSelector(target, selector)) {
        return ((CGSize (*)(id, SEL, CGSize))objc_msgSend)(target, selector, size);
    }

    return fallback;
}

static id BHStyleClassTarget(SEL selector) {
    Class styleButtonClass = BHStyleButtonClass();
    if ([styleButtonClass respondsToSelector:selector]) {
        return styleButtonClass;
    }

    return nil;
}

static NSUInteger BHStyleUnsignedIntegerValue(id target, SEL selector, NSUInteger fallback) {
    if (BHStyleRespondsToSelector(target, selector)) {
        return ((NSUInteger (*)(id, SEL))objc_msgSend)(target, selector);
    }

    return fallback;
}

static id BHStyleButton(NSUInteger actionType, NSUInteger options, id overrideSize, id account) {
    Class styleButtonClass = BHStyleButtonClass();
    if (!styleButtonClass) {
        return nil;
    }

    id button = nil;

    @try {
        SEL optionsInit = @selector(initWithOptions:overrideSize:account:);
        if ([styleButtonClass instancesRespondToSelector:optionsInit]) {
            button = ((id (*)(id, SEL, NSUInteger, id, id))objc_msgSend)([styleButtonClass alloc], optionsInit, options, overrideSize, account);
        }

        SEL inlineInit = @selector(initWithInlineActionType:options:overrideSize:account:);
        if (!button && [styleButtonClass instancesRespondToSelector:inlineInit]) {
            button = ((id (*)(id, SEL, NSUInteger, NSUInteger, id, id))objc_msgSend)([styleButtonClass alloc], inlineInit, actionType, options, overrideSize, account);
        }
    } @catch (__unused NSException *exception) {
        button = nil;
    }

    return button;
}

static id BHViewModelFromInlineDelegate(id delegate, id fallback) {
    SEL viewModelSelector = @selector(viewModel);
    if (BHStyleRespondsToSelector(delegate, viewModelSelector)) {
        id viewModel = ((id (*)(id, SEL))objc_msgSend)(delegate, viewModelSelector);
        if (viewModel) return viewModel;
    }

    SEL statusViewModelSelector = @selector(statusViewModel);
    if (BHStyleRespondsToSelector(delegate, statusViewModelSelector)) {
        id viewModel = ((id (*)(id, SEL))objc_msgSend)(delegate, statusViewModelSelector);
        if (viewModel) return viewModel;
    }

    return fallback;
}

static NSArray *BHMediaEntitiesFromViewModel(id viewModel) {
    SEL selector = @selector(representedMediaEntities);
    if (!BHStyleRespondsToSelector(viewModel, selector)) {
        return nil;
    }

    return ((NSArray *(*)(id, SEL))objc_msgSend)(viewModel, selector);
}

static UIImageView *BHImageViewInView(UIView *view) {
    if ([view isKindOfClass:UIImageView.class]) {
        return (UIImageView *)view;
    }

    for (UIView *subview in view.subviews) {
        UIImageView *imageView = BHImageViewInView(subview);
        if (imageView) {
            return imageView;
        }
    }

    return nil;
}

static UIColor *BHTintColorInView(UIView *view) {
    UIImageView *imageView = BHImageViewInView(view);
    return imageView.tintColor ?: view.tintColor;
}

static NSString *BHMethodTypeEncodingForSelector(SEL selector) {
    NSString *selectorName = NSStringFromSelector(selector);
    NSString *returnType = @"@";

    if ([selectorName hasPrefix:@"set"]) {
        returnType = @"v";
    } else if ([selectorName hasPrefix:@"is"] ||
               [selectorName hasPrefix:@"can"] ||
               [selectorName hasPrefix:@"has"] ||
               [selectorName hasPrefix:@"should"]) {
        returnType = @"B";
    } else if ([selectorName containsString:@"Insets"]) {
        returnType = [NSString stringWithUTF8String:@encode(UIEdgeInsets)];
    } else if ([selectorName containsString:@"Size"]) {
        returnType = [NSString stringWithUTF8String:@encode(CGSize)];
    } else if ([selectorName containsString:@"Width"] ||
               [selectorName containsString:@"Height"] ||
               [selectorName containsString:@"Inset"] ||
               [selectorName containsString:@"Spacing"]) {
        returnType = @"d";
    } else if ([selectorName containsString:@"Type"] ||
               [selectorName containsString:@"Count"] ||
               [selectorName containsString:@"Priority"] ||
               [selectorName containsString:@"Visibility"]) {
        returnType = @"Q";
    }

    NSMutableString *encoding = [NSMutableString stringWithFormat:@"%@@:", returnType];
    for (NSUInteger idx = 0; idx < BHSelectorArgumentCount(selector); idx++) {
        [encoding appendString:@"@"];
    }
    return encoding;
}

#pragma mark - BHDownloadInlineButton
@interface BHDownloadInlineButton () <BHDownloadDelegate>
@property (nonatomic, strong) JGProgressHUD *hud;
@property (nonatomic, assign) BOOL applyingCentreAdjustment;
@property (nonatomic, assign) BOOL hasAdjustedCentreX;
@property (nonatomic, assign) CGFloat adjustedCentreX;
@property (nonatomic, assign) CGSize adjustedCentreBoundsSize;
@property (nonatomic, weak) UIView *adjustedCentreSuperview;
@property (nonatomic, assign) CGSize styleImageSize;
@property (nonatomic, strong) id styleButton;
@end

@implementation BHDownloadInlineButton

#pragma mark ••• Class helpers
+ (CGSize)buttonImageSizeUsingViewModel:(id)viewModel
                                options:(NSUInteger)options
                      overrideButtonSize:(CGSize)overrideSize
                                 account:(id)account
{
    return CGSizeZero; // let host lay the image out
}

+ (void)setStyleButtonClass:(Class)styleButtonClass {
    kBHStyleButtonClass = styleButtonClass;
}

#pragma mark ••• Status updates
- (void)statusDidUpdate:(id)status
                options:(NSUInteger)options
     displayTextOptions:(NSUInteger)textOptions
               animated:(BOOL)animated
        featureSwitches:(id)featureSwitches
{
    self.viewModel = status;
    _bh_callSuperIfPossible(self, _cmd, status, options, textOptions, animated, featureSwitches);

    if (BHStyleRespondsToSelector(self.styleButton, _cmd)) {
        @try {
            ((void (*)(id, SEL, id, NSUInteger, NSUInteger, BOOL, id))objc_msgSend)(self.styleButton, _cmd, status, options, textOptions, animated, featureSwitches);
        } @catch (__unused NSException *exception) {
        }
    }

    [self _bh_applyTint];
}

- (void)statusDidUpdate:(id)status
                options:(NSUInteger)options
     displayTextOptions:(NSUInteger)textOptions
               animated:(BOOL)animated
{
    self.viewModel = status;
    _bh_callSuperIfPossible(self, _cmd, status, options, textOptions, animated, nil);

    if (BHStyleRespondsToSelector(self.styleButton, _cmd)) {
        @try {
            ((void (*)(id, SEL, id, NSUInteger, NSUInteger, BOOL))objc_msgSend)(self.styleButton, _cmd, status, options, textOptions, animated);
        } @catch (__unused NSException *exception) {
        }
    }

    [self _bh_applyTint];
}

- (void)_bh_applyTint {
    if ([self.styleButton isKindOfClass:UIView.class]) {
        UIColor *styleTintColor = BHTintColorInView((UIView *)self.styleButton);
        if (styleTintColor) {
            self.tintColor = styleTintColor;
            return;
        }
    }

    id dlg = self.delegate.delegate;
    if ([dlg isKindOfClass:objc_getClass("T1SlideshowStatusView")] ||
        [dlg isKindOfClass:objc_getClass("T1ImmersiveExploreCardView")] ||
        [dlg isKindOfClass:objc_getClass("T1TwitterSwift.ImmersiveExploreCardViewHelper")])
    {
        self.tintColor = UIColor.whiteColor;
    } else {
        self.tintColor = [UIColor colorFromHexString:@"6D6E70"];
    }
}

#pragma mark ••• Init
- (instancetype)initWithOptions:(NSUInteger)options overrideSize:(id)overrideSize account:(id)account {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.styleButton = BHStyleButton(0, options, overrideSize, account);
        [self _bh_commonInitWithInlineType:131];
    }
    return self;
}

- (instancetype)initWithInlineActionType:(NSUInteger)actionType
                                 options:(NSUInteger)options
                              overrideSize:(id)overrideSize
                                 account:(id)account
{
    if ((self = [super initWithFrame:CGRectZero])) {
        self.styleButton = BHStyleButton(actionType, options, overrideSize, account);
        [self _bh_commonInitWithInlineType:actionType];
    }
    return self;
}

- (void)_bh_commonInitWithInlineType:(NSUInteger)type {
    self.inlineActionType = type;
    self.tintColor        = [UIColor colorFromHexString:@"6D6E70"];
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    [self setImage:[UIImage systemImageNamed:@"arrow.down"] forState:UIControlStateNormal];
    [self addTarget:self action:@selector(DownloadHandler:) forControlEvents:UIControlEventTouchUpInside];
}

- (void)_bh_applyStyleImageSize:(CGSize)imageSize {
    if (CGSizeEqualToSize(imageSize, CGSizeZero) || CGSizeEqualToSize(imageSize, self.styleImageSize)) {
        return;
    }

    self.styleImageSize = imageSize;
    [self setNeedsLayout];

    if (@available(iOS 13.0, *)) {
        CGFloat pointSize = MIN(imageSize.width, imageSize.height);
        UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:pointSize];
        [self setPreferredSymbolConfiguration:configuration forImageInState:UIControlStateNormal];
    }
}

- (void)_bh_updateStyleLayout {
    if (![self.styleButton isKindOfClass:UIView.class] || CGRectIsEmpty(self.bounds)) {
        return;
    }

    UIView *styleView = (UIView *)self.styleButton;

    @try {
        styleView.bounds = self.bounds;
        styleView.frame = self.bounds;
        [styleView setNeedsLayout];
        [styleView layoutIfNeeded];

        UIImageView *styleImageView = BHImageViewInView(styleView);
        if (styleImageView && !CGSizeEqualToSize(styleImageView.bounds.size, CGSizeZero)) {
            [self _bh_applyStyleImageSize:styleImageView.bounds.size];
        }

        UIColor *styleTintColor = BHTintColorInView(styleView);
        if (styleTintColor) {
            self.tintColor = styleTintColor;
        }
    } @catch (__unused NSException *exception) {
    }
}

- (BOOL)_bh_adjustedCentreContextIsCurrent {
    return self.hasAdjustedCentreX &&
           self.adjustedCentreSuperview == self.superview &&
           CGSizeEqualToSize(self.adjustedCentreBoundsSize, self.bounds.size);
}

- (void)_bh_applyAdjustedCentreX:(CGFloat)centreX {
    if (fabs(self.center.x - centreX) < 0.5) {
        return;
    }

    self.applyingCentreAdjustment = YES;
    CGPoint centre = self.center;
    centre.x = centreX;
    self.center = centre;
    self.applyingCentreAdjustment = NO;
}

- (void)_bh_restoreAdjustedCentreIfNeeded {
    if (self.applyingCentreAdjustment || ![self _bh_adjustedCentreContextIsCurrent]) {
        return;
    }

    [self _bh_applyAdjustedCentreX:self.adjustedCentreX];
}

- (void)_bh_centerBetweenSiblingButtons {
    UIView *superview = self.superview;
    if (!superview || self.hidden || CGRectIsEmpty(self.frame)) {
        return;
    }

    NSMutableArray<UIView *> *siblings = [NSMutableArray array];
    for (UIView *subview in superview.subviews) {
        if (subview.hidden || subview.alpha == 0.0 || CGRectIsEmpty(subview.frame)) {
            continue;
        }

        if ([subview isKindOfClass:UIControl.class] || [NSStringFromClass(subview.class) containsString:@"Button"]) {
            [siblings addObject:subview];
        }
    }

    if (siblings.count < 3 || ![siblings containsObject:self]) {
        return;
    }

    [siblings sortUsingComparator:^NSComparisonResult(UIView *firstView, UIView *secondView) {
        CGFloat firstMidX = CGRectGetMidX(firstView.frame);
        CGFloat secondMidX = CGRectGetMidX(secondView.frame);

        if (firstMidX < secondMidX) {
            return NSOrderedAscending;
        }

        if (firstMidX > secondMidX) {
            return NSOrderedDescending;
        }

        return NSOrderedSame;
    }];

    NSUInteger index = [siblings indexOfObject:self];
    if (index == NSNotFound || index == 0 || index >= siblings.count - 1) {
        return;
    }

    UIView *leadingView = siblings[index - 1];
    UIView *trailingView = siblings[index + 1];
    CGFloat targetX = (CGRectGetMidX(leadingView.frame) + CGRectGetMidX(trailingView.frame)) / 2.0;

    self.hasAdjustedCentreX = YES;
    self.adjustedCentreX = targetX;
    self.adjustedCentreBoundsSize = self.bounds.size;
    self.adjustedCentreSuperview = superview;
    [self _bh_applyAdjustedCentreX:targetX];
}

- (void)layoutSubviews {
    [self _bh_updateStyleLayout];
    [super layoutSubviews];
    [self _bh_centerBetweenSiblingButtons];
}

- (void)setCenter:(CGPoint)center {
    [super setCenter:center];
    [self _bh_restoreAdjustedCentreIfNeeded];
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
    [self _bh_restoreAdjustedCentreIfNeeded];
}

- (CGRect)imageRectForContentRect:(CGRect)contentRect {
    if (!CGSizeEqualToSize(self.styleImageSize, CGSizeZero)) {
        CGSize imageSize = self.styleImageSize;
        return CGRectMake(CGRectGetMidX(contentRect) - imageSize.width / 2.0,
                          CGRectGetMidY(contentRect) - imageSize.height / 2.0,
                          imageSize.width,
                          imageSize.height);
    }

    return [super imageRectForContentRect:contentRect];
}

- (CGSize)intrinsicContentSize {
    return BHStyleRespondsToSelector(self.styleButton, _cmd) ? ((CGSize (*)(id, SEL))objc_msgSend)(self.styleButton, _cmd) : [super intrinsicContentSize];
}

- (CGSize)sizeThatFits:(CGSize)size {
    return BHStyleSizeThatFits(self.styleButton, _cmd, size, [super sizeThatFits:size]);
}

#pragma mark ••• Inline‑action metrics
- (double)extraWidth { return BHStyleDoubleValue(self.styleButton, _cmd, 0.0); }
+ (double)extraWidth { return BHStyleDoubleValue(BHStyleClassTarget(_cmd), _cmd, 0.0); }

- (BOOL)shouldShowCount { return NO; }
+ (BOOL)shouldShowCount { return NO; }

- (NSUInteger)visibility { return 1; }
+ (NSUInteger)visibility { return 1; }

- (void)setButtonAnimator:(id)buttonAnimator {
    _buttonAnimator = buttonAnimator;

    if (BHStyleRespondsToSelector(self.styleButton, _cmd)) {
        ((void (*)(id, SEL, id))objc_msgSend)(self.styleButton, _cmd, buttonAnimator);
    }
}

- (void)setDelegate:(T1StatusInlineActionsView *)delegate {
    _delegate = delegate;

    if (BHStyleRespondsToSelector(self.styleButton, _cmd)) {
        ((void (*)(id, SEL, id))objc_msgSend)(self.styleButton, _cmd, delegate);
    }
}

- (void)setDisplayType:(NSUInteger)displayType {
    _displayType = displayType;

    if (BHStyleRespondsToSelector(self.styleButton, _cmd)) {
        ((void (*)(id, SEL, NSUInteger))objc_msgSend)(self.styleButton, _cmd, displayType);
    }
}

- (void)setViewModel:(id)viewModel {
    _viewModel = viewModel;

    if (BHStyleRespondsToSelector(self.styleButton, _cmd)) {
        ((void (*)(id, SEL, id))objc_msgSend)(self.styleButton, _cmd, viewModel);
    }
}

// Twitter asks subclasses (+ class) for a custom glyph via this selector.
- (id)_t1_imageNamed:(id)name fitSize:(CGSize)size fillColor:(id)fill { return nil; }
+ (id)_t1_imageNamed:(id)name fitSize:(CGSize)size fillColor:(id)fill { return nil; }

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    NSMethodSignature *signature = [super methodSignatureForSelector:selector];
    if (signature) return signature;

    return [NSMethodSignature signatureWithObjCTypes:[BHMethodTypeEncodingForSelector(selector) UTF8String]];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    NSUInteger returnLength = invocation.methodSignature.methodReturnLength;
    if (returnLength == 0) return;

    void *zeroReturn = calloc(1, returnLength);
    [invocation setReturnValue:zeroReturn];
    free(zeroReturn);
}

#pragma mark ••• Hit‑testing tweaks
- (void)setTouchInsets:(UIEdgeInsets)insets {
    if (BHStyleRespondsToSelector(self.styleButton, _cmd)) {
        ((void (*)(id, SEL, UIEdgeInsets))objc_msgSend)(self.styleButton, _cmd, insets);
    }

    if ([self.delegate.delegate isKindOfClass:objc_getClass("T1StandardStatusInlineActionsViewAdapter")]) {
        [self setHitTestEdgeInsets:insets];
    }
}

- (void)setHitTestEdgeInsets:(UIEdgeInsets)insets {
    objc_setAssociatedObject(self, &kHitTestEdgeInsetsKey,
                             [NSValue value:&insets withObjCType:@encode(UIEdgeInsets)],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (UIEdgeInsets)hitTestEdgeInsets {
    NSValue *val = objc_getAssociatedObject(self, &kHitTestEdgeInsetsKey);
    if (val) { UIEdgeInsets e; [val getValue:&e]; return e; }
    return UIEdgeInsetsZero;
}

- (BOOL)pointInside:(CGPoint)pt withEvent:(UIEvent *)evt {
    if (UIEdgeInsetsEqualToEdgeInsets(self.hitTestEdgeInsets, UIEdgeInsetsZero) || !self.enabled || self.isHidden) {
        return [super pointInside:pt withEvent:evt];
    }
    return CGRectContainsPoint(UIEdgeInsetsInsetRect(self.bounds, self.hitTestEdgeInsets), pt);
}

#pragma mark ••• Download handler
- (void)DownloadHandler:(UIButton *)sender {
    @try {
        NSAttributedString *titleString = [[NSAttributedString alloc] initWithString:[[BHTBundle sharedBundle] localizedStringForKey:@"DOWNLOAD_MENU_TITLE"]
                                                                         attributes:@{ NSFontAttributeName : [[objc_getClass("TAEStandardFontGroup") sharedFontGroup] headline2BoldFont],
                                                                                       NSForegroundColorAttributeName : UIColor.labelColor }];
        TFNActiveTextItem *title = [[objc_getClass("TFNActiveTextItem") alloc] initWithTextModel:[[objc_getClass("TFNAttributedTextModel") alloc] initWithAttributedString:titleString] activeRanges:nil];

        NSMutableArray *actions      = [NSMutableArray arrayWithObject:title];
        NSMutableArray *innerActions = [NSMutableArray arrayWithObject:title];

        // HUD helpers
        void (^startHUD)(NSString *) = ^(NSString *key) {
            if ([BHTManager DirectSave]) return;
            self.hud = [JGProgressHUD progressHUDWithStyle:JGProgressHUDStyleDark];
            self.hud.textLabel.text = [[BHTBundle sharedBundle] localizedStringForKey:key];
            [self.hud showInView:BHTopMostController().view];
        };
        void (^dismissHUD)(void) = ^{ [self.hud dismiss]; };

        // Variant builders
        TFNActionItem* (^makeMP4Item)(NSURL *) = ^TFNActionItem*(NSURL *url) {
            return [objc_getClass("TFNActionItem") actionItemWithTitle:[BHTManager getVideoQuality:url.absoluteString]
                                                               imageName:@"arrow_down_circle_stroke" action:^{
                BHDownload *dwManager = [[BHDownload alloc] init];
                [dwManager setDelegate:self];
                [dwManager downloadFileWithURL:url];
                startHUD(@"PROGRESS_DOWNLOADING_STATUS_TITLE");
            }];
        };

        TFNActionItem* (^makeM3U8Item)(NSURL *) = ^TFNActionItem*(NSURL *url) {
            return [objc_getClass("TFNActionItem") actionItemWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"FFMPEG_DOWNLOAD_OPTION_TITLE"]
                                                               imageName:@"arrow_down_circle_stroke" action:^{
                startHUD(@"FETCHING_PROGRESS_TITLE");
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                    MediaInformation *info = [BHTManager getM3U8Information:url];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        dismissHUD();
                        TFNMenuSheetViewController *sheet = [BHTManager newFFmpegDownloadSheet:info downloadingURL:url progressView:self.hud];
                        [sheet tfnPresentedCustomPresentFromViewController:BHTopMostController() animated:YES completion:nil];
                    });
                });
            }];
        };

        // Media enumeration
        BOOL isSlideShow = [self.delegate.delegate isKindOfClass:objc_getClass("T1SlideshowStatusView")];
        if (isSlideShow) {
            T1SlideshowStatusView *slide = self.delegate.delegate;
            for (TFSTwitterEntityMediaVideoVariant *variant in slide.media.videoInfo.variants) {
                if ([variant.contentType isEqualToString:@"video/mp4"])          [actions addObject:makeMP4Item([NSURL URLWithString:variant.url])];
                if ([variant.contentType isEqualToString:@"application/x-mpegURL"]) [actions addObject:makeM3U8Item([NSURL URLWithString:variant.url])];
            }
        } else {
            id viewModel = BHViewModelFromInlineDelegate(self.delegate, self.viewModel);
            NSArray *mediaEntities = BHMediaEntitiesFromViewModel(viewModel);
            if (mediaEntities.count > 1) {
                [mediaEntities enumerateObjectsUsingBlock:^(TFSTwitterEntityMedia *obj, NSUInteger idx, BOOL *stop) {
                    if (obj.mediaType == 2 || obj.mediaType == 3) {
                        TFNActionItem *videoGroup = [objc_getClass("TFNActionItem") actionItemWithTitle:[NSString stringWithFormat:@"Video %lu", (unsigned long)idx + 1]
                                                                                           imageName:@"arrow_down_circle_stroke" action:^{
                            for (TFSTwitterEntityMediaVideoVariant *variant in obj.videoInfo.variants) {
                                if ([variant.contentType isEqualToString:@"video/mp4"])          [innerActions addObject:makeMP4Item([NSURL URLWithString:variant.url])];
                                if ([variant.contentType isEqualToString:@"application/x-mpegURL"]) [innerActions addObject:makeM3U8Item([NSURL URLWithString:variant.url])];
                            }
                            TFNMenuSheetViewController *inner = [[objc_getClass("TFNMenuSheetViewController") alloc] initWithActionItems:innerActions.copy];
                            [inner tfnPresentedCustomPresentFromViewController:BHTopMostController() animated:YES completion:nil];
                        }];
                        [actions addObject:videoGroup];
                    }
                }];
            } else if (mediaEntities.firstObject) {
                TFSTwitterEntityMedia *first = mediaEntities.firstObject;
                for (TFSTwitterEntityMediaVideoVariant *variant in first.videoInfo.variants) {
                    if ([variant.contentType isEqualToString:@"video/mp4"])          [actions addObject:makeMP4Item([NSURL URLWithString:variant.url])];
                    if ([variant.contentType isEqualToString:@"application/x-mpegURL"]) [actions addObject:makeM3U8Item([NSURL URLWithString:variant.url])];
                }
            }
        }

        TFNMenuSheetViewController *sheet = [[objc_getClass("TFNMenuSheetViewController") alloc] initWithActionItems:actions.copy];
        [sheet tfnPresentedCustomPresentFromViewController:BHTopMostController() animated:YES completion:nil];
    } @catch (__unused NSException *ex) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"ERROR_TITLE"]
                                                                       message:[[BHTBundle sharedBundle] localizedStringForKey:@"UNKNOWN_ERROR"]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"OK_BUTTON"] style:UIAlertActionStyleDefault handler:nil]];
        [BHTopMostController() presentViewController:alert animated:YES completion:nil];
    }
}

#pragma mark ••• BHDownloadDelegate
- (void)downloadProgress:(float)pct {
    self.hud.detailTextLabel.text = [BHTManager getDownloadingPersent:pct];
}

- (void)downloadDidFinish:(NSURL *)tmpURL Filename:(NSString *)name {
    NSString *doc = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSURL *dst = [[NSURL fileURLWithPath:doc]
                  URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4", NSUUID.UUID.UUIDString]];

    [[NSFileManager defaultManager] moveItemAtURL:tmpURL toURL:dst error:nil];

    if (![BHTManager DirectSave]) {
        [self.hud dismiss];
        [BHTManager showSaveVC:dst];
    } else {
        if (@available(iOS 10.0, *)) {
            UINotificationFeedbackGenerator *g = [UINotificationFeedbackGenerator new];
            [g prepare];
            [g notificationOccurred:UINotificationFeedbackTypeSuccess];
        }
        [BHTManager save:dst];
    }
}

- (void)downloadDidFailureWithError:(NSError *)error {
    [self.hud dismiss];
    if (!error) return;

    UIAlertController *a = [UIAlertController alertControllerWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"ERROR_TITLE"]
                                                               message:error.localizedDescription
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"OK_BUTTON"]
                                          style:UIAlertActionStyleDefault
                                        handler:nil]];
    [BHTopMostController() presentViewController:a animated:YES completion:nil];

    if (@available(iOS 10.0, *)) {
        UINotificationFeedbackGenerator *g = [UINotificationFeedbackGenerator new];
        [g prepare];
        [g notificationOccurred:UINotificationFeedbackTypeError];
    }
}

#pragma mark ••• Required by Twitter runtime
- (BOOL)enabled                { return YES; }
- (NSString *)actionSheetTitle { return @"BHDownload"; }
- (NSUInteger)inlineActionType { return self->_inlineActionType; }
@end
