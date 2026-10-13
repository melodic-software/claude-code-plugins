#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/list-items.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S" --state bogus

# --- the envelope reports truncation at the declared ceiling ---
# Runs a fixture copy of the adapter whose manifest declares a ceiling of 2, so a
# three-row listing is past it. The stub logs gh's argv: the adapter must ask for
# one row past the ceiling, or it cannot tell "exactly 2" from "more than 2".
if command -v jq >/dev/null 2>&1; then
  FIX="$(mktemp -d)"
  trap 'rm -rf "$FIX"' EXIT
  mkdir -p "$FIX/adapters" "$FIX/bin"
  cp -R "$(dirname "$S")" "$FIX/adapters/github"
  cp -R "$(dirname "$S")/../../lib" "$FIX/lib"
  jq '.limits.list_items_max = 2' "$(dirname "$S")/capabilities.json" >"$FIX/adapters/github/capabilities.json"
  cat >"$FIX/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_STUB_ARGV"
if [[ -n "${GH_STUB_LIST_FILE:-}" ]]; then cat "$GH_STUB_LIST_FILE"; else printf '%s\n' "${GH_STUB_LIST:?}"; fi
EOF
  chmod +x "$FIX/bin/gh"
  row() { printf '{"number":%s,"title":"t","state":"OPEN","assignees":[],"labels":[],"issueType":null,"blockedBy":{"nodes":[]},"url":"https://github.com/o/r/issues/%s","createdAt":"2026-03-0%sT10:00:00Z"}' "$1" "$1" "$1"; }

  OUT="$(PATH="$FIX/bin:$PATH" GH_STUB_ARGV="$FIX/argv" GH_STUB_LIST="[$(row 1),$(row 2),$(row 3)]" \
    bash "$FIX/adapters/github/list-items.sh" --repo o/r)"
  assert_eq "a listing past the ceiling → exit 0 (documented truncation)" "0" "$?"
  assert_eq "past the ceiling: truncated is true" "true" "$(jq -c '.truncated' <<<"$OUT")"
  assert_eq "past the ceiling: only the ceiling's worth of rows" \
    "github:o/r#1,github:o/r#2" "$(jq -r '[.items[].id] | join(",")' <<<"$OUT")"
  assert_contains "the request asks for one row past the ceiling" "$(cat "$FIX/argv")" "--limit 3"

  OUT="$(PATH="$FIX/bin:$PATH" GH_STUB_ARGV="$FIX/argv" GH_STUB_LIST="[$(row 1),$(row 2)]" \
    bash "$FIX/adapters/github/list-items.sh" --repo o/r)"
  assert_eq "exactly the ceiling's worth of rows: truncated is false" "false" "$(jq -c '.truncated' <<<"$OUT")"
  assert_eq "exactly the ceiling: every row kept" "2" "$(jq '.items | length' <<<"$OUT")"
  assert_eq "each row carries its createdAt as created_at" "2026-03-01T10:00:00Z,2026-03-02T10:00:00Z" \
    "$(jq -r '[.items[].created_at] | join(",")' <<<"$OUT")"
  assert_contains "createdAt is requested" "$(cat "$FIX/argv")" "url,createdAt"

  # --label goes to gh, so GitHub filters before the ceiling counts.
  : >"$FIX/argv"
  PATH="$FIX/bin:$PATH" GH_STUB_ARGV="$FIX/argv" GH_STUB_LIST="[$(row 1)]" \
    bash "$FIX/adapters/github/list-items.sh" --repo o/r --label "area: ci" >/dev/null
  assert_contains "--label reaches gh issue list" "$(cat "$FIX/argv")" "--label area: ci --limit 3"
  assert_usage_error "$S" --label

  # A labeled read goes through GitHub search, which returns at most 1000 results, so
  # 1000 labeled rows cannot prove the listing complete; 1000 unlabeled rows can.
  jq '.limits.list_items_max = 1000' "$(dirname "$S")/capabilities.json" >"$FIX/adapters/github/capabilities.json"
  jq -cn '[range(1; 1001) | {number: ., title: "t", state: "OPEN", assignees: [], labels: [],
    issueType: null, blockedBy: {nodes: []}, url: "https://github.com/o/r/issues/\(.)"}]' >"$FIX/thousand.json"
  OUT="$(PATH="$FIX/bin:$PATH" GH_STUB_ARGV="$FIX/argv" GH_STUB_LIST_FILE="$FIX/thousand.json" \
    bash "$FIX/adapters/github/list-items.sh" --repo o/r --label "area: ci")"
  assert_eq "1000 labeled rows (the search cap) → truncated:true" "true" "$(jq -c '.truncated' <<<"$OUT")"
  OUT="$(PATH="$FIX/bin:$PATH" GH_STUB_ARGV="$FIX/argv" GH_STUB_LIST_FILE="$FIX/thousand.json" \
    bash "$FIX/adapters/github/list-items.sh" --repo o/r)"
  assert_eq "1000 unlabeled rows at a 1000 ceiling → truncated:false" "false" "$(jq -c '.truncated' <<<"$OUT")"
fi

[[ $FAILED -eq 0 ]] || exit 1
