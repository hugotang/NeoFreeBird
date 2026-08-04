# V6 Twitter 12.14 Compatibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add capability-gated Twitter 12.14 tab and immersive timestamp paths to the v6 base while preserving older runtime hooks and excluding Grok Premium.

**Architecture:** Focused Objective-C modules use `MSHookMessageEx` only after runtime class/selector checks. A one-time Logos bootstrap installs them after injection, and a shared tab helper is reused by the live accent picker.

**Tech Stack:** Objective-C, Logos, Cydia Substrate, UIKit, PowerShell, Theos.

---

### Task 1: Add The Failing Compatibility Contract

**Files:**

- Create: `tests/compatibility/Test-Twitter1214Compatibility.ps1`

- [ ] Assert the tab adapter exports an installer and shared reapply helper,
  guards `_t1_updateAppearance:`, and invokes `applyCurrentThemeToIcon`.
- [ ] Assert the immersive adapter guards `ImmersiveCardView.layoutSubviews`,
  respects `restore_video_timestamp`, bounds traversal, and never forces
  `hidden` or `alpha`.
- [ ] Assert bootstrap/coordinator wiring, preservation of the old immersive
  hook, preservation of the modern launch path, and absence of Grok Premium
  function hooks.
- [ ] Run `pwsh -NoProfile -File tests/compatibility/Test-Twitter1214Compatibility.ps1`
  and confirm it fails because the adapter files do not exist.

### Task 2: Implement Tab Compatibility

**Files:**

- Create: `src/Compatibility/BHTTabBarCompatibility.h`
- Create: `src/Compatibility/BHTTabBarCompatibility.m`
- Modify: `src/ThemeColor/ColorThemeViewController.m`

- [ ] Export `BHTInstallTabBarCompatibility` and
  `BHTApplyCurrentThemeToTabBarController`.
- [ ] Implement guarded `MSHookMessageEx` installation for
  `_t1_updateAppearance:` with an `NSInteger` argument.
- [ ] Call the original implementation first, then reapply the theme.
- [ ] Replace the accent picker's duplicated tab iteration with the shared
  helper.
- [ ] Run the focused `Tab` contract and confirm it passes.

### Task 3: Implement Immersive Timestamp Compatibility

**Files:**

- Create: `src/Compatibility/BHTImmersiveTimestampCompatibility.h`
- Create: `src/Compatibility/BHTImmersiveTimestampCompatibility.m`

- [ ] Resolve both the module-qualified and mangled Swift card class names.
- [ ] Install a guarded `layoutSubviews` replacement and call the original
  implementation first.
- [ ] Find a timestamp label within at most 100 visited views.
- [ ] Reapply timestamp styling when `restore_video_timestamp` is enabled,
  without changing visibility.
- [ ] Run the focused `Timestamp` contract and confirm it passes.

### Task 4: Wire The One-Time Installer

**Files:**

- Create: `src/Compatibility/BHTTwitter1214Compatibility.h`
- Create: `src/Compatibility/BHTTwitter1214Compatibility.m`
- Create: `src/Compatibility/BHTTwitter1214Bootstrap.x`

- [ ] Add a `dispatch_once` coordinator for both focused installers.
- [ ] Schedule the coordinator on the main queue from `%ctor`.
- [ ] Run the focused `Wiring` and `Launch` contracts and confirm they pass.

### Task 5: Verify, Document, Commit, And Push

**Files:**

- Test: `tests/compatibility/Test-Twitter1214Compatibility.ps1`
- Test: `tests/localization/Test-V6Localization.ps1`

- [ ] Run both PowerShell contracts and `git diff --check`.
- [ ] Confirm compatibility sources contain no `MSHookFunction`, Swift Grok
  getter symbol, `isPremiumUser`, `launchTransitionProvider`, or
  `T1AppLaunchTransition`.
- [ ] Attempt the configured Theos build; report missing host prerequisites
  instead of claiming a build passed.
- [ ] Review the complete diff, commit the implementation, and push
  `codex/v6-i18n` to `origin`.

