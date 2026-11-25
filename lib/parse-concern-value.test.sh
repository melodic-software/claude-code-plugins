#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/parse-concern-value.sh"

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
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: [$2], actual: [$3]"; fi
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

resolve() {
  local content="$1" key="${2:-memory_dir}" fallback="${3:-}"
  local f="$TEST_TMPDIR/concern.yaml"
  printf '%s\n' "$content" >"$f"
  bash "$SCRIPT" "$f" "$key" "$fallback"
}

rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

assert_eq 'double-quoted a#b keeps the #' "a#b" "$(resolve 'memory_dir: "a#b"')"
assert_eq 'single-quoted a#b keeps the #' "a#b" "$(resolve "memory_dir: 'a#b'")"
assert_eq 'unquoted .work/#topic keeps the #' ".work/#topic" "$(resolve 'memory_dir: .work/#topic')"
assert_eq 'quoted value with trailing comment drops comment, keeps inner #' \
  "a#b" "$(resolve 'memory_dir: "a#b"  # inline comment')"

assert_eq 'space before the colon resolves' ".scratch" "$(resolve 'memory_dir : .scratch')"
assert_eq 'indented root mapping resolves' ".scratch" "$(resolve '  memory_dir: .scratch')"
assert_eq 'a tab-indented key is a parse error, so it reads as unset' "" "$(resolve "$(printf '\tmemory_dir: .scratch')")"
assert_eq 'space before colon does not defeat the fallback path' \
  ".notes" "$(resolve 'memory_dir :' memory_dir '.notes')"
assert_eq 'root key wins over a nested one' "top" \
  "$(resolve "$(printf 'other:\n  memory_dir: nested\nmemory_dir: top')")"
assert_eq 'a nested key never answers for an empty root key' ".notes" \
  "$(resolve "$(printf 'other:\n  memory_dir: nested\nmemory_dir:')" memory_dir '.notes')"
assert_eq 'a nested key never answers for an absent root key' ".notes" \
  "$(resolve "$(printf 'other:\n  memory_dir: nested\n')" memory_dir '.notes')"
assert_eq 'a key deeper than an indented root mapping is still nested' ".notes" \
  "$(resolve "$(printf '  other:\n    memory_dir: nested\n  other_key: docs/x')" memory_dir '.notes')"
assert_eq 'a YAML directive is a parse error, so it reads as unset' ".notes" \
  "$(resolve "$(printf -- '%%YAML 1.2\n  memory_dir: .scratch')" memory_dir .notes 2>/dev/null)"
assert_eq 'a leading document marker is a parse error, so it reads as unset' ".notes" \
  "$(resolve "$(printf -- '---\nmemory_dir: .scratch')" memory_dir .notes 2>/dev/null)"
assert_eq 'a decorated document marker is a parse error, so it reads as unset' ".notes" \
  "$(resolve "$(printf -- '--- # generated file\n  memory_dir: .scratch')" memory_dir .notes 2>/dev/null)"
assert_eq 'a leading comment does not become the base indent' ".scratch" \
  "$(resolve "$(printf -- '# committed, team-shared\n  memory_dir: .scratch')")"
assert_eq 'a longer key is not matched by a shorter one' \
  ".notes" "$(resolve 'memory_dir_extra: .scratch' memory_dir '.notes')"

assert_eq 'written_against and provenance beside a key return its value' "$(resolve 'memory_dir: .scratch')" \
  "$(resolve "$(printf 'written_against: fixture@1.2.0\nmemory_dir: .scratch\nprovenance:\n  memory_dir: chosen (default .work)')")"
assert_eq 'written_against and provenance beside a key: the value is .scratch' ".scratch" \
  "$(resolve "$(printf 'written_against: fixture@1.2.0\nmemory_dir: .scratch\nprovenance:\n  memory_dir: chosen (default .work)')")"

assert_eq 'unquoted trailing comment stripped' ".scratch" "$(resolve 'memory_dir: .scratch  # the tier')"

assert_eq 'leading/trailing whitespace trimmed (unquoted)' ".scratch" "$(resolve 'memory_dir:    .scratch   ')"

assert_eq 'quoted interior space preserved' ".scratch dir" "$(resolve 'memory_dir: ".scratch dir"')"

assert_eq 'trailing slash normalized (unquoted)' ".work" "$(resolve 'memory_dir: .work/')"
assert_eq 'trailing slash normalized (quoted)' "foo/bar" "$(resolve 'memory_dir: "foo/bar/"')"

assert_eq 'absent key returns fallback (declared fallback)' \
  ".notes" "$(resolve 'other_key: x' memory_dir '.notes')"
assert_eq 'empty value returns fallback' \
  ".notes" "$(resolve 'memory_dir:' memory_dir '.notes')"
assert_eq 'comment-only value falls back (memory_dir: # use default)' \
  ".notes" "$(resolve 'memory_dir: # use default' memory_dir '.notes')"
assert_eq 'comment-only value, no fallback => empty' \
  "" "$(resolve 'memory_dir: # use default')"
assert_eq 'fallback is trailing-slash-agnostic passthrough' \
  ".notes/deep" "$(resolve 'other_key: x' memory_dir '.notes/deep')"

assert_eq 'missing file, no fallback => empty' "" "$(bash "$SCRIPT" "$TEST_TMPDIR/nope.yaml" memory_dir)"
assert_eq 'missing file, with fallback => fallback' ".x" "$(bash "$SCRIPT" "$TEST_TMPDIR/nope.yaml" memory_dir '.x')"

assert_eq 'present key overrides fallback' ".real" "$(resolve 'memory_dir: .real' memory_dir '.fallback')"

assert_eq 'no key, no fallback => empty' "" "$(resolve 'other_key: x')"

rc=0
bash "$SCRIPT" >/dev/null 2>&1 || rc=$?
assert_exit "no args exits 2" 2 "$rc"

EX="$SCRIPT_DIR/../docs/conventions/pr-pipeline/examples/claude-code-plugins.yaml"
assert_eq 'nested key merge.rung (example :201)' "merge" "$(bash "$SCRIPT" "$EX" merge.rung)"
assert_eq '--list prints a flow list one item per line, quotes removed (example :207)' \
  $'.github/**\n.claude/**\ndocs/conventions/pr-pipeline.yaml' \
  "$(bash "$SCRIPT" "$EX" merge.diff-check.denied-paths --list)"
assert_eq 'a block sequence of mappings is indexed (example :143)' "merge" \
  "$(bash "$SCRIPT" "$EX" lanes.pr-merge.slots.0.activity)"
assert_eq 'an absent nested key takes the fallback' "true" \
  "$(bash "$SCRIPT" "$EX" lanes.pr-merge.slots.0.enabled true)"
assert_eq 'a later key of a sequence item (example :152)' "false" \
  "$(bash "$SCRIPT" "$EX" lanes.post-merge-sweep-comments.slots.0.enabled true)"
assert_eq 'a flow list inside a sequence item (example :111)' "run-tests" \
  "$(bash "$SCRIPT" "$EX" lanes.pr-run-checks.slots.1.needs --list)"
assert_eq 'one item of a flow list by index (example :80)' "base-sha" \
  "$(bash "$SCRIPT" "$EX" activities.resolve-conflicts.inputs.1)"
assert_eq 'a quoted glob in a flow list (example :19)' '**/*.md' \
  "$(bash "$SCRIPT" "$EX" activities.fix-docs.applies-when.paths --list)"
assert_eq 'a list key read as a scalar is absent' ".none" \
  "$(bash "$SCRIPT" "$EX" merge.diff-check.denied-paths .none)"
assert_eq '--list on an absent key prints the fallback' "x" \
  "$(bash "$SCRIPT" "$EX" merge.nope --list x)"

assert_eq 'a flow mapping inside a flow list is a parse error, so it reads as unset' ".none" \
  "$(resolve 'x: [{a: 1}, "r, s"]' x.1 .none 2>/dev/null)"
assert_eq 'a quoted comma stays inside its item' "r, s" \
  "$(resolve 'x: [p, "r, s"]' x.1)"
printf 'k:\n- a\n- b\nz: 1\n' >"$TEST_TMPDIR/indentless.yaml"
assert_eq 'a sequence at its key indent is still the key value' $'a\nb' \
  "$(bash "$SCRIPT" "$TEST_TMPDIR/indentless.yaml" k --list)"
assert_eq 'a root key after such a sequence is still a root key' "1" \
  "$(bash "$SCRIPT" "$TEST_TMPDIR/indentless.yaml" z)"

assert_eq 'stdin form equals the file form' "$(bash "$SCRIPT" "$EX" merge.rung)" \
  "$(bash "$SCRIPT" - merge.rung <"$EX")"

esc() { printf '%b' "$1" >"$TEST_TMPDIR/esc.yaml"; shift; bash "$SCRIPT" --strict "$TEST_TMPDIR/esc.yaml" "$@" 2>&1; }
assert_eq "a doubled single quote is one quote" "it's" "$(esc "a: 'it''s'\nb: 2\n" a)"
assert_eq "a sibling of an escaped value still reads" "2" "$(esc "a: 'it''s'\nb: 2\n" b FB)"
assert_eq 'a backslash-escaped double quote' 'x "y"' "$(esc 'a: "x \\"y\\""\n' a)"
assert_eq 'an escaped backslash' 'p\q' "$(esc 'a: "p\\\\q"\n' a)"
assert_eq 'a trailing comment after an escaped value is dropped' "it's" "$(esc "a: 'it''s' # note\n" a)"
assert_eq 'escapes inside a flow list' $'it\'s\nx "y"\na,b' \
  "$(esc "l: ['it''s', \"x \\\\\"y\\\\\"\", \"a,b\"]\n" l --list)"
assert_eq 'a quoted key with an escape does not break the file' "2" "$(esc "'it''s': 1\nb: 2\n" b FB)"
assert_eq 'a double-quoted root key reads' ".x" "$(esc '"memory_dir": .x\n' memory_dir)"
assert_eq 'a sibling of quoted nested keys' "w" "$(esc "m:\n  \"k\": v\n  'q''r': w\n  z: 'w'\n" m.z)"
assert_eq 'a double-quoted nested key' "v" "$(esc "m:\n  \"k\": v\n" m.k)"
assert_eq 'a quoted key on a sequence item' "n1" "$(esc 's:\n  - "name": n1\n' s.0.name)"

printf 'memory_dir: .x\nk: [a, b\n' >"$TEST_TMPDIR/unclosed.yaml"
printf 'memory_dir: .x\nother:\n\tb: c\n' >"$TEST_TMPDIR/tab.yaml"
for f in unclosed tab; do
  rc=0
  out=$(bash "$SCRIPT" "$TEST_TMPDIR/$f.yaml" memory_dir .fb 2>"$TEST_TMPDIR/err") || rc=$?
  assert_exit "$f: default mode exits 0" 0 "$rc"
  assert_eq "$f: default mode prints the fallback" ".fb" "$out"
  assert_eq "$f: default mode writes one stderr line" "1" "$(wc -l <"$TEST_TMPDIR/err" | tr -d ' ')"
  rc=0
  out=$(bash "$SCRIPT" "$TEST_TMPDIR/$f.yaml" memory_dir 2>/dev/null) || rc=$?
  assert_eq "$f: default mode with no fallback prints nothing" "" "$out"
  rc=0
  bash "$SCRIPT" --strict "$TEST_TMPDIR/$f.yaml" memory_dir .fb >/dev/null 2>&1 || rc=$?
  assert_exit "$f: --strict exits 3" 3 "$rc"
done
printf 'merge:\n  rung: C1\n  rung: C2\n' >"$TEST_TMPDIR/dup.yaml"
rc=0
out=$(bash "$SCRIPT" "$TEST_TMPDIR/dup.yaml" merge.rung .fb 2>/dev/null) || rc=$?
assert_exit 'duplicate key: default mode exits 0' 0 "$rc"
assert_eq 'duplicate key: default mode takes the fallback' ".fb" "$out"
rc=0
out=$(bash "$SCRIPT" --strict "$TEST_TMPDIR/dup.yaml" merge.rung .fb 2>"$TEST_TMPDIR/err") || rc=$?
assert_exit 'duplicate key: --strict exits 3' 3 "$rc"
assert_eq 'duplicate key: --strict names the second line' "parse-concern-value: $TEST_TMPDIR/dup.yaml: line 3: duplicate key \`merge.rung\` (first at line 2)" "$(cat "$TEST_TMPDIR/err")"
rc=0
out=$(bash "$SCRIPT" --strict "$EX" merge.rung) || rc=$?
assert_exit '--strict on a clean file exits 0' 0 "$rc"
assert_eq '--strict on a clean file prints the value' "merge" "$out"
assert_eq '--strict on a missing file prints the fallback' ".x" \
  "$(bash "$SCRIPT" --strict "$TEST_TMPDIR/nope.yaml" memory_dir .x)"

# --- --ref: validated before any git call; passed after --end-of-options ---
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1
FAKE_BIN="$TEST_TMPDIR/fakebin"
mkdir -p "$FAKE_BIN"
export FAKE_GIT_LOG="$TEST_TMPDIR/git-calls"
# shellcheck disable=SC2016 # the fake git body is written literally.
{
  printf '#!/usr/bin/env bash\n'
  printf 'printf "%%s\\n" "$*" >>"$FAKE_GIT_LOG"\n'
  printf '[[ "$1" == show ]] && printf "rung: C4\\n"\n'
  printf 'exit 0\n'
} >"$FAKE_BIN/git"
chmod +x "$FAKE_BIN/git"
# shellcheck disable=SC2016 # hostile refs are literal strings.
for ref in '--output=x' '-p' 'HEAD:../x' 'origin/../x' 'a b' '' 'origin/-p' 'origin/' \
  'origin/a..b' 'origin/$(touch pwned)' 'deadbeef'; do
  rm -f "$FAKE_GIT_LOG"
  rc=0
  (cd "$TEST_TMPDIR" && PATH="$FAKE_BIN:$PATH" bash "$SCRIPT" --ref "$ref" x.yaml rung >/dev/null 2>&1) || rc=$?
  assert_exit "hostile ref [$ref] exits 2" 2 "$rc"
  if [[ -e "$FAKE_GIT_LOG" ]]; then fail "hostile ref [$ref] makes no git call" "git was called"; else pass "hostile ref [$ref] makes no git call"; fi
done
if [[ -e "$TEST_TMPDIR/pwned" ]]; then fail 'a ref is never evaluated' "pwned exists"; else pass 'a ref is never evaluated'; fi
rm -f "$FAKE_GIT_LOG"
sha40=0123456789abcdef0123456789abcdef01234567
out=$(PATH="$FAKE_BIN:$PATH" bash "$SCRIPT" --ref "$sha40" x.yaml rung)
assert_eq 'a 40-hex ref reads through git show' "C4" "$out"
assert_contains 'git show gets the ref after --end-of-options' "$(cat "$FAKE_GIT_LOG")" \
  "show --end-of-options $sha40:x.yaml"
rc=0
PATH="$FAKE_BIN:$PATH" bash "$SCRIPT" --ref "$sha40" - rung </dev/null >/dev/null 2>&1 || rc=$?
assert_exit '--ref with stdin is a usage error' 2 "$rc"

REPO="$TEST_TMPDIR/repo"
git init -q "$REPO"
git -C "$REPO" config user.email t@example.invalid
git -C "$REPO" config user.name t
git -C "$REPO" config commit.gpgsign false
mkdir -p "$REPO/docs/conventions"
printf 'rung: C3\n' >"$REPO/docs/conventions/x.yaml"
git -C "$REPO" add docs/conventions/x.yaml
git -C "$REPO" commit -q -m fixture
sha=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" update-ref refs/remotes/origin/main "$sha"
printf 'rung: C9\n' >"$REPO/docs/conventions/x.yaml"
assert_eq 'a commit ref reads the committed file' "C3" \
  "$(cd "$REPO" && bash "$SCRIPT" --ref "$sha" docs/conventions/x.yaml rung)"
assert_eq 'an origin/<name> ref reads the committed file' "C3" \
  "$(cd "$REPO" && bash "$SCRIPT" --ref origin/main docs/conventions/x.yaml rung)"
assert_eq 'a path absent at the ref takes the fallback' ".fb" \
  "$(cd "$REPO" && bash "$SCRIPT" --ref origin/main docs/conventions/none.yaml rung .fb)"
rc=0
(cd "$REPO" && bash "$SCRIPT" --ref origin/nope docs/conventions/x.yaml rung >/dev/null 2>&1) || rc=$?
assert_exit 'a well-formed ref that does not resolve exits 2' 2 "$rc"

printf 'bug_path:\n  fix_gate:\n    scope:\n      - src/report/\n      - tests/report\n' \
  >"$REPO/docs/conventions/work-items.yaml"
git -C "$REPO" add docs/conventions/work-items.yaml
git -C "$REPO" commit -q -m scope
git -C "$REPO" update-ref refs/remotes/origin/main "$(git -C "$REPO" rev-parse HEAD)"
printf 'bug_path:\n  fix_gate:\n    scope: [elsewhere]\n' >"$REPO/docs/conventions/work-items.yaml"
assert_eq '--list --ref resolves a nested scope list to its committed paths' $'src/report\ntests/report' \
  "$(cd "$REPO" && bash "$SCRIPT" --list --ref origin/main docs/conventions/work-items.yaml bug_path.fix_gate.scope)"
assert_eq 'the same list key read without --list is empty' "" \
  "$(cd "$REPO" && bash "$SCRIPT" --ref origin/main docs/conventions/work-items.yaml bug_path.fix_gate.scope)"

rc=0
(cd "$TEST_TMPDIR" && bash "$SCRIPT" "$EX" 'a$(touch pwned2)' >/dev/null 2>&1) || rc=$?
assert_exit 'a key outside [A-Za-z0-9_.-] exits 2' 2 "$rc"
evil="$TEST_TMPDIR/\$(touch pwned3).yaml"
printf 'memory_dir: .evil\n' >"$evil"
# shellcheck disable=SC2016 # a literal name.
assert_eq 'a file name holding $(...) is read as a name' ".evil" \
  "$(cd "$TEST_TMPDIR" && BASH_COMPAT=51 bash "$SCRIPT" "$evil" memory_dir)"
if [[ -e "$TEST_TMPDIR/pwned2" || -e "$TEST_TMPDIR/pwned3" ]]; then
  fail 'no name is evaluated' "a pwned file exists"
else
  pass 'no name is evaluated'
fi

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
