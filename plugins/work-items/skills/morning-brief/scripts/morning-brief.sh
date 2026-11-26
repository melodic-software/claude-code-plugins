#!/usr/bin/env bash
# Exit codes:
#   0  brief rendered, every section read
#   3  invalid argument
#   4  prerequisite missing (gh or jq), or repo could not be resolved
#   5  every section was unreadable; the brief carries no data
#   6  brief rendered, but at least one section was unreadable

# shellcheck disable=SC2329  # the per-section fetch functions are dispatched by name through gql_or_rest, which ShellCheck cannot follow
set -uo pipefail

DEFAULT_QUEUE_LABELS=(
  "needs-triage"
  "status: ready"
  "needs-owner-decision"
  "needs-human"
)
DEFAULT_DECISION_LABEL="needs-owner-decision"
QUEUE_LABELS=()
DECISION_LABEL=""
QUEUE_LABELS_ARG=""
DECISION_LABEL_ARG=""

REPO=""
REPO_SOURCE=""
TELEMETRY_ISSUE=""
REPO_LABELS_JSON=""
STALE_HOURS="6"
REC_MAXLEN="240"
PR_LIMIT="50"
NOW_ISO=""
COUNTS_JSON=""
PR_JSON=""
BEHIND_JSON=""
DECISIONS_JSON=""
TELEMETRY_JSON=""
MERGED_JSON=""
STRANDED_DAYS="3"
LANDED_SAMPLE=""
STRANDED_READ_CUTOFF=""
STUCK_DAYS="7"
STUCK_LIMIT="20"
STUCK_JSON=""
TOUCH_DAYS="2"
TOUCH_JSON=""
STATUS_JSON=""
OWNER_LOGIN_ARG=""
LANE_IDENTITY_ARG=""
HOLD_LABEL="needs-human"
DATA_DIR_ARG=""
LANE_RUNS_JSON=""
LANE_ANNOTATIONS_JSON=""
LANE_WORKFLOWS_ARG=""
LANE_WORKFLOWS_CONFIG=""
LANE_OUTCOME_CONTRACT_REF=""
CLAUDE_ACTION_RE='uses:[[:space:]]*["'\'']?anthropics/claude-code(-base)?-action@'
LANE_DAYS=7
LANE_READ_LIMIT=200
MAX_TURNS_HITS=""
ORG_ARG=""
ORG_FLAG=0
SUBSCRIPTION_FLAG=0
ORG_SCAN_JSON=""
ACTIONS_INCLUDED_MINUTES=""
ACTIONS_INCLUDED_STORAGE_GB=""
USAGE_ALERT_PERCENT=""
LOG_CAP_ALERT_PERCENT=""
FORECAST_ALERT=""
REQUIRED_BUDGETS_ARG=""
ANOMALY_ALERT=""
EXPIRY_DAYS=""
ALLOWED_COLLABORATORS_ARG=""
WORKFLOW_READ_LIMIT=""
CONFIG_HOME_ARG=""
SUBSCRIPTION_ARG=""
BILLING_USAGE_JSON=""
BILLING_BUDGETS_JSON=""
AZURE_JSON=""

LABEL_LIMIT=500
COUNT_LIMIT=1000
PR_LIST_LIMIT=200
DECISION_LIMIT=200
TELEMETRY_SEARCH_LIMIT=100

TELEMETRY_SEARCH='loop-lane telemetry running per-lane status in:title'
read -ra TELEMETRY_TITLE_TOKENS <<<"${TELEMETRY_SEARCH% in:title}"

usage() {
  cat <<'TXT'
Read-only operator morning view for a GitHub repo.

Usage: morning-brief.sh [options]
  --repo owner/name                 target a specific repo (default: the current one)
  --telemetry-issue N               pin the lane-telemetry issue
  --queue-labels A,B,C              pin the queue-label set
  --decision-label L                pin the parked-decision label
  --stale-hours N                   age past which a lane is STALE (default 6)
  --stranded-days N                 floor of the stranded-findings window, in days (default 3)
  --stuck-days N                    age in a queue label past which an item is stuck (default 7)
  --stuck-limit N                   cap on the stuck items listed (default 20)
  --landed-sample N                 PRs listed under "Read these" (default 3)
  --data-dir DIR                    base dir for the stranded bookmark
  --rec-maxlen N                    truncate RECOMMENDED previews (default 240; 0 = full)
  --pr-limit N                      cap on per-PR reads (default 50)
  --lane-workflows A,B              pin the lane workflow files
  --lane-read-limit N               cap on lane runs whose annotations are read (default 200)
  --max-turns-hits N                max-turns hits above which the model-usage table prints RECOMMENDED
  --touch-days N                    UTC days the owner-touch section covers (default 2)
  --owner-login L                   the operator login the owner-touch section counts
  --lane-identity L                 the lane login whose escalations count
  --hold-label L                    the hold label whose waits are measured (default needs-human)
  --org ORG                         GitHub org whose billing the cost section reads
  --subscription ID                 Azure subscription the cost section reads
  --actions-included-minutes N      Actions minutes the plan includes
  --actions-included-storage-gb N   artifact storage the plan includes, in GB
  --usage-alert-percent N           share of an included amount that is an ALERT (default 50)
  --log-cap-alert-percent N         share of a workspace's daily cap that is an ALERT (default 50)
  --forecast-alert N                budget forecast above which a budget is an ALERT
  --required-budgets A,B            Azure budgets that must exist
  --anomaly-alert NAME              the cost anomaly alert that must exist
  --expiry-days N                   days before a budget or alert ends that are an ALERT (default 30)
  --allowed-collaborators A,B       direct collaborators besides org admins
  --workflow-read-limit N           cap on workflow files read for secret triggers (default 300)
  --config-home DIR                 convention home holding work-items.yaml
  --help                            print this help
Fixture flags (skip the network): --now, --counts-json, --repo-labels-json, --pr-json, --behind-json,
  --decisions-json, --telemetry-json, --merged-json, --stuck-json, --touch-json, --status-json,
  --lane-runs-json, --lane-annotations-json, --billing-usage-json, --billing-budgets-json, --azure-json, --org-scan-json

Exit 0 every section read; 3 invalid argument; 4 gh or jq missing, or no repo; 5 every section unreadable;
6 rendered with at least one section unreadable.
TXT
  exit 0
}

require_value() {
  [[ -n "${2:-}" && "$2" != -* ]] || {
    printf 'morning-brief: %s requires an argument\n' "$1" >&2
    exit 3
  }
}

require_file() {
  [[ -f "$2" ]] || {
    printf 'morning-brief: %s file not found: %s\n' "$1" "$2" >&2
    exit 3
  }
}

require_amount() {
  [[ "$2" =~ ^[0-9]+(\.[0-9]+)?$ ]] || {
    printf 'morning-brief: %s requires a non-negative number\n' "$1" >&2
    exit 3
  }
}

require_uint() {
  [[ "$2" =~ ^[0-9]+$ ]] || {
    printf 'morning-brief: %s requires a non-negative integer\n' "$1" >&2
    exit 3
  }
}

is_percent() { [[ "$1" =~ ^[0-9]+$ ]] && ((10#$1 <= 100)); }
require_percent() {
  is_percent "$2" || {
    printf 'morning-brief: %s requires an integer from 0 to 100\n' "$1" >&2
    exit 3
  }
}

is_owner() { [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$ ]]; }

take() {
  local kind="$1" var="$2" flag="$3" value="${4:-}"
  require_value "$flag" "$value"
  case "$kind" in
  file) require_file "$flag" "$value" ;;
  uint)
    require_uint "$flag" "$value"
    value="$((10#$value))"
    ;;
  percent)
    require_percent "$flag" "$value"
    value="$((10#$value))"
    ;;
  amount) require_amount "$flag" "$value" ;;
  *) ;;
  esac
  printf -v "$var" '%s' "$value"
}

while (($# > 0)); do
  case "$1" in
  -h | --help) usage ;;
  --repo)
    take text REPO "$@"
    REPO_SOURCE="--repo"
    ;;
  --telemetry-issue) take text TELEMETRY_ISSUE "$@" ;;
  --queue-labels) take text QUEUE_LABELS_ARG "$@" ;;
  --decision-label) take text DECISION_LABEL_ARG "$@" ;;
  --stale-hours) take uint STALE_HOURS "$@" ;;
  --rec-maxlen) take uint REC_MAXLEN "$@" ;;
  --stranded-days) take uint STRANDED_DAYS "$@" ;;
  --stuck-days) take uint STUCK_DAYS "$@" ;;
  --landed-sample) take uint LANDED_SAMPLE "$@" ;;
  --stuck-limit) take uint STUCK_LIMIT "$@" ;;
  --data-dir)
    require_value "$1" "${2:-}"
    abs_re='^(/|[A-Za-z]:[/\\])' dotdot_re='(^|[/\\])\.\.([/\\]|$)'
    [[ "$2" =~ $abs_re && ! "$2" =~ $dotdot_re && "$2" != *[[:cntrl:]]* ]] || {
      printf 'morning-brief: --data-dir must be an absolute path with no .. segment or control character\n' >&2
      exit 3
    }
    DATA_DIR_ARG="$2"
    ;;
  --pr-limit) take uint PR_LIMIT "$@" ;;
  --lane-workflows) take text LANE_WORKFLOWS_ARG "$@" ;;
  --lane-read-limit) take uint LANE_READ_LIMIT "$@" ;;
  --max-turns-hits) take uint MAX_TURNS_HITS "$@" ;;
  --org)
    require_value "$1" "${2:-}"
    is_owner "$2" || {
      printf 'morning-brief: --org requires a GitHub owner name (letters, digits, inner hyphens)\n' >&2
      exit 3
    }
    ORG_ARG="$2"
    ORG_FLAG=1
    ;;
  --subscription)
    take text SUBSCRIPTION_ARG "$@"
    SUBSCRIPTION_FLAG=1
    ;;
  --config-home) take text CONFIG_HOME_ARG "$@" ;;
  --actions-included-minutes) take amount ACTIONS_INCLUDED_MINUTES "$@" ;;
  --actions-included-storage-gb) take amount ACTIONS_INCLUDED_STORAGE_GB "$@" ;;
  --usage-alert-percent) take percent USAGE_ALERT_PERCENT "$@" ;;
  --log-cap-alert-percent) take percent LOG_CAP_ALERT_PERCENT "$@" ;;
  --forecast-alert) take amount FORECAST_ALERT "$@" ;;
  --required-budgets) take text REQUIRED_BUDGETS_ARG "$@" ;;
  --anomaly-alert) take text ANOMALY_ALERT "$@" ;;
  --expiry-days) take uint EXPIRY_DAYS "$@" ;;
  --allowed-collaborators) take text ALLOWED_COLLABORATORS_ARG "$@" ;;
  --workflow-read-limit) take uint WORKFLOW_READ_LIMIT "$@" ;;
  --now) take text NOW_ISO "$@" ;;
  --touch-days)
    take uint TOUCH_DAYS "$@"
    ((TOUCH_DAYS >= 1)) || {
      printf 'morning-brief: --touch-days must be 1 or more\n' >&2
      exit 3
    }
    ;;
  --owner-login) take text OWNER_LOGIN_ARG "$@" ;;
  --lane-identity) take text LANE_IDENTITY_ARG "$@" ;;
  --hold-label) take text HOLD_LABEL "$@" ;;
  --repo-labels-json) take file REPO_LABELS_JSON "$@" ;;
  --counts-json) take file COUNTS_JSON "$@" ;;
  --pr-json) take file PR_JSON "$@" ;;
  --behind-json) take file BEHIND_JSON "$@" ;;
  --decisions-json) take file DECISIONS_JSON "$@" ;;
  --telemetry-json) take file TELEMETRY_JSON "$@" ;;
  --merged-json) take file MERGED_JSON "$@" ;;
  --stuck-json) take file STUCK_JSON "$@" ;;
  --touch-json) take file TOUCH_JSON "$@" ;;
  --status-json) take file STATUS_JSON "$@" ;;
  --lane-runs-json) take file LANE_RUNS_JSON "$@" ;;
  --lane-annotations-json) take file LANE_ANNOTATIONS_JSON "$@" ;;
  --billing-usage-json) take file BILLING_USAGE_JSON "$@" ;;
  --billing-budgets-json) take file BILLING_BUDGETS_JSON "$@" ;;
  --org-scan-json) take file ORG_SCAN_JSON "$@" ;;
  --azure-json) take file AZURE_JSON "$@" ;;
  -*)
    printf 'morning-brief: unknown flag %q (use --help)\n' "$1" >&2
    exit 3
    ;;
  *)
    printf 'morning-brief: unexpected argument %q\n' "$1" >&2
    exit 3
    ;;
  esac
  shift 2
done

have() { command -v "$1" >/dev/null 2>&1; }
have jq || {
  printf 'morning-brief: jq required\n' >&2
  exit 4
}

CONFIG_SOURCES=()
SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[[ "$SCRIPT_DIR" == "${BASH_SOURCE[0]}" ]] && SCRIPT_DIR=.
config_home() {
  local root
  if [[ -n "$CONFIG_HOME_ARG" ]]; then
    printf '%s' "$CONFIG_HOME_ARG"
    return
  fi
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  [[ -n "$root" && "$root" != "$HOME" ]] || return 1
  printf '%s/docs/conventions' "$root"
}
config_layer() {
  local file="$1" out msg
  [[ -f "$file" ]] || return 0
  if [[ -L "$file" ]]; then
    printf 'morning-brief: %s is a symlink; that layer is skipped\n' "$file" >&2
    return 0
  fi
  if ! out="$(awk -f "$SCRIPT_DIR/lib/yaml-subset.awk" "$file" 2>/dev/null)"; then
    msg="$(cut -f2- <<<"$out" | tr '\t' ' ')"
    [[ "$msg" == *[[:cntrl:]]* ]] && printf -v msg '%q' "$msg"
    printf 'morning-brief: %s could not be parsed (%s); that layer is skipped\n' "$file" "$msg" >&2
    return 0
  fi
  CONFIG_SOURCES+=("${file##*/}")
  awk -F'\t' '$1 ~ /^morning_brief\./ { sub(/^morning_brief\./, "", $1); print $1 "\t" $2 }' <<<"$out"
}
binding_decision_label() {
  local out
  [[ -f "$1" && ! -L "$1" ]] || return 0
  out="$(awk -f "$SCRIPT_DIR/lib/yaml-subset.awk" "$1" 2>/dev/null)" || return 0
  awk -F'\t' '$1 == "tracker.config.role_labels.owner-decision" && $2 !~ /[[:cntrl:]]/ { print $2; exit }' <<<"$out"
}
CONFIG_TEAM=""
CONFIG_LOCAL=""
CONFIG_DECISION_LABEL=""
if CONFIG_HOME="$(config_home)"; then
  CONFIG_TEAM="$(config_layer "$CONFIG_HOME/work-items.yaml")"
  CONFIG_LOCAL="$(config_layer "$CONFIG_HOME/work-items.local.yaml")"
  CONFIG_DECISION_LABEL="$(binding_decision_label "$CONFIG_HOME/work-items.yaml")"
fi
DECISION_LABEL="${DECISION_LABEL_ARG:-${CONFIG_DECISION_LABEL:-$DEFAULT_DECISION_LABEL}}"
COST_SETTING_LAYERS=()
config_value() {
  local var="$1" key="$2" kind="$3" default="$4" layer value file
  if [[ -n "${!var}" ]]; then
    COST_SETTING_LAYERS+=("$key=${!var} (flag)")
    return
  fi
  for layer in local team; do
    if [[ "$layer" == local ]]; then value="$CONFIG_LOCAL" file="work-items.local.yaml"; else value="$CONFIG_TEAM" file="work-items.yaml"; fi
    if [[ "$kind" == list ]]; then
      value="$(awk -F'\t' -v k="$key" '
        index($1, k ".") == 1 && substr($1, length(k) + 2) ~ /^[0-9]+$/ { printf "%s%s", (n++ ? "," : ""), $2 }
        $1 == k || (index($1, k ".") == 1 && substr($1, length(k) + 2) !~ /^[0-9]+$/) { bad = 1 }
        END { if (bad) printf "\001" }' <<<"$value")"
    else
      value="$(awk -F'\t' -v k="$key" '$1 == k { print $2; found = 1 } index($1, k ".") == 1 { print "\001"; found = 1 } END { if (!found) exit 1 }' <<<"$value")" || continue
    fi
    [[ -n "$value" ]] || continue
    case "$kind" in
    uint) [[ "$value" =~ ^[0-9]+$ ]] ;;
    percent) is_percent "$value" ;;
    owner) is_owner "$value" ;;
    amount) [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]] ;;
    *) [[ "$value" != *[[:cntrl:]]* ]] ;;
    esac || {
      printf 'morning-brief: %s: morning_brief.%s has an invalid value (%q); the default is used\n' "$file" "$key" "${value//$'\001'/}" >&2
      COST_SETTING_LAYERS+=("$key=default (invalid in $file)")
      printf -v "$var" '%s' "$default"
      return
    }
    [[ "$kind" == uint || "$kind" == percent ]] && value="$((10#$value))"
    COST_SETTING_LAYERS+=("$key=$value ($file)")
    printf -v "$var" '%s' "$value"
    return
  done
  printf -v "$var" '%s' "$default"
}
config_value ORG_ARG org owner ""
config_value SUBSCRIPTION_ARG subscription text ""
config_value ACTIONS_INCLUDED_MINUTES actions_included_minutes amount ""
config_value ACTIONS_INCLUDED_STORAGE_GB actions_included_storage_gb amount ""
config_value USAGE_ALERT_PERCENT usage_alert_percent percent 50
config_value LOG_CAP_ALERT_PERCENT log_cap_alert_percent percent 50
config_value FORECAST_ALERT forecast_alert amount ""
config_value REQUIRED_BUDGETS_ARG required_budgets list ""
config_value ANOMALY_ALERT anomaly_alert text ""
config_value EXPIRY_DAYS expiry_days uint 30
config_value ALLOWED_COLLABORATORS_ARG allowed_collaborators list ""
config_value WORKFLOW_READ_LIMIT workflow_read_limit uint 300
n_cost_settings=${#COST_SETTING_LAYERS[@]}
config_value LANDED_SAMPLE landed_sample uint 3
LANDED_SETTING="${COST_SETTING_LAYERS[*]:n_cost_settings}"
config_value LANE_WORKFLOWS_CONFIG lane_workflows list ""
config_value LANE_OUTCOME_CONTRACT_REF lane_outcome_contract_ref list ""
COST_SETTING_LAYERS=("${COST_SETTING_LAYERS[@]:0:n_cost_settings}")

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ERR_FILE="$WORK/stderr"

LAST_ERR=""
TRANSPORT="gh"

first_error_line() {
  local out="$1" err="$2" line=""
  line="$(grep -m1 -v '^[[:space:]]*$' "$err" 2>/dev/null)"
  [[ -n "$line" ]] || line="$(jq -r -s 'first(.[] | objects | (.errors[]?.message // .message // empty)) // empty' "$out" 2>/dev/null)"
  line="${line#gh: }"
  printf '%s' "$line"
}

body_error() {
  jq -r -s '
    [ .. | objects
      | select(has("errors") or (has("message") and has("documentation_url")))
      | (.errors[]?.message // .message) ]
    | first // empty
  ' "$1" 2>/dev/null
}

gh_read() {
  local out="$1"
  shift
  LAST_ERR=""
  : >"$ERR_FILE"
  gh "$@" >"$out" 2>"$ERR_FILE"
  local rc=$?
  if ((rc != 0)); then
    LAST_ERR="$(first_error_line "$out" "$ERR_FILE")"
    [[ -n "$LAST_ERR" ]] || LAST_ERR="gh exited $rc"
    return 1
  fi
  local body_err
  body_err="$(body_error "$out")"
  if [[ -n "$body_err" ]]; then
    LAST_ERR="$body_err"
    return 1
  fi
  return 0
}

graphql_blocked() {
  grep -qi 'GraphQL is not available from Claude Code sessions' <<<"$1"
}

gql_or_rest() {
  local out="$1" gql_fn="$2" rest_fn="$3"
  if [[ "$TRANSPORT" == "gh" ]]; then
    "$gql_fn" "$out" && return 0
    graphql_blocked "$LAST_ERR" || return 1
    TRANSPORT="rest"
  fi
  "$rest_fn" "$out"
}

urlencode() { jq -rn --arg s "$1" '$s | @uri'; }

rest_paginate_array() {
  local out="$1"
  shift
  gh_read "$WORK/page" api --paginate "$@" || return 1
  jq -s '[ .[][] ]' "$WORK/page" >"$out" 2>/dev/null || {
    LAST_ERR="could not parse REST response"
    return 1
  }
}

NEEDS_LIVE_COUNTS=0
NEEDS_LIVE_PRS=0
NEEDS_LIVE_DECISIONS=0
NEEDS_LIVE_TELEMETRY=0
NEEDS_LIVE_MERGED=0
NEEDS_LIVE_STUCK=0
NEEDS_LIVE_TOUCH=0
[[ -z "$COUNTS_JSON" ]] && NEEDS_LIVE_COUNTS=1
[[ -z "$PR_JSON" ]] && NEEDS_LIVE_PRS=1
[[ -z "$DECISIONS_JSON" ]] && NEEDS_LIVE_DECISIONS=1
[[ -z "$TELEMETRY_JSON" ]] && NEEDS_LIVE_TELEMETRY=1
[[ -z "$MERGED_JSON" ]] && NEEDS_LIVE_MERGED=1
[[ -z "$STUCK_JSON" ]] && NEEDS_LIVE_STUCK=1
[[ -z "$TOUCH_JSON" ]] && NEEDS_LIVE_TOUCH=1

LABELS_CAPPED=0
fetch_repo_labels_gql() {
  gh_read "$WORK/labels.raw" label list "${REPO_ARGS[@]}" --limit "$LABEL_LIMIT" --json name -q '.[].name' || return 1
  tr -d '\r' <"$WORK/labels.raw" | jq -R -s 'split("\n") | map(select(length > 0))' >"$WORK/labels.all" || {
    LAST_ERR="could not parse the label list"
    return 1
  }
  if (($(jq 'length' "$WORK/labels.all") >= LABEL_LIMIT)); then
    LABELS_CAPPED=1
    LAST_ERR="label inventory reached its $LABEL_LIMIT-label cap"
    return 1
  fi
  jq 'unique' "$WORK/labels.all" >"$1"
}

fetch_repo_labels_rest() {
  rest_paginate_array "$WORK/labels.rest" "repos/$REPO/labels?per_page=100" || return 1
  jq '[ .[].name ] | unique' "$WORK/labels.rest" >"$1"
}

fetch_repo_label_names() {
  local out="$1"
  if [[ -n "$REPO_LABELS_JSON" ]]; then
    jq -e 'type == "array"' "$REPO_LABELS_JSON" >/dev/null 2>&1 || {
      LAST_ERR="--repo-labels-json is not an array"
      return 1
    }
    jq '[ .[] | if type == "string" then . else .name end ] | unique' "$REPO_LABELS_JSON" >"$out" 2>/dev/null || {
      LAST_ERR="--repo-labels-json could not be parsed"
      return 1
    }
    return 0
  fi
  [[ -n "$REPO" ]] || {
    LAST_ERR="no repo resolved"
    return 1
  }
  gql_or_rest "$out" fetch_repo_labels_gql fetch_repo_labels_rest
}

label_exists_in_repo() {
  local label="$1" names_file="$2"
  jq -e --arg l "$label" 'index($l) != null' "$names_file" >/dev/null 2>&1
}

if ((NEEDS_LIVE_DECISIONS)) && [[ -n "$REPO_LABELS_JSON" ]]; then
  if fetch_repo_label_names "$WORK/probe-labels.json"; then
    label_exists_in_repo "$DECISION_LABEL" "$WORK/probe-labels.json" || NEEDS_LIVE_DECISIONS=0
  fi
fi
ANY_LIVE=$((NEEDS_LIVE_COUNTS || NEEDS_LIVE_PRS || NEEDS_LIVE_DECISIONS || NEEDS_LIVE_TELEMETRY || ((NEEDS_LIVE_MERGED || NEEDS_LIVE_STUCK || NEEDS_LIVE_TOUCH) && ${#REPO} > 0)))
if ((ANY_LIVE)) && ! have gh; then
  printf 'morning-brief: gh required for live queries (pass fixtures to run offline)\n' >&2
  exit 4
fi

repo_from_git_remote() {
  local url
  url="$(git remote get-url origin 2>/dev/null | tr -d '\r')" || return 1
  [[ -n "$url" ]] || return 1
  url="${url%.git}"
  url="${url%/}"
  case "$url" in
  *github.com[:/]*)
    url="${url##*github.com[:/]}"
    ;;
  *) return 1 ;;
  esac
  [[ "$url" == */* && "$url" != */*/* ]] || return 1
  printf '%s' "$url"
}

if [[ -z "$REPO" ]] && ((ANY_LIVE)); then
  if gh_read "$WORK/repo" repo view --json nameWithOwner -q .nameWithOwner; then
    REPO="$(tr -d '\r' <"$WORK/repo")"
    REPO_SOURCE="gh repo view"
  fi
  if [[ -z "$REPO" ]]; then
    graphql_blocked "$LAST_ERR" && TRANSPORT="rest"
    if REPO="$(repo_from_git_remote)"; then
      REPO_SOURCE="git remote"
    else
      printf 'morning-brief: could not resolve owner/repo (run inside a checkout with a GitHub origin remote, or pass --repo)\n' >&2
      [[ -n "$LAST_ERR" ]] && printf 'morning-brief: gh repo view: %s\n' "$LAST_ERR" >&2
      exit 4
    fi
  fi
fi
REPO_ARGS=()
if [[ -n "$REPO" ]]; then
  REPO_ARGS=(--repo "$REPO")
else
  NEEDS_LIVE_MERGED=0 NEEDS_LIVE_STUCK=0 NEEDS_LIVE_TOUCH=0
fi

to_epoch() {
  local s="$1" e fmt
  # portability-ok: GNU-first of the dual-dialect ladder
  e="$(date -u -d "$s" +%s 2>/dev/null)" && {
    printf '%s' "$e"
    return
  }
  for fmt in '%Y-%m-%dT%H:%MZ' '%Y-%m-%dT%H:%M:%SZ' '%Y-%m-%dT%H:%M:%S' '%Y-%m-%dT%H:%M'; do
    e="$(TZ=UTC date -j -f "$fmt" "$s" +%s 2>/dev/null)" && {
      printf '%s' "$e"
      return
    }
  done
}

from_epoch() {
  local e="$1" out
  # portability-ok: GNU-first of the dual-dialect ladder
  out="$(date -u -d "@$e" '+%Y-%m-%dT%H:%MZ' 2>/dev/null)" && {
    printf '%s' "$out"
    return
  }
  out="$(date -u -r "$e" '+%Y-%m-%dT%H:%MZ' 2>/dev/null)" && {
    printf '%s' "$out"
    return
  }
  date -u '+%Y-%m-%dT%H:%MZ'
}

utc_stamp() { printf '%s UTC' "$(from_epoch "$1")"; }

if [[ -n "$NOW_ISO" ]]; then
  NOW_EPOCH="$(to_epoch "$NOW_ISO")"
  [[ -n "$NOW_EPOCH" ]] || {
    printf 'morning-brief: could not parse --now value: %s\n' "$NOW_ISO" >&2
    exit 3
  }
else
  NOW_EPOCH="$(date -u +%s)"
fi

fmt_age() {
  local secs="$1"
  if ((secs < 0)); then
    printf 'future'
    return
  fi
  local d=$((secs / 86400)) h=$(((secs % 86400) / 3600)) m=$(((secs % 3600) / 60))
  if ((d > 0)); then
    printf '%dd %dh' "$d" "$h"
  elif ((h > 0)); then
    printf '%dh %dm' "$h" "$m"
  else
    printf '%dm' "$m"
  fi
}

resolve_queue_labels() {
  QUEUE_LABELS=()
  if [[ -n "$QUEUE_LABELS_ARG" ]]; then
    local part _parts
    IFS=',' read -ra _parts <<<"$QUEUE_LABELS_ARG"
    for part in "${_parts[@]}"; do
      part="${part#"${part%%[![:space:]]*}"}"
      part="${part%"${part##*[![:space:]]}"}"
      [[ -n "$part" ]] && QUEUE_LABELS+=("$part")
    done
  else
    local label
    for label in "${DEFAULT_QUEUE_LABELS[@]}"; do
      [[ "$label" == "$DEFAULT_DECISION_LABEL" ]] && label="${CONFIG_DECISION_LABEL:-$label}"
      QUEUE_LABELS+=("$label")
    done
  fi
}

resolve_queue_labels

STUCK_LABELS=("${QUEUE_LABELS[@]}")

SECTIONS_TOTAL=10
UNREADABLE=0
UNREADABLE_NAMES=()

unreadable() {
  UNREADABLE=$((UNREADABLE + 1))
  UNREADABLE_NAMES+=("$1")
  echo "  UNREADABLE: ${2:-data source failed}"
  echo
}

partial_labels() {
  local list
  printf -v list '%s, ' "${@:2}"
  echo "  PARTIAL: ${list%, }: $1"
}

fetch_pipeline() {
  [[ -f "$WORK/pipeline.yaml" ]] && return 0
  gh_read "$WORK/pipeline.raw" api -H 'Accept: application/vnd.github.raw' "repos/$REPO/contents/docs/conventions/pr-pipeline.yaml" || {
    [[ "$LAST_ERR" == *"Not Found"* || "$LAST_ERR" == *"HTTP 404"* ]] || return 1
    : >"$WORK/pipeline.raw"
  }
  mv "$WORK/pipeline.raw" "$WORK/pipeline.yaml"
}

STATUS_MODEL=""
status_model() {
  [[ -n "$STATUS_MODEL" ]] && return 0
  if [[ -n "$STATUS_JSON" ]]; then
    jq -c 'if type == "object" and has("model") then .model else error end' "$STATUS_JSON" >"$WORK/status.model" 2>/dev/null || {
      LAST_ERR="$(body_error "$STATUS_JSON")"
      LAST_ERR="${LAST_ERR:-"--status-json is not an object {model, pages}"}"
      return 1
    }
  else
    fetch_pipeline || {
      LAST_ERR="Work status model (docs/conventions/pr-pipeline.yaml): $LAST_ERR"
      return 1
    }
    awk -f "$SCRIPT_DIR/lib/yaml-subset.awk" "$WORK/pipeline.yaml" >"$WORK/pipeline.flat" 2>/dev/null || {
      LAST_ERR="docs/conventions/pr-pipeline.yaml could not be parsed"
      return 1
    }
    jq -R -n -c '
      reduce (inputs | split("\t") | select(.[0] | startswith("models.issue-status.")))
        as $r ({}; setpath($r[0] | ltrimstr("models.issue-status.") | split("."); $r[1]))
      | if has("field-id") then .labels |= map_values([to_entries[] | .value])
          | if has("hold-states") then .["hold-states"] |= [to_entries[] | .value] else . end
        else null end
    ' "$WORK/pipeline.flat" >"$WORK/status.model"
  fi
  jq -e '. == null or ((.["field-id"] | tostring | test("^[1-9][0-9]*$")) and (.options | type == "object")
    and (.labels | type == "object" and all(.[]; type == "array"))
    and (.["hold-states"] | . == null or (type == "array" and all(.[]; type == "string")))
    and (.["ready-state"] | . == null or type == "string"))' "$WORK/status.model" >/dev/null 2>&1 || {
    LAST_ERR="the Work status model (models.issue-status) is malformed"
    return 1
  }
  STATUS_MODEL="$(cat "$WORK/status.model")"
}

# shellcheck disable=SC2016  # jq program, not shell
STATUS_DEFS='
  def fold: ascii_downcase;
  def holds: $m["hold-states"] // [] | if length == 0 then ["needs-human", "needs-owner-decision", "needs-reporter-info", "needs-spec"] else . end;
  def ready: $m["ready-state"] // "" | if . == "" then "agent-ready" else . end;
  def mapped: if . == null or IN($m.options[]) then . else error("Work status `\(.)` is no option of the model") end;
  def effective($state):
    if $state == null then .
    else ready as $ready | ([$m.labels | to_entries[]
           | select(.key != $ready and (.key | IN(holds[]) | not))
           | .value[] | fold]) as $queue
      | [ .[] | select(fold | IN($queue[]) | not) ] as $kept
      | $m.labels[$state][0] as $label
      | if $state == $ready or $label == null or any($kept[]; fold == ($label | fold)) then $kept else $kept + [$label] end
    end;
  def synthetic:
    reduce (.[]? | select(.issueField.fullDatabaseId == ($m["field-id"] | tostring))) as $e ({held: null, out: []};
      (if $e.__typename == "IssueFieldRemovedEvent" then null elif $e.__typename == "IssueFieldChangedEvent" then $e.newValue else $e.value end | mapped) as $to
      | .out += [{at: $e.createdAt, actor: $e.actor,
                  from: (if $e.__typename == "IssueFieldChangedEvent" then $e.previousValue | mapped else .held end), to: $to}]
      | .held = $to)
    | .out[]
    | select(.actor.__typename != "Bot" or $m["field-events-since"] == null
             or (.at | fromdateiso8601) >= ($m["field-events-since"] | fromdateiso8601))
    | . as $e
    | (["UnlabeledEvent", $e.from], ["LabeledEvent", $e.to])
    | select(.[1] != null and .[1] != ready and $m.labels[.[1]][0] != null)
    | {__typename: .[0], createdAt: $e.at, actor: {login: ($e.actor.login // "")}, label: {name: $m.labels[.[1]][0]}};
'

STATUS_PAGE_LIMIT=20
STATUS_FIELD_EVENTS='nodes { __typename
          ... on IssueFieldAddedEvent { createdAt value actor { __typename login } issueField { ...status } }
          ... on IssueFieldChangedEvent { createdAt previousValue newValue actor { __typename login } issueField { ...status } }
          ... on IssueFieldRemovedEvent { createdAt actor { __typename login } issueField { ...status } } }'
STATUS_EVENT_TYPES='[ISSUE_FIELD_ADDED_EVENT, ISSUE_FIELD_CHANGED_EVENT, ISSUE_FIELD_REMOVED_EVENT]'
STATUS_FRAGMENT='fragment status on IssueFields { ... on IssueFieldSingleSelect { fullDatabaseId } }'
# shellcheck disable=SC2016  # GraphQL variables bound by -f, which MUST reach the server unexpanded
STATUS_QUERY='
    query($owner:String!, $name:String!, $endCursor:String) {
      repository(owner:$owner, name:$name) {
        issues(states:OPEN, first:50, after:$endCursor) {
          pageInfo { hasNextPage endCursor }
          nodes {
            number title url
            subIssuesSummary { total completed }
            labels(first:100) { nodes { name } }
            issueFieldValues(first:25) {
              pageInfo { hasNextPage }
              nodes { ... on IssueFieldSingleSelectValue { name field { ...status } } }
            }
            labelEvents: timelineItems(itemTypes:[LABELED_EVENT], last:100) { nodes { __typename ... on LabeledEvent { createdAt label { name } } } }
            fieldEvents: timelineItems(itemTypes:'"$STATUS_EVENT_TYPES"', last:100) { '"$STATUS_FIELD_EVENTS"' }
          }
        }
      }
    }
    '"$STATUS_FRAGMENT"

fetch_status_pages() {
  local out="$1" cursor="" pages=0 args
  : >"$out"
  while :; do
    args=(api graphql -f query="$STATUS_QUERY" -f owner="${REPO%%/*}" -f name="${REPO#*/}")
    [[ -n "$cursor" ]] && args+=(-f endCursor="$cursor")
    gh_read "$WORK/status.page" "${args[@]}" || return 1
    cat "$WORK/status.page" >>"$out"
    pages=$((pages + 1))
    cursor="$(jq -r '.data.repository.issues.pageInfo | if .hasNextPage != true then "" elif .endCursor == null then "!" else .endCursor end' \
      "$WORK/status.page" 2>/dev/null)" || {
      LAST_ERR="could not parse a Work status page"
      return 1
    }
    [[ "$cursor" != "!" ]] || {
      LAST_ERR="a Work status page reported more issues but no cursor to them"
      return 1
    }
    [[ -n "$cursor" ]] || return 0
    ((pages >= STATUS_PAGE_LIMIT)) && return 0
  done
}

STATUS_STATE=""
STATUS_CAPPED=0
STATUS_PARTIAL_NOTE="the Work status field needs GraphQL, which this session does not serve"
status_items() {
  [[ -n "$STATUS_STATE" ]] && return 0
  local pages="$WORK/status.pages"
  status_model || return 1
  if [[ "$STATUS_MODEL" == null ]]; then
    STATUS_STATE=none
    return 0
  fi
  if [[ -n "$STATUS_JSON" ]]; then
    jq -c '.pages // []' "$STATUS_JSON" >"$pages"
  elif [[ "$TRANSPORT" == rest ]]; then
    STATUS_STATE=rest
    return 0
  elif ! fetch_status_pages "$pages"; then
    graphql_blocked "$LAST_ERR" || {
      LAST_ERR="Work status: $LAST_ERR"
      return 1
    }
    TRANSPORT=rest STATUS_STATE=rest
    return 0
  fi
  local err
  err="$(body_error "$pages")"
  [[ -z "$err" ]] || {
    LAST_ERR="Work status: $err"
    return 1
  }
  jq -s -e '[ .. | objects | select(has("data")) | .data.repository.issues | objects ] | length > 0' "$pages" >/dev/null 2>&1 || {
    LAST_ERR="Work status: could not parse the open-issue pages"
    return 1
  }
  jq -s -e '[ .. | objects | select(has("data")) | .data.repository.issues.pageInfo.hasNextPage ] | last == true' "$pages" >/dev/null 2>&1 &&
    STATUS_CAPPED=1
  jq -s -c --argjson m "$STATUS_MODEL" "$STATUS_DEFS"'
    [ .. | objects | select(has("data")) | .data.repository.issues.nodes[]? | select(type == "object" and .number != null) ]
    | unique_by(.number)[]
    | . as $n
    | ([ .issueFieldValues.nodes[]? | select(.field.fullDatabaseId? == ($m["field-id"] | tostring)) | .name ][0]
       | try mapped catch error("#\($n.number): \(.)")) as $v
    | if $v == null and .issueFieldValues.pageInfo.hasNextPage == true
      then error("#\(.number): Work status is not among its first 25 field values") else . end
    | {number, title: ((.title // "") | gsub("[\\r\\n]+"; " ")), url,
       parent: ((.subIssuesSummary.total // 0) > (.subIssuesSummary.completed // 0)),
       labels: ([.labels.nodes[]?.name] | effective($v)),
       events: ([.labelEvents.nodes[]? | select(.createdAt != null)]
                + [.fieldEvents.nodes | try synthetic catch error("#\($n.number): \(.)")])}
  ' "$pages" >"$WORK/status.items" 2>"$WORK/status.err" || {
    err="$(sed -n 's/^jq: error ([^)]*): //p' "$WORK/status.err" | head -n1)"
    LAST_ERR="Work status: ${err:-could not parse the open-issue pages}"
    return 1
  }
  STATUS_STATE=ok
}

status_with_label() {
  jq -c --arg l "$1" 'select(any(.labels[]; ascii_downcase == ($l | ascii_downcase)))' "$WORK/status.items"
}

count_label_gql() {
  gh_read "$WORK/count.raw" issue list "${REPO_ARGS[@]}" --state open --label "$2" \
    --limit "$COUNT_LIMIT" --json number,subIssuesSummary \
    -q '"\(length) \(map(select((.subIssuesSummary.total // 0) > (.subIssuesSummary.completed // 0))) | length)"' || return 1
  tr -d '\r' <"$WORK/count.raw" >"$1"
}

count_label_rest() {
  rest_paginate_array "$WORK/count.rest" \
    "repos/$REPO/issues?state=open&per_page=100&labels=$(urlencode "$2")" || return 1
  jq -r '[ .[] | select(has("pull_request") | not) ]
    | "\(length) \(map(select((.sub_issues_summary.total // 0) > (.sub_issues_summary.completed // 0))) | length)"' \
    "$WORK/count.rest" >"$1"
}

SEARCH_ZERO_NOTE="the search read 0 and the REST issue listing did not confirm it"
search_zero_unconfirmed() {
  count_label_rest "$WORK/count.check" "$1" || return 0
  [[ "${2:-}" == prs ]] && jq 'length' "$WORK/count.rest" >"$WORK/count.check"
  local total=""
  read -r total _ <"$WORK/count.check"
  [[ "$total" != "0" ]]
}

print_queues() {
  echo "== Queues (open issues per label) =="
  local labels_to_show=() label n labels_available=0
  if [[ -n "$REPO_LABELS_JSON" || (-z "$COUNTS_JSON" && -n "$REPO") ]]; then
    if fetch_repo_label_names "$WORK/labels.json"; then
      labels_available=1
    fi
  fi
  if ((labels_available)); then
    for label in "${QUEUE_LABELS[@]}"; do
      label_exists_in_repo "$label" "$WORK/labels.json" && labels_to_show+=("$label")
    done
    STUCK_LABELS=()
    ((${#labels_to_show[@]})) && STUCK_LABELS=("${labels_to_show[@]}")
    if ((${#labels_to_show[@]} == 0)); then
      echo "  no queue labels found in this repo (nothing to report)"
      if [[ -z "$QUEUE_LABELS_ARG" ]]; then
        echo "  defaults: ${DEFAULT_QUEUE_LABELS[*]} — pass --queue-labels to customize"
      else
        echo "  pinned: ${QUEUE_LABELS[*]}"
      fi
      echo
      return
    fi
  else
    labels_to_show=("${QUEUE_LABELS[@]}")
  fi
  local rows=() capped=() unavailable=() via_list via_rest total parents
  if [[ -n "$STATUS_JSON" || (-z "$COUNTS_JSON" && -n "$REPO") ]]; then
    status_items || {
      unreadable queues "$LAST_ERR"
      return
    }
  fi
  for label in "${labels_to_show[@]}"; do
    via_list=0 total="" parents=0
    if [[ "$STATUS_STATE" == ok ]]; then
      read -r total parents < <(status_with_label "$label" | jq -rs '"\(length) \(map(select(.parent == true)) | length)"')
    elif [[ -n "$COUNTS_JSON" ]]; then
      total="$(jq -r --arg l "$label" 'if type == "object" then (.[$l] // 0) else 0 end' "$COUNTS_JSON" 2>/dev/null)"
    else
      via_rest=0
      if [[ "$TRANSPORT" == "gh" ]]; then
        if count_label_gql "$WORK/count" "$label"; then
          via_list=1
        elif graphql_blocked "$LAST_ERR"; then
          TRANSPORT="rest"
        elif [[ "$LAST_ERR" == *"Unknown JSON field"* ]]; then
          via_rest=1
        else
          unreadable queues "$label: $LAST_ERR"
          return
        fi
      fi
      if [[ "$TRANSPORT" == "rest" ]] || ((via_rest)); then
        count_label_rest "$WORK/count" "$label" || {
          unreadable queues "$label: $LAST_ERR"
          return
        }
      fi
      read -r total parents <"$WORK/count"
    fi
    [[ "$total" =~ ^[0-9]+$ && "$parents" =~ ^[0-9]+$ ]] || {
      unreadable queues "$label: count not numeric"
      return
    }
    n=$((total - parents))
    if ((via_list && total >= COUNT_LIMIT)); then
      capped+=("$label")
      n="$n+"
    elif ((via_list && total == 0)) && search_zero_unconfirmed "$label"; then
      unavailable+=("$label")
      n="count unavailable"
    fi
    ((parents)) && n="$n (+$parents with open sub-issues)"
    rows+=("$(printf '  %-24s %s' "$label" "$n")")
  done
  printf '%s\n' "${rows[@]}"
  ((LABELS_CAPPED)) && echo "  PARTIAL: the label inventory reached its $LABEL_LIMIT-label cap; rows are not filtered to labels that exist"
  ((${#capped[@]})) && partial_labels "count reached the $COUNT_LIMIT-issue read cap; the true count may be higher" "${capped[@]}"
  ((${#unavailable[@]})) && partial_labels "count unavailable: $SEARCH_ZERO_NOTE" "${unavailable[@]}"
  [[ "$STATUS_STATE" == rest ]] && echo "  PARTIAL: $STATUS_PARTIAL_NOTE; counts are by label alone"
  ((STATUS_CAPPED)) && echo "  PARTIAL: the open-issue read reached its $((STATUS_PAGE_LIMIT * 50))-issue cap; counts may be low"
  echo
}

STUCK_PAGE_LIMIT=10 # 10 pages of 100 is the search ceiling
fetch_stuck_label_gql() {
  local out="$1" label="$2" cursor="" args pages=0 esc search
  esc="${label//\"/\\\"}"
  search="repo:$REPO is:open label:\"$esc\""
  : >"$out"
  while :; do
    args=(api graphql -f query="$STUCK_QUERY" -f search="$search")
    [[ -n "$cursor" ]] && args+=(-f endCursor="$cursor")
    gh_read "$WORK/stuck.page" "${args[@]}" || return 1
    cat "$WORK/stuck.page" >>"$out"
    pages=$((pages + 1))
    cursor="$(jq -r '
      .data.search.pageInfo
      | if .hasNextPage != true then ""
        elif .endCursor == null then "!"
        else .endCursor end
    ' "$WORK/stuck.page" 2>/dev/null)" || {
      LAST_ERR="could not parse a stuck-item page"
      return 1
    }
    [[ "$cursor" != "!" ]] || {
      LAST_ERR="a stuck-item page reported more results but no cursor to them"
      return 1
    }
    [[ -n "$cursor" ]] || return 0
    ((pages >= STUCK_PAGE_LIMIT)) && return 0
  done
}

# shellcheck disable=SC2016  # $search/$endCursor are GraphQL variables bound by -f, and MUST reach the server unexpanded
STUCK_QUERY='
    query($search:String!, $endCursor:String) {
      search(query:$search, type:ISSUE, first:100, after:$endCursor) {
        issueCount
        pageInfo { hasNextPage endCursor }
        nodes {
          __typename
          ... on Issue {
            number title
            timelineItems(itemTypes:[LABELED_EVENT], last:100) { nodes { ... on LabeledEvent { createdAt label { name } } } }
          }
          ... on PullRequest {
            number title
            timelineItems(itemTypes:[LABELED_EVENT], last:100) { nodes { ... on LabeledEvent { createdAt label { name } } } }
          }
        }
      }
    }'

print_stuck() {
  echo "== Stuck (open items in a queue label for more than ${STUCK_DAYS}d) =="
  local label pages="$WORK/stuck.pages" items="$WORK/stuck.items" err ceiling=() unavailable=() out
  if [[ -n "$STUCK_JSON" ]]; then
    err="$(body_error "$STUCK_JSON")"
    if [[ -n "$err" ]]; then
      unreadable stuck "$err"
      return
    fi
    jq -e 'type == "object"' "$STUCK_JSON" >/dev/null 2>&1 || {
      unreadable stuck "--stuck-json is not an object mapping each label to its search pages"
      return
    }
  elif [[ -z "$REPO" ]]; then
    echo "  (no repo resolved — pass --repo or --stuck-json)"
    echo
    return
  elif [[ "$TRANSPORT" == "rest" ]]; then
    unreadable stuck "label events need GraphQL, which this session does not serve"
    return
  fi
  if ((${#STUCK_LABELS[@]} == 0)); then
    echo "  no queue labels found in this repo (nothing to report)"
    echo
    return
  fi
  local by_status=false
  if [[ -n "$STATUS_JSON" || -z "$STUCK_JSON" ]]; then
    status_items || {
      unreadable stuck "$LAST_ERR"
      return
    }
    [[ "$STATUS_STATE" == rest ]] && {
      unreadable stuck "label events need GraphQL, which this session does not serve"
      return
    }
    [[ "$STATUS_STATE" == ok ]] && by_status=true
  fi

  : >"$items"
  for label in "${STUCK_LABELS[@]}"; do
    if [[ "$by_status" == true ]]; then
      status_with_label "$label" | jq -c --arg l "$label" '
        {number, title, label: $l, kind: "issue",
         since: ([ .events[] | select(.__typename == "LabeledEvent" and (.label.name | ascii_downcase) == ($l | ascii_downcase))
                   | .createdAt | fromdateiso8601 ] | max)}' >>"$items"
    fi
    if [[ -n "$STUCK_JSON" ]]; then
      jq -c --arg l "$label" '.[$l] // []' "$STUCK_JSON" >"$pages" 2>/dev/null || {
        unreadable stuck "$label: could not parse the search pages"
        return
      }
      err="$(body_error "$pages")"
      if [[ -n "$err" ]]; then
        unreadable stuck "$label: $err"
        return
      fi
      [[ "$(jq 'length' "$pages" 2>/dev/null)" == "0" ]] && continue
    elif ! fetch_stuck_label_gql "$pages" "$label"; then
      graphql_blocked "$LAST_ERR" && TRANSPORT="rest"
      unreadable stuck "$label: $LAST_ERR"
      return
    fi
    jq -s -e '[ .. | objects | select(has("data")) | .data.search | objects ] | length > 0' \
      "$pages" >/dev/null 2>&1 || {
      unreadable stuck "$label: could not parse the search pages"
      return
    }
    if [[ -z "$STUCK_JSON" ]] &&
      jq -s -e '[ .. | objects | select(has("data")) | .data.search.nodes[]? ] | length == 0' \
        "$pages" >/dev/null 2>&1 &&
      search_zero_unconfirmed "$label" prs; then
      unavailable+=("$label")
      continue
    fi
    if jq -s -e '
      [ .. | objects | select(has("data")) | .data.search | objects ] as $p
      | ($p[0].issueCount // 0) > ([ $p[].nodes[]? ] | length)
    ' "$pages" >/dev/null 2>&1; then
      ceiling+=("$label")
    fi
    jq -s -c --arg l "$label" --argjson prs "$by_status" '
      [ .. | objects | select(has("data")) | .data.search.nodes[]?
        | select(type == "object" and .number != null and (($prs | not) or .__typename == "PullRequest")) ]
      | .[]
      | . as $n
      | { number: $n.number,
          title: (($n.title // "") | gsub("[\\r\\n]+"; " ")),
          label: $l,
          kind: (if $n.__typename == "PullRequest" then "PR" else "issue" end),
          since: ([ $n.timelineItems.nodes[]?
                    | select(.label.name == $l and .createdAt != null)
                    | .createdAt | fromdateiso8601 ] | max) }
    ' "$pages" >>"$items" 2>/dev/null || {
      unreadable stuck "$label: could not parse the search pages"
      return
    }
  done

  out="$(jq -s -r --argjson now "$NOW_EPOCH" --argjson days "$STUCK_DAYS" --argjson cap "$STUCK_LIMIT" '
    def line:
      "  #\(.number) \(.kind)  \(.title)  (\(.label), "
      + (if .since == null then "days unknown" else "\((($now - .since) / 86400) | floor)d in stage" end) + ")";
    ([ .[] | select(.since != null and ($now - .since) > ($days * 86400)) ] | sort_by(.since, .number)) as $dated
    | ([ .[] | select(.since == null) ] | sort_by(.number)) as $unknown
    | ($dated + $unknown) as $all
    | ($all[:$cap][] | line),
      (if ($all | length) > $cap
       then "  PARTIAL: \($all | length) stuck items; showing the oldest \($cap) (raise --stuck-limit)"
       else empty end)
  ' "$items" 2>/dev/null)" || {
    unreadable stuck "could not parse the stuck items"
    return
  }
  if [[ -n "$out" ]]; then
    echo "$out"
  elif ((${#unavailable[@]} == 0)); then
    echo "  (none — no open item has held a queue label for more than ${STUCK_DAYS}d)"
  fi
  ((${#unavailable[@]})) && partial_labels "count unavailable: $SEARCH_ZERO_NOTE" "${unavailable[@]}"
  ((${#ceiling[@]})) && partial_labels "the search reached its 1,000-result ceiling; the list may be missing items" "${ceiling[@]}"
  [[ "$by_status" == true ]] && ((STATUS_CAPPED)) &&
    echo "  PARTIAL: the open-issue read reached its $((STATUS_PAGE_LIMIT * 50))-issue cap; a stuck issue past it is not shown"
  echo
}

PR_PARTIAL=()
fetch_prs_gql() {
  gh_read "$1" pr list "${REPO_ARGS[@]}" --state open --limit "$PR_LIST_LIMIT" \
    --json number,title,url,isDraft,mergeStateStatus,reviewDecision,baseRefName,headRefOid || return 1
  local n
  n="$(jq -e 'length' "$1" 2>/dev/null)" || {
    LAST_ERR="could not parse the PR list"
    return 1
  }
  ((n >= PR_LIST_LIMIT)) && PR_PARTIAL+=("the open-PR list reached its $PR_LIST_LIMIT-PR read cap; a clean PR past it is not shown")
  return 0
}

MERGE_STATE_RETRY_SECS="${MORNING_BRIEF_MERGE_STATE_RETRY_SECS:-2}"

merge_state_uncomputed() {
  jq -e '(.mergeable == null) or ((.mergeable_state // "unknown") == "unknown")' "$1" >/dev/null 2>&1
}

fetch_prs_rest() {
  local out="$1" total i number numbers=() retry=() uncomputed=()
  rest_paginate_array "$WORK/prs.rest" "repos/$REPO/pulls?state=open&per_page=100" || return 1
  total="$(jq 'length' "$WORK/prs.rest")"
  PR_PARTIAL=()
  ((total > PR_LIMIT)) && PR_PARTIAL+=("$total open PRs; merge state read for the first $PR_LIMIT only (raise --pr-limit)")
  : >"$WORK/prs.detail"
  for ((i = 0; i < total && i < PR_LIMIT; i++)); do
    number="$(jq -r ".[$i].number" "$WORK/prs.rest")"
    numbers+=("$number")
    gh_read "$WORK/pr.$number" api "repos/$REPO/pulls/$number" || return 1
    merge_state_uncomputed "$WORK/pr.$number" && retry+=("$number")
  done
  if ((${#retry[@]} > 0)); then
    sleep "$MERGE_STATE_RETRY_SECS"
    for number in "${retry[@]}"; do
      gh_read "$WORK/pr.$number" api "repos/$REPO/pulls/$number" || return 1
      merge_state_uncomputed "$WORK/pr.$number" && uncomputed+=("#$number")
    done
  fi
  for number in "${numbers[@]}"; do
    cat "$WORK/pr.$number" >>"$WORK/prs.detail"
  done
  if ((${#uncomputed[@]} > 0)); then
    PR_PARTIAL+=("merge state not yet computed by GitHub for ${uncomputed[*]}; inconclusive, re-run shortly")
  fi
  jq -s '[ .[] | {number, title, url: .html_url, isDraft: .draft,
                  mergeStateStatus: ((.mergeable_state // "unknown") | ascii_upcase),
                  reviewDecision: "n/a", baseRefName: .base.ref, headRefOid: .head.sha} ]' "$WORK/prs.detail" >"$out"
}

freshness_note() {
  local number="$1" base="$2" sha="$3" behind=""
  if [[ -z "$base" || ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
    printf 'base freshness unread: the PR record names no base branch or head commit'
    return
  fi
  if [[ -n "$BEHIND_JSON" ]]; then
    behind="$(jq -r --arg n "$number" '.[$n] // empty' "$BEHIND_JSON" 2>/dev/null)"
  elif [[ -n "$PR_JSON" ]]; then
    printf 'base freshness unread: --pr-json given without --behind-json'
    return
  elif gh_read "$WORK/compare" api "repos/$REPO/compare/$(urlencode "$base")...$sha?per_page=1"; then
    behind="$(jq -r '.behind_by // empty' "$WORK/compare" 2>/dev/null)"
  else
    printf 'base freshness unread: %s' "$LAST_ERR"
    return
  fi
  if [[ ! "$behind" =~ ^[0-9]+$ ]]; then
    printf 'base freshness unread: no behind count for #%s' "$number"
  elif ((behind > 0)); then
    printf 'head is %s commit(s) behind %s; checks may predate the current base' "$behind" "$base"
  fi
}

print_merge_ready() {
  echo "== Merge-ready PRs (non-draft, mergeStateStatus=CLEAN) =="
  local prs_file="$WORK/prs.json"
  if [[ -n "$PR_JSON" ]]; then
    prs_file="$PR_JSON"
  else
    gql_or_rest "$prs_file" fetch_prs_gql fetch_prs_rest || {
      unreadable merge-ready "$LAST_ERR"
      return
    }
  fi
  jq -e 'type == "array"' "$prs_file" >/dev/null 2>&1 || {
    unreadable merge-ready "could not parse the PR list"
    return
  }
  local clean='[ .[] | select(.isDraft == false and .mergeStateStatus == "CLEAN") ] | sort_by(.number) | .[]'
  local notes='{}' number base sha note ready read=0
  while IFS=$'\t' read -r number base sha; do
    if ((read < PR_LIMIT)); then
      note="$(freshness_note "$number" "$base" "$sha" </dev/null)"
    else
      note="base freshness unread: compare reads capped at $PR_LIMIT (raise --pr-limit)"
    fi
    ((++read))
    [[ -n "$note" ]] && notes="$(jq -c --arg n "$number" --arg v "$note" '.[$n] = $v' <<<"$notes")"
  done < <(jq -r "$clean"' | [.number, (.baseRefName // ""), (.headRefOid // "")] | @tsv' "$prs_file" 2>/dev/null)
  ((read > PR_LIMIT)) && PR_PARTIAL+=("$read clean PRs; base freshness read for the first $PR_LIMIT only (raise --pr-limit)")
  ready="$(jq -r --argjson notes "$notes" "$clean"'
    | "  #\(.number) \(.title)\n    \(.url)  review=\(.reviewDecision // "" | if . == "" then "none" else . end)"
      + ($notes[.number | tostring] | if . then "\n    UNVERIFIED: \(.)" else "" end)
  ' "$prs_file" 2>/dev/null)" || {
    unreadable merge-ready "could not parse the PR list"
    return
  }
  if [[ -n "$ready" ]]; then
    echo "$ready"
  else
    echo "  (none clean right now)"
  fi
  local note
  for note in "${PR_PARTIAL[@]}"; do
    echo "  PARTIAL: $note"
  done
  echo "  authoritative merge gate: /source-control:babysit-prs"
  echo
}

fetch_decisions_gql() {
  gh_read "$1" issue list "${REPO_ARGS[@]}" --state open --label "$DECISION_LABEL" \
    --limit "$DECISION_LIMIT" --json number,title,url,body,comments || return 1
  local n
  n="$(jq -e 'length' "$1" 2>/dev/null)" || {
    LAST_ERR="could not parse the decision issues"
    return 1
  }
  ((n >= DECISION_LIMIT)) && DECISIONS_PARTIAL=1
  return 0
}

DECISIONS_PARTIAL=0
fetch_decisions_rest() {
  local out="$1" total i number
  rest_paginate_array "$WORK/dec.rest" \
    "repos/$REPO/issues?state=open&per_page=100&labels=$(urlencode "$DECISION_LABEL")" || return 1
  jq '[ .[] | select(has("pull_request") | not) ]' "$WORK/dec.rest" >"$WORK/dec.all"
  (($(jq 'length' "$WORK/dec.all") > DECISION_LIMIT)) && DECISIONS_PARTIAL=1
  jq --argjson lim "$DECISION_LIMIT" '.[:$lim]' "$WORK/dec.all" >"$WORK/dec.issues"
  total="$(jq 'length' "$WORK/dec.issues")"
  : >"$WORK/dec.detail"
  for ((i = 0; i < total; i++)); do
    number="$(jq -r ".[$i].number" "$WORK/dec.issues")"
    rest_paginate_array "$WORK/dec.comments" "repos/$REPO/issues/$number/comments?per_page=100" || return 1
    jq -c --slurpfile c "$WORK/dec.comments" ".[$i] | {number, title, url: .html_url, body, comments: (\$c[0] | map({body}))}" \
      "$WORK/dec.issues" >>"$WORK/dec.detail"
  done
  jq -s '.' "$WORK/dec.detail" >"$out"
}

print_decisions() {
  echo "== Parked decisions (${DECISION_LABEL}) with RECOMMENDED lines =="
  local decisions_file="$WORK/decisions.json"
  if [[ -z "$DECISIONS_JSON" && (-n "$REPO" || -n "$REPO_LABELS_JSON") ]]; then
    if fetch_repo_label_names "$WORK/labels.json" &&
      ! label_exists_in_repo "$DECISION_LABEL" "$WORK/labels.json"; then
      echo "  (decision label not found in this repo — pass --decision-label to customize)"
      echo
      return
    fi
  fi
  if [[ -n "$DECISIONS_JSON" ]]; then
    decisions_file="$DECISIONS_JSON"
  else
    gql_or_rest "$decisions_file" fetch_decisions_gql fetch_decisions_rest || {
      unreadable decisions "$LAST_ERR"
      return
    }
  fi

  local count
  count="$(jq -r 'if type == "array" then length else error("not a list") end' "$decisions_file" 2>/dev/null)" || {
    unreadable decisions "could not parse the decision issues"
    return
  }
  if [[ -n "$STATUS_JSON" || (-z "$DECISIONS_JSON" && -n "$REPO") ]]; then
    status_items || {
      unreadable decisions "$LAST_ERR"
      return
    }
  fi
  if [[ "$STATUS_STATE" == ok ]]; then
    local number members="$WORK/dec.members" joined="$WORK/dec.joined"
    status_with_label "$DECISION_LABEL" | jq -s '.' >"$members"
    jq --slurpfile s "$WORK/status.items" --slurpfile k "$members" '
      [ .[] | select(.number as $n | ($k[0] | any(.number == $n)) or ($s | all(.number != $n))) ]' \
      "$decisions_file" >"$joined"
    for number in $(jq -r --slurpfile d "$joined" '.[] | .number as $n | select($d[0] | all(.number != $n)) | .number' "$members"); do
      if [[ -n "$STATUS_JSON" ]]; then
        jq -c -s --argjson n "$number" 'first(.. | objects | select(has("data")) | .data.repository.issues.nodes[]? | select(.number == $n)
          | {number, title, url, body, comments: (.comments // [])})' "$WORK/status.pages" >"$WORK/dec.view"
      else
        gh_read "$WORK/dec.view" issue view "$number" "${REPO_ARGS[@]}" --json number,title,url,body,comments || {
          unreadable decisions "#$number: $LAST_ERR"
          return
        }
      fi
      jq --slurpfile v "$WORK/dec.view" '. + $v' "$joined" >"$WORK/dec.next" && mv "$WORK/dec.next" "$joined"
    done
    decisions_file="$joined"
    count="$(jq 'length' "$joined")"
  fi
  if ((count == 0)); then
    echo "  (none parked)"
    decisions_status_partial
    echo
    return
  fi

  local i number title url rec
  for ((i = 0; i < count; i++)); do
    number="$(jq -r ".[$i].number" "$decisions_file")"
    title="$(jq -r ".[$i].title" "$decisions_file")"
    url="$(jq -r ".[$i].url // \"\"" "$decisions_file")"
    local combined marker_re
    marker_re='RECOMMENDED[[:space:]]*\**[[:space:]]*[-:—]'
    combined="$(jq -r ".[$i] | (.body // \"\") + \"\n\" + ((.comments // []) | map(.body // \"\") | join(\"\n\"))" \
      "$decisions_file")"
    rec="$(grep -am1 -E "$marker_re" <<<"$combined")"
    [[ -n "$rec" ]] || rec="$(grep -iam1 -E "$marker_re" <<<"$combined")"
    rec="$(sed -E 's/^[[:space:]]*//; s/^[0-9]+[.)][[:space:]]*//; s/^[-*>|#[:space:]]*//; s/\*\*//g; s/[[:space:]]*$//' <<<"$rec")"
    if [[ "$rec" == RECOMMENDED* || "$rec" == recommended* ]]; then
      rec="${rec#RECOMMENDED}"
      rec="${rec#recommended}"
      rec="$(sed -E 's/^([[:space:]]|[-:—])*//' <<<"$rec")"
    fi
    if [[ "$REC_MAXLEN" != "0" && -n "$rec" && "${#rec}" -gt "$REC_MAXLEN" ]]; then
      rec="${rec:0:$REC_MAXLEN}…"
    fi
    printf '  #%s %s\n' "$number" "$title"
    [[ -n "$url" ]] && printf '    %s\n' "$url"
    if [[ -n "$rec" ]]; then
      printf '    RECOMMENDED: %s\n' "$rec"
    else
      printf '    (no RECOMMENDED line found)\n'
    fi
  done
  ((DECISIONS_PARTIAL)) && echo "  PARTIAL: the decision list reached its $DECISION_LIMIT-issue read cap; an issue past it is not shown"
  decisions_status_partial
  echo
}

decisions_status_partial() {
  [[ "$STATUS_STATE" == rest ]] && echo "  PARTIAL: $STATUS_PARTIAL_NOTE; an issue parked only on the field is not shown"
  ((STATUS_CAPPED)) && echo "  PARTIAL: the open-issue read reached its $((STATUS_PAGE_LIMIT * 50))-issue cap; an issue parked only on the field past it is not shown"
  return 0
}

TELEMETRY_PARTIAL=0
find_telemetry_issue_gql() {
  gh_read "$WORK/tel.raw" issue list "${REPO_ARGS[@]}" --state open \
    --search "$TELEMETRY_SEARCH" --limit "$TELEMETRY_SEARCH_LIMIT" --json number || return 1
  local n
  n="$(jq -e 'length' "$WORK/tel.raw" 2>/dev/null)" || {
    LAST_ERR="could not parse the issue search"
    return 1
  }
  ((n >= TELEMETRY_SEARCH_LIMIT)) && TELEMETRY_PARTIAL=1
  jq -r 'sort_by(.number) | .[0].number // empty' "$WORK/tel.raw" >"$1"
}

find_telemetry_issue_rest() {
  rest_paginate_array "$WORK/tel.rest" "repos/$REPO/issues?state=open&per_page=100" || return 1
  jq -r --argjson tokens "$(printf '%s\n' "${TELEMETRY_TITLE_TOKENS[@]}" | jq -R . | jq -s .)" '
    [ .[] | select(has("pull_request") | not)
      | select(.title as $t | $tokens | all(. as $tok | ($t | ascii_downcase | contains($tok))))
      | .number ]
    | sort | .[0] // empty
  ' "$WORK/tel.rest" >"$1"
}

fetch_telemetry_comments_gql() {
  gh_read "$1" issue view "$TELEMETRY_ISSUE_RESOLVED" "${REPO_ARGS[@]}" --json comments -q '.comments'
}

fetch_telemetry_comments_rest() {
  rest_paginate_array "$WORK/telc.rest" "repos/$REPO/issues/$TELEMETRY_ISSUE_RESOLVED/comments?per_page=100" || return 1
  jq 'map({body})' "$WORK/telc.rest" >"$1"
}

TELEMETRY_ISSUE_RESOLVED=""
print_telemetry() {
  echo "== Lane telemetry freshness (last-cycle age + flags) =="
  local comments_file="$WORK/telemetry.json"
  if [[ -n "$TELEMETRY_JSON" ]]; then
    comments_file="$TELEMETRY_JSON"
  else
    if [[ -n "$TELEMETRY_ISSUE" ]]; then
      TELEMETRY_ISSUE_RESOLVED="$TELEMETRY_ISSUE"
    else
      gql_or_rest "$WORK/tel.issue" find_telemetry_issue_gql find_telemetry_issue_rest || {
        unreadable telemetry "issue search: $LAST_ERR"
        return
      }
      TELEMETRY_ISSUE_RESOLVED="$(tr -d '[:space:]' <"$WORK/tel.issue")"
    fi
    if [[ -z "$TELEMETRY_ISSUE_RESOLVED" ]]; then
      echo "  no telemetry issue found (nothing to report)"
      echo
      return
    fi
    gql_or_rest "$comments_file" fetch_telemetry_comments_gql fetch_telemetry_comments_rest || {
      unreadable telemetry "issue #$TELEMETRY_ISSUE_RESOLVED: $LAST_ERR"
      return
    }
    echo "  source: issue #$TELEMETRY_ISSUE_RESOLVED"
  fi
  local comments
  comments="$(cat "$comments_file")"
  if [[ -z "$comments" || "$comments" == "null" ]]; then
    echo "  no telemetry issue found (nothing to report)"
    echo
    return
  fi

  local n
  n="$(jq -r 'if type == "array" then length else error("not a list") end' <<<"$comments" 2>/dev/null)" || {
    unreadable telemetry "could not parse the telemetry comments"
    return
  }
  ((TELEMETRY_PARTIAL)) && echo "  PARTIAL: the telemetry issue search reached its $TELEMETRY_SEARCH_LIMIT-issue cap; the oldest match may lie past it"
  local i body lane last flags any=0
  for ((i = 0; i < n; i++)); do
    body="$(jq -r ".[$i].body // \"\"" <<<"$comments" 2>/dev/null)"
    [[ "$body" == "<!-- harness-ops:lane-telemetry marker="* ]] || continue
    lane="$(grep -im1 -oE '(^|[^a-z])lane:[[:space:]]*[a-z0-9_-]+' <<<"$body" | sed -E 's/.*lane:[[:space:]]*//')"
    [[ -n "$lane" ]] || continue
    any=1
    last="$(grep -im1 'last-cycle:' <<<"$body" | sed -E 's/.*last-cycle:[[:space:]]*//; s/[[:space:]].*$//; s/[[:space:]]*$//')"
    flags="$(grep -im1 'flags:' <<<"$body" | sed -E 's/.*flags:[[:space:]]*//; s/[[:space:]]*$//')"

    local age_note=""
    if [[ -n "$last" ]]; then
      local then_epoch
      then_epoch="$(to_epoch "$last")"
      if [[ -n "$then_epoch" ]]; then
        local delta=$((NOW_EPOCH - then_epoch))
        age_note="$(fmt_age "$delta")"
        if ((delta > STALE_HOURS * 3600)); then
          age_note="$age_note  STALE (>${STALE_HOURS}h)"
        fi
        last="$last UTC"
      else
        age_note="unparsable timestamp"
      fi
    else
      last="(none)"
      age_note="no last-cycle recorded"
    fi

    printf '  %-10s last-cycle=%s  age=%s\n' "$lane" "$last" "$age_note"
    if [[ -n "$flags" && "$flags" != "none" && "$flags" != "-" ]]; then
      printf '    flags: %s\n' "$flags"
    fi
  done
  ((any)) || echo "  (no per-lane comments found on the telemetry issue)"
  echo
}

fetch_merged_gql() {
  local out="$1" cutoff="$2" cursor="" args
  : >"$out"
  while :; do
    args=(api graphql -F owner="${REPO%%/*}" -F name="${REPO##*/}" -f query="$MERGED_QUERY")
    [[ -n "$cursor" ]] && args+=(-f endCursor="$cursor")
    gh_read "$WORK/merged.page" "${args[@]}" || return 1
    cat "$WORK/merged.page" >>"$out"
    cursor="$(jq -r --argjson cutoff "$cutoff" '
      .data.repository.pullRequests
      | if .pageInfo.hasNextPage != true then ""
        elif (.nodes | length) == 0 or .pageInfo.endCursor == null then "!"
        elif ((.nodes | last | .updatedAt // null) == null)
          or ((.nodes | last | .updatedAt | fromdateiso8601) < $cutoff)
        then "" else .pageInfo.endCursor end
    ' "$WORK/merged.page" 2>/dev/null)" || {
      LAST_ERR="could not parse a merged-PR page"
      return 1
    }
    [[ "$cursor" != "!" ]] || {
      LAST_ERR="a merged-PR page reported more results but no cursor to them"
      return 1
    }
    [[ -n "$cursor" ]] || return 0
  done
}

# shellcheck disable=SC2016  # $owner/$name/$endCursor are GraphQL variables bound by -F/-f, and MUST reach the server unexpanded
MERGED_QUERY='
    query($owner:String!, $name:String!, $endCursor:String) {
      repository(owner:$owner, name:$name) {
        pullRequests(states:MERGED, first:25, orderBy:{field:UPDATED_AT, direction:DESC}, after:$endCursor) {
          pageInfo { hasNextPage endCursor }
          nodes {
            number title url mergedAt updatedAt
            # 100 is the GraphQL page maximum. The walk follows only the
            # OUTER cursor, so a PR with more threads than this would be
            # truncated with no signal. hasNextPage is read below and
            # reported, because a partial read must never render as an
            # all-clear.
            reviewThreads(first:100) {
              pageInfo { hasNextPage }
              nodes {
                isResolved
                comments(first:1) { nodes { createdAt author { login } body } }
              }
            }
          }
        }
      }
    }'

stranded_bookmark_path() {
  local base="$DATA_DIR_ARG" seg="${CLAUDE_PLUGIN_DATA:-}" key
  if [[ -z "$base" ]]; then
    seg="${seg%[/\\]}"
    seg="${seg##*[/\\]}"
    if [[ "$seg" == work-items || "$seg" == work-items-* ]]; then
      base="$CLAUDE_PLUGIN_DATA"
    else
      base="${HOME:-}/.claude/plugins/data/work-items"
    fi
  fi
  key="$(printf '%s' "$REPO" | tr '[:upper:]' '[:lower:]')"
  [[ "$key" =~ ^[a-z0-9._-]+/[a-z0-9._-]+$ && "$key" != *..* ]] || return 0
  printf '%s/morning-brief/%s/stranded-cutoff' "${base%/}" "$key"
}

save_bookmark() {
  local file="$1" value="$2" tmp
  [[ ! -L "$file" ]] && mkdir -p "${file%/*}" 2>/dev/null &&
    tmp="$(mktemp "$file.XXXXXX" 2>/dev/null)" || return 1
  if ! { printf '%s\n' "$value" >"$tmp" && mv -f "$tmp" "$file"; } 2>/dev/null; then
    rm -f "$tmp"
    return 1
  fi
}

print_stranded() {
  local floor=$((NOW_EPOCH - STRANDED_DAYS * 86400)) cutoff bookmark="" mark mark_epoch window
  cutoff=$floor
  window="last ${STRANDED_DAYS}d"
  if [[ -z "$MERGED_JSON" && -n "$REPO" ]]; then
    bookmark="$(stranded_bookmark_path)"
    if [[ -n "$bookmark" && -f "$bookmark" ]]; then
      mark="$(tr -d '[:space:]' <"$bookmark")"
      mark_epoch="$(to_epoch "$mark")"
      if [[ -z "$mark_epoch" ]]; then
        window="$window; bookmark unparsable, ignored"
      elif ((mark_epoch < floor)); then
        cutoff=$mark_epoch
        window="$window, widened to the last full read's bookmark"
      fi
    fi
  fi
  echo "== Findings stranded on merged PRs (merged since $(utc_stamp "$cutoff"): $window) =="
  local merged_file="$WORK/merged.json"
  if [[ -n "$MERGED_JSON" ]]; then
    merged_file="$MERGED_JSON"
    local fixture_err
    fixture_err="$(body_error "$merged_file")"
    if [[ -n "$fixture_err" ]]; then
      unreadable stranded "$fixture_err"
      return
    fi
  elif [[ -z "$REPO" ]]; then
    echo "  (no repo resolved — pass --repo or --merged-json)"
    echo
    return
  elif [[ "$TRANSPORT" == "rest" ]]; then
    unreadable stranded "review threads need GraphQL, which this session does not serve"
    return
  else
    if ! fetch_merged_gql "$merged_file" "$cutoff"; then
      graphql_blocked "$LAST_ERR" && TRANSPORT="rest"
      unreadable stranded "$LAST_ERR"
      return
    fi
    STRANDED_READ_CUTOFF=$cutoff
  fi

  jq -s -e '[ .. | objects | select(has("data")) | .data.repository.pullRequests | objects ] | length > 0' \
    "$merged_file" >/dev/null 2>&1 || {
    unreadable stranded "could not parse the merged-PR pages"
    return
  }

  local stranded
  stranded="$(jq -s -r --argjson cutoff "$cutoff" '
    # `jq -s` wraps the input in one more array, and `gh --paginate` emits a
    # bare sequence of page objects while a fixture file is already an array of
    # them. `..|objects` walks both shapes without caring which arrived, then
    # selects only true page documents.
    [ .. | objects | select(has("data")) | .data.repository.pullRequests.nodes[]? ]
    | map(select(.mergedAt != null and ((.mergedAt | fromdateiso8601) >= $cutoff)))
    | map(
        . as $pr
        | ($pr.reviewThreads.nodes // [])
          | map(select(
              .isResolved == false
              and (.comments.nodes[0].createdAt // null) != null
              # The discriminator: the finding arrived after the gate had passed.
              and ((.comments.nodes[0].createdAt | fromdateiso8601) > ($pr.mergedAt | fromdateiso8601))
            ))
          | map({
              pr: $pr.number, title: $pr.title, url: $pr.url,
              author: (.comments.nodes[0].author.login // "unknown"),
              # Severity must survive to the operator: a stranded P1 cannot read
              # like a P3. Matched on the STRUCTURED marker only — the badge
              # alt-text (`![P1 Badge]`), the shields URL (`badge/P1`), or a
              # leading bracket — never on free prose. A body-wide substring
              # test falsely promotes a P2 titled "Preserve P1 labels", and any
              # finding that merely discusses CRITICAL or SECURITY.
              sev: (
                (.comments.nodes[0].body // "")
                # `[ match(...) ]` rather than `capture(...).s` or a bare
                # `match(...)`: a non-match must yield EMPTY so the next
                # alternative is tried. Indexing a non-matching capture instead
                # aborts the whole program, which renders every PR as clear.
                | . as $b
                | [ ( $b | [ match("!\\[[[:space:]]*(P[0-9])[ _-]?Badge"; "i") ] ),
                    ( $b | [ match("badge/(P[0-9])"; "i") ] ),
                    ( $b | [ match("^[[:space:]]*\\[(P[0-9])\\]"; "i") ] ) ]
                | map(.[0].captures[0].string // empty)
                | (.[0] // "")
                | ascii_upcase
              )
            })
      )
    | add // []
    # Collapse to one line per PR. Several findings on one PR are one thing for
    # the operator to go look at, and repeating the identical title once per
    # thread buries the other PRs. The PR carries its WORST severity, so
    # collapsing can never soften a P0 sitting beside advisory findings.
    | group_by(.pr)
    | map({
        pr: .[0].pr, title: .[0].title, url: .[0].url,
        author: (map(.author) | unique | join(", ")),
        n: length,
        # Rank NUMERICALLY, never on the display string: "--" sorts before "P0"
        # lexicographically, so an unclassified thread beside a P0 would hide
        # the P0 behind a "[--]" label. Unrecognized ranks last (99).
        sev: (map(.sev) | map(if . == "" then 99 else (.[1:] | tonumber) end) | min
              | if . == 99 then "--" else "P\(.)" end)
      })
    | sort_by(if .sev == "--" then 99 else (.sev[1:] | tonumber) end, .pr)
    | .[]
    | "  [\(.sev)] #\(.pr) \(.title)  (\(.n) finding\(if .n == 1 then "" else "s" end))\n    \(.url)  by \(.author)"
  ' "$merged_file" 2>/dev/null)" || {
    unreadable stranded "could not parse the merged-PR pages"
    return
  }

  local truncated
  truncated="$(jq -s -r '
    [ .. | objects | select(has("data")) | .data.repository.pullRequests.nodes[]?
      | select(.reviewThreads.pageInfo.hasNextPage == true) | .number ]
    | unique | map("#\(.)") | join(", ")
  ' "$merged_file" 2>/dev/null)" || {
    unreadable stranded "could not parse the merged-PR pages"
    return
  }
  if [[ -n "$truncated" ]]; then
    echo "  WARNING: more than 100 review threads on $truncated — this read is PARTIAL, not an all-clear"
  fi

  if [[ -n "$stranded" ]]; then
    echo "$stranded"
    echo "  these merged with the finding unread — the merge gate could not see it"
  else
    echo "  (none — every merged PR in the window is clear)"
  fi
  if [[ -n "$bookmark" ]]; then
    if [[ -n "$truncated" ]]; then
      echo "  bookmark not advanced: this read is PARTIAL"
    elif ! save_bookmark "$bookmark" "$(from_epoch "$floor")"; then
      echo "  bookmark not saved under the data dir; the next run reads back to its floor or an older bookmark"
    fi
  fi
  echo
}

print_landed() {
  local cutoff=$((NOW_EPOCH - 86400)) window="first read on this machine: last 1d" stamp="" mark mark_epoch
  if [[ -z "$MERGED_JSON" && -n "$REPO" ]]; then
    stamp="$(stranded_bookmark_path)"
    [[ -n "$stamp" ]] && stamp="${stamp%/*}/landed-at"
    if [[ -n "$stamp" && -f "$stamp" ]]; then
      mark="$(tr -d '[:space:]' <"$stamp")"
      mark_epoch="$(to_epoch "$mark")"
      if [[ -n "$mark_epoch" ]]; then
        cutoff=$mark_epoch
        window="since landed_at"
      else
        window="landed_at unparsable, ignored: last 1d"
      fi
    fi
  fi
  echo "== Landed (merged since $(utc_stamp "$cutoff"): $window) =="
  [[ -n "$LANDED_SETTING" ]] && echo "  setting: $LANDED_SETTING"
  local merged_file="$WORK/merged.json" err
  if [[ -n "$MERGED_JSON" ]]; then
    merged_file="$MERGED_JSON"
    err="$(body_error "$merged_file")"
    if [[ -n "$err" ]]; then
      unreadable landed "$err"
      return
    fi
  elif [[ -z "$REPO" ]]; then
    echo "  (no repo resolved — pass --repo or --merged-json)"
    echo
    return
  elif [[ "$TRANSPORT" == "rest" ]]; then
    unreadable landed "the merged-PR read needs GraphQL, which this session does not serve"
    return
  elif [[ -z "$STRANDED_READ_CUTOFF" ]] || ((STRANDED_READ_CUTOFF > cutoff)); then
    merged_file="$WORK/landed.json"
    if ! fetch_merged_gql "$merged_file" "$cutoff"; then
      graphql_blocked "$LAST_ERR" && TRANSPORT="rest"
      unreadable landed "$LAST_ERR"
      return
    fi
  fi

  local landed
  landed="$(jq -s -r --argjson cutoff "$cutoff" --argjson k "$LANDED_SAMPLE" '
    if ([ .. | objects | select(has("data")) | .data.repository.pullRequests | objects ] | length) == 0
    then error("no page") else . end
    | [ .. | objects | select(has("data")) | .data.repository.pullRequests.nodes[]? ]
    | map(select(.mergedAt != null and ((.mergedAt | fromdateiso8601) >= $cutoff)))
    | unique_by(.number) | sort_by(.mergedAt, .number)
    | length as $n
    | "  \($n) PR\(if $n == 1 then "" else "s" end) merged",
      if $n == 0 or $k == 0 then empty else
        ([$k, $n] | min) as $m
        | "  Read these (\($m) of \($n), spread across the window):",
          # The oldest, the newest and evenly between; one pick is the newest.
          ( (if $m == 1 then [$n - 1] else [ range(0; $m) | (. * ($n - 1) / ($m - 1) | floor) ] end) as $picks
            | .[$picks[]]
            | "    #\(.number) \(.title)\n      \(.url)  merged \(.mergedAt)" )
      end
  ' "$merged_file" 2>/dev/null)" || {
    unreadable landed "could not parse the merged-PR pages"
    return
  }
  echo "$landed"
  if [[ -n "$stamp" ]] && ! save_bookmark "$stamp" "$(from_epoch "$NOW_EPOCH")"; then
    echo "  landed_at not saved under the data dir; the next run reads back to this cutoff"
  fi
  echo
}

# shellcheck disable=SC2016  # $runs, $ann, $lanes, $since and $threshold are jq variables bound by --slurpfile/--argjson
LANE_DEFS='
  def num(re): [match(re; "i") | .captures[0].string | tonumber] | first;
  def tok($k): [match("(?:^|[^A-Za-z0-9_-])" + $k + "=([A-Za-z0-9._:/,\\[\\]-]+)") | .captures[0].string | sub("[.,]+$"; "")] | first;
  def count: if type == "number" and . >= 0 and . == floor then . else null end;
  # Turns and the cap from the records of the run ($recs), else from the SDK
  # result and the turn-cap text of the action.
  def turns_of($recs): ($recs | map(.turns | count) | first) // num("\"num_turns\":([0-9]+)") // num("after ([0-9]+) turns, exceeding");
  def cap_of($recs): ($recs | map(.maxTurns | count) | first) // num("configured maximum of ([0-9]+)");
  def klass($recs):
    ($recs | map(.class)) as $c
    | if $c | index("rate-limit") then "rate-limit"
      elif $c | index("auth") then "auth"
      elif ($c | index("max-turns")) or test("error_max_turns|exceeding the configured maximum of [0-9]+|maximum number of turns"; "i") then "max-turns"
      elif $c | index("review-unposted") then "review-unposted"
      else "other" end;
  def hot($cap): $cap != null and . != null and . * 100 >= 80 * $cap;
  def median: if length == 0 then null elif length % 2 == 1 then .[length / 2 | floor] else (.[length / 2 - 1] + .[length / 2]) / 2 end;
  # The v1 lane-outcome records in a run text, at most 8: after each marker,
  # the shortest prefix ending at a "}" that parses, since free text may follow
  # the JSON. A record whose credential or fallback is not an object is dropped.
  def records:
    [ split("lane-outcome ")[1:9][] | .[:1100] | split("}") as $p
      | first(range(1; $p | length) as $k | $p[:$k] | join("}") + "}" | fromjson? | objects) ]
    | map(select(.v == 1 and (.credential | type) == "object" and ((.fallback // {}) | type) == "object"));
  def lane_runs($wf):
    ($ann[0]) as $texts
    | ($wf | sub("\\.ya?ml$"; "")) as $lane
    | [ ($runs[0][$wf] // [])[]
      | select(.status == "completed" and .conclusion != "skipped" and .conclusion != null)
      | select((.created_at | fromdateiso8601) >= $since)
      # A leg that handed off leaves its own record, a notice with handoff
      # true; its class and turns are not those of the run, so its record and
      # line are dropped.
      | ($texts[(.id | tostring)] | if . == null then null else split("\n") | map(select(test("\"handoff\":true") | not)) | join("\n") end) as $t
      | (if $t != null then ($t | records | map(select(.handoff != true))) else [] end) as $recs
      | (if $t != null then ($t | tok("activity")) else null end) as $act
      | . + {
          read: ($t != null),
          record: ($recs | length > 0),
          # A run with no working shell: a success record with shellFailed
          # true, or an older record of class shell-failed.
          shell: ($recs | any(.shellFailed == true or .class == "shell-failed")),
          failed: (.conclusion | IN("failure", "timed_out", "startup_failure")),
          turns: (if $t != null then ($t | turns_of($recs)) else null end),
          cap: (if $t != null then ($t | cap_of($recs)) else null end),
          head: (((.event // "") | startswith("pull_request")) or .event == "workflow_run"),
          number: ([(.display_title // "") | capture(" #(?<n>[0-9]+)$") | .n] | first),
          name: (if $act != null and $act != $lane then "\($lane) / \($act)" else $lane end),
          # The record carries no models profile.
          profile: "unknown",
          models: ([$recs[] | .models // [] | .[] | strings] | unique)
        }
      | . + {
          key: (if .head then "head \(.head_sha)" elif .number then "\(.event) #\(.number)" else "title \(.display_title)" end)
        }
      | . + {class: (if .failed | not then null
                     elif .conclusion != "failure" then "other"
                     elif .read then ($t | klass($recs))
                     else "unread" end)}
    ];
'
# shellcheck disable=SC2016  # jq variables, as above
LANES_JQ="$LANE_DEFS"'
  $lanes[]
  | . as $wf
  | lane_runs($wf) as $r
  | ($r | map(select(.failed))) as $f
  | ($f | map(select(.class == "rate-limit")) | length) as $stops
  | ($r | group_by(.key) | map(sort_by(.created_at))) as $items
  | ([ $items[] | . as $g | range(1; length) | select($g[. - 1].class == "rate-limit") ] | length) as $restarts
  | [ $items[] | select((map(select(.class == "rate-limit")) | length) >= 3)
      | {n: (map(select(.class == "rate-limit")) | length), title: .[0].display_title, sha: (.[0].head_sha // "")[0:7], head: .[0].head} ] as $repeat
  | ($r | map(.turns | numbers) | sort) as $ts
  | ($r | sort_by(.created_at) | map(.cap | numbers) | last) as $cap
  | (if ($ts | length) > 0 then $ts[((($ts | length) * 0.9) | ceil) - 1] else null end) as $p90
  | ($f | map(select(.class == "max-turns")) | length) as $maxturns
  | "  \($wf)  runs=\($r | length)  failed=\($f | length) [rate-limit \($stops), max-turns \($maxturns), auth \($f | map(select(.class == "auth")) | length), other \($f | map(select(.class == "other")) | length)\(($f | map(select(.class == "review-unposted")) | length) as $n | if $n > 0 then ", review-unposted \($n)" else "" end)\(($f | map(select(.class == "unread")) | length) as $u | if $u > 0 then ", unread \($u)" else "" end)]  limit-stops=\($stops)  restarts=\($restarts)\(($r | map(select(.shell)) | length) as $sh | if $sh > 0 then "  shell-failed=\($sh)" else "" end)",
    (if ($ts | length) > 0 then
       "    turns: max=\($ts | last) p90=\($p90) cap=\($cap // "?") (\($ts | length) runs)"
       + (if $maxturns > 0 or ($p90 | hot($cap)) then "  CHECK: " + ([ (if $maxturns > 0 then "\($maxturns) max-turns failure(s)" else empty end), (if ($p90 | hot($cap)) then "p90 at or above 80% of the cap" else empty end) ] | join("; ")) + "; raise the cap or inspect the runs" else "" end)
     elif $maxturns > 0 then "    turns: none recorded  CHECK: \($maxturns) max-turns failure(s); raise the cap or inspect the runs"
     else empty end),
    ($r | map(select(.class == "max-turns" or ((.cap // $cap) as $c | .turns | hot($c)))) | sort_by(.created_at) | reverse | .[:5][] | "      \(.html_url)"),
    ($repeat[] | "    \(.n) limit stops on one \(if .head then "head" else "item" end): \(.title)\(if .head and .sha != "" then " @ \(.sha)" else "" end)")
'
# shellcheck disable=SC2016  # jq variables, as above
MODELS_JQ="$LANE_DEFS"'
  [ $lanes[] as $wf | lane_runs($wf)[] ] as $all
  | ($all | map(select(.record))) as $read
  | (($all | length) - ($read | length)) as $unread
  | ($read | group_by([.name, .profile]) | map({
      name: .[0].name, profile: .[0].profile, runs: length,
      pass: (map(select(.conclusion == "success")) | length),
      median: (map(.turns | numbers) | sort | median),
      hits: (map(select(.class == "max-turns")) | length),
      models: ([.[].models[]] | unique)
    })) as $cells
  | "  model usage by activity and profile (runs with a read lane record; no sizes):",
    (if ($cells | length) == 0 then "    no lane records read" else empty end),
    ($cells[] | "    \(.name)  profile=\(.profile)  runs=\(.runs)  pass=\(.pass)/\(.runs)  median-turns=\(.median // "-")  max-turns-hits=\(.hits)  models=\(if (.models | length) > 0 then .models | join(",") else "none recorded" end)"),
    (if $unread > 0 then "    \($unread) run(s) left out: no lane record was read" else empty end),
    (if $threshold == null then "    no threshold set: pass --max-turns-hits N for RECOMMENDED lines"
     else ($cells[] | select(.hits > $threshold)
       | "    RECOMMENDED: \(.name) profile=\(.profile) hit max-turns \(.hits) times, over the threshold of \($threshold); raise its max-turns or route it to a stronger profile in the models: table")
     end)
'
# shellcheck disable=SC2016  # jq variables, as above
KEYS_JQ="$LANE_DEFS"'
  [ $lanes[] as $wf | lane_runs($wf)[] | ($ann[0][.id | tostring] // "" | records)
    | map(select(.credential.role | strings | test("\\A[A-Z0-9_]+\\z")))
    | group_by(.credential.role)[]
    | {role: .[0].credential.role,
       auth: any(.[]; .fallback.reason == "auth" or (.credential.kind == "api-key" and .class == "auth")),
       credit: any(.[]; .fallback.reason == "credit-stop" or (.credential.kind == "api-key" and .class == "credit-stop"))} ]
  | group_by(.role)[]
  | length as $m
  | (map(select(.auth)) | length) as $a
  | (map(select(.credit)) | length) as $c
  | (if $a > 0 then "  KEY: \(.[0].role) auth (fallback on \($a) of \($m) runs read) — replace \(.[0].role)_CLAUDE_API_KEY" else empty end),
    (if $c > 0 then "  KEY: \(.[0].role) credit-stop (\($c) of \($m)) — rotate a spare key into \(.[0].role)" else empty end)
'
# shellcheck disable=SC2016  # jq variables, as above
SPEND_JQ="$LANE_DEFS"'
  def usd: (. * 100 | round) as $c | "\($c / 100 | floor).\($c % 100 | tostring | if length == 1 then "0" + . else . end)";
  [ $lanes[] as $wf | lane_runs($wf) as $r | $r[]
    | ($ann[0][.id | tostring] // "" | records)[]
    | select(.credential.kind == "api-key" and (.credential.role | strings | test("\\A[A-Z0-9_]+\\z")))
    | {wf: $wf, runs: ($r | length), role: .credential.role,
       cost: (.costUsd | if type == "number" and . >= 0 and . < 1e6 then (if . == 0 then 0 else . end) else null end)} + {ok: (.outcome == "success" and .class != "credit-stop")} ]
  | group_by(.role)[]
  | length as $n
  | (map(select(.ok) | .cost | numbers) | sort | median) as $med
  | (unique_by(.wf) | map(.runs) | add) as $runs
  | (map(.cost | numbers) | add) as $sum
  | if $med == null then "  SPEND: \(.[0].role) cost not recorded (n=\($n))"
    else "  SPEND: \(.[0].role) ~$\($med * $runs / $days | usd)/day (list price, n=\($n)) — estimate: median $\($med | usd) per successful key leg × \($runs) runs over \($days)d; $\($sum | usd) summed over the legs read" end
'

LANES_PARTIAL=0
LANE_RUNS_SHORT=0
CALLER_JOB_RE='^([A-Za-z0-9][A-Za-z0-9 -]*) / '
fetch_lane_runs_by_day() {
  local wf="$1" e="$2" day today
  today="$(from_epoch "$NOW_EPOCH")"
  today="${today%%T*}"
  : >"$WORK/lane.days"
  while day="$(from_epoch "$e")" && day="${day%%T*}" && [[ ! "$day" > "$today" ]]; do
    gh_read "$WORK/lane.day" api --paginate "repos/$REPO/actions/workflows/$(urlencode "$wf")/runs?created=$day&per_page=100" || return 1
    LANE_RUNS_SHORT=$((LANE_RUNS_SHORT + $(jq -s '[(.[0].total_count // 0) - ([.[].workflow_runs[]?] | length), 0] | max' "$WORK/lane.day" 2>/dev/null || echo 0)))
    cat "$WORK/lane.day" >>"$WORK/lane.days"
    e=$((e + 86400))
  done
  mv "$WORK/lane.days" "$WORK/lane.page"
}

fetch_lane_runs() {
  local out="$1" day wf
  day="$(from_epoch "$2")"
  day="${day%%T*}"
  echo '{}' >"$out"
  for wf in "${LANE_WORKFLOWS[@]}"; do
    gh_read "$WORK/lane.page" api --paginate "repos/$REPO/actions/workflows/$(urlencode "$wf")/runs?created=>=$day&per_page=100" || return 1
    if [[ "$(jq -s '(.[0].total_count // 0) > ([.[].workflow_runs[]?] | length)' "$WORK/lane.page" 2>/dev/null)" == "true" ]]; then
      fetch_lane_runs_by_day "$wf" "$2" || return 1
    fi
    jq -s --arg wf "$wf" --slurpfile acc "$out" '
      $acc[0] + {($wf): [ .[].workflow_runs[]? | {id, html_url, event, display_title, head_sha, status, conclusion, created_at} ]}
    ' "$WORK/lane.page" >"$WORK/lane.acc" 2>/dev/null || {
      LAST_ERR="could not parse the runs of $wf"
      return 1
    }
    mv "$WORK/lane.acc" "$out"
  done
}

fetch_lane_annotations() {
  local runs="$1" out="$2" id jid jname ids n act
  : >"$WORK/lane.ann"
  ids="$(jq -r 'map_values(map(select(.status == "completed" and .conclusion != "skipped")) | sort_by(.created_at) | reverse)
    | ([ .[][:3][].id ]) as $newest
    | $newest + ([ [.[][]] | sort_by(.created_at) | reverse | sort_by(.conclusion != "failure") | .[].id ] - $newest) | .[]' "$runs")"
  n="$(grep -c . <<<"$ids")"
  ((n > LANE_READ_LIMIT)) && LANES_PARTIAL=$((n - LANE_READ_LIMIT))
  for id in $(head -n "$LANE_READ_LIMIT" <<<"$ids"); do
    gh_read "$WORK/lane.jobs" api --paginate "repos/$REPO/actions/runs/$id/jobs?per_page=100" || continue
    : >"$WORK/lane.msgs"
    local ok=1
    while IFS=$'\t' read -r jid jname; do
      [[ -n "$jid" ]] || continue
      gh_read "$WORK/lane.one" api "repos/$REPO/check-runs/$jid/annotations?per_page=100" || {
        ok=0
        break
      }
      jq -r '.[]?.message // empty | split("lane-outcome ")
        | if length > 2 then .[0] + "lane-outcome " + (.[1:] | join("lane-outcome-")) else join("lane-outcome ") end' \
        "$WORK/lane.one" >>"$WORK/lane.msgs" 2>/dev/null
      if [[ "$jname" =~ $CALLER_JOB_RE ]] && jq -e 'length > 0' "$WORK/lane.one" >/dev/null 2>&1; then
        act="${BASH_REMATCH[1],,}"
        echo "activity=${act// /-}" >>"$WORK/lane.msgs"
      fi
    done < <(jq -r -s '.[].jobs[]? | [.id, (.name // "")] | @tsv' "$WORK/lane.jobs" 2>/dev/null)
    ((ok)) && jq -R -s -c --arg id "$id" '{($id): .}' "$WORK/lane.msgs" >>"$WORK/lane.ann"
  done
  jq -s 'add // {}' "$WORK/lane.ann" >"$out"
}

print_lanes() {
  local since=$((NOW_EPOCH - LANE_DAYS * 86400)) runs="$WORK/lane-runs.json" ann="$WORK/lane-ann.json" part _parts
  echo "== Lanes, last ${LANE_DAYS}d (runs, failures by class, limit stops, restarts, turn headroom, model usage) =="
  [[ -n "$LANE_OUTCOME_CONTRACT_REF" ]] && echo "  lane-outcome record contract: ${LANE_OUTCOME_CONTRACT_REF//,/ }"
  LANE_WORKFLOWS=()
  if [[ -n "$LANE_WORKFLOWS_ARG" ]]; then
    IFS=',' read -ra _parts <<<"$LANE_WORKFLOWS_ARG"
    for part in "${_parts[@]}"; do
      part="${part//[[:space:]]/}"
      [[ -n "$part" ]] && LANE_WORKFLOWS+=("$part")
    done
  fi
  if [[ -n "$LANE_RUNS_JSON" ]]; then
    runs="$LANE_RUNS_JSON"
    jq -e 'type == "object"' "$runs" >/dev/null 2>&1 || {
      unreadable lanes "--lane-runs-json is not an object"
      return
    }
    ((${#LANE_WORKFLOWS[@]})) || mapfile -t LANE_WORKFLOWS < <(jq -r 'keys[]' "$runs")
    if [[ -n "$LANE_ANNOTATIONS_JSON" ]]; then ann="$LANE_ANNOTATIONS_JSON"; else echo '{}' >"$ann"; fi
    ((${#LANE_WORKFLOWS[@]})) || {
      echo "  no lane workflows found (nothing to report)"
      echo
      return
    }
  elif [[ -z "$REPO" ]]; then
    echo "  (no repo resolved — pass --repo or --lane-runs-json)"
    echo
    return
  else
    if ((${#LANE_WORKFLOWS[@]} == 0)); then
      gh_read "$WORK/lane.wfs" api --paginate "repos/$REPO/actions/workflows?per_page=100" || {
        unreadable lanes "workflow list: $LAST_ERR"
        return
      }
      local wf path
      if [[ -n "$LANE_WORKFLOWS_CONFIG" ]]; then
        IFS=',' read -ra _parts <<<"$LANE_WORKFLOWS_CONFIG"
        for wf in "${_parts[@]}"; do
          jq -s -e --arg wf "$wf" '[ .[].workflows[]?.path | split("/") | last ] | index($wf) != null' "$WORK/lane.wfs" >/dev/null 2>&1 &&
            LANE_WORKFLOWS+=("$wf")
        done
      else
        while IFS= read -r path; do
          if ! gh_read "$WORK/lane.wf" api -H 'Accept: application/vnd.github.raw' \
            "repos/$REPO/contents/.github/workflows/$(urlencode "${path##*/}")"; then
            [[ "$LAST_ERR" == *"HTTP 404"* ]] && continue
            unreadable lanes "workflow $path: $LAST_ERR"
            return
          fi
          grep -Eq "$CLAUDE_ACTION_RE" "$WORK/lane.wf" && LANE_WORKFLOWS+=("${path##*/}")
        done < <(jq -r -s '.[].workflows[]? | select(.state != "deleted") | .path
          | select(test("^\\.github/workflows/[^/]+\\.ya?ml$"))' "$WORK/lane.wfs")
      fi
    fi
    ((${#LANE_WORKFLOWS[@]})) || {
      echo "  no lane workflows found (nothing to report)"
      echo
      return
    }
    fetch_lane_runs "$runs" "$since" || {
      unreadable lanes "$LAST_ERR"
      return
    }
    fetch_lane_annotations "$runs" "$ann"
  fi
  local rows lane_args
  lane_args=(-n -r --argjson since "$since" --slurpfile runs "$runs" --slurpfile ann "$ann"
    --argjson lanes "$(printf '%s\n' "${LANE_WORKFLOWS[@]}" | jq -R . | jq -s .)")
  rows="$(jq "${lane_args[@]}" "$LANES_JQ" 2>&1)" || {
    unreadable lanes "could not parse the lane runs: ${rows%%$'\n'*}"
    return
  }
  echo "$rows"
  ((LANE_RUNS_SHORT)) && echo "  PARTIAL: $LANE_RUNS_SHORT runs not listed: a lane passed the runs search's result cap in one day"
  ((LANES_PARTIAL)) && echo "  PARTIAL: annotations read for $LANE_READ_LIMIT runs, the newest 3 of each lane and then failed runs first; $LANES_PARTIAL more were not read (raise --lane-read-limit)"
  rows="$(jq "${lane_args[@]}" "$KEYS_JQ" 2>&1)" || {
    UNREADABLE=$((UNREADABLE + 1))
    UNREADABLE_NAMES+=(lanes)
    rows="  UNREADABLE: could not parse the lane-outcome records: ${rows%%$'\n'*}"
  }
  [[ -n "$rows" ]] && echo "$rows"
  rows="$(jq "${lane_args[@]}" --argjson days "$LANE_DAYS" "$SPEND_JQ" 2>&1)" || {
    UNREADABLE=$((UNREADABLE + 1))
    UNREADABLE_NAMES+=(lanes)
    rows="  UNREADABLE: could not read the lane spend: ${rows%%$'\n'*}"
  }
  [[ -n "$rows" ]] && echo "$rows"
  rows="$(jq "${lane_args[@]}" --argjson threshold "${MAX_TURNS_HITS:-null}" "$MODELS_JQ" 2>&1)" || {
    unreadable lanes "could not parse the lane records: ${rows%%$'\n'*}"
    return
  }
  echo "$rows"
  echo
}

TOUCH_PAGE_LIMIT=20 # 20 pages of 50 is the search ceiling
TOUCH_TOP=10

# shellcheck disable=SC2016  # GraphQL variables bound by -f, which MUST reach the server unexpanded
TOUCH_QUERY='
    query($search:String!, $since:DateTime!, $endCursor:String) {
      search(query:$search, type:ISSUE, first:50, after:$endCursor) {
        issueCount
        pageInfo { hasNextPage endCursor }
        nodes {
          __typename
          ... on Issue {
            number
            acts: timelineItems(since:$since, first:100, itemTypes:[ISSUE_COMMENT]) {
              pageInfo { hasNextPage }
              nodes { __typename ... on IssueComment { createdAt author { login } body } }
            }
            labels: timelineItems(itemTypes:[LABELED_EVENT, UNLABELED_EVENT], last:100) {
              pageInfo { hasPreviousPage }
              nodes { __typename
                ... on LabeledEvent { createdAt actor { login } label { name } }
                ... on UnlabeledEvent { createdAt actor { login } label { name } } }
            }
            @FIELDS@
          }
          ... on PullRequest {
            number createdAt mergedAt
            touch: timelineItems(first:100, itemTypes:[PULL_REQUEST_COMMIT, PULL_REQUEST_REVIEW, ISSUE_COMMENT]) {
              pageInfo { hasNextPage }
              nodes { __typename
                ... on PullRequestCommit { commit { author { email user { login } } } }
                ... on PullRequestReview { createdAt author { __typename login } }
                ... on IssueComment { createdAt author { __typename login } } }
            }
            acts: timelineItems(since:$since, first:100, itemTypes:[ISSUE_COMMENT, PULL_REQUEST_REVIEW, MERGED_EVENT]) {
              pageInfo { hasNextPage }
              nodes { __typename
                ... on IssueComment { createdAt author { login } body }
                ... on PullRequestReview { createdAt author { login } state }
                ... on MergedEvent { createdAt actor { login } } }
            }
            labels: timelineItems(itemTypes:[LABELED_EVENT, UNLABELED_EVENT], last:100) {
              pageInfo { hasPreviousPage }
              nodes { __typename
                ... on LabeledEvent { createdAt actor { login } label { name } }
                ... on UnlabeledEvent { createdAt actor { login } label { name } } }
            }
          }
        }
      }
    }'

gql_stamp() { local s; s="$(from_epoch "$1")" && printf '%s:%sZ' "${s%Z}" "$2"; }

fetch_touch_pages() {
  local out="$1" start="$2" day_start day_end cursor pages args since fields="" query
  [[ "${STATUS_MODEL:-null}" == null ]] || fields="fields: timelineItems(itemTypes:$STATUS_EVENT_TYPES, last:100) { $STATUS_FIELD_EVENTS }"
  query="${TOUCH_QUERY/@FIELDS@/$fields}"
  [[ -z "$fields" ]] || query+=$'\n'"$STATUS_FRAGMENT"
  since="$(gql_stamp "$start" 00)"
  : >"$out"
  for ((day_start = start; day_start <= NOW_EPOCH; day_start += 86400)); do
    day_end=$((day_start + 86399))
    cursor="" pages=0
    while :; do
      args=(api graphql -f query="$query" -f since="$since"
        -f search="repo:$REPO updated:$(gql_stamp "$day_start" 00)..$(gql_stamp "$day_end" 59)")
      [[ -n "$cursor" ]] && args+=(-f endCursor="$cursor")
      gh_read "$WORK/touch.page" "${args[@]}" || return 1
      cat "$WORK/touch.page" >>"$out"
      pages=$((pages + 1))
      cursor="$(jq -r '.data.search.pageInfo | if .hasNextPage != true then "" elif .endCursor == null then "!" else .endCursor end' \
        "$WORK/touch.page" 2>/dev/null)" || {
        LAST_ERR="could not parse an owner-touch page"
        return 1
      }
      [[ "$cursor" != "!" ]] || {
        LAST_ERR="an owner-touch page reported more results but no cursor to them"
        return 1
      }
      [[ -n "$cursor" ]] || break
      ((pages >= TOUCH_PAGE_LIMIT)) && break
    done
  done
}

fetch_lane_identity() {
  fetch_pipeline || return 1
  awk '/^[^[:space:]#]/ { top = $0 } top ~ /^merge:/ && /^[[:space:]]+agent-identity:/ { sub(/^[^:]*:[[:space:]]*/, ""); sub(/[[:space:]]+#.*$/, ""); gsub(/["'"'"']/, ""); print; exit }' "$WORK/pipeline.yaml"
}

# shellcheck disable=SC2016  # jq program, not shell
TOUCH_JQ='
  def norm: ascii_downcase | sub("\\[bot\\]$"; "");
  def ep: fromdateiso8601;
  def age: if . == null then "unknown" else (. / 86400 | floor) as $d | ((. % 86400) / 3600 | floor) as $h | ((. % 3600) / 60 | floor) as $m
    | if $d > 0 then "\($d)d \($h)h" elif $h > 0 then "\($h)h \($m)m" else "\($m)m" end end;
  def pad($w): tostring | (" " * ([$w - length, 0] | max)) + .;
  def reason($l):
    first($l[] | capture("^- (?:Lane code|Reason): `(?<r>[^`]+)`").r)
    // first($l[1:2][] | capture("^<!-- babysit-merge-(?<r>[a-z0-9-]+) -->").r)
    // first($l[1:2][] | capture("^<!-- work-resolve-issue outcome=(?<r>[a-z]+(-[a-z]+)*)").r)
    // "unspecified";
  def bot($a): ($a.__typename // "") == "Bot" or ($a.login // "" | test("\\[bot\\]$"; "i"))
    or ($a.login // "" | norm) == ($lane | norm);
  def person($a): ($a.login // "") != "" and (bot($a) | not);
  def person_commit($g): if ($g.user.login // "") != "" then person($g.user)
    else ($g.email // "" | test("\\[bot\\]@users\\.noreply\\.github\\.com$"; "i") | not) end;
  ($op | norm) as $op
  | ($trusted | map(norm)) as $trusted
  | [ .. | objects | select(has("data")) | .data.search.nodes[]? | select(type == "object" and .number != null) ]
  | unique_by(.number) as $items
  | [ $items[] as $n
      | (if $n.__typename == "PullRequest" then "PR" else "issue" end) as $kind
      | ([ $n.labels.nodes[]? | select(.createdAt != null) ]
         + if $m == null then [] else [ $n.fields.nodes | try synthetic catch error("#\($n.number): \(.)") ] end) as $lab
      | ( ( $n.acts.nodes[]? | select(.createdAt != null and (.createdAt | ep) >= $start)
            | .createdAt as $at
            | (((.actor // .author) // {}).login // "" | norm) as $who
            | if .__typename == "PullRequestReview" and .state == "APPROVED" and $who == $op then {k: "approve"}
              elif .__typename == "MergedEvent" and $who == $op then {k: "merge"}
              elif .__typename == "IssueComment" and ($trusted | index($who)) != null
                   and ((.body // "") | split("\n")[0] | rtrimstr("\r") | test("^<!-- work-items:escalation lane=[^ ]+ kind=[^ ]+ -->$"))
                then ((.body | split("\n") | map(rtrimstr("\r"))) as $l
                  | ($l[0] | capture("lane=(?<lane>[^ ]+) kind=(?<kind>[^ ]+)")) as $m
                  | {k: "escalate", lane: $m.lane, ekind: $m.kind, reason: reason($l)})
              else empty end
            | . + {n: $n.number, kind: $kind, at: $at} ),
          ( $lab[] | select((.createdAt | ep) >= $start)
            | . as $e
            | ((.actor // {}).login // "" | norm) as $who
            | if .label.name == $hold and .__typename == "LabeledEvent" then {k: "hold-on"}
              elif .label.name == $hold and .__typename == "UnlabeledEvent" then
                {k: "hold-off", op: ($who == $op),
                 wait: ([ $lab[] | select(.__typename == "LabeledEvent" and .label.name == $hold and (.createdAt | ep) <= ($e.createdAt | ep)) | .createdAt | ep ]
                        | max | if . == null then null else ($e.createdAt | ep) - . end)}
              elif .label.name == "do-not-merge" and .__typename == "UnlabeledEvent" and $who == $op then {k: "dnm-lift"}
              else empty end
            | . + {n: $n.number, kind: $kind, at: $e.createdAt} ) ) ] as $ev
  | ([ range($start; $now + 1; 86400) | todate[0:10] ]) as $days
  | ["approve", "merge", "dnm-lift", "hold-on", "hold-off", "escalate"] as $cols
  | "  operator: \($op); escalations trusted from: \($trusted | unique | join(", "))",
    "  day         " + ($cols | map(pad(9)) | join("")) + "  hold-off by operator",
    ( $days[] as $d | [ $ev[] | select(.at[0:10] == $d) ] as $de
      | "  \($d)  " + ($cols | map(. as $c | [ $de[] | select(.k == $c) ] | length | pad(9)) | join(""))
        + ([ $de[] | select(.k == "hold-off" and .op) ] | length | pad(22)) ),
    ( [ $items[] | select(.__typename == "PullRequest" and .mergedAt != null and (.mergedAt | ep) >= $start)
        | (.mergedAt | ep) as $end | ((.createdAt // .mergedAt) | ep) as $open
        | ([ .touch.nodes[]? | select(if .__typename == "PullRequestCommit" then person_commit(.commit.author // {})
               else .createdAt != null and (.createdAt | ep) >= $open and (.createdAt | ep) <= $end and person(.author // {}) end) ]
           | length > 0) as $touched
        | {n: .number, touched: $touched, partial: (($touched | not) and .touch.pageInfo.hasNextPage == true)} ] as $mr
      | if ($mr | length) == 0 then "  merged with no human touch: no pull request merged in the window"
        else ([ $mr[] | select(.touched | not) ] | length) as $u
          | "  merged with no human touch: \($u) of \($mr | length) pull requests merged in the window (\($u * 100 / ($mr | length) | floor)%)",
            ( [ $mr[] | select(.partial) | "#\(.n)" ] as $p
              | if ($p | length) > 0 then "  PARTIAL: more than 100 commits, reviews and comments on \($p | join(" ")); read as untouched from the first 100" else empty end )
        end ),
    "  note: a touch is a commit on the pull request, or a review or comment from its open to its merge, by a person; a Bot account, a login ending in [bot] and the lane identity are not people, the operator login is, and the merge itself is not a touch",
    ( [ $ev[] | select(.k == "hold-off") ] as $off
      | if ($off | length) == 0 then "  hold waits: no hold lifted in the window"
        else ([ $off[] | .wait | select(. != null) ] | sort) as $w
          | "  hold waits (\($hold) applied to lifted): n=\($w | length)"
            + (if ($w | length) > 0 then ", median \($w[(($w | length) - 1) / 2 | floor] | age), max \($w[-1] | age)" else "" end)
            + (if ($off | length) > ($w | length) then ", \(($off | length) - ($w | length)) with no apply event read" else "" end)
        end ),
    ( [ $ev[] | select(.k == "escalate") ] as $es
      | if ($es | length) == 0 then "  escalations: none in the window"
        else "  escalations by lane, kind and reason:",
          ( $es | group_by([.lane, .ekind, .reason]) | map({c: length, key: "\(.[0].lane) \(.[0].ekind) \(.[0].reason)"})
            | sort_by(-.c, .key)[] | "    \(.c | pad(4))  \(.key)" )
        end ),
    ( [ $ev[] | select(.k != "hold-on" and (.k != "hold-off" or .op)) ] | group_by(.n)
      | map({n: .[0].n, kind: .[0].kind, c: length, parts: (group_by(.k) | map("\(.[0].k) \(length)") | join(", "))})
      | sort_by(-.c, .n) as $top
      | if ($top | length) == 0 then empty
        else "  most-touched items (operator actions and escalations):",
          ( $top[:$cap][] | "    #\(.n) \(.kind)  \(.parts)" ),
          ( if ($top | length) > $cap then "  PARTIAL: \($top | length) items touched; showing the top \($cap)" else empty end )
        end ),
    ( [ $items[] | select(.acts.pageInfo.hasNextPage == true
          or (.labels.pageInfo.hasPreviousPage == true
              and ([ .labels.nodes[]? | .createdAt | select(. != null) | ep ] | min // $start) >= $start))
        | "#\(.number)" ] as $t
      | if ($t | length) > 0 then "  PARTIAL: more than 100 events in the window on \($t | join(" ")); counts on those may be low" else empty end ),
    "  note: approve, merge, dnm-lift and hold-off by operator count actions under the operator login, including any agent session that holds it"
'

print_touches() {
  echo "== Owner touches (last ${TOUCH_DAYS} UTC days) =="
  local pages="$WORK/touch.pages" op lane_id trusted out start
  start=$((NOW_EPOCH - NOW_EPOCH % 86400 - (TOUCH_DAYS - 1) * 86400))
  if [[ -n "$STATUS_JSON" || (-z "$TOUCH_JSON" && -n "$REPO" && "$TRANSPORT" != rest) ]]; then
    status_model || {
      unreadable touches "$LAST_ERR"
      return
    }
  fi
  if [[ -n "$TOUCH_JSON" ]]; then
    local err
    err="$(body_error "$TOUCH_JSON")"
    if [[ -n "$err" ]]; then
      unreadable touches "$err"
      return
    fi
    jq -e 'type == "object"' "$TOUCH_JSON" >/dev/null 2>&1 || {
      unreadable touches "--touch-json is not an object {owner, laneIdentity, pages}"
      return
    }
    op="${OWNER_LOGIN_ARG:-$(jq -r '.owner // empty' "$TOUCH_JSON")}"
    lane_id="${LANE_IDENTITY_ARG:-$(jq -r '.laneIdentity // empty' "$TOUCH_JSON")}"
    jq -c '.pages // []' "$TOUCH_JSON" >"$pages"
  elif [[ -z "$REPO" ]]; then
    echo "  (no repo resolved — pass --repo or --touch-json)"
    echo
    return
  elif [[ "$TRANSPORT" == "rest" ]]; then
    unreadable touches "timeline events need GraphQL, which this session does not serve"
    return
  else
    op="$OWNER_LOGIN_ARG"
    if [[ -z "$op" ]]; then
      gh_read "$WORK/touch.user" api user -q .login || {
        unreadable touches "operator login: $LAST_ERR"
        return
      }
      op="$(tr -d '\r\n' <"$WORK/touch.user")"
    fi
    lane_id="$LANE_IDENTITY_ARG"
    if [[ -z "$lane_id" ]]; then
      lane_id="$(fetch_lane_identity)" || {
        unreadable touches "lane identity (docs/conventions/pr-pipeline.yaml): $LAST_ERR"
        return
      }
    fi
    fetch_touch_pages "$pages" "$start" || {
      graphql_blocked "$LAST_ERR" && TRANSPORT="rest"
      unreadable touches "$LAST_ERR"
      return
    }
  fi
  [[ -n "$op" ]] || {
    unreadable touches "no operator login (pass --owner-login)"
    return
  }
  trusted="$(jq -cn --arg a "$op" --arg b "$lane_id" '[$a, $b] | map(select(length > 0))')"
  out="$(jq -s -r --arg op "$op" --arg lane "$lane_id" --argjson trusted "$trusted" --arg hold "$HOLD_LABEL" --argjson m "${STATUS_MODEL:-null}" \
    --argjson start "$start" --argjson now "$NOW_EPOCH" --argjson cap "$TOUCH_TOP" "$STATUS_DEFS$TOUCH_JQ" "$pages" 2>&1)" || {
    unreadable touches "could not parse the owner-touch pages: ${out%%$'\n'*}"
    return
  }
  echo "$out"
  if jq -s -e '[ .. | objects | select(has("data")) | .data.search | objects | select((.issueCount // 0) > 1000) ] | length > 0' \
    "$pages" >/dev/null 2>&1; then
    echo "  PARTIAL: a day's search reached its 1,000-result ceiling; that day's counts may be low"
  fi
  echo
}

COST_ROWS=()
COST_PARTIAL=()
COST_HAS_DATA=0
COST_LOST=0
AZ_SUB_ARGS=()
[[ -n "$SUBSCRIPTION_ARG" ]] && AZ_SUB_ARGS=(--subscription "$SUBSCRIPTION_ARG")
COST_QUERY_BODY='{"type":"ActualCost","timeframe":"MonthToDate","dataset":{"granularity":"Daily","aggregation":{"cost":{"name":"Cost","function":"Sum"}},"grouping":[{"type":"Dimension","name":"ServiceName"},{"type":"Dimension","name":"MeterCategory"}]}}'
AZ_ACTIVITY_LIMIT=1000
AZ_QUERY_PAGE_LIMIT=20
COST_WRITE_OPS='["microsoft.security/pricings/write","microsoft.authorization/policyassignments/write","microsoft.authorization/roleassignments/write"]'
COST_MONTH="$(from_epoch "$NOW_EPOCH")"
COST_MONTH="${COST_MONTH:0:7}"
COST_ORG="${ORG_ARG:-${REPO%%/*}}"
COST_ORG_ERR=""
if [[ -n "$COST_ORG" ]] && ! is_owner "$COST_ORG"; then
  COST_ORG_ERR="${COST_ORG//[[:cntrl:]]/ } is not a GitHub owner name"
  COST_ORG=""
fi
GH_COST_LIVE=$(((ANY_LIVE || ORG_FLAG) && ${#COST_ORG} > 0))
AZ_COST_LIVE=$((ANY_LIVE || ORG_FLAG || SUBSCRIPTION_FLAG))
COST_DATA_DATE="usage data date unread"
COST_YEAR=$((10#${COST_MONTH:0:4}))
COST_MON=$((10#${COST_MONTH:5:2}))
COST_NEXT="$((COST_YEAR + COST_MON / 12))-$(printf '%02d' $((COST_MON % 12 + 1)))"
COST_HOURS=$((($(to_epoch "${COST_NEXT}-01T00:00Z") - $(to_epoch "${COST_MONTH}-01T00:00Z")) / 3600))
csv_json() { jq -cn --arg s "$1" '$s | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) | map(select(length > 0))'; }
REQUIRED_BUDGETS_JSON="$(csv_json "$REQUIRED_BUDGETS_ARG")"
ALLOWED_COLLABORATORS_JSON="$(csv_json "$ALLOWED_COLLABORATORS_ARG")"
ANOMALY_ALERT_JSON="$(jq -cn --arg a "$ANOMALY_ALERT" 'if $a == "" then null else $a end')"
COST_READ_AT="$(utc_stamp "$NOW_EPOCH")"
USAGE_LABELS=("usage $COST_MONTH" "Actions minutes $COST_MONTH, private repos" "Actions storage $COST_MONTH, private repos")
SCAN_LABELS=("collaborators" "fork-triggered workflows")
ADMIN_FIX="org admin needed: run gh auth login with an org admin account"
AZ_LABELS=("budgets" "budget and anomaly alerts" "Defender plans" "Defender charges, month to date"
  "Log Analytics" "activity, last 24h" "secure score" "Advisor security" "Advisor cost")
LA_PEAK_QUERY='Usage | where TimeGenerated > ago(31d) | where IsBillable == true | summarize GB = sum(Quantity) / 1000.0 by Day = bin(TimeGenerated, 1d) | top 1 by GB desc'

# shellcheck disable=SC2016  # $month, $ops and $label are jq variables bound by cost_jq
COST_DEFS='
  def money: (. * 100 | round) / 100 | tostring;
  def num: if type == "string" then tonumber elif type == "number" then . else error("not a number") end;
  def list: if type == "array" then . else error("not a list") end;
  def str: if type == "string" then . else error("not a string") end;
  def bool: if type == "boolean" then . else error("not a boolean") end;
'
# shellcheck disable=SC2016  # jq variables, as above
USAGE_JQ='
  .usageItems | list
  | map(select(.date | str | startswith($month))) | group_by(.product)
  | if length == 0 then ["OK", "GitHub", "usage \($month)", "no metered usage"]
    else .[] | (map(.netAmount | num) | add) as $net
      | [(if $net > 0 then "ALERT" else "OK" end), "GitHub", "usage \($month) \(.[0].product)", "net \($net | money)"]
    end'
# shellcheck disable=SC2016  # jq variables, as above
INCLUDED_JQ='
  (if .repos == null then {} else (.repos | list | map({key: (.name | str), value: (.visibility | str)}) | from_entries) end) as $vis
  | (if .repos == null then "; repo visibility unread, every repo counted as private" else "" end) as $note
  | [.usage.usageItems | list | .[]
      | select(.date | str | startswith($month)) | select((.product | str) == "actions")
      | select(($vis[.repositoryName // ""] // "private") != "public")] as $private
  | ($private | map(select((.unitType | str) == "Minutes") | .quantity | num) | add // 0) as $minutes
  | ($private | map(select((.unitType | str) == "GigabyteHours") | .quantity | num) | add // 0) as $gb_hours
  | def against($used; $included; $unit; $label; $flag):
      if $included == null
      then ["INFO", "GitHub", $label, "\($used | money) \($unit) used; included amount not configured (pass \($flag))\($note)"]
      else (if $included > 0 then $used * 100 / $included else 100 end) as $pct
        | [(if $pct >= $pct_alert then "ALERT" else "OK" end), "GitHub", $label,
           "\($used | money) of \($included | money) \($unit) included (\($pct | round)%)\($note)"]
      end;
    against($minutes; $inc_minutes; "minutes"; "Actions minutes \($month), private repos"; "--actions-included-minutes"),
    against($gb_hours; (if $inc_gb == null then null else $inc_gb * $hours end); "GB-hours"; "Actions storage \($month), private repos";
      "--actions-included-storage-gb")'
# shellcheck disable=SC2016  # jq variables, as above
SCAN_JQ='
  (.admins | list | map(.login? // . | str)) as $admins
  | (.repos | list) as $all_repos
  | [$all_repos[] | select(.archived != true)] as $repos
  | (.partial // 0 | num) as $partial
  | ([$repos[].workflows | list | length] | add // 0) as $files
  | [$repos[] | .name as $r | .collaborators | list | .[] | (.login? // . | str)
      | . as $who | select(($admins + $allowed) | index($who) | not) | {r: $r, who: $who}] as $extra
  | [$repos[] | (.name | str) as $r | .workflows | list | .[]
      | (.path | str) as $path
      | (.text | str | split("\n") | map(select(test("^[[:space:]]*#") | not))) as $lines
      | ([$lines[] | select(test("(^|[[:space:],\\[{\"\u0027])(pull_request_target|workflow_run)[\"\u0027]?([[:space:]]*:|[[:space:]]*[\\]},]|[[:space:]]*$|[[:space:]]+#)"))
          | match("pull_request_target|workflow_run").string] | unique) as $events
      | ([$lines[] | match("secrets\\.([A-Za-z0-9_]*_CLAUDE_[A-Za-z0-9_]*)|secrets\\[[[:space:]]*.([A-Za-z0-9_]*_CLAUDE_[A-Za-z0-9_]*).[[:space:]]*\\]"; "gi")
          | .captures[] | .string // empty] | unique) as $named
      | ([$lines[]
          | (if test("(^|[[:space:],{])secrets[[:space:]]*:[[:space:]]*[\"\u0027]?inherit[\"\u0027]?([[:space:],}#]|$)"; "i") then "every secret (secrets: inherit)" else empty end),
            (if test("tojson[[:space:]]*\\([[:space:]]*secrets[[:space:]]*\\)"; "i") then "every secret (toJSON(secrets))" else empty end),
            (if test("secrets[[:space:]]*\\[[[:space:]]*[^[:space:]\\]\"\u0027]"; "i") then "a secret by computed name (secrets[...])" else empty end)]
          | unique) as $every
      | ($named + $every) as $secrets
      | select(($events | length) > 0 and ($secrets | length) > 0)
      | {r: $r, path: $path, events: $events, secrets: $secrets}] as $hits
  | if ($all_repos | length) == 0
    then (["collaborators", "fork-triggered workflows"][] as $l
          | ["UNREADABLE", "GitHub", $l, "the org scan listed 0 repos; check that gh auth status can read the org\u0027s repos"])
    else
      (if ($extra | length) == 0
       then [["OK", "GitHub", "collaborators", "no direct collaborator besides org admins on \($repos | length) repos"]]
       else [$extra[] | ["ALERT", "GitHub", "collaborators", "\(.r): direct collaborator \(.who)"]] end)
      + [$hits[] | ["ALERT", "GitHub", "fork-triggered workflows", "\(.r) \(.path): \(.events | join(", ")) reads \(.secrets | join(", "))"]]
      + (if $partial > 0
         then [["UNREADABLE", "GitHub", "fork-triggered workflows", "read \($files) workflow files on \($repos | length) repos; \($partial) more not read (raise --workflow-read-limit)"]]
         elif ($hits | length) == 0
         then [["OK", "GitHub", "fork-triggered workflows", "none reads a _CLAUDE_ secret or passes every secret (\($files) files on \($repos | length) repos)"]]
         else [] end)
      | .[]
    end'
# shellcheck disable=SC2016  # jq variables, as above
BUDGETS_JQ='
  .budgets | list
  | if length == 0 then ["INFO", "GitHub", "budgets", "none set"]
    else .[] | (.budget_amount | num) as $amount | (.prevent_further_usage | bool) as $stop
      | [(if $amount > 0 or ($stop | not) then "ALERT" else "OK" end), "GitHub",
         "budget \(.budget_product_sku // .budget_type // .id)",
         "amount \($amount | money), stop at limit \(if $stop then "on" else "off" end)"]
    end'
# shellcheck disable=SC2016  # jq variables, as above
AZ_BUDGETS_JQ='
  .value | list
  | if length == 0 then ["INFO", "Azure", "budgets", "none on this subscription"]
    else .[] | .name as $name | .properties
      | (.currentSpend.amount | num) as $spent | (.amount | num) as $cap
      | (.forecastSpend.amount | num) as $forecast | ($forecast_alert // $cap) as $limit
      | [(if $spent >= $cap or $forecast > $limit then "ALERT" else "OK" end), "Azure", "budget \($name)",
         "spent \($spent | money), forecast \($forecast | money) (alert above \($limit | money)), of \($cap | money) \(.currentSpend.unit | str); \($data_date); read \($read_at)"]
    end'
# shellcheck disable=SC2016  # jq variables, as above
ALERTS_JQ='
  ((.budgets.value | list | map({key: (.name | str), value: .properties})) | from_entries) as $budgets
  | (.actions.value | list) as $actions
  | ($now + $days * 86400) as $horizon
  | def ends($end; $what):
      ($end | str | sub("\\.[0-9]+"; "") | fromdateiso8601) as $e
      | if $e <= $horizon then ["ALERT", "Azure", "budget and anomaly alerts", "\($what) ends \($end[0:10]), within \($days) days"]
        else ["OK", "Azure", "budget and anomaly alerts", "\($what) ends \($end[0:10])"] end;
    (if ($required | length) == 0 then ["INFO", "Azure", "budget and anomaly alerts", "no required budgets named (pass --required-budgets)"]
     else $required[] as $b
       | if $budgets[$b] == null then ["ALERT", "Azure", "budget and anomaly alerts", "budget \($b) is missing"]
         else ends($budgets[$b].timePeriod.endDate; "budget \($b)") end
     end),
    ([$actions[] | select(if $anomaly != null then .name == $anomaly else (.kind | str) == "InsightAlert" end)] as $found
     | if ($found | length) == 0
       then ["ALERT", "Azure", "budget and anomaly alerts", "anomaly alert \($anomaly // "(any)") is missing"]
       else $found[] | .name as $n
         | if (.properties.status | str) != "Enabled"
           then ["ALERT", "Azure", "budget and anomaly alerts", "anomaly alert \($n) is \(.properties.status)"]
           else ends(.properties.schedule.endDate; "anomaly alert \($n)") end
       end)'
# shellcheck disable=SC2016  # jq variables, as above
LA_JQ='
  .ws as $ws | ($ws.workspaceCapping.dailyQuotaGb | num) as $cap
  | (.rows | list | map(.GB | num) | max // 0) as $peak
  | (.rows | list | map(.Day | str) | first // "none") as $day
  | if $cap < 0 then ["ALERT", "Azure", "Log Analytics \($ws.name | str)", "no daily cap; peak \($peak | money) GB on \($day[0:10])"]
    else ($peak * 100 / $cap) as $pct
      | [(if $pct >= $log_pct_alert then "ALERT" else "OK" end), "Azure", "Log Analytics \($ws.name | str)",
         "peak \($peak | money) GB on \($day[0:10]) of a \($cap | money) GB daily cap (\($pct | round)%)"]
    end'
# shellcheck disable=SC2016  # jq variables, as above
PRICINGS_JQ='
  (if type == "object" then .value else . end) | list
  | map(select((.pricingTier // "") != "Free")) as $paid
  | if ($paid | length) > 0
    then ["INFO", "Azure", "Defender plans", "not Free: " + ($paid | map("\(.name) (\(.pricingTier // "no tier"))") | join(", "))]
    else ["INFO", "Azure", "Defender plans", "\(length) plans, all Free"] end'
# shellcheck disable=SC2016  # jq variables, as above
CHARGES_JQ='
  .properties as $p
  | ($p.columns | list | map(.name | ascii_downcase)) as $c
  | ($c | index("cost")) as $ic | ($c | index("servicename")) as $is
  | ($c | index("metercategory")) as $im | ($c | index("currency")) as $iu
  | if $ic == null or $is == null or $im == null then error("missing columns") else . end
  | [ $p.rows | list | .[]
      | ([.[$is], .[$im]] | map(if . == null or type == "string" then . // "" else error("a service or meter category is not a string") end)) as $names
      | if ($names | all(. == "")) then error("a cost row names no service or meter category") else . end
      | select($names | join(" ") | ascii_downcase | test("defender|security center")) ]
  | (map(.[$ic] | num) | add // 0) as $cost
  | [(if $cost > 0 then "ALERT" else "OK" end), "Azure", $label,
     (if length == 0 then "no Defender cost rows"
      else ("\($cost | money) \(if $iu != null then .[0][$iu] // "" else "" end)" | rtrimstr(" ")) end)]'
# shellcheck disable=SC2016  # jq variables, as above
ACTIVITY_JQ='
  list
  | map(select((.operationName.value | str | if . == "" then error("an event names no operation") else ascii_downcase end) as $op | $ops | index($op)))
  | if length == 0 then ["OK", "Azure", "activity, last 24h", "no Defender plan, policy assignment or role assignment writes"]
    else group_by(.operationName.value | ascii_downcase)[] | max_by(.eventTimestamp // "") as $last
      | ["ALERT", "Azure", "activity, last 24h",
         "\($last.operationName.value): \(length) event(s), latest \(($last.eventTimestamp // "")[0:16])Z UTC by \($last.caller // "unknown")"]
    end'
SCORES_JQ='
  list
  | if length == 0 then ["INFO", "Azure", "secure score", "none reported"]
    else .[] | ["INFO", "Azure", "secure score", "\(.displayName // .name) \(.current | num | money)/\(.max | num | money)"] end'
# shellcheck disable=SC2016  # jq variables, as above
ADVISOR_JQ='list | ["INFO", "Azure", $label, "\(length) recommendation(s)"]'

cost_row() {
  local f row=""
  for f in "$1" "$2" "$3" "$4"; do
    row+="${row:+$'\x1f'}${f//[[:cntrl:]]/ }"
  done
  COST_ROWS+=("$row")
}

cost_jq() {
  local rows
  rows="$(jq -r --arg month "$COST_MONTH" --argjson ops "$COST_WRITE_OPS" --arg label "$3" \
    --argjson pct_alert "$USAGE_ALERT_PERCENT" --argjson log_pct_alert "$LOG_CAP_ALERT_PERCENT" \
    --argjson inc_minutes "${ACTIONS_INCLUDED_MINUTES:-null}" --argjson inc_gb "${ACTIONS_INCLUDED_STORAGE_GB:-null}" \
    --argjson hours "$COST_HOURS" --argjson forecast_alert "${FORECAST_ALERT:-null}" \
    --arg read_at "$COST_READ_AT" --argjson now "$NOW_EPOCH" --argjson days "$EXPIRY_DAYS" \
    --argjson required "$REQUIRED_BUDGETS_JSON" --argjson anomaly "$ANOMALY_ALERT_JSON" \
    --argjson allowed "$ALLOWED_COLLABORATORS_JSON" --arg data_date "$COST_DATA_DATE" \
    "$COST_DEFS $2"' | map(tostring | gsub("[[:cntrl:]]"; " ")) | join("\u001f")' "$1" 2>/dev/null)" || return 1
  [[ -n "$rows" ]] || return 1
  mapfile -t -O "${#COST_ROWS[@]}" COST_ROWS <<<"$rows"
}

billing_read() {
  local out="$1" fixture="$2"
  LAST_ERR=""
  if [[ -n "$fixture" ]]; then
    cp "$fixture" "$out"
    LAST_ERR="$(body_error "$out")"
  elif ((!GH_COST_LIVE)); then
    return 3
  elif ! have gh; then
    LAST_ERR="gh not installed"
    return 1
  else
    gh_read "$out" api "$3"
  fi
  [[ -n "$LAST_ERR" ]] || return 0
  if ! graphql_blocked "$LAST_ERR" &&
    { [[ "$LAST_ERR" == *"HTTP 403"* ]] || jq -e '.status == "403"' "$out" >/dev/null 2>&1; } &&
    grep -qiE 'admin|billing manager|organization owner' <<<"$LAST_ERR"; then
    return 2
  fi
  return 1
}

fetch_org_scan() {
  local out="$1" repo branch archived name files=0 skipped=0
  rest_paginate_array "$WORK/org-repos" "orgs/$COST_ORG/repos?per_page=100&type=all" || return 1
  rest_paginate_array "$WORK/org-admins" "orgs/$COST_ORG/members?role=admin&per_page=100" || return 1
  : >"$WORK/scan-repos"
  while IFS=$'\t' read -r repo branch archived; do
    jq -n --slurpfile repos "$WORK/org-repos" --arg r "$repo" \
      '$repos[0][] | select(.name == $r) | {name, visibility, archived, collaborators: [], workflows: []}' >"$WORK/scan-repo"
    if [[ "$archived" != true ]]; then
      rest_paginate_array "$WORK/collab" "repos/$COST_ORG/$repo/collaborators?affiliation=direct&per_page=100" || {
        LAST_ERR="$repo collaborators: $LAST_ERR"
        return 1
      }
      jq --slurpfile c "$WORK/collab" '.collaborators = [$c[0][].login]' "$WORK/scan-repo" >"$WORK/scan-repo.next" &&
        mv "$WORK/scan-repo.next" "$WORK/scan-repo"
      if gh_read "$WORK/wf-list" api "repos/$COST_ORG/$repo/contents/.github/workflows?ref=$(urlencode "$branch")"; then
        while IFS= read -r name; do
          if ((files >= WORKFLOW_READ_LIMIT)); then
            skipped=$((skipped + 1))
            continue
          fi
          gh_read "$WORK/wf" api -H "Accept: application/vnd.github.raw" \
            "repos/$COST_ORG/$repo/contents/.github/workflows/$(urlencode "$name")?ref=$(urlencode "$branch")" || {
            LAST_ERR="$repo $name: $LAST_ERR"
            return 1
          }
          files=$((files + 1))
          jq --arg p ".github/workflows/$name" --rawfile t "$WORK/wf" '.workflows += [{path: $p, text: $t}]' "$WORK/scan-repo" \
            >"$WORK/scan-repo.next" && mv "$WORK/scan-repo.next" "$WORK/scan-repo"
        done < <(jq -r '.[]? | select(.type == "file" and (.name | test("\\.ya?ml$"))) | .name' "$WORK/wf-list")
      elif [[ "$LAST_ERR" != *"HTTP 404"* ]]; then
        LAST_ERR="$repo workflows: $LAST_ERR"
        return 1
      fi
    fi
    cat "$WORK/scan-repo" >>"$WORK/scan-repos"
  done < <(jq -r '.[] | [.name, (.default_branch // "main"), (.archived | tostring)] | @tsv' "$WORK/org-repos")
  jq -n --slurpfile admins "$WORK/org-admins" --slurpfile repos "$WORK/scan-repos" --argjson partial "$skipped" \
    '{admins: [$admins[0][].login], repos: $repos, partial: $partial}' >"$out"
}

cost_unreadable() {
  local source="$1" reason="$2" label
  shift 2
  for label in "$@"; do
    cost_row UNREADABLE "$source" "$label" "$reason"
  done
}

cost_gh_unread_reason() {
  if [[ -n "$COST_ORG_ERR" ]]; then
    printf '%s; pass --org' "$COST_ORG_ERR"
  elif [[ -z "$COST_ORG" ]]; then
    printf 'no org resolved; pass --org'
  else
    printf 'not read live in a fixture run; pass --org or the billing and org-scan fixtures'
  fi
}

cost_github() {
  local usage="$WORK/billing-usage.json" budgets="$WORK/billing-budgets.json" scan="$WORK/org-scan.json" rc scanned=0
  if [[ -z "$BILLING_USAGE_JSON$BILLING_BUDGETS_JSON$ORG_SCAN_JSON" ]] && ((!GH_COST_LIVE)); then
    cost_unreadable GitHub "$(cost_gh_unread_reason)" "${USAGE_LABELS[@]}" budgets "${SCAN_LABELS[@]}"
    return
  fi
  if [[ -n "$ORG_SCAN_JSON" ]]; then
    cp "$ORG_SCAN_JSON" "$scan" && scanned=1
  elif ((GH_COST_LIVE)) && have gh; then
    fetch_org_scan "$scan" && scanned=1
  elif ((GH_COST_LIVE)); then
    LAST_ERR="gh not installed; install gh"
  else
    LAST_ERR="$(cost_gh_unread_reason)"
  fi
  local scan_err="$LAST_ERR"
  billing_read "$usage" "$BILLING_USAGE_JSON" "orgs/$COST_ORG/settings/billing/usage?year=${COST_MONTH:0:4}&month=$((10#${COST_MONTH:5:2}))"
  rc=$?
  case $rc in
  0)
    cost_jq "$usage" "$USAGE_JQ" "" || cost_row UNREADABLE GitHub "usage $COST_MONTH" "could not parse the billing usage"
    if ((scanned)); then
      jq -n --slurpfile u "$usage" --slurpfile s "$scan" '{usage: $u[0], repos: $s[0].repos}' >"$WORK/included.json"
    else
      jq -n --slurpfile u "$usage" '{usage: $u[0], repos: null}' >"$WORK/included.json"
    fi
    cost_jq "$WORK/included.json" "$INCLUDED_JQ" "" ||
      cost_unreadable GitHub "could not parse the billing usage" "${USAGE_LABELS[@]:1}"
    ;;
  1) cost_unreadable GitHub "$LAST_ERR" "${USAGE_LABELS[@]}" ;;
  2) cost_unreadable GitHub "$ADMIN_FIX" "${USAGE_LABELS[@]}" ;;
  *) cost_unreadable GitHub "$(cost_gh_unread_reason)" "${USAGE_LABELS[@]}" ;;
  esac
  billing_read "$budgets" "$BILLING_BUDGETS_JSON" "orgs/$COST_ORG/settings/billing/budgets?per_page=100"
  rc=$?
  case $rc in
  0)
    cost_jq "$budgets" "$BUDGETS_JQ" "" || cost_row UNREADABLE GitHub "budgets" "could not parse the billing budgets"
    jq -e '.has_next_page == true' "$budgets" >/dev/null 2>&1 &&
      COST_PARTIAL+=("GitHub budgets: more than one page; the rest were not read")
    ;;
  1) cost_row UNREADABLE GitHub "budgets" "$LAST_ERR" ;;
  2) cost_row UNREADABLE GitHub "budgets" "$ADMIN_FIX" ;;
  *) cost_row UNREADABLE GitHub "budgets" "$(cost_gh_unread_reason)" ;;
  esac
  if ! { ((scanned)) && cost_jq "$scan" "$SCAN_JQ" ""; }; then
    ((scanned)) && scan_err="could not parse the org scan"
    cost_unreadable GitHub "$scan_err" "${SCAN_LABELS[@]}"
  fi
}

az_read() {
  local out="$1" key="$2" rc
  shift 2
  LAST_ERR=""
  if [[ -n "$AZURE_JSON" ]]; then
    jq -e --arg k "$key" 'type == "object" and getpath($k | split("/")) != null' "$AZURE_JSON" >/dev/null 2>&1 || {
      LAST_ERR="no $key in --azure-json"
      return 1
    }
    jq --arg k "$key" 'getpath($k | split("/"))' "$AZURE_JSON" >"$out"
    return 0
  fi
  have az || {
    LAST_ERR="az not installed"
    return 1
  }
  : >"$ERR_FILE"
  WSLENV="${WSLENV:+$WSLENV:}AZURE_EXTENSION_USE_DYNAMIC_INSTALL" AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no az "$@" "${AZ_SUB_ARGS[@]}" --only-show-errors -o json >"$out" 2>"$ERR_FILE" </dev/null
  rc=$?
  if ((rc != 0)); then
    LAST_ERR="$(grep -m1 -v '^[[:space:]]*$' "$ERR_FILE" 2>/dev/null)"
    LAST_ERR="${LAST_ERR#ERROR: }"
    [[ -n "$LAST_ERR" ]] || LAST_ERR="az exited $rc"
    return 1
  fi
}

az_check() {
  local key="$1" label="$2" prog="$3" out="$WORK/az-$1.json"
  shift 3
  if az_read "$out" "$key" "$@"; then
    cost_jq "$out" "$prog" "$label" && return
    LAST_ERR="could not parse the $key response"
  fi
  cost_row UNREADABLE Azure "$label" "$LAST_ERR"
}

az_unreadable() {
  cost_unreadable Azure "$1" "subscription${SUBSCRIPTION_ARG:+ $SUBSCRIPTION_ARG}" "${AZ_LABELS[@]}"
}

cost_query() {
  local out="$WORK/az-defenderCost.json" page=1 next prefix="${1%%\?*}?" lower path
  COST_QUERY_ERR=""
  az_read "$out" defenderCost rest --method post --url "$1" --body "$COST_QUERY_BODY" || {
    COST_QUERY_ERR="$LAST_ERR"
    return 1
  }
  cp "$out" "$WORK/az-cq-1.json"
  while next="$(jq -r '.properties.nextLink // empty' "$WORK/az-cq-$page.json" 2>/dev/null)" && [[ -n "$next" ]]; do
    lower="${next,,}"
    path="${lower%%\?*}"
    if [[ "$next" == *[![:ascii:]]* || "$lower" != "${prefix,,}"* || "${path#https://}" == *//* || "$path" == *..* ||
      "$lower" == *\\* || "$path" == *%2e* || "$path" == *%2f* || "$lower" == *[[:cntrl:]]* ]]; then
      COST_QUERY_ERR="the cost query's next page is not the query endpoint; it was not read"
      return 1
    fi
    if ((page >= AZ_QUERY_PAGE_LIMIT)); then
      COST_PARTIAL+=("Azure cost query: the read reached its $AZ_QUERY_PAGE_LIMIT-page cap; the rest were not read")
      return 0
    fi
    page=$((page + 1))
    az_read "$WORK/az-cq-$page.json" "defenderCost_$page" rest --method post --url "$next" --body "$COST_QUERY_BODY" || {
      COST_QUERY_ERR="page $page: $LAST_ERR"
      return 1
    }
    if ! jq -s '.[1].properties.rows as $r | if ($r | type) != "array" then error("rows") else .[0] | .properties.rows += $r end' \
      "$out" "$WORK/az-cq-$page.json" >"$out.next" 2>/dev/null; then
      COST_QUERY_ERR="could not parse the defenderCost response"
      return 1
    fi
    mv "$out.next" "$out"
  done
}

cost_azure() {
  local acct="$WORK/az-account.json" ws_file="$WORK/az-workspaces.json" sub arm id
  if [[ -z "$AZURE_JSON" ]] && ((!AZ_COST_LIVE)); then
    az_unreadable "not read live in a fixture run; pass --subscription or --azure-json"
    return
  fi
  if [[ -z "$AZURE_JSON" ]] && ! have az; then
    az_unreadable "az not installed; install az"
    return
  fi
  if ! az_read "$acct" account account show || ! sub="$(jq -r '.id // empty' "$acct" 2>/dev/null)" || [[ -z "$sub" ]]; then
    LAST_ERR="${LAST_ERR:-account show named no subscription id}"
    [[ "$LAST_ERR" == *"az login"* ]] || LAST_ERR="$LAST_ERR; run az login"
    az_unreadable "$LAST_ERR"
    return
  fi
  AZ_SUB_ARGS=(--subscription "$sub")
  arm="https://management.azure.com/subscriptions/$sub/providers"
  cost_row INFO Azure "subscription" "$(jq -r '"\(.name // .id) (\(.state // "state unknown"))"' "$acct")"
  if cost_query "$arm/Microsoft.CostManagement/query?api-version=2023-11-01"; then
    COST_DATA_DATE="$(jq -r '
      (.properties.columns | map(.name | ascii_downcase) | index("usagedate")) as $i
      | if $i == null then "usage data date unread"
        elif (.properties.rows | length) == 0 then "no usage rows this month"
        else ([.properties.rows[] | .[$i] | numbers] | max) as $d
          | if $d == null then "usage data date unread"
            else ($d | tostring) as $s | "usage data through \($s[0:4])-\($s[4:6])-\($s[6:8])" end
        end' "$WORK/az-defenderCost.json" 2>/dev/null)" || COST_DATA_DATE="usage data date unread"
  fi
  az_check budgets "budgets" "$AZ_BUDGETS_JQ" rest --method get --url "$arm/Microsoft.Consumption/budgets?api-version=2024-08-01"
  if az_read "$WORK/az-actions.json" scheduledActions rest --method get \
    --url "$arm/Microsoft.CostManagement/scheduledActions?api-version=2023-11-01"; then
    if ! jq -n --slurpfile b "$WORK/az-budgets.json" --slurpfile a "$WORK/az-actions.json" '{budgets: $b[0], actions: $a[0]}' \
      >"$WORK/az-alerts.json" 2>/dev/null || ! cost_jq "$WORK/az-alerts.json" "$ALERTS_JQ" ""; then
      cost_row UNREADABLE Azure "budget and anomaly alerts" "could not parse the budgets or scheduled actions"
    fi
  else
    cost_row UNREADABLE Azure "budget and anomaly alerts" "$LAST_ERR"
  fi
  az_check pricings "Defender plans" "$PRICINGS_JQ" security pricing list
  if [[ -n "$COST_QUERY_ERR" ]]; then
    cost_row UNREADABLE Azure "Defender charges, month to date" "$COST_QUERY_ERR"
  elif ! cost_jq "$WORK/az-defenderCost.json" "$CHARGES_JQ" "Defender charges, month to date"; then
    cost_row UNREADABLE Azure "Defender charges, month to date" "could not parse the defenderCost response"
  fi
  if ! az_read "$ws_file" workspaces monitor log-analytics workspace list; then
    cost_row UNREADABLE Azure "Log Analytics" "$LAST_ERR"
  elif ! jq -e 'type == "array"' "$ws_file" >/dev/null 2>&1; then
    cost_row UNREADABLE Azure "Log Analytics" "could not parse the workspaces response"
  elif jq -e 'length == 0' "$ws_file" >/dev/null; then
    cost_row INFO Azure "Log Analytics" "no workspaces on this subscription"
  else
    while IFS= read -r id; do
      if ! az_read "$WORK/az-la.json" "laUsage/$id" monitor log-analytics query --workspace "$id" --analytics-query "$LA_PEAK_QUERY" ||
        ! jq -n --slurpfile w "$ws_file" --slurpfile r "$WORK/az-la.json" --arg id "$id" \
          '{ws: ($w[0][] | select(.customerId == $id)), rows: $r[0]}' >"$WORK/az-la-one.json" 2>/dev/null ||
        ! cost_jq "$WORK/az-la-one.json" "$LA_JQ" ""; then
        [[ -n "$LAST_ERR" ]] || LAST_ERR="could not parse the Log Analytics response"
        cost_row UNREADABLE Azure "Log Analytics $(jq -r --arg id "$id" '.[] | select(.customerId == $id) | .name' "$ws_file")" "$LAST_ERR"
      fi
    done < <(jq -r '.[] | .customerId // "missing-id"' "$ws_file")
  fi
  az_check activity "activity, last 24h" "$ACTIVITY_JQ" monitor activity-log list --offset 1d --max-events "$AZ_ACTIVITY_LIMIT"
  jq -e --argjson n "$AZ_ACTIVITY_LIMIT" 'type == "array" and length >= $n' "$WORK/az-activity.json" >/dev/null 2>&1 &&
    COST_PARTIAL+=("Azure activity: the read reached its $AZ_ACTIVITY_LIMIT-event cap; a write past it is not shown")
  az_check secureScores "secure score" "$SCORES_JQ" security secure-scores list
  az_check advisorSecurity "Advisor security" "$ADVISOR_JQ" advisor recommendation list --category Security
  az_check advisorCost "Advisor cost" "$ADVISOR_JQ" advisor recommendation list --category Cost
}

print_cost() {
  local row status source label detail unread=0 line
  echo "== Cost (GitHub and Azure: charges, included usage, budgets and alerts, secret triggers, posture) =="
  if ((${#COST_SETTING_LAYERS[@]})); then
    line="${COST_SETTING_LAYERS[*]}"
    echo "  settings: ${line//[[:cntrl:]]/ }"
  else
    echo "  settings: defaults (no morning_brief cost key in work-items.yaml or work-items.local.yaml)"
  fi
  cost_github
  cost_azure
  for row in "${COST_ROWS[@]}"; do
    IFS=$'\x1f' read -r status source label detail <<<"$row"
    if [[ "$status" == UNREADABLE ]]; then unread=$((unread + 1)); else COST_HAS_DATA=1; fi
    printf '  %-10s %s\n' "$status" "$source${label:+ $label}: $detail"
  done
  for line in "${COST_PARTIAL[@]}"; do
    echo "  PARTIAL: $line"
  done
  if ((unread > 0)); then
    UNREADABLE=$((UNREADABLE + 1))
    UNREADABLE_NAMES+=("cost")
    COST_LOST=1
  fi
  echo
}

print_queues >"$WORK/s1"
print_stuck >"$WORK/s1b"
print_merge_ready >"$WORK/s2"
print_decisions >"$WORK/s3"
print_telemetry >"$WORK/s4"
print_stranded >"$WORK/s5"
print_landed >"$WORK/s5b"
print_lanes >"$WORK/s6"
print_touches >"$WORK/s6b"
print_cost >"$WORK/s7"

printf 'Morning brief — %s — %s\n' "${REPO:-<fixtures>}" "$(utc_stamp "$NOW_EPOCH")"
[[ "$REPO_SOURCE" == "git remote" ]] && echo "  repo resolved from the git origin remote (gh repo view unavailable)"
[[ "$TRANSPORT" == "rest" ]] && echo "  transport: REST (this session does not serve the gh GraphQL queries)"
if ((UNREADABLE > 0)); then
  echo "  $UNREADABLE of $SECTIONS_TOTAL sections unreadable: ${UNREADABLE_NAMES[*]}"
fi
echo
cat "$WORK/s1" "$WORK/s1b" "$WORK/s2" "$WORK/s3" "$WORK/s4" "$WORK/s5" "$WORK/s5b" "$WORK/s6" "$WORK/s6b" "$WORK/s7"

if ((UNREADABLE - COST_LOST >= SECTIONS_TOTAL - 1 && !COST_HAS_DATA)); then
  exit 5
elif ((UNREADABLE > 0)); then
  exit 6
fi
exit 0
