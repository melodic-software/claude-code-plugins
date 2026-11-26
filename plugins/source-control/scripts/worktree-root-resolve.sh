#!/usr/bin/env bash
# GENERATED from lib/worktree-root-resolve.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# worktree-root-resolve.sh — last-wins read of worktreeroot.path.
# Owner: reference/worktree-root-convention.md (source-control).
#
# Git-config(1) Variables invites third-party keys that do not collide with
# Git or popular tools. Git owns worktree.*; git-wt owns wt.basedir. This
# capability section is the collision-free spelling.
#
# A retired alias peel (auto-rewrite onto this key, then drop) lives in
# worktree-root-legacy.sh and is deleted after 2026-12-31.
#
# Sourced or executed. When executed:
#   worktree-root-resolve.sh --repo-dir <dir>
#   stdout: the path (one line) or empty
#   exit 0 (including unset), 2 usage
#
# When sourced, call worktree_root_resolve <repo-dir>
#   returns 0 and sets WORKTREE_ROOT_VALUE / WORKTREE_ROOT_KEY_USED
#   returns 1 if no key yields a non-empty last value
#   KEY_USED is always the current key when a value is returned
#
# Git invocation: _worktree_root_git if that function is defined (the
# fleet-audit allowlist wrapper), else hook::git_untrusted when hook-utils.sh is
# loaded (its overrides: https://git-scm.com/docs/git#Documentation/git.txt--cltnamegtltvaluegt),
# else git. No scope flag: includes stay on.

WORKTREE_ROOT_CURRENT_KEY="worktreeroot.path"

# Command-substitution `$(cd && pwd)` would add a fork on every source, including
# the containment-gate hot path. Keep the same `%/*` form the other callers use.
# shellcheck source=worktree-root-legacy.sh
source "${BASH_SOURCE[0]%/*}/worktree-root-legacy.sh"

worktree_root_git() {
  if declare -F _worktree_root_git >/dev/null 2>&1; then
    _worktree_root_git "$@"
  elif declare -F hook::git_untrusted >/dev/null 2>&1; then
    hook::git_untrusted "$@"
  else
    command git "$@"
  fi
}

# Last record of --get-all --type=path, including a blank last record.
# Prints that record (possibly empty) and returns 0 when the key had at
# least one value; returns 1 when the key is unset.
worktree_root_last_raw() {
  local repo="$1" key="$2" last="" had=0 line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    last="$line"
    had=1
  done < <(worktree_root_git -C "$repo" config --get-all --type=path "$key" 2>/dev/null)
  ((had)) || return 1
  printf '%s' "$last"
  return 0
}

# Sets WORKTREE_ROOT_VALUE and WORKTREE_ROOT_KEY_USED. Empty last value on a
# key is not usable: try the next key (matching create.sh falling through
# when tail -n 1 is blank). A retired-alias hit is rewritten onto the current
# key at the winning origin unless the git wrapper is read-only.
worktree_root_resolve() {
  local repo="$1" raw=""
  # Exported: sourced callers (create, doctor, containment, fleet audit) read these.
  export WORKTREE_ROOT_VALUE=""
  export WORKTREE_ROOT_KEY_USED=""
  [[ -n "$repo" ]] || return 1
  worktree_root_git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || return 1

  if raw=$(worktree_root_last_raw "$repo" "$WORKTREE_ROOT_CURRENT_KEY") &&
    [[ -n "$raw" ]]; then
    worktree_root_legacy_retire "$repo"
  elif [[ -n "${WORKTREE_ROOT_LEGACY_KEY:-}" ]] &&
    raw=$(worktree_root_last_raw "$repo" "$WORKTREE_ROOT_LEGACY_KEY") &&
    [[ -n "$raw" ]]; then
    worktree_root_legacy_promote "$repo" || true
  else
    return 1
  fi
  WORKTREE_ROOT_VALUE="$raw"
  WORKTREE_ROOT_KEY_USED="$WORKTREE_ROOT_CURRENT_KEY"
  return 0
}

worktree_root_expand_tilde() {
  local p="$1"
  # Config values arrive verbatim, so matching the literal unexpanded tilde is the point.
  # shellcheck disable=SC2088
  if [[ "$p" == "~/"* && -n "${HOME:-}" ]]; then
    printf '%s/%s' "${HOME%/}" "${p#\~/}"
  elif [[ "$p" == "~" && -n "${HOME:-}" ]]; then
    printf '%s' "${HOME%/}"
  else
    printf '%s' "$p"
  fi
}

worktree_root_canon() {
  local r
  if r=$(realpath -- "$1" 2>/dev/null) || r=$(readlink -f -- "$1" 2>/dev/null); then
    [[ -n "$r" ]] && {
      printf '%s' "$r"
      return 0
    }
  fi
  printf '%s' "$1"
}

_worktree_root_resolve_include_target() {
  local raw="$1" origin="$2" rp
  rp="$(worktree_root_expand_tilde "$raw")"
  if [[ "$rp" != /* && ! "$rp" =~ ^[A-Za-z]:/ && -n "$origin" ]]; then
    rp="$(dirname -- "$origin")/$rp"
  fi
  worktree_root_canon "$rp"
}

_worktree_root_parse_config_stream() {
  local origin kv key val ofile cond resolved kind
  while IFS= read -r -d '' origin && IFS= read -r -d '' kv; do
    if [[ "$kv" == *$'\n'* ]]; then
      key="${kv%%$'\n'*}"
      val="${kv#*$'\n'}"
    else
      key="$kv"
      val=""
    fi
    ofile=""
    [[ "$origin" == file:* ]] && ofile="${origin#file:}"
    if [[ -n "$ofile" ]]; then
      WORKTREE_ROOT_ORIGINS+=("$(worktree_root_canon "$ofile")")
    fi
    kind=""
    cond=""
    if [[ "$key" == "include.path" ]]; then
      kind="include"
    elif [[ "$key" == includeif.*.path ]]; then
      kind="includeif"
      cond="${key#includeif.}"
      cond="${cond%.path}"
    else
      continue
    fi
    resolved="$(_worktree_root_resolve_include_target "$val" "$ofile")"
    WORKTREE_ROOT_INC_KINDS+=("$kind")
    WORKTREE_ROOT_INC_CONDS+=("$cond")
    WORKTREE_ROOT_INC_PATHS+=("$val")
    WORKTREE_ROOT_INC_ORIGINS+=("$ofile")
    WORKTREE_ROOT_INC_RESOLVED+=("$resolved")
  done
}

worktree_root_collect_includes() {
  local repo="${1:-}"
  WORKTREE_ROOT_INC_KINDS=()
  WORKTREE_ROOT_INC_CONDS=()
  WORKTREE_ROOT_INC_PATHS=()
  WORKTREE_ROOT_INC_ORIGINS=()
  WORKTREE_ROOT_INC_RESOLVED=()
  WORKTREE_ROOT_ORIGINS=()

  if [[ -n "$repo" ]]; then
    _worktree_root_parse_config_stream < <(
      worktree_root_git -C "$repo" config --list --show-origin -z 2>/dev/null | tr -d '\r'
    )
    return 0
  fi

  _worktree_root_parse_config_stream < <(
    worktree_root_git config --global --includes --list --show-origin -z 2>/dev/null | tr -d '\r'
  )

  local -A visited=()
  local orig idx=0 f
  for orig in ${WORKTREE_ROOT_ORIGINS[@]+"${WORKTREE_ROOT_ORIGINS[@]}"}; do
    visited["$orig"]=1
  done
  while ((idx < ${#WORKTREE_ROOT_INC_RESOLVED[@]})); do
    f="${WORKTREE_ROOT_INC_RESOLVED[$idx]}"
    idx=$((idx + 1))
    [[ -n "$f" && -f "$f" && -r "$f" ]] || continue
    [[ -z "${visited[$f]+x}" ]] || continue
    visited["$f"]=1
    _worktree_root_parse_config_stream < <(
      worktree_root_git config --file "$f" --includes --list --show-origin -z 2>/dev/null | tr -d '\r'
    )
  done
  return 0
}

_worktree_root_file_last() {
  local file="$1" key="$2" last="" had=0 line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    last="$line"
    had=1
  done < <(worktree_root_git config --file "$file" --includes --get-all --type=path "$key" 2>/dev/null)
  ((had)) || return 1
  printf '%s' "$last"
  return 0
}

worktree_root_list_all() {
  local -a found=()
  local -A seen=()
  local line val f norm

  _wt_add_root() {
    local p="${1//\\//}"
    [[ -n "$p" ]] || return 0
    while [[ ${#p} -gt 1 && "$p" == */ ]]; do p="${p%/}"; done
    [[ -z "${seen[$p]+x}" ]] || return 0
    seen["$p"]=1
    found+=("$p")
  }

  val=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    val="${line%$'\r'}"
  done < <(worktree_root_git config --global --includes --get-all --type=path "$WORKTREE_ROOT_CURRENT_KEY" 2>/dev/null)
  if [[ -z "$val" && -n "${WORKTREE_ROOT_LEGACY_KEY:-}" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      val="${line%$'\r'}"
    done < <(worktree_root_git config --global --includes --get-all --type=path "$WORKTREE_ROOT_LEGACY_KEY" 2>/dev/null)
  fi
  [[ -n "$val" ]] && _wt_add_root "$val"

  worktree_root_collect_includes
  local -A inspected=()
  for f in ${WORKTREE_ROOT_INC_RESOLVED[@]+"${WORKTREE_ROOT_INC_RESOLVED[@]}"}; do
    [[ -n "$f" && -f "$f" && -r "$f" ]] || continue
    [[ -z "${inspected[$f]+x}" ]] || continue
    inspected["$f"]=1
    val=""
    if ! val="$(_worktree_root_file_last "$f" "$WORKTREE_ROOT_CURRENT_KEY")" || [[ -z "$val" ]]; then
      if [[ -n "${WORKTREE_ROOT_LEGACY_KEY:-}" ]]; then
        val="$(_worktree_root_file_last "$f" "$WORKTREE_ROOT_LEGACY_KEY")" || val=""
      fi
    fi
    [[ -n "$val" ]] || continue
    norm="$(worktree_root_expand_tilde "$val")"
    if [[ "$norm" != /* && ! "$norm" =~ ^[A-Za-z]:/ ]]; then
      norm="$(dirname -- "$f")/$norm"
    fi
    _wt_add_root "$norm"
  done

  for norm in ${found[@]+"${found[@]}"}; do
    printf '%s\n' "$norm"
  done
  return 0
}

worktree_root_resolve_main() {
  local repo_dir="." repo_dir_set=0 all_mode=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --repo-dir)
      [[ $# -ge 2 ]] || {
        printf 'worktree-root-resolve.sh: --repo-dir requires a value\n' >&2
        return 2
      }
      repo_dir="$2"
      repo_dir_set=1
      shift 2
      ;;
    --all)
      all_mode=1
      shift
      ;;
    -h | --help)
      printf '%s\n' "worktree-root-resolve.sh [--repo-dir <dir> | --all]"
      return 0
      ;;
    *)
      printf 'worktree-root-resolve.sh: unknown argument: %s\n' "$1" >&2
      return 2
      ;;
    esac
  done
  if ((all_mode && repo_dir_set)); then
    printf 'worktree-root-resolve.sh: --all and --repo-dir cannot be combined\n' >&2
    return 2
  fi
  if ((all_mode)); then
    worktree_root_list_all
    return 0
  fi
  if worktree_root_resolve "$repo_dir"; then
    printf '%s\n' "$WORKTREE_ROOT_VALUE"
  fi
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  worktree_root_resolve_main "$@"
fi
