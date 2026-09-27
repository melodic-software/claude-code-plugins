#!/usr/bin/env bash
# Tests for skill-version.sh against a fixture installed_plugins.json, a fixture
# repo with a linked worktree, and fixture plugin dirs, all in a temp dir.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/skill-version.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }

gitf() { git -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
repo="$TMP/repo"
mkdir -p "$repo"
gitf -C "$repo" init --quiet
gitf -C "$repo" commit --quiet --no-verify --allow-empty -m fixture
gitf -C "$repo" worktree add --quiet -b wt "$TMP/wt" 2>/dev/null
main=$(dirname "$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)")
nonrepo="$TMP/nonrepo"
mkdir -p "$nonrepo"

installed="$TMP/installed_plugins.json"
jq -n --arg main "$main" '{version: 2, plugins: {
  "alpha-extra@mkt": [{scope: "user", version: "9.9.9"}],
  "alpha@mkt": [
    {scope: "user", version: "1.0.0"},
    {scope: "project", projectPath: "/elsewhere", version: "0.5.0"},
    {scope: "project", projectPath: $main, version: "0.9.0"}
  ],
  "beta@other": [{scope: "user", version: "ca08d5e47d64"}],
  "delta@mkt": [{scope: "project", projectPath: "/elsewhere", version: "3.0.0"}]
}}' >"$installed"

run_in() { # <dir> <args...>
  local dir=$1
  shift
  (cd "$dir" && REPO_SWEEP_INSTALLED_PLUGINS="$installed" GIT_CEILING_DIRECTORIES="$TMP" bash "$SCRIPT" "$@")
}

assert_eq "main checkout: its project-scope install wins" "alpha:x@0.9.0" "$(run_in "$repo" alpha:x)"
assert_eq "linked worktree resolves to the main checkout's install" "alpha:x@0.9.0" "$(run_in "$TMP/wt" alpha:x)"
assert_eq "outside a repo: user scope" "alpha:x@1.0.0" "$(run_in "$nonrepo" alpha:x)"
assert_eq "SHA-style version kept verbatim" "beta:y@ca08d5e47d64" "$(run_in "$repo" beta:y)"
assert_eq "no plugin prefix: builtin" "claude-api@builtin" "$(run_in "$repo" claude-api)"
assert_eq "not installed: unknown" "gamma:z@unknown" "$(run_in "$repo" gamma:z)"
assert_eq "installed only for another project: unknown" "delta:z@unknown" "$(run_in "$repo" delta:z)"
assert_eq "one line per argument, in order" "beta:y@ca08d5e47d64
claude-api@builtin
alpha:x@0.9.0" "$(run_in "$repo" beta:y claude-api alpha:x)"
assert_eq "missing installed_plugins.json: unknown" "alpha:x@unknown" \
  "$(cd "$repo" && REPO_SWEEP_INSTALLED_PLUGINS="$TMP/absent.json" bash "$SCRIPT" alpha:x)"

mkdir -p "$TMP/pd/other/.claude-plugin" "$TMP/pd/alpha/.claude-plugin" "$TMP/pd/beta/.claude-plugin"
printf '{"name":"other","version":"7.0.0"}\n' >"$TMP/pd/other/.claude-plugin/plugin.json"
printf '{"name":"alpha","version":"2.0.0-dev"}\n' >"$TMP/pd/alpha/.claude-plugin/plugin.json"
printf '{"name":"beta"}\n' >"$TMP/pd/beta/.claude-plugin/plugin.json"
dirs="$TMP/pd/missing:$TMP/pd/other:$TMP/pd/alpha:$TMP/pd/beta"
assert_eq "REPO_SWEEP_PLUGIN_DIRS match beats installed_plugins.json" "alpha:x@2.0.0-dev" \
  "$(REPO_SWEEP_PLUGIN_DIRS="$dirs" run_in "$repo" alpha:x)"
assert_eq "plugin dir match with no version: unknown, no fallback" "beta:y@unknown" \
  "$(REPO_SWEEP_PLUGIN_DIRS="$dirs" run_in "$repo" beta:y)"
assert_eq "no plugin dir match: falls back to installed_plugins.json" "gamma:z@unknown
delta:z@unknown
alpha-extra:q@9.9.9" "$(REPO_SWEEP_PLUGIN_DIRS="$dirs" run_in "$repo" gamma:z delta:z alpha-extra:q)"

if ((FAILED)); then
  printf '%d FAILED\n' "$FAILED" >&2
  exit 1
fi
printf 'skill-version.test.sh: all passed\n'
