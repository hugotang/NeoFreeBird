# Tweet Quick Actions Design

## Goal

Add a default-enabled `Tweet Quick Actions` setting that exposes four useful
copy commands from a Tweet's existing overflow menu on Twitter 12.14 while
preserving the working 12.3-12.12 paths.

The feature must be lazy, capability-checked, and unable to affect application
startup. Grok Premium remains explicitly out of scope.

## Scope

- Add one `Quick Actions` item to the Tweet `...` overflow menu.
- Open a second-level native menu containing:
  1. Copy Tweet Text
  2. Copy Tweet Link
  3. Copy Author
  4. Copy as Markdown
- Add the `tweet_quick_actions` toggle under `Tweets and replies`, defaulting to
  enabled.
- Reuse the existing `sharing_domain` preference for copied Tweet links.
- Add complete English and existing 15-locale coverage for all new UI text.
- Preserve the existing Tweet media-download action and its behavior.

## Non-Goals

- Do not copy direct media CDN URLs.
- Do not add another long-press Share gesture; that gesture remains reserved
  for Tweet-to-image.
- Do not fetch Tweet data, resolve URLs, or expand `t.co` links over the
  network.
- Do not add Swift class hooks, fixed offsets, KVC access, or work performed at
  application launch.
- Do not change Grok Premium behavior.

## User Experience

The existing `UIViewController
-_t1_actionItemsForStatus:account:shareableEntity:entityURL:source:options:scribeComponent:doneBlock:`
hook remains the only injection point. Custom items immediately before the
native final item are ordered as follows:

1. Quick Actions
2. Download Media, when the Tweet has downloadable media and that setting is
   enabled
3. The native final item

When `tweet_quick_actions` is disabled, the first item is not inserted. Media
downloads remain independently controlled by `download_videos`.

`Quick Actions` opens `TFNMenuSheetViewController`. The commands use existing
Twitter vector artwork where available: `copy_stroke` for the top-level and
Markdown actions, `news_stroke` for Tweet text, `link` for the Tweet link, and
`account` for the author. A missing image falls back to a title-only action; it
does not remove the command.

After a nonempty value is placed on the pasteboard, the feature emits light
haptic feedback and briefly displays a localized `Copied` `TFNHUD`. It never
shows a blocking success dialog.

## Exact Output Rules

### Tweet Text

- Copy only the outer Tweet's body, not the body of an embedded quoted Tweet.
- Trim leading and trailing whitespace and newlines.
- Preserve internal line breaks, blank lines, Unicode, and the text's existing
  URL representation.
- Prefer the user-visible text representation when the 12.14 model exposes it.
  If only raw status text is available, preserve it as-is instead of attempting
  network URL expansion.
- Disable the command when the normalized body is empty, including a
  media-only Tweet.

### Clean Tweet Link

- Construct `https://<host>/<handle>/status/<id>` when both the handle and a
  positive status ID are available. This is the preferred canonical form.
- Otherwise fall back to a valid Tweet `entityURL` supplied to the existing
  menu callback.
- Use `x.com` when `sharing_domain` is unset and use the normalized configured
  host otherwise.
- A constructed canonical link has no query or fragment. An `entityURL`
  fallback removes its fragment plus `s` and `t` query items, including an
  empty query delimiter.
- Preserve nontracking query items on an `entityURL` fallback and on existing
  shared URLs so extracting the current cleaner does not silently change
  existing share behavior.
- Disable the command when no valid Tweet URL can be produced.

### Author

Normalize a handle by removing any leading `@` characters before formatting:

- name and handle: `Display Name (@handle)`
- handle only: `@handle`
- name only: `Display Name`
- neither: disable the command

### Markdown Quote

Prefix every nonblank Tweet line with `> ` and every blank line with `>`. Add
one blank line before attribution. For example:

```markdown
> First line
>
> Second line

— [Display Name (@handle)](https://x.com/handle/status/123)
```

Tweet-body Markdown characters remain unchanged. Backslashes and square
brackets in the attribution label are escaped so they cannot break its link.
The attribution degrades deterministically:

- label and URL: `— [label](URL)`
- label only: `— label`
- URL only: `— URL`
- neither: omit attribution

If a Tweet has no text, copy only its attribution. This makes a media-only
Tweet with complete author and URL data produce:

```markdown
— [Display Name (@handle)](https://x.com/handle/status/123)
```

Disable the Markdown command only when both the normalized body and attribution
are empty.

## Architecture

### Shared URL Utility

Move the static share-link cleaner currently in `src/Hooks/Misc.x` into a
small Foundation-only utility under `src/Core/`. Both the existing
`TFNTwitterStatus`/profile share hooks and Tweet Quick Actions call the same
function, preventing `sharing_domain` or tracking-removal behavior from
drifting.

### Immutable Context and Formatter

A focused Tweet Quick Actions module owns:

- an immutable context containing copied strings for body, display name,
  handle, clean URL, and status ID;
- pure formatting helpers for normalized author, plain text, and Markdown;
- creation and presentation of the native second-level menu;
- pasteboard success feedback.

The module builds the context synchronously while the menu callback's
`__unsafe_unretained` parameters are valid. Action blocks capture only that
immutable context. They never retain or later message `status`, `account`,
`shareableEntity`, `entityURL`, or the other unsafe callback parameters.

The presenting controller retains one provider through an associated object,
matching the existing downloader pattern. The provider owns the current HUD
until it is hidden.

### Single Hook Integration

`src/Hooks/MediaDownloads.x` continues to own the single hook of the private
action-items selector. It starts with `%orig`, computes the native final-item
insertion index once, and then independently asks the Quick Actions provider
and downloader for optional items. This removes the current download-only
early return without changing download eligibility.

No second Logos hook is added for this selector, so hook ordering cannot
duplicate or reorder the custom actions.

## Data Extraction and Compatibility

Before implementation, Tweet text and author selectors must be confirmed
against the Twitter 12.14 binary. Only selectors with verified Objective-C
signatures are declared or dispatched.

Extraction occurs only while constructing an opened Tweet menu:

1. Check the setting and required private classes.
2. Read only objects that pass class validation and selectors guarded by
   `respondsToSelector:`.
3. Accept either `NSString` or `NSAttributedString` text and immediately copy
   the resulting string.
4. Prefer status/shareable-entity author data; use the entity URL path as a
   handle/ID fallback when possible.
5. Normalize and validate all values before constructing the immutable
   context.

Every private getter sequence is contained by an Objective-C exception guard.
There is no global constructor lookup, eager Swift metadata access, or launch
hook. Missing 12.14 capabilities therefore reduce available commands rather
than preventing startup.

## Runtime Flow

1. Twitter asks the controller to create Tweet overflow actions.
2. The hook calls `%orig` and receives the native action array.
3. When enabled, the provider safely snapshots available Tweet data and builds
   a Quick Actions item if at least one command can work.
4. The existing download eligibility logic independently builds Download Media
   when applicable.
5. The hook inserts available custom items in the approved order.
6. A Quick Actions tap presents a native second-level sheet generated entirely
   from the immutable snapshot.
7. A command formats a nonempty value, writes it to `UIPasteboard`, and emits
   nonblocking success feedback.

No step performs network I/O.

## Failure Handling

- If the setting is off, return the native actions plus any independently
  eligible Download Media item.
- If context construction fails or every command is unavailable, omit Quick
  Actions and return the otherwise unchanged menu.
- Disable individual commands whose required data is absent; do not present an
  error for expected missing Tweet fields.
- If a private class, selector, vector image, or presenter is unavailable,
  degrade to the supported subset or omit the feature item.
- If formatting unexpectedly returns an empty value, do not touch the
  pasteboard and do not show success feedback.
- Catch private-model exceptions at the feature boundary and preserve the
  original menu.

## Settings and Localization

Register `tweet_quick_actions` in the `tweets` settings page immediately after
`tweet_to_image`, with a default value of `YES`. Existing users need no
migration because `BHTSettings` supplies the declared default when the key is
absent.

Add these keys to English and all 15 supported locale files:

- `TWEET_QUICK_ACTIONS_TITLE`
- `TWEET_QUICK_ACTIONS_DETAIL`
- `TWEET_QUICK_ACTIONS_MENU_TITLE`
- `TWEET_QUICK_ACTIONS_COPY_TEXT`
- `TWEET_QUICK_ACTIONS_COPY_LINK`
- `TWEET_QUICK_ACTIONS_COPY_AUTHOR`
- `TWEET_QUICK_ACTIONS_COPY_MARKDOWN`
- `TWEET_QUICK_ACTIONS_COPIED`

Translations must be native-language strings, not copied English placeholders.
No new format token is required.

## Verification

Implementation follows red-green TDD using a focused Quick Actions contract
before production changes. Automated coverage must verify:

- registration, placement, default-on behavior, and disabled behavior of
  `tweet_quick_actions`;
- a single action-items hook and `Quick Actions -> Download Media -> native
  final item` ordering;
- safe immutable snapshotting rather than delayed use of unsafe callback
  arguments;
- plain-text trimming and multiline preservation;
- all author permutations and multiline Markdown output;
- media-only Markdown and missing-text/author/URL fallbacks;
- default and custom sharing hosts plus removal of `s` and `t` parameters;
- use of the shared cleaner by both existing share hooks and Quick Actions;
- localization key parity, nonempty translations, duplicate-key absence, and
  format-token consistency;
- continued exclusion of Grok Premium function hooks and startup getters.

Final host-side gates are the focused contract, every Twitter 12.14
compatibility case, the full localization contract, formatter/style checks,
`git diff --check`, and a clean worktree after commit. The exact pushed commit
must then pass the macOS/Theos rootless build workflow.

## Device Acceptance

On Twitter 12.14, verify all four clipboard values against:

- a normal one-line Tweet;
- a multiline Tweet containing a blank line and Unicode;
- a quote Tweet, confirming that plain text excludes the embedded Tweet;
- a media-only Tweet;
- an author with both display name and handle;
- default `x.com` and a configured sharing domain;
- a source URL containing `s` and `t` tracking parameters;
- the setting disabled and re-enabled;
- a Tweet with downloadable media, confirming custom-item order and that media
  download still works.

Finally verify both a fresh, logged-out installation and an already logged-in
upgrade. Both must reach the login or timeline UI without remaining on the
bird splash screen.

## Completion Criteria

The feature is complete only when automated contracts, all localization checks,
the exact-commit rootless build, and the 12.14 device acceptance checklist pass.
Any startup regression, native-menu regression, lost download action, or Grok
Premium change blocks completion.
