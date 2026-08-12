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

# --- Case 6b: vendored (non-loadable) SKILL.md excluded ----------------------
# A SKILL.md under a vendor/ path segment is a vendored upstream reference, not
# a loadable skill, so its allowed-tools never take effect and must not be
# flagged — while a real sibling skill with the same grant still is. Covers both
# a direct child (vendor/SKILL.md) and a nested one (vendor/<tool>/SKILL.md).
# Fixture root deliberately NOT named "vendor" — the exclusion matches a
# /vendor/ path segment anywhere, so a root literally named vendor would exclude
# every file beneath it and mask the real-vs-vendored distinction under test.
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
err_out=$(env -u CLAUDE_CONFIG_DIR -u HOME PERMISSION_HYGIENE_FIXTURE_DIR="$D8C" bash "$SCRIPT" 2>&1 >/dev/null)
assert_contains "unresolvable user scope is announced" "$err_out" "user-global scope not scanned"

# --- Case 9b: unresolvable scan root refuses instead of sweeping -------------
# The root ladder is $PERMISSION_HYGIENE_FIXTURE_DIR -> git toplevel ->
# $CLAUDE_PROJECT_DIR, with NO fallback to the cwd. Run from a non-repo directory
# with every rung unset: the scan must refuse (exit 2, the environment-gap channel)
# rather than walk whatever the cwd happens to be and report a clean bill.
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
# "No fragile permission grants found." used to print identically whether the run
# parsed forty grants and found them healthy or parsed none at all. These cases
# pin that the two are now different strings, and that the coverage block reports
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

# 10bc: the completeness invariant. Every enumerated frontmatter candidate must
# land in exactly one bucket, and the script reconciles the buckets against the
# enumeration itself rather than trusting each `continue` site.
D10BC="$TEST_TMPDIR/reconcile"
mkdir -p "$D10BC/skills/a" "$D10BC/skills/b" "$D10BC/skills/c/vendor"
printf -- '---\nname: a\nallowed-tools: Bash(npm test)\n---\nbody\n' >"$D10BC/skills/a/SKILL.md"
printf -- '---\nname: b\n---\nbody\n' >"$D10BC/skills/b/SKILL.md"
printf -- '---\nname: v\nallowed-tools: Bash(npm:*)\n---\nbody\n' >"$D10BC/skills/c/vendor/SKILL.md"
OUT=$(run "$D10BC")
assert_contains "coverage reconciles candidates against buckets" "$OUT" "reconciled: 3 candidate(s)"
assert_contains "reconciliation names each bucket" "$OUT" \
  "1 vendor-excluded + 0 unreadable + 1 without an allowed-tools block + 1 parsed"
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
mkdir -p "$D10BE"
printf -- '---\nname: u\nallowed-tools: Bash(python*)\n---\nbody\n' >"$D10BE/SKILL.md"
chmod 000 "$D10BE/SKILL.md" 2>/dev/null
if [[ -r "$D10BE/SKILL.md" ]]; then
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
    "0 vendor-excluded + 1 unreadable + 0 without an allowed-tools block + 0 parsed"
  assert_not_contains "an unreadable-only root is not a plain clean bill" "$OUT" \
    "No fragile permission grants found."
  assert_contains "an unreadable-only root names the blocked inputs" "$OUT" "COULD NOT BE READ"
fi
chmod u+rw "$D10BE/SKILL.md" 2>/dev/null

# 10c: a settings file that is present but not valid JSON was skipped in silence,
# so its rules were never read and the run still printed a clean bill. The skip
# is now named — an unparsable rules file is exactly where a fragile grant would
# sit unexamined.
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

# 10e: the vendor/ exclusion reports how many files it removed. An exclusion
# nothing counts is indistinguishable from a tree that had nothing in it.
OUT=$(run "$D6B")
assert_contains "vendor exclusion discloses its count" "$OUT" "2 excluded under a vendor/ path segment"
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

# --- Case 8b: #2282 — full-rule reporting, `//` is NOT exempt, P1 pinned npm view
#
# `//` is the ABSOLUTE anchor, not a portable one. permissions.md's own table row is
# `//path` = "Absolute path from filesystem root", with `Read(//Users/<name>/secrets/**)`
# resolving to `/Users/<name>/secrets/**`, and the same page says "Use
# `//Users/<name>/file` for absolute paths." The docs' literal example names a concrete
# user home and leaks `alice`. An earlier revision of this suite asserted the opposite,
# which would have taught an `error`-tier username-leak check to ignore the canonical
# spelling of the leak.
D8B="$TEST_TMPDIR/issue-2282"
mkdir -p "$D8B/.claude"
jq -n --arg posix "Bash(${POSIX_MP}:*)" --arg abs "Read(${ABS_MP})" \
  '{permissions:{allow:[$abs, "Bash(npm view ctx7 version*)", $posix]}}' >"$D8B/.claude/settings.json"
OUT_2282=$(run "$D8B")
assert_contains "// absolute anchor IS flagged — it names a concrete user home" "$OUT_2282" "Read(${ABS_MP})"
assert_contains "P2 reports the full offending Bash rule" "$OUT_2282" "Bash(${POSIX_MP}:*)"
assert_not_contains "fully-pinned npm view rule is not flagged as P1" "$OUT_2282" "npm view ctx7 version"
assert_eq "both machine-path rules flagged, npm view not" "2" "$(run "$D8B" --count)"

# --- Case 8c: the genuinely portable anchors stay exempt ----------------------
# The distinction the fix turns on: `~/` and `${CLAUDE_PROJECT_DIR}/` supply the
# user/project segment at resolution time; `//` does not.
D8C="$TEST_TMPDIR/issue-2282-portable"
mkdir -p "$D8C/.claude"
jq -n '{permissions:{allow:["Read(~/Documents/*.pdf)","Bash(${CLAUDE_PROJECT_DIR}/scripts/x.sh:*)"]}}' >"$D8C/.claude/settings.json"
assert_eq "portable anchors produce no P2 finding" "0" "$(run "$D8C" --count)"

# --- Case 8d: P2 reach is the open tool grammar, not five hardcoded names ------
# A hardcoded machine path leaks a username whatever tool the rule names. An
# enumerated (Read|Edit|Write|Bash|PowerShell) list silently stopped flagging these;
# `Agent` in particular is indefensible, since this script has a dedicated
# scan_agent(). Each rule below must produce its own P2 finding.
D8D="$TEST_TMPDIR/issue-2282-tools"
mkdir -p "$D8D/.claude"
jq -n --arg wf "WebFetch(${WF_MP})" --arg gl "Glob(${GLOB_MP})"   --arg nb "NotebookEdit(${NB_MP})" --arg mc "mcp__srv__tool(${MCP_MP})"   '{permissions:{allow:[$wf,$gl,$nb,$mc]}}' >"$D8D/.claude/settings.json"
OUT_TOOLS=$(run "$D8D")
assert_contains "P2 sees WebFetch rules" "$OUT_TOOLS" "WebFetch(${WF_MP})"
assert_contains "P2 sees Glob rules" "$OUT_TOOLS" "Glob(${GLOB_MP})"
assert_contains "P2 sees NotebookEdit rules" "$OUT_TOOLS" "NotebookEdit(${NB_MP})"
assert_contains "P2 sees MCP tool rules" "$OUT_TOOLS" "mcp__srv__tool(${MCP_MP})"

# --- Case 8e: a `//` prefix does not launder a path later in the same rule -----
# Regression guard for a substring carve-out (`$m == *"(//"*`) that passed any rule
# whose payload merely began with `//`, leaving the rest unexamined.
D8E="$TEST_TMPDIR/issue-2282-traversal"
mkdir -p "$D8E/.claude"
jq -n --arg l "Read(${LAUNDER_MP})" '{permissions:{allow:[$l]}}' >"$D8E/.claude/settings.json"
assert_eq "a // prefix does not exempt a user home later in the rule" "1" "$(run "$D8E" --count)"

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
