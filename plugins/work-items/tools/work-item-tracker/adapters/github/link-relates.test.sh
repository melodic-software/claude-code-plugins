#!/usr/bin/env bash
# test-scope: plugins/work-items/tools/work-item-tracker/adapters/github/fixtures/gh-relates-to-graphql.json plugins/work-items/tools/work-item-tracker/adapters/github/fixtures/gh-relates-to-rest.json
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG RUNNER_TEMP GITHUB_ACTIONS

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINK_S="$SCRIPT_DIR/link-relates.sh"
UNLINK_S="$SCRIPT_DIR/unlink-relates.sh"
LIST_S="$SCRIPT_DIR/list-relates.sh"
FIX_GQL="$SCRIPT_DIR/fixtures/gh-relates-to-graphql.json"
FIX_REST="$SCRIPT_DIR/fixtures/gh-relates-to-rest.json"
source "$SCRIPT_DIR/../../lib/verb-test-helpers.sh"

assert_help "$LINK_S"
assert_usage_error "$LINK_S"
assert_usage_error "$LINK_S" "github:o/r#1"
assert_usage_error "$LINK_S" "github:o/r#1" --related-to "github:o/r#1"
assert_usage_error "$LINK_S" "local-markdown:o/r#1" --related-to "github:o/r#2"

command -v jq >/dev/null 2>&1 || skip_suite "jq not on PATH"

STUB="$TMP_ROOT/bin"
LOG="$TMP_ROOT/gh.log"
EDGES="$TMP_ROOT/edges.json"
mkdir -p "$STUB"

cat >"$STUB/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_STUB_LOG"

if [[ "$1" == "api" && "$2" == "--paginate" && "$3" == repos/*/issues/*/relates_to* ]]; then
  path="${3%%\?*}"
  owner="${path#repos/}"; owner="${owner%%/*}"
  rest="${path#repos/"$owner"/}"; repo="${rest%%/*}"
  num="${path##*issues/}"; num="${num%/relates_to}"
  key="github:$owner/$repo#$num"
  jq -c --arg k "$key" '.[$k] // []' "$GH_STUB_EDGES"
  exit 0
fi

if [[ "$1" == "api" && "$2" == repos/*/issues/* ]]; then
  [[ "${GH_STUB_ISSUE_EXISTS:-1}" == "1" ]] && { echo "1"; exit 0; }
  echo "gh: Not Found (HTTP 404)" >&2
  exit 1
fi

if [[ "$1 $2" == "api graphql" ]]; then
  query="" o1="" r1="" n1="" o2="" r2="" n2="" id_a="" id_b=""
  shift 2
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -f | -F)
      kv="$2"
      case "$kv" in
      query=*) query="${kv#query=}" ;;
      o1=*) o1="${kv#o1=}" ;;
      r1=*) r1="${kv#r1=}" ;;
      n1=*) n1="${kv#n1=}" ;;
      o2=*) o2="${kv#o2=}" ;;
      r2=*) r2="${kv#r2=}" ;;
      n2=*) n2="${kv#n2=}" ;;
      issueId=*) id_a="${kv#issueId=}" ;;
      relatedIssueId=*) id_b="${kv#relatedIssueId=}" ;;
      esac
      shift 2
      ;;
    *) shift ;;
    esac
  done

  if [[ "$query" == query* ]]; then
    if [[ "${GH_STUB_MISSING_SIDE:-}" == "a" ]]; then
      printf '{"data":{"a":{"issue":null},"b":{"issue":{"id":"I_2"}}}}\n'
      exit 0
    fi
    if [[ "${GH_STUB_MISSING_SIDE:-}" == "b" ]]; then
      printf '{"data":{"a":{"issue":{"id":"I_1"}},"b":{"issue":null}}}\n'
      exit 0
    fi
    printf '{"data":{"a":{"issue":{"id":"I_%s_%s_%s"}},"b":{"issue":{"id":"I_%s_%s_%s"}}}}\n' \
      "$o1" "$r1" "$n1" "$o2" "$r2" "$n2"
    exit 0
  fi

  if [[ -n "${GH_STUB_MUT_ERR:-}" ]]; then
    printf '%s\n' "$GH_STUB_MUT_ERR" >&2
    exit 1
  fi
  if [[ -n "${GH_STUB_GQL_200_ERR:-}" ]]; then
    jq -cn --arg m "$GH_STUB_GQL_200_ERR" '{data:null,errors:[{message:$m}]}'
    exit 0
  fi

  parse_node() {
    local s="${1#I_}"
    local o="${s%%_*}"; s="${s#*_}"
    local r="${s%%_*}"; local n="${s#*_}"
    printf '%s %s %s' "$o" "$r" "$n"
  }
  read -r ao ar an <<<"$(parse_node "$id_a")"
  read -r bo br bn <<<"$(parse_node "$id_b")"
  ka="github:$ao/$ar#$an"
  kb="github:$bo/$br#$bn"
  obja="$(jq -c --argjson n "$an" --arg u "https://github.com/$ao/$ar/issues/$an" --arg ru "https://api.github.com/repos/$ao/$ar" '.[0] + {number:$n,html_url:$u,repository_url:$ru}' "$GH_STUB_FIX_REST")"
  objb="$(jq -c --argjson n "$bn" --arg u "https://github.com/$bo/$br/issues/$bn" --arg ru "https://api.github.com/repos/$bo/$br" '.[1] + {number:$n,html_url:$u,repository_url:$ru}' "$GH_STUB_FIX_REST")"

  if [[ "$query" == *"addRelatesTo"* ]]; then
    jq -c --arg ka "$ka" --arg kb "$kb" --argjson oa "$obja" --argjson ob "$objb" \
      '.[$ka] = ((.[$ka] // []) + [$ob]) | .[$kb] = ((.[$kb] // []) + [$oa])' \
      "$GH_STUB_EDGES" >"$GH_STUB_EDGES.new" && mv "$GH_STUB_EDGES.new" "$GH_STUB_EDGES"
    jq -c --argjson an "$an" --argjson bn "$bn" '.add | .data.addRelatesTo.issue.number = $an | .data.addRelatesTo.relatedIssue.number = $bn' "$GH_STUB_FIX_GQL"
    exit 0
  fi
  if [[ "$query" == *"removeRelatesTo"* ]]; then
    jq -c --arg ka "$ka" --arg kb "$kb" --argjson an "$an" --argjson bn "$bn" \
      '.[$ka] = [(.[$ka] // [])[] | select(.number != $bn)] | .[$kb] = [(.[$kb] // [])[] | select(.number != $an)]' \
      "$GH_STUB_EDGES" >"$GH_STUB_EDGES.new" && mv "$GH_STUB_EDGES.new" "$GH_STUB_EDGES"
    jq -c --argjson an "$an" --argjson bn "$bn" '.remove | .data.removeRelatesTo.issue.number = $an | .data.removeRelatesTo.relatedIssue.number = $bn' "$GH_STUB_FIX_GQL"
    exit 0
  fi
fi
exit 90
EOF
chmod +x "$STUB/gh"

run_script() {
  local script="$1"
  shift
  OUT="$(PATH="$STUB:$PATH" GH_STUB_LOG="$LOG" GH_STUB_EDGES="$EDGES" \
    GH_STUB_FIX_GQL="$FIX_GQL" GH_STUB_FIX_REST="$FIX_REST" WIT_WRITE_SPACING_S=0 \
    bash "$script" "$@" 2>"$TMP_ROOT/err")"
  RC=$?
}

printf '{}\n' >"$EDGES"
: >"$LOG"

run_script "$LINK_S" "github:o/r#1" --related-to "github:other/repo#9"
assert_eq "link-relates happy path → exit 0" "0" "$RC"
assert_eq "link-relates linked=true" "true" "$(jq -r '.linked' <<<"$OUT")"
assert_eq "link-relates symmetric=true" "true" "$(jq -r '.symmetric' <<<"$OUT")"
assert_eq "link-relates related_to" "github:other/repo#9" "$(jq -r '.related_to' <<<"$OUT")"

run_script "$LIST_S" "github:o/r#1"
assert_eq "list-relates on #1 sees cross-repo #9" "github:other/repo#9" "$(jq -r '.items[0].id' <<<"$OUT")"
run_script "$LIST_S" "github:other/repo#9"
assert_eq "list-relates on #9 symmetrically sees #1" "github:o/r#1" "$(jq -r '.items[0].id' <<<"$OUT")"

run_script "$UNLINK_S" "github:o/r#1" --related-to "github:other/repo#9"
assert_eq "unlink-relates → exit 0" "0" "$RC"
assert_eq "unlink-relates unlinked=true" "true" "$(jq -r '.unlinked' <<<"$OUT")"
run_script "$LIST_S" "github:other/repo#9"
assert_eq "list-relates on #9 empty after symmetric unlink" "0" "$(jq '.items | length' <<<"$OUT")"

GH_STUB_MISSING_SIDE=b run_script "$LINK_S" "github:o/r#1" --related-to "github:o/r#999"
assert_eq "missing related issue → exit 5" "5" "$RC"

CLAUDE_CODE_REMOTE=true run_script "$LINK_S" "github:o/r#1" --related-to "github:o/r#2"
assert_eq "cloud GraphQL refusal → graceful exit 6" "6" "$RC"
assert_eq "cloud refusal available=false" "false" "$(jq -r '.available' <<<"$OUT")"
assert_eq "cloud refusal fallback=refs-comment" "refs-comment" "$(jq -r '.fallback' <<<"$OUT")"

GH_STUB_MUT_ERR="GraphQL: Field 'addRelatesTo' doesn't exist on type 'Mutation'" \
  run_script "$LINK_S" "github:o/r#1" --related-to "github:o/r#2"
assert_eq "missing GraphQL mutation → graceful exit 6" "6" "$RC"
assert_eq "missing GraphQL mutation fallback=refs-comment" "refs-comment" "$(jq -r '.fallback' <<<"$OUT")"

GH_STUB_GQL_200_ERR="Field 'addRelatesTo' doesn't exist on type 'Mutation'" \
  run_script "$LINK_S" "github:o/r#1" --related-to "github:o/r#2"
assert_eq "HTTP 200 GraphQL schema error → graceful exit 6" "6" "$RC"

GH_STUB_MUT_ERR="gh: Forbidden (HTTP 403)" \
  run_script "$LINK_S" "github:o/r#1" --related-to "github:o/r#2"
assert_eq "HTTP 403 → graceful exit 6" "6" "$RC"

[[ $FAILED -eq 0 ]] || exit 1
