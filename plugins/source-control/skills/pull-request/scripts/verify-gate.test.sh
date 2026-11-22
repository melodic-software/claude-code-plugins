#!/usr/bin/env bash
# Regression tests for verify-gate.sh: the ready flip needs a recorded pass (or skip) for the head.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/verify-gate.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

export READY_VERIFY_DIR="$TEST_TMPDIR/state"
HEAD_A=$(printf 'a%.0s' $(seq 40))
HEAD_B=$(printf 'b%.0s' $(seq 40))

out=$(bash "$SCRIPT" check --head "$HEAD_A" 2>&1)
assert_exit "a missing result refuses the flip" 2 "$?"
assert_contains "the missing-result refusal names the head" "$out" "$HEAD_A"

bash "$SCRIPT" record --head "$HEAD_A" --result fail
assert_exit "recording a failed result succeeds" 0 "$?"
out=$(bash "$SCRIPT" check --head "$HEAD_A" 2>&1)
assert_exit "a failed result refuses the flip" 3 "$?"
assert_contains "the failure refusal says the gate failed" "$out" "failed"

bash "$SCRIPT" record --head "$HEAD_A" --result pass
out=$(bash "$SCRIPT" check --head "$HEAD_A" 2>&1)
assert_exit "a recorded pass lets the flip go on" 0 "$?"
assert_silent "a pass prints nothing" "$out"

bash "$SCRIPT" check --head "$HEAD_B" >/dev/null 2>&1
assert_exit "a pass on another head does not cover this head" 2 "$?"

bash "$SCRIPT" record --head "$HEAD_B" --result skipped
bash "$SCRIPT" check --head "$HEAD_B" >/dev/null 2>&1
assert_exit "a recorded skip for the head lets the flip go on" 0 "$?"

bash "$SCRIPT" record --head "$HEAD_A" --result fail
bash "$SCRIPT" check --head "$HEAD_A" >/dev/null 2>&1
assert_exit "a later failure replaces an earlier pass" 3 "$?"

HEAD_C=$(printf 'c%.0s' $(seq 40))
printf 'garbage\n' >"$READY_VERIFY_DIR/$HEAD_C"
bash "$SCRIPT" check --head "$HEAD_C" >/dev/null 2>&1
assert_exit "an unknown recorded value refuses the flip" 2 "$?"

bash "$SCRIPT" check --head "$HEAD_B" --result pass >/dev/null 2>&1
assert_exit "check with --result is a usage error" 1 "$?"

bash "$SCRIPT" record --head "$HEAD_A" --result maybe >/dev/null 2>&1
assert_exit "an unknown result is a usage error" 1 "$?"
bash "$SCRIPT" check --head abc123 >/dev/null 2>&1
assert_exit "a short sha is a usage error" 1 "$?"
bash "$SCRIPT" bogus >/dev/null 2>&1
assert_exit "an unknown subcommand is a usage error" 1 "$?"

# Without READY_VERIFY_DIR, a record made from the main checkout covers a check run from a linked
# worktree of the same repository, and the reverse.
unset READY_VERIFY_DIR
REPO="$TEST_TMPDIR/main" WT="$TEST_TMPDIR/host-run-1"
git init -q "$REPO" && git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$REPO" worktree add -q -b feat "$WT"
HEAD_W=$(git -C "$WT" rev-parse HEAD)
(cd "$REPO" && bash "$SCRIPT" record --head "$HEAD_W" --result pass)
(cd "$WT" && bash "$SCRIPT" check --head "$HEAD_W")
assert_exit "a pass recorded from the main checkout covers a check from a linked worktree" 0 "$?"
(cd "$WT" && bash "$SCRIPT" record --head "$HEAD_W" --result fail)
(cd "$REPO" && bash "$SCRIPT" check --head "$HEAD_W" >/dev/null 2>&1)
assert_exit "a failure recorded from a linked worktree reaches a check from the main checkout" 3 "$?"

# --dir names the checkout, so a shell outside every checkout records where a check from the
# checkout itself reads.
OUTSIDE="$TEST_TMPDIR/outside"
mkdir -p "$OUTSIDE"
(cd "$OUTSIDE" && bash "$SCRIPT" record --head "$HEAD_W" --result pass --dir "$WT")
assert_exit "a record with --dir from outside the checkout succeeds" 0 "$?"
(cd "$REPO" && bash "$SCRIPT" check --head "$HEAD_W")
assert_exit "a pass recorded with --dir from outside covers a check from the checkout" 0 "$?"
(cd "$OUTSIDE" && bash "$SCRIPT" check --head "$HEAD_W" --dir "$REPO")
assert_exit "a check with --dir from outside the checkout reads the same record" 0 "$?"
(cd "$OUTSIDE" && bash "$SCRIPT" check --head "$HEAD_W" >/dev/null 2>&1)
assert_exit "without --dir, a shell outside every checkout cannot read the record" 2 "$?"
(cd "$OUTSIDE" && READY_VERIFY_DIR="$TEST_TMPDIR/override" bash "$SCRIPT" check --head "$HEAD_W" --dir "$REPO" >/dev/null 2>&1)
assert_exit "READY_VERIFY_DIR wins over --dir" 2 "$?"
bash "$SCRIPT" check --head "$HEAD_W" --dir >/dev/null 2>&1
assert_exit "--dir without a value is a usage error" 1 "$?"
bash "$SCRIPT" check --head "$HEAD_W" --dir "$TEST_TMPDIR/missing" >/dev/null 2>&1
assert_exit "--dir naming no directory is a usage error" 1 "$?"
bash "$SCRIPT" check --head "$HEAD_W" --dir "$REPO" --dir "$WT" >/dev/null 2>&1
assert_exit "--dir given twice is a usage error" 1 "$?"

STUB_DIR="$TEST_TMPDIR/stubs"
mkdir -p "$STUB_DIR"
cat >"$STUB_DIR/gh" <<STUB_EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TEST_TMPDIR/calls"
if [[ " \$* " == *" -i "* ]]; then
  [[ -f "$TEST_TMPDIR/response" ]] || exit 1
  cat "$TEST_TMPDIR/response"
else
  printf 'main\n'
fi
STUB_EOF
chmod +x "$STUB_DIR/gh"
config() { printf 'HTTP/2.0 200 OK\r\n\r\npre_ready:\n  - step: verify\n    enabled: %s\n' "$1" >"$TEST_TMPDIR/response"; }
from_config() {
  local head="$1" base="$2"
  PATH="$STUB_DIR:$PATH" bash "$SCRIPT" record --from-pre-ready --repo acme/app --base "$base" --head "$head" --dir "$WT"
}
HEAD_D=$(printf 'd%.0s' $(seq 40)) HEAD_E=$(printf 'e%.0s' $(seq 40)) HEAD_F=$(printf 'f%.0s' $(seq 40))
HEAD_9=$(printf '9%.0s' $(seq 40))

config false
: >"$TEST_TMPDIR/calls"
from_config "$HEAD_D" main
assert_exit "a default branch that disables verify records skipped" 0 "$?"
assert_contains "the record read the file at the base" "$(cat "$TEST_TMPDIR/calls")" "ref=main"
bash "$SCRIPT" check --head "$HEAD_D" --dir "$WT"
assert_exit "a skip recorded from the config lets the flip go on" 0 "$?"

config true
out=$(from_config "$HEAD_E" main 2>&1)
assert_exit "a default branch that keeps verify on refuses the skip" 4 "$?"
assert_contains "the refusal says verify is not disabled" "$out" "does not disable verify"
bash "$SCRIPT" check --head "$HEAD_E" --dir "$WT" >/dev/null 2>&1
assert_exit "a refused skip records nothing" 2 "$?"

config false
from_config "$HEAD_F" stack/layer-2 >/dev/null 2>&1
assert_exit "a base other than the default branch refuses the skip" 4 "$?"
bash "$SCRIPT" check --head "$HEAD_F" --dir "$WT" >/dev/null 2>&1
assert_exit "a skip refused on a non-default base records nothing" 2 "$?"

rm -f "$TEST_TMPDIR/response"
from_config "$HEAD_9" main >/dev/null 2>&1
assert_exit "a base read that fails refuses the skip" 4 "$?"
bash "$SCRIPT" check --head "$HEAD_9" --dir "$WT" >/dev/null 2>&1
assert_exit "a skip refused on a read error records nothing" 2 "$?"

config false
PATH="$STUB_DIR:$PATH" bash "$SCRIPT" record --from-pre-ready --repo acme/app --base main --head "$HEAD_9" --result pass --dir "$WT" >/dev/null 2>&1
assert_exit "--from-pre-ready with --result is a usage error" 1 "$?"
PATH="$STUB_DIR:$PATH" bash "$SCRIPT" record --from-pre-ready --base main --head "$HEAD_9" --dir "$WT" >/dev/null 2>&1
assert_exit "--from-pre-ready without --repo is a usage error" 1 "$?"
PATH="$STUB_DIR:$PATH" bash "$SCRIPT" check --from-pre-ready --repo acme/app --base main --head "$HEAD_9" --dir "$WT" >/dev/null 2>&1
assert_exit "check with --from-pre-ready is a usage error" 1 "$?"
bash "$SCRIPT" check --head "$HEAD_9" --dir "$WT" >/dev/null 2>&1
assert_exit "no usage error records anything" 2 "$?"

[[ $FAILED -eq 0 ]] || exit 1
