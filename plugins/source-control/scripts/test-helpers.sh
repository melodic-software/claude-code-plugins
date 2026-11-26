# shellcheck shell=bash

[[ -n "${_TESTS_LIB_LOADED:-}" ]] && return 0
readonly _TESTS_LIB_LOADED=1

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG

# fixture-isolation-scope: reads the host worktreeroot.path once, on purpose, before isolating (https://github.com/melodic-software/claude-code-plugins/issues/4472)
_REAL_WORKTREE_ROOT="$(git config --global --includes --type=path --get worktreeroot.path 2>/dev/null || true)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT

: "${FAILED:=0}"
: "${CASE_NUM:=0}"
: "${SKIP_CASES:=0}"
: "${DISCRIMINATING_SKIP_CASES:=0}"

native_mktemp_dir() {
  local d
  d="$(mktemp -d)"
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$d"; else printf '%s' "$d"; fi
}

physical_dir() {
  local d="$1"
  if command -v cygpath >/dev/null 2>&1; then d="$(cygpath -m "$d")"; fi
  (cd "$d" && pwd -P)
}

mkrepo() {
  local repo
  repo="$(mktemp -d "${TEST_TMPDIR:?}/repoXXXXXX")"
  git -C "$repo" init -q -b main >/dev/null 2>&1
  git -C "$repo" config user.email t@t.t
  git -C "$repo" config user.name t
  git -C "$repo" config commit.gpgsign false
  printf 'seed\n' >"$repo/README"
  git -C "$repo" add README
  git -C "$repo" commit -q -m seed
  printf '%s' "$repo"
}

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}

_fail_with() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s — %s\n' "$CASE_NUM" "$1" "$2" >&2
  FAILED=$((FAILED + 1))
}

fail() {
  local detail
  printf -v detail 'expected %q got %q' "$2" "$3"
  _fail_with "$1" "$detail"
}

skip_suite() {
  printf 'SKIP: %s\n' "$1" >&2
  exit 0
}

skip_case() {
  SKIP_CASES=$((SKIP_CASES + 1))
  printf 'SKIP: %s\n' "$1" >&2
}

fail_discriminating_skip() {
  DISCRIMINATING_SKIP_CASES=$((DISCRIMINATING_SKIP_CASES + 1))
  CASE_NUM=$((CASE_NUM + 1))
  printf 'DISCRIMINATING SKIP: [%d] %s\n' "$CASE_NUM" "$1" >&2
  FAILED=$((FAILED + 1))
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label" "$expected" "$actual"
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3" detail
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$label"
  else
    printf -v detail 'expected %q in: %s' "$needle" "$haystack"
    _fail_with "$label" "$detail"
  fi
}

assert_not_contains() {
  local label="$1" haystack="$2" needle="$3" detail
  if [[ "$haystack" != *"$needle"* ]]; then
    pass "$label"
  else
    printf -v detail 'forbidden %q present in: %s' "$needle" "$haystack"
    _fail_with "$label" "$detail"
  fi
}

assert_silent() {
  local label="$1" output="$2"
  if [[ -z "${output//[[:space:]]/}" ]]; then
    pass "$label"
  else
    _fail_with "$label" "expected empty/whitespace, got: $output"
  fi
}

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    _fail_with "$label" "exit expected $expected got $actual"
  fi
}

assert_stdout_contains() {
  assert_contains "$@"
}

assert_file_exists() {
  local label="$1" path="$2"
  if [[ -f "$path" ]]; then
    pass "$label"
  else
    _fail_with "$label" "expected file $path"
  fi
}

assert_file_absent() {
  local label="$1" path="$2"
  if [[ ! -f "$path" ]]; then
    pass "$label"
  else
    _fail_with "$label" "expected absent, found $path"
  fi
}

assert_real_worktree_root_clean() {
  local marker leaked
  marker="$(basename "$1")"
  if [[ -z "$_REAL_WORKTREE_ROOT" || ! -d "$_REAL_WORKTREE_ROOT" ]]; then
    pass "no real worktree root on this host to leak into"
    return
  fi
  leaked="$(grep -lsF "$marker" "$_REAL_WORKTREE_ROOT"/*/.git 2>/dev/null)"
  if [[ -z "$leaked" ]]; then
    pass "no fixture worktree leaked into the real root $_REAL_WORKTREE_ROOT"
  else
    fail "no fixture worktree leaked into the real root" "" "$leaked"
  fi
}
