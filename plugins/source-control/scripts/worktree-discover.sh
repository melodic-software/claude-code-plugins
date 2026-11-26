#!/usr/bin/env bash
# Exit codes:
#   0  inventory printed
#   2  usage, or an unreadable root file or fleet config
#   3  no worktree root resolved (rows for repositories are still printed)
#   5  a repository's worktrees cannot be listed (git older than the -z floor);
#      nothing is printed

set -uo pipefail

PROG=${0##*/}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() {
  printf '%s: %s\n' "$PROG" "$*" >&2
  exit 2
}

_worktree_root_git() { command git "$@"; }
# shellcheck source=worktree-root-resolve.sh
source "$SCRIPT_DIR/worktree-root-resolve.sh"
# shellcheck source=scope-resolve.sh
source "$SCRIPT_DIR/scope-resolve.sh"
# shellcheck source=fleet-discovery.sh
source "$SCRIPT_DIR/fleet-discovery.sh"
# shellcheck source=lib/worktree-facts.sh
source "$SCRIPT_DIR/lib/worktree-facts.sh"

usage() {
  printf 'Usage: %s [--repo-dir REPO]... [--fallback-root-file PATH] [--data-root-file PATH] [--project-dir DIR] [--remove-input-files]\n' "$PROG" >&2
  exit 2
}

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

# shellcheck disable=SC2329  # invoked by the EXIT trap
remove_input_files_on_exit() {
  local file
  for file in "${fallback_root_file:-}" "${data_root_file:-}"; do
    [[ -n "$file" ]] || continue
    rm -f -- "$file"
    rmdir -- "$(dirname -- "$file")" 2>/dev/null || true
  done
}

named=()
fallback_root=""
data_root=""
unset fallback_root_file data_root_file
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
    fallback_root_file="$2"
    shift 2
    ;;
  --data-root-file)
    [[ $# -ge 2 ]] || usage
    data_root_file="$2"
    shift 2
    ;;
  --project-dir)
    [[ $# -ge 2 ]] || usage
    project_dir="$2"
    shift 2
    ;;
  --remove-input-files)
    trap remove_input_files_on_exit EXIT
    shift
    ;;
  *) usage ;;
  esac
done
if [[ -n "${fallback_root_file+x}" ]]; then
  fallback_root="$(read_root_file "$fallback_root_file")" || exit 2
fi
if [[ -n "${data_root_file+x}" ]]; then
  data_root="$(read_root_file "$data_root_file")" || exit 2
fi

SKIP_NAMES=()
SKIP_APPEND_NAMES=()
FLEET_CONFIG_ROOTS=()
FLEET_CONFIG_REPOS=()
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

repos=()
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

roots=()
rungs=()
add_root() {
  local p="${1//\\//}" r
  while [[ ${#p} -gt 1 && "$p" == */ ]]; do p="${p%/}"; done
  tsv_safe "$p" || return 0
  for r in ${roots[@]+"${roots[@]}"}; do
    [[ "$r" == "$p" ]] && return 0
  done
  roots+=("$p")
  rungs+=("$2")
}
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

wt_rows=""
wt_seen=$'\n'
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
      wt_seen+="$d"$'\n'
    done
  done
done

roots_phys=()
for i in ${roots[@]+"${!roots[@]}"}; do
  roots_phys[i]="$(cd -P -- "${roots[$i]}" 2>/dev/null && pwd)" || roots_phys[i]=""
done
under_root() {
  local i phys
  for i in ${roots[@]+"${!roots[@]}"}; do
    phys="${roots_phys[$i]}"
    if [[ "$1" == "${roots[$i]}"/* ]]; then
      UNDER="$1"
      return 0
    elif [[ -n "$phys" && "$1" == "$phys"/* ]]; then
      UNDER="${roots[$i]}/${1#"$phys"/}"
      return 0
    fi
  done
  return 1
}

repo_rows=""
for r in ${repos[@]+"${repos[@]}"}; do
  porcelain="$(mktemp)" || fail "cannot create a temporary file"
  if ! git -C "$r" worktree list --porcelain -z >"$porcelain" 2>/dev/null; then
    rm -f -- "$porcelain"
    printf '%s: cannot list worktrees of %s; %s\n' "$PROG" "$r" "$(worktree_list_z_floor_note)" >&2
    exit 5
  fi
  worktree_facts_parse_z "$porcelain"
  rm -f -- "$porcelain"
  linked=$((${#WT_FACT_PATH[@]} - 1))
  for i in ${WT_FACT_PATH[@]+"${!WT_FACT_PATH[@]}"}; do
    ((i > 0)) || continue
    under_root "${WT_FACT_PATH[$i]}" || continue
    [[ -d "$UNDER" && "$wt_seen" != *$'\n'"$UNDER"$'\n'* ]] || continue
    tsv_safe "$UNDER" || continue
    wt_rows+="worktree"$'\t'"$UNDER"$'\t'"$r"$'\n'
    wt_seen+="$UNDER"$'\n'
  done
  repo_rows+="repo"$'\t'"$r"$'\t'"$((linked > 0 ? linked : 0))"$'\n'
done

for i in ${roots[@]+"${!roots[@]}"}; do
  printf 'root\t%s\t%s\n' "${roots[$i]}" "${rungs[$i]}"
done
printf '%s' "$repo_rows"
printf '%s' "$wt_rows"

if [[ ${#roots[@]} -eq 0 ]]; then
  printf '%s: no worktree root resolved; set worktreeroot.path or pass --data-root-file\n' "$PROG" >&2
  exit 3
fi
exit 0
