#!/usr/bin/env bash
# test-scope: docs/conventions/source-control.yaml
# Template basenames named for the affected-tests mapping: this suite covers
# check-file-names.sh.tmpl, check-file-names.test.sh.tmpl, and
# file-names-rule.md.tmpl.
#
# Every single-quoted `$v` below is a jq program argument naming jq's own
# variable, and every single-quoted backtick or `$(...)` is the literal payload
# of an injection case. None is a shell expansion.
# shellcheck disable=SC2016
# test-scope: plugins/docs-naming/skills/audit-file-names/scripts/fixtures/tree/*
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/emit-gate.sh"
BUILD="$SCRIPT_DIR/../../audit-file-names/scripts/fixtures/build-fixture.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"

new_fixture() {
  d="$TEST_TMPDIR/fx-$CASES-$RANDOM"
  bash "$BUILD" "$d" >/dev/null
  cp "${BUILD%/*}/config.json" "$d.json"
  printf '%s' "$d"
}

emit() {
  root="$1"
  shift
  bash "$SUT" --root "$root" --config "$root.json" "$@" 2>&1
}

root="$(new_fixture)"
out="$(emit "$root")"
rc=$?

assert_eq "a clean emission exits 0" "0" "$rc"
assert_contains "the checker is named" "$out" "EMITTED	scripts/check-file-names.sh"
assert_contains "its suite is named" "$out" "EMITTED	scripts/check-file-names.test.sh"
assert_absent "no rule file without --rule" "$out" ".claude/rules/file-names.md"
assert_eq "the checker is executable" "yes" \
  "$([[ -x "$root/scripts/check-file-names.sh" ]] && echo yes || echo no)"
assert_contains "the wiring it does NOT do is stated" "$out" "NOT-WIRED	a CI step"

assert_absent "no placeholder survives rendering" "$(cat "$root/scripts/check-file-names.sh")" "@@"
assert_absent "no placeholder survives in the suite" "$(cat "$root/scripts/check-file-names.test.sh")" "@@"

assert_contains "the consumer's regex is inlined verbatim" \
  "$(cat "$root/scripts/check-file-names.sh")" '^[a-z0-9]+([.-][a-z0-9]+)*\.[a-z0-9]+$'
assert_absent "the emitted checker carries no plugin path" \
  "$(cat "$root/scripts/check-file-names.sh")" "CLAUDE_SKILL_DIR"
assert_absent "nor a plugin root" \
  "$(cat "$root/scripts/check-file-names.sh")" "CLAUDE_PLUGIN_ROOT"

clean="$TEST_TMPDIR/clean-$RANDOM"
mkdir -p "$clean/docs" "$clean/scripts"
printf '# ok\n' >"$clean/docs/conforming-name.md"
cp "$root/scripts/check-file-names.sh" "$clean/scripts/"
git init -q "$clean"
git -C "$clean" config user.email fixture@example.invalid
git -C "$clean" config user.name Fixture
git -C "$clean" config commit.gpgsign false
git -C "$clean" add -A >/dev/null
git -C "$clean" commit -qm clean >/dev/null

stdout="$(bash "$clean/scripts/check-file-names.sh" --check 2>"$TEST_TMPDIR/e1")"
rc=$?
assert_eq "a clean fixture exits 0" "0" "$rc"
assert_contains "the statement is on stdout" "$stdout" "every tracked file under"
assert_eq "and stderr is empty" "" "$(cat "$TEST_TMPDIR/e1")"

printf '# bad\n' >"$clean/docs/NEW-FILE.md"
git -C "$clean" add -A >/dev/null
stdout="$(bash "$clean/scripts/check-file-names.sh" --check 2>"$TEST_TMPDIR/e2")"
rc=$?
assert_eq "a seeded violation exits 1" "1" "$rc"
assert_eq "and stdout is empty" "" "$stdout"
assert_contains "the finding is on stderr" "$(cat "$TEST_TMPDIR/e2")" "docs/NEW-FILE.md"

BASH_BIN="$(command -v bash)"
stub="$TEST_TMPDIR/nogit-$RANDOM"
mkdir -p "$stub"
out="$(PATH="$stub" "$BASH_BIN" "$clean/scripts/check-file-names.sh" --check 2>&1)"
rc=$?
assert_eq "git hidden from PATH exits 2" "2" "$rc"
assert_contains "the reason names git" "$out" "git is required"

pass "emitted checker passes the three contract dimensions"

out="$(timeout 300 bash "$root/scripts/check-file-names.test.sh" 2>&1)"
rc=$?
assert_eq "the emitted suite exits 0" "0" "$rc"
assert_contains "and reports no failures" "$out" "0 failure(s)"
assert_contains "it exercises the exemptions the config declares" "$out" "the exempt basename README.md"
assert_contains "and the case-collision pass" "$out" "differing only by case"

if command -v shellcheck >/dev/null 2>&1; then
  RC_FILE="$(bash "$SCRIPT_DIR/../../../../../lib/org-standards.sh" dir --root "$SCRIPT_DIR/../../../../.." 2>/dev/null)/.shellcheckrc"
  sc_args=(-x)
  if [[ -f "$RC_FILE" ]] && grep -q -- '--rcfile' < <(shellcheck --help 2>&1); then
    sc_args+=("--rcfile=$RC_FILE")
    sc="$(shellcheck "${sc_args[@]}" "$root/scripts/check-file-names.sh" "$root/scripts/check-file-names.test.sh" 2>&1)"
    assert_eq "shellcheck is clean on the emitted pair under this repo's rcfile" "" "$sc"
  elif [[ -f "$RC_FILE" ]]; then
    printf 'SKIP: shellcheck has no --rcfile, so the repo rcfile cannot be applied\n'
  else
    sc="$(shellcheck "${sc_args[@]}" "$root/scripts/check-file-names.sh" "$root/scripts/check-file-names.test.sh" 2>&1)"
    assert_eq "shellcheck is clean on the emitted pair under this repo's rcfile" "" "$sc"
  fi
else
  printf 'SKIP: shellcheck not installed\n'
fi

root="$(new_fixture)"
jq '.file_names.roots += [{"path": ".", "extensions": ["md"], "exempt_paths": ["**/fixtures/**"]}]' \
  "$root.json" >"$root.t.json"
mv "$root.t.json" "$root.json"
out="$(emit "$root" --rule)"
assert_contains "a root object emits" "$out" "EMITTED	scripts/check-file-names.sh"
assert_contains "the rule lists the root's extension glob" "$(cat "$root/.claude/rules/file-names.md")" "paths: docs/**, **/*.[mM][dD]"

scoped="$TEST_TMPDIR/scoped-$RANDOM"
mkdir -p "$scoped/scripts" "$scoped/docs/fixtures" "$scoped/tools/fixtures"
cp "$root/scripts/check-file-names.sh" "$scoped/scripts/"
for f in docs/conforming-name.md tools/Other_File.txt tools/fixtures/Kept_Name.md README.md; do
  printf 'x\n' >"$scoped/$f"
done
git init -q "$scoped"
git -C "$scoped" config user.email fixture@example.invalid
git -C "$scoped" config user.name Fixture
git -C "$scoped" config commit.gpgsign false
git -C "$scoped" add -A >/dev/null
git -C "$scoped" commit -qm scoped >/dev/null
out="$(bash "$scoped/scripts/check-file-names.sh" --check 2>&1)"
assert_eq "an exempt path and an unclaimed extension pass" "0" "$?"
assert_contains "the clean line labels the extension filter" "$out" "under docs, . (*.md) is"

for f in tools/Notes_Here.md tools/LOUD.MD docs/fixtures/Judged_Name.md tools/fixtures/kept_name.md; do
  printf 'x\n' >"$scoped/$f"
done
git -C "$scoped" add -A >/dev/null
out="$(bash "$scoped/scripts/check-file-names.sh" --check 2>&1)"
assert_eq "markdown outside docs is judged" "1" "$?"
assert_contains "a markdown offender outside docs is named" "$out" "tools/Notes_Here.md: basename"
assert_contains "the extension filter matches in any case" "$out" "tools/LOUD.MD: basename"
assert_contains "a path another root claims stays judged" "$out" "docs/fixtures/Judged_Name.md: basename"
assert_absent "a root's exempt path is not judged by basename" "$out" "tools/fixtures/Kept_Name.md: basename"
assert_contains "an exempt path still collides by case" "$out" "tools/fixtures/Kept_Name.md: differs only by case"
assert_absent "an unclaimed extension is out of scope" "$out" "tools/Other_File.txt"
assert_contains "the summary counts each finding once" "$out" "5 offender(s)"

out="$(timeout 300 bash "$root/scripts/check-file-names.test.sh" 2>&1)"
assert_eq "the emitted suite passes under a root object" "0" "$?"

root="$(new_fixture)"
jq '.file_names.roots = [{"path": "docs", "extensions": ["rst"]}]' \
  "$root.json" >"$root.t.json"
mv "$root.t.json" "$root.json"
out="$(emit "$root")"
assert_contains "an rst-only root emits" "$out" "EMITTED	scripts/check-file-names.sh"
out="$(timeout 300 bash "$root/scripts/check-file-names.test.sh" 2>&1)"
assert_eq "the emitted suite passes under an rst-only root" "0" "$?"

for ex in '**/zzz/**' '**/fixtures/**'; do
  root="$(new_fixture)"
  jq --arg ex "$ex" '.file_names.roots += [{"path": "tools", "extensions": ["md"], "exempt_paths": [$ex]}]' \
    "$root.json" >"$root.t.json"
  mv "$root.t.json" "$root.json"
  emit "$root" >/dev/null
  nested="$TEST_TMPDIR/nested-$RANDOM"
  mkdir -p "$nested/scripts" "$nested/tools/fixtures" "$nested/docs"
  cp "$root/scripts/check-file-names.sh" "$nested/scripts/"
  for f in docs/conforming-name.md tools/Notes_Here.md tools/fixtures/Kept_Name.md; do
    printf 'x\n' >"$nested/$f"
  done
  git init -q "$nested"
  git -C "$nested" add -A >/dev/null
  out="$(bash "$nested/scripts/check-file-names.sh" --check 2>&1)"
  assert_contains "a nested root still judges its offender ($ex)" "$out" "tools/Notes_Here.md: basename"
  if [[ "$ex" == '**/zzz/**' ]]; then
    assert_contains "an exempt glob matching nothing exempts nothing" "$out" "tools/fixtures/Kept_Name.md: basename"
  else
    assert_absent "a nested root's exempt glob exempts its path" "$out" "tools/fixtures/Kept_Name.md"
  fi
done

for bad in '{"path": ".", "extensions": ["m]d"]}' '{"path": "a\nb"}' '{"path": "../x"}' \
  '{"path": ".", "exempt_paths": ["/abs/**"]}' '{"path": "docs", "exempt_paths": ["docs/../../x"]}'; do
  root="$(new_fixture)"
  jq --argjson r "$bad" '.file_names.roots += [$r]' "$root.json" >"$root.t.json"
  mv "$root.t.json" "$root.json"
  emit "$root" >/dev/null
  assert_eq "a root the gate cannot carry is refused ($bad)" "2" "$?"
done

for filter in '.file_names.regex += "\ntouch PWNED #"' '.file_names.rule += "\ntouch PWNED #"'; do
  root="$(new_fixture)"
  jq "$filter" "$root.json" >"$root.t.json"
  mv "$root.t.json" "$root.json"
  emit "$root" >/dev/null
  assert_eq "a newline in the config is refused ($filter)" "2" "$?"
done

root="$(new_fixture)"
out="$(emit "$root" --rule)"
assert_contains "--rule writes the path-scoped rule" "$out" "EMITTED	.claude/rules/file-names.md"
rule="$(cat "$root/.claude/rules/file-names.md")"
assert_contains "the rule declares the paths it covers" "$rule" "paths: docs/**"
assert_contains "the rule names the gate that actually enforces it" "$rule" "scripts/check-file-names.sh"
assert_absent "no placeholder survives in the rule" "$rule" "@@"
assert_absent "a tree with no index block gets no re-render notice" "$out" "REINDEX"

root="$(new_fixture)"
printf '# Agents\n\n<!-- BEGIN GENERATED: instruction-placement rules index -->\n<!-- END -->\n' \
  >"$root/AGENTS.md"
out="$(emit "$root" --rule)"
assert_contains "an index block gets the re-render notice" "$out" "REINDEX	AGENTS.md"

root="$(new_fixture)"
emit "$root" >/dev/null
out="$(emit "$root")"
rc=$?
assert_eq "a second emission without --force exits 1" "1" "$rc"
assert_contains "the refusal names the existing file" "$out" "scripts/check-file-names.sh' already exists"
assert_contains "and names the remedy" "$out" "--force"

printf 'sentinel\n' >>"$root/scripts/check-file-names.sh"
emit "$root" >/dev/null
assert_contains "a refused run wrote nothing" "$(cat "$root/scripts/check-file-names.sh")" "sentinel"

out="$(emit "$root" --force)"
rc=$?
assert_eq "--force overwrites" "0" "$rc"
assert_absent "the overwritten file is the freshly rendered one" \
  "$(cat "$root/scripts/check-file-names.sh")" "sentinel"

hostile() {
  out="$TEST_TMPDIR/hostile-$CASES-$RANDOM.json"
  jq --arg v "$3" "$2" "$1.json" >"$out"
  printf '%s' "$out"
}

# shellcheck disable=SC2016  # the payload is literal text a jq --arg carries; the jq filters below name $v, jq's variable, not the shell's
root="$(new_fixture)"
marker="$TEST_TMPDIR/PWNED-$RANDOM"
payload='docs/`touch '"$marker"'-tick`/$(touch '"$marker"'-dollar)/**'
cfgfile="$(hostile "$root" '.file_names.exempt_paths = [$v]' "$payload")"
bash "$SUT" --root "$root" --config "$cfgfile" >/dev/null 2>&1
assert_eq "a backtick and a command substitution in an exemption still emit" "0" "$?"
bash "$root/scripts/check-file-names.sh" --check >/dev/null 2>&1
assert_eq "and the emitted gate runs no command substitution" "no" \
  "$([[ -e "$marker-tick" || -e "$marker-dollar" ]] && echo yes || echo no)"
assert_contains "the value survives as a literal" \
  "$(cat "$root/scripts/check-file-names.sh")" "$payload"

root="$(new_fixture)"
cfgfile="$(hostile "$root" '.file_names.exempt_extensions = [$v]' 'md"; echo INJECTED; #')"
bash "$SUT" --root "$root" --config "$cfgfile" >/dev/null 2>&1
assert_eq "a double quote in a list entry still emits" "0" "$?"
bash -n "$root/scripts/check-file-names.sh" 2>/dev/null
assert_eq "and the emitted checker parses" "0" "$?"
bash -n "$root/scripts/check-file-names.test.sh" 2>/dev/null
assert_eq "as does the emitted suite" "0" "$?"

root="$(new_fixture)"
apostrophe="O'REILLY.md"
cfgfile="$(hostile "$root" '.file_names.exempt_basenames = [$v]' "$apostrophe")"
bash "$SUT" --root "$root" --config "$cfgfile" >/dev/null 2>&1
assert_eq "a single quote in a list entry still emits" "0" "$?"
bash -n "$root/scripts/check-file-names.sh" 2>/dev/null
assert_eq "and the emitted checker parses" "0" "$?"
assert_contains "the entry survives intact" \
  "$(cat "$root/scripts/check-file-names.sh")" "$apostrophe"

root="$(new_fixture)"
hostile_re='^[a-z0-9]+([.-][a-z0-9]+)*\.[a-z0-9]+$|^[a-z&|/]+\\[a-z]+\t[a-z]+$'
cfgfile="$(hostile "$root" '.file_names.regex = $v' "$hostile_re")"
bash "$SUT" --root "$root" --config "$cfgfile" >/dev/null 2>&1
emitted_re="$(grep '^NAME_RE=' "$root/scripts/check-file-names.sh")"
assert_eq "the regex reaches the emitted file byte for byte" "NAME_RE='$hostile_re'" "$emitted_re"
assert_eq "no tab was introduced" "0" \
  "$(printf '%s' "$emitted_re" | grep -c "$(printf '\t')")"

root="$(new_fixture)"
marker="$TEST_TMPDIR/ROOTPWN-$RANDOM"
cfgfile="$(hostile "$root" '.file_names.roots = [$v, "docs"]' "do'\$(touch $marker)'cs")"
bash "$SUT" --root "$root" --config "$cfgfile" >/dev/null 2>&1
assert_eq "a quote in a root still emits" "0" "$?"
timeout 120 bash "$root/scripts/check-file-names.test.sh" >/dev/null 2>&1
assert_eq "and running the emitted suite executes no command substitution" "no" \
  "$([[ -e "$marker" ]] && echo yes || echo no)"

root="$(new_fixture)"
cfgfile="$(hostile "$root" '.file_names.rule = $v' '100%s-percent-kebab')"
bash "$SUT" --root "$root" --config "$cfgfile" >/dev/null 2>&1
pct="$TEST_TMPDIR/pct-$RANDOM"
mkdir -p "$pct/docs" "$pct/scripts"
printf '# ok\n' >"$pct/docs/conforming-name.md"
cp "$root/scripts/check-file-names.sh" "$pct/scripts/"
git init -q "$pct"
git -C "$pct" config user.email fixture@example.invalid
git -C "$pct" config user.name Fixture
git -C "$pct" add -A >/dev/null
out="$(bash "$pct/scripts/check-file-names.sh" --check 2>&1)"
assert_contains "a percent in the rule name reaches the message intact" "$out" "100%s-percent-kebab"

root="$(new_fixture)"
cfgfile="$(hostile "$root" '.file_names.regex = $v' '^$')"
out="$(bash "$SUT" --root "$root" --config "$cfgfile" 2>&1)"
rc=$?
assert_eq "a rule no probe name satisfies is refused" "2" "$rc"
assert_contains "the refusal says the suite would have no clean case" "$out" "no probe name"

root="$(new_fixture)"
out="$(emit "$root" --out-dir ../escaped)"
rc=$?
assert_eq "a traversing out-dir is refused" "2" "$rc"
assert_contains "the refusal says why" "$out" "must not leave the root"
assert_eq "and nothing was written outside it" "no" \
  "$([[ -e "$(dirname "$root")/escaped" ]] && echo yes || echo no)"

out="$(emit "$root" --out-dir /abs)"
rc=$?
assert_eq "an absolute out-dir is refused" "2" "$rc"
assert_contains "the refusal says why" "$out" "must be relative to the root"

out="$(emit "$root" --out-dir 'scripts"; touch /tmp/od-pwn; #')"
rc=$?
assert_eq "an out-dir carrying shell metacharacters is refused" "2" "$rc"
assert_contains "the refusal names the character class it allows" "$out" "letters, digits, dot"

root="$(new_fixture)"
printf '{"schema": 1, "file_names": {"roots": ["docs"]}}\n' >"$TEST_TMPDIR/noregex.json"
out="$(bash "$SUT" --root "$root" --config "$TEST_TMPDIR/noregex.json" 2>&1)"
rc=$?
assert_eq "a configuration with no regex exits 2" "2" "$rc"
assert_contains "the reason names the missing key" "$out" "file_names.regex"

out="$(bash "$SUT" --root "$root" --config "$TEST_TMPDIR/does-not-exist.json" 2>&1)"
rc=$?
assert_eq "an unreadable configuration exits 2" "2" "$rc"

out="$(bash "$SUT" --root "$root" --nonsense 2>&1)"
rc=$?
assert_eq "an unknown argument exits 2" "2" "$rc"
assert_contains "the refusal names the argument" "$out" "unknown argument"

root="$(new_fixture)"
out="$(emit "$root" --out-dir tools/gates)"
assert_contains "--out-dir places the checker" "$out" "EMITTED	tools/gates/check-file-names.sh"
assert_contains "the header names the emitted path" \
  "$(sed -n '4p' "$root/tools/gates/check-file-names.sh")" "tools/gates/check-file-names.sh"
# shellcheck disable=SC2016  # the grep pattern is literal: $SCRIPT_DIR is what the emitted file says
assert_contains "the root hop matches the out-dir depth" \
  "$(grep -n 'cd "\$SCRIPT_DIR' "$root/tools/gates/check-file-names.sh")" '../..'
sub="$(bash "$root/tools/gates/check-file-names.sh" --check 2>&1)"
assert_contains "a nested checker still resolves the repository" "$sub" "docs/Alpha-One.md"

printf '\n%d case(s), %d failure(s)\n' "$CASES" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 1
