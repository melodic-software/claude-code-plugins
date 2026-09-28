#!/usr/bin/env bash
# The hygiene scan must judge a PR or a main push on that event's commits.
# A secret that exists only on another ref is invisible to the event range
# and visible to --log-opts=--all, which is what scan-mode git does.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN="$SCRIPT_DIR/gitleaks-scoped-scan.sh"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$3" "$2"; fi
}

BASE="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
HEAD_SHA="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

out="$(EVENT_NAME=pull_request PR_BASE_SHA="$BASE" PR_HEAD_SHA="$HEAD_SHA" bash "$SCAN" --resolve-only)"
rc=$?
assert_eq "pull_request resolves" "$rc" "0"
assert_eq "pull_request uses the action's base^..head range" \
  "$out" "--no-merges --first-parent ${BASE}^..${HEAD_SHA}"

out="$(EVENT_NAME=push PUSH_BEFORE="$BASE" PUSH_AFTER="$BASE" bash "$SCAN" --resolve-only)"
rc=$?
assert_eq "a same-ref push resolves" "$rc" "0"
assert_eq "a same-ref push scans one commit" "$out" "-1"

out="$(EVENT_NAME=push PUSH_BEFORE="$BASE" PUSH_AFTER="$HEAD_SHA" bash "$SCAN" --resolve-only)"
rc=$?
assert_eq "a push range resolves" "$rc" "0"
assert_eq "a push uses before^..after" \
  "$out" "--no-merges --first-parent ${BASE}^..${HEAD_SHA}"

out="$(EVENT_NAME=push PUSH_BEFORE="0000000000000000000000000000000000000000" PUSH_AFTER="$HEAD_SHA" bash "$SCAN" --resolve-only 2>&1)"
rc=$?
assert_eq "an all-zero before fails closed" "$rc" "2"

out="$(EVENT_NAME=pull_request PR_BASE_SHA="" PR_HEAD_SHA="$HEAD_SHA" bash "$SCAN" --resolve-only 2>&1)"
rc=$?
assert_eq "a missing pull_request SHA fails closed" "$rc" "2"

out="$(EVENT_NAME=workflow_dispatch bash "$SCAN" --resolve-only)"
rc=$?
assert_eq "workflow_dispatch resolves" "$rc" "0"
assert_eq "workflow_dispatch scans the checked-out commit" "$out" "-1"

out="$(EVENT_NAME=schedule bash "$SCAN" --resolve-only 2>&1)"
rc=$?
assert_eq "an event with no range contract fails closed" "$rc" "2"

if ! command -v gitleaks >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  printf '\nPassed: %s  Failed: %s\n' "$((CASE_NUM - FAILED))" "$FAILED"
  echo "SKIP: gitleaks or git missing; range contract was still checked" >&2
  [[ "$FAILED" -eq 0 ]]
  exit $?
fi

REPO="$TEST_TMPDIR/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email "test@example.com"
git -C "$REPO" config user.name "Test"
cp "$ROOT/.gitleaks.toml" "$REPO/.gitleaks.toml"
printf '%s\n' '# clean' >"$REPO/README.md"
git -C "$REPO" add README.md .gitleaks.toml
git -C "$REPO" commit -qm "root"
root="$(git -C "$REPO" rev-parse HEAD)"
printf '%s\n' 'more' >>"$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -qm "middle"
middle="$(git -C "$REPO" rev-parse HEAD)"
printf '%s\n' 'still clean' >>"$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -qm "tip"
tip="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" checkout -q -b leak "$middle"
printf '%s\n' 'api_key = "abcd1234efgh5678ijkl9012"' >"$REPO/secret.txt"
git -C "$REPO" add secret.txt
git -C "$REPO" commit -qm "leak on another ref"
git -C "$REPO" checkout -q main

set +e
(
  cd "$REPO"
  EVENT_NAME=push PUSH_BEFORE="$middle" PUSH_AFTER="$tip" \
    GITLEAKS_BIN="$(command -v gitleaks)" GITLEAKS_CONFIG=".gitleaks.toml" \
    bash "$SCAN"
)
scoped_rc=$?
set -e
assert_eq "a push range ignores a secret that lives only on another ref" "$scoped_rc" "0"

set +e
(
  cd "$REPO"
  gitleaks git . --log-opts=--all --config .gitleaks.toml --no-banner --redact
)
all_rc=$?
set -e
assert_eq "--all, the scan-mode git behavior, sees the other ref" "$all_rc" "1"

printf '%s\n' 'api_key = "abcd1234efgh5678ijkl9012"' >"$REPO/on-push.txt"
git -C "$REPO" add on-push.txt
git -C "$REPO" commit -qm "secret on the pushed commit"
pushed="$(git -C "$REPO" rev-parse HEAD)"
set +e
(
  cd "$REPO"
  EVENT_NAME=push PUSH_BEFORE="$tip" PUSH_AFTER="$pushed" \
    GITLEAKS_BIN="$(command -v gitleaks)" GITLEAKS_CONFIG=".gitleaks.toml" \
    bash "$SCAN"
)
hit_rc=$?
set -e
assert_eq "a secret on the pushed commit fails the scoped scan" "$hit_rc" "1"

set +e
(
  cd "$REPO"
  EVENT_NAME=pull_request PR_BASE_SHA="$middle" PR_HEAD_SHA="$tip" \
    GITLEAKS_BIN="$(command -v gitleaks)" GITLEAKS_CONFIG=".gitleaks.toml" \
    bash "$SCAN"
)
pr_rc=$?
set -e
assert_eq "a pull_request range that stops before the secret is clean" "$pr_rc" "0"

# root^ does not exist. The scan must fail closed rather than scan every ref.
set +e
(
  cd "$REPO"
  EVENT_NAME=pull_request PR_BASE_SHA="$root" PR_HEAD_SHA="$tip" \
    GITLEAKS_BIN="$(command -v gitleaks)" GITLEAKS_CONFIG=".gitleaks.toml" \
    bash "$SCAN" >"$TEST_TMPDIR/root.out" 2>"$TEST_TMPDIR/root.err"
)
root_rc=$?
set -e
# root is not the first commit's parent problem for tip: root's parent is missing,
# so base^ does not resolve. That is fail-closed (exit 2), not a clean all-refs scan.
assert_eq "a base with no parent fails closed" "$root_rc" "2"

printf '\nPassed: %s  Failed: %s\n' "$((CASE_NUM - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]]
