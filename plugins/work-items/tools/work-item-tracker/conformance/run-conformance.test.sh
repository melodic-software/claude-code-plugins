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

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT/bindings"

write_marker_binding() {
  printf '# shellcheck shell=bash\ncb_setup() {\n  echo "%s" >&2\n  exit %s\n}\ncb_teardown() { :; }\n' \
    "$2" "$3" >"$1"
}

write_marker_binding "$TMP_ROOT/bindings/marker.sh" "MARKER-BINDING-SOURCED" 42

override_err="$(WIT_CONFORMANCE_BINDINGS_DIR="$TMP_ROOT/bindings" bash "$S" --binding marker 2>&1 >/dev/null)"
override_rc=$?
assert_contains "override root is the one sourced" "$override_err" "MARKER-BINDING-SOURCED"
assert_eq "override binding's own exit propagates" "42" "$override_rc"

WIT_CONFORMANCE_BINDINGS_DIR="$TMP_ROOT/bindings" bash "$S" --binding local-markdown >/dev/null 2>&1
assert_eq "override root does not fall back to bundled" "2" "$?"

CONSUMER_ROOT="$TMP_ROOT/consumer"
mkdir -p "$CONSUMER_ROOT/tools/work-item-tracker/conformance/bindings"
write_marker_binding \
  "$CONSUMER_ROOT/tools/work-item-tracker/conformance/bindings/local-markdown.sh" \
  "CONSUMER-LOCAL-SHADOW" 43

shadow_err="$(CLAUDE_PROJECT_DIR="$CONSUMER_ROOT" bash "$S" --binding local-markdown 2>&1 >/dev/null)"
shadow_rc=$?
assert_contains "consumer-local binding shadows the bundled one" "$shadow_err" "CONSUMER-LOCAL-SHADOW"
assert_eq "shadowing binding's own exit propagates" "43" "$shadow_rc"

EMPTY_ROOT="$TMP_ROOT/empty"
mkdir -p "$EMPTY_ROOT"
fallback_err="$(CLAUDE_PROJECT_DIR="$EMPTY_ROOT" bash "$S" --binding no-such-binding 2>&1 >/dev/null)"
assert_contains "falls back to the bundled bindings dir" "$fallback_err" "$SCRIPT_DIR/bindings/no-such-binding.sh"

[[ $FAILED -eq 0 ]] || exit 1
