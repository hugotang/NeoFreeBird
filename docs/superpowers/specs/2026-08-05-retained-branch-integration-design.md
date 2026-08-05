# Retained Branch Integration Design

## Goal

Preserve the remaining useful behavior from
`origin/codex/fix-logos-orig-inline-actions` in the modular v6 codebase, verify
the result against Twitter 12.14, and then delete the obsolete remote branch.

## Audit Result

The retained branch has 16 commits that are not ancestors of v6. Most of their
behavior is already represented by newer v6 implementations:

- promoted-video blocking is covered by
  `TFNTwitterAccount.isVideoDynamicAdEnabled` and the current promoted-content
  filters;
- community video download is covered by the shared status action-sheet
  download item instead of a custom inline button;
- menu font fallback uses `BHTManager.menuTitleFont` and
  `TFNUIDefaultFontGroup`;
- immersive and slideshow like confirmation already exists;
- modern DM download uses `DMConversation.MessageAttachmentView`;
- tab-bar and immersive timestamp compatibility use the newer v6 adapters;
- launch-transition hooks are intentionally absent on Twitter 12.14;
- age-verification strings are present in every supported v6 localization;
- Grok Premium remains intentionally excluded.

IDA analysis of Twitter 12.14 found five useful gaps whose classes and
selectors still exist:

1. the four Full HD/4K methods on `T1LongerVideoUploadEnabledConfig`;
2. `PremiumUpsellBarButtonItemPlugin.rightBarButtonItem` and
   `showPremiumSignUp`;
3. `T1StatusCell.handleLikeKeyCommand`;
4. `T1FleetLineHeaderController._t1_configureFleets_helper` and
   `_t1_removeFleetLineView`;
5. the legacy `T1DirectMessageConversationStatusView` media accessors used as a
   guarded DM-download fallback.

The old `TFNBarButtonItemButton` tint override will not be ported. It forced
black or white unconditionally and conflicts with v6's native accent-color
flow. The old custom community inline button will also not be ported because
the current downloader is deliberately an action-sheet service rather than a
view subclass.

## Architecture

The retained behavior stays with the v6 module that already owns the feature:

- `src/Hooks/FeatureSwitches.x` hooks the four
  `T1LongerVideoUploadEnabledConfig` getters. When `auto_highest_load` is on,
  each getter returns `YES`; otherwise it returns `%orig`.
- `src/Hooks/Ads.x` hooks the TwitterHome Premium upsell plugin. When
  `hide_premium_offer` is on, `rightBarButtonItem` returns `nil` and
  `showPremiumSignUp` returns without presenting anything. Both methods retain
  native behavior when the setting is off.
- `src/Hooks/Confirmations.x` hooks `T1StatusCell.handleLikeKeyCommand`. It uses
  the existing `ShowConfirmation` helper and invokes `%orig` exactly once after
  confirmation. Pointer/touch likes continue through the existing inline-action
  hook, so the paths do not overlap.
- `src/Hooks/Timeline.x` augments the existing fleet-line visibility hook with
  `_t1_configureFleets_helper`. When `hide_spaces` is on, it removes an already
  created line through `_t1_removeFleetLineView` and does not run the native
  configure method. When the setting is off, it calls `%orig`.
- `src/Hooks/MediaDownloads.x` adds a legacy-DM adapter beside the existing
  Swift DM adapter. Both feed media entities into the same
  `DownloadInlineButton` service.

No centralized compatibility installer is added. Keeping each hook beside its
setting and existing implementation makes future selector removal easy to
identify and avoids a second feature-dispatch layer.

## Legacy DM Data Flow

After `T1DirectMessageConversationStatusView.setViewModel:options:account:`
calls `%orig`, the adapter resolves the current media dynamically:

```text
status view
  -> inlineMedia
  -> inlineMediaViewModel or viewModel
  -> playerSessionProducer
  -> sessionProducible
  -> mediaEntity
  -> videoInfo.variants
```

If the direct inline-media path has no view model, the adapter walks
`visibleMediaForwardView` and uses the first `T1InlineMediaView` that exposes a
view model. It does not access fixed ivar offsets or use KVC.

A context-menu interaction is installed only once per target view. The menu
configuration resolves media again every time it opens so a reused view cannot
download stale content. When a downloadable video or GIF entity is available,
the menu action passes a one-element media array to
`DownloadInlineButton.presentDownloadOptionsForMediaEntities:`. A missing
class, selector, view model, session, entity, or variant yields no menu and no
side effect.

## Failure and Compatibility Rules

- Every setting-disabled path calls `%orig`.
- Capability reads use `respondsToSelector:` and dynamic Objective-C dispatch.
- The Spaces removal selector is optional; a missing selector results in a
  no-op while hidden, never a call through an unknown method.
- DM state is resolved at interaction time and retained only through the
  existing downloader object.
- No Grok symbols, `MSFindSymbol`, or `MSHookFunction` calls are introduced.
- No legacy launch-transition selector or class is restored.

## Verification

`tests/compatibility/Test-Twitter1214Compatibility.ps1` gains a selectable
retained-hooks contract. The contract checks all five mappings, their setting
keys and native fallbacks, the shared DM downloader path, and the continued
absence of Grok function hooks.

Implementation follows red-green TDD:

1. add the retained-hooks assertions and observe the expected failure;
2. implement only the mappings required to make the contract pass;
3. run all Twitter 12.14 compatibility cases;
4. run `tests/localization/Test-V6Localization.ps1` for all 15 locales;
5. run `git diff --check`;
6. push the exact commit and compile it with the macOS/Theos rootless workflow;
7. verify the workflow `headSha`, local HEAD, and `origin/v6` match.

The device smoke-test checklist is: Full HD/4K upload gates, Premium home-bar
upsell hiding, keyboard-like confirmation, Spaces removal, modern DM download,
and legacy DM download when that UI is reachable. An unreachable legacy DM UI
does not block branch cleanup because its selectors, guarded data flow, static
contract, and Theos compilation are independently verified.

After every automated gate succeeds, delete
`origin/codex/fix-logos-orig-inline-actions`. The v6 branch remains the GitHub
default branch and the sole active development line.
