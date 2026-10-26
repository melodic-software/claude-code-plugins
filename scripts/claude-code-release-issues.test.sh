#!/usr/bin/env bash
# Black-box suite for claude-code-release-issues.sh.
#
#   bash scripts/claude-code-release-issues.test.sh
#
# Hermetic: a stub `gh` first on PATH records every call (one argv element per
# line) and copies any --body-file into the log, so no case reaches GitHub.
# Status files are written by hand in the form changelog-status.sh prints (its
# header, "Output"), and the last cases feed the filer what changelog-status.sh
# itself prints for a fixture ledger and changelog, so the two cannot drift apart.
# test-scope: plugins/harness-ops/skills/changelog/scripts/changelog-status.sh
# shellcheck disable=SC2016  # stub source and expected code spans are literal text
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
SUT="$SCRIPT_DIR/claude-code-release-issues.sh"
STATUS_SH="$SCRIPT_DIR/../plugins/harness-ops/skills/changelog/scripts/changelog-status.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh" || exit 2

TMP="$(mktemp -d)" || exit 2
cleanup() { [[ -n "$TMP" && "$TMP" != / ]] && rm -rf "$TMP"; }
trap cleanup EXIT

STUB="$TMP/bin"
mkdir -p "$STUB"
# The stub answers `gh issue list` with $GH_STUB_LIST (a JSON array) and fails
# the issue subcommand named in $GH_STUB_FAIL (list or create).
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

LOG=""
OUT=""
CODE=0

# run_sut <status-file> [sut args...]: runs the script with the stub, in a
# fresh log; leaves stdout+stderr in OUT and the exit code in CODE.
run_sut() {
  local status="$1"
  shift
  LOG="$(mktemp -d "$TMP/log.XXXXXX")" || exit 2
  OUT="$(env PATH="$STUB:$PATH" GH_STUB_LOG="$LOG" \
    GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=acme/site GITHUB_RUN_ID=777 \
    ${GH_STUB_LIST:+GH_STUB_LIST="$GH_STUB_LIST"} ${GH_STUB_FAIL:+GH_STUB_FAIL="$GH_STUB_FAIL"} \
    bash "$SUT" "$@" "$status" 2>&1)"
  CODE=$?
}

calls() {
  local i n
  n="$(cat "$LOG/count" 2>/dev/null || echo 0)"
  for ((i = 1; i <= n; i++)); do
    paste -sd' ' "$LOG/call.$i"
  done
}

creates() { calls | grep -c '^issue create' || true; }

# body_n <k>: the body file of the k-th create call.
body_n() {
  local i n k=0
  n="$(cat "$LOG/count" 2>/dev/null || echo 0)"
  for ((i = 1; i <= n; i++)); do
    if [[ "$(sed -n 2p "$LOG/call.$i")" == create ]]; then
      k=$((k + 1))
      if ((k == $1)) && [[ -f "$LOG/body.$i" ]]; then
        cat "$LOG/body.$i"
        return 0
      fi
    fi
  done
  return 1
}

expect_code() { # <name> <expected>
  if [[ "$CODE" == "$2" ]]; then pass "$1"; else bad "$1" "exit $CODE, want $2; output: $OUT"; fi
}
expect_eq() { # <name> <got> <want>
  if [[ "$2" == "$3" ]]; then pass "$1"; else bad "$1" "got '$2', want '$3'"; fi
}
expect_has() { # <name> <haystack> <needle>
  if [[ "$2" == *"$3"* ]]; then pass "$1"; else bad "$1" "missing '$3' in: $2"; fi
}
expect_lacks() { # <name> <haystack> <needle>
  if [[ "$2" != *"$3"* ]]; then pass "$1"; else bad "$1" "unexpected '$3' in: $2"; fi
}

LEDGER=/repo/docs/upstream/claude-code.md
CAP_TITLE='Claude Code changelog: unread releases beyond the replay cap'
RECOMMEND="recommend: replay cost scales with items and the current docs carry the cumulative state. Run a docs-conformance recheck of the components, then set the marker in $LEDGER to 2.1.320 and diff only from there"

# status <range line> [more lines...]: a status file with the fixed head lines.
status() {
  local f
  f="$(mktemp "$TMP/status.XXXXXX")" || exit 2
  {
    printf '%s\n' "last-applied: 2.1.296" "source: ledger:$LEDGER" "ledger: $LEDGER (present)" \
      "installed: unknown" "latest: 2.1.310"
    printf '%s\n' "$@"
  } >"$f"
  printf '%s' "$f"
}

LIST_EMPTY="$TMP/list-empty.json"
printf '[]\n' >"$LIST_EMPTY"
LIST_ONE="$TMP/list-one.json"
# A closed issue with the exact title, and one whose title only starts like another version's.
printf '[{"number":40,"title":"Claude Code changelog: 2.1.297","state":"CLOSED"},{"number":41,"title":"Claude Code changelog: 2.1.2980","state":"OPEN"}]\n' >"$LIST_ONE"
LIST_CAP_OPEN="$TMP/list-cap-open.json"
printf '[{"number":50,"title":"%s","state":"OPEN"}]\n' "$CAP_TITLE" >"$LIST_CAP_OPEN"
LIST_CAP_CLOSED="$TMP/list-cap-closed.json"
printf '[{"number":50,"title":"%s","state":"CLOSED"}]\n' "$CAP_TITLE" >"$LIST_CAP_CLOSED"

# --- marker equal to newest: nothing to file ----------------------------------
GH_STUB_LIST="$LIST_EMPTY"
run_sut "$(status 'range: up to date')"
expect_code "up to date: exit 0" 0
expect_eq "up to date: no gh call" "$(calls)" ""

# --- one unread release -------------------------------------------------------
run_sut "$(status 'range: 2.1.297..2.1.297 (1 releases, 4 core items)' 'releases: 2.1.297' 'cap: within budget (10 releases / 300 items)')"
expect_code "one unread: exit 0" 0
expect_eq "one unread: one issue filed" "$(creates)" 1
c="$(calls)"
expect_has "one unread: reads issues of every state" "$c" 'issue list --state all'
expect_has "one unread: titled with the version" "$c" 'issue create --title Claude Code changelog: 2.1.297 --body-file'
expect_lacks "one unread: no label" "$c" '--label'
body="$(body_n 1)"
expect_has "one unread: body asks for apply over the release" "$body" '`/harness-ops:changelog apply v2.1.297`'
expect_has "one unread: body names the marker" "$body" '`2.1.296`'
expect_has "one unread: body names the run" "$body" 'https://github.com/acme/site/actions/runs/777'
expect_lacks "one unread: body carries no agent-ready" "$body" 'agent-ready'

# --- an existing issue with the same title (closed) ---------------------------
GH_STUB_LIST="$LIST_ONE"
run_sut "$(status 'range: 2.1.297..2.1.297 (1 releases, 4 core items)' 'releases: 2.1.297' 'cap: within budget (10 releases / 300 items)')"
expect_code "existing title: exit 0" 0
expect_eq "existing title: nothing filed" "$(creates)" 0

# --- two unread releases; a near-match title does not count -------------------
GH_STUB_LIST="$LIST_EMPTY"
run_sut "$(status 'range: 2.1.297..2.1.298 (2 releases, 9 core items)' 'releases: 2.1.297 2.1.298' 'cap: within budget (10 releases / 300 items)')"
expect_code "two unread: exit 0" 0
expect_eq "two unread: two issues filed" "$(creates)" 2
c="$(calls)"
expect_has "two unread: first title" "$c" 'Claude Code changelog: 2.1.297 --body-file'
expect_has "two unread: second title" "$c" 'Claude Code changelog: 2.1.298 --body-file'
expect_eq "two unread: one issue list read" "$(calls | grep -c '^issue list')" 1

GH_STUB_LIST="$LIST_ONE"
run_sut "$(status 'range: 2.1.297..2.1.298 (2 releases, 9 core items)' 'releases: 2.1.297 2.1.298' 'cap: within budget (10 releases / 300 items)')"
expect_eq "one of two exists: only the other is filed" "$(creates)" 1
expect_has "one of two exists: the near-match title does not hide 2.1.298" "$(calls)" 'Claude Code changelog: 2.1.298 --body-file'

# --- over the cap: one beyond-the-cap issue, no per-release issue -------------
GH_STUB_LIST="$LIST_EMPTY"
run_sut "$(status 'range: 2.1.297..2.1.320 (24 releases, 410 core items)' 'releases: (24 releases, list omitted beyond the cap)' 'cap: exceeded (10 releases / 300 items)' "$RECOMMEND")"
expect_code "over cap: exit 0" 0
expect_eq "over cap: one issue filed" "$(creates)" 1
c="$(calls)"
expect_has "over cap: titled beyond the cap" "$c" "issue create --title $CAP_TITLE --body-file"
expect_lacks "over cap: no per-release issue" "$c" 'Claude Code changelog: 2.1.'
expect_lacks "over cap: no label" "$c" '--label'
body="$(body_n 1)"
expect_has "over cap: body holds the recommend line" "$body" "$RECOMMEND"
expect_has "over cap: body names the range" "$body" '2.1.297..2.1.320'

# Items alone over the cap: the list is printed, still no per-release issue.
run_sut "$(status 'range: 2.1.297..2.1.299 (3 releases, 400 core items)' 'releases: 2.1.297 2.1.298 2.1.299' 'cap: exceeded (10 releases / 300 items)' "$RECOMMEND")"
expect_eq "over cap by items: one issue filed" "$(creates)" 1
expect_lacks "over cap by items: no per-release issue" "$(calls)" 'Claude Code changelog: 2.1.'

GH_STUB_LIST="$LIST_CAP_OPEN"
run_sut "$(status 'range: 2.1.297..2.1.320 (24 releases, 410 core items)' 'releases: (24 releases, list omitted beyond the cap)' 'cap: exceeded (10 releases / 300 items)' "$RECOMMEND")"
expect_code "over cap, issue open: exit 0" 0
expect_eq "over cap, issue open: nothing filed" "$(creates)" 0

GH_STUB_LIST="$LIST_CAP_CLOSED"
run_sut "$(status 'range: 2.1.297..2.1.320 (24 releases, 410 core items)' 'releases: (24 releases, list omitted beyond the cap)' 'cap: exceeded (10 releases / 300 items)' "$RECOMMEND")"
expect_eq "over cap, issue only closed: filed again" "$(creates)" 1

# --- not computed: non-zero, nothing filed ------------------------------------
GH_STUB_LIST="$LIST_EMPTY"
run_sut "$(status 'range: not computed (fetch of the changelog page failed (http-503); pass --changelog <file> or retry)')"
expect_code "not computed: exit 2" 2
expect_eq "not computed: no gh call" "$(calls)" ""
expect_has "not computed: says why" "$OUT" 'not computed'

# A missing marker is the same case.
f="$(mktemp "$TMP/status.XXXXXX")"
printf '%s\n' 'last-applied: none' 'source: none' "ledger: $LEDGER (absent)" 'installed: unknown' 'latest: 2.1.310' \
  'range: 2.1.1..2.1.310 (300 releases, 9000 core items)' 'releases: (300 releases, list omitted beyond the cap)' \
  'cap: exceeded (10 releases / 300 items)' "$RECOMMEND" >"$f"
run_sut "$f"
expect_code "no marker: exit 2" 2
expect_eq "no marker: no gh call" "$(calls)" ""

# --- malformed input files nothing --------------------------------------------
run_sut "$(status 'range: 2.1.297..2.1.297 (1 releases, 4 core items)' 'releases: 2.1.297;rm' 'cap: within budget (10 releases / 300 items)')"
expect_code "bad version: exit 2" 2
expect_eq "bad version: no gh call" "$(calls)" ""

run_sut "$(status 'range: 2.1.297..2.1.297 (1 releases, 4 core items)' 'releases: 2.1.297')"
expect_code "no cap line: exit 2" 2
expect_eq "no cap line: no gh call" "$(calls)" ""

run_sut "$TMP/does-not-exist.txt"
expect_code "missing status file: exit 2" 2

# --- gh failures ----------------------------------------------------------------
GH_STUB_FAIL=list
run_sut "$(status 'range: 2.1.297..2.1.297 (1 releases, 4 core items)' 'releases: 2.1.297' 'cap: within budget (10 releases / 300 items)')"
expect_code "failed list: exit 1" 1
expect_eq "failed list: nothing filed" "$(creates)" 0
GH_STUB_FAIL=create
run_sut "$(status 'range: 2.1.297..2.1.298 (2 releases, 9 core items)' 'releases: 2.1.297 2.1.298' 'cap: within budget (10 releases / 300 items)')"
expect_code "failed create: exit 1" 1
expect_eq "failed create: the other release is still tried" "$(calls | grep -c '^issue create')" 2
unset GH_STUB_FAIL

# --- dry run reads the list and writes nothing --------------------------------
run_sut "$(status 'range: 2.1.297..2.1.298 (2 releases, 9 core items)' 'releases: 2.1.297 2.1.298' 'cap: within budget (10 releases / 300 items)')" --dry-run
expect_code "dry run: exit 0" 0
expect_eq "dry run: nothing filed" "$(creates)" 0
expect_has "dry run: prints the planned creates" "$OUT" 'action=create title=Claude Code changelog: 2.1.298'

# --- against changelog-status.sh's own output ----------------------------------
FIX="$TMP/fixture"
mkdir -p "$FIX"
printf '%s\n' '# Ledger' '' '**Last audited upstream state:** changelog through `2.1.296` (published 2026-10-09)' >"$FIX/ledger.md"
{
  printf '%s\n' '# Claude Code changelog' ''
  for v in 2.1.298 2.1.297 2.1.296; do
    printf '<Update label="%s">\n* item one\n* item two\n</Update>\n\n' "$v"
  done
} >"$FIX/changelog.md"
real_status() { # <ledger> <changelog> [extra args]: changelog-status.sh output as a file
  local f
  f="$(mktemp "$TMP/real.XXXXXX")" || exit 2
  (cd "$FIX" && bash "$STATUS_SH" --ledger "$1" --changelog "$2" "${@:3}") >"$f" 2>/dev/null
  printf '%s' "$f"
}
GH_STUB_LIST="$LIST_EMPTY"
run_sut "$(real_status "$FIX/ledger.md" "$FIX/changelog.md")"
expect_code "real status, two unread: exit 0" 0
expect_eq "real status, two unread: two issues filed" "$(creates)" 2

run_sut "$(real_status "$FIX/ledger.md" "$FIX/changelog.md" --cap-releases 1)"
expect_eq "real status, over cap: one issue filed" "$(creates)" 1
expect_has "real status, over cap: the beyond-the-cap title" "$(calls)" "$CAP_TITLE"

sed 's/2\.1\.296/2.1.298/' "$FIX/ledger.md" >"$FIX/ledger-current.md"
run_sut "$(real_status "$FIX/ledger-current.md" "$FIX/changelog.md")"
expect_code "real status, up to date: exit 0" 0
expect_eq "real status, up to date: no gh call" "$(calls)" ""

printf '%s\n' '# Claude Code changelog' '' '**2.1.298**' '* item' >"$FIX/changelog-moved.md"
run_sut "$(real_status "$FIX/ledger.md" "$FIX/changelog-moved.md")"
expect_code "real status, markup moved: exit 2" 2
expect_eq "real status, markup moved: no gh call" "$(calls)" ""

test_harness::report
