#!/usr/bin/env bash
# Tests for resolve-config.sh: layer order, list concatenation, scalar
# override, validation exits, hook coverage, and the one path-glob matcher.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG CLAUDE_PROJECT_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVE="$SCRIPT_DIR/resolve-config.sh"
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
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "expected to contain: $3; got: $2"; fi; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
REPO="$T/repo"
mkdir -p "$HOME/.claude" "$REPO/.claude"
git -C "$REPO" init -q

# run [args...]: resolve against $REPO, output in $out, exit code in $rc.
run() {
  rc=0
  out="$(bash "$RESOLVE" --root "$REPO" "$@" 2>&1)" || rc=$?
}
# records <key>: the values of <key>, space-joined, in output order.
records() { awk -F'\t' -v k="$1" '$1 == k { printf "%s%s", s, $2; s = " " }' <<<"$out"; }
reset() { rm -f "$HOME/.claude/testing.yaml" "$REPO/.claude/testing.yaml" "$REPO/.claude/testing.local.yaml"; }

run
assert_eq "no layer file prints nothing" "0:" "$rc:$out"

# --- layer order, list concatenation, scalar override -------------------------
cat >"$HOME/.claude/testing.yaml" <<'EOF'
paths:
  exclude: ['**/*.snap.ts', 'gen/**']
rules:
  rule-zero-assertion: error
EOF
cat >"$REPO/.claude/testing.yaml" <<'EOF'
# team layer
adapters:
  disable: [py-unittest]
paths:
  exclude:
    - 'legacy/**'
    - 'gen/**'
rules:
  testing/audit/rule-weak-oracle: off
EOF
printf "adapters:\r\n  disable: [bash-bats]\r\nrules:\r\n  rule-zero-assertion: warn\r\n" >"$REPO/.claude/testing.local.yaml"
run
assert_eq "resolves with three layers" 0 "$rc"
assert_eq "layers print in cascade order: user, team, overlay" \
  "$HOME/.claude/testing.yaml $REPO/.claude/testing.yaml $REPO/.claude/testing.local.yaml" "$(records layer)"
assert_eq "lists concatenate across layers, first occurrence kept" "**/*.snap.ts gen/** legacy/**" "$(records paths.exclude)"
assert_eq "adapter lists concatenate too (the CRLF overlay loads)" "py-unittest bash-bats" "$(records adapters.disable)"
assert_eq "a later layer's scalar overrides" "warn" "$(records rules.zero-assertion)"
assert_eq "the full rule id resolves to its slug" "off" "$(records rules.weak-oracle)"
mkdir -p "$T/proj/.claude"
printf 'paths:\n  exclude: [proj-only/**]\n' >"$T/proj/.claude/testing.yaml"
rc=0
out="$(CLAUDE_PROJECT_DIR="$T/proj" bash "$RESOLVE" --root "$REPO" 2>&1)" || rc=$?
assert_eq "the team layer is the root's, whatever CLAUDE_PROJECT_DIR names" \
  "$HOME/.claude/testing.yaml $REPO/.claude/testing.yaml $REPO/.claude/testing.local.yaml" "$(records layer)"
rc=0
out="$(cd "$T" && CLAUDE_PROJECT_DIR="$T/proj" bash "$RESOLVE" 2>&1)" || rc=$?
assert_contains "outside a repository with no --root, CLAUDE_PROJECT_DIR is the root" "$(records paths.exclude)" "proj-only/**"

# --- validation exits ---------------------------------------------------------
reset
printf 'paths:\n  exclude: [a]\n  excludes: [b]\n' >"$REPO/.claude/testing.yaml"
run
assert_eq "an unknown key exits 2" 2 "$rc"
assert_contains "and names the file and line" "$out" "$REPO/.claude/testing.yaml:3: unknown key: paths.excludes"
printf 'rules:\n  rule-made-up: off\n' >"$REPO/.claude/testing.yaml"
run
assert_eq "an unknown rule id exits 2" "2" "$rc"
assert_contains "and names it" "$out" "unknown rule: rule-made-up"
printf 'rules:\n  test-weaken-block: error\n' >"$REPO/.claude/testing.yaml"
run
assert_eq "the test-weaken hook's block switch is a rule key" "0:error" "$rc:$(records rules.test-weaken-block)"
printf 'rules:\n  rule-test-weaken-block: warn\n' >"$REPO/.claude/testing.yaml"
run
assert_eq "also spelled rule-test-weaken-block, the form setup apply --rule writes" "0:warn" "$rc:$(records rules.test-weaken-block)"
printf 'rules:\n  test-weaken-block: loud\n' >"$REPO/.claude/testing.yaml"
run
assert_eq "and takes only off, warn or error" 2 "$rc"
printf 'rules:\n  rule-weak-oracle: loud\n' >"$REPO/.claude/testing.yaml"
run
assert_contains "a rule level other than off, warn or error is refused" "$rc $out" "2 "
printf 'adapters:\n  disable: [js-nope]\n' >"$REPO/.claude/testing.yaml"
run
assert_eq "an unknown adapter id exits 2" 2 "$rc"
assert_contains "and names it at its file and line" "$out" "$REPO/.claude/testing.yaml:2: unknown adapter: js-nope"
printf 'adapters:\n  enable:\n    - js-vitest\n    - js-vitset\n' >"$REPO/.claude/testing.yaml"
run --quick
assert_eq "--quick still refuses an unknown adapter id" 2 "$rc"
assert_contains "at its file and line" "$out" "$REPO/.claude/testing.yaml:4: unknown adapter: js-vitset"
printf 'adapter_dirs: [~/adapters]\n' >"$REPO/.claude/testing.yaml"
mkdir -p "$HOME/adapters"
run
assert_eq "a leading ~/ in adapter_dirs is the home directory" "0:$HOME/adapters" "$rc:$(records adapter_dirs)"
printf 'extend:\n  js-vitest:\n    language: [js]\n' >"$REPO/.claude/testing.yaml"
run
assert_eq "extend of a scalar field exits 2" 2 "$rc"
printf 'extend:\n  js-vitest:\n    assertion:\n      calls: [x\\d]\n' >"$REPO/.claude/testing.yaml"
run
assert_eq "an extend regex gets the loader's portability check" 2 "$rc"
assert_contains "at its file and line" "$out" "testing.yaml:4: non-portable regex escape"
printf 'extend:\n  js-nope:\n    files: [x.ts]\n' >"$REPO/.claude/testing.yaml"
run
assert_eq "extend of an unknown adapter exits 2" 2 "$rc"
printf 'paths:\n  exclude:\n    - **/*.test.ts\n' >"$REPO/.claude/testing.yaml"
run
assert_eq "an unquoted glob starting with * exits 2" 2 "$rc"
assert_contains "and says to quote it" "$out" "single-quote"
printf 'adapter_dirs: [missing]\n' >"$REPO/.claude/testing.yaml"
run
assert_eq "an adapter_dirs entry that is not a directory exits 2" 2 "$rc"

# --- extension, consumer adapters and hook coverage ---------------------------
mkdir -p "$REPO/tools/adapters"
cat >"$REPO/tools/adapters/js-spec.yaml" <<'EOF'
id: js-spec
extends: js-vitest
files: ['*.check.ts']
EOF
cat >"$REPO/.claude/testing.yaml" <<'EOF'
adapter_dirs: [tools/adapters]
adapters:
  enable: [js-spec, js-vitest]
extend:
  js-vitest:
    files: ['*.it.ts', '*.test.ts']
paths:
  include: ['e2e/**/*.e2e.ts', 'tests/test_one.py']
EOF
run
assert_eq "a consumer adapter and an extension resolve" 0 "$rc"
assert_eq "adapter_dirs resolves to an absolute directory" "$REPO/tools/adapters" "$(records adapter_dirs)"
assert_eq "extend prints one record per item" "*.it.ts *.test.ts" "$(records extend.js-vitest.files)"
assert_eq "an id from adapter_dirs is a known adapter" "js-spec js-vitest" "$(records adapters.enable)"
assert_eq "every consumer adapter or extend glob no shipped hook row matches is listed" "*.it.ts *.check.ts" "$(records hook.uncovered)"
printf "paths:\n  include: ['legacy/**', 'tests/*.py']\n" >"$REPO/.claude/testing.yaml"
run
assert_eq "a paths.include glob never feeds hook.uncovered" "0:" "$rc:$(records hook.uncovered)"
cat >"$REPO/.claude/testing.yaml" <<'EOF'
adapter_dirs: [tools/adapters]
adapters:
  enable: [js-spec, js-vitest]
extend:
  js-vitest:
    files: ['*.it.ts', '*.test.ts']
EOF
run --quick
assert_eq "--quick prints the same records" "*.it.ts *.test.ts" "$(records extend.js-vitest.files)"
assert_eq "without the hook coverage the scanner's hook path does not need" "" "$(records hook.uncovered)"

# --- the path-glob matcher ----------------------------------------------------
match() {
  local want="$1" glob="$2" path="$3" got=0
  bash "$RESOLVE" match "$glob" "$path" || got=1
  assert_eq "match '$glob' '$path'" "$want" "$got"
}
match 0 '**/*.test.ts' 'a.test.ts'
match 0 '**/*.test.ts' 'src/deep/a.test.ts'
match 1 '*.test.ts' 'src/a.test.ts'
match 0 'src/**' 'src/a/b.ts'
match 0 'src/**/b.ts' 'src/b.ts'
match 1 'src/?.ts' 'src/ab.ts'
match 1 'src/a?b.ts' 'src/a/b.ts'
match 1 '*.test.ts' 'axtest.ts'
match 0 'src/**/*.test.ts' 'src\deep\a.test.ts'
match 0 '/c/repo/*.ts' 'C:\repo\a.ts'
match 0 'src/*.ts' './src/a.ts'
match 0 'src/[x].ts' 'src/[x].ts'
match 1 'src/[x].ts' 'src/x.ts'

# --- a repository layer that is a symlink is refused ----------------------------
reset
printf 'paths:\n  exclude: [secret]\n' >"$T/foreign.yaml"
ln -s ../../foreign.yaml "$REPO/.claude/testing.yaml"
run
assert_eq "a symlinked team layer exits 2" 2 "$rc"
assert_contains "and names it" "$out" "$REPO/.claude/testing.yaml"
assert_eq "without parsing the file it points at" "" "$(grep -F secret <<<"$out")"
rm -f "$REPO/.claude/testing.yaml"
mv "$REPO/.claude" "$T/real-claude"
ln -s ../real-claude "$REPO/.claude"
cp "$T/foreign.yaml" "$T/real-claude/testing.local.yaml"
run
assert_eq "a layer under a symlinked .claude exits 2" 2 "$rc"
rm "$REPO/.claude" "$T/real-claude/testing.local.yaml"
mv "$T/real-claude" "$REPO/.claude"

# --- the whole suite again under mawk -----------------------------------------
if [[ -z "${TCFG_TEST_MAWK_LEG:-}" ]] && command -v mawk >/dev/null 2>&1; then
  mkdir -p "$T/mawk-shim"
  ln -sf "$(command -v mawk)" "$T/mawk-shim/awk"
  rc=0
  mawk_out="$(TCFG_TEST_MAWK_LEG=1 PATH="$T/mawk-shim:$PATH" bash "${BASH_SOURCE[0]}" 2>&1)" || rc=$?
  assert_eq "the whole suite passes under mawk" 0 "$rc"
  [[ "$rc" -eq 0 ]] || printf '%s\n' "$mawk_out" | grep -A1 '^FAIL' >&2
fi

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
