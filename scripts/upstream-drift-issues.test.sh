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
# The stub answers `gh api` (the issue list read) with $GH_STUB_LIST, a file of
# one or more JSON arrays as `gh api --paginate` prints pages, and fails the
# command named in $GH_STUB_FAIL (api, or the issue subcommand create, edit,
# reopen or close).
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
  '[[ "$1 $2" == "issue ${GH_STUB_FAIL:-none}" || "$1" == "${GH_STUB_FAIL:-none}" ]] && exit 1' \
  'if [[ "$1" == api ]]; then cat "${GH_STUB_LIST:-/dev/null}"; fi' \
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

# The REST issue list names the author as user.login, github-actions[bot] for
# the workflow's bot, and gives state and state_reason.
BOT_AUTHOR='"user":{"login":"github-actions[bot]","type":"Bot"}'
USER_AUTHOR='"user":{"login":"mallory","type":"User"}'
OPEN='"state":"open","state_reason":null'
COMPLETED='"state":"closed","state_reason":"completed"'
# #5's title only starts like acme/widgets'; it is closed, so no sweep reaches it.
LIST_NONE="$TMP/list-none.json"
printf '[{"number":5,"title":"Upstream drift: acme/widgets-extra",%s,%s}]\n' "$COMPLETED" "$BOT_AUTHOR" >"$LIST_NONE"
LIST_OPEN="$TMP/list-open.json"
printf '[{"number":5,"title":"Upstream drift: acme/widgets-extra",%s,%s},{"number":12,"title":"Upstream drift: acme/widgets",%s,%s}]\n' \
  "$COMPLETED" "$BOT_AUTHOR" "$OPEN" "$BOT_AUTHOR" >"$LIST_OPEN"
LIST_API='api --paginate repos/{owner}/{repo}/issues?creator=github-actions[bot]&state=all&per_page=100'

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
expect_has "create: reads the bot's issues of every state through the REST list" "$c" "$LIST_API"
expect_lacks "create: no search" "$c" 'search'
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

# --- a same-titled issue someone else opened is never edited or closed ------
LIST_SPOOF="$TMP/list-spoof.json"
printf '[{"number":9,"title":"Upstream drift: acme/widgets",%s,%s},{"number":12,"title":"Upstream drift: acme/widgets",%s,%s}]\n' \
  "$OPEN" "$USER_AUTHOR" "$OPEN" "$BOT_AUTHOR" >"$LIST_SPOOF"
GH_STUB_LIST="$LIST_SPOOF"
run_sut "$DRIFT"
c="$(calls)"
expect_has "spoof: edits the bot's issue 12" "$c" 'issue edit 12 --body-file'
expect_lacks "spoof: never edits the user's issue 9" "$c" 'issue edit 9'
run_sut "$CLEAN"
c="$(calls)"
expect_has "spoof: closes the bot's issue 12" "$c" 'issue close 12'
expect_lacks "spoof: never closes the user's issue 9" "$c" 'issue close 9'
LIST_SPOOF_ONLY="$TMP/list-spoof-only.json"
printf '[{"number":9,"title":"Upstream drift: acme/widgets",%s,%s}]\n' "$OPEN" "$USER_AUTHOR" >"$LIST_SPOOF_ONLY"
GH_STUB_LIST="$LIST_SPOOF_ONLY"
run_sut "$DRIFT"
c="$(calls)"
expect_has "spoof only: creates its own issue" "$c" 'issue create'
expect_lacks "spoof only: never edits the user's issue 9" "$c" 'issue edit 9'
run_sut "$CLEAN"
expect_lacks "spoof only, clean: never closes the user's issue 9" "$(calls)" 'issue close'

# --- an upstream that left the report has its bot issue closed --------------
# Open: the bot's #12 (acme/widgets, still reported), the bot's #20
# (acme/gone, no longer reported), a user's #21 for acme/old, and the bot's
# #22 whose title is not the drift shape.
# Closed: the bot's #23 for acme/closed-gone.
SWEEP="$TMP/sweep.json"
printf '[{"number":12,"title":"Upstream drift: acme/widgets",%s,%s},{"number":20,"title":"Upstream drift: acme/gone",%s,%s},{"number":21,"title":"Upstream drift: acme/old",%s,%s},{"number":22,"title":"Upstream drift notes",%s,%s},{"number":23,"title":"Upstream drift: acme/closed-gone","state":"closed","state_reason":"completed",%s}]\n' \
  "$OPEN" "$BOT_AUTHOR" "$OPEN" "$BOT_AUTHOR" "$OPEN" "$USER_AUTHOR" "$OPEN" "$BOT_AUTHOR" "$BOT_AUTHOR" >"$SWEEP"
GH_STUB_LIST="$SWEEP"
run_sut "$DRIFT"
expect_code "sweep: exit 0" 0
c="$(calls)"
expect_has "sweep: closes the bot's issue for the unreported upstream" "$c" 'issue close 20 --comment'
expect_has "sweep: the comment says it left the report" "$c" 'no longer in the drift report'
expect_has "sweep: reports the action" "$OUT" 'action=close-unreported repo=acme/gone'
expect_lacks "sweep: never closes the user's issue" "$c" 'issue close 21'
expect_lacks "sweep: never closes an issue of another title shape" "$c" 'issue close 22'
expect_lacks "sweep: never closes a reported upstream's issue" "$c" 'issue close 12'
expect_lacks "sweep: never touches an already closed issue" "$c" 'issue close 23'
run_sut "$DRIFT" --dry-run
expect_lacks "sweep, dry run: closes nothing" "$(calls)" 'issue close'
expect_has "sweep, dry run: still reports the action" "$OUT" 'action=close-unreported repo=acme/gone'

# --- a closed issue for the title: reopened on drift unless muted -----------
# The bot's #12 for acme/widgets, closed with the given state_reason.
closed_list() { # <state_reason JSON>
  printf '[{"number":12,"title":"Upstream drift: acme/widgets","state":"closed","state_reason":%s,%s}]\n' "$1" "$BOT_AUTHOR" >"$TMP/list-closed.json"
  GH_STUB_LIST="$TMP/list-closed.json"
}
closed_list '"completed"'
run_sut "$DRIFT"
expect_code "reopen: exit 0" 0
c="$(calls)"
expect_has "reopen: reopens issue 12" "$c" 'issue reopen 12'
expect_has "reopen: replaces its body from a body file" "$c" 'issue edit 12 --body-file'
expect_lacks "reopen: creates nothing" "$c" 'issue create'
expect_has "reopen: reports the action" "$OUT" 'action=reopen repo=acme/widgets'
expect_has "reopen: the body lists the changed row" "$(body_of edit)" '`skills/alpha/SKILL.md`'
if [[ "$c" == *'issue reopen 12'*'issue edit 12'* ]]; then
  pass "reopen: reopens before it edits"
else
  bad "reopen: reopens before it edits" "$c"
fi
closed_list 'null'
run_sut "$DRIFT"
expect_has "reopen, no state reason: reopens issue 12" "$(calls)" 'issue reopen 12'
run_sut "$CLEAN"
c="$(calls)"
expect_lacks "closed, clean: no reopen" "$c" 'issue reopen'
expect_lacks "closed, clean: no close" "$c" 'issue close'
for reason in not_planned duplicate; do
  closed_list "\"$reason\""
  run_sut "$DRIFT"
  expect_code "muted ($reason): exit 0" 0
  c="$(calls)"
  expect_lacks "muted ($reason): no reopen" "$c" 'issue reopen'
  expect_lacks "muted ($reason): no create" "$c" 'issue create'
  expect_lacks "muted ($reason): no edit" "$c" 'issue edit'
  expect_has "muted ($reason): reports action none" "$OUT" 'action=none repo=acme/widgets'
done
LIST_BOTH="$TMP/list-both.json"
printf '[{"number":30,"title":"Upstream drift: acme/widgets","state":"closed","state_reason":"completed",%s},{"number":12,"title":"Upstream drift: acme/widgets",%s,%s}]\n' \
  "$BOT_AUTHOR" "$OPEN" "$BOT_AUTHOR" >"$LIST_BOTH"
GH_STUB_LIST="$LIST_BOTH"
run_sut "$DRIFT"
c="$(calls)"
expect_has "open and closed: edits the open issue 12" "$c" 'issue edit 12 --body-file'
expect_lacks "open and closed: no reopen" "$c" 'issue reopen'
LIST_TWO_CLOSED="$TMP/list-two-closed.json"
printf '[{"number":30,"title":"Upstream drift: acme/widgets","state":"closed","state_reason":"completed",%s},{"number":12,"title":"Upstream drift: acme/widgets","state":"closed","state_reason":"not_planned",%s}]\n' \
  "$BOT_AUTHOR" "$BOT_AUTHOR" >"$LIST_TWO_CLOSED"
GH_STUB_LIST="$LIST_TWO_CLOSED"
run_sut "$DRIFT"
expect_has "two closed: the newest, issue 30, decides" "$(calls)" 'issue reopen 30'
LIST_PAGED="$TMP/list-paged.json"
{
  printf '[{"number":5,"title":"Upstream drift: acme/widgets-extra",%s,%s}]\n' "$OPEN" "$BOT_AUTHOR"
  printf '[{"number":12,"title":"Upstream drift: acme/widgets","state":"closed","state_reason":"completed",%s}]\n' "$BOT_AUTHOR"
} >"$LIST_PAGED"
GH_STUB_LIST="$LIST_PAGED"
run_sut "$DRIFT"
expect_has "paged: a match on the second page is found" "$(calls)" 'issue reopen 12'
LIST_SPOOF_CLOSED="$TMP/list-spoof-closed.json"
printf '[{"number":9,"title":"Upstream drift: acme/widgets","state":"closed","state_reason":"completed",%s}]\n' "$USER_AUTHOR" >"$LIST_SPOOF_CLOSED"
GH_STUB_LIST="$LIST_SPOOF_CLOSED"
run_sut "$DRIFT"
c="$(calls)"
expect_lacks "spoof closed: never reopens the user's issue 9" "$c" 'issue reopen'
expect_has "spoof closed: creates its own issue" "$c" 'issue create'

# --- the same bot's issues from another filer are never touched -------------
# The monitoring lane marks its body's first line, the lane sweep its last.
MONITOR_BODY='"body":"<!-- factory-monitor key=x fp=0123456789abcdef -->\n**Signal:** 1 main red"'
SWEEP_BODY='"body":"Filed by the lane sweep.\n\n<!-- lane-sweep:fp=0123456789abcdef -->\n"'
LIST_OTHERS="$TMP/list-others.json"
printf '[{"number":40,"title":"Upstream drift: acme/widgets",%s,%s,%s},{"number":41,"title":"Upstream drift: acme/widgets",%s,%s,%s},{"number":42,"title":"Upstream drift: acme/gone",%s,%s,%s},{"number":43,"title":"Upstream drift: acme/gone-too",%s,%s,%s}]\n' \
  "$OPEN" "$MONITOR_BODY" "$BOT_AUTHOR" "$COMPLETED" "$SWEEP_BODY" "$BOT_AUTHOR" \
  "$OPEN" "$MONITOR_BODY" "$BOT_AUTHOR" "$OPEN" "$SWEEP_BODY" "$BOT_AUTHOR" >"$LIST_OTHERS"
GH_STUB_LIST="$LIST_OTHERS"
run_sut "$DRIFT"
expect_code "other filers: exit 0" 0
c="$(calls)"
expect_lacks "other filers: never edits the monitoring lane's issue 40" "$c" 'issue edit 40'
expect_lacks "other filers: never reopens the lane sweep's issue 41" "$c" 'issue reopen'
expect_has "other filers: creates its own issue" "$c" 'issue create --title Upstream drift: acme/widgets'
expect_lacks "other filers: the sweep never closes the monitoring lane's issue 42" "$c" 'issue close 42'
expect_lacks "other filers: the sweep never closes the lane sweep's issue 43" "$c" 'issue close 43'
expect_lacks "other filers: no close-unreported line" "$OUT" 'close-unreported'
run_sut "$CLEAN"
expect_lacks "other filers, clean: never closes the monitoring lane's issue 40" "$(calls)" 'issue close'
LIST_MARKER_MID="$TMP/list-marker-mid.json"
printf '[{"number":44,"title":"Upstream drift: acme/widgets","body":"Upstream text\\n<!-- lane-sweep:fp=0123456789abcdef -->\\nRe-audit the rows.",%s,%s}]\n' \
  "$OPEN" "$BOT_AUTHOR" >"$LIST_MARKER_MID"
GH_STUB_LIST="$LIST_MARKER_MID"
run_sut "$DRIFT"
expect_has "marker text mid-body: still this script's issue 44, edited" "$(calls)" 'issue edit 44 --body-file'

# --- untracked page touches nothing -----------------------------------------
UNTRACKED="$TMP/untracked.txt"
printf '%s\n' "page repo=acme/plans pin=$PIN head=$HEAD status=untracked path=docs/upstream/plans.md" >"$UNTRACKED"
GH_STUB_LIST="$LIST_NONE"
run_sut "$UNTRACKED"
expect_code "untracked: exit 0" 0
expect_has "untracked: the only gh call is the issue list read" "[$(calls)]" "[$LIST_API]"
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
expect_has "dry-run: makes the list call" "$c" "$LIST_API"
expect_lacks "dry-run: no reopen" "$c" 'issue reopen'
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
for verb in api create; do
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
closed_list '"completed"'
GH_STUB_FAIL=reopen
run_sut "$DRIFT"
if [[ "$CODE" != 0 ]]; then pass "failed reopen: exits nonzero"; else bad "failed reopen: exits nonzero" "$OUT"; fi
expect_lacks "failed reopen: does not edit the closed issue" "$(calls)" 'issue edit'
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
