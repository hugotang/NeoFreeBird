param(
    [ValidateSet(
        "All", "ar", "de", "es", "fr", "hr", "id", "ja", "ko",
        "pl", "ru", "sv", "tr", "uk", "zh_CN", "zh-Hant"
    )]
    [string[]]$Locale = @("All")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$bundleRoot = Join-Path $repoRoot "layout\Library\Application Support\BHT\BHTwitter.bundle"
$supportedLocales = @(
    "ar", "de", "es", "fr", "hr", "id", "ja", "ko",
    "pl", "ru", "sv", "tr", "uk", "zh_CN", "zh-Hant"
)
$selectedLocales = if ($Locale -contains "All") {
    $supportedLocales
} else {
    @($Locale | Select-Object -Unique)
}
$failures = [System.Collections.Generic.List[string]]::new()

function Get-StringsFile {
    param([string]$Path)

    $values = @{}
    $duplicates = [System.Collections.Generic.List[string]]::new()
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*"(?<key>(?:\\.|[^"])*)"\s*=\s*"(?<value>(?:\\.|[^"])*)"\s*;\s*$') {
            $key = $Matches.key
            if ($values.ContainsKey($key)) {
                $duplicates.Add($key)
            }
            $values[$key] = $Matches.value
        }
    }

    return [PSCustomObject]@{
        Values = $values
        Duplicates = @($duplicates)
    }
}

function Get-FormatTokens {
    param([string]$Value)

    $pattern = '(?<!%)%(?:\d+\$)?(?:@|(?:hh|h|ll|l|z|t|j)?[diuoxXfFeEgGaAcsp])'
    return @([regex]::Matches($Value, $pattern) | ForEach-Object { $_.Value })
}

function Get-EscapedNewlineCount {
    param([string]$Value)

    return [regex]::Matches($Value, '\\n').Count
}

$baseAllowedEnglishValues = @(
    "MODERN_SETTINGS_GROK_TITLE",
    "NFB_SETTINGS_TITLE"
)
$localeAllowedEnglishValues = @{
    de = @(
        "DOWNLOAD_VIDEO_NUMBER_TITLE",
        "MODERN_SETTINGS_BRANDING_TITLE",
        "MODERN_SETTINGS_DEBUG_TITLE",
        "MODERN_SETTINGS_TIMELINES_TITLE"
    )
    es = @("MODERN_SETTINGS_LAYOUT_TITLE")
    id = @("MODERN_SETTINGS_BRANDING_TITLE", "MODERN_SETTINGS_DEBUG_TITLE")
    sv = @("DOWNLOAD_VIDEO_NUMBER_TITLE")
    tr = @("DOWNLOAD_VIDEO_NUMBER_TITLE")
}

$englishPath = Join-Path $bundleRoot "en.lproj\Localizable.strings"
$englishResult = Get-StringsFile $englishPath
$english = $englishResult.Values
if ($englishResult.Duplicates.Count -gt 0) {
    $failures.Add("en contains duplicate keys: $($englishResult.Duplicates -join ', ')")
}

$actualLocales = @(
    Get-ChildItem $bundleRoot -Directory -Filter "*.lproj" |
        ForEach-Object { $_.Name -replace '\.lproj$', '' } |
        Where-Object { $_ -ne "en" } |
        Sort-Object
)
$localeSetDifference = @(Compare-Object ($supportedLocales | Sort-Object) $actualLocales)
if ($localeSetDifference.Count -gt 0) {
    $failures.Add("Locale directory set differs from the supported locale contract.")
}

foreach ($localeName in $selectedLocales) {
    $path = Join-Path $bundleRoot "$localeName.lproj\Localizable.strings"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $failures.Add("$localeName is missing Localizable.strings")
        continue
    }

    $result = Get-StringsFile $path
    $localized = $result.Values
    if ($result.Duplicates.Count -gt 0) {
        $failures.Add("$localeName contains duplicate keys: $($result.Duplicates -join ', ')")
    }

    $missingKeys = @($english.Keys | Where-Object { -not $localized.ContainsKey($_) } | Sort-Object)
    $extraKeys = @($localized.Keys | Where-Object { -not $english.ContainsKey($_) } | Sort-Object)
    if ($missingKeys.Count -gt 0) {
        $failures.Add("$localeName is missing keys: $($missingKeys -join ', ')")
    }
    if ($extraKeys.Count -gt 0) {
        $failures.Add("$localeName has extra keys: $($extraKeys -join ', ')")
    }

    $allowedEnglishValues = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($key in $baseAllowedEnglishValues) {
        [void]$allowedEnglishValues.Add($key)
    }
    if ($localeAllowedEnglishValues.ContainsKey($localeName)) {
        foreach ($key in $localeAllowedEnglishValues[$localeName]) {
            [void]$allowedEnglishValues.Add($key)
        }
    }

    foreach ($key in $english.Keys) {
        if (-not $localized.ContainsKey($key)) {
            continue
        }

        $value = $localized[$key]
        if ([string]::IsNullOrWhiteSpace($value) -or $value -ceq $key) {
            $failures.Add("$localeName has an empty or unresolved value for $key")
        }

        if ($value -ceq $english[$key] -and -not $allowedEnglishValues.Contains($key)) {
            $failures.Add("$localeName still uses English for $key")
        }

        $englishTokens = (Get-FormatTokens $english[$key]) -join "`n"
        $localizedTokens = (Get-FormatTokens $value) -join "`n"
        if ($localizedTokens -cne $englishTokens) {
            $failures.Add("$localeName changed format tokens for $key")
        }

        $englishNewlines = Get-EscapedNewlineCount $english[$key]
        $localizedNewlines = Get-EscapedNewlineCount $value
        if ($localizedNewlines -ne $englishNewlines) {
            $failures.Add("$localeName changed escaped newline count for $key")
        }
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host "FAIL: $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host "V6 localization contract passed: $($selectedLocales -join ', ')"
