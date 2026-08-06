# Tweet Quick Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a default-enabled, startup-safe Tweet overflow submenu that copies Tweet text, a clean Tweet link, author details, or a Markdown quote on Twitter 12.14 without regressing media downloads or older supported Twitter builds.

**Architecture:** Keep the existing `UIViewController` action-items hook as the sole insertion point. Snapshot all unsafe callback data into an immutable context, delegate pure URL and text formatting to Foundation-only helpers, and present the four actions with Twitter's existing menu-sheet classes. Capability checks and Objective-C exception boundaries turn missing private APIs into unavailable actions instead of startup failures.

**Tech Stack:** Objective-C/Logos, Foundation, UIKit, Objective-C runtime dispatch, Twitter private menu APIs, PowerShell contract tests, macOS Foundation test harness, Theos, GitHub Actions.

---

## Verified Twitter 12.14 Mappings

These mappings were verified before this plan was written. Recheck them only if
the target binary changes.

IDA instance `13338`, `T1Twitter`:

- `-[UIViewController _t1_actionItemsForStatus:account:shareableEntity:entityURL:source:options:scribeComponent:doneBlock:]` is at `0x302828` and returns an object/array.
- `-[TFNTwitterStatus plainTextSubject]` is at `0x49c330` and directly returns `-[TFNTwitterStatus text]`.
- `-[TFNTwitterStatus shareableAuthorName]` is at `0x49cfac` and resolves `representedStatus.fromUser.fullName`.
- `-[TFNTwitterStatus shareableAuthorHandle]` is at `0x49d010` and resolves `representedStatus.fromUser.displayUsername`.
- `-[TFNTwitterStatus twitterURLForCopy]` is at `0x49c260` and calls `twitterURLForShareWithSParam:`.
- `-[TFNTwitterStatus twitterURLForShareWithoutSParam]` is at `0x49bfe0` and builds `https://x.com/<username>/status/<id>`.

IDA instance `13339`, `TwitterSPMMigration`:

- `-[TFNActionItem setDisabled:]` is at `0xbc6264`.
- `-[TFNMenuSheetViewController initWithTitle:actionItems:]` is at `0xca73ec`.
- `-[TFNMenuSheetViewController tfnPresentedCustomPresentFromViewController:animated:completion:]` is at `0xcaac84`.
- `-[TFNHUD hideAfterDelay:]` is at `0xc51104`.

All mappings are Objective-C. No Swift getter, fixed offset, launch hook, Grok
Premium symbol, or network call is required.

## File Structure

- Create `tests/quick-actions/Test-TweetQuickActions.ps1`: focused selectable source contracts for mappings, URL helpers, formatter, provider, wiring, and localization.
- Create `tests/quick-actions/TweetQuickActionsFoundationTests.m`: executable golden tests for Foundation-only URL and formatting behavior.
- Create `tests/quick-actions/run-foundation-tests.sh`: compile and run the golden tests on macOS; report an explicit skip on non-macOS hosts.
- Create `src/Core/BHTShareURL.h` and `src/Core/BHTShareURL.m`: sharing-host normalization, tracking removal, canonical Tweet URL construction, and URL handle/ID parsing.
- Create `src/TweetQuickActions/TweetQuickActionsFormatter.h` and `src/TweetQuickActions/TweetQuickActionsFormatter.m`: plain text, author, attribution escaping, and Markdown formatting.
- Create `src/TweetQuickActions/TweetQuickActionsProvider.h` and `src/TweetQuickActions/TweetQuickActionsProvider.m`: immutable status snapshot, menu construction, pasteboard writes, haptic feedback, and HUD presentation.
- Modify `src/Headers/TFNHeaders.h`: declare only the private selectors verified above.
- Modify `src/Hooks/Misc.x`: delegate existing share-link cleanup to the shared URL helper.
- Modify `src/Hooks/MediaDownloads.x`: build Quick Actions and Download Media independently and insert them in deterministic order.
- Modify `src/Core/BHTSettings.m`: register `tweet_quick_actions` after `tweet_to_image`, default enabled.
- Modify all `layout/Library/Application Support/BHT/BHTwitter.bundle/*.lproj/Localizable.strings`: add eight translated strings.
- Modify `.github/workflows/build.yml`: run the Foundation golden tests before the Theos build.

## Task 1: Lock the Private API Contract

**Files:**
- Create: `tests/quick-actions/Test-TweetQuickActions.ps1`
- Modify: `src/Headers/TFNHeaders.h:32-83,107-114`

- [ ] **Step 1: Write the failing mappings contract**

Create `tests/quick-actions/Test-TweetQuickActions.ps1` with this initial
content:

```powershell
param(
    [ValidateSet("Mappings")]
    [string]$Case = "Mappings"
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
    if ($Text -notmatch $Pattern) { $failures.Add($Message) }
}

function Assert-NotMatch {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) { $failures.Add($Message) }
}

function Test-MappingsContract {
    $headers = Get-RepoText "src/Headers/TFNHeaders.h"

    foreach ($selector in @(
        "plainTextSubject",
        "shareableAuthorName",
        "shareableAuthorHandle",
        "twitterURLForCopy"
    )) {
        Assert-Match $headers $selector `
            "TFNTwitterStatus is missing the verified $selector declaration."
    }

    Assert-Match $headers `
        '@property\s*\([^)]*getter=isDisabled[^)]*\)\s*BOOL\s+disabled' `
        "TFNActionItem does not expose the verified disabled setter."
    Assert-Match $headers 'hideAfterDelay:\(NSTimeInterval\)' `
        "TFNHUD does not expose the verified delayed-hide selector."
    Assert-NotMatch $headers 'isPremiumUser|\$s4Grok|MSHookFunction|MSFindSymbol' `
        "Grok Premium or function-hook declarations entered the Quick Actions mapping surface."
}

Test-MappingsContract

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host "FAIL: $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host "Tweet Quick Actions contract passed: $Case"
```

- [ ] **Step 2: Run the mappings contract and verify RED**

Run:

```powershell
& '.\tests\quick-actions\Test-TweetQuickActions.ps1' -Case Mappings
```

Expected: exit 1 with missing `plainTextSubject`, author getters,
`twitterURLForCopy`, `disabled`, and `hideAfterDelay:` messages.

- [ ] **Step 3: Add only the verified declarations**

Add this property to `TFNActionItem` in `src/Headers/TFNHeaders.h`:

```objc
@property (nonatomic, assign, getter=isDisabled) BOOL disabled;
```

Add this method to `TFNHUD`:

```objc
- (void)hideAfterDelay:(NSTimeInterval)delay;
```

Add these methods to `TFNTwitterStatus`:

```objc
- (NSString*)plainTextSubject;
- (NSString*)shareableAuthorName;
- (NSString*)shareableAuthorHandle;
- (NSString*)twitterURLForCopy;
```

- [ ] **Step 4: Run the mappings contract and verify GREEN**

```powershell
& '.\tests\quick-actions\Test-TweetQuickActions.ps1' -Case Mappings
```

Expected: exit 0 with `Tweet Quick Actions contract passed: Mappings`.

- [ ] **Step 5: Commit the mapping contract**

```powershell
git add -- src/Headers/TFNHeaders.h tests/quick-actions/Test-TweetQuickActions.ps1
git commit -m "Declare Tweet quick action mappings"
```

## Task 2: Extract and Test Shared URL Handling

**Files:**
- Create: `src/Core/BHTShareURL.h`
- Create: `src/Core/BHTShareURL.m`
- Create: `tests/quick-actions/TweetQuickActionsFoundationTests.m`
- Create: `tests/quick-actions/run-foundation-tests.sh`
- Modify: `tests/quick-actions/Test-TweetQuickActions.ps1`
- Modify: `src/Hooks/Misc.x:169-194`

- [ ] **Step 1: Add the failing URL source contract**

Extend the script parameter to:

```powershell
[ValidateSet("Mappings", "URL", "All")]
```

Add this function before the final test dispatch:

```powershell
function Test-URLContract {
    $header = Get-RepoText "src/Core/BHTShareURL.h"
    $implementation = Get-RepoText "src/Core/BHTShareURL.m"
    $misc = Get-RepoText "src/Hooks/Misc.x"

    foreach ($symbol in @(
        "BHTEffectiveSharingHost",
        "BHTNormalizedTwitterHandle",
        "BHTCleanShareURLString",
        "BHTCanonicalTweetURLString",
        "BHTTweetHandleFromURLString",
        "BHTTweetStatusIDFromURLString"
    )) {
        Assert-Match ($header + $implementation) $symbol `
            "The shared URL helper is missing $symbol."
    }

    Assert-Match $implementation `
        '(?s)item\.name isEqualToString:@"s".*item\.name isEqualToString:@"t"' `
        "The shared URL helper does not remove both tracking parameters."
    Assert-Match $misc '#import\s+"Core/BHTShareURL\.h"' `
        "Misc.x does not import the shared URL helper."
    Assert-Match $misc 'BHTCleanShareURLString\s*\(' `
        "Existing share hooks do not delegate to the shared URL helper."
}
```

Replace the single dispatch call with:

```powershell
switch ($Case) {
    "Mappings" { Test-MappingsContract }
    "URL" { Test-URLContract }
    "All" {
        Test-MappingsContract
        Test-URLContract
    }
}
```

- [ ] **Step 2: Run the URL contract and verify RED**

```powershell
& '.\tests\quick-actions\Test-TweetQuickActions.ps1' -Case URL
```

Expected: exit 1 reporting missing `src/Core/BHTShareURL.h`,
`src/Core/BHTShareURL.m`, and all six helper symbols.

- [ ] **Step 3: Write the Foundation URL golden tests**

Create `tests/quick-actions/TweetQuickActionsFoundationTests.m`:

```objc
#import <Foundation/Foundation.h>
#import "Core/BHTShareURL.h"

static NSUInteger assertions = 0;
static NSUInteger failures = 0;

static void AssertEqual(id actual, id expected, NSString* label) {
    assertions++;
    if ((actual == nil && expected == nil) || [actual isEqual:expected]) {
        return;
    }
    failures++;
    NSLog(@"FAIL %@: expected %@, got %@", label, expected, actual);
}

static void TestURLs(void) {
    AssertEqual(BHTEffectiveSharingHost(nil), @"x.com", @"default host");
    AssertEqual(BHTEffectiveSharingHost(@" https://FxTwitter.com/path "),
                @"fxtwitter.com", @"normalized host");
    AssertEqual(BHTNormalizedTwitterHandle(@" @@alice "), @"alice",
                @"normalized handle");

    NSString* source =
        @"https://twitter.com/alice/status/123?s=20&t=token&lang=en#media";
    AssertEqual(BHTCleanShareURLString(source, @"fxtwitter.com", YES),
                @"https://fxtwitter.com/alice/status/123?lang=en",
                @"clean fallback URL");
    AssertEqual(BHTCleanShareURLString(source, nil, NO),
                @"https://twitter.com/alice/status/123?lang=en#media",
                @"preserve existing host and fragment");
    AssertEqual(BHTCanonicalTweetURLString(@"@alice", 123, nil),
                @"https://x.com/alice/status/123", @"canonical URL");
    AssertEqual(BHTCanonicalTweetURLString(nil, 123, nil), nil,
                @"canonical URL requires handle");
    AssertEqual(BHTTweetHandleFromURLString(source), @"alice",
                @"handle from URL");
    AssertEqual(@(BHTTweetStatusIDFromURLString(source)), @123,
                @"status ID from URL");
    AssertEqual(BHTTweetHandleFromURLString(@"not-a-tweet/status/123"), nil,
                @"reject invalid Tweet URL handle");
    AssertEqual(@(BHTTweetStatusIDFromURLString(@"not-a-tweet/status/123")), @0,
                @"reject invalid Tweet URL ID");
}

int main(void) {
    @autoreleasepool {
        TestURLs();
        if (failures > 0) {
            NSLog(@"Tweet Quick Actions Foundation tests failed: %lu/%lu",
                  (unsigned long)failures, (unsigned long)assertions);
            return 1;
        }
        NSLog(@"Tweet Quick Actions Foundation tests passed: %lu assertions",
              (unsigned long)assertions);
    }
    return 0;
}
```

Create `tests/quick-actions/run-foundation-tests.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]] || ! command -v xcrun >/dev/null 2>&1; then
  echo "SKIP: Tweet Quick Actions Foundation tests require macOS Foundation."
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

xcrun clang -fobjc-arc -fmodules -framework Foundation \
  -I"$root/src" \
  "$root/tests/quick-actions/TweetQuickActionsFoundationTests.m" \
  "$root/src/Core/BHTShareURL.m" \
  -o "$tmp/tweet-quick-actions-foundation-tests"

"$tmp/tweet-quick-actions-foundation-tests"
```

- [ ] **Step 4: Implement the shared URL API**

Create `src/Core/BHTShareURL.h`:

```objc
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString* BHTEffectiveSharingHost(NSString* _Nullable selectedHost);
FOUNDATION_EXPORT NSString* _Nullable BHTNormalizedTwitterHandle(
    NSString* _Nullable handle);
FOUNDATION_EXPORT NSString* _Nullable BHTCleanShareURLString(
    NSString* _Nullable urlString,
    NSString* _Nullable selectedHost,
    BOOL removeFragment);
FOUNDATION_EXPORT NSString* _Nullable BHTCanonicalTweetURLString(
    NSString* _Nullable handle,
    long long statusID,
    NSString* _Nullable selectedHost);
FOUNDATION_EXPORT NSString* _Nullable BHTTweetHandleFromURLString(
    NSString* _Nullable urlString);
FOUNDATION_EXPORT long long BHTTweetStatusIDFromURLString(
    NSString* _Nullable urlString);

NS_ASSUME_NONNULL_END
```

Create `src/Core/BHTShareURL.m`:

```objc
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
```

- [ ] **Step 5: Delegate the existing share hooks to the new helper**

Add this import to `src/Hooks/Misc.x`:

```objc
#import "Core/BHTShareURL.h"
```

Replace the body of the existing static `CleanedShareURLString` with:

```objc
static NSString* CleanedShareURLString(NSString* urlString) {
    NSString* selectedHost =
        [[NSUserDefaults standardUserDefaults] objectForKey:@"sharing_domain"];
    return BHTCleanShareURLString(urlString, selectedHost, NO);
}
```

- [ ] **Step 6: Run URL tests and verify GREEN**

```powershell
& '.\tests\quick-actions\Test-TweetQuickActions.ps1' -Case URL
& '.\tests\quick-actions\Test-TweetQuickActions.ps1' -Case All
bash tests/quick-actions/run-foundation-tests.sh
```

Expected on Windows: both PowerShell commands exit 0 and the shell test prints
the explicit macOS Foundation skip. Expected on macOS: the shell test exits 0
with `11 assertions`.

- [ ] **Step 7: Commit the shared URL helper**

```powershell
git add -- src/Core/BHTShareURL.h src/Core/BHTShareURL.m src/Hooks/Misc.x `
    tests/quick-actions/Test-TweetQuickActions.ps1 `
    tests/quick-actions/TweetQuickActionsFoundationTests.m `
    tests/quick-actions/run-foundation-tests.sh
git commit -m "Share Tweet URL cleaning utilities"
```

## Task 3: Implement and Golden-Test Text Formatting

**Files:**
- Create: `src/TweetQuickActions/TweetQuickActionsFormatter.h`
- Create: `src/TweetQuickActions/TweetQuickActionsFormatter.m`
- Modify: `tests/quick-actions/Test-TweetQuickActions.ps1`
- Modify: `tests/quick-actions/TweetQuickActionsFoundationTests.m`
- Modify: `tests/quick-actions/run-foundation-tests.sh`

- [ ] **Step 1: Add the failing formatter source contract**

Add `"Formatter"` to the script `ValidateSet`, add this function, add its
switch case, and invoke it from `All`:

```powershell
function Test-FormatterContract {
    $header = Get-RepoText "src/TweetQuickActions/TweetQuickActionsFormatter.h"
    $implementation =
        Get-RepoText "src/TweetQuickActions/TweetQuickActionsFormatter.m"

    foreach ($selector in @(
        "normalizedTextFromValue:",
        "authorWithName:handle:",
        "markdownWithText:author:URLString:"
    )) {
        Assert-Match ($header + $implementation) ([regex]::Escape($selector)) `
            "The formatter is missing $selector."
    }
    Assert-Match $implementation 'componentsSeparatedByString:@"\\n"' `
        "Markdown formatting does not process each line independently."
    Assert-Match $implementation '@"> %@".*@">"' `
        "Markdown formatting does not distinguish text and blank quote lines."
}
```

- [ ] **Step 2: Run the formatter contract and verify RED**

```powershell
& '.\tests\quick-actions\Test-TweetQuickActions.ps1' -Case Formatter
```

Expected: exit 1 reporting both missing formatter files and all three methods.

- [ ] **Step 3: Extend the executable golden tests before implementation**

Add this import to the test file:

```objc
#import "TweetQuickActions/TweetQuickActionsFormatter.h"
```

Add this test function before `main`:

```objc
static void TestFormatting(void) {
    AssertEqual([BHTTweetQuickActionsFormatter normalizedTextFromValue:
                     @"  First line\n\nSecond line  "],
                @"First line\n\nSecond line", @"trim and preserve lines");
    AssertEqual([BHTTweetQuickActionsFormatter normalizedTextFromValue:
                     [[NSAttributedString alloc] initWithString:@"Attributed"]],
                @"Attributed", @"attributed text");
    AssertEqual([BHTTweetQuickActionsFormatter authorWithName:@"Alice"
                                                       handle:@"@alice"],
                @"Alice (@alice)", @"full author");
    AssertEqual([BHTTweetQuickActionsFormatter authorWithName:nil
                                                       handle:@"alice"],
                @"@alice", @"handle-only author");
    AssertEqual([BHTTweetQuickActionsFormatter authorWithName:@"Alice"
                                                       handle:nil],
                @"Alice", @"name-only author");
    AssertEqual([BHTTweetQuickActionsFormatter markdownWithText:
                     @"First line\n\nSecond line"
                                                              author:@"Alice (@alice)"
                                                           URLString:@"https://x.com/alice/status/123"],
                @"> First line\n>\n> Second line\n\n— [Alice (@alice)](https://x.com/alice/status/123)",
                @"multiline Markdown");
    AssertEqual([BHTTweetQuickActionsFormatter markdownWithText:nil
                                                              author:@"Alice [A]"
                                                           URLString:@"https://x.com/alice/status/123"],
                @"— [Alice \\[A\\]](https://x.com/alice/status/123)",
                @"media-only Markdown and escaped label");
    AssertEqual([BHTTweetQuickActionsFormatter markdownWithText:@"Body"
                                                              author:nil
                                                           URLString:@"https://x.com/a/status/1"],
                @"> Body\n\n— https://x.com/a/status/1", @"URL-only attribution");
    AssertEqual([BHTTweetQuickActionsFormatter markdownWithText:@"Body"
                                                              author:nil
                                                           URLString:nil],
                @"> Body", @"body-only Markdown");
}
```

Call `TestFormatting();` immediately after `TestURLs();` in `main`.

Add the formatter implementation to `run-foundation-tests.sh`:

```bash
  "$root/src/TweetQuickActions/TweetQuickActionsFormatter.m" \
```

Run the shell test on macOS before creating the formatter. Expected: compiler
failure because the header and implementation do not exist. On Windows, the
PowerShell red result from Step 2 is the executable red gate available on the
host.

- [ ] **Step 4: Create the formatter interface**

Create `src/TweetQuickActions/TweetQuickActionsFormatter.h`:

```objc
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BHTTweetQuickActionsFormatter : NSObject
+ (NSString* _Nullable)normalizedTextFromValue:(id _Nullable)value;
+ (NSString* _Nullable)authorWithName:(NSString* _Nullable)name
                               handle:(NSString* _Nullable)handle;
+ (NSString* _Nullable)markdownWithText:(NSString* _Nullable)text
                                  author:(NSString* _Nullable)author
                               URLString:(NSString* _Nullable)URLString;
@end

NS_ASSUME_NONNULL_END
```

- [ ] **Step 5: Implement the formatter**

Create `src/TweetQuickActions/TweetQuickActionsFormatter.m`:

```objc
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
```

- [ ] **Step 6: Run formatter tests and verify GREEN**

```powershell
& '.\tests\quick-actions\Test-TweetQuickActions.ps1' -Case Formatter
& '.\tests\quick-actions\Test-TweetQuickActions.ps1' -Case All
bash tests/quick-actions/run-foundation-tests.sh
```

Expected on Windows: PowerShell exits 0 and the shell test explicitly skips.
Expected on macOS: the shell test exits 0 with `20 assertions`.

- [ ] **Step 7: Commit the formatter**

```powershell
git add -- src/TweetQuickActions/TweetQuickActionsFormatter.h `
    src/TweetQuickActions/TweetQuickActionsFormatter.m `
    tests/quick-actions/Test-TweetQuickActions.ps1 `
    tests/quick-actions/TweetQuickActionsFoundationTests.m `
    tests/quick-actions/run-foundation-tests.sh
git commit -m "Format Tweet quick action output"
```

## Task 4: Build the Immutable Context and Native Submenu

**Files:**
- Create: `src/TweetQuickActions/TweetQuickActionsProvider.h`
- Create: `src/TweetQuickActions/TweetQuickActionsProvider.m`
- Modify: `tests/quick-actions/Test-TweetQuickActions.ps1`

- [ ] **Step 1: Add the failing provider contract**

Add `"Provider"` to the script `ValidateSet`, add this function, add its switch
case, and invoke it from `All`:

```powershell
function Test-ProviderContract {
    $header = Get-RepoText "src/TweetQuickActions/TweetQuickActionsProvider.h"
    $implementation =
        Get-RepoText "src/TweetQuickActions/TweetQuickActionsProvider.m"

    Assert-Match $header '(?s)actionItemForStatus:.*entityURL:' `
        "The provider does not expose a focused action-item factory."
    Assert-Match $implementation '@interface\s+BHTTweetQuickActionsContext' `
        "The provider has no immutable snapshot type."
    Assert-Match $implementation '(?s)@try.*@catch' `
        "Private model reads are not bounded by an Objective-C exception guard."

    Assert-Match $implementation `
        '(?s)BHTQuickObjectGetter.*respondsToSelector:selector.*objc_msgSend' `
        "Object-returning private getters do not share one guarded dispatch helper."
    Assert-Match $implementation `
        '(?s)BHTQuickIntegerGetter.*respondsToSelector:selector.*objc_msgSend' `
        "Integer-returning private getters do not share one guarded dispatch helper."

    foreach ($selector in @(
        "plainTextSubject",
        "shareableAuthorName",
        "shareableAuthorHandle",
        "twitterURLForCopy",
        "statusID"
    )) {
        Assert-Match $implementation `
            ("BHTQuick(?:Object|Integer)Getter\s*\([^;]+@selector\(" +
             [regex]::Escape($selector) + "\)\s*\)") `
            "The provider does not route $selector through guarded dispatch."
    }

    Assert-Match $implementation 'setDisabled:' `
        "Unavailable submenu commands are not disabled."
    Assert-Match $implementation 'TFNMenuSheetViewController' `
        "The provider does not use Twitter's native second-level sheet."
    Assert-Match $implementation 'UIPasteboard.*string\s*=' `
        "The provider does not write selected output to the pasteboard."
    Assert-Match $implementation 'UIImpactFeedbackGeneratorStyleLight' `
        "Copy success does not emit the approved light haptic."
    Assert-Match $implementation 'hideAfterDelay:' `
        "The copied HUD is not dismissed nonblockingly."
    Assert-NotMatch $implementation 'MSHookFunction|MSFindSymbol|\$s4Grok|isPremiumUser' `
        "The provider introduced a prohibited Grok/function-hook path."
    Assert-NotMatch $implementation '%ctor|\+\s*\(void\)load|__attribute__\(\(constructor\)\)' `
        "The provider introduced startup-time execution."
    Assert-NotMatch $implementation 'NSURLSession|NSMutableURLRequest|dataTaskWith' `
        "The provider introduced network I/O."
}
```

- [ ] **Step 2: Run the provider contract and verify RED**

```powershell
& '.\tests\quick-actions\Test-TweetQuickActions.ps1' -Case Provider
```

Expected: exit 1 reporting both provider files and their required behavior as
missing.

- [ ] **Step 3: Create the provider interface**

Create `src/TweetQuickActions/TweetQuickActionsProvider.h`:

```objc
#import <Foundation/Foundation.h>

@class TFNActionItem;

NS_ASSUME_NONNULL_BEGIN

@interface TweetQuickActionsProvider : NSObject
- (TFNActionItem* _Nullable)actionItemForStatus:(id _Nullable)status
                                      entityURL:(id _Nullable)entityURL;
@end

NS_ASSUME_NONNULL_END
```

- [ ] **Step 4: Implement immutable extraction, menu actions, and feedback**

Create `src/TweetQuickActions/TweetQuickActionsProvider.m` with these complete
units in order:

```objc
#import "TweetQuickActionsProvider.h"
#import "TweetQuickActionsFormatter.h"
#import "Core/BHTShareURL.h"
#import "Hooks/HookHelpers.h"

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
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
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
            [BHTTweetQuickActionsFormatter authorWithName:displayName handle:handle];
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
            initWithStyle:UIImpactFeedbackGeneratorStyleLight];
    [feedback prepare];
    [feedback impactOccurred];

    Class hudClass = objc_getClass("TFNHUD");
    if (!hudClass) {
        return;
    }
    self.hud = [[hudClass alloc]
        initWithText:[[BHTBundle sharedBundle]
                         localizedStringForKey:@"TWEET_QUICK_ACTIONS_COPIED"]];
    [self.hud show];
    if ([self.hud respondsToSelector:@selector(hideAfterDelay:)]) {
        [self.hud hideAfterDelay:0.8];
    } else {
        TFNHUD* hud = self.hud;
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
    Class sheetClass = objc_getClass("TFNMenuSheetViewController");
    UIViewController* presenter = topMostController();
    if (!sheetClass || !presenter) {
        return;
    }

    NSMutableArray* items = [NSMutableArray array];
    NSArray* candidates = @[
        [self copyItemWithTitleKey:@"TWEET_QUICK_ACTIONS_COPY_TEXT"
                         imageName:@"news_stroke"
                              value:context.text] ?: NSNull.null,
        [self copyItemWithTitleKey:@"TWEET_QUICK_ACTIONS_COPY_LINK"
                         imageName:@"link"
                              value:context.URLString] ?: NSNull.null,
        [self copyItemWithTitleKey:@"TWEET_QUICK_ACTIONS_COPY_AUTHOR"
                         imageName:@"account"
                              value:context.author] ?: NSNull.null,
        [self copyItemWithTitleKey:@"TWEET_QUICK_ACTIONS_COPY_MARKDOWN"
                         imageName:@"copy_stroke"
                              value:context.markdown] ?: NSNull.null,
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
        !objc_getClass("TFNMenuSheetViewController")) {
        return nil;
    }

    BHTTweetQuickActionsContext* context =
        [self contextForStatus:status entityURL:entityURL];
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
```

Do not store `status`, `entityURL`, or any other hook argument as a property.
The block captures only the immutable context created before the hook returns.

- [ ] **Step 5: Run the provider and aggregate contracts and verify GREEN**

```powershell
& '.\tests\quick-actions\Test-TweetQuickActions.ps1' -Case Provider
& '.\tests\quick-actions\Test-TweetQuickActions.ps1' -Case All
```

Expected: both commands exit 0.

- [ ] **Step 6: Commit the provider**

```powershell
git add -- src/TweetQuickActions/TweetQuickActionsProvider.h `
    src/TweetQuickActions/TweetQuickActionsProvider.m `
    tests/quick-actions/Test-TweetQuickActions.ps1
git commit -m "Add Tweet quick actions provider"
```

## Task 5: Wire the Setting and Preserve Download Ordering

**Files:**
- Modify: `tests/quick-actions/Test-TweetQuickActions.ps1`
- Modify: `src/Core/BHTSettings.m:221-234`
- Modify: `src/Hooks/MediaDownloads.x:357-410`

- [ ] **Step 1: Add the failing wiring contract**

Add `"Wiring"` to the script `ValidateSet`, add this function, add its switch
case, and invoke it from `All`:

```powershell
function Test-WiringContract {
    $settings = Get-RepoText "src/Core/BHTSettings.m"
    $downloads = Get-RepoText "src/Hooks/MediaDownloads.x"

    Assert-Match $settings `
        '(?s)tweet_to_image.*tweet_quick_actions.*@"default":\s*@YES' `
        "tweet_quick_actions is not directly after Tweet-to-image with a YES default."
    Assert-Match $downloads `
        '#import\s+"TweetQuickActions/TweetQuickActionsProvider\.h"' `
        "The action-items hook does not import the provider."
    Assert-Match $downloads `
        'objc_getAssociatedObject\s*\([^,]+,\s*&quickActionsProviderKey\)' `
        "The presenting controller does not retain one provider."
    Assert-Match $downloads `
        '(?s)quickItem.*insertObject:quickItem.*downloadItem.*insertObject:downloadItem' `
        "Quick Actions is not inserted before Download Media."
    Assert-Match $downloads `
        '(?s)DownloadActionItemForController.*download_videos.*entities.*mediaType' `
        "Download eligibility was not preserved as an independent helper."

    $hookCount = ([regex]::Matches(
        $downloads, '(?m)^\s*%hook\s+UIViewController\s*$')).Count
    if ($hookCount -ne 1) {
        $failures.Add("Expected one UIViewController action-items hook, found $hookCount.")
    }
}
```

- [ ] **Step 2: Run the wiring contract and verify RED**

```powershell
& '.\tests\quick-actions\Test-TweetQuickActions.ps1' -Case Wiring
```

Expected: exit 1 with missing setting, provider import/retention, and ordering
messages.

- [ ] **Step 3: Register the default-enabled setting**

Insert immediately after the existing `tweet_to_image` dictionary in the
`tweets` page of `src/Core/BHTSettings.m`:

```objc
@{ @"key": @"tweet_quick_actions",
   @"default": @YES,
   @"type": @"toggle" },
```

No migration is added. `BHTSettings.boolForKey:` already returns the declared
default when no stored value exists.

- [ ] **Step 4: Extract the existing download item builder**

Above the existing `UIViewController` hook in `src/Hooks/MediaDownloads.x`,
move the current media checks and action construction into:

```objc
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
```

- [ ] **Step 5: Replace the hook body with independent item construction**

Add this import near the top of `MediaDownloads.x`:

```objc
#import "TweetQuickActions/TweetQuickActionsProvider.h"
```

Keep the existing method signature and replace only its body with:

```objc
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
```

- [ ] **Step 6: Run wiring, compatibility, and aggregate contracts**

```powershell
& '.\tests\quick-actions\Test-TweetQuickActions.ps1' -Case Wiring
& '.\tests\quick-actions\Test-TweetQuickActions.ps1' -Case All
& '.\tests\compatibility\Test-Twitter1214Compatibility.ps1' -Case All
```

Expected: all commands exit 0. Existing media-download assertions remain
green.

- [ ] **Step 7: Commit setting and hook integration**

```powershell
git add -- src/Core/BHTSettings.m src/Hooks/MediaDownloads.x `
    tests/quick-actions/Test-TweetQuickActions.ps1
git commit -m "Insert Tweet quick actions menu"
```

## Task 6: Add Complete Localizations

**Files:**
- Modify: `layout/Library/Application Support/BHT/BHTwitter.bundle/en.lproj/Localizable.strings`
- Modify: all 15 non-English `Localizable.strings` files in the same bundle
- Modify: `tests/quick-actions/Test-TweetQuickActions.ps1`

- [ ] **Step 1: Add the eight English keys**

Insert this block directly after `TWEET_TO_IMAGE_DETAIL` in English:

```text
"TWEET_QUICK_ACTIONS_TITLE" = "Tweet quick actions";
"TWEET_QUICK_ACTIONS_DETAIL" = "Copy Tweet text, a clean link, author details, or a Markdown quote.";
"TWEET_QUICK_ACTIONS_MENU_TITLE" = "Quick actions";
"TWEET_QUICK_ACTIONS_COPY_TEXT" = "Copy Tweet text";
"TWEET_QUICK_ACTIONS_COPY_LINK" = "Copy Tweet link";
"TWEET_QUICK_ACTIONS_COPY_AUTHOR" = "Copy author";
"TWEET_QUICK_ACTIONS_COPY_MARKDOWN" = "Copy as Markdown";
"TWEET_QUICK_ACTIONS_COPIED" = "Copied";
```

- [ ] **Step 2: Run localization and verify RED**

```powershell
& '.\tests\localization\Test-V6Localization.ps1' -Locale All
```

Expected: exit 1 listing the eight missing keys for every non-English locale.

- [ ] **Step 3: Add the approved native-language translations**

Insert each exact block after that locale's `TWEET_TO_IMAGE_DETAIL`.

`ar`:

```text
"TWEET_QUICK_ACTIONS_TITLE" = "إجراءات التغريدة السريعة";
"TWEET_QUICK_ACTIONS_DETAIL" = "انسخ نص التغريدة أو رابطًا نظيفًا أو بيانات صاحب التغريدة أو اقتباسًا بصيغة Markdown.";
"TWEET_QUICK_ACTIONS_MENU_TITLE" = "إجراءات سريعة";
"TWEET_QUICK_ACTIONS_COPY_TEXT" = "نسخ نص التغريدة";
"TWEET_QUICK_ACTIONS_COPY_LINK" = "نسخ رابط التغريدة";
"TWEET_QUICK_ACTIONS_COPY_AUTHOR" = "نسخ صاحب التغريدة";
"TWEET_QUICK_ACTIONS_COPY_MARKDOWN" = "نسخ بصيغة Markdown";
"TWEET_QUICK_ACTIONS_COPIED" = "تم النسخ";
```

`de`:

```text
"TWEET_QUICK_ACTIONS_TITLE" = "Tweet-Schnellaktionen";
"TWEET_QUICK_ACTIONS_DETAIL" = "Kopiere Tweet-Text, einen bereinigten Link, Autorendaten oder ein Markdown-Zitat.";
"TWEET_QUICK_ACTIONS_MENU_TITLE" = "Schnellaktionen";
"TWEET_QUICK_ACTIONS_COPY_TEXT" = "Tweet-Text kopieren";
"TWEET_QUICK_ACTIONS_COPY_LINK" = "Tweet-Link kopieren";
"TWEET_QUICK_ACTIONS_COPY_AUTHOR" = "Autor kopieren";
"TWEET_QUICK_ACTIONS_COPY_MARKDOWN" = "Als Markdown kopieren";
"TWEET_QUICK_ACTIONS_COPIED" = "Kopiert";
```

`es`:

```text
"TWEET_QUICK_ACTIONS_TITLE" = "Acciones rápidas de Tweets";
"TWEET_QUICK_ACTIONS_DETAIL" = "Copia el texto del Tweet, un enlace limpio, el autor o una cita en Markdown.";
"TWEET_QUICK_ACTIONS_MENU_TITLE" = "Acciones rápidas";
"TWEET_QUICK_ACTIONS_COPY_TEXT" = "Copiar texto del Tweet";
"TWEET_QUICK_ACTIONS_COPY_LINK" = "Copiar enlace del Tweet";
"TWEET_QUICK_ACTIONS_COPY_AUTHOR" = "Copiar autor";
"TWEET_QUICK_ACTIONS_COPY_MARKDOWN" = "Copiar como Markdown";
"TWEET_QUICK_ACTIONS_COPIED" = "Copiado";
```

`fr`:

```text
"TWEET_QUICK_ACTIONS_TITLE" = "Actions rapides pour les Tweets";
"TWEET_QUICK_ACTIONS_DETAIL" = "Copiez le texte du Tweet, un lien épuré, l’auteur ou une citation Markdown.";
"TWEET_QUICK_ACTIONS_MENU_TITLE" = "Actions rapides";
"TWEET_QUICK_ACTIONS_COPY_TEXT" = "Copier le texte du Tweet";
"TWEET_QUICK_ACTIONS_COPY_LINK" = "Copier le lien du Tweet";
"TWEET_QUICK_ACTIONS_COPY_AUTHOR" = "Copier l’auteur";
"TWEET_QUICK_ACTIONS_COPY_MARKDOWN" = "Copier au format Markdown";
"TWEET_QUICK_ACTIONS_COPIED" = "Copié";
```

`hr`:

```text
"TWEET_QUICK_ACTIONS_TITLE" = "Brze radnje za Tweet";
"TWEET_QUICK_ACTIONS_DETAIL" = "Kopirajte tekst Tweeta, čistu poveznicu, autora ili Markdown citat.";
"TWEET_QUICK_ACTIONS_MENU_TITLE" = "Brze radnje";
"TWEET_QUICK_ACTIONS_COPY_TEXT" = "Kopiraj tekst Tweeta";
"TWEET_QUICK_ACTIONS_COPY_LINK" = "Kopiraj poveznicu Tweeta";
"TWEET_QUICK_ACTIONS_COPY_AUTHOR" = "Kopiraj autora";
"TWEET_QUICK_ACTIONS_COPY_MARKDOWN" = "Kopiraj kao Markdown";
"TWEET_QUICK_ACTIONS_COPIED" = "Kopirano";
```

`id`:

```text
"TWEET_QUICK_ACTIONS_TITLE" = "Tindakan cepat Tweet";
"TWEET_QUICK_ACTIONS_DETAIL" = "Salin teks Tweet, tautan bersih, penulis, atau kutipan Markdown.";
"TWEET_QUICK_ACTIONS_MENU_TITLE" = "Tindakan cepat";
"TWEET_QUICK_ACTIONS_COPY_TEXT" = "Salin teks Tweet";
"TWEET_QUICK_ACTIONS_COPY_LINK" = "Salin tautan Tweet";
"TWEET_QUICK_ACTIONS_COPY_AUTHOR" = "Salin penulis";
"TWEET_QUICK_ACTIONS_COPY_MARKDOWN" = "Salin sebagai Markdown";
"TWEET_QUICK_ACTIONS_COPIED" = "Disalin";
```

`ja`:

```text
"TWEET_QUICK_ACTIONS_TITLE" = "ツイートのクイックアクション";
"TWEET_QUICK_ACTIONS_DETAIL" = "ツイート本文、追跡情報のないリンク、投稿者情報、Markdown形式の引用をすばやくコピーします。";
"TWEET_QUICK_ACTIONS_MENU_TITLE" = "クイックアクション";
"TWEET_QUICK_ACTIONS_COPY_TEXT" = "ツイート本文をコピー";
"TWEET_QUICK_ACTIONS_COPY_LINK" = "ツイートのリンクをコピー";
"TWEET_QUICK_ACTIONS_COPY_AUTHOR" = "投稿者をコピー";
"TWEET_QUICK_ACTIONS_COPY_MARKDOWN" = "Markdown形式でコピー";
"TWEET_QUICK_ACTIONS_COPIED" = "コピーしました";
```

`ko`:

```text
"TWEET_QUICK_ACTIONS_TITLE" = "트윗 빠른 작업";
"TWEET_QUICK_ACTIONS_DETAIL" = "트윗 본문, 추적 정보가 없는 링크, 작성자 정보 또는 Markdown 인용문을 복사합니다.";
"TWEET_QUICK_ACTIONS_MENU_TITLE" = "빠른 작업";
"TWEET_QUICK_ACTIONS_COPY_TEXT" = "트윗 본문 복사";
"TWEET_QUICK_ACTIONS_COPY_LINK" = "트윗 링크 복사";
"TWEET_QUICK_ACTIONS_COPY_AUTHOR" = "작성자 복사";
"TWEET_QUICK_ACTIONS_COPY_MARKDOWN" = "Markdown으로 복사";
"TWEET_QUICK_ACTIONS_COPIED" = "복사됨";
```

`pl`:

```text
"TWEET_QUICK_ACTIONS_TITLE" = "Szybkie działania dla Tweeta";
"TWEET_QUICK_ACTIONS_DETAIL" = "Kopiuj tekst Tweeta, czysty link, dane autora lub cytat Markdown.";
"TWEET_QUICK_ACTIONS_MENU_TITLE" = "Szybkie działania";
"TWEET_QUICK_ACTIONS_COPY_TEXT" = "Kopiuj tekst Tweeta";
"TWEET_QUICK_ACTIONS_COPY_LINK" = "Kopiuj link do Tweeta";
"TWEET_QUICK_ACTIONS_COPY_AUTHOR" = "Kopiuj autora";
"TWEET_QUICK_ACTIONS_COPY_MARKDOWN" = "Kopiuj jako Markdown";
"TWEET_QUICK_ACTIONS_COPIED" = "Skopiowano";
```

`ru`:

```text
"TWEET_QUICK_ACTIONS_TITLE" = "Быстрые действия с твитом";
"TWEET_QUICK_ACTIONS_DETAIL" = "Копируйте текст твита, чистую ссылку, данные автора или цитату в Markdown.";
"TWEET_QUICK_ACTIONS_MENU_TITLE" = "Быстрые действия";
"TWEET_QUICK_ACTIONS_COPY_TEXT" = "Копировать текст твита";
"TWEET_QUICK_ACTIONS_COPY_LINK" = "Копировать ссылку на твит";
"TWEET_QUICK_ACTIONS_COPY_AUTHOR" = "Копировать автора";
"TWEET_QUICK_ACTIONS_COPY_MARKDOWN" = "Копировать как Markdown";
"TWEET_QUICK_ACTIONS_COPIED" = "Скопировано";
```

`sv`:

```text
"TWEET_QUICK_ACTIONS_TITLE" = "Snabbåtgärder för Tweets";
"TWEET_QUICK_ACTIONS_DETAIL" = "Kopiera Tweet-text, en ren länk, författaren eller ett Markdown-citat.";
"TWEET_QUICK_ACTIONS_MENU_TITLE" = "Snabbåtgärder";
"TWEET_QUICK_ACTIONS_COPY_TEXT" = "Kopiera Tweet-text";
"TWEET_QUICK_ACTIONS_COPY_LINK" = "Kopiera Tweet-länk";
"TWEET_QUICK_ACTIONS_COPY_AUTHOR" = "Kopiera författare";
"TWEET_QUICK_ACTIONS_COPY_MARKDOWN" = "Kopiera som Markdown";
"TWEET_QUICK_ACTIONS_COPIED" = "Kopierat";
```

`tr`:

```text
"TWEET_QUICK_ACTIONS_TITLE" = "Tweet hızlı işlemleri";
"TWEET_QUICK_ACTIONS_DETAIL" = "Tweet metnini, temiz bağlantıyı, yazarı veya Markdown alıntısını kopyalayın.";
"TWEET_QUICK_ACTIONS_MENU_TITLE" = "Hızlı işlemler";
"TWEET_QUICK_ACTIONS_COPY_TEXT" = "Tweet metnini kopyala";
"TWEET_QUICK_ACTIONS_COPY_LINK" = "Tweet bağlantısını kopyala";
"TWEET_QUICK_ACTIONS_COPY_AUTHOR" = "Yazarı kopyala";
"TWEET_QUICK_ACTIONS_COPY_MARKDOWN" = "Markdown olarak kopyala";
"TWEET_QUICK_ACTIONS_COPIED" = "Kopyalandı";
```

`uk`:

```text
"TWEET_QUICK_ACTIONS_TITLE" = "Швидкі дії з твітами";
"TWEET_QUICK_ACTIONS_DETAIL" = "Копіюйте текст твіту, чисте посилання, дані автора або цитату Markdown.";
"TWEET_QUICK_ACTIONS_MENU_TITLE" = "Швидкі дії";
"TWEET_QUICK_ACTIONS_COPY_TEXT" = "Копіювати текст твіту";
"TWEET_QUICK_ACTIONS_COPY_LINK" = "Копіювати посилання на твіт";
"TWEET_QUICK_ACTIONS_COPY_AUTHOR" = "Копіювати автора";
"TWEET_QUICK_ACTIONS_COPY_MARKDOWN" = "Копіювати як Markdown";
"TWEET_QUICK_ACTIONS_COPIED" = "Скопійовано";
```

`zh_CN`:

```text
"TWEET_QUICK_ACTIONS_TITLE" = "推文快捷操作";
"TWEET_QUICK_ACTIONS_DETAIL" = "快速复制推文正文、无跟踪参数的链接、作者信息或 Markdown 引用。";
"TWEET_QUICK_ACTIONS_MENU_TITLE" = "快捷操作";
"TWEET_QUICK_ACTIONS_COPY_TEXT" = "复制推文正文";
"TWEET_QUICK_ACTIONS_COPY_LINK" = "复制推文链接";
"TWEET_QUICK_ACTIONS_COPY_AUTHOR" = "复制作者";
"TWEET_QUICK_ACTIONS_COPY_MARKDOWN" = "复制为 Markdown";
"TWEET_QUICK_ACTIONS_COPIED" = "已复制";
```

`zh-Hant`:

```text
"TWEET_QUICK_ACTIONS_TITLE" = "推文快速操作";
"TWEET_QUICK_ACTIONS_DETAIL" = "快速複製推文內文、無追蹤參數的連結、作者資訊或 Markdown 引用。";
"TWEET_QUICK_ACTIONS_MENU_TITLE" = "快速操作";
"TWEET_QUICK_ACTIONS_COPY_TEXT" = "複製推文內文";
"TWEET_QUICK_ACTIONS_COPY_LINK" = "複製推文連結";
"TWEET_QUICK_ACTIONS_COPY_AUTHOR" = "複製作者";
"TWEET_QUICK_ACTIONS_COPY_MARKDOWN" = "複製為 Markdown";
"TWEET_QUICK_ACTIONS_COPIED" = "已複製";
```

- [ ] **Step 4: Add a focused localization case**

Add `"Localization"` to the focused script `ValidateSet`, add this function,
add its switch case, and invoke it from `All`:

```powershell
function Test-LocalizationContract {
    $keys = @(
        "TWEET_QUICK_ACTIONS_TITLE",
        "TWEET_QUICK_ACTIONS_DETAIL",
        "TWEET_QUICK_ACTIONS_MENU_TITLE",
        "TWEET_QUICK_ACTIONS_COPY_TEXT",
        "TWEET_QUICK_ACTIONS_COPY_LINK",
        "TWEET_QUICK_ACTIONS_COPY_AUTHOR",
        "TWEET_QUICK_ACTIONS_COPY_MARKDOWN",
        "TWEET_QUICK_ACTIONS_COPIED"
    )
    $bundle = Join-Path $repoRoot `
        "layout\Library\Application Support\BHT\BHTwitter.bundle"
    foreach ($file in Get-ChildItem $bundle -Recurse -Filter Localizable.strings) {
        $text = [System.IO.File]::ReadAllText($file.FullName)
        foreach ($key in $keys) {
            Assert-Match $text ('"' + [regex]::Escape($key) + '"\s*=\s*".+";') `
                "$($file.Directory.Name) is missing or has an empty $key."
        }
    }
}
```

- [ ] **Step 5: Run focused and full localization tests and verify GREEN**

```powershell
& '.\tests\quick-actions\Test-TweetQuickActions.ps1' -Case Localization
& '.\tests\quick-actions\Test-TweetQuickActions.ps1' -Case All
& '.\tests\localization\Test-V6Localization.ps1' -Locale All
```

Expected: all commands exit 0; the full localization contract names all 15
non-English locales.

- [ ] **Step 6: Commit all translations together**

```powershell
git add -- 'layout/Library/Application Support/BHT/BHTwitter.bundle' `
    tests/quick-actions/Test-TweetQuickActions.ps1
git commit -m "Localize Tweet quick actions"
```

## Task 7: Aggregate Verification, Formatting, Push, and Rootless Build

**Files:**
- Modify: `.github/workflows/build.yml:66-72`
- Verify: every file changed by Tasks 1-6

- [ ] **Step 1: Run the Foundation golden tests in CI**

Insert immediately after `Checkout Main` in `.github/workflows/build.yml`:

```yaml
      - name: Test Tweet Quick Actions Foundation Helpers
        run: bash main/tests/quick-actions/run-foundation-tests.sh
```

- [ ] **Step 2: Format only touched Objective-C/Logos sources**

Run on a host with `bash` and `clang-format`:

```bash
./format.sh \
  src/Core/BHTShareURL.h \
  src/Core/BHTShareURL.m \
  src/Core/BHTSettings.m \
  src/Headers/TFNHeaders.h \
  src/Hooks/Misc.x \
  src/Hooks/MediaDownloads.x \
  src/TweetQuickActions/TweetQuickActionsFormatter.h \
  src/TweetQuickActions/TweetQuickActionsFormatter.m \
  src/TweetQuickActions/TweetQuickActionsProvider.h \
  src/TweetQuickActions/TweetQuickActionsProvider.m \
  tests/quick-actions/TweetQuickActionsFoundationTests.m
```

Then verify formatting without rewriting:

```bash
./format.sh --check \
  src/Core/BHTShareURL.h \
  src/Core/BHTShareURL.m \
  src/Core/BHTSettings.m \
  src/Headers/TFNHeaders.h \
  src/Hooks/Misc.x \
  src/Hooks/MediaDownloads.x \
  src/TweetQuickActions/TweetQuickActionsFormatter.h \
  src/TweetQuickActions/TweetQuickActionsFormatter.m \
  src/TweetQuickActions/TweetQuickActionsProvider.h \
  src/TweetQuickActions/TweetQuickActionsProvider.m \
  tests/quick-actions/TweetQuickActionsFoundationTests.m
```

Expected: the check prints no `would reformat` lines and exits 0.

- [ ] **Step 3: Run every fresh local verification gate**

```powershell
& '.\tests\quick-actions\Test-TweetQuickActions.ps1' -Case All
& '.\tests\compatibility\Test-Twitter1214Compatibility.ps1' -Case All
& '.\tests\localization\Test-V6Localization.ps1' -Locale All
bash tests/quick-actions/run-foundation-tests.sh
git diff --check
```

Expected: all three PowerShell suites and `git diff --check` exit 0. The
Foundation shell test passes on macOS or prints its explicit skip on Windows.

- [ ] **Step 4: Audit scope and prohibited symbols**

```powershell
$prohibited = rg -n 'MSHookFunction|MSFindSymbol|\$s4Grok|isPremiumUser' `
    src/TweetQuickActions src/Core/BHTShareURL.h src/Core/BHTShareURL.m `
    src/Hooks/MediaDownloads.x
if ($LASTEXITCODE -eq 0) { throw "Prohibited symbols found:`n$prohibited" }
if ($LASTEXITCODE -ne 1) { throw "Prohibited-symbol scan failed." }
git status --short
git diff --stat
```

Expected: `rg` returns no matches. Git lists only Quick Actions, shared URL,
settings, localization, tests, and workflow files.

- [ ] **Step 5: Commit the CI and formatting checkpoint**

```powershell
git add -- .github/workflows/build.yml `
    src/Core/BHTShareURL.h `
    src/Core/BHTShareURL.m `
    src/Core/BHTSettings.m `
    src/Headers/TFNHeaders.h `
    src/Hooks/Misc.x `
    src/Hooks/MediaDownloads.x `
    src/TweetQuickActions/TweetQuickActionsFormatter.h `
    src/TweetQuickActions/TweetQuickActionsFormatter.m `
    src/TweetQuickActions/TweetQuickActionsProvider.h `
    src/TweetQuickActions/TweetQuickActionsProvider.m `
    tests/quick-actions/TweetQuickActionsFoundationTests.m
git commit -m "Test Tweet quick actions integration"
```

- [ ] **Step 6: Re-run verification from the committed tree and push**

```powershell
& '.\tests\quick-actions\Test-TweetQuickActions.ps1' -Case All
& '.\tests\compatibility\Test-Twitter1214Compatibility.ps1' -Case All
& '.\tests\localization\Test-V6Localization.ps1' -Locale All
git diff --check
git status -sb
git push origin v6
```

Expected: tests exit 0, the worktree is clean, and `origin/v6` advances to the
exact local HEAD.

- [ ] **Step 7: Dispatch and watch the exact rootless build**

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

$runId = gh run list --repo hugotang/NeoFreeBird --workflow build.yml `
    --branch v6 --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $runId --repo hugotang/NeoFreeBird --interval 10 --exit-status
gh run view $runId --repo hugotang/NeoFreeBird `
    --json status,conclusion,headSha,url
```

Expected: the Foundation helper step and `Build Package` both succeed,
conclusion is `success`, and `headSha` equals `git rev-parse HEAD`.

- [ ] **Step 8: Verify local and remote SHAs match**

```powershell
$head = git rev-parse HEAD
$remote = (git ls-remote origin refs/heads/v6).Split()[0]
if ($head -ne $remote) { throw "HEAD $head does not match origin/v6 $remote" }
git status --porcelain
```

Expected: the SHAs match and `git status --porcelain` is empty.

## Task 8: Twitter 12.14 Device Acceptance

**Files:**
- No source changes unless a device check exposes a reproducible defect.

- [ ] **Step 1: Verify startup safety in both account states**

Install the exact CI artifact twice:

1. Fresh install with no logged-in account: the bird splash must advance to the
   login UI.
2. Upgrade over an already logged-in installation: the bird splash must advance
   to the timeline.

Any splash hang blocks completion and returns to a failing regression test plus
the `superpowers:systematic-debugging` workflow.

- [ ] **Step 2: Verify menu placement and setting behavior**

Check a normal Tweet and a Tweet with downloadable video:

- default state shows `Quick Actions`;
- video order is `Quick Actions`, `Download Media`, native final item;
- disabling `Tweet quick actions` removes only Quick Actions;
- Download Media continues to work while its own setting is enabled;
- re-enabling the setting restores Quick Actions without restarting Twitter.

- [ ] **Step 3: Verify exact clipboard outputs**

Use a Tweet by `Alice` (`@alice`) with ID `123`, text
`First line\n\nSecond line`, and no custom sharing domain.

Expected outputs:

```text
Copy Tweet Text:
First line

Second line

Copy Tweet Link:
https://x.com/alice/status/123

Copy Author:
Alice (@alice)

Copy as Markdown:
> First line
>
> Second line

— [Alice (@alice)](https://x.com/alice/status/123)
```

Repeat with a custom sharing domain and confirm only the host changes. Repeat
with a source link containing `s` and `t`; neither parameter may remain.

- [ ] **Step 4: Verify fallback cases**

- Quote Tweet: copied text contains only the outer body.
- Media-only Tweet: Copy Tweet Text is disabled; Markdown contains only the
  author attribution/link.
- Missing display name: author becomes `@handle`.
- Missing author but valid link: Markdown attribution is `— URL`.
- Missing URL: Copy Tweet Link is disabled while text/author actions remain.
- Every successful command emits one light haptic and a short localized
  `Copied` HUD; disabled commands emit neither.

- [ ] **Step 5: Record final evidence**

Report the implementation commit, GitHub Actions URL, matching local/remote
SHA, focused/compatibility/localization results, fresh-install result,
logged-in-upgrade result, and each clipboard fallback result. Only then mark
Tweet Quick Actions complete.
