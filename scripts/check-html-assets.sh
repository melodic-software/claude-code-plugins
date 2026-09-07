#!/usr/bin/env bash
# Validate the repo's checked-in rendered-view HTML assets (the rendered-views
# convention's shared chrome/token reference and any future sibling), so a
# tracked .html asset is never the unaudited instruction surface the
# affected-tests contract forbids.
#
#   scripts/check-html-assets.sh
#
# Two checks, both fail-closed:
#   1. Every asset in the manifest below exists and lints clean under the
#      exact-pinned htmlhint from the repo's locked toolchain.
#   2. Every TRACKED plugins/*/reference/*.html is in the manifest, so a new
#      asset must register here (which is also what routes its changes to this
#      suite: affected-tests' reference rules match the basenames this file
#      names). An unregistered asset fails as UNREGISTERED, never passes
#      silently.
#
# The manifest is deliberately an explicit list, not a glob: registration is
# the stopping rule the rendered-views convention requires, and the named
# basenames are the coverage signal.
#
# Exit 0 clean, 1 findings, 2 environment/usage (htmlhint missing: run
# `npm ci`). Test injection: CHECK_HTML_ASSETS_ROOT overrides the repo root,
# HTML_ASSETS_MANIFEST points at a newline-separated manifest file,
# HTMLHINT_BIN overrides the linter path.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
REPO_ROOT="${CHECK_HTML_ASSETS_ROOT:-$SCRIPT_DIR/..}"
cd "$REPO_ROOT" || exit 2

HTMLHINT_BIN="${HTMLHINT_BIN:-node_modules/.bin/htmlhint}"
if ! command -v "$HTMLHINT_BIN" >/dev/null 2>&1 && [[ ! -x "$HTMLHINT_BIN" ]]; then
  echo "check-html-assets: htmlhint not found at $HTMLHINT_BIN (run npm ci)" >&2
  exit 2
fi

assets=()
if [[ -n "${HTML_ASSETS_MANIFEST:-}" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    assets+=("$line")
  done <"$HTML_ASSETS_MANIFEST" || exit 2
else
  assets=(
    plugins/visualization/reference/html-chrome.html
    plugins/visualization/reference/html-loop-closure.html
  )
fi

errors=0

for asset in ${assets[@]+"${assets[@]}"}; do
  if [[ ! -f "$asset" ]]; then
    echo "MISSING: $asset is in the asset manifest but not on disk." >&2
    errors=$((errors + 1))
    continue
  fi
  if ! "$HTMLHINT_BIN" "$asset" >/dev/null 2>&1; then
    echo "LINT: $asset fails htmlhint:" >&2
    "$HTMLHINT_BIN" "$asset" >&2 || true
    errors=$((errors + 1))
  fi
done

while IFS= read -r tracked; do
  found=0
  for asset in ${assets[@]+"${assets[@]}"}; do
    [[ "$tracked" == "$asset" ]] && {
      found=1
      break
    }
  done
  if ((found == 0)); then
    echo "UNREGISTERED: $tracked is a tracked rendered-view asset with no manifest entry in scripts/check-html-assets.sh." >&2
    errors=$((errors + 1))
  fi
done < <(git ls-files 'plugins/*/reference/*.html')

if ((errors > 0)); then
  exit 1
fi
echo "All registered rendered-view HTML assets lint clean; no unregistered assets."
