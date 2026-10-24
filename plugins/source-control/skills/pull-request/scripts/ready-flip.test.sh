#!/usr/bin/env bash
# Regression tests for ready's wait, guarded flip and ready-run confirmation (the "Wait for the
# push's CI run", "Flip to ready" and "Confirm a ready run" blocks of the GitHub ready reference)
# against a forge that lags one read behind a push: its first head read still returns the
# pre-push commit. Black-box, with the
# blocks extracted from the reference and run in a fixture repository against a stubbed `gh`.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REF="$SCRIPT_DIR/../../../reference/providers/github/pull-request/ready-for-review.md"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

# block <heading> [<n>]: the nth (default first) fenced block in that heading's section, with
# <skill-dir> filled in.
block() {
  awk -v h="$1" -v n="${2:-1}" '$0 == h { on = 1; next } on && !f && /^## / { exit }
    on && /^```bash/ { if (++i == n) f = 1; next } f && /^```/ { exit } f' "$REF" |
    sed "s#<skill-dir>#$SKILL_DIR#g"
}

FLOW="$TEST_TMPDIR/flow.sh"
# shellcheck disable=SC2016 # the echoed lines expand in the generated script, not this one
{
  block "## Wait for the push's CI run"
  echo 'echo "WAITED=${FOUND:-skipped} HEAD_SHA=$HEAD_SHA"'
  block "## Flip to ready"
  echo 'echo "FLIP_EXIT=$?"'
  block "## Confirm a ready run" 1
  block "## Confirm a ready run" 2
  echo 'echo "CONFIRM=$?"'
} >"$FLOW"
if ! grep -q 'verify-gate.sh" check --head' "$FLOW" || ! grep -q '^ready_run_seen$' "$FLOW"; then
  echo "FAIL: the wait, flip and confirmation blocks were not found in $REF" >&2
  exit 1
fi

# Fixture: the parent commit is the PR head before the push, the tip is the pushed commit.
REPO="$TEST_TMPDIR/repo"
git init -q "$REPO"
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m before
BEFORE=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m review-fix
PUSHED=$(git -C "$REPO" rev-parse HEAD)

STUB_DIR="$TEST_TMPDIR/stubs"
mkdir -p "$STUB_DIR"
printf '#!/usr/bin/env bash\nexit 0\n' >"$STUB_DIR/sleep"
# The forge's first head read returns STUB_STALE, later reads STUB_FORGE (default: the pushed
# commit). Runs exist only for the pushed commit, and a new one only once the PR is flipped. Each
# run list logs the commit it asked about; `pr ready` logs the flip.
cat >"$STUB_DIR/gh" <<'STUB_EOF'
#!/usr/bin/env bash
case "$1 $2" in
"pr view")
  if [[ ! -e "$STUB_STATE/read" ]]; then
    : >"$STUB_STATE/read"
    echo "$STUB_STALE"
  else
    echo "${STUB_FORGE:-$STUB_PUSHED}"
  fi
  ;;
"run list")
  args="$*" commit=""
  while (($# > 0)); do
    [[ "$1" == --commit ]] && commit="$2"
    shift
  done
  echo "$commit" >>"$STUB_STATE/runs"
  if [[ "$args" == *index* ]]; then
    [[ "$commit" == "$STUB_PUSHED" && -e "$STUB_STATE/flipped" ]] && echo 1 || echo 0
  elif [[ "$commit" == "$STUB_PUSHED" ]]; then
    [[ "$args" == *length* ]] && echo 2 || echo '[11,12]'
  else
    [[ "$args" == *length* ]] && echo 0 || echo '[]'
  fi
  ;;
"pr ready") echo "$*" >>"$STUB_STATE/flipped" ;;
*) exit 1 ;;
esac
STUB_EOF
chmod +x "$STUB_DIR/gh" "$STUB_DIR/sleep"

# new_state [<sha>]: a fresh stub state and verify dir, with a pass recorded for <sha>.
RUN=0
new_state() {
  RUN=$((RUN + 1))
  STATE="$TEST_TMPDIR/state-$RUN"
  mkdir -p "$STATE/verify"
  [[ -z "${1:-}" ]] || READY_VERIFY_DIR="$STATE/verify" bash "$SKILL_DIR/scripts/verify-gate.sh" record --head "$1" --result pass
}

# run_flow <stale-head> <head-before> [<later-forge-head>], in the state new_state made.
run_flow() {
  (cd "$REPO" && PATH="$STUB_DIR:$PATH" STUB_STATE="$STATE" STUB_STALE="$1" STUB_PUSHED="$PUSHED" \
    STUB_FORGE="${3:-$PUSHED}" \
    READY_VERIFY_DIR="$STATE/verify" PR_NUMBER=5 HEAD_BEFORE="$2" timeout 30 bash "$FLOW" 2>&1)
}

new_state "$PUSHED"
out=$(run_flow "$BEFORE" "$BEFORE")
assert_contains "lagging forge: the wait finds the pushed commit's runs" "$out" "WAITED=1 HEAD_SHA=$PUSHED"
assert_contains "lagging forge: the guarded flip passes on the pushed commit" "$out" "FLIP_EXIT=0"
assert_eq "lagging forge: the PR is flipped once" "pr ready 5" "$(cat "$STATE/flipped" 2>/dev/null)"
assert_not_contains "lagging forge: no run list asks about the pre-push commit" "$(cat "$STATE/runs")" "$BEFORE"
assert_contains "lagging forge: the confirmation sees the ready run, so no toggle" "$out" "CONFIRM=0"

new_state ""
out=$(run_flow "$BEFORE" "$BEFORE")
assert_contains "no verify record for the pushed commit: the guard refuses" "$out" "FLIP_EXIT=2"
[[ -e "$STATE/flipped" ]] && flipped=yes || flipped=no
assert_eq "no verify record for the pushed commit: the PR is not flipped" "no" "$flipped"

new_state "$BEFORE"
out=$(run_flow "$BEFORE" "$BEFORE")
assert_contains "a record for the pre-push commit only: the guard refuses" "$out" "FLIP_EXIT=2"

new_state "$PUSHED"
out=$(run_flow "$PUSHED" "$PUSHED")
assert_contains "nothing pushed: the wait is skipped" "$out" "WAITED=skipped HEAD_SHA=$PUSHED"
assert_contains "nothing pushed: the guarded flip passes on the head" "$out" "FLIP_EXIT=0"

PEER=$(git -C "$REPO" -c user.name=t -c user.email=t@t commit-tree -p "$PUSHED" -m peer "$(git -C "$REPO" rev-parse "HEAD^{tree}")")
new_state "$PUSHED"
out=$(run_flow "$PEER" "$BEFORE" "$PEER")
assert_contains "the forge's head is a peer commit: the guard refuses" "$out" "FLIP_EXIT=1"
[[ -e "$STATE/flipped" ]] && flipped=yes || flipped=no
assert_eq "the forge's head is a peer commit: the PR is not flipped" "no" "$flipped"

[[ $FAILED -eq 0 ]] || exit 1
exit 0
