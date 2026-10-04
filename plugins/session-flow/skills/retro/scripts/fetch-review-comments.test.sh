#!/usr/bin/env bash
# Tests for fetch-review-comments.sh. A stub gh on PATH serves fixed JSON
# fixtures per request and logs every call; jq is the real one. Every expected
# value below comes from the fixtures written in this file.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/fetch-review-comments.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi
JQ_DIR="$(dirname "$(command -v jq)")"

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

# The stub: logs its arguments, fails when a fail-<key> marker exists, and
# otherwise prints the fixture for the request.
STUB_BIN="$TEST_TMPDIR/bin"
mkdir -p "$STUB_BIN"
# shellcheck disable=SC2016 # the stub's own source, expanded when it runs
printf '%s\n' '#!/usr/bin/env bash' \
  'printf "%s\n" "$*" >>"$FIX/calls.log"' \
  'key=""' \
  'case "$1 $2" in' \
  '"repo view") key=repo ;;' \
  '"pr list") key=prs ;;' \
  'esac' \
  'for a in "$@"; do' \
  '  case "$a" in' \
  '  repos/*/pulls/*/comments) n="${a%/comments}"; key="comments-${n##*/}" ;;' \
  '  repos/*/pulls/*/reviews) n="${a%/reviews}"; key="reviews-${n##*/}" ;;' \
  '  number=*) key="threads-${a#number=}" ;;' \
  '  esac' \
  'done' \
  '[[ -n "$key" && ! -e "$FIX/fail-$key" && -f "$FIX/$key.json" ]] || exit 1' \
  'cat "$FIX/$key.json"' >"$STUB_BIN/gh"
chmod +x "$STUB_BIN/gh"

# run FIXDIR ARGS...: run the script with the stub first on PATH, from a
# scratch working directory; sets OUT and RC.
run() {
  local fix="$1"
  shift
  mkdir -p "$fix/work"
  OUT="$(cd "$fix/work" && FIX="$fix" PATH="$STUB_BIN:$JQ_DIR:/usr/bin:/bin" bash "$SCRIPT" "$@" 2>/dev/null)"
  RC=$?
}

# Main fixture: repository o/r, merged PRs 11 (author alice) and 12 (author bob).
F="$TEST_TMPDIR/main"
mkdir -p "$F"
printf '%s\n' '{"nameWithOwner":"o/r"}' >"$F/repo.json"
printf '%s\n' '[{"number":11,"author":{"login":"alice"}},{"number":12,"author":{"login":"bob"}}]' >"$F/prs.json"
# shellcheck disable=SC2016 # the $(...) and backticks are fixture data
HOSTILE_BODY='Rename this $(touch pwned) and `touch pwned2`
second line'
# shellcheck disable=SC2016 # a jq program; $hostile is a jq variable
"$JQ_DIR/jq" -n --arg hostile "$HOSTILE_BODY" '[
  {id: 101, in_reply_to_id: null, user: {login: "carol", type: "User"}, path: "src/a.ts", line: 4, body: "Guard the null case here"},
  {id: 102, in_reply_to_id: null, user: {login: "alice", type: "User"}, path: "src/a.ts", line: 9, body: "Author note to self"},
  {id: 103, in_reply_to_id: 101, user: {login: "dave", type: "User"}, path: "src/a.ts", line: 4, body: "Agreed with carol"},
  {id: 104, in_reply_to_id: null, user: {login: "lint-bot[bot]", type: "Bot"}, path: "src/b.ts", line: null, original_line: 7, body: "Unused import"},
  {id: 105, in_reply_to_id: null, user: {login: "lint-bot[bot]", type: "Bot"}, path: "src/b.ts", line: 12, body: "Resolved but unchanged"},
  {id: 106, in_reply_to_id: null, user: {login: "lint-bot[bot]", type: "Bot"}, path: "src/c.ts", line: 3, body: "Prefer const"},
  {id: 107, in_reply_to_id: 106, user: {login: "alice", type: "User"}, path: "src/c.ts", line: 3, body: "wont fix"},
  {id: 108, in_reply_to_id: null, user: {login: "carol", type: "User"}, path: "src/$(touch pwned3).ts", line: 2, body: $hostile}
]' >"$F/comments-11.json"
printf '%s\n' '[
  {"user":{"login":"carol","type":"User"},"body":"Please split this module"},
  {"user":{"login":"lint-bot[bot]","type":"Bot"},"body":"Bot summary body"},
  {"user":{"login":"erin","type":"User"},"body":""},
  {"user":{"login":"alice","type":"User"},"body":"Author review body"}
]' >"$F/reviews-11.json"
printf '%s\n' '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
  {"isResolved":false,"isOutdated":false,"comments":{"nodes":[{"databaseId":101}]}},
  {"isResolved":false,"isOutdated":true,"comments":{"nodes":[{"databaseId":104}]}},
  {"isResolved":true,"isOutdated":false,"comments":{"nodes":[{"databaseId":105}]}},
  {"isResolved":false,"isOutdated":false,"comments":{"nodes":[{"databaseId":106}]}}
]}}}}}' >"$F/threads-11.json"
printf '%s\n' '[{"id":201,"in_reply_to_id":null,"user":{"login":"carol","type":"User"},"path":"lib/x.py","line":1,"body":"Same null guard missing"}]' >"$F/comments-12.json"
printf '%s\n' '[]' >"$F/reviews-12.json"
printf '%s\n' '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}' >"$F/threads-12.json"

q() { printf '%s\n' "$OUT" | "$JQ_DIR/jq" -sc "$1"; }

run "$F" --prs 2
assert_eq "main: exit 0" 0 "$RC"
assert_eq "main: kept rows (101, 108, 104, carol's review, 201)" 5 "$(q 'length')"
assert_eq "main: human inline bodies" '["Guard the null case here","Same null guard missing"]' \
  "$(q '[.[] | select(.kind == "inline" and .source == "human" and (.body | startswith("Rename") | not)) | .body]')"
assert_eq "main: an outdated bot thread is kept as accepted-bot" \
  '[{"pr":11,"source":"accepted-bot","author":"lint-bot[bot]","kind":"inline","path":"src/b.ts","line":7,"body":"Unused import"}]' \
  "$(q '[.[] | select(.source == "accepted-bot")]')"
assert_eq "main: a resolved bot thread whose line is unchanged is dropped" 0 "$(q '[.[] | select(.body == "Resolved but unchanged")] | length')"
assert_eq "main: a bot thread with a rejecting author reply is dropped" 0 "$(q '[.[] | select(.body == "Prefer const" or .body == "wont fix")] | length')"
assert_eq "main: a reply is dropped" 0 "$(q '[.[] | select(.author == "dave")] | length')"
assert_eq "main: the PR author's own comments and review are dropped" 0 "$(q '[.[] | select(.pr == 11 and .author == "alice")] | length')"
assert_eq "main: one human review body, labelled" '[{"pr":11,"source":"human","author":"carol","kind":"review","path":null,"line":null,"body":"Please split this module"}]' \
  "$(q '[.[] | select(.kind == "review")]')"
assert_eq "main: the hostile body comes out as a JSON string" "$HOSTILE_BODY" \
  "$(printf '%s\n' "$OUT" | "$JQ_DIR/jq" -r 'select(.body | startswith("Rename")) | .body')"
assert_eq "main: no file created from a body or path" "" "$(ls "$F/work")"
assert_eq "main: issue-level comments never requested" 0 "$(grep -c 'issues/' "$F/calls.log")"
assert_eq "main: merged PRs listed with the --prs limit" 1 "$(grep -c -- 'pr list --state merged --limit 2 ' "$F/calls.log")"

BASH_COMPAT=51 run "$F" --prs 2
assert_eq "BASH_COMPAT=51: exit 0 and no file created" "0:" "$RC:$(ls "$F/work")"

# --repo skips the repo lookup and is passed to gh pr list.
: >"$F/calls.log"
run "$F" --prs 2 --repo o/r
assert_eq "--repo: exit 0" 0 "$RC"
assert_eq "--repo: no repo view call" 0 "$(grep -c 'repo view' "$F/calls.log")"
assert_eq "--repo: passed to pr list" 1 "$(grep -c -- 'pr list .*--repo o/r' "$F/calls.log")"

# Usage errors: exit 2, nothing on stdout, and no gh call.
for bad in "--prs 1" "--prs 201" "--prs abc" "--prs 2 --repo o/r/x" "--prs 2 --repo o;r/x" "--prs" "--bogus"; do
  : >"$F/calls.log"
  # shellcheck disable=SC2086 # split the case into its arguments on purpose
  run "$F" $bad
  assert_eq "usage ($bad): exit 2, empty stdout, no gh call" "2::0" "$RC:$OUT:$(grep -c . "$F/calls.log")"
done

run "$F" --help
assert_eq "--help: exit 0 with usage" "0:1" "$RC:$(printf '%s\n' "$OUT" | grep -c -- '--prs <n>')"

# A failed gh call: exit 2, nothing on stdout.
touch "$F/fail-comments-12"
run "$F" --prs 2
assert_eq "failed gh call: exit 2 and empty stdout" "2:" "$RC:$OUT"
rm -f "$F/fail-comments-12"

# Missing gh or jq: exit 2, nothing on stdout.
NOGH="$TEST_TMPDIR/nogh"
mkdir -p "$NOGH/work"
OUT="$(cd "$NOGH/work" && PATH="$JQ_DIR:/usr/bin:/bin" bash "$SCRIPT" --prs 2 2>/dev/null)"
RC=$?
assert_eq "missing gh: exit 2 and empty stdout" "2:" "$RC:$OUT"
OUT="$(cd "$NOGH/work" && FIX="$F" PATH="$STUB_BIN:/usr/bin:/bin" bash "$SCRIPT" --prs 2 2>/dev/null)"
RC=$?
assert_eq "missing jq: exit 2 and empty stdout" "2:" "$RC:$OUT"

# Output cap: 200 human comments of 1,000 characters each on one PR.
T="$TEST_TMPDIR/big"
mkdir -p "$T"
cp "$F/repo.json" "$T/"
printf '%s\n' '[{"number":31,"author":{"login":"alice"}},{"number":32,"author":{"login":"alice"}}]' >"$T/prs.json"
"$JQ_DIR/jq" -n '[range(1; 201) | {id: ., in_reply_to_id: null, user: {login: "carol", type: "User"}, path: "a.ts", line: 1, body: ("x" * 1000)}]' >"$T/comments-31.json"
printf '%s\n' '[]' >"$T/reviews-31.json"
cp "$F/threads-12.json" "$T/threads-31.json"
run "$T" --prs 2
LAST="$(printf '%s\n' "$OUT" | tail -n 1)"
BODY_BYTES="$(printf '%s\n' "$OUT" | sed '$d' | LC_ALL=C wc -c | tr -d ' ')"
assert_eq "cap: exit 0" 0 "$RC"
assert_eq "cap: last line is the truncation record" true "$(printf '%s\n' "$LAST" | "$JQ_DIR/jq" -r '.truncated')"
if ((BODY_BYTES <= 65536 && BODY_BYTES > 60000)); then pass "cap: rows stop at 64 KB ($BODY_BYTES bytes)"; else fail "cap: rows stop at 64 KB" "$BODY_BYTES bytes"; fi
assert_eq "cap: the second PR is never fetched" 0 "$(grep -c 'pulls/32' "$T/calls.log")"

if ((FAILED > 0)); then
  printf '%d of %d checks failed\n' "$FAILED" "$CASE_NUM" >&2
  exit 1
fi
printf 'all %d checks passed\n' "$CASE_NUM"
