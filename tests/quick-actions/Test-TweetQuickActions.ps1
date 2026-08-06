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
