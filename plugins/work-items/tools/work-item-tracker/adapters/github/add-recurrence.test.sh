#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# Offline: add-recurrence against a gh stub that keeps the item's comments in a JSON file,
# applies each call's --jq filter to it, and appends a POSTed comment to it.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/add-recurrence.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

LINK="https://github.com/o/r/actions/runs/1"
assert_help "$S"
assert_usage_error "$S"                                                  # no id
assert_usage_error "$S" "github:o/r#1" --note seen                       # no --source-link
assert_usage_error "$S" "github:o/r#1" --source-link "$LINK"             # no --note
assert_usage_error "$S" "github:o/r#1" --source-link "$LINK" --note ""   # empty note
assert_usage_error "$S" "github:o/r#1" --source-link "ftp://x" --note seen
assert_usage_error "$S" "github:o/r#1" --source-link "https://a b" --note seen
assert_usage_error "$S" "local-markdown:o/r#1" --source-link "$LINK" --note seen

command -v jq >/dev/null 2>&1 || skip_suite "jq not on PATH"

STUB="$TMP_ROOT/bin"
LOG="$TMP_ROOT/gh.log"
COMMENTS="$TMP_ROOT/comments.json"
mkdir -p "$STUB"
cat >"$STUB/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_STUB_LOG"
method=GET filter=. body=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --method) method="$2"; shift 2 ;;
  --jq) filter="$2"; shift 2 ;;
  -f) [[ "$2" == body=* ]] && body="${2#body=}"; shift 2 ;;
  *) shift ;;
  esac
done
if [[ "$method" == POST ]]; then
  jq -c --arg b "$body" '. + [{id: (length + 100), body: $b, author_association: "OWNER",
    user: {login: "me", type: "User"}}]' "$GH_STUB_COMMENTS" >"$GH_STUB_COMMENTS.new" &&
    mv "$GH_STUB_COMMENTS.new" "$GH_STUB_COMMENTS"
  jq -c "$filter" <<<'{"id": 100}'
  exit 0
fi
jq -c "$filter" "$GH_STUB_COMMENTS"
EOF
chmod +x "$STUB/gh"

run() {
  OUT="$(PATH="$STUB:$PATH" GH_STUB_LOG="$LOG" GH_STUB_COMMENTS="$COMMENTS" WIT_WRITE_SPACING_S=0 \
    bash "$S" "$@" 2>"$TMP_ROOT/err")"
  RC=$?
}
posts() { grep -c -- '--method POST' "$LOG"; }

printf '%s\n' '[{"id":1,"body":"unrelated","author_association":"OWNER","user":{"login":"me","type":"User"}}]' >"$COMMENTS"
: >"$LOG"

run "github:o/r#9" --source-link "$LINK" --note "seen on run 1"
assert_eq "first sighting → exit 0" "0" "$RC"
assert_eq "first sighting is recorded" "true" "$(jq -r '.recorded' <<<"$OUT")"
assert_eq "result carries the item id" "github:o/r#9" "$(jq -r '.id' <<<"$OUT")"
assert_eq "result carries the source link" "$LINK" "$(jq -r '.source_link' <<<"$OUT")"
assert_eq "first sighting posts one comment" "1" "$(posts)"
assert_contains "posts on the item's comments" "$(grep -- '--method POST' "$LOG")" "repos/o/r/issues/9/comments"
POSTED="$(jq -r '.[-1].body' "$COMMENTS")"
assert_contains "the comment opens with the marker" "$(head -n 1 <<<"$POSTED")" "<!-- work-item-recurrence v1 "
assert_contains "the marker carries the link" "$(head -n 1 <<<"$POSTED")" "\"source_link\":\"$LINK\""
assert_contains "the comment shows the note" "$POSTED" "seen on run 1"

run "github:o/r#9" --source-link "$LINK" --note "seen again"
assert_eq "same link again → exit 0" "0" "$RC"
assert_eq "same link again is not recorded" "false" "$(jq -r '.recorded' <<<"$OUT")"
assert_eq "same link again writes nothing" "1" "$(posts)"

run "github:o/r#9" --source-link "https://github.com/o/r/actions/runs/2" --note "seen on run 2"
assert_eq "another link is recorded" "true" "$(jq -r '.recorded' <<<"$OUT")"
assert_eq "another link posts once more" "2" "$(posts)"

# Anyone can comment on a public repository: a marker an outsider posted records nothing.
OTHER="https://github.com/o/r/actions/runs/3"
jq -c --arg b "<!-- work-item-recurrence v1 {\"source_link\":\"$OTHER\"} -->" \
  '. + [{id: 50, body: $b, author_association: "NONE", user: {login: "x", type: "User"}}]' \
  "$COMMENTS" >"$COMMENTS.new" && mv "$COMMENTS.new" "$COMMENTS"
run "github:o/r#9" --source-link "$OTHER" --note "seen on run 3"
assert_eq "an outsider's marker does not count" "true" "$(jq -r '.recorded' <<<"$OUT")"
assert_eq "an outsider's marker leaves the post in place" "3" "$(posts)"

[[ $FAILED -eq 0 ]] || exit 1
