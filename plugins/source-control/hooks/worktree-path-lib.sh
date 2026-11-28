# shellcheck shell=bash

WORKTREE_ADD_DIR_CHANGED=0

# shellcheck disable=SC2034  # consumed by the sourcing guard, not by this file
WORKTREE_ADD_BASE=""

worktree_path_is_dynamic() {
  [[ "$1" == *'$'* || "$1" == *'`'* ]]
}

worktree_path_is_abs() {
  [[ "$1" == /* || "$1" =~ ^[A-Za-z]:[/\\] ]]
}

worktree_path_normalize() {
  local input="$1" root rest seg
  if [[ "$input" == /* ]]; then
    root="/"
    rest="${input#/}"
  elif [[ "$input" =~ ^[A-Za-z]:/ ]]; then
    root="${input:0:2}/"
    rest="${input:3}"
  else
    root=""
    rest="$input"
  fi
  local -a segs=() out=()
  IFS='/' read -r -a segs <<<"$rest"
  for seg in "${segs[@]}"; do
    [[ -z "$seg" || "$seg" == "." ]] && continue
    if [[ "$seg" == ".." ]]; then
      ((${#out[@]})) && out=("${out[@]:0:${#out[@]}-1}")
      continue
    fi
    out+=("$seg")
  done
  local IFS='/'
  printf '%s%s' "$root" "${out[*]}"
}

worktree_path_resolve_against() {
  local base="$1" p="$2"
  if [[ ("$p" == *\\* || "$base" == *\\*) && ("${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin*) ]]; then
    local bslash="\\" fwd="/"
    p="${p//"$bslash"/"$fwd"}"
    base="${base//"$bslash"/"$fwd"}"
  fi
  # Matching the literal unexpanded tilde is the point: git never saw a shell-expanded one.
  # shellcheck disable=SC2088
  if [[ "$p" == "~/"* && -n "${HOME:-}" ]]; then
    p="${HOME}/${p#\~/}"
  fi
  # shellcheck disable=SC2310  # worktree_path_is_abs is a pure predicate; both branches are handled
  if worktree_path_is_abs "$p"; then
    printf '%s' "$p"
    return 0
  fi
  [[ -n "$base" ]] || return 0
  printf '%s/%s' "${base%/}" "$p"
}

# shellcheck disable=SC2154,SC2034  # HOOK_SHELL_C_OPERAND / HOOK_GITINV_* are hook-utils.sh result globals; WORKTREE_ADD_BASE is read by the sourcing guard
worktree_add_target_to() {
  local __wt_dest="$1" __wt_cb="$2" __wt_base="$3"
  shift 3
  local -a __wt_w=("$@")
  local __wt_n=$# __wt_i=0 __wt_d __wt_word __wt_hop __wt_j
  WORKTREE_ADD_BASE=""

  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" "$__wt_cb"
    return 1
  fi

  while ((__wt_i < __wt_n)) && [[ "${__wt_w[__wt_i]}" == *=* && "${__wt_w[__wt_i]}" != -* ]]; do ((__wt_i++)); done

  __wt_d=$__wt_i
  while ((__wt_d < __wt_n)); do
    case "${__wt_w[__wt_d]}" in
    command | builtin | eval | -p) ((__wt_d++)) ;;
    *) break ;;
    esac
  done
  case "${__wt_w[__wt_d]:-}" in
  cd | pushd | popd)
    WORKTREE_ADD_DIR_CHANGED=1
    return 1
    ;;
  *) ;;
  esac
  ((WORKTREE_ADD_DIR_CHANGED)) && return 1

  hook::git_invocation "${__wt_w[@]}" || return 1
  local __wt_gi="$HOOK_GITINV_GI"
  local -a __wt_words=("${HOOK_GITINV_WORDS[@]}")
  __wt_n=${#__wt_words[@]}

  [[ "$HOOK_GITINV_SUB" == "worktree" ]] || return 1
  local __wt_sub_idx="$HOOK_GITINV_SUB_IDX"
  [[ "${__wt_words[__wt_sub_idx + 1]:-}" == "add" ]] || return 1

  local -a __wt_hops=(${HOOK_GITINV_WRAPPER_DIRS[@]+"${HOOK_GITINV_WRAPPER_DIRS[@]}"})
  for ((__wt_j = __wt_gi + 1; __wt_j < __wt_sub_idx; __wt_j++)); do
    [[ "${__wt_words[__wt_j]}" == "-C" ]] || continue
    ((__wt_j++))
    [[ -n "${__wt_words[__wt_j]:-}" ]] || return 1
    __wt_hops+=("${__wt_words[__wt_j]}")
  done
  for __wt_hop in ${__wt_hops[@]+"${__wt_hops[@]}"}; do
    # shellcheck disable=SC2310  # worktree_path_is_dynamic is a pure predicate; the match is the verdict
    worktree_path_is_dynamic "$__wt_hop" && return 1
    __wt_base=$(worktree_path_resolve_against "$__wt_base" "$__wt_hop")
    [[ -n "$__wt_base" ]] || return 1
  done

  # `git worktree add` takes a value only after -b, -B and --reason; the walk steps over the rest:
  # https://git-scm.com/docs/git-worktree
  local __wt_target="" __wt_seen_ddash=0
  for ((__wt_j = __wt_sub_idx + 2; __wt_j < __wt_n; __wt_j++)); do
    __wt_word="${__wt_words[__wt_j]}"
    if ((__wt_seen_ddash == 0)); then
      case "$__wt_word" in
      --)
        __wt_seen_ddash=1
        continue
        ;;
      -b | -B | --reason)
        ((__wt_j++))
        continue
        ;;
      -*)
        continue
        ;;
      *) ;;
      esac
    fi
    __wt_target="$__wt_word"
    break
  done
  [[ -n "$__wt_target" ]] || return 1
  # shellcheck disable=SC2310  # worktree_path_is_dynamic is a pure predicate; the match is the verdict
  worktree_path_is_dynamic "$__wt_target" && return 1

  local __wt_abs
  __wt_abs=$(worktree_path_resolve_against "$__wt_base" "$__wt_target")
  [[ -n "$__wt_abs" ]] || return 1
  __wt_abs=$(worktree_path_normalize "$__wt_abs")
  WORKTREE_ADD_BASE="$__wt_base"
  printf -v "$__wt_dest" '%s' "$__wt_abs"
  return 0
}
