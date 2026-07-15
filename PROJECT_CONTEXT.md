# PROJECT_CONTEXT.md

## Project Goal

NeoFreeBird is a Theos-based iOS tweak project for Twitter/X customization. The main tweak target is `BHTwitter`, built from `Tweak.x` plus Objective-C modules under feature-specific folders such as `BHDownload/`, `BHTBundle/`, `AppIcon/`, `CustomTabBar/`, and `ThemeColor/`.

## Build Flow

- `Makefile` defines the `BHTwitter` tweak target for `arm64` using Theos.
- `build.sh` wraps common build modes: `--sideloaded`, `--rootless`, `--trollstore`, and `--rootfull`.
- The sideloaded build runs `make SIDELOADED=1`, which includes the `libflex` and `zxPluginsInject` subprojects.

## Current Structure

- `Tweak.x`: Logos hook definitions and shared helper functions for runtime behavior changes.
- `Compatibility/`: version-specific runtime symbol and Objective-C method hooks.
- `BHTManager.*`: central preference and feature-state access.
- `BHDownload/`: download-related logic.
- `BHTBundle/`: bundle/resource access helpers.
- `AppIcon/`, `CustomTabBar/`, `ThemeColor/`: settings UI and customization modules.
- `JGProgressHUD/`, `SAMKeychain/`, `Colours/`: bundled support libraries.
- `.github/workflows/build.yml`: CI build workflow.

## Change Log

### 2026-07-16 - Add Twitter 12.8 compatibility hooks

Files changed:

- `Compatibility/BHTTwitter128Compatibility.h`
- `Compatibility/BHTTwitter128Compatibility.m`
- `Makefile`
- `Tweak.x`
- `PROJECT_CONTEXT.md`

What changed:

- Added a dedicated runtime compatibility module for Twitter 12.8 instead of
  adding more version-specific implementation to the already large `Tweak.x`.
- Added function hooks for the Twitter 12.8 Swift getters
  `GrokFeatureAccess.isPremiumUser` and
  `GrokRootView.ViewModel.isPremiumUser`. Twitter 12.8 still exposes the old
  Objective-C class and `_isPremiumUser` strings, but its class metadata no
  longer exposes that getter as an Objective-C method, so the legacy Logos hook
  alone cannot cover the new path.
- Added guarded message hooks for
  `T1FleetLineHeaderController._t1_configureFleets_helper` and
  `_t1_shouldShowFleetLine`. These are the Twitter 12.8 replacements for the
  removed home-controller `_t1_initializeFleets` path used by the Hide Spaces
  Bar setting.
- The configure hook removes an already-created fleet line when hiding is
  enabled and otherwise preserves the original method. The visibility hook
  returns `NO` only while the setting is enabled, covering later visibility
  refreshes as well as initial setup.
- Updated the tweak source list to compile Objective-C modules in
  `Compatibility/`, and invoked the compatibility installer from the main
  Logos constructor after `%init`.

Behavior impact:

- Existing hooks remain available for older Twitter versions.
- Twitter 12.8 uses its current Swift Grok access getters and fleet-line
  controller without hard-coded image offsets.
- Missing 12.8 classes or symbols are skipped, so the compatibility module
  degrades safely on other supported versions.

IDA verification notes:

- `TwitterAppSPMMigration.framework` contains
  `_$s4Grok0A13FeatureAccessC13isPremiumUserSbvg` at `0xf49e9c` and
  `_$s4Grok0A8RootViewV0C5ModelC13isPremiumUserSbvg` at `0x1091e84`.
- `T1Twitter.framework` contains
  `-[T1FleetLineHeaderController _t1_configureFleets_helper]` at `0x1c5924`
  and `-_t1_shouldShowFleetLine` at `0x1c5760`.
- The configure helper creates or removes the fleet-line view according to the
  app feature state, while the visibility method controls the container's
  hidden state. Hooking both preserves layout and avoids unnecessary setup.
- The existing 12.6 mappings remain present in 12.8: community inline actions
  at `0x406838`/`0x406b60`, immersive double-tap like at `0x752be0`, all four
  `T1LongerVideoUploadEnabledConfig` selectors, Premium upsell actions at
  `0x1105da4`/`0x1106208`, like actions at `0x3337f0`/`0x14c35c`, and the DM
  status/media accessors at `0x305da4`, `0x3066e0`, `0x306bfc`, and `0x2f8adc`.
- The compose send path still enters `_t1_didTapSendButton:` before
  `_t1_handleTweetWithSkipAltTextPrompt:`. No lower-level confirmation hook was
  added because that would show duplicate confirmation alerts.
- `T1Twitter.framework` still imports `TFNBarButtonItemButton` from
  `TwitterSPMMigration.framework`, so the existing runtime class hook remains
  the correct mapping even though its implementation is outside `T1Twitter`.

Validation notes:

- Run `git diff --check` and the available Theos build after changing these
  runtime hooks.
- Runtime validation still requires launching Twitter 12.8 on a hooked device
  and exercising Grok plus the Hide Spaces Bar toggle.

### 2026-07-07 - Fix Logos `%orig` compile failure

Files changed:

- `Tweak.x`
- `PROJECT_CONTEXT.md`

What changed:

- Fixed two `_t1_inlineActionViewClassesForViewModel:options:displayType:account:` hooks.
- The hooks previously passed `%orig` directly as the first argument to `BHT_inlineActionViewClassesForViewModel(...)`.
- Logos expands `%orig` into an original-method call expression with statement syntax, which broke the generated Objective-C parentheses and caused `expected ')'` during compilation.
- The hooks now first assign `%orig` to `NSArray *classes`, then pass `classes` to `BHT_inlineActionViewClassesForViewModel(...)`.
- Rewrote the `@available(iOS 13.0, *)` check in `BHTCurrentTwitterThemeVariant(...)` into a nested guard so Clang recognizes the availability check.

Behavior impact:

- Intended runtime behavior is unchanged.
- Inline action class customization still starts from Twitter's original class list, then applies NeoFreeBird download/view-count/bookmark adjustments.
- The availability warning is removed without changing theme detection behavior.

Validation notes:

- Local validation should include `git diff --check`.
- Full Theos build validation requires a configured Theos/iOS toolchain and should run `./build.sh --sideloaded` or the relevant release mode in CI.

### 2026-07-07 - Add Twitter 12.6 community inline action support

Files changed:

- `Tweak.x`
- `BHDownloadInlineButton.m`
- `TWHeaders.h`
- `PROJECT_CONTEXT.md`

What changed:

- IDA MCP analysis of Twitter 12.6 showed the main `Twitter` binary does not contain the inline action classes.
- `T1Twitter.framework/T1Twitter` contains `T1StatusCommunitiesConversationBarView` and builds community conversation-bar buttons through `-_t1_setupInlineActionButtonsForStatusViewModel:option:account:`.
- Added a hook for that setup method. It preserves the original setup, then appends `BHDownloadInlineButton` only when downloads are enabled and the status view model is a video cell.
- Added a minimal `T1StatusCommunitiesConversationBarView` interface with `inlineActionButtons` and `statusViewModel`.
- Updated `BHDownloadInlineButton` so it stores the latest status view model from `statusDidUpdate...` and can read media from either `viewModel` or `statusViewModel` delegates.

Behavior impact:

- Existing timeline inline action class-list hooks are unchanged.
- Twitter 12.6 community conversation bars can now receive the download button through the newer setup flow.
- Non-video community conversation bars are not modified.

Validation notes:

- IDA MCP verified `+[T1StatusCommunitiesConversationBarView _t1_inlineButtonClasses]` originally returns reply and favorite button classes.
- IDA MCP verified `-_t1_setupInlineActionButtonsForStatusViewModel:option:account:` creates buttons from that class list, assigns delegate/animator, stores `inlineActionButtons`, and the caller sends `statusDidUpdate...` immediately afterward.
- Full Theos build validation still requires a configured Theos/iOS toolchain.

### 2026-07-08 - Add additional Twitter 12.6 compatibility mappings

Files changed:

- `Tweak.x`
- `BHDownloadInlineButton.m`
- `BHTManager.m`
- `TWHeaders.h`
- `PROJECT_CONTEXT.md`

What changed:

- Added safe `TAEStandardFontGroup` fallbacks for menu title fonts. Twitter 12.6 no longer exposes that class in the scanned app binaries, so dictionary literals must not receive a nil font value.
- Added `T1LongerVideoUploadEnabledConfig` hooks for Full HD and 4K upload enablement/default selectors used by Twitter 12.6's media upload configuration path.
- Added a `T1TwitterSwift.ImmersiveDoubleTapLikePluginView` hook for the Swift immersive double-tap like path.
- Added a `TFNBarButtonItemButton` hook alongside the legacy `TFNBarButtonItemButtonV1` hook for navigation button tint handling.

Behavior impact:

- Existing legacy hooks remain in place for older supported Twitter versions.
- Twitter 12.6 gets additional mappings for media upload quality, immersive double-tap like confirmation, and navigation button tinting.
- DM video download is not fully remapped yet because Twitter 12.6 no longer exposes the old `T1DirectMessageEntryMediaCell setEntryViewModel:` path; that requires a separate runtime/IDA pass before adding a safe hook.

Validation notes:

- Static IPA scanning found `T1LongerVideoUploadEnabledConfig`, `TFNBarButtonItemButton`, `TTAStatusInlineFavoriteButton`, and `T1TwitterSwift.ImmersiveDoubleTapLikePluginView` in `T1Twitter.framework`.
- IDA MCP confirmed `T1LongerVideoUploadEnabledConfig` owns Full HD/4K upload selectors and confirmed `ImmersiveDoubleTapLikePluginView` implements `handleDoubleTap:`.

### 2026-07-08 - Fill remaining confirmed Twitter 12.6 hook gaps

Files changed:

- `Tweak.x`
- `TWHeaders.h`
- `PROJECT_CONTEXT.md`

What changed:

- Added `TwitterHome.PremiumUpsellBarButtonItemPlugin` hooks for `rightBarButtonItem` and `showPremiumSignUp`, mapped from the Twitter 12.6 `T1Twitter.framework` Swift class `_TtC11TwitterHome32PremiumUpsellBarButtonItemPlugin`.
- Added 12.6 like-confirm coverage for `T1StatusCell handleLikeKeyCommand` and `T1SlideshowStatusView _favoriteAction:`. The old `T1TweetDetailsViewController _t1_toggleFavoriteOnCurrentStatus` selector was not present in 12.6 and was not remapped directly.
- Refactored DM video download menu creation into shared helpers that resolve video variants from `inlineMediaViewModel -> playerSessionProducer -> sessionProducible`.
- Added a conservative `T1DirectMessageConversationStatusView setViewModel:options:account:` hook. It adds a context menu only when the new 12.6 DM/status view can dynamically resolve downloadable video variants.
- Updated the top-level font helper to use `objc_getClass("TAEStandardFontGroup")` plus `objc_msgSend`, avoiding direct Logos class lookup for a class missing from the scanned 12.6 binaries.

Behavior impact:

- Premium home bar-button upsells are hidden by the existing `hidePremiumOffer` setting on Twitter 12.6.
- Like confirmation now covers the confirmed 12.6 keyboard/responder and slideshow favorite paths without hooking `T1MenuBarBuilder`, avoiding duplicate confirmation alerts.
- Legacy `T1DirectMessageEntryMediaCell` download support remains for older app versions, while Twitter 12.6 gets a new guarded DM/status media path.

Validation notes:

- IDA MCP confirmed `PremiumUpsellBarButtonItemPlugin rightBarButtonItem`, `showPremiumSignUp`, `T1StatusCell handleLikeKeyCommand`, `T1SlideshowStatusView _favoriteAction:`, and `T1DirectMessageConversationStatusView setViewModel:options:account:` exist in `T1Twitter.framework`.
- Binary string scanning confirmed the old `T1TweetDetailsViewController _t1_toggleFavoriteOnCurrentStatus` and `T1DirectMessageEntryMediaCell setEntryViewModel:` entries are not present in Twitter 12.6.
- Full Theos build validation still requires a configured Theos/iOS toolchain.
