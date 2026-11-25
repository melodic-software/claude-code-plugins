#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/memory-dir-stats.sh"

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

slug_of() {
  local root
  root=$(cd "$1" && (cygpath -w "$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')" 2>/dev/null ||
    git rev-parse --show-toplevel 2>/dev/null | tr -d '\r'))
  printf '%s' "$root" | sed 's/[:\\/.]/-/g'
}

REPO="$TEST_TMPDIR/repo"
make_repo "$REPO"
SLUG=$(slug_of "$REPO")

mem_dir_for() {
  local dir="$1/.claude/projects/$SLUG/memory"
  mkdir -p "$dir"
  printf '%s' "$dir"
}

run() { (cd "$REPO" && env -u CLAUDE_CONFIG_DIR HOME="$1" bash "$SCRIPT" "$2"); }

rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

rc=0
OUT=$(bash "$SCRIPT" --bogus 2>"$TEST_TMPDIR/err") || rc=$?
assert_exit "bad flag exits 2" 2 "$rc"
assert_eq "bad flag prints nothing on stdout" "" "$OUT"
assert_contains "bad flag prints usage on stderr" "$(cat "$TEST_TMPDIR/err")" "Usage:"
rc=0
OUT=$(bash "$SCRIPT" 2>/dev/null) || rc=$?
assert_exit "missing mode exits 2" 2 "$rc"
assert_eq "missing mode prints nothing on stdout" "" "$OUT"

H3="$TEST_TMPDIR/h3"
M3=$(mem_dir_for "$H3")
printf '# Index\n' >"$M3/MEMORY.md"
printf 'a\n' >"$M3/a.md"
printf 'b\n' >"$M3/b.md"
printf 'not markdown\n' >"$M3/notes.txt"
rc=0
OUT=$(run "$H3" --md-count) || rc=$?
assert_exit "--md-count exits 0" 0 "$rc"
assert_eq "--md-count counts every *.md (MEMORY.md + 2 topics)" "3" "$OUT"

printf 'one\ntwo\nthree\n' >"$M3/MEMORY.md"
rc=0
OUT=$(run "$H3" --memory-lines) || rc=$?
assert_exit "--memory-lines exits 0" 0 "$rc"
assert_eq "--memory-lines counts MEMORY.md lines" "3" "$OUT"

printf -- "---\ntype: index\n---\n# Index\n<!-- hidden\nstill hidden -->\nreal\n\`\`\`\n<!-- kept -->\n\`\`\`\n" >"$M3/MEMORY.md"
assert_eq "--memory-lines counts post-strip lines" "5" "$(run "$H3" --memory-lines)"
assert_eq "--memory-bytes counts post-strip bytes" "35" "$(run "$H3" --memory-bytes)"

printf -- "---\ntype: index\n# Title\nreal\n" >"$M3/MEMORY.md"
assert_eq "unclosed frontmatter counts the whole file" "4" "$(run "$H3" --memory-lines)"
printf -- "---\n# Title\nreal one\nreal two\n" >"$M3/MEMORY.md"
assert_eq "leading thematic break is not frontmatter" "4" "$(run "$H3" --memory-lines)"
printf -- "<!-- note\na\nb\nc\n" >"$M3/MEMORY.md"
assert_eq "unclosed comment counts the whole file" "4" "$(run "$H3" --memory-lines)"

raw_lines() { printf '%s' "$(($(wc -l <"$M3/MEMORY.md")))"; }
raw_bytes() { printf '%s' "$(($(wc -c <"$M3/MEMORY.md")))"; }
repeat_lines() {
  local i=0
  while [[ "$i" -lt "$1" ]]; do
    printf '%s%d%s\n' "$2" "$i" "$3"
    i=$((i + 1))
  done
}

{
  printf -- '---\n# Title\n'
  repeat_lines 249 'content line ' ''
  printf -- '---\ntail\n'
} >"$M3/MEMORY.md"
assert_eq "leading break + later --- counts every line" "$(raw_lines)" "$(run "$H3" --memory-lines)"

PAD=$(printf '%200s' '' | tr ' ' 'x')
{
  printf -- '---\n# Title\n'
  repeat_lines 150 'content ' " $PAD"
  printf -- '---\ntail\n'
} >"$M3/MEMORY.md"
if [[ "$(raw_bytes)" -gt 25600 ]]; then
  pass "byte-limb fixture is genuinely over the 25KB limit"
else
  fail "byte-limb fixture is genuinely over the 25KB limit" "only $(raw_bytes) bytes"
fi
assert_eq "leading break + later --- counts every byte" "$(raw_bytes)" "$(run "$H3" --memory-bytes)"

{
  printf -- '---\n'
  repeat_lines 250 'Label' ': value'
  printf -- '---\ntail\n'
} >"$M3/MEMORY.md"
assert_eq "a key:-shaped runaway is bounded by length" "$(raw_lines)" "$(run "$H3" --memory-lines)"

HEAVY=$(printf '%26000s' '' | tr ' ' 'x')
{
  printf -- '---\n'
  printf 'Note: %s\n' "$HEAVY"
  printf -- '---\nbody\n'
} >"$M3/MEMORY.md"
assert_eq "a heavy one-line runaway is bounded by weight" "$(raw_bytes)" "$(run "$H3" --memory-bytes)"
assert_eq "a heavy one-line runaway counts every line" "$(raw_lines)" "$(run "$H3" --memory-lines)"

WIDE=$(for ((i = 0; i < 600; i++)); do printf '\303\251'; done)
{
  printf -- '---\n'
  printf 'Note: %s\n' "$WIDE"
  printf -- '---\nbody\n'
} >"$M3/MEMORY.md"
assert_eq "a multibyte heavy line is bounded by weight in bytes" "$(raw_bytes)" "$(run "$H3" --memory-bytes)"

{
  printf -- '---\n'
  repeat_lines 15 'key' ": $(printf '%40s' '' | tr ' ' 'v')"
  printf -- '---\nbody\n'
} >"$M3/MEMORY.md"
assert_eq "frontmatter under the weight cap still strips" "1" "$(run "$H3" --memory-lines)"

printf -- "---\ntype: index\nmodified: 2026-01-01\n---\n# A\none\n---\ntwo\n" >"$M3/MEMORY.md"
assert_eq "real frontmatter still strips despite a later ---" "4" "$(run "$H3" --memory-lines)"

printf -- "---\n# heading one\n# heading two\n---\nbody\n" >"$M3/MEMORY.md"
assert_eq "a heading-only pseudo block counts every line" "$(raw_lines)" "$(run "$H3" --memory-lines)"
assert_eq "a heading-only pseudo block counts every byte" "$(raw_bytes)" "$(run "$H3" --memory-bytes)"
printf -- "---\ntype: index\n# note\nmodified: x\n---\nbody\n" >"$M3/MEMORY.md"
assert_eq "a comment in frontmatter ends the block and counts" "$(raw_lines)" "$(run "$H3" --memory-lines)"
printf -- "---\ntype: index\nmodified: 2026-01-01\n---\nbody\n" >"$M3/MEMORY.md"
assert_eq "key-only frontmatter still strips" "1" "$(run "$H3" --memory-lines)"

printf -- "<!-- note\n\`\`\`bash\nLEAKED\n\`\`\`\n-->\nreal\n" >"$M3/MEMORY.md"
assert_eq "fence inside a comment stays stripped" "1" "$(run "$H3" --memory-lines)"

printf -- "<!-- x --> KEPT\n" >"$M3/MEMORY.md"
assert_eq "content after a single-line comment survives" "1" "$(run "$H3" --memory-lines)"
printf -- "<!-- a\nb --> TAIL\nreal\n" >"$M3/MEMORY.md"
assert_eq "content after a multi-line comment's close survives" "2" "$(run "$H3" --memory-lines)"

printf -- "<!-- a --> KEPT TEXT <!-- b -->\n" >"$M3/MEMORY.md"
assert_eq "text between two comments on one line survives" "1" "$(run "$H3" --memory-lines)"
assert_eq "text between two comments keeps its bytes" "12" "$(run "$H3" --memory-bytes)"

printf -- "<!-- open\nmid\n--> KEPT ONE <!-- again --> KEPT TWO\nplain\n" >"$M3/MEMORY.md"
assert_eq "a close followed by a reopen counts both texts" "2" "$(run "$H3" --memory-lines)"
assert_eq "a close followed by a reopen keeps its bytes" "26" "$(run "$H3" --memory-bytes)"

printf -- "<!-- a --> mid <!-- b --> tail\n" >"$M3/MEMORY.md"
assert_eq "two comments plus a tail keep every fragment" "11" "$(run "$H3" --memory-bytes)"
printf -- "<!-- a --> mid <!-- b -->\n" >"$M3/MEMORY.md"
assert_eq "two comments with no tail keep the middle" "6" "$(run "$H3" --memory-bytes)"

printf -- "<!-- a\nb --> mid <!-- c -->\nreal\n" >"$M3/MEMORY.md"
assert_eq "a close line that reopens and recloses counts both" "2" "$(run "$H3" --memory-lines)"
assert_eq "a close line that reopens and recloses keeps bytes" "11" "$(run "$H3" --memory-bytes)"
printf -- "<!-- a\nb --> real content -->\n" >"$M3/MEMORY.md"
assert_eq "text before a stray close is not dropped" "1" "$(run "$H3" --memory-lines)"
assert_eq "text before a stray close keeps its bytes" "18" "$(run "$H3" --memory-bytes)"

printf -- "# H\n<!--\nsecret\n-->\nvisible\n" >"$M3/MEMORY.md"
assert_eq "a plain block comment still strips" "2" "$(run "$H3" --memory-lines)"
assert_eq "a plain block comment still strips its bytes" "12" "$(run "$H3" --memory-bytes)"

printf -- "<!---->\nreal\n" >"$M3/MEMORY.md"
assert_eq "an empty comment strips" "1" "$(run "$H3" --memory-lines)"
printf -- "<!-- a - b --> tail\n" >"$M3/MEMORY.md"
assert_eq "a lone dash in a comment body does not close it" "6" "$(run "$H3" --memory-bytes)"
printf -- "<!-- a ---->\ntail\n" >"$M3/MEMORY.md"
assert_eq "a multi-dash closer still closes" "1" "$(run "$H3" --memory-lines)"

printf -- "<!-- a --> KEEP <!-- open\nnext\n" >"$M3/MEMORY.md"
assert_eq "text before an unterminated opener counts once" "3" "$(run "$H3" --memory-lines)"
assert_eq "text before an unterminated opener keeps its bytes" "22" "$(run "$H3" --memory-bytes)"

printf -- "<!-- a --> KEEP <!-- open\nstill\n--> tail\n" >"$M3/MEMORY.md"
assert_eq "text before an opener survives a later close" "2" "$(run "$H3" --memory-lines)"
assert_eq "text before an opener keeps bytes past a close" "13" "$(run "$H3" --memory-bytes)"

printf -- "  <!-- note\na\n" >"$M3/MEMORY.md"
assert_eq "an indented unterminated opener keeps its indent" "2" "$(run "$H3" --memory-lines)"
assert_eq "an indented unterminated opener counts its bytes" "14" "$(run "$H3" --memory-bytes)"
printf -- "<!-- a --><!-- open\nnext\n" >"$M3/MEMORY.md"
assert_eq "a stripped comment is not re-counted by the hold" "15" "$(run "$H3" --memory-bytes)"

H5="$TEST_TMPDIR/h5"
mkdir -p "$H5"
rc=0
OUT=$(run "$H5" --md-count) || rc=$?
assert_exit "absent memory dir --md-count exits 0" 0 "$rc"
assert_eq "absent memory dir --md-count == 0" "0" "$OUT"
rc=0
OUT=$(run "$H5" --memory-lines) || rc=$?
assert_exit "absent MEMORY.md exits 0" 0 "$rc"
assert_eq "absent MEMORY.md --memory-lines == 0" "0" "$OUT"

H6="$TEST_TMPDIR/h6"
mem_dir_for "$H6" >/dev/null
assert_eq "empty memory dir --md-count == 0" "0" "$(run "$H6" --md-count)"
assert_eq "empty memory dir --memory-lines == 0" "0" "$(run "$H6" --memory-lines)"
assert_eq "empty memory dir --memory-bytes == 0" "0" "$(run "$H6" --memory-bytes)"

for m in --md-count --memory-lines --memory-bytes; do
  OUT=$(run "$H3" "$m")
  if [[ "$OUT" =~ ^[0-9]+$ ]]; then
    pass "$m emits exactly one bare integer"
  else
    fail "$m emits exactly one bare integer" "got: [$OUT]"
  fi
done

report_and_exit
