#!/usr/bin/env bash
# test-scope: plugins/harness-config/skills/audit-automation-gaps/context/enforcement-ladder.md plugins/harness-config/lib/yaml-subset.awk plugins/harness-config/lib/resolve-convention-home.sh
# shellcheck disable=SC2016
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="$SCRIPT_DIR/rule-inventory.sh"
LADDER="$SCRIPT_DIR/../context/enforcement-ladder.md"

FAILED=0
CASES=0
pass() { CASES=$((CASES + 1)); printf 'PASS: %s\n' "$1"; }
fail() { CASES=$((CASES + 1)); FAILED=$((FAILED + 1)); printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2; }
assert_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi; }
assert_line() { if grep -Fxq -- "$3" <<<"$2"; then pass "$1"; else fail "$1" "no line [$3] in:
$2"; fi; }
assert_no() { if grep -Fq -- "$3" <<<"$2"; then fail "$1" "unexpected [$3] in:
$2"; else pass "$1"; fi; }
assert_has() { if grep -Fq -- "$3" <<<"$2"; then pass "$1"; else fail "$1" "no [$3] in:
$2"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

new_repo() {
  mkdir -p "$1"
  git -C "$1" init -q
}
commit_all() {
  git -C "$1" add -A
  git -C "$1" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm fixture
}

A="$TMP/one-per-tier"
new_repo "$A"
mkdir -p "$A/docs/conventions" "$A/.claude/skills/control-app"
cat >"$A/docs/conventions/harness-config.yaml" <<'EOF'
rule_inventory:
  declared:
    - rule: "an order is draft or submitted, one status field"
      enforcer: "src/order.ts Order type"
      rung: make-impossible
EOF
cat >"$A/.claude/settings.json" <<'EOF'
{"permissions": {"deny": ["Read(./.env)"]}}
EOF
printf -- '---\nname: control-app\n---\n\nDrive the app.\n' >"$A/.claude/skills/control-app/SKILL.md"
printf -- '- Never call `eval` in shell scripts.\n' >"$A/AGENTS.md"
printf -- '- Ask a maintainer before changing the release process.\n' >"$A/CONTRIBUTING.md"
commit_all "$A"

rows="$(bash "$GEN" --root "$A" --rows)"
assert_eq "A: one row per rule" 5 "$(wc -l <<<"$rows" | tr -d ' ')"
assert_line "A: declared codebase row" "$rows" "$(printf 'an order is draft or submitted, one status field\tsrc/order.ts Order type\tmake-impossible\t1')"
assert_line "A: deny row" "$rows" "$(printf 'Read(./.env)\t.claude/settings.json permissions.deny\tharness-setting\t2')"
assert_line "A: control skill row" "$rows" "$(printf 'runtime verification through the control-app skill\t.claude/skills/control-app/SKILL.md\truntime-verification\t3')"
assert_line "A: instruction row" "$rows" "$(printf 'Never call `eval` in shell scripts.\tAGENTS.md:1\tinstruction\t4')"
assert_line "A: human row" "$rows" "$(printf 'Ask a maintainer before changing the release process.\tCONTRIBUTING.md:1\thuman-review\t5')"

out="$(bash "$GEN" --root "$A")"
assert_line "A: tier 1 count" "$out" "| 1 Codebase | 1 | make-impossible 1 |"
assert_line "A: tier 2 count" "$out" "| 2 Static analysis | 1 | harness-setting 1 |"
assert_line "A: tier 3 count" "$out" "| 3 Verification | 1 | runtime-verification 1 |"
assert_line "A: tier 4 count" "$out" "| 4 Guidance | 1 | instruction 1 |"
assert_line "A: tier 5 count" "$out" "| 5 Human only | 1 | human-review 1 |"
assert_line "A: lower-than total" "$out" "Sits lower than it could: 1 guidance rule(s) forbid a literal that a pattern check could match (candidates to judge, not findings)"
assert_line "A: lower-than entry" "$out" '- AGENTS.md:1: forbids `eval` (instruction)'
assert_no "A: no target wording" "$out" "%"

B="$TMP/negatives"
new_repo "$B"
mkdir -p "$B/.claude"
printf '{"permissions": {"deny": ["Read(./.env)"]}}\n' >"$B/.claude/settings.json"
cat >"$B/AGENTS.md" <<'EOF'
- Prefer small pull requests that a reviewer can read in one sitting.
- Never read `./.env` directly.
- Never call `sudo` in a script. Enforced by: `bash scripts/check.sh`.
- If a pull request must not merge, apply the `hold` label.

Keep `README.md` short enough to read in a minute.
EOF
commit_all "$B"
out="$(bash "$GEN" --root "$B")"
assert_line "B: no candidate" "$out" "Sits lower than it could: 0 guidance rule(s) forbid a literal that a pattern check could match (candidates to judge, not findings)"
assert_line "B: every statement counted" "$out" "| 4 Guidance | 5 | instruction 5 |"

G="$TMP/whole-token"
new_repo "$G"
mkdir -p "$G/.claude/ecosystems" "$G/evals"
printf 'check-cmd: "ruff check --force-exclude <files>"\n' >"$G/.claude/ecosystems/python.yaml"
cat >"$G/.claude/settings.json" <<'EOF'
{"permissions": {"deny": ["Read(./.env)", "Edit(.github/workflows/*)"]},
 "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "guard.sh", "if": "Bash(git push --no-verify*)"}]}]}}
EOF
printf 'x\n' >"$G/evals/case.test.sh"
cat >"$G/AGENTS.md" <<'EOF'
- Never push with `--force` to a shared branch.
- Never call `eval` in shell scripts.
- Never edit `settings.json` without a review.
- Never edit `.github/workflows` from a session.
- Never pass `--no-verify` to git.
- Do not use `PreToolUse` hooks for formatting.
EOF
commit_all "$G"
assert_line "G: hook row" "$(bash "$GEN" --root "$G" --rows)" "$(printf 'PreToolUse Bash if Bash(git push --no-verify*)\t.claude/settings.json hooks\taction-guard\t2')"
out="$(bash "$GEN" --root "$G")"
assert_line "G: --force not hidden by --force-exclude" "$out" '- AGENTS.md:1: forbids `--force` (instruction)'
assert_line "G: eval not hidden by a test path under evals/" "$out" '- AGENTS.md:2: forbids `eval` (instruction)'
assert_line "G: settings.json not hidden by a deny row's enforcer label" "$out" '- AGENTS.md:3: forbids `settings.json` (instruction)'
assert_no "G: a literal a deny entry holds stays out" "$out" 'forbids `.github/workflows`'
assert_no "G: a literal a hook if value holds stays out" "$out" 'forbids `--no-verify`'
assert_line "G: a hook event name covers nothing" "$out" '- AGENTS.md:6: forbids `PreToolUse` (instruction)'
assert_line "G: four candidates" "$out" "Sits lower than it could: 4 guidance rule(s) forbid a literal that a pattern check could match (candidates to judge, not findings)"

C="$TMP/empty"
new_repo "$C"
out="$(bash "$GEN" --root "$C")"
assert_line "C: tier 1 says why it is empty" "$out" "| 1 Codebase | 0 | none declared; no file shows this tier, so only declared rows count |"
for t in "2 Static analysis" "3 Verification" "4 Guidance" "5 Human only"; do
  assert_line "C: $t printed" "$out" "| $t | 0 | none found in the sources below |"
done
assert_line "C: settings absent named" "$out" "- settings: .claude/settings.json absent"
assert_line "C: declared absent named" "$out" "- declared: docs/conventions/harness-config.yaml absent, so no declared rows"
assert_line "C: no ecosystem record named" "$out" "- ecosystems: no .claude/ecosystems/*.yaml record, so no recorded build, test or check command"
assert_line "C: review absent named" "$out" "- review: REVIEW.md absent"

D="$TMP/records"
new_repo "$D"
mkdir -p "$D/.claude/ecosystems" "$D/docs/conventions" "$D/src" "$D/tests/fixtures"
cat >"$D/.claude/ecosystems/shell.yaml" <<'EOF'
globs: ["*.sh"]
build-cmd: null
test-cmd: "bash run-tests.sh"
check-cmd: |
  shellcheck <files>
  # a comment line is not a command
  shfmt -d <files>
fix-cmd: "shfmt -w <files>"
EOF
cat >"$D/docs/conventions/harness-config.yaml" <<'EOF'
rule_inventory:
  declared:
    - rule: "no eval of request text"
      rung: semgrep-rule
    - rule: "a made-up rung"
      rung: bogus-rung
EOF
cat >"$D/CLAUDE.md" <<'EOF'
---
description: frontmatter is not a rule
---

# Heading is not a rule

| a table | is not a rule |
|---|---|

```bash
- a fenced line is not a rule
```

<!-- a comment
- is not a rule -->

@AGENTS.md

One paragraph that wraps
onto a second line is one rule.
EOF
printf 'x\n' >"$D/src/a.test.js"
printf 'x\n' >"$D/src/b_test.go"
printf -- '- a fixture instruction is not ours\n' >"$D/tests/fixtures/AGENTS.md"
printf 'x\n' >"$D/tests/fixtures/c.test.js"
printf 'x\n' >"$D/tests/test_d.py"
commit_all "$D"
rows="$(bash "$GEN" --root "$D" --rows)"
assert_line "D: check-cmd line 1" "$rows" "$(printf 'shell check-cmd: shellcheck <files>\t.claude/ecosystems/shell.yaml\tanalyzer-pack-rule\t2')"
assert_line "D: check-cmd line 2" "$rows" "$(printf 'shell check-cmd: shfmt -d <files>\t.claude/ecosystems/shell.yaml\tanalyzer-pack-rule\t2')"
assert_line "D: test-cmd" "$rows" "$(printf 'shell test-cmd: bash run-tests.sh\t.claude/ecosystems/shell.yaml\tbehavior-test\t2')"
assert_no "D: fix-cmd is not a check" "$rows" "fix-cmd"
assert_line "D: alias read as new id" "$rows" "$(printf 'no eval of request text\tdeclared in docs/conventions/harness-config.yaml\tsyntax-pattern-rule\t2')"
assert_no "D: unknown rung not emitted" "$rows" "bogus-rung"
assert_line "D: paragraph joined" "$rows" "$(printf 'One paragraph that wraps onto a second line is one rule.\tCLAUDE.md:19\tinstruction\t4')"
assert_eq "D: one instruction statement only" 1 "$(grep -c "	instruction	" <<<"$rows")"
assert_eq "D: three test files, tests/ kept, fixtures excluded" 3 "$(grep -c "^tests in " <<<"$rows")"
out="$(bash "$GEN" --root "$D")"
assert_line "D: alias notice" "$out" "- declared: item 0 names semgrep-rule, read as syntax-pattern-rule (renamed in ladder 3.0.0)"
assert_line "D: unknown rung named" "$out" '- skipped: rung `bogus-rung` from declared in docs/conventions/harness-config.yaml is not a rung of ladder '"$(awk -F': *' '/^enforcement-ladder:/ {print $2; exit}' "$LADDER")"

F="$TMP/uncounted"
new_repo "$F"
mkdir -p "$F/.github/workflows" "$F/.claude"
printf 'on: [pull_request]\n' >"$F/.github/workflows/ci.yml"
printf 'pre-commit:\n  commands: {}\n' >"$F/lefthook.yml"
printf '{"permissions": {"deny": ["Read(./.env)"]}, "enabledPlugins": {"guard@market": true}}\n' >"$F/.claude/settings.json"
commit_all "$F"
out="$(bash "$GEN" --root "$F")"
assert_line "F: counts unchanged by uncounted sources" "$out" "| 2 Static analysis | 1 | harness-setting 1 |"
assert_line "F: workflows named" "$out" "- present, not counted: 1 CI workflow file(s) under .github/workflows; a check that runs only there is in no row"
assert_line "F: git hooks named" "$out" "- present, not counted: lefthook.yml (git hooks); a check that runs only there is in no row"
assert_line "F: plugin hooks named" "$out" "- present, not counted: hooks and settings of the plugins .claude/settings.json enables"
out="$(bash "$GEN" --root "$C")"
assert_no "C: nothing named as uncounted" "$out" "present, not counted"

E="$TMP/parity"
new_repo "$E"
mkdir -p "$E/docs/conventions"
expected="make-impossible:1 shared-helper:1 compiler-setting:2 editorconfig-severity:2 analyzer-pack-rule:2 custom-analyzer:2 syntax-pattern-rule:2 architecture-test:2 behavior-test:2 harness-setting:2 action-guard:2 scaffold:2 runtime-verification:3 formal-verification:3 automated-review:4 instruction:4 skill:4 human-review:5"
{
  echo "rule_inventory:"
  echo "  declared:"
  for p in $expected; do
    printf '    - rule: "r %s"\n      rung: %s\n' "${p%%:*}" "${p%%:*}"
  done
} >"$E/docs/conventions/harness-config.yaml"
commit_all "$E"
got="$(bash "$GEN" --root "$E" --rows | awk -F'\t' '{printf "%s%s:%s", sep, $3, $4; sep = " "}')"
assert_eq "parity: every ladder rung maps to its tier" "$expected" "$got"
n_ids="$(grep -Eo '^(\| `[a-z-]+` \||[0-9]+\. \*\*`[a-z-]+`\*\*)' "$LADDER" | wc -l | tr -d ' ')"
assert_eq "parity: the ladder copy holds no other rung id" 18 "$n_ids"

home_repo() {
  new_repo "$1"
  mkdir -p "$1/docs/conventions"
  printf 'rule_inventory:\n  declared:\n    - rule: "stale default-home rule"\n      rung: make-impossible\n' >"$1/docs/conventions/harness-config.yaml"
  printf '<!-- BEGIN GENERATED: convention-home -->\n%s\n<!-- END GENERATED: convention-home -->\n' "$2" >"$1/AGENTS.md"
}
TIER1_SKIPPED="| 1 Codebase | 0 | declared rows not read (see the declared source line); no file shows this tier |"

H="$TMP/home-resolved"
home_repo "$H" 'Team conventions live in `team/conv`.'
mkdir -p "$H/team/conv"
printf 'rule_inventory:\n  declared:\n    - rule: "bound-home rule"\n      rung: make-impossible\n' >"$H/team/conv/harness-config.yaml"
commit_all "$H"
rows="$(bash "$GEN" --root "$H" --rows)"
assert_line "home resolved: its row counted" "$rows" "$(printf 'bound-home rule\tdeclared in team/conv/harness-config.yaml\tmake-impossible\t1')"
assert_no "home resolved: default-home file not read" "$rows" "stale default-home rule"
assert_line "home resolved: source named" "$(bash "$GEN" --root "$H")" "- declared: team/conv/harness-config.yaml read, 1 item(s)"

H="$TMP/home-declined"
home_repo "$H" 'declined'
commit_all "$H"
out="$(bash "$GEN" --root "$H")"
assert_no "home declined: leftover file not read" "$(bash "$GEN" --root "$H" --rows)" "stale default-home rule"
assert_line "home declined: tier 1 not a plain zero" "$out" "$TIER1_SKIPPED"
assert_line "home declined: named" "$out" "- declared: not read, so no declared rows: the repository declined a convention home (docs/conventions/harness-config.yaml is present and not read)"

H="$TMP/home-unresolved"
home_repo "$H" 'Team conventions live in `team/missing`.'
commit_all "$H"
out="$(bash "$GEN" --root "$H")"
assert_no "home unresolved: not rebound to docs/conventions" "$(bash "$GEN" --root "$H" --rows)" "stale default-home rule"
assert_line "home unresolved: tier 1 not a plain zero" "$out" "$TIER1_SKIPPED"
assert_has "home unresolved: failure named" "$out" "- declared: not read, so no declared rows: the convention home did not resolve (FAIL: pointer target directory missing: team/missing"

H="$TMP/home-not-applicable"
mkdir -p "$H/docs/conventions"
printf 'rule_inventory:\n  declared:\n    - rule: "stale default-home rule"\n      rung: make-impossible\n' >"$H/docs/conventions/harness-config.yaml"
out="$(bash "$GEN" --root "$H")"
assert_no "home not applicable: file not read" "$(bash "$GEN" --root "$H" --rows)" "stale default-home rule"
assert_line "home not applicable: named" "$out" "- declared: not read, so no declared rows: no convention home applies to this root (docs/conventions/harness-config.yaml is present and not read)"

bash "$GEN" --bogus >/dev/null 2>&1
assert_eq "unknown argument exits 2" 2 "$?"
bash "$GEN" --root "$TMP/missing" >/dev/null 2>&1
assert_eq "missing root exits 2" 2 "$?"
RULE_INVENTORY_LADDER="$TMP/no-ladder.md" bash "$GEN" --root "$A" >/dev/null 2>&1
assert_eq "unreadable ladder exits 2" 2 "$?"

printf '\n%d case(s), %d failed\n' "$CASES" "$FAILED"
[[ "$FAILED" -eq 0 ]]
