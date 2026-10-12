#!/usr/bin/env bash
# worktree-discover.sh — cross-repository inventory for the worktree skill's
# `status`, `audit` and `cleanup` when the session is not inside a repository.
# Report only: it never writes git config, deletes, moves or repairs anything.
#
# Usage:
#   worktree-discover.sh [--repo-dir REPO]... [--fallback-root-file PATH]
#                        [--data-root-file PATH]
#     --repo-dir            a repository to include (repeatable); with none, and
#                           no fleet.root/fleet.repo in the user-global
#                           ~/.claude/repo-fleet-hygiene.conf, repositories come
#                           from the same no-scope ladder the fleet audit uses
#                           (ghq roots, then an ancestor holding 2+ repositories)
#     --fallback-root-file  the worktree_root plugin option, as worktree-create.sh
#     --data-root-file      the plugin data directory, as worktree-create.sh
#
# Output, tab-separated:
#   root      <path> <rung>         each distinct worktree root: the chain
#                                   worktree-create.sh uses, evaluated once with no
#                                   repository and once per repository (rung is
#                                   git-config, plugin-option or plugin-data)
#   repo      <path> <linked>       each canonical repository, with its count of
#                                   linked worktrees anywhere on disk
#   worktree  <path> <repo>         each direct child of a root holding a .git
#                                   entry, with its owning repository, or `-` when
#                                   git cannot resolve one (worktree-root-scan.sh
#                                   classifies those)
# A repository that owns a worktree under a root is listed even when discovery
# did not reach it.
#
# Exit codes:
#   0  inventory printed
#   2  usage, or an unreadable root file or fleet config
#   3  no worktree root resolved (rows for repositories are still printed)

set -uo pipefail

PROG=${0##*/}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() {
  printf '%s: %s\n' "$PROG" "$*" >&2
  exit 2
}

# Read-only: with this wrapper defined the resolver's retired-alias peel only
# reads, as in the fleet audit.
_worktree_root_git() { command git "$@"; }
# shellcheck source=worktree-root-resolve.sh
source "$SCRIPT_DIR/worktree-root-resolve.sh"
# shellcheck source=scope-resolve.sh
source "$SCRIPT_DIR/scope-resolve.sh"
# shellcheck source=fleet-discovery.sh
source "$SCRIPT_DIR/fleet-discovery.sh"

usage() {
  printf 'Usage: %s [--repo-dir REPO]... [--fallback-root-file PATH] [--data-root-file PATH]\n' "$PROG" >&2
  exit 2
}

# read_root_file <file>: the file's bytes verbatim; empty for an unexpanded
# substitution token, which means the rung is unconfigured.
read_root_file() {
  local value
  [[ -f "$1" ]] || fail "root file not found: $1"
  value=$(
    cat "$1"
    printf x
  )
  value=${value%x}
  [[ "$value" != *$'\n'* ]] || fail "root file holds a newline: $1"
  # shellcheck disable=SC2016
  [[ "$value" == *'${'* ]] && value=""
  printf '%s' "$value"
}

named=()
fallback_root=""
data_root=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --repo-dir)
    [[ $# -ge 2 ]] || usage
    named+=("$2")
    shift 2
    ;;
  --fallback-root-file)
    [[ $# -ge 2 ]] || usage
    fallback_root="$(read_root_file "$2")" || exit 2
    shift 2
    ;;
  --data-root-file)
    [[ $# -ge 2 ]] || usage
    data_root="$(read_root_file "$2")" || exit 2
    shift 2
    ;;
  *) usage ;;
  esac
done

# --- Repository discovery: the fleet audit's scope, without its CLI ----------
SKIP_NAMES=()
SKIP_APPEND_NAMES=()
FLEET_CONFIG_ROOTS=()
FLEET_CONFIG_REPOS=()
conf="${HOME:-${USERPROFILE:-}}/.claude/repo-fleet-hygiene.conf"
if [[ -f "$conf" ]]; then
  git config --file "$conf" --list >/dev/null 2>&1 || fail "invalid Git config: $conf"
  fleet_load_config_scope "$conf" "${conf%/*}"
  fleet_load_config_skip "$conf"
else
  conf=""
fi
fleet_finalize_skip_names
fleet_resolve_max_depth "" "$conf"

candidates=(${named[@]+"${named[@]}"} ${FLEET_CONFIG_REPOS[@]+"${FLEET_CONFIG_REPOS[@]}"})
search_roots=(${FLEET_CONFIG_ROOTS[@]+"${FLEET_CONFIG_ROOTS[@]}"})
if [[ ${#candidates[@]} -eq 0 && ${#search_roots[@]} -eq 0 ]]; then
  while IFS=$'\t' read -r kind value; do
    case "$kind" in
    repo) candidates+=("$value") ;;
    root) search_roots+=("$value") ;;
    *) ;;
    esac
  done < <(scope_resolve_fallback ${named[@]+"${named[@]}"} || true)
fi

fleet_on_repo() { candidates+=("$1"); }
for r in ${search_roots[@]+"${search_roots[@]}"}; do
  r="${r//\\//}"
  [[ "$r" =~ ^[A-Za-z]:$ ]] && r="$r/"
  fleet_discover_root "$r"
done

# --- Canonical repositories, keyed by common dir -----------------------------
repos=()
# owner_of <dir>: the canonical repository owning <dir>, or fail. A linked
# worktree maps to its main checkout; a bare hub maps to its common dir.
owner_of() {
  local common
  common="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  common="${common%$'\r'}"
  [[ -n "$common" ]] || return 1
  if [[ "${common##*/}" == .git ]]; then
    printf '%s' "${common%/.git}"
  else
    printf '%s' "$common"
  fi
}
add_repo() {
  local r
  for r in ${repos[@]+"${repos[@]}"}; do
    [[ "$r" == "$1" ]] && return 0
  done
  repos+=("$1")
}
for c in ${candidates[@]+"${candidates[@]}"}; do
  owner="$(owner_of "$c")" && add_repo "$owner"
done

# --- Worktree roots ----------------------------------------------------------
roots=()
rungs=()
add_root() {
  local p="${1//\\//}" i
  while [[ ${#p} -gt 1 && "$p" == */ ]]; do p="${p%/}"; done
  for i in ${roots[@]+"${!roots[@]}"}; do
    [[ "${roots[$i]}" == "$p" ]] && return 0
  done
  roots+=("$p")
  rungs+=("$2")
}
# The chain worktree-create.sh applies, below its explicit --root rung.
machine_key=""
while IFS= read -r line; do
  machine_key="${line%$'\r'}"
done < <(git config --global --includes --type=path --get-all worktreeroot.path 2>/dev/null)
rest_of_chain() {
  if [[ -n "$fallback_root" ]]; then
    add_root "$fallback_root" plugin-option
  elif [[ -n "$data_root" ]]; then
    add_root "$data_root/worktrees" plugin-data
  fi
}
if [[ -n "$machine_key" ]]; then add_root "$machine_key" git-config; else rest_of_chain; fi
for r in ${repos[@]+"${repos[@]}"}; do
  # shellcheck disable=SC2310  # unset is an answer, handled by the else arm
  if worktree_root_resolve "$r"; then
    add_root "$WORKTREE_ROOT_VALUE" git-config
  else
    rest_of_chain
  fi
done

# --- Worktrees under each root -----------------------------------------------
wt_rows=""
for root in ${roots[@]+"${roots[@]}"}; do
  [[ -d "$root" ]] || continue
  for d in "$root"/* "$root"/.[!.]* "$root"/..?*; do
    [[ -d "$d" && ! -L "$d" ]] || continue
    [[ -e "$d/.git" ]] || continue
    owner="$(GIT_CEILING_DIRECTORIES="$root" owner_of "$d")" || owner="-"
    [[ "$owner" == - ]] || add_repo "$owner"
    wt_rows+="worktree"$'\t'"$d"$'\t'"$owner"$'\n'
  done
done

for i in ${roots[@]+"${!roots[@]}"}; do
  printf 'root\t%s\t%s\n' "${roots[$i]}" "${rungs[$i]}"
done
for r in ${repos[@]+"${repos[@]}"}; do
  linked="$(git -C "$r" worktree list --porcelain 2>/dev/null | grep -c '^worktree ')" || true
  linked=$((${linked:-0} > 0 ? linked - 1 : 0))
  printf 'repo\t%s\t%s\n' "$r" "$linked"
done
printf '%s' "$wt_rows"

if [[ ${#roots[@]} -eq 0 ]]; then
  printf '%s: no worktree root resolved; set worktreeroot.path or pass --data-root-file\n' "$PROG" >&2
  exit 3
fi
exit 0
