#!/usr/bin/env bash
set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ENABLED:-true}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary block-dangerous-git PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it
# shellcheck source=refuse.sh
source "$_HOOK_SELF/refuse.sh" || exit 70 # not a chosen status: the boundary reports it

start=${EPOCHREALTIME:-}

hook::buffer_stdin_to INPUT || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}

hook::require_jq_blocking "guardrails-block-dangerous-git" "block_dangerous_git_enabled"

hook::jq_fields "$INPUT" '.tool_input.command' '.cwd' '.tool_name' || exit 2

if ((HOOK_JQ_FIELDS_NUL)); then
  guard::refuse_nul
  exit 2
fi

COMMAND="${HOOK_JQ_FIELDS[0]}"
[[ -n "$COMMAND" ]] || exit 0
HOOK_REFUSE_COMMAND="$COMMAND"
HOOK_CWD="${HOOK_JQ_FIELDS[1]}"
TOOL_NAME="${HOOK_JQ_FIELDS[2]:-Bash}"

MAX_COMMAND_LEN=16384

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data subject
  hook::extract_bash_subject_to subject "$TOOL_NAME" "$COMMAND"
  hook::json_str_object_to data tool "$TOOL_NAME" subject "$subject" form "$2"
  hook::emit_telemetry "block-dangerous-git" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# Is a form token in the block_dangerous_git_allow userConfig comma list?
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
allowed() {
  local tok="$1" list=",${CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW:-},"
  [[ "$list" == *,"$tok",* ]]
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
block() {
  local form="$1"
  allowed "$form" && return 0
  emit_tel "blocked" "$form"
  hook::refuse "$2 $3; or the user adds $form to block_dangerous_git_allow."
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
block_clean_force() {
  repo_is_temp_scratch && return 0
  block "clean-force" \
    "BLOCKED: git clean with a force flag permanently deletes untracked files." \
    "Preview with git clean -n"
}

_BDG_TEAM_REL="docs/conventions/guardrails.yaml"
_unpinned_lease_state=""
_unpinned_lease_source=""
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
unpinned_lease_blocked() {
  [[ -n "$_unpinned_lease_state" ]] && return "$_unpinned_lease_state"
  _unpinned_lease_state=1
  if [[ "${CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_UNPINNED_LEASE:-allow}" == block ]]; then
    _unpinned_lease_source="block_dangerous_git_unpinned_lease"
    _unpinned_lease_state=0
    return 0
  fi
  local root text recs val key=$'\nunpinned_lease\t'
  hook::repo_root_to root "${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}" || return 1
  text=$(hook::git_untrusted -C "$root" show "refs/remotes/origin/HEAD:$_BDG_TEAM_REL" 2>/dev/null) || return 1
  if ! recs=$(LC_ALL=C awk -v STRICT=1 -f "$_HOOK_SELF/yaml-subset.awk" <<<"$text" 2>/dev/null); then
    printf 'guardrails: %s does not parse; unpinned_lease stays allow.\n' "$_BDG_TEAM_REL" >&2
    return 1
  fi
  recs=$'\n'"$recs"
  [[ "$recs" == *"$key"* ]] || return 1
  val="${recs#*"$key"}"
  val="${val%%$'\n'*}"
  if [[ "$val" == block ]]; then
    _unpinned_lease_source="$_BDG_TEAM_REL"
    _unpinned_lease_state=0
    return 0
  fi
  [[ "$val" == allow ]] ||
    printf "guardrails: %s sets unpinned_lease: '%s', not allow or block; it stays allow.\n" "$_BDG_TEAM_REL" "$val" >&2
  return 1
}

PUSH_FORCE_FIX="--force-with-lease=<ref>:<full-sha>"

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
block_push_refspec_plus() {
  block "push-force" \
    "BLOCKED: a leading + on a push refspec is a force-push." \
    "Drop the +, or use $PUSH_FORCE_FIX"
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
block_checkout_tree_wide() {
  block "checkout-dot" \
    "BLOCKED: a worktree-wide git checkout pathspec discards every unstaged change." \
    "Check out specific paths or stash first"
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
block_restore_tree_wide() {
  block "restore-dot" \
    "BLOCKED: a worktree-wide git restore pathspec discards every unstaged change." \
    "Restore specific paths or stash first"
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
abbrev_match() {
  local full="$1" word="$2" min="$3" p
  [[ "$word" == --* ]] || return 1
  p="${word#--}"
  [[ -n "$p" ]] || return 1
  ((${#p} >= min)) || return 1
  [[ "$full" == "$p"* ]]
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
is_push_value_opt() {
  local x="$1"
  [[ "$x" == *=* ]] && return 1
  abbrev_match "push-option" "$x" 2 || abbrev_match "repo" "$x" 3 ||
    abbrev_match "receive-pack" "$x" 4 || abbrev_match "exec" "$x" 1
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
is_lease_opt() { abbrev_match "force-with-lease" "${1%%=*}" 7; }

_repo_oid_width=""
_repo_oid_width_key=""
_repo_oid_width_err=""
_lease_oid_width_unknown=0
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
repo_oid_width() {
  local key="$*" out
  [[ -n "$_repo_oid_width" && "$key" == "$_repo_oid_width_key" ]] && return 0
  _repo_oid_width_key="$key"
  _repo_oid_width=""
  _repo_oid_width_err=""
  out="$(
    exec 2>&1
    hook::git_untrusted "$@" rev-parse --show-object-format
  )" || true
  case "$out" in
  sha1) _repo_oid_width=40 ;;
  sha256) _repo_oid_width=64 ;;
  *)
    _repo_oid_width_err="${out:-could not read repository object format}"
    _repo_oid_width_key=""
    ;;
  esac
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
temp_root_persists() {
  local p="${1%/}/" t
  case "$p" in
  /var/tmp/* | /private/var/tmp/*) ;;
  *) return 1 ;;
  esac
  for t in "${TMPDIR:-}" "${TMP:-}" "${TEMP:-}"; do
    [[ -n "$t" && "$p" == "${t%/}"/* ]] && return 1
  done
  return 0
}
_temp_scratch_key=""
_temp_scratch=1
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
repo_is_temp_scratch() {
  local j key out top common unsafe=$'[][;&|\n\r$\\\\\'"`(){}<>*?#]'
  [[ "$TOOL_NAME" == "Bash" && -n "${HOME:-}" ]] || return 1
  [[ "$COMMAND" =~ $unsafe ]] && return 1
  ((gi == 0 && HOOK_ALIAS_DEPTH == 0)) || return 1
  for ((j = gi + 1; j < sub_idx; j++)); do
    case "${w[j]}" in
    -c* | --config*) return 1 ;;
    *) ;;
    esac
  done
  key="${git_locating_opts[*]}"
  [[ "$key" == "$_temp_scratch_key" ]] && return "$_temp_scratch"
  _temp_scratch_key="$key"
  _temp_scratch=1
  { out="$(hook::git_untrusted "${git_locating_opts[@]}" rev-parse --path-format=absolute \
    --show-toplevel --git-common-dir)"; } 2>/dev/null || return 1
  out="${out//$'\r'/}"
  top="${out%%$'\n'*}"
  common="${out#*$'\n'}"
  [[ -n "$top" && -n "$common" && "$common" != "$out" && "$common" != *$'\n'* ]] || return 1
  hook::under_temp_root "$top" && hook::under_temp_root "$common" || return 1
  temp_root_persists "$top" || temp_root_persists "$common" && return 1
  hook::under_temp_root "$HOME" && return 1
  _temp_scratch=0
}

# Reads $git_locating_opts from the calling check_segment frame.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
lease_expect_is_immutable() {
  local expect="$1"
  [[ -z "$expect" ]] && return 0
  [[ "$expect" =~ ^[0-9a-fA-F]+$ ]] || return 1
  repo_oid_width ${git_locating_opts[@]+"${git_locating_opts[@]}"}
  if [[ -z "$_repo_oid_width" ]]; then
    _lease_oid_width_unknown=1
    return 1
  fi
  ((${#expect} == _repo_oid_width))
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
collect_git_locating_opts() {
  local gi="$1" sub_idx="$2"
  shift 2
  local -a w=("$@")
  local j=$((gi + 1)) wdir
  git_locating_opts=(-C "${HOOK_EFFECTIVE_BASE:-${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}}")
  for wdir in ${HOOK_GITINV_WRAPPER_DIRS[@]+"${HOOK_GITINV_WRAPPER_DIRS[@]}"}; do
    git_locating_opts+=(-C "$wdir")
  done
  while ((j < sub_idx)); do
    case "${w[j]}" in
    -C | --git-dir | --work-tree | --namespace)
      ((j + 1 < sub_idx)) && git_locating_opts+=("${w[j]}" "${w[j + 1]}")
      ((j += 2))
      ;;
    --git-dir=* | --work-tree=* | --namespace=*)
      git_locating_opts+=("${w[j]}")
      ((j++))
      ;;
    -c | --config | --config-env | --super-prefix | --attr-source | --exec-path)
      ((j += 2))
      ;;
    *) ((j++)) ;;
    esac
  done
  if ((${#HOOK_GIT_INHERITED_LOCATING_OPTS[@]})); then
    git_locating_opts+=("${HOOK_GIT_INHERITED_LOCATING_OPTS[@]}")
  fi
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
git_inherited_locating_opts_from_words() {
  local gi="$1" sub_idx="$2"
  shift 2
  local -a w=("$@")
  local j=$((gi + 1))
  HOOK_GIT_INHERITED_LOCATING_OPTS=()
  while ((j < sub_idx)); do
    case "${w[j]}" in
    --git-dir | --work-tree | --namespace)
      ((j + 1 < sub_idx)) && HOOK_GIT_INHERITED_LOCATING_OPTS+=("${w[j]}" "${w[j + 1]}")
      ((j += 2))
      ;;
    --git-dir=* | --work-tree=* | --namespace=*)
      HOOK_GIT_INHERITED_LOCATING_OPTS+=("${w[j]}")
      ((j++))
      ;;
    -C | -c | --config | --config-env | --super-prefix | --attr-source | --exec-path)
      ((j += 2))
      ;;
    *) ((j++)) ;;
    esac
  done
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
lease_refs_equivalent() {
  local left_ref="$1" right_ref="$2"
  [[ "$left_ref" == "$right_ref" ]] && return 0
  [[ "$left_ref" == refs/heads/* && "${left_ref#refs/heads/}" == "$right_ref" ]] && return 0
  [[ "$right_ref" == refs/heads/* && "${right_ref#refs/heads/}" == "$left_ref" ]] && return 0
  return 1
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
lease_ref_claimed() {
  local seen="$1" ref="$2" r
  while IFS= read -r r; do
    [[ -z "$r" ]] && continue
    lease_refs_equivalent "$r" "$ref" && return 0
  done <<<"$seen"
  return 1
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
is_tree_wide_pathspec() {
  local magic pattern
  case "$1" in
  "." | ":/") return 0 ;;
  ":("*")"*)
    magic="${1#:(}"
    pattern="${magic#*)}"
    magic="${magic%%)*}"
    [[ ",${magic}," == *",exclude,"* ]] && return 1
    [[ -z "$pattern" || "$pattern" =~ ^[./*?]+$ ]]
    ;;
  ":/"*)
    [[ "${1#:/}" =~ ^[./*?]+$ ]]
    ;;
  ":!"* | ":^"*) return 1 ;;
  ":"*)
    [[ "${1#:}" =~ ^:?[./*?]*$ ]]
    ;;
  *)
    [[ "$1" =~ ^[./*?]+$ ]]
    ;;
  esac
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
is_exclude_pathspec() {
  local magic
  case "$1" in
  ":!"* | ":^"*) return 0 ;;
  ":("*")"*)
    magic="${1#:(}"
    magic="${magic%%)*}"
    [[ ",${magic}," == *",exclude,"* ]]
    ;;
  *) return 1 ;;
  esac
}

HOOK_ALIAS_WORK_MAX=128

guard::alias_depth_max

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
alias_reexpand_admit() {
  hook::git_alias_admit "$@"
  local rc=$?
  ((rc == 2)) || return "$rc"
  guard::refuse_alias_chain
  emit_tel "blocked" "alias-traversal-cap"
  exit 2
}

# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
check_segment() {
  local -a w=()
  local nseg gi k x rest ch sub sub_idx staged worktree dry forced excl pos opseen
  local if_includes lease_tracking lease_movable lease_width_unknown lease_empty lease_seen lease_ref lease_expect
  local -a git_locating_opts=()

  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" check_segment
    return 0
  fi

  hook::git_invocation "$@" || return 0
  gi=$HOOK_GITINV_GI
  w=("${HOOK_GITINV_WORDS[@]}")
  nseg=${#w[@]}
  sub=$HOOK_GITINV_SUB
  sub_idx=$HOOK_GITINV_SUB_IDX
  collect_git_locating_opts "$gi" "$sub_idx" "${w[@]}"

  local exp reparse s seen_hit=0 saved_base="" saved_inherited=() composed_base
  local -a expw=() saved_seen=() nextw=()
  if [[ "$HOOK_GITINV_ALIAS_TERM" == "config-env" ]]; then
    guard::refuse_config_env_alias "$sub"
    emit_tel "blocked" "config-env-alias"
    exit 2
  fi
  for s in ${HOOK_ALIAS_SEEN[@]+"${HOOK_ALIAS_SEEN[@]}"}; do
    [[ "$s" == "$sub" ]] && {
      seen_hit=1
      break
    }
  done
  if [[ "$HOOK_GITINV_ALIAS_TERM" == "inline" ]] && ((seen_hit == 0)); then
    saved_seen=(${HOOK_ALIAS_SEEN[@]+"${HOOK_ALIAS_SEEN[@]}"})
    saved_base="${HOOK_EFFECTIVE_BASE-}"
    if ((HOOK_ALIAS_DEPTH >= HOOK_ALIAS_DEPTH_MAX)); then
      guard::refuse_alias_chain
      emit_tel "blocked" "alias-depth-cap"
      exit 2
    fi
    ((++HOOK_ALIAS_DEPTH))
    HOOK_ALIAS_SEEN+=("$sub")
    for exp in ${HOOK_GITINV_ALIAS_EXPS[@]+"${HOOK_GITINV_ALIAS_EXPS[@]}"}; do
      [[ -n "$exp" ]] || continue
      if [[ "$exp" == '!'* ]]; then
        hook::git_alias_reparse_to reparse "$exp" "${w[@]:sub_idx+1}"
        HOOK_ALIAS_SEEN=()
        saved_inherited=(${HOOK_GIT_INHERITED_LOCATING_OPTS[@]+"${HOOK_GIT_INHERITED_LOCATING_OPTS[@]}"})
        git_inherited_locating_opts_from_words "$gi" "$sub_idx" "${w[@]}"
        hook::git_effective_dir_to composed_base ${git_locating_opts[@]+"${git_locating_opts[@]:2}"}
        HOOK_EFFECTIVE_BASE="$composed_base"
        alias_reexpand_admit shell "$reparse" &&
          hook::bash_parse_segments "$reparse" check_segment
        HOOK_EFFECTIVE_BASE="$saved_base"
        HOOK_GIT_INHERITED_LOCATING_OPTS=(${saved_inherited[@]+"${saved_inherited[@]}"})
        HOOK_ALIAS_SEEN=(${saved_seen[@]+"${saved_seen[@]}"} "$sub")
      else
        hook::env_s_split "$exp"
        expw=(${HOOK_ENV_S_WORDS[@]+"${HOOK_ENV_S_WORDS[@]}"})
        nextw=("${w[@]:0:sub_idx}" ${expw[@]+"${expw[@]}"} "${w[@]:sub_idx+1}")
        alias_reexpand_admit git "${nextw[@]}" && check_segment "${nextw[@]}"
      fi
    done
    ((--HOOK_ALIAS_DEPTH))
    HOOK_ALIAS_SEEN=(${saved_seen[@]+"${saved_seen[@]}"})
    HOOK_EFFECTIVE_BASE="$saved_base"
  fi

  case "$sub" in
  push)
    dry=0
    if_includes=0
    lease_tracking=0
    lease_movable=0
    lease_width_unknown=0
    lease_empty=0
    _lease_oid_width_unknown=0
    lease_seen=""
    k=$((sub_idx + 1))
    while ((k < nseg)); do
      x="${w[k]}"
      case "$x" in
      --) break ;;
      -o | --push-option | --repo | --receive-pack | --exec)
        ((k += 2))
        continue
        ;;
      -o?* | --push-option=* | --repo=* | --receive-pack=* | --exec=*) ;;
      --no-*)
        abbrev_match "dry-run" "--${x#--no-}" 2 && dry=0
        abbrev_match "force-if-includes" "--${x#--no-}" 7 && if_includes=0
        if abbrev_match "force-with-lease" "--${x#--no-}" 7; then
          lease_tracking=0
          lease_movable=0
          lease_width_unknown=0
          lease_empty=0
          _lease_oid_width_unknown=0
          lease_seen=""
        fi
        ((k++))
        continue
        ;;
      --*)
        if is_push_value_opt "$x"; then
          ((k += 2))
          continue
        fi
        ;;&
      *)
        if [[ "$x" == "-n" ]] || abbrev_match "dry-run" "$x" 2 ||
          [[ "$x" =~ ^-[A-Za-z]+$ && "$x" == *n* ]]; then
          dry=1
        fi
        abbrev_match "force-if-includes" "${x%%=*}" 7 && if_includes=1
        if is_lease_opt "$x"; then
          if [[ "$x" != *=* ]]; then
            lease_tracking=1
          else
            lease_ref="${x#*=}"
            lease_ref="${lease_ref%%:*}"
            if ! lease_ref_claimed "$lease_seen" "$lease_ref"; then
              lease_seen="$lease_seen$lease_ref"$'\n'
              if [[ "$x" != *=*:* ]]; then
                lease_tracking=1
              else
                lease_expect="${x#*=}"
                lease_expect="${lease_expect#*:}"
                [[ -z "$lease_expect" ]] && lease_empty=1
                if ! lease_expect_is_immutable "$lease_expect"; then
                  if ((_lease_oid_width_unknown)); then
                    lease_width_unknown=1
                  else
                    lease_movable=1
                  fi
                fi
              fi
            fi
          fi
        fi
        ;;
      esac
      ((k++))
    done
    ((dry)) && return 0
    if ((lease_width_unknown)); then
      block "push-lease-unsafe" \
        "BLOCKED: --force-with-lease=<ref>:<sha> needs the repo's hash format, which could not be read (${_repo_oid_width_err:-git rev-parse --show-object-format failed})." \
        "Name the repository with -C: git -C <repo> push --force-with-lease=<ref>:<full-sha>"
    fi
    if ((lease_movable)); then
      block "push-lease-unsafe" \
        "BLOCKED: --force-with-lease=<ref>:<expect> with a name (branch, tag, HEAD, short or wrong-width sha) leases against a moving target." \
        "Resolve it first (git rev-parse <ref>) and pass =<ref>:<full-sha> literally; a substitution is not evaluated here"
    fi
    if ((lease_tracking)) && ((!if_includes)); then
      block "push-lease-unsafe" \
        "BLOCKED: --force-with-lease without an expected value can still clobber work a background fetch pulled in." \
        "Use $PUSH_FORCE_FIX, resolving <full-sha> in a separate step"
    fi
    if ((lease_tracking || lease_empty)) && unpinned_lease_blocked; then
      block "push-lease-unsafe" \
        "BLOCKED: $_unpinned_lease_source allows only a lease pinned to a full commit id; this --force-with-lease pins none." \
        "Use --force-with-lease=<ref>:<full-sha>, resolving <full-sha> in a separate step"
    fi
    k=$((sub_idx + 1))
    while ((k < nseg)); do
      x="${w[k]}"
      case "$x" in
      --)
        for ((k++; k < nseg; k++)); do
          [[ "${w[k]}" == +* ]] && block_push_refspec_plus
        done
        break
        ;;
      -o | --push-option | --repo | --receive-pack | --exec)
        ((k += 2))
        continue
        ;;
      -o?* | --push-option=* | --repo=* | --receive-pack=* | --exec=*)
        ((k++))
        continue
        ;;
      --*)
        if is_push_value_opt "$x"; then
          ((k += 2))
          continue
        fi
        ;;&
      --force)
        block "push-force" \
          "BLOCKED: git push --force overwrites remote commits." \
          "Use $PUSH_FORCE_FIX"
        ;;
      --force-*) ;;
      +*)
        block_push_refspec_plus
        ;;
      -[A-Za-z]*)
        if [[ "$x" =~ ^-[A-Za-z]+$ && "$x" == *f* ]]; then
          block "push-force" \
            "BLOCKED: git push -f overwrites remote commits." \
            "Use $PUSH_FORCE_FIX"
        fi
        ;;
      *)
        if abbrev_match "mirror" "$x" 1; then
          block "push-force" \
            "BLOCKED: git push --mirror force-updates every remote ref." \
            "Push specific refs instead"
        fi
        ;;
      esac
      ((k++))
    done
    ;;
  reset)
    for ((k = sub_idx + 1; k < nseg; k++)); do
      x="${w[k]}"
      [[ "$x" == "--" ]] && break
      if [[ "$x" != *=* ]] && abbrev_match "pathspec-from-file" "$x" 11; then
        ((k++))
        continue
      fi
      abbrev_match "hard" "$x" 1 && ! repo_is_temp_scratch && block "reset-hard" \
        "BLOCKED: git reset --hard discards uncommitted work." \
        "Commit or stash first (git stash push -u), or use git reset --keep"
    done
    ;;
  clean)
    dry=0
    forced=0
    for ((k = sub_idx + 1; k < nseg; k++)); do
      x="${w[k]}"
      [[ "$x" == "--" ]] && break
      case "$x" in
      -e)
        ((k++))
        continue
        ;;
      -e?*) continue ;;
      --no-*)
        abbrev_match "dry-run" "--${x#--no-}" 1 && dry=0
        continue
        ;;
      *) ;;
      esac
      if [[ "$x" == --*=* ]] && abbrev_match "exclude" "${x%%=*}" 1; then
        continue
      fi
      if [[ "$x" != *=* ]] && abbrev_match "exclude" "$x" 1; then
        ((k++))
        continue
      fi
      if [[ "$x" =~ ^-[A-Za-z]*e[A-Za-z]*$ ]]; then
        rest="${x%%e*}"
        [[ "$x" == *e ]] && ((k++))
        [[ "$rest" == *n* ]] && dry=1
        [[ "$rest" == *f* ]] && ((++forced))
        continue
      fi
      if [[ "$x" == "-n" ]] || abbrev_match "dry-run" "$x" 1 ||
        [[ "$x" =~ ^-[A-Za-z]+$ && "$x" == *n* ]]; then
        dry=1
      fi
      if abbrev_match "force" "$x" 1 || [[ "$x" =~ ^-[A-Za-z]+$ && "$x" == *f* ]]; then
        ((++forced))
      fi
    done
    ((dry)) && return 0
    for (( ; forced > 0; forced--)); do
      block_clean_force
    done
    ;;
  checkout)
    excl=0
    pos=0
    opseen=0
    k=$((sub_idx + 1))
    while ((k < nseg)); do
      x="${w[k]}"
      case "$x" in
      --)
        for ((k++; k < nseg; k++)); do
          is_tree_wide_pathspec "${w[k]}" && block_checkout_tree_wide
          if is_exclude_pathspec "${w[k]}"; then ((excl++)); else ((pos++)); fi
        done
        break
        ;;
      --pathspec-*)
        rest="${x%%=*}"
        if abbrev_match "pathspec-from-file" "$rest" 11; then
          block "checkout-dot" \
            "BLOCKED: git checkout --pathspec-from-file can address the whole worktree, and the file cannot be checked." \
            "Pass explicit paths instead"
          if [[ "$x" == *=* ]]; then ((k++)); else ((k += 2)); fi
        else
          ((k++))
        fi
        continue
        ;;
      -b | -B | --orphan | --conflict)
        ((k += 2))
        continue
        ;;
      -b?* | -B?*)
        ((k++))
        continue
        ;;
      *)
        if [[ "$x" != *=* ]] &&
          { abbrev_match "conflict" "$x" 1 || abbrev_match "orphan" "$x" 2; }; then
          ((k += 2))
          continue
        fi
        if [[ "$x" == "-f" ]] || abbrev_match "force" "$x" 1 ||
          [[ "$x" =~ ^-[A-Za-z]+$ && "$x" == *f* ]]; then
          block "checkout-force" \
            "BLOCKED: git checkout -f/--force throws away local modifications." \
            "Commit or stash first"
        fi
        is_tree_wide_pathspec "$x" && block_checkout_tree_wide
        if [[ "$x" != -* ]]; then
          if is_exclude_pathspec "$x"; then
            ((excl++))
            opseen=1
          elif ((opseen)) || [[ "$x" == :* ]]; then
            ((pos++))
            opseen=1
          else
            opseen=1
          fi
        fi
        ;;
      esac
      ((k++))
    done
    ((excl > 0 && pos == 0)) && block "checkout-dot" \
      "BLOCKED: an exclude-only git checkout pathspec restores everything outside the excluded set." \
      "Add positive paths to scope the checkout"
    ;;
  switch)
    k=$((sub_idx + 1))
    while ((k < nseg)); do
      x="${w[k]}"
      case "$x" in
      --) break ;;
      -c | -C | --orphan | --conflict)
        ((k += 2))
        continue
        ;;
      -c?* | -C?*)
        ((k++))
        continue
        ;;
      *)
        if [[ "$x" == "-f" ]] || abbrev_match "force" "$x" 1 ||
          abbrev_match "discard-changes" "$x" 2 ||
          [[ "$x" =~ ^-[A-Za-z]+$ && "$x" == *f* ]]; then
          block "checkout-force" \
            "BLOCKED: git switch -f/--discard-changes throws away local modifications." \
            "Commit or stash first"
        fi
        ;;
      esac
      ((k++))
    done
    ;;
  restore)
    staged=0
    worktree=0
    for ((k = sub_idx + 1; k < nseg; k++)); do
      x="${w[k]}"
      [[ "$x" == "--" ]] && break
      case "$x" in
      --no-*)
        rest="--${x#--no-}"
        abbrev_match "staged" "$rest" 2 && staged=0
        abbrev_match "worktree" "$rest" 1 && worktree=0
        ;;
      --s* | --w*)
        abbrev_match "staged" "$x" 2 && staged=1
        abbrev_match "worktree" "$x" 1 && worktree=1
        ;;
      -[A-Za-z]*)
        if [[ "$x" =~ ^-[A-Za-z]+$ ]]; then
          rest="${x#-}"
          for ((ch = 0; ch < ${#rest}; ch++)); do
            case "${rest:ch:1}" in
            S) staged=1 ;;
            W) worktree=1 ;;
            *) ;;
            esac
          done
        fi
        ;;
      *) ;;
      esac
    done
    if ((staged == 0 || worktree == 1)); then
      excl=0
      pos=0
      k=$((sub_idx + 1))
      while ((k < nseg)); do
        x="${w[k]}"
        case "$x" in
        --)
          for ((k++; k < nseg; k++)); do
            is_tree_wide_pathspec "${w[k]}" && block_restore_tree_wide
            if is_exclude_pathspec "${w[k]}"; then ((excl++)); else ((pos++)); fi
          done
          break
          ;;
        --pathspec-*)
          rest="${x%%=*}"
          if abbrev_match "pathspec-from-file" "$rest" 11; then
            block "restore-dot" \
              "BLOCKED: git restore --pathspec-from-file can address the whole worktree, and the file cannot be checked." \
              "Pass explicit paths instead"
            if [[ "$x" == *=* ]]; then ((k++)); else ((k += 2)); fi
          else
            ((k++))
          fi
          continue
          ;;
        -s | --source | --conflict)
          ((k += 2))
          continue
          ;;
        *)
          if [[ "$x" != *=* ]] &&
            { abbrev_match "source" "$x" 2 || abbrev_match "conflict" "$x" 1; }; then
            ((k += 2))
            continue
          fi
          is_tree_wide_pathspec "$x" && block_restore_tree_wide
          if [[ "$x" != -* ]]; then
            if is_exclude_pathspec "$x"; then ((excl++)); else ((pos++)); fi
          fi
          ;;
        esac
        ((k++))
      done
      ((excl > 0 && pos == 0)) && block "restore-dot" \
        "BLOCKED: an exclude-only git restore pathspec discards everything outside the excluded set." \
        "Add positive paths to scope the restore"
    fi
    ;;
  *) ;;
  esac

  return 0
}

if ((${#COMMAND} > MAX_COMMAND_LEN)); then
  echo "BLOCKED: command over $MAX_COMMAND_LEN chars is too long to check. Split it into shorter commands." >&2
  emit_tel "blocked" "too-long"
  exit 2
fi

if [[ "$TOOL_NAME" == "PowerShell" ]]; then
  # shellcheck source=guard-requires.sh
  declare -F guard::require_libs >/dev/null || source "$_HOOK_SELF/guard-requires.sh"
  guard::require_libs
  ps::classify_git_command "$TOOL_NAME" "$COMMAND" "interrogation-ok"
  _ps_rc=$?
  _ps_sink_attempts=0
  while ((_ps_rc == 2)); do
    if ((PS_REDUCTION_UNTRUSTED)); then
      PS_SINK_TRIGGER="${PS_REDUCTION_UNTRUSTED_REASON:-herestring-comment-char}"
      ps::print_unparsable_git_block_message
      emit_tel "blocked" "powershell-unparsable-${PS_SINK_TRIGGER}"
      exit 2
    fi
    if ((_ps_sink_attempts > 4)); then
      ps::print_sink_budget_message
      emit_tel "blocked" "powershell-unparsable-budget-exhausted"
      exit 2
    fi
    sink_allow="ps-unparsable-${PS_SINK_TRIGGER:-unknown}"
    if ! allowed "$sink_allow"; then
      ps::print_unparsable_git_block_message
      emit_tel "blocked" "powershell-unparsable-${PS_SINK_TRIGGER:-unknown}"
      exit 2
    fi
    ps::blank_sink_opaque_regions "$COMMAND" "${PS_SINK_TRIGGER:-unknown}"
    COMMAND="$PS_SAFE_COMMAND"
    if [[ -z "${COMMAND//[[:space:]]/}" ]]; then
      emit_tel "ok" ""
      exit 0
    fi
    _ps_sink_attempts=$((_ps_sink_attempts + 1))
    ps::classify_git_command "$TOOL_NAME" "$COMMAND" "interrogation-ok"
    _ps_rc=$?
  done
  case $_ps_rc in
  1) exit 0 ;; # non-git PowerShell with an A2b-deferred construct
  *) COMMAND="$PS_SAFE_COMMAND" ;;
  esac
fi

HOOK_ALIAS_SEEN=()
HOOK_ALIAS_DEPTH=0

HOOK_EFFECTIVE_BASE="${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}"
HOOK_GIT_INHERITED_LOCATING_OPTS=()

hook::bash_parse_segments "$COMMAND" check_segment

hook::refuse_flush
emit_tel "ok" ""
exit 0
