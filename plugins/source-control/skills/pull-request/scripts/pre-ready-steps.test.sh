#!/usr/bin/env bash
# Tests for pre-ready-steps.sh, the one definition of the pre-flip steps. The
# expected list is the five steps reference/ready-for-review.md names, in run
# order; no other script may declare its own copy.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

# shellcheck source=pre-ready-steps.sh
source "$SCRIPT_DIR/pre-ready-steps.sh" 2>/dev/null
assert_eq "the steps are the five pre-flip steps in run order" \
  "base-merge plan-evidence code-review security-review verify" "${PRE_READY_STEPS[*]:-}"

for script in "$SCRIPT_DIR"/*.sh; do
  case "$script" in *.test.sh | */pre-ready-steps.sh) continue ;; *) ;; esac
  name="${script##*/}"
  if grep -qE 'base-merge[[:space:]]+plan-evidence' "$script"; then
    fail "$name declares no step list of its own" "no literal list" "a literal list"
  else
    pass "$name declares no step list of its own"
  fi
done

for script in parse-ready-skip.sh read-pre-ready.sh ready-skip-comment.sh; do
  assert_contains "$script sources pre-ready-steps.sh" "$(cat "$SCRIPT_DIR/$script" 2>/dev/null)" "pre-ready-steps.sh"
done

[[ $FAILED -eq 0 ]] || exit 1
