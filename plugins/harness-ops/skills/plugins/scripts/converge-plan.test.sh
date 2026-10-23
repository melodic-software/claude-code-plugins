#!/usr/bin/env bash
# Black-box contract tests for converge-plan.sh (self-contained — ships with the
# plugin). Reports are built per-case with `--from`, so no Claude Code state file
# is read; the project paths are real throwaway directories because the script
# reads each present path's tracked settings through git.
# test-scope: .gitattributes
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/converge-plan.sh"
# Never /tmp, and backslashes folded to slashes: see cache-content-check.test.sh.
TMP_BASE="${TMPDIR:-${TEMP:-/var/tmp}}"
TMP_BASE="${TMP_BASE//\\//}"
TEST_TMPDIR="$(mktemp -d "$TMP_BASE/converge-plan.XXXXXX")"
TEST_TMPDIR="${TEST_TMPDIR//\\//}"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
# A fixture directory that is not a repository must not discover one above it.
export GIT_CEILING_DIRECTORIES="$TEST_TMPDIR"

FAILED=0

pass() {
  printf 'PASS: %s\n' "$1"
}
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed — every case here parses the script's JSON output" >&2
  exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not installed — the committed-enable read is git plumbing" >&2
  exit 0
fi

# A tracked repo whose .claude/settings.json carries the given enabledPlugins map.
tracked_repo() {
  local repo="$1" map="$2"
  mkdir -p "$repo/.claude"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email fixture@example.invalid
  git -C "$repo" config user.name fixture
  git -C "$repo" config commit.gpgsign false
  printf '{"enabledPlugins":%s}\n' "$map" >"$repo/.claude/settings.json"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m fixture
}

P_OK="$TEST_TMPDIR/ok"
P_COMMIT="$TEST_TMPDIR/committed"
P_WT="$TEST_TMPDIR/worktree"
P_NOGIT="$TEST_TMPDIR/nogit"
P_GONE="$TEST_TMPDIR/gone"
tracked_repo "$P_OK" '{"other@mk":true}'
tracked_repo "$P_COMMIT" '{"beta@mk":false}'
tracked_repo "$P_WT" '{"other@mk":true}'
mkdir -p "$P_NOGIT"

# One divergence per class, user scope holding the highest version unless noted.
#   alpha    project pin, not committed             -> actionable, uninstall
#   beta     project pin, committed enable (false)  -> actionable, update
#   gamma    project pin in an absent path          -> blocked-absent
#   delta    project pin in a home directory        -> blocked-home
#   epsilon  project pin in a linked worktree       -> worktree, uninstall
#   zeta     user pin behind a project pin, catalog below the project pin
#                                                   -> blocked-catalog
#   theta    linked worktree behind a project pin   -> worktree, strategy none
#   iota     project pin, settings check unreadable (no git) -> update
#   kappa    local pin                              -> actionable, uninstall -s local
#   eta      every scope at one version             -> no row
REPORT="$TEST_TMPDIR/report.json"
jq -n --arg ok "$P_OK" --arg commit "$P_COMMIT" --arg wt "$P_WT" --arg nogit "$P_NOGIT" \
  --arg gone "$P_GONE" '
  def rec($s; $v; $p; $present; $home; $wt):
    {scope: $s, version: $v, projectPath: $p, projectPathPresent: $present,
     projectPathIsHome: $home, linkedWorktree: $wt, label: null};
  def user($v): {scope: "user", version: $v, projectPath: null, projectPathPresent: null,
                 projectPathIsHome: null, linkedWorktree: null, label: null};
  {marketplace: {name: "mk"},
   catalog_versions: {"zeta@mk": "1.0.5", "alpha@mk": "1.2.0", "beta@mk": "1.2.0"},
   installed: [],
   divergences: [
     {id: "alpha@mk", versionsMatch: false, scopes: [user("1.2.0"), rec("project"; "1.0.0"; $ok; true; false; false)]},
     {id: "beta@mk", versionsMatch: false, scopes: [user("1.2.0"), rec("project"; "1.0.0"; $commit; true; false; false)]},
     {id: "gamma@mk", versionsMatch: false, scopes: [user("1.2.0"), rec("project"; "1.0.0"; $gone; false; false; null)]},
     {id: "delta@mk", versionsMatch: false, scopes: [user("1.2.0"), rec("project"; "1.0.0"; "/home/someone"; true; true; false)]},
     {id: "epsilon@mk", versionsMatch: false, scopes: [user("1.2.0"), rec("project"; "1.0.0"; $wt; true; false; true)]},
     {id: "zeta@mk", versionsMatch: false, scopes: [user("1.0.0"), rec("project"; "1.1.0"; $ok; true; false; false)]},
     {id: "theta@mk", versionsMatch: false, scopes: [rec("project"; "1.1.0"; $ok; true; false; false), rec("project"; "1.0.0"; $wt; true; false; true)]},
     {id: "iota@mk", versionsMatch: false, scopes: [user("1.2.0"), rec("project"; "1.0.0"; $nogit; true; false; false)]},
     {id: "kappa@mk", versionsMatch: false, scopes: [user("1.2.0"), rec("local"; "1.0.0"; $ok; true; false; false)]},
     {id: "eta@mk", versionsMatch: true, scopes: [user("1.2.0"), rec("project"; "1.2.0"; $ok; true; false; false)]}
   ]}' >"$REPORT"

PLAN="$TEST_TMPDIR/plan.json"
"$SCRIPT" --from "$REPORT" >"$PLAN" 2>"$TEST_TMPDIR/err"
assert_eq "plan exits 0" "0" "$?"

# field <id> <jq path under the row>
field() {
  jq -r --arg id "$1" ".groups[].rows[] | select(.id == \$id) | $2" "$PLAN"
}

assert_eq "actionable: class" "actionable" "$(field alpha@mk .class)"
assert_eq "actionable: user holds highest, not committed -> uninstall" "uninstall" "$(field alpha@mk .strategy)"
assert_eq "actionable: command cds into the row's own path" \
  "(cd '$P_OK' && claude plugin uninstall alpha@mk -s project --keep-data)" "$(field alpha@mk .command)"
assert_eq "committed enable (false) defaults to update" "update" "$(field beta@mk .strategy)"
assert_eq "committed enable: command" \
  "(cd '$P_COMMIT' && claude plugin update beta@mk -s project)" "$(field beta@mk .command)"
assert_eq "blocked-absent: class" "blocked-absent" "$(field gamma@mk .class)"
assert_eq "blocked-absent: no command" "null" "$(field gamma@mk .command)"
assert_eq "blocked-home: class" "blocked-home" "$(field delta@mk .class)"
assert_eq "blocked-home: no command" "null" "$(field delta@mk .command)"
assert_eq "worktree: class" "worktree" "$(field epsilon@mk .class)"
assert_eq "worktree: only uninstall is offered" "uninstall" "$(field epsilon@mk .strategy)"
assert_eq "worktree: command" \
  "(cd '$P_WT' && claude plugin uninstall epsilon@mk -s project --keep-data)" "$(field epsilon@mk .command)"
assert_eq "blocked-catalog: class" "blocked-catalog" "$(field zeta@mk .class)"
assert_eq "blocked-catalog: no command" "null" "$(field zeta@mk .command)"
assert_eq "worktree behind a project pin: strategy none" "none" "$(field theta@mk .strategy)"
assert_eq "worktree behind a project pin: no command" "null" "$(field theta@mk .command)"
assert_eq "unreadable settings check counts as committed -> update" "update" "$(field iota@mk .strategy)"
assert_eq "local scope uninstalls with -s local" \
  "(cd '$P_OK' && claude plugin uninstall kappa@mk -s local --keep-data)" "$(field kappa@mk .command)"
assert_eq "matching versions produce no row" "0" "$(jq '[.groups[].rows[] | select(.id == "eta@mk")] | length' "$PLAN")"

assert_eq "user-scope row sits in the null-path group" "null" \
  "$(jq -r '.groups[] | select(.rows[].id == "zeta@mk") | .projectPath' "$PLAN")"
assert_eq "rows group by path: one group holds both pins in the shared path" "alpha@mk,kappa@mk" \
  "$(jq -r --arg p "$P_OK" '.groups[] | select(.projectPath == $p) | [.rows[].id] | join(",")' "$PLAN")"
assert_eq "counts: worktree, blocked-absent, blocked-home, blocked-catalog" "2 1 1 1" \
  "$(jq -r '.counts | "\(.worktree) \(.["blocked-absent"]) \(.["blocked-home"]) \(.["blocked-catalog"])"' "$PLAN")"
assert_eq "counts: actionable" "4" "$(jq -r '.counts.actionable' "$PLAN")"
assert_eq "counts: rows" "9" "$(jq -r '.counts.rows' "$PLAN")"

# A worktree row with a committed enable keeps uninstall as the non-default option.
WT_COMMIT="$TEST_TMPDIR/wt-commit"
tracked_repo "$WT_COMMIT" '{"mu@mk":true}'
jq -n --arg p "$WT_COMMIT" '
  {marketplace: {name: "mk"}, catalog_versions: {}, installed: [],
   divergences: [{id: "mu@mk", versionsMatch: false, scopes: [
     {scope: "user", version: "1.2.0", projectPath: null, projectPathPresent: null,
      projectPathIsHome: null, linkedWorktree: null, label: null},
     {scope: "project", version: "1.0.0", projectPath: $p, projectPathPresent: true,
      projectPathIsHome: false, linkedWorktree: true, label: null}]}]}' >"$TEST_TMPDIR/wt-report.json"
WT_PLAN="$("$SCRIPT" --from "$TEST_TMPDIR/wt-report.json")"
assert_eq "worktree + committed enable: uninstall is not the default" "false" \
  "$(jq -r '.groups[0].rows[0].default' <<<"$WT_PLAN")"
assert_eq "worktree + committed enable: carries the warning" "removes a committed enabledPlugins entry" \
  "$(jq -r '.groups[0].rows[0].warning' <<<"$WT_PLAN")"

# Usage and shape errors.
"$SCRIPT" --from "$TEST_TMPDIR/missing.json" >/dev/null 2>&1
assert_eq "missing --from file exits 2" "2" "$?"
printf '{"marketplaces":{}}' >"$TEST_TMPDIR/envelope.json"
"$SCRIPT" --from "$TEST_TMPDIR/envelope.json" >/dev/null 2>&1
assert_eq "an --all envelope exits 2" "2" "$?"
"$SCRIPT" --from "$REPORT" --marketplace other >/dev/null 2>&1
assert_eq "a --marketplace that disagrees with the report exits 2" "2" "$?"
printf '{"marketplace":{"name":"mk","error":"not found"}}' >"$TEST_TMPDIR/errblock.json"
"$SCRIPT" --from "$TEST_TMPDIR/errblock.json" >/dev/null 2>&1
assert_eq "an error block exits 1" "1" "$?"
"$SCRIPT" --bogus >/dev/null 2>&1
assert_eq "an unknown argument exits 2" "2" "$?"

if ((FAILED > 0)); then
  printf '%d case(s) failed\n' "$FAILED" >&2
  exit 1
fi
printf 'all cases passed\n'
