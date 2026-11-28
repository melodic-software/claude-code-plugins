#!/usr/bin/env bash
# Exit codes: 0 = allow, 2 = block (stderr reason returned to Claude)

set -uo pipefail

_src="${BASH_SOURCE[0]}"
[[ "$_src" == */* ]] || _src="./$_src"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=lib/run-marker.sh
source "$SCRIPT_DIR/lib/run-marker.sh"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'TXT'
PreToolUse guard that blocks destructive Bash and PowerShell commands during a clean run unless acknowledged.

Usage: destructive-guard.sh [--help]   (the hook runner passes PreToolUse JSON on stdin)
  Bash tool ack:        CLEAN_GUARD_ACK=1 <command>
  PowerShell tool ack:  $env:CLEAN_GUARD_ACK=1; <command>
  --help                print this help

Exit 0 allow; 2 block (the reason on stderr).
TXT
  exit 0
fi

INPUT="$(cat)"

if [[ "${CLAUDE_PLUGIN_OPTION_CLEAN_DESTRUCTIVE_GUARD_ENABLED:-true}" == "false" ]]; then
  exit 0
fi

CLEAN_SCRIPT_NAMES='clean-caches|clean-build|git-prune|git-tree-reset-batch|git-tree-reset|remove-path|clean-batch'
CLEAN_SCRIPT_RE="(^|[[:space:][:punct:]])(${CLEAN_SCRIPT_NAMES})\\.sh([^[:alnum:]_.-]|$)"

is_destructive() {
  local cmd="$1"
  local gopt='((-C|-c|--(config|config-env|git-dir|work-tree|namespace|super-prefix|attr-source|exec-path))[[:space:]]+[^[:space:]]+[[:space:]]+|--[a-zA-Z-]+=[^[:space:]]+[[:space:]]+|(-[pP]|--[a-zA-Z-]+)[[:space:]]+)*'
  local force_re='[[:space:]]-[a-zA-Z]*f|[[:space:]]--force([^[:alnum:]_-]|$)'
  if grep -qE '(^|[[:space:];&|(])rm[[:space:]]' <<<"$cmd" &&
    grep -qE '[[:space:]]-[a-zA-Z]*[rR]|[[:space:]]--recursive([[:space:]]|=|$)' <<<"$cmd" &&
    grep -qE "$force_re" <<<"$cmd"; then
    return 0
  fi
  if grep -qE "git[[:space:]]+${gopt}clean[[:space:]]" <<<"$cmd" &&
    grep -qE "$force_re" <<<"$cmd"; then
    return 0
  fi
  if grep -qE "$CLEAN_SCRIPT_RE" <<<"$cmd" &&
    grep -qE '(^|[^[:alnum:]_-])--apply([^[:alnum:]_-]|$)' <<<"$cmd"; then
    return 0
  fi
  if grep -qE "git[[:space:]]+${gopt}worktree[[:space:]]+remove[[:space:]]" <<<"$cmd" &&
    grep -qE "$force_re" <<<"$cmd"; then
    return 0
  fi
  if grep -qE "git[[:space:]]+${gopt}branch[[:space:]]([^;&|]*[[:space:]])?['\"]?(--delete|-[a-zA-Z]*[dD])" <<<"$cmd"; then
    return 0
  fi
  local push
  while IFS= read -r push; do
    if grep -qE "[[:space:]](['\"]?(--delete|-[a-np-zA-Z]*d)|['\"]?[+]?['\"]?:[^[:space:]'\"])" <<<"$push" &&
      ! grep -qE '[[:space:]](--dry-run|-[a-np-zA-Z]*n[a-np-zA-Z]*)([[:space:]]|$)' <<<"$push"; then
      return 0
    fi
  done < <(grep -oE "git[[:space:]]+${gopt}push[[:space:]][^;&|]*" <<<"$cmd")
  grep -qE "git[[:space:]]+${gopt}reset[[:space:]]+--hard|git[[:space:]]+${gopt}checkout[[:space:]]+--[[:space:]]|git[[:space:]]+${gopt}stash[[:space:]]+(drop|clear)([[:space:]]|$)|Remove-Item[[:space:]].*-Recurse" <<<"$cmd"
}

argv_destructive() {
  local -a w=("$@")
  local n=${#w[@]} i j sub word base script=0 apply=0
  local -a rest
  local recursive force dry del
  for ((i = 0; i < n; i++)); do
    word="${w[i]}"
    base="${word##*/}"
    base="${base##*\\}"
    [[ "$word" == "--apply" ]] && apply=1
    [[ "$base" =~ ^(${CLEAN_SCRIPT_NAMES})\.sh$ ]] && script=1
    case "$base" in
    rm)
      recursive=0 force=0
      for ((j = i + 1; j < n; j++)); do
        [[ "${w[j]}" =~ ^-[a-zA-Z]*[rR] || "${w[j]}" =~ ^--recursive(=.*)?$ ]] && recursive=1
        [[ "${w[j]}" =~ ^-[a-zA-Z]*f || "${w[j]}" == --force ]] && force=1
      done
      ((recursive && force)) && return 0
      ;;
    Remove-Item)
      for ((j = i + 1; j < n; j++)); do
        [[ "${w[j]}" == -Recurse* ]] && return 0
      done
      ;;
    git)
      hook::git_resolve_subcommand "$i" "${w[@]}" || continue
      sub="$HOOK_GIT_SUB"
      rest=("${w[@]:HOOK_GIT_SUB_IDX+1}")
      force=0
      for word in "${rest[@]}"; do
        [[ "$word" =~ ^-[a-zA-Z]*f || "$word" == --force ]] && force=1
      done
      case "$sub" in
      clean)
        ((force)) && return 0
        ;;
      worktree)
        [[ "${rest[0]:-}" == remove ]] && ((force)) && return 0
        ;;
      branch)
        for word in "${rest[@]}"; do
          [[ "$word" =~ ^-[a-zA-Z]*[dD] || "$word" =~ ^--delete ]] && return 0
        done
        ;;
      push)
        del=0 dry=0
        for word in "${rest[@]}"; do
          [[ "$word" =~ ^--delete || "$word" =~ ^-[a-np-zA-Z]*d || "$word" =~ ^[+]?:. ]] && del=1
          [[ "$word" == --dry-run || "$word" =~ ^-[a-np-zA-Z]*n[a-np-zA-Z]*$ ]] && dry=1
        done
        ((del && !dry)) && return 0
        ;;
      reset)
        [[ "${rest[0]:-}" == --hard ]] && return 0
        ;;
      checkout)
        [[ "${rest[0]:-}" == -- ]] && return 0
        ;;
      stash)
        [[ "${rest[0]:-}" == drop || "${rest[0]:-}" == clear ]] && return 0
        ;;
      *) ;;
      esac
      ;;
    *) ;;
    esac
  done
  ((script && apply)) && return 0
  return 1
}

ARGV_HIT=0
GUARD_DEPTH=0
GUARD_DEPTH_MAX=32

guard_parse() {
  ((ARGV_HIT)) && return 0
  if ((GUARD_DEPTH >= GUARD_DEPTH_MAX)); then
    ARGV_HIT=1
    return 0
  fi
  GUARD_DEPTH=$((GUARD_DEPTH + 1))
  local -a _gp_prev=() _gp_prev_hs=() _gp_prev_hd=() _gp_hd_feed=() _gp_subs=() _gp_bodies=()
  local _gp_hd_seen=0 _gp_s _gp_e _gp_start _gp_end
  hook::bash_parse_segments "$1" argv_segment
  _gp_bodies=(${HOOK_HEREDOC_BODIES[@]+"${HOOK_HEREDOC_BODIES[@]}"})
  if ((${#_gp_hd_feed[@]})); then
    _gp_hd_feed=("${!_gp_bodies[@]}")
  fi
  for _gp_s in ${_gp_hd_feed[@]+"${_gp_hd_feed[@]}"}; do
    _gp_e="${_gp_bodies[_gp_s]-}"
    [[ -n "$_gp_e" ]] || continue
    _gp_start="${_gp_e%% *}"
    _gp_e="${_gp_e#* }"
    _gp_end="${_gp_e%% *}"
    hook::_c_locale byte_slice_to _gp_e "$1" "$_gp_start" $((_gp_end - _gp_start))
    guard_parse "$_gp_e"
  done
  substitutions_to _gp_subs "$1" ${_gp_bodies[@]+"${_gp_bodies[@]}"}
  for _gp_s in ${_gp_subs[@]+"${_gp_subs[@]}"}; do
    guard_parse "$_gp_s"
  done
  GUARD_DEPTH=$((GUARD_DEPTH - 1))
  return 0
}

# shellcheck disable=SC2329  # reached through hook::_c_locale
byte_slice_to() {
  if (($# > 3)); then
    printf -v "$1" '%s' "${2:$3:$4}"
  else
    printf -v "$1" '%s' "${2:$3}"
  fi
}

# shellcheck disable=SC1003  # '\' compares a literal backslash char, not a quote escape
substitutions_to() {
  local -n _st_out="$1"
  local cmd="$2"
  shift 2
  local -a chars=() bodies=("$@")
  local n i=0 b=0 nb=$# dq=0 hd=0 hd_end=0 c rest start j s
  _st_out=()
  hook::_bps_chars "$cmd"
  n=${#chars[@]}
  while ((i < n)); do
    ((hd && i >= hd_end)) && hd=0
    while ((!hd && b < nb)); do
      rest="${bodies[b]#* }"
      ((${rest%% *} <= i && ${bodies[b]%% *} < i)) || break
      b=$((b + 1))
    done
    if ((!hd && b < nb)); then
      start="${bodies[b]%% *}"
      if ((i >= start)); then
        rest="${bodies[b]#* }"
        hd_end="${rest%% *}"
        rest="${rest#* }"
        b=$((b + 1))
        if [[ "${rest%% *}" == 1 ]]; then
          i=$hd_end
          continue
        fi
        hd=1
      fi
    fi
    c="${chars[i]}"
    case "$c" in
    '\')
      i=$((i + 2))
      continue
      ;;
    "'")
      if ((!dq && !hd)); then
        i=$((i + 1))
        while ((i < n)) && [[ "${chars[i]}" != "'" ]]; do i=$((i + 1)); done
      fi
      ;;
    '"')
      ((hd)) || dq=$((!dq))
      ;;
    '$')
      if ((dq || hd)) && [[ "${chars[i + 1]-}" == '(' ]]; then
        subst_end_to j $((i + 2))
        hook::_c_locale byte_slice_to s "$cmd" $((i + 2)) $((j - i - 2))
        _st_out+=("$s")
        i=$j
      elif ((!dq && !hd)) && [[ "${chars[i + 1]-}" == "'" ]]; then
        i=$((i + 2))
        while ((i < n)) && [[ "${chars[i]}" != "'" ]]; do
          [[ "${chars[i]}" == '\' ]] && i=$((i + 1))
          i=$((i + 1))
        done
      fi
      ;;
    '`')
      if ((dq || hd)); then
        s=""
        for ((i++; i < n; i++)); do
          [[ "${chars[i]}" == '`' ]] && break
          [[ "${chars[i]}" == '\' && "${chars[i + 1]-}" == [\$\`\\\"] ]] && i=$((i + 1))
          s+="${chars[i]}"
        done
        _st_out+=("$s")
      fi
      ;;
    '#')
      if ((!dq && !hd)) && { ((i == 0)) || [[ "${chars[i - 1]}" == [[:space:]\;\&\|\(\)] ]]; }; then
        while ((i + 1 < n)) && [[ "${chars[i + 1]}" != $'\n' ]]; do i=$((i + 1)); done
      fi
      ;;
    *) ;;
    esac
    i=$((i + 1))
  done
}

subst_end_to() {
  local -n _se_out="$1"
  local from="$2" close tail e s
  local -a hs=() he=()
  paren_close_to close "$from"
  hook::_c_locale byte_slice_to tail "$cmd" "$from" $((close - from))
  if [[ "$tail" == *'<<'* ]]; then
    for e in ${bodies[@]+"${bodies[@]}"}; do
      s="${e%% *}"
      ((s >= from)) || continue
      e="${e#* }"
      hs+=("$s")
      he+=("${e%% *}")
    done
    paren_close_to close "$from"
  fi
  _se_out=$close
}

# shellcheck disable=SC1003  # '\' compares a literal backslash char, not a quote escape
paren_close_to() {
  local -n _pc_out="$1"
  local k="$2" depth=1 hb=0
  while ((k < n)); do
    if ((hb < ${#hs[@]} && k >= hs[hb])); then
      k=${he[hb]}
      hb=$((hb + 1))
      continue
    fi
    case "${chars[k]}" in
    '#')
      if [[ "${chars[k - 1]}" == [[:space:]\;\&\|\(\)] ]]; then
        while ((k + 1 < n)) && [[ "${chars[k + 1]}" != $'\n' ]]; do k=$((k + 1)); done
      fi
      ;;
    '\') k=$((k + 1)) ;;
    "'")
      k=$((k + 1))
      while ((k < n)) && [[ "${chars[k]}" != "'" ]]; do k=$((k + 1)); done
      ;;
    '"')
      k=$((k + 1))
      while ((k < n)) && [[ "${chars[k]}" != '"' ]]; do
        [[ "${chars[k]}" == '\' ]] && k=$((k + 1))
        k=$((k + 1))
      done
      ;;
    '(') depth=$((depth + 1)) ;;
    ')')
      depth=$((depth - 1))
      ((depth)) || break
      ;;
    *) ;;
    esac
    k=$((k + 1))
  done
  _pc_out=$k
}

shell_reads_stdin() {
  local -a a=("$@")
  local n=$# i=0 s=0
  while ((i < n)); do
    case "${a[i]}" in
    --)
      i=$((i + 1))
      break
      ;;
    -o | +o | -O | +O | --rcfile | --init-file) i=$((i + 2)) ;;
    -* | +*)
      [[ "${a[i]}" =~ ^-[A-Za-z]*s[A-Za-z]*$ ]] && s=1
      i=$((i + 1))
      ;;
    *) break ;;
    esac
  done
  ((s || i >= n))
}

ssh_command_to() {
  local -n _sc_out="$1"
  shift
  local -a a=("$@")
  local n=$# i=0 k t IFS=' '
  _sc_out=""
  while ((i < n)) && [[ "${a[i]}" == -* ]]; do
    t="${a[i]}"
    i=$((i + 1))
    [[ "$t" == -- ]] && break
    for ((k = 1; k < ${#t}; k++)); do
      case "${t:k:1}" in
      [BbcDEeFIiJLlmOoPpQRSWw])
        ((k + 1 < ${#t})) || i=$((i + 1))
        break
        ;;
      *) ;;
      esac
    done
  done
  ((i < n)) || return 1
  _sc_out="${a[*]:i+1}"
}

shell_name_to() {
  local -n _sn_out="$1"
  _sn_out="${2##*/}"
  _sn_out="${_sn_out##*\\}"
  _sn_out="${_sn_out,,}"
  _sn_out="${_sn_out%.exe}"
}

stdin_script_reader() {
  local -a w=("$@")
  local n=$# i=0 wrapped=0 name line
  while ((i < n)); do
    shell_name_to name "${w[i]}"
    if [[ "${w[i]}" == *=* && "${w[i]}" != -* ]]; then
      :
    elif ((wrapped)) && [[ "${w[i]}" == -* || "${w[i]}" =~ ^[0-9.]+[smhd]?$ ]]; then
      :
    else
      case "$name" in
      sudo | doas | env | timeout | nice | nohup | time | command | exec | stdbuf | setsid) wrapped=1 ;;
      *) break ;;
      esac
    fi
    i=$((i + 1))
  done
  ((i < n)) || return 1
  case "$name" in
  bash | sh | zsh | dash | ksh | mksh) shell_reads_stdin "${w[@]:i+1}" ;;
  ssh) ssh_command_to line "${w[@]:i+1}" && [[ -z "$line" ]] ;;
  *) return 1 ;;
  esac
}

# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
argv_segment() {
  ((ARGV_HIT)) && return 0
  local -a w=("$@") prev=(${_gp_prev[@]+"${_gp_prev[@]}"})
  local -a prev_hs=(${_gp_prev_hs[@]+"${_gp_prev_hs[@]}"}) prev_hd=(${_gp_prev_hd[@]+"${_gp_prev_hd[@]}"})
  local -a ops=(${HOOK_SEG_REDIR_OP[@]+"${HOOK_SEG_REDIR_OP[@]}"})
  local -a targets=(${HOOK_SEG_REDIR_TARGET[@]+"${HOOK_SEG_REDIR_TARGET[@]}"})
  local -a hs=() hd=()
  local n=$# i j name line dec
  for ((j = 0; j < ${#ops[@]}; j++)); do
    case "${ops[j]}" in
    '<<' | '<<-')
      hd+=("$_gp_hd_seen")
      _gp_hd_seen=$((_gp_hd_seen + 1))
      ;;
    '<<<') hs+=("${targets[j]}") ;;
    *) ;;
    esac
  done
  _gp_prev=("$@")
  _gp_prev_hs=(${hs[@]+"${hs[@]}"})
  _gp_prev_hd=(${hd[@]+"${hd[@]}"})
  if argv_destructive "$@"; then
    ARGV_HIT=1
    return 0
  fi
  for ((i = 0; i < n; i++)); do
    shell_name_to name "${w[i]}"
    case "$name" in
    eval)
      guard_parse "${w[*]:i+1}"
      break
      ;;
    ssh)
      if ssh_command_to line "${w[@]:i+1}" && [[ -n "$line" ]]; then
        guard_parse "$line"
        break
      fi
      ;;
    bash | sh | zsh | dash | ksh | mksh | wsl)
      if hook::shell_c_operand "${w[@]:i}"; then
        guard_parse "$HOOK_SHELL_C_OPERAND"
        break
      fi
      ;;
    *) ;;
    esac
  done
  ((ARGV_HIT)) && return 0
  stdin_script_reader "$@" || return 0
  _gp_hd_feed+=(${hd[@]+"${hd[@]}"} ${prev_hd[@]+"${prev_hd[@]}"})
  for line in ${hs[@]+"${hs[@]}"} ${prev_hs[@]+"${prev_hs[@]}"}; do
    guard_parse "$line"
  done
  line=""
  for ((j = 1; j < ${#prev[@]}; j++)); do
    hook::ansi_c_decode_to dec "${prev[j]}"
    line+="$dec "
  done
  [[ -z "$line" ]] || guard_parse "$line"
  return 0
}

SCRIPT_HIT=0
# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
script_segment() {
  ((SCRIPT_HIT)) && return 0
  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" script_segment
    return 0
  fi
  local -a w=("$@")
  local n=${#w[@]} i=0 base
  while ((i < n)) && [[ "${w[i]}" == *=* && "${w[i]}" != -* ]]; do ((i++)); done
  base="${w[i]:-}"
  base="${base##*/}"
  base="${base##*\\}"
  case "$base" in
  bash | sh)
    for ((i++; i < n; i++)); do [[ "${w[i]}" == -* ]] || break; done
    base="${w[i]:-}"
    base="${base##*/}"
    base="${base##*\\}"
    ;;
  *) ;;
  esac
  [[ "$base" =~ ^(${CLEAN_SCRIPT_NAMES})\.sh$ ]] && SCRIPT_HIT=1
  return 0
}

invokes_clean_script() {
  SCRIPT_HIT=0
  hook::bash_parse_segments "$1" script_segment
  ((SCRIPT_HIT))
}

is_destructive_bash() {
  ARGV_HIT=0
  GUARD_DEPTH=0
  guard_parse "$1"
  ((ARGV_HIT))
}

if ! command -v jq >/dev/null 2>&1; then
  if is_destructive "${INPUT//\"/ }"; then
    {
      echo "BLOCKED by the clean skill's destructive guard (degraded mode: jq not found)."
      echo "Without jq the guard cannot verify the CLEAN_GUARD_ACK acknowledgement, so destructive commands are blocked outright."
      echo "Install jq to restore the dry-run -> user-confirmation -> CLEAN_GUARD_ACK=1 flow."
    } >&2
    exit 2
  fi
  exit 0
fi

CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[[ -n "$CMD" ]] || exit 0
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)"
SESSION="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"

refresh_marker() {
  [[ -z "$MARKER_FILE" ]] || run_marker_write "$MARKER_FILE"
}

MARKER_FILE="" MARKER_STATE=""
if run_marker_data_dir_ours "${CLAUDE_PLUGIN_DATA:-}" &&
  run_marker_path_to MARKER_FILE "${CLAUDE_PLUGIN_DATA:-}" "$SESSION"; then
  run_marker_state_to MARKER_STATE "$MARKER_FILE"
  [[ "$MARKER_STATE" != absent ]] || exit 0
fi

# shellcheck source=hook-utils.sh
source "$SCRIPT_DIR/hook-utils.sh" || {
  echo "BLOCKED by the clean skill's destructive guard: $SCRIPT_DIR/hook-utils.sh did not load, so the guard cannot read the command." >&2
  exit 2
}

if [[ -n "$MARKER_STATE" ]]; then
  if invokes_clean_script "$CMD"; then
    MARKER_STATE=live
    refresh_marker
  fi
  if [[ "$MARKER_STATE" == stale ]]; then
    rm -f "$MARKER_FILE"
    exit 0
  fi
fi

is_acknowledged() {
  local cmd="$1" tool="$2"
  case "$tool" in
  Bash)
    [[ "$cmd" == CLEAN_GUARD_ACK=1\ * ]]
    ;;
  PowerShell)
    # shellcheck disable=SC2016  # literal `$env:` is the PowerShell spelling
    local ps_ack_re='^[[:space:]]*\$env:CLEAN_GUARD_ACK[[:space:]]*=[[:space:]]*(1|'"'"'1'"'"'|"1")[[:space:]]*;'
    [[ "$cmd" =~ $ps_ack_re ]]
    ;;
  *)
    return 1
    ;;
  esac
}

if is_acknowledged "$CMD" "$TOOL"; then
  refresh_marker
  exit 0
fi

command_is_destructive() {
  if [[ "$TOOL" == Bash ]]; then is_destructive_bash "$CMD"; else is_destructive "$CMD"; fi
}
if command_is_destructive; then
  refresh_marker
  # shellcheck disable=SC2016  # literal `$env:` is the PowerShell spelling
  case "$TOOL" in
  Bash) ack_form='CLEAN_GUARD_ACK=1 <command>' ;;
  PowerShell) ack_form='$env:CLEAN_GUARD_ACK=1; <command>' ;;
  *) ack_form='' ;;
  esac
  {
    echo "BLOCKED by the clean skill's destructive guard (session-scoped skill hook)."
    echo "Destructive commands during a clean run go only through the skill's dry-run -> user-confirmation gate."
    if [[ -n "$ack_form" ]]; then
      echo "After the user has explicitly confirmed, re-issue with the acknowledgement prefix for this tool: $ack_form"
    else
      echo "This tool has no acknowledgement path, so there is nothing to re-issue with here. Run the confirmed command through the Bash or PowerShell tool instead."
    fi
  } >&2
  exit 2
fi

exit 0
