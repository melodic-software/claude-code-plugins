#!/usr/bin/env bash
# Contract tests for hooks/coverage.json, the data manifest that declares which
# baseline permission families and patterns each guard blocks, and the levers
# that narrow or switch it off. The manifest is never executed; the claims it
# makes about the guards are what this file pins: every hook it names ships and
# is registered, every event is one hooks.json declares, every family and
# pattern is one the claude-config audit baseline actually lists, and every
# lever is a documented option.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HOOK_DIR/.." && pwd)"
MANIFEST="$HOOK_DIR/coverage.json"
HOOKS_JSON="$HOOK_DIR/hooks.json"
README="$PLUGIN_ROOT/README.md"
# The baseline lives in a sibling plugin. It is present in the marketplace
# checkout and absent when guardrails is installed alone, so the pattern
# assertion below skips visibly instead of failing on a missing file.
BASELINE="$PLUGIN_ROOT/../claude-config/skills/audit/reference/required-permissions.md"
# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required for these tests" >&2
  exit 1
fi

FAMILIES="sensitive-file-deny destructive-bash-deny ask-rules"

# --- the file itself ----------------------------------------------------------
if jq -e . "$MANIFEST" >/dev/null 2>&1; then
  ok "coverage.json is valid JSON"
else
  bad "coverage.json is not valid JSON"
  report
  exit 1
fi
assert_eq "schemaVersion is 1" "1" "$(jq -r '.schemaVersion' "$MANIFEST")"
assert_eq "coverage is a non-empty array" "true" \
  "$(jq -r '(.coverage | type == "array") and (.coverage | length > 0)' "$MANIFEST")"

# --- what hooks.json declares -------------------------------------------------
declared_events=$(jq -r '.hooks | keys[]' "$HOOKS_JSON")
declared_commands=$(jq -r '.hooks[][] | .hooks[] | .command' "$HOOKS_JSON")

# --- per entry ----------------------------------------------------------------
count=$(jq -r '.coverage | length' "$MANIFEST")
i=0
while ((i < count)); do
  entry=$(jq -c ".coverage[$i]" "$MANIFEST")
  hook=$(jq -r '.hook' <<<"$entry")
  event=$(jq -r '.event' <<<"$entry")
  label="entry $i ($hook)"

  # hook path exists relative to the plugin root and is registered
  if [[ -f "$PLUGIN_ROOT/$hook" ]]; then
    ok "$label: hook file exists"
  else
    bad "$label: hook file missing at $PLUGIN_ROOT/$hook"
  fi
  assert_contains "$label: hook basename is in a hooks.json command" \
    "$declared_commands" "${hook##*/}"

  # event is one hooks.json declares
  if grep -qx -- "$event" <<<"$declared_events"; then
    ok "$label: event $event is declared in hooks.json"
  else
    bad "$label: event $event is not declared in hooks.json"
  fi

  # every family is one of the three baseline names
  while IFS= read -r family; do
    [[ -n "$family" ]] || continue
    if grep -qw -- "$family" <<<"$FAMILIES"; then
      ok "$label: family $family is a baseline family"
    else
      bad "$label: family $family is not one of: $FAMILIES"
    fi
  done < <(jq -r '.families[]' <<<"$entry")

  # every pattern is literally present (backticked) in the baseline
  while IFS= read -r pattern; do
    [[ -n "$pattern" ]] || continue
    if [[ ! -f "$BASELINE" ]]; then
      echo "SKIP: $label: pattern $pattern not checked, baseline absent at $BASELINE"
      continue
    fi
    if grep -qF -- "\`$pattern\`" "$BASELINE"; then
      ok "$label: pattern $pattern is in the baseline"
    else
      bad "$label: pattern $pattern is not in $BASELINE"
    fi
  done < <(jq -r '.patterns[]' <<<"$entry")

  # every lever name appears in the README options table
  while IFS= read -r lever; do
    [[ -n "$lever" ]] || continue
    if grep -qF -- "| \`$lever\` |" "$README"; then
      ok "$label: lever $lever is in the README options table"
    else
      bad "$label: lever $lever is not in the README options table"
    fi
  done < <(jq -r '.levers[].name' <<<"$entry")

  i=$((i + 1))
done

echo
if [[ $FAIL -eq 0 ]]; then
  echo "All $PASS checks passed."
  exit 0
fi
echo "PASS=$PASS FAIL=$FAIL"
exit 1
