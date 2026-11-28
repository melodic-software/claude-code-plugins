#!/usr/bin/env bash
# test-scope: .gitattributes plugins/harness-ops/skills/plugins/scripts/question-groups.jq
# test-scope: plugins/harness-ops/skills/plugins/scripts/version.jq
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/converge-plan.sh"
TMP_BASE="${TMPDIR:-${TEMP:-/var/tmp}}"
TMP_BASE="${TMP_BASE//\\//}"
TEST_TMPDIR="$(mktemp -d "$TMP_BASE/converge-plan.XXXXXX")"
TEST_TMPDIR="${TEST_TMPDIR//\\//}"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
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
P_HOME="$TEST_TMPDIR/home-dir"
tracked_repo "$P_OK" '{"other@mk":true}'
tracked_repo "$P_COMMIT" '{"beta@mk":false}'
tracked_repo "$P_WT" '{"other@mk":true}'
mkdir -p "$P_NOGIT"

REPORT="$TEST_TMPDIR/report.json"
jq -n --arg ok "$P_OK" --arg commit "$P_COMMIT" --arg wt "$P_WT" --arg nogit "$P_NOGIT" \
  --arg gone "$P_GONE" --arg homedir "$P_HOME" '
  def rec($s; $v; $p; $present; $home; $wt; $c):
    {scope: $s, version: $v, projectPath: $p, projectPathPresent: $present,
     projectPathIsHome: $home, linkedWorktree: $wt, label: null, class: $c,
     projectEnabledEntry: (if $present != true or $home then null elif $p == $commit then "false" else "absent" end)};
  def user($v; $c): {scope: "user", version: $v, projectPath: null, projectPathPresent: null,
                     projectPathIsHome: null, linkedWorktree: null, label: null, class: $c};
  def div($id; $hi; $uh; $match; $scopes): {id: $id, versionsMatch: $match, highest: $hi, userHolds: $uh, scopes: $scopes};
  {marketplace: {name: "mk"},
   catalog_versions: {"zeta@mk": "1.0.5", "alpha@mk": "1.2.0", "beta@mk": "1.2.0"},
   installed: [],
   divergences: [
     div("alpha@mk"; "1.2.0"; true; false; [user("1.2.0"; "actionable"), rec("project"; "1.0.0"; $ok; true; false; false; "actionable")]),
     div("beta@mk"; "1.2.0"; true; false; [user("1.2.0"; "actionable"), rec("project"; "1.0.0"; $commit; true; false; false; "actionable")]),
     div("gamma@mk"; "1.2.0"; true; false; [user("1.2.0"; "actionable"), rec("project"; "1.0.0"; $gone; false; false; null; "blocked-absent")]),
     div("delta@mk"; "1.2.0"; true; false; [user("1.2.0"; "actionable"), rec("project"; "1.0.0"; $homedir; true; true; false; "blocked-home")]),
     div("epsilon@mk"; "1.2.0"; true; false; [user("1.2.0"; "actionable"), rec("project"; "1.0.0"; $wt; true; false; true; "worktree")]),
     div("zeta@mk"; "1.1.0"; false; false; [user("1.0.0"; "blocked-catalog"), rec("project"; "1.1.0"; $ok; true; false; false; "blocked-catalog")]),
     div("theta@mk"; "1.1.0"; false; false; [rec("project"; "1.1.0"; $ok; true; false; false; "actionable"), rec("project"; "1.0.0"; $wt; true; false; true; "worktree")]),
     div("iota@mk"; "1.2.0"; true; false; [user("1.2.0"; "actionable"), rec("project"; "1.0.0"; $nogit; true; false; false; "actionable")]),
     div("kappa@mk"; "1.2.0"; true; false; [user("1.2.0"; "actionable"), rec("local"; "1.0.0"; $ok; true; false; false; "actionable")]),
     div("eta@mk"; "1.2.0"; true; true; [user("1.2.0"; "actionable"), rec("project"; "1.2.0"; $ok; true; false; false; "actionable")])
   ]}' >"$REPORT"

PLAN="$TEST_TMPDIR/plan.json"
"$SCRIPT" --from "$REPORT" >"$PLAN" 2>"$TEST_TMPDIR/err"
assert_eq "plan exits 0" "0" "$?"

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
assert_eq "committed-enable update row offers uninstall as the alternative" \
  "uninstall|(cd '$P_COMMIT' && claude plugin uninstall beta@mk -s project --keep-data)|removes a committed enabledPlugins entry" \
  "$(field beta@mk '.alternative | "\(.strategy)|\(.command)|\(.warning)"')"
assert_eq "uninstall row offers update as the alternative, with no warning" \
  "update|(cd '$P_OK' && claude plugin update alpha@mk -s project)|null" \
  "$(field alpha@mk '.alternative | "\(.strategy)|\(.command)|\(.warning)"')"
assert_eq "worktree and blocked rows offer no alternative" "null null null" \
  "$(field epsilon@mk .alternative) $(field theta@mk .alternative) $(field zeta@mk .alternative)"
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
assert_eq "question calls: a blocked row in the path gets no question" "[[0,1]]" \
  "$(jq -c --arg p "$P_OK" '.groups[] | select(.projectPath == $p) | .question_calls' "$PLAN")"
assert_eq "question calls: a path with no runnable row asks nothing" "[]" \
  "$(jq -c --arg p "$P_GONE" '.groups[] | select(.projectPath == $p) | .question_calls' "$PLAN")"
jq -n --arg p "$P_OK" '
  {marketplace: {name: "mk"}, catalog_versions: {}, installed: [],
   divergences: [("a", "b", "c", "d", "e") | {id: "\(.)@mk", versionsMatch: false, highest: "1.2.0", userHolds: true, scopes: [
     {scope: "user", version: "1.2.0", projectPath: null, class: "actionable"},
     {scope: "project", version: "1.0.0", projectPath: $p, projectPathPresent: true, projectPathIsHome: false,
      linkedWorktree: false, projectEnabledEntry: "absent", class: "actionable"}]}]}' >"$TEST_TMPDIR/five-report.json"
assert_eq "question calls: five runnable rows in one path take a further call for the fifth" "[[0,1,2,3],[4]]" \
  "$("$SCRIPT" --from "$TEST_TMPDIR/five-report.json" | jq -c '.groups[] | select(.projectPath != null) | .question_calls')"

WT_COMMIT="$TEST_TMPDIR/wt-commit"
tracked_repo "$WT_COMMIT" '{"mu@mk":true}'
jq -n --arg p "$WT_COMMIT" '
  {marketplace: {name: "mk"}, catalog_versions: {}, installed: [],
   divergences: [{id: "mu@mk", versionsMatch: false, highest: "1.2.0", userHolds: true, scopes: [
     {scope: "user", version: "1.2.0", projectPath: null, projectPathPresent: null,
      projectPathIsHome: null, linkedWorktree: null, label: null, class: "actionable"},
     {scope: "project", version: "1.0.0", projectPath: $p, projectPathPresent: true,
      projectPathIsHome: false, linkedWorktree: true, label: null, class: "worktree"}]}]}' >"$TEST_TMPDIR/wt-report.json"
WT_PLAN="$("$SCRIPT" --from "$TEST_TMPDIR/wt-report.json")"
assert_eq "worktree + committed enable: uninstall is not the default" "false" \
  "$(jq -r '.groups[0].rows[0].default' <<<"$WT_PLAN")"
assert_eq "worktree + committed enable: carries the warning" "removes a committed enabledPlugins entry" \
  "$(jq -r '.groups[0].rows[0].warning' <<<"$WT_PLAN")"

SHADOW="$TEST_TMPDIR/shadow"
tracked_repo "$SHADOW" '{}'
entry_plan() {
  jq -n --arg p "$SHADOW" --argjson e "$1" '
    {marketplace: {name: "mk"}, catalog_versions: {"nu@mk": "1.2.0"}, installed: [],
     divergences: [{id: "nu@mk", versionsMatch: false, highest: "1.2.0", userHolds: true, scopes: [
       {scope: "user", version: "1.2.0", projectPath: null, projectPathPresent: null,
        projectPathIsHome: null, linkedWorktree: null, label: null, projectEnabledEntry: null, class: "actionable"},
       ({scope: "project", version: "1.0.0", projectPath: $p, projectPathPresent: true,
         projectPathIsHome: false, linkedWorktree: false, label: null, class: "actionable"}
        + (if $e == "missing" then {} else {projectEnabledEntry: $e} end))]}]}' >"$TEST_TMPDIR/entry-report.json"
  "$SCRIPT" --from "$TEST_TMPDIR/entry-report.json" | jq -r '.groups[] | select(.projectPath != null) | .rows[0].strategy'
}
assert_eq "an explicit committed false in the report defaults to update" "update" "$(entry_plan '"false"')"
assert_eq "an explicit committed true in the report defaults to update" "update" "$(entry_plan '"true"')"
assert_eq "no entry in the report keeps the uninstall default" "uninstall" "$(entry_plan '"absent"')"
assert_eq "an unreadable settings file counts as a committed enable" "update" "$(entry_plan '"unreadable"')"
assert_eq "a report without the field counts as a committed enable" "update" "$(entry_plan '"missing"')"

FLEET="$TEST_TMPDIR/fleet"
F_REPO="$FLEET/repo"
F_WT="$FLEET/wt"
F_HOME="$FLEET/home"
F_GONE="$FLEET/gone"
tracked_repo "$F_REPO" '{"beta@mk":false}'
git -C "$F_REPO" worktree add -q "$F_WT" -b wt
mkdir -p "$F_HOME"
for spec in alpha=1.2.0 beta=1.2.0 gamma=1.2.0 delta=1.2.0 epsilon=1.2.0 zeta=1.0.5; do
  mkdir -p "$FLEET/catalog/mk/${spec%=*}/.claude-plugin"
  printf '{"version":"%s"}\n' "${spec#*=}" >"$FLEET/catalog/mk/${spec%=*}/.claude-plugin/plugin.json"
done
jq -cn '{plugins: [("alpha", "beta", "gamma", "delta", "epsilon", "zeta") | {name: ., source: ("./" + .)}]}' \
  >"$FLEET/catalog/mk.json"
jq -cn '{mk: {source: {source: "github", repo: "e/mk"}, installLocation: "unused", lastUpdated: "2026-01-01T00:00:00Z"}}' \
  >"$FLEET/known_marketplaces.json"
printf '{"enabledPlugins":{}}\n' >"$FLEET/user_settings.json"
jq -n --arg repo "$F_REPO" --arg wt "$F_WT" --arg home "$F_HOME" --arg gone "$F_GONE" '
  def u($v): {scope: "user", installPath: "u", version: $v};
  def p($path; $v): {scope: "project", projectPath: $path, installPath: "p", version: $v};
  {version: 1, plugins: {
    "alpha@mk": [u("1.2.0"), p($repo; "1.0.0")],
    "beta@mk": [u("1.2.0"), p($repo; "1.0.0")],
    "gamma@mk": [u("1.2.0"), p($gone; "1.0.0")],
    "delta@mk": [u("1.2.0"), p($home; "1.0.0")],
    "epsilon@mk": [u("1.2.0"), p($wt; "1.0.0")],
    "zeta@mk": [u("1.0.0"), p($repo; "1.1.0")]}}' >"$FLEET/installed_plugins.json"
fleet_env=(HOME="$F_HOME" CLAUDE_PROJECT_DIR="$FLEET"
  FLEET_STATE_INSTALLED_JSON="$FLEET/installed_plugins.json"
  FLEET_STATE_MARKETPLACES_JSON="$FLEET/known_marketplaces.json"
  FLEET_STATE_USER_SETTINGS="$FLEET/user_settings.json"
  FLEET_STATE_CATALOG_DIR="$FLEET/catalog")
env "${fleet_env[@]}" bash "$SCRIPT_DIR/fleet-state.sh" --marketplace mk >"$FLEET/report.json"
assert_eq "fleet seam: fleet-state reads the fixture fleet" "0" "$?"
FLEET_PLAN="$("$SCRIPT" --from "$FLEET/report.json")"
counts() { jq -r '.counts | "\(.actionable) \(.worktree) \(.["blocked-absent"]) \(.["blocked-home"]) \(.["blocked-catalog"]) \(.rows)"' <<<"$1"; }
assert_eq "fleet seam: actionable, worktree, blocked-absent, blocked-home, blocked-catalog, rows" \
  "2 1 1 1 1 6" "$(counts "$FLEET_PLAN")"
fleet_row() { jq -r --arg id "$1" ".groups[].rows[] | select(.id == \$id) | $2" <<<"$FLEET_PLAN"; }
assert_eq "fleet seam: each pin's class comes from the real report" \
  "actionable actionable blocked-absent blocked-home worktree blocked-catalog" \
  "$(fleet_row alpha@mk .class) $(fleet_row beta@mk .class) $(fleet_row gamma@mk .class) $(fleet_row delta@mk .class) $(fleet_row epsilon@mk .class) $(fleet_row zeta@mk .class)"
assert_eq "fleet seam: the committed false entry fleet-state read defaults beta to update, alpha to uninstall" \
  "update uninstall" "$(fleet_row beta@mk .strategy) $(fleet_row alpha@mk .strategy)"
assert_eq "fleet seam: running fleet-state itself plans the same fleet" "$FLEET_PLAN" \
  "$(env "${fleet_env[@]}" "$SCRIPT" --marketplace mk)"

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
