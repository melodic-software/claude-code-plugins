# shellcheck shell=bash
# worktree-path-lib.sh: the lexical path helpers, and the `git worktree add`
# target resolver, shared by this plugin's worktree surfaces. Sourced, never
# executed, and never sourced across a plugin boundary.
#
# Consumers:
#   - hooks/worktree-add-containment-gate.sh  (PreToolUse: blocks a nested target)
#   - hooks/worktree-add-claim-gate.sh        (PostToolUse: claims the add target)
#   - scripts/worktree-claim.sh               (normalizer only)
#   - scripts/worktree-create.sh              (normalizer only)
#
# Everything here is PURE STRING WORK: no filesystem probe, no git call, no
# process. That is what lets a target be judged before `git worktree add`
# creates the components it names. Each consumer keeps its own verdict (block
# message, exit code, claim call) and its own `Exit:` taxonomy; only the parse
# and the path arithmetic are shared.
#
# worktree_add_target_to calls hook::shell_c_operand, hook::bash_parse_segments
# and hook::git_invocation, so a consumer that calls it must have sourced
# hook-utils.sh first. The normalizer and the two predicates stand alone, which
# is what the two scripts source this file for: neither pays for the library.

# Set once a segment changes the working directory; every later segment then
# resolves against a directory a static parse cannot see (the same rule and the
# same rationale as pr-body-linkage-gate: only the CURRENT shell's own
# relocation counts).
WORKTREE_ADD_DIR_CHANGED=0

# The effective directory the parsed git process would run in: the payload cwd
# composed with each wrapper chdir and each git global `-C`. Written by
# worktree_add_target_to on a successful resolution, read by a caller that needs
# a repository hint for its own message.
# shellcheck disable=SC2034  # consumed by the sourcing guard, not by this file
WORKTREE_ADD_BASE=""

# A value the tokenizer could not fully resolve, an unexpanded expansion or a
# command substitution, is not a guard's to judge on its face.
worktree_path_is_dynamic() {
  [[ "$1" == *'$'* || "$1" == *'`'* ]]
}

# True for an absolute path in either grammar these guards meet: POSIX `/...`
# or drive-letter `C:/...` / `C:\...`.
worktree_path_is_abs() {
  [[ "$1" == /* || "$1" =~ ^[A-Za-z]:[/\\] ]]
}

# worktree_path_normalize <path> lexically collapses `.`, `..` and `//`,
# echoing the result. Pure string work: it does NOT touch the filesystem, so it
# resolves `..` even when leading components do not exist yet, the case
# `git worktree add` handles by creating the missing dirs and letting the OS
# resolve `..`. `realpath -m` would do this too but is a GNU extension absent
# on BSD/macOS (the repo's realpath/readlink -f idiom needs every-but-last
# component to exist, so it cannot resolve a nonexistent-prefix `..`). A path
# with no `.`/`..`/`//` segment re-splits and re-joins identically, so this is a
# no-op for ordinary roots. A relative input keeps an empty root and can
# therefore collapse to the empty string; a caller that wants `.` for that case
# supplies it. Symlink resolution of existing components is left to the caller:
# git's own realpath at creation, `pwd -P` in the claim helper.
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
      # Pop the last kept segment; a `..` at the root is a no-op (clamped).
      ((${#out[@]})) && out=("${out[@]:0:${#out[@]}-1}")
      continue
    fi
    out+=("$seg")
  done
  local IFS='/'
  printf '%s%s' "$root" "${out[*]}"
}

# worktree_path_resolve_against <base> <path> absolutizes <path> against
# <base>, echoing the result; echoes nothing when neither is absolute.
# Backslashes are folded to forward slashes on Windows shells only, mirroring
# the creation helper's canonicalize (off-Windows `\` is a legal filename byte).
worktree_path_resolve_against() {
  local base="$1" p="$2"
  if [[ ("$p" == *\\* || "$base" == *\\*) && ("${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin*) ]]; then
    local bslash="\\" fwd="/"
    p="${p//"$bslash"/"$fwd"}"
    base="${base//"$bslash"/"$fwd"}"
  fi
  # A leading unquoted `~` would have been expanded by the shell before git ever
  # saw it; reproduce the common case, and let an unresolvable one fall out as
  # relative-with-no-base (allow). SC2088: matching the literal unexpanded tilde
  # is the point.
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

# worktree_add_target_to <dest> <segment-callback> <payload-cwd> <argv…>
#
# ONE tokenized segment, as hook::bash_parse_segments hands it to a callback.
# Returns 0 and writes the lexically resolved absolute `git worktree add`
# target into <dest>, having set WORKTREE_ADD_BASE to the directory the git
# process would run in; returns 1 when the segment names no statically
# resolvable add target.
#
# A `sh -c` operand is re-parsed through <segment-callback> with the same
# tokenizer, then 1 is returned: whatever the operand names is judged by the
# callback's own re-entry, never by this frame.
#
# Every fail-open condition the two gates share lives here, and each returns 1:
# a value carrying an unexpanded `$`/backtick, a segment after a
# `cd`/`pushd`/`popd` (the effective directory is a runtime fact), a missing
# base for a relative path, a segment that is not `git worktree add`, and a
# command the tokenizer cannot reduce to a positional target.
#
# shellcheck disable=SC2154,SC2034  # HOOK_SHELL_C_OPERAND / HOOK_GITINV_* are hook-utils.sh result globals; WORKTREE_ADD_BASE is read by the sourcing guard
worktree_add_target_to() {
  local __wt_dest="$1" __wt_cb="$2" __wt_base="$3"
  shift 3
  # Every local is `__wt_`-prefixed so a caller dest named `abs`, `base`,
  # `target` or any other ordinary name cannot collide with this function's own
  # variables (the `_to` helper convention in lib/hook-utils.sh). An unprefixed
  # local would make `printf -v` write into THIS frame and return 0 while the
  # caller kept stale data.
  local -a __wt_w=("$@")
  local __wt_n=$# __wt_i=0 __wt_d __wt_word __wt_hop __wt_j
  WORKTREE_ADD_BASE=""

  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" "$__wt_cb"
    return 1
  fi

  # Leading `VAR=val` assignments are not the command word.
  while ((__wt_i < __wt_n)) && [[ "${__wt_w[__wt_i]}" == *=* && "${__wt_w[__wt_i]}" != -* ]]; do ((__wt_i++)); done

  # Only the CURRENT shell can relocate later segments; `command`/`builtin`/
  # `eval` dispatch the cd builtin inside this shell, `sudo cd`/`env cd` are
  # separate processes that fail on a builtin and move nothing (they fall
  # through to the resolver, where `cd` is simply not `git`).
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

  # One parsed invocation: the argv `env -S` splicing may have rewritten, git's
  # index, the wrapper chdirs the [git, subcommand) walk below cannot see, and
  # the subcommand with its index.
  hook::git_invocation "${__wt_w[@]}" || return 1
  local __wt_gi="$HOOK_GITINV_GI"
  local -a __wt_words=("${HOOK_GITINV_WORDS[@]}")
  local -a __wt_wrapper_dirs=(${HOOK_GITINV_WRAPPER_DIRS[@]+"${HOOK_GITINV_WRAPPER_DIRS[@]}"})
  __wt_n=${#__wt_words[@]}

  [[ "$HOOK_GITINV_SUB" == "worktree" ]] || return 1
  local __wt_sub_idx="$HOOK_GITINV_SUB_IDX"
  [[ "${__wt_words[__wt_sub_idx + 1]:-}" == "add" ]] || return 1

  # The effective directory the git process runs in: the payload cwd, composed
  # with each wrapper chdir in execution order, then each git global -C in
  # order (git applies multiple -C values cumulatively). Any dynamic hop makes
  # the base unknowable, so the segment is left alone.
  for __wt_hop in ${__wt_wrapper_dirs[@]+"${__wt_wrapper_dirs[@]}"}; do
    # shellcheck disable=SC2310  # worktree_path_is_dynamic is a pure predicate; the match is the verdict
    worktree_path_is_dynamic "$__wt_hop" && return 1
    __wt_base=$(worktree_path_resolve_against "$__wt_base" "$__wt_hop")
    [[ -n "$__wt_base" ]] || return 1
  done
  __wt_j=$((__wt_gi + 1))
  while ((__wt_j < __wt_sub_idx)); do
    if [[ "${__wt_words[__wt_j]}" == "-C" ]]; then
      __wt_hop="${__wt_words[__wt_j + 1]:-}"
      [[ -n "$__wt_hop" ]] || return 1
      # shellcheck disable=SC2310  # worktree_path_is_dynamic is a pure predicate; the match is the verdict
      worktree_path_is_dynamic "$__wt_hop" && return 1
      __wt_base=$(worktree_path_resolve_against "$__wt_base" "$__wt_hop")
      [[ -n "$__wt_base" ]] || return 1
      ((__wt_j += 2))
      continue
    fi
    ((__wt_j++))
  done

  # Walk the `add` arguments for the target path: the first positional word.
  # Value-taking options for `git worktree add` are exactly -b, -B, and
  # --reason (their attached forms are single words); every other option is a
  # boolean the walk steps over, and `--` ends option parsing.
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
