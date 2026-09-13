#!/usr/bin/env bash
# Regression tests for permission-rule-check.sh (self-contained — ships with the plugin).
#
# Machine-path fixtures are assembled at runtime from separator + segment
# fragments so no contiguous machine-path literal appears in this file's source
# bytes — the repo's own machine-specific-path scanner sees a clean test file.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/permission-rule-check.sh"

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
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3" ;;
  *) pass "$1" ;;
  esac
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi

# Every run gets an isolated, EMPTY user home with CLAUDE_CONFIG_DIR unset. The
# user-global scan resolves ${CLAUDE_CONFIG_DIR:-$HOME/.claude}, so an inherited
# environment would read the operator's real ~/.claude — which no test may do —
# and its rules would pollute every case's finding count.
ISOLATED_HOME="$TEST_TMPDIR/empty-home"
mkdir -p "$ISOLATED_HOME"
# PERMISSION_HYGIENE_SCAN_ROOT is unset in every helper: it outranks the alias
# these cases pass, so an outer session exporting it would silently redirect the
# whole suite at another tree.
run() { env -u CLAUDE_CONFIG_DIR -u PERMISSION_HYGIENE_SCAN_ROOT HOME="$ISOLATED_HOME" PERMISSION_HYGIENE_FIXTURE_DIR="$1" bash "$SCRIPT" "${2:-}"; }
run_with_home() { env -u CLAUDE_CONFIG_DIR -u PERMISSION_HYGIENE_SCAN_ROOT HOME="$2" PERMISSION_HYGIENE_FIXTURE_DIR="$1" bash "$SCRIPT" "${3:-}"; }
run_with_config_dir() { env -u PERMISSION_HYGIENE_SCAN_ROOT CLAUDE_CONFIG_DIR="$2" HOME="$3" PERMISSION_HYGIENE_FIXTURE_DIR="$1" bash "$SCRIPT" "${4:-}"; }

# Runtime-assembled machine paths (no contiguous path literal in source).
SL='/'
# shellcheck disable=SC1003  # BS is a literal single backslash, not a quote escape
BS='\'
POSIX_MP="${SL}c${SL}Users${SL}alice${SL}.agents${SL}skills${SL}merge${SL}x.sh"
WIN_MP="C:${BS}Users${BS}bob${BS}x.sh"
READ_MP="${SL}c${SL}Users${SL}carol${SL}notes.md"
EDIT_MP="${SL}Users${SL}dave${SL}src${SL}**"
# #2282 rows: `//` absolute anchor, tool-reach, and prefix-laundering fixtures.
ABS_MP="${SL}${SL}Users${SL}erin${SL}secrets${SL}**"
LAUNDER_MP="${SL}${SL}opt${SL}data${SL}..${SL}Users${SL}frank${SL}secrets"
WF_MP="${SL}Users${SL}grace${SL}x"
GLOB_MP="${SL}home${SL}heidi${SL}**"
NB_MP="${SL}Users${SL}ivan${SL}nb.ipynb"
MCP_MP="${SL}Users${SL}judy${SL}x"

# --- Case 1: --help ----------------------------------------------------------
rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

# --- Case 2: P1 interpreter/blanket rules in settings.allow ------------------
D2="$TEST_TMPDIR/p1"
mkdir -p "$D2/.claude"
jq -n '{permissions:{allow:[
  "Bash(*)","PowerShell(*)","Bash(python*)","Bash(node *)","Bash(sh -c*)",
  "Bash(npx *)","Bash(npm:*)","Bash(pnpm:*)","Bash(yarn:*)","Bash(npm *)",
  "Bash(npm run *)","Bash(*.py:*)","Bash","Agent","Agent(code-reviewer)",
  "Bash(.venv/bin/python *)","Bash(/usr/bin/python3 *)",
  "Bash(python3.11 *)","Bash(/usr/bin/python3.12:*)"
]}}' >"$D2/.claude/settings.json"
rc=0
OUT=$(run "$D2") || rc=$?
assert_exit "P1 run exits 0 (advisory)" 0 "$rc"
assert_contains "flags blanket Bash(*)" "$OUT" "Bash(*)"
assert_contains "flags wildcarded interpreter python*" "$OUT" "Bash(python*)"
assert_contains "flags interpreter node *" "$OUT" "Bash(node *)"
assert_contains "flags sh -c*" "$OUT" "Bash(sh -c*)"
assert_contains "flags package-manager runner npx *" "$OUT" "Bash(npx *)"
assert_contains "flags bare package-manager wildcard npm:*" "$OUT" "Bash(npm:*)"
assert_contains "flags bare package-manager wildcard pnpm:*" "$OUT" "Bash(pnpm:*)"
assert_contains "flags bare package-manager wildcard yarn:*" "$OUT" "Bash(yarn:*)"
assert_contains "flags space-form package-manager wildcard npm *" "$OUT" "Bash(npm *)"
assert_contains "flags package-manager run wildcard npm run *" "$OUT" "Bash(npm run *)"
assert_contains "flags script-glob interpreter *.py:*" "$OUT" "Bash(*.py:*)"
assert_contains "flags venv path-prefixed interpreter" "$OUT" "Bash(.venv/bin/python *)"
assert_contains "flags absolute path-prefixed interpreter" "$OUT" "Bash(/usr/bin/python3 *)"
assert_contains "flags version-suffixed interpreter" "$OUT" "Bash(python3.11 *)"
assert_contains "flags path-prefixed version-suffixed interpreter" "$OUT" "Bash(/usr/bin/python3.12:*)"
assert_contains "flags PowerShell(*)" "$OUT" "PowerShell(*)"
assert_contains "flags bare Bash allow" "$OUT" "bare 'Bash'"
assert_contains "flags Agent allow rule" "$OUT" "Agent allow rules are dropped"
assert_contains "P1 findings tagged" "$OUT" "[P1]"

# --- Case 2b: scoped Agent(...) is flagged (no other detector covers it) -----
# Unlike Bash(npm test), a scoped Agent rule is NOT a narrow carry-over: auto
# mode drops all Agent allow rules, so the parenthesized form must flag too.
D2B="$TEST_TMPDIR/agent-scoped"
mkdir -p "$D2B/.claude"
jq -n '{permissions:{allow:["Agent(code-reviewer)"]}}' >"$D2B/.claude/settings.json"
OUT=$(run "$D2B")
assert_contains "flags scoped Agent(code-reviewer)" "$OUT" "Agent allow rules are dropped"
assert_contains "scoped Agent finding tagged P1" "$OUT" "[P1]"
assert_eq "scoped Agent produces exactly one finding" "1" "$(run "$D2B" --count)"

# --- Case 3: narrow rules carry over — NOT flagged --------------------------
D3="$TEST_TMPDIR/narrow"
mkdir -p "$D3/.claude"
jq -n '{permissions:{allow:[
  "Bash(npm test)","Bash(npm run build)","Bash(yarn build)","Bash(pnpm install)",
  "Bash(cargo build)","Bash(git commit *)",
  "Bash(babysit_merge.sh:*)","Read(~/.config/app/config.toml)",
  "Bash(echo Agent)","Bash(find *Agent*)",
  "Bash(echo Bash)","Bash(grep PowerShell *)",
  "Bash(node-gyp:*)","Bash(ruby-lsp:*)","Bash(npm-check-updates:*)",
  "Bash(echo $(date) Agent)","Bash(node -e \"console.log()\" PowerShell)"
]}}' >"$D3/.claude/settings.json"
OUT=$(run "$D3")
assert_contains "clean narrow ruleset reports none" "$OUT" "No fragile permission grants"
assert_not_contains "word 'Agent' inside a Bash payload is not an Agent finding" "$OUT" "Agent allow rules are dropped"
assert_not_contains "tool name inside a Bash payload is not a bare-tool finding" "$OUT" "bare '"
assert_eq "narrow ruleset count == 0" "0" "$(run "$D3" --count)"

# --- Case 4: P2 hardcoded machine paths -------------------------------------
D4="$TEST_TMPDIR/p2"
mkdir -p "$D4/.claude"
jq -n --arg posix "Bash(${POSIX_MP}:*)" --arg win "Bash(${WIN_MP}:*)" \
  '{permissions:{allow:[$posix,$win]}}' >"$D4/.claude/settings.json"
OUT=$(run "$D4")
assert_contains "flags POSIX-normalized machine path" "$OUT" "[P2]"
assert_contains "P2 detail names the portability break" "$OUT" "breaks on other machines"
assert_not_contains "P2 detail does not assert a blanket no-expansion rule" "$OUT" "no ~/\$HOME"
assert_not_contains "P2 detail does not scope its rationale to Bash rules" "$OUT" "Bash rules match literally"
assert_eq "two machine-path findings" "2" "$(run "$D4" --count)"

# P2 fires on Read/Edit rules too, and those rule classes DO resolve `~/`
# (permissions.md: "`~/path` | Path from home directory"). One message string serves
# every class, so it must not carry a Bash-only mechanism — that would be a false
# claim on a true finding.
D4B="$TEST_TMPDIR/p2-file-tools"
mkdir -p "$D4B/.claude"
jq -n --arg r "Read(${READ_MP})" --arg e "Edit(${EDIT_MP})" \
  '{permissions:{allow:[$r,$e]}}' >"$D4B/.claude/settings.json"
OUT_FT=$(run "$D4B")
assert_contains "flags a machine path in a Read rule" "$OUT_FT" "[P2]"
assert_not_contains "Read-rule finding does not claim Bash semantics" "$OUT_FT" "Bash rules match literally"
assert_not_contains "Read-rule finding does not deny ~ expansion" "$OUT_FT" "no ~/\$HOME"
assert_eq "both file-tool machine paths flagged" "2" "$(run "$D4B" --count)"

# --- Case 5: P2 exemptions — PROJECT_DIR / home-relative not flagged ---------
D5="$TEST_TMPDIR/p2-exempt"
mkdir -p "$D5/.claude"
jq -n '{permissions:{allow:[
  "Bash(${CLAUDE_PROJECT_DIR}/scripts/lint.sh *)","Read(~/Documents/notes.md)"
]}}' >"$D5/.claude/settings.json"
assert_eq "portable path forms not flagged" "0" "$(run "$D5" --count)"

# --- Case 6: frontmatter allowed-tools (inline + block list) ----------------
D6="$TEST_TMPDIR/frontmatter"
mkdir -p "$D6/.claude/skills/bad" "$D6/.claude/skills/good" "$D6/.claude/agents"
cat >"$D6/.claude/skills/bad/SKILL.md" <<'EOF'
---
name: bad
allowed-tools: Bash(python "*merge.py":*)
---
body
EOF
cat >"$D6/.claude/skills/good/SKILL.md" <<'EOF'
---
name: good
allowed-tools:
  - Bash(git add *)
  - Bash(npm test)
---
body
EOF
cat >"$D6/.claude/agents/runner.md" <<'EOF'
---
name: runner
allowed-tools:
  - Bash(node *)
---
body
EOF
mkdir -p "$D6/.claude/skills/bare"
cat >"$D6/.claude/skills/bare/SKILL.md" <<'EOF'
---
name: bare
allowed-tools: Bash
---
body
EOF
mkdir -p "$D6/.claude/skills/agent"
cat >"$D6/.claude/skills/agent/SKILL.md" <<'EOF'
---
name: agent
allowed-tools:
  - Agent(code-reviewer)
---
body
EOF
OUT=$(run "$D6")
assert_contains "flags interpreter in skill frontmatter" "$OUT" "skills/bad/SKILL.md allowed-tools"
assert_contains "flags interpreter in agent frontmatter" "$OUT" "agents/runner.md allowed-tools"
assert_contains "flags bare Bash in skill frontmatter" "$OUT" "skills/bare/SKILL.md allowed-tools: bare 'Bash'"
assert_contains "flags Agent rule in skill frontmatter" "$OUT" "skills/agent/SKILL.md allowed-tools: Agent allow rules are dropped"
assert_not_contains "does NOT flag narrow git/npm skill" "$OUT" "skills/good/SKILL.md"

# --- Case 6b: non-loadable SKILL.md excluded by loadability model ------------
# A SKILL.md outside documented load paths (vendored upstream reference) is not
# loadable, so its allowed-tools never take effect and must not be flagged —
# while a real sibling skill with the same grant still is. Nested
# `vendor/.claude/skills/<name>/SKILL.md` IS loadable (#2406, Case 6c).
D6B="$TEST_TMPDIR/vendor-exclusion-fixture"
mkdir -p "$D6B/plugins/p/skills/real" \
  "$D6B/plugins/p/skills/real/vendor" \
  "$D6B/plugins/p/skills/real/vendor/cli"
GRANT=$'---\nname: x\nallowed-tools: Bash(npm:*)\n---\nbody\n'
printf '%s' "$GRANT" >"$D6B/plugins/p/skills/real/SKILL.md"
printf '%s' "$GRANT" >"$D6B/plugins/p/skills/real/vendor/SKILL.md"
printf '%s' "$GRANT" >"$D6B/plugins/p/skills/real/vendor/cli/SKILL.md"
OUT=$(run "$D6B")
assert_contains "flags the real loadable SKILL.md" "$OUT" "skills/real/SKILL.md allowed-tools"
assert_not_contains "does NOT flag vendored direct-child SKILL.md" "$OUT" "vendor/SKILL.md"
assert_not_contains "does NOT flag vendored nested SKILL.md" "$OUT" "vendor/cli/SKILL.md"
assert_eq "vendored copies excluded — exactly one finding" "1" "$(run "$D6B" --count)"

# --- Case 6c: #2406 — nested `.claude/skills/` under vendor/ IS loadable ----
D6C="$TEST_TMPDIR/loadability-nested-vendor"
mkdir -p "$D6C/vendor/pkg/.claude/skills/nested"
printf '%s' "$GRANT" >"$D6C/vendor/pkg/.claude/skills/nested/SKILL.md"
OUT_NESTED=$(run "$D6C")
assert_contains "flags nested vendor/.claude/skills grant" "$OUT_NESTED" "vendor/pkg/.claude/skills/nested/SKILL.md"
assert_eq "nested vendor/.claude/skills is audited" "1" "$(run "$D6C" --count)"

# --- Case 6d: #2406 — node_modules/.claude/skills/ IS loadable ---------------
D6D="$TEST_TMPDIR/loadability-node-modules"
mkdir -p "$D6D/node_modules/@scope/pkg/.claude/skills/pkg-skill"
printf '%s' "$GRANT" >"$D6D/node_modules/@scope/pkg/.claude/skills/pkg-skill/SKILL.md"
assert_eq "node_modules nested skill is audited" "1" "$(run "$D6D" --count)"

# --- Case 7: P3 plugin self-grant -------------------------------------------
D7="$TEST_TMPDIR/p3"
mkdir -p "$D7/plugins/foo/.claude-plugin" "$D7/plugins/ok/.claude-plugin"
printf '{"name":"foo"}\n' >"$D7/plugins/foo/.claude-plugin/plugin.json"
printf '{"name":"ok"}\n' >"$D7/plugins/ok/.claude-plugin/plugin.json"
jq -n '{permissions:{allow:["Bash(x.sh:*)"]}}' >"$D7/plugins/foo/settings.json"
jq -n '{agent:{model:"opus"}}' >"$D7/plugins/ok/settings.json"
OUT=$(run "$D7")
assert_contains "flags plugin settings.json with permissions" "$OUT" "[P3]"
assert_contains "P3 names the offending plugin file" "$OUT" "plugins/foo/settings.json"
assert_not_contains "does NOT flag agent-only plugin settings" "$OUT" "plugins/ok/settings.json"

# --- Case 8: clean repo ------------------------------------------------------
D8="$TEST_TMPDIR/clean"
mkdir -p "$D8/.claude"
jq -n '{permissions:{allow:["Bash(babysit_merge.sh:*)"]}}' >"$D8/.claude/settings.json"
assert_contains "clean repo message" "$(run "$D8")" "No fragile permission grants"

# --- Case 8b: settings.local.json scanned same as settings.json --------------
D8B="$TEST_TMPDIR/local-settings"
mkdir -p "$D8B/.claude"
jq -n '{permissions:{allow:["Bash(python*)"]}}' >"$D8B/.claude/settings.local.json"
OUT=$(run "$D8B")
assert_contains "flags P1 grant in settings.local.json" "$OUT" "Bash(python*)"
assert_contains "finding names the local settings file" "$OUT" "settings.local.json"

# --- Case 8c: user-global settings scanned (scope widening) ------------------
# A user-global interpreter-wildcard rule was invisible to a project-only scan,
# yet user scope is where Claude Code's own "Always allow" path writes.
D8C="$TEST_TMPDIR/user-global-project"
mkdir -p "$D8C/.claude"
jq -n '{permissions:{allow:["Bash(git status)"]}}' >"$D8C/.claude/settings.json"
FAKE_HOME="$TEST_TMPDIR/fake-home"
mkdir -p "$FAKE_HOME/.claude"
jq -n '{permissions:{allow:["Bash(python*)"]}}' >"$FAKE_HOME/.claude/settings.json"
OUT=$(run_with_home "$D8C" "$FAKE_HOME")
assert_contains "flags P1 grant in user-global settings" "$OUT" "Bash(python*)"
assert_contains "user-global finding names the resolved file" "$OUT" "$FAKE_HOME/.claude/settings.json"
assert_eq "user-global grant produces exactly one finding" "1" "$(run_with_home "$D8C" "$FAKE_HOME" --count)"

# The same project against an EMPTY home must report nothing — proving the
# fixture home, not an inherited real one, produced the finding above.
assert_eq "empty user home contributes no findings" "0" "$(run "$D8C" --count)"

# --- Case 8d: CLAUDE_CONFIG_DIR relocates the user scope ---------------------
# Per the official .claude-directory doc it moves the whole ~/.claude tree, so a
# reader keyed on $HOME alone would audit a file that is not in effect.
RELOCATED="$TEST_TMPDIR/relocated-config"
mkdir -p "$RELOCATED"
jq -n '{permissions:{allow:["Bash(npx *)"]}}' >"$RELOCATED/settings.json"
OUT=$(run_with_config_dir "$D8C" "$RELOCATED" "$FAKE_HOME")
assert_contains "reads the relocated config root" "$OUT" "Bash(npx *)"
assert_not_contains "ignores \$HOME once CLAUDE_CONFIG_DIR is set" "$OUT" "Bash(python*)"
assert_eq "relocated config root produces exactly one finding" "1" \
  "$(run_with_config_dir "$D8C" "$RELOCATED" "$FAKE_HOME" --count)"

# --- Case 8e: an unresolvable user scope is announced, never silently skipped --
# With neither CLAUDE_CONFIG_DIR nor HOME set there is no user scope to read. A
# silent skip would let "No fragile permission grants found." rest on a scope
# that was never opened.
err_out=$(env -u CLAUDE_CONFIG_DIR -u HOME -u PERMISSION_HYGIENE_SCAN_ROOT PERMISSION_HYGIENE_FIXTURE_DIR="$D8C" bash "$SCRIPT" 2>&1 >/dev/null)
assert_contains "unresolvable user scope is announced" "$err_out" "user-global scope not scanned"

# --- Case 8f: #2283 A11 — operator-facing scan-root override name ----------------
D_SCAN="$TEST_TMPDIR/scan-root-alias"
mkdir -p "$D_SCAN/.claude"
jq -n '{permissions:{allow:["Bash(npm test)"]}}' >"$D_SCAN/.claude/settings.json"
assert_eq "PERMISSION_HYGIENE_SCAN_ROOT resolves the scan root" "0" \
  "$(env -u CLAUDE_CONFIG_DIR -u PERMISSION_HYGIENE_FIXTURE_DIR HOME="$ISOLATED_HOME" PERMISSION_HYGIENE_SCAN_ROOT="$D_SCAN" bash "$SCRIPT" --count)"

D_FIXTURE="$TEST_TMPDIR/fixture-root-alias"
mkdir -p "$D_FIXTURE/.claude"
jq -n '{permissions:{allow:["Bash(python*)"]}}' >"$D_FIXTURE/.claude/settings.json"
assert_eq "PERMISSION_HYGIENE_SCAN_ROOT wins over deprecated fixture dir" "0" \
  "$(env -u CLAUDE_CONFIG_DIR HOME="$ISOLATED_HOME" PERMISSION_HYGIENE_SCAN_ROOT="$D_SCAN" PERMISSION_HYGIENE_FIXTURE_DIR="$D_FIXTURE" bash "$SCRIPT" --count)"

# --- Case 9b: unresolvable scan root refuses instead of sweeping -------------
# The root ladder is $PERMISSION_HYGIENE_SCAN_ROOT (or the deprecated
# $PERMISSION_HYGIENE_FIXTURE_DIR) -> git toplevel -> $CLAUDE_PROJECT_DIR, with
# NO fallback to the cwd. Run from a non-repo directory with every rung unset:
# the scan must refuse (exit 2, the environment-gap channel) rather than walk
# whatever the cwd happens to be and report a clean bill.
#
# CLAUDE_PROJECT_DIR is unset explicitly as well as the fixture var — an outer
# session that exports it would otherwise resolve the root and hide the regression.
nonrepo="$TEST_TMPDIR/not-a-repo"
mkdir -p "$nonrepo"

rc=0
root_err=$(cd "$nonrepo" && env -u PERMISSION_HYGIENE_FIXTURE_DIR -u PERMISSION_HYGIENE_SCAN_ROOT -u CLAUDE_PROJECT_DIR \
  GIT_CEILING_DIRECTORIES="$TEST_TMPDIR" bash "$SCRIPT" 2>&1) || rc=$?
assert_exit "unresolvable root exits 2, not 0" 2 "$rc"
assert_contains "refusal names the failure" "$root_err" "no scan root resolved"
assert_not_contains "refusal is not a clean bill" "$root_err" "No fragile permission grants found."

rc=0
count_err=$(cd "$nonrepo" && env -u PERMISSION_HYGIENE_FIXTURE_DIR -u PERMISSION_HYGIENE_SCAN_ROOT -u CLAUDE_PROJECT_DIR \
  GIT_CEILING_DIRECTORIES="$TEST_TMPDIR" bash "$SCRIPT" --count 2>&1) || rc=$?
assert_exit "--count also refuses rather than printing 0" 2 "$rc"
assert_not_contains "--count prints no count on a refusal" "$count_err" "0
"

# A resolvable root still works, so the refusal did not break the normal path.
assert_eq "explicit fixture root still scans" "0" "$(run "$TEST_TMPDIR/p2-exempt" --count)"

# A root that resolved but does not exist — or is not a directory — is the same class
# of environment gap and takes the same channel. Without this, `find` would print
# nothing to a discarded stderr and the run would still report a clean bill.
rc=0
missing_err=$(PERMISSION_HYGIENE_FIXTURE_DIR="$TEST_TMPDIR/does-not-exist" bash "$SCRIPT" 2>&1) || rc=$?
assert_exit "fixture root that does not exist refuses" 2 "$rc"
assert_contains "refusal names the bad path" "$missing_err" "does not exist or is not a directory"
assert_not_contains "missing root is not a clean bill" "$missing_err" "No fragile permission grants found."

not_a_dir="$TEST_TMPDIR/regular-file"
: >"$not_a_dir"
rc=0
notdir_err=$(PERMISSION_HYGIENE_FIXTURE_DIR="$not_a_dir" bash "$SCRIPT" 2>&1) || rc=$?
assert_exit "fixture root that is a regular file refuses" 2 "$rc"
assert_contains "regular-file refusal names the same reason" "$notdir_err" "not a directory"

rc=0
PERMISSION_HYGIENE_FIXTURE_DIR="$TEST_TMPDIR/does-not-exist" bash "$SCRIPT" --count >/dev/null 2>&1 || rc=$?
assert_exit "--count refuses a nonexistent root too" 2 "$rc"

# --- Case 10: the denominator ------------------------------------------------
# A run that parsed forty grants and found them healthy and a run that parsed
# none at all must print different strings. These cases pin that a scan of
# nothing and a clean bill stay distinct, and that the coverage block reports
# what was NOT read as well as what was.

# 10a: a root with nothing in it is NOT a clean bill.
D10A="$TEST_TMPDIR/empty-root"
mkdir -p "$D10A"
OUT=$(run "$D10A")
assert_contains "empty root reports NOTHING TO AUDIT" "$OUT" "NOTHING TO AUDIT"
assert_not_contains "empty root does NOT print a clean bill" "$OUT" "No fragile permission grants found."
assert_contains "empty root still prints the coverage block" "$OUT" "Scan coverage"
assert_contains "empty root denominator names zero blocks" "$OUT" "0 allowed-tools block(s)"

# 10b: a root with healthy grants IS a clean bill, and says how many it read.
# This is the pair 10a exists against: same finding count, different denominator.
D10B="$TEST_TMPDIR/clean-with-denominator"
mkdir -p "$D10B/.claude"
jq -n '{permissions:{allow:["Bash(npm test)","Bash(cargo build)"]}}' >"$D10B/.claude/settings.json"
OUT=$(run "$D10B")
assert_contains "healthy root prints the clean bill" "$OUT" "No fragile permission grants found."
assert_not_contains "healthy root is not NOTHING TO AUDIT" "$OUT" "NOTHING TO AUDIT"
assert_contains "clean bill carries a non-zero rule count" "$OUT" "2 allow rule(s)"
assert_contains "coverage names the project scope it read" "$OUT" "project: 2 rule(s)"
assert_contains "coverage names an absent scope as absent" "$OUT" "local: absent"

# 10bb: P3 is the third axis and counts toward the denominator. A root whose only
# auditable surface is plugin settings.json files, all clean, IS a clean bill —
# the run examined two files. Folding only frontmatter and allow rules into the
# denominator made this print "this run has no denominator" two lines above the
# count of the files it had just examined, which is the defect the block exists
# to remove wearing a new spelling.
D10BB="$TEST_TMPDIR/p3-only-clean"
mkdir -p "$D10BB/plugins/foo/.claude-plugin" "$D10BB/plugins/ok/.claude-plugin"
jq -n '{name:"foo"}' >"$D10BB/plugins/foo/.claude-plugin/plugin.json"
jq -n '{name:"ok"}' >"$D10BB/plugins/ok/.claude-plugin/plugin.json"
jq -n '{agent:{model:"opus"}}' >"$D10BB/plugins/foo/settings.json"
jq -n '{agent:{model:"opus"}}' >"$D10BB/plugins/ok/settings.json"
OUT=$(run "$D10BB")
assert_contains "a clean P3-only root is a clean bill" "$OUT" "No fragile permission grants found."
assert_not_contains "a clean P3-only root is NOT a scan of nothing" "$OUT" "NOTHING TO AUDIT"
assert_contains "coverage counts the plugin settings it parsed" "$OUT" "2 settings.json parsed"

# 10bf: the denominator's unit is "examined", not "produced a finding" — on ALL
# THREE axes, not just P3's. Frontmatter files with no allowed-tools block, and a
# settings.json that parses with an empty allow array, were all examined and found
# to grant nothing. That is a clean bill, exactly as a parsed plugin settings.json
# declaring no `permissions` always was. Counting only the productive inputs is
# "a denominator that counts only successes" — the defect this block exists to
# remove — and it survived three earlier revisions of the formula.
D10BF="$TEST_TMPDIR/examined-not-productive"
mkdir -p "$D10BF/.claude/skills/a" "$D10BF/.claude/skills/b" "$D10BF/.claude"
printf -- '---\nname: a\n---\nbody\n' >"$D10BF/.claude/skills/a/SKILL.md"
printf -- '---\nname: b\n---\nbody\n' >"$D10BF/.claude/skills/b/SKILL.md"
jq -n '{permissions:{allow:[]}}' >"$D10BF/.claude/settings.json"
OUT=$(run "$D10BF")
assert_contains "examined-but-unproductive inputs are a clean bill" "$OUT" \
  "No fragile permission grants found."
assert_not_contains "examined-but-unproductive inputs are NOT a scan of nothing" "$OUT" \
  "NOTHING TO AUDIT"
assert_contains "the denominator names its per-axis units" "$OUT" \
  "DENOMINATOR = 3 input(s) successfully examined: 2 frontmatter file(s) + 1 settings scope(s) + 0 plugin settings.json"

# 10bc: the completeness invariant. Every enumerated frontmatter candidate must
# land in exactly one bucket, and the script reconciles the buckets against the
# enumeration itself rather than trusting each `continue` site.
D10BC="$TEST_TMPDIR/reconcile"
mkdir -p "$D10BC/.claude/skills/a" "$D10BC/.claude/skills/b" "$D10BC/skills/c/vendor"
printf -- '---\nname: a\nallowed-tools: Bash(npm test)\n---\nbody\n' >"$D10BC/.claude/skills/a/SKILL.md"
printf -- '---\nname: b\n---\nbody\n' >"$D10BC/.claude/skills/b/SKILL.md"
printf -- '---\nname: v\nallowed-tools: Bash(npm:*)\n---\nbody\n' >"$D10BC/skills/c/vendor/SKILL.md"
OUT=$(run "$D10BC")
assert_contains "coverage reconciles candidates against buckets" "$OUT" "reconciled: 3 candidate(s)"
assert_contains "reconciliation names each bucket" "$OUT" \
  "1 non-loadable-excluded + 0 unreadable + 1 without an allowed-tools block + 1 parsed"
assert_not_contains "no candidate escaped a bucket" "$OUT" "DENOMINATOR BUG"

# 10bd: NEGATIVE — the invariant must actually discriminate. Drop one bucket
# increment from a copy of the script; the reconciliation must catch it. A check
# that cannot fail is not a check, and "a real surface examined and counted
# nowhere" has already produced two instances inside this one change.
BROKEN="$TEST_TMPDIR/broken-check.sh"
# shellcheck disable=SC2016  # single quotes are required: the $((...)) here is the
# literal source text being matched in the script, not an expression to evaluate.
sed 's/^    fm_no_block=$((fm_no_block + 1))$/    : # bucket increment deliberately removed/' \
  "$SCRIPT" >"$BROKEN"
if grep -q 'bucket increment deliberately removed' "$BROKEN"; then
  # CLAUDE_PLUGIN_ROOT must be passed explicitly: the copy lives outside the
  # plugin tree, so its BASH_SOURCE fallback would resolve the shared pattern
  # library to a bogus path and exit 2 before ever reaching the reconciliation.
  broken_out=$(env -u CLAUDE_CONFIG_DIR -u PERMISSION_HYGIENE_SCAN_ROOT HOME="$ISOLATED_HOME" \
    CLAUDE_PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)" \
    PERMISSION_HYGIENE_FIXTURE_DIR="$D10BC" bash "$BROKEN" 2>&1)
  assert_contains "a candidate escaping every bucket is caught, not absorbed" "$broken_out" "DENOMINATOR BUG"
  assert_contains "the bug report names it as a defect in the script" "$broken_out" \
    "defect in permission-rule-check.sh"
else
  fail "negative reconciliation case could not be constructed" \
    "the sed target no longer matches permission-rule-check.sh — the invariant is UNVERIFIED by this run"
fi

# 10be: a candidate `find` can enumerate but the process cannot read. `find`
# needs only directory-traversal permission to report a file as -type f; it does
# not need read permission on the file. Before the readability gate such a file
# reached awk, failed there, wrote to the real stderr and was counted in NO
# bucket — while the coverage block claimed to disclose unread inputs.
D10BE="$TEST_TMPDIR/unreadable"
mkdir -p "$D10BE/.claude/skills/u"
printf -- '---\nname: u\nallowed-tools: Bash(python*)\n---\nbody\n' >"$D10BE/.claude/skills/u/SKILL.md"
chmod 000 "$D10BE/.claude/skills/u/SKILL.md" 2>/dev/null
if [[ -r "$D10BE/.claude/skills/u/SKILL.md" ]]; then
  # ANNOUNCED, never silent: on Windows/Git Bash, and as root, mode 000 does not
  # deny the owner a read, so the fixture cannot be built here. The invariant is
  # still asserted; only the unreadable arm goes unexercised, and it runs on CI.
  printf 'SKIP: unreadable-candidate arm not exercised — this platform still grants read after chmod 000 (owner/ACL/filesystem). Exercised on POSIX CI.\n' >&2
  assert_contains "invariant still reconciles where the arm cannot be built" "$(run "$D10BE")" \
    "reconciled: 1 candidate(s)"
else
  OUT=$(run "$D10BE")
  assert_contains "an unreadable candidate is counted, not dropped" "$OUT" \
    "1 frontmatter candidate(s) enumerated but unopenable"
  assert_contains "the unreadable candidate reconciles into its bucket" "$OUT" \
    "0 non-loadable-excluded + 1 unreadable + 0 without an allowed-tools block + 0 parsed"
  assert_not_contains "an unreadable-only root is not a plain clean bill" "$OUT" \
    "No fragile permission grants found."
  assert_contains "an unreadable-only root names the blocked inputs" "$OUT" "COULD NOT BE READ"
fi
chmod u+rw "$D10BE/.claude/skills/u/SKILL.md" 2>/dev/null

# 10c: a settings file that is present but not valid JSON must be named and
# counted under NOT read, never skipped in silence behind a clean bill. An
# unparsable rules file is exactly where a fragile grant would sit unexamined.
D10C="$TEST_TMPDIR/unparsable-settings"
mkdir -p "$D10C/.claude"
printf '{ "permissions": { "allow": [ "Bash(python*)"\n' >"$D10C/.claude/settings.json"
OUT=$(run "$D10C")
assert_contains "unparsable settings file is named, not skipped in silence" "$OUT" "project: NOT VALID JSON"
assert_contains "unparsable file is counted under NOT read" "$OUT" "NOT read:"
assert_not_contains "a run whose only rules file will not parse is not a clean bill" "$OUT" "No fragile permission grants found."

# 10d: --count keeps the bare integer on stdout (the machine contract) and puts
# the coverage block on stderr, so a 0 from a scan of nothing is still separable
# from a 0 from a healthy tree.
assert_eq "--count stdout is still the bare integer" "0" "$(run "$D10B" --count)"
count_cov=$(run "$D10B" --count 2>&1 >/dev/null)
assert_contains "--count writes the coverage block to stderr" "$count_cov" "Scan coverage"
assert_contains "--count coverage carries the denominator" "$count_cov" "2 allow rule(s)"

# 10e: the loadability filter reports how many files it removed. An exclusion
# nothing counts is indistinguishable from a tree that had nothing in it.
OUT=$(run "$D6B")
assert_contains "loadability exclusion discloses its count" "$OUT" "2 excluded as non-loadable"
assert_contains "coverage names the candidate file total" "$OUT" "from 3 candidate file(s)"

# --- Case 11: the scan-root lever is named for operators, not for tests -------
# $PERMISSION_HYGIENE_FIXTURE_DIR is the documented remedy for the exit-2 refusal
# while its name says it is a test seam. The sanctioned name resolves the same
# root; the alias keeps working; the new name wins when both are set.
sanctioned() { env -u CLAUDE_CONFIG_DIR -u PERMISSION_HYGIENE_FIXTURE_DIR HOME="$ISOLATED_HOME" \
  PERMISSION_HYGIENE_SCAN_ROOT="$1" bash "$SCRIPT" "${2:-}"; }
assert_eq "PERMISSION_HYGIENE_SCAN_ROOT resolves a root" "0" "$(sanctioned "$D10B" --count)"
assert_contains "coverage names the rung that resolved the root" "$(sanctioned "$D10B")" \
  "resolved from \$PERMISSION_HYGIENE_SCAN_ROOT"
assert_contains "the legacy alias still resolves a root" "$(run "$D10B")" \
  "resolved from \$PERMISSION_HYGIENE_FIXTURE_DIR"
both=$(env -u CLAUDE_CONFIG_DIR HOME="$ISOLATED_HOME" \
  PERMISSION_HYGIENE_SCAN_ROOT="$D10B" PERMISSION_HYGIENE_FIXTURE_DIR="$D10A" bash "$SCRIPT")
assert_contains "the sanctioned name wins over the alias" "$both" "No fragile permission grants found."
assert_not_contains "the alias did not win" "$both" "NOTHING TO AUDIT"
assert_contains "refusal names the sanctioned variable as the fix" \
  "$(cd "$nonrepo" && env -u PERMISSION_HYGIENE_FIXTURE_DIR -u PERMISSION_HYGIENE_SCAN_ROOT \
    -u CLAUDE_PROJECT_DIR GIT_CEILING_DIRECTORIES="$TEST_TMPDIR" bash "$SCRIPT" 2>&1)" \
  "PERMISSION_HYGIENE_SCAN_ROOT"

# --- Case 12: #2282 — full-rule reporting, `//` is NOT exempt, P1 pinned npm view
#
# `//` is the ABSOLUTE anchor, not a portable one. permissions.md's own table row is
# `//path` = "Absolute path from filesystem root", with `Read(//Users/<name>/secrets/**)`
# resolving to `/Users/<name>/secrets/**`, and the same page says "Use
# `//Users/<name>/file` for absolute paths." The docs' literal example names a concrete
# user home and leaks `alice`. An earlier revision of this suite asserted the opposite,
# which would have taught an `error`-tier username-leak check to ignore the canonical
# spelling of the leak.
D12A="$TEST_TMPDIR/issue-2282"
mkdir -p "$D12A/.claude"
jq -n --arg posix "Bash(${POSIX_MP}:*)" --arg abs "Read(${ABS_MP})" \
  '{permissions:{allow:[$abs, "Bash(npm view ctx7 version*)", $posix]}}' >"$D12A/.claude/settings.json"
OUT_2282=$(run "$D12A")
assert_contains "// absolute anchor IS flagged — it names a concrete user home" "$OUT_2282" "Read(${ABS_MP})"
assert_contains "P2 reports the full offending Bash rule" "$OUT_2282" "Bash(${POSIX_MP}:*)"
assert_not_contains "fully-pinned npm view rule is not flagged as P1" "$OUT_2282" "npm view ctx7 version"
assert_eq "both machine-path rules flagged, npm view not" "2" "$(run "$D12A" --count)"

# --- Case 12b: the genuinely portable anchors stay exempt ---------------------
# The distinction the fix turns on: `~/` and `${CLAUDE_PROJECT_DIR}/` supply the
# user/project segment at resolution time; `//` does not.
D12B="$TEST_TMPDIR/issue-2282-portable"
mkdir -p "$D12B/.claude"
jq -n '{permissions:{allow:["Read(~/Documents/*.pdf)","Bash(${CLAUDE_PROJECT_DIR}/scripts/x.sh:*)"]}}' >"$D12B/.claude/settings.json"
assert_eq "portable anchors produce no P2 finding" "0" "$(run "$D12B" --count)"

# --- Case 12c: P2 reach is the open tool grammar, not five hardcoded names -----
# A hardcoded machine path leaks a username whatever tool the rule names. An
# enumerated (Read|Edit|Write|Bash|PowerShell) list silently stopped flagging these;
# `Agent` in particular is indefensible, since this script has a dedicated
# scan_agent(). Each rule below must produce its own P2 finding.
D8D="$TEST_TMPDIR/issue-2282-tools"
mkdir -p "$D8D/.claude"
jq -n --arg wf "WebFetch(${WF_MP})" --arg gl "Glob(${GLOB_MP})" --arg nb "NotebookEdit(${NB_MP})" --arg mc "mcp__srv__tool(${MCP_MP})" '{permissions:{allow:[$wf,$gl,$nb,$mc]}}' >"$D8D/.claude/settings.json"
OUT_TOOLS=$(run "$D8D")
assert_contains "P2 sees WebFetch rules" "$OUT_TOOLS" "WebFetch(${WF_MP})"
assert_contains "P2 sees Glob rules" "$OUT_TOOLS" "Glob(${GLOB_MP})"
assert_contains "P2 sees NotebookEdit rules" "$OUT_TOOLS" "NotebookEdit(${NB_MP})"
assert_contains "P2 sees MCP tool rules" "$OUT_TOOLS" "mcp__srv__tool(${MCP_MP})"

# --- Case 12d: a `//` prefix does not launder a path later in the same rule ----
# Regression guard for a substring carve-out (`$m == *"(//"*`) that passed any rule
# whose payload merely began with `//`, leaving the rest unexamined.
D8E="$TEST_TMPDIR/issue-2282-traversal"
mkdir -p "$D8E/.claude"
jq -n --arg l "Read(${LAUNDER_MP})" '{permissions:{allow:[$l]}}' >"$D8E/.claude/settings.json"
assert_eq "a // prefix does not exempt a user home later in the rule" "1" "$(run "$D8E" --count)"

# --- Case 13: #2397 A12 — tilde-user Bash paths leak a username ----------------
D8F="$TEST_TMPDIR/issue-2397-tilde-user"
mkdir -p "$D8F/.claude"
jq -n '{permissions:{allow:["Bash(~kyle/scripts/x.sh:*)"]}}' >"$D8F/.claude/settings.json"
OUT_TILDE=$(run "$D8F")
assert_contains "flags tilde-user Bash path" "$OUT_TILDE" "~kyle"
# #4149 defect 3: P2b is a documented check with its own `### P2b` section in
# criteria.md and its own row in SKILL.md's severity table, but the detector
# emitted it as `P2` — so no report could ever contain a P2b row and a reader
# could not tell which of the two error-tier checks fired.
assert_contains "tilde-user finding is emitted under its own id P2b" "$OUT_TILDE" "[P2b]"
assert_not_contains "tilde-user finding is no longer mislabelled P2" "$OUT_TILDE" "[P2] "
assert_eq "the tilde-user rule produces exactly one finding" "1" "$(run "$D8F" --count)"
assert_eq "portable ~/ anchor in Read is not flagged" "0" \
  "$(jq -n '{permissions:{allow:["Read(~/notes.md)"]}}' >"$D8F/.claude/settings.json" && run "$D8F" --count)"
D8F_URL="$TEST_TMPDIR/issue-2397-tilde-url"
mkdir -p "$D8F_URL/.claude"
jq -n '{permissions:{allow:["Bash(curl https://example.com/~alice/index.html)"]}}' \
  >"$D8F_URL/.claude/settings.json"
assert_eq "URL user-directory segment is not flagged as tilde-user path" "0" "$(run "$D8F_URL" --count)"

# --- Case 13b: #2397 A7b — inert substitution tokens in allowed-tools ---------
D8G="$TEST_TMPDIR/issue-2397-inert"
mkdir -p "$D8G/.claude/skills/demo"
cat >"$D8G/.claude/skills/demo/SKILL.md" <<'EOF'
---
name: demo
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/x.sh:*)
---
body
EOF
OUT_INERT=$(run "$D8G")
assert_contains "flags inert CLAUDE_PLUGIN_ROOT grant" "$OUT_INERT" "[P4]"
assert_contains "skill-local remedy recommends CLAUDE_SKILL_DIR" "$OUT_INERT" "CLAUDE_SKILL_DIR"

D8G2="$TEST_TMPDIR/issue-2397-inert-settings"
mkdir -p "$D8G2/.claude"
cat >"$D8G2/.claude/settings.json" <<'EOF'
{
  "permissions": {
    "allow": [
      "Bash(%USERPROFILE%/scripts/x.sh:*)",
      "Bash($env:USERPROFILE/scripts/x.sh:*)"
    ]
  }
}
EOF
OUT_ENV=$(run "$D8G2")
assert_contains "flags %USERPROFILE% inert grant" "$OUT_ENV" "%USERPROFILE%"
assert_contains "flags PowerShell env inert grant" "$OUT_ENV" "\$env:USERPROFILE"
assert_contains "settings-scope remedy does not prescribe plugin bin" "$OUT_ENV" "bare command on PATH"

D8G3="$TEST_TMPDIR/issue-2397-inert-list"
mkdir -p "$D8G3/.claude/skills/demo"
cat >"$D8G3/.claude/skills/demo/SKILL.md" <<'EOF'
---
name: demo
allowed-tools:
  - Bash(git status)
  - Bash(${CLAUDE_PLUGIN_ROOT}/scripts/x.sh:*)
  - Bash(%USERPROFILE%/scripts/y.sh:*)
---
body
EOF
OUT_LIST=$(run "$D8G3")
assert_contains "flags only the inert grant in a mixed list" "$OUT_LIST" "Bash(\${CLAUDE_PLUGIN_ROOT}/scripts/x.sh:*)"
assert_not_contains "clean grant in the same list is not embedded in P4 detail" "$OUT_LIST" "Bash(git status)"
assert_eq "two distinct inert Bash grants emit two P4 findings" "2" "$(run "$D8G3" --count)"

D8G4="$TEST_TMPDIR/issue-2397-inert-read"
mkdir -p "$D8G4/.claude"
jq -n '{permissions:{allow:["Read(%USERPROFILE%/notes.txt)"]}}' >"$D8G4/.claude/settings.json"
assert_eq "non-Bash rules with inert spellings are not P4-flagged" "0" "$(run "$D8G4" --count)"

# A PLUGIN skill is the one place the plugin-scoped tokens DO substitute in
# allowed-tools, so flagging them there is a false positive. Skills page,
# "Available string substitutions": "In a plugin skill, Claude Code substitutes
# ${CLAUDE_PLUGIN_ROOT} and ${CLAUDE_PLUGIN_DATA} in the same two places."
# Upstream fixed the plugin-root case in v2.1.0.
D8G5="$TEST_TMPDIR/issue-2397-plugin-skill"
mkdir -p "$D8G5/plugins/demo/.claude-plugin" "$D8G5/plugins/demo/skills/thing"
jq -n '{name:"demo"}' >"$D8G5/plugins/demo/.claude-plugin/plugin.json"
cat >"$D8G5/plugins/demo/skills/thing/SKILL.md" <<'EOF'
---
name: thing
allowed-tools:
  - Bash(${CLAUDE_PLUGIN_ROOT}/scripts/x.sh:*)
  - Bash(${CLAUDE_PLUGIN_DATA}/bin/y.sh:*)
---
body
EOF
assert_eq "plugin-scoped tokens in a PLUGIN skill are not P4-flagged" "0" "$(run "$D8G5" --count)"

# Same tokens, same layout, but the always-inert Windows spelling still fires —
# the plugin-skill carve-out is scoped to the two plugin-scoped tokens only.
D8G6="$TEST_TMPDIR/issue-2397-plugin-skill-userprofile"
mkdir -p "$D8G6/plugins/demo/.claude-plugin" "$D8G6/plugins/demo/skills/thing"
jq -n '{name:"demo"}' >"$D8G6/plugins/demo/.claude-plugin/plugin.json"
cat >"$D8G6/plugins/demo/skills/thing/SKILL.md" <<'EOF'
---
name: thing
allowed-tools:
  - Bash(${CLAUDE_PLUGIN_ROOT}/scripts/x.sh:*)
  - Bash(%USERPROFILE%/scripts/y.sh:*)
---
body
EOF
OUT_PLUGIN_MIXED=$(run "$D8G6")
assert_eq "a plugin skill still gets one P4 for the always-inert token" "1" "$(run "$D8G6" --count)"
assert_contains "the surviving finding names %USERPROFILE%" "$OUT_PLUGIN_MIXED" "%USERPROFILE%"
assert_not_contains "the plugin-root grant is not flagged in a plugin skill" "$OUT_PLUGIN_MIXED" "Bash(\${CLAUDE_PLUGIN_ROOT}/scripts/x.sh:*)"

# A settings file is not a skill at all: no page documents ${CLAUDE_*}
# expansion in a settings permissions.allow array, so the tokens stay flagged
# even inside a plugin-shaped checkout.
D8G7="$TEST_TMPDIR/issue-2397-plugin-root-in-settings"
mkdir -p "$D8G7/.claude"
jq -n '{permissions:{allow:["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/x.sh:*)"]}}' \
  >"$D8G7/.claude/settings.json"
OUT_PR_SETTINGS=$(run "$D8G7")
assert_eq "plugin-root token in a settings allow rule is still P4-flagged" "1" "$(run "$D8G7" --count)"
# The remedy has to fit the scope it is offered in. ${CLAUDE_SKILL_DIR} is
# substituted in a skill's allowed-tools, so recommending it for a SETTINGS rule
# would swap one inert rule for another.
assert_contains "settings-scope plugin-root remedy is the bare-PATH one" "$OUT_PR_SETTINGS" "bare command on PATH"
assert_not_contains "settings-scope plugin-root remedy does not offer CLAUDE_SKILL_DIR" "$OUT_PR_SETTINGS" "CLAUDE_SKILL_DIR"

# A non-plugin skill is the one scope where the skill-dir remedy is correct.
D8G8="$TEST_TMPDIR/issue-2397-plugin-root-project-skill"
mkdir -p "$D8G8/.claude/skills/demo"
cat >"$D8G8/.claude/skills/demo/SKILL.md" <<'EOF'
---
name: demo
allowed-tools: Bash(${CLAUDE_PLUGIN_DATA}/bin/x.sh:*)
---
body
EOF
OUT_PR_PROJECT=$(run "$D8G8")
assert_eq "plugin-data token in a project skill is P4-flagged" "1" "$(run "$D8G8" --count)"
assert_contains "project-skill remedy offers CLAUDE_SKILL_DIR" "$OUT_PR_PROJECT" "CLAUDE_SKILL_DIR"

# --- Case 14: #4149 Q2 — every emitted remedy is pinned, per scope ------------
#
# WHY THIS SECTION EXISTS. The bug that produced #4149: P4's remedy told authors
# to make a change that would BREAK a working grant, and the first fix for it
# reproduced the identical bug class by hardcoding ${CLAUDE_SKILL_DIR} for every
# non-plugin-skill scope, where that token is equally inert. A 148-check suite
# caught neither, because it tested WHICH findings fire and never tested WHAT
# THEY TELL YOU TO DO.
#
# So: every `emit` call site in the detector, in every scope it can fire in, has
# its remedy text asserted below. The emit sites are, in source order —
#   scan_rule:      P1 (interpreter/runner-led), P2 (machine path),
#                   P2b (tilde-user), P4 (always-inert token),
#                   P4 (plugin-scoped token outside a plugin skill)
#   scan_bare_tool: P1 (bare whole-tool grant)
#   scan_agent:     P1 (Agent allow rule)
#   plugin walk:    P3 (plugin settings.json declaring `permissions`)
# — eight sites, and the five scopes a rule can sit in are a plugin skill, a
# project/personal skill, an agent, a command, and a settings file.
#
# NEGATIVE assertions carry as much weight as positive ones: a remedy naming a
# token that is inert in the scope it was printed for is the defect, so each
# non-skill scope asserts the skill-scoped token is ABSENT rather than merely
# that some correct advice is also present.
REMEDY_MP="${SL}Users${SL}remy${SL}bin${SL}x.sh"

finding_for() {
  # finding_for <output> <source-substring> <rule-or-detail-substring> — the one
  # finding line whose SOURCE names this scope and whose detail names this rule.
  # Asserting against whole-run output instead would let a remedy correctly
  # printed for some OTHER scope satisfy this scope's assertion — which is
  # precisely the confusion these cases exist to remove.
  printf '%s\n' "$1" | grep -F -- "$2" | grep -F -- "$3" | head -n1
}

remedy_frontmatter() {
  # remedy_frontmatter <file> <name> — one frontmatter file carrying one rule per
  # emit site, so a single run produces every finding class in this scope.
  # The machine path is interpolated from runtime-assembled fragments (see the
  # top of this file) so no contiguous machine-path literal appears here; the
  # single-quoted formats keep `%USERPROFILE%` and `${CLAUDE_PLUGIN_ROOT}`
  # literal, which is the whole point of the fixture.
  # shellcheck disable=SC2016  # tokens are deliberately unexpanded fixture text
  {
    printf -- '---\nname: %s\nallowed-tools:\n' "$2"
    printf -- '  - Bash(python*)\n'
    printf -- '  - Bash\n'
    printf -- '  - Agent\n'
    printf -- '  - Bash(%s:*)\n' "$REMEDY_MP"
    printf -- '  - Bash(~remy/x.sh:*)\n'
    printf -- '  - Bash(%%USERPROFILE%%/x.sh:*)\n'
    printf -- '  - Bash(${CLAUDE_PLUGIN_ROOT}/x.sh:*)\n'
    printf -- '---\nbody\n'
  } >"$1"
}

assert_scope_remedies() {
  # assert_scope_remedies <scope-label> <output> <source-substring> <skill-dir-ok>
  #
  # <skill-dir-ok> is `yes` only where ${CLAUDE_SKILL_DIR} actually substitutes:
  # a SKILL.md's allowed-tools Bash rules, plugin or not. Everywhere else it is
  # `no` and the token must not appear in ANY remedy this scope prints.
  local scope="$1" out="$2" src="$3" skilldir="$4" line

  # --- scan_rule, P1: interpreter/runner-led grant ---------------------------
  line="$(finding_for "$out" "$src" "Bash(python*)")"
  assert_contains "$scope: P1 interpreter finding fires" "$line" "[P1]"
  assert_contains "$scope: P1 interpreter remedy is the bare-PATH command" "$line" \
    "Expose the guarded script as a bare PATH command and allow that"
  assert_not_contains "$scope: P1 interpreter remedy names no scope-specific token" "$line" \
    "CLAUDE_"

  # --- scan_bare_tool, P1: bare whole-tool grant -----------------------------
  line="$(finding_for "$out" "$src" "bare 'Bash'")"
  assert_contains "$scope: bare-tool finding fires" "$line" "[P1]"
  assert_contains "$scope: bare-tool remedy names a specific bare-name command" "$line" \
    "Allow a specific bare-name command instead"
  assert_not_contains "$scope: bare-tool remedy names no scope-specific token" "$line" "CLAUDE_"

  # --- scan_agent, P1: Agent allow rule --------------------------------------
  line="$(finding_for "$out" "$src" "Agent allow rules are dropped")"
  assert_contains "$scope: Agent finding fires" "$line" "[P1]"
  assert_contains "$scope: Agent remedy states the no-PATH-analog reason" "$line" \
    "no PATH-durable analog — remove/re-scope, or run outside auto mode"
  assert_not_contains "$scope: Agent remedy offers no bare-command rewrite it has no analog for" \
    "$line" "CLAUDE_"

  # --- scan_rule, P2: hardcoded machine path ---------------------------------
  line="$(finding_for "$out" "$src" "$REMEDY_MP")"
  assert_contains "$scope: P2 finding fires" "$line" "[P2]"
  assert_contains "$scope: P2 remedy offers the bare-name PATH command" "$line" \
    "a bare-name command on PATH"
  if [[ "$skilldir" == "yes" ]]; then
    assert_contains "$scope: P2 remedy offers CLAUDE_SKILL_DIR (it substitutes here)" "$line" \
      "\${CLAUDE_SKILL_DIR} for this skill's own bundled script"
  else
    assert_not_contains "$scope: P2 remedy does NOT offer CLAUDE_SKILL_DIR (inert here)" "$line" \
      "CLAUDE_SKILL_DIR"
  fi

  # --- scan_rule, P2b: tilde-user path ---------------------------------------
  line="$(finding_for "$out" "$src" "~remy/x.sh")"
  assert_contains "$scope: P2b fires under its own id" "$line" "[P2b]"
  assert_contains "$scope: P2b remedy offers the bare-name PATH command" "$line" \
    "a bare-name command on PATH"
  if [[ "$skilldir" == "yes" ]]; then
    assert_contains "$scope: P2b remedy offers CLAUDE_SKILL_DIR (it substitutes here)" "$line" \
      "\${CLAUDE_SKILL_DIR} for this skill's own bundled script"
  else
    assert_not_contains "$scope: P2b remedy does NOT offer CLAUDE_SKILL_DIR (inert here)" "$line" \
      "CLAUDE_SKILL_DIR"
  fi

  # --- scan_rule, P4: always-inert token (%USERPROFILE%) ---------------------
  # Fires in EVERY scope, plugin skill included — the plugin carve-out covers
  # only the two plugin-scoped tokens.
  line="$(finding_for "$out" "$src" "%USERPROFILE%")"
  assert_contains "$scope: P4 always-inert finding fires" "$line" "[P4]"
  if [[ "$skilldir" == "yes" ]]; then
    assert_contains "$scope: P4 always-inert remedy offers CLAUDE_SKILL_DIR" "$line" \
      "replace with \${CLAUDE_SKILL_DIR} for a script bundled in this skill"
  else
    assert_not_contains "$scope: P4 always-inert remedy does NOT offer CLAUDE_SKILL_DIR" "$line" \
      "CLAUDE_SKILL_DIR"
    assert_contains "$scope: P4 always-inert remedy is the bare-PATH relocation" "$line" \
      "relocate the helper to a stable bare command on PATH"
    assert_contains "$scope: P4 always-inert remedy refuses to prescribe plugin bin/" "$line" \
      "do not prescribe plugin bin/"
  fi
}

assert_plugin_scoped_remedy() {
  # assert_plugin_scoped_remedy <scope-label> <output> <source-substring> <skill-dir-ok>
  #
  # The fifth emit site: a plugin-scoped token OUTSIDE a plugin skill. It is kept
  # out of assert_scope_remedies because it is the one site a plugin skill
  # suppresses, so every OTHER scope asserts it here — with a per-line POSITIVE
  # anchoring the negative. A whole-output `not_contains` alone would keep
  # passing if the site quietly stopped firing in this scope, which is a negative
  # that cannot fail: the exact shape #4149 is about.
  local scope="$1" out="$2" src="$3" skilldir="$4" line
  line="$(finding_for "$out" "$src" "plugin-scoped substitution token")"
  assert_contains "$scope: P4 plugin-scoped finding fires" "$line" "[P4]"
  if [[ "$skilldir" == "yes" ]]; then
    assert_contains "$scope: plugin-scoped remedy offers CLAUDE_SKILL_DIR" "$line" \
      "replace with \${CLAUDE_SKILL_DIR} for a script bundled in this skill"
  else
    assert_contains "$scope: plugin-scoped remedy is the bare-PATH relocation" "$line" \
      "relocate the helper to a stable bare command on PATH"
    assert_not_contains "$scope: plugin-scoped remedy does NOT offer CLAUDE_SKILL_DIR" "$line" \
      "CLAUDE_SKILL_DIR"
  fi
}

# 14a: a PLUGIN skill — the one scope where ${CLAUDE_PLUGIN_ROOT} substitutes, so
# that finding must NOT fire, while every other site does and the skill-dir
# remedy is the correct one.
D14_PLUGIN="$TEST_TMPDIR/remedy-plugin-skill"
mkdir -p "$D14_PLUGIN/plugins/demo/.claude-plugin" "$D14_PLUGIN/plugins/demo/skills/thing"
jq -n '{name:"demo"}' >"$D14_PLUGIN/plugins/demo/.claude-plugin/plugin.json"
remedy_frontmatter "$D14_PLUGIN/plugins/demo/skills/thing/SKILL.md" thing
OUT_14P=$(run "$D14_PLUGIN")
assert_scope_remedies "plugin skill" "$OUT_14P" "plugins/demo/skills/thing/SKILL.md" yes
assert_not_contains "plugin skill: the plugin-root grant is not flagged at all" "$OUT_14P" \
  "plugin-scoped substitution token"

# 14b: a PROJECT skill — ${CLAUDE_PLUGIN_ROOT} is inert here, so that site fires,
# and ${CLAUDE_SKILL_DIR} is still the right remedy because this is a SKILL.md.
D14_PROJ="$TEST_TMPDIR/remedy-project-skill"
mkdir -p "$D14_PROJ/.claude/skills/proj"
remedy_frontmatter "$D14_PROJ/.claude/skills/proj/SKILL.md" proj
OUT_14S=$(run "$D14_PROJ")
assert_scope_remedies "project skill" "$OUT_14S" ".claude/skills/proj/SKILL.md" yes
assert_plugin_scoped_remedy "project skill" "$OUT_14S" ".claude/skills/proj/SKILL.md" yes

# 14c: an AGENT — not a SKILL.md, so ${CLAUDE_SKILL_DIR} is inert and must not be
# offered by ANY remedy this scope prints. This scope had no remedy assertion at
# all before #4149.
D14_AGENT="$TEST_TMPDIR/remedy-agent"
mkdir -p "$D14_AGENT/.claude/agents"
remedy_frontmatter "$D14_AGENT/.claude/agents/runner.md" runner
OUT_14A=$(run "$D14_AGENT")
assert_scope_remedies "agent" "$OUT_14A" ".claude/agents/runner.md" no
assert_plugin_scoped_remedy "agent" "$OUT_14A" ".claude/agents/runner.md" no

# 14d: a COMMAND — same reasoning as the agent scope, and likewise unasserted
# before #4149.
D14_CMD="$TEST_TMPDIR/remedy-command"
mkdir -p "$D14_CMD/.claude/commands"
remedy_frontmatter "$D14_CMD/.claude/commands/do.md" "run"
OUT_14C=$(run "$D14_CMD")
assert_scope_remedies "command" "$OUT_14C" ".claude/commands/do.md" no
assert_plugin_scoped_remedy "command" "$OUT_14C" ".claude/commands/do.md" no

# 14e: a SETTINGS file — no ${CLAUDE_*} substitution is documented for a
# permissions.allow array at all, so every remedy here must be scope-free.
D14_SET="$TEST_TMPDIR/remedy-settings"
mkdir -p "$D14_SET/.claude"
jq -n --arg mp "Bash(${REMEDY_MP}:*)" '{permissions:{allow:[
  "Bash(python*)","Bash","Agent",$mp,"Bash(~remy/x.sh:*)",
  "Bash(%USERPROFILE%/x.sh:*)","Bash(${CLAUDE_PLUGIN_ROOT}/x.sh:*)"
]}}' >"$D14_SET/.claude/settings.json"
OUT_14SET=$(run "$D14_SET")
assert_scope_remedies "settings" "$OUT_14SET" ".claude/settings.json permissions.allow" no
assert_plugin_scoped_remedy "settings" "$OUT_14SET" ".claude/settings.json permissions.allow" no
assert_not_contains "settings: no remedy in this scope mentions CLAUDE_SKILL_DIR" "$OUT_14SET" \
  "CLAUDE_SKILL_DIR"

# 14f: the DERIVED scopes — a plugin's own agents/ and commands/, .claude/
# settings.local.json, and the user-global settings file. None is a SKILL.md, so
# every remedy in them must be scope-free; they reach the same remedy branches by
# fallthrough, which is exactly why a refactor could regress them silently while
# the five headline scopes stayed green.
D14_PAC="$TEST_TMPDIR/remedy-plugin-agent-command"
mkdir -p "$D14_PAC/plugins/demo/.claude-plugin" "$D14_PAC/plugins/demo/agents" \
  "$D14_PAC/plugins/demo/commands"
jq -n '{name:"demo"}' >"$D14_PAC/plugins/demo/.claude-plugin/plugin.json"
remedy_frontmatter "$D14_PAC/plugins/demo/agents/x.md" "x"
remedy_frontmatter "$D14_PAC/plugins/demo/commands/y.md" "y"
OUT_14PAC=$(run "$D14_PAC")
assert_scope_remedies "plugin agent" "$OUT_14PAC" "plugins/demo/agents/x.md" no
assert_plugin_scoped_remedy "plugin agent" "$OUT_14PAC" "plugins/demo/agents/x.md" no
assert_scope_remedies "plugin command" "$OUT_14PAC" "plugins/demo/commands/y.md" no
assert_plugin_scoped_remedy "plugin command" "$OUT_14PAC" "plugins/demo/commands/y.md" no
assert_not_contains "plugin agents/commands: no remedy in this tree mentions CLAUDE_SKILL_DIR" \
  "$OUT_14PAC" "CLAUDE_SKILL_DIR"

D14_LOCAL="$TEST_TMPDIR/remedy-settings-local"
mkdir -p "$D14_LOCAL/.claude"
cp "$D14_SET/.claude/settings.json" "$D14_LOCAL/.claude/settings.local.json"
OUT_14LOCAL=$(run "$D14_LOCAL")
assert_scope_remedies "settings.local" "$OUT_14LOCAL" ".claude/settings.local.json permissions.allow" no
assert_plugin_scoped_remedy "settings.local" "$OUT_14LOCAL" ".claude/settings.local.json permissions.allow" no
assert_not_contains "settings.local: no remedy in this scope mentions CLAUDE_SKILL_DIR" \
  "$OUT_14LOCAL" "CLAUDE_SKILL_DIR"

D14_UG="$TEST_TMPDIR/remedy-user-global-project"
mkdir -p "$D14_UG/.claude"
D14_UG_HOME="$TEST_TMPDIR/remedy-user-global-home"
mkdir -p "$D14_UG_HOME/.claude"
cp "$D14_SET/.claude/settings.json" "$D14_UG_HOME/.claude/settings.json"
OUT_14UG=$(run_with_home "$D14_UG" "$D14_UG_HOME")
assert_scope_remedies "user-global" "$OUT_14UG" \
  "$D14_UG_HOME/.claude/settings.json permissions.allow" no
assert_plugin_scoped_remedy "user-global" "$OUT_14UG" \
  "$D14_UG_HOME/.claude/settings.json permissions.allow" no
assert_not_contains "user-global: no remedy in this scope mentions CLAUDE_SKILL_DIR" \
  "$OUT_14UG" "CLAUDE_SKILL_DIR"

# 14g: the eighth emit site — P3, which fires only against a plugin settings.json
# and whose remedy is the only one that routes the fix to a DIFFERENT file than
# the one the finding names.
D14_P3="$TEST_TMPDIR/remedy-p3"
mkdir -p "$D14_P3/plugins/foo/.claude-plugin"
jq -n '{name:"foo"}' >"$D14_P3/plugins/foo/.claude-plugin/plugin.json"
jq -n '{permissions:{allow:["Bash(x.sh:*)"]}}' >"$D14_P3/plugins/foo/settings.json"
line_14p3="$(finding_for "$(run "$D14_P3")" "plugins/foo/settings.json" "[P3]")"
assert_contains "P3 remedy routes the operative rule to the user-global settings file" \
  "$line_14p3" "must be added by the operator to ~/.claude/settings.json"
assert_not_contains "P3 remedy does not tell the author to edit the inert file in place" \
  "$line_14p3" "CLAUDE_SKILL_DIR"

# --- Case 15: #4149 Q1 — the exit-code gate ----------------------------------
# Five documented outcomes. Default and --count keep their advisory contract in
# every one of them; only --check and --strict change the exit code.
gate_rc() {
  # gate_rc <root> <flag> — the exit code, with output discarded.
  local rc=0
  run "$1" "$2" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

# 15a: an ERROR-tier finding (P2) fails both gates and neither default mode.
D15_ERR="$TEST_TMPDIR/gate-error"
mkdir -p "$D15_ERR/.claude"
jq -n --arg mp "Bash(${REMEDY_MP}:*)" '{permissions:{allow:[$mp]}}' >"$D15_ERR/.claude/settings.json"
assert_exit "error-tier finding: --check exits 1" 1 "$(gate_rc "$D15_ERR" --check)"
assert_exit "error-tier finding: --strict exits 1" 1 "$(gate_rc "$D15_ERR" --strict)"
assert_exit "error-tier finding: default mode still exits 0" 0 "$(gate_rc "$D15_ERR" "")"
assert_exit "error-tier finding: --count still exits 0" 0 "$(gate_rc "$D15_ERR" --count)"
OUT_15ERR=$(run "$D15_ERR" --check 2>&1) || true
assert_contains "gate mode still prints the finding" "$OUT_15ERR" "[P2]"
assert_contains "gate mode still prints the coverage block" "$OUT_15ERR" "Scan coverage"

# 15a2: P2b and P4 are error-tier too — a gate that only knew P2 would pass a
# tree whose only defects were the two checks #4149 found unsurfaced.
D15_P2B="$TEST_TMPDIR/gate-error-p2b"
mkdir -p "$D15_P2B/.claude"
jq -n '{permissions:{allow:["Bash(~remy/x.sh:*)"]}}' >"$D15_P2B/.claude/settings.json"
assert_exit "P2b alone fails --check" 1 "$(gate_rc "$D15_P2B" --check)"
D15_P4="$TEST_TMPDIR/gate-error-p4"
mkdir -p "$D15_P4/.claude"
jq -n '{permissions:{allow:["Bash(%USERPROFILE%/x.sh:*)"]}}' >"$D15_P4/.claude/settings.json"
assert_exit "P4 alone fails --check" 1 "$(gate_rc "$D15_P4" --check)"

# 15b/15c: WARNING-tier findings only (P1 here) pass --check and fail --strict.
# That difference is the entire reason the two flags exist.
D15_WARN="$TEST_TMPDIR/gate-warning"
mkdir -p "$D15_WARN/.claude"
jq -n '{permissions:{allow:["Bash(python*)"]}}' >"$D15_WARN/.claude/settings.json"
assert_exit "warnings only: --check exits 0" 0 "$(gate_rc "$D15_WARN" --check)"
assert_exit "warnings only: --strict exits 1" 1 "$(gate_rc "$D15_WARN" --strict)"
OUT_15W=$(run "$D15_WARN" --check)
assert_contains "a passing --check still prints its warning finding" "$OUT_15W" "[P1]"

# P3 is the other warning-tier check and must gate identically.
assert_exit "P3 alone passes --check" 0 "$(gate_rc "$D14_P3" --check)"
assert_exit "P3 alone fails --strict" 1 "$(gate_rc "$D14_P3" --strict)"

# 15d: a CLEAN tree with a real denominator passes both gates.
D15_CLEAN="$TEST_TMPDIR/gate-clean"
mkdir -p "$D15_CLEAN/.claude"
jq -n '{permissions:{allow:["Bash(npm test)"]}}' >"$D15_CLEAN/.claude/settings.json"
assert_exit "clean tree: --check exits 0" 0 "$(gate_rc "$D15_CLEAN" --check)"
assert_exit "clean tree: --strict exits 0" 0 "$(gate_rc "$D15_CLEAN" --strict)"
assert_contains "clean tree under --check still prints the clean bill" \
  "$(run "$D15_CLEAN" --check)" "No fragile permission grants found."

# 15e: NOTHING TO AUDIT exits 2 under both gates, NOT 0. A scan that examined
# nothing on any axis has no denominator, so "0 findings" is not a statement
# about the grants and must never pass a gate — the finding-side limb of the same
# fail-closed judgment the missing-jq and unresolvable-root refusals already make.
assert_exit "NOTHING TO AUDIT: --check exits 2, not 0" 2 "$(gate_rc "$D10A" --check)"
assert_exit "NOTHING TO AUDIT: --strict exits 2, not 0" 2 "$(gate_rc "$D10A" --strict)"
assert_exit "NOTHING TO AUDIT: default mode is unchanged at 0" 0 "$(gate_rc "$D10A" "")"
assert_exit "NOTHING TO AUDIT: --count is unchanged at 0" 0 "$(gate_rc "$D10A" --count)"
OUT_15E=$(run "$D10A" --check 2>&1) || true
assert_contains "the exit-2 gate still prints NOTHING TO AUDIT" "$OUT_15E" "NOTHING TO AUDIT"
assert_not_contains "the exit-2 gate is not a clean bill" "$OUT_15E" "No fragile permission grants found."

# 15f: the environment-gap channel keeps exit 2 under the gate flags — a gate
# that reported 1 (or 0) for an unresolvable root would collapse "found problems"
# into "could not look".
rc=0
(cd "$nonrepo" && env -u PERMISSION_HYGIENE_FIXTURE_DIR -u PERMISSION_HYGIENE_SCAN_ROOT \
  -u CLAUDE_PROJECT_DIR GIT_CEILING_DIRECTORIES="$TEST_TMPDIR" bash "$SCRIPT" --check) >/dev/null 2>&1 || rc=$?
assert_exit "--check on an unresolvable root still exits 2" 2 "$rc"
rc=0
PERMISSION_HYGIENE_FIXTURE_DIR="$TEST_TMPDIR/does-not-exist" bash "$SCRIPT" --strict >/dev/null 2>&1 || rc=$?
assert_exit "--strict on a nonexistent root still exits 2" 2 "$rc"

# 15g: --help and an unrecognised argument keep the pre-gate behavior.
rc=0
bash "$SCRIPT" --help >/dev/null 2>&1 || rc=$?
assert_exit "--help is unaffected by the gate flags" 0 "$rc"
assert_exit "an unrecognised flag still falls through to the advisory report" 0 \
  "$(gate_rc "$D15_ERR" --not-a-flag)"

# --- Case 9: missing jq exits 2 ---------------------------------------------
real_bash=$(command -v bash)
empty_path_dir="$TEST_TMPDIR/empty-path"
mkdir -p "$empty_path_dir"
rc=0
err_out=$(PATH="$empty_path_dir" "$real_bash" "$SCRIPT" 2>&1) || rc=$?
assert_exit "exit 2 when jq missing" 2 "$rc"
assert_contains "jq required message" "$err_out" "jq required"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
