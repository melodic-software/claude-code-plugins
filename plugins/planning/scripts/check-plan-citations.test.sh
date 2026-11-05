#!/usr/bin/env bash
# Black-box contract test for check-plan-citations.sh.
#
# Self-contained and cwd-independent; builds a fixture repository in its own
# mktemp dir and mutates nothing else.
#
# SC2016 is disabled file-wide on purpose: the single-quoted `$HOME`, `${ROOT}`
# and backtick spans are literal fixture text, not expansions.
# shellcheck disable=SC2016
set -uo pipefail

# A git hook chain can export these; a fixture `git init` would then touch the real repo.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/check-plan-citations.sh"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
fixture_git() { git -C "$REPO" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
if ! {
  mkdir -p "$REPO/scripts" "$REPO/src/lib" "$REPO/docs" &&
    git -C "$REPO" init -q &&
    printf 'l1\nl2\nl3\nl4\nl5\n' >"$REPO/scripts/build.sh" &&
    printf 'a\nb\nc' >"$REPO/src/app.ts" &&
    printf 'x\n' >"$REPO/src/lib/util.ts" &&
    printf 'export function main() {}\nconst helper = 1\n// --dry-run\n' >"$REPO/src/shape.ts" &&
    printf 'old\n' >"$REPO/docs/old.md" &&
    fixture_git add -A &&
    fixture_git commit -qm first
}; then
  printf 'FAIL - could not build the fixture repository\n' >&2
  exit 1
fi
FIRST="$(git -C "$REPO" rev-parse HEAD)"
fixture_git rm -q docs/old.md && fixture_git commit -qm second
SECOND="$(git -C "$REPO" rev-parse HEAD)"

# plan <file> <line>...: a PLAN.md whose body is the given lines.
plan() {
  local file="$TMP/$1"
  shift
  { printf '## Plan\n\n### Phase 1: Build\n'; printf '%s\n' "$@"; } >"$file"
}

# run <label> <want_exit> <plan file> <pattern> [extra args]
run() {
  local label="$1" want="$2" file="$TMP/$3" pattern="$4" out got
  shift 4
  out="$(bash "$SUT" --repo "$REPO" "$@" "$file" 2>&1)"
  got=$?
  if [[ "$got" -ne "$want" ]]; then
    fail "$label (want exit $want, got $got)"
    printf '%s\n' "$out" | sed 's/^/       /' >&2
    return
  fi
  if [[ -n "$pattern" ]] && ! grep -qE -- "$pattern" <<<"$out"; then
    fail "$label (exit $got as wanted, but no /$pattern/ in output)"
    printf '%s\n' "$out" | sed 's/^/       /' >&2
    return
  fi
  pass "$label"
}

# quiet <label> <plan file>: exit 0 and no per-citation line.
quiet() {
  local out
  if out="$(bash "$SUT" --repo "$REPO" "$TMP/$2" 2>&1)" && ! grep -q '^citation=' <<<"$out"; then
    pass "$1"
  else
    fail "$1"
    printf '%s\n' "$out" | sed 's/^/       /' >&2
  fi
}

if out="$(bash "$SUT" --help 2>&1)" && grep -q 'Citation gate' <<<"$out"; then pass "--help exits 0"; else fail "--help exits 0"; fi
bash "$SUT" >/dev/null 2>&1
if [[ $? -eq 2 ]]; then pass "no argument exits 2"; else fail "no argument exits 2"; fi
bash "$SUT" --repo "$REPO" "$TMP/missing.md" >/dev/null 2>&1
if [[ $? -eq 2 ]]; then pass "a missing plan exits 2"; else fail "a missing plan exits 2"; fi

plan valid.md \
  '- Edit `scripts/build.sh:2` and scripts/build.sh:5.' \
  '- The block at scripts/build.sh:1-5 moves; see (./src/app.ts:3), the last line with no newline.' \
  '- **Sanity Check:** `bash scripts/build.sh` exits 0.'
run "valid citations pass and are counted" 0 valid.md "^citations=4 failed=0 commit=$SECOND status=ok\$"
quiet "a valid citation prints no citation line" valid.md

mkdir -p "$TMP/notrepo"
GIT_CEILING_DIRECTORIES="$TMP" bash "$SUT" --repo "$TMP/notrepo" "$TMP/valid.md" >/dev/null 2>&1
if [[ $? -eq 2 ]]; then pass "a directory outside any repository exits 2"; else fail "a directory outside any repository exits 2"; fi
run "a commit that does not resolve exits 2" 2 valid.md 'not a commit' --commit no-such-ref

plan none.md '- Nothing cited here.'
run "a plan with no citation passes" 0 none.md '^citations=0 failed=0 .*status=ok$'

plan missing.md '- Edit scripts/deploy.sh:3 next.'
run "a citation of a missing file fails" 1 missing.md '^citation=[0-9]+:scripts/deploy.sh:3 status=fail reason=missing-path$'

plan pastend.md '- Edit scripts/build.sh:6 next.'
run "a line past the end of a file fails" 1 pastend.md '^citation=[0-9]+:scripts/build.sh:6 status=fail reason=past-end last-line=5$'

plan rangepast.md '- Move scripts/build.sh:4-9 out.'
run "a range ending past the end fails" 1 rangepast.md 'citation=[0-9]+:scripts/build.sh:4-9 status=fail reason=past-end'

plan nonewline.md '- See src/app.ts:4.'
run "a file with no trailing newline still has its last line counted, and no more" 1 nonewline.md 'reason=past-end last-line=3$'

plan dir.md '- Look in src/lib:1 first.'
run "a directory citation fails" 1 dir.md 'reason=not-a-file$'

plan zero.md '- Edit scripts/build.sh:0.'
run "line zero fails" 1 zero.md 'reason=line-zero$'

plan reversed.md '- Edit scripts/build.sh:4-2.'
run "a reversed range fails" 1 reversed.md 'reason=reversed$'

plan commas.md '- Edit scripts/build.sh:1,3-4,9 next.'
run "each item of a comma list is checked on its own" 1 commas.md '^citations=3 failed=1 '
run "the comma-list item past the end is the one named" 1 commas.md '^citation=[0-9]+:scripts/build.sh:9 status=fail reason=past-end last-line=5$'

plan mixed.md '- Keep scripts/build.sh:2, drop scripts/gone.sh:1.'
run "only the bad citation of several is reported" 1 mixed.md '^citations=2 failed=1 '

plan notcitations.md \
  '- Serve https://example.com:443/x and localhost:8080 at 10:30, ratio 1.5:1.' \
  '- Not repo paths: ~/.bashrc:3, $HOME/x.sh:2, ${ROOT}/x.sh:2, pkg@lib.js:3, scripts/build.sh:12abc.' \
  '- Not citations either: ghcr.io/org/app:1.2.3, ghcr.io/x/y:20-alpine, scripts/build.sh:99:3, localhost:3000/api/x.ts:5, app/[id]/page.tsx:12.'
quiet "URLs, ports, times, home and variable paths, pins, tags and line:col are not citations" notcitations.md

plan fenced.md '```text' 'scripts/nope.sh:9: error: example output' '```' '- Edit scripts/gone.sh:1.'
run "a citation inside a code fence is ignored, and the fence closes" 1 fenced.md '^citations=1 failed=1 '

plan listfence.md '- ```bash' '  grep -n x scripts/nope.sh:9' '  ```' '- Edit scripts/gone.sh:1.'
run "a fence opened in a list item is a fence, and closes" 1 listfence.md '^citations=1 failed=1 '

plan openfence.md '```' '- Edit scripts/gone.sh:1.'
run "a fence left open exits 2" 2 openfence.md 'unterminated fenced block'

plan example.md '- For example scripts/nope.sh:9 <!-- citation-example -->'
quiet "a line marked citation-example is ignored" example.md

printf '## Plan\r\n\r\n```\r\nscripts/nope.sh:9\r\n```\r\n- Edit scripts/gone.sh:1.\r\n- Keep scripts/build.sh:5.\r\n' >"$TMP/crlf.md"
run "a CRLF plan grades the same, fence close included" 1 crlf.md '^citations=2 failed=1 '

plan shapeok.md '```shape src/shape.ts#main L1' 'main' '  helper' '```'
run "a shape anchor that resolves passes and is counted" 0 shapeok.md '^shapes=1 failed=0 warned=0$'

plan shapepath.md '```shape src/nope.ts#main' 'main' '```'
run "a shape anchor on a missing path fails" 1 shapepath.md '^shape=[0-9]+:src/nope.ts#main status=fail reason=shape-missing-path$'

plan shapesym.md '```shape src/shape.ts#absent' 'absent' '```'
run "a shape anchor whose symbol is not in the file fails" 1 shapesym.md '^shape=[0-9]+:src/shape.ts#absent status=fail reason=shape-missing-symbol$'

plan shapenosym.md '```shape src/shape.ts' 'main' '```'
run "a shape anchor on a file with no symbol fails" 1 shapenosym.md 'reason=shape-missing-symbol$'

plan shapepast.md '```shape src/shape.ts#main L9' 'main' '```'
run "a shape anchor line past the end fails" 1 shapepast.md '^shape=[0-9]+:src/shape.ts#main L9 status=fail reason=shape-past-end last-line=3$'

plan shapeline.md '```shape src/shape.ts#main L2' 'main' '```'
run "a shape anchor line that lacks the symbol warns and passes" 0 shapeline.md '^shape=[0-9]+:src/shape.ts#main L2 status=warn reason=shape-line$'

plan shapedir.md '```shape src/lib/' 'src/lib/' '  util.ts' '```'
run "a directory shape anchor needs no symbol" 0 shapedir.md '^shapes=1 failed=0 '

plan shapedirline.md '```shape src/lib/ L1' 'src/lib/' '```'
run "a shape anchor with L<n> on a directory fails" 1 shapedirline.md '^shape=[0-9]+:src/lib/ L1 status=fail reason=shape-not-a-file$'

# A raw US byte (\037) in the info string must not shift the fields bash reads
# back into the line number, where arithmetic would run a command substitution.
plan shapeus.md $'```shape src/shape.ts\037main\037x[$(touch${IFS}'"$TMP"$'/pwned)]' 'main' '```'
run "a shape anchor with a control byte is malformed" 1 shapeus.md 'status=fail reason=shape-malformed$'
if [[ -e "$TMP/pwned" ]]; then
  fail "a shape anchor with a control byte runs no command"
else
  pass "a shape anchor with a control byte runs no command"
fi

plan shapedash.md '```shape src/shape.ts#--dry-run' '--dry-run' '```'
run "a shape symbol starting with - is searched for, not read as an option" 0 shapedash.md '^shapes=1 failed=0 '

plan shapebad.md '```shape src/shape.ts#main L2 extra' 'main' '```'
run "a shape anchor with an extra word is malformed" 1 shapebad.md 'reason=shape-malformed$'

plan shapequoted.md '````markdown' '```shape src/nope.ts#main' 'main' '```' '````'
run "a shape fence quoted in a longer fence is not checked" 0 shapequoted.md '^shapes=0 failed=0 '

plan old.md '- Retire docs/old.md:1.'
run "a file removed after the named commit fails at HEAD" 1 old.md 'reason=missing-path$'
run "the same citation passes at the commit that has the file, and prints that commit" 0 old.md "commit=$FIRST status=ok\$" --commit "$FIRST"

if out="$(cd "$REPO" && bash "$SUT" "$TMP/valid.md" 2>&1)" && grep -q "commit=$SECOND" <<<"$out"; then
  pass "with no --repo the current directory's repository is used"
else
  fail "with no --repo the current directory's repository is used"
fi

printf '\n'
if [[ "$fails" -eq 0 ]]; then
  printf 'All check-plan-citations tests passed.\n'
  exit 0
fi
printf '%d check-plan-citations test(s) failed.\n' "$fails" >&2
exit 1
