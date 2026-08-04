# Twitter 12.14 Compatibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add capability-gated Twitter 12.14 compatibility for tab theming, immersive timestamps, and the removed legacy launch path without restoring Grok Premium hooks.

**Architecture:** A small coordinator installs three focused Objective-C runtime-hook modules. Existing Logos behavior remains for older versions, while shared tab logic removes selector-specific refresh calls. A PowerShell contract test provides host-side red/green coverage; IDA and device checks cover runtime-only behavior.

**Tech Stack:** Objective-C, Logos, Cydia Substrate `MSHookMessageEx`, UIKit, PowerShell, Theos.

---

## File Map

- Create `tests/compatibility/Test-Twitter1214Compatibility.ps1`: selectable static contract tests for tab, timestamp, launch, and wiring behavior.
- Create `Compatibility/BHTTabBarCompatibility.h`: tab installer and shared theme-reapply API.
- Create `Compatibility/BHTTabBarCompatibility.m`: `_t1_updateAppearance:` runtime hook and shared tab-view iteration.
- Create `Compatibility/BHTImmersiveTimestampCompatibility.h`: immersive timestamp installer API.
- Create `Compatibility/BHTImmersiveTimestampCompatibility.m`: `ImmersiveCardView.layoutSubviews` hook and bounded timestamp-label styling.
- Create `Compatibility/BHTLaunchTransitionCompatibility.h`: guarded legacy launch installer API.
- Create `Compatibility/BHTLaunchTransitionCompatibility.m`: capability-gated `launchTransitionProvider` class-method hook.
- Create `Compatibility/BHTTwitter1214Compatibility.h`: coordinator installer API.
- Create `Compatibility/BHTTwitter1214Compatibility.m`: one-time installation of all three feature modules.
- Modify `Tweak.x`: import/install the coordinator, share tab reapply logic, and remove the unconditional launch Logos block.
- Modify `TWHeaders.h`: remove the obsolete direct `launchTransitionProvider` declaration.
- Modify `PROJECT_CONTEXT.md`: record the 12.14 mappings, exclusions, and verification limits.

### Task 1: Add The Failing Compatibility Contract

**Files:**

- Create: `tests/compatibility/Test-Twitter1214Compatibility.ps1`

- [ ] **Step 1: Create the contract test**

```powershell
param(
    [ValidateSet("Tab", "Timestamp", "Launch", "Wiring", "All")]
    [string]$Case = "All"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Get-RepoText {
    param([string]$RelativePath)

    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $failures.Add("Missing file: $RelativePath")
        return ""
    }

    return [System.IO.File]::ReadAllText($path)
}

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)

    if ($Text -notmatch $Pattern) {
        $failures.Add($Message)
    }
}

function Assert-NotMatch {
    param([string]$Text, [string]$Pattern, [string]$Message)

    if ($Text -match $Pattern) {
        $failures.Add($Message)
    }
}

function Test-TabContract {
    $header = Get-RepoText "Compatibility/BHTTabBarCompatibility.h"
    $source = Get-RepoText "Compatibility/BHTTabBarCompatibility.m"

    Assert-Match $header 'BHTInstallTabBarCompatibility' "Tab installer is not exported."
    Assert-Match $header 'BHTApplyCurrentThemeToTabBarController' "Shared tab reapply API is not exported."
    Assert-Match $source '_t1_updateAppearance:' "The Twitter 12.14 tab selector is not hooked."
    Assert-Match $source 'MSHookMessageEx' "The tab module is not using a guarded runtime hook."
    Assert-Match $source 'bh_applyCurrentThemeToIcon' "The tab module does not reapply tab icon state."
}

function Test-TimestampContract {
    $source = Get-RepoText "Compatibility/BHTImmersiveTimestampCompatibility.m"

    Assert-Match $source 'ImmersiveCardView' "The immersive card class is not resolved."
    Assert-Match $source 'layoutSubviews' "The immersive layout selector is not hooked."
    Assert-Match $source 'restoreVideoTimestamp' "The timestamp preference is not respected."
    Assert-Match $source 'BHT_StyledTimestamp' "Legacy and 12.14 timestamp styling are not deduplicated."
    Assert-Match $source 'BHTTimestampMaximumVisitedViews' "Timestamp traversal is not bounded."
    Assert-NotMatch $source 'setHidden:|\.hidden\s*=' "The 12.14 timestamp module must not force visibility."
}

function Test-LaunchContract {
    $source = Get-RepoText "Compatibility/BHTLaunchTransitionCompatibility.m"
    $tweak = Get-RepoText "Tweak.x"

    Assert-Match $source 'class_getClassMethod' "Launch installation does not require the legacy class method."
    Assert-Match $source 'T1AppLaunchTransition' "Launch installation does not require the legacy transition class."
    Assert-Match $source 'object_getClass' "The launch class method is not hooked on the metaclass."
    Assert-Match $source 'MSHookMessageEx' "The launch module is not using a guarded runtime hook."
    Assert-Match $source 'BHTOriginalLaunchTransitionProvider' "The launch replacement has no original fallback."
    Assert-NotMatch $tweak '(?s)%hook\s+T1AppDelegate.*?launchTransitionProvider' "The unconditional launch Logos hook still exists."
}

function Test-WiringContract {
    $tweak = Get-RepoText "Tweak.x"
    $coordinator = Get-RepoText "Compatibility/BHTTwitter1214Compatibility.m"
    $newSources = @(
        $coordinator,
        (Get-RepoText "Compatibility/BHTTabBarCompatibility.m"),
        (Get-RepoText "Compatibility/BHTImmersiveTimestampCompatibility.m"),
        (Get-RepoText "Compatibility/BHTLaunchTransitionCompatibility.m")
    ) -join "`n"

    Assert-Match $tweak 'BHTTwitter1214Compatibility\.h' "The 12.14 coordinator header is not imported."
    Assert-Match $tweak 'BHTInstallTwitter1214Compatibility\(\)' "The 12.14 coordinator is not installed."
    Assert-Match $tweak 'BHTApplyCurrentThemeToTabBarController\(self\)' "The legacy tab hook does not use shared reapply logic."
    Assert-Match $coordinator 'BHTInstallTabBarCompatibility\(\)' "The coordinator does not install tab compatibility."
    Assert-Match $coordinator 'BHTInstallImmersiveTimestampCompatibility\(\)' "The coordinator does not install timestamp compatibility."
    Assert-Match $coordinator 'BHTInstallLaunchTransitionCompatibility\(\)' "The coordinator does not install launch compatibility."
    Assert-NotMatch $newSources 'MSHookFunction|\$s4Grok' "Grok function hooks were added to 12.14 compatibility."
}

switch ($Case) {
    "Tab" { Test-TabContract }
    "Timestamp" { Test-TimestampContract }
    "Launch" { Test-LaunchContract }
    "Wiring" { Test-WiringContract }
    "All" {
        Test-TabContract
        Test-TimestampContract
        Test-LaunchContract
        Test-WiringContract
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host "FAIL: $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host "Twitter 12.14 compatibility contract passed: $Case"
```

- [ ] **Step 2: Run the complete contract and verify RED**

Run:

```powershell
pwsh -NoProfile -File tests/compatibility/Test-Twitter1214Compatibility.ps1 -Case All
```

Expected: exit code `1`, with missing-file failures for the four 12.14 compatibility modules. The test must not fail because of a PowerShell syntax error.

### Task 2: Implement Tab Bar Compatibility

**Files:**

- Create: `Compatibility/BHTTabBarCompatibility.h`
- Create: `Compatibility/BHTTabBarCompatibility.m`
- Test: `tests/compatibility/Test-Twitter1214Compatibility.ps1`

- [ ] **Step 1: Re-run the focused tab contract and verify RED**

```powershell
pwsh -NoProfile -File tests/compatibility/Test-Twitter1214Compatibility.ps1 -Case Tab
```

Expected: exit code `1`, reporting the missing tab compatibility files.

- [ ] **Step 2: Create the tab compatibility header**

```objective-c
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT void BHTInstallTabBarCompatibility(void);
FOUNDATION_EXPORT void BHTApplyCurrentThemeToTabBarController(id controller);

NS_ASSUME_NONNULL_END
```

- [ ] **Step 3: Create the tab compatibility implementation**

```objective-c
#import "BHTTabBarCompatibility.h"

#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

typedef void (*BHTTabAppearanceIMP)(id, SEL, NSInteger);

static BHTTabAppearanceIMP BHTOriginalTabAppearance;

void BHTApplyCurrentThemeToTabBarController(id controller) {
    SEL tabViewsSelector = NSSelectorFromString(@"tabViews");
    if (!controller || ![controller respondsToSelector:tabViewsSelector]) {
        return;
    }

    id tabViews = ((id (*)(id, SEL))objc_msgSend)(controller, tabViewsSelector);
    if (![tabViews isKindOfClass:[NSArray class]]) {
        return;
    }

    SEL applySelector = NSSelectorFromString(@"bh_applyCurrentThemeToIcon");
    for (id tabView in (NSArray *)tabViews) {
        if ([tabView respondsToSelector:applySelector]) {
            ((void (*)(id, SEL))objc_msgSend)(tabView, applySelector);
        }
    }
}

static void BHTUpdateTabAppearance(id self, SEL selector, NSInteger appearance) {
    if (BHTOriginalTabAppearance) {
        BHTOriginalTabAppearance(self, selector, appearance);
    }
    BHTApplyCurrentThemeToTabBarController(self);
}

void BHTInstallTabBarCompatibility(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class controllerClass = objc_getClass("T1TabBarViewController");
        SEL selector = NSSelectorFromString(@"_t1_updateAppearance:");
        if (!controllerClass || !class_getInstanceMethod(controllerClass, selector)) {
            return;
        }

        MSHookMessageEx(controllerClass, selector,
            (IMP)&BHTUpdateTabAppearance,
            (IMP *)&BHTOriginalTabAppearance);
    });
}
```

- [ ] **Step 4: Run the focused tab contract and verify GREEN**

```powershell
pwsh -NoProfile -File tests/compatibility/Test-Twitter1214Compatibility.ps1 -Case Tab
```

Expected: exit code `0` and `Twitter 12.14 compatibility contract passed: Tab`.

- [ ] **Step 5: Commit the green tab slice**

```powershell
git add tests/compatibility/Test-Twitter1214Compatibility.ps1 Compatibility/BHTTabBarCompatibility.h Compatibility/BHTTabBarCompatibility.m
git commit -m "Add Twitter 12.14 tab compatibility"
```

### Task 3: Implement Immersive Timestamp Compatibility

**Files:**

- Create: `Compatibility/BHTImmersiveTimestampCompatibility.h`
- Create: `Compatibility/BHTImmersiveTimestampCompatibility.m`
- Test: `tests/compatibility/Test-Twitter1214Compatibility.ps1`

- [ ] **Step 1: Run the focused timestamp contract and verify RED**

```powershell
pwsh -NoProfile -File tests/compatibility/Test-Twitter1214Compatibility.ps1 -Case Timestamp
```

Expected: exit code `1`, reporting the missing timestamp implementation.

- [ ] **Step 2: Create the timestamp compatibility header**

```objective-c
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT void BHTInstallImmersiveTimestampCompatibility(void);

NS_ASSUME_NONNULL_END
```

- [ ] **Step 3: Create the timestamp compatibility implementation**

```objective-c
#import "BHTImmersiveTimestampCompatibility.h"

#import "../BHTManager.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>

static const NSUInteger BHTTimestampMaximumVisitedViews = 100;
static char BHTTimestampStyleKey;

typedef void (*BHTLayoutSubviewsIMP)(UIView *, SEL);

static BHTLayoutSubviewsIMP BHTOriginalImmersiveCardLayoutSubviews;

static BOOL BHTLooksLikeTimestamp(NSString *text) {
    if (text.length == 0) {
        return NO;
    }

    static NSRegularExpression *expression;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *pattern = @"^\\s*[0-9]{1,2}(?::[0-9]{2}){1,2}\\s*/\\s*[0-9]{1,2}(?::[0-9]{2}){1,2}\\s*$";
        expression = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    });

    NSRange range = NSMakeRange(0, text.length);
    return [expression firstMatchInString:text options:0 range:range] != nil;
}

static UILabel *BHTFindTimestampLabel(UIView *rootView) {
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:rootView];
    NSUInteger visited = 0;

    while (pending.count > 0 && visited < BHTTimestampMaximumVisitedViews) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        visited++;

        if ([view isKindOfClass:[UILabel class]] &&
            BHTLooksLikeTimestamp(((UILabel *)view).text)) {
            return (UILabel *)view;
        }

        [pending addObjectsFromArray:view.subviews];
    }

    return nil;
}

static void BHTStyleTimestampLabel(UILabel *label) {
    if ([objc_getAssociatedObject(label, &BHTTimestampStyleKey) boolValue] ||
        [objc_getAssociatedObject(label, "BHT_StyledTimestamp") boolValue]) {
        return;
    }

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
    objc_setAssociatedObject(label, &BHTTimestampStyleKey, @YES,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(label, "BHT_StyledTimestamp", @YES,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void BHTImmersiveCardLayoutSubviews(UIView *self, SEL selector) {
    if (BHTOriginalImmersiveCardLayoutSubviews) {
        BHTOriginalImmersiveCardLayoutSubviews(self, selector);
    }

    if (![BHTManager restoreVideoTimestamp]) {
        return;
    }

    UILabel *timestampLabel = BHTFindTimestampLabel(self);
    if (timestampLabel) {
        BHTStyleTimestampLabel(timestampLabel);
    }
}

static Class BHTImmersiveCardClass(void) {
    Class cardClass = NSClassFromString(@"T1TwitterSwift.ImmersiveCardView");
    return cardClass ?: objc_getClass("_TtC14T1TwitterSwift17ImmersiveCardView");
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
            (IMP *)&BHTOriginalImmersiveCardLayoutSubviews);
    });
}
```

- [ ] **Step 4: Run the focused timestamp contract and verify GREEN**

```powershell
pwsh -NoProfile -File tests/compatibility/Test-Twitter1214Compatibility.ps1 -Case Timestamp
```

Expected: exit code `0` and `Twitter 12.14 compatibility contract passed: Timestamp`.

- [ ] **Step 5: Commit the green timestamp slice**

```powershell
git add Compatibility/BHTImmersiveTimestampCompatibility.h Compatibility/BHTImmersiveTimestampCompatibility.m
git commit -m "Add Twitter 12.14 timestamp compatibility"
```

### Task 4: Guard The Legacy Launch Transition

**Files:**

- Create: `Compatibility/BHTLaunchTransitionCompatibility.h`
- Create: `Compatibility/BHTLaunchTransitionCompatibility.m`
- Modify: `Tweak.x:5259`
- Modify: `TWHeaders.h:36`
- Test: `tests/compatibility/Test-Twitter1214Compatibility.ps1`

- [ ] **Step 1: Run the focused launch contract and verify RED**

```powershell
pwsh -NoProfile -File tests/compatibility/Test-Twitter1214Compatibility.ps1 -Case Launch
```

Expected: exit code `1`, reporting the missing launch compatibility implementation.

- [ ] **Step 2: Create the launch compatibility header**

```objective-c
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT void BHTInstallLaunchTransitionCompatibility(void);

NS_ASSUME_NONNULL_END
```

- [ ] **Step 3: Create the launch compatibility implementation**

```objective-c
#import "BHTLaunchTransitionCompatibility.h"

#import <objc/runtime.h>
#import <substrate.h>

typedef id (*BHTLaunchTransitionProviderIMP)(id, SEL);

static BHTLaunchTransitionProviderIMP BHTOriginalLaunchTransitionProvider;

static id BHTLaunchTransitionProvider(id self, SEL selector) {
    Class transitionClass = NSClassFromString(@"T1AppLaunchTransition");
    if (transitionClass) {
        return [[transitionClass alloc] init];
    }

    return BHTOriginalLaunchTransitionProvider
        ? BHTOriginalLaunchTransitionProvider(self, selector)
        : nil;
}

void BHTInstallLaunchTransitionCompatibility(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class appDelegateClass = objc_getClass("T1AppDelegate");
        Class transitionClass = NSClassFromString(@"T1AppLaunchTransition");
        SEL selector = NSSelectorFromString(@"launchTransitionProvider");
        if (!appDelegateClass || !transitionClass ||
            !class_getClassMethod(appDelegateClass, selector)) {
            return;
        }

        Class metaClass = object_getClass(appDelegateClass);
        MSHookMessageEx(metaClass, selector,
            (IMP)&BHTLaunchTransitionProvider,
            (IMP *)&BHTOriginalLaunchTransitionProvider);
    });
}
```

- [ ] **Step 4: Remove the unconditional launch Logos block**

Delete this block from `Tweak.x`:

```objective-c
// MARK: Restore Launch Animation

%hook T1AppDelegate
+ (id)launchTransitionProvider {
    Class T1AppLaunchTransitionClass = NSClassFromString(@"T1AppLaunchTransition");
    if (T1AppLaunchTransitionClass) {
        return [[T1AppLaunchTransitionClass alloc] init];
    }
    return nil;
}
%end
```

Remove the obsolete method declaration from `TWHeaders.h` so `T1AppDelegate`
retains only its `window` property.

- [ ] **Step 5: Run the focused launch contract and verify GREEN**

```powershell
pwsh -NoProfile -File tests/compatibility/Test-Twitter1214Compatibility.ps1 -Case Launch
```

Expected: exit code `0` and `Twitter 12.14 compatibility contract passed: Launch`.

- [ ] **Step 6: Commit the green launch slice**

```powershell
git add Compatibility/BHTLaunchTransitionCompatibility.h Compatibility/BHTLaunchTransitionCompatibility.m Tweak.x TWHeaders.h
git commit -m "Guard legacy Twitter launch transition"
```

### Task 5: Wire The Coordinator And Shared Tab Refresh

**Files:**

- Create: `Compatibility/BHTTwitter1214Compatibility.h`
- Create: `Compatibility/BHTTwitter1214Compatibility.m`
- Modify: `Tweak.x:21`
- Modify: `Tweak.x:4893`
- Modify: `Tweak.x:4992`
- Test: `tests/compatibility/Test-Twitter1214Compatibility.ps1`

- [ ] **Step 1: Run the focused wiring contract and verify RED**

```powershell
pwsh -NoProfile -File tests/compatibility/Test-Twitter1214Compatibility.ps1 -Case Wiring
```

Expected: exit code `1`, reporting the missing coordinator and main-hook wiring.

- [ ] **Step 2: Create the coordinator header**

```objective-c
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT void BHTInstallTwitter1214Compatibility(void);

NS_ASSUME_NONNULL_END
```

- [ ] **Step 3: Create the coordinator implementation**

```objective-c
#import "BHTTwitter1214Compatibility.h"

#import "BHTImmersiveTimestampCompatibility.h"
#import "BHTLaunchTransitionCompatibility.h"
#import "BHTTabBarCompatibility.h"

void BHTInstallTwitter1214Compatibility(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        BHTInstallTabBarCompatibility();
        BHTInstallImmersiveTimestampCompatibility();
        BHTInstallLaunchTransitionCompatibility();
    });
}
```

- [ ] **Step 4: Wire the coordinator in `Tweak.x`**

Add these imports near the existing 12.8 compatibility import:

```objective-c
#import "Compatibility/BHTTabBarCompatibility.h"
#import "Compatibility/BHTTwitter1214Compatibility.h"
```

Invoke the coordinator immediately after the existing compatibility installer:

```objective-c
%init;
BHTInstallTwitter128Compatibility();
BHTInstallTwitter1214Compatibility();
```

- [ ] **Step 5: Share tab reapply logic across old and new paths**

Replace the body after `%orig` in the legacy controller hook with:

```objective-c
- (void)_t1_updateTabBarAppearance {
    %orig;
    BHTApplyCurrentThemeToTabBarController(self);
}
```

In `BHT_UpdateAllTabBarIcons` and `BHT_applyThemeToWindow`, replace the old
`_t1_updateTabBarAppearance` selector calls with direct calls to:

```objective-c
BHTApplyCurrentThemeToTabBarController(rootVC);
```

and:

```objective-c
BHTApplyCurrentThemeToTabBarController(window.rootViewController);
```

Keep the existing `T1TabBarViewController` class checks and the appearance
notification.

- [ ] **Step 6: Run the focused wiring contract and verify GREEN**

```powershell
pwsh -NoProfile -File tests/compatibility/Test-Twitter1214Compatibility.ps1 -Case Wiring
```

Expected: exit code `0` and `Twitter 12.14 compatibility contract passed: Wiring`.

- [ ] **Step 7: Commit the green wiring slice**

```powershell
git add Compatibility/BHTTwitter1214Compatibility.h Compatibility/BHTTwitter1214Compatibility.m Tweak.x
git commit -m "Wire Twitter 12.14 compatibility modules"
```

### Task 6: Document And Verify The Complete Change

**Files:**

- Modify: `PROJECT_CONTEXT.md`
- Test: `tests/compatibility/Test-Twitter1214Compatibility.ps1`

- [ ] **Step 1: Update project context**

Add a dated change-log entry recording:

- The three focused modules and coordinator.
- The 12.14 `_t1_updateAppearance:` and `ImmersiveCardView.layoutSubviews`
  mappings.
- Capability-gated launch handling.
- The deliberate Grok Premium exclusion.
- The active global feature-switch coverage.
- Static, build, IDA, and device validation status.

- [ ] **Step 2: Run the full compatibility contract**

```powershell
pwsh -NoProfile -File tests/compatibility/Test-Twitter1214Compatibility.ps1 -Case All
```

Expected: exit code `0` and `Twitter 12.14 compatibility contract passed: All`.

- [ ] **Step 3: Run repository static checks**

```powershell
git diff --check
rg -n "MSHookFunction|\$s4Grok" Compatibility
```

Expected: `git diff --check` exits `0`. The `rg` command exits `1` with no
matches, proving no Grok function hook was introduced.

- [ ] **Step 4: Reconfirm the 12.14 IDA targets**

On IDA instance `13338`, verify:

- `-[T1TabBarViewController _t1_updateAppearance:]` remains at `0x210c80` with
  a signed 64-bit argument.
- `-[_TtC14T1TwitterSwift17ImmersiveCardView layoutSubviews]` remains at
  `0xf0b108`.
- The old immersive callbacks and `+[T1AppDelegate launchTransitionProvider]`
  remain absent.

Expected: the new targets resolve and the removed targets do not.

- [ ] **Step 5: Run the available build**

```powershell
./build.sh --sideloaded
```

Expected when Theos is configured: exit code `0`. If `make`, `clang`, or
`THEOS` is unavailable, record the missing prerequisite and do not claim the
build passed.

- [ ] **Step 6: Commit documentation and any verification-only fixes**

```powershell
git add PROJECT_CONTEXT.md
git commit -m "Document Twitter 12.14 compatibility"
```

- [ ] **Step 7: Inspect and push the completed branch**

```powershell
git status --short --branch
git log -6 --oneline
git push origin codex/fix-logos-orig-inline-actions
```

Expected: only intentional changes are committed, the branch push succeeds,
and device-only smoke tests are listed as remaining rather than reported as
passed.
