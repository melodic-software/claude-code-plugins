#!/usr/bin/env bash
# create-item — Gitea / Forgejo adapter (provider `gitea`).
# Scaffolded by /work-items:onboard-adapter; the provider mapping below is written
# against POST /repos/{owner}/{repo}/issues and Gitea's `CreateIssueOption`.
#
# Contract: tools/work-item-tracker/CONTRACT.md — "Verbs", "Adapter contract",
# "JSON output contract", "Exit codes".
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
  --title)
    [[ $# -ge 2 ]] || wit_usage_error "--title needs a value"
    TITLE="$2"
    shift 2
    ;;
  --body)
    [[ $# -ge 2 ]] || wit_usage_error "--body needs a value"
    BODY="$2"
    shift 2
    ;;
  --labels)
    [[ $# -ge 2 ]] || wit_usage_error "--labels needs a value"
    LABELS="$2"
    shift 2
    ;;
  --type)
    [[ $# -ge 2 ]] || wit_usage_error "--type needs a value"
    TYPE="$2"
    shift 2
    ;;
  --parent)
    [[ $# -ge 2 ]] || wit_usage_error "--parent needs a value"
    PARENT="$2"
    shift 2
    ;;
  --blocked-by)
    [[ $# -ge 2 ]] || wit_usage_error "--blocked-by needs a value"
    BLOCKED_BY="$2"
    shift 2
    ;;
  --repo)
    [[ $# -ge 2 ]] || wit_usage_error "--repo needs a value"
    REPO="$2"
    shift 2
    ;;
  *) wit_usage_error "unexpected argument: $1" ;;
  esac
done
[[ -n "$TITLE" ]] || wit_usage_error "--title is required"

# --parent asks for a sub-item link. Gitea's Issue has no parent field and this
# adapter's manifest declares sub_items=false, so honoring it is impossible — and
# accepting it silently would report a created item whose stated parent does not exist.
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

# Every --blocked-by id is validated BEFORE the item is created. The edges are written
# in a second request, so a malformed id discovered afterwards would leave a created
# item whose declared blockers were never linked — an item that then looks ready.
BLOCKERS=()
if [[ -n "$BLOCKED_BY" ]]; then
  IFS=',' read -r -a BLOCKERS <<<"$BLOCKED_BY"
  for b in "${BLOCKERS[@]}"; do
    wit_require_gitea_id "$b" || wit_usage_error "not a gitea item id: $b"
    wit_gitea_scope_in_scope "$WIT_ID_OWNER/$WIT_ID_REPO" ||
      wit_usage_error "blocker $b is outside config.gitea.scopes"
  done
fi

# Gitea's CreateIssueOption takes label IDs (`labels: []int64`), NOT label names — a
# real divergence from GitHub's API, and one that fails silently if ignored (a name
# array is simply not accepted). Resolve names to ids against the repo's label set, and
# refuse an unknown name rather than dropping it: a work item filed without its
# priority or type label is invisible to the very tiers that would have selected it.
LABEL_IDS='[]'
if [[ -n "$LABELS" ]]; then
  wit_gitea_http GET "/repos/$WIT_GITEA_OWNER/$WIT_GITEA_REPO/labels?page=1&limit=$WIT_GITEA_PAGE_SIZE"
  wit_gitea_require_ok "listing labels in $REPO"
  ALL_LABELS="$WIT_GITEA_BODY"
  PAGE=2
  LABELS_TRUNCATED=0
  # This handler calls ctx.SetTotalCountHeader (routers/api/v1/repo/label.go), so when the
  # header is present it decides when the list is exhausted. That matters more here than in
  # list-items: gitea clamps `limit` to `[api] MAX_RESPONSE_ITEMS` (stock 50), and under the
  # old page-length test an instance whose cap is below config.gitea.page_size stopped after
  # page 1 — making a label past that point indistinguishable from a nonexistent one, so the
  # operator was told to create a label that already exists. SEEN/-n mirror list-items: an
  # empty header means "no count sent", never zero.
  LABEL_SEEN="$(jq 'length' <<<"$WIT_GITEA_BODY" 2>/dev/null)" || LABEL_SEEN=0
  LABEL_TOTAL="$WIT_GITEA_TOTAL_COUNT"
  while :; do
    if [[ -n "$LABEL_TOTAL" ]]; then
      ((LABEL_SEEN >= LABEL_TOTAL)) && break
    else
      (($(jq 'length' <<<"$WIT_GITEA_BODY") < WIT_GITEA_PAGE_SIZE)) && break
    fi
    # Bounded like every other paginated loop in this adapter: a server that keeps
    # answering a full page would otherwise spin forever with ALL_LABELS growing
    # without limit.
    if ((PAGE * WIT_GITEA_PAGE_SIZE > WIT_GITEA_LIST_ITEMS_MAX)); then
      LABELS_TRUNCATED=1
      break
    fi
    wit_gitea_http GET "/repos/$WIT_GITEA_OWNER/$WIT_GITEA_REPO/labels?page=$PAGE&limit=$WIT_GITEA_PAGE_SIZE"
    wit_gitea_require_ok "listing labels in $REPO (page $PAGE)"
    ALL_LABELS="$(jq -c --argjson acc "$ALL_LABELS" '$acc + .' <<<"$WIT_GITEA_BODY")"
    LABEL_SEEN=$((LABEL_SEEN + $(jq 'length' <<<"$WIT_GITEA_BODY" 2>/dev/null || echo 0)))
    # An empty page ends the walk whatever the header claimed — a count that never gets
    # satisfied must not turn into an unbounded loop.
    (($(jq 'length' <<<"$WIT_GITEA_BODY" 2>/dev/null || echo 0) == 0)) && break
    PAGE=$((PAGE + 1))
  done
  # ORGANIZATION-WIDE labels are usable on this repo's issues and are NOT in the repo label
  # list. `GetLabelsByRepoID` backs /repos/{o}/{r}/labels with `WHERE repo_id = ?`, so an org
  # label never appears there — but `NewIssueWithIndex` accepts any label whose
  # `OrgID == repo.OwnerID`. The asymmetry was user-visible and backwards: get-item and
  # list-items DO report an org label in `.labels[]` (it is on the issue), so the tracker
  # returned a label name it would then refuse to write back, telling the operator to create
  # a label that already exists. A user-owned repo has no org and answers 404 here, which is
  # not an error — it just means there are no org labels to merge.
  wit_gitea_http GET "/orgs/$WIT_GITEA_OWNER/labels?page=1&limit=$WIT_GITEA_PAGE_SIZE"
  if [[ "$WIT_GITEA_STATUS" != "404" ]]; then
    wit_gitea_require_ok "listing organization labels for $WIT_GITEA_OWNER"
    ORG_PAGE="$WIT_GITEA_BODY"
    ORG_EFFECTIVE=0
    ORG_PAGE_NUM=2
    while :; do
      ALL_LABELS="$(jq -c --argjson acc "$ALL_LABELS" '$acc + .' <<<"$ORG_PAGE")"
      ORG_GOT="$(jq 'length' <<<"$ORG_PAGE" 2>/dev/null)" || ORG_GOT=0
      ((ORG_GOT > ORG_EFFECTIVE)) && ORG_EFFECTIVE="$ORG_GOT"
      ((ORG_GOT == 0)) && break
      ((ORG_GOT < ORG_EFFECTIVE)) && break
      if ((ORG_PAGE_NUM * WIT_GITEA_PAGE_SIZE > WIT_GITEA_LIST_ITEMS_MAX)); then
        LABELS_TRUNCATED=1
        break
      fi
      wit_gitea_http GET "/orgs/$WIT_GITEA_OWNER/labels?page=$ORG_PAGE_NUM&limit=$WIT_GITEA_PAGE_SIZE"
      wit_gitea_require_ok "listing organization labels for $WIT_GITEA_OWNER (page $ORG_PAGE_NUM)"
      ORG_PAGE="$WIT_GITEA_BODY"
      ORG_PAGE_NUM=$((ORG_PAGE_NUM + 1))
    done
  fi
  MISSING="$(jq -rc --arg names "$LABELS" --argjson all "$ALL_LABELS" \
    '[($names | split(",") | .[] | select(length > 0)) as $n | select([$all[].name] | index($n) | not) | $n]' <<<'null')"
  if [[ "$MISSING" != "[]" ]]; then
    # The ceiling changes what "not found" is allowed to mean. Unlike list-items, where
    # truncation just returns fewer items, stopping early here makes an unseen label
    # indistinguishable from a nonexistent one — and telling someone to create a label
    # that already exists sends them to do the wrong thing. Say which case this is.
    if ((LABELS_TRUNCATED)); then
      printf 'create-item.sh: label(s) not found in the first %s labels of %s: %s — the label list was truncated at the declared ceiling, so these may exist beyond it; narrow --labels or raise the ceiling rather than re-creating them\n' \
        "$WIT_GITEA_LIST_ITEMS_MAX" "$REPO" "$MISSING" >&2
    else
      printf 'create-item.sh: label(s) not found in %s: %s — create them first, or drop them from --labels\n' \
        "$REPO" "$MISSING" >&2
    fi
    exit "$EX_NOT_FOUND"
  fi
  LABEL_IDS="$(jq -c --arg names "$LABELS" --argjson all "$ALL_LABELS" \
    '[($names | split(",") | .[] | select(length > 0)) as $n | ($all[] | select(.name == $n) | .id)]' <<<'null')"
fi

# --type is accepted and cannot be honored: Gitea has no issue-type registry, so the
# normalized `type` is structurally null for this provider. Said on stderr rather than
# dropped silently, because a caller that set a type deserves to know it did not stick.
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

# Blocker edges are a separate call per edge; Gitea has no create-with-dependencies
# form. A failure here exits non-zero rather than reporting the item as created-and-
# linked, so the caller learns the graph is incomplete.
for b in ${BLOCKERS[@]+"${BLOCKERS[@]}"}; do
  wit_require_gitea_id "$b"
  wit_gitea_http POST "/repos/$WIT_GITEA_OWNER/$WIT_GITEA_REPO/issues/$NUMBER/dependencies" \
    "$(jq -cn --arg o "$WIT_ID_OWNER" --arg r "$WIT_ID_REPO" --argjson i "$WIT_ID_NUMBER" \
      '{owner: $o, repo: $r, index: $i}')"
  wit_gitea_require_ok "linking $REPO#$NUMBER as blocked by $b"
done

# The count is a READ-BACK: by here the issue EXISTS and its blocker edges are written.
# The helper exits on transport/HTTP failure, but inside $( ) that only ends the
# subshell, and continuing with "" fed jq an empty --argjson — the item was created and
# the caller was told exit 2, "usage".
#
# The read still has to fail the verb: the contract's item object requires
# blocked_by_count, and there is no honest value to substitute — 0 is the frontier lie
# this adapter counts open blockers to avoid. So propagate the read's own code, keeping
# the seam's status vocabulary intact (8 stays "unavailable, back off", 4 stays auth).
# What non-zero must NOT mean here is "nothing happened": name the created id on stderr
# so a retry re-reads the item instead of filing a second one.
BBC="$(wit_gitea_blocked_by_count "$WIT_GITEA_OWNER" "$WIT_GITEA_REPO" "$NUMBER")" || {
  RC=$?
  printf 'create-item.sh: gitea:%s#%s WAS CREATED (blocker edges written); only its open-blocker count could not be read — re-read it with get-item, do not create it again\n' \
    "$REPO" "$NUMBER" >&2
  exit "$RC"
}
jq -c --arg sv "$WIT_SCHEMA_VERSION" --argjson bbc "$BBC" \
  --arg full "$WIT_GITEA_OWNER/$WIT_GITEA_REPO" \
  '(.repository.full_name //= $full) | '"$WIT_GITEA_NORMALIZE_PROGRAM" <<<"$CREATED"
