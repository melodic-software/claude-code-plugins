#!/usr/bin/env bash
# test-scope: docs/conventions/work-items.yaml
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/list-sub-items.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

write_gh_stub() {
  cat >"$1/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  printf 'gh version 2.97.0 (test)\n'
  exit 0
fi
mode=""
for a in "$@"; do
  case "$a" in
  view) mode=view ;;
  list) mode=list ;;
  esac
done
case "$mode" in
view) printf '%s\n' "${GH_STUB_VIEW:?}" ;;
list) printf '%s\n' "${GH_STUB_LIST:?}" ;;
*)
  printf 'gh-stub: unhandled\n' >&2
  exit 90
  ;;
esac
EOF
  chmod +x "$1/gh"
}

assert_help "$S"
assert_usage_error "$S"
assert_usage_error "$S" "github:o/r#1" --state bogus
assert_usage_error "$S" "not-an-id"
assert_usage_error "$S" "local-markdown:o/r#1"

if command -v jq >/dev/null 2>&1; then
  STUB="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
  write_gh_stub "$STUB"
  VIEW='{"subIssues":{"nodes":[
    {"id":"a","number":11,"title":"one","url":"https://github.com/o/r/issues/11","state":"OPEN"},
    {"id":"b","number":12,"title":"foreign","url":"https://github.com/x/y/issues/12","state":"OPEN"}
  ],"totalCount":2}}'
  LIST='[
    {"number":11,"title":"one","state":"OPEN","assignees":[],"labels":[],"issueType":null,"blockedBy":{"nodes":[]},"url":"https://github.com/o/r/issues/11"},
    {"number":12,"title":"same number, this repo","state":"OPEN","assignees":[],"labels":[],"issueType":null,"blockedBy":{"nodes":[]},"url":"https://github.com/o/r/issues/12"},
    {"number":13,"title":"unrelated","state":"OPEN","assignees":[],"labels":[],"issueType":null,"blockedBy":{"nodes":[]},"url":"https://github.com/o/r/issues/13"}
  ]'

  ERRFILE="$(mktemp "$TMP_ROOT/f.XXXXXX")"
  OUT="$(PATH="$STUB:$PATH" GH_STUB_VIEW="$VIEW" GH_STUB_LIST="$LIST" bash "$S" "github:o/r#99" 2>"$ERRFILE")"
  rc=$?
  assert_eq "list-sub-items over stubbed subIssues → exit 0" "0" "$rc"
  assert_eq "url-derived filter keeps the same-repo child" \
    "github:o/r#11" "$(jq -r '[.items[].id] | join(",")' <<<"$OUT")"
  assert_eq "child row is re-parented to the container" \
    "github:o/r#99" "$(jq -r '.items[0].parent_id' <<<"$OUT")"
  assert_eq "the intersect carries list-items' truncated flag" \
    "false" "$(jq -c '.truncated' <<<"$OUT")"
  assert_eq "well-formed nodes emit no derivable-repo warning" \
    "0" "$(grep -c 'no derivable repo' "$ERRFILE")"

  rm -f "$ERRFILE"
  rm -rf "$STUB"
fi

if command -v jq >/dev/null 2>&1; then
  STUB="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
  write_gh_stub "$STUB"
  VIEW='{"subIssues":{"nodes":[
    {"id":"a","number":21,"title":"one","url":"https://github.com/o/r/issues/21","state":"OPEN"},
    {"id":"b","number":22,"title":"no url","state":"OPEN"},
    {"id":"c","number":23,"title":"odd url","url":"https://github.com/o/r/pull/23","state":"OPEN"}
  ],"totalCount":3}}'
  LIST='[
    {"number":21,"title":"one","state":"OPEN","assignees":[],"labels":[],"issueType":null,"blockedBy":{"nodes":[]},"url":"https://github.com/o/r/issues/21"},
    {"number":22,"title":"two","state":"OPEN","assignees":[],"labels":[],"issueType":null,"blockedBy":{"nodes":[]},"url":"https://github.com/o/r/issues/22"},
    {"number":23,"title":"three","state":"OPEN","assignees":[],"labels":[],"issueType":null,"blockedBy":{"nodes":[]},"url":"https://github.com/o/r/issues/23"}
  ]'

  ERRFILE="$(mktemp "$TMP_ROOT/f.XXXXXX")"
  OUT="$(PATH="$STUB:$PATH" GH_STUB_VIEW="$VIEW" GH_STUB_LIST="$LIST" bash "$S" "github:o/r#99" 2>"$ERRFILE")"
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

if command -v jq >/dev/null 2>&1; then
  STUB="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
  write_gh_stub "$STUB"
  VIEW='{"subIssues":{"nodes":[
    {"id":"a","number":31,"title":"one","url":"https://github.com/Acme/Widgets/issues/31","state":"OPEN"},
    {"id":"b","number":32,"title":"foreign","url":"https://github.com/Other/Repo/issues/32","state":"OPEN"}
  ],"totalCount":2}}'
  LIST='[
    {"number":31,"title":"one","state":"OPEN","assignees":[],"labels":[],"issueType":null,"blockedBy":{"nodes":[]},"url":"https://github.com/acme/widgets/issues/31"},
    {"number":32,"title":"same number, this repo","state":"OPEN","assignees":[],"labels":[],"issueType":null,"blockedBy":{"nodes":[]},"url":"https://github.com/acme/widgets/issues/32"}
  ]'

  ERRFILE="$(mktemp "$TMP_ROOT/f.XXXXXX")"
  OUT="$(PATH="$STUB:$PATH" GH_STUB_VIEW="$VIEW" GH_STUB_LIST="$LIST" bash "$S" "github:acme/widgets#99" 2>"$ERRFILE")"
  rc=$?
  assert_eq "case-differing repo → exit 0" "0" "$rc"
  assert_eq "case-differing same-repo child is kept, not read as foreign" \
    "github:acme/widgets#31" "$(jq -r '[.items[].id] | join(",")' <<<"$OUT")"
  assert_eq "case-folding does not pull in a cross-repo node" \
    "1" "$(jq -r '.items | length' <<<"$OUT")"
  assert_eq "case-differing nodes are attributable, so no warning" \
    "0" "$(grep -c 'no derivable repo' "$ERRFILE")"

  rm -f "$ERRFILE"
  rm -rf "$STUB"
fi

[[ $FAILED -eq 0 ]] || exit 1
