#!/usr/bin/env bash
# Exit codes:
#   0  the requested mode's lines were emitted
#   3  invalid, missing, or conflicting argument

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# One containment rule for the log root, shared with the hooks that write it.
# shellcheck source=../../../hooks/session-log-lib.sh
. "$SCRIPT_DIR/../../../hooks/session-log-lib.sh"

err() { printf 'ERROR: %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
probe-observability-state.sh: report local telemetry-store state for the observability skill.

Usage:
  probe-observability-state.sh --hook-events [--root <rel-dir>]
  probe-observability-state.sh --otel-store
  probe-observability-state.sh --pipeline [--root <rel-dir>] [--enabled <v>]
      [--categories <v>] [--keep-sessions <n>] [--keep-days <n>]
      [--pre-prune-command <v>] [--observed]

  --hook-events            one line: the hook-event count under the log root
  --otel-store             six lines: each OTEL store file's size, the cold tier, last prune, prune task
  --pipeline               six lines: root, guard, sessions, shared log, prune-pending, envelope
  --root <rel-dir>         hook log root, project-relative (default .observability/claude)
  --enabled <v>            the event-log switch as rendered
  --categories <v>         the logged categories as rendered
  --keep-sessions <n>      session retention as rendered
  --keep-days <n>          day retention as rendered
  --pre-prune-command <v>  the pre-prune command as rendered
  --observed               --pipeline without the option tier
An empty or unexpanded `${user_config...}` value reads as the option's default.

Exit codes:
  0  the requested mode's lines were emitted
  3  invalid, missing, or conflicting argument
EOF
}

# shellcheck disable=SC2016  # the literal placeholder text is the thing matched
unset_value() { [[ -z "$1" || "$1" == '${user_config.'* ]]; }

is_windows() { [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* || "${OSTYPE:-}" == win* ]]; }

MODE=""
OBSERVED=0
ROOT_ARG=""
ENABLED_ARG=""
CATEGORIES_ARG=""
KEEP_SESSIONS_ARG=""
KEEP_DAYS_ARG=""
PRE_PRUNE_ARG=""
while (($#)); do
  case "$1" in
  --hook-events | --otel-store | --pipeline)
    if [[ -n "$MODE" ]]; then
      err "modes are mutually exclusive: $MODE and $1"
      exit 3
    fi
    MODE="$1"
    shift
    ;;
  --observed)
    OBSERVED=1
    shift
    ;;
  --root | --enabled | --categories | --keep-sessions | --keep-days | --pre-prune-command)
    if (($# < 2)); then
      err "$1 needs a value"
      exit 3
    fi
    case "$1" in
    --root) ROOT_ARG="$2" ;;
    --enabled) ENABLED_ARG="$2" ;;
    --categories) CATEGORIES_ARG="$2" ;;
    --keep-sessions) KEEP_SESSIONS_ARG="$2" ;;
    --keep-days) KEEP_DAYS_ARG="$2" ;;
    --pre-prune-command) PRE_PRUNE_ARG="$2" ;;
    *) ;;
    esac
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    err "unknown argument: $1 (see --help)"
    exit 3
    ;;
  esac
done

if [[ -z "$MODE" ]]; then
  err "a mode is required: --hook-events, --otel-store or --pipeline (see --help)"
  exit 3
fi

repo_root() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  printf '%s\n' "${root:-$PWD}"
}

hook_anchor() {
  local anchor
  slog_anchor_to anchor "$(repo_root)"
  printf '%s\n' "$anchor"
}

ROOT_REL="$SLOG_DEFAULT_ROOT"
ROOT_ORIGIN="default"
ROOT_VALID=1
if ! unset_value "$ROOT_ARG"; then
  ROOT_REL="${ROOT_ARG%/}"
  ROOT_ORIGIN="configured"
  slog_contained "$ROOT_REL" || ROOT_VALID=0
fi

SHARED_FILES=()
shared_files() {
  local f
  SHARED_FILES=()
  for f in "$1/hook-events.jsonl" "$1/hook-events.jsonl.1"; do
    [[ -f "$f" ]] && SHARED_FILES+=("$f")
  done
  return 0
}

HOOK_FILES=()
hook_files() {
  local f
  HOOK_FILES=()
  shopt -s nullglob
  for f in "$1"/sessions/*.jsonl; do HOOK_FILES+=("$f"); done
  shopt -u nullglob
  shared_files "$1"
  ((${#SHARED_FILES[@]})) && HOOK_FILES+=("${SHARED_FILES[@]}")
  return 0
}

prune_task_state() {
  if ! is_windows; then
    printf 'n/a (not Windows)'
    return 0
  fi
  if ! command -v schtasks >/dev/null 2>&1; then
    printf 'unknown (schtasks not found)'
    return 0
  fi
  local xml command arguments path
  if ! xml="$(MSYS2_ARG_CONV_EXCL='*' schtasks /query /tn ClaudeCodeOtelPrune /xml 2>/dev/null | tr -d '\r')"; then
    printf 'missing'
    return 0
  fi
  if [[ "$xml" == *'<Enabled>false</Enabled>'* ]]; then
    printf 'disabled'
    return 0
  fi
  command="$(sed -n 's:.*<Command>\(.*\)</Command>.*:\1:p' <<<"$xml" | head -n 1)"
  arguments="$(sed -n 's:.*<Arguments>\(.*\)</Arguments>.*:\1:p' <<<"$xml" | head -n 1)"
  if [[ "$command" == *pwsh.exe && "$arguments" == *installed_plugins.json* &&
    "$arguments" == *harness-ops@* && "$arguments" == *skills/observability/otel/prune-otel-store.sh* ]]; then
    printf 'provisioned'
    return 0
  fi
  path="$(grep -o '[^";]*prune-otel-store\.sh' <<<"$arguments" | head -n 1)"
  path="${path//\\//}"
  if [[ -z "$path" || "$path" == //* ]]; then
    printf 'unrecognized action'
  elif [[ -f "$path" ]]; then
    printf 'hand-registered'
  else
    printf 'stale path'
  fi
}

case "$MODE" in
--hook-events)
  if ((!ROOT_VALID)); then
    printf 'INVALID root (%s): the hooks write nothing\n' "$ROOT_ARG"
    exit 0
  fi
  hook_files "$(hook_anchor)/$ROOT_REL"
  if ((${#HOOK_FILES[@]})); then
    printf '%s events\n' "$(cat "${HOOK_FILES[@]}" | wc -l)"
  else
    printf 'EMPTY (no hook-event emitter wired, or no hooks fired yet)\n'
  fi
  ;;
--otel-store)
  STORE="${CC_OTEL_STORE:-$(repo_root)/.claude/observability/otel}"
  is_windows && STORE="${STORE//\\//}"
  for name in cc-logs.json cc-metrics.json cc-traces.json; do
    if [[ -f "$STORE/$name" ]]; then
      printf '%s:%sB\n' "$name" "$(wc -c <"$STORE/$name" 2>/dev/null || echo 0)"
    else
      printf '%s:absent\n' "$name"
    fi
  done
  cold_bytes=0
  cold_files=0
  shopt -s nullglob
  for f in "$STORE"/cold/*.parquet; do
    cold_bytes=$((cold_bytes + $(wc -c <"$f" 2>/dev/null || echo 0)))
    cold_files=$((cold_files + 1))
  done
  shopt -u nullglob
  if ((cold_files)); then
    printf 'cold:%sB (%s files)\n' "$cold_bytes" "$cold_files"
  else
    printf 'cold:absent\n'
  fi
  stamp=""
  [[ -f "$STORE/.last-prune" ]] && read -r stamp <"$STORE/.last-prune" 2>/dev/null
  stamp="${stamp%$'\r'}"
  stamp_epoch=""
  if [[ -n "$stamp" ]]; then
    stamp_epoch="$(date -u -d "$stamp" +%s 2>/dev/null || date -j -u -f %Y-%m-%dT%H:%M:%SZ "$stamp" +%s 2>/dev/null || true)" # portability-ok: BSD date -j fallback on the same line
  fi
  if [[ -n "$stamp_epoch" ]]; then
    age=$(($(date +%s) - stamp_epoch))
    ((age < 0)) && age=0
    if ((age >= 172800)); then age_txt="$((age / 86400))d"; else age_txt="$((age / 3600))h"; fi
    printf 'last-prune:%s (%s)\n' "$stamp" "$age_txt"
  else
    printf 'last-prune:never\n'
  fi
  printf 'prune-task:%s\n' "$(prune_task_state)"
  ;;
--pipeline)
  PROJECT="$(hook_anchor)"
  ABS_ROOT="$PROJECT/$ROOT_REL"
  if ((ROOT_VALID)); then
    printf 'root: %s (%s)\n' "$ROOT_REL" "$ROOT_ORIGIN"
  else
    printf 'root: %s INVALID (uncontained; the hooks write nothing)\n' "$ROOT_ARG"
  fi

  if ((!ROOT_VALID)); then
    printf 'guard: n/a (root invalid)\n'
  elif ! slog_in_checkout "$PROJECT"; then
    printf 'guard: not needed (not a git checkout)\n'
  elif [[ ! -f "$ABS_ROOT/.gitignore" ]]; then
    printf 'guard: absent (the first write heals it)\n'
  else
    guard_state="absent (the first write heals it)"
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      case "$line" in
      '' | '#'*) continue ;;
      '*') guard_state="ok" ;;
      *) guard_state="operator-edited (writes refused)" ;;
      esac
      break
    done <"$ABS_ROOT/.gitignore"
    printf 'guard: %s\n' "$guard_state"
  fi

  session_count=0
  newest=""
  if ((ROOT_VALID)) && [[ -d "$ABS_ROOT/sessions" ]]; then
    shopt -s nullglob
    session_files=("$ABS_ROOT"/sessions/*.jsonl)
    shopt -u nullglob
    session_count=${#session_files[@]}
    if ((session_count)); then
      # shellcheck disable=SC2012  # mtime order is the point; names are hook-validated ids
      newest="$(ls -t "${session_files[@]}" 2>/dev/null | head -n 1)"
      newest="${newest##*/}"
      newest="${newest%.jsonl}"
    fi
  fi
  if ((session_count)); then
    printf 'sessions: %s file(s), newest %s\n' "$session_count" "$newest"
  else
    printf 'sessions: none\n'
  fi
  ((ROOT_VALID)) && shared_files "$ABS_ROOT"
  shared_rows=0
  if ((${#SHARED_FILES[@]})); then
    shared_rows="$(cat "${SHARED_FILES[@]}" | wc -l | tr -d ' ')"
    printf 'shared: %s event(s) in hook-events.jsonl (rotated .1 included)\n' "$shared_rows"
  else
    printf 'shared: absent\n'
  fi

  pending_total=0
  pending_old=0
  if ((ROOT_VALID)) && [[ -d "$ABS_ROOT/prune-pending" ]]; then
    shopt -s nullglob
    pending_dirs=("$ABS_ROOT"/prune-pending/*/)
    shopt -u nullglob
    pending_total=${#pending_dirs[@]}
    pending_old="$(find "$ABS_ROOT/prune-pending" -mindepth 1 -maxdepth 1 -type d -mmin +1440 2>/dev/null | wc -l | tr -d ' ')"
  fi
  if ((pending_total == 0)); then
    printf 'prune-pending: none\n'
  else
    pending_warn=""
    ((pending_old > 0)) && pending_warn=" WARN: an archiver is not finishing"
    printf 'prune-pending: %s dir(s), %s older than 24 h%s\n' "$pending_total" "$pending_old" "$pending_warn"
  fi

  envelope="none"
  envelope_rows=0
  if ((ROOT_VALID)) && [[ -d "$ABS_ROOT/sessions" ]]; then
    envelope_rows="$(cat "$ABS_ROOT"/sessions/*.jsonl 2>/dev/null | grep -c '"source":"envelope"')"
  fi
  envelope_rows=$((envelope_rows + shared_rows))
  ((envelope_rows)) && envelope="$envelope_rows row(s) from the audit hooks, outside the switch"

  if ((OBSERVED)); then
    printf 'envelope: %s; options: rendered by the section 2.6 re-run, not here\n' "$envelope"
    exit 0
  fi

  logging="off"
  [[ "$ENABLED_ARG" == "true" ]] && logging="on"
  categories="all"
  unset_value "$CATEGORIES_ARG" || categories="$CATEGORIES_ARG"
  keep_sessions="30"
  unset_value "$KEEP_SESSIONS_ARG" || keep_sessions="$KEEP_SESSIONS_ARG"
  keep_days="14"
  unset_value "$KEEP_DAYS_ARG" || keep_days="$KEEP_DAYS_ARG"
  pre_prune="none"
  unset_value "$PRE_PRUNE_ARG" || pre_prune="set (runs detached at SessionEnd)"
  printf 'envelope: %s; event log: %s; categories: %s; keep: %s sessions or %s days; pre-prune: %s\n' \
    "$envelope" "$logging" "$categories" "$keep_sessions" "$keep_days" "$pre_prune"
  ;;
*)
  err "unhandled mode: $MODE"
  exit 3
  ;;
esac
