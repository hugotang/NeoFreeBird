# V6 i18N Completion Design

## Context

NeoFreeBird v6.0.4 contains `Localizable.strings` files for English and 15
additional locales. All locale files currently have the same 186 keys, but a
set of user-facing values in every non-English locale still copies the English
text. A few locales also retain additional English values that should be
reviewed individually.

The work will use `theacrat/NeoFreeBird` branch `v6` as its base. Development
will occur on `codex/v6-i18n` in the independent `E:\NeoFreeBird-v6` clone,
with `theacrat` configured as `upstream` and `hugotang` configured as `origin`.

## Goals

- Replace the confirmed English placeholders with natural, native UI wording
  in Arabic, German, Spanish, French, Croatian, Indonesian, Japanese, Korean,
  Polish, Russian, Swedish, Turkish, Ukrainian, Simplified Chinese, and
  Traditional Chinese.
- Preserve product names, format substitutions, escaped newlines, file order,
  comments, and UTF-8 encoding.
- Add a repeatable localization test that catches missing keys, unresolved
  placeholders, and format-token regressions.
- Keep the patch isolated from v6 runtime hooks, settings behavior, branding,
  dependency management, and build workflows.

## Translation Scope

The following 27 keys are confirmed translation targets because all 15
non-English locales currently use the exact English value:

- `CUSTOM_TAB_BAR_GRID_DETAIL`
- `DOWNLOAD_VIDEO_NUMBER_TITLE`
- `FONT_SYSTEM_DEFAULT_SUBTITLE`
- `INSTALL_IFONT_BUTTON_TITLE`
- `LEGACY_LOGIN_BUILD_CHALLENGE_FAILED_MESSAGE`
- `LEGACY_LOGIN_BUILD_COMMAND_FAILED_MESSAGE`
- `LEGACY_LOGIN_CHALLENGE_CLASSES_MISSING_MESSAGE`
- `LEGACY_LOGIN_CHALLENGE_MISSING_INFO_MESSAGE`
- `LEGACY_LOGIN_CLASSES_MISSING_MESSAGE`
- `LEGACY_LOGIN_CRASH_AVOIDED_TITLE`
- `LEGACY_LOGIN_FAILED_TITLE`
- `LEGACY_LOGIN_INFO_LABEL`
- `LEGACY_LOGIN_MISSING_INPUT_MESSAGE`
- `LEGACY_LOGIN_MISSING_INPUT_TITLE`
- `LEGACY_LOGIN_NO_ACCOUNT_MESSAGE`
- `LEGACY_LOGIN_NO_TOKEN_MESSAGE`
- `LEGACY_LOGIN_NO_TOKEN_NO_CHALLENGE_MESSAGE`
- `LEGACY_LOGIN_RATE_LIMITED_MESSAGE`
- `LEGACY_LOGIN_RATE_LIMITED_TITLE`
- `LEGACY_LOGIN_SIGNING_IN_STATUS`
- `LEGACY_LOGIN_UNAVAILABLE_TITLE`
- `LEGACY_LOGIN_UNEXPECTED_RESPONSE_TITLE`
- `LEGACY_LOGIN_UNKNOWN_ERROR`
- `LEGACY_LOGIN_VERIFYING_STATUS`
- `PADLOCK_LOCKED_LABEL`
- `UNKNOWN_ERROR`
- `UNKNOWN_SOURCE`

The audit will also review the small set of values that match English in only
one locale. A value will be translated when it is an untranslated phrase;
established loanwords may remain only when they are normal native UI usage and
are recorded as a locale-specific test exception.

`MODERN_SETTINGS_GROK_TITLE` and `NFB_SETTINGS_TITLE` are intentionally excluded
from translation because `Grok` and `NeoFreeBird` are product names. The `iFont`
name and placeholders such as `%@` and `%lu` must remain unchanged inside their
translated surrounding text.

## Validation Design

A PowerShell test under `tests/localization/` will parse every v6
`Localizable.strings` file and enforce the following contracts:

1. Every locale contains exactly the English key set.
2. Every translation target is present, non-empty, and does not resolve to its
   key name.
3. Confirmed placeholder values no longer equal English, except for explicit
   product-name or locale-specific allowlist entries.
4. Each translated value preserves the same ordered printf-style tokens as its
   English source, including `%@` and `%lu`.
5. Escaped newline structure is preserved for multi-paragraph login messages.

The test will be run once before translation to prove it fails for the current
English placeholders, then again after translation to prove the completed
locale set passes. `git diff --check` and UTF-8 decoding checks will accompany
the targeted test. A full Theos build is outside this localization-only scope
and may be unavailable on the Windows host.

## Non-Goals

- Rewriting translations that are already localized solely for stylistic
  consistency.
- Adding or removing settings, hooks, preferences, or supported locales.
- Porting changes from the existing 12.14 compatibility branch into v6.
- Changing the v6 FFmpeg, icon, rebranding, release, or dependency workflows.

## Acceptance Criteria

- All 15 non-English locales retain all 186 English source keys.
- The 27 confirmed targets and approved locale-specific targets use natural
  localized wording.
- Product names and all substitution tokens remain intact.
- The localization regression test and repository whitespace check pass.
- The final implementation is committed and pushed on `codex/v6-i18n`.
