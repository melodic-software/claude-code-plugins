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

run() { PERMISSION_HYGIENE_FIXTURE_DIR="$1" bash "$SCRIPT" "${2:-}"; }

# Runtime-assembled machine paths (no contiguous path literal in source).
SL='/'
# shellcheck disable=SC1003  # BS is a literal single backslash, not a quote escape
BS='\'
POSIX_MP="${SL}c${SL}Users${SL}alice${SL}.agents${SL}skills${SL}merge${SL}x.sh"
WIN_MP="C:${BS}Users${BS}bob${BS}x.sh"

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
  "Bash(npm run *)","Bash(*.py:*)","Bash","Agent","Agent(code-reviewer)"
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
  "Bash(echo Agent)","Bash(find *Agent*)"
]}}' >"$D3/.claude/settings.json"
OUT=$(run "$D3")
assert_contains "clean narrow ruleset reports none" "$OUT" "No fragile permission grants"
assert_not_contains "word 'Agent' inside a Bash payload is not an Agent finding" "$OUT" "Agent allow rules are dropped"
assert_eq "narrow ruleset count == 0" "0" "$(run "$D3" --count)"

# --- Case 4: P2 hardcoded machine paths -------------------------------------
D4="$TEST_TMPDIR/p2"
mkdir -p "$D4/.claude"
jq -n --arg posix "Bash(${POSIX_MP}:*)" --arg win "Bash(${WIN_MP}:*)" \
  '{permissions:{allow:[$posix,$win]}}' >"$D4/.claude/settings.json"
OUT=$(run "$D4")
assert_contains "flags POSIX-normalized machine path" "$OUT" "[P2]"
assert_contains "P2 detail mentions literal matching" "$OUT" "no ~/\$HOME"
assert_eq "two machine-path findings" "2" "$(run "$D4" --count)"

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
