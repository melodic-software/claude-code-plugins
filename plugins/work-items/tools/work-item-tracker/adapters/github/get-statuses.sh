#!/usr/bin/env bash
# get-statuses --field <name> <id>... — CONTRACT.md "Verbs (core public surface)". Read-only.
# Reads each item's value of one single-select issue field (the core passes "Work status"), as
# GraphQL Issue.issueFieldValues answers it: one query per repository per 100 items. An item
# whose field is unset, or that the answer leaves out, reads null.
#
# When the binding sets config.github.status_trust (README "Work status trust"), the value is
# instead the one the newest counted Work status event left, null when that event removed it,
# so an uncounted change neither sets nor clears a counted state. The field is the model's
# models.issue-status field-id. Trust covers Work status only: any other --field reads plain.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage="usage: get-statuses --field <name> <id>..."
wit_help_if_requested "$usage" "$@"

field="" ids=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  --field)
    [[ $# -ge 2 && -n "$2" && -z "$field" ]] || wit_usage_error "--field needs one non-empty value"
    field="$2"
    shift 2
    ;;
  -*) wit_usage_error "unknown argument: $1" ;;
  *)
    wit_require_github_id "$1" || wit_usage_error "not a github item id: $1"
    ids+=("$1")
    shift
    ;;
  esac
done
[[ -n "$field" ]] || wit_usage_error "$usage"
wit_require_graphql_session "get-statuses"
wit_gh_load_status_trust
COUNTED_TRUST=""
[[ "$field" != "Work status" ]] || COUNTED_TRUST="$WIT_GH_STATUS_TRUST"

# A full page of field values may hide the Work status value; a full event window holding a
# value and no counted event may have pushed the counted setter out. Either fails the read.
readonly FIELD_VALUE_PAGE=25
readonly FIELD_EVENT_WINDOW=100
# The job token's bot, the one bot-setters entry the trust list need not hold.
readonly ACTIONS_BOT_ID=41898282 ACTIONS_BOT_LOGIN="github-actions[bot]"

TRUST_TMP=""
[[ -z "$COUNTED_TRUST" ]] || {
  TRUST_TMP="$(mktemp -d)"
  trap 'rm -rf "$TRUST_TMP"' EXIT
}

# trust_fail <exit> <message>: one stderr line, nothing on stdout.
trust_fail() {
  printf 'get-statuses: %s\n' "$2" >&2
  exit "$1"
}

# fetch_repo_file <repo> <path> <dest>: <path> on <repo>'s default branch into <dest>. A file
# that is not there exits 3 (configuration); any other failure exits with its mapped code.
fetch_repo_file() {
  local errfile="$TRUST_TMP/err" code
  if ! gh api -H "Accept: application/vnd.github.raw" "repos/$1/contents/$2" >"$3" 2>"$errfile"; then
    code="$(wit_map_gh_error "$(<"$errfile")")"
    [[ "$code" != "$EX_NOT_FOUND" ]] || code="$EX_CONFIG"
    trust_fail "$code" "status_trust: $2 on $1 unread: $(head -n 1 "$errfile")"
  fi
}

# trust_context <repo>: set CONTEXT to {field, states, ready, people, bots} from <repo>'s
# trust list and model: field the Work status field id, states the mapped option names, ready
# the one state a bot-setters value never counts for (the model's ready-state, else
# WIT_DEFAULT_READY_STATE), people the ids that count for every state (kind human, or the
# lanes App's login), bots the bot-setters ids that count for every state but ready. Exits 3
# when either file is invalid.
trust_context() {
  local repo="$1" actors_path model_path lanes actors records
  actors_path="$(jq -r '.trusted_actors' <<<"$WIT_GH_STATUS_TRUST")"
  model_path="$(jq -r '.model' <<<"$WIT_GH_STATUS_TRUST")"
  lanes="$(jq -r '.lanes_app' <<<"$WIT_GH_STATUS_TRUST")"
  fetch_repo_file "$repo" "$actors_path" "$TRUST_TMP/actors.json"
  fetch_repo_file "$repo" "$model_path" "$TRUST_TMP/model.yaml"
  actors="$(jq -ce '(if (.actors | type) == "array" then .actors else [] end) as $a
    | select(.version == 1 and all($a[]; type == "object" and (.id | type) == "number"
        and .id == (.id | floor) and .id > 0)) | $a' "$TRUST_TMP/actors.json" 2>/dev/null)" ||
    trust_fail "$EX_CONFIG" "status_trust: $actors_path on $repo is not version 1 with a positive whole id per actor"
  records="$(wit_yaml_records "$TRUST_TMP/model.yaml" 2>&1)" ||
    trust_fail "$EX_CONFIG" "status_trust: $model_path on $repo does not parse: $(tail -n 1 <<<"$records")"
  # shellcheck disable=SC2154  # WIT_DEFAULT_READY_STATE: lib/labels.sh, sourced through common.sh
  CONTEXT="$(jq -R -n -c --argjson actors "$actors" --arg lanes "$lanes" \
    --argjson bot_id "$ACTIONS_BOT_ID" --arg bot_login "$ACTIONS_BOT_LOGIN" \
    --arg default_ready "$WIT_DEFAULT_READY_STATE" '
    def ident: test("^[1-9][0-9]*$");
    [inputs | select(startswith("models.issue-status.")) | split("\t")
      | {key: (.[0] | ltrimstr("models.issue-status.")), value: (.[1:] | join("\t"))}] as $rows
    | ([$rows[] | select(.key == "field-id") | .value] | first // "") as $field
    | ([$rows[] | select(.key == "ready-state") | .value] | first // "") as $ready_set
    | (if $ready_set == "" then $default_ready else $ready_set end) as $ready
    | [$rows[] | select(.key | startswith("options.")) | {id: (.key | ltrimstr("options.")), state: .value}] as $options
    | [$rows[] | select(.key | startswith("bot-setters.")) | .key |= ltrimstr("bot-setters.")] as $setter_rows
    | (($setter_rows | length) / 2 | floor) as $count
    | [range($count) as $i | {id: ($setter_rows[] | select(.key == "\($i).id") | .value),
        login: ($setter_rows[] | select(.key == "\($i).login") | .value)}] as $setters
    | if ($field | ident | not) then {error: "field-id \($field | tojson) is not an id"}
      elif ($options | length) == 0 or any($options[]; (.id | ident | not) or .state == "")
      then {error: "options must map option ids to states"}
      elif ($options | map(.state) | unique | length) != ($options | length)
      then {error: "options map two option ids to one state"}
      elif ($setter_rows | map(.key) | sort) != ([range($count) | "\(.).id", "\(.).login"] | sort)
        or ($setters | length) != $count or any($setters[]; .login == "" or (.id | ident | not))
      then {error: "bot-setters is not a list of {id, login}"}
      elif $ready_set != "" and ([$options[].state] | index($ready_set) | not)
      then {error: "ready-state names a state no option maps"}
      else {
        field: $field,
        states: ($options | map(.state)),
        ready: $ready,
        people: [$actors[] | select(.kind == "human" or .login == $lanes) | .id],
        bots: [$setters[] | (.id | tonumber) as $id | .login as $login
          | select(($id == $bot_id and $login == $bot_login)
              or any($actors[]; .kind == "bot" and .id == $id and .login == $login)) | $id]
      } end' <<<"$records")" ||
    trust_fail "$EX_INTERNAL" "status_trust: $model_path on $repo could not be read"
  if jq -e 'has("error")' <<<"$CONTEXT" >/dev/null; then
    trust_fail "$EX_CONFIG" "status_trust: $model_path on $repo models.issue-status: $(jq -r '.error' <<<"$CONTEXT")"
  fi
}

# One JSON object per id: {id, repo, number}, grouped by repository.
rows="$(for id in "${ids[@]+"${ids[@]}"}"; do
  wit_require_github_id "$id"
  jq -nc --arg id "$id" --arg repo "$WIT_ID_OWNER/$WIT_ID_REPO" --argjson n "$WIT_ID_NUMBER" \
    '{id: $id, repo: $repo, number: $n}'
done | jq -sc 'group_by(.repo)')"

# shellcheck disable=SC2016  # GraphQL fragments, not bash expansions
readonly TRUST_FRAGMENTS='fragment who on Actor { __typename login ... on User { databaseId } ... on Bot { databaseId } }
fragment field on IssueFields { ... on IssueFieldSingleSelect { fullDatabaseId } }'
readonly TRUST_SELECTION="issueFieldValues(first: $FIELD_VALUE_PAGE) { nodes { ... on IssueFieldSingleSelectValue { name field { ...field } } } } timelineItems(last: $FIELD_EVENT_WINDOW, itemTypes: [ISSUE_FIELD_ADDED_EVENT, ISSUE_FIELD_CHANGED_EVENT, ISSUE_FIELD_REMOVED_EVENT]) { nodes { __typename ... on IssueFieldAddedEvent { value actor { ...who } issueField { ...field } } ... on IssueFieldChangedEvent { newValue actor { ...who } issueField { ...field } } ... on IssueFieldRemovedEvent { actor { ...who } issueField { ...field } } } }"

# The trusted walk over one answer: {statuses} or {error}.
# shellcheck disable=SC2016  # jq program
readonly TRUST_WALK_JQ='
  def listed($list): . as $x | any($list[]; . == $x);
  def ours($key): (.[$key].fullDatabaseId? // null) as $f | $f != null and ($f | tostring) == $ctx.field;
  def status($n):
    if . == null then {s: null}
    elif (.issueFieldValues.nodes | type) != "array" or (.timelineItems.nodes | type) != "array"
    then {e: "#\($n) Work status: the answer holds no list"}
    elif (.issueFieldValues.nodes | length) >= $page
    then {e: "#\($n) Work status: \(.issueFieldValues.nodes | length) field values fill the page"}
    else
      ([.issueFieldValues.nodes[] | objects | select(ours("field")) | .name] | first) as $value
      | .timelineItems.nodes as $events
      | [$events | reverse[] | objects | select(ours("issueField"))
          | {setter: (.actor.databaseId? // null),
             state: (if .__typename == "IssueFieldRemovedEvent" then null
                     elif .__typename == "IssueFieldChangedEvent" then .newValue else .value end)}
          | select((.setter | type) == "number"
              and ((.setter | listed($ctx.people))
                or ((.setter | listed($ctx.bots)) and .state != $ctx.ready)))] as $counted
      | if ($counted | length) > 0 then
          $counted[0].state as $state
          | if $state != null and ($state | listed($ctx.states) | not)
            then {e: "#\($n) Work status holds \($state | tojson), which models.issue-status does not map"}
            else {s: $state} end
        elif $value != null and ($events | length) >= $window
        then {e: "#\($n) Work status: no counted setter in its newest \($window) field events"}
        else {s: null} end
    end;
  .data.repository as $r
  | [$chunk[] as $c | {id: $c.id, out: ($r["i\($c.number)"] | status($c.number))}] as $rows
  | if any($rows[]; .out | has("e")) then {error: ([$rows[] | .out.e // empty] | first)}
    else {statuses: (reduce $rows[] as $row ({}; .[$row.id] = $row.out.s))} end'

statuses='{}'
while IFS= read -r group; do
  [[ -n "$group" ]] || continue
  repo="$(jq -r '.[0].repo' <<<"$group")"
  count="$(jq 'length' <<<"$group")"
  [[ -z "$COUNTED_TRUST" ]] || trust_context "$repo"
  for ((i = 0; i < count; i += 100)); do
    chunk="$(jq -c --argjson i "$i" '.[$i:$i + 100]' <<<"$group")"
    # Aliases are built from validated issue numbers only.
    if [[ -z "$COUNTED_TRUST" ]]; then
      aliases="$(jq -r 'map("i\(.number): issue(number: \(.number)) { issueFieldValues(first: 25) { nodes { ... on IssueFieldSingleSelectValue { name field { ... on IssueFieldSingleSelect { name } } } } } }") | join(" ")' <<<"$chunk")"
      fragments=""
    else
      aliases="$(jq -r --arg sel "$TRUST_SELECTION" 'map("i\(.number): issue(number: \(.number)) { \($sel) }") | join(" ")' <<<"$chunk")"
      fragments=" $TRUST_FRAGMENTS"
    fi
    # shellcheck disable=SC2016  # GraphQL variables, not bash expansions
    query="query(\$owner: String!, \$name: String!) { repository(owner: \$owner, name: \$name) { $aliases } }$fragments"
    if [[ -z "$COUNTED_TRUST" ]]; then
      query_arg=(-f query="$query")
    else
      # 100 trusted aliases run past the 32,767-character Windows command line, so the
      # query goes to gh as a file.
      printf '%s' "$query" >"$TRUST_TMP/query.graphql"
      query_arg=(-F query="@$TRUST_TMP/query.graphql")
    fi
    wit_run_gh read api graphql -f owner="${repo%%/*}" -f name="${repo#*/}" "${query_arg[@]}"
    if [[ -z "$COUNTED_TRUST" ]]; then
      page="$(jq -c --argjson chunk "$chunk" --arg f "$field" '
        .data.repository as $r
        | {statuses: (reduce $chunk[] as $c ({}; .[$c.id] =
            ([($r["i\($c.number)"].issueFieldValues.nodes // [])[] | select(.field.name? == $f) | .name] | first)))}' \
        <<<"$WIT_GH_OUT")"
    else
      page="$(jq -c --argjson chunk "$chunk" --argjson ctx "$CONTEXT" --argjson page "$FIELD_VALUE_PAGE" \
        --argjson window "$FIELD_EVENT_WINDOW" "$TRUST_WALK_JQ" <<<"$WIT_GH_OUT")"
    fi || {
      echo "get-statuses: the field value answer for $repo is not JSON" >&2
      exit "$EX_INTERNAL"
    }
    if jq -e 'has("error")' <<<"$page" >/dev/null; then
      trust_fail "$EX_INTERNAL" "$(jq -r '.error' <<<"$page") ($repo)"
    fi
    statuses="$(jq -c --argjson acc "$statuses" '$acc + .statuses' <<<"$page")"
  done
done < <(jq -c '.[]' <<<"$rows")

jq -nc --arg sv "$WIT_SCHEMA_VERSION" --argjson statuses "$statuses" '{schema_version: $sv, statuses: $statuses}'
