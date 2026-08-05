param(
    [ValidateSet(
        "Tab", "Timestamp", "Launch", "LoggedOut", "Upload", "Premium",
        "LikeKey", "Spaces", "LegacyDM", "Retained", "Wiring", "All"
    )]
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

function Get-SourceTreeText {
    $sourceRoot = Join-Path $repoRoot "src"
    return @(
        Get-ChildItem -LiteralPath $sourceRoot -Recurse -File |
            Where-Object { $_.Extension -in @(".h", ".m", ".x") } |
            ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }
    ) -join "`n"
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
    $header = Get-RepoText "src/Compatibility/BHTTabBarCompatibility.h"
    $source = Get-RepoText "src/Compatibility/BHTTabBarCompatibility.m"

    Assert-Match $header 'BHTInstallTabBarCompatibility' `
        "The tab compatibility installer is not exported."
    Assert-Match $header 'BHTApplyCurrentThemeToTabBarController' `
        "The shared tab theme helper is not exported."
    Assert-Match $source '_t1_updateAppearance:' `
        "The Twitter 12.14 tab appearance selector is not targeted."
    Assert-Match $source 'class_getInstanceMethod' `
        "The tab selector is not capability-gated."
    Assert-Match $source 'MSHookMessageEx' `
        "The tab callback is not installed with a runtime hook."
    Assert-Match $source 'NSInteger\s+appearance' `
        "The tab appearance callback does not use the verified signed 64-bit argument type."
    Assert-Match $source 'applyCurrentThemeToIcon' `
        "The tab adapter does not invoke v6 tab icon theming."
    Assert-Match $source `
        '(?s)BHTOriginalTabAppearance\(self, selector, appearance\);.*BHTApplyCurrentThemeToTabBarController\(self\);' `
        "The tab adapter must call Twitter before reapplying the v6 theme."
}

function Test-TimestampContract {
    $header = Get-RepoText "src/Compatibility/BHTImmersiveTimestampCompatibility.h"
    $source = Get-RepoText "src/Compatibility/BHTImmersiveTimestampCompatibility.m"
    $legacySource = Get-RepoText "src/Hooks/ImmersivePlayer.x"

    Assert-Match $header 'BHTInstallImmersiveTimestampCompatibility' `
        "The immersive timestamp installer is not exported."
    Assert-Match $source 'T1TwitterSwift\.ImmersiveCardView' `
        "The module-qualified ImmersiveCardView class name is not resolved."
    Assert-Match $source '_TtC14T1TwitterSwift17ImmersiveCardView' `
        "The mangled ImmersiveCardView class fallback is missing."
    Assert-Match $source 'layoutSubviews' `
        "The Twitter 12.14 immersive layout selector is not targeted."
    Assert-Match $source 'class_getInstanceMethod' `
        "The immersive layout selector is not capability-gated."
    Assert-Match $source 'MSHookMessageEx' `
        "The immersive callback is not installed with a runtime hook."
    Assert-Match $source 'restore_video_timestamp' `
        "The v6 timestamp preference is not respected."
    Assert-Match $source 'BHTTimestampMaximumVisitedViews\s*=\s*100' `
        "The immersive timestamp traversal is not bounded to 100 views."
    Assert-Match $source 'NSRegularExpression' `
        "The timestamp label is not identified by a text contract."
    Assert-Match $source 'sizeToFit' `
        "The timestamp label is not sized before padding is applied."
    Assert-Match $source 'cornerRadius' `
        "The timestamp label pill styling is incomplete."
    Assert-Match $source `
        '(?s)BHTOriginalImmersiveCardLayoutSubviews\(self, selector\);.*restore_video_timestamp.*BHTStyleTimestampLabel' `
        "The immersive adapter must call Twitter before applying enabled timestamp styling."
    Assert-NotMatch $source 'setHidden:|\.hidden\s*=|setAlpha:|\.alpha\s*=' `
        "The Twitter 12.14 timestamp adapter must not force control visibility."
    Assert-Match $legacySource 'cardStateFieldIndexNamed' `
        "The legacy alpha hook does not resolve shifted Swift state fields by name."
    Assert-Match $legacySource '"isPanningBetweenCards"' `
        "The legacy alpha hook does not resolve the panning field dynamically."
    Assert-Match $legacySource '"isChromeFadedOutWhilePanning"' `
        "The legacy alpha hook does not resolve the chrome-fade field dynamically."
    Assert-NotMatch $legacySource `
        'CardStateFieldIsPanningBetweenCards\s*=\s*19|CardStateFieldIsChromeFadedOutWhilePanning\s*=\s*20' `
        "The legacy alpha hook still hard-codes the pre-12.14 Swift field indexes."
}

function Test-LaunchContract {
    $allSources = Get-SourceTreeText
    $lifecycle = Get-RepoText "src/Hooks/AppLifecycle.x"
    $switches = Get-RepoText "src/Hooks/FeatureSwitches.x"

    Assert-Match $lifecycle '%hook\s+T1AnimatedLaunchScreenView' `
        "The v6 animated launch view path is missing."
    Assert-Match $switches 'app_launch_animated_launch_screen_enabled' `
        "The v6 animated launch feature switch is missing."
    Assert-NotMatch $allSources 'launchTransitionProvider|T1AppLaunchTransition' `
        "The removed legacy launch transition path was reintroduced."
}

function Test-LoggedOutLaunchContract {
    $switches = Get-RepoText "src/Hooks/FeatureSwitches.x"
    $legacyLogin = Get-RepoText "src/LegacyLogin/LegacyLoginViewController.m"

    Assert-Match $switches 'NSClassFromString\(@"BootViewController"\)' `
        "The signed-out startup path is not capability-gated for Twitter 12.14's BootViewController."
    Assert-Match $switches `
        '(?s)- \(void\)viewBootViewController\s*\{.*accounts.*count.*viewSignedOutAnimated:.*return;.*%orig;' `
        "An empty account store does not bypass Twitter 12.14's blocking BootViewController while preserving the native fallback."
    Assert-Match $switches 'void\s*\(\^nativeCompletion\)\(id\)' `
        "The signed-out onboarding hook does not preserve Twitter's native completion chain."
    Assert-Match $switches '%orig\(nativeCompletion\)' `
        "The signed-out onboarding hook bypasses Twitter's 12.14 Quick Auth initialization."
    Assert-Match $switches `
        '(?s)nativeCompletion.*completion\(\[LegacyLoginViewController loginRootNavigationController\]\)' `
        "The native onboarding completion does not replace the final screen with the legacy login."
    Assert-NotMatch $switches `
        '(?s)if \(completion == nil\) \{\s*%orig;\s*return;\s*\}\s*completion\(' `
        "The legacy login is still delivered synchronously before signed-out initialization finishes."
    Assert-Match $legacyLogin 'NSClassFromString\(@"TFNNavigationController"\)' `
        "The signed-out login root does not prefer Twitter's native navigation controller."
    Assert-Match $legacyLogin 'setSupportsInteractivePops:' `
        "The signed-out login root does not mirror Twitter's onboarding navigation contract."
}

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

function Test-LikeKeyContract {
    $confirmations = Get-RepoText "src/Hooks/Confirmations.x"

    Assert-Match $confirmations `
        '(?s)%hook\s+T1StatusCell.*handleLikeKeyCommand.*like_confirm.*ShowConfirmation.*%orig;' `
        "Keyboard-triggered likes do not pass through the shared confirmation flow."
}

function Test-SpacesContract {
    $timeline = Get-RepoText "src/Hooks/Timeline.x"

    Assert-Match $timeline `
        '(?s)_t1_configureFleets_helper.*!\[BHTSettings boolForKey:@"hide_spaces"\].*%orig;.*return;.*_t1_removeFleetLineView' `
        "The configured Spaces line is not removed while preserving the native enabled path."
    Assert-Match $timeline `
        '(?s)_t1_shouldShowFleetLine.*hide_spaces.*return NO;.*%orig;' `
        "The Spaces visibility gate no longer preserves its native fallback."
}

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
        '(?s)visibleMediaForwardView.*T1InlineMediaView.*EnumerateSubviewsRecursively' `
        "The legacy DM visible-view fallback is missing."
    Assert-Match $downloads `
        '(?s)LegacyDMDownloadInteractionKey.*objc_getAssociatedObject.*UIContextMenuInteraction' `
        "The legacy DM context menu is not installed idempotently."
    Assert-Match $downloads `
        '(?s)%hook\s+T1DirectMessageConversationStatusView.*download_videos.*DownloadInlineButton.*presentDownloadOptionsForMediaEntities' `
        "The legacy DM fallback does not reuse the shared downloader."
}

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

function Test-WiringContract {
    $coordinator = Get-RepoText "src/Compatibility/BHTTwitter1214Compatibility.m"
    $bootstrap = Get-RepoText "src/Compatibility/BHTTwitter1214Bootstrap.x"
    $themePicker = Get-RepoText "src/ThemeColor/ColorThemeViewController.m"
    $legacyTimestamp = Get-RepoText "src/Hooks/ImmersivePlayer.x"
    $compatibilitySources = @(
        $coordinator,
        $bootstrap,
        (Get-RepoText "src/Compatibility/BHTTabBarCompatibility.m"),
        (Get-RepoText "src/Compatibility/BHTImmersiveTimestampCompatibility.m")
    ) -join "`n"

    Assert-Match $coordinator 'BHTInstallTabBarCompatibility\(\)' `
        "The coordinator does not install tab compatibility."
    Assert-Match $coordinator 'BHTInstallImmersiveTimestampCompatibility\(\)' `
        "The coordinator does not install immersive timestamp compatibility."
    Assert-Match $bootstrap '%ctor' `
        "The Twitter 12.14 coordinator has no tweak bootstrap."
    Assert-Match $bootstrap 'dispatch_async\(dispatch_get_main_queue\(\)' `
        "The compatibility installer is not deferred to the main queue."
    Assert-Match $bootstrap 'BHTInstallTwitter1214Compatibility\(\)' `
        "The bootstrap does not invoke the Twitter 12.14 coordinator."
    Assert-Match $themePicker 'BHTTabBarCompatibility\.h' `
        "The accent picker does not import the shared tab helper."
    Assert-Match $themePicker 'BHTApplyCurrentThemeToTabBarController\(vc\)' `
        "The accent picker still duplicates tab theme iteration."
    Assert-Match $legacyTimestamp '_TtC14T1TwitterSwift32ImmersiveProgressLabelPluginView' `
        "The older immersive timestamp hook was removed."
    Assert-Match $legacyTimestamp 'setAlpha:' `
        "The older immersive timestamp alpha path was removed."
    Assert-NotMatch $compatibilitySources `
        'MSHookFunction|MSFindSymbol|\$s4Grok|isPremiumUser' `
        "Grok Premium function hooking was added to Twitter 12.14 compatibility."
}

switch ($Case) {
    "Tab" { Test-TabContract }
    "Timestamp" { Test-TimestampContract }
    "Launch" { Test-LaunchContract }
    "LoggedOut" { Test-LoggedOutLaunchContract }
    "Upload" { Test-UploadContract }
    "Premium" { Test-PremiumContract }
    "LikeKey" { Test-LikeKeyContract }
    "Spaces" { Test-SpacesContract }
    "LegacyDM" { Test-LegacyDMContract }
    "Retained" { Test-RetainedBranchContract }
    "Wiring" { Test-WiringContract }
    "All" {
        Test-TabContract
        Test-TimestampContract
        Test-LaunchContract
        Test-LoggedOutLaunchContract
        Test-RetainedBranchContract
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
