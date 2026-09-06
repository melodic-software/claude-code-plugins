#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# Offline: the skill-script contract (--help), the pre-I/O usage-error paths, and
# the subIssues + intersect path against a gh stub that reproduces gh's real
# `--json subIssues` projection. End-to-end behavior against the live provider
# stays with the on-demand e2e-probe.
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/list-sub-items.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S"                              # no parent id
assert_usage_error "$S" "github:o/r#1" --state bogus # bad state
assert_usage_error "$S" "not-an-id"                  # malformed id
assert_usage_error "$S" "local-markdown:o/r#1"       # foreign provider

# --- subIssues nodes carry no `repository`, so the filter reads `url` (#3825) ---
# The stub emits exactly what gh's export path emits for `--json subIssues`:
# id/number/title/url/state and nothing else. The old predicate selected on
# `.repository.nameWithOwner`, which is absent there, so it matched no node and
# every container came back childless — this case fails on that predicate.
if command -v jq >/dev/null 2>&1; then
  STUB="$(mktemp -d)"
  cat >"$STUB/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  printf 'gh version 2.97.0 (test)\n'
  exit 0
fi
for a in "$@"; do
  case "$a" in
  view) mode=view ;;
  list) mode=list ;;
  esac
done
case "${mode:-}" in
view)
  # #12 is a genuine cross-repo sub-issue whose number also exists in o/r —
  # dropping it is what the same-repo filter is for.
  printf '%s\n' '{"subIssues":{"nodes":[
    {"id":"a","number":11,"title":"one","url":"https://github.com/o/r/issues/11","state":"OPEN"},
    {"id":"b","number":12,"title":"foreign","url":"https://github.com/x/y/issues/12","state":"OPEN"}
  ],"totalCount":2}}'
  ;;
list)
  printf '%s\n' '[
    {"number":11,"title":"one","state":"OPEN","assignees":[],"labels":[],"issueType":null,"blockedBy":{"nodes":[]},"url":"https://github.com/o/r/issues/11"},
    {"number":12,"title":"same number, this repo","state":"OPEN","assignees":[],"labels":[],"issueType":null,"blockedBy":{"nodes":[]},"url":"https://github.com/o/r/issues/12"},
    {"number":13,"title":"unrelated","state":"OPEN","assignees":[],"labels":[],"issueType":null,"blockedBy":{"nodes":[]},"url":"https://github.com/o/r/issues/13"}
  ]'
  ;;
*)
  printf 'gh-stub: unhandled\n' >&2
  exit 90
  ;;
esac
EOF
  chmod +x "$STUB/gh"

  ERRFILE="$(mktemp)"
  OUT="$(PATH="$STUB:$PATH" bash "$S" "github:o/r#99" 2>"$ERRFILE")"
  rc=$?
  assert_eq "list-sub-items over stubbed subIssues → exit 0" "0" "$rc"
  assert_eq "url-derived filter keeps the same-repo child" \
    "github:o/r#11" "$(jq -r '[.items[].id] | join(",")' <<<"$OUT")"
  assert_eq "child row is re-parented to the container" \
    "github:o/r#99" "$(jq -r '.items[0].parent_id' <<<"$OUT")"
  # The cross-repo drop is a documented truncation, not a fault, so a well-formed
  # node set must stay silent or the diagnostic below is noise on every read.
  assert_eq "well-formed nodes emit no derivable-repo warning" \
    "0" "$(grep -c 'no derivable repo' "$ERRFILE")"

  rm -f "$ERRFILE"
  rm -rf "$STUB"
fi

# --- a node attributable to no repo is still dropped, but not silently (#3825) ---
# gh always emits `url` today, so this is unreachable on well-formed input. A
# projection change that dropped `url` too would re-blind every lane exactly the
# way #3825 did, with an empty list and no signal. The drop itself stays: the
# intersect is number-keyed and sub-issues CAN be cross-repo, so treating an
# unattributable node as same-repo would pull in an unrelated same-numbered item.
# What changes is that the drop now says so on stderr, leaving stdout parseable.
if command -v jq >/dev/null 2>&1; then
  STUB="$(mktemp -d)"
  cat >"$STUB/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  printf 'gh version 2.97.0 (test)\n'
  exit 0
fi
for a in "$@"; do
  case "$a" in
  view) mode=view ;;
  list) mode=list ;;
  esac
done
case "${mode:-}" in
view)
  # #21 is well-formed. #22 carries no url at all and #23 a url that is not an
  # issue path: the two ways a narrowed projection could go unattributable.
  printf '%s\n' '{"subIssues":{"nodes":[
    {"id":"a","number":21,"title":"one","url":"https://github.com/o/r/issues/21","state":"OPEN"},
    {"id":"b","number":22,"title":"no url","state":"OPEN"},
    {"id":"c","number":23,"title":"odd url","url":"https://github.com/o/r/pull/23","state":"OPEN"}
  ],"totalCount":3}}'
  ;;
list)
  printf '%s\n' '[
    {"number":21,"title":"one","state":"OPEN","assignees":[],"labels":[],"issueType":null,"blockedBy":{"nodes":[]},"url":"https://github.com/o/r/issues/21"},
    {"number":22,"title":"two","state":"OPEN","assignees":[],"labels":[],"issueType":null,"blockedBy":{"nodes":[]},"url":"https://github.com/o/r/issues/22"},
    {"number":23,"title":"three","state":"OPEN","assignees":[],"labels":[],"issueType":null,"blockedBy":{"nodes":[]},"url":"https://github.com/o/r/issues/23"}
  ]'
  ;;
*)
  printf 'gh-stub: unhandled\n' >&2
  exit 90
  ;;
esac
EOF
  chmod +x "$STUB/gh"

  ERRFILE="$(mktemp)"
  OUT="$(PATH="$STUB:$PATH" bash "$S" "github:o/r#99" 2>"$ERRFILE")"
  rc=$?
  ERR="$(<"$ERRFILE")"
  assert_eq "unattributable node → still exit 0" "0" "$rc"
  assert_eq "unattributable nodes dropped, the attributable one kept" \
    "github:o/r#21" "$(jq -r '[.items[].id] | join(",")' <<<"$OUT")"
  assert_eq "stdout stays machine-parseable, diagnostic did not leak into it" \
    "1.0" "$(jq -r '.schema_version' <<<"$OUT")"
  assert_eq "stderr names both unattributable nodes on one line" \
    "1" "$(grep -c 'no derivable repo (number: 22, 23)' <<<"$ERR")"

  rm -f "$ERRFILE"
  rm -rf "$STUB"
fi

[[ $FAILED -eq 0 ]] || exit 1
