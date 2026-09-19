#!/usr/bin/env bash
# Self-contained tests for emit-gate.sh, driven against the committed fixture
# tree the audit sibling owns (fixtures/build-fixture.sh in audit-file-names).
#
# The emitted artifacts are RUN here, not just diffed. A renderer is only as
# good as the script it produces, and a template that renders cleanly into a
# file bash then refuses is the exact failure a text comparison misses.
#
# Template basenames named for the affected-tests mapping: this suite covers
# check-file-names.sh.tmpl, check-file-names.test.sh.tmpl, and
# file-names-rule.md.tmpl.
#
# Every single-quoted `$v` below is a jq program argument naming jq's own
# variable, and every single-quoted backtick or `$(...)` is the literal payload
# of an injection case. None is a shell expansion.
# shellcheck disable=SC2016
#
# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/emit-gate.sh"
BUILD="$SCRIPT_DIR/../../audit-file-names/scripts/fixtures/build-fixture.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASES=0

pass() {
  CASES=$((CASES + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  CASES=$((CASES + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}

assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}

assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}

assert_absent() {
  case "$2" in
  *"$3"*) fail "$1" "does NOT contain: $3" "$2" ;;
  *) pass "$1" ;;
  esac
}

new_fixture() {
  d="$TEST_TMPDIR/fx-$CASES-$RANDOM"
  bash "$BUILD" "$d" >/dev/null
  printf '%s' "$d"
}

emit() {
  root="$1"
  shift
  bash "$SUT" --root "$root" --config "$root/.claude/docs-hygiene.json" "$@" 2>&1
}

# --- emission ----------------------------------------------------------------

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

# --- the emitted checker against the three contract dimensions ---------------
#
# Exit code, which stream the output went to, and what the message says. A
# checker that gets the code right and the stream wrong still breaks every
# caller that pipes it.

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

# BASH is resolved before PATH is replaced, or the stub would hide the
# interpreter as well as git and the case would prove nothing.
BASH_BIN="$(command -v bash)"
stub="$TEST_TMPDIR/nogit-$RANDOM"
mkdir -p "$stub"
out="$(PATH="$stub" "$BASH_BIN" "$clean/scripts/check-file-names.sh" --check 2>&1)"
rc=$?
assert_eq "git hidden from PATH exits 2" "2" "$rc"
assert_contains "the reason names git" "$out" "git is required"

pass "emitted checker passes the three contract dimensions"

# --- the emitted suite runs against the emitted checker -----------------------

out="$(timeout 300 bash "$root/scripts/check-file-names.test.sh" 2>&1)"
rc=$?
assert_eq "the emitted suite exits 0" "0" "$rc"
assert_contains "and reports no failures" "$out" "0 failure(s)"
assert_contains "it exercises the exemptions the config declares" "$out" "the exempt basename README.md"
assert_contains "and the case-collision pass" "$out" "differing only by case"

# --- shellcheck over what was emitted ----------------------------------------

# Under THIS repository's rcfile, not shellcheck's defaults. The emitted pair
# lands in a consumer that lints it with its own configuration, and the strict
# options here (a `set -e` suppression, `[[ ]]` over `[ ]`, a default case) are
# exactly the ones a bare run does not enable. A bare run passed this pair while
# the repository's own lint lane would have rejected it.
if command -v shellcheck >/dev/null 2>&1; then
  RC_FILE="$SCRIPT_DIR/../../../../../.shellcheckrc"
  sc_args=(-x)
  [[ -f "$RC_FILE" ]] && sc_args+=("--rcfile=$RC_FILE")
  sc="$(shellcheck "${sc_args[@]}" "$root/scripts/check-file-names.sh" "$root/scripts/check-file-names.test.sh" 2>&1)"
  assert_eq "shellcheck is clean on the emitted pair under this repo's rcfile" "" "$sc"
else
  printf 'SKIP: shellcheck not installed\n'
fi

# --- --rule -------------------------------------------------------------------

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

# --- overwrite refusal --------------------------------------------------------

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

# --- a configuration value is untrusted text ---------------------------------
#
# These are the discriminating cases for the three hazards the emitter's header
# names. A fixture whose regex carries no metacharacter cannot tell a literal
# renderer from a `sed` one, so each case below uses a value that WOULD break
# the wrong implementation. Every hostile value is built with `jq --arg` rather
# than spliced into a shell string, so this suite's own quoting cannot be what
# a case is really testing.

# hostile <root> <jq-filter> <arg-value> : write a variant config, print its path
hostile() {
  out="$TEST_TMPDIR/hostile-$CASES-$RANDOM.json"
  jq --arg v "$3" "$2" "$1/.claude/docs-hygiene.json" >"$out"
  printf '%s' "$out"
}

# A backtick and a `$(...)` in an exemption. Under a double-quoted splice each
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

# A double quote in a list entry. Under a double-quoted splice this closes the
# string and the emitted file stops parsing.
root="$(new_fixture)"
cfgfile="$(hostile "$root" '.file_names.exempt_extensions = [$v]' 'md"; echo INJECTED; #')"
bash "$SUT" --root "$root" --config "$cfgfile" >/dev/null 2>&1
assert_eq "a double quote in a list entry still emits" "0" "$?"
bash -n "$root/scripts/check-file-names.sh" 2>/dev/null
assert_eq "and the emitted checker parses" "0" "$?"
bash -n "$root/scripts/check-file-names.test.sh" 2>/dev/null
assert_eq "as does the emitted suite" "0" "$?"

# A single quote, the one character the single-quoting must handle itself
# rather than merely rely on.
root="$(new_fixture)"
apostrophe="O'REILLY.md"
cfgfile="$(hostile "$root" '.file_names.exempt_basenames = [$v]' "$apostrophe")"
bash "$SUT" --root "$root" --config "$cfgfile" >/dev/null 2>&1
assert_eq "a single quote in a list entry still emits" "0" "$?"
bash -n "$root/scripts/check-file-names.sh" 2>/dev/null
assert_eq "and the emitted checker parses" "0" "$?"
assert_contains "the entry survives intact" \
  "$(cat "$root/scripts/check-file-names.sh")" "$apostrophe"

# A regex carrying a doubled backslash and a literal backslash-t. awk's `-v`
# halves the first and turns the second into a TAB; the environment channel
# does neither.
# The fixture's own rule with a metacharacter-carrying branch bolted on, so the
# probe names still resolve and the case is about the channel, not the rule.
root="$(new_fixture)"
hostile_re='^[a-z0-9]+([.-][a-z0-9]+)*\.[a-z0-9]+$|^[a-z&|/]+\\[a-z]+\t[a-z]+$'
cfgfile="$(hostile "$root" '.file_names.regex = $v' "$hostile_re")"
bash "$SUT" --root "$root" --config "$cfgfile" >/dev/null 2>&1
emitted_re="$(grep '^NAME_RE=' "$root/scripts/check-file-names.sh")"
assert_eq "the regex reaches the emitted file byte for byte" "NAME_RE='$hostile_re'" "$emitted_re"
assert_eq "no tab was introduced" "0" \
  "$(printf '%s' "$emitted_re" | grep -c "$(printf '\t')")"

# A single quote in the PRIMARY ROOT, which lands in a single-quoted assignment
# in the emitted SUITE rather than in the checker's arrays. `bash -n` accepts
# the broken-out result, so the parse gate cannot catch this one: only escaping
# can.
root="$(new_fixture)"
marker="$TEST_TMPDIR/ROOTPWN-$RANDOM"
cfgfile="$(hostile "$root" '.file_names.roots = [$v, "docs"]' "do'\$(touch $marker)'cs")"
bash "$SUT" --root "$root" --config "$cfgfile" >/dev/null 2>&1
assert_eq "a quote in a root still emits" "0" "$?"
timeout 120 bash "$root/scripts/check-file-names.test.sh" >/dev/null 2>&1
assert_eq "and running the emitted suite executes no command substitution" "no" \
  "$([[ -e "$marker" ]] && echo yes || echo no)"

# A `%` in the rule name. Spliced into a printf FORMAT it would be read as a
# conversion and eat the arguments after it.
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

# A rule the emitted suite could not probe. Refused at emission rather than
# handed over as a suite that fails on its own clean fixture.
root="$(new_fixture)"
cfgfile="$(hostile "$root" '.file_names.regex = $v' '^$')"
out="$(bash "$SUT" --root "$root" --config "$cfgfile" 2>&1)"
rc=$?
assert_eq "a rule no probe name satisfies is refused" "2" "$rc"
assert_contains "the refusal says the suite would have no clean case" "$out" "no probe name"

# --- an out-dir stays inside the root ----------------------------------------

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

# The out-dir lands in a double-quoted path inside the emitted checker, so shell
# metacharacters in it would reach that file as shell.
out="$(emit "$root" --out-dir 'scripts"; touch /tmp/od-pwn; #')"
rc=$?
assert_eq "an out-dir carrying shell metacharacters is refused" "2" "$rc"
assert_contains "the refusal names the character class it allows" "$out" "letters, digits, dot"

# --- configuration refusals ---------------------------------------------------

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

# --- --out-dir ----------------------------------------------------------------

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

# --- results ------------------------------------------------------------------

printf '\n%d case(s), %d failure(s)\n' "$CASES" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 1
