#!/usr/bin/env bash
# label-provenance <id> --label <name> [--label <name> ...] — CONTRACT.md "Verbs (core public
# surface)". Read-only. For each named label, finds the most recent `labeled` timeline event,
# reads that actor's repository permission, and trusts the label only when the permission is
# `admin` or `write` (maintain maps to write, triage to read). `admitted` is true only when
# every named label is trusted. A failed timeline read exits non-zero; a missing event or a
# failed permission read is an untrusted entry with its reason.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage="usage: label-provenance <id> --label <name> [--label <name> ...]"
wit_help_if_requested "$usage" "$@"

id="${1:-}"
[[ -n "$id" && "$id" != --* ]] || wit_usage_error "$usage"
shift
labels=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  --label)
    [[ $# -ge 2 && -n "$2" ]] || wit_usage_error "--label needs a non-empty value"
    labels+=("$2")
    shift 2
    ;;
  *) wit_usage_error "unknown argument: $1" ;;
  esac
done
[[ ${#labels[@]} -gt 0 ]] || wit_usage_error "at least one --label is required"
wit_require_github_id "$id" || wit_usage_error "malformed or non-github id: $id (expected github:<owner>/<repo>#<number>)"
owner="$WIT_ID_OWNER"
repo="$WIT_ID_REPO"
number="$WIT_ID_NUMBER"

wit_run_gh read api --paginate "repos/$owner/$repo/issues/$number/timeline?per_page=100" \
  --jq '[.[] | select(.event == "labeled") | {label: (.label.name // null), actor: (.actor.login // null), at: (.created_at // "")}]'
events="$(jq -cs 'add // []' <<<"$WIT_GH_OUT")" || {
  echo "label-provenance: timeline response for $id is not JSON" >&2
  exit "$EX_INTERNAL"
}

# A GitHub login, optionally an app's `[bot]` form. Anything else never reaches the API path.
login_re='^[A-Za-z0-9][A-Za-z0-9-]*(\[bot\])?$'

# entry <label> <actor> <permission> <role> <trusted> <reason>: one result row; empty strings
# become null so a reader can tell "not read" from a value.
entry() {
  jq -nc --arg label "$1" --arg actor "$2" --arg permission "$3" --arg role "$4" \
    --argjson trusted "$5" --arg reason "$6" \
    '{label: $label,
      actor: (if $actor == "" then null else $actor end),
      permission: (if $permission == "" then null else $permission end),
      role: (if $role == "" then null else $role end),
      trusted: $trusted,
      reason: (if $reason == "" then null else $reason end)}'
}

rows=""
for label in "${labels[@]}"; do
  last="$(jq -c --arg l "$label" '[.[] | select(.label == $l)] | sort_by(.at) | last // empty' <<<"$events")"
  if [[ -z "$last" ]]; then
    rows+="$(entry "$label" "" "" "" false "no labeled event for this label")"$'\n'
    continue
  fi
  actor="$(jq -r '.actor // ""' <<<"$last")"
  if [[ ! "$actor" =~ $login_re ]]; then
    rows+="$(entry "$label" "" "" "" false "labeled event has no usable actor login")"$'\n'
    continue
  fi
  errfile="$(mktemp)"
  perm_json="$(gh api "repos/$owner/$repo/collaborators/$actor/permission" 2>"$errfile")"
  perm_rc=$?
  perm_err="$(head -n 1 "$errfile")"
  rm -f "$errfile"
  if ((perm_rc != 0)); then
    rows+="$(entry "$label" "$actor" "" "" false "permission read failed: ${perm_err:-gh exited $perm_rc}")"$'\n'
    continue
  fi
  permission="$(jq -r '.permission // ""' <<<"$perm_json" 2>/dev/null)"
  role="$(jq -r '.role_name // ""' <<<"$perm_json" 2>/dev/null)"
  case "$permission" in
  admin | write)
    rows+="$(entry "$label" "$actor" "$permission" "$role" true "")"$'\n'
    ;;
  "")
    rows+="$(entry "$label" "$actor" "" "$role" false "permission read returned no permission")"$'\n'
    ;;
  *)
    rows+="$(entry "$label" "$actor" "$permission" "$role" false "labeler permission is below write")"$'\n'
    ;;
  esac
done

printf '%s' "$rows" | jq -cs --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" \
  '{schema_version: $sv, id: $id, admitted: all(.[]; .trusted), labels: .}'
