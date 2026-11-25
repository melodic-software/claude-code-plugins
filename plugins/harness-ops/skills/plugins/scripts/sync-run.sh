#!/usr/bin/env bash
# Exit codes:
#   0  the run completed; per-marketplace and per-id failures are reported in the
#      digest body, because a failed id is a finding, not a run failure
#   2  usage error, a missing prerequisite, or a run-level failure that left no
#      digest to emit

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_STATE="${SYNC_RUN_FLEET_STATE:-$SCRIPT_DIR/fleet-state.sh}"
CACHE_CHECK="${SYNC_RUN_CACHE_CHECK:-$SCRIPT_DIR/cache-content-check.sh}"
NORMALIZE="${SYNC_RUN_NORMALIZE:-$SCRIPT_DIR/normalize-enabled-plugins.sh}"
CLAUDE_BIN="${SYNC_RUN_CLAUDE_BIN:-claude}"
MARKETPLACES_JSON="${FLEET_STATE_MARKETPLACES_JSON:-$HOME/.claude/plugins/known_marketplaces.json}"
STALE_PARENT_ROWS=10
DIVERGENCE_PATH_IDS=3

JQ_CAPTURE="$SCRIPT_DIR/jq-capture.sh"
if [[ -f "$JQ_CAPTURE" ]]; then
  # shellcheck source=jq-capture.sh
  source "$JQ_CAPTURE"
else
  echo "ERROR: jq-capture.sh not found at $JQ_CAPTURE" >&2
  exit 2
fi

export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

CLOCK_RESOLUTION=""
# EPOCHREALTIME needs bash 5.0; macOS system bash 3.2 lacks it, so keep the `date +%s` rung.
# https://tiswww.case.edu/php/chet/bash/NEWS
resolve_clock() {
  local probe
  [[ "${SYNC_RUN_NO_EPOCHREALTIME:-0}" != "1" ]] || unset EPOCHREALTIME
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    CLOCK_RESOLUTION="microseconds"
    return 0
  fi
  probe=$(LC_ALL=C date +%s.%N 2>/dev/null)
  if [[ "$probe" =~ ^[0-9]+\.[0-9]+$ ]]; then
    CLOCK_RESOLUTION="nanoseconds"
  else
    CLOCK_RESOLUTION="seconds"
  fi
}
clock_into() {
  local __var="$1"
  local t
  case "$CLOCK_RESOLUTION" in
  microseconds) t="${EPOCHREALTIME:-}" ;;
  nanoseconds) t=$(LC_ALL=C date +%s.%N) ;;
  *) t=$(date +%s) ;;
  esac
  printf -v "$__var" '%s' "${t//,/.}"
}
resolve_clock
T_RUN_S=""
clock_into T_RUN_S
MAIN_READ_MP="" MAIN_READ_S="" MAIN_READ_E=""

MODE="sync"
TARGET_MP=""
ALL=0
ALLOW_DOWNGRADE=0
INSTALL_NEW="ask"
INSTALL_NEW_INVALID=""
JOURNAL_ROOT=""
RUN_DIR=""
ONLY_INSTALL=""
ONLY_INSTALL_MODE=0
RENDER=0
SOURCE_PULL="ask"
SOURCE_PULL_INVALID=""
SOURCE_PULL_OFF=""
PULL_SOURCES=""
PULL_SOURCES_SET=0
QUIET_AUTO_UPDATE=""
UPDATE_OTHER_PATHS=0

usage() {
  cat <<'EOF'
sync-run.sh — run `sync`/`audit` Steps 1-5b and print one JSON digest.

Usage:
  sync-run.sh [--marketplace <name> | --all] --journal-root <dir>
              [--install-new all|none|ask] [--allow-downgrade] [--render]
              [--source-pull ask|never] [--pull-source <names>]
              [--quiet-auto-update <names>] [--update-other-paths]
  sync-run.sh [--marketplace <name> | --all] --audit
              [--install-new all|none|ask] [--allow-downgrade] [--render]
              [--source-pull ask|never] [--quiet-auto-update <names>]
              [--update-other-paths]
  sync-run.sh --only-install <ids> --run-dir <dir> [--marketplace <name> | --all]
              [--render]

--render prints the Step 6 report (render-report.jq over the digest) after the
digest line; the report is written to <run_dir>/report.txt either way.
--audit is the dry run: it reads the fleet, predicts every claude call without
issuing it, and leaves nothing behind.
--pull-source fast-forwards each named marketplace's directory checkout before
its refresh, only when the checkout is clean, tracking, not ahead and behind.
--update-other-paths updates the lagging records of every other present path, one
call per record; without it they are counted in the report and left alone.

Exit: 0 the run completed (per-marketplace and per-id failures are in the digest);
2 usage error, jq missing, or a run-level failure that left no digest.
EOF
}

need_value() {
  (($1 >= 2)) || {
    echo "ERROR: $2" >&2
    exit 2
  }
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --marketplace)
    need_value $# "--marketplace requires a name"
    TARGET_MP="$2"
    shift 2
    ;;
  --all)
    ALL=1
    shift
    ;;
  --audit)
    MODE="audit"
    shift
    ;;
  --allow-downgrade)
    ALLOW_DOWNGRADE=1
    shift
    ;;
  --render)
    RENDER=1
    shift
    ;;
  --install-new)
    need_value $# "--install-new requires a value"
    INSTALL_NEW="$2"
    shift 2
    ;;
  --journal-root)
    need_value $# "--journal-root requires a directory"
    JOURNAL_ROOT="$2"
    shift 2
    ;;
  --run-dir)
    need_value $# "--run-dir requires a directory"
    RUN_DIR="$2"
    shift 2
    ;;
  --only-install)
    need_value $# "--only-install requires an id list (an empty string is legal)"
    ONLY_INSTALL="$2"
    ONLY_INSTALL_MODE=1
    shift 2
    ;;
  --source-pull)
    need_value $# "--source-pull requires a value"
    SOURCE_PULL="$2"
    shift 2
    ;;
  --pull-source)
    need_value $# "--pull-source requires marketplace names"
    PULL_SOURCES="$2"
    PULL_SOURCES_SET=1
    shift 2
    ;;
  --quiet-auto-update)
    need_value $# "--quiet-auto-update requires marketplace names"
    QUIET_AUTO_UPDATE="$2"
    shift 2
    ;;
  --update-other-paths)
    UPDATE_OTHER_PATHS=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "ERROR: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if ((ALL == 1)) && [[ -n "$TARGET_MP" ]]; then
  echo "ERROR: --all cannot be combined with --marketplace" >&2
  exit 2
fi

case "$INSTALL_NEW" in
all | none | ask) ;;
*)
  INSTALL_NEW_INVALID="$INSTALL_NEW"
  INSTALL_NEW="ask"
  ;;
esac
case "$SOURCE_PULL" in
ask | never) ;;
*)
  SOURCE_PULL_INVALID="$SOURCE_PULL"
  SOURCE_PULL="ask"
  ;;
esac
apply_pull_policy() {
  if [[ -n "${CLAUDE_CODE_REMOTE:-}" ]]; then
    SOURCE_PULL="never"
    SOURCE_PULL_OFF="autonomous session (CLAUDE_CODE_REMOTE set)"
  elif [[ "$SOURCE_PULL" == "never" ]]; then
    SOURCE_PULL_OFF="policy never"
  else
    SOURCE_PULL_OFF=""
  fi
}
apply_pull_policy

if ((PULL_SOURCES_SET == 1)); then
  if [[ "$MODE" == "audit" ]]; then
    echo "ERROR: --pull-source is a sync-mode request; audit changes nothing" >&2
    exit 2
  fi
  if ((ONLY_INSTALL_MODE == 1)); then
    echo "ERROR: --pull-source runs before Step 1; an --only-install re-entry starts at Step 4" >&2
    exit 2
  fi
fi

if ((ONLY_INSTALL_MODE == 1)); then
  if [[ -z "$RUN_DIR" ]]; then
    echo "ERROR: --only-install requires --run-dir <dir> (the run it re-enters)" >&2
    exit 2
  fi
  if [[ ! -d "$RUN_DIR" ]]; then
    echo "ERROR: --run-dir is not a directory: $RUN_DIR" >&2
    exit 2
  fi
  if [[ "$MODE" == "audit" ]]; then
    echo "ERROR: --only-install is a sync-mode re-entry; audit installs nothing" >&2
    exit 2
  fi
elif [[ "$MODE" == "sync" && -z "$JOURNAL_ROOT" ]]; then
  echo "ERROR: --journal-root <dir> is required in sync mode" >&2
  echo "  SKILL.md passes the substituted \${CLAUDE_PLUGIN_DATA} journal path;" >&2
  echo "  a context/*.md spoke is read raw and cannot substitute it." >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required (install with: winget install jqlang.jq | apt install jq | brew install jq)" >&2
  exit 2
fi

json_lines() {
  local __var="$1"
  local __file="$2"
  if [[ ! -f "$__file" ]]; then
    printf -v "$__var" '%s' '[]'
    return 0
  fi
  jq_to "$__var" -R -s -c 'gsub("\r"; "") | split("\n") | map(select(length > 0))' <"$__file"
}

json_array_of() {
  local __var="$1"
  shift
  if (($# == 0)); then
    printf -v "$__var" '%s' '[]'
    return 0
  fi
  jq_to "$__var" -c -s '.' <<<"$(printf '%s\n' "$@")"
}

json_strings_of() {
  local __var="$1"
  shift
  if (($# == 0)); then
    printf -v "$__var" '%s' '[]'
    return 0
  fi
  jq_to "$__var" -c -R -s 'split("\n") | map(select(length > 0))' <<<"$(printf '%s\n' "$@")"
}

json_object_file() {
  local __file="$1"
  local __sep=""
  shift
  {
    printf '{'
    while (($# >= 2)); do
      printf '%s"%s":%s' "$__sep" "$1" "$2"
      __sep=","
      shift 2
    done
    printf '}\n'
  } >"$__file"
}

move_row_to() {
  local __mr_id __mr_sc __mr_o __mr_n __mr_d __mr_k=""
  json_string_to __mr_id "$2"
  json_string_to __mr_sc "$3"
  json_string_to __mr_o "$4"
  json_string_to __mr_n "$5"
  json_string_to __mr_d "$6"
  [[ -z "${7:-}" ]] || {
    json_string_to __mr_k "$7"
    __mr_k="\"kind\":$__mr_k,"
  }
  printf -v "$1" '{"id":%s,"scope":%s,%s"old":%s,"new":%s,"direction":%s}' \
    "$__mr_id" "$__mr_sc" "$__mr_k" "$__mr_o" "$__mr_n" "$__mr_d"
}
downgrade_row_to() {
  local __dr_id __dr_sc __dr_o __dr_n
  json_string_to __dr_id "$2"
  json_string_to __dr_sc "$3"
  json_string_to __dr_o "$4"
  json_string_to __dr_n "$5"
  printf -v "$1" '{"id":%s,"scope":%s,"old":%s,"new":%s%s}' \
    "$__dr_id" "$__dr_sc" "$__dr_o" "$__dr_n" "${6:+,\"concurrent\":true}"
}

RUN_ERRORS=()
MP_ERRORS=()

run_error() { RUN_ERRORS+=("$1"); }
mp_error() { MP_ERRORS+=("$1"); }

version_direction() {
  local __vd
  version_direction_to __vd "$1" "$2"
  echo "$__vd"
}

version_direction_to() {
  local __vd_var="$1" old="$2" new="$3" ore_ok=0 nre_ok=0 o1 o2 o3 n1 n2 n3 __vd_d
  if [[ "$old" =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
    o1=$((10#${BASH_REMATCH[1]}))
    o2=$((10#${BASH_REMATCH[2]}))
    o3=$((10#${BASH_REMATCH[3]}))
    ore_ok=1
  fi
  if [[ "$new" =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
    n1=$((10#${BASH_REMATCH[1]}))
    n2=$((10#${BASH_REMATCH[2]}))
    n3=$((10#${BASH_REMATCH[3]}))
    nre_ok=1
  fi
  if [[ "$ore_ok$nre_ok" != "11" ]]; then
    __vd_d="unknown"
  elif ((n1 > o1)) || { ((n1 == o1)) && ((n2 > o2)); } ||
    { ((n1 == o1)) && ((n2 == o2)) && ((n3 > o3)); }; then
    __vd_d="forward"
  elif ((n1 < o1)) || { ((n1 == o1)) && ((n2 < o2)); } ||
    { ((n1 == o1)) && ((n2 == o2)) && ((n3 < o3)); }; then
    __vd_d="backward"
  elif [[ "$old" == "$new" ]]; then
    __vd_d="same"
  else
    __vd_d="unknown"
  fi
  printf -v "$__vd_var" '%s' "$__vd_d"
}

if [[ -n "${SYNC_RUN_VERSION_DIRECTION:-}" ]]; then
  version_direction "${SYNC_RUN_VERSION_DIRECTION%%$'\t'*}" "${SYNC_RUN_VERSION_DIRECTION#*$'\t'}"
  exit 0
fi

version_at() {
  local __var="$1"
  local report="$2"
  local id="$3"
  local scope="$4"
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to "$__var" -r --arg id "$id" --arg sc "$scope" \
    'first(.installed[]? | select(.id == $id and .scope == $sc
      and ($sc == "user" or .currentProject == true)) | .version) // ""' "$report"
}

CLI_OUT=""
CLI_RC=0
CLI_CWD=""
stamp_us() {
  local __su_s="$2"
  local __su_f=""
  [[ "$__su_s" == *.* ]] && __su_f="${__su_s#*.}"
  __su_f="${__su_f}000000"
  printf -v "$1" '%s' "$((10#${__su_s%%.*} * 1000000 + 10#${__su_f:0:6}))"
}
run_cli() {
  local label="$1"
  shift
  local sink="$RUN_DIR/.last-cli-out"
  local t_s
  local t_e
  clock_into t_s
  {
    echo "\$ $label"
    if [[ -n "$CLI_CWD" ]]; then
      (cd "$CLI_CWD" && exec "$CLAUDE_BIN" "$@") 2>&1 </dev/null
    else
      "$CLAUDE_BIN" "$@" 2>&1 </dev/null
    fi
  } | tee -a "$JOURNAL_LOG" >"$sink"
  CLI_RC=${PIPESTATUS[0]}
  clock_into t_e
  stamp_us t_s "$t_s"
  stamp_us t_e "$t_e"
  t_e=$(((t_e - t_s) / 1000))
  ((t_e >= 0)) || t_e=0
  CLI_CALLS=$((CLI_CALLS + 1))
  CLI_MS=$((CLI_MS + t_e))
  printf '# elapsed %d.%03ds, exit %d\n' $((t_e / 1000)) $((t_e % 1000)) "$CLI_RC" >>"$JOURNAL_LOG"
  CLI_OUT=""
  IFS= read -r -d '' CLI_OUT <"$sink"
  while [[ "$CLI_OUT" == *$'\n' ]]; do CLI_OUT="${CLI_OUT%$'\n'}"; done
  CLI_OUT="${CLI_OUT//$'\r'/}"
  if ((CLI_RC != 0)) && [[ " $* " == *" --json "* && "$CLI_OUT" == *"unknown option"*"--json"* ]]; then
    local -a args=()
    local arg
    for arg in "$@"; do [[ "$arg" == --json ]] || args+=("$arg"); done
    run_cli "${label/ --json/}" "${args[@]}"
  fi
}

predict_cli() {
  local label="$1"
  echo "would run: $label" >>"$JOURNAL_LOG"
  CLI_RC=0
  CLI_OUT="would run: $label"
}

object_lines_to() {
  local __ol_line __ol_lines=""
  while IFS= read -r __ol_line || [[ -n "$__ol_line" ]]; do
    [[ "$__ol_line" == '{'* ]] && __ol_lines+="$__ol_line"$'\n'
  done <<<"$2"
  printf -v "$1" '%s' "$__ol_lines"
}

# `| values` drops the null that last(empty) yields before jq 1.8.
# https://github.com/jqlang/jq/blob/master/NEWS.md
RESULT_LINE_JQ='last(inputs | (try fromjson catch null) | select(type == "object" and has("command"))) | values'
cli_json() {
  local __var="$1" __lines __found=""
  object_lines_to __lines "$2"
  [[ -z "$__lines" ]] ||
    jq_to __found -c -R -n "$RESULT_LINE_JQ" <<<"$__lines" 2>/dev/null || __found=""
  printf -v "$__var" '%s' "$__found"
}

cli_message() {
  local __var="$1"
  local __text="$2"
  local __json
  cli_json __json "$__text"
  if [[ -n "$__json" ]]; then
    jq_to "$__var" -r '.message // ""' <<<"$__json"
  else
    printf -v "$__var" '%s' "$__text"
  fi
}

cli_reported_version() {
  local __var="$1"
  local text="$2"
  local json
  cli_json json "$text"
  if [[ -n "$json" ]]; then
    jq_to "$__var" -r 'if .updateOutcome == "updated" or .updateOutcome == "up_to_date"
      then .newVersion // "" else "" end' <<<"$json"
  elif [[ "$text" =~ updated\ from\ ([^[:space:]]+)\ to\ ([^[:space:]]+) ]]; then
    printf -v "$__var" '%s' "${BASH_REMATCH[2]}"
  elif [[ "$text" =~ already\ at\ the\ latest\ version\ \(([^\)[:space:]]+)\) ]]; then
    printf -v "$__var" '%s' "${BASH_REMATCH[1]}"
  else
    printf -v "$__var" '%s' ""
  fi
}

unset_user_config_of() {
  local __var="$1"
  local text="$2" json pair count="" n="" r=""
  cli_json json "$2"
  if [[ -n "$json" ]]; then
    jq_to pair -r '(.unsetOptionCount | if type == "number" and . > 0 then tostring else "" end)
      + "\u001f" + (.message // "")' <<<"$json"
    count="${pair%%$'\x1f'*}"
    text="${pair#*$'\x1f'}"
  fi
  if [[ "$text" =~ ([0-9]+)\ userConfig\ options?\ not\ yet\ set(\ \(([0-9]+)\ required\))? ]]; then
    n="${BASH_REMATCH[1]}"
    r="${BASH_REMATCH[3]:-}"
  fi
  n="${count:-$n}"
  if [[ -z "$n" ]]; then
    printf -v "$__var" '%s' "null"
    return 0
  fi
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to "$__var" -c -n --arg n "$n" --arg r "$r" \
    '{options_unset: ($n | tonumber), required: (if $r == "" then null else ($r | tonumber) end)}'
}

cli_move_result() {
  local __var="$1"
  local text="$2"
  local json outcome=""
  cli_json json "$text"
  if [[ -n "$json" ]]; then
    jq_to outcome -r '.updateOutcome // ""' <<<"$json"
    case "$outcome" in
    updated) printf -v "$__var" '%s' "updated" ;;
    up_to_date) printf -v "$__var" '%s' "noop" ;;
    *) printf -v "$__var" '%s' "other" ;;
    esac
    return 0
  fi
  case "$text" in
  *"updated from"*) printf -v "$__var" '%s' "updated" ;;
  *"already at the latest version"*) printf -v "$__var" '%s' "noop" ;;
  *) printf -v "$__var" '%s' "other" ;;
  esac
}

cli_update_result() {
  local __ur_res="$1" __ur_new="$2" __ur_lines __ur_pair=""
  object_lines_to __ur_lines "$3"
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  [[ -z "$__ur_lines" ]] ||
    jq_to __ur_pair -r -R -n "$RESULT_LINE_JQ"'
      | (.updateOutcome // "") as $o
      | (if $o == "updated" then "updated" elif $o == "up_to_date" then "noop" else "other" end)
        + "\u001f"
        + (if $o == "updated" or $o == "up_to_date" then (.newVersion // "" | tostring) else "" end)' \
      <<<"$__ur_lines" 2>/dev/null || __ur_pair=""
  if [[ -z "$__ur_pair" ]]; then
    cli_reported_version "$__ur_new" "$3"
    cli_move_result "$__ur_res" "$3"
    return 0
  fi
  printf -v "$__ur_res" '%s' "${__ur_pair%%$'\x1f'*}"
  printf -v "$__ur_new" '%s' "${__ur_pair#*$'\x1f'}"
}

cli_outcome_line() {
  local text="$1"
  local line json message
  local fallback=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line//$'\r'/}"
    [[ "$line" == '$ '* ]] && continue
    [[ -z "$line" ]] && continue
    if [[ -z "$fallback" ]]; then
      fallback="$line"
    fi
    if [[ "$line" == ✘* || "$line" == *Failed* || "$line" == *Error* ]]; then
      [[ "$line" == '{'* ]] && continue
      printf '%s' "$line"
      return 0
    fi
  done <<<"$text"
  cli_json json "$text"
  if [[ -n "$json" ]]; then
    jq_to message -r '.message // "" | split("\n")[0]' <<<"$json"
    [[ -z "$message" ]] || {
      printf '%s' "$message"
      return 0
    }
  fi
  printf '%s' "$fallback"
}

install_disabled_notice() {
  local text
  cli_message text "$1"
  case "$text" in
  *"disabled by default"* | *"Disabled by default"*) return 0 ;;
  *) return 1 ;;
  esac
}

project_ids() {
  local selector="$1"
  local from="$2"
  local out="$3"
  "$FLEET_STATE" --ids "$selector" --from "$from" >"$out" 2>"$RUN_DIR/.proj-err"
}

trunc() {
  local __var="$1" text="$2" max="${3:-400}"
  if ((${#text} > max)); then
    printf -v "$__var" '%s' "${text:0:max}…"
  else
    printf -v "$__var" '%s' "$text"
  fi
}

proj_err() {
  local text=""
  local bounded=""
  [[ -f "$RUN_DIR/.proj-err" ]] && text=$(<"$RUN_DIR/.proj-err")
  trunc bounded "${text//$'\r'/}"
  printf '%s' "$bounded"
}

setup_run_dir() {
  if ((ONLY_INSTALL_MODE == 1)); then
    JOURNAL_LOG="$RUN_DIR/journal.log"
    return 0
  fi
  if [[ "$MODE" == "audit" ]]; then
    RUN_DIR=$(mktemp -d "${TMPDIR:-${TEMP:-.}}/plugins-audit.XXXXXX") || {
      echo "ERROR: could not create the audit scratch directory" >&2
      exit 2
    }
    AUDIT_SCRATCH="$RUN_DIR"
    trap 'rm -rf "$AUDIT_SCRATCH"' EXIT
  else
    mkdir -p "$JOURNAL_ROOT" 2>/dev/null
    RUN_DIR=$(mktemp -d "$JOURNAL_ROOT/$(date -u +%Y%m%dT%H%M%SZ).XXXXXX") || {
      echo "ERROR: could not create a run directory under: $JOURNAL_ROOT" >&2
      exit 2
    }
  fi
  JOURNAL_LOG="$RUN_DIR/journal.log"
  : >"$JOURNAL_LOG"
}

own_plugin_name() {
  local manifest="$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json"
  local name=""
  [[ -f "$manifest" ]] && jq_to name -r '.name // ""' "$manifest" 2>/dev/null
  printf '%s' "$name"
}

catalog_regression_rows() {
  local __interval_var="$1"
  local __rows_var="$2"
  local mp="$3"
  local snaps=(pre-refresh pre mid post)
  local i a b rows=""
  printf -v "$__interval_var" '%s' ""
  printf -v "$__rows_var" '%s' "[]"
  for ((i = 0; i + 1 < ${#snaps[@]}; i++)); do
    a="$RUN_DIR/${snaps[i]}.$mp.json"
    b="$RUN_DIR/${snaps[i + 1]}.$mp.json"
    [[ -f "$a" && -f "$b" ]] || continue
    # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
    jq_to rows -c --slurpfile a "$a" --slurpfile b "$b" -n "$TRIPLE_DEF"'
      ($a[0].catalog_versions // {}) as $before | ($b[0].catalog_versions // {}) as $after
      | [$before | to_entries[]
         | select((.value | triple) != null and ($after[.key] | triple) != null
                  and ($after[.key] | triple) < (.value | triple))
         | "\(.key) \(.value) \($after[.key])"]' || continue
    if [[ -n "$rows" && "$rows" != "[]" ]]; then
      printf -v "$__interval_var" '%s' "${snaps[i]}->${snaps[i + 1]}"
      printf -v "$__rows_var" '%s' "$rows"
      return 0
    fi
  done
  return 0
}

# shellcheck disable=SC2016  # a jq program: every $var is a jq variable
ACTIONABLE_DEF='def actionable: select(.versionsMatch == false)
    | select(([.scopes[]? | select(.projectPathIsHome != true) | .version] | unique | length) > 1);'
linked_worktree_paths() {
  local __var="$1" post="$2" paths="" p fs line
  local found=()
  jq_to paths -r "$ACTIONABLE_DEF"'[.divergences[]? | actionable | .scopes[]?
    | select(.projectPathIsHome != true and .projectPathPresent == true) | .projectPath]
    | unique | .[]' "$post" || paths=""
  while IFS= read -r p; do
    p="${p//$'\r'/}"
    [[ -n "$p" ]] || continue
    fs="${p//\\//}"
    [[ -f "$fs/.git" ]] || continue
    line=""
    IFS= read -r line <"$fs/.git" || true
    line="${line//$'\r'/}"
    case "$line" in
    "gitdir:"*".git/worktrees/"*) found+=("$p") ;;
    *) ;;
    esac
  done <<<"$paths"
  json_strings_of "$__var" ${found[@]+"${found[@]}"}
}

would_pins() {
  local __var="$1"
  local ir_w
  json_array_of ir_w ${IR_WOULD[@]+"${IR_WOULD[@]}"}
  local skipped="$RUN_DIR/.other-paths-skipped.$2.jsonl"
  [[ -f "$skipped" ]] || skipped=/dev/null
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to "$__var" -c -n --argjson ir "$ir_w" --argjson op "$OTHER_PATHS_JSON" \
    --slurpfile skipped "$skipped" \
    '[($ir[] | {id, scope, current: true}), ($op.would_update[]? | {id, scope, path}), $skipped[]]' ||
    printf -v "$__var" '%s' "[]"
  [[ -n "${!__var}" ]] || printf -v "$__var" '%s' "[]"
}

divergence_block() {
  local __var="$1" mp="$2" linked="[]"
  local pre="$RUN_DIR/pre.$mp.json" mid="$RUN_DIR/mid.$mp.json" post="$RUN_DIR/post.$mp.json"
  if [[ ! -f "$pre" || ! -f "$mid" || ! -f "$post" ]]; then
    jq_to "$__var" -c -n '{pre: null, mid: null, post: null, new_total: null,
      new_by_interval: {in_repo: null, user_sweep: null, concurrent: null}, pre_existing: null,
      note: "a snapshot was missing, so the split could not be computed"}'
    return 0
  fi
  linked_worktree_paths linked "$post"
  [[ -n "$linked" ]] || linked="[]"
  local moved_rows
  local would
  would_pins would "$mp"
  json_array_of moved_rows ${MOVED_DURING[@]+"${MOVED_DURING[@]}"}
  json_object_file "$RUN_DIR/.divergence-args.$mp.json" moved "$moved_rows" wt "$linked" would "$would"
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to "$__var" -c \
    --slurpfile p "$pre" --slurpfile m "$mid" --slurpfile q "$post" \
    --argjson cap "$DIVERGENCE_PATH_IDS" "$ACTIONABLE_DEF$TRIPLE_DEF"'
    . as {$moved, $wt, $would}
    # Under --audit nothing moved, so a pin sync would forward-update (Step 2 or
    # Step 3a) is read at the catalog version: it is not work for converge. So is a
    # pin Step 3a skipped, which `--update-other-paths` moves. A linked worktree
    # keeps its own version, since update leaves it behind there.
    | ($q[0] | if ($would | length) == 0 then . else
        .catalog_versions as $cv
        | ([.installed[]? | select(.currentProject == true) | {id, scope, path: .projectPath}]) as $cur
        | ([$would[] | . as $w
            | if .current == true then ($cur[] | select(.id == $w.id and .scope == $w.scope))
              else {id, scope, path} end]) as $wp
        | .divergences |= map(.id as $id | .scopes |= map(
            . as $s
            | if $s.linkedWorktree != true and $s.projectPathIsHome != true
                 and ($s.projectPath as $pp | $wt | index($pp)) == null
                 and any($wp[]; .id == $id and .scope == $s.scope and .path == $s.projectPath)
                 and ($cv[$id] | triple) != null and ($s.version | triple) != null
                 and ($s.version | triple) < ($cv[$id] | triple)
              then .version = $cv[$id] else . end))
      end) as $qq
    # A pin at the project the run stands in is converge-actionable even when that
    # project is itself a linked worktree, so it is never classed `worktree`.
    | ([$qq.installed[]? | select(.currentProject == true) | .projectPath]) as $curp
    | def act: [.divergences[]? | actionable | .id];
    def pin_class:
      if .projectPathPresent == false then "blocked"
      elif .projectPathPresent == true and (.projectPath as $pp | $curp | index($pp)) == null
           and (.projectPath as $pp | $wt | index($pp)) != null then "worktree"
      else "actionable" end;
    # Only a pin that differs from the row'"'"'s highest version is the skew converge or
    # a worktree removal would settle; a pin already at it is not what makes the
    # row actionable. An unparsable version stays in, the conservative direction.
    # A pin keyed to a user home (`projectPathIsHome`) is dropped like in `actionable`:
    # it never sets the highest version and never classes the row.
    def row_class:
      [.scopes[]? | select(.projectPathIsHome != true)] as $s
      | ([$s[] | .version | triple | select(. != null)] | max) as $top
      | [$s[] | select((.projectPath // "") != "")
         | select($top == null or (.version | triple) != $top)
         | pin_class] as $c
      | if ($c | length) == 0 or ($c | index("actionable")) != null then "actionable"
        elif ($c | index("worktree")) != null then "worktree"
        else "blocked" end;
    # The records that make a row skewed: the same pins row_class judges, plus a
    # user-scope record behind a project pin, so every diverging id is named. A row
    # whose versions differ only past the triple (`1.2.3` against `1.2.3-beta`) has
    # no such pin, so all of its scopes are kept rather than none. Each record also
    # carries its pin_class, which by_path keeps and records[] drops.
    def diverging_records:
      .id as $id
      | [.scopes[]? | select(.projectPathIsHome != true)] as $s
      | ([$s[] | .version | triple | select(. != null)] | max) as $top
      | [$s[] | select($top == null or (.version | triple) != $top)] as $d
      | (if ($d | length) > 0 then $d else $s end)
      | map({id: $id, scope, version, projectPath: (.projectPath // null),
             class: (if (.projectPath // "") != "" then pin_class else null end)});
    ($moved | map(.id)) as $conc
    | ($p[0] | act) as $pre | ($m[0] | act) as $mid | ($qq | act) as $post
    | ($post - $pre) as $new
    | [$new[] | select(. as $i | $conc | index($i))] as $by_conc
    | ($new - $by_conc) as $by_step
    | ([$qq.installed[]? | select(.currentProject == true) | .id]) as $here
    | ([$qq.divergences[]? | actionable | {id, c: row_class}]) as $rows
    | ([$rows[] | select(.c == "actionable")]) as $act_rows
    | ([$qq.divergences[]? | actionable | diverging_records[]]) as $records
    # A path converge can act on sorts before a linked worktree, and a worktree
    # before a path that is not present, so the first sub-line under the
    # converge pointer is a place converge can run from.
    | ([$records[] | select((.projectPath // "") != "")]
       | group_by(.projectPath)
       | map((map(.id) | unique) as $ids
             | {path: .[0].projectPath, class: .[0].class, count: length, ids: $ids[:$cap],
                more: ([($ids | length) - $cap, 0] | max)})
       | sort_by(({actionable: 0, worktree: 1, blocked: 2}[.class // ""] // 0), -.count, .path)) as $paths
    | {pre: ($pre | length), mid: ($mid | length), post: ($post | length),
       new_total: ($new | length),
       new_by_interval: {in_repo: ([$by_step[] | select(. as $i | $mid | index($i))] | length),
                         user_sweep: ([$by_step[] | select(. as $i | $mid | index($i) | not)] | length),
                         concurrent: ($by_conc | length)},
       pre_existing: (($post | length) - ($new | length)),
       actionable_here: ([$act_rows[] | select(.id as $i | $here | index($i))] | length),
       actionable_elsewhere: ([$act_rows[] | select(.id as $i | $here | index($i) | not)] | length),
       in_worktrees: ([$rows[] | select(.c == "worktree")] | length),
       blocked: ([$rows[] | select(.c == "blocked")] | length),
       records: [$records[] | del(.class)],
       # The stale project records section already counts every path that is
       # not present, so the digest names those paths by count only.
       by_path: [$paths[] | select(.class != "blocked")],
       blocked_paths: ([$paths[] | select(.class == "blocked")]
                       | {paths: length, records: (map(.count) | add // 0)}),
       by_path_all: $paths}' \
    "$RUN_DIR/.divergence-args.$mp.json" || return
  local full="${!__var}"
  local detail=""
  local detail_file="$RUN_DIR/divergences.$mp.json"
  if [[ "$MODE" != "audit" ]] &&
    jq_to detail -c '{records, by_path: .by_path_all}' <<<"$full" &&
    printf '%s\n' "$detail" >"$detail_file"; then
    # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
    jq_to "$__var" -c --arg f "$detail_file" \
      '(.records | length) as $n | del(.records, .by_path_all) + {record_count: $n, records_file: $f}' <<<"$full"
  else
    jq_to "$__var" -c 'del(.by_path_all) + {record_count: (.records | length), records_file: null}' <<<"$full"
  fi
}

# shellcheck disable=SC2016  # a jq program: every $var is a jq variable
TRIPLE_DEF='def triple:
    if type == "string" then
      ((capture("^v?(?<x>[0-9]+)[.](?<y>[0-9]+)[.](?<z>[0-9]+)") // null)
       | if . == null then null else [.x, .y, .z] | map(tonumber) end)
    else null end;'

SS_GIT_DIR=""
SS_GIT_IN=0
settings_state() {
  local __var="$1"
  local dir="$2"
  local st=""
  local f
  local text
  if [[ "$dir" != "$SS_GIT_DIR" ]]; then
    SS_GIT_DIR="$dir"
    SS_GIT_IN=0
    git --no-optional-locks -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 && SS_GIT_IN=1
  fi
  if ((SS_GIT_IN == 1)); then
    st=$(git --no-optional-locks -C "$dir" status --porcelain -- .claude/ 2>&1)
  fi
  for f in settings.json settings.local.json; do
    text="absent"
    if [[ -f "$dir/.claude/$f" ]]; then
      text=""
      IFS= read -r -d '' text <"$dir/.claude/$f"
      text="present:$text"
    fi
    st+=$'\n'"$f $text"
  done
  printf -v "$__var" '%s' "$st"
}

path_row() {
  local j_id j_sc j_path j_old j_cat j_label j_result j_reason
  local j_home="false"
  json_string_to j_id "$id"
  json_string_to j_sc "$scope"
  json_string_to j_path "$path"
  json_string_to j_old "$old"
  json_string_to j_cat "$cat"
  json_string_to j_label "$label"
  json_string_to j_result "$1"
  json_string_to j_reason "$2"
  [[ "$home" == "true" ]] && j_home="true"
  printf '{"id":%s,"scope":%s,"path":%s,"old":%s,"catalog":%s,"label":%s,"home":%s,"result":%s,"reason":%s,"stopped":%s}\n' \
    "$j_id" "$j_sc" "$j_path" "$j_old" "$j_cat" "$j_label" "$j_home" "$j_result" "$j_reason" "$3"
}

other_paths_step() {
  local mp="$1"
  local cands=""
  local path id scope old cat label home fs reason
  local before=""
  local after=""
  local cur=""
  local stopped=""
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  if ! jq_to cands -r "$TRIPLE_DEF"'
    .catalog_versions as $cv
    | [.installed[]? | select((.scope == "project" or .scope == "local") and .currentProject != true
         and .projectPathPresent == true and (.projectPath // "") != "")
       | select(($cv[.id] | triple) as $c | (.version | triple) as $v | $c != null and $v != null and $v < $c)
       | {projectPath, id, scope, version, cat: $cv[.id], label: (.label // ""),
          home: (.projectPathIsHome == true | tostring)}]
    | sort_by(.projectPath, .id, .scope)[]
    | [.projectPath, .id, .scope, .version, .cat, .label, .home] | join("\u001f")' "$RUN_DIR/mid.$mp.json"; then
    mp_error "other-paths selection failed, step not run"
    return 0
  fi
  if ((UPDATE_OTHER_PATHS == 0)); then
    printf '%s\n' "$cands" | jq -c -R 'select(. != "") | gsub("\r"; "") | split("\u001f")
      | {path: .[0], id: .[1], scope: .[2]}' >"$RUN_DIR/.other-paths-skipped.$mp.jsonl" ||
      mp_error "other-paths count failed"
    return 0
  fi
  while IFS=$'\x1f' read -r path id scope old cat label home; do
    path="${path//$'\r'/}" id="${id//$'\r'/}" scope="${scope//$'\r'/}" old="${old//$'\r'/}"
    cat="${cat//$'\r'/}" label="${label//$'\r'/}" home="${home//$'\r'/}"
    [[ -n "$id" ]] || continue
    if [[ "$MODE" == "audit" ]]; then
      predict_cli "(cd \"$path\" && claude plugin update $id -s $scope)"
      PATH_ROWS+=("$(path_row would "" false)")
      continue
    fi
    fs="${path//\\//}"
    if [[ "$path" != "$cur" ]]; then
      cur="$path"
      settings_state before "$fs"
    fi
    if [[ "$path" == "$stopped" ]]; then
      PATH_ROWS+=("$(path_row failed "not tried: the .claude/ settings in this path changed after an earlier call" true)")
      continue
    fi
    CLI_CWD="$fs"
    run_cli "(cd \"$path\" && claude plugin update $id -s $scope --json)" plugin update "$id" -s "$scope" --json
    CLI_CWD=""
    settings_state after "$fs"
    if [[ "$after" != "$before" ]]; then
      stopped="$path"
      PATH_ROWS+=("$(path_row failed "the .claude/ settings in this path changed after this call, so the path was stopped" true)")
      continue
    fi
    if ((CLI_RC != 0)); then
      reason=$(cli_outcome_line "$CLI_OUT")
      PATH_ROWS+=("$(path_row failed "exit $CLI_RC: $reason" false)")
      continue
    fi
    PATH_ROWS+=("$(path_row called "" false)")
  done <<<"$cands"
}

finalize_other_paths() {
  local mp="$1" rows result=""
  local file="$RUN_DIR/other-paths.$mp.json" rows_file="$RUN_DIR/.other-paths-rows.$mp.json"
  local post="$RUN_DIR/post.$mp.json" pre="$RUN_DIR/pre.$mp.json"
  local skipped="$RUN_DIR/.other-paths-skipped.$mp.jsonl"
  if ((ONLY_INSTALL_MODE == 1)); then
    [[ -f "$file" ]] && OTHER_PATHS_JSON=$(<"$file")
    return 0
  fi
  json_array_of rows ${PATH_ROWS[@]+"${PATH_ROWS[@]}"}
  printf '%s\n' "$rows" >"$rows_file"
  [[ -f "$post" ]] || post="$rows_file"
  [[ -f "$pre" ]] || pre="$rows_file"
  [[ -f "$skipped" ]] || skipped=/dev/null
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to result -c -n --slurpfile rows "$rows_file" --slurpfile post "$post" --slurpfile pre "$pre" \
    --slurpfile skipped "$skipped" "$TRIPLE_DEF"'
    ($post[0] | if type == "object" then . else {} end) as $q
    | ($pre[0] | if type == "object" then . else {} end) as $p
    | [$rows[0][] | select(.result == "called")
       | . as $r
       | . + {new: (first($q.installed[]? | select(.id == $r.id and .scope == $r.scope
                     and .projectPath == $r.path) | .version) // null)}
       | . + {moved: ((.new | triple) != null and (.old | triple) < (.new | triple))}] as $called
    | {updated: [$called[] | select(.moved) | {id, scope, path, old, new}],
       not_moved: [$called[] | select((.moved | not) and (.label != "" or .home))
                   | {id, scope, path, version: (.new // .old), catalog,
                      label: (if .label != "" then .label else "user home" end)}],
       failed: ([$rows[0][] | select(.result == "failed") | {id, scope, path, reason, stopped}]
                + [$called[] | select((.moved | not) and .label == "" and (.home | not))
                   | {id, scope, path, stopped: false,
                      reason: ("the record did not move: still at \(.new // "an unread version"), the catalog reads \(.catalog)")}]),
       would_update: [$rows[0][] | select(.result == "would") | {id, scope, path, old, catalog}],
       skipped: {records: ($skipped | length), paths: ($skipped | map(.path) | unique | length)},
       catalog_moved: (($p.catalog_versions // {}) as $a | ($q.catalog_versions // {}) as $b
                       | [$a | keys[] | select($b[.] != null and $a[.] != null and $a[.] != $b[.])] | length)}' || result=""
  if [[ -n "$result" ]]; then
    OTHER_PATHS_JSON="$result"
  else
    mp_error "other-paths read-back failed"
  fi
  printf '%s\n' "$OTHER_PATHS_JSON" >"$file"
}

reset_marketplace_state() {
  MP_ERRORS=()
  IR_UPDATED=() IR_FAILED=() IR_WOULD=() IR_LIVE=()
  US_UPDATED=() US_FAILED=() US_WOULD=()
  MOVED_DURING=() NOOP_UNVERIFIED=0
  PATH_ROWS=() OTHER_PATHS_JSON='{"updated":[],"failed":[],"not_moved":[],"would_update":[]}'
  WITHHELD=() DOWNGRADED=() INSTALLED_ROWS=() ENABLED_ROWS=() PROJECT_ROWS=() RECOVERED_ROWS=()
  INSTALL_GAP="[]" ENABLE_GAP="[]" NORMALIZE_JSON="null" CACHE_JSON="null"
  SELF_UPDATED="false" SELF_UPDATE="null" INSTALL_DEFERRED="false" STOPPED_BEFORE_INSTALL="false"
  REFRESH_RC="null" REFRESH_OUT="" REFRESH_REASON="" REFRESH_PREDICTED="false" REFRESH_FAILED=0
  REFRESH_SKIP_JSON="null"
  CATALOG_LAST_UPDATED="" PROJECT_ROOT_JSON="null" SOURCE_PULL_JSON="null"
  T_PRR_S="" T_PRR_E="" T_MU_S="" T_MU_E="" T_IR_S="" T_IR_E="" T_OP_S="" T_OP_E="" T_US_S="" T_US_E=""
  T_PI_S="" T_PI_E="" T_IE_S="" T_IE_E="" T_CC_S="" T_CC_E="" T_PR_S="" T_PR_E=""
  T_FN_S="" T_MP_S="" T_MP_E=""
  CACHE_CHECK_RAN=0
  CLI_CALLS=0 CLI_MS=0
}
reset_marketplace_state

persist_first_pass_rows() {
  local mp="$1" ir_f us_f errs persisted
  json_array_of ir_f ${IR_FAILED[@]+"${IR_FAILED[@]}"}
  json_array_of us_f ${US_FAILED[@]+"${US_FAILED[@]}"}
  json_strings_of errs ${MP_ERRORS[@]+"${MP_ERRORS[@]}"}
  json_object_file "$RUN_DIR/.first-pass-args.$mp.json" \
    errors "$errs" ir_failed "$ir_f" us_failed "$us_f" source_pull "$SOURCE_PULL_JSON" \
    refresh_skipped "$REFRESH_SKIP_JSON"
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to persisted -c \
    --arg refresh_rc "$REFRESH_RC" \
    --arg refresh_out "$REFRESH_OUT" \
    --arg refresh_reason "$REFRESH_REASON" \
    --arg refresh_predicted "$REFRESH_PREDICTED" \
    '{errors, ir_failed, us_failed, source_pull,
      refresh: {rc: (if $refresh_rc == "null" or $refresh_rc == "" then null
                     else ($refresh_rc | tonumber? // $refresh_rc) end),
                output: $refresh_out,
                reason: $refresh_reason,
                predicted: ($refresh_predicted == "true"),
                skipped: .refresh_skipped}}' "$RUN_DIR/.first-pass-args.$mp.json"
  printf '%s\n' "$persisted" >"$RUN_DIR/first-pass.$mp.json"
}

restore_first_pass_rows() {
  local mp="$1" lines line
  local sidecar="$RUN_DIR/first-pass.$mp.json"
  [[ -f "$sidecar" ]] || return 0
  jq_to lines -r '.errors[]?' "$sidecar"
  while IFS= read -r line; do
    [[ -n "$line" ]] && MP_ERRORS+=("$line")
  done <<<"$lines"
  jq_to lines -c '.ir_failed[]?' "$sidecar"
  while IFS= read -r line; do
    [[ -n "$line" ]] && IR_FAILED+=("$line")
  done <<<"$lines"
  jq_to lines -c '.us_failed[]?' "$sidecar"
  while IFS= read -r line; do
    [[ -n "$line" ]] && US_FAILED+=("$line")
  done <<<"$lines"
  jq_to REFRESH_OUT -r '.refresh.output // ""' "$sidecar"
  jq_to REFRESH_REASON -r '.refresh.reason // ""' "$sidecar"
  jq_to REFRESH_PREDICTED -r 'if .refresh.predicted == true then "true" else "false" end' "$sidecar"
  jq_to REFRESH_RC -r 'if .refresh.rc == null then "null" else (.refresh.rc | tostring) end' "$sidecar"
  jq_to REFRESH_SKIP_JSON -c '.refresh.skipped // null' "$sidecar"
  [[ -n "$REFRESH_SKIP_JSON" ]] || REFRESH_SKIP_JSON="null"
  jq_to SOURCE_PULL_JSON -c '.source_pull // null' "$sidecar"
  [[ -n "$SOURCE_PULL_JSON" ]] || SOURCE_PULL_JSON="null"
}

name_listed() {
  local name
  for name in ${2//,/ }; do
    [[ "$name" == "$1" ]] && return 0
  done
  return 1
}

# shellcheck disable=SC2016  # a jq program: every $var is a jq variable
FF_REFUSAL_DEF='def ff_refusal:
  if . == null then "not a directory source"
  elif .state == "not_a_repo" then "not a git work tree"
  elif .state == "detached" then "detached HEAD"
  elif .state == "no_upstream" then "no upstream branch"
  elif .dirty == true then "tracked files modified"
  elif (.ahead // 0) > 0 and (.behind // 0) > 0 then
    "diverged from \(.upstream): \(.ahead) ahead, \(.behind) behind"
  elif (.ahead // 0) > 0 then "\(.ahead) local commit(s) ahead of \(.upstream)"
  elif (.behind // 0) == 0 then "not behind \(.upstream)"
  else "" end;'

source_fast_forward() {
  local mp="$1" snapshot="$2" src="" checkout="null" refusal="" path="" from="" to="" rc=0 out="" reason=""
  local sink="$RUN_DIR/.last-git-out"
  if [[ -n "$SOURCE_PULL_OFF" ]]; then
    refusal="$SOURCE_PULL_OFF"
  else
    jq_to src -r '.marketplace.source // ""' "$snapshot"
    source_checkout checkout "$src"
    if ! jq_to path -r 'if type == "object" then .path // "" else "" end' <<<"${checkout:-null}" ||
      { [[ -z "$path" ]] && [[ "$src" == directory:* ]]; }; then
      refusal="source checkout unreadable"
    else
      jq_to refusal -r "$FF_REFUSAL_DEF"' ff_refusal' <<<"${checkout:-null}" || refusal="source checkout unreadable"
    fi
  fi
  if [[ -n "$refusal" ]]; then
    echo "fast-forward refused for $mp: $refusal" >>"$JOURNAL_LOG"
    # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
    jq_to SOURCE_PULL_JSON -c -n --arg r "$refusal" '{status: "refused", reason: $r}'
    return 0
  fi
  from=$(git -C "$path" rev-parse HEAD 2>/dev/null)
  {
    echo "\$ git -C $path pull --ff-only"
    GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never git -C "$path" pull --ff-only 2>&1 </dev/null
  } | tee -a "$JOURNAL_LOG" >"$sink"
  rc=${PIPESTATUS[0]}
  out=$(<"$sink")
  to=$(git -C "$path" rev-parse HEAD 2>/dev/null)
  if ((rc == 0)); then
    # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
    jq_to SOURCE_PULL_JSON -c -n --arg f "$from" --arg t "$to" \
      '{status: "pulled", reason: "", from: $f, to: $t}'
  else
    reason=$(cli_outcome_line "${out//$'\r'/}")
    trunc reason "$reason"
    # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
    jq_to SOURCE_PULL_JSON -c -n --argjson rc "$rc" --arg r "$reason" --arg f "$from" --arg t "$to" \
      '{status: "failed", rc: $rc, reason: $r, from: $f, to: $t}'
  fi
}

refresh_skip_check() {
  local mp="$1"
  local fields=""
  local loc="" kind="" repo="" url="" pin=""
  local origin="" origin_rc=0 head="" branch="" dirty="" ref="HEAD" remote="" sha="" name="" remote_sha=""
  REFRESH_SKIP_JSON="null"
  [[ -f "$MARKETPLACES_JSON" ]] || return 0
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to fields -r --arg mp "$mp" '
    # A source key this check does not know could be a pin it would ignore.
    .[$mp] | if type == "object" and (.source | type) == "object"
                and ((.source | keys) - ["source", "repo", "url", "ref", "path"]) == [] then
      [.installLocation, .source.source, .source.repo, .source.url, .source.ref]
      | map(. // "" | tostring | gsub("[\u001f\n]"; " ")) | join("\u001f")
    else "" end' "$MARKETPLACES_JSON" 2>/dev/null || return 0
  [[ -n "$fields" ]] || return 0
  IFS=$'\x1f' read -r loc kind repo url pin <<<"$fields"
  loc="${loc//\\//}"
  [[ "$kind" == "github" || "$kind" == "git" ]] || return 0
  [[ -n "$loc" && -e "$loc/.git" ]] || return 0
  local g=(git --no-optional-locks -C "$loc")
  origin=$("${g[@]}" remote get-url origin 2>/dev/null) || return 0
  origin="${origin%/}"
  origin="${origin%.git}"
  if [[ "$kind" == "github" ]]; then
    [[ -n "$repo" ]] || return 0
    shopt -s nocasematch
    [[ "$origin" == *[/@]github.com[/:]"$repo" ]]
    origin_rc=$?
    shopt -u nocasematch
    ((origin_rc == 0)) || return 0
  else
    url="${url%/}"
    [[ -n "$url" && "$origin" == "${url%.git}" ]] || return 0
  fi
  dirty=$("${g[@]}" status --porcelain 2>/dev/null) || return 0
  [[ -z "$dirty" ]] || return 0
  head=$("${g[@]}" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null) || return 0
  if [[ -n "$pin" ]]; then
    branch=$("${g[@]}" symbolic-ref -q --short HEAD 2>/dev/null) || return 0
    [[ "$branch" == "$pin" ]] || return 0
    ref="refs/heads/$pin"
  fi
  local ssh_env=()
  if [[ -z "${GIT_SSH_COMMAND:-}" && -z "${GIT_SSH:-}" ]] &&
    ! "${g[@]}" config --get core.sshCommand >/dev/null 2>&1; then
    ssh_env=("GIT_SSH_COMMAND=ssh -o BatchMode=yes")
  fi
  remote=$(env ${ssh_env[@]+"${ssh_env[@]}"} GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never \
    "${g[@]}" ls-remote origin "$ref" 2>/dev/null </dev/null) || return 0
  while IFS=$'\t' read -r sha name; do
    if [[ "${name//$'\r'/}" == "$ref" ]]; then
      remote_sha="$sha"
      break
    fi
  done <<<"$remote"
  [[ "$remote_sha" == "$head" ]] || return 0
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  if ! jq_to REFRESH_SKIP_JSON -c -n --arg h "$head" --arg r "$ref" '{head: $h, ref: $r}'; then
    REFRESH_SKIP_JSON="null"
    return 0
  fi
  echo "marketplace refresh skipped for $mp: $loc is at $head, the commit origin $ref points at" >>"$JOURNAL_LOG"
}

slurp_to() {
  local __sl=""
  [[ -f "$2" ]] && IFS= read -r -d '' __sl <"$2"
  printf -v "$1" '%s' "$__sl"
}

fingerprint_to() {
  local __fp_p __fp_l __fp_st="" __fp_out="" __fp_i=0
  local -a __fp_paths=() __fp_lines=()
  while IFS= read -r __fp_p; do __fp_paths+=("$__fp_p"); done <"$2"
  if ((${#__fp_paths[@]} > 0)); then
    # portability-ok: GNU-first rung of a dual-dialect ladder; the BSD -f spelling follows on empty output
    __fp_st=$(stat -L -c '%.9Y|%.9Z|%s|%n' -- "${__fp_paths[@]}" 2>/dev/null)
    [[ -n "$__fp_st" ]] || __fp_st=$(stat -L -f '%Fm|%Fc|%z|%N' -- "${__fp_paths[@]}" 2>/dev/null)
  fi
  [[ -z "$__fp_st" ]] || while IFS= read -r __fp_l; do __fp_lines+=("$__fp_l"); done <<<"$__fp_st"
  for __fp_p in ${__fp_paths[@]+"${__fp_paths[@]}"}; do
    __fp_l="${__fp_lines[__fp_i]:-}"
    if [[ -n "$__fp_l" && "${__fp_l#*|*|*|}" == "$__fp_p" ]]; then
      __fp_i=$((__fp_i + 1))
    elif [[ -e "$__fp_p" ]]; then
      __fp_i=-1
      break
    else
      __fp_l="absent|$__fp_p"
    fi
    if [[ "$__fp_l" != absent\|* && ! "$__fp_l" =~ ^[0-9]+\.[0-9]+\|[0-9]+\.[0-9]+\| ]]; then
      __fp_i=-1
      break
    fi
    __fp_out+="${__fp_out:+$'\n'}$__fp_l"
  done
  ((__fp_i == ${#__fp_lines[@]})) || __fp_out=""
  printf -v "$1" '%s' "$__fp_out"
}

inputs_older_than() {
  local line m c
  while IFS= read -r line; do
    [[ "$line" != absent\|* ]] || continue
    stamp_us m "${line%%|*}"
    line="${line#*|}"
    stamp_us c "${line%%|*}"
    ((m < $2 && c < $2)) || return 1
  done <<<"$1"
}

SNAPSHOT_KEY="$PWD|${HOME:-}|${CLAUDE_PROJECT_DIR:-}|$CLAUDE_PLUGIN_ROOT|${FLEET_STATE_INSTALLED_JSON:-}"
SNAPSHOT_KEY+="|${FLEET_STATE_MARKETPLACES_JSON:-}|${FLEET_STATE_USER_SETTINGS:-}|${FLEET_STATE_CATALOG_DIR:-}"
STORE_MARGIN_S=2
[[ ! "${SYNC_FLEET_STATE_STORE_MARGIN_S:-}" =~ ^[0-9]{1,6}$ ]] || STORE_MARGIN_S=$((10#$SYNC_FLEET_STATE_STORE_MARGIN_S))
fleet_snapshot() {
  local mp="$1" out="$2" label="$3"
  local c="$RUN_DIR/fs-cache.$mp"
  local rc text list_pre="" list_post fp_pre="" fp_post stored t_s t_e
  local key="$SNAPSHOT_KEY"
  slurp_to text "$c.key"
  if [[ "$text" == "$key" && -f "$c.list" ]]; then
    slurp_to list_pre "$c.list"
    fingerprint_to fp_pre "$c.list"
    slurp_to stored "$c.fp"
    if [[ -n "$fp_pre" && "$fp_pre" == "$stored" ]]; then
      slurp_to text "$c.json"
      printf '%s' "$text" >"$out"
      slurp_to text "$c.from"
      echo "# fleet-state reuse $label: inputs unchanged since the $text read" >>"$JOURNAL_LOG"
      return 0
    fi
  fi
  clock_into t_s
  FLEET_STATE_READ_LIST="$c.next" "$FLEET_STATE" --marketplace "$mp" >"$out" 2>"$RUN_DIR/.fs-err"
  rc=$?
  clock_into t_e
  stamp_us t_s "$t_s"
  stamp_us t_e "$t_e"
  t_e=$(((t_e - t_s) / 1000))
  printf '# fleet-state read %s: elapsed %d.%03ds, exit %d, ' "$label" $((t_e / 1000)) $((t_e % 1000)) "$rc" >>"$JOURNAL_LOG"
  : >"$c.fp"
  slurp_to list_post "$c.next"
  fp_post=""
  ((rc != 0)) || [[ -z "$list_post" ]] || fingerprint_to fp_post "$c.next"
  printf '%s' "$key" >"$c.key"
  printf '%s' "$list_post" >"$c.list"
  if [[ -n "$fp_post" && -n "$list_pre" && "$list_post" == "$list_pre" && "$fp_post" == "$fp_pre" ]] &&
    inputs_older_than "$fp_post" $((t_s - STORE_MARGIN_S * 1000000)); then
    slurp_to text "$out"
    printf '%s' "$text" >"$c.json"
    printf '%s' "$fp_post" >"$c.fp"
    printf '%s' "$label" >"$c.from"
    echo "stored for reuse" >>"$JOURNAL_LOG"
  else
    echo "not stored: a failed read, no fingerprint, no earlier read to compare, or an input changed during or within $STORE_MARGIN_S s before it" >>"$JOURNAL_LOG"
  fi
  return "$rc"
}

fleet_read() {
  local label="$3"
  local rc=0
  local text
  fleet_snapshot "$@"
  rc=$?
  if ((rc != 0)); then
    text=$(<"$RUN_DIR/.fs-err")
    mp_error "$label fleet-state read failed (exit $rc): ${text//$'\r'/}"
  fi
  return "$rc"
}

withheld_add() {
  WITHHELD+=("$(jq -c -n --arg id "$1" --arg sc "$2" --arg o "$3" --arg n "$4" \
    '{id: $id, scope: $sc, installed: $o, catalog: $n}')")
}

us_failed_add() {
  local reason out
  reason=$(cli_outcome_line "$CLI_OUT")
  trunc out "$CLI_OUT"
  US_FAILED+=("$(jq -c -n --arg id "$1" --argjson rc "$CLI_RC" --arg out "$out" \
    --arg reason "$reason" '{id: $id, rc: $rc, output: $out, reason: $reason}')")
}

ir_stopped_add() {
  IR_FAILED+=("$(jq -c -n --arg id "$1" --arg sc "$2" --arg path "$3" --arg reason "$4" \
    '{id: $id, scope: $sc, rc: 0, output: "", path: $path, stopped: true, reason: $reason}')")
}

run_marketplace() {
  local mp="$1"
  reset_marketplace_state
  clock_into T_MP_S
  ((ONLY_INSTALL_MODE == 1)) || : >"$RUN_DIR/moves.$mp.tsv"

  local rc dg_rc id scope old new result row out reason
  local pre_refresh="$RUN_DIR/pre-refresh.$mp.json"

  if ((ONLY_INSTALL_MODE == 0)); then
    if [[ ! -f "$pre_refresh" ]]; then
      clock_into T_PRR_S
      fleet_read "$mp" "$pre_refresh" pre-refresh
      rc=$?
      clock_into T_PRR_E
      if ((rc != 0)); then
        emit_marketplace_block "$mp"
        return 0
      fi
    elif [[ "$mp" == "$MAIN_READ_MP" ]]; then
      T_PRR_S="$MAIN_READ_S"
      T_PRR_E="$MAIN_READ_E"
      T_MP_S="$MAIN_READ_S"
    fi

    if [[ "$MODE" == "audit" ]]; then
      predict_cli "claude plugin marketplace update $mp"
      REFRESH_PREDICTED="true"
      REFRESH_RC="null"
      trunc REFRESH_OUT "$CLI_OUT"
    else
      clock_into T_MU_S
      if ((PULL_SOURCES_SET == 1)) && name_listed "$mp" "$PULL_SOURCES"; then
        source_fast_forward "$mp" "$pre_refresh"
      fi
      refresh_skip_check "$mp"
      if [[ "$REFRESH_SKIP_JSON" != "null" ]]; then
        clock_into T_MU_E
      else
        run_cli "claude plugin marketplace update $mp" plugin marketplace update "$mp"
        clock_into T_MU_E
        REFRESH_RC="$CLI_RC"
        trunc REFRESH_OUT "$CLI_OUT"
        REFRESH_REASON=$(cli_outcome_line "$CLI_OUT")
        if ((CLI_RC != 0)); then
          REFRESH_FAILED=1
          mp_error "marketplace refresh failed (exit $CLI_RC): ${REFRESH_REASON}, so the catalog may be stale and install/enable maintenance is deferred"
        fi
      fi
    fi
  else
    if [[ -f "$RUN_DIR/pre.$mp.json" ]]; then
      jq_to CATALOG_LAST_UPDATED -r '.marketplace.lastUpdated // ""' "$RUN_DIR/pre.$mp.json"
      jq_to PROJECT_ROOT_JSON -c '.project_root' "$RUN_DIR/pre.$mp.json"
      [[ -n "$PROJECT_ROOT_JSON" ]] || PROJECT_ROOT_JSON="null"
    fi
    if ((ALLOW_DOWNGRADE == 0)) && [[ -f "$RUN_DIR/downgrades.$mp.txt" ]]; then
      while IFS=$'\t' read -r id scope old new; do
        id="${id//$'\r'/}"
        [[ -n "$id" ]] || continue
        withheld_add "$id" "${scope//$'\r'/}" "${old//$'\r'/}" "${new//$'\r'/}"
      done <"$RUN_DIR/downgrades.$mp.txt"
    fi
    restore_first_pass_rows "$mp"
  fi

  if ((ONLY_INSTALL_MODE == 0)); then
    clock_into T_IR_S
    fleet_read "$mp" "$RUN_DIR/pre.$mp.json" pre
    rc=$?
    if ((rc != 0)); then
      emit_marketplace_block "$mp"
      return 0
    fi
    jq_to CATALOG_LAST_UPDATED -r '.marketplace.lastUpdated // ""' "$RUN_DIR/pre.$mp.json"
    jq_to PROJECT_ROOT_JSON -c '.project_root' "$RUN_DIR/pre.$mp.json"
    [[ -n "$PROJECT_ROOT_JSON" ]] || PROJECT_ROOT_JSON="null"

    project_ids update-candidates-project "$RUN_DIR/pre.$mp.json" "$RUN_DIR/ids.pre.$mp.txt"
    rc=$?
    if ((rc != 0)); then
      mp_error "in-repo projection failed (exit $rc), step not run: $(proj_err)"
    else
      local live_path=""
      if [[ "$MODE" == "audit" ]]; then
        # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
        jq_to live_path -r '
          def fold: gsub("\\\\"; "/") | rtrimstr("/");
          (.marketplace.source // "") as $s | (.project_root // "" | fold) as $r
          # fleet-state folds the project root to lower case after the drive letter
          # on Windows, where the recorded source keeps its case: compare folded.
          | ($r | test("^[A-Za-z]:")) as $ci
          | def eqp($a; $b): if $ci then ($a | ascii_downcase) == ($b | ascii_downcase) else $a == $b end;
          if ($s | startswith("directory:")) and $r != "" then
              ($s | sub("^directory:"; "") | fold) as $p
              | if eqp($p; $r) or eqp(($p | .[0:($r | length) + 1]); $r + "/") then $p else "" end
            else "" end' "$RUN_DIR/pre.$mp.json"
      fi
      local ir_root=""
      local ir_before=""
      local ir_after=""
      local ir_stopped=0
      jq_to ir_root -r '.project_root // ""' "$RUN_DIR/pre.$mp.json"
      ir_root="${ir_root//\\//}"
      if [[ "$MODE" == "sync" && -n "$ir_root" ]]; then
        settings_state ir_before "$ir_root"
      fi
      while IFS=$'\t' read -r id scope; do
        id="${id//$'\r'/}"
        scope="${scope//$'\r'/}"
        [[ -n "$id" ]] || continue
        if ((ir_stopped == 1)); then
          ir_stopped_add "$id" "$scope" "$ir_root" \
            "not tried: the .claude/ settings in this path changed after an earlier call"
          continue
        fi
        version_at old "$RUN_DIR/pre.$mp.json" "$id" "$scope"
        if [[ "$MODE" == "audit" && -n "$live_path" ]]; then
          IR_LIVE+=("$(jq -c -n --arg id "$id" --arg sc "$scope" --arg old "$old" --arg path "$live_path" \
            '{id: $id, scope: $sc, installed: $old, path: $path}')")
          continue
        fi
        if [[ "$MODE" == "audit" ]]; then
          predict_cli "claude plugin update $id -s $scope"
          IR_WOULD+=("$(jq -c -n --arg id "$id" --arg sc "$scope" --arg old "$old" \
            '{id: $id, scope: $sc, installed: $old}')")
          continue
        fi
        run_cli "claude plugin update $id -s $scope --json" plugin update "$id" -s "$scope" --json
        if [[ -n "$ir_root" ]]; then
          settings_state ir_after "$ir_root"
          if [[ "$ir_after" != "$ir_before" ]]; then
            ir_stopped=1
            ir_stopped_add "$id" "$scope" "$ir_root" \
              "the .claude/ settings in this path changed after this call, so the path was stopped"
            continue
          fi
        fi
        if ((CLI_RC != 0)); then
          reason=$(cli_outcome_line "$CLI_OUT")
          trunc out "$CLI_OUT"
          IR_FAILED+=("$(jq -c -n --arg id "$id" --arg sc "$scope" --argjson rc "$CLI_RC" \
            --arg out "$out" --arg reason "$reason" \
            '{id: $id, scope: $sc, rc: $rc, output: $out, reason: $reason}')")
          continue
        fi
        cli_update_result result new "$CLI_OUT"
        printf 'in_repo\t%s\t%s\t%s\t%s\t%s\n' "$id" "$scope" "${old:--}" "${new:--}" "$result" \
          >>"$RUN_DIR/moves.$mp.tsv"
      done <"$RUN_DIR/ids.pre.$mp.txt"
    fi
    clock_into T_IR_E
  fi

  if ((ONLY_INSTALL_MODE == 0)); then
    clock_into T_US_S
    fleet_read "$mp" "$RUN_DIR/mid.$mp.json" mid
    rc=$?
    if ((rc != 0)); then
      emit_marketplace_block "$mp"
      return 0
    fi

    T_OP_S="$T_US_S"
    other_paths_step "$mp"
    clock_into T_OP_E
    T_US_S="$T_OP_E"

    project_ids downgrade-candidates "$RUN_DIR/mid.$mp.json" "$RUN_DIR/downgrades.$mp.txt"
    dg_rc=$?
    if ((dg_rc != 0)); then
      mp_error "downgrade projection failed (exit $dg_rc): $(proj_err)"
      : >"$RUN_DIR/downgrades.$mp.txt"
    fi

    project_ids update-candidates-user "$RUN_DIR/mid.$mp.json" "$RUN_DIR/ids.mid.$mp.txt"
    rc=$?
    if ((rc != 0)); then
      mp_error "user-scope projection failed (exit $rc), sweep not run: $(proj_err)"
    else
      local sweep_rows=""
      # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
      jq_to sweep_rows -r --rawfile ids "$RUN_DIR/ids.mid.$mp.txt" '
        . as $s
        | $ids | gsub("\r"; "") | split("\n")[] | select(length > 0) as $id
        | $id + "\u001f"
          + (first($s.installed[]? | select(.id == $id and .scope == "user") | .version) // "" | tostring)' \
        "$RUN_DIR/mid.$mp.json" || sweep_rows=$(<"$RUN_DIR/ids.mid.$mp.txt")
      sweep_rows="${sweep_rows//$'\r'/}"
      while IFS=$'\x1f' read -r id old; do
        [[ -n "$id" ]] || continue
        if [[ "$MODE" == "audit" ]]; then
          predict_cli "claude plugin update $id -s user"
          US_WOULD+=("$(jq -c -n --arg id "$id" --arg old "$old" '{id: $id, installed: $old}')")
          continue
        fi
        run_cli "claude plugin update $id -s user --json" plugin update "$id" -s user --json
        if ((CLI_RC != 0)); then
          us_failed_add "$id"
          continue
        fi
        cli_update_result result new "$CLI_OUT"
        printf 'user_sweep\t%s\t%s\t%s\t%s\t%s\n' "$id" user "${old:--}" "${new:--}" "$result" \
          >>"$RUN_DIR/moves.$mp.tsv"
      done <<<"$sweep_rows"
    fi

    while IFS=$'\t' read -r id scope old new; do
      id="${id//$'\r'/}"
      [[ -n "$id" ]] || continue
      scope="${scope//$'\r'/}"
      old="${old//$'\r'/}"
      new="${new//$'\r'/}"
      if ((ALLOW_DOWNGRADE == 1)) && [[ "$MODE" == "sync" ]]; then
        run_cli "claude plugin update $id -s $scope --json   # downgrade $old -> $new" \
          plugin update "$id" -s "$scope" --json
        if ((CLI_RC != 0)); then
          us_failed_add "$id"
          continue
        fi
        local applied=""
        local applied_result=""
        cli_move_result applied_result "$CLI_OUT"
        [[ "$applied_result" == "updated" ]] && cli_reported_version applied "$CLI_OUT"
        [[ -n "$applied" ]] || applied="$new"
        printf 'user_sweep\t%s\t%s\t%s\t%s\t%s\n' "$id" "$scope" "${old:--}" "${applied:--}" updated \
          >>"$RUN_DIR/moves.$mp.tsv"
      else
        withheld_add "$id" "$scope" "$old" "$new"
      fi
    done <"$RUN_DIR/downgrades.$mp.txt"
    clock_into T_US_E
  fi

  clock_into T_PI_S
  fleet_read "$mp" "$RUN_DIR/pre-install.$mp.json" pre-install
  rc=$?
  if ((rc == 0)); then
    project_ids missing-user-install "$RUN_DIR/pre-install.$mp.json" "$RUN_DIR/ids.pre-install.$mp.txt"
    rc=$?
    if ((rc != 0)); then
      mp_error "install-gap projection failed (exit $rc), Step 4 not run: $(proj_err)"
    else
      json_lines INSTALL_GAP "$RUN_DIR/ids.pre-install.$mp.txt"
    fi
    project_ids missing-enabled "$RUN_DIR/pre-install.$mp.json" "$RUN_DIR/ids.gap-enable.$mp.txt"
    rc=$?
    if ((rc != 0)); then
      mp_error "enable-gap projection failed (exit $rc): $(proj_err)"
    else
      json_lines ENABLE_GAP "$RUN_DIR/ids.gap-enable.$mp.txt"
    fi
  fi

  local gap_count
  local enable_gap_count
  jq_to gap_count -r 'length' <<<"$INSTALL_GAP"
  jq_to enable_gap_count -r 'length' <<<"$ENABLE_GAP"
  clock_into T_PI_E

  recover_pending "$mp"

  if ((REFRESH_FAILED == 1)); then
    INSTALL_DEFERRED="true"
  elif [[ "$MODE" == "sync" && "$INSTALL_NEW" == "ask" ]] && ((gap_count > 0)) && ((ONLY_INSTALL_MODE == 0)); then
    STOPPED_BEFORE_INSTALL="true"
  elif ((gap_count > 0)) || ((enable_gap_count > 0)) || ((ONLY_INSTALL_MODE == 1)); then
    clock_into T_IE_S
    run_install_step "$mp" "$gap_count"
    run_enable_step "$mp"
    clock_into T_IE_E
  fi

  if [[ "$STOPPED_BEFORE_INSTALL" != "true" ]]; then
    clock_into T_CC_S
    cache_content_block "$mp"
    if ((CACHE_CHECK_RAN == 1)); then
      clock_into T_CC_E
    else
      T_CC_S=""
    fi
  fi

  clock_into T_PR_S
  fleet_read "$mp" "$RUN_DIR/post.$mp.json" post
  clock_into T_PR_E

  clock_into T_FN_S
  finalize_moves "$mp"
  finalize_other_paths "$mp"

  local own
  own=$(own_plugin_name)
  if [[ -n "$own" ]]; then
    for row in ${IR_UPDATED[@]+"${IR_UPDATED[@]}"} ${US_UPDATED[@]+"${US_UPDATED[@]}"} \
      ${DOWNGRADED[@]+"${DOWNGRADED[@]}"} ${MOVED_DURING[@]+"${MOVED_DURING[@]}"}; do
      case "$row" in
      *"\"id\":\"$own@"*)
        SELF_UPDATED="true"
        if [[ "$SELF_UPDATE" == "null" ]]; then
          jq_to SELF_UPDATE -c '{id, scope, old, new}' <<<"$row"
        fi
        ;;
      *) ;;
      esac
    done
  fi

  emit_marketplace_block "$mp"
}

PENDING_FILE=""
pending_path() {
  local root
  if [[ "$MODE" == "audit" ]]; then
    return 0
  elif ((ONLY_INSTALL_MODE == 1)); then
    root="${RUN_DIR%/}"
    root="${root%/*}"
  else
    root="${JOURNAL_ROOT%/}"
  fi
  PENDING_FILE="${root%/*}/pending-enable.txt"
}

pending_add() {
  [[ -n "$PENDING_FILE" ]] || return 0
  mkdir -p "${PENDING_FILE%/*}" 2>/dev/null
  grep -qxF -- "$1" "$PENDING_FILE" 2>/dev/null || printf '%s\n' "$1" >>"$PENDING_FILE"
}

pending_remove() {
  [[ -n "$PENDING_FILE" && -f "$PENDING_FILE" ]] || return 0
  grep -vxF -- "$1" "$PENDING_FILE" >"$PENDING_FILE.next" 2>/dev/null
  mv "$PENDING_FILE.next" "$PENDING_FILE"
}

recover_pending() {
  local mp="$1" id state
  [[ -n "$PENDING_FILE" && -f "$PENDING_FILE" && "$MODE" == "sync" ]] || return 0
  [[ -f "$RUN_DIR/pre-install.$mp.json" ]] || return 0
  while IFS= read -r id; do
    id="${id//$'\r'/}"
    [[ -n "$id" && "$id" == *"@$mp" ]] || continue
    case ",${ONLY_INSTALL// /,}," in *",$id,"*) continue ;; *) ;; esac
    # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
    jq_to state -r --arg id "$id" '
      (any(.installed[]?; .id == $id and .scope == "user")) as $in
      | .enabled[$id] as $en
      | if ($in | not) then "absent" elif $en == false then "off" else "on" end' \
      "$RUN_DIR/pre-install.$mp.json" || continue
    case "$state" in
    off)
      enable_one "$id" user
      if ((CLI_RC == 0)); then
        pending_remove "$id"
        RECOVERED_ROWS+=("$(jq -c -n --arg id "$id" '{id: $id, outcome: "enabled"}')")
      else
        RECOVERED_ROWS+=("$(jq -c -n --arg id "$id" '{id: $id, outcome: "enable_failed"}')")
      fi
      ;;
    *) pending_remove "$id" ;;
    esac
  done <"$PENDING_FILE"
}

install_one() {
  local id="$1" out reason unset_cfg="null" disabled="false"
  run_cli "claude plugin install $id -s user --json" plugin install "$id" -s user --json
  reason=$(cli_outcome_line "$CLI_OUT")
  install_disabled_notice "$CLI_OUT" && disabled="true"
  INSTALLED_DISABLED="$disabled"
  trunc out "$CLI_OUT"
  unset_user_config_of unset_cfg "$CLI_OUT"
  INSTALLED_ROWS+=("$(jq -c -n --arg id "$id" --argjson rc "$CLI_RC" --arg out "$out" \
    --argjson unset "$unset_cfg" --argjson disabled "$disabled" --arg reason "$reason" \
    '{id: $id, rc: $rc, output: $out, unset_user_config: $unset, disabled_by_default: $disabled, reason: $reason}')")
}

run_install_step() {
  local mp="$1" gap_count="$2" id installed_any=0 wanted=""

  if ((ONLY_INSTALL_MODE == 1)); then
    wanted=$(printf '%s' "${ONLY_INSTALL//,/ }")
    for id in $wanted; do
      [[ "$id" == *"@$mp" ]] || continue
      pending_add "$id"
      install_one "$id"
      if ((CLI_RC != 0)); then
        pending_remove "$id"
        continue
      fi
      installed_any=1
      if [[ "$INSTALLED_DISABLED" == "true" ]]; then
        enable_one "$id" user
        ((CLI_RC == 0)) && pending_remove "$id"
      else
        pending_remove "$id"
      fi
    done
  elif ((gap_count > 0)) && [[ "$INSTALL_NEW" == "all" ]]; then
    while IFS= read -r id; do
      id="${id//$'\r'/}"
      [[ -n "$id" ]] || continue
      if [[ "$MODE" == "audit" ]]; then
        predict_cli "claude plugin install $id -s user"
        installed_any=1
        continue
      fi
      install_one "$id"
      ((CLI_RC == 0)) && installed_any=1
    done <"$RUN_DIR/ids.pre-install.$mp.txt"
  fi

  ((installed_any == 1)) || return 0
  local nrc=0
  local nout=""
  if [[ "$MODE" == "audit" ]]; then
    nout=$("$NORMALIZE" --check 2>&1) || nrc=$?
  else
    nout=$("$NORMALIZE" 2>&1) || nrc=$?
  fi
  trunc nout "${nout//$'\r'/}" 200

  local prc=0
  local pout=""
  local proot=""
  jq_to proot -r '. // ""' <<<"$PROJECT_ROOT_JSON"
  if [[ -n "$proot" && -f "$proot/.claude/settings.json" ]]; then
    pout=$("$NORMALIZE" --report-project "$proot/.claude/settings.json" 2>&1) || prc=$?
    trunc pout "${pout//$'\r'/}" 200
  fi

  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to NORMALIZE_JSON -c -n --argjson rc "$nrc" --arg out "$nout" --arg mode "$MODE" \
    --argjson prc "$prc" --arg pout "$pout" \
    '{rc: $rc, output: $out, checked_only: ($mode == "audit"),
      project_report: (if $pout == "" then null else {rc: $prc, output: $pout} end)}'
}

run_enable_step() {
  local mp="$1" rc id row has_user has_local has_project ppath

  fleet_snapshot "$mp" "$RUN_DIR/pre-enable.$mp.json" pre-enable
  rc=$?
  if ((rc != 0)); then
    mp_error "pre-enable fleet-state read failed (exit $rc), Step 5 not run"
    return 0
  fi

  project_ids missing-enabled "$RUN_DIR/pre-enable.$mp.json" "$RUN_DIR/ids.pre-enable.$mp.txt"
  rc=$?
  if ((rc != 0)); then
    mp_error "enable projection failed (exit $rc), Step 5 not run: $(proj_err)"
    return 0
  fi
  json_lines ENABLE_GAP "$RUN_DIR/ids.pre-enable.$mp.txt"

  while IFS= read -r id; do
    id="${id//$'\r'/}"
    [[ -n "$id" ]] || continue
    # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
    jq_to row -r --arg id "$id" '
      [.installed[]? | select(.id == $id)] as $r
      | [(any($r[]; .scope == "user") | tostring),
         (any($r[]; .scope == "local" and .currentProject == true) | tostring),
         (any($r[]; .scope == "project" and .currentProject == true) | tostring),
         (first($r[] | select(.scope == "project" and .currentProject == true) | .projectPath) // "")]
      | @tsv' "$RUN_DIR/pre-enable.$mp.json"
    IFS=$'\t' read -r has_user has_local has_project ppath <<<"$row"

    local enabled_here=0
    if [[ "$has_user" == "true" ]]; then
      enable_one "$id" user
      enabled_here=1
    fi
    if [[ "$has_local" == "true" ]]; then
      enable_one "$id" local
      enabled_here=1
    fi
    if [[ "$has_project" == "true" ]] && ((enabled_here == 0)); then
      PROJECT_ROWS+=("$(jq -c -n --arg id "$id" --arg p "$ppath" '{id: $id, project_path: $p}')")
    fi
  done <"$RUN_DIR/ids.pre-enable.$mp.txt"
}

enable_one() {
  local id="$1" scope="$2" out reason
  if [[ "$MODE" == "audit" ]]; then
    predict_cli "claude plugin enable $id -s $scope"
    ENABLED_ROWS+=("$(jq -c -n --arg id "$id" --arg sc "$scope" \
      '{id: $id, scope: $sc, rc: null, predicted: true}')")
    return 0
  fi
  run_cli "claude plugin enable $id -s $scope" plugin enable "$id" -s "$scope"
  reason=$(cli_outcome_line "$CLI_OUT")
  trunc out "$CLI_OUT"
  ENABLED_ROWS+=("$(jq -c -n --arg id "$id" --arg sc "$scope" --argjson rc "$CLI_RC" --arg out "$out" \
    --arg reason "$reason" \
    '{id: $id, scope: $sc, rc: $rc, output: $out, reason: $reason, predicted: false}')")
}

cache_content_block() {
  local mp="$1" rc=0 ids
  local report="$RUN_DIR/cache-content.$mp.json"

  if [[ ! -f "$report" ]]; then
    CACHE_CHECK_RAN=1
    "$CACHE_CHECK" --marketplace "$mp" --scope user >"$report" 2>"$RUN_DIR/.cc-err"
    rc=$?
  fi

  if ((rc == 0)) && jq -e 'has("checked")' "$report" >/dev/null 2>&1; then
    jq_to CACHE_JSON -c '{scope: (.scope // "user"), checked, match, stale_content, unverifiable,
      not_checked: (.not_checked // 0),
      stale_ids: [.installs[]? | select(.verdict == "stale-content") | .id],
      stale: [.installs[]? | select(.verdict == "stale-content")
              | {id, version, files_differ: ((.differing // 0) + (.missing_from_cache // 0)
                                             + (.extra_in_cache // 0)),
                 unreleased_changes: (.unreleased_changes // false)}],
      source: "json"}' "$report"
    return 0
  fi

  CACHE_CHECK_RAN=1
  "$CACHE_CHECK" --marketplace "$mp" --scope user --ids >"$RUN_DIR/cache-stale-ids.$mp.txt" 2>>"$RUN_DIR/.cc-err"
  rc=$?
  json_lines ids "$RUN_DIR/cache-stale-ids.$mp.txt"
  mp_error "cache-content JSON unusable, so the stale ids come from the checker's --ids form (exit $rc)"
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to CACHE_JSON -c \
    '. as $ids
    | {scope: "user", checked: null, match: null, stale_content: ($ids | length), unverifiable: null,
      not_checked: null, stale_ids: $ids,
      stale: ($ids | map({id: ., version: null, files_differ: null, unreleased_changes: null})),
      source: "ids-fallback"}' <<<"$ids"
}

finalize_moves() {
  local mp="$1" kind id scope old new result dir row line post_v ncat nlabel joined=""
  local post="$RUN_DIR/post.$mp.json"
  [[ -f "$RUN_DIR/moves.$mp.tsv" ]] || return 0
  if [[ -f "$post" ]]; then
    # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
    jq_to joined -r --rawfile moves "$RUN_DIR/moves.$mp.tsv" '
      . as $p
      | $moves | gsub("\r"; "") | split("\n")[] | select(length > 0)
      | . as $line | split("\t") as $f | $f[1] as $id | $f[2] as $sc
      | [$line,
         (first($p.installed[]? | select(.id == $id and .scope == $sc
            and ($sc == "user" or .currentProject == true)) | .version) // "" | tostring),
         ($p.catalog_versions[$id]? // "" | tostring),
         (first($p.installed[]? | select(.id == $id and .scope == $sc and .currentProject == true)
            | .label) // "" | tostring)]
      | join("\u001f")' "$post" 2>/dev/null || joined=""
  fi
  [[ -n "$joined" ]] || joined=$(<"$RUN_DIR/moves.$mp.tsv")
  joined="${joined//$'\r'/}"
  while IFS=$'\x1f' read -r line post_v ncat nlabel; do
    IFS=$'\t' read -r kind id scope old new result <<<"$line"
    [[ -n "$id" ]] || continue
    [[ "$old" == "-" ]] && old=""
    [[ "$new" == "-" ]] && new=""
    if [[ "$result" == "noop" ]]; then
      if ((ONLY_INSTALL_MODE == 0)) && [[ "$kind" == "in_repo" && "$scope" != "user" && -f "$post" ]]; then
        dir=""
        [[ -n "$post_v" && -n "$ncat" ]] && version_direction_to dir "$post_v" "$ncat"
        if [[ "$dir" == "forward" ]]; then
          IR_FAILED+=("$(jq -c -n --arg id "$id" --arg sc "$scope" --arg cur "$post_v" --arg cat "$ncat" --arg label "$nlabel" \
            '{id: $id, scope: $sc, rc: 0, output: "",
              reason: ("the CLI said already at the latest version, but this project'"'"'s record is still at \($cur) and the catalog reads \($cat): the update did not take"
                + (if $label == "" then "" else " (" + $label + ")" end))}')")
          continue
        fi
      fi
      if [[ -z "$old" || -z "$post_v" ]]; then
        NOOP_UNVERIFIED=$((NOOP_UNVERIFIED + 1))
        continue
      fi
      if [[ "$post_v" == "$old" ]]; then
        [[ -z "$new" || "$new" == "$old" ]] || NOOP_UNVERIFIED=$((NOOP_UNVERIFIED + 1))
        continue
      fi
      new="$post_v"
      version_direction_to dir "$old" "$new"
      [[ "$dir" == "same" ]] && continue
      move_row_to row "$id" "$scope" "$old" "$new" "$dir" "$kind"
      MOVED_DURING+=("$row")
      if [[ "$dir" == "backward" ]]; then
        downgrade_row_to row "$id" "$scope" "$old" "$new" concurrent
        DOWNGRADED+=("$row")
      fi
      continue
    fi
    if [[ -z "$new" && -f "$post" ]]; then
      new="$post_v"
      [[ "$new" == "$old" ]] && new=""
    fi
    if ((ONLY_INSTALL_MODE == 0)) && [[ "$kind" == "in_repo" && "$scope" != "user" &&
      "$result" == "updated" && -n "$new" && -n "$old" && -f "$post" ]]; then
      local moved=""
      if [[ "$post_v" == "$old" && "$new" != "$old" ]]; then
        local after_step2="$post"
        [[ -f "$RUN_DIR/mid.$mp.json" ]] && after_step2="$RUN_DIR/mid.$mp.json"
        if [[ -f "$RUN_DIR/pre.$mp.json" ]]; then
          # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
          jq_to moved -r -n --arg id "$id" --arg sc "$scope" \
            --slurpfile pre "$RUN_DIR/pre.$mp.json" --slurpfile post "$after_step2" \
            '[$post[0].installed[]? | select(.id == $id and .scope == $sc and .currentProject != true)
              | . as $r | select(([$pre[0].installed[]? | select(.id == $id and .scope == $sc
                  and .projectPath == $r.projectPath) | .version] | first) != $r.version)
              | .projectPath] | map("\"\(.)\"") | join(", ")'
        fi
        IR_FAILED+=("$(jq -c -n --arg id "$id" --arg sc "$scope" --arg old "$old" --arg new "$new" --arg moved "$moved" \
          '{id: $id, scope: $sc, rc: 0, output: "",
            reason: ("the CLI reported \($old) to \($new), but this project'"'"'s record is still at \($old): it updated "
              + (if $moved == "" then "another record of the id (a sibling worktree'"'"'s)" else $moved end) + " instead")}')")
        continue
      fi
    fi
    if [[ -z "$new" ]]; then
      new="unknown"
      dir="unknown"
    else
      version_direction_to dir "$old" "$new"
    fi
    case "$dir" in
    same) continue ;;
    backward)
      downgrade_row_to row "$id" "$scope" "$old" "$new"
      DOWNGRADED+=("$row")
      ;;
    *)
      move_row_to row "$id" "$scope" "$old" "$new" "$dir"
      if [[ "$kind" == "in_repo" ]]; then IR_UPDATED+=("$row"); else US_UPDATED+=("$row"); fi
      ;;
    esac
  done <<<"$joined"
}

report_extras() {
  local __var="$1"
  local mp="$2"
  local src=""
  for src in "$RUN_DIR/post.$mp.json" "$RUN_DIR/pre-install.$mp.json" "$RUN_DIR/pre.$mp.json" \
    "$RUN_DIR/pre-refresh.$mp.json"; do
    [[ -f "$src" ]] && break
    src=""
  done
  if [[ -z "$src" ]]; then
    jq_to "$__var" -c -n '{auto_update: null, catalog_source: null, user_scope_orphans: [],
      user_home_records: {total: 0, paths: []},
      delisted: [], delisted_project: [], delisted_settings_only: [],
      stale_project_records: {total: null, paths: null, by_parent: [], more_parents: 0, list_file: null},
      in_repo_records: null, in_repo_ids: [], divergences_here: null}'
    return 0
  fi
  local list_file=""
  local stale_list=""
  if [[ "$MODE" != "audit" ]] &&
    jq_to stale_list -c '[.installed[]? | select(.projectPathPresent == false)] | group_by(.projectPath)
      | map({path: .[0].projectPath, count: length})' "$src" &&
    [[ "$stale_list" != "[]" ]] &&
    printf '%s\n' "$stale_list" >"$RUN_DIR/stale-project-records.$mp.json"; then
    list_file="$RUN_DIR/stale-project-records.$mp.json"
  fi
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to "$__var" -c --argjson cap "$STALE_PARENT_ROWS" --arg list_file "$list_file" \
    --argjson left_to_step3a "$([[ "$MODE" == "audit" || "$UPDATE_OTHER_PATHS" == 0 ]] && echo true || echo false)" \
    "$ACTIONABLE_DEF$TRIPLE_DEF"'
    def parent: capture("^(?<p>.*[/\\\\])[^/\\\\]+[/\\\\]*$").p // .;
    ([.divergences[]? | actionable | .id]) as $act
    | .catalog_versions as $cv
    | ([.installed[]? | select(.currentProject == true) | .id]) as $here
    | ([.installed[]? | select(.projectPathPresent == false)]) as $absent
    # A home record still below the catalog, or with no version to compare: the
    # ones Step 3a could not move. Under --audit or with Step 3a off, the present
    # ones it would move are left out.
    | ([.installed[]? | select(.projectPathIsHome == true)
        | select(($cv[.id] | triple) as $c | (.version | triple) as $v
                 | ($c == null or $v == null or $v < $c)
                   and (($left_to_step3a and .projectPathPresent == true and $c != null and $v != null) | not))]) as $homes
    | {auto_update: .marketplace.autoUpdate,
       user_home_records: {total: ($homes | length),
                           paths: ($homes | map(.projectPath) | unique)},
       catalog_source: (.marketplace.source // null),
       user_scope_orphans: (.user_scope_orphans // []),
       delisted: (.delisted // []),
       delisted_project: (.delisted_project // []),
       delisted_settings_only: (.delisted_settings_only // []),
       stale_project_records: (($absent | group_by(.projectPath | parent)
                                | map({parent: (.[0].projectPath | parent), count: length,
                                       paths: (map(.projectPath) | unique | length)})
                                | sort_by(-.count, .parent)) as $groups
                               | {total: ($absent | length),
                                  paths: ($absent | map(.projectPath) | unique | length),
                                  project: ($absent | map(select(.scope == "project")) | length),
                                  "local": ($absent | map(select(.scope == "local")) | length),
                                  by_parent: $groups[:$cap],
                                  more_parents: ([0, ($groups | length) - $cap] | max),
                                  list_file: (if $list_file == "" then null else $list_file end)}),
       in_repo_records: ($here | length),
       in_repo_ids: $here,
       divergences_here: ($act | map(select(. as $i | $here | index($i))) | length)}' "$src"
}

source_checkout() {
  local __var="$1"
  local src="$2"
  local path
  local state="tracking"
  local branch=""
  local upstream=""
  local counts="0 0"
  local dirty=""
  if [[ "$src" != directory:* ]]; then
    printf -v "$__var" '%s' null
    return 0
  fi
  path="${src#directory:}"
  path="${path//\\//}"
  local g=(git --no-optional-locks -C "$path")
  if [[ "$("${g[@]}" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]]; then
    state="not_a_repo"
  else
    dirty=$("${g[@]}" status --porcelain --untracked-files=no 2>/dev/null | head -n 1)
    if ! branch=$("${g[@]}" symbolic-ref -q --short HEAD 2>/dev/null); then
      state="detached"
    elif ! upstream=$("${g[@]}" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) ||
      ! counts=$("${g[@]}" rev-list --left-right --count 'HEAD...@{u}' 2>/dev/null); then
      state="no_upstream"
      counts="0 0"
    fi
  fi
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to "$__var" -c -n --arg path "$path" --arg state "$state" --arg branch "$branch" \
    --arg upstream "$upstream" --arg counts "$counts" --arg dirty "$dirty" '
    [$counts | splits("[ \t]+") | tonumber? // 0] as $c
    | {path: $path, state: $state,
       branch: (if $branch == "" then null else $branch end),
       upstream: (if $state == "tracking" then $upstream else null end),
       ahead: (if $state == "tracking" then $c[0] else null end),
       behind: (if $state == "tracking" then $c[1] else null end),
       dirty: (if $state == "not_a_repo" then null else $dirty != "" end)}'
}

monitor_count_at() {
  local __mc_var="$1"
  local __mc_root="$2"
  local __mc_manifest="$2/.claude-plugin/plugin.json"
  local __mc_n="0"
  local __mc_spec=""
  local __mc_kind=""
  local __mc_path=""
  printf -v "$__mc_var" '%s' "0"
  [[ -d "$__mc_root" ]] || return 0
  local __mc_text=""
  [[ -f "$__mc_manifest" ]] && IFS= read -r -d '' __mc_text <"$__mc_manifest"
  if [[ -f "$__mc_manifest" && "$__mc_text" != *monitors* && "$__mc_text" != *'\u'* &&
    ! -f "$__mc_root/monitors/monitors.json" ]]; then
    __mc_kind="false"
  elif [[ -f "$__mc_manifest" ]]; then
    # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
    if ! jq_to __mc_spec -c '
      if (.experimental | type) == "object" and (.experimental | has("monitors")) then
        {present: true, value: .experimental.monitors}
      elif has("monitors") then
        {present: true, value: .monitors}
      else {present: false} end' "$__mc_manifest" 2>/dev/null; then
      __mc_kind="unreadable"
    else
      jq_to __mc_kind -r 'if .present == true then "true" else "false" end' <<<"$__mc_spec" 2>/dev/null || __mc_kind="unreadable"
    fi
    case "$__mc_kind" in
    true)
      # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
      jq_to __mc_n -r '
        .value
        | if type == "array" then "array:\(length)"
          elif type == "string" then "path:\(.)"
          else "other" end' <<<"$__mc_spec" 2>/dev/null || __mc_n="other"
      case "$__mc_n" in
      array:*) __mc_n="${__mc_n#array:}" ;;
      path:*)
        __mc_path="${__mc_n#path:}"
        __mc_path="${__mc_path#./}"
        __mc_n="0"
        [[ -f "$__mc_root/$__mc_path" ]] &&
          jq_to __mc_n -r 'if type == "array" then length else 0 end' "$__mc_root/$__mc_path" 2>/dev/null
        ;;
      *) __mc_n="0" ;;
      esac
      ;;
    false) ;;
    *)
      __mc_kind="unreadable"
      ;;
    esac
  fi
  if [[ "$__mc_kind" != "true" && "$__mc_kind" != "unreadable" && -f "$__mc_root/monitors/monitors.json" ]]; then
    jq_to __mc_n -r 'if type == "array" then length else 0 end' "$__mc_root/monitors/monitors.json" 2>/dev/null || __mc_n="0"
  fi
  [[ "$__mc_n" =~ ^[0-9]+$ ]] || __mc_n="0"
  printf -v "$__mc_var" '%s' "$__mc_n"
}

monitor_rows() {
  local __var="$1" mp="$2" row id scope path n paths="" j_id j_sc
  local post="$RUN_DIR/post.$mp.json"
  local rows=() moved=()
  printf -v "$__var" '%s' "[]"
  [[ -f "$post" ]] || return 0
  for row in ${IR_UPDATED[@]+"${IR_UPDATED[@]}"} ${US_UPDATED[@]+"${US_UPDATED[@]}"} \
    ${DOWNGRADED[@]+"${DOWNGRADED[@]}"} ${MOVED_DURING[@]+"${MOVED_DURING[@]}"}; do
    [[ "$row" == *'"kind":'* && "$row" == *'"direction":"backward"'* ]] && continue
    moved+=("$row")
  done
  ((${#moved[@]} > 0)) || return 0
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to paths -r -n --slurpfile p "$post" '
    $p[0] as $q
    | inputs | . as $r
    | [$r.id, $r.scope,
       (first($q.installed[]? | select(.id == $r.id and .scope == $r.scope
          and ($r.scope == "user" or .currentProject == true)) | .installPath) // "")]
    | join("\u001f")' <<<"$(printf '%s\n' "${moved[@]}")" || return 0
  while IFS=$'\x1f' read -r id scope path; do
    [[ -n "$path" ]] || continue
    monitor_count_at n "${path//\\//}"
    ((n > 0)) || continue
    json_string_to j_id "$id"
    json_string_to j_sc "$scope"
    rows+=("{\"id\":$j_id,\"scope\":$j_sc,\"monitors\":$n}")
  done <<<"$paths"
  json_array_of "$__var" ${rows[@]+"${rows[@]}"}
}

source_pull_field() {
  local __var="$1"
  local checkout="$2"
  if [[ "$SOURCE_PULL_JSON" != "null" ]]; then
    printf -v "$__var" '%s' "$SOURCE_PULL_JSON"
    return 0
  fi
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to "$__var" -c --arg off "$SOURCE_PULL_OFF" --arg mode "$MODE" "$FF_REFUSAL_DEF"'
    if . == null or (.behind // 0) == 0 then null
    else ff_refusal as $r
      | if $r != "" then {status: "skipped", reason: $r}
        elif $off != "" then {status: "skipped", reason: $off}
        elif $mode == "audit" then {status: "skipped", reason: "audit changes nothing"}
        else {status: "offered", reason: ""} end
    end' <<<"$checkout"
}

emit_marketplace_block() {
  local mp="$1" ir_u ir_f ir_w ir_l us_u us_f us_w wh dg moved inst en pr rec errs
  local unset_cfg installed_disabled monitors
  [[ -n "$T_FN_S" ]] || clock_into T_FN_S
  if ((ONLY_INSTALL_MODE == 0)); then
    persist_first_pass_rows "$mp"
  fi
  local reg_interval reg_rows div extras block checkout pull

  json_array_of ir_u ${IR_UPDATED[@]+"${IR_UPDATED[@]}"}
  json_array_of ir_f ${IR_FAILED[@]+"${IR_FAILED[@]}"}
  json_array_of ir_w ${IR_WOULD[@]+"${IR_WOULD[@]}"}
  json_array_of ir_l ${IR_LIVE[@]+"${IR_LIVE[@]}"}
  json_array_of us_u ${US_UPDATED[@]+"${US_UPDATED[@]}"}
  json_array_of us_f ${US_FAILED[@]+"${US_FAILED[@]}"}
  json_array_of us_w ${US_WOULD[@]+"${US_WOULD[@]}"}
  json_array_of wh ${WITHHELD[@]+"${WITHHELD[@]}"}
  json_array_of dg ${DOWNGRADED[@]+"${DOWNGRADED[@]}"}
  json_array_of moved ${MOVED_DURING[@]+"${MOVED_DURING[@]}"}
  json_array_of inst ${INSTALLED_ROWS[@]+"${INSTALLED_ROWS[@]}"}
  json_array_of en ${ENABLED_ROWS[@]+"${ENABLED_ROWS[@]}"}
  json_array_of pr ${PROJECT_ROWS[@]+"${PROJECT_ROWS[@]}"}
  json_array_of rec ${RECOVERED_ROWS[@]+"${RECOVERED_ROWS[@]}"}
  json_strings_of errs ${MP_ERRORS[@]+"${MP_ERRORS[@]}"}

  catalog_regression_rows reg_interval reg_rows "$mp"
  divergence_block div "$mp"
  report_extras extras "$mp"
  jq_to checkout -r '.catalog_source // ""' <<<"$extras"
  source_checkout checkout "$checkout"
  source_pull_field pull "${checkout:-null}"
  monitor_rows monitors "$mp"
  jq_to unset_cfg -c '[.[] | select(.unset_user_config != null)
    | {id, options_unset: .unset_user_config.options_unset, required: .unset_user_config.required}]' <<<"$inst"
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to installed_disabled -c -s '
    .[0] as $inst | .[1] as $en
    | [$en[] | select(.predicted == false and .rc == 0 and .scope == "user") | .id] as $on
    | [$inst[] | select(.rc == 0 and .disabled_by_default == true) | .id | select(IN($on[]) | not)]' \
    <<<"$inst"$'\n'"$en"
  [[ -n "$div" ]] || div='{}'
  [[ -n "$extras" ]] || extras='{}'
  [[ -n "$reg_rows" ]] || reg_rows='[]'

  clock_into T_MP_E
  local args_file="$RUN_DIR/.block-args.$mp.json"
  local err_file="$RUN_DIR/.block-err.$mp"
  local block_rc=0
  local jq_err=""
  json_object_file "$args_file" \
    refresh_rc "${REFRESH_RC:-null}" refresh_predicted "$REFRESH_PREDICTED" \
    refresh_skipped "$REFRESH_SKIP_JSON" project_root "$PROJECT_ROOT_JSON" \
    ir_u "$ir_u" ir_f "$ir_f" ir_w "$ir_w" ir_l "$ir_l" \
    us_u "$us_u" us_f "$us_f" us_w "$us_w" wh "$wh" dg "$dg" \
    moved "$moved" noop_unverified "$NOOP_UNVERIFIED" \
    install_gap "$INSTALL_GAP" inst "$inst" \
    enable_gap "$ENABLE_GAP" en "$en" pr "$pr" rec "$rec" \
    deferred "$INSTALL_DEFERRED" stopped "$STOPPED_BEFORE_INSTALL" \
    normalize "$NORMALIZE_JSON" cache "$CACHE_JSON" reg_rows "$reg_rows" \
    div "$div" self_updated "$SELF_UPDATED" self_update "$SELF_UPDATE" \
    extras "$extras" checkout "${checkout:-null}" pull "${pull:-null}" \
    unset_cfg "${unset_cfg:-[]}" installed_disabled "${installed_disabled:-[]}" \
    monitors "${monitors:-[]}" errors "$errs" other_paths "$OTHER_PATHS_JSON"
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to block -c \
    --arg name "$mp" \
    --arg lastUpdated "$CATALOG_LAST_UPDATED" \
    --arg refresh_out "$REFRESH_OUT" \
    --arg refresh_reason "$REFRESH_REASON" \
    --arg reg_interval "$reg_interval" \
    --arg t_prr_s "$T_PRR_S" --arg t_prr_e "$T_PRR_E" \
    --arg t_mu_s "$T_MU_S" --arg t_mu_e "$T_MU_E" \
    --arg t_ir_s "$T_IR_S" --arg t_ir_e "$T_IR_E" \
    --arg t_op_s "$T_OP_S" --arg t_op_e "$T_OP_E" \
    --arg t_us_s "$T_US_S" --arg t_us_e "$T_US_E" \
    --arg t_pi_s "$T_PI_S" --arg t_pi_e "$T_PI_E" \
    --arg t_ie_s "$T_IE_S" --arg t_ie_e "$T_IE_E" \
    --arg t_cc_s "$T_CC_S" --arg t_cc_e "$T_CC_E" \
    --arg t_pr_s "$T_PR_S" --arg t_pr_e "$T_PR_E" \
    --arg t_fn_s "$T_FN_S" \
    --arg t_mp_s "$T_MP_S" --arg t_mp_e "$T_MP_E" \
    --argjson cli_calls "$CLI_CALLS" --argjson cli_ms "$CLI_MS" \
    --arg resolution "$CLOCK_RESOLUTION" '
    # Seconds to three decimals; an empty stamp pair is a step that did not run.
    # Steps round DOWN and the total rounds UP, so the total is never below the
    # sum of its steps after rounding. Clamped at zero so a wall clock stepped
    # backwards mid-run cannot report a negative duration.
    def ms($s; $e): (($e | tonumber) - ($s | tonumber)) * 1000;
    def dur($s; $e):
      if $s == "" or $e == "" then null else ([0, ((ms($s; $e) | floor) / 1000)] | max) end;
    def dur_up($s; $e):
      if $s == "" or $e == "" then null else ([0, ((ms($s; $e) | ceil) / 1000)] | max) end;
    . as {$refresh_rc, $refresh_predicted, $refresh_skipped, $project_root, $ir_u, $ir_f, $ir_w, $ir_l,
          $us_u, $us_f, $us_w, $wh, $dg, $moved, $noop_unverified, $install_gap, $inst,
          $enable_gap, $en, $pr, $rec, $deferred, $stopped, $normalize, $cache, $reg_rows,
          $div, $self_updated, $self_update, $extras, $checkout, $pull, $unset_cfg,
          $installed_disabled, $monitors, $errors, $other_paths}
    | {pre_refresh_read: dur($t_prr_s; $t_prr_e),
     marketplace_update: dur($t_mu_s; $t_mu_e),
     in_repo_update: dur($t_ir_s; $t_ir_e),
     other_paths: dur($t_op_s; $t_op_e),
     user_sweep: dur($t_us_s; $t_us_e),
     pre_install_read: dur($t_pi_s; $t_pi_e),
     install_enable: dur($t_ie_s; $t_ie_e),
     cache_content_check: dur($t_cc_s; $t_cc_e),
     post_read: dur($t_pr_s; $t_pr_e),
     finalize: dur($t_fn_s; $t_mp_e)} as $steps
    | dur_up($t_mp_s; $t_mp_e) as $total
    # The time between and around the named steps, so the steps plus this
    # remainder account for the whole total.
    | (if $total == null then null
       else [0, ((($total * 1000) - ([$steps[] | select(. != null)] | add // 0) * 1000) | round) / 1000]
            | max end) as $unattributed
    | $extras + {name: $name,
     timings: ($steps + {unattributed: $unattributed, total: $total, resolution: $resolution}),
     cli: {calls: $cli_calls, seconds: ($cli_ms / 1000)},
     catalog_last_updated: (if $lastUpdated == "" then null else $lastUpdated end),
     source_checkout: $checkout,
     source_pull: $pull,
     refresh: {rc: $refresh_rc, output: $refresh_out, reason: $refresh_reason, predicted: $refresh_predicted,
               skipped: $refresh_skipped},
     project_root: $project_root,
     in_repo: {updated: $ir_u, failed: $ir_f, would_update: $ir_w, live_read: $ir_l},
     user_sweep: {updated: $us_u, failed: $us_f, would_update: $us_w,
                  withheld_downgrades: $wh},
     downgraded: $dg,
     moved_during_run: $moved,
     noop_unverified: $noop_unverified,
     install_gap: $install_gap,
     installed: $inst,
     installed_with_unset_user_config: $unset_cfg,
     installed_disabled: $installed_disabled,
     install_enable_deferred: $deferred,
     stopped_before_install: $stopped,
     enable_gap: $enable_gap,
     enabled: $en,
     project_enable_rows: $pr,
     other_paths: $other_paths,
     pending_enable: $rec,
     normalize: $normalize,
     cache_content: $cache,
     catalog_regression: (if $reg_interval == "" then null
                          else {interval: $reg_interval, rows: $reg_rows} end),
     divergences: $div,
     self_updated: $self_updated,
     self_update: $self_update,
     updated_with_monitors: $monitors,
     errors: $errors}' "$args_file" 2>"$err_file" || block_rc=$?
  if ((block_rc == 0)) && [[ -n "$block" ]]; then
    printf '%s\n' "$block" >>"$RUN_DIR/.blocks.jsonl"
    return 0
  fi
  [[ -f "$err_file" ]] && IFS= read -r jq_err <"$err_file"
  jq_err="${jq_err//$'\r'/}"
  run_error "marketplace $mp: its report block could not be assembled (jq exit $block_rc: ${jq_err:-no error output})"
}

setup_run_dir
pending_path

SAVED_ALLOW_DOWNGRADE=""
SAVED_INSTALL_NEW=""
SAVED_INSTALL_NEW_INVALID=""
if ((ONLY_INSTALL_MODE == 1)); then
  if [[ -f "$RUN_DIR/flags.json" ]]; then
    jq_to SAVED_ALLOW_DOWNGRADE -r '.allow_downgrade // false' "$RUN_DIR/flags.json" 2>/dev/null
    [[ "$SAVED_ALLOW_DOWNGRADE" != "true" ]] || ALLOW_DOWNGRADE=1
    jq_to SAVED_INSTALL_NEW -r '.install_new // ""' "$RUN_DIR/flags.json" 2>/dev/null
    jq_to SAVED_INSTALL_NEW_INVALID -r '.install_new_invalid // ""' "$RUN_DIR/flags.json" 2>/dev/null
    case "$SAVED_INSTALL_NEW" in
    all | none | ask)
      INSTALL_NEW="$SAVED_INSTALL_NEW"
      INSTALL_NEW_INVALID="$SAVED_INSTALL_NEW_INVALID"
      ;;
    *) ;;
    esac
    SAVED_SOURCE_PULL=""
    jq_to SAVED_SOURCE_PULL -r '.source_pull // ""' "$RUN_DIR/flags.json" 2>/dev/null
    case "$SAVED_SOURCE_PULL" in
    ask | never)
      SOURCE_PULL="$SAVED_SOURCE_PULL"
      jq_to SOURCE_PULL_INVALID -r '.source_pull_invalid // ""' "$RUN_DIR/flags.json" 2>/dev/null
      jq_to SOURCE_PULL_OFF -r '.source_pull_off // ""' "$RUN_DIR/flags.json" 2>/dev/null
      jq_to QUIET_AUTO_UPDATE -r '.quiet_auto_update // [] | join(",")' "$RUN_DIR/flags.json" 2>/dev/null
      jq_to UPDATE_OTHER_PATHS -r 'if .update_other_paths == true then 1 else 0 end' "$RUN_DIR/flags.json" 2>/dev/null
      [[ -z "${CLAUDE_CODE_REMOTE:-}" ]] || apply_pull_policy
      ;;
    *) ;;
    esac
  fi
else
  FLAG_AD="false"
  ((ALLOW_DOWNGRADE == 0)) || FLAG_AD="true"
  FLAG_IN=""
  json_string_to FLAG_IN "$INSTALL_NEW"
  FLAG_INV="null"
  [[ -z "$INSTALL_NEW_INVALID" ]] || json_string_to FLAG_INV "$INSTALL_NEW_INVALID"
  FLAG_SP=""
  json_string_to FLAG_SP "$SOURCE_PULL"
  FLAG_SPI="null"
  [[ -z "$SOURCE_PULL_INVALID" ]] || json_string_to FLAG_SPI "$SOURCE_PULL_INVALID"
  FLAG_SPO="null"
  [[ -z "$SOURCE_PULL_OFF" ]] || json_string_to FLAG_SPO "$SOURCE_PULL_OFF"
  FLAG_QAU="[]"
  # shellcheck disable=SC2086  # word splitting on the comma-folded list is the point
  json_strings_of FLAG_QAU ${QUIET_AUTO_UPDATE//,/ }
  FLAG_UOP="false"
  ((UPDATE_OTHER_PATHS == 0)) || FLAG_UOP="true"
  printf '{"allow_downgrade":%s,"install_new":%s,"install_new_invalid":%s,"source_pull":%s,"source_pull_invalid":%s,"source_pull_off":%s,"quiet_auto_update":%s,"update_other_paths":%s}\n' \
    "$FLAG_AD" "$FLAG_IN" "$FLAG_INV" "$FLAG_SP" "$FLAG_SPI" "$FLAG_SPO" "$FLAG_QAU" "$FLAG_UOP" >"$RUN_DIR/flags.json"
fi

FIRST_PASS_RUN="$RUN_DIR/first-pass-run.json"
FIRST_PASS_TIMINGS="null"
if ((ONLY_INSTALL_MODE == 1)) && [[ -f "$FIRST_PASS_RUN" ]]; then
  jq_to FIRST_PASS_TIMINGS -c '.timings | select((.total | type) == "number")
    | {total, resolution,
       outside_marketplaces: (if (.outside_marketplaces | type) == "number" then .outside_marketplaces else null end)}' \
    "$FIRST_PASS_RUN" 2>/dev/null || FIRST_PASS_TIMINGS="null"
  [[ -n "$FIRST_PASS_TIMINGS" ]] || FIRST_PASS_TIMINGS="null"
fi

: >"$RUN_DIR/.blocks.jsonl"
[[ -f "$JOURNAL_LOG" ]] || : >"$JOURNAL_LOG"

MPS=()
if ((ONLY_INSTALL_MODE == 1)); then
  for snapshot in "$RUN_DIR"/pre-refresh.*.json; do
    [[ -f "$snapshot" ]] || continue
    snapshot="${snapshot##*/pre-refresh.}"
    MPS+=("${snapshot%.json}")
  done
  if [[ -n "$TARGET_MP" ]]; then
    if [[ ! -f "$RUN_DIR/pre-refresh.$TARGET_MP.json" ]]; then
      echo "ERROR: that run directory carries no snapshot for marketplace: $TARGET_MP" >&2
      echo "  --only-install re-enters a run; it cannot start one for a new marketplace." >&2
      exit 2
    fi
    MPS=("$TARGET_MP")
  fi
  if ((${#MPS[@]} == 0)); then
    echo "ERROR: that run directory carries no marketplace snapshot: $RUN_DIR" >&2
    exit 2
  fi
elif ((ALL == 1)); then
  if ! "$FLEET_STATE" --marketplaces >"$RUN_DIR/.marketplaces.txt" 2>"$RUN_DIR/.fs-err"; then
    echo "ERROR: could not enumerate marketplaces" >&2
    cat "$RUN_DIR/.fs-err" >&2
    exit 2
  fi
  while IFS= read -r line; do
    line="${line//$'\r'/}"
    [[ -n "$line" ]] || continue
    MPS+=("$line")
  done <"$RUN_DIR/.marketplaces.txt"
elif [[ -n "$TARGET_MP" ]]; then
  MPS=("$TARGET_MP")
else
  clock_into MAIN_READ_S
  if ! FLEET_STATE_READ_LIST="$RUN_DIR/.default.list" "$FLEET_STATE" >"$RUN_DIR/.default.json" 2>"$RUN_DIR/.fs-err"; then
    echo "ERROR: could not resolve the default marketplace" >&2
    cat "$RUN_DIR/.fs-err" >&2
    exit 2
  fi
  clock_into MAIN_READ_E
  jq_to DEFAULT_MP -r '.marketplace.name // ""' "$RUN_DIR/.default.json"
  if [[ -z "$DEFAULT_MP" ]]; then
    echo "ERROR: the default marketplace report carries no marketplace name" >&2
    exit 2
  fi
  MPS=("$DEFAULT_MP")
  MAIN_READ_MP="$DEFAULT_MP"
  [[ -f "$RUN_DIR/pre-refresh.$DEFAULT_MP.json" ]] ||
    mv "$RUN_DIR/.default.json" "$RUN_DIR/pre-refresh.$DEFAULT_MP.json"
  printf '%s' "$SNAPSHOT_KEY" >"$RUN_DIR/fs-cache.$DEFAULT_MP.key"
  slurp_to line "$RUN_DIR/.default.list"
  printf '%s' "$line" >"$RUN_DIR/fs-cache.$DEFAULT_MP.list"
  stamp_us t_s "$MAIN_READ_S"
  stamp_us t_e "$MAIN_READ_E"
  t_e=$(((t_e - t_s) / 1000))
  printf '# fleet-state read pre-refresh: elapsed %d.%03ds, exit 0, not stored, its read list is kept\n' \
    $((t_e / 1000)) $((t_e % 1000)) >>"$JOURNAL_LOG"
fi

if ((${#MPS[@]} == 0)); then
  run_error "no marketplace resolved for this run"
fi

for mp in ${MPS[@]+"${MPS[@]}"}; do
  run_marketplace "$mp"
done

if ((ONLY_INSTALL_MODE == 1)); then
  for id in ${ONLY_INSTALL//,/ }; do
    claimed=0
    for mp in ${MPS[@]+"${MPS[@]}"}; do
      [[ "$id" == *"@$mp" ]] && claimed=1
    done
    ((claimed == 1)) || run_error "--only-install id matches no marketplace in this run: $id"
  done
fi
if ((PULL_SOURCES_SET == 1)); then
  for name in ${PULL_SOURCES//,/ }; do
    claimed=0
    for mp in ${MPS[@]+"${MPS[@]}"}; do
      [[ "$name" == "$mp" ]] && claimed=1
    done
    ((claimed == 1)) || run_error "--pull-source names no marketplace in this run: $name"
  done
fi

RUN_ERRS='[]'
json_strings_of RUN_ERRS ${RUN_ERRORS[@]+"${RUN_ERRORS[@]}"}

DIGEST=""
ALLOW_DOWNGRADE_JSON="false"
((ALLOW_DOWNGRADE == 1)) && ALLOW_DOWNGRADE_JSON="true"
QUIET_JSON='[]'
# shellcheck disable=SC2086  # word splitting on the comma-folded list is the point
json_strings_of QUIET_JSON ${QUIET_AUTO_UPDATE//,/ }
T_RUN_E=""
clock_into T_RUN_E

# shellcheck disable=SC2016  # a jq program: every $var is a jq variable
jq_to DIGEST -c -n \
  --arg run_dir "$RUN_DIR" \
  --arg cwd "$PWD" \
  --arg mode "$MODE" \
  --argjson allow_downgrade "$ALLOW_DOWNGRADE_JSON" \
  --arg install_new "$INSTALL_NEW" \
  --arg install_new_invalid "$INSTALL_NEW_INVALID" \
  --arg source_pull "$SOURCE_PULL" \
  --arg source_pull_invalid "$SOURCE_PULL_INVALID" \
  --argjson quiet_auto_update "$QUIET_JSON" \
  --slurpfile marketplaces "$RUN_DIR/.blocks.jsonl" \
  --arg t_run_s "$T_RUN_S" --arg t_run_e "$T_RUN_E" \
  --arg resolution "$CLOCK_RESOLUTION" \
  --argjson first "$FIRST_PASS_TIMINGS" \
  --argjson errors "$RUN_ERRS" '
  def ms_sum($a; $b): ((($a * 1000) + ($b * 1000)) | round) / 1000;
  # The combined total is only as fine as the coarser clock that timed it. The
  # rungs run fine to coarse here, not in the ladder'"'"'s try order.
  def coarser($a; $b):
    ["nanoseconds", "microseconds", "seconds"] as $rungs
    | if ($rungs | index($a)) == null then $b
      elif ($rungs | index($b)) == null then $a
      elif ($rungs | index($a)) > ($rungs | index($b)) then $a
      else $b end;
  (([0, (((($t_run_e | tonumber) - ($t_run_s | tonumber)) * 1000 | ceil) / 1000)] | max) as $total
   | {total: $total,
      # Run setup and the per-block assembly: the part of the total no
      # block window covers. The clock stops before this jq runs, since a digest
      # cannot time its own assembly without a second jq process.
      outside_marketplaces: ([0, ((($total * 1000)
                                   - ([$marketplaces[].timings.total | numbers] | add // 0) * 1000)
                                  | round) / 1000] | max),
      resolution: $resolution}) as $this
  # A re-entry adds the first pass it continues. The blocks time only this pass,
  # so `outside_marketplaces` sums each pass'"'"'s own remainder, and the wait
  # between the passes (the caller'"'"'s prompt) is in neither.
  | (if $first == null then $this
     else {total: ms_sum($first.total; $this.total),
           outside_marketplaces: (if $first.outside_marketplaces == null then $this.outside_marketplaces
                                  else ms_sum($first.outside_marketplaces; $this.outside_marketplaces) end),
           resolution: coarser($first.resolution; $this.resolution),
           passes: [{pass: "first"} + $first, {pass: "only_install"} + $this]}
     end) as $timings
  | {run_dir: $run_dir, cwd: $cwd, mode: $mode, allow_downgrade: $allow_downgrade,
     install_new: $install_new,
     install_new_invalid: (if $install_new_invalid == "" then null else $install_new_invalid end),
     source_pull: $source_pull,
     source_pull_invalid: (if $source_pull_invalid == "" then null else $source_pull_invalid end),
     quiet_auto_update: $quiet_auto_update,
     timings: $timings,
     marketplaces: $marketplaces, errors: $errors}'

printf '%s\n' "$DIGEST" >"$RUN_DIR/digest.json"
if [[ "$MODE" == "sync" ]] && ((ONLY_INSTALL_MODE == 0)); then
  FIRST_PASS_OUT=""
  jq_to FIRST_PASS_OUT -c '{timings}' <<<"$DIGEST" && printf '%s\n' "$FIRST_PASS_OUT" >"$FIRST_PASS_RUN"
fi

REPORT=""
if jq_to REPORT -r -f "$SCRIPT_DIR/render-report.jq" "$RUN_DIR/digest.json"; then
  printf '%s\n' "$REPORT" >"$RUN_DIR/report.txt"
else
  echo "ERROR: report render failed; the digest above is complete, report.txt was not written" >&2
  REPORT=""
fi

printf '%s\n' "$DIGEST"
if ((RENDER == 1)) && [[ -n "$REPORT" ]]; then
  printf '\n%s\n' "$REPORT"
fi
exit 0
