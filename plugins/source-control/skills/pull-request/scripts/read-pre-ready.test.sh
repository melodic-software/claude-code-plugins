#!/usr/bin/env bash
# Tests for read-pre-ready.sh. Expected outputs follow the pre_ready contract in
# reference/ready-for-review.md: an absent key runs every step, a listed
# `enabled: false` turns that one step off, and anything the reader cannot
# trust (an unknown step, a bad value, a file it cannot parse) runs every step.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/read-pre-ready.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

ALL_ON=$'base-merge\tenabled\nplan-evidence\tenabled\ncode-review\tenabled\nsecurity-review\tenabled\nverify\tenabled'

read_doc() { printf '%s' "$1" | bash "$SCRIPT" - 2>/dev/null; }

out=$(read_doc '')
assert_eq "an empty document runs every step by default" $'source\tdefault\n'"$ALL_ON" "$out"

out=$(read_doc $'pr_open_state: ready\n')
assert_eq "a file without pre_ready runs every step by default" $'source\tdefault\n'"$ALL_ON" "$out"

out=$(read_doc $'pre_ready: []\n')
assert_eq "an empty list runs every step by default" $'source\tdefault\n'"$ALL_ON" "$out"

out=$(read_doc $'pre_ready:\n  - step: base-merge\n    enabled: true\n  - step: code-review\n    enabled: false\n  - step: verify\n    enabled: true\n')
assert_eq "a disabled step is off and every other step stays on" \
  $'source\tconfig\nbase-merge\tenabled\nplan-evidence\tenabled\ncode-review\tdisabled\nsecurity-review\tenabled\nverify\tenabled' "$out"

out=$(read_doc $'pre_ready: [{step: security-review, enabled: false}, {step: plan-evidence, enabled: false}]  # flow form\n')
assert_eq "the flow form disables the steps it names" \
  $'source\tconfig\nbase-merge\tenabled\nplan-evidence\tdisabled\ncode-review\tenabled\nsecurity-review\tdisabled\nverify\tenabled' "$out"

# Each untrusted shape: the source line fails closed with a reason, and every step is on.
check_fail_closed() {
  local label="$1" doc="$2" reason="$3" got
  got=$(read_doc "$doc")
  assert_eq "$label runs every step" $'source\tfail-closed\t'"$reason"$'\n'"$ALL_ON" "$got"
}

check_fail_closed "an unknown step" \
  $'pre_ready:\n  - step: code-review\n    enabled: false\n  - step: lint\n    enabled: false\n' "unknown step 'lint' in pre_ready"
check_fail_closed "a step listed twice" \
  $'pre_ready:\n  - step: verify\n    enabled: true\n  - step: verify\n    enabled: false\n' "step 'verify' is listed twice in pre_ready"
check_fail_closed "an enabled value other than true or false" \
  $'pre_ready:\n  - step: verify\n    enabled: maybe\n' "step 'verify' has enabled 'maybe', not true or false"
check_fail_closed "an item with no enabled value" \
  $'pre_ready:\n  - step: verify\n' "step 'verify' has no enabled value in pre_ready"
check_fail_closed "an item with no step" \
  $'pre_ready:\n  - enabled: false\n' "pre_ready item 0 has no step"
check_fail_closed "a list of bare step names" \
  $'pre_ready: [verify]\n' "pre_ready item 0 is not a {step, enabled} mapping"
check_fail_closed "a scalar pre_ready" \
  $'pre_ready: none\n' "pre_ready is not a list"
check_fail_closed "a mapping keyed by step" \
  $'pre_ready:\n  verify:\n    enabled: false\n' "pre_ready is a mapping, not a list"
check_fail_closed "a file the parser rejects" \
  $'pre_ready:\n\t- step: verify\n' "docs/conventions/source-control.yaml does not parse"

check_fail_closed "a tab inside a quoted step name, turned into a space," \
  $'pre_ready:\n  - step: "lint\\tx"\n    enabled: false\n' "unknown step 'lint x' in pre_ready"

# --ref reads the committed file, not the working tree.
REPO="$TEST_TMPDIR/repo"
git init -q "$REPO"
mkdir -p "$REPO/docs/conventions"
printf 'pre_ready:\n  - step: verify\n    enabled: false\n' >"$REPO/docs/conventions/source-control.yaml"
git -C "$REPO" add docs/conventions/source-control.yaml
git -C "$REPO" -c user.name=t -c user.email=t@example.invalid commit -qm base
BASE_SHA=$(git -C "$REPO" rev-parse HEAD)
printf 'pre_ready:\n  - step: code-review\n    enabled: false\n' >"$REPO/docs/conventions/source-control.yaml"
out=$(cd "$REPO" && bash "$SCRIPT" --ref "$BASE_SHA" docs/conventions/source-control.yaml 2>/dev/null)
assert_eq "--ref reads the value committed at the ref, not the working tree" \
  $'source\tconfig\nbase-merge\tenabled\nplan-evidence\tenabled\ncode-review\tenabled\nsecurity-review\tenabled\nverify\tdisabled' "$out"
out=$(cd "$REPO" && bash "$SCRIPT" --ref "$BASE_SHA" docs/conventions/absent.yaml 2>/dev/null)
assert_eq "--ref on a file the ref lacks runs every step by default" $'source\tdefault\n'"$ALL_ON" "$out"

bash "$SCRIPT" >/dev/null 2>&1
assert_exit "no argument is a usage error" 2 "$?"
bash "$SCRIPT" "$REPO/docs/conventions/source-control.yaml" >/dev/null 2>&1
assert_exit "a working-tree path is refused" 2 "$?"
(cd "$REPO" && bash "$SCRIPT" --ref origin/nope docs/conventions/source-control.yaml >/dev/null 2>&1)
assert_exit "a ref that does not resolve exits 2" 2 "$?"

[[ $FAILED -eq 0 ]] || exit 1
