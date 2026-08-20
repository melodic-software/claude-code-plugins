#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$SCRIPT_DIR/run-conformance.sh"
source "$SCRIPT_DIR/../tests/lib.sh"

out="$(bash "$S" --help 2>/dev/null)"
assert_eq "--help exit 0" "0" "$?"
assert_contains "--help mentions --binding" "$out" "--binding"

bash "$S" >/dev/null 2>&1
assert_eq "no --binding → usage exit 2" "2" "$?"

bash "$S" --binding no-such-binding >/dev/null 2>&1
assert_eq "unknown binding → exit 2" "2" "$?"

# The not-found diagnostic names the search, not just one path — a consumer whose
# generated binding did not land where the runner looks needs to see that both
# roots were tried.
err="$(bash "$S" --binding no-such-binding 2>&1 >/dev/null)"
assert_contains "unknown binding names the search order" "$err" "consumer-local then plugin-bundled"

# --- binding-name validation (path-traversal guard) ---
# The name is interpolated into a path under a bindings root, so a traversing or
# absolute name must be refused BEFORE any file is sourced.
for bad in "../../etc/passwd" "/etc/passwd" "has space" "Upper" "" "."; do
  bash "$S" --binding "$bad" >/dev/null 2>&1
  assert_eq "invalid binding name ${bad:-<empty>} → exit 2" "2" "$?"
done

traverse_err="$(bash "$S" --binding "../../etc/passwd" 2>&1 >/dev/null)"
assert_contains "traversing name rejected as invalid, not as not-found" \
  "$traverse_err" "invalid binding name"

# --- WIT_CONFORMANCE_BINDINGS_DIR override ---
# An explicit bindings root replaces the search outright (the sibling of
# WIT_ADAPTERS_DIR). Proven by pointing it at a temp root holding a marker
# binding whose cb_setup aborts the run with a recognizable code: reaching it at
# all proves the override root was the one sourced.
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT/bindings"
cat >"$TMP_ROOT/bindings/marker.sh" <<'EOF'
# shellcheck shell=bash
cb_setup() {
  echo "MARKER-BINDING-SOURCED" >&2
  exit 42
}
cb_teardown() { :; }
EOF

override_err="$(WIT_CONFORMANCE_BINDINGS_DIR="$TMP_ROOT/bindings" bash "$S" --binding marker 2>&1 >/dev/null)"
override_rc=$?
assert_contains "override root is the one sourced" "$override_err" "MARKER-BINDING-SOURCED"
assert_eq "override binding's own exit propagates" "42" "$override_rc"

# A name absent from the override root is not silently backfilled from the
# bundled set — the override is a replacement, not an additional search step.
WIT_CONFORMANCE_BINDINGS_DIR="$TMP_ROOT/bindings" bash "$S" --binding local-markdown >/dev/null 2>&1
assert_eq "override root does not fall back to bundled" "2" "$?"

# --- consumer-local-first resolution ---
# With no override, a bindings file under <repo root>/tools/work-item-tracker/
# conformance/bindings wins over the plugin-bundled copy. CLAUDE_PROJECT_DIR is
# the repo-root anchor wit_project_root reads first, so a temp root stands in for
# a consuming repo without needing a git fixture.
CONSUMER_ROOT="$TMP_ROOT/consumer"
mkdir -p "$CONSUMER_ROOT/tools/work-item-tracker/conformance/bindings"
cat >"$CONSUMER_ROOT/tools/work-item-tracker/conformance/bindings/local-markdown.sh" <<'EOF'
# shellcheck shell=bash
cb_setup() {
  echo "CONSUMER-LOCAL-SHADOW" >&2
  exit 43
}
cb_teardown() { :; }
EOF

shadow_err="$(CLAUDE_PROJECT_DIR="$CONSUMER_ROOT" bash "$S" --binding local-markdown 2>&1 >/dev/null)"
shadow_rc=$?
assert_contains "consumer-local binding shadows the bundled one" "$shadow_err" "CONSUMER-LOCAL-SHADOW"
assert_eq "shadowing binding's own exit propagates" "43" "$shadow_rc"

# A consuming repo with no local bindings dir still resolves the bundled set —
# the fallback leg. Proven by the not-found path naming the BUNDLED directory for
# a name that exists in neither root.
EMPTY_ROOT="$TMP_ROOT/empty"
mkdir -p "$EMPTY_ROOT"
fallback_err="$(CLAUDE_PROJECT_DIR="$EMPTY_ROOT" bash "$S" --binding no-such-binding 2>&1 >/dev/null)"
assert_contains "falls back to the bundled bindings dir" "$fallback_err" "$SCRIPT_DIR/bindings/no-such-binding.sh"

[[ $FAILED -eq 0 ]] || exit 1
