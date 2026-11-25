#!/usr/bin/env bash
# Exit: 0 always.
set -u

usage() {
  cat <<'EOF'
resolve-clean-action.sh — normalize clean-skill invocation tokens.

Usage:
  resolve-clean-action.sh [<token> ...]
  resolve-clean-action.sh --help

With no args, emits Action: menu.
Exit: 0.
EOF
}

case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
*) ;;
esac

if [[ $# -eq 0 ]]; then
  printf 'Action: menu\n'
  exit 0
fi

joined="$(printf '%s ' "$@" | tr '[:upper:]' '[:lower:]')"

resolve_token() {
  local t
  t="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$t" in
  scan | inventory | space | audit | report | show)
    printf 'scan'
    ;;
  cache | caches | linter-caches | linter)
    printf 'caches'
    ;;
  build | artifacts | artifact | bin | obj | output)
    printf 'build'
    ;;
  git | branches | branch | prune | gc)
    printf 'git'
    ;;
  stash | stashes | stash-audit)
    printf 'stash'
    ;;
  tree | fresh | fresh-pull | fresh-pull-state | pristine | reset-tree | working-tree)
    printf 'tree'
    ;;
  tree-batch | batch | fleet | multi-repo | reset-all)
    printf 'tree-batch'
    ;;
  scan-batch | scan-fleet | inventory-batch)
    printf 'scan-batch'
    ;;
  caches-batch | caches-fleet | cache-batch)
    printf 'caches-batch'
    ;;
  build-batch | build-fleet | artifacts-batch)
    printf 'build-batch'
    ;;
  git-batch | git-fleet | prune-batch | gc-batch)
    printf 'git-batch'
    ;;
  all-batch | all-fleet | sweep-batch | clean-all)
    printf 'all-batch'
    ;;
  all | sweep | everything)
    printf 'all'
    ;;
  *) ;;
  esac
}

is_fleet_phrase() {
  case "$1" in
  *reset\ all* | *all\ my\ repos* | *all\ repos* | *every\ repo* | *across\ repos* | *ghq\ list*)
    return 0
    ;;
  *) return 1 ;;
  esac
}

has_fleet_indicator() {
  is_fleet_phrase "$1" && return 0
  case "$1" in
  *fleet* | *batch* | *multi-repo*) return 0 ;;
  *) return 1 ;;
  esac
}

has_reset_intent() {
  case "$1" in
  *reset* | *fresh\ pull* | *fresh-pull* | *fresh\ clone* | *pristine* | *wipe*) return 0 ;;
  *) return 1 ;;
  esac
}

fleet_tier() {
  if has_reset_intent "$1"; then printf 'tree-batch'; else printf 'all-batch'; fi
}

sel=""
for token in "$@"; do
  t="$(resolve_token "$token")"
  case "$t" in
  caches | build | git)
    if [[ -z "$sel" ]]; then
      sel="$t"
    elif [[ "$sel" != "$t" ]]; then
      sel="__conflict__"
    fi
    ;;
  *) ;;
  esac
done
if [[ -n "$sel" && "$sel" != "__conflict__" ]] && has_fleet_indicator "$joined"; then
  printf 'Action: %s-batch\n' "$sel"
  exit 0
fi

canonical=""
note=""

first_action="$(resolve_token "$1")"
second_action="$(resolve_token "${2:-}")"
if [[ -n "$first_action" && $# -ge 2 && -z "$second_action" ]] && ! has_fleet_indicator "$joined"; then
  canonical="$first_action"
  shift
  note="$*"
  note="${note#"${note%%[![:space:]]*}"}"
  note="${note%"${note##*[![:space:]]}"}"
fi

if [[ -z "$canonical" ]]; then
  for token in "$@"; do
    hit="$(resolve_token "$token")"
    if [[ "$hit" == "all" ]] && is_fleet_phrase "$joined"; then
      hit="$(fleet_tier "$joined")"
    fi
    if [[ -n "$hit" ]]; then
      if [[ -z "$canonical" ]]; then
        canonical="$hit"
      elif [[ "$canonical" != "$hit" ]]; then
        printf 'Action: menu\n'
        exit 0
      fi
    fi
  done
fi

if [[ -z "$canonical" ]] && is_fleet_phrase "$joined"; then
  canonical="$(fleet_tier "$joined")"
elif [[ -z "$canonical" ]]; then
  case "$joined" in
  *fresh\ pull* | *fresh\ clone* | *like\ a\ fresh* | *reset\ to\ origin* | *wipe\ ignored*)
    canonical=tree
    ;;
  *disk\ space* | *taking\ up\ space* | *what*using*space* | *how\ much*)
    canonical=scan
    ;;
  *node_modules* | *\.venv* | *build\ output* | *bin/*obj*)
    canonical=build
    ;;
  *stale\ branch* | *merged\ branch*)
    canonical=git
    ;;
  *) ;;
  esac
fi

if [[ -z "$canonical" ]]; then
  printf 'Action: menu\n'
else
  printf 'Action: %s\n' "$canonical"
  [[ -n "$note" ]] && printf 'Note: %s\n' "$note"
fi
exit 0
