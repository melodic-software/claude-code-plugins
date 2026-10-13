#!/usr/bin/env bash
# worktree-discover.sh — cross-repository inventory for the worktree skill's
# `status`, `audit` and `cleanup` when the session is not inside a repository.
# Report only: it never writes git config, deletes, moves or repairs anything.
#
# Usage:
#   worktree-discover.sh [--repo-dir REPO]... [--fallback-root-file PATH]
#                        [--data-root-file PATH] [--project-dir DIR]
#     --repo-dir            a repository to inventory (repeatable). When given,
#                           only these repositories are discovered. Otherwise the
#                           fleet audit's scope applies: fleet.root/fleet.repo
#                           from <project-dir>/.claude/repo-fleet-hygiene.conf,
#                           else ~/.claude/repo-fleet-hygiene.conf, else its
#                           no-scope ladder (ghq roots, then an ancestor holding
#                           2+ repositories)
#     --project-dir         the session's project directory. A skill passes the
#                           value its own body substituted for CLAUDE_PROJECT_DIR,
#                           which the Bash tool's environment does not carry;
#                           without the flag the environment variable is read, for
#                           callers that have it
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
# did not reach it, and its own root is resolved and scanned in turn. A path
# holding a tab or newline cannot be a TSV field: it is skipped with a warning
# on stderr.
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
  printf 'Usage: %s [--repo-dir REPO]... [--fallback-root-file PATH] [--data-root-file PATH] [--project-dir DIR]\n' "$PROG" >&2
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
project_dir="${CLAUDE_PROJECT_DIR:-}"
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
  --project-dir)
    [[ $# -ge 2 ]] || usage
    project_dir="$2"
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
# The fleet audit's config ladder: the project-scoped file, then the user-global
# one. A literal ${...} that survived substitution is no project directory.
# shellcheck disable=SC2016  # the literal token, not an expansion
[[ "$project_dir" == '${'* ]] && project_dir=""
conf=""
for f in ${project_dir:+"$project_dir/.claude/repo-fleet-hygiene.conf"} \
  "${HOME:-${USERPROFILE:-}}/.claude/repo-fleet-hygiene.conf"; do
  [[ -f "$f" ]] && conf="$f" && break
done
if [[ -n "$conf" ]]; then
  git config --file "$conf" --list >/dev/null 2>&1 || fail "invalid Git config: $conf"
  fleet_load_config_skip "$conf"
  # Named repositories replace the configured scope rather than adding to it.
  [[ ${#named[@]} -gt 0 ]] || fleet_load_config_scope "$conf" "${conf%/*}"
fi
fleet_finalize_skip_names
fleet_resolve_max_depth "" "$conf"

candidates=(${named[@]+"${named[@]}"} ${FLEET_CONFIG_REPOS[@]+"${FLEET_CONFIG_REPOS[@]}"})
search_roots=(${FLEET_CONFIG_ROOTS[@]+"${FLEET_CONFIG_ROOTS[@]}"})
if [[ ${#candidates[@]} -eq 0 && ${#search_roots[@]} -eq 0 ]]; then
  # shellcheck disable=SC2119  # no named paths reach this branch
  while IFS=$'\t' read -r kind value; do
    case "$kind" in
    repo) candidates+=("$value") ;;
    root) search_roots+=("$value") ;;
    *) ;;
    esac
  done < <(scope_resolve_fallback || true)
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
# tsv_safe <path>: false, with a warning, when <path> cannot be a TSV field.
tsv_safe() {
  [[ "$1" != *$'\t'* && "$1" != *$'\n'* ]] && return 0
  printf '%s: skipped a path holding a tab or newline: %q\n' "$PROG" "$1" >&2
  return 1
}
add_repo() {
  local r
  tsv_safe "$1" || return 0
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
  tsv_safe "$p" || return 0
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

# --- Resolve each repository's root and scan each root, until neither grows --
# A root scan can find an owner discovery missed, whose own root may differ.
wt_rows=""
resolved=0
scanned=0
while [[ $resolved -lt ${#repos[@]} || $scanned -lt ${#roots[@]} ]]; do
  while [[ $resolved -lt ${#repos[@]} ]]; do
    # shellcheck disable=SC2310  # unset is an answer, handled by the else arm
    if worktree_root_resolve "${repos[$resolved]}"; then
      add_root "$WORKTREE_ROOT_VALUE" git-config
    else
      rest_of_chain
    fi
    resolved=$((resolved + 1))
  done
  while [[ $scanned -lt ${#roots[@]} ]]; do
    root="${roots[$scanned]}"
    scanned=$((scanned + 1))
    [[ -d "$root" ]] || continue
    for d in "$root"/* "$root"/.[!.]* "$root"/..?*; do
      [[ -d "$d" && ! -L "$d" ]] || continue
      [[ -e "$d/.git" ]] || continue
      tsv_safe "$d" || continue
      owner="$(GIT_CEILING_DIRECTORIES="$root" owner_of "$d")" || owner="-"
      if [[ "$owner" != - ]] && ! tsv_safe "$owner"; then owner="-"; fi
      [[ "$owner" == - ]] || add_repo "$owner"
      wt_rows+="worktree"$'\t'"$d"$'\t'"$owner"$'\n'
    done
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
