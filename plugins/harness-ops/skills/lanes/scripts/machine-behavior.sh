#!/usr/bin/env bash
# Exit codes:
#   0  emitted (individual fields may read `unavailable`)
#   3  invalid argument
#   4  prerequisite missing (jq) or the repo could not be resolved

set -uo pipefail

jq() { command jq "$@" | tr -d '\r'; }

err() { printf 'ERROR: %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
machine-behavior.sh: emit a loop lane's MACHINE-BEHAVIOR environment block (clone path,
worktree inventory, gh identity, installed plugin versions). Unresolvable fields read
`unavailable`; deviations from standing rules are the lane's own judgment, not a field.

Usage:
  machine-behavior.sh [--plugin <id>]... [--repo DIR] [--max-worktrees N]

  --plugin <id>      plugin NAME to report a version for; repeatable (default: every installed plugin)
  --repo DIR         repo root for the worktree inventory (default: the git toplevel)
  --max-worktrees N  list at most N worktrees (default 50; 0 lists all)
  --help

Env (testing only): MACHINE_BEHAVIOR_INSTALLED_JSON  path to installed_plugins.json

Exit codes:
  0  emitted (individual fields may read `unavailable`)
  3  invalid argument
  4  prerequisite missing (jq) or the repo could not be resolved
EOF
}

require_value() {
  [[ -n "${2:-}" && "$2" != -* ]] && return 0
  err "option '$1' requires a value"
  exit 3
}

set_opt() {
  case "$1" in
  --plugin) WANT_PLUGINS+=("$2") ;;
  --repo) REPO="$2" ;;
  --max-worktrees) MAX_WORKTREES="$2" ;;
  *) ;;
  esac
}

INSTALLED_JSON="${MACHINE_BEHAVIOR_INSTALLED_JSON:-$HOME/.claude/plugins/installed_plugins.json}"

REPO=""
MAX_WORKTREES=50
declare -a WANT_PLUGINS=()
while (($#)); do
  case "$1" in
  --plugin | --repo | --max-worktrees)
    require_value "$1" "${2:-}"
    set_opt "$1" "$2"
    shift 2
    ;;
  --plugin=* | --repo=* | --max-worktrees=*)
    set_opt "${1%%=*}" "${1#*=}"
    shift
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

[[ "$MAX_WORKTREES" =~ ^[0-9]+$ ]] || {
  err "--max-worktrees requires a non-negative integer, got: $MAX_WORKTREES"
  exit 3
}
MAX_WORKTREES=$((10#$MAX_WORKTREES))

type -P jq >/dev/null 2>&1 || {
  err "jq not found (required)"
  exit 4
}

if [[ -n "$REPO" ]]; then
  [[ -d "$REPO" ]] || {
    err "repo not a directory: $REPO"
    exit 4
  }
  REPO="$(cd "$REPO" && pwd)"
else
  REPO="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')" || true
  [[ -n "$REPO" ]] || {
    err "not inside a git repo; pass --repo DIR"
    exit 4
  }
fi

gh_identity() {
  local login id
  if ! command -v gh >/dev/null 2>&1; then
    printf 'unavailable (gh not found)'
    return
  fi
  login="$(gh api user --jq '.login' 2>/dev/null | tr -d '\r')"
  id="$(gh api user --jq '.id' 2>/dev/null | tr -d '\r')"
  if [[ -z "$login" ]]; then
    printf 'unavailable (gh api user failed — not authenticated?)'
    return
  fi
  printf '%s (id %s)' "$login" "${id:-?}"
}

CLONE_PATH="unavailable"
CURRENT_WT="unavailable"
declare -a WT_LINES=()

read_worktrees() {
  local porcelain common_dir
  porcelain="$(git -C "$REPO" worktree list --porcelain 2>/dev/null | tr -d '\r')" || return
  common_dir="$(git -C "$REPO" rev-parse --git-common-dir 2>/dev/null | tr -d '\r')"
  if [[ -n "$common_dir" ]]; then
    case "$common_dir" in
    /* | [A-Za-z]:[\\/]*) : ;;           # already absolute (POSIX or Windows drive)
    *) common_dir="$REPO/$common_dir" ;; # relative → anchor to the repo root
    esac
    case "$common_dir" in
    */.git) CLONE_PATH="${common_dir%/.git}" ;;
    *) CLONE_PATH="$(dirname "$common_dir")" ;;
    esac
  fi
  CURRENT_WT="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"

  local path="" branch=""
  while IFS= read -r line; do
    case "$line" in
    "worktree "*) path="${line#worktree }" ;;
    "branch "*) branch="${line#branch refs/heads/}" ;;
    "detached") branch="(detached)" ;;
    "")
      if [[ -n "$path" ]]; then
        WT_LINES+=("$path|${branch:-(detached)}")
        path="" branch=""
      fi
      ;;
    *) ;; # other porcelain fields (HEAD, bare, locked, …) are not needed here
    esac
  done <<<"$porcelain"$'\n'
}

plugin_versions() {
  if [[ ! -f "$INSTALLED_JSON" ]]; then
    printf '  unavailable (installed_plugins.json not found: %s)\n' "$INSTALLED_JSON"
    return
  fi
  if ! jq empty "$INSTALLED_JSON" 2>/dev/null; then
    printf '  unavailable (installed_plugins.json is not valid JSON: %s)\n' "$INSTALLED_JSON"
    return
  fi

  local want_json='[]'
  ((${#WANT_PLUGINS[@]})) && want_json="$(printf '%s\n' "${WANT_PLUGINS[@]}" | jq -Rcn '[inputs]')"

  local rows
  rows="$(jq -r --argjson want "$want_json" '
    (.plugins // {})
    | to_entries
    | map({name: (.key | sub("@.*$"; "")), versions: [.value[].version]})
    | group_by(.name)
    | map({name: .[0].name, versions: (map(.versions) | add | unique)})
    | (if ($want | length) > 0 then map(select(.name as $n | $want | index($n))) else . end)
    | sort_by(.name)
    | .[]
    | "  \(.name)  \(.versions | join(", "))\(if (.versions | length) > 1 then "  (scope-divergent)" else "" end)"
  ' "$INSTALLED_JSON")"

  if [[ -z "$rows" ]]; then
    if ((${#WANT_PLUGINS[@]})); then
      printf '  none of the requested plugins are installed: %s\n' "${WANT_PLUGINS[*]}"
    else
      printf '  (no plugins installed)\n'
    fi
    return
  fi
  printf '%s\n' "$rows"
}

read_worktrees

printf '== MACHINE-BEHAVIOR ==\n'
printf 'gh-identity: %s\n' "$(gh_identity)"
printf 'clone-path: %s\n' "$CLONE_PATH"
printf 'current-worktree: %s\n' "$CURRENT_WT"
printf 'worktree-count: %s\n' "${#WT_LINES[@]}"
if ((${#WT_LINES[@]})); then
  printf 'worktrees:\n'
  shown=${#WT_LINES[@]}
  ((MAX_WORKTREES > 0 && shown > MAX_WORKTREES)) && shown=$MAX_WORKTREES
  for wt_line in "${WT_LINES[@]:0:shown}"; do
    printf '  %s  [%s]\n' "${wt_line%%|*}" "${wt_line#*|}"
  done
  ((shown < ${#WT_LINES[@]})) &&
    printf '  ... %d more (--max-worktrees 0 lists all)\n' "$((${#WT_LINES[@]} - shown))"
fi
printf 'plugin-versions:\n'
plugin_versions
printf 'deviations: assess these facts against the lane standing rules (not scripted: a model judgment)\n'
