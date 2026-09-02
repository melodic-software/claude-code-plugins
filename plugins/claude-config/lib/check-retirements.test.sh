#!/usr/bin/env bash
# Self-contained tests for lib/check-retirements.sh (no external test lib — ships with the plugin).
#
# The copies in carrying plugins are byte-identical and registered in
# scripts/cross-plugin-source-registry.txt, so this suite covers all of them.
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git rev-parse` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-retirements.sh"
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
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3 -- got: $2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3" ;;
  *) pass "$1" ;;
  esac
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_file_eq() {
  # assert_file_eq <label> <expected-file> <actual-file> — byte-for-byte
  if cmp -s "$2" "$3"; then pass "$1"; else fail "$1" "files differ: $(od -c "$3" | head -5)"; fi
}

# mkrepo <name> — echo a fresh fixture root (a git repo when git is present,
# so the default-root rung can be exercised; a plain directory otherwise).
mkrepo() {
  local d="$TEST_TMPDIR/$1"
  mkdir -p "$d"
  if command -v git >/dev/null 2>&1; then
    git -C "$d" init -q 2>/dev/null
  fi
  printf '%s' "$d"
}

# manifest <path> — write stdin (a heredoc) to <path>.
manifest() { cat >"$1"; }

# run <args...> — OUT/ERR/RC come back through globals, not stdout: a command
# substitution would run this in a subshell and RC would silently keep the
# previous case's value.
OUT=""
ERR=""
RC=0
run() {
  OUT="$(bash "$SCRIPT" "$@" 2>"$TEST_TMPDIR/err")"
  RC=$?
  ERR="$(cat "$TEST_TMPDIR/err")"
}

# A well-formed record template, one field overridden per malformed case.
good_record() {
  # good_record <id> <kind> <path> <action> [extra lines...]
  printf 'id: %s\nretired: 2026-09-01\nplugin_version: 1.2.3\nkind: %s\npath: %s\naction: %s\nnote: fixture record\n' "$1" "$2" "$3" "$4"
  shift 4
  local extra
  for extra in "$@"; do printf '%s\n' "$extra"; done
}

# --- Case 1: --help exits 0 ---------------------------------------------------
run --help
assert_exit "case 1: --help exits 0" 0 "$RC"
assert_contains "case 1: --help prints usage" "$OUT" "Usage:"
run -h
assert_exit "case 1: -h exits 0" 0 "$RC"

# --- Case 2: usage errors exit 2 ----------------------------------------------
r="$(mkrepo usage)"
m="$TEST_TMPDIR/usage.yaml"
good_record fx-r001 file .claude/old.json delete | manifest "$m"
run
assert_exit "case 2: no --manifest exits 2" 2 "$RC"
run --manifest "$TEST_TMPDIR/does-not-exist.yaml" --root "$r"
assert_exit "case 2: missing manifest exits 2" 2 "$RC"
run --manifest "$m" --root "$TEST_TMPDIR/no-such-root"
assert_exit "case 2: missing --root exits 2" 2 "$RC"
run --manifest "$m" --root "$r" --nope
assert_exit "case 2: unknown argument exits 2" 2 "$RC"
run --manifest "$m" --root "$r" --i-migrated
assert_exit "case 2: --i-migrated without --clean exits 2" 2 "$RC"
run --manifest "$m" --root "$r" --clean
assert_exit "case 2: --clean with no id exits 2" 2 "$RC"
run --manifest
assert_exit "case 2: --manifest with no value exits 2" 2 "$RC"

# --- Case 3: kind file — hit, TSV shape, miss ---------------------------------
r="$(mkrepo file-kind)"
mkdir -p "$r/.claude"
printf '{}\n' >"$r/.claude/old.json"
m="$TEST_TMPDIR/file.yaml"
good_record fx-r001 file .claude/old.json delete | manifest "$m"
run --manifest "$m" --root "$r"
assert_exit "case 3: present file is an active leftover (exit 1)" 1 "$RC"
assert_eq "case 3: one TSV row" "1" "$(printf '%s\n' "$OUT" | grep -c .)"
assert_eq "case 3: TSV row has 6 columns" "6" "$(printf '%s\n' "$OUT" | awk -F '\t' '{ print NF }')"
assert_eq "case 3: TSV row content" "$(printf 'fx-r001\tfile\t.claude/old.json\tdelete\tactive\tfixture record')" "$OUT"
assert_contains "case 3: stderr summary counts the active hit" "$ERR" "1 active leftover(s)"
rm "$r/.claude/old.json"
run --manifest "$m" --root "$r"
assert_exit "case 3: absent file exits 0" 0 "$RC"
assert_eq "case 3: absent file prints no row" "" "$OUT"
mkdir -p "$r/.claude/old.json"
run --manifest "$m" --root "$r"
assert_exit "case 3: a directory at a file record's path is not a hit" 0 "$RC"

# --- Case 4: kind dir — hit and miss ------------------------------------------
r="$(mkrepo dir-kind)"
mkdir -p "$r/.claude/scratch"
m="$TEST_TMPDIR/dir.yaml"
good_record fx-r001 dir .claude/scratch delete | manifest "$m"
run --manifest "$m" --root "$r"
assert_exit "case 4: present dir exits 1" 1 "$RC"
assert_contains "case 4: dir row names the kind" "$OUT" "$(printf '\tdir\t')"
rmdir "$r/.claude/scratch"
run --manifest "$m" --root "$r"
assert_exit "case 4: absent dir exits 0" 0 "$RC"
printf 'x' >"$r/.claude/scratch"
run --manifest "$m" --root "$r"
assert_exit "case 4: a file at a dir record's path is not a hit" 0 "$RC"

# --- Case 5: kind line — hit and miss (LF file) -------------------------------
r="$(mkrepo line-kind)"
printf 'node_modules/\n.claude/scratch/\ndist/\n' >"$r/.gitignore"
m="$TEST_TMPDIR/line.yaml"
good_record fx-r001 line .gitignore remove-line 'match: "^\.claude/scratch/$"' | manifest "$m"
run --manifest "$m" --root "$r"
assert_exit "case 5: matching line exits 1" 1 "$RC"
assert_contains "case 5: line row names remove-line" "$OUT" "$(printf '\tremove-line\t')"
printf 'node_modules/\ndist/\n' >"$r/.gitignore"
run --manifest "$m" --root "$r"
assert_exit "case 5: no matching line exits 0" 0 "$RC"
rm "$r/.gitignore"
run --manifest "$m" --root "$r"
assert_exit "case 5: missing file for a line record exits 0" 0 "$RC"

# --- Case 6: content_match guards a reused path -------------------------------
# The successor may legitimately live at the retired path. Only the OLD shape
# is a leftover.
r="$(mkrepo reused-path)"
printf 'version: 2\nkey: new\n' >"$r/config.yaml"
m="$TEST_TMPDIR/content.yaml"
good_record fx-r001 file config.yaml migrate 'content_match: "^version: 1$"' 'successor: move keys into settings.yaml' | manifest "$m"
run --manifest "$m" --root "$r"
assert_exit "case 6: reused path with successor content is not a hit" 0 "$RC"
printf 'version: 1\nkey: old\n' >"$r/config.yaml"
run --manifest "$m" --root "$r"
assert_exit "case 6: old content at the same path is a hit" 1 "$RC"

# --- Case 7: CRLF fixtures match $-anchored patterns --------------------------
# A Windows-authored file ends every line in \r\n; the trailing \r is stripped
# before matching so `^...$` still means the whole line.
r="$(mkrepo crlf)"
printf 'node_modules/\r\n.claude/scratch/\r\ndist/\r\n' >"$r/.gitignore"
m="$TEST_TMPDIR/crlf-line.yaml"
good_record fx-r001 line .gitignore remove-line 'match: "^\.claude/scratch/$"' | manifest "$m"
run --manifest "$m" --root "$r"
assert_exit "case 7: CRLF line matches a \$-anchored ERE" 1 "$RC"
printf 'version: 1\r\nkey: old\r\n' >"$r/config.yaml"
m="$TEST_TMPDIR/crlf-file.yaml"
good_record fx-r001 file config.yaml delete 'content_match: "^version: 1$"' | manifest "$m"
run --manifest "$m" --root "$r"
assert_exit "case 7: CRLF content_match matches a \$-anchored ERE" 1 "$RC"

# --- Case 8: report-only is listed but does not fail --------------------------
r="$(mkrepo report-only)"
printf 'x\n' >"$r/old.txt"
printf 'y\n' >"$r/older.txt"
m="$TEST_TMPDIR/report-only.yaml"
{
  good_record fx-r001 file old.txt delete 'status: report-only'
} | manifest "$m"
run --manifest "$m" --root "$r"
assert_exit "case 8: a report-only leftover exits 0" 0 "$RC"
assert_contains "case 8: the report-only row is still listed" "$OUT" "$(printf 'fx-r001\tfile\told.txt\tdelete\treport-only\t')"
{
  good_record fx-r001 file old.txt delete 'status: report-only'
  echo '---'
  good_record fx-r002 file older.txt delete 'status: active'
} | manifest "$m"
run --manifest "$m" --root "$r"
assert_exit "case 8: one active among report-only exits 1" 1 "$RC"
assert_eq "case 8: both rows listed" "2" "$(printf '%s\n' "$OUT" | grep -c .)"
assert_contains "case 8: summary splits active from report-only" "$ERR" "1 active leftover(s), 1 report-only"

# --- Case 9: malformed records fail the whole run, naming record and field ----
r="$(mkrepo malformed)"
printf 'x\n' >"$r/present.txt"
m="$TEST_TMPDIR/bad.yaml"

# bad_case <label> <field> <id-or-empty> — runs the manifest already at $m.
# Called as a plain statement, never on the right of a pipe: a pipeline would
# run it in a subshell and the pass/fail counters would be lost.
bad_case() {
  local label="$1" field="$2" id="$3"
  run --manifest "$m" --root "$r"
  assert_exit "case 9: $label exits 2" 2 "$RC"
  assert_contains "case 9: $label names the field" "$ERR" "field '$field'"
  if [[ -n "$id" ]]; then
    assert_contains "case 9: $label names the record" "$ERR" "id: $id"
  fi
}

# Literal backslash and tilde built without the literals themselves: shellcheck
# flags every quoted spelling of a backslash (SC1003) and a quoted ~/ (SC2088),
# and these assertions are precisely about those characters reaching the path.
backslash=$(printf '%b' '\134')
tilde=$(printf '%b' '\176')

good_record fx-r001 symlink present.txt delete >"$m"
bad_case "bad kind" kind fx-r001
good_record fx-r001 line present.txt remove-line >"$m"
bad_case "line without match" match fx-r001
good_record fx-r001 file present.txt delete 'match: x' >"$m"
bad_case "match on kind file" match fx-r001
good_record fx-r001 dir present.txt delete 'content_match: x' >"$m"
bad_case "content_match on kind dir" content_match fx-r001
good_record fx-r001 file present.txt delete 'heading: "## leftover"' >"$m"
bad_case "heading on kind file" heading fx-r001
good_record fx-r001 line present.txt remove-line 'match: "^X$"' 'heading: convention_source' >"$m"
bad_case "heading that is not ATX" heading fx-r001
good_record fx-r001 file /etc/passwd delete >"$m"
bad_case "absolute path" path fx-r001
good_record fx-r001 file ../outside.txt delete >"$m"
bad_case "leading .. path" path fx-r001
good_record fx-r001 file a/../../b delete >"$m"
bad_case "embedded .. path" path fx-r001
good_record fx-r001 file "${tilde}/x" delete >"$m"
bad_case "tilde path" path fx-r001
good_record fx-r001 file "a${backslash}b" delete >"$m"
bad_case "backslash path" path fx-r001
good_record fx-r001 file 'C:/x' delete >"$m"
bad_case "drive path" path fx-r001
good_record fx-r001 dir . delete >"$m"
bad_case "dot path" path fx-r001
good_record fx-r001 dir ./ delete >"$m"
bad_case "dot-slash path" path fx-r001
good_record fx-r001 dir sub/. delete >"$m"
bad_case "trailing dot segment" path fx-r001
{
  good_record fx-r001 file present.txt delete
  echo '---'
  good_record fx-r001 file other.txt delete
} >"$m"
bad_case "duplicate id" id fx-r001
good_record fx-r001 file present.txt migrate >"$m"
bad_case "migrate without successor" successor fx-r001
good_record fx-r001 file present.txt remove-line >"$m"
bad_case "remove-line on kind file" action fx-r001
good_record fx-r001 line present.txt delete 'match: x' >"$m"
bad_case "delete on kind line" action fx-r001
good_record fx-r001 file present.txt delete 'status: retired' >"$m"
bad_case "bad status" status fx-r001
good_record fx-r001 file present.txt shred >"$m"
bad_case "bad action" action fx-r001
printf 'id: fx-r001\nretired: 2026-09-01\nplugin_version: 1.2.3\nkind: file\npath: present.txt\naction: delete\n' >"$m"
bad_case "missing note" note fx-r001
good_record fx-r001 file present.txt delete 'colour: blue' >"$m"
bad_case "unknown key" colour fx-r001
good_record fx-r001 line present.txt remove-line 'match: "("' >"$m"
bad_case "invalid ERE" match fx-r001
printf 'id: fx-r001\nretired: yesterday\nplugin_version: 1.2.3\nkind: file\npath: present.txt\naction: delete\nnote: n\n' >"$m"
bad_case "bad date" retired fx-r001
printf 'id: fx-r001\nretired: 2026-09-01\nplugin_version: v1\nkind: file\npath: present.txt\naction: delete\nnote: n\n' >"$m"
bad_case "bad semver" plugin_version fx-r001
good_record 'Fixture 1' file present.txt delete >"$m"
bad_case "bad id shape" id ""
printf 'retired: 2026-09-01\nplugin_version: 1.2.3\nkind: file\npath: present.txt\naction: delete\nnote: n\n' >"$m"
bad_case "missing id" id ""
{
  good_record fx-r001 file present.txt delete
  printf 'note: twice\n'
} >"$m"
bad_case "field set twice" note fx-r001

printf 'id: fx-r001\n  nested:\n    key: value\n' | manifest "$m"
run --manifest "$m" --root "$r"
assert_exit "case 9: nesting exits 2" 2 "$RC"
assert_contains "case 9: nesting names the line" "$ERR" "is not 'key: value'"

# The property that matters most: one bad record silences NOTHING. A valid
# record whose artifact IS present emits no row when a sibling is malformed.
{
  good_record fx-r001 file present.txt delete
  echo '---'
  good_record fx-r002 teapot present.txt delete
} | manifest "$m"
run --manifest "$m" --root "$r"
assert_exit "case 9: a bad record fails the whole run" 2 "$RC"
assert_eq "case 9: no row is emitted for the valid record" "" "$OUT"
assert_contains "case 9: the bad record is named" "$ERR" "id: fx-r002"

# --- Case 10: parsing — CRLF manifest, quotes, comments, separators -----------
r="$(mkrepo parsing)"
mkdir -p "$r/old dir"
printf 'x\n' >"$r/old dir/file.txt"
printf 'x\n' >"$r/plain.txt"
m="$TEST_TMPDIR/parsing.yaml"
{
  printf -- '# leading comment\r\n'
  printf -- '---\r\n'
  printf 'id: "fx-r001"\r\n'
  printf "retired: '2026-09-01'\r\n"
  printf 'plugin_version: 1.2.3\r\n'
  printf 'kind: file\r\n'
  printf "path: 'old dir/file.txt'\r\n"
  printf 'action: delete\r\n'
  printf '\r\n'
  printf 'note: "a note: with a colon, and # a hash"\r\n'
  printf -- '---\r\n'
  printf -- '# comment between records\r\n'
  printf 'id: fx-r002\r\n'
  printf 'retired: 2026-09-01\r\n'
  printf 'plugin_version: 1.2.3\r\n'
  printf 'kind: file\r\n'
  printf 'path: plain.txt\r\n'
  printf 'action: delete\r\n'
  printf 'note: plain\r\n'
  printf -- '---\r\n'
} >"$m"
run --manifest "$m" --root "$r"
assert_exit "case 10: CRLF manifest parses and detects" 1 "$RC"
assert_eq "case 10: both records evaluated" "2" "$(printf '%s\n' "$OUT" | grep -c .)"
assert_contains "case 10: quoted path with a space survives" "$OUT" "$(printf '\told dir/file.txt\t')"
assert_contains "case 10: quoted note keeps its colon and hash" "$OUT" "a note: with a colon, and # a hash"
assert_not_contains "case 10: quotes are stripped" "$OUT" '"fx-r001"'
assert_contains "case 10: summary counts records" "$ERR" "2 record(s)"

printf '# only a comment\n\n' >"$m"
run --manifest "$m" --root "$r"
assert_exit "case 10: an empty manifest is valid" 0 "$RC"
assert_contains "case 10: empty manifest reports zero records" "$ERR" "0 record(s)"

# --- Case 11: emitted paths are repo-relative, exactly as declared ------------
run --manifest "$TEST_TMPDIR/file.yaml" --root "$(mkrepo relpath)"
mkdir -p "$TEST_TMPDIR/relpath/.claude"
printf '{}\n' >"$TEST_TMPDIR/relpath/.claude/old.json"
run --manifest "$TEST_TMPDIR/file.yaml" --root "$TEST_TMPDIR/relpath/"
assert_exit "case 11: trailing slash on --root is fine" 1 "$RC"
row_path="$(printf '%s\n' "$OUT" | cut -f3)"
assert_eq "case 11: path column is the declared repo-relative path" ".claude/old.json" "$row_path"
assert_not_contains "case 11: stdout never carries the root" "$OUT" "$TEST_TMPDIR"

# --- Case 12: --clean delete (file) -------------------------------------------
r="$(mkrepo clean-file)"
mkdir -p "$r/.claude"
printf '{}\n' >"$r/.claude/old.json"
printf 'keep\n' >"$r/.claude/keep.json"
m="$TEST_TMPDIR/file.yaml"
run --manifest "$m" --root "$r" --clean fx-r001
assert_exit "case 12: clean delete exits 0" 0 "$RC"
if [[ -e "$r/.claude/old.json" ]]; then fail "case 12: file removed" "still present"; else pass "case 12: file removed"; fi
if [[ -f "$r/.claude/keep.json" ]]; then pass "case 12: sibling untouched"; else fail "case 12: sibling untouched" "gone"; fi
run --manifest "$m" --root "$r" --clean fx-r001
assert_exit "case 12: clean with nothing present exits 1" 1 "$RC"
assert_contains "case 12: nothing-present is explained" "$ERR" "nothing present"
run --manifest "$m" --root "$r" --clean fx-r999
assert_exit "case 12: clean of an unknown id exits 2" 2 "$RC"
assert_contains "case 12: unknown id is named" "$ERR" "fx-r999"

# --- Case 12b: --clean file refuses a symlink parent that leaves ROOT --------
r="$(mkrepo clean-symlink-parent)"
outside="$TEST_TMPDIR/outside-clean-symlink"
mkdir -p "$outside"
printf 'secret\n' >"$outside/old.json"
ln -s "$outside" "$r/.claude"
m="$TEST_TMPDIR/symlink-parent.yaml"
good_record fx-r001 file .claude/old.json delete | manifest "$m"
run --manifest "$m" --root "$r" --clean fx-r001
assert_exit "case 12b: clean through a symlink parent exits 2" 2 "$RC"
assert_contains "case 12b: the refusal names the outside resolve" "$ERR" "resolves outside the repository root"
if [[ -f "$outside/old.json" ]]; then
  pass "case 12b: the external file is left untouched"
else
  fail "case 12b: the external file is left untouched" "deleted"
fi

# --- Case 13: --clean respects content_match at clean time --------------------
r="$(mkrepo clean-guard)"
printf 'version: 2\n' >"$r/config.yaml"
m="$TEST_TMPDIR/clean-guard.yaml"
good_record fx-r001 file config.yaml delete 'content_match: "^version: 1$"' | manifest "$m"
run --manifest "$m" --root "$r" --clean fx-r001
assert_exit "case 13: successor content at the path is not cleaned (exit 1)" 1 "$RC"
if [[ -f "$r/config.yaml" ]]; then pass "case 13: reused file preserved"; else fail "case 13: reused file preserved" "deleted"; fi
assert_contains "case 13: the reason is stated" "$ERR" "content no longer matches"

# --- Case 14: --clean delete (dir) --------------------------------------------
r="$(mkrepo clean-dir)"
mkdir -p "$r/.claude/scratch/deep"
printf 'x\n' >"$r/.claude/scratch/deep/f.txt"
printf 'keep\n' >"$r/.claude/keep.json"
m="$TEST_TMPDIR/dir.yaml"
run --manifest "$m" --root "$r" --clean fx-r001
assert_exit "case 14: clean delete dir exits 0" 0 "$RC"
if [[ -e "$r/.claude/scratch" ]]; then fail "case 14: dir removed" "still present"; else pass "case 14: dir removed"; fi
if [[ -f "$r/.claude/keep.json" ]]; then pass "case 14: sibling untouched"; else fail "case 14: sibling untouched" "gone"; fi
run --manifest "$m" --root "$r" --clean fx-r001
assert_exit "case 14: dir clean with nothing present exits 1" 1 "$RC"

# --- Case 15: --clean remove-line keeps every other byte ----------------------
r="$(mkrepo clean-line)"
m="$TEST_TMPDIR/rm-line.yaml"
good_record fx-r001 line notes.txt remove-line 'match: "^X$"' | manifest "$m"

printf 'a\nX\nb\nX\nc\n' >"$r/notes.txt"
printf 'a\nb\nc\n' >"$TEST_TMPDIR/expected"
run --manifest "$m" --root "$r" --clean fx-r001
assert_exit "case 15: remove-line exits 0" 0 "$RC"
assert_file_eq "case 15: LF file — unrelated lines byte-identical" "$TEST_TMPDIR/expected" "$r/notes.txt"
assert_contains "case 15: count reported" "$ERR" "removed 2 line(s)"

printf 'a\nX\nb' >"$r/notes.txt"
printf 'a\nb' >"$TEST_TMPDIR/expected"
run --manifest "$m" --root "$r" --clean fx-r001
assert_file_eq "case 15: missing final newline preserved" "$TEST_TMPDIR/expected" "$r/notes.txt"

printf 'a\nb\nX' >"$r/notes.txt"
printf 'a\nb\n' >"$TEST_TMPDIR/expected"
run --manifest "$m" --root "$r" --clean fx-r001
assert_file_eq "case 15: removing an unterminated last line keeps the newline of the line before it" "$TEST_TMPDIR/expected" "$r/notes.txt"

printf '  X\n\tindented\nX  \n' >"$r/notes.txt"
printf '  X\n\tindented\nX  \n' >"$TEST_TMPDIR/expected"
run --manifest "$m" --root "$r" --clean fx-r001
assert_exit "case 15: no line matches exactly — nothing to clean (exit 1)" 1 "$RC"
assert_file_eq "case 15: whitespace-bearing lines untouched when nothing matches" "$TEST_TMPDIR/expected" "$r/notes.txt"

# --- Case 16: --clean remove-line preserves CRLF ------------------------------
printf 'a\r\nX\r\nb\r\n' >"$r/notes.txt"
printf 'a\r\nb\r\n' >"$TEST_TMPDIR/expected"
run --manifest "$m" --root "$r" --clean fx-r001
assert_exit "case 16: CRLF remove-line exits 0" 0 "$RC"
assert_file_eq "case 16: CRLF endings preserved on kept lines" "$TEST_TMPDIR/expected" "$r/notes.txt"

printf 'a\r\nX\nb\n' >"$r/notes.txt"
printf 'a\r\nb\n' >"$TEST_TMPDIR/expected"
run --manifest "$m" --root "$r" --clean fx-r001
assert_file_eq "case 16: mixed endings — each kept line keeps its own" "$TEST_TMPDIR/expected" "$r/notes.txt"

# --- Case 17: --clean on migrate refuses without --i-migrated -----------------
r="$(mkrepo clean-migrate)"
printf 'version: 1\n' >"$r/config.yaml"
m="$TEST_TMPDIR/migrate.yaml"
good_record fx-r001 file config.yaml migrate 'successor: move keys into settings.yaml under tools.legacy' | manifest "$m"
run --manifest "$m" --root "$r" --clean fx-r001
assert_exit "case 17: migrate without --i-migrated exits 2" 2 "$RC"
assert_contains "case 17: refusal quotes the successor prose" "$ERR" "move keys into settings.yaml under tools.legacy"
assert_contains "case 17: refusal names the flag" "$ERR" "--i-migrated"
if [[ -f "$r/config.yaml" ]]; then pass "case 17: artifact preserved on refusal"; else fail "case 17: artifact preserved on refusal" "deleted"; fi
run --manifest "$m" --root "$r" --clean fx-r001 --i-migrated
assert_exit "case 17: migrate with --i-migrated exits 0" 0 "$RC"
if [[ -e "$r/config.yaml" ]]; then fail "case 17: artifact removed after migration" "still present"; else pass "case 17: artifact removed after migration"; fi

printf 'a\nold=1\nb\n' >"$r/.env"
printf 'a\nb\n' >"$TEST_TMPDIR/expected"
good_record fx-r002 line .env migrate 'match: "^old="' 'successor: set NEW in settings' | manifest "$m"
run --manifest "$m" --root "$r" --clean fx-r002
assert_exit "case 17: migrate line record refuses too" 2 "$RC"
run --manifest "$m" --root "$r" --clean fx-r002 --i-migrated
assert_exit "case 17: migrate line record cleans with --i-migrated" 0 "$RC"
assert_file_eq "case 17: migrate line record removes only the matched line" "$TEST_TMPDIR/expected" "$r/.env"

# --- Case 18: --clean works on a report-only record ---------------------------
r="$(mkrepo clean-report-only)"
printf 'x\n' >"$r/old.txt"
m="$TEST_TMPDIR/clean-ro.yaml"
good_record fx-r001 file old.txt delete 'status: report-only' | manifest "$m"
run --manifest "$m" --root "$r" --clean fx-r001
assert_exit "case 18: report-only record is cleanable on request" 0 "$RC"

# --- Case 19: --clean also refuses a manifest with a bad sibling record -------
r="$(mkrepo clean-bad-sibling)"
printf 'x\n' >"$r/old.txt"
m="$TEST_TMPDIR/clean-bad.yaml"
{
  good_record fx-r001 file old.txt delete
  echo '---'
  good_record fx-r002 nope old.txt delete
} | manifest "$m"
run --manifest "$m" --root "$r" --clean fx-r001
assert_exit "case 19: clean fails on an invalid manifest" 2 "$RC"
if [[ -f "$r/old.txt" ]]; then pass "case 19: nothing cleaned from an invalid manifest"; else fail "case 19: nothing cleaned from an invalid manifest" "deleted"; fi

# --- Case 20: default root — CLAUDE_PROJECT_DIR, then git toplevel ------------
r="$(mkrepo default-root)"
mkdir -p "$r/.claude" "$r/sub/dir"
printf '{}\n' >"$r/.claude/old.json"
m="$TEST_TMPDIR/file.yaml"
OUT="$(cd "$TEST_TMPDIR" && CLAUDE_PROJECT_DIR="$r" bash "$SCRIPT" --manifest "$m" 2>/dev/null)"
RC=$?
assert_exit "case 20: CLAUDE_PROJECT_DIR supplies the root" 1 "$RC"
if command -v git >/dev/null 2>&1; then
  OUT="$(cd "$r/sub/dir" && env -u CLAUDE_PROJECT_DIR bash "$SCRIPT" --manifest "$m" 2>/dev/null)"
  RC=$?
  assert_exit "case 20: git toplevel supplies the root from a subdirectory" 1 "$RC"
  assert_eq "case 20: path stays repo-relative under the git rung" ".claude/old.json" "$(printf '%s\n' "$OUT" | cut -f3)"
else
  echo "SKIP: git not installed — git-toplevel rung not exercised" >&2
fi
OUT="$(cd "$TEST_TMPDIR" && CLAUDE_PROJECT_DIR="$r" bash "$SCRIPT" --manifest "$m" --root "$TEST_TMPDIR/parsing" 2>/dev/null)"
RC=$?
assert_exit "case 20: --root wins over CLAUDE_PROJECT_DIR" 0 "$RC"

# --- Case 21: every emitted row has exactly 6 columns -------------------------
r="$(mkrepo columns)"
mkdir -p "$r/d"
printf 'x\n' >"$r/f.txt"
printf 'X\n' >"$r/l.txt"
m="$TEST_TMPDIR/columns.yaml"
{
  good_record fx-r001 file f.txt delete
  echo '---'
  good_record fx-r002 dir d delete
  echo '---'
  good_record fx-r003 line l.txt remove-line 'match: "^X$"'
  echo '---'
  good_record fx-r004 file f.txt migrate 'successor: elsewhere' 'status: report-only'
} | manifest "$m"
run --manifest "$m" --root "$r"
assert_exit "case 21: mixed manifest exits 1" 1 "$RC"
assert_eq "case 21: four rows" "4" "$(printf '%s\n' "$OUT" | grep -c .)"
assert_eq "case 21: every row has 6 columns" "6" "$(printf '%s\n' "$OUT" | awk -F '\t' '{ print NF }' | sort -u | tr -d '\n')"
assert_eq "case 21: rows are in manifest order" "fx-r001 fx-r002 fx-r003 fx-r004" "$(printf '%s\n' "$OUT" | cut -f1 | tr '\n' ' ' | sed 's/ $//')"

# --- Case 22: heading scopes kind:line to one markdown section ----------------
r="$(mkrepo heading-scope)"
mkdir -p "$r/.claude"
m="$TEST_TMPDIR/heading.yaml"
good_record fx-r001 line .claude/doc.md remove-line \
  'match: "^docs/conventions/source-control/commit-convention\.yml$"' \
  'heading: "## convention_source"' | manifest "$m"

cat >"$r/.claude/doc.md" <<'EOF'
# title

docs/conventions/source-control/commit-convention.yml

## other

docs/conventions/source-control/commit-convention.yml

## convention_source

docs/conventions/source-control/commit-convention.yml

### nested

docs/conventions/source-control/commit-convention.yml

## later

docs/conventions/source-control/commit-convention.yml
EOF
run --manifest "$m" --root "$r"
assert_exit "case 22: heading-scoped leftover exits 1" 1 "$RC"
assert_contains "case 22: heading-scoped leftover emits a row" "$OUT" "fx-r001"

cat >"$r/.claude/doc.md" <<'EOF'
# title

docs/conventions/source-control/commit-convention.yml

## other

docs/conventions/source-control/commit-convention.yml
EOF
run --manifest "$m" --root "$r"
assert_exit "case 22: decoy lines outside the heading are not a leftover" 0 "$RC"
assert_eq "case 22: decoy-only file prints no row" "" "$OUT"

cat >"$r/.claude/doc.md" <<'EOF'
## convention_source

something-else.yml
EOF
run --manifest "$m" --root "$r"
assert_exit "case 22: heading present without a matching body line is not a leftover" 0 "$RC"

cat >"$r/.claude/doc.md" <<'EOF'
# title

docs/conventions/source-control/commit-convention.yml

## other

docs/conventions/source-control/commit-convention.yml

## convention_source

docs/conventions/source-control/commit-convention.yml

### nested

docs/conventions/source-control/commit-convention.yml

## later

docs/conventions/source-control/commit-convention.yml
EOF
printf '%s\n' \
  '# title' \
  '' \
  'docs/conventions/source-control/commit-convention.yml' \
  '' \
  '## other' \
  '' \
  'docs/conventions/source-control/commit-convention.yml' \
  '' \
  '## convention_source' \
  '' \
  '' \
  '### nested' \
  '' \
  '' \
  '## later' \
  '' \
  'docs/conventions/source-control/commit-convention.yml' \
  >"$TEST_TMPDIR/heading-expected"
run --manifest "$m" --root "$r" --clean fx-r001
assert_exit "case 22: heading-scoped --clean exits 0" 0 "$RC"
assert_file_eq "case 22: --clean removes only in-section matches and keeps decoys" \
  "$TEST_TMPDIR/heading-expected" "$r/.claude/doc.md"
assert_contains "case 22: --clean reports two in-section lines" "$ERR" "removed 2 line(s)"

# Trailing whitespace on the heading line still identifies the section; a
# second same-level heading with the same title is a second section.
printf '## convention_source  \r\ndocs/conventions/source-control/commit-convention.yml\r\n## convention_source\r\ndocs/conventions/source-control/commit-convention.yml\r\n' \
  >"$r/.claude/doc.md"
run --manifest "$m" --root "$r"
assert_exit "case 22: trailing-space / CRLF heading still detects" 1 "$RC"
run --manifest "$m" --root "$r" --clean fx-r001
assert_exit "case 22: CRLF heading-scoped --clean exits 0" 0 "$RC"
printf '## convention_source  \r\n## convention_source\r\n' >"$TEST_TMPDIR/heading-crlf-expected"
assert_file_eq "case 22: both heading-titled sections cleaned; heading lines kept" \
  "$TEST_TMPDIR/heading-crlf-expected" "$r/.claude/doc.md"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
