#!/usr/bin/env bash
# Map clean-skill user tokens to canonical action names (Tier-0 fact emission).
#
# Output: Action: <scan|caches|build|git|stash|tree|tree-batch|all|menu>
#   plus an optional `Note: <trailing free text>` when a leading action token is
#   followed by advisory context (a question or a live-session constraint).
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
  stash | stashes | stash-audit)
    printf 'stash'
    ;;
  tree | fresh | fresh-pull | fresh-pull-state | pristine | reset-tree | working-tree)
    printf 'tree'
    ;;
  tree-batch | batch | fleet | multi-repo | reset-all)
    printf 'tree-batch'
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

# Any multi-repo signal: a fleet phrase, or a bare fleet/batch/multi-repo word.
# Broader than is_fleet_phrase because it also catches "across the fleet" and a
# lone "fleet"/"batch" token co-occurring with a selective tier.
has_fleet_indicator() {
  is_fleet_phrase "$1" && return 0
  case "$1" in
  *fleet* | *batch* | *multi-repo*) return 0 ;;
  *) return 1 ;;
  esac
}

# Destructive fresh-pull / reset intent. A fleet phrase that names the `all` tier
# is the DESTRUCTIVE tree-batch only when it also reads as a reset; a plain
# "clean all repos" is a selective all-batch sweep, not a reset-hard preview.
has_reset_intent() {
  case "$1" in
  *reset* | *fresh\ pull* | *fresh-pull* | *fresh\ clone* | *pristine* | *wipe*) return 0 ;;
  *) return 1 ;;
  esac
}

# Selective tier + fleet intent => the selective batch form, decided BEFORE the
# bare fleet/all -> tree-batch upgrade below. A selective sweep across a fleet
# ("clean caches across all repos", "caches fleet", "prune git across the fleet")
# must route to the non-destructive `<tier>-batch`, never the destructive tree
# reset. Only fires for a single unambiguous selective tier; a mix (caches + build)
# falls through to the normal conflict path.
sel=""
for token in "$@"; do
  case "$(resolve_one "$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')")" in
  caches | build | git)
    t="$(resolve_one "$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')")"
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

# "Action token + advisory note" shape: a leading action token followed by free
# text (a question or a live-session constraint), where that trailing text is NOT
# itself a second action token and the whole input carries no fleet indicator. The
# note must not be re-interpreted as an action — so trailing text that merely
# mentions an action word (e.g. "…include stashes?") does not read as a conflict.
# A genuine second action token (e.g. "scan tree", "scan all repos") is left to the
# full-token resolution below, which reports the ambiguity as `menu`. Gate on
# has_fleet_indicator (not just is_fleet_phrase) so a fleet request the phrase list
# misses ("all across the fleet") routes to the batch tier below instead of being
# preempted into a single-repo action with the fleet words demoted to a note.
first_lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
first_action="$(resolve_one "$first_lower")"
second_action=""
if [[ $# -ge 2 ]]; then
  second_lower="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
  second_action="$(resolve_one "$second_lower")"
fi
if [[ -n "$first_action" && $# -ge 2 && -z "$second_action" ]] && ! has_fleet_indicator "$joined"; then
  canonical="$first_action"
  shift
  note="$*"
  note="${note#"${note%%[![:space:]]*}"}"
  note="${note%"${note##*[![:space:]]}"}"
fi

if [[ -z "$canonical" ]]; then
  for token in "$@"; do
    lower="$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')"
    hit="$(resolve_one "$lower")"
    # A bare "all" token is the single-repo `all` tier, but inside a fleet phrase it
    # names a multi-repo sweep. Reset/fresh-pull phrasing ("reset all my repos") is
    # the DESTRUCTIVE tree-batch; a plain fleet cleanup ("clean all repos", "sweep
    # across all repos") is the SELECTIVE all-batch — never preview a reset-hard for
    # an innocuous all-tier request. A genuine conflict with another explicit token
    # (e.g. "scan all repos") still falls to the menu via the mismatch check below.
    if [[ "$hit" == "all" ]] && is_fleet_phrase "$joined"; then
      if has_reset_intent "$joined"; then hit=tree-batch; else hit=all-batch; fi
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

if [[ -z "$canonical" ]]; then
  if is_fleet_phrase "$joined"; then
    if has_reset_intent "$joined"; then canonical=tree-batch; else canonical=all-batch; fi
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
  [[ -n "$note" ]] && printf 'Note: %s\n' "$note"
fi
exit 0
