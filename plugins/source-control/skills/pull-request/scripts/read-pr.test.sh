#!/usr/bin/env bash
# Regression tests for read-pr.sh, black-box with a stubbed `gh` on PATH.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/read-pr.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not installed"

STUB_DIR="$TEST_TMPDIR/stubs"
mkdir -p "$STUB_DIR"
# The stubs log each call's arguments, so a case can check what reached gh.
# `view` must reach only REST endpoints (`gh api`); `list` still uses `gh pr list`.
cat >"$STUB_DIR/gh" <<'STUB_EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_STUB_CALLS"
if [[ "$1 $2" == "pr list" ]]; then
  [[ "${GH_STUB_LIST_FAIL:-}" == 1 ]] && exit 1
  printf '[{"number":1,"headRefName":"fix/improve-a"},{"number":2,"headRefName":"feat/other"},{"number":3,"headRefName":"docs/improve-b"}]'
  exit 0
fi
[[ "$1" == api ]] || { echo "gh-stub: unrouted $*" >&2; exit 1; }
shift
host=github.com accept=""
while [[ "${1:-}" == -* ]]; do
  case "$1" in
  --hostname) host="$2" ;;
  -H) accept="$2" ;;
  *) break ;;
  esac
  shift 2
done
ep="$1"
repo="${ep#repos/}" repo="${repo%%/pulls*}"
[[ "$repo" == "{owner}/{repo}" ]] && repo=acme/app
# A forge can report a pull request URL on a different host or repo than the one asked.
url_host="${GH_STUB_URL_HOST:-$host}" url_repo="${GH_STUB_URL_REPO:-$repo}"
case "$ep" in
repos/*/pulls\?head=*)
  # The stub's branch feat/7-x has a closed pull request 6 and an open one 7.
  if [[ "$ep" == *"head={owner}:feat%2F7-x&"* ]]; then
    printf '[{"number":6,"state":"closed"},{"number":7,"state":"open"}]'
  elif [[ "$ep" == *"head={owner}:feat%2F7-closed&"* ]]; then
    # Closed-only: the forge lists the most recent first.
    printf '[{"number":7,"state":"closed"},{"number":6,"state":"closed"}]'
  else
    printf '[]'
  fi
  ;;
repos/*/pulls/404*) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
repos/*/pulls/7/files*)
  page="${ep##*page=}" total="${GH_STUB_FILES:-1}"
  jq -n --argjson s "$(((page - 1) * 100))" --argjson t "$total" \
    '[range($s; [$s + 100, $t] | min) | {filename: "f\(.).md", status: (if . == 0 then "removed" else "modified" end), additions: 1, deletions: 0}]'
  ;;
repos/*/pulls/7)
  if [[ "$accept" == "Accept: application/vnd.github.diff" ]]; then
    printf 'diff --git a/a.md b/a.md\n'
  elif [[ "${GH_STUB_MERGED:-}" == 1 ]]; then
    printf '{"number":7,"html_url":"https://%s/%s/pull/7","state":"closed","draft":false,"merged_at":"2026-01-01T00:00:00Z","merge_commit_sha":"m1","title":"t","base":{"ref":"main","sha":"b1"},"head":{"ref":"feat/7-x","sha":"h1"},"additions":3,"deletions":1,"labels":[]}' "$url_host" "$url_repo"
  else
    printf '{"number":7,"html_url":"https://%s/%s/pull/7","state":"open","draft":true,"merged_at":null,"merge_commit_sha":"t1","title":"t","base":{"ref":"main","sha":"b1"},"head":{"ref":"feat/7-x","sha":"h1"},"additions":3,"deletions":1,"labels":[{"node_id":"L1","name":"bug","description":"d","color":"f00"}]}' "$url_host" "$url_repo"
  fi
  ;;
repos/acme/app | repos/acme/ghe-app)
  [[ "${GH_STUB_API_FAIL:-}" == 1 ]] && exit 1
  [[ "$host" == github.com ]] && echo public || echo private
  ;;
*) echo "gh-stub: unrouted api $ep" >&2; exit 1 ;;
esac
STUB_EOF
cat >"$STUB_DIR/git" <<'STUB_EOF'
#!/usr/bin/env bash
[[ "$1 $2" == "branch --show-current" ]] && printf '%s\n' "${GIT_STUB_BRANCH:-}"
STUB_EOF
chmod +x "$STUB_DIR/gh" "$STUB_DIR/git"

run() {
  : >"$TEST_TMPDIR/calls"
  GH_STUB_CALLS="$TEST_TMPDIR/calls" PATH="$STUB_DIR:$PATH" bash "$SCRIPT" "$@"
}

out=$(run view 7)
assert_eq "view merges the repository visibility into the facts" "PUBLIC" "$(jq -r .visibility <<<"$out")"
assert_eq "view keeps the pull request's own fields" "main" "$(jq -r .baseRefName <<<"$out")"
assert_eq "view maps the REST head and base shas to oids" "h1 b1" "$(jq -r '"\(.headRefOid) \(.baseRefOid)"' <<<"$out")"
assert_eq "view upper-cases an open state and keeps draft" "OPEN true" "$(jq -r '"\(.state) \(.isDraft)"' <<<"$out")"
assert_eq "an unmerged pull request has no merge commit" "null" "$(jq -c .mergeCommit <<<"$out")"
assert_eq "view maps a removed file to DELETED" "f0.md DELETED" "$(jq -r '.files[0] | "\(.path) \(.changeType)"' <<<"$out")"
assert_eq "view keeps label names" "bug" "$(jq -r '.labels[0].name' <<<"$out")"
calls=$(cat "$TEST_TMPDIR/calls")
assert_not_contains "view never reaches gh's GraphQL commands" "$calls" "pr "
assert_contains "view without --repo reads the current repository" "$calls" "api repos/{owner}/{repo}/pulls/7"

out=$(GH_STUB_MERGED=1 run view 7)
assert_eq "a merged pull request reads MERGED with its merge commit" "MERGED m1" "$(jq -r '"\(.state) \(.mergeCommit.oid)"' <<<"$out")"

out=$(GH_STUB_FILES=250 run view 7)
assert_eq "view pages through every file" "250" "$(jq '.files | length' <<<"$out")"
assert_eq "paged files keep their order" "f100.md" "$(jq -r '.files[100].path' <<<"$out")"
assert_eq "paging stops at the first short page" "3" "$(grep -c '/files?' "$TEST_TMPDIR/calls")"

out=$(GH_STUB_API_FAIL=1 run view 7)
assert_eq "a failed visibility lookup reads UNKNOWN, never a guess" "UNKNOWN" "$(jq -r .visibility <<<"$out")"

out=$(run view 7 --repo ghe.example/acme/ghe-app)
assert_eq "visibility on another host asks that host" "PRIVATE" "$(jq -r .visibility <<<"$out")"
calls=$(cat "$TEST_TMPDIR/calls")
assert_contains "--repo HOST/OWNER/REPO reads from that host" "$calls" "api --hostname ghe.example repos/acme/ghe-app/pulls/7"
assert_contains "the visibility host comes from the pull request URL" "$calls" "api --hostname ghe.example repos/acme/ghe-app --jq"

out=$(GH_STUB_URL_HOST=ghe.example GH_STUB_URL_REPO=acme/ghe-app run view 7)
assert_eq "visibility asks the host in the pull request URL, not the requested host" "PRIVATE" "$(jq -r .visibility <<<"$out")"
assert_contains "a URL host that differs from the requested host reaches the visibility lookup" "$(cat "$TEST_TMPDIR/calls")" "api --hostname ghe.example repos/acme/ghe-app --jq"

out=$(run view https://ghe.example/acme/ghe-app/pull/7)
assert_eq "a pull request URL names its own host and repository" "https://ghe.example/acme/ghe-app/pull/7" "$(jq -r .url <<<"$out")"

run view 7 --repo acme/app >/dev/null
calls=$(cat "$TEST_TMPDIR/calls")
assert_contains "--repo OWNER/REPO reads that repository" "$calls" "api repos/acme/app/pulls/7"
assert_not_contains "--repo OWNER/REPO names no host" "$calls" "--hostname"

out=$(run view feat/7-closed)
assert_eq "a branch with no open pull request reads its most recent one" "7" "$(jq -r .number <<<"$out")"

run view 7 --repo a/b/c/d >/dev/null 2>&1
assert_exit "a malformed --repo exits 1" 1 "$?"

run view 404 >/dev/null 2>&1
assert_exit "no pull request exits 2" 2 "$?"

out=$(run view 7 --diff)
assert_contains "view --diff prints the diff" "$out" "diff --git a/a.md b/a.md"
assert_contains "view --diff asks REST for the diff media type" "$(cat "$TEST_TMPDIR/calls")" "Accept: application/vnd.github.diff"

out=$(run view 7 --diff --out "$TEST_TMPDIR/pr.diff")
assert_silent "--out leaves stdout empty" "$out"
assert_eq "--out writes the diff to the file" "diff --git a/a.md b/a.md" "$(cat "$TEST_TMPDIR/pr.diff")"
run view 7 --out "$TEST_TMPDIR/facts.json" >/dev/null
assert_eq "--out writes the facts to the file" "PUBLIC" "$(jq -r .visibility "$TEST_TMPDIR/facts.json")"

out=$(GIT_STUB_BRANCH=feat/7-x run view)
assert_eq "view with no number reads the current branch's open pull request" "7" "$(jq -r .number <<<"$out")"
out=$(run view feat/7-x)
assert_eq "view with a branch name reads that branch's pull request" "7" "$(jq -r .number <<<"$out")"
GIT_STUB_BRANCH=feat/none run view >/dev/null 2>&1
assert_exit "a branch with no pull request exits 2" 2 "$?"
GIT_STUB_BRANCH="" run view >/dev/null 2>&1
assert_exit "no number on a detached HEAD exits 2" 2 "$?"

out=$(run list --head-match '^[a-z]+/improve-')
assert_eq "list --head-match keeps only matching head branches" "1,3" "$(jq -r 'map(.number) | join(",")' <<<"$out")"
calls=$(cat "$TEST_TMPDIR/calls")
assert_contains "list lifts gh's 30-row default" "$calls" "--limit 1000"
assert_contains "list defaults to open pull requests" "$calls" "--state open"

run list --head feat/x --state all >/dev/null
calls=$(cat "$TEST_TMPDIR/calls")
assert_contains "list passes --head through" "$calls" "--head feat/x"
assert_contains "list passes --state through" "$calls" "--state all"

run list --head feat/x --search '#42' >/dev/null
calls=$(cat "$TEST_TMPDIR/calls")
assert_contains "list passes --search through" "$calls" "--head feat/x --search #42"
run list --search '#42' >/dev/null
assert_contains "list --search works without --head" "$(cat "$TEST_TMPDIR/calls")" "--search #42"
run view 7 --search x >/dev/null 2>&1
assert_exit "--search on view exits 1" 1 "$?"

GH_STUB_LIST_FAIL=1 run list >/dev/null 2>&1
assert_exit "a failed list exits 2, never an empty array" 2 "$?"
run list --head-match '(' >/dev/null 2>&1
assert_exit "an invalid --head-match exits 1" 1 "$?"
run >/dev/null 2>&1
assert_exit "no action exits 1" 1 "$?"
assert_contains "list asks for the merge commit" "$calls" "mergeCommit"

run list --state draft >/dev/null 2>&1
assert_exit "an unknown --state exits 1" 1 "$?"
run view 7 --head x >/dev/null 2>&1
assert_exit "a list flag on view exits 1" 1 "$?"
run list --diff >/dev/null 2>&1
assert_exit "--diff on list exits 1" 1 "$?"
run frobnicate >/dev/null 2>&1
assert_exit "an unknown action exits 1" 1 "$?"

[[ $FAILED -eq 0 ]] || exit 1
exit 0
