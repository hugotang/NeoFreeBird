#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]] || ! command -v xcrun >/dev/null 2>&1; then
  echo "SKIP: Tweet Quick Actions Foundation tests require macOS Foundation."
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

xcrun clang -fobjc-arc -fmodules -framework Foundation \
  -I"$root/src" \
  "$root/tests/quick-actions/TweetQuickActionsFoundationTests.m" \
  "$root/src/Core/BHTShareURL.m" \
  "$root/src/TweetQuickActions/TweetQuickActionsFormatter.m" \
  -o "$tmp/tweet-quick-actions-foundation-tests"

"$tmp/tweet-quick-actions-foundation-tests"
