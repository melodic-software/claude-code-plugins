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
assert_contains "that runs test-scan with --enabled" "$out" 'exec bash \"$p\" --enabled'
assert_contains "with an Edit row too" "$out" '"if": "Edit(*.it.ts)"'
assert_contains "run outside the plugin cache, the marketplace is a placeholder" "$out" 'cache/<marketplace>\"/testing/'
assert_contains "with a note saying so" "$out" 'replace <marketplace>'
cmd="$(sed -n '/^{/,$p' <<<"$out" | jq -r '.hooks.PostToolUse[0].hooks[0].command')"
rc=0
got="$(echo '{}' | bash -c "$cmd" 2>&1)" || rc=$?
assert_eq "left unreplaced, the entry says so on stderr and exits 0" \
  "0:testing: no installed test-scan.sh under ~/.claude/plugins/cache/<marketplace>/testing takes --enabled; this settings hook did nothing" "$rc:$got"

# The entry, run from a cached copy: pinned to that copy's marketplace, the
# highest version by sort -V whatever the mtimes, and never silent.
C="$HOME/.claude/plugins/cache"
mkdir -p "$C/mk/testing" "$C/other/testing/9.0.0/hooks"
ln -s "$(cd "$(dirname "$SETUP")/../../.." && pwd)" "$C/mk/testing/0.0.1"
for v in 1.9.0 1.10.0; do
  mkdir -p "$C/mk/testing/$v/hooks"
  printf 'cat >/dev/null; echo "%s $*" # --enabled\n' "$v" >"$C/mk/testing/$v/hooks/test-scan.sh"
done
printf 'echo other --enabled\n' >"$C/other/testing/9.0.0/hooks/test-scan.sh"
touch -d '1 minute ago' "$C/mk/testing/1.10.0/hooks/test-scan.sh"
rc=0
out="$(bash "$C/mk/testing/0.0.1/skills/setup/scripts/setup.sh" check --root "$R" 2>&1)" || rc=$?
assert_contains "run from the cache, the entry pins that marketplace" "$out" 'cache/mk\"/testing/*/hooks/test-scan.sh'
cmd="$(sed -n '/^{/,$p' <<<"$out" | jq -r '.hooks.PostToolUse[0].hooks[0].command')"
entry() {
  rc=0
  out="$(echo '{}' | bash -c "$cmd" 2>&1)" || rc=$?
}
entry
assert_eq "the entry runs the highest version by sort -V, not the newest mtime" "0:1.10.0 --enabled" "$rc:$out"
rm -rf "$C/mk/testing/1.10.0" "$C/mk/testing/0.0.1"
printf 'echo old\n' >"$C/mk/testing/1.9.0/hooks/test-scan.sh"
entry
assert_contains "a copy that predates --enabled prints why on stderr" "$out" "--enabled"
assert_eq "and exits 0" 0 "$rc"
assert_eq "without running it" "" "$(grep -x old <<<"$out")"
rm -rf "$C/mk"
entry
assert_contains "no installed copy prints why on stderr" "$out" "test-scan"
assert_eq "and exits 0" 0 "$rc"
rm -rf "$HOME/.claude/plugins"

# A paths.include glob adds no basename to the hook's `if` rows, so it needs
# no entry.
cp "$R/.claude/testing.yaml" "$T/kept.yaml"
run apply --include 'legacy/**' --include 'tests/*.py'
run check
assert_contains "paths.include globs print no hook entry" "$out" "none: every consumer test glob is covered"
assert_eq "and no Write(**) or Write(*.py) row" "" "$(grep -F -e 'Write(**)' -e 'Write(*.py)' <<<"$out")"
cp "$T/kept.yaml" "$R/.claude/testing.yaml"

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
