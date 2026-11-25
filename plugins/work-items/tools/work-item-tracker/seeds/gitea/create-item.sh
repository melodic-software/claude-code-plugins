#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

USAGE='usage: create-item.sh --title <t> [--body <b>] [--labels a,b] [--type <name>] [--parent <id>] [--blocked-by <id>[,<id>]] [--repo <o>/<r>]'
wit_help_if_requested "$USAGE" "$@"

TITLE=""
BODY=""
LABELS=""
TYPE=""
PARENT=""
BLOCKED_BY=""
REPO=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --title | --body | --labels | --type | --parent | --blocked-by | --repo)
    [[ $# -ge 2 ]] || wit_usage_error "$1 needs a value"
    case "$1" in
    --title) TITLE="$2" ;;
    --body) BODY="$2" ;;
    --labels) LABELS="$2" ;;
    --type) TYPE="$2" ;;
    --parent) PARENT="$2" ;;
    --blocked-by) BLOCKED_BY="$2" ;;
    *) REPO="$2" ;;
    esac
    shift 2
    ;;
  *) wit_usage_error "unexpected argument: $1" ;;
  esac
done
[[ -n "$TITLE" ]] || wit_usage_error "--title is required"

[[ -z "$PARENT" ]] ||
  wit_usage_error "--parent is unsupported: gitea has no native sub-item link (capabilities.json features.sub_items=false)"

wit_need_gitea_config

if [[ -z "$REPO" ]]; then
  if [[ "$(jq 'length' <<<"$WIT_GITEA_SCOPES")" != "1" ]]; then
    wit_usage_error "--repo is required when config.gitea.scopes declares more than one repository"
  fi
  REPO="$(jq -r '.[0]' <<<"$WIT_GITEA_SCOPES")"
fi
[[ "$REPO" =~ $WIT_GITEA_SCOPE_RE ]] ||
  wit_usage_error "--repo must be <owner>/<repo>: $REPO"
wit_gitea_scope_in_scope "$REPO" ||
  wit_usage_error "$REPO is not in config.gitea.scopes (the declared write scope)"
wit_gitea_scope_parts "$REPO"

BLOCKERS=()
if [[ -n "$BLOCKED_BY" ]]; then
  IFS=',' read -r -a BLOCKERS <<<"$BLOCKED_BY"
  for b in "${BLOCKERS[@]}"; do
    wit_require_gitea_id "$b" || wit_usage_error "not a gitea item id: $b"
    wit_gitea_scope_in_scope "$WIT_ID_OWNER/$WIT_ID_REPO" ||
      wit_usage_error "blocker $b is outside config.gitea.scopes"
  done
fi

LABEL_IDS='[]'
if [[ -n "$LABELS" ]]; then
  wit_gitea_http GET "/repos/$WIT_GITEA_OWNER/$WIT_GITEA_REPO/labels?page=1&limit=$WIT_GITEA_PAGE_SIZE"
  wit_gitea_require_ok "listing labels in $REPO"
  wit_gitea_require_array "listing labels in $REPO"
  ALL_LABELS="$WIT_GITEA_BODY"
  PAGE=2
  LABELS_TRUNCATED=0
  LABEL_SEEN="$(jq 'length' <<<"$WIT_GITEA_BODY" 2>/dev/null)" || LABEL_SEEN=0
  LABEL_GOT="$LABEL_SEEN"
  LABEL_TOTAL="$WIT_GITEA_TOTAL_COUNT"
  while :; do
    if [[ -n "$LABEL_TOTAL" ]]; then
      ((LABEL_SEEN >= LABEL_TOTAL)) && break
    else
      ((LABEL_GOT < WIT_GITEA_PAGE_SIZE)) && break
    fi
    if ((LABEL_SEEN > WIT_GITEA_LIST_ITEMS_MAX)); then
      LABELS_TRUNCATED=1
      break
    fi
    wit_gitea_http GET "/repos/$WIT_GITEA_OWNER/$WIT_GITEA_REPO/labels?page=$PAGE&limit=$WIT_GITEA_PAGE_SIZE"
    wit_gitea_require_ok "listing labels in $REPO (page $PAGE)"
    wit_gitea_require_array "listing labels in $REPO (page $PAGE)"
    ALL_LABELS="$(jq -c --argjson page "$WIT_GITEA_BODY" '. + $page' <<<"$ALL_LABELS")" || {
      printf 'create-item.sh: could not accumulate label page %s for %s\n' "$PAGE" "$REPO" >&2
      exit "$EX_INTERNAL"
    }
    LABEL_GOT="$(jq 'length' <<<"$WIT_GITEA_BODY" 2>/dev/null)" || LABEL_GOT=0
    LABEL_SEEN=$((LABEL_SEEN + LABEL_GOT))
    ((LABEL_GOT == 0)) && break
    PAGE=$((PAGE + 1))
  done
  wit_gitea_http GET "/orgs/$WIT_GITEA_OWNER/labels?page=1&limit=$WIT_GITEA_PAGE_SIZE"
  if [[ "$WIT_GITEA_STATUS" != "404" ]]; then
    wit_gitea_require_ok "listing organization labels for $WIT_GITEA_OWNER"
    wit_gitea_require_array "listing organization labels for $WIT_GITEA_OWNER"
    ORG_PAGE="$WIT_GITEA_BODY"
    ORG_TOTAL="$WIT_GITEA_TOTAL_COUNT"
    ORG_SEEN=0
    ORG_PAGE_NUM=2
    while :; do
      ALL_LABELS="$(jq -c --argjson page "$ORG_PAGE" '. + $page' <<<"$ALL_LABELS")" || {
        printf 'create-item.sh: could not accumulate org label page %s for %s\n' \
          "$ORG_PAGE_NUM" "$WIT_GITEA_OWNER" >&2
        exit "$EX_INTERNAL"
      }
      ORG_GOT="$(jq 'length' <<<"$ORG_PAGE" 2>/dev/null)" || ORG_GOT=0
      ORG_SEEN=$((ORG_SEEN + ORG_GOT))
      ((ORG_GOT == 0)) && break
      if [[ -n "$ORG_TOTAL" ]]; then
        ((ORG_SEEN >= ORG_TOTAL)) && break
      else
        ((ORG_GOT < WIT_GITEA_PAGE_SIZE)) && break
      fi
      if ((ORG_SEEN > WIT_GITEA_LIST_ITEMS_MAX)); then
        LABELS_TRUNCATED=1
        break
      fi
      wit_gitea_http GET "/orgs/$WIT_GITEA_OWNER/labels?page=$ORG_PAGE_NUM&limit=$WIT_GITEA_PAGE_SIZE"
      wit_gitea_require_ok "listing organization labels for $WIT_GITEA_OWNER (page $ORG_PAGE_NUM)"
      wit_gitea_require_array "listing organization labels for $WIT_GITEA_OWNER (page $ORG_PAGE_NUM)"
      ORG_PAGE="$WIT_GITEA_BODY"
      ORG_PAGE_NUM=$((ORG_PAGE_NUM + 1))
    done
  fi
  MISSING="$(jq -rcn --arg names "$LABELS" --argjson all "$ALL_LABELS" \
    '[($names | split(",") | .[] | select(length > 0)) as $n | select([$all[].name] | index($n) | not) | $n]')"
  if [[ "$MISSING" != "[]" ]]; then
    if ((LABELS_TRUNCATED)); then
      printf 'create-item.sh: label(s) not found in the first %s labels of %s: %s — the label list was truncated at the declared ceiling, so these may exist beyond it; narrow --labels or raise the ceiling rather than re-creating them\n' \
        "$WIT_GITEA_LIST_ITEMS_MAX" "$REPO" "$MISSING" >&2
    else
      printf 'create-item.sh: label(s) not found in %s: %s — create them first, or drop them from --labels\n' \
        "$REPO" "$MISSING" >&2
    fi
    exit "$EX_NOT_FOUND"
  fi
  LABEL_IDS="$(jq -cn --arg names "$LABELS" --argjson all "$ALL_LABELS" \
    '[($names | split(",") | .[] | select(length > 0)) as $n | ($all[] | select(.name == $n) | .id)]')"
fi

[[ -z "$TYPE" ]] ||
  printf 'create-item.sh: --type is ignored: gitea has no native issue-type axis (normalized type is always null)\n' >&2

PAYLOAD="$(jq -cn --arg t "$TITLE" --arg b "$BODY" --argjson l "$LABEL_IDS" \
  '{title: $t} + (if ($b | length) > 0 then {body: $b} else {} end) + (if ($l | length) > 0 then {labels: $l} else {} end)')"
wit_gitea_http POST "/repos/$WIT_GITEA_OWNER/$WIT_GITEA_REPO/issues" "$PAYLOAD"
wit_gitea_require_ok "creating an issue in $REPO"

CREATED="$WIT_GITEA_BODY"
NUMBER="$(jq -r '.number' <<<"$CREATED")"
[[ "$NUMBER" =~ ^[0-9]+$ ]] || {
  printf 'create-item.sh: gitea returned no issue number for the created item in %s\n' "$REPO" >&2
  exit "$EX_INTERNAL"
}

for b in ${BLOCKERS[@]+"${BLOCKERS[@]}"}; do
  wit_require_gitea_id "$b"
  wit_gitea_http POST "/repos/$WIT_GITEA_OWNER/$WIT_GITEA_REPO/issues/$NUMBER/dependencies" \
    "$(jq -cn --arg o "$WIT_ID_OWNER" --arg r "$WIT_ID_REPO" --argjson i "$WIT_ID_NUMBER" \
      '{owner: $o, repo: $r, index: $i}')"
  wit_gitea_require_ok "linking $REPO#$NUMBER as blocked by $b"
done

BBC="$(wit_gitea_blocked_by_count "$WIT_GITEA_OWNER" "$WIT_GITEA_REPO" "$NUMBER")" || {
  RC=$?
  printf 'create-item.sh: gitea:%s#%s WAS CREATED (blocker edges written); only its open-blocker count could not be read — re-read it with get-item, do not create it again\n' \
    "$REPO" "$NUMBER" >&2
  exit "$RC"
}
jq -c --arg sv "$WIT_SCHEMA_VERSION" --argjson bbc "$BBC" \
  --arg full "$WIT_GITEA_OWNER/$WIT_GITEA_REPO" \
  '(.repository.full_name //= $full) | '"$WIT_GITEA_NORMALIZE_PROGRAM" <<<"$CREATED"
