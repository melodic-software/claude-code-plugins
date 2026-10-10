#!/usr/bin/env bash
# Tests for setup.sh: check's four sections, lint findings, the consumer hook
# entry, and an apply that writes only the docs convention file or .claude/testing.yaml.
# test-scope: plugins/testing/skills/audit/adapters/*.yaml
# shellcheck disable=SC2016 # fence lines in fixtures are literal text
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
assert_not_contains() { if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "expected not to contain: $3"; fi; }
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
assert_contains "the config section says no layer is present" "$out" "no testing config layer"
assert_line "a Vitest repo without the ESLint plugin is a finding" "$out" '^js +vitest/valid-expect +FINDING'
assert_line "select without PL leaves PLR0124 off, a finding" "$out" '^python +ruff PLR0124 +FINDING'
assert_line "PT011 is not in the default set, a finding" "$out" '^python +ruff PT011 +FINDING'
assert_line "F selects F631" "$out" '^python +ruff F631 +PRESENT'
assert_line "xunit brings xUnit2021" "$out" '^cs +xUnit2021 +PRESENT'
assert_line "Bash has no maintained rule" "$out" '^bash .*no maintained rule'
assert_contains "the instruction line is printed to paste" "$out" "never edits them"
assert_line "with CLAUDE.md and AGENTS.md, it names CLAUDE.md, the one Claude Code loads" "$out" '^Optional\..* Paste this into CLAUDE\.md yourself:$'
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
TY="$R/docs/conventions/testing.yaml"
expected='# Test-file scope and rule levels for the testing plugin (/testing:setup).
adapters:
  disable: ['"'py-unittest'"']
paths:
  exclude: ['"'legacy/**'"']
extend:
  js-vitest:
    files: ['"'*.it.ts'"']
rules:
  rule-weak-oracle: warn
  rule-zero-assertion: error'
assert_eq "apply creates docs/conventions/testing.yaml with the answers" "$expected" "$(cat "$TY")"
assert_eq "and writes no .claude/testing.yaml" "" "$(ls "$R/.claude" 2>/dev/null)"
run check
assert_line "check prints the resolved config" "$out" $'^rules\\.weak-oracle\twarn$'
assert_line "the layer record names testing.yaml" "$out" "^layer"$'\t'"$TY\$"
assert_not_contains "with no docs/conventions/testing.md, check offers no pointer line" "$out" "If testing, read"
assert_contains "and a hook entry for the uncovered glob" "$out" '"if": "Write(*.it.ts)"'
# shellcheck disable=SC2016 # literal command text
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
# highest version (numeric major.minor.patch) whatever the mtimes, and never silent.
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
assert_eq "the entry runs the highest version, not the newest mtime" "0:1.10.0 --enabled" "$rc:$out"
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

# A marketplace name that is not a plain name is never spliced into the command.
# shellcheck disable=SC2016 # the name must not expand
bad='m$(touch pwned)k'
mkdir -p "$C/$bad/testing"
ln -s "$(cd "$(dirname "$SETUP")/../../.." && pwd)" "$C/$bad/testing/0.0.1"
out="$(bash "$C/$bad/testing/0.0.1/skills/setup/scripts/setup.sh" check --root "$R" 2>&1)"
assert_contains "a marketplace name with shell syntax falls back to the placeholder" "$out" 'cache/<marketplace>\"/testing/'
assert_eq "and is not in the entry" "" "$(grep -F 'pwned' <<<"$out")"
rm -rf "$HOME/.claude/plugins"

# A paths.include glob adds no basename to the hook's `if` rows, so it needs
# no entry.
cp "$TY" "$T/kept.yaml"
run apply --include 'legacy/**' --include 'tests/*.py'
run check
assert_contains "paths.include globs print no hook entry" "$out" "none: every consumer test glob is covered"
assert_eq "and no Write(**) or Write(*.py) row" "" "$(grep -F -e 'Write(**)' -e 'Write(*.py)' <<<"$out")"
cp "$T/kept.yaml" "$TY"

# Interleaved --extend flags still write one mapping per adapter.
run apply --extend js-vitest.files='*.it.ts' --extend py-pytest.files='check_*.py' \
  --extend js-vitest.assertion.calls='verify'
assert_eq "apply accepts --extend flags that interleave adapters" 0 "$rc"
expected="extend:
  js-vitest:
    files: ['*.it.ts']
    assertion.calls: ['verify']
  py-pytest:
    files: ['check_*.py']"
assert_eq "and groups each adapter's fields under one key" "$expected" "$(sed -n '/^extend:/,$p' "$TY")"
cp "$T/kept.yaml" "$TY"

# A test file only an extend.*.files glob or a consumer adapter claims still
# gets the lint check.
L="$T/lintonly"
mkdir -p "$L/.claude" "$L/adapters"
git -C "$L" init -q
printf '{ "devDependencies": { "vitest": "^3.0.0" } }\n' >"$L/package.json"
printf "import { it } from 'vitest';\n" >"$L/a.it.ts"
printf "extend:\n  js-vitest:\n    files: ['*.it.ts']\n" >"$L/.claude/testing.yaml"
git -C "$L" add -A
rc=0
out="$(bash "$SETUP" check --root "$L" 2>&1)" || rc=$?
assert_line "an extend.*.files test file gets the Vitest lint check" "$out" '^js +vitest/valid-expect +FINDING'
assert_eq "and check exits 1" 1 "$rc"
printf "id: js-spec\nextends: js-vitest\nfiles: ['*.it.ts']\n" >"$L/adapters/js-spec.yaml"
printf 'adapter_dirs: [adapters]\n' >"$L/.claude/testing.yaml"
rc=0
out="$(bash "$SETUP" check --root "$L" 2>&1)" || rc=$?
assert_line "an adapter_dirs adapter's files glob gets it too" "$out" '^js +vitest/valid-expect +FINDING'

# The instruction line names the file Claude Code loads here: AGENTS.md only
# when no CLAUDE.md, .claude/CLAUDE.md or CLAUDE.local.md exists; CLAUDE.local.md
# always loads, and the user file follows CLAUDE_CONFIG_DIR
# (code.claude.com/docs/en/memory#agents-md).
target() {
  local d="$T/instr-$1" f
  shift
  mkdir -p "$d/.claude"
  git -C "$d" init -q
  for f; do printf '# x\n' >"$d/$f"; done
  env -u CLAUDE_CONFIG_DIR ${CFG:+CLAUDE_CONFIG_DIR="$CFG"} bash "$SETUP" check --root "$d" 2>&1 | grep '^Optional\.'
}
assert_line "AGENTS.md alone is the file named" "$(target agents AGENTS.md)" 'Paste this into AGENTS\.md yourself:$'
assert_line ".claude/CLAUDE.md beats AGENTS.md" "$(target dotclaude .claude/CLAUDE.md AGENTS.md)" 'Paste this into \.claude/CLAUDE\.md yourself:$'
assert_line "CLAUDE.local.md keeps AGENTS.md from loading, so CLAUDE.local.md is named" \
  "$(target local CLAUDE.local.md AGENTS.md)" 'Paste this into CLAUDE\.local\.md yourself \(it is personal; a CLAUDE\.md would share the line with the team\):$'
assert_line "CLAUDE.local.md alone loads for this repository, so it is named" \
  "$(target localonly CLAUDE.local.md)" 'Paste this into CLAUDE\.local\.md yourself \(it is personal; a CLAUDE\.md would share the line with the team\):$'
assert_line "with neither, the user file is named" "$(target none)" 'Paste this into ~/\.claude/CLAUDE\.md yourself \(this repository has neither; that file applies to every repository\):$'
assert_line "a relocated CLAUDE_CONFIG_DIR names its CLAUDE.md" "$(CFG=/cfg/claude target relocated)" 'Paste this into /cfg/claude/CLAUDE\.md yourself'

cp "$TY" "$T/kept.yaml"
run apply --rule no-such-rule=off
assert_eq "apply refuses answers that do not resolve" 2 "$rc"
assert_eq "and leaves the file as it was" "$(cat "$T/kept.yaml")" "$(cat "$TY")"
run apply --rule $'weak-oracle=off\n```\nInjected prose\n'
assert_eq "apply refuses a flag value that holds a line break" 2 "$rc"
assert_eq "and leaves the file as it was after a line break" "$(cat "$T/kept.yaml")" "$(cat "$TY")"
run apply --rule weak-oracle=loud
assert_eq "apply refuses a rule level other than off, warn or error" 2 "$rc"

# apply never writes through a symlink a repository commits.
S="$T/sym"
mkdir -p "$S/.claude" "$S/elsewhere"
git -C "$S" init -q
printf '# Team instructions\n' >"$S/CLAUDE.md"
ln -s ../CLAUDE.md "$S/.claude/testing.yaml"
rc=0
out="$(bash "$SETUP" apply --root "$S" --exclude 'legacy/**' 2>&1)" || rc=$?
assert_eq "apply refuses a .claude/testing.yaml symlink" 2 "$rc"
assert_eq "and CLAUDE.md is unchanged" "# Team instructions" "$(cat "$S/CLAUDE.md")"
rm -rf "$S/.claude"
mkdir -p "$S/docs"
ln -s ../elsewhere "$S/docs/conventions"
rc=0
out="$(bash "$SETUP" apply --root "$S" --exclude 'legacy/**' 2>&1)" || rc=$?
assert_eq "apply refuses a symlinked docs/conventions directory" 2 "$rc"
assert_eq "and writes nothing through it" "" "$(ls -A "$S/elsewhere")"
rm -rf "$S/docs"
ln -s elsewhere "$S/docs"
rc=0
out="$(bash "$SETUP" apply --root "$S" --exclude 'legacy/**' 2>&1)" || rc=$?
assert_eq "apply refuses a symlinked docs directory" 2 "$rc"
assert_eq "and writes nothing through it" "" "$(ls -A "$S/elsewhere")"
rm -f "$S/docs"
mkdir -p "$S/docs/conventions"
printf '```yaml config\nbad line\n```\n' >"$S/elsewhere/target.md"
ln -s ../../elsewhere/target.md "$S/docs/conventions/testing.md"
rc=0
out="$(bash "$SETUP" apply --root "$S" --exclude 'legacy/**' 2>&1)" || rc=$?
assert_eq "apply refuses a symlinked docs file" 2 "$rc"
assert_eq "and never reads what it points at" 0 "$(grep -c "bad line" <<<"$out")"
rm -rf "$S/docs" "$S/elsewhere/target.md"
ln -s elsewhere "$S/.claude"
printf 'paths:\n  exclude: [a]\n' >"$S/elsewhere/testing.yaml"
rc=0
out="$(bash "$SETUP" apply --root "$S" --exclude 'legacy/**' 2>&1)" || rc=$?
assert_eq "apply refuses a symlinked .claude directory holding the team file" 2 "$rc"
assert_eq "and leaves that file alone" "paths:
  exclude: [a]" "$(cat "$S/elsewhere/testing.yaml")"

# The target: testing.yaml when it exists, else the docs block when the docs file has one, else .claude/testing.yaml
# when that is the file in use, else a new testing.yaml. Other text in the docs file stays.
G="$T/target"
mkdir -p "$G/.claude" "$G/docs/conventions"
git -C "$G" init -q
printf "paths:\n  exclude: [old]\n" >"$G/.claude/testing.yaml"
run_g() {
  rc=0
  out="$(bash "$SETUP" apply --root "$G" "$@" 2>&1)" || rc=$?
}
run_g --exclude 'new/**'
assert_eq "with only a .claude/testing.yaml in use, apply rewrites it" "0:# Test-file scope and rule levels for the testing plugin (/testing:setup).
paths:
  exclude: ['new/**']" "$rc:$(cat "$G/.claude/testing.yaml")"
assert_eq "and creates no docs file" "" "$(ls "$G/docs/conventions")"
printf '# Testing\n\nProse first.\n' >"$G/docs/conventions/testing.md"
run_g --exclude 'new/**'
assert_eq "a docs file with no block and a .claude file in use: the docs file is not touched" "# Testing

Prose first." "$(cat "$G/docs/conventions/testing.md")"
printf '# Testing\n\nBefore.\n\n```yaml config\npaths:\n  exclude: [old]\n```\n\nAfter.\n' >"$G/docs/conventions/testing.md"
printf 'paths:\n  exclude: [claude-file]\n' >"$G/.claude/testing.yaml"
run_g --exclude 'replaced/**' --include 'keep/**'
assert_eq "an existing block's body is replaced, the text around it kept" "0:# Testing

Before.

\`\`\`yaml config
paths:
  include: ['keep/**']
  exclude: ['replaced/**']
\`\`\`

After." "$rc:$(cat "$G/docs/conventions/testing.md")"
assert_eq "and the .claude file, shadowed by the block, is untouched" "paths:
  exclude: [claude-file]" "$(cat "$G/.claude/testing.yaml")"
printf '# Testing\n\n```yaml config\npaths:\n  excludes: [x]\n```\n' >"$G/docs/conventions/testing.md"
run_g --exclude 'y/**'
assert_eq "a docs block that does not parse is refused, not overwritten" 2 "$rc"
assert_contains "naming the .md line" "$out" "testing.md:5: unknown key: paths.excludes"
rm -f "$G/.claude/testing.yaml"
printf '# Testing\n\nProse only.\n' >"$G/docs/conventions/testing.md"
run_g --exclude 'fresh/**'
assert_eq "a docs file with no block and no other team file: apply creates testing.yaml" "0:# Test-file scope and rule levels for the testing plugin (/testing:setup).
paths:
  exclude: ['fresh/**']" "$rc:$(cat "$G/docs/conventions/testing.yaml")"
assert_eq "and leaves the prose file as it was" "# Testing

Prose only." "$(cat "$G/docs/conventions/testing.md")"
block_md='# Testing\n\n```yaml config\npaths:\n  exclude: [old]\n```\n'
printf '%b' "$block_md" >"$G/docs/conventions/testing.md"
printf 'e2e_driver: run\npaths:\n  exclude: [old]\nreuse_running_instance: false\nfeature_map_dir: docs/map\n' >"$G/docs/conventions/testing.yaml"
run_g --exclude 'yaml/**'
assert_eq "testing.yaml in use: apply rewrites it and keeps the run-e2e keys" "0:# Test-file scope and rule levels for the testing plugin (/testing:setup).
paths:
  exclude: ['yaml/**']
e2e_driver: run
reuse_running_instance: false
feature_map_dir: docs/map" "$rc:$(cat "$G/docs/conventions/testing.yaml")"
assert_eq "and the docs block it shadows is untouched" "$(printf '%b' "$block_md")" "$(cat "$G/docs/conventions/testing.md")"

assert_eq "neither check nor apply changed CLAUDE.md or AGENTS.md" "$before" "$(sums)"
assert_eq "apply wrote no file but docs/conventions/testing.yaml" "docs/conventions/testing.yaml" \
  "$(git -C "$R" status --porcelain --untracked-files=all | sed 's/^?? //' | grep -v '^A ' | sort | paste -sd' ')"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
