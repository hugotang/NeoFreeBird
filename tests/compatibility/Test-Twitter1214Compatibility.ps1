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
