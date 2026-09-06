#!/usr/bin/env bash
# probe-observability-state.sh — report local telemetry-store state for the
# observability skill's `## Pre-computed context` block and its "Toggles and
# retention in effect" section.
#
# The block's lines are real shell work — a repo-root-or-working-directory
# default, an env override, a per-file size loop — and a pre-compute line carrying
# genuine shell expansion (`$f`, `$d`, `${VAR:-default}`, `$(…)`) is refused by the
# worktree-isolation guard, so the whole skill fails to load when invoked from an
# isolated agent (#1687). The lines therefore call this script through
# `${CLAUDE_PLUGIN_ROOT}`, which the harness substitutes into a literal path before
# any shell sees it.
#
# One script, three modes rather than three scripts: every mode reads the same
# local observability tree, so they are facets of one probe surface, and a caller
# picking a mode is the only difference between them.
#
# Usage:
#   probe-observability-state.sh --hook-events [--root <rel-dir>]
#   probe-observability-state.sh --otel-store
#   probe-observability-state.sh --pipeline [--root <rel-dir>] [--enabled <v>]
#       [--categories <v>] [--keep-sessions <n>] [--keep-days <n>]
#       [--pre-prune-command <v>]
#
# --root is the hook log root, project-relative: the plugin's
# session_event_log_dir option. Absent, empty, or still an unexpanded
# `${user_config...}` placeholder → `.observability/claude`. The skill passes the
# rendered option through this flag because a skill subprocess inherits no
# CLAUDE_PLUGIN_OPTION_* (the hooks read theirs from the session environment).
# The same holds for every --pipeline value: an unexpanded placeholder reads as
# the option's manifest default.
#
# --hook-events output (stdout, exactly one line) over the root's
# sessions/*.jsonl files plus its hook-events.jsonl:
#   <N> events
#   EMPTY (no hook-event emitter wired, or no hooks fired yet)
#   INVALID root (<value>): the hooks write nothing
#
# --otel-store output (stdout, three lines — one per store file, in order
# cc-logs.json, cc-metrics.json, cc-traces.json):
#   <name>:<bytes>B
#   <name>:absent
#
# --pipeline output (stdout, six lines, fixed order and labels; read-only, it
# never heals the guard):
#   root: <rel> (default|configured) | root: <value> INVALID (uncontained; the hooks write nothing)
#   guard: ok | absent (the first write heals it) | operator-edited (writes refused)
#        | not needed (not a git checkout) | n/a (root invalid)
#   sessions: <S> file(s), newest <id> | none
#   shared: <L> event(s) in hook-events.jsonl | absent
#   prune-pending: none | <D> dir(s), <O> older than 24 h[ WARN: an archiver is not finishing]
#   logging: on|off; categories: all|<v>; keep: <n> sessions or <n> days; pre-prune: none|set
#
# Store resolution:
#   --hook-events  <git toplevel, or the working directory when not inside a
#                  repo>/<root> — no env override.
#   --otel-store   CC_OTEL_STORE when set and non-empty, used verbatim; otherwise
#                  <git toplevel, or the working directory>/.claude/observability/otel.
#
# The git toplevel is CR-stripped through an empty-means-fall-back test rather than
# a `|| pwd` continuation, because piping through `tr` would make the pipeline
# always succeed and swallow the not-in-a-repo fallback. `wc` output is emitted
# as captured.
#
# Exit codes:
#   0  the requested mode's lines were emitted
#   3  invalid, missing, or conflicting argument

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# One containment rule for the log root, shared with the hooks that write it.
# shellcheck source=../../../hooks/session-log-lib.sh
. "$SCRIPT_DIR/../../../hooks/session-log-lib.sh"

err() { printf 'ERROR: %s\n' "$*" >&2; }

usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"; }

# An option value the skill passed through unrendered (`${user_config.x}`) or
# empty means "unset": the manifest default applies.
# shellcheck disable=SC2016  # the literal placeholder text is the thing matched
unset_value() { [[ -z "$1" || "$1" == '${user_config.'* ]]; }

MODE=""
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
    err "unknown argument: $1"
    exit 3
    ;;
  esac
done

if [[ -z "$MODE" ]]; then
  err "a mode is required: --hook-events, --otel-store or --pipeline"
  exit 3
fi

repo_root() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  if [[ -n "$root" ]]; then
    printf '%s\n' "$root"
  else
    printf '%s\n' "$PWD"
  fi
}

# The configured root, its origin, and whether the hooks would accept it.
ROOT_REL="$SLOG_DEFAULT_ROOT"
ROOT_ORIGIN="default"
ROOT_VALID=1
if ! unset_value "$ROOT_ARG"; then
  ROOT_REL="${ROOT_ARG%/}"
  ROOT_ORIGIN="configured"
  slog_contained "$ROOT_REL" || ROOT_VALID=0
fi

# The files the hook log holds: sessions/*.jsonl plus the shared file.
# Populated by hook_files <abs-root> into HOOK_FILES.
HOOK_FILES=()
hook_files() {
  local f
  HOOK_FILES=()
  shopt -s nullglob
  for f in "$1"/sessions/*.jsonl; do HOOK_FILES+=("$f"); done
  shopt -u nullglob
  [[ -f "$1/hook-events.jsonl" ]] && HOOK_FILES+=("$1/hook-events.jsonl")
  return 0
}

case "$MODE" in
--hook-events)
  if ((!ROOT_VALID)); then
    printf 'INVALID root (%s): the hooks write nothing\n' "$ROOT_ARG"
    exit 0
  fi
  hook_files "$(repo_root)/$ROOT_REL"
  if ((${#HOOK_FILES[@]})); then
    printf '%s events\n' "$(cat "${HOOK_FILES[@]}" | wc -l)"
  else
    printf 'EMPTY (no hook-event emitter wired, or no hooks fired yet)\n'
  fi
  ;;
--otel-store)
  STORE="${CC_OTEL_STORE:-$(repo_root)/.claude/observability/otel}"
  for name in cc-logs.json cc-metrics.json cc-traces.json; do
    if [[ -f "$STORE/$name" ]]; then
      printf '%s:%sB\n' "$name" "$(wc -c <"$STORE/$name" 2>/dev/null || echo 0)"
    else
      printf '%s:absent\n' "$name"
    fi
  done
  ;;
--pipeline)
  PROJECT="$(repo_root)"
  ABS_ROOT="$PROJECT/$ROOT_REL"
  if ((ROOT_VALID)); then
    printf 'root: %s (%s)\n' "$ROOT_REL" "$ROOT_ORIGIN"
  else
    printf 'root: %s INVALID (uncontained; the hooks write nothing)\n' "$ROOT_ARG"
  fi

  # Guard state, read the way the hooks read it (first non-blank, non-comment
  # line is `*`) and never written: healing is the hooks' and setup apply's job.
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

  # Session files, newest by mtime; the shared file's line count.
  session_count=0
  newest=""
  if ((ROOT_VALID)) && [[ -d "$ABS_ROOT/sessions" ]]; then
    shopt -s nullglob
    session_files=("$ABS_ROOT"/sessions/*.jsonl)
    shopt -u nullglob
    session_count=${#session_files[@]}
    if ((session_count)); then
      # shellcheck disable=SC2012  # mtime order is the point; names are hook-validated ids
      newest="$(ls -t "$ABS_ROOT"/sessions/*.jsonl 2>/dev/null | head -n 1)"
      newest="${newest##*/}"
      newest="${newest%.jsonl}"
    fi
  fi
  if ((session_count)); then
    printf 'sessions: %s file(s), newest %s\n' "$session_count" "$newest"
  else
    printf 'sessions: none\n'
  fi
  if ((ROOT_VALID)) && [[ -f "$ABS_ROOT/hook-events.jsonl" ]]; then
    printf 'shared: %s event(s) in hook-events.jsonl\n' "$(wc -l <"$ABS_ROOT/hook-events.jsonl" | tr -d ' ')"
  else
    printf 'shared: absent\n'
  fi

  # Moved-aside prune sets waiting for an archiver; retention deletes them after
  # 24 h, so an older one means the detached command never finished.
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
  elif ((pending_old > 0)); then
    printf 'prune-pending: %s dir(s), %s older than 24 h WARN: an archiver is not finishing\n' "$pending_total" "$pending_old"
  else
    printf 'prune-pending: %s dir(s), %s older than 24 h\n' "$pending_total" "$pending_old"
  fi

  # The six options as rendered, defaults applied where unset.
  logging="off"
  ! unset_value "$ENABLED_ARG" && [[ "$ENABLED_ARG" == "true" ]] && logging="on"
  categories="all"
  unset_value "$CATEGORIES_ARG" || categories="$CATEGORIES_ARG"
  keep_sessions="30"
  unset_value "$KEEP_SESSIONS_ARG" || keep_sessions="$KEEP_SESSIONS_ARG"
  keep_days="14"
  unset_value "$KEEP_DAYS_ARG" || keep_days="$KEEP_DAYS_ARG"
  pre_prune="none"
  unset_value "$PRE_PRUNE_ARG" || pre_prune="set (runs detached at SessionEnd)"
  printf 'logging: %s; categories: %s; keep: %s sessions or %s days; pre-prune: %s\n' \
    "$logging" "$categories" "$keep_sessions" "$keep_days" "$pre_prune"
  ;;
*)
  err "unhandled mode: $MODE"
  exit 3
  ;;
esac
