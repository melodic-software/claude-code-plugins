#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=/dev/null
[[ -z "${RUNNER_TEMP:-}" ]] || ! . "${BASH_SOURCE[0]%/*}/../.github/actions/log-api-budget/api-budget.bash" 2>/dev/null || api_budget_wrap_gh github-token
export LC_ALL=C

SELF="upstream-drift-issues"
CAP=60000

usage() {
  printf 'usage: %s [--dry-run] <report-file> | --help\n' "${0##*/}"
}

usage_error() {
  usage >&2
  exit 2
}

die() {
  printf '%s: %s\n' "$SELF" "$*" >&2
  exit 2
}

DRY=0
REPORT=""
while (($# > 0)); do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --dry-run) DRY=1 ;;
  -*) usage_error ;;
  *)
    [[ -z "$REPORT" ]] || usage_error
    REPORT="$1"
    ;;
  esac
  shift
done
[[ -n "$REPORT" ]] || usage_error
[[ -f "$REPORT" && -r "$REPORT" ]] || die "cannot read report file: $REPORT"
command -v jq >/dev/null 2>&1 || die "jq is required"

span() {
  local s="$1"
  # shellcheck disable=SC2016  # the backticks are the literal span delimiters
  printf '`%s`' "${s//\`/\'}"
}

skill_name() {
  if [[ "$1" =~ ^plugins/([^/]+)/skills/([^/]+)/ ]]; then
    printf '%s:%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  else
    printf '%s' "$2"
  fi
}

REPOS=()
STATE=()
DETAIL=()
PINNED=()
UNTRACKED=()
repo_index=-1
page_status=""
counting=0
changed=0 new=0 removed=0

flush_counts() {
  ((counting)) && DETAIL[repo_index]+="Changed rows: $changed, new units: $new, removed units: $removed."$'\n'
  counting=0 changed=0 new=0 removed=0
}

find_repo() {
  local i
  for i in "${!REPOS[@]}"; do
    if [[ "${REPOS[i]}" == "$1" ]]; then
      repo_index=$i
      return 0
    fi
  done
  REPOS+=("$1")
  STATE+=(none)
  DETAIL+=("")
  PINNED+=(0)
  UNTRACKED+=(0)
  repo_index=$((${#REPOS[@]} - 1))
}

re_page='^page repo=([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+) pin=([0-9a-f]+|unknown) head=([0-9a-f]+|unknown) status=(untracked|unreachable|clean|drift) path=(.+)$'
re_row='^row line=([0-9]+) status=([A-Za-z]+) path=(.+)$'
re_unit='^(new|removed)-unit path=(.+)$'

lineno=0
while IFS= read -r line || [[ -n "$line" ]]; do
  lineno=$((lineno + 1))
  if [[ "$line" =~ $re_page ]]; then
    repo="${BASH_REMATCH[1]}" pin="${BASH_REMATCH[2]}" head="${BASH_REMATCH[3]}"
    page_status="${BASH_REMATCH[4]}" page="${BASH_REMATCH[5]}"
    flush_counts
    find_repo "$repo"
    case "$page_status" in
    drift)
      STATE[repo_index]=drift
      if [[ "$pin" == unknown ]]; then
        DETAIL[repo_index]+=$'\n'"### $(span "$(skill_name "$page" "$repo")")"$'\n\n'"Run $(span "$page"); restore or re-vendor what it names; its output is in the run's job summary."$'\n\n'
      else
        PINNED[repo_index]=1
        counting=1
        DETAIL[repo_index]+=$'\n'"### $(span "$page")"$'\n\n'"Pin $(span "$pin"), upstream head $(span "$head")."$'\n\n'
      fi
      ;;
    clean) [[ "${STATE[repo_index]}" == drift ]] || STATE[repo_index]=clean ;;
    *) UNTRACKED[repo_index]=1 ;;
    esac
  elif ((repo_index >= 0)) && [[ "$line" =~ $re_row ]]; then
    [[ "${BASH_REMATCH[2]}" != unchanged ]] && changed=$((changed + 1))
  elif ((repo_index >= 0)) && [[ "$line" =~ $re_unit ]]; then
    if [[ "${BASH_REMATCH[1]}" == new ]]; then new=$((new + 1)); else removed=$((removed + 1)); fi
  else
    die "$REPORT:$lineno: line does not follow the report field order"
  fi
done <"$REPORT"
flush_counts

RUN_DATE="$(date -u +%Y-%m-%d)"
RUN_URL="(local run, no run URL)"
if [[ -n "${GITHUB_SERVER_URL:-}" && -n "${GITHUB_REPOSITORY:-}" && -n "${GITHUB_RUN_ID:-}" ]]; then
  RUN_URL="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
fi

TMPDIR_RUN="$(mktemp -d)" || die "mktemp failed"
trap 'rm -rf "$TMPDIR_RUN"' EXIT

failed=0

fail() {
  printf '%s: %s\n' "$SELF" "$*" >&2
  failed=1
}

# The REST list, not search, which is rate-limited and can return incomplete results:
# https://docs.github.com/en/rest/search/search
BOT='github-actions[bot]'
if ! listed="$(gh api --paginate "repos/{owner}/{repo}/issues?creator=$BOT&state=all&per_page=100")"; then
  printf '%s: issue list failed\n' "$SELF" >&2
  exit 1
fi
ISSUES="$(jq -s --arg bot "$BOT" 'add // [] | map(select(.pull_request == null and .user.login == $bot)
  | select(((.body // "") | split("\n")) as $l
    | ($l[0] // "" | startswith("<!-- factory-monitor key=")) or ($l | map(select(test("[^[:space:]]"))) | last // "" | test("^<!-- lane-sweep:fp=[0-9a-f]{16} -->[[:space:]]*$"))
    | not))' <<<"$listed")" || {
  printf '%s: unreadable issue list\n' "$SELF" >&2
  exit 1
}

bot_issue() {
  jq -r --arg t "$1" '[.[] | select(.title == $t)] | (map(select(.state == "open")) + sort_by(-.number))
    | first // empty | "\(.number) \(.state) \(.state_reason // "none")"' <<<"$ISSUES"
}

write_body() {
  local body note lead footer
  if ((PINNED[$1])); then
    lead="changed since the pin on its docs/upstream page."
    footer="Run scripts/check-upstream-drift.sh --page <page> on each page above to list its changed rows and units, then re-audit them as docs/contracts/upstream-drift/README.md, \"When a trigger fires\", requires. Moving the pin makes the next run clean, which closes this issue."
  else
    lead="no longer matches the copy vendored here."
    footer="A clean run closes this issue."
  fi
  body="Upstream $(span "${REPOS[$1]}") $lead"$'\n\n'"Run: $RUN_DATE, $RUN_URL"$'\n'"${DETAIL[$1]}"$'\n'"$footer"$'\n'
  if ((${#body} > CAP)); then
    note=$'\n'"Cut at $CAP characters. The full report is in the run's job summary: $RUN_URL"$'\n'
    body="${body:0:$((CAP - ${#note}))}"
    body="${body%$'\n'*}"
    body+="$note"
  fi
  printf '%s' "$body" >"$2"
}

for i in "${!REPOS[@]}"; do
  repo="${REPOS[i]}"
  title="Upstream drift: $repo"
  action=none
  if [[ "${STATE[i]}" != none ]]; then
    if ! found="$(bot_issue "$title")" || ! read -r num issue_state reason <<<"$found" ||
      [[ -n "$num" && ! "$num" =~ ^[0-9]+$ ]]; then
      fail "unreadable issue list for $repo"
      continue
    fi
    if [[ "${STATE[i]}" == drift ]]; then
      if [[ -z "$num" ]]; then
        action=create
      elif [[ "$issue_state" == open ]]; then
        action=edit
      elif [[ "$reason" != not_planned && "$reason" != duplicate ]]; then
        action=reopen
      fi
    elif [[ "$issue_state" == open ]] && ((!UNTRACKED[i])); then
      action=close
    fi
  fi
  printf 'action=%s repo=%s\n' "$action" "$repo"
  ((DRY)) && continue
  body_file="$TMPDIR_RUN/body-$i.md"
  case "$action" in
  create)
    write_body "$i" "$body_file"
    if url="$(gh issue create --title "$title" --body-file "$body_file")"; then
      [[ "$url" =~ /issues/([0-9]+)$ ]] && ! gh api -X PATCH "repos/{owner}/{repo}/issues/${BASH_REMATCH[1]}" -f type=Task >/dev/null &&
        printf '%s: could not set the Issue Type on %s\n' "$SELF" "$url" >&2
    else
      fail "issue create failed for $repo"
    fi
    ;;
  edit)
    write_body "$i" "$body_file"
    gh issue edit "$num" --body-file "$body_file" >/dev/null || fail "issue edit failed for $repo"
    ;;
  reopen)
    write_body "$i" "$body_file"
    if ! gh issue reopen "$num" >/dev/null; then
      fail "issue reopen failed for $repo"
    elif ! gh issue edit "$num" --body-file "$body_file" --remove-label needs-human >/dev/null; then
      fail "issue edit failed for $repo"
    fi
    ;;
  close)
    gh issue close "$num" --comment "Upstream $(span "$repo") is clean as of $RUN_DATE ($RUN_URL)." >/dev/null ||
      fail "issue close failed for $repo"
    ;;
  *) ;;
  esac
done

rows="$(jq -r '.[] | select(.state == "open" and (.title | startswith("Upstream drift: ")))
  | [.number, (.title | ltrimstr("Upstream drift: "))] | @tsv' <<<"$ISSUES")" || {
  printf '%s: unreadable issue list for the sweep\n' "$SELF" >&2
  exit 1
}
reported="$(printf '%s\n' "${REPOS[@]}")"
while IFS=$'\t' read -r num repo; do
  [[ "$num" =~ ^[0-9]+$ && "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || continue
  grep -qxF -- "$repo" <<<"$reported" && continue
  printf 'action=close-unreported repo=%s\n' "$repo"
  ((DRY)) && continue
  gh issue close "$num" --comment "Upstream $(span "$repo") is no longer in the drift report as of $RUN_DATE ($RUN_URL): its docs/upstream page was removed or renamed." >/dev/null ||
    fail "issue close failed for $repo"
done <<<"$rows"

exit "$failed"
