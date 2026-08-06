//
//  MediaDownloads.x
//  NeoFreeBird
//

#import "HookHelpers.h"
#import "TweetQuickActions/TweetQuickActionsProvider.h"

// MARK: - DM video download

// The DM UI is Swift now: media messages live in DMConversation.MessageAttachmentView,
// which hosts a shared TweetMediaAttachments media view exposing its models through
// -inlineMediaInfos. Collect the entities from whichever descendant carries them.
static NSArray* DMVideoEntities(UIView* attachmentView) {
    NSMutableArray* entities = [NSMutableArray new];

    EnumerateSubviewsRecursively(attachmentView, ^(UIView* view) {
        if (![view respondsToSelector:@selector(inlineMediaInfos)]) {
            return;
        }

        for (TFSTwitterMediaInfo* info in
             [(_TtC21TweetMediaAttachments14MultiMediaView*)view inlineMediaInfos]) {
            TFSTwitterEntityMedia* media = info.mediaEntity;
            if (media.videoInfo.variants.count > 0) {
                [entities addObject:media];
            }
        }
    });

    return [entities copy];
}

%hook _TtC14DMConversation21MessageAttachmentView
%property (nonatomic, strong) UIContextMenuInteraction* downloadMenuInteraction;
%property (nonatomic, strong) DownloadInlineButton* downloadHandler;
- (void)layoutSubviews {
    %orig;

    if ([BHTSettings boolForKey:@"download_videos"] && self.downloadMenuInteraction == nil) {
        self.downloadMenuInteraction = [[UIContextMenuInteraction alloc] initWithDelegate:self];
        [self addInteraction:self.downloadMenuInteraction];
    }
}
%new
- (UIContextMenuConfiguration*)contextMenuInteraction:(UIContextMenuInteraction*)interaction
                       configurationForMenuAtLocation:(CGPoint)location {
    NSArray* videoEntities = DMVideoEntities(self);
    if (videoEntities.count == 0) {
        return nil;
    }

    return [UIContextMenuConfiguration
        configurationWithIdentifier:nil
                    previewProvider:nil
                     actionProvider:^UIMenu* _Nullable(
                         NSArray<UIMenuElement*>* _Nonnull suggestedActions) {
                         UIAction* saveAction = [UIAction
                             actionWithTitle:
                                 [[BHTBundle sharedBundle]
                                     localizedTwitterStringForKey:@"DOWNLOAD_ACTIVITY_VIEW_LABEL"]
                                       image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                                  identifier:nil
                                     handler:^(__kindof UIAction* _Nonnull action) {
                                         if (self.downloadHandler == nil) {
                                             self.downloadHandler = [%c(DownloadInlineButton) new];
                                         }
                                         [self.downloadHandler
                                             presentDownloadOptionsForMediaEntities:videoEntities];
                                     }];
                         return [UIMenu menuWithTitle:@"" children:@[saveAction]];
                     }];
}
%end

// The older status-based DM renderer still ships beside the Swift DM UI in
// Twitter 12.14. Keep it as a capability-checked fallback and feed the entity
// into the same downloader used by the modern path.
static char LegacyDMDownloadInteractionKey;
static char LegacyDMDownloadHandlerKey;

static id LegacyDMObjectForSelector(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) {
        return nil;
    }

    return ((id(*)(id, SEL))objc_msgSend)(object, selector);
}

static UIView* LegacyDMVisibleMediaView(id statusView) {
    id view = LegacyDMObjectForSelector(
        statusView, NSSelectorFromString(@"visibleMediaForwardView"));
    return [view isKindOfClass:UIView.class] ? view : nil;
}

static TFSTwitterEntityMedia* LegacyDMVideoEntity(id statusView) {
    id inlineMedia = LegacyDMObjectForSelector(
        statusView, NSSelectorFromString(@"inlineMedia"));
    id viewModel = LegacyDMObjectForSelector(
        inlineMedia, NSSelectorFromString(@"inlineMediaViewModel"));
    if (!viewModel) {
        viewModel = LegacyDMObjectForSelector(inlineMedia, @selector(viewModel));
    }

    if (!viewModel) {
        UIView* visibleView = LegacyDMVisibleMediaView(statusView);
        Class inlineMediaViewClass = objc_getClass("T1InlineMediaView");
        if (visibleView && inlineMediaViewClass) {
            __block id visibleViewModel = nil;
            EnumerateSubviewsRecursively(visibleView, ^(UIView* currentView) {
                if (!visibleViewModel &&
                    [currentView isKindOfClass:inlineMediaViewClass]) {
                    visibleViewModel = LegacyDMObjectForSelector(
                        currentView, @selector(viewModel));
                }
            });
            viewModel = visibleViewModel;
        }
    }

    id producer = LegacyDMObjectForSelector(
        viewModel, NSSelectorFromString(@"playerSessionProducer"));
    id session = LegacyDMObjectForSelector(
        producer, NSSelectorFromString(@"sessionProducible"));
    id mediaEntity = LegacyDMObjectForSelector(
        session, NSSelectorFromString(@"mediaEntity"));

    Class mediaClass = objc_getClass("TFSTwitterEntityMedia");
    if (!mediaClass || ![mediaEntity isKindOfClass:mediaClass]) {
        return nil;
    }

    id videoInfo = LegacyDMObjectForSelector(mediaEntity, @selector(videoInfo));
    NSArray* variants = LegacyDMObjectForSelector(videoInfo, @selector(variants));
    return [variants isKindOfClass:NSArray.class] && variants.count > 0
               ? mediaEntity
               : nil;
}

static void InstallLegacyDMDownloadInteraction(id statusView) {
    if (![BHTSettings boolForKey:@"download_videos"] ||
        !LegacyDMVideoEntity(statusView)) {
        return;
    }

    UIView* targetView = LegacyDMVisibleMediaView(statusView);
    if (!targetView ||
        objc_getAssociatedObject(targetView, &LegacyDMDownloadInteractionKey)) {
        return;
    }

    UIContextMenuInteraction* interaction = [[UIContextMenuInteraction alloc]
        initWithDelegate:(id<UIContextMenuInteractionDelegate>)statusView];
    targetView.userInteractionEnabled = YES;
    [targetView addInteraction:interaction];
    objc_setAssociatedObject(targetView, &LegacyDMDownloadInteractionKey,
                             interaction, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook T1DirectMessageConversationStatusView

- (void)setViewModel:(id)viewModel
             options:(NSUInteger)options
             account:(id)account {
    %orig;
    InstallLegacyDMDownloadInteraction(self);
}

%new
- (UIContextMenuConfiguration*)contextMenuInteraction:(UIContextMenuInteraction*)interaction
                       configurationForMenuAtLocation:(CGPoint)location {
    if (![BHTSettings boolForKey:@"download_videos"] ||
        !LegacyDMVideoEntity(self)) {
        return nil;
    }

    __weak id weakStatusView = self;
    return [UIContextMenuConfiguration
        configurationWithIdentifier:nil
                    previewProvider:nil
                     actionProvider:^UIMenu* _Nullable(
                         NSArray<UIMenuElement*>* _Nonnull suggestedActions) {
                         UIAction* saveAction = [UIAction
                             actionWithTitle:
                                 [[BHTBundle sharedBundle]
                                     localizedTwitterStringForKey:
                                         @"DOWNLOAD_ACTIVITY_VIEW_LABEL"]
                                       image:[UIImage systemImageNamed:
                                                          @"square.and.arrow.down"]
                                  identifier:nil
                                     handler:^(__kindof UIAction* _Nonnull action) {
                                         id statusView = weakStatusView;
                                         TFSTwitterEntityMedia* media =
                                             LegacyDMVideoEntity(statusView);
                                         if (!media) {
                                             return;
                                         }

                                         DownloadInlineButton* downloader =
                                             objc_getAssociatedObject(
                                                 statusView,
                                                 &LegacyDMDownloadHandlerKey);
                                         if (!downloader) {
                                             downloader = [%c(DownloadInlineButton) new];
                                             objc_setAssociatedObject(
                                                 statusView,
                                                 &LegacyDMDownloadHandlerKey,
                                                 downloader,
                                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                                         }

                                         [downloader
                                             presentDownloadOptionsForMediaEntities:
                                                 @[media]];
                                     }];
                         return [UIMenu menuWithTitle:@""
                                             children:@[saveAction]];
                     }];
}

%end

// MARK: - Upload custom voice

// Overwrites the recording at the attachment's existing file path, so the
// composer picks up the replacement without any model changes.
%hook T1MediaAttachmentsViewCell
%property (nonatomic, strong) UIButton* uploadButton;
- (void)updateCellElements {
    %orig;

    BOOL isVoiceRecording = [self.attachment isKindOfClass:%c(TTMAssetVoiceRecording)];

    if (isVoiceRecording && self.uploadButton == nil) {
        TFNButton* removeButton = [self valueForKey:@"_removeButton"];
        if (removeButton == nil) {
            return;
        }

        self.uploadButton = [UIButton buttonWithType:UIButtonTypeCustom];
        UIImageSymbolConfiguration* smallConfig =
            [UIImageSymbolConfiguration configurationWithScale:UIImageSymbolScaleSmall];
        UIImage* arrowUpImage = [UIImage systemImageNamed:@"arrow.up" withConfiguration:smallConfig];
        [self.uploadButton setImage:arrowUpImage forState:UIControlStateNormal];
        [self.uploadButton addTarget:self
                              action:@selector(handleUploadButton:)
                    forControlEvents:UIControlEventTouchUpInside];
        [self.uploadButton setTintColor:UIColor.labelColor];
        [self.uploadButton setBackgroundColor:[UIColor blackColor]];
        [self.uploadButton.layer setCornerRadius:29 / 2];
        [self.uploadButton setTranslatesAutoresizingMaskIntoConstraints:false];

        [self addSubview:self.uploadButton];
        [NSLayoutConstraint activateConstraints:@[
            [self.uploadButton.trailingAnchor constraintEqualToAnchor:removeButton.leadingAnchor
                                                             constant:-10],
            [self.uploadButton.topAnchor constraintEqualToAnchor:removeButton.topAnchor],
            [self.uploadButton.widthAnchor constraintEqualToConstant:29],
            [self.uploadButton.heightAnchor constraintEqualToConstant:29],
        ]];
    }

    self.uploadButton.hidden = !isVoiceRecording;
}
%new
- (void)handleUploadButton:(UIButton*)sender {
    UIImagePickerController* videoPicker = [[UIImagePickerController alloc] init];
    videoPicker.mediaTypes = @[(NSString*)kUTTypeMovie];
    videoPicker.delegate = self;

    [topMostController() presentViewController:videoPicker animated:YES completion:nil];
}
%new
- (void)imagePickerController:(UIImagePickerController*)picker
    didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id>*)info {
    NSURL* videoURL = info[UIImagePickerControllerMediaURL];
    TTMAssetVoiceRecording* attachment = self.attachment;
    NSURL* recorder_url = [NSURL fileURLWithPath:attachment.filePath];

    if (recorder_url != nil) {
        NSFileManager* fileManager = [NSFileManager defaultManager];

        NSError* error = nil;
        if ([fileManager fileExistsAtPath:[recorder_url path]]) {
            [fileManager removeItemAtURL:recorder_url error:&error];
            if (error) {
                NSLog(@"[BHTwitter] Error removing existing file: %@", error);
            }
        }

        [fileManager copyItemAtURL:videoURL toURL:recorder_url error:&error];
        if (error) {
            NSLog(@"[BHTwitter] Error copying file: %@", error);
        }
    }

    [picker dismissViewControllerAnimated:true completion:nil];
}
%new
- (void)imagePickerControllerDidCancel:(UIImagePickerController*)picker {
    [picker dismissViewControllerAnimated:true completion:nil];
}
%end

// MARK: - Save tweet as an image

%hook TTAStatusInlineShareButton
- (void)didLongPressActionButton:(UILongPressGestureRecognizer*)gestureRecognizer {
    if ([BHTSettings boolForKey:@"tweet_to_image"]) {
        if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
            UIView* statusView = self.superview;
            while (statusView && ![statusView respondsToSelector:@selector(eventHandler)]) {
                statusView = statusView.superview;
            }

            UIView* tweetView = nil;
            id eventHandler = [(T1StandardStatusView*)statusView eventHandler];
            if ([eventHandler isKindOfClass:UIView.class]) {
                tweetView = eventHandler;
            }

            if (tweetView == nil) {
                UIView* ancestor = self.superview;
                while (ancestor && ![ancestor isKindOfClass:UITableViewCell.class] &&
                       ![ancestor isKindOfClass:UICollectionViewCell.class]) {
                    ancestor = ancestor.superview;
                }
                tweetView = ancestor;
            }

            if (tweetView == nil) {
                return %orig;
            }

            UIImage* tweetImage = imageFromView(tweetView);
            NSData* pngData = UIImagePNGRepresentation(tweetImage);
            NSURL* pngURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                URLByAppendingPathComponent:[NSString
                                                stringWithFormat:@"%@.png", [[NSUUID UUID] UUIDString]]];
            [pngData writeToURL:pngURL atomically:YES];
            UIActivityViewController* acVC =
                [[UIActivityViewController alloc] initWithActivityItems:@[pngURL]
                                                  applicationActivities:nil];
            if (is_iPad()) {
                acVC.popoverPresentationController.sourceView = self;
                acVC.popoverPresentationController.sourceRect = self.frame;
            }
            [topMostController() presentViewController:acVC animated:true completion:nil];
            return;
        }
    }
    return %orig;
}
%end

// MARK: - Tweet video download

static TFNActionItem* DownloadActionItemForController(UIViewController* controller,
                                                      id status) {
    if (![BHTSettings boolForKey:@"download_videos"] ||
        ![status respondsToSelector:@selector(entities)]) {
        return nil;
    }

    NSArray* mediaEntities = [[status entities] media];
    BOOL hasVideo = NO;
    for (TFSTwitterEntityMedia* media in mediaEntities) {
        if ([media isKindOfClass:objc_getClass("TFSTwitterEntityMedia")] &&
            (media.mediaType == 2 || media.mediaType == 3)) {
            hasVideo = YES;
            break;
        }
    }
    if (!hasVideo) {
        return nil;
    }

    static char downloaderKey;
    DownloadInlineButton* downloader =
        objc_getAssociatedObject(controller, &downloaderKey);
    if (!downloader) {
        downloader = [objc_getClass("DownloadInlineButton") new];
        objc_setAssociatedObject(controller, &downloaderKey, downloader,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    return [objc_getClass("TFNActionItem")
        actionItemWithTitle:[[BHTBundle sharedBundle]
                                localizedStringForKey:@"DOWNLOAD_VIDEOS_TITLE"]
                  imageName:@"arrow_down_circle_stroke"
                     action:^{
                         [downloader
                             presentDownloadOptionsForMediaEntities:mediaEntities];
                     }];
}

// _t1_actionItemsForStatus:... is a category method on UIViewController, so the
// hook has to land on the base class to cover every share/action sheet.
%hook UIViewController
- (NSArray*)_t1_actionItemsForStatus:(__unsafe_unretained id)status
                             account:(__unsafe_unretained id)account
                     shareableEntity:(__unsafe_unretained id)shareableEntity
                           entityURL:(__unsafe_unretained id)entityURL
                              source:(__unsafe_unretained id)source
                             options:(NSUInteger)options
                     scribeComponent:(__unsafe_unretained id)scribeComponent
                           doneBlock:(__unsafe_unretained id)doneBlock {
    NSArray* origItems = %orig;

    TFNActionItem* quickItem = nil;
    if ([BHTSettings boolForKey:@"tweet_quick_actions"]) {
        static char quickActionsProviderKey;
        TweetQuickActionsProvider* provider =
            objc_getAssociatedObject(self, &quickActionsProviderKey);
        if (!provider) {
            provider = [TweetQuickActionsProvider new];
            objc_setAssociatedObject(self, &quickActionsProviderKey, provider,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        quickItem = [provider actionItemForStatus:status entityURL:entityURL];
    }

    TFNActionItem* downloadItem = DownloadActionItemForController(self, status);
    if (!quickItem && !downloadItem) {
        return origItems;
    }

    NSMutableArray* newItems =
        origItems ? [origItems mutableCopy] : [NSMutableArray array];
    NSUInteger insertIndex = newItems.count > 0 ? newItems.count - 1 : 0;
    if (quickItem) {
        [newItems insertObject:quickItem atIndex:insertIndex];
        insertIndex++;
    }
    if (downloadItem) {
        [newItems insertObject:downloadItem atIndex:insertIndex];
    }
    return newItems;
}
%end
