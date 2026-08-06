param(
    [ValidateSet("Mappings", "URL", "All")]
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

switch ($Case) {
    "Mappings" {
        Test-MappingsContract
        Test-MappingsPatternGuardrails
    }
    "URL" { Test-URLContract }
    "All" {
        Test-MappingsContract
        Test-MappingsPatternGuardrails
        Test-URLContract
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host "FAIL: $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host "Tweet Quick Actions contract passed: $Case"
