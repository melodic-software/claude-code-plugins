#!/usr/bin/env bash
# Runs the `Write the rate-limit-aware read helper` step body of
# .github/workflows/pr-require-checks.yml's ci-status, then calls the
# pr_labels and pr_comments functions it writes, against a stub `gh`.
#
# Each reads a pull request's labels or issue comments from one GraphQL send,
# which GITHUB_TOKEN meters apart from the core pool, and prints them in the
# REST shape the steps read. Anything short of a whole, well-formed answer
# reads REST through gh_read, every page, as before. The parity cases replay a
# REST and a GraphQL answer recorded for the same pull request (#16631 in
# melodic-software/claude-code-plugins, fixtures/ci-gh-read-graphql); the
# REST one, cut by jq to the fields the steps read, is the expected value.
# test-scope: .github/workflows/pr-require-checks.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"
FIXTURES="$ROOT/scripts/fixtures/ci-gh-read-graphql"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"
# shellcheck source=lib/ci-gh-read.sh
. "$ROOT/scripts/lib/ci-gh-read.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
export TMPDIR="$TMP_ROOT"

if ! ci_gh_read::install "$WORKFLOW" "$TMP_ROOT" budget; then
  fail "no working 'Write the rate-limit-aware read helper' step in $WORKFLOW"
  test_harness::report
  exit 1
fi

# The stub logs its arguments. A GraphQL send prints the file STUB_GQL, with
# a graphql-resource header block under -i (STUB_GQL_REMAINING left, 4000 by
# default), or fails when STUB_GQL is unset.
# A REST send prints the file STUB_REST (pages concatenated, as --paginate
# prints them), with a core header block under -i, or fails when it is unset.
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
include=; [[ "$2" == -i ]] && include=1
if [[ " $* " == *" graphql "* ]]; then file=${STUB_GQL:-}; resource=graphql; else file=${STUB_REST:-}; resource=core; fi
[[ -n $file ]] || { echo "gh: stub refuses (HTTP 502)" >&2; exit 1; }
remaining=4000; [[ $resource == graphql ]] && remaining=${STUB_GQL_REMAINING:-4000}
[[ -z $include ]] || printf 'HTTP/2.0 200 OK\r\nX-Ratelimit-Limit: 5000\r\nX-Ratelimit-Remaining: %s\r\nX-Ratelimit-Resource: %s\r\nX-Ratelimit-Reset: 1792803600\r\n\r\n' "$remaining" "$resource"
cat "$file"
EOF
printf '#!/usr/bin/env bash\n' >"$TMP_ROOT/bin/sleep"
chmod +x "$TMP_ROOT/bin/gh" "$TMP_ROOT/bin/sleep"

# run <function> ; sets out, rc, and the log of sends.
run() {
  : >"$TMP_ROOT/log"
  ci_gh_read::reset "$TMP_ROOT" "$(($(date +%s) + 600))"
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" GITHUB_REPOSITORY=o/r RUNNER_TEMP="$TMP_ROOT" \
    bash -ec '. "$RUNNER_TEMP/gh-read.sh"; '"$1"' 6419' 2>"$TMP_ROOT/err")" && rc=0 || rc=$?
}
rest_sends() { grep -c '^api \(-i \)\?repos/' "$TMP_ROOT/log"; }
gql_sends() { grep -c ' graphql ' "$TMP_ROOT/log"; }

# The fields the steps and filterLaneHolds read from a REST comment.
PROJECT='[.[] | {id, node_id, body, created_at, updated_at, user: {login: .user.login, id: .user.id, type: .user.type}}]'

STUB_GQL="$FIXTURES/graphql-comments-16631.json" STUB_REST="$FIXTURES/rest-comments-16631.json" run pr_comments
want="$(jq -c "$PROJECT" "$FIXTURES/rest-comments-16631.json")"
got="$(jq -c "$PROJECT" <<<"$out" 2>/dev/null)"
if [[ $rc -eq 0 && -n "$got" && "$got" == "$want" ]]; then
  ok "parity: the GraphQL comments read prints what REST prints for every field the steps read"
else
  fail "parity: GraphQL comments differ from REST (rc=$rc): got '$got' want '$want'"
fi
if [[ "$(jq -r '[.[].user.login] | join(",")' <<<"$out" 2>/dev/null)" == "kyle-sexton,chatgpt-codex-connector[bot],github-actions[bot],github-actions[bot],github-actions[bot]" ]]; then
  ok "a bot's GraphQL login gets the [bot] REST gives it, and a person's does not"
else
  fail "the comment logins are not REST's: '$out'"
fi
if [[ "$(gql_sends)" -eq 1 && "$(rest_sends)" -eq 0 ]]; then
  ok "a whole GraphQL answer spends one GraphQL send and no REST read"
else
  fail "a whole GraphQL answer made these sends: '$(cat "$TMP_ROOT/log")'"
fi
calls="$(RUNNER_TEMP="$TMP_ROOT" bash -c '. "$RUNNER_TEMP/gh-read.sh"; api_budget_emit_calls github-token' 2>/dev/null)"
if [[ "$calls" == *"github-token=1 "*"graphql=1"* ]]; then
  ok "the GraphQL send is counted, as graphql, in the job's api-calls notice"
else
  fail "the api-calls notice does not count the GraphQL send: '$calls'"
fi

STUB_GQL="$FIXTURES/graphql-labels-16631.json" STUB_REST="$FIXTURES/rest-labels-16631.json" run pr_labels
want="$(jq -c '[.[] | {name}]' "$FIXTURES/rest-labels-16631.json")"
if [[ $rc -eq 0 && "$out" == "$want" && "$(rest_sends)" -eq 0 ]]; then
  ok "parity: the GraphQL labels read prints REST's label names, with no REST read"
else
  fail "parity: GraphQL labels '$out' (rc=$rc) are not REST's '$want': '$(cat "$TMP_ROOT/log")'"
fi

# Pagination: a connection with another page reads REST, every page of it.
# Two REST pages of 100 and 1 comments stand for a pull request with 101.
jq -c '.data.repository.pullRequest.comments.pageInfo.hasNextPage = true' "$FIXTURES/graphql-comments-16631.json" >"$TMP_ROOT/gql-more.json"
{
  jq -c '[range(100) as $i | .[0] | .id = $i]' "$FIXTURES/rest-comments-16631.json"
  jq -c '[.[0] | .id = 100]' "$FIXTURES/rest-comments-16631.json"
} >"$TMP_ROOT/rest-101.json"
STUB_GQL="$TMP_ROOT/gql-more.json" STUB_REST="$TMP_ROOT/rest-101.json" run pr_comments
if [[ $rc -eq 0 && "$(jq -s 'add | length' <<<"$out")" == 101 ]] &&
  grep -qxF 'api repos/o/r/issues/6419/comments?per_page=100 --paginate' "$TMP_ROOT/log"; then
  ok "pagination: comments past GraphQL's first page are read over REST, all 101"
else
  fail "pagination: a second comments page did not read every comment over REST (rc=$rc): '$(cat "$TMP_ROOT/log")'"
fi
jq -c '.data.repository.pullRequest.labels.pageInfo.hasNextPage = true' "$FIXTURES/graphql-labels-16631.json" >"$TMP_ROOT/gql-labels-more.json"
STUB_GQL="$TMP_ROOT/gql-labels-more.json" STUB_REST="$FIXTURES/rest-labels-16631.json" run pr_labels
if [[ $rc -eq 0 && "$(rest_sends)" -eq 1 && "$(jq -r '.[].name' <<<"$out")" == "$(jq -r '.[].name' "$FIXTURES/rest-labels-16631.json")" ]]; then
  ok "pagination: labels past GraphQL's first page are read over REST"
else
  fail "pagination: a second labels page did not read REST (rc=$rc): '$(cat "$TMP_ROOT/log")'"
fi

# Every other doubt reads REST too: the answer REST gives is the one printed.
fallback() {
  local label="$1" fn="$2" gql="$3" rest="$4"
  STUB_GQL="$gql" STUB_REST="$rest" run "$fn"
  if [[ $rc -eq 0 && "$(rest_sends)" -eq 1 && "$out" == "$(cat "$rest")" ]] && grep -q 'reading them over REST' "$TMP_ROOT/err"; then
    ok "$label reads REST"
  else
    fail "$label: rc=$rc out='$out' sends='$(cat "$TMP_ROOT/log")'"
  fi
}
REST_C="$FIXTURES/rest-comments-16631.json"
jq -c '.errors = [{"type": "NOT_FOUND", "message": "Could not resolve to a node"}]' "$FIXTURES/graphql-comments-16631.json" >"$TMP_ROOT/gql-errors.json"
fallback "a GraphQL answer carrying errors" pr_comments "$TMP_ROOT/gql-errors.json" "$REST_C"
# GraphQL's own primary limit spent stops only the graphql pool, so the core
# read still goes out.
echo '{"data":null,"errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded for installation."}]}' >"$TMP_ROOT/gql-limited.json"
STUB_GQL_REMAINING=0 fallback "a spent GraphQL limit" pr_comments "$TMP_ROOT/gql-limited.json" "$REST_C"
jq -c '.data.repository.pullRequest.comments.nodes[2].body = "<!-- claude-lane-hold lane=claude-review sha=bbbb criteria=cost -->\nHeld."' "$FIXTURES/graphql-comments-16631.json" >"$TMP_ROOT/gql-hold.json"
fallback "a review-lane hold comment (its updated_at feeds the lane binding)" pr_comments "$TMP_ROOT/gql-hold.json" "$REST_C"

# A rate-limit answer with GraphQL points left is a secondary limit, which the
# rate guard stops every pool for, as it does on REST: the REST read is not
# sent and the read fails, so the caller fails closed as on a REST secondary
# limit today.
STUB_GQL="$TMP_ROOT/gql-limited.json" STUB_REST="$REST_C" run pr_comments
if [[ $rc -ne 0 && "$(rest_sends)" -eq 0 ]] && grep -q 'was not sent' "$TMP_ROOT/err"; then
  ok "a secondary-limit answer stops every pool, as on REST, and the read fails closed"
else
  fail "a secondary-limit answer: rc=$rc sends='$(cat "$TMP_ROOT/log")' err='$(cat "$TMP_ROOT/err")'"
fi
jq -c '.data.repository.pullRequest.comments.nodes[0].author = null' "$FIXTURES/graphql-comments-16631.json" >"$TMP_ROOT/gql-ghost.json"
fallback "a comment by a deleted account (REST shows it as ghost)" pr_comments "$TMP_ROOT/gql-ghost.json" "$REST_C"
jq -c '.data.repository.pullRequest.comments.nodes[0].author = {"__typename": "Mannequin", "login": "m"}' "$FIXTURES/graphql-comments-16631.json" >"$TMP_ROOT/gql-mannequin.json"
fallback "a comment by an author that is neither User nor Bot" pr_comments "$TMP_ROOT/gql-mannequin.json" "$REST_C"
echo '{"data":{"repository":{"pullRequest":null}}}' >"$TMP_ROOT/gql-null.json"
fallback "a GraphQL answer with no pull request" pr_comments "$TMP_ROOT/gql-null.json" "$REST_C"
fallback "a GraphQL answer with no pull request" pr_labels "$TMP_ROOT/gql-null.json" "$FIXTURES/rest-labels-16631.json"
fallback "a failed GraphQL send" pr_comments "" "$REST_C"
fallback "a failed GraphQL send" pr_labels "" "$FIXTURES/rest-labels-16631.json"
if [[ "$(gql_sends)" -eq 1 ]]; then
  ok "a failed GraphQL send is not sent again: REST is the retry"
else
  fail "a failed GraphQL send was sent $(gql_sends) times"
fi

# Both failing fails the read, so the caller fails closed as before.
STUB_GQL='' STUB_REST='' run pr_comments
if [[ $rc -ne 0 && -z "$out" ]]; then
  ok "comments unreadable both ways fail the read"
else
  fail "comments unreadable both ways returned rc=$rc out='$out'"
fi

test_harness::report
