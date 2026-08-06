param(
    [ValidateSet("Mappings", "URL", "Formatter", "Provider", "Wiring", "Localization", "All")]
    [string]$Case = "Mappings"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$failures = [System.Collections.Generic.List[string]]::new()
$mappingPatterns = @{
    ActionItem = '(?m)^[ \t]*@property[ \t]*\([ \t]*nonatomic[ \t]*,[ \t]*assign[ \t]*,[ \t]*getter[ \t]*=[ \t]*isDisabled[ \t]*\)[ \t]*BOOL[ \t]+disabled[ \t]*;[ \t]*$'
    HUD = '(?m)^[ \t]*-[ \t]*\([ \t]*void[ \t]*\)[ \t]*hideAfterDelay[ \t]*:[ \t]*\([ \t]*NSTimeInterval[ \t]*\)[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*;[ \t]*$'
    Status = [ordered]@{
        plainTextSubject = '(?m)^[ \t]*-[ \t]*\([ \t]*NSString[ \t]*\*[ \t]*\)[ \t]*plainTextSubject[ \t]*;[ \t]*$'
        shareableAuthorName = '(?m)^[ \t]*-[ \t]*\([ \t]*NSString[ \t]*\*[ \t]*\)[ \t]*shareableAuthorName[ \t]*;[ \t]*$'
        shareableAuthorHandle = '(?m)^[ \t]*-[ \t]*\([ \t]*NSString[ \t]*\*[ \t]*\)[ \t]*shareableAuthorHandle[ \t]*;[ \t]*$'
        twitterURLForCopy = '(?m)^[ \t]*-[ \t]*\([ \t]*NSString[ \t]*\*[ \t]*\)[ \t]*twitterURLForCopy[ \t]*;[ \t]*$'
    }
}

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
    if (-not [regex]::IsMatch(
            $Text, $Pattern,
            [Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
        $failures.Add($Message)
    }
}

function Assert-NotMatch {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ([regex]::IsMatch(
            $Text, $Pattern,
            [Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
        $failures.Add($Message)
    }
}

function Get-ObjectiveCInterfaceBlock {
    param([string]$Text, [string]$InterfaceName)

    $escapedName = [regex]::Escape($InterfaceName)
    $pattern = "(?ms)^[ \t]*@interface[ \t]+$escapedName(?=[ \t:(]|\r?$)(?:[ \t]*:[^\r\n]+)?[^\r\n]*\r?\n.*?^[ \t]*@end\b"
    return [regex]::Match($Text, $pattern).Value
}

function Test-MappingsContract {
    $headers = Get-RepoText "src/Headers/TFNHeaders.h"
    $actionItem = Get-ObjectiveCInterfaceBlock $headers "TFNActionItem"
    $hud = Get-ObjectiveCInterfaceBlock $headers "TFNHUD"
    $status = Get-ObjectiveCInterfaceBlock $headers "TFNTwitterStatus"

    foreach ($selector in $mappingPatterns.Status.Keys) {
        Assert-Match $status $mappingPatterns.Status[$selector] `
            "TFNTwitterStatus is missing the verified $selector declaration."
    }

    Assert-Match $actionItem $mappingPatterns.ActionItem `
        "TFNActionItem does not expose the verified disabled setter."
    Assert-Match $hud $mappingPatterns.HUD `
        "TFNHUD does not expose the verified delayed-hide selector."
    Assert-NotMatch $headers 'isPremiumUser|\$s4Grok|MSHookFunction|MSFindSymbol' `
        "Grok Premium or function-hook declarations entered the Quick Actions mapping surface."
}

function Test-MappingsPatternGuardrails {
    $invalidHeaders = @'
@interface TFNActionItemLookalike : NSObject
@property (nonatomic, assign, getter=isDisabled) BOOL disabled;
@end

@interface TFNHUDLookalike : NSObject
- (void)hideAfterDelay:(NSTimeInterval)delay;
@end

@interface TFNTwitterStatusLookalike : NSObject
- (NSString*)plainTextSubject;
- (NSString*)shareableAuthorName;
- (NSString*)shareableAuthorHandle;
- (NSString*)twitterURLForCopy;
@end

@interface TFNActionItem : NSObject
@property (nonatomic, readonly, getter=isDisabled) BOOL disabled;
@end

@interface TFNHUD : NSObject
+ (int)hideAfterDelay:(NSTimeInterval)delay;
@end

@interface TFNTwitterStatus : NSObject
// - (NSString*)plainTextSubject;
- (NSString*)PlainTextSubject;
- (id)shareableAuthorName;
- (NSString*)shareableAuthorHandle:(id)value;
- (NSString*)twitterURLForCopy { return nil; }
@end
'@
    $actionItem = Get-ObjectiveCInterfaceBlock $invalidHeaders "TFNActionItem"
    $hud = Get-ObjectiveCInterfaceBlock $invalidHeaders "TFNHUD"
    $status = Get-ObjectiveCInterfaceBlock $invalidHeaders "TFNTwitterStatus"

    foreach ($selector in $mappingPatterns.Status.Keys) {
        Assert-NotMatch $status $mappingPatterns.Status[$selector] `
            "Mapping guardrail accepted an invalid $selector declaration."
    }
    Assert-NotMatch $actionItem $mappingPatterns.ActionItem `
        "Mapping guardrail accepted a readonly disabled property."
    Assert-NotMatch $hud $mappingPatterns.HUD `
        "Mapping guardrail accepted a class method with the wrong return type."
}

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

function Test-FormatterContract {
    $header = Get-RepoText "src/TweetQuickActions/TweetQuickActionsFormatter.h"
    $implementation =
        Get-RepoText "src/TweetQuickActions/TweetQuickActionsFormatter.m"

    $selectorPatterns = [ordered]@{
        "normalizedTextFromValue:" =
            'normalizedTextFromValue\s*:\s*\([^)]*\)\s*[A-Za-z_][A-Za-z0-9_]*'
        "authorWithName:handle:" =
            '(?s)authorWithName\s*:\s*\([^)]*\)\s*[A-Za-z_][A-Za-z0-9_]*\s+handle\s*:'
        "markdownWithText:author:URLString:" =
            '(?s)markdownWithText\s*:\s*\([^)]*\)\s*[A-Za-z_][A-Za-z0-9_]*\s+author\s*:\s*\([^)]*\)\s*[A-Za-z_][A-Za-z0-9_]*\s+URLString\s*:'
    }
    foreach ($selector in $selectorPatterns.Keys) {
        Assert-Match ($header + $implementation) $selectorPatterns[$selector] `
            "The formatter is missing $selector."
    }
    Assert-Match $implementation 'componentsSeparatedByString:@"\\n"' `
        "Markdown formatting does not process each line independently."
    Assert-Match $implementation '(?s)@"> %@".*@">"' `
        "Markdown formatting does not distinguish text and blank quote lines."
}

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
    Assert-Match $implementation `
        'instancesRespondToSelector:@selector\(initWithTitle:actionItems:\)' `
        "The provider does not capability-check the native sheet initializer."
    Assert-Match $implementation `
        '(?s)instancesRespondToSelector\s*:\s*@selector\(\s*tfnPresentedCustomPresentFromViewController\s*:\s*animated\s*:\s*completion\s*:\s*\)' `
        "The provider does not capability-check native sheet presentation."
    Assert-Match $implementation 'UIPasteboard.*string\s*=' `
        "The provider does not write selected output to the pasteboard."
    Assert-Match $implementation 'UIImpactFeedbackStyleLight' `
        "Copy success does not emit the approved light haptic."
    Assert-NotMatch $implementation 'UIImpactFeedbackGeneratorStyleLight' `
        "The provider uses a nonexistent UIKit haptic enum."
    Assert-Match $implementation 'hideAfterDelay:' `
        "The copied HUD is not dismissed nonblockingly."
    Assert-Match $implementation `
        'instancesRespondToSelector:@selector\(initWithText:\)' `
        "The provider does not capability-check HUD construction."
    Assert-Match $implementation 'respondsToSelector:@selector\(show\)' `
        "The provider does not capability-check HUD presentation."
    Assert-Match $implementation 'respondsToSelector:@selector\(hide\)' `
        "The provider does not capability-check the fallback HUD dismissal."
    Assert-NotMatch $implementation 'MSHookFunction|MSFindSymbol|\$s4Grok|isPremiumUser' `
        "The provider introduced a prohibited Grok/function-hook path."
    Assert-NotMatch $implementation '%ctor|\+\s*\(void\)load|__attribute__\(\(constructor\)\)' `
        "The provider introduced startup-time execution."
    Assert-NotMatch $implementation 'NSURLSession|NSMutableURLRequest|dataTaskWith' `
        "The provider introduced network I/O."
}

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

switch ($Case) {
    "Mappings" {
        Test-MappingsContract
        Test-MappingsPatternGuardrails
    }
    "URL" { Test-URLContract }
    "Formatter" { Test-FormatterContract }
    "Provider" { Test-ProviderContract }
    "Wiring" { Test-WiringContract }
    "Localization" { Test-LocalizationContract }
    "All" {
        Test-MappingsContract
        Test-MappingsPatternGuardrails
        Test-URLContract
        Test-FormatterContract
        Test-ProviderContract
        Test-WiringContract
        Test-LocalizationContract
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host "FAIL: $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host "Tweet Quick Actions contract passed: $Case"
