#!/usr/bin/env bash
# Contract tests for scripts/check-html-assets.sh: the manifest is enforced in
# both directions (a listed asset must exist and lint; a tracked asset must be
# listed), and a missing linter is an environment error, never a silent pass.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)" || exit 2
CHECK="$SCRIPT_DIR/check-html-assets.sh"
REAL_HTMLHINT="$REPO_ROOT/node_modules/.bin/htmlhint"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# The builder clears the inherited git environment for the whole suite: the
# fixture below is its own git repo, and an inherited absolute GIT_DIR would
# redirect its writes into the caller's clone.
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

# The builder assigns through a nameref, which shellcheck cannot follow;
# declaring the out-var here is what tells it (SC2154) the name is written.
fixture=""

bad() { fail "$@"; }

expect_exit() {
  local want="$1" label="$2" got
  shift 2
  set +e
  "$@" >/dev/null 2>&1
  got=$?
  set -e
  if [[ "$got" == "$want" ]]; then
    ok "$label"
  else
    bad "$label (exit $got, wanted $want)"
  fi
}

set -e

# Fixture repo: a temp git worktree with one tracked asset.
fixture_tree::build fixture --git --plugins
mkdir -p "$fixture/plugins/demo/reference" "$fixture/node_modules/.bin"
cat >"$fixture/plugins/demo/reference/html-chrome.html" <<'HTML'
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>t</title></head>
<body><p>ok</p></body></html>
HTML
git -C "$fixture" add -A

manifest="$fixture/manifest.txt"
printf '%s\n' "plugins/demo/reference/html-chrome.html" >"$manifest"

# 1. Clean fixture passes.
expect_exit 0 "registered, existing, lint-clean asset passes" \
  env CHECK_HTML_ASSETS_ROOT="$fixture" HTML_ASSETS_MANIFEST="$manifest" \
  HTMLHINT_BIN="$REAL_HTMLHINT" "$CHECK"

# 2. A manifest entry with no file on disk fails.
printf '%s\n' "plugins/demo/reference/ghost.html" >"$manifest"
expect_exit 1 "manifest entry missing from disk fails" \
  env CHECK_HTML_ASSETS_ROOT="$fixture" HTML_ASSETS_MANIFEST="$manifest" \
  HTMLHINT_BIN="$REAL_HTMLHINT" "$CHECK"

# 3. A tracked asset absent from the manifest fails as unregistered.
: >"$manifest"
set +e
out="$(env CHECK_HTML_ASSETS_ROOT="$fixture" HTML_ASSETS_MANIFEST="$manifest" \
  HTMLHINT_BIN="$REAL_HTMLHINT" "$CHECK" 2>&1)"
code=$?
set -e
if [[ "$code" == 1 ]] && grep -q "UNREGISTERED" <<<"$out"; then
  ok "tracked asset with no manifest entry fails as UNREGISTERED"
else
  bad "unregistered tracked asset (exit $code; output: $out)"
fi

# 4. An htmlhint violation on a registered asset fails.
printf '%s\n' "plugins/demo/reference/html-chrome.html" >"$manifest"
printf '%s\n' "<html><p>no doctype, unclosed" >"$fixture/plugins/demo/reference/html-chrome.html"
expect_exit 1 "registered asset with lint violations fails" \
  env CHECK_HTML_ASSETS_ROOT="$fixture" HTML_ASSETS_MANIFEST="$manifest" \
  HTMLHINT_BIN="$REAL_HTMLHINT" "$CHECK"

# 5. Missing linter is an environment error (exit 2), not a pass.
expect_exit 2 "missing htmlhint binary exits 2" \
  env CHECK_HTML_ASSETS_ROOT="$fixture" HTML_ASSETS_MANIFEST="$manifest" \
  HTMLHINT_BIN="$fixture/node_modules/.bin/absent" "$CHECK"

# 6. The real repo state passes end to end.
expect_exit 0 "real repository manifest passes" "$CHECK"

test_harness::report
