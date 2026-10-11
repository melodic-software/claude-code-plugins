#!/usr/bin/env bash
# Black-box suite for upstream-drift-issues.sh.
#
#   bash scripts/upstream-drift-issues.test.sh
#
# Hermetic: a stub `gh` first on PATH records every call (one argv element per
# line) and copies any --body-file into the log, so no case reaches GitHub.
# Report lines are written by hand in the form check-upstream-drift.sh --report
# prints (docs/conventions/upstream-drift/README.md, the --report row); titles,
# issue numbers and the 60,000-character cap are literals of the plan.
# shellcheck disable=SC2016  # stub source and expected code spans are literal text; expansion is never wanted
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
SUT="$SCRIPT_DIR/upstream-drift-issues.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh" || exit 2

TMP="$(mktemp -d)" || exit 2
cleanup() { [[ -n "$TMP" && "$TMP" != / ]] && rm -rf "$TMP"; }
trap cleanup EXIT

STUB="$TMP/bin"
mkdir -p "$STUB"
# The stub answers `issue list` with $GH_STUB_LIST (a JSON file) and fails the
# subcommand named in $GH_STUB_FAIL (list, create, edit or close).
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'n=$(($(cat "$GH_STUB_LOG/count" 2>/dev/null || echo 0) + 1))' \
  'printf "%s\n" "$n" >"$GH_STUB_LOG/count"' \
  'printf "%s\n" "$@" >"$GH_STUB_LOG/call.$n"' \
  'prev=""' \
  'for a in "$@"; do' \
  '  [[ "$prev" == --body-file ]] && cp "$a" "$GH_STUB_LOG/body.$n"' \
  '  prev="$a"' \
  'done' \
  '[[ "$1 $2" == "issue ${GH_STUB_FAIL:-none}" ]] && exit 1' \
  'if [[ "$1 $2" == "issue list" ]]; then cat "${GH_STUB_LIST:-/dev/null}"; fi' \
  'exit 0' >"$STUB/gh"
chmod +x "$STUB/gh"

PIN=aaaaaaaaaaaa
HEAD=bbbbbbbbbbbb
LOG=""
OUT=""
CODE=0

# run_sut <report-file> [sut args...]: runs the script with the stub, in a
# fresh log; leaves stdout+stderr in OUT and the exit code in CODE.
run_sut() {
  local report="$1"
  shift
  LOG="$(mktemp -d "$TMP/log.XXXXXX")" || exit 2
  OUT="$(env PATH="$STUB:$PATH" GH_STUB_LOG="$LOG" \
    GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=acme/site GITHUB_RUN_ID=777 \
    ${GH_STUB_LIST:+GH_STUB_LIST="$GH_STUB_LIST"} ${GH_STUB_FAIL:+GH_STUB_FAIL="$GH_STUB_FAIL"} \
    ${COMPAT:+BASH_COMPAT="$COMPAT"} \
    bash "$SUT" "$@" "$report" 2>&1)"
  CODE=$?
}

# calls: every recorded call, one per line, argv joined by spaces.
calls() {
  local i n
  n="$(cat "$LOG/count" 2>/dev/null || echo 0)"
  for ((i = 1; i <= n; i++)); do
    paste -sd' ' "$LOG/call.$i"
  done
}

# body_of <verb>: the body file recorded for the first call whose verb matches.
body_of() {
  local i n
  n="$(cat "$LOG/count" 2>/dev/null || echo 0)"
  for ((i = 1; i <= n; i++)); do
    if [[ "$(sed -n 2p "$LOG/call.$i")" == "$1" && -f "$LOG/body.$i" ]]; then
      cat "$LOG/body.$i"
      return 0
    fi
  done
  return 1
}

expect_code() { # <name> <expected>
  if [[ "$CODE" == "$2" ]]; then pass "$1"; else bad "$1" "exit $CODE, want $2; output: $OUT"; fi
}
expect_has() { # <name> <haystack> <needle>
  if [[ "$2" == *"$3"* ]]; then pass "$1"; else bad "$1" "missing '$3' in: $2"; fi
}
expect_lacks() { # <name> <haystack> <needle>
  if [[ "$2" != *"$3"* ]]; then pass "$1"; else bad "$1" "unexpected '$3' in: $2"; fi
}

LIST_NONE="$TMP/list-none.json"
printf '[{"number":5,"title":"Upstream drift: acme/widgets-extra"}]\n' >"$LIST_NONE"
LIST_OPEN="$TMP/list-open.json"
printf '[{"number":5,"title":"Upstream drift: acme/widgets-extra"},{"number":12,"title":"Upstream drift: acme/widgets"}]\n' >"$LIST_OPEN"

DRIFT="$TMP/drift.txt"
printf '%s\n' \
  "page repo=acme/widgets pin=$PIN head=$HEAD status=drift path=docs/upstream/widgets.md" \
  "row line=7 status=M path=skills/alpha/SKILL.md" \
  "row line=8 status=unchanged path=skills/gamma/SKILL.md" \
  "new-unit path=skills/delta/SKILL.md" \
  "removed-unit path=skills/beta" >"$DRIFT"
CLEAN="$TMP/clean.txt"
printf '%s\n' \
  "page repo=acme/widgets pin=$PIN head=$HEAD status=clean path=docs/upstream/widgets.md" \
  "row line=7 status=unchanged path=skills/alpha/SKILL.md" >"$CLEAN"

# --- create: no exact-title issue open, drift -------------------------------
GH_STUB_LIST="$LIST_NONE"
run_sut "$DRIFT"
expect_code "create: exit 0" 0
c="$(calls)"
expect_has "create: list searches the exact title" "$c" 'issue list --state open --search in:title "Upstream drift: acme/widgets" --json number,title'
expect_has "create: creates the titled issue from a body file" "$c" 'issue create --title Upstream drift: acme/widgets --body-file'
expect_lacks "create: a near-match title is not edited" "$c" 'issue edit'
body="$(body_of create)"
expect_has "create: body lists the changed row in a code span" "$body" '`skills/alpha/SKILL.md`'
expect_has "create: body lists the new unit" "$body" '`skills/delta/SKILL.md`'
expect_has "create: body lists the removed unit" "$body" '`skills/beta`'
expect_lacks "create: unchanged rows are left out" "$body" 'skills/gamma'
expect_has "create: body names the pin" "$body" "\`$PIN\`"
expect_has "create: body names the head" "$body" "\`$HEAD\`"
expect_has "create: body names the run URL" "$body" 'https://github.com/acme/site/actions/runs/777'
expect_lacks "create: no label flag" "$c" '--label'
expect_lacks "create: no assignee flag" "$c" '--assignee'

# --- edit: exact-title issue open, drift ------------------------------------
GH_STUB_LIST="$LIST_OPEN"
run_sut "$DRIFT"
expect_code "edit: exit 0" 0
c="$(calls)"
expect_has "edit: edits issue 12 from a body file" "$c" 'issue edit 12 --body-file'
expect_lacks "edit: creates nothing" "$c" 'issue create'
expect_lacks "edit: never touches the near-match issue 5" "$c" 'issue edit 5'

# --- close: exact-title issue open, clean -----------------------------------
run_sut "$CLEAN"
expect_code "close: exit 0" 0
c="$(calls)"
expect_has "close: closes issue 12 with a clean comment" "$c" 'issue close 12 --comment'
expect_has "close: the comment says clean" "$c" 'clean'
expect_lacks "close: no create" "$c" 'issue create'
expect_lacks "close: no edit" "$c" 'issue edit'

# --- clean with nothing open: no write --------------------------------------
GH_STUB_LIST="$LIST_NONE"
run_sut "$CLEAN"
expect_code "clean, none open: exit 0" 0
c="$(calls)"
expect_lacks "clean, none open: no create" "$c" 'issue create'
expect_lacks "clean, none open: no close" "$c" 'issue close'

# --- untracked page touches nothing -----------------------------------------
UNTRACKED="$TMP/untracked.txt"
printf '%s\n' "page repo=acme/plans pin=$PIN head=$HEAD status=untracked path=docs/upstream/plans.md" >"$UNTRACKED"
GH_STUB_LIST="$LIST_OPEN"
run_sut "$UNTRACKED"
expect_code "untracked: exit 0" 0
expect_has "untracked: no gh call at all" "[$(calls)]" '[]'
expect_has "untracked: reports action none" "$OUT" 'action=none repo=acme/plans'

# --- body over the cap is cut with a job-summary pointer --------------------
BIG="$TMP/big.txt"
{
  printf '%s\n' "page repo=acme/widgets pin=$PIN head=$HEAD status=drift path=docs/upstream/widgets.md"
  for ((i = 1; i <= 1500; i++)); do
    printf 'row line=%d status=A path=skills/a-rather-long-directory-name-for-padding/file-%04d.md\n' "$i" "$i"
  done
} >"$BIG"
GH_STUB_LIST="$LIST_NONE"
run_sut "$BIG"
expect_code "cap: exit 0" 0
body="$(body_of create)"
if ((${#body} <= 60000 && ${#body} > 50000)); then
  pass "cap: body is cut to at most 60,000 characters"
else
  bad "cap: body is cut to at most 60,000 characters" "length ${#body}"
fi
expect_has "cap: body points at the job summary" "$body" 'job summary'
expect_has "cap: the pointer carries the run URL" "$body" 'https://github.com/acme/site/actions/runs/777'
expect_lacks "cap: the last row is cut" "$body" 'file-1500.md'

# --- hostile path: @, backticks and ${{ inside a code span ------------------
HOSTILE="$TMP/hostile.txt"
printf '%s\n' \
  "page repo=acme/widgets pin=$PIN head=$HEAD status=drift path=docs/upstream/widgets.md" \
  'row line=7 status=M path=skills/@octocat/`rm -rf`/${{ github.token }}.md' >"$HOSTILE"
run_sut "$HOSTILE"
expect_code "hostile: exit 0" 0
body="$(body_of create)"
expect_has "hostile: path sits in one code span, backticks replaced" "$body" "\`skills/@octocat/'rm -rf'/\${{ github.token }}.md\`"
expect_lacks "hostile: no raw backtick from the path survives" "$body" '`rm -rf`'

# --- path holding a space, = and | is parsed whole, on the right repo --------
ODD="$TMP/odd.txt"
printf '%s\n' \
  "page repo=acme/widgets pin=$PIN head=$HEAD status=clean path=docs/upstream/widgets.md" \
  "page repo=other/tools pin=$PIN head=$HEAD status=drift path=docs/upstream/my tools.md" \
  "row line=4 status=M path=dir a=b|c status=X path=d.md" >"$ODD"
run_sut "$ODD"
expect_code "odd path: exit 0" 0
c="$(calls)"
expect_has "odd path: the drifted repo gets the issue" "$c" 'issue create --title Upstream drift: other/tools'
expect_lacks "odd path: the clean repo gets no issue" "$c" 'Upstream drift: acme/widgets --body-file'
body="$(body_of create)"
expect_has "odd path: the path is kept whole" "$body" '`dir a=b|c status=X path=d.md`'
expect_has "odd path: the page path with a space is kept whole" "$body" '`docs/upstream/my tools.md`'

# --- a line breaking the field order exits nonzero with no write ------------
for shape in split reordered orphan; do
  BROKEN="$TMP/broken-$shape.txt"
  case "$shape" in
  split)
    printf '%s\n' "page repo=acme/widgets pin=$PIN head=$HEAD status=drift path=docs/upstream/widgets.md" \
      "row line=7 status=M path=skills/first" "half/SKILL.md" >"$BROKEN"
    ;;
  reordered)
    printf '%s\n' "page repo=acme/widgets pin=$PIN head=$HEAD status=drift path=docs/upstream/widgets.md" \
      "row status=M line=7 path=skills/alpha/SKILL.md" >"$BROKEN"
    ;;
  orphan)
    printf '%s\n' "row line=7 status=M path=skills/alpha/SKILL.md" >"$BROKEN"
    ;;
  *) exit 2 ;;
  esac
  run_sut "$BROKEN"
  if [[ "$CODE" != 0 ]]; then pass "broken ($shape): exits nonzero"; else bad "broken ($shape): exits nonzero" "$OUT"; fi
  expect_has "broken ($shape): no gh call at all" "[$(calls)]" '[]'
done

# --- --dry-run: list calls only, one action line per repository -------------
MIXED="$TMP/mixed.txt"
printf '%s\n' \
  "page repo=acme/widgets pin=$PIN head=$HEAD status=drift path=docs/upstream/widgets.md" \
  "row line=7 status=M path=skills/alpha/SKILL.md" \
  "page repo=acme/widgets pin=$PIN head=$HEAD status=clean path=docs/upstream/widgets-two.md" \
  "page repo=acme/plans pin=$PIN head=$HEAD status=untracked path=docs/upstream/plans.md" >"$MIXED"
GH_STUB_LIST="$LIST_OPEN"
run_sut "$MIXED" --dry-run
expect_code "dry-run: exit 0" 0
c="$(calls)"
expect_has "dry-run: makes the list call" "$c" 'issue list'
expect_lacks "dry-run: no create" "$c" 'issue create'
expect_lacks "dry-run: no edit" "$c" 'issue edit'
expect_lacks "dry-run: no close" "$c" 'issue close'
want=$'action=edit repo=acme/widgets\naction=none repo=acme/plans'
if [[ "$OUT" == "$want" ]]; then
  pass "dry-run: prints exactly one action line per repository"
else
  bad "dry-run: prints exactly one action line per repository" "got: $OUT"
fi
GH_STUB_LIST="$LIST_NONE"
run_sut "$DRIFT" --dry-run
expect_has "dry-run: create when none is open" "$OUT" 'action=create repo=acme/widgets'
run_sut "$CLEAN" --dry-run
expect_has "dry-run: none when clean and none open" "$OUT" 'action=none repo=acme/widgets'
GH_STUB_LIST="$LIST_OPEN"
run_sut "$CLEAN" --dry-run
expect_has "dry-run: close when clean and one is open" "$OUT" 'action=close repo=acme/widgets'

# --- a failed gh call fails the run -----------------------------------------
for verb in list create; do
  GH_STUB_LIST="$LIST_NONE" GH_STUB_FAIL="$verb"
  run_sut "$DRIFT"
  if [[ "$CODE" != 0 ]]; then pass "failed $verb: exits nonzero"; else bad "failed $verb: exits nonzero" "$OUT"; fi
done
GH_STUB_LIST="$LIST_OPEN" GH_STUB_FAIL=edit
run_sut "$DRIFT"
if [[ "$CODE" != 0 ]]; then pass "failed edit: exits nonzero"; else bad "failed edit: exits nonzero" "$OUT"; fi
GH_STUB_FAIL=close
run_sut "$CLEAN"
if [[ "$CODE" != 0 ]]; then pass "failed close: exits nonzero"; else bad "failed close: exits nonzero" "$OUT"; fi
GH_STUB_FAIL=""

# --- untrusted text never reaches shell evaluation (bash 5.1 semantics) -----
PWNED="$TMP/pwned"
INJECT="$TMP/inject.txt"
printf '%s\n' \
  "page repo=acme/widgets pin=$PIN head=$HEAD status=drift path=docs/upstream/\$(touch $PWNED).md" \
  "row line=7 status=M path=skills/\$(touch $PWNED)/x[\$(touch $PWNED)].md" >"$INJECT"
GH_STUB_LIST="$LIST_NONE" COMPAT=51
run_sut "$INJECT"
COMPAT=""
expect_code "inject: exit 0" 0
if [[ ! -e "$PWNED" ]]; then pass "inject: no command in a path ran"; else bad "inject: no command in a path ran" "$PWNED exists"; fi
body="$(body_of create)"
expect_has "inject: the path lands literally" "$body" "\`skills/\$(touch $PWNED)/x[\$(touch $PWNED)].md\`"

# --- usage ------------------------------------------------------------------
LOG="$(mktemp -d "$TMP/log.XXXXXX")"
OUT="$(bash "$SUT" --help 2>&1)"
CODE=$?
expect_code "--help: exit 0" 0
expect_has "--help: prints usage" "$OUT" 'usage:'
run_sut "$TMP/does-not-exist.txt"
expect_code "missing report file: exit 2" 2
expect_has "missing report file: no gh call" "[$(calls)]" '[]'

test_harness::report
