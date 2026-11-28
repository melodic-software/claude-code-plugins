#!/usr/bin/env bash
# fixture-isolation-scope: the counter-fixture for check-fixture-git-isolation.sh; it must export GIT_DIR
# shellcheck disable=SC2030,SC2031  # every export is subshell-local, on purpose
set -uo pipefail

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="${TEST_GIT_HELPERS_UNDER_TEST:-$SELF_DIR/test-git-helpers.sh}"

if [[ ! -f "$HELPER" ]]; then
  echo "FAIL: harness under test not found: $HELPER" >&2
  exit 1
fi

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

SENTINEL="sentinel@example.invalid"

new_caller() {
  local d
  d="$(mktemp -d "$TMP/x.XXXX")"
  git -c init.defaultBranch=main init -q "$d"
  git -C "$d" config --local user.email "$SENTINEL"
  git -C "$d" config --local user.name sentinel
  printf '%s' "$d"
}

caller_email() {
  git -C "$1" config --local --get user.email 2>/dev/null || printf '<unset>'
}

assert_isolated() {
  local label="$1" caller="$2" fixture="$3" before="$4"
  local after
  after="$(caller_email "$caller")"
  if [[ "$after" == "$SENTINEL" ]]; then
    ok "$label: caller identity intact ($after)"
  else
    fail "$label: caller identity POISONED (before=$before after=$after)"
  fi
  if [[ -e "$fixture/.git" ]]; then
    ok "$label: fixture owns its own .git"
  else
    fail "$label: fixture has NO .git — the work went to the caller instead"
  fi
}

scenario_a() {
  local caller fixture before
  caller="$(new_caller)"
  fixture="$(mktemp -d "$TMP/x.XXXX")/fx"
  mkdir -p "$fixture"
  before="$(caller_email "$caller")"
  (
    cd "$(mktemp -d "$TMP/x.XXXX")" || exit 1
    export GIT_DIR="$caller/.git"
    export GIT_WORK_TREE="$caller"
    # shellcheck source=test-git-helpers.sh
    . "$HELPER"
    git_init_test_repo "$fixture"
  ) >/dev/null 2>&1
  assert_isolated "A absolute GIT_DIR" "$caller" "$fixture" "$before"
}

scenario_b() {
  local caller wt lgd fixture before
  caller="$(new_caller)"
  git -C "$caller" -c user.email="$SENTINEL" -c user.name=sentinel \
    -c commit.gpgsign=false commit -q --allow-empty -m seed
  wt="$(mktemp -d "$TMP/x.XXXX")/lw"
  if ! git -C "$caller" worktree add -q -b lw "$wt" >/dev/null 2>&1; then
    fail "B linked worktree: could not create the linked worktree fixture"
    return
  fi
  lgd="$(git -C "$wt" rev-parse --absolute-git-dir)"
  fixture="$(mktemp -d "$TMP/x.XXXX")/fx"
  mkdir -p "$fixture"
  before="$(caller_email "$caller")"
  (
    cd "$(mktemp -d "$TMP/x.XXXX")" || exit 1
    export GIT_DIR="$lgd"
    export GIT_WORK_TREE="$wt"
    # shellcheck source=test-git-helpers.sh
    . "$HELPER"
    git_init_test_repo "$fixture"
  ) >/dev/null 2>&1
  assert_isolated "B linked worktree" "$caller" "$fixture" "$before"
  git -C "$caller" worktree remove --force "$wt" >/dev/null 2>&1 || true
}

scenario_c() {
  local caller fixture before
  caller="$(new_caller)"
  fixture="$caller/nested/fx"
  mkdir -p "$fixture"
  before="$(caller_email "$caller")"
  (
    cd "$(mktemp -d "$TMP/x.XXXX")" || exit 1
    export GIT_DIR="$caller/.git"
    export GIT_WORK_TREE="$caller"
    # shellcheck source=test-git-helpers.sh
    . "$HELPER"
    git_test_config "$fixture" init -q
    git_test_config "$fixture" config user.email nested@example.invalid
  ) >/dev/null 2>&1
  assert_isolated "C nested non-repo dir" "$caller" "$fixture" "$before"
}

scenario_d() {
  local caller fixture before
  caller="$(new_caller)"
  fixture="$(mktemp -d "$TMP/x.XXXX")/fx"
  mkdir -p "$fixture"
  before="$(caller_email "$caller")"
  (
    cd "$(mktemp -d "$TMP/x.XXXX")" || exit 1
    export GIT_CONFIG="$caller/.git/config"
    # shellcheck source=test-git-helpers.sh
    . "$HELPER"
    git_test_config "$fixture" init -q
    git_test_config "$fixture" config user.email gitconfig@example.invalid
  ) >/dev/null 2>&1
  assert_isolated "D exported GIT_CONFIG" "$caller" "$fixture" "$before"
}

scenario_e() {
  local caller before rc_empty rc_nested
  caller="$(new_caller)"
  mkdir -p "$caller/no-repo"
  before="$(caller_email "$caller")"
  rc_empty="$(
    cd "$caller" || exit 1
    # shellcheck source=test-git-helpers.sh
    . "$HELPER"
    git_test_config "" config user.email empty@example.invalid >/dev/null 2>&1
    printf '%s' "$?"
  )"
  rc_nested="$(
    cd "$(mktemp -d "$TMP/x.XXXX")" || exit 1
    # shellcheck source=test-git-helpers.sh
    . "$HELPER"
    git_test_config "$caller/no-repo" config user.email nested@example.invalid >/dev/null 2>&1
    printf '%s' "$?"
  )"
  local after
  after="$(caller_email "$caller")"
  if [[ "$after" == "$SENTINEL" && "$rc_empty" != 0 && "$rc_nested" != 0 ]]; then
    ok "E empty or non-repo dir: refused (rc $rc_empty, $rc_nested), caller identity intact"
  else
    fail "E empty or non-repo dir: rc empty=$rc_empty nested=$rc_nested, caller before=$before after=$after"
  fi
}

scenario_f() {
  local caller out rc
  caller="$(new_caller)"
  mkdir -p "$caller/tmp"
  out="$(
    cd "$caller" || exit 1
    TMPDIR="$caller/tmp" HELPER="$HELPER" bash -c '. "$HELPER"; echo reached' 2>&1
  )" && rc=0 || rc=$?
  if [[ "$rc" == 2 && "$out" != *reached* && "$out" == *"refusing TMPDIR"* ]]; then
    ok "F TMPDIR inside a repository: the suite stops at source time"
  else
    fail "F TMPDIR inside a repository: rc=$rc out='$out'"
  fi
}

scenario_declares_full_env_clear() {
  local v missing=()
  for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CONFIG; do
    grep -Eq "^[[:space:]]*unset([[:space:]]+[A-Z_]+)*[[:space:]]+$v([[:space:]]|$)" "$HELPER" ||
      missing+=("$v")
  done
  if ((${#missing[@]} == 0)); then
    ok "harness clears every discovery-redirecting variable"
  else
    fail "harness does not clear: ${missing[*]}"
  fi
}

echo "harness under test: $HELPER"
scenario_a
scenario_b
scenario_c
scenario_d
scenario_e
scenario_f
scenario_declares_full_env_clear

test_harness::report
