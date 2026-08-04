# V6 Twitter 12.14 Compatibility Design

## Goal

Extend the v6 base from its Twitter 12.3 runtime mappings to Twitter 12.14
without regressing the working 12.3-12.12 paths.

The adapter must use Objective-C runtime capability checks rather than app
version comparisons or binary offsets. Grok Premium remains deliberately out
of scope.

## Confirmed 12.14 Changes

- `-[T1TabBarViewController _t1_updateAppearance:]` is the 12.14 tab appearance
  callback. Its argument is a signed 64-bit value on arm64.
- `-[_TtC14T1TwitterSwift17ImmersiveCardView layoutSubviews]` is a stable
  12.14 layout seam for the immersive timestamp.
- The older immersive navigation callbacks and
  `+[T1AppDelegate launchTransitionProvider]` are absent.

## Scope

- Reapply v6 tab icon and label theming after the new 12.14 tab appearance
  callback.
- Style the timestamp found inside a 12.14 `ImmersiveCardView` after layout.
- Share tab reapplication with the live accent picker to avoid duplicate
  private-selector traversal.
- Preserve the existing 12.3 immersive progress-label hook for older builds.
- Verify that v6's modern animated-launch path remains and that no removed
  launch transition hook is introduced.

## Non-Goals

- Do not hook either Swift `isPremiumUser` getter or add `MSHookFunction`.
- Do not replace or remove v6's existing Grok visibility preferences.
- Do not add a `launchTransitionProvider` compatibility hook. V6 already uses
  the `app_launch_animated_launch_screen_enabled` feature switch and
  `T1AnimatedLaunchScreenView`.
- Do not replace the existing 12.3-12.12 hooks with 12.14-only code.
- Do not use image offsets or hard-coded app-version checks.

## Architecture

`src/Compatibility/` contains focused Objective-C runtime modules for the tab
bar and immersive timestamp, plus a one-time coordinator. A small Logos
bootstrap schedules installation on the main queue after tweak injection.
Each installer checks that its target class and selector exist before calling
`MSHookMessageEx`.

The tab module exports `BHTApplyCurrentThemeToTabBarController`. It reads
`tabViews` only when supported and invokes v6's existing
`applyCurrentThemeToIcon` method on compatible tab views. Both the 12.14 hook
and the live accent picker use this helper.

The timestamp module calls the original `layoutSubviews` first, checks
`restore_video_timestamp`, then performs a traversal bounded to 100 views. It
styles only a `UILabel` whose text matches an elapsed/duration timestamp. It
does not set `hidden` or `alpha`, leaving immersive control visibility under
Twitter's ownership.

## Runtime Flow

1. The compatibility bootstrap queues installation on the main queue.
2. The coordinator invokes both installers once.
3. Missing classes or selectors make the corresponding installer a no-op.
4. On 12.14, each replacement calls the captured original implementation
   before applying NeoFreeBird behavior.
5. On older builds, the new targets are absent and the existing Logos hooks
   continue unchanged.

## Failure Handling

- Every installer and coordinator is protected by `dispatch_once`.
- Original implementation pointers are checked before invocation.
- Tab access uses `respondsToSelector:` and validates the returned collection.
- Timestamp matching is restricted to the current card and a fixed number of
  descendants.
- The adapter never forces timestamp visibility.

## Verification

A PowerShell contract test is written before production code. It verifies the
guarded runtime hooks, bounded traversal, preference key, bootstrap wiring,
old-path preservation, modern launch path, and Grok Premium exclusion.

Final host-side checks are the compatibility contract, the full localization
contract, `git diff --check`, and a source scan for prohibited Grok/launch
symbols. A Theos build is attempted only when the iOS toolchain is available;
device smoke testing remains required for actual UIKit behavior.

