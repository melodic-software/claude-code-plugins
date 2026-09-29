#!/usr/bin/env bash
# Tests for setup.sh: check's four sections, lint findings, the consumer hook
# entry, and an apply that writes only .claude/testing.yaml.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG CLAUDE_PROJECT_DIR

SETUP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup.sh"
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
assert_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi; }
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "expected to contain: $3"; fi; }
assert_line() { if grep -Eq "$3" <<<"$2"; then pass "$1"; else fail "$1" "no line matches: $3"; fi; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
R="$T/repo"
mkdir -p "$HOME" "$R/src" "$R/tests"
git -C "$R" init -q
printf '# Team instructions\n' >"$R/CLAUDE.md"
printf '# Agent instructions\n' >"$R/AGENTS.md"
printf '{ "devDependencies": { "vitest": "^3.0.0" } }\n' >"$R/package.json"
printf "import { it } from 'vitest';\n" >"$R/src/a.test.ts"
printf 'def test_x():\n    assert 1\n' >"$R/tests/test_x.py"
printf '[tool.ruff.lint]\nselect = [\n  "E",\n  "F",\n]\n' >"$R/pyproject.toml"
printf '#!/usr/bin/env bash\n' >"$R/run.test.sh"
printf '<Project><ItemGroup><PackageReference Include="xunit" Version="2.9.0" /></ItemGroup></Project>\n' >"$R/Unit.csproj"
printf 'public class SumTests {}\n' >"$R/src/SumTests.cs"
git -C "$R" add -A
sums() { cksum "$R/CLAUDE.md" "$R/AGENTS.md"; }
before="$(sums)"

run() {
  rc=0
  out="$(bash "$SETUP" "$@" --root "$R" 2>&1)" || rc=$?
}

run check
assert_eq "check exits 1 when a test-lint rule is missing" 1 "$rc"
assert_contains "the config section says no layer is present" "$out" "no .claude/testing.yaml layer"
assert_line "a Vitest repo without the ESLint plugin is a finding" "$out" '^js +vitest/valid-expect +FINDING'
assert_line "select without PL leaves PLR0124 off, a finding" "$out" '^python +ruff PLR0124 +FINDING'
assert_line "PT011 is not in the default set, a finding" "$out" '^python +ruff PT011 +FINDING'
assert_line "F selects F631" "$out" '^python +ruff F631 +PRESENT'
assert_line "xunit brings xUnit2021" "$out" '^cs +xUnit2021 +PRESENT'
assert_line "Bash has no maintained rule" "$out" '^bash .*no maintained rule'
assert_contains "the instruction line is printed to paste" "$out" "never edits them"
assert_contains "no consumer glob means no hook entry" "$out" "none: every consumer test glob is covered"

printf "import vitest from '@vitest/eslint-plugin';\nexport default [vitest.configs.recommended];\n" >"$R/eslint.config.mjs"
printf '[tool.ruff.lint]\nextend-select = ["PT", "PLR0124"]\n' >"$R/pyproject.toml"
git -C "$R" add -A
run check
assert_line "the plugin's recommended config turns valid-expect on" "$out" '^js +vitest/valid-expect +PRESENT'
assert_line "extend-select PT covers PT011" "$out" '^python +ruff PT011 +PRESENT'
assert_line "defaults keep F631 when select is unset" "$out" '^python +ruff F631 +PRESENT'
assert_eq "check exits 0 with no finding" 0 "$rc"

run apply --exclude 'legacy/**' --rule weak-oracle=warn --rule testing/audit/rule-zero-assertion=error \
  --extend js-vitest.files='*.it.ts' --disable py-unittest
assert_eq "apply exits 0" 0 "$rc"
expected="# Test-file scope and rule levels for the testing plugin (/testing:setup).
adapters:
  disable: ['py-unittest']
paths:
  exclude: ['legacy/**']
extend:
  js-vitest:
    files: ['*.it.ts']
rules:
  rule-weak-oracle: warn
  rule-zero-assertion: error"
assert_eq "apply writes the answers as .claude/testing.yaml" "$expected" "$(cat "$R/.claude/testing.yaml")"
run check
assert_line "check prints the resolved config" "$out" $'^rules\\.weak-oracle\twarn$'
assert_contains "and a hook entry for the uncovered glob" "$out" '"if": "Write(*.it.ts)"'
assert_contains "that runs test-scan with --enabled" "$out" 'exec bash \"$p\" --enabled"'
assert_contains "with an Edit row too" "$out" '"if": "Edit(*.it.ts)"'

cp "$R/.claude/testing.yaml" "$T/kept.yaml"
run apply --rule no-such-rule=off
assert_eq "apply refuses answers that do not resolve" 2 "$rc"
assert_eq "and leaves the file as it was" "$(cat "$T/kept.yaml")" "$(cat "$R/.claude/testing.yaml")"

assert_eq "neither check nor apply changed CLAUDE.md or AGENTS.md" "$before" "$(sums)"
assert_eq "apply wrote no file but .claude/testing.yaml" ".claude/testing.yaml" \
  "$(git -C "$R" status --porcelain --untracked-files=all | sed 's/^?? //' | grep -v '^A ' | sort | paste -sd' ')"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
