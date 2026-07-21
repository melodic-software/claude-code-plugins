#!/usr/bin/env bash
# Regression tests for machine-behavior.sh.
#
# Coverage:
#   - gh identity rendered from `gh api user`; degrades to `unavailable` when gh
#     is missing or unauthenticated
#   - worktree inventory parsed from `git worktree list --porcelain`: count,
#     per-worktree branch, detached HEAD, clone-path from the common git dir
#   - plugin versions read from installed_plugins.json, filtered by --plugin,
#     with the scope-divergent marker when a name has >1 installed version
#   - missing / malformed installed_plugins.json degrades to `unavailable`
#   - a --plugin naming no installed plugin is reported, not silently empty
#   - argument + repo validation exit codes
#   - missing jq BINARY (not just the in-script wrapper function) exits 4
#
# PATH-stubs `gh` and `git` and env-overrides the installed_plugins.json path so
# no real CLI, network, or on-disk plugin state is touched.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/machine-behavior.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s\n      expected: %q\n      got:      %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}
assert_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "contains: $3" "$2"; fi; }
assert_not_contains() { if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "absent: $3" "$2"; fi; }

# --- Fixtures ----------------------------------------------------------------
INSTALLED="$TMP/installed_plugins.json"
cat >"$INSTALLED" <<'JSON'
{
  "plugins": {
    "claude-ops@melodic-software": [
      { "scope": "user", "version": "0.15.4", "installPath": "/x" }
    ],
    "work-items@melodic-software": [
      { "scope": "user", "version": "0.17.2", "installPath": "/y" },
      { "scope": "project", "version": "0.17.1", "installPath": "/z" }
    ],
    "caveman@caveman": [
      { "scope": "user", "version": "0d95a81d35a9", "installPath": "/c" }
    ]
  }
}
JSON

# git stub: distinct output per subcommand the script calls.
STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"
cat >"$STUB_BIN/git" <<'STUB'
#!/usr/bin/env bash
# Ignore a leading `-C <dir>`.
[[ "$1" == "-C" ]] && shift 2
case "$*" in
  "worktree list --porcelain")
    cat <<'WT'
worktree /repos/claude-code-plugins
HEAD aaaa
branch refs/heads/main

worktree /repos/wt-538
HEAD bbbb
branch refs/heads/feat/538-lane-mechanics

worktree /repos/wt-detached
HEAD cccc
detached

WT
    ;;
  "rev-parse --git-common-dir") echo "${STUB_COMMON_DIR:-/repos/claude-code-plugins/.git}" ;;
  "rev-parse --show-toplevel") echo "/repos/wt-538" ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$STUB_BIN/git"

make_gh_stub() { # $1 = login (empty → simulate auth failure)
  cat >"$STUB_BIN/gh" <<STUB
#!/usr/bin/env bash
if [[ "\$1 \$2" == "api user" ]]; then
  login="$1"
  [[ -z "\$login" ]] && exit 1
  # --jq '.login' or '.id'
  case "\$*" in
    *".login"*) echo "\$login" ;;
    *".id"*) echo "42" ;;
  esac
  exit 0
fi
exit 0
STUB
  chmod +x "$STUB_BIN/gh"
}
make_gh_stub "octocat"

export PATH="$STUB_BIN:$PATH"

run() { MACHINE_BEHAVIOR_INSTALLED_JSON="$INSTALLED" bash "$SCRIPT" --repo "$TMP" "$@"; }

# ============================================================================
# Happy path — identity, worktrees, filtered plugin versions
# ============================================================================
out="$(run --plugin claude-ops --plugin work-items 2>&1)"
rc=$?
assert_eq "emits successfully (exit 0)" 0 "$rc"
assert_contains "gh identity login + id" "$out" "gh-identity: octocat (id 42)"
assert_contains "clone-path from common git dir" "$out" "clone-path: /repos/claude-code-plugins"
assert_contains "current worktree from show-toplevel" "$out" "current-worktree: /repos/wt-538"
assert_contains "worktree count" "$out" "worktree-count: 3"
assert_contains "branch of a worktree rendered" "$out" "/repos/wt-538  [feat/538-lane-mechanics]"
assert_contains "detached worktree flagged" "$out" "/repos/wt-detached  [(detached)]"
assert_contains "selected plugin version" "$out" "claude-ops  0.15.4"
assert_contains "scope-divergent plugin shows both + marker" "$out" "work-items  0.17.1, 0.17.2  (scope-divergent)"
assert_not_contains "unselected plugin omitted" "$out" "caveman"
assert_contains "deviations left to the model, not scripted" "$out" "not scripted"

# ============================================================================
# clone-path from a RELATIVE git-common-dir (the main-worktree case, where
# `rev-parse --git-common-dir` returns a bare `.git`) must be the absolute repo
# path, not "." — regression guard for the dirname(".git") == "." bug.
# ============================================================================
export STUB_COMMON_DIR=".git"
expected_clone="$(cd "$TMP" && pwd)"
out="$(run 2>&1)"
assert_contains "relative git-common-dir yields the absolute clone-path" "$out" "clone-path: $expected_clone"
assert_not_contains "relative git-common-dir is not rendered as '.'" "$out" "clone-path: ."
unset STUB_COMMON_DIR

# ============================================================================
# gh unavailable degrades (not a failure)
# ============================================================================
make_gh_stub "" # login empty → gh api user exits 1
out="$(run --plugin claude-ops 2>&1)"
rc=$?
assert_eq "gh failure still exits 0 (degraded)" 0 "$rc"
assert_contains "gh identity degrades to unavailable" "$out" "gh-identity: unavailable"
make_gh_stub "octocat"

# ============================================================================
# No --plugin → every installed plugin reported
# ============================================================================
out="$(run 2>&1)"
assert_contains "no filter includes claude-ops" "$out" "claude-ops  0.15.4"
assert_contains "no filter includes caveman (commit-pinned version)" "$out" "caveman  0d95a81d35a9"

# ============================================================================
# --plugin naming no installed plugin is reported explicitly
# ============================================================================
out="$(run --plugin nonesuch 2>&1)"
assert_contains "unknown plugin reported, not silently empty" "$out" "none of the requested plugins are installed: nonesuch"

# ============================================================================
# Missing / malformed installed_plugins.json degrades
# ============================================================================
out="$(MACHINE_BEHAVIOR_INSTALLED_JSON="$TMP/nope.json" bash "$SCRIPT" --repo "$TMP" 2>&1)"
rc=$?
assert_eq "missing installed json still exits 0" 0 "$rc"
assert_contains "missing installed json degrades" "$out" "installed_plugins.json not found"

echo '{ not json' >"$TMP/bad.json"
out="$(MACHINE_BEHAVIOR_INSTALLED_JSON="$TMP/bad.json" bash "$SCRIPT" --repo "$TMP" 2>&1)"
assert_contains "malformed installed json degrades" "$out" "is not valid JSON"

# ============================================================================
# Argument + repo validation
# ============================================================================
out="$(run --bogus 2>&1)"
rc=$?
assert_eq "unknown argument exits 3" 3 "$rc"
out="$(run --plugin 2>&1)"
rc=$?
assert_eq "--plugin with no value exits 3" 3 "$rc"
out="$(MACHINE_BEHAVIOR_INSTALLED_JSON="$INSTALLED" bash "$SCRIPT" --repo "$TMP/does-not-exist" 2>&1)"
rc=$?
assert_eq "--repo non-directory exits 4" 4 "$rc"

# ============================================================================
# jq binary missing exits 4 — regression guard for the jq() wrapper (defined
# before this prereq check) shadowing `command -v jq` and fail-opening the
# guard. A PATH with no jq binary must still be caught by `type -P jq`, which
# looks at PATH executables only and ignores the wrapper function.
# ============================================================================
# Resolve bash's own absolute path first so invoking it below needs no PATH
# lookup; then restrict the child's PATH to just STUB_BIN (the git/gh stubs),
# which never contains jq — reaching the prereq check without an external jq
# binary anywhere in PATH, on any platform.
BASH_BIN="$(command -v bash)"
out="$(PATH="$STUB_BIN" MACHINE_BEHAVIOR_INSTALLED_JSON="$INSTALLED" "$BASH_BIN" "$SCRIPT" --repo "$TMP" 2>&1)"
rc=$?
assert_eq "missing jq binary exits 4" 4 "$rc"
assert_contains "missing jq binary message" "$out" "jq not found"

# ============================================================================
echo
if ((FAILED)); then
  printf 'machine-behavior.test: FAIL — %d case(s) failed\n' "$FAILED" >&2
  exit 1
fi
printf 'machine-behavior.test: PASS — %d cases\n' "$CASE_NUM"
