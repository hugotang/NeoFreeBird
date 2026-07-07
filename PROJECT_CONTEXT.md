# PROJECT_CONTEXT.md

## Project Goal

NeoFreeBird is a Theos-based iOS tweak project for Twitter/X customization. The main tweak target is `BHTwitter`, built from `Tweak.x` plus Objective-C modules under feature-specific folders such as `BHDownload/`, `BHTBundle/`, `AppIcon/`, `CustomTabBar/`, and `ThemeColor/`.

## Build Flow

- `Makefile` defines the `BHTwitter` tweak target for `arm64` using Theos.
- `build.sh` wraps common build modes: `--sideloaded`, `--rootless`, `--trollstore`, and `--rootfull`.
- The sideloaded build runs `make SIDELOADED=1`, which includes the `libflex` and `zxPluginsInject` subprojects.

## Current Structure

- `Tweak.x`: Logos hook definitions and shared helper functions for runtime behavior changes.
- `BHTManager.*`: central preference and feature-state access.
- `BHDownload/`: download-related logic.
- `BHTBundle/`: bundle/resource access helpers.
- `AppIcon/`, `CustomTabBar/`, `ThemeColor/`: settings UI and customization modules.
- `JGProgressHUD/`, `SAMKeychain/`, `Colours/`: bundled support libraries.
- `.github/workflows/build.yml`: CI build workflow.

## Change Log

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
