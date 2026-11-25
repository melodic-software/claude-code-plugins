# shellcheck shell=bash

[[ -n "${_GUARDRAILS_ABORT_BOUNDARY_LOADED:-}" ]] && return 0
readonly _GUARDRAILS_ABORT_BOUNDARY_LOADED=1

_GAB_NAME=""
_GAB_EVENT=""
_GAB_POSTURE="open"
_GAB_CHOSEN=" "

_GUARD_SAID=" "
guard::say_once() {
  [[ "$_GUARD_SAID" == *" $1 "* ]] && return 0
  _GUARD_SAID+="$1 "
  printf '%s\n' "$2" >&2
}

guard::refuse_nul() {
  guard::say_once nul "BLOCKED: the payload carries a NUL byte. Reissue the call without it."
}
guard::refuse_unparsable() {
  guard::say_once unparsable "BLOCKED: the hook payload could not be parsed."
}

# shellcheck disable=SC2154  # HOOK_JQ_FIELDS_NUL is hook::jq_fields', loaded by every caller
guard::payload_verdict() {
  if (($1 == 2)); then
    guard::refuse_unparsable
    return 2
  fi
  (($1 == 0)) || return 3
  if ((HOOK_JQ_FIELDS_NUL)); then
    guard::refuse_nul
    return 2
  fi
  return 0
}
# The git guards that walk alias chains (hook::git_alias_admit).
# shellcheck disable=SC2154  # HOOK_ALIAS_WORK_MAX is hook-utils.sh's, loaded by every caller
guard::refuse_alias_chain() {
  guard::say_once alias-chain "BLOCKED: checking this git alias chain needs over $HOOK_ALIAS_WORK_MAX re-expansions. Run the subcommand directly."
}
guard::alias_depth_max() {
  local file line cap
  HOOK_ALIAS_DEPTH_MAX=
  for file in /proc/self/limits ${GUARDRAILS_PROC_LIMITS:+"$GUARDRAILS_PROC_LIMITS"}; do
    cap=25
    if [[ -r "$file" ]]; then
      while IFS= read -r line; do
        if [[ "$line" =~ ^Max\ stack\ size[[:space:]]+([0-9]+)[[:space:]] ]]; then
          cap=$((10#${BASH_REMATCH[1]} / 1024 / 20))
          break
        fi
      done <"$file"
    fi
    ((cap <= 409)) || cap=409
    [[ -n "$HOOK_ALIAS_DEPTH_MAX" ]] && ((cap >= HOOK_ALIAS_DEPTH_MAX)) || HOOK_ALIAS_DEPTH_MAX=$cap
  done
  if [[ "${GUARDRAILS_ALIAS_DEPTH_MAX-}" =~ ^[0-9]+$ ]] && ((10#$GUARDRAILS_ALIAS_DEPTH_MAX < HOOK_ALIAS_DEPTH_MAX)); then
    HOOK_ALIAS_DEPTH_MAX=$((10#$GUARDRAILS_ALIAS_DEPTH_MAX))
  fi
}
guard::refuse_config_env_alias() { # <alias>
  guard::say_once "config-env-$1" "BLOCKED: git alias '$1' is defined via --config-env, so its expansion cannot be checked. Define it in git config or run the subcommand directly."
}

# shellcheck disable=SC2154  # HOOK_NOTICE_TO_USER is set by hook::notice_once
guard::bad_switch_notice() {
  hook::notice_once "guardrails-bad-switch-$1" "$3" || return 0
  [[ "$HOOK_NOTICE_TO_USER" == 1 ]] || return 0
  hook::emit_channels PreToolUse "" "guardrails: $1=$2 is not true or false, so the guard stays on. Fix it in /plugin configure."
}

guard::abort_boundary() {
  _GAB_NAME="$1"
  _GAB_EVENT="$2"
  case "$3" in
  open | closed) _GAB_POSTURE="$3" ;;
  *)
    printf 'guardrails %s: abort boundary posture %q is not open or closed; using open\n' "$1" "$3" >&2
    _GAB_POSTURE="open"
    ;;
  esac
  shift 3
  _GAB_CHOSEN=" $* "
  trap guard::_abort_on_exit EXIT
}

guard::abort_boundary_release() {
  trap - EXIT
}

guard::_abort_json_escape_to() {
  local __gab_s="$2"
  __gab_s="${__gab_s//\\/\\\\}"
  __gab_s="${__gab_s//\"/\\\"}"
  __gab_s="${__gab_s//$'\n'/\\n}"
  __gab_s="${__gab_s//$'\r'/\\r}"
  __gab_s="${__gab_s//$'\t'/\\t}"
  printf -v "$1" '%s' "$__gab_s"
}

_GAB_CONTINUE=""

guard::_abort_on_exit() {
  local rc=$?
  trap - EXIT
  if [[ -n "$_GAB_CONTINUE" ]]; then
    "$_GAB_CONTINUE" "$rc"
  fi
  guard::_abort_settle "$rc" && return 0
  [[ -n "$_GAB_DOC" ]] && printf '%s\n' "$_GAB_DOC"
  exit "$_GAB_RC"
}

readonly _GAB_GUARDS=" block-body-format-violation block-cd-prefix block-convention-violation block-credential-read block-cross-domain block-dangerous-git block-exported-msys-pathconv block-fix-request-post block-foreground-wait block-github-post-content block-lane-pr-disable-auto block-main-checkout-edit block-no-verify block-noncanonical-commit block-pr-poller block-root-delete-target block-windows-drive-tmp flag-commit-pr-skill-bypass hardcoded-path-check merge-guard run-guards secret-pattern-detection workflow-resilience-check "
_GAB_DIR="${BASH_SOURCE[0]%/*}"
[[ "$_GAB_DIR" == "${BASH_SOURCE[0]}" ]] && _GAB_DIR=.
_GAB_TEAM_REL="docs/conventions/guardrails.yaml"
_GAB_DENY_RESOLVED=0
_GAB_DENY_OPT=" "
_GAB_DENY_TEAM=" "
_GAB_DENY_UNKNOWN=" "
_GAB_DENY_NOTE=""

guard::_abort_deny_add() {
  local list="$1," item
  while [[ -n "$list" ]]; do
    item="${list%%,*}"
    list="${list#*,}"
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [[ -n "$item" ]] || continue
    if [[ "$_GAB_GUARDS" == *" $item "* ]]; then
      printf -v "$2" '%s%s ' "${!2}" "$item"
      continue
    fi
    item="${item//[^[:print:]]/?}"
    if [[ "$_GAB_DENY_UNKNOWN" != *" $item "* ]]; then
      _GAB_DENY_UNKNOWN+="$item "
    fi
  done
}

guard::_abort_deny_resolve() {
  ((_GAB_DENY_RESOLVED)) && return 0
  _GAB_DENY_RESOLVED=1
  guard::_abort_deny_add "${CLAUDE_PLUGIN_OPTION_DENY_ON_CRASH-}" _GAB_DENY_OPT
  local text recs k v
  if text=$(command git --no-pager -c core.fsmonitor=false -c core.hooksPath=/dev/null -C "${CLAUDE_PROJECT_DIR:-.}" show "refs/remotes/origin/HEAD:$_GAB_TEAM_REL" 2>/dev/null); then
    if recs=$(LC_ALL=C command awk -f "$_GAB_DIR/yaml-subset.awk" <<<"$text" 2>/dev/null); then
      while IFS=$'\t' read -r k v; do
        [[ "$k" == deny_on_crash || "$k" =~ ^deny_on_crash\.[0-9]+$ ]] &&
          guard::_abort_deny_add "$v" _GAB_DENY_TEAM
      done <<<"$recs"
    else
      _GAB_DENY_NOTE=" $_GAB_TEAM_REL does not parse, so its deny_on_crash was not read."
    fi
  fi
  [[ "$_GAB_DENY_UNKNOWN" == " " ]] ||
    _GAB_DENY_NOTE+=" deny_on_crash names no guard that gates a tool call:${_GAB_DENY_UNKNOWN% }; ignored."
}

_GAB_DOC=""
_GAB_RC=0
guard::_abort_settle() {
  local rc="$1"
  _GAB_DOC=""
  _GAB_RC=0
  [[ "$_GAB_CHOSEN" == *" $rc "* ]] && return 0
  local msg="" note=""
  if [[ "$_GAB_POSTURE" != closed ]]; then
    guard::_abort_deny_resolve
    note="$_GAB_DENY_NOTE"
    _GAB_DENY_NOTE=""
    local why="" how=""
    if [[ "$_GAB_DENY_OPT" == *" $_GAB_NAME "* ]]; then
      why="the deny_on_crash option names this guard"
      how="from deny_on_crash in /plugin configure"
    fi
    if [[ "$_GAB_DENY_TEAM" == *" $_GAB_NAME "* ]]; then
      if [[ -n "$why" ]]; then
        why="the deny_on_crash option and deny_on_crash in ${_GAB_TEAM_REL} both name this guard"
        how+=" and from deny_on_crash in ${_GAB_TEAM_REL} on the default branch"
      else
        why="deny_on_crash in ${_GAB_TEAM_REL} names this guard"
        how="from that list on the default branch"
      fi
    fi
    if [[ -n "$why" ]]; then
      msg="guardrails ${_GAB_NAME}: guard did not run (internal error, rc=${rc}); deny-on-crash: this tool call is denied because ${why}. To let such a call through with a notice instead, remove ${_GAB_NAME} ${how}. The failing line is on the hook's stderr.${note}"
    fi
    if [[ -n "$msg" ]]; then
      printf '%s\n' "$msg" >&2
      _GAB_RC=2
      return 1
    fi
  fi
  if [[ "$_GAB_POSTURE" == closed ]]; then
    msg="guardrails ${_GAB_NAME}: guard did not run (internal error, rc=${rc}); fail-closed: this tool call is denied because the guard could not check it. The failing line is on the hook's stderr."
    printf '%s\n' "$msg" >&2
    _GAB_RC=2
    return 1
  fi
  msg="guardrails ${_GAB_NAME}: guard did not run (internal error, rc=${rc}); this call was not checked. Details: claude --debug.${note}"
  printf '%s\n' "$msg" >&2
  local esc
  guard::_abort_json_escape_to esc "$msg"
  _GAB_DOC='{"systemMessage":"'"$esc"'"}'
  return 1
}
