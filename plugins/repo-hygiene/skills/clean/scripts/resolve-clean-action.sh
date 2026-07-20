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
  tree-batch | batch | fleet | multi-repo | reset-all)
    printf 'tree-batch'
    ;;
  all | sweep | everything)
    printf 'all'
    ;;
  *)
    printf ''
    ;;
  esac
}

# A whole-phrase fleet intent ("reset all my repos", "every repo", "ghq list").
# Kept in one place so the token loop and the no-token fallback below agree on
# what reads as a multi-repo reset.
is_fleet_phrase() {
  case "$1" in
  *reset\ all* | *all\ my\ repos* | *all\ repos* | *every\ repo* | *across\ repos* | *ghq\ list*)
    return 0
    ;;
  *) return 1 ;;
  esac
}

canonical=""
for token in "$@"; do
  lower="$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')"
  hit="$(resolve_one "$lower")"
  # A bare "all" token is the single-repo `all` tier, but inside a fleet phrase it
  # names the multi-repo tree-batch. Let the phrase win over the token so "reset
  # all my repos" routes to tree-batch instead of the single-repo sweep. A genuine
  # conflict with another explicit token (e.g. "scan all repos") still falls to the
  # menu via the mismatch check below.
  if [[ "$hit" == "all" ]] && is_fleet_phrase "$joined"; then
    hit=tree-batch
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

if [[ -z "$canonical" ]]; then
  if is_fleet_phrase "$joined"; then
    canonical=tree-batch
  else
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
fi

if [[ -z "$canonical" ]]; then
  printf 'Action: menu\n'
else
  printf 'Action: %s\n' "$canonical"
fi
exit 0
