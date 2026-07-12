#!/usr/bin/env bash
# Map clean-skill user tokens to canonical action names (Tier-0 fact emission).
#
# Output: Action: <scan|caches|build|git|tree|all|menu>
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

resolve_one() {
  case "$1" in
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
  tree | fresh | fresh-pull | fresh-pull-state | pristine | reset-tree | working-tree)
    printf 'tree'
    ;;
  all | sweep | everything)
    printf 'all'
    ;;
  *)
    printf ''
    ;;
  esac
}

canonical=""
for token in "$@"; do
  lower="$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')"
  hit="$(resolve_one "$lower")"
  if [[ -n "$hit" ]]; then
    if [[ -z "$canonical" ]]; then
      canonical="$hit"
    elif [[ "$canonical" != "$hit" ]]; then
      printf 'Action: menu\n'
      exit 0
    fi
  fi
done

if [[ -z "$canonical" ]]; then
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
fi
exit 0
