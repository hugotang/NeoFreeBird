# Retained Branch Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the five Twitter 12.14 mappings that remain useful from the retained legacy branch into modular v6, verify the exact pushed commit with Theos CI, and delete the obsolete remote branch.

**Architecture:** Keep each hook in the v6 feature module that owns its setting. Reuse the existing confirmation and download services, use dynamic selector checks for the legacy DM fallback, and add one independently runnable PowerShell contract per mapping so every change follows a complete red-green cycle.

**Tech Stack:** Objective-C/Logos, UIKit context menus, Objective-C runtime dispatch, PowerShell contract tests, Theos, GitHub Actions.

---

## File Structure

- Modify `tests/compatibility/Test-Twitter1214Compatibility.ps1`: add five independently selectable retained-hook contracts plus a final aggregate contract.
- Modify `src/Hooks/FeatureSwitches.x`: restore the four Full HD/4K upload gates.
- Modify `src/Hooks/Ads.x`: hide the TwitterHome Premium upsell bar-button plugin.
- Modify `src/Hooks/Confirmations.x`: confirm keyboard-triggered likes.
- Modify `src/Hooks/Timeline.x`: remove an already-configured Spaces/Fleets line while hidden.
- Modify `src/Hooks/MediaDownloads.x`: add the guarded legacy DM status-view adapter and reuse `DownloadInlineButton`.

## Task 1: Full HD and 4K Upload Gates

**Files:**
- Modify: `tests/compatibility/Test-Twitter1214Compatibility.ps1:1-210`
- Modify: `src/Hooks/FeatureSwitches.x:581-594`

- [ ] **Step 1: Add the failing upload contract**

Add `"Upload"` to the `ValidateSet`, add this function before
`Test-WiringContract`, add its switch case, and call it from `"All"`:

```powershell
function Test-UploadContract {
    $switches = Get-RepoText "src/Hooks/FeatureSwitches.x"

    Assert-Match $switches '%hook\s+T1LongerVideoUploadEnabledConfig' `
        "The Twitter 12.14 longer-video upload config is not hooked."

    foreach ($selector in @(
        "isUploadFullHDVideoEnabled",
        "isUploadFullHDVideoEnabledByDefault",
        "isUpload4kVideoEnabled",
        "isUpload4kVideoEnabledByDefault"
    )) {
        Assert-Match $switches `
            "(?s)- \(BOOL\)$selector\s*\{.*?auto_highest_load.*?%orig;" `
            "The $selector upload gate does not preserve its native fallback."
    }
}
```

The switch additions are:

```powershell
"Upload" { Test-UploadContract }
```

and inside `"All"`:

```powershell
Test-UploadContract
```

- [ ] **Step 2: Run the upload contract and verify RED**

Run:

```powershell
& '.\tests\compatibility\Test-Twitter1214Compatibility.ps1' -Case Upload
```

Expected: exit 1 with `The Twitter 12.14 longer-video upload config is not hooked.` and selector fallback failures.

- [ ] **Step 3: Implement the four upload gates**

Insert after the `T1ImageDisplayView` hook in
`src/Hooks/FeatureSwitches.x`:

```objc
%hook T1LongerVideoUploadEnabledConfig

- (BOOL)isUploadFullHDVideoEnabled {
    return [BHTSettings boolForKey:@"auto_highest_load"] ? YES : %orig;
}

- (BOOL)isUploadFullHDVideoEnabledByDefault {
    return [BHTSettings boolForKey:@"auto_highest_load"] ? YES : %orig;
}

- (BOOL)isUpload4kVideoEnabled {
    return [BHTSettings boolForKey:@"auto_highest_load"] ? YES : %orig;
}

- (BOOL)isUpload4kVideoEnabledByDefault {
    return [BHTSettings boolForKey:@"auto_highest_load"] ? YES : %orig;
}

%end
```

- [ ] **Step 4: Run upload and full contracts and verify GREEN**

Run:

```powershell
& '.\tests\compatibility\Test-Twitter1214Compatibility.ps1' -Case Upload
& '.\tests\compatibility\Test-Twitter1214Compatibility.ps1' -Case All
```

Expected: both commands exit 0.

- [ ] **Step 5: Commit the upload mapping**

```powershell
git add -- src/Hooks/FeatureSwitches.x tests/compatibility/Test-Twitter1214Compatibility.ps1
git commit -m "Restore high quality video upload gates"
```

## Task 2: Premium Home-Bar Upsell Hiding

**Files:**
- Modify: `tests/compatibility/Test-Twitter1214Compatibility.ps1`
- Modify: `src/Hooks/Ads.x:1-163`

- [ ] **Step 1: Add the failing Premium contract**

Add `"Premium"` to the `ValidateSet`, add this function before
`Test-WiringContract`, add its switch case, and call it from `"All"`:

```powershell
function Test-PremiumContract {
    $ads = Get-RepoText "src/Hooks/Ads.x"

    Assert-Match $ads `
        '%hook\s+_TtC11TwitterHome32PremiumUpsellBarButtonItemPlugin' `
        "The Twitter 12.14 Premium upsell bar-button plugin is not hooked."
    Assert-Match $ads `
        '(?s)rightBarButtonItem.*hide_premium_offer.*\? nil : %orig' `
        "The Premium bar button does not preserve its native fallback."
    Assert-Match $ads `
        '(?s)showPremiumSignUp.*hide_premium_offer.*return;.*%orig;' `
        "The Premium signup action is not suppressed only while configured."
}
```

The switch addition is:

```powershell
"Premium" { Test-PremiumContract }
```

- [ ] **Step 2: Run the Premium contract and verify RED**

Run:

```powershell
& '.\tests\compatibility\Test-Twitter1214Compatibility.ps1' -Case Premium
```

Expected: exit 1 with `The Twitter 12.14 Premium upsell bar-button plugin is not hooked.`

- [ ] **Step 3: Implement the Premium plugin hook**

Append to `src/Hooks/Ads.x`:

```objc
// MARK: - Premium home-bar upsell

%hook _TtC11TwitterHome32PremiumUpsellBarButtonItemPlugin

- (id)rightBarButtonItem {
    return [BHTSettings boolForKey:@"hide_premium_offer"] ? nil : %orig;
}

- (void)showPremiumSignUp {
    if ([BHTSettings boolForKey:@"hide_premium_offer"]) {
        return;
    }

    %orig;
}

%end
```

- [ ] **Step 4: Run Premium and full contracts and verify GREEN**

```powershell
& '.\tests\compatibility\Test-Twitter1214Compatibility.ps1' -Case Premium
& '.\tests\compatibility\Test-Twitter1214Compatibility.ps1' -Case All
```

Expected: both commands exit 0.

- [ ] **Step 5: Commit the Premium mapping**

```powershell
git add -- src/Hooks/Ads.x tests/compatibility/Test-Twitter1214Compatibility.ps1
git commit -m "Hide Twitter 12.14 Premium upsell button"
```

## Task 3: Keyboard Like Confirmation

**Files:**
- Modify: `tests/compatibility/Test-Twitter1214Compatibility.ps1`
- Modify: `src/Hooks/Confirmations.x:55-88`

- [ ] **Step 1: Add the failing keyboard-like contract**

Add `"LikeKey"` to the `ValidateSet`, add this function before
`Test-WiringContract`, add its switch case, and call it from `"All"`:

```powershell
function Test-LikeKeyContract {
    $confirmations = Get-RepoText "src/Hooks/Confirmations.x"

    Assert-Match $confirmations `
        '(?s)%hook\s+T1StatusCell.*handleLikeKeyCommand.*like_confirm.*ShowConfirmation.*%orig;' `
        "Keyboard-triggered likes do not pass through the shared confirmation flow."
}
```

The switch addition is:

```powershell
"LikeKey" { Test-LikeKeyContract }
```

- [ ] **Step 2: Run the keyboard-like contract and verify RED**

```powershell
& '.\tests\compatibility\Test-Twitter1214Compatibility.ps1' -Case LikeKey
```

Expected: exit 1 with `Keyboard-triggered likes do not pass through the shared confirmation flow.`

- [ ] **Step 3: Implement the keyboard-like hook**

Insert after the `TTAStatusInlineActionsView` hook in
`src/Hooks/Confirmations.x`:

```objc
// Keyboard shortcuts bypass the inline-action view and send action type 3
// directly through T1StatusCell.
%hook T1StatusCell

- (void)handleLikeKeyCommand {
    if (![BHTSettings boolForKey:@"like_confirm"]) {
        return %orig;
    }

    ShowConfirmation(^{
        %orig;
    });
}

%end
```

- [ ] **Step 4: Run keyboard-like and full contracts and verify GREEN**

```powershell
& '.\tests\compatibility\Test-Twitter1214Compatibility.ps1' -Case LikeKey
& '.\tests\compatibility\Test-Twitter1214Compatibility.ps1' -Case All
```

Expected: both commands exit 0.

- [ ] **Step 5: Commit the confirmation mapping**

```powershell
git add -- src/Hooks/Confirmations.x tests/compatibility/Test-Twitter1214Compatibility.ps1
git commit -m "Confirm keyboard-triggered likes"
```

## Task 4: Remove an Already-Configured Spaces Line

**Files:**
- Modify: `tests/compatibility/Test-Twitter1214Compatibility.ps1`
- Modify: `src/Hooks/Timeline.x:121-135`

- [ ] **Step 1: Add the failing Spaces contract**

Add `"Spaces"` to the `ValidateSet`, add this function before
`Test-WiringContract`, add its switch case, and call it from `"All"`:

```powershell
function Test-SpacesContract {
    $timeline = Get-RepoText "src/Hooks/Timeline.x"

    Assert-Match $timeline `
        '(?s)_t1_configureFleets_helper.*!\[BHTSettings boolForKey:@"hide_spaces"\].*%orig;.*return;.*_t1_removeFleetLineView' `
        "The configured Spaces line is not removed while preserving the native enabled path."
    Assert-Match $timeline `
        '(?s)_t1_shouldShowFleetLine.*hide_spaces.*return NO;.*%orig;' `
        "The Spaces visibility gate no longer preserves its native fallback."
}
```

The switch addition is:

```powershell
"Spaces" { Test-SpacesContract }
```

- [ ] **Step 2: Run the Spaces contract and verify RED**

```powershell
& '.\tests\compatibility\Test-Twitter1214Compatibility.ps1' -Case Spaces
```

Expected: exit 1 with `The configured Spaces line is not removed while preserving the native enabled path.`

- [ ] **Step 3: Implement the configure helper hook**

Add this method before `_t1_shouldShowFleetLine` inside the existing
`T1FleetLineHeaderController` hook:

```objc
- (void)_t1_configureFleets_helper {
    if (![BHTSettings boolForKey:@"hide_spaces"]) {
        %orig;
        return;
    }

    SEL removeSelector = NSSelectorFromString(@"_t1_removeFleetLineView");
    if ([self respondsToSelector:removeSelector]) {
        ((void (*)(id, SEL))objc_msgSend)(self, removeSelector);
    }
}
```

- [ ] **Step 4: Run Spaces and full contracts and verify GREEN**

```powershell
& '.\tests\compatibility\Test-Twitter1214Compatibility.ps1' -Case Spaces
& '.\tests\compatibility\Test-Twitter1214Compatibility.ps1' -Case All
```

Expected: both commands exit 0.

- [ ] **Step 5: Commit the Spaces mapping**

```powershell
git add -- src/Hooks/Timeline.x tests/compatibility/Test-Twitter1214Compatibility.ps1
git commit -m "Remove configured Spaces bar when hidden"
```

## Task 5: Legacy DM Video Download Fallback

**Files:**
- Modify: `tests/compatibility/Test-Twitter1214Compatibility.ps1`
- Modify: `src/Hooks/MediaDownloads.x:8-75`

- [ ] **Step 1: Add the failing legacy-DM contract**

Add `"LegacyDM"` to the `ValidateSet`, add this function before
`Test-WiringContract`, add its switch case, and call it from `"All"`:

```powershell
function Test-LegacyDMContract {
    $downloads = Get-RepoText "src/Hooks/MediaDownloads.x"

    Assert-Match $downloads '%hook\s+T1DirectMessageConversationStatusView' `
        "The legacy DM status-view fallback is not hooked."
    Assert-Match $downloads `
        '(?s)setViewModel:\(id\)viewModel.*%orig;.*InstallLegacyDMDownloadInteraction' `
        "The legacy DM adapter does not install after Twitter updates its view model."
    Assert-Match $downloads `
        '(?s)inlineMediaViewModel.*viewModel.*playerSessionProducer.*sessionProducible.*mediaEntity.*variants' `
        "The legacy DM media chain is incomplete."
    Assert-Match $downloads `
        '(?s)visibleMediaForwardView.*EnumerateSubviewsRecursively.*T1InlineMediaView' `
        "The legacy DM visible-view fallback is missing."
    Assert-Match $downloads `
        '(?s)LegacyDMDownloadInteractionKey.*objc_getAssociatedObject.*UIContextMenuInteraction' `
        "The legacy DM context menu is not installed idempotently."
    Assert-Match $downloads `
        '(?s)download_videos.*DownloadInlineButton.*presentDownloadOptionsForMediaEntities' `
        "The legacy DM fallback does not reuse the shared downloader."
}
```

The switch addition is:

```powershell
"LegacyDM" { Test-LegacyDMContract }
```

- [ ] **Step 2: Run the legacy-DM contract and verify RED**

```powershell
& '.\tests\compatibility\Test-Twitter1214Compatibility.ps1' -Case LegacyDM
```

Expected: exit 1 with `The legacy DM status-view fallback is not hooked.` and the remaining legacy-DM failures.

- [ ] **Step 3: Add guarded legacy-DM resolution and context-menu code**

Insert after the modern `DMConversation.MessageAttachmentView` hook in
`src/Hooks/MediaDownloads.x`:

```objc
// The older status-based DM renderer still ships beside the Swift DM UI in
// Twitter 12.14. Keep it as a capability-checked fallback and feed the entity
// into the same downloader used by the modern path.
static char LegacyDMDownloadInteractionKey;
static char LegacyDMDownloadHandlerKey;

static id LegacyDMObjectForSelector(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) {
        return nil;
    }

    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
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
                                                 @[ media ]];
                                     }];
                         return [UIMenu menuWithTitle:@""
                                             children:@[ saveAction ]];
                     }];
}

%end
```

- [ ] **Step 4: Run legacy-DM and full contracts and verify GREEN**

```powershell
& '.\tests\compatibility\Test-Twitter1214Compatibility.ps1' -Case LegacyDM
& '.\tests\compatibility\Test-Twitter1214Compatibility.ps1' -Case All
```

Expected: both commands exit 0.

- [ ] **Step 5: Commit the legacy-DM fallback**

```powershell
git add -- src/Hooks/MediaDownloads.x tests/compatibility/Test-Twitter1214Compatibility.ps1
git commit -m "Restore legacy DM video download fallback"
```

## Task 6: Aggregate Retained-Branch Contract

**Files:**
- Modify: `tests/compatibility/Test-Twitter1214Compatibility.ps1`

- [ ] **Step 1: Add the aggregate retained contract and Grok exclusion**

Add `"Retained"` to the `ValidateSet` and add:

```powershell
function Test-RetainedBranchContract {
    Test-UploadContract
    Test-PremiumContract
    Test-LikeKeyContract
    Test-SpacesContract
    Test-LegacyDMContract

    $allSources = Get-SourceTreeText
    Assert-NotMatch $allSources 'MSHookFunction|MSFindSymbol|\$s4Grok' `
        "Grok Premium function hooks were restored during retained-branch integration."
}
```

Add the switch case:

```powershell
"Retained" { Test-RetainedBranchContract }
```

Inside `"All"`, replace the five individual retained-contract calls with:

```powershell
Test-RetainedBranchContract
```

- [ ] **Step 2: Run retained, full compatibility, and localization contracts**

```powershell
& '.\tests\compatibility\Test-Twitter1214Compatibility.ps1' -Case Retained
& '.\tests\compatibility\Test-Twitter1214Compatibility.ps1' -Case All
& '.\tests\localization\Test-V6Localization.ps1'
```

Expected: all three commands exit 0; localization reports all 15 supported locales.

- [ ] **Step 3: Run whitespace and source-scope checks**

```powershell
git diff --check
git status --short
git diff --stat
```

Expected: `git diff --check` exits 0; status and stat list only the aggregate test change.

- [ ] **Step 4: Commit the aggregate contract**

```powershell
git add -- tests/compatibility/Test-Twitter1214Compatibility.ps1
git commit -m "Test retained Twitter 12.14 mappings"
```

## Task 7: Push, Compile, and Delete the Obsolete Branch

**Files:**
- No source changes.
- Verify: local Git state, `origin/v6`, GitHub Actions run, remote branch list.

- [ ] **Step 1: Run fresh pre-merge verification**

```powershell
& '.\tests\compatibility\Test-Twitter1214Compatibility.ps1' -Case All
& '.\tests\localization\Test-V6Localization.ps1'
git diff --check
git status -sb
```

Expected: both suites and diff check exit 0; the implementation branch is clean.

- [ ] **Step 2: Re-run tests on v6 and push**

```powershell
& '.\tests\compatibility\Test-Twitter1214Compatibility.ps1' -Case All
& '.\tests\localization\Test-V6Localization.ps1'
git push origin v6
```

Expected: tests exit 0 and `origin/v6` advances to local HEAD.

- [ ] **Step 3: Dispatch the exact v6 branch to macOS/Theos CI**

```powershell
gh workflow run build.yml --repo hugotang/NeoFreeBird --ref v6 `
    -f sdk_version=16.5 `
    -f target_version=14.0 `
    -f decrypted_ipa_url=unused `
    -f deploy_format=rootless `
    -f twitter_branding=true `
    -f resource_pack_url= `
    -f upload_artifact=true `
    -f create_release=false
```

Read the newest run ID for the v6 branch and watch it:

```powershell
$runId = gh run list --repo hugotang/NeoFreeBird --workflow build.yml `
    --branch v6 --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $runId --repo hugotang/NeoFreeBird --interval 10 --exit-status
gh run view $runId --repo hugotang/NeoFreeBird `
    --json status,conclusion,headSha,url
```

Expected: `Build Package` succeeds, conclusion is `success`, and `headSha`
equals `git rev-parse HEAD`.

- [ ] **Step 4: Verify the exact remote state before deletion**

```powershell
git rev-parse HEAD
git ls-remote origin refs/heads/v6
gh repo view hugotang/NeoFreeBird --json defaultBranchRef `
    --jq '.defaultBranchRef.name'
```

Expected: both SHAs match and the default branch is `v6`.

- [ ] **Step 5: Delete the audited obsolete branch**

```powershell
git push origin --delete codex/fix-logos-orig-inline-actions
git fetch --prune origin
git ls-remote --heads origin
```

Expected: the deleted branch is absent and `refs/heads/v6` remains.

- [ ] **Step 6: Verify the final v6 checkout and report device checks**

```powershell
git status -sb
git branch --show-current
git log -1 --oneline --decorate
```

Expected: the checkout is clean on `v6`, tracking `origin/v6`. Report the
commit SHA, CI URL, remote branch list, and the remaining optional device smoke
tests: Full HD/4K, Premium button, keyboard like, Spaces, modern DM, and legacy
DM when reachable.
