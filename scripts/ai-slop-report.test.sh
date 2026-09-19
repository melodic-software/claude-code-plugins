#!/usr/bin/env bash
# Regression tests for ai-slop-report.sh.
#
#   bash scripts/ai-slop-report.test.sh
#
# Black box through the CLI against throwaway git repositories under a mktemp
# directory, with the REAL ai-slop detector: the annotation shape is the
# contract between the detector's `Finding:` rows and what GitHub renders on a
# changed line, and a stubbed detector would pin this suite to a format the
# detector no longer emits.
#
# The discriminating cases: a changed markdown file with a finding annotates
# the line it is on, a changed markdown file without one annotates nothing, an
# event that is not a pull request declines before touching git, and every one
# of them exits 0, because this reporter runs in a lint job that its findings
# must never turn red.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/ai-slop-report.sh"

# shellcheck source=test-git-helpers.sh
. "$SELF_DIR/test-git-helpers.sh"
# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

command -v git >/dev/null 2>&1 || {
  printf 'ai-slop-report.test.sh: git is not available; nothing exercised\n' >&2
  exit 2
}

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

EM_DASH=$'\xe2\x80\x94'

# mkfixture — a git repository with one commit on `main` and a `work` branch
# checked out. Echoes its path.
mkfixture() {
  local repo
  repo="$(mktemp -d "$TEST_TMPDIR/repoXXXXXX")"
  git_init_safe "$repo" >/dev/null 2>&1
  git_test_config "$repo" checkout -q -b main 2>/dev/null || true
  printf 'seed\n' >"$repo/README.md"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm base >/dev/null
  git_test_config "$repo" checkout -q -b work
  printf '%s' "$repo"
}

# run <repo> <base> [VAR=value ...] — the reporter, from inside the fixture.
RUN_OUT=""
RUN_CODE=0
run() {
  local repo="$1" base="$2"
  shift 2
  RUN_OUT="$(cd "$repo" && env GITHUB_EVENT_NAME=pull_request "$@" bash "$SCRIPT" "$base" 2>&1)"
  RUN_CODE=$?
}

contains() {
  local name="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    ok "$name"
  else
    bad "$name" "expected output to contain '$needle'; got: $haystack"
  fi
}

lacks() {
  local name="$1" haystack="$2" needle="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    ok "$name"
  else
    bad "$name" "expected output NOT to contain '$needle'; got: $haystack"
  fi
}

exits() {
  local name="$1" want="$2" got="$3"
  if [[ "$got" -eq "$want" ]]; then
    ok "$name"
  else
    bad "$name" "expected exit $want, got $got"
  fi
}

# --- a finding in changed markdown is annotated on its line -----------------

REPO="$(mkfixture)"
printf 'A sentence with an em dash %s right here in the middle of it.\n' "$EM_DASH" \
  >"$REPO/docs.md"
git_test_config "$REPO" add -A >/dev/null
git_test_config "$REPO" commit -qm change >/dev/null
run "$REPO" main
exits "a finding exits 0" 0 "$RUN_CODE"
contains "a finding is annotated as a warning on its file and line" "$RUN_OUT" \
  "::warning file=docs.md,line=1::ai-slop/audit/rule-em-dash:"
contains "the total is reported" "$RUN_OUT" "1 ai-slop finding(s) in 1 changed markdown file(s)"

# --- clean changed markdown annotates nothing -------------------------------

CLEAN_REPO="$(mkfixture)"
printf 'A plain sentence with nothing to report in it at all.\n' >"$CLEAN_REPO/clean.md"
git_test_config "$CLEAN_REPO" add -A >/dev/null
git_test_config "$CLEAN_REPO" commit -qm clean >/dev/null
run "$CLEAN_REPO" main
exits "a clean file exits 0" 0 "$RUN_CODE"
lacks "a clean file annotates nothing" "$RUN_OUT" "::warning"
contains "a clean file says so" "$RUN_OUT" "no ai-slop findings in 1 changed markdown file(s)"

# --- an unchanged markdown file is never scanned ----------------------------

SEED_REPO="$(mkfixture)"
printf 'A sentence with an em dash %s in a file nobody changed.\n' "$EM_DASH" \
  >"$SEED_REPO/README.md"
git_test_config "$SEED_REPO" add -A >/dev/null
git_test_config "$SEED_REPO" commit -qm seeded >/dev/null
git_test_config "$SEED_REPO" checkout -q main
git_test_config "$SEED_REPO" merge -q work
git_test_config "$SEED_REPO" checkout -q work
printf 'code\n' >"$SEED_REPO/tool.sh"
git_test_config "$SEED_REPO" add -A >/dev/null
git_test_config "$SEED_REPO" commit -qm shell >/dev/null
run "$SEED_REPO" main
exits "a diff with no markdown exits 0" 0 "$RUN_CODE"
lacks "a diff with no markdown annotates nothing" "$RUN_OUT" "::warning"
contains "a diff with no markdown says so" "$RUN_OUT" "changes no markdown file"

# --- a deleted markdown file is not scanned ---------------------------------

DEL_REPO="$(mkfixture)"
git_test_config "$DEL_REPO" rm -q README.md >/dev/null
git_test_config "$DEL_REPO" commit -qm delete >/dev/null
run "$DEL_REPO" main
exits "a deletion exits 0" 0 "$RUN_CODE"
lacks "a deletion annotates nothing" "$RUN_OUT" "::warning"

# --- the annotation cap holds, and the total names what it hid --------------

CAP_REPO="$(mkfixture)"
: >"$CAP_REPO/many.md"
for i in $(seq 1 60); do
  printf 'Sentence number %s with an em dash %s inside it for the detector.\n' \
    "$i" "$EM_DASH" >>"$CAP_REPO/many.md"
done
git_test_config "$CAP_REPO" add -A >/dev/null
git_test_config "$CAP_REPO" commit -qm many >/dev/null
run "$CAP_REPO" main
exits "a capped run exits 0" 0 "$RUN_CODE"
CAP_COUNT="$(printf '%s\n' "$RUN_OUT" | grep -c '^::warning')"
if [[ "$CAP_COUNT" -eq 50 ]]; then
  ok "no more than 50 findings are annotated"
else
  bad "no more than 50 findings are annotated" "annotated $CAP_COUNT"
fi
contains "the summary names the total, not the cap" "$RUN_OUT" "60 ai-slop finding(s)"

# --- declines ---------------------------------------------------------------

REPO2="$(mkfixture)"
RUN_OUT="$(cd "$REPO2" && env GITHUB_EVENT_NAME=push bash "$SCRIPT" main 2>&1)"
RUN_CODE=$?
exits "a push event exits 0" 0 "$RUN_CODE"
contains "a push event declines with a notice" "$RUN_OUT" "declined on a push event"
lacks "a push event annotates nothing" "$RUN_OUT" "::warning"

run "$REPO2" origin/does-not-exist
exits "an unresolvable base ref exits 0" 0 "$RUN_CODE"
contains "an unresolvable base ref declines with a notice" "$RUN_OUT" "does not resolve"

RUN_OUT="$(cd "$REPO2" && env GITHUB_EVENT_NAME=pull_request bash "$SCRIPT" 2>&1)"
RUN_CODE=$?
exits "no base ref exits 0" 0 "$RUN_CODE"
contains "no base ref declines with a notice" "$RUN_OUT" "no base ref was given"

run "$REPO2" main AI_SLOP_DETECTOR="$TEST_TMPDIR/absent-detector.sh"
exits "an absent detector exits 0" 0 "$RUN_CODE"
contains "an absent detector declines with a notice" "$RUN_OUT" "detector is not in this checkout"

test_harness::report
