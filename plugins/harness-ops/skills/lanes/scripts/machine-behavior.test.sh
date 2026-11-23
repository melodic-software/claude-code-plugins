#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/machine-behavior.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s\n      expected: %q\n      got:      %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}

INSTALLED="$TMP/installed_plugins.json"
cat >"$INSTALLED" <<'JSON'
{
  "plugins": {
    "harness-ops@melodic-software": [
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

make_gh_stub() {
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

out="$(run --plugin harness-ops --plugin work-items 2>&1)"
rc=$?
assert_eq "emits successfully (exit 0)" 0 "$rc"
assert_contains "gh identity login + id" "$out" "gh-identity: octocat (id 42)"
assert_contains "clone-path from common git dir" "$out" "clone-path: /repos/claude-code-plugins"
assert_contains "current worktree from show-toplevel" "$out" "current-worktree: /repos/wt-538"
assert_contains "worktree count" "$out" "worktree-count: 3"
assert_contains "branch of a worktree rendered" "$out" "/repos/wt-538  [feat/538-lane-mechanics]"
assert_contains "detached worktree flagged" "$out" "/repos/wt-detached  [(detached)]"
assert_contains "selected plugin version" "$out" "harness-ops  0.15.4"
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

make_gh_stub ""
out="$(run --plugin harness-ops 2>&1)"
rc=$?
assert_eq "gh failure still exits 0 (degraded)" 0 "$rc"
assert_contains "gh identity degrades to unavailable" "$out" "gh-identity: unavailable"
make_gh_stub "octocat"

out="$(run 2>&1)"
assert_contains "no filter includes harness-ops" "$out" "harness-ops  0.15.4"
assert_contains "no filter includes caveman (commit-pinned version)" "$out" "caveman  0d95a81d35a9"

out="$(run --plugin nonesuch 2>&1)"
assert_contains "unknown plugin reported, not silently empty" "$out" "none of the requested plugins are installed: nonesuch"

out="$(MACHINE_BEHAVIOR_INSTALLED_JSON="$TMP/nope.json" bash "$SCRIPT" --repo "$TMP" 2>&1)"
rc=$?
assert_eq "missing installed json still exits 0" 0 "$rc"
assert_contains "missing installed json degrades" "$out" "installed_plugins.json not found"

echo '{ not json' >"$TMP/bad.json"
out="$(MACHINE_BEHAVIOR_INSTALLED_JSON="$TMP/bad.json" bash "$SCRIPT" --repo "$TMP" 2>&1)"
assert_contains "malformed installed json degrades" "$out" "is not valid JSON"

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

out="$(PATH="$STUB_BIN" "$BASH_BIN" "$SCRIPT" --help 2>&1)"
rc=$?
assert_eq "--help answers with no jq binary" 0 "$rc"

out="$(run --max-worktrees 1)"
assert_contains "cap keeps the full worktree count" "$out" "worktree-count: 3"
assert_contains "cap lists the first worktree" "$out" "/repos/claude-code-plugins  [main]"
assert_not_contains "cap drops the worktrees past it" "$out" "/repos/wt-538  ["
assert_contains "cap says how many were dropped" "$out" "... 2 more (--max-worktrees 0 lists all)"
out="$(run --max-worktrees 0)"
assert_contains "0 lists every worktree" "$out" "/repos/wt-detached  [(detached)]"
assert_not_contains "0 prints no truncation line" "$out" "more (--max-worktrees"
out="$(run --max-worktrees 08 2>&1)"
assert_not_contains "a zero-padded cap is decimal, not octal" "$out" "value too great"
assert_contains "a zero-padded cap above the count lists every worktree" "$out" "/repos/wt-detached  [(detached)]"
out="$(run --max-worktrees 01)"
assert_contains "a zero-padded cap of 1 still truncates" "$out" "... 2 more (--max-worktrees 0 lists all)"
out="$(run --max-worktrees=three 2>&1)"
rc=$?
assert_eq "--max-worktrees rejects a non-integer" 3 "$rc"

echo
if ((FAILED)); then
  printf 'machine-behavior.test: FAIL — %d case(s) failed\n' "$FAILED" >&2
  exit 1
fi
printf 'machine-behavior.test: PASS — %d cases\n' "$CASE_NUM"
