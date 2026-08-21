#!/usr/bin/env bash
# create-item — Linear adapter.
#
# Contract: tools/work-item-tracker/CONTRACT.md — "Verbs", "JSON output contract",
# "Exit codes".
#
# shellcheck disable=SC2016  # single-quoted `$name` here is a GraphQL variable, not a shell one
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

USAGE='usage: create-item.sh --title <t> [--body <b>] [--labels a,b] [--type <name>] [--parent <id>] [--blocked-by <id>[,<id>]] [--repo <workspace>/<TEAMKEY>]'
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

wit_need_linear_config

if [[ -z "$REPO" ]]; then
  # With exactly one declared team the target is unambiguous. With several, picking one
  # would quietly file into the wrong team, so it is a usage error naming the fix.
  if [[ "$(jq 'length' <<<"$WIT_LINEAR_SCOPES")" != "1" ]]; then
    wit_usage_error "--repo is required when config.linear.scopes declares more than one team"
  fi
  REPO="$(jq -r '.[0]' <<<"$WIT_LINEAR_SCOPES")"
fi
[[ "$REPO" =~ $WIT_LINEAR_SCOPE_RE ]] ||
  wit_usage_error "--repo must be <workspace>/<TEAMKEY>: $REPO"
wit_linear_scope_in_scope "$REPO" ||
  wit_usage_error "$REPO is not in config.linear.scopes (the declared scope)"
wit_linear_scope_parts "$REPO"
TARGET_TEAM="$WIT_LINEAR_TEAM"

# Everything referenced by id is validated and RESOLVED before the item is created.
# Parent and blocker links are separate operations, so a bad id discovered afterwards
# would leave a created item whose declared relationships were never written — an item
# that then looks ready.
PARENT_UUID=""
if [[ -n "$PARENT" ]]; then
  wit_linear_require_scoped_id "$PARENT"
  wit_linear_fetch_issue "$WIT_LINEAR_TEAM" "$WIT_ID_NUMBER"
  PARENT_UUID="$(jq -r '.id' <<<"$WIT_LINEAR_ISSUE")"
fi

BLOCKER_UUIDS=()
if [[ -n "$BLOCKED_BY" ]]; then
  IFS=',' read -r -a BLOCKERS <<<"$BLOCKED_BY"
  for b in "${BLOCKERS[@]}"; do
    wit_linear_require_scoped_id "$b"
    wit_linear_fetch_issue "$WIT_LINEAR_TEAM" "$WIT_ID_NUMBER"
    BLOCKER_UUIDS+=("$(jq -r '.id' <<<"$WIT_LINEAR_ISSUE")")
  done
fi

# The team's UUID, and the label ids for any requested label names. Linear's
# IssueCreateInput takes `labelIds`, not names — the same shape trap as Gitea's — so
# names are resolved here and an unknown one is REFUSED rather than dropped: an item
# filed without its type or priority label is invisible to the selection tiers that
# would have picked it up.
wit_linear_gql \
  'query($key: String!) { teams(filter: { key: { eq: $key } }, first: 1) { nodes { id } } }' \
  "$(jq -cn --arg k "$TARGET_TEAM" '{key: $k}')" \
  "resolving team $TARGET_TEAM"
TEAM_NODE="$(jq -c '.teams.nodes[0] // empty' <<<"$WIT_LINEAR_DATA")"
[[ -n "$TEAM_NODE" ]] || {
  printf 'create-item.sh: team %s not found in workspace %s\n' "$TARGET_TEAM" "$(wit_linear_workspace)" >&2
  exit "$EX_NOT_FOUND"
}
TEAM_UUID="$(jq -r '.id' <<<"$TEAM_NODE")"

LABEL_IDS='[]'
if [[ -n "$LABELS" ]]; then
  # Labels come from the ROOT `issueLabels` connection, PAGINATED. Two defects this shape
  # replaces, both found by validating this adapter against Linear's published schema:
  #
  #  1. The old query asked `team.labels(first: 250)` with no pageInfo and no loop. 250 is
  #     Linear's per-page maximum, not a "surely enough" number, so a team past that count
  #     silently lost labels — and because an unresolved name is REFUSED below, the failure
  #     was not a dropped label but a hard exit on a label that exists.
  #  2. `Team.labels` is documented only as "Labels associated with the team", while
  #     `IssueLabel.team` says "If null, the label is a workspace-level label available to
  #     all teams" and the root `issueLabels` query is the one documented to return "both
  #     workspace-level and team-scoped labels". A workspace label is valid on this team's
  #     issues, so refusing it was wrong.
  #
  # Filtering to this team OR workspace-level (`team: { null: true }`) keeps the resolution
  # scoped — a same-named label on some other team is still not silently borrowed.
  LABEL_QUERY='query($team: ID!, $first: Int!, $after: String) {
    issueLabels(
      filter: { or: [{ team: { id: { eq: $team } } }, { team: { null: true } }] }
      first: $first
      after: $after
    ) {
      nodes { id name }
      pageInfo { hasNextPage endCursor }
    }
  }'
  ALL_LABELS='[]'
  LABEL_CURSOR=""
  while :; do
    wit_linear_gql "$LABEL_QUERY" \
      "$(jq -cn --arg t "$TEAM_UUID" --argjson f "$WIT_LINEAR_PAGE_SIZE" --arg a "$LABEL_CURSOR" \
        '{team: $t, first: $f, after: (if ($a | length) > 0 then $a else null end)}')" \
      "resolving labels for team $TARGET_TEAM"
    LABEL_PAGE="$(jq -c '.issueLabels // {nodes: [], pageInfo: {hasNextPage: false}}' <<<"$WIT_LINEAR_DATA")"
    ALL_LABELS="$(jq -c --argjson acc "$ALL_LABELS" --argjson page "$LABEL_PAGE" \
      '$acc + ($page.nodes // [])' <<<'null')"
    [[ "$(jq -r '.pageInfo.hasNextPage // false' <<<"$LABEL_PAGE")" == "true" ]] || break
    LABEL_CURSOR="$(jq -r '.pageInfo.endCursor // ""' <<<"$LABEL_PAGE")"
    # endCursor is nullable in the schema; without a cursor the next request would restart
    # from the beginning and loop forever, so stop rather than spin.
    [[ -n "$LABEL_CURSOR" ]] || break
  done
  MISSING="$(jq -rc --arg names "$LABELS" --argjson all "$ALL_LABELS" \
    '[($names | split(",") | .[] | select(length > 0)) as $n | select([$all[].name] | index($n) | not) | $n]' <<<'null')"
  if [[ "$MISSING" != "[]" ]]; then
    printf 'create-item.sh: label(s) not found on team %s or at workspace level: %s — create them first, or drop them from --labels\n' \
      "$TARGET_TEAM" "$MISSING" >&2
    exit "$EX_NOT_FOUND"
  fi
  # first(...) — a name present both team-scoped and workspace-level resolves to one id, not two.
  LABEL_IDS="$(jq -c --arg names "$LABELS" --argjson all "$ALL_LABELS" \
    '[($names | split(",") | .[] | select(length > 0)) as $n | (first($all[] | select(.name == $n)) | .id)]' <<<'null')"
fi

# --type is accepted and cannot be honored: Linear has no issue-type axis in the
# contract's sense (its workflow-state "type" is the open/closed category, not a
# Task/Bug/Feature label), so the normalized `type` is structurally null. Said on stderr
# rather than dropped silently, because a caller that set a type deserves to know.
[[ -z "$TYPE" ]] ||
  printf 'create-item.sh: --type is ignored: linear has no native issue-type axis (normalized type is always null)\n' >&2

# The parent link rides in the CREATE input rather than a follow-up update — one fewer
# window in which a created item exists without its container.
INPUT="$(jq -cn --arg t "$TITLE" --arg d "$BODY" --arg team "$TEAM_UUID" \
  --argjson labels "$LABEL_IDS" --arg parent "$PARENT_UUID" \
  '{title: $t, teamId: $team}
   + (if ($d | length) > 0 then {description: $d} else {} end)
   + (if ($labels | length) > 0 then {labelIds: $labels} else {} end)
   + (if ($parent | length) > 0 then {parentId: $parent} else {} end)')"

wit_linear_gql \
  'mutation($input: IssueCreateInput!) { issueCreate(input: $input) { success issue { id number team { key } } } }' \
  "$(jq -cn --argjson i "$INPUT" '{input: $i}')" \
  "creating an issue in $REPO"
CREATED="$(jq -c '.issueCreate.issue // empty' <<<"$WIT_LINEAR_DATA")"
[[ -n "$CREATED" ]] || {
  printf 'create-item.sh: issue creation reported no issue\n' >&2
  exit "$EX_INTERNAL"
}
NEW_UUID="$(jq -r '.id' <<<"$CREATED")"
NEW_NUMBER="$(jq -r '.number' <<<"$CREATED")"

# Blocker edges are one mutation each; Linear has no create-with-relations form. A
# failure here exits non-zero rather than reporting the item as created-and-linked, so
# the caller learns the graph is incomplete.
for buuid in ${BLOCKER_UUIDS[@]+"${BLOCKER_UUIDS[@]}"}; do
  wit_linear_gql \
    'mutation($input: IssueRelationCreateInput!) { issueRelationCreate(input: $input) { success } }' \
    "$(jq -cn --arg b "$buuid" --arg t "$NEW_UUID" '{input: {issueId: $b, relatedIssueId: $t, type: "blocks"}}')" \
    "linking the new issue as blocked by $buuid"
done

# Re-read rather than normalizing the mutation payload: the created item's labels,
# relations, and state all come from the server, and the create response deliberately
# selects only what is needed to address it.
wit_linear_fetch_issue "$(jq -r '.team.key' <<<"$CREATED")" "$NEW_NUMBER"
wit_linear_normalize "$WIT_LINEAR_ISSUE"
