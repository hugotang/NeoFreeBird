# Twitter 12.14 Compatibility Design

## Goal

Restore the non-Grok runtime paths that changed in Twitter/X 12.14 while
preserving the working Twitter 12.8 and 12.12 behavior.

The implementation must avoid image offsets and app-version string checks.
Hooks are installed only when the required runtime class and selector exist.

## Scope

This change covers:

- Tab bar theme reapplication after Twitter 12.14 calls
  `T1TabBarViewController._t1_updateAppearance:`.
- Immersive video timestamp styling when Twitter 12.14 lays out an
  `ImmersiveCardView`.
- Capability-gated installation of the legacy launch-transition hook so the
  removed Twitter 12.14 launch path is left untouched.
- Static compatibility tests, IDA selector verification, and project context
  documentation.

## Non-Goals

- Do not restore or hook either Grok Swift `isPremiumUser` getter.
- Do not rebuild Twitter 12.14's launch animation on a new lifecycle path.
- Do not add hard-coded binary addresses or app-version comparisons.
- Do not replace the working global `TPSTwitterFeatureSwitches` or
  `TFSFeatureSwitches` hooks. The removed account-specific implementations do
  not require a 12.14 replacement because the active global layers remain.
- Do not refactor unrelated Logos hooks in `Tweak.x`.

## Selected Approach

Use focused Objective-C compatibility modules installed by one Twitter 12.14
coordinator. Each feature module performs runtime capability checks before
calling `MSHookMessageEx`.

This approach is preferred over adding more Logos methods to `Tweak.x` because
missing Logos targets silently become ineffective and the main tweak file is
already large. It is preferred over version-string gating because selector
availability expresses the actual runtime capability and remains useful for
later app releases.

## Components

### Twitter 12.14 Coordinator

`Compatibility/BHTTwitter1214Compatibility.h` exports one installer.
`Compatibility/BHTTwitter1214Compatibility.m` calls the tab bar, immersive
timestamp, and launch-transition installers once with `dispatch_once`.

`Tweak.x` invokes the coordinator after `%init`, next to the existing Twitter
12.8 compatibility installer.

### Tab Bar Compatibility

`Compatibility/BHTTabBarCompatibility.h` exports:

- An installer for the Twitter 12.14 `_t1_updateAppearance:` hook.
- A shared function that reapplies the current NeoFreeBird theme to all tab
  views owned by a tab bar controller.

`Compatibility/BHTTabBarCompatibility.m` installs the new selector hook only
when `T1TabBarViewController` implements it. The replacement calls the original
implementation first, then iterates the controller's `tabViews` and invokes
`bh_applyCurrentThemeToIcon` on compatible tab views.

The existing `_t1_updateTabBarAppearance` Logos hook remains for older Twitter
versions but delegates its post-update work to the same shared function. Manual
theme refresh helpers call the shared function directly instead of attempting
to invoke a private selector with an unknown argument.

### Immersive Timestamp Compatibility

`Compatibility/BHTImmersiveTimestampCompatibility.h` exports an installer.

`Compatibility/BHTImmersiveTimestampCompatibility.m` resolves the Swift
`ImmersiveCardView` class by runtime name and hooks `layoutSubviews` only when
the class owns that selector. After the original layout, it does nothing unless
`restoreVideoTimestamp` is enabled.

When enabled, the module searches only inside that immersive card for a label
whose text matches an elapsed/duration timestamp form. It applies the existing
timestamp font, foreground color, background color, alignment, padding, and
corner radius. The same associated-object marker used by the legacy timestamp
logic prevents duplicate styling when old and new paths overlap.

The module does not force visibility. Twitter's card hierarchy continues to
hide and show the timestamp with its controls, avoiding a replacement for the
removed navigation-button callback. A reused card containing a new label is
handled by a later layout pass.

### Launch Transition Compatibility

`Compatibility/BHTLaunchTransitionCompatibility.h` exports an installer.

`Compatibility/BHTLaunchTransitionCompatibility.m` installs the legacy class
method hook only when all of these exist:

- `T1AppDelegate`
- Its `launchTransitionProvider` class method
- `T1AppLaunchTransition`

The old unconditional Logos block is removed from `Tweak.x`. Older supported
versions retain the same transition object. Twitter 12.14 has neither required
launch capability, so no method is added and no startup path is patched. The
replacement preserves the legacy override semantics; if the transition class
cannot be resolved when called, it delegates to the captured original method.

## Runtime Flow

1. The main Logos constructor completes `%init`.
2. The existing 12.8 compatibility installer runs.
3. The 12.14 coordinator asks each focused module to install its guarded hook.
4. Missing classes or selectors cause that module to return without changing
   runtime behavior.
5. Tab and timestamp replacements invoke the original implementation before
   applying NeoFreeBird behavior. The launch replacement uses the legacy
   override described above.

## Failure Handling

- Every installer is protected by `dispatch_once`.
- Class and selector lookups are checked before hook installation.
- Original implementation pointers are checked before invocation.
- Tab view access uses selector checks rather than unguarded KVC.
- Timestamp matching is bounded to the current immersive card and a fixed
  maximum number of descendants.
- Grok symbols and `MSHookFunction` are absent from the new compatibility code.

## Testing And Verification

A PowerShell contract test is added under `tests/compatibility/` before the
production changes. Its first run must fail because the 12.14 modules and
wiring do not exist. After implementation it verifies:

- The coordinator is called from `Tweak.x`.
- The new tab selector and shared reapply function are present.
- The immersive hook targets `ImmersiveCardView.layoutSubviews`.
- Launch hook installation requires both the legacy method and class.
- The unconditional launch Logos block is removed.
- No Grok Swift symbol or `MSHookFunction` is added to the 12.14 modules.

Final static verification includes the contract test, `git diff --check`, and
fresh IDA lookups for all targeted 12.14 selectors. A Theos build is required
when a configured iOS toolchain is available. Device smoke testing remains
required for launch, live tab theme changes, immersive control visibility, and
immersive card reuse because those UIKit runtime behaviors cannot be exercised
on this Windows host.

## Success Criteria

- Twitter 12.8 and 12.12 retain their existing legacy paths.
- Twitter 12.14 applies classic tab theming after its new appearance update.
- Twitter 12.14 styles immersive timestamps without forcing control visibility.
- Twitter 12.14 receives no launch-transition method or Grok function patch.
- All available static checks pass and any unavailable build or device checks
  are reported explicitly.
