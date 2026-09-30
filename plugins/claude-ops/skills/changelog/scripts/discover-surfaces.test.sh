#!/usr/bin/env bash
# Regression tests for discover-surfaces.sh.
#
# Coverage:
#   - this repository is a marketplace: the shape line, the plugins and plugin
#     skills lines, the vendor-excluded line, exit 0
#   - the consumer fixture is a consumer: each consumer class line, no marketplace
#     class line, exit 0
#   - the classes the fixture cannot carry (gitignored or repo-root files) appear
#     when a temp copy of the fixture adds them
#   - an empty directory is a consumer with no class lines and still exits 0 (the
#     script once aborted under set -e on a zero count)
#   - a missing root and an unknown argument exit 2 with a message
#
# Uses the fixture under ../evals/fixtures/consumer-repo and needs no git, network
# or installed CLI.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/discover-surfaces.sh"
FIXTURE="$SCRIPT_DIR/../evals/fixtures/consumer-repo"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
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

# run ROOT-OR-ARGS...: sets OUT, ERR and RC.
run() {
  OUT="$(bash "$SCRIPT" "$@" 2>"$TMP/err")"
  RC=$?
  ERR="$(<"$TMP/err")"
}

# --- Case 1: this repository is a marketplace ----------------------------------------
run "$REPO_ROOT"
assert_eq "marketplace: exits 0" 0 "$RC"
assert_contains "marketplace: shape line" "$OUT" "repo-shape: marketplace"
assert_contains "marketplace: plugins line" "$OUT" "plugins/*/"
assert_contains "marketplace: plugin skills line" "$OUT" "plugin skills (excl. vendor)"
assert_contains "marketplace: plugin skills glob" "$OUT" "plugins/*/skills/*/SKILL.md"
assert_contains "marketplace: vendor trees reported as excluded" "$OUT" "excluded: "
assert_contains "marketplace: exclusion names the vendor glob" "$OUT" "*/skills/*/vendor"
assert_contains "marketplace: official-docs index found" "$OUT" "docs/official-docs.md"
assert_contains "marketplace: native-surfaces store found" "$OUT" "docs/native-surfaces/records.json"

# --- Case 2: the consumer fixture ----------------------------------------------------
run "$FIXTURE"
assert_eq "consumer: exits 0" 0 "$RC"
assert_contains "consumer: shape line" "$OUT" "repo-shape: consumer"
assert_contains "consumer: CLAUDE.md" "$OUT" "project instructions (CLAUDE.md)"
assert_contains "consumer: rules" "$OUT" ".claude/rules/**/*.md"
assert_contains "consumer: settings" "$OUT" ".claude/settings.json"
assert_contains "consumer: mcp config" "$OUT" ".mcp.json"
assert_contains "consumer: hooks" "$OUT" ".claude/hooks/**"
assert_contains "consumer: skills" "$OUT" ".claude/skills/*/SKILL.md"
assert_contains "consumer: agents" "$OUT" ".claude/agents/*.md"
assert_not_contains "consumer: no plugins line" "$OUT" "plugins/*/"
assert_not_contains "consumer: no AGENTS.md line when absent" "$OUT" "AGENTS.md"
assert_not_contains "consumer: no vendor line when none exist" "$OUT" "excluded:"

# --- Case 3: classes the fixture cannot carry ----------------------------------------
COPY="$TMP/copy"
cp -R "$FIXTURE" "$COPY"
: >"$COPY/AGENTS.md"
: >"$COPY/CLAUDE.local.md"
: >"$COPY/README.md"
mkdir -p "$COPY/docs"
: >"$COPY/docs/guide.md"
: >"$COPY/.claude/settings.local.json"
mkdir -p "$COPY/.claude/skills/other/vendor"
run "$COPY"
assert_eq "consumer copy: exits 0" 0 "$RC"
assert_contains "consumer copy: AGENTS.md" "$OUT" "project instructions (AGENTS.md)"
assert_contains "consumer copy: CLAUDE.local.md" "$OUT" "CLAUDE.local.md"
assert_contains "consumer copy: local settings" "$OUT" ".claude/settings.local.json"
assert_contains "consumer copy: readme" "$OUT" "readme (README.md)"
assert_contains "consumer copy: documentation" "$OUT" "docs/**/*.md"
assert_contains "consumer copy: a skill-less directory is not counted" "$OUT" "project skills                            1  .claude/skills/*/SKILL.md"
assert_contains "consumer copy: counts the vendor tree" "$OUT" "excluded: 1 vendor tree(s)"

# --- Case 4: empty directory (the set -e regression) -----------------------------------
mkdir -p "$TMP/empty"
run "$TMP/empty"
assert_eq "empty: exits 0" 0 "$RC"
assert_eq "empty: prints only the consumer shape" "repo-shape: consumer" "$OUT"

# --- Case 5: marketplace shape needs both markers ---------------------------------------
mkdir -p "$TMP/half/plugins"
run "$TMP/half"
assert_contains "plugins/ without marketplace.json is a consumer" "$OUT" "repo-shape: consumer"

# --- Case 5b: a standalone plugin has root-level plugin classes ---------------------------
PLUG="$TMP/plug"
mkdir -p "$PLUG/.claude-plugin" "$PLUG/skills/a" "$PLUG/skills/empty" "$PLUG/agents"
: >"$PLUG/.claude-plugin/plugin.json"
: >"$PLUG/skills/a/SKILL.md"
: >"$PLUG/agents/x.md"
run "$PLUG"
assert_contains "plugin: shape line" "$OUT" "repo-shape: plugin"
assert_contains "plugin: skills counted by SKILL.md" "$OUT" "plugin skills (excl. vendor)              1  skills/*/SKILL.md"
assert_contains "plugin: agents" "$OUT" "agents/*.md"

# --- Case 5c: eval fixtures under a plugin skill are not plugin surfaces -------------------
MKT="$TMP/mkt"
FX="$MKT/plugins/p/skills/s/evals/fixtures/f/.claude"
mkdir -p "$MKT/.claude-plugin" "$MKT/plugins/p/skills/s" "$MKT/plugins/p/agents" "$FX/skills/d" "$FX/agents"
: >"$MKT/.claude-plugin/marketplace.json"
: >"$MKT/plugins/p/skills/s/SKILL.md"
: >"$MKT/plugins/p/agents/a.md"
: >"$FX/skills/d/SKILL.md"
: >"$FX/agents/d.md"
: >"$FX/skills/d/spoke.md"
mkdir -p "$MKT/plugins/evals/skills/e"
: >"$MKT/plugins/evals/skills/e/SKILL.md"
: >"$MKT/plugins/evals/skills/e/spoke.md"
run "$MKT"
assert_contains "fixtures: plugin skills ignore nested SKILL.md and count a plugin named evals" "$OUT" "plugin skills (excl. vendor)              2  "
assert_contains "fixtures: spokes skip nested evals but keep a plugin named evals" "$OUT" "plugin skill spokes (excl. vendor)        1  "
assert_contains "fixtures: plugin agents ignore nested agents" "$OUT" "plugin agents                             1  "

# --- Case 6: argument errors -------------------------------------------------------------
run "$TMP/does-not-exist"
assert_eq "args: missing root exits 2" 2 "$RC"
assert_contains "args: missing root named" "$ERR" "no such directory: $TMP/does-not-exist"
run --bogus
assert_eq "args: unknown argument exits 2" 2 "$RC"
assert_contains "args: unknown argument named" "$ERR" "unknown argument: --bogus"
run "$TMP/empty" extra
assert_eq "args: a second argument exits 2" 2 "$RC"

# --- Summary -------------------------------------------------------------------------------
if ((FAILED > 0)); then
  printf '\n%d of %d assertions failed\n' "$FAILED" "$CASE_NUM" >&2
  exit 1
fi
printf '\nAll %d assertions passed\n' "$CASE_NUM"
