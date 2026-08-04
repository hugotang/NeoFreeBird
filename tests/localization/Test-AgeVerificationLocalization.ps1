Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$bundleRoot = Join-Path $repoRoot "layout\Library\Application Support\BHT\BHTwitter.bundle"
$requiredKeys = @(
    "BYPASS_AGE_VERIFICATION_OPTION_TITLE",
    "BYPASS_AGE_VERIFICATION_OPTION_DETAIL_TITLE"
)
$failures = [System.Collections.Generic.List[string]]::new()

function Get-LocalizedStrings {
    param([string]$Path)

    $strings = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*"(?<key>[^"]+)"\s*=\s*"(?<value>(?:\\.|[^"])*)"\s*;\s*$') {
            $strings[$Matches.key] = $Matches.value
        }
    }

    return $strings
}

$englishPath = Join-Path $bundleRoot "en.lproj\Localizable.strings"
$englishStrings = Get-LocalizedStrings $englishPath

foreach ($localizationDirectory in Get-ChildItem $bundleRoot -Directory -Filter "*.lproj" | Sort-Object Name) {
    $locale = $localizationDirectory.Name -replace '\.lproj$', ''
    $stringsPath = Join-Path $localizationDirectory.FullName "Localizable.strings"
    $strings = Get-LocalizedStrings $stringsPath

    foreach ($key in $requiredKeys) {
        if (-not $strings.ContainsKey($key)) {
            $failures.Add("$locale is missing $key")
            continue
        }

        $value = $strings[$key]
        if ([string]::IsNullOrWhiteSpace($value) -or $value -eq $key) {
            $failures.Add("$locale has an empty or unresolved value for $key")
        }

        if ($locale -ne "en" -and $value -eq $englishStrings[$key]) {
            $failures.Add("$locale still uses the English value for $key")
        }
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host "FAIL: $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host "Age-verification localization coverage passed."
