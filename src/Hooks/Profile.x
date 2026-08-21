//
//  Profile.x
//  NeoFreeBird
//

#import "HookHelpers.h"

// MARK: - Selectable profile text

// The profile's fields are custom-drawn (TFNAttributedTextView, plain labels
// and buttons), so none of them offer native text selection. A long-press lays
// an invisible UITextView carrying the field's text over it, adding selection
// while the field keeps rendering itself; a truncated bio is first expanded
// through the app's own toggle. The website button keeps its own native
// long-press menu.

static char kSelectableFieldKey;
static char kActiveOverlayKey;

static NSAttributedString* FieldAttributedText(UIView* field) {
    NSAttributedString* text = nil;

    if ([field respondsToSelector:@selector(textModel)]) {
        text = ((TFNAttributedTextView*)field).textModel.attributedString;
    } else if ([field isKindOfClass:[UIButton class]]) {
        text = ((UIButton*)field).currentAttributedTitle;
    } else if ([field isKindOfClass:[UILabel class]]) {
        UILabel* label = (UILabel*)field;
        text = label.attributedText;
        if (!text.length && label.text.length) {
            text = [[NSAttributedString alloc] initWithString:label.text
                                                   attributes:@{
                                                       NSFontAttributeName:
                                                           label.font
                                                   }];
        }
    }

    if (!text.length) {
        return nil;
    }

    // TFN's strings are CoreText-flavoured and crash TextKit as they stand, so
    // they go through Twitter's own converter first.
    return [text respondsToSelector:@selector(tfnUIKitSafeAttributedString)]
               ? [text tfnUIKitSafeAttributedString]
               : [[NSAttributedString alloc] initWithString:text.string];
}

// The two engines split TFN's padded line height differently around the first
// baseline, and not by any fixed ratio — so both placements are measured from
// their live layouts and the overlay shifted by the difference.
static CGFloat CoreTextFirstBaseline(UIView* field) {
    if (![field respondsToSelector:@selector(textModel)]) {
        return NAN;
    }

    TFNAttributedTextModel* model = ((TFNAttributedTextView*)field).textModel;
    // The same refit the renderer performs before every draw, so the measured
    // box is the one on screen.
    [model fitToSize:field.bounds.size];

    CTFrameRef frame = model.coreTextFrame;
    CGPathRef path = frame ? CTFrameGetPath(frame) : NULL;
    if (!path) {
        return NAN;
    }

    CGRect box = CGPathGetBoundingBox(path);
    if (fabs(CGRectGetHeight(box) - CGRectGetHeight(field.bounds)) > 1.0) {
        return NAN;
    }

    CGPoint origin = CGPointZero;
    CTFrameGetLineOrigins(frame, CFRangeMake(0, 1), &origin);
    return CGRectGetMaxY(box) - origin.y;
}

static CGFloat TextKitFirstBaseline(UITextView* overlay) {
    NSLayoutManager* layout = overlay.layoutManager;
    [layout ensureLayoutForTextContainer:overlay.textContainer];
    CGRect fragment = [layout lineFragmentRectForGlyphAtIndex:0
                                              effectiveRange:NULL];
    return CGRectGetMinY(fragment) + [layout locationForGlyphAtIndex:0].y;
}

// Only a button's title is stood in for, so its bullet icon has to be left
// alone — both when placing the overlay and when hiding what it covers.
static UIView* FieldTextView(UIView* field) {
    if ([field isKindOfClass:[UIButton class]]) {
        UILabel* title = ((UIButton*)field).titleLabel;
        if (title && !CGRectIsEmpty(title.frame)) {
            return title;
        }
    }
    return field;
}

static CGRect FieldTextFrame(UIView* field) {
    UIView* textView = FieldTextView(field);
    return [textView convertRect:textView.bounds toView:field.superview];
}

@interface BHTFieldSelectionTextView : UITextView
@property (weak, nonatomic) UIView* sourceField;
@property (strong, nonatomic) UITapGestureRecognizer* outsideTapRecognizer;
@end

@implementation BHTFieldSelectionTextView

+ (void)handleFieldLongPress:(UILongPressGestureRecognizer*)gesture {
    UIView* field = gesture.view;
    if (gesture.state != UIGestureRecognizerStateBegan ||
        objc_getAssociatedObject(field, &kActiveOverlayKey)) {
        return;
    }

    NSAttributedString* text = FieldAttributedText(field);
    if (!text.length) {
        return;
    }

    CGRect frame = FieldTextFrame(field);

    // An explicit TextKit 1 stack, the same way Twitter builds its own
    // selectable tweet body, so the layout manager can be measured.
    NSTextStorage* storage = [[NSTextStorage alloc] init];
    NSLayoutManager* layout = [[NSLayoutManager alloc] init];
    [storage addLayoutManager:layout];
    NSTextContainer* container =
        [[NSTextContainer alloc] initWithSize:CGSizeZero];
    [layout addTextContainer:container];

    BHTFieldSelectionTextView* overlay =
        [[BHTFieldSelectionTextView alloc] initWithFrame:frame
                                           textContainer:container];
    overlay.sourceField = field;
    overlay.editable = NO;
    overlay.scrollEnabled = NO;
    overlay.clipsToBounds = NO;
    overlay.backgroundColor = UIColor.clearColor;
    overlay.textContainerInset = UIEdgeInsetsZero;
    overlay.textContainer.lineFragmentPadding = 0.0;
    overlay.attributedText = text;

    CGSize fitted = [overlay
        sizeThatFits:CGSizeMake(CGRectGetWidth(frame), CGFLOAT_MAX)];
    if (fitted.height > CGRectGetHeight(frame) + 10.0) {
        for (UIView* view = field.superview; view; view = view.superview) {
            if ([view isKindOfClass:%c(T1ProfileUserInfoView)]) {
                ((T1ProfileUserInfoView*)view).bioExpanded = YES;
                [view layoutIfNeeded];
                frame = FieldTextFrame(field);
                break;
            }
        }
    }

    CGFloat fieldBaseline = CoreTextFirstBaseline(field);
    CGFloat overlayBaseline = TextKitFirstBaseline(overlay);
    if (!isnan(fieldBaseline) && !isnan(overlayBaseline)) {
        frame.origin.y -= overlayBaseline - fieldBaseline;
    }
    overlay.frame = frame;

    NSMutableAttributedString* ghost = [text mutableCopy];
    [ghost addAttribute:NSForegroundColorAttributeName
                  value:UIColor.clearColor
                  range:NSMakeRange(0, ghost.length)];
    overlay.attributedText = ghost;

    [field.superview addSubview:overlay];
    objc_setAssociatedObject(field, &kActiveOverlayKey, overlay,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // Taps land on their target as usual; the recogniser only ends the
    // selection when they fall outside the overlay.
    UITapGestureRecognizer* outsideTap = [[UITapGestureRecognizer alloc]
        initWithTarget:overlay
                action:@selector(handleOutsideTap:)];
    outsideTap.cancelsTouchesInView = NO;
    [field.window addGestureRecognizer:outsideTap];
    overlay.outsideTapRecognizer = outsideTap;

    [overlay becomeFirstResponder];
    [overlay selectAll:nil];
}

- (void)endFieldSelection {
    objc_setAssociatedObject(self.sourceField, &kActiveOverlayKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    self.sourceField = nil;
    [self.outsideTapRecognizer.view
        removeGestureRecognizer:self.outsideTapRecognizer];
    self.outsideTapRecognizer = nil;
    [self removeFromSuperview];
}

- (BOOL)resignFirstResponder {
    BOOL resigned = [super resignFirstResponder];
    if (resigned) {
        [self endFieldSelection];
    }
    return resigned;
}

// Copies plain text, so the invisible overlay's clear colour can't ride along
// into rich-text pastes.
- (void)copy:(id)sender {
    UIPasteboard.generalPasteboard.string =
        [self.textStorage.string substringWithRange:self.selectedRange];
}

- (void)handleOutsideTap:(UITapGestureRecognizer*)gesture {
    if (![self pointInside:[gesture locationInView:self] withEvent:nil]) {
        [self resignFirstResponder];
    }
}

@end

static void MakeFieldSelectable(UIView* field) {
    if (!field) {
        return;
    }

    // The header labels ship with touches off and reassert it on every user
    // update, so this is applied on each pass rather than once.
    field.userInteractionEnabled = YES;

    if (objc_getAssociatedObject(field, &kSelectableFieldKey)) {
        return;
    }
    objc_setAssociatedObject(field, &kSelectableFieldKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [field addGestureRecognizer:
               [[UILongPressGestureRecognizer alloc]
                   initWithTarget:[BHTFieldSelectionTextView class]
                           action:@selector(handleFieldLongPress:)]];
}

%hook T1ProfileUserInfoView

// Builds the bio and translated-bio views.
- (id)_t1_buildBioLabelWithAccessibilityIdentifier:(id)identifier {
    UIView* label = %orig;
    MakeFieldSelectable(label);
    return label;
}

// Titles the bullet-pointed rows; the location is only filled in here, so the
// button has no text at the time its getter runs.
- (void)_t1_refreshBulletpointButton:(UIButton*)button
                           withTitle:(NSString*)title
                               image:(NSString*)imageName
                            linkable:(BOOL)linkable
                       invisibleLink:(BOOL)invisibleLink
                 accessibilityFormat:(NSString*)accessibilityFormat {
    %orig;

    if (button != self.locationButton) {
        return;
    }

    // A disabled control never sees a touch, and the row has no action of its
    // own; the icon is set for every state, so only the highlight has to go.
    button.enabled = YES;
    button.adjustsImageWhenHighlighted = NO;
    MakeFieldSelectable(button);
}

%end

%hook T1ProfileSummaryView

- (void)_t1_updatePropertiesForFullNameLabel:(UIView*)fullNameLabel
                               subtitleLabel:(UIView*)subtitleLabel
                                  atPosition:(NSUInteger)position {
    %orig;
    MakeFieldSelectable(fullNameLabel);
    MakeFieldSelectable(subtitleLabel);
}

// MARK: - Hide premium offer

- (BOOL)shouldShowGetVerifiedButton {
    return [BHTSettings boolForKey:@"hide_premium_offer"] ? NO : %orig;
}

%end

// MARK: - Show unrounded follower/following counts

%hook T1ProfileFriendsFollowingViewModel

- (id)_t1_followCountTextWithLabel:(__unsafe_unretained id)label
                     singularLabel:(__unsafe_unretained id)singularLabel
                             count:(NSNumber*)count
                       highlighted:(BOOL)highlighted {
    id original = %orig;

    if (![count isKindOfClass:[NSNumber class]] ||
        ![original isKindOfClass:[NSAttributedString class]]) {
        return original;
    }

    NSString* abbreviated = [count tfs_twitterAbbreviated];
    NSNumberFormatter* formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    NSString* fullCount = [formatter stringFromNumber:count];

    if (!abbreviated.length || !fullCount.length || [abbreviated isEqualToString:fullCount]) {
        return original;
    }

    NSRange range = [[original string] rangeOfString:abbreviated];
    if (range.location == NSNotFound) {
        return original;
    }

    NSMutableAttributedString* expanded = [original mutableCopy];
    [expanded replaceCharactersInRange:range withString:fullCount];
    return [expanded copy];
}

%end
