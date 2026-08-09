#!/usr/bin/env bash
# Regression tests for memory-dir-stats.sh (self-contained — ships with the plugin).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/memory-dir-stats.sh"

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
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
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

# Fixture git repos must never inherit an outer hook chain's exported git env.
make_repo() {
  unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_COMMON_DIR
  mkdir -p "$1"
  (cd "$1" && git init -q && git config user.email "test@example.com" && git config user.name "test" && git commit -q --allow-empty -m init)
}

slug_of() {
  local root
  root=$(cd "$1" && (cygpath -w "$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')" 2>/dev/null ||
    git rev-parse --show-toplevel 2>/dev/null | tr -d '\r'))
  printf '%s' "$root" | sed 's/[:\\/.]/-/g'
}

REPO="$TEST_TMPDIR/repo"
make_repo "$REPO"
SLUG=$(slug_of "$REPO")

# mem_dir_for <home> — create + echo the memory dir the resolver will pick for that HOME.
mem_dir_for() {
  local dir="$1/.claude/projects/$SLUG/memory"
  mkdir -p "$dir"
  printf '%s' "$dir"
}

# CLAUDE_CONFIG_DIR is unset per-run: the resolver honors it over $HOME, so leaving an
# ambient value in place would let the host machine's real config answer for the fixture.
run() { (cd "$REPO" && env -u CLAUDE_CONFIG_DIR HOME="$1" bash "$SCRIPT" "$2"); }

# --- Case 1: --help ---
rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

# --- Case 2: bad flag and missing mode -> usage on stderr, exit 2, empty stdout ---
rc=0
OUT=$(bash "$SCRIPT" --bogus 2>"$TEST_TMPDIR/err") || rc=$?
assert_exit "bad flag exits 2" 2 "$rc"
assert_eq "bad flag prints nothing on stdout" "" "$OUT"
assert_contains "bad flag prints usage on stderr" "$(cat "$TEST_TMPDIR/err")" "Usage:"
rc=0
OUT=$(bash "$SCRIPT" 2>/dev/null) || rc=$?
assert_exit "missing mode exits 2" 2 "$rc"
assert_eq "missing mode prints nothing on stdout" "" "$OUT"

# --- Case 3: --md-count with N md files (MEMORY.md included, as the old inline `ls *.md` counted it) ---
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

# --- Case 4: --memory-lines with MEMORY.md present ---
printf 'one\ntwo\nthree\n' >"$M3/MEMORY.md"
rc=0
OUT=$(run "$H3" --memory-lines) || rc=$?
assert_exit "--memory-lines exits 0" 0 "$rc"
assert_eq "--memory-lines counts MEMORY.md lines" "3" "$OUT"

# --- Case 4b: MEMORY.md stats measure loaded content only — frontmatter and
# block-level HTML comments are stripped (they don't count toward the limits),
# while a comment inside a fenced code block is preserved ---
printf -- "---\ntype: index\n---\n# Index\n<!-- hidden\nstill hidden -->\nreal\n\`\`\`\n<!-- kept -->\n\`\`\`\n" >"$M3/MEMORY.md"
assert_eq "--memory-lines counts post-strip lines" "5" "$(run "$H3" --memory-lines)"
assert_eq "--memory-bytes counts post-strip bytes" "35" "$(run "$H3" --memory-bytes)"

# --- Case 4c: an unterminated block is content, not a block. M1 is a [FAIL]-severity
# size gate and 0 always passes it, so a block that swallows the file to EOF would
# disarm the gate outright. Each input below must report its whole line count. ---
printf -- "---\ntype: index\n# Title\nreal\n" >"$M3/MEMORY.md"
assert_eq "unclosed frontmatter counts the whole file" "4" "$(run "$H3" --memory-lines)"
printf -- "---\n# Title\nreal one\nreal two\n" >"$M3/MEMORY.md"
assert_eq "leading thematic break is not frontmatter" "4" "$(run "$H3" --memory-lines)"
printf -- "<!-- note\na\nb\nc\n" >"$M3/MEMORY.md"
assert_eq "unclosed comment counts the whole file" "4" "$(run "$H3" --memory-lines)"

# --- Case 4c2: closing is not enough — a leading thematic break must not open a
# frontmatter block that runs to whatever `---` appears next. Markdown carries thematic
# breaks freely, so the whole span between them would be stripped and an index that is
# over the limit would report a single loaded line, leaving this [FAIL] gate unable to
# fire. Both limbs of M1 are covered: the line limit and the 25KB byte limit.
#
# The expectation is the file's own raw size: none of these fixtures holds frontmatter,
# so nothing may be stripped from any of them. ---
raw_lines() { printf '%s' "$(($(wc -l <"$M3/MEMORY.md")))"; }
raw_bytes() { printf '%s' "$(($(wc -c <"$M3/MEMORY.md")))"; }
# repeat_lines <count> <prefix> <suffix> — <count> distinct lines of "<prefix><n><suffix>".
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

# Byte limb: content long enough to blow the 25KB limit on its own.
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

# Grammar alone cannot bound the block: every line here is a well-formed `key: value`
# mapping entry, a plausible hand-written index shape. Only the length cap ends it.
{
  printf -- '---\n'
  repeat_lines 250 'Label' ': value'
  printf -- '---\ntail\n'
} >"$M3/MEMORY.md"
assert_eq "a key:-shaped runaway is bounded by length" "$(raw_lines)" "$(run "$H3" --memory-lines)"

# The length cap alone cannot bound the block either: markdown prose opening `Note:` is a
# well-formed mapping entry, so a single heavy paragraph passes the grammar AND the line
# cap and was stripped however much it weighed — 26KB of content reporting 5 bytes, the
# under-count that leaves M1's byte limb unable to fire. Only the weight cap ends it.
HEAVY=$(printf '%26000s' '' | tr ' ' 'x')
{
  printf -- '---\n'
  printf 'Note: %s\n' "$HEAVY"
  printf -- '---\nbody\n'
} >"$M3/MEMORY.md"
assert_eq "a heavy one-line runaway is bounded by weight" "$(raw_bytes)" "$(run "$H3" --memory-bytes)"
assert_eq "a heavy one-line runaway counts every line" "$(raw_lines)" "$(run "$H3" --memory-lines)"

# The weight cap measures BYTES, not characters: in a multibyte locale awk's length()
# counts characters, so 900 two-byte characters (1800 bytes) would read as 906 and slip
# under the 1024-byte cap — the same under-count, resurrected by locale. LC_ALL=C on the
# awk pass pins byte semantics; this fixture fails without it.
WIDE=$(i=0; while [ "$i" -lt 900 ]; do printf 'Ã©'; i=$((i+1)); done)
{
  printf -- '---
'
  printf 'Note: %s
' "$WIDE"
  printf -- '---
body
'
} >"$M3/MEMORY.md"
assert_eq "a multibyte heavy line is bounded by weight in bytes" "$(raw_bytes)" "$(run "$H3" --memory-bytes)"

# The weight cap must not cost real frontmatter its strip: a block comfortably under the
# cap — far heavier than the `modified` scalar Claude Code stamps — still strips whole.
{
  printf -- '---\n'
  repeat_lines 15 'key' ": $(printf '%40s' '' | tr ' ' 'v')"
  printf -- '---\nbody\n'
} >"$M3/MEMORY.md"
assert_eq "frontmatter under the weight cap still strips" "1" "$(run "$H3" --memory-lines)"

# --- Case 4c3: the bound must not cost real frontmatter its strip. A well-formed block
# is still stripped even when a thematic break appears later in the file. ---
printf -- "---\ntype: index\nmodified: 2026-01-01\n---\n# A\none\n---\ntwo\n" >"$M3/MEMORY.md"
assert_eq "real frontmatter still strips despite a later ---" "4" "$(run "$H3" --memory-lines)"

# --- Case 4c4: a `#` line is a comment to YAML but a HEADING to markdown, and headings
# are loaded content. Admitting them to the grammar let a pseudo-frontmatter block of
# headings swallow them — the under-count this gate cannot tolerate. The cost is that a
# real YAML comment inside frontmatter now ends the block early and counts: an
# over-count, and a rare shape, since Claude Code writes only the `modified` scalar. ---
printf -- "---\n# heading one\n# heading two\n---\nbody\n" >"$M3/MEMORY.md"
assert_eq "a heading-only pseudo block counts every line" "$(raw_lines)" "$(run "$H3" --memory-lines)"
assert_eq "a heading-only pseudo block counts every byte" "$(raw_bytes)" "$(run "$H3" --memory-bytes)"
printf -- "---\ntype: index\n# note\nmodified: x\n---\nbody\n" >"$M3/MEMORY.md"
assert_eq "a comment in frontmatter ends the block and counts" "$(raw_lines)" "$(run "$H3" --memory-lines)"
printf -- "---\ntype: index\nmodified: 2026-01-01\n---\nbody\n" >"$M3/MEMORY.md"
assert_eq "key-only frontmatter still strips" "1" "$(run "$H3" --memory-lines)"

# --- Case 4d: a fence inside a comment must not toggle fence state — otherwise the
# commented-out fence body leaks back into the count ---
printf -- "<!-- note\n\`\`\`bash\nLEAKED\n\`\`\`\n-->\nreal\n" >"$M3/MEMORY.md"
assert_eq "fence inside a comment stays stripped" "1" "$(run "$H3" --memory-lines)"

# --- Case 4e: a block-level comment occupies whole lines; real text sharing a line
# with the comment's open or close still loads ---
printf -- "<!-- x --> KEPT\n" >"$M3/MEMORY.md"
assert_eq "content after a single-line comment survives" "1" "$(run "$H3" --memory-lines)"
printf -- "<!-- a\nb --> TAIL\nreal\n" >"$M3/MEMORY.md"
assert_eq "content after a multi-line comment's close survives" "2" "$(run "$H3" --memory-lines)"

# --- Case 4f: one line can carry several comments. Each ends at the FIRST `-->` after
# its own opener, and the line is re-scanned for the next: matching to the LAST `-->`
# blanks the text between two comments, an UNDER-count on this [FAIL]-severity gate and
# the one direction the strip must never take. Only whole comment spans are removed, so
# text always survives. Byte expectations below are the measured post-strip size. ---
printf -- "<!-- a --> KEPT TEXT <!-- b -->\n" >"$M3/MEMORY.md"
assert_eq "text between two comments on one line survives" "1" "$(run "$H3" --memory-lines)"
assert_eq "text between two comments keeps its bytes" "12" "$(run "$H3" --memory-bytes)"

# The close path re-scans too: a line closing one comment may open and close another.
printf -- "<!-- open\nmid\n--> KEPT ONE <!-- again --> KEPT TWO\nplain\n" >"$M3/MEMORY.md"
assert_eq "a close followed by a reopen counts both texts" "2" "$(run "$H3" --memory-lines)"
assert_eq "a close followed by a reopen keeps its bytes" "26" "$(run "$H3" --memory-bytes)"

# Both texts on an open line, with and without a tail after the second comment.
printf -- "<!-- a --> mid <!-- b --> tail\n" >"$M3/MEMORY.md"
assert_eq "two comments plus a tail keep every fragment" "11" "$(run "$H3" --memory-bytes)"
printf -- "<!-- a --> mid <!-- b -->\n" >"$M3/MEMORY.md"
assert_eq "two comments with no tail keep the middle" "6" "$(run "$H3" --memory-bytes)"

# A close line that reopens and re-closes, and one whose text is followed by a stray
# close: the second must keep its whole line rather than reporting nothing.
printf -- "<!-- a\nb --> mid <!-- c -->\nreal\n" >"$M3/MEMORY.md"
assert_eq "a close line that reopens and recloses counts both" "2" "$(run "$H3" --memory-lines)"
assert_eq "a close line that reopens and recloses keeps bytes" "11" "$(run "$H3" --memory-bytes)"
printf -- "<!-- a\nb --> real content -->\n" >"$M3/MEMORY.md"
assert_eq "text before a stray close is not dropped" "1" "$(run "$H3" --memory-lines)"
assert_eq "text before a stray close keeps its bytes" "18" "$(run "$H3" --memory-bytes)"

# The re-scan must not cost an ordinary block comment its strip, on either limb.
printf -- "# H\n<!--\nsecret\n-->\nvisible\n" >"$M3/MEMORY.md"
assert_eq "a plain block comment still strips" "2" "$(run "$H3" --memory-lines)"
assert_eq "a plain block comment still strips its bytes" "12" "$(run "$H3" --memory-bytes)"

# Scan guards: the walk must still close on an empty comment, on a body holding a lone
# dash, and on a closer padded with extra dashes.
printf -- "<!---->\nreal\n" >"$M3/MEMORY.md"
assert_eq "an empty comment strips" "1" "$(run "$H3" --memory-lines)"
printf -- "<!-- a - b --> tail\n" >"$M3/MEMORY.md"
assert_eq "a lone dash in a comment body does not close it" "6" "$(run "$H3" --memory-bytes)"
printf -- "<!-- a ---->\ntail\n" >"$M3/MEMORY.md"
assert_eq "a multi-dash closer still closes" "1" "$(run "$H3" --memory-lines)"

# A line can close one comment and open an unterminated one. What loaded before the
# opener is emitted at once and only the unterminated fragment is held, so that text is
# neither counted twice when the flush lands nor lost if the comment closes later.
printf -- "<!-- a --> KEEP <!-- open\nnext\n" >"$M3/MEMORY.md"
assert_eq "text before an unterminated opener counts once" "3" "$(run "$H3" --memory-lines)"
assert_eq "text before an unterminated opener keeps its bytes" "22" "$(run "$H3" --memory-bytes)"

# The same shape with the comment closing further down. The held block is dropped on
# close, and the text that loaded before the opener must survive that drop — folding it
# into the held block instead of emitting it would lose it outright here.
printf -- "<!-- a --> KEEP <!-- open\nstill\n--> tail\n" >"$M3/MEMORY.md"
assert_eq "text before an opener survives a later close" "2" "$(run "$H3" --memory-lines)"
assert_eq "text before an opener keeps bytes past a close" "13" "$(run "$H3" --memory-bytes)"

# Only whitespace ahead of the opener joins the held block: an indented opener keeps its
# indent, while a comment already stripped off the line is not counted a second time.
printf -- "  <!-- note\na\n" >"$M3/MEMORY.md"
assert_eq "an indented unterminated opener keeps its indent" "2" "$(run "$H3" --memory-lines)"
assert_eq "an indented unterminated opener counts its bytes" "14" "$(run "$H3" --memory-bytes)"
printf -- "<!-- a --><!-- open\nnext\n" >"$M3/MEMORY.md"
assert_eq "a stripped comment is not re-counted by the hold" "15" "$(run "$H3" --memory-bytes)"

# --- Case 5: fresh project — no memory dir at all: both modes report 0, exit 0 ---
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

# --- Case 6: memory dir exists but is empty (no MEMORY.md) ---
H6="$TEST_TMPDIR/h6"
mem_dir_for "$H6" >/dev/null
assert_eq "empty memory dir --md-count == 0" "0" "$(run "$H6" --md-count)"
assert_eq "empty memory dir --memory-lines == 0" "0" "$(run "$H6" --memory-lines)"
assert_eq "empty memory dir --memory-bytes == 0" "0" "$(run "$H6" --memory-bytes)"

# --- Case 7: output contract — a single bare integer, nothing else, for every stat mode ---
for m in --md-count --memory-lines --memory-bytes; do
  OUT=$(run "$H3" "$m")
  if [[ "$OUT" =~ ^[0-9]+$ ]]; then
    pass "$m emits exactly one bare integer"
  else
    fail "$m emits exactly one bare integer" "got: [$OUT]"
  fi
done

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
