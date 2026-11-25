#!/usr/bin/env bash

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_ROOT_DELETE_TARGET_ENABLED:-true}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary block-root-delete-target PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it
# shellcheck source=refuse.sh
source "$_HOOK_SELF/refuse.sh" || exit 70 # not a chosen status: the boundary reports it
# shellcheck source=block-root-delete-target-resolve.sh
source "$_HOOK_SELF/block-root-delete-target-resolve.sh" || exit 70 # not a chosen status: the boundary reports it

start=${EPOCHREALTIME:-}

hook::buffer_stdin_to INPUT || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}

hook::require_jq_blocking "guardrails-block-root-delete-target" "block_root_delete_target_enabled"

jq_rc=0
hook::jq_fields "$INPUT" '.tool_input.command' '.tool_name' || jq_rc=$?
guard::payload_verdict "$jq_rc" || exit $(($? == 3 ? 0 : 2))

COMMAND="${HOOK_JQ_FIELDS[0]}"
TOOL_NAME="${HOOK_JQ_FIELDS[1]:-Bash}"
PAYLOAD_CWD=""
RDT_CWD_NUL=0

[[ "$TOOL_NAME" == "Bash" || "$TOOL_NAME" == "PowerShell" ]] || exit 0

if [[ "$TOOL_NAME" == "PowerShell" && ("$INPUT" == *'\r'* || "$INPUT" == *'\u000'[dD]*) ]]; then
  rdt_bs=$'\\'
  rdt_cr="${rdt_bs}r" rdt_lf="${rdt_bs}n"
  rdt_in="${INPUT//"$rdt_bs$rdt_bs"/$'\001'}"
  rdt_in="${rdt_in//"${rdt_bs}u000"[dD]/"$rdt_cr"}"
  rdt_in="${rdt_in//"${rdt_bs}u000"[aA]/"$rdt_lf"}"
  rdt_in="${rdt_in//"$rdt_cr$rdt_lf"/"$rdt_lf"}"
  rdt_in="${rdt_in//"$rdt_cr"/"$rdt_lf"}"
  rdt_in="${rdt_in//$'\001'/"$rdt_bs$rdt_bs"}"
  if [[ "$rdt_in" != "$INPUT" ]] && hook::jq_fields "$rdt_in" '.tool_input.command'; then
    COMMAND="${HOOK_JQ_FIELDS[0]}"
  fi
fi
HOOK_REFUSE_COMMAND="$COMMAND"

[[ -n "$COMMAND" ]] || exit 0

MAX_COMMAND_LEN=16384

MAX_SUBST_DEPTH=32

MAX_SEGMENT_DEPTH=24
rdt_depth=0

MAX_SEGMENTS=1024
rdt_segments=0

rdt_emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local SUBJECT data
  hook::extract_bash_subject_to SUBJECT "$TOOL_NAME" "$COMMAND"
  hook::json_str_object_to data tool "$TOOL_NAME" subject "$SUBJECT" form "$2"
  hook::emit_telemetry "block-root-delete-target" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

rdt_block() {
  local form="$1" target="${2:-}" msg
  case "$form" in
  no-preserve-root)
    printf -v msg '%s\n' \
      'BLOCKED: this is a recursive delete carrying --no-preserve-root.' \
      'Fix: drop --no-preserve-root and name the directory to remove explicitly, under the working tree.'
    ;;
  too-long)
    printf -v msg '%s\n' \
      'BLOCKED: the command is too long to parse, so a recursive delete inside it cannot be ruled out.' \
      'Fix: split it into shorter commands, or write it to a script and run that.'
    ;;
  nesting-too-deep)
    printf -v msg '%s\n' \
      "BLOCKED: substitution nesting deeper than $MAX_SUBST_DEPTH." \
      'Fix: flatten the command substitutions, or assign the inner results to variables in separate commands.'
    ;;
  eval-too-long)
    printf -v msg '%s\n' \
      'BLOCKED: eval, parallel, interpreter-spawned and substitution text exceeds MAX_COMMAND_LEN in total.' \
      'Fix: drop the nested evals or parallel options, or run the inner command on its own.'
    ;;
  too-many-readings)
    printf -v msg '%s\n' \
      'BLOCKED: too many launcher readings to judge every one; flatten the command.' \
      'Fix: drop the repeated launchers, or run the inner command on its own.'
    ;;
  nesting-too-deep-launcher)
    printf -v msg '%s\n' \
      "BLOCKED: launcher or eval nesting deeper than $MAX_SEGMENT_DEPTH; flatten the command." \
      'Fix: drop the repeated launchers, or run the inner command on its own.'
    ;;
  too-many-abbreviations)
    printf -v msg '%s\n' \
      'BLOCKED: too many command segments with abbreviated launcher options to judge every reading; spell the options in full.' \
      'Fix: spell the launcher options in full (flock --wait 5), or split the command into shorter ones.'
    ;;
  bodies-too-long)
    printf -v msg '%s\n' \
      'BLOCKED: substitution bodies exceed MAX_COMMAND_LEN in total.' \
      'Fix: flatten the command substitutions, or assign the inner results to variables in separate commands.'
    ;;
  empty-operand)
    printf -v msg '%s\n' \
      'BLOCKED: this recursive delete has an empty operand ("").' \
      'Fix: name the directory to remove explicitly, or drop the empty word.'
    ;;
  pipeline-target)
    printf -v msg '%s\n' \
      'BLOCKED: this recursive delete takes its target from the pipeline or a grouping, which this guard cannot name.' \
      'Fix: write the directory to remove out literally: as a -Path or -LiteralPath value for a cmdlet, or as the path argument itself for robocopy or a .NET Delete call.'
    ;;
  pipeline-feed)
    printf -v msg '%s\n' \
      'BLOCKED: xargs or parallel runs a recursive delete on items no confined listing produced (read from a file, from the stdin of the shell, or from a command other than find or git ls-files), so this guard cannot name its targets.' \
      'Fix: pipe find <dir> (without -printf, -ls or -exec) or git ls-files into it, through grep, sort, uniq, head or tail at most, or name the targets as operands.'
    ;;
  bare-variable)
    # Single-quoted on purpose: the text shows a literal ${NAME:?}.
    # shellcheck disable=SC2016
    printf -v msg '%s\n' \
      "BLOCKED: this recursive delete targets a bare variable ('$target'), whose value is not known until it runs." \
      'Fix: write the path out literally, or use "${NAME:?}/sub" so an unset or empty value aborts the command before rm runs.'
    ;;
  outside-tree)
    printf -v msg '%s\n' \
      "BLOCKED: recursive delete of $target, outside the working tree, the temp directories, the session scratchpad and the roots in block_root_delete_target_allowed_roots." \
      'Fix: delete only strictly under one of those (put scratch work under the working tree, for example a gitignored .work/), and do not retry the delete with another tool (find -delete, rmtree, git clean).' \
      'Otherwise the user runs it, or lists its root in block_root_delete_target_allowed_roots (only the user can).'
    ;;
  protected-tree)
    printf -v msg '%s\n' \
      "BLOCKED: recursive delete of $target. A protected tree is refused even under the working tree, a temp root or an allowed root." \
      'Fix: name only the paths inside it you mean to remove, and do not retry the delete with another tool (find -delete, rmtree, git clean); remove a worktree with git worktree remove.' \
      'Otherwise the user runs it, or drops it from block_root_delete_target_protected_trees when it is listed there (only the user can).'
    ;;
  too-many-origins)
    printf -v msg '%s\n' \
      "BLOCKED: too many directory changes to judge every place this delete may run from (more than $MAX_ORIGINS)." \
      'Fix: cd once to an absolute directory, or run the delete as its own command.'
    ;;
  too-many-targets)
    printf -v msg '%s\n' \
      "BLOCKED: too many recursive delete targets to judge (more than $MAX_TARGETS directory-and-target pairs)." \
      'Fix: delete a parent directory, or split the delete into shorter commands.'
    ;;
  too-many-glob-entries)
    printf -v msg '%s\n' \
      "BLOCKED: a glob in this recursive delete reads more than $MAX_GLOB directory entries, files included." \
      'Fix: narrow the glob to the names you mean, or delete the parent directory whole.'
    ;;
  operand-too-long)
    printf -v msg '%s\n' \
      "BLOCKED: this recursive delete names $target." \
      'Fix: check how the command was built; name the directory to remove directly.'
    ;;
  too-slow)
    printf -v msg '%s\n' \
      "BLOCKED: judging where this recursive delete lands ran out of time (a bound of $RDT_DEADLINE seconds for the judgment, $RDT_DEADLINE_ABS for the whole hook)." \
      'Fix: delete fewer targets per command, or cd once to an absolute directory first.'
    ;;
  unplaceable)
    printf -v msg '%s\n' \
      "BLOCKED: recursive delete of $target, which cannot be judged (another user's home, a newline, \`..\` after a glob, or a cd CDPATH may redirect)." \
      'Fix: write the target as an absolute or working-tree-relative path.'
    ;;
  interp-unplaceable)
    printf -v msg '%s\n' \
      "BLOCKED: interpreter code deletes or runs $target, which this guard cannot read: only a plain string literal is judged." \
      'Fix: write the path or command in the code as a plain string literal, or delete with rm -rf <path> as its own command.'
    ;;
  brace)
    printf -v msg '%s\n' \
      "BLOCKED: this recursive delete has a brace expansion ($target) that cannot be judged alternative by alternative." \
      'Fix: write each target out as its own operand.'
    ;;
  brace-too-large)
    printf -v msg '%s\n' \
      "BLOCKED: this recursive delete has a brace expansion ($target) too large to expand in time." \
      'Fix: write each target out as its own operand.'
    ;;
  nul-field)
    printf -v msg '%s\n' \
      "BLOCKED: this recursive delete cannot be judged, because the hook payload's $target carries a NUL byte." \
      'Fix: reissue the tool call; if it repeats, report the malformed payload.'
    ;;
  control-bytes)
    printf -v msg '%s\n' \
      "BLOCKED: recursive delete of $target, whose \$ signs cannot be read as literal or expanded because the command carries every control byte the guard could mark them with." \
      'Fix: remove the control characters from the command.'
    ;;
  judge-error)
    printf -v msg '%s\n' \
      'BLOCKED: judging where this recursive delete lands failed unexpectedly.' \
      'Fix: simplify the command, or run the delete on its own.'
    ;;
  decoder-sink)
    printf -v msg '%s\n' \
      'BLOCKED: decoded text (base64 -d, base32 -d, basenc -d, xxd -r or [Convert]::FromBase64String) is run as a command, by a shell, eval, source, Invoke-Expression or a substitution in command position, so this guard cannot read what would run.' \
      'Fix: decode to a file, read it, and run the commands it holds as commands of their own.'
    ;;
  encoded-unreadable)
    printf -v msg '%s\n' \
      'BLOCKED: this -EncodedCommand is not a literal base64 string of UTF-16LE text this guard can read (printable ASCII, tab and line breaks), so a delete inside it cannot be ruled out.' \
      'Fix: pass the command as -Command text, or run what it holds as a command of its own.'
    ;;
  *)
    # shellcheck disable=SC2016
    printf -v msg '%s\n' \
      "BLOCKED: recursive delete of a filesystem root (normalizes to '$target')." \
      'Fix: name the directory to remove, relative to the working tree. $HOME and ~ are matched as written, not expanded.'
    ;;
  esac
  rdt_emit_tel "blocked" "$form"
  case "$form" in
  no-preserve-root | empty-operand | pipeline-target | pipeline-feed | bare-variable | outside-tree | protected-tree | unplaceable | interp-unplaceable | brace | root-operand)
    hook::refuse "${msg%$'\n'}"
    return 0
    ;;
  *) ;;
  esac
  printf '%s' "$msg" >&2
  exit 2
}

if ((${#COMMAND} > MAX_COMMAND_LEN)); then
  rdt_block "too-long"
fi

if [[ "$TOOL_NAME" == "PowerShell" ]]; then
  rdt_ps_pre="${COMMAND,,}"
  case "$rdt_ps_pre" in
  *rm* | *remove-item* | *erase* | *cmd* | *rd* | *del* | *robocopy* | *frombase64* | *pwsh* | *powershell* | \
    *move* | *mv* | *clear-content* | *set-content*) ;;
  *unlink* | *rsync* | *worktree* | *truncate* | *shred* | *of=* | *base64* | *base32* | *basenc* | *xxd*) ;;
  *) [[ "$rdt_ps_pre" =~ (^|[^[:alnum:]_])(ri|mi|clc)([^[:alnum:]_]|$) ]] || exit 0 ;;
  esac
else
  case "${COMMAND,,}" in
  *rm* | *-delete* | *.delete* | *unlink* | *rsync* | *robocopy* | *worktree* | *remove* | *mv* | *truncate* | \
    *shred* | *of=* | *base64* | *base32* | *basenc* | *xxd* | *cmd*rd* | *cmd*del* | *cmd*erase*) ;;
  *) exit 0 ;;
  esac
fi

if hook::jq_fields "$INPUT" '.cwd'; then
  if ((HOOK_JQ_FIELDS_NUL)); then
    RDT_CWD_NUL=1
  else
    PAYLOAD_CWD="${HOOK_JQ_FIELDS[0]:-}"
  fi
fi

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_normalize_to() {
  local __rdt_dest="$1" __rdt_s="$2"
  __rdt_s="${__rdt_s//\\//}"
  __rdt_s="${__rdt_s,,}"
  local __rdt_lead=""
  if [[ "$__rdt_s" == //* && "$__rdt_s" != ///* ]]; then
    __rdt_lead="/"
    __rdt_s="${__rdt_s#/}"
  fi
  while [[ "$__rdt_s" == *//* ]]; do
    __rdt_s="${__rdt_s//\/\//\/}"
  done
  __rdt_s="$__rdt_lead$__rdt_s"
  rdt_strip_nameless_to __rdt_s "$__rdt_s" 0
  printf -v "$__rdt_dest" '%s' "$__rdt_s"
}

# shellcheck disable=SC2016,SC2329  # literal `${` pattern; invoked from rdt_normalize_to and rdt_strip_tail_to
rdt_strip_nameless_to() {
  local __sn_s="$2" __sn_min="$3" __sn_i __sn_d=0 __sn_k __sn_cut __sn_end
  local -a __sn_cuts=()
  for ((__sn_i = 0; __sn_i < ${#__sn_s}; __sn_i++)); do
    case "${__sn_s:__sn_i:1}" in
    '$')
      if [[ "${__sn_s:__sn_i+1:1}" == '{' ]]; then
        __sn_d=$((__sn_d + 1))
        __sn_i=$((__sn_i + 1))
      fi
      ;;
    '}') ((__sn_d > 0)) && __sn_d=$((__sn_d - 1)) ;;
    /) ((__sn_d == 0)) && __sn_cuts+=("$__sn_i") ;;
    *) ;;
    esac
  done
  __sn_end=${#__sn_s}
  for ((__sn_k = ${#__sn_cuts[@]} - 1; __sn_k >= 0; __sn_k--)); do
    __sn_cut=${__sn_cuts[__sn_k]}
    ((__sn_cut >= __sn_min)) || break
    [[ "${__sn_s:__sn_cut+1:__sn_end-__sn_cut-1}" == *[[:alnum:]_]* ]] && break
    __sn_end=$__sn_cut
  done
  __sn_s="${__sn_s:0:__sn_end}"
  [[ -z "$__sn_s" && "$__sn_min" == 0 ]] && __sn_s="/"
  printf -v "$1" '%s' "$__sn_s"
}

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_is_root() {
  local s="$1"
  [[ -n "$s" ]] || return 1
  # shellcheck disable=SC2016  # matching the literal text, not expanding it
  case "$s" in
  '/' | '~' | '$home' | '${home}') return 0 ;;
  *) ;;
  esac
  [[ "$s" =~ ^/+$ ]] && return 0
  [[ "$s" =~ ^//[^/]+/[^/]+$ ]] && return 0
  [[ "$s" =~ ^([a-z]:|/[a-z]|/cygdrive/[a-z]|/mnt/[a-z])$ ]]
}

RDT_RU_POSIX=0
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_runuser_argv() {
  local off="$1"
  shift
  local -a a=("$@")
  local n=$# k=0 m w name hit hits opt ch val bad
  RDT_RU_CMDS=()
  RDT_RU_ARGV=()
  RDT_RU_QUOTED=()
  RDT_RU_U=0
  RDT_RU_SHELL=""
  while ((k < n)); do
    w="${a[k]}"
    case "$w" in
    --)
      for ((m = k + 1; m < n; m++)); do
        RDT_RU_ARGV+=("${a[m]}")
        RDT_RU_QUOTED+=("${HOOK_SEG_WORD_QUOTED[off + m]:-0}")
      done
      return 0
      ;;
    --?*)
      name="${w#--}"
      name="${name%%=*}"
      hit=""
      hits=0
      for opt in command session-command fast login preserve-environment pty no-pty shell group supp-group user whitelist-environment help version; do
        if [[ "$opt" == "$name" ]]; then
          hit="$opt"
          hits=1
          break
        fi
        if [[ -n "$name" && "$opt" == "$name"* ]]; then
          hit="$opt"
          hits=$((hits + 1))
        fi
      done
      ((hits == 1)) || hit=""
      if [[ -z "$hit" ]]; then
        if ((${#RDT_RU_ARGV[@]} == 0)); then
          k=$((k + 1))
          continue
        fi
        RDT_RU_ARGV+=("$w")
        RDT_RU_QUOTED+=("${HOOK_SEG_WORD_QUOTED[off + k]:-0}")
        k=$((k + 1))
        continue
      fi
      k=$((k + 1))
      case "$hit" in
      command | session-command | shell | group | supp-group | user | whitelist-environment)
        if [[ "$w" == *=* ]]; then
          val="${w#*=}"
        else
          val="${a[k]-}"
          ((k < n)) && k=$((k + 1))
        fi
        if [[ "$hit" == "command" || "$hit" == "session-command" ]]; then
          RDT_RU_CMDS+=("$val")
          [[ "$val" == "--" ]] && ((k < n)) && RDT_RU_CMDS+=("${a[k]}")
        fi
        [[ "$hit" == "user" ]] && RDT_RU_U=1
        [[ "$hit" == "shell" ]] && RDT_RU_SHELL="$val"
        ;;
      *) ;;
      esac
      continue
      ;;
    -?*)
      bad=0
      for ((m = 1; m < ${#w}; m++)); do
        ch="${w:m:1}"
        case "$ch" in
        f | l | m | p | P | T | h | V) ;;
        c | g | G | s | u | w) break ;;
        *)
          bad=1
          break
          ;;
        esac
      done
      if ((bad == 0)); then
        k=$((k + 1))
        if ((m < ${#w})); then
          val="${w:m+1}"
          if [[ -z "$val" ]]; then
            val="${a[k]-}"
            ((k < n)) && k=$((k + 1))
          fi
          [[ "$ch" == "c" ]] && RDT_RU_CMDS+=("$val")
          [[ "$ch" == "c" && "$val" == "--" ]] && ((k < n)) && RDT_RU_CMDS+=("${a[k]}")
          [[ "$ch" == "u" ]] && RDT_RU_U=1
          [[ "$ch" == "s" ]] && RDT_RU_SHELL="$val"
        fi
        continue
      fi
      if ((${#RDT_RU_ARGV[@]} == 0)); then
        k=$((k + 1))
        continue
      fi
      ;;
    *) ;;
    esac
    if ((RDT_RU_POSIX)); then
      for ((m = k; m < n; m++)); do
        RDT_RU_ARGV+=("${a[m]}")
        RDT_RU_QUOTED+=("${HOOK_SEG_WORD_QUOTED[off + m]:-0}")
      done
      return 0
    fi
    RDT_RU_ARGV+=("$w")
    RDT_RU_QUOTED+=("${HOOK_SEG_WORD_QUOTED[off + k]:-0}")
    k=$((k + 1))
  done
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_ru_key_to() {
  local -n _rk_out="$1"
  printf -v _rk_out '%q ' "$RDT_RU_U" "$RDT_RU_SHELL" "${#RDT_RU_CMDS[@]}" ${RDT_RU_CMDS[@]+"${RDT_RU_CMDS[@]}"} \
    "${#RDT_RU_ARGV[@]}" ${RDT_RU_ARGV[@]+"${RDT_RU_ARGV[@]}"} ${RDT_RU_QUOTED[@]+"${RDT_RU_QUOTED[@]}"}
}

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_su_shell_run() {
  local prog="$RDT_RU_SHELL" name
  [[ -n "$prog" ]] || return 0
  name="${prog##*/}"
  name="${name,,}"
  name="${name%.exe}"
  case "$name" in
  bash | sh | zsh | dash | ksh | mksh) return 0 ;;
  *) ;;
  esac
  local -a av=(${RDT_RU_ARGV[@]+"${RDT_RU_ARGV[@]}"}) avq=(${RDT_RU_QUOTED[@]+"${RDT_RU_QUOTED[@]}"})
  HOOK_SEG_WORD_QUOTED=(0 ${avq[@]+"${avq[@]:1}"})
  rdt_check_segment "$prog" ${av[@]+"${av[@]:1}"}
}

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_short_cluster_arg() {
  local w="$2" ops opt="" k ch
  RDT_SC_NEXT=0
  case "$1" in
  sudo)
    ops="aCcDgpRrTtUu"
    opt="h"
    ;;
  env) ops="aCu" ;;
  prlimit)
    ops="po"
    opt="cdefilmnqrstuvxy"
    ;;
  systemd-run) ops="HMCupE" ;;
  chrt) ops="DPTUX" ;;
  flock) ops="wE" ;;
  unshare) ops="RwSGl" ;;
  nsenter)
    ops="tNSG"
    opt="muinpCUTrwW"
    ;;
  numactl) ops="iwpPcNCmSfoLMI" ;;
  *) return 1 ;;
  esac
  for ((k = 1; k < ${#w}; k++)); do
    ch="${w:k:1}"
    if [[ "$ops" == *"$ch"* ]]; then
      ((k == ${#w} - 1)) && RDT_SC_NEXT=1
      return 0
    fi
    [[ -n "$opt" && "$opt" == *"$ch"* ]] && return 1
  done
  return 1
}

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_long_takes_arg() {
  local name="$2" ops fls o nop=0
  [[ -n "$name" ]] || return 1
  case "$1" in
  sudo)
    ops="other-user auth-type close-from login-class chdir group host prompt chroot role command-timeout type user"
    fls="background preserve-env edit set-home login remove-timestamp list preserve-groups shell validate askpass bell help reset-timestamp no-update non-interactive stdin version"
    ;;
  env)
    ops="unset chdir argv0 env0-from quoting-style"
    fls="ignore-environment null block-signal default-signal ignore-signal list-signal-handling debug help version"
    ;;
  setpriv)
    ops="inh-caps ambient-caps ruid euid rgid egid reuid regid groups bounding-set securebits pdeathsig ptracer selinux-label apparmor-profile landlock-access landlock-rule list-landlock-rights seccomp-filter" # spellchecker:disable-line
    fls="dump nnp no-new-privs list-caps clear-groups keep-groups init-groups landlock-support list-landlock-access help reset-env version"
    ;;
  prlimit)
    ops="pid output"
    fls="as core cpu data fsize locks memlock msgqueue nice nofile nproc rss rtprio rttime sigpending stack version help noheadings raw verbose"
    ;;
  systemd-run)
    ops="host machine capsule unit property description slice expand-environment service-type uid gid nice working-directory root-directory setenv output json job-mode background path-property socket-property timer-property on-active on-boot on-startup on-unit-active on-unit-inactive on-calendar"
    fls="help version no-ask-password user system scope slice-inherit no-block remain-after-exit wait send-sighup same-dir same-root-dir tty pty pty-late pipe quiet verbose collect shell ignore-failure no-pager on-timezone-change on-clock-change"
    ;;
  timeout)
    ops="signal kill-after"
    fls="foreground preserve-status verbose help version"
    ;;
  nice)
    ops="adjustment"
    fls="help version"
    ;;
  ionice)
    ops="class classdata pid pgid uid"
    fls="ignore help version"
    ;;
  stdbuf)
    ops="input output error"
    fls="help version"
    ;;
  time)
    ops="format output"
    fls="append verbose portability quiet help version"
    ;;
  chrt)
    ops="sched-runtime sched-period sched-deadline clamp-min clamp-max"
    fls="all-tasks batch deadline deadline-overrun ext fifo idle pid help max other rr reset-on-fork reclaim-grub verbose version"
    ;;
  flock)
    ops="timeout wait conflict-exit-code start length fd"
    fls="shared exclusive unlock nonblocking nb close no-fork verbose fcntl help version"
    ;;
  unshare)
    ops="map-user map-users map-group map-groups owner propagation setgroups setuid setgid root wd monotonic boottime load-interp whitelist-env"
    fls="help version mount uts ipc net pid user cgroup time fork kill-child forward-signals mount-proc mount-binfmt map-root-user map-current-user map-auto map-subids keep-caps clear-env"
    ;;
  nsenter)
    ops="target net-socket setuid setgid"
    fls="all help version mount uts ipc net pid user cgroup time root wd wdns env no-fork join-cgroup preserve-credentials keep-caps user-parent follow-context"
    ;;
  numactl)
    ops="interleave weighted-interleave preferred preferred-many cpubind cpunodebind physcpubind membind shm file offset length shmmode shmid"
    fls="all show localalloc balancing hardware strict dump dump-nodes huge touch cpu-compress verify version"
    ;;
  chroot)
    ops="userspec groups"
    fls="skip-chdir help version"
    ;;
  *) return 1 ;;
  esac
  for o in $ops; do
    [[ "$o" == "$name" ]] && return 0
    [[ "$o" == "$name"* ]] && nop=$((nop + 1))
  done
  for o in $fls; do
    [[ "$o" == "$name" ]] && return 1
  done
  ((nop > 0))
}

rdt_abbr=0
rdt_resolved=0
MAX_RESOLVED_WALKS=256

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_resolved_walk() {
  rdt_resolved=$((rdt_resolved + 1))
  ((rdt_resolved > MAX_RESOLVED_WALKS)) && rdt_block "too-many-abbreviations"
  local rdt_abbr=1
  local -a saved_q=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"})
  rdt_check_segment "$@"
  HOOK_SEG_WORD_QUOTED=(${saved_q[@]+"${saved_q[@]}"})
}

# shellcheck disable=SC2016,SC2329  # literal `$` patterns; called from the operand loop
rdt_bare_var() {
  local s="$1" safe=1 unit inner i d n
  local re_plain='^\$([a-z_][a-z0-9_]*|[0-9]|[@*#?$!-])' re_safe='^[a-z_][a-z0-9_]*:\?'
  [[ "$s" == '$'* ]] || return 1
  while [[ -n "$s" ]]; do
    if [[ "$s" == '${'* ]]; then
      d=1
      n=${#s}
      for ((i = 2; i < n; i++)); do
        case "${s:i:1}" in
        '$')
          if [[ "${s:i+1:1}" == '{' ]]; then
            d=$((d + 1))
            i=$((i + 1))
          fi
          ;;
        '}')
          d=$((d - 1))
          ((d == 0)) && break
          ;;
        *) ;;
        esac
      done
      ((i < n)) || return 0
      unit="${s:0:i+1}"
      inner="${s:2:i-2}"
      [[ "$inner" =~ $re_safe ]] || safe=0
    elif [[ "$s" =~ $re_plain ]]; then
      unit="${BASH_REMATCH[0]}"
      safe=0
    else
      local rem="$s" re_br='\[[^]]*\]'
      while [[ "$rem" =~ $re_br ]]; do rem="${rem/"${BASH_REMATCH[0]}"/}"; done
      [[ "$rem" == *[[:alnum:]_]* ]] && return 1
      break
    fi
    s="${s:${#unit}}"
  done
  ((safe == 0))
}

RDT_NAME_SET_CALLS=0
RDT_NAME_SET_MAX=256
RDT_NAME_SET_FORBID_RE='(^|[^A-Za-z0-9_])IFS\+?=|(^|[;&|({'$'\n'']|(^|[[:space:]])(then|else|do|if|while|until|time|command|builtin|!))[[:space:]]*(eval|source)[[:space:]]|(^|[;&|({'$'\n''])[[:space:]]*\.[[:space:]]'
# shellcheck disable=SC2016,SC2329  # literal `$` patterns; called from rdt_led_by_unbound
rdt_name_set() {
  local n="$1" t="$COMMAND" v grounded=0 self_ref re ref
  local re_ref='\$\{?([A-Za-z_][A-Za-z0-9_]*)'
  RDT_NAME_SET_CALLS=$((RDT_NAME_SET_CALLS + 1))
  ((RDT_NAME_SET_CALLS > RDT_NAME_SET_MAX || $2 > 4)) && return 1
  [[ "$t" =~ $RDT_NAME_SET_FORBID_RE ]] && return 1
  local tq="${t//[\"\'\\]/}" rest seg b w head post r_eq=0 r_for=0 q_eq=0 q_for=0
  local -a words
  [[ "$tq" == *'${!'* ]] && return 1
  local re_set='(^|[^A-Za-z0-9_])(read|mapfile|readarray|getopts|select|printf|wait|declare|typeset|local|export|readonly)([[:blank:]][^;&|)'$'\n'']*|[;&|)'$'\n'']|$)'
  rest="$tq"
  while [[ "$rest" =~ $re_set ]]; do
    b="${BASH_REMATCH[2]}" seg="${BASH_REMATCH[3]}"
    rest="${rest#*"${BASH_REMATCH[0]}"}"
    [[ "$t" == *"\$'"* || "$t" == *'$"'* ]] && return 1
    if [[ "$b" == printf ]]; then
      re='(^|[[:blank:]])-[A-Za-z]*v[[:blank:]]*[^[:blank:]]*[$`{]'
      [[ "$seg" =~ $re ]] && return 1
      continue
    fi
    re='(^|[[:blank:]])-[A-Za-z]*n'
    [[ "$b" == declare || "$b" == typeset || "$b" == local ]] && [[ "$seg" =~ $re ]] && return 1
    read -ra words <<<"$seg"
    for w in ${words[@]+"${words[@]}"}; do
      [[ "$w" == ['<>']* || "$w" == [0-9]['<>']* ]] && continue
      [[ "${w%%=*}" == *[\$\`\{]* ]] && return 1
    done
  done
  re_set='(^|[^A-Za-z0-9_])(read|mapfile|readarray|getopts|select|printf|wait|declare|typeset|local|export|readonly)([^A-Za-z0-9_]|$)'
  local re_word_h='(^|[[:space:];&|(])$' re_for_h='(^|[[:space:];&|(])for[[:space:]]+$'
  local re_cmd_x='^[[:space:]]*[^[:space:]]*[$`]' re_opt_h='(^|[[:space:]])-$'
  post="$tq" head=""
  while [[ "$post" == *"$n"* ]]; do
    head+="${post%%"$n"*}"
    post="${post#*"$n"}"
    if [[ "$post" == [A-Za-z0-9_]* ]]; then
      :
    elif [[ "$head" == *[A-Za-z0-9_] ]]; then
      re='(^|[^A-Za-z0-9_])-[A-Za-z]+$'
      seg="${head##*[;&|($'\n']}"
      [[ "$head" =~ $re && ("$seg" =~ $re_set || "$seg" =~ $re_cmd_x) ]] && return 1
    elif [[ "$head" == *'$' || "$head" == *'${' || "$head" == *'${#' ]]; then
      [[ "$head" == *'${' && ("$post" == =* || "$post" == :=* || "$post" == '['*) ]] && return 1
    elif [[ "$head" =~ $re_opt_h ]]; then
      :
    elif [[ "$head" =~ $re_for_h ]]; then
      q_for=$((q_for + 1))
    elif [[ "$head" =~ $re_word_h && "$post" == =* ]]; then
      q_eq=$((q_eq + 1))
    else
      return 1
    fi
    head+="$n"
  done
  re="(^|[[:space:];&|(\"'])${n}=(\"[^\"]*\"|'[^']*'|[^[:space:];&|)\"']*)"
  while [[ "$t" =~ $re ]]; do
    v="${BASH_REMATCH[2]}"
    t="${t#*"${BASH_REMATCH[0]}"}"
    r_eq=$((r_eq + 1))
    [[ "${BASH_REMATCH[1]}" == [\"\'] && "$t" == [[:blank:]]* ]] && return 1
    [[ -z "$t" || "$t" == [[:space:]\;\&\|\)]* ]] || return 1
    [[ "$v" == *'('* || "$v" == *'`'* || "$v" == *\\* ]] && return 1
    [[ "$v" == [\"\']* ]] && v="${v:1:${#v}-2}"
    [[ "$v" == *[[:space:]]* ]] && return 1
    self_ref=0
    while [[ "$v" =~ $re_ref ]]; do
      ref="${BASH_REMATCH[1]}"
      v="${v/"${BASH_REMATCH[0]}"/}"
      if [[ "$ref" == "$n" ]]; then
        self_ref=1
      else
        rdt_name_set "$ref" $(($2 + 1)) || return 1
      fi
    done
    [[ "$v" == *\$* ]] && return 1
    ((self_ref)) || grounded=1
  done
  t="$COMMAND"
  re="(^|[[:space:];&|(\"'])for[[:space:]]+${n}([^A-Za-z0-9_][[:space:]]*(in[[:space:]]+[^;"$'\n'"]*)?|$)"
  while [[ "$t" =~ $re ]]; do
    v="${BASH_REMATCH[3]}"
    t="${t#*"${BASH_REMATCH[0]}"}"
    r_for=$((r_for + 1))
    [[ -n "$v" && "$v" != *[\`\"\'\\]* && "$v" != *'$('* ]] || return 1
    grounded=1
  done
  ((r_eq == q_eq && r_for == q_for)) || return 1
  ((grounded))
}

# shellcheck disable=SC2016,SC2329  # literal `$` patterns; called from the operand loop
rdt_led_by_unbound() {
  local name re_plain='^\$([A-Za-z_][A-Za-z0-9_]*|[0-9]|[@*#?$!-])' re_brace='^\$\{([A-Za-z_][A-Za-z0-9_]*)\}' re_safe='^\$\{[A-Za-z_][A-Za-z0-9_]*:\?'
  [[ "$1" =~ $re_safe ]] && return 1
  if [[ "$1" =~ $re_plain || "$1" =~ $re_brace ]]; then
    name="${BASH_REMATCH[1]}"
    [[ "$name" == "HOME" || "$name" == "TMPDIR" ]] && return 1
    [[ "$name" =~ ^[A-Za-z_] ]] || return 0
    rdt_name_set "$name" 0 && return 1
    return 0
  fi
  [[ "$1" == '${'* ]]
}

MAX_ORIGINS=32
MAX_TARGETS=512
MAX_GLOB=256
MAX_WORKTREES=256
RDT_DEADLINE=25
RDT_DEADLINE_ABS=50
RDT_T0=-1
rdt_cdpath=0
[[ -n "${CDPATH:-}" ]] && rdt_cdpath=1
rdt_cd_refuse=0
RDT_ARM=0
RDT_ORIGINS=()
RDT_ORIGIN_OVERFLOW=0
rdt_cd_unknown=0
rdt_in_subst=0
RDT_P_TEXT=()
RDT_P_Q=()
RDT_P_NORIG=()
RDT_P_UNK=()
RDT_P_REF=()
RDT_P_SUB=()
RDT_P_WT=()
RDT_WTRM=0
RDT_PS_BASHC=0
RDT_P_PSDOT=0
RDT_WIN=0
case "${OSTYPE:-}" in
msys* | cygwin* | win32) RDT_WIN=1 ;;
*) ;;
esac
RDT_DOTS=0
RDT_HOME="${HOME:-}"
RDT_HOME="${RDT_HOME//\\//}"

rdt_deadline() {
  ((RDT_T0 >= 0)) || RDT_T0=$SECONDS
  ((SECONDS - RDT_T0 < RDT_DEADLINE && SECONDS < RDT_DEADLINE_ABS)) || rdt_block "too-slow"
}

rdt_remaining_to() {
  rdt_deadline
  local __rr_a=$((RDT_DEADLINE - (SECONDS - RDT_T0))) __rr_b=$((RDT_DEADLINE_ABS - SECONDS))
  ((__rr_b < __rr_a)) && __rr_a=$__rr_b
  ((__rr_a < 1)) && __rr_a=1
  printf -v "$1" '%s' "$__rr_a"
}

rdt_is_unc() {
  [[ "$1" == //* && "$1" != ///* ]]
}

rdt_parent_to() {
  local __rpt_p="${2%/*}"
  [[ -z "$__rpt_p" ]] && __rpt_p=/
  [[ "$__rpt_p" =~ ^[A-Za-z]:$ ]] && __rpt_p="$__rpt_p/"
  printf -v "$1" '%s' "$__rpt_p"
}

rdt_nearest_to() {
  local __rn_a="$3"
  while [[ -n "$__rn_a" && "$__rn_a" == */* && "$__rn_a" != / && ! "$__rn_a" =~ ^[A-Za-z]:/$ ]]; do
    rdt_deadline
    if [[ "$2" == -d ]]; then [[ -d "$__rn_a" ]] && break; else [[ -e "$__rn_a" ]] && break; fi
    rdt_parent_to __rn_a "$__rn_a"
  done
  [[ "$2" == -d && ! -d "$__rn_a" ]] && __rn_a=""
  printf -v "$1" '%s' "$__rn_a"
}

rdt_lines_to() {
  local __rb_dest="$1" __rb_want="$2" __rb_out="" __rb_left __rb_rc=0
  shift 2
  rdt_remaining_to __rb_left
  rdt_bounded_to __rb_out "$__rb_left" "$@" || __rb_rc=$?
  ((__rb_rc == 124)) && rdt_block "too-slow"
  ((__rb_rc == 0)) || return 1
  mapfile -t "$__rb_dest" <<<"$__rb_out"
  local -n __rb_ref="$__rb_dest"
  ((${#__rb_ref[@]} == __rb_want))
}

rdt_glob_on() {
  RDT_NG_WAS=0
  shopt -q nullglob && RDT_NG_WAS=1
  shopt -s nullglob
}
rdt_glob_off() {
  ((RDT_NG_WAS)) || shopt -u nullglob
}

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_note_cdpath() {
  [[ "$1" == CDPATH=* ]] && rdt_cdpath=1
  return 0
}

rdt_is_abs() {
  [[ "$1" == /* || "$1" =~ ^[A-Za-z]:/ ]]
}

rdt_lex_to() {
  local __rl_p="$2" __rl_pre="" __rl_c __rl_out=""
  local -a __rl_st=()
  if [[ "$__rl_p" =~ ^([A-Za-z]:)(.*)$ ]]; then
    __rl_pre="${BASH_REMATCH[1]}"
    __rl_p="${BASH_REMATCH[2]}"
  elif rdt_is_unc "$__rl_p"; then
    __rl_pre="/"
  fi
  while :; do
    __rl_c="${__rl_p%%/*}"
    case "$__rl_c" in
    '' | .) ;;
    ..) ((${#__rl_st[@]})) && __rl_st=("${__rl_st[@]:0:${#__rl_st[@]}-1}") ;;
    *) __rl_st+=("$__rl_c") ;;
    esac
    [[ "$__rl_p" == */* ]] || break
    __rl_p="${__rl_p#*/}"
  done
  for __rl_c in ${__rl_st[@]+"${__rl_st[@]}"}; do __rl_out+="/$__rl_c"; done
  printf -v "$1" '%s' "$__rl_pre${__rl_out:-/}"
}

rdt_join_to() {
  if [[ -z "$3" ]]; then
    printf -v "$1" '%s' "$2"
  elif [[ "$2" == */ ]]; then
    printf -v "$1" '%s' "$2${3#/}"
  else
    printf -v "$1" '%s' "$2/${3#/}"
  fi
}

rdt_canon_to() {
  local __rc_p="${2//\\//}" __rc_lead=""
  if rdt_is_unc "$__rc_p"; then
    __rc_lead=/
    __rc_p="${__rc_p#/}"
  fi
  while [[ "$__rc_p" == *//* ]]; do __rc_p="${__rc_p//\/\//\/}"; done
  __rc_p="$__rc_lead$__rc_p"
  [[ "$__rc_p" == ?*/ && ! "$__rc_p" =~ ^[A-Za-z]:/$ ]] && __rc_p="${__rc_p%/}"
  hook::normalize_path_to __rc_p "$__rc_p"
  ((RDT_WIN)) && __rc_p="${__rc_p,,}"
  printf -v "$1" '%s' "$__rc_p"
}

rdt_root_like() {
  [[ "$1" == / || "$1" =~ ^[A-Za-z]:/?$ || "$1" =~ ^/[A-Za-z]$ ]]
}

# shellcheck disable=SC2016  # `$HOME` here is the literal text of the operand
rdt_place_to() {
  local __rp_t="${2//\\//}" __rp_q="$3" __rp_dir="" __rp_last __rp_pre __rp_rest __rp_slash=0
  RDT_PL_ABS=0
  RDT_PL_GLOB=0
  RDT_PL_MODE=leaf
  RDT_PL_ENUM=""
  RDT_PL_FULL=""
  RDT_PL_SLASH=0
  [[ -n "$__rp_t" ]] || return 1
  [[ "$__rp_t" == *$'\n'* ]] && return 2
  [[ "$__rp_t" =~ ^//[?.]/([A-Za-z]:/.*)$ ]] && __rp_t="${BASH_REMATCH[1]}"
  if ((__rp_q < 2 || __rp_q == 4)); then
    # shellcheck disable=SC2088  # matching the literal text, expanded by hand below
    case "$__rp_t" in
    '~' | '~/'*)
      [[ -n "$RDT_HOME" ]] || return 1
      __rp_t="$RDT_HOME${__rp_t#\~}"
      ;;
    '~+' | '~+/'*) __rp_t=".${__rp_t#\~+}" ;;
    '~'*) return 2 ;;
    *) ;;
    esac
  fi
  if ((__rp_q < 3)); then
    case "$__rp_t" in
    '$HOME' | '$HOME/'*)
      [[ -n "$RDT_HOME" ]] || return 1
      __rp_t="$RDT_HOME${__rp_t#\$HOME}"
      ;;
    '${HOME}' | '${HOME}/'*)
      [[ -n "$RDT_HOME" ]] || return 1
      __rp_t="$RDT_HOME${__rp_t#\$\{HOME\}}"
      ;;
    *) ;;
    esac
    case "$__rp_t" in
    *'$'* | *'`'*) return 1 ;;
    *) ;;
    esac
  fi
  if rdt_is_abs "$__rp_t"; then
    RDT_PL_ABS=1
  elif [[ "$__rp_t" =~ ^[A-Za-z]: ]]; then
    return 1
  fi
  while [[ "$__rp_t" == ?*/ ]]; do
    __rp_t="${__rp_t%/}"
    __rp_slash=1
  done
  RDT_PL_FULL="$__rp_t"
  RDT_PL_SLASH=$__rp_slash
  if ((__rp_q != 3)) && [[ "$__rp_t" == *[*?[]* ]]; then
    local __rp_c __rp_seen=0 __rp_ifs="$IFS"
    local -a __rp_cs=()
    IFS=/ read -r -a __rp_cs <<<"$__rp_t"
    IFS="$__rp_ifs"
    for __rp_c in ${__rp_cs[@]+"${__rp_cs[@]}"}; do
      [[ "$__rp_c" == *[*?[]* ]] && __rp_seen=1
      ((__rp_seen)) && [[ "$__rp_c" == .. ]] && return 2
    done
    RDT_PL_GLOB=1
    __rp_pre="${__rp_t%%[*?[]*}"
    [[ "$__rp_pre" == */* ]] && __rp_dir="${__rp_pre%/*}"
    __rp_rest="${__rp_t:${#__rp_dir}}"
    __rp_rest="${__rp_rest#/}"
    if [[ -z "$__rp_dir" ]]; then
      if ((RDT_PL_ABS)); then __rp_dir=/; else __rp_dir=.; fi
    fi
    [[ "$__rp_dir" =~ ^[A-Za-z]:$ ]] && __rp_dir="$__rp_dir/"
    if [[ "$__rp_rest" == */* ]]; then
      RDT_PL_MODE=deep
    else
      RDT_PL_MODE=whole
      ((__rp_slash)) && RDT_PL_ENUM="$__rp_rest"
    fi
    __rp_t="$__rp_dir"
  else
    __rp_last="${__rp_t##*/}"
    if ((__rp_slash)) || [[ "$__rp_last" == . || "$__rp_last" == .. ]]; then
      RDT_PL_MODE=whole
    fi
  fi
  printf -v "$1" '%s' "$__rp_t"
}

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_add_origin() {
  local t o c k have rc=0 q="$2"
  local -a add=() bases=()
  if [[ "$1" == *'{'* ]] && ((q != 2)); then
    rdt_cd_unknown=1
    return 0
  fi
  if ((q == 2)) && [[ "$1" != *'$'* && "$1" != *'`'* ]]; then q=3; fi
  rdt_place_to t "$1" "$q" || rc=$?
  if ((rc == 2)); then
    rdt_cd_refuse=1
    return 0
  fi
  if ((rc != 0)); then
    rdt_cd_unknown=1
    return 0
  fi
  if ((RDT_PL_GLOB)); then
    local full="$RDT_PL_FULL"
    if ((RDT_PL_ABS)); then bases=(""); else bases=(${RDT_ORIGINS[@]+"${RDT_ORIGINS[@]}"}); fi
    for o in ${bases[@]+"${bases[@]}"}; do
      rdt_glob_dirs "$o" "$full"
      if ((${#RDT_GLOB[@]} != 1)); then
        rdt_cd_refuse=1
        return 0
      fi
      rdt_lex_to c "${RDT_GLOB[0]}"
      add+=("$c")
    done
  elif ((RDT_PL_ABS)); then
    rdt_lex_to c "$t"
    add=("$c")
  else
    for o in ${RDT_ORIGINS[@]+"${RDT_ORIGINS[@]}"}; do
      rdt_lex_to c "$o/$t"
      add+=("$c")
    done
  fi
  for c in ${add[@]+"${add[@]}"}; do
    have=0
    for k in ${RDT_ORIGINS[@]+"${RDT_ORIGINS[@]}"}; do
      [[ "$k" == "$c" ]] && have=1 && break
    done
    ((have)) && continue
    if ((${#RDT_ORIGINS[@]} >= MAX_ORIGINS)); then
      RDT_ORIGIN_OVERFLOW=1
      return 0
    fi
    RDT_ORIGINS+=("$c")
  done
}

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_note_cd() {
  local verb="$1" off="$2"
  shift 2
  local -a a=("$@")
  local n=$# k=0 w
  if [[ "$verb" == popd ]]; then
    rdt_cd_unknown=1
    return 0
  fi
  while ((k < n)); do
    w="${a[k]}"
    if [[ "$w" == -- ]]; then
      k=$((k + 1))
      break
    fi
    [[ "$w" == -?* && ! "$w" =~ ^-[0-9]+$ ]] || break
    k=$((k + 1))
  done
  if ((k >= n)); then
    if [[ "$verb" == cd ]]; then
      rdt_add_origin '~' 0
    else
      rdt_cd_unknown=1
    fi
    return 0
  fi
  w="${a[k]}"
  case "$w" in
  - | [+-][0-9]*)
    rdt_cd_unknown=1
    return 0
    ;;
  *) ;;
  esac
  if ((rdt_cdpath)); then
    # shellcheck disable=SC2088  # matching the literal text of the operand
    case "${w//\\//}" in
    / | /* | [A-Za-z]:/* | . | .. | ./* | ../* | '~' | '~/'*) ;;
    *)
      rdt_cd_refuse=1
      return 0
      ;;
    esac
  fi
  rdt_add_origin "$w" "${HOOK_SEG_WORD_QUOTED[off + k]:-0}"
}

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_note_login() {
  local w
  for w in "$@"; do
    [[ "$w" == -- ]] && break
    if [[ "$w" == - || ("$w" == --l* && "login" == "${w#--}"*) ]] ||
      [[ "$w" =~ ^-[A-Za-z]+$ && "$w" == *l* ]]; then
      rdt_cd_unknown=1
      return 0
    fi
  done
}

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_note_launcher_dir() {
  case "$1" in
  env)
    case "$2" in
    -C | --c | --ch | --chd | --chdi | --chdir) (($3)) && rdt_add_origin "$4" "$6" ;;
    --c=* | --ch=* | --chd=* | --chdi=* | --chdir=*) rdt_add_origin "${2#*=}" "$5" ;;
    -C?*) rdt_add_origin "${2#-C}" "$5" ;;
    *) ;;
    esac
    ;;
  sudo)
    case "$2" in
    -D | --chdir) (($3)) && rdt_add_origin "$4" "$6" ;;
    --chdir=*) rdt_add_origin "${2#*=}" "$5" ;;
    -D?*) rdt_add_origin "${2#-D}" "$5" ;;
    --login) rdt_cd_unknown=1 ;;
    *) [[ "$2" =~ ^-[A-Za-z]+$ && "$2" == *i* ]] && rdt_cd_unknown=1 ;;
    esac
    ;;
  *) ;;
  esac
  return 0
}

declare -A RDT_RES=()

rdt_resolve_all() {
  local p i a rem r
  local -a todo=() res=() lines=()
  local -A seen=()
  for p in "$@"; do
    [[ -n "$p" && -z "${RDT_RES[$p]+x}" && -z "${seen[$p]+x}" ]] || continue
    seen[$p]=1
    if rdt_is_unc "$p" || { ((!RDT_WIN)) && [[ "$p" =~ ^[A-Za-z]: ]]; }; then
      rdt_lex_to r "$p"
      RDT_RES[$p]="$r"
      continue
    fi
    if ((RDT_WIN)); then
      rdt_deadline
      if [[ "$p" != *$'\n'* ]] && rdt_phys_to r "$p"; then
        RDT_RES[$p]="$r"
        continue
      fi
    fi
    todo+=("$p")
  done
  ((${#todo[@]})) || return 0
  local ok=0
  [[ "${todo[*]}" != *$'\n'* ]] && rdt_lines_to lines "${#todo[@]}" realpath -m -- "${todo[@]}" && ok=1
  for ((i = 0; i < ${#todo[@]}; i++)); do
    if ((ok)) && [[ -n "${lines[i]}" ]]; then
      res[i]="${lines[i]}"
      continue
    fi
    rdt_deadline
    rdt_lex_to a "${todo[i]}"
    rem=""
    rdt_split_existing a rem "$a"
    if hook::_physical_cached_to r "$a"; then
      rdt_join_to r "$r" "$rem"
    else
      rdt_join_to r "$a" "$rem"
    fi
    res[i]="$r"
  done
  for ((i = 0; i < ${#todo[@]}; i++)); do RDT_RES[${todo[i]}]="${res[i]}"; done
}

declare -A RDT_WMAP=()

rdt_winmap_all() {
  local p i a rem r
  local -a todo=() ancestors=() rems=() uniq=() lines=()
  local -A seen=() amap=()
  for p in "$@"; do
    [[ -n "$p" && -z "${RDT_WMAP[$p]+x}" && -z "${seen[$p]+x}" ]] || continue
    seen[$p]=1
    RDT_WMAP[$p]="$p"
    ((RDT_WIN)) || continue
    rdt_is_unc "$p" && continue
    todo+=("$p")
  done
  ((${#todo[@]})) || return 0
  command -v cygpath >/dev/null 2>&1 || return 0
  local -a slow=()
  for p in "${todo[@]}"; do
    rdt_deadline
    if [[ "$p" != *$'\n'* ]] && rdt_win_to r "$p"; then
      RDT_WMAP[$p]="$r"
    else
      slow+=("$p")
    fi
  done
  todo=(${slow[@]+"${slow[@]}"})
  ((${#todo[@]})) || return 0
  for ((i = 0; i < ${#todo[@]}; i++)); do
    rdt_deadline
    rdt_split_existing a rem "${todo[i]}"
    if [[ -z "$rem" && -L "$a" && "$a" == */?* ]]; then
      rem="/${a##*/}"
      rdt_parent_to a "$a"
    fi
    ancestors[i]="$a"
    rems[i]="$rem"
    if [[ -z "${amap[$a]+x}" ]]; then
      amap[$a]=""
      uniq+=("$a")
    fi
  done
  [[ "${uniq[*]}" != *$'\n'* ]] || return 0
  rdt_lines_to lines "${#uniq[@]}" cygpath -l -m -- "${uniq[@]}" || return 0
  for ((i = 0; i < ${#uniq[@]}; i++)); do amap[${uniq[i]}]="${lines[i]}"; done
  for ((i = 0; i < ${#todo[@]}; i++)); do
    a="${amap[${ancestors[i]}]}"
    [[ -n "$a" ]] || continue
    rdt_join_to r "$a" "${rems[i]}"
    RDT_WMAP[${todo[i]}]="$r"
  done
}

rdt_split_existing() {
  local __rs_a __rs_r
  rdt_nearest_to __rs_a -e "$3"
  __rs_r="${3:${#__rs_a}}"
  [[ -n "$__rs_r" && "$__rs_r" != /* ]] && __rs_r="/$__rs_r"
  printf -v "$1" '%s' "$__rs_a"
  printf -v "$2" '%s' "$__rs_r"
}

declare -A RDT_TREE=()
rdt_tree_to() {
  local o="$2" d="" out="" rc=0
  if [[ -n "${RDT_TREE[$o]+x}" ]]; then
    printf -v "$1" '%s' "${RDT_TREE[$o]}"
    return 0
  fi
  rdt_is_unc "$o" || rdt_nearest_to d -d "$o"
  if [[ -n "$d" ]]; then
    local left RDT_BOUND_UNSET=(GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_CEILING_DIRECTORIES GIT_DISCOVERY_ACROSS_FILESYSTEM)
    rdt_remaining_to left
    rdt_bounded_to out "$left" git --no-pager -c core.fsmonitor=false -c core.hooksPath=/dev/null \
      -C "$d" rev-parse --show-toplevel || rc=$?
    ((rc == 124)) && rdt_block "too-slow"
    ((rc == 0)) || out=""
  fi
  RDT_TREE[$o]="$out"
  printf -v "$1" '%s' "$out"
}

rdt_allowed() {
  local t="$1" deep="$2" link="${3:-0}" c i rest seg
  if ((deep == 0)); then
    [[ -n "$RDT_SPC" && "$t" == "$RDT_SPC" ]] && return 1
    for c in ${RDT_TEMPC[@]+"${RDT_TEMPC[@]}"}; do
      [[ "$t" == "$c" ]] && return 1
    done
  fi
  [[ -n "$RDT_SPC" && ("$t" == "$RDT_SPC"/* || (deep -eq 1 && "$t" == "$RDT_SPC")) ]] && return 0
  for c in ${RDT_TEMPC[@]+"${RDT_TEMPC[@]}"}; do
    [[ "$t" == "$c"/* || (deep -eq 1 && "$t" == "$c") ]] && return 0
  done
  [[ -n "$RDT_TREEC" && ("$t" == "$RDT_TREEC" || "$t" == "$RDT_TREEC"/*) ]] && return 0
  ((${#RDT_ALLOWC[@]} + ${#RDT_PDIRC[@]} + ${#RDT_SDIRC[@]})) || return 1
  { rdt_root_like "$t" || rdt_is_root "${t,,}"; } && return 1
  [[ "$t" == "$RDT_HOMEC" || "$RDT_HOMEC" == "$t"/* ]] && return 1
  for c in ${RDT_ALLOWC[@]+"${RDT_ALLOWC[@]}"}; do
    [[ "$t" == "$c"/* || (deep -eq 1 && "$t" == "$c") ]] && return 0
  done
  ((link)) && return 1
  for ((i = 0; i < ${#RDT_PDIRC[@]}; i++)); do
    c="${RDT_PDIRC[i]}"
    [[ "$t" == "$c"/* ]] || continue
    rest="${t#"$c"/}"
    [[ "$rest" != */* && "$rest" != *[.\ ] && "$rest" == "${RDT_PNAME[i]}"?* ]] && return 0
  done
  for ((i = 0; i < ${#RDT_SDIRC[@]}; i++)); do
    c="${RDT_SDIRC[i]}"
    [[ "$t" == "$c"/?*/* ]] || continue
    rest="${t#"$c"/}"
    seg="${rest%%/*}"
    rest="${rest#*/}"
    [[ "$seg" != *[.\ ] ]] || continue
    [[ "$rest" == "${RDT_SNAME[i]}"/* && "${rest##*/}" != *[.\ ] ]] && return 0
    [[ deep -eq 1 && "$rest" == "${RDT_SNAME[i]}" ]] && return 0
  done
  return 1
}

rdt_allowed_beside_tree() {
  local RDT_TREEC=""
  rdt_allowed "$1" 0 "$2"
}

rdt_within() {
  [[ "$1" == "$2" ]] && return 0
  if [[ "$2" == */ ]]; then [[ "$1" == "$2"?* ]]; else [[ "$1" == "$2"/* ]]; fi
}

rdt_pat_hits() {
  local n="$1" p="$2"
  if ((RDT_WIN)); then
    n="${n,,}"
    p="${p,,}"
  fi
  ((RDT_DOTS == 0)) && [[ "$n" == .* && "$p" != .* ]] && return 1
  # shellcheck disable=SC2053  # the pattern is meant to glob
  [[ "$n" == $p ]]
}

rdt_reaches() {
  local c="$1" p="$2" first
  ((${3:-0})) && return 1
  [[ "$p" != "$c" ]] || return 1
  rdt_within "$p" "$c" || return 1
  [[ -n "$4" ]] || return 0
  first="${p:${#c}}"
  first="${first#/}"
  rdt_pat_hits "${first%%/*}" "$4"
}

rdt_read_line_to() {
  local __rd_l=""
  [[ -f "$2" && -r "$2" ]] || return 1
  IFS= read -r -n 4096 __rd_l 2>/dev/null <"$2" || [[ -n "$__rd_l" ]] || return 1
  __rd_l="${__rd_l%$'\r'}"
  __rd_l="${__rd_l//\\//}"
  [[ -n "$__rd_l" ]] || return 1
  printf -v "$1" '%s' "$__rd_l"
}

rdt_worktrees() {
  local top="$1" line gd com f
  local -a regs=()
  RDT_WT=()
  [[ -n "$top" ]] || return 0
  if [[ -d "$top/.git" ]]; then
    com="$top/.git"
  elif rdt_read_line_to line "$top/.git" && [[ "$line" == "gitdir: "?* ]]; then
    gd="${line#gitdir: }"
    rdt_is_abs "$gd" || gd="$top/$gd"
    com="$gd"
    if rdt_read_line_to line "$gd/commondir"; then
      if rdt_is_abs "$line"; then com="$line"; else com="$gd/$line"; fi
    fi
  else
    return 0
  fi
  rdt_lex_to com "$com"
  [[ "$com" == ?*/.git ]] && RDT_WT+=("${com%/*}")
  rdt_glob_on
  regs=("$com"/worktrees/* "$com"/worktrees/.[!.]* "$com"/worktrees/..?*)
  rdt_glob_off
  for f in ${regs[@]+"${regs[@]:0:MAX_WORKTREES}"}; do
    rdt_deadline
    rdt_read_line_to line "$f/gitdir" || continue
    rdt_is_abs "$line" || line="$f/$line"
    rdt_lex_to line "$line"
    [[ "$line" == ?*/.git ]] && RDT_WT+=("${line%/*}")
  done
  return 0
}

rdt_protected() {
  local c="$1" real="$2" deep="$3" pat="$4" link="$5" p rest i t intmp free=0
  RDT_PROT=""
  if ((RDT_WIN)); then
    while [[ "$c" == */*[.\ ] && "${c##*/}" != . && "${c##*/}" != .. ]]; do c="${c%?}"; done
    while [[ "$real" == */*[.\ ] && "${real##*/}" != . && "${real##*/}" != .. ]]; do real="${real%?}"; done
  fi
  if ((${6:-0} && deep == 0)) && [[ -z "$pat" && "$c" != "$RDT_TREEC" ]]; then
    for p in ${RDT_PROT_B[@]+"${RDT_PROT_B[@]}"}; do
      [[ "$p" == "$c" ]] && rdt_allowed_beside_tree "$c" "$link" && free=1 && break
    done
  fi
  p="${c##*/}"
  if [[ "${p,,}" == .git ]]; then
    RDT_PROT="a .git"
    return 0
  fi
  if ((deep == 0 && link == 0 && free == 0)) && [[ -e "$real/.git" || -L "$real/.git" ]]; then
    if [[ -z "$pat" ]]; then
      RDT_PROT="a directory holding a .git"
      return 0
    fi
    if rdt_pat_hits .git "$pat"; then
      RDT_PROT="the .git inside it"
      return 0
    fi
  fi
  for ((i = 0; i < ${#RDT_PROT_B[@]}; i++)); do
    p="${RDT_PROT_B[i]}"
    [[ "$p" == "$c"* ]] || continue
    if [[ "$p" == "$c" ]]; then
      if [[ -z "$pat" ]] && ((deep == 0 && free == 0)); then
        RDT_PROT="${RDT_PROT_BW[i]}"
        return 0
      fi
      continue
    fi
    if rdt_reaches "$c" "$p" "$deep" "$pat"; then
      RDT_PROT="a directory holding ${RDT_PROT_BW[i]}"
      return 0
    fi
  done
  for ((i = 0; i < ${#RDT_PROT_A[@]}; i++)); do
    p="${RDT_PROT_A[i]}"
    if [[ "$c" == "$p" || "$c" == "$p"/* ]]; then
      RDT_PROT="${RDT_PROT_AW[i]}"
      return 0
    fi
    if [[ "$p" == "$c"* ]] && rdt_reaches "$c" "$p" "$deep" "$pat"; then
      RDT_PROT="a directory holding ${RDT_PROT_AW[i]}"
      return 0
    fi
  done
  for p in ${RDT_CLAUDEC[@]+"${RDT_CLAUDEC[@]}"}; do
    if [[ "$p" == "$c"* ]] && rdt_reaches "$c" "$p" "$deep" "$pat"; then
      RDT_PROT="a directory holding Claude Code's temp tree, where other sessions keep their scratchpads"
      return 0
    fi
    [[ "$c" == "$p" || "$c" == "$p"/* ]] || continue
    [[ -n "$RDT_SPC" ]] && rdt_within "$c" "$RDT_SPC" && continue
    intmp=0
    for t in ${RDT_TEMPC[@]+"${RDT_TEMPC[@]}"}; do
      if rdt_within "$t" "$p" && rdt_within "$c" "$t"; then
        intmp=1
        break
      fi
    done
    rest="${c:${#p}}"
    rest="${rest#/}"
    if ((intmp == 0)) && { [[ "$rest" != */* ]] ||
      { [[ "$rest" != */*/* ]] && { [[ -z "$pat" ]] || rdt_pat_hits scratchpad "$pat"; }; }; }; then
      RDT_PROT="Claude Code's temp tree, where sessions keep their scratchpads"
      return 0
    fi
    [[ "$rest" == */*/* ]] || continue
    rest="${rest#*/}"
    rest="${rest#*/}"
    if [[ "${rest%%/*}" == scratchpad ]]; then
      RDT_PROT="another session's scratchpad"
      return 0
    fi
  done
  return 1
}

# shellcheck disable=SC2206  # the pattern is meant to glob; IFS is empty so it cannot split
rdt_enum_links() {
  local dir="$1" pat="$2" m IFS=
  local -a all=()
  RDT_LINKS=()
  rdt_glob_on
  all=("$dir"/$pat)
  rdt_glob_off
  ((${#all[@]} > MAX_GLOB)) && rdt_block "too-many-glob-entries"
  for m in ${all[@]+"${all[@]}"}; do
    [[ -L "$m" && -d "$m" ]] && RDT_LINKS+=("$m")
  done
  return 0
}

# shellcheck disable=SC2206  # the component is meant to glob; IFS is empty so it cannot split
rdt_glob_dirs() {
  local pat="$2" c d m total=0 IFS=
  local -a cur=() next=() comps=() hits=()
  RDT_GLOB=()
  if [[ -n "$1" ]]; then
    cur=("${1%/}")
  elif [[ "$pat" =~ ^([A-Za-z]:)/(.*)$ ]]; then
    cur=("${BASH_REMATCH[1]}")
    pat="${BASH_REMATCH[2]}"
  else
    cur=("")
  fi
  IFS=/ read -r -a comps <<<"$pat"
  IFS=
  rdt_glob_on
  for c in ${comps[@]+"${comps[@]}"}; do
    [[ -n "$c" ]] || continue
    next=()
    for d in ${cur[@]+"${cur[@]}"}; do
      rdt_deadline
      if [[ "$c" == *[*?[]* ]]; then
        hits=("$d"/$c)
        total=$((total + ${#hits[@]}))
        ((total > MAX_GLOB)) && rdt_block "too-many-glob-entries"
        for m in ${hits[@]+"${hits[@]}"}; do
          [[ -d "$m" ]] && next+=("$m")
        done
      elif [[ -d "$d/$c" ]]; then
        next+=("$d/$c")
      fi
    done
    cur=(${next[@]+"${next[@]}"})
    ((${#cur[@]})) || break
  done
  rdt_glob_off
  RDT_GLOB=(${cur[@]+"${cur[@]}"})
  return 0
}

# shellcheck disable=SC2034  # the arrays belong to the caller
rdt_add_pair() {
  local p="$1" mode="$2" last="" key
  [[ "$mode" == leaf && "${wtm:-0}" == 1 ]] && mode=whole
  if [[ "$mode" == leaf ]]; then
    last="${p##*/}"
    rdt_parent_to p "$p"
  else
    [[ -z "$p" ]] && p=/
    [[ "$p" =~ ^[A-Za-z]:$ ]] && p="$p/"
  fi
  key="$mode|$p|$last|$3|${5:-}|${wtm:-0}"
  [[ -n "${tseen[$key]+x}" ]] && return 0
  tseen[$key]=1
  tp+=("$p")
  tn+=("$last")
  if [[ "$mode" == deep ]]; then td+=(1); else td+=(0); fi
  te+=("$3")
  tw+=("$4")
  tg+=("${5:-}")
  tx+=("${wtm:-0}")
  ((${#tp[@]} > MAX_TARGETS)) && rdt_block "too-many-targets"
  return 0
}

rdt_add_literal() {
  local t rc=0
  rdt_place_to t "$1" 3 || rc=$?
  ((rc == 2)) && rdt_block "unplaceable" "'$2'"
  ((rc == 0)) || return 0
  rdt_add_pair "$t" "$RDT_PL_MODE" "" "$2"
}

rdt_compared_to() {
  rdt_canon_to "$1" "${RDT_WMAP[${RDT_RES[$2]}]}"
}

rdt_allowed_root_to() {
  local __ar_t
  [[ "${RDT_RES[$2]}" != / ]] || return 1
  rdt_compared_to __ar_t "$2"
  { rdt_root_like "$__ar_t" || rdt_is_root "${__ar_t,,}" || [[ "$__ar_t" == "$RDT_HOMEC" ]]; } && return 1
  printf -v "$1" '%s' "$__ar_t"
}

rdt_judge_pending() {
  local np=${#RDT_P_TEXT[@]}
  ((np)) || return 0
  ((RDT_ORIGIN_OVERFLOW)) && rdt_block "too-many-origins"
  local k m no unk cdp t p sp c rc mode enum full slash abs glob base g t2 word lastc e gp wtm wtany=0
  local -a tp=() tn=() td=() te=() tw=() tg=() tx=() gl=()
  local -A tseen=()
  for ((k = 0; k < np; k++)); do
    rdt_deadline
    word="${RDT_P_TEXT[k]}"
    wtm="${RDT_P_WT[k]:-0}"
    ((wtm)) && wtany=1
    rc=0
    rdt_place_to t "$word" "${RDT_P_Q[k]}" || rc=$?
    ((rc == 2)) && rdt_block "unplaceable" "'$word'"
    ((rc == 0)) || continue
    if ((RDT_P_SUB[k])); then
      no=${#RDT_ORIGINS[@]}
      unk=$rdt_cd_unknown
      cdp=$rdt_cd_refuse
    else
      no=${RDT_P_NORIG[k]}
      unk=${RDT_P_UNK[k]}
      cdp=${RDT_P_REF[k]}
    fi
    if ((RDT_PL_ABS == 0)); then
      ((cdp)) && rdt_block "unplaceable" "'$word' (after a cd this guard cannot follow to one directory: CDPATH is set, its glob matched no directory or several, or it names ~name or a \`..\` after a glob)"
      ((unk)) && continue
    fi
    mode="$RDT_PL_MODE"
    enum="$RDT_PL_ENUM"
    full="$RDT_PL_FULL"
    slash="$RDT_PL_SLASH"
    abs="$RDT_PL_ABS"
    glob="$RDT_PL_GLOB"
    for ((m = 0; m < no; m++)); do
      if ((abs)); then p="$t"; else rdt_join_to p "${RDT_ORIGINS[m]}" "$t"; fi
      if ((glob)); then
        if ((abs)); then t2="$full"; else rdt_join_to t2 "${RDT_ORIGINS[m]}" "$full"; fi
        ((slash)) && t2+=/
        rdt_add_literal "$t2" "$word"
      fi
      if [[ "$mode" != deep ]]; then
        gp=""
        ((glob)) && gp="${full##*/}"
        rdt_add_pair "$p" "$mode" "$enum" "$word" "$gp"
        continue
      fi
      base=""
      ((abs)) || base="${RDT_ORIGINS[m]}"
      rdt_glob_dirs "$base" "${full%/*}"
      gl=(${RDT_GLOB[@]+"${RDT_GLOB[@]}"})
      if ((${#gl[@]} == 0)); then
        rdt_add_pair "$p" deep "" "$word"
        continue
      fi
      lastc="${full##*/}"
      for g in "${gl[@]}"; do
        if [[ "$lastc" == *[*?[]* ]]; then
          e=""
          ((slash)) && e="$lastc"
          rdt_add_pair "$g" whole "$e" "$word" "$lastc"
        else
          t2="$g/$lastc"
          ((slash)) && t2+=/
          rdt_add_literal "$t2" "$word"
        fi
      done
    done
  done
  ((${#tp[@]} || wtany)) || return 0

  sp=""
  if hook::jq_fields "$INPUT" '.scratchpad_dir'; then
    ((HOOK_JQ_FIELDS_NUL)) && rdt_block "nul-field" "scratchpad_dir"
    sp="${HOOK_JQ_FIELDS[0]:-}"
    sp="${sp//\\//}"
  fi
  rdt_is_abs "$sp" || sp=""
  hook::_temp_root_candidates --no-drive
  local -a temps=()
  for c in ${_HOOK_TEMP_CANDS[@]+"${_HOOK_TEMP_CANDS[@]}"}; do temps+=("${c//\\//}"); done
  local tree=""
  rdt_tree_to tree "${RDT_ORIGINS[0]}"
  rdt_deadline
  local -a allow=() pdir=() pname=() sdir=() sname=()
  local home="${HOME:-}" roots="${CLAUDE_PLUGIN_OPTION_BLOCK_ROOT_DELETE_TARGET_ALLOWED_ROOTS:-}" x pfx sfx
  home="${home//\\//}"
  if ! rdt_is_abs "$home" || rdt_is_unc "$home"; then roots=""; fi
  while [[ -n "$roots" ]]; do
    c="${roots%%,*}"
    if [[ "$c" == "$roots" ]]; then roots=""; else roots="${roots#*,}"; fi
    [[ "$c" != *[$'\n\r']* ]] || continue
    c="${c#"${c%%[![:space:]]*}"}"
    c="${c%"${c##*[![:space:]]}"}"
    c="${c//\\//}"
    pfx=""
    sfx=""
    if [[ "$c" == */?*'*' ]]; then
      pfx="${c##*/}"
      pfx="${pfx%'*'}"
      c="${c%/*}"
      [[ -n "$pfx" && "$pfx" != *[*?[]* ]] || continue
    elif [[ "$c" == */'*'/?* ]]; then
      sfx="${c##*/}"
      c="${c%/*}"
      c="${c%/'*'}"
      [[ "$sfx" != *[*?[]* && "$sfx" != . && "$sfx" != .. ]] || continue
    fi
    x="${c//[^\/]/}"
    [[ -n "$c" && "$c" != *[$'\n\r*?[']* && "/$c/" != */../* ]] || continue
    ((${#c} + ${#pfx} + ${#sfx} <= MAX_OPERAND_LEN && ${#x} <= MAX_OPERAND_DEPTH)) || continue
    if ! rdt_is_abs "$c" || rdt_is_unc "$c"; then continue; fi
    ((RDT_WIN)) || [[ ! "$c" =~ ^[A-Za-z]: ]] || continue
    if [[ -n "$pfx" ]]; then
      ((RDT_WIN)) && pfx="${pfx,,}"
      pdir+=("$c")
      pname+=("$pfx")
    elif [[ -n "$sfx" ]]; then
      ((RDT_WIN)) && sfx="${sfx,,}"
      sdir+=("$c")
      sname+=("$sfx")
    else
      allow+=("$c")
    fi
  done
  local hcl=""
  if rdt_is_abs "$home" && ! rdt_is_unc "$home"; then hcl="${home%/}/.claude"; fi
  ((${#allow[@]} + ${#pdir[@]} + ${#sdir[@]})) || home=""

  rdt_worktrees "$tree"
  local -a wts=(${RDT_WT[@]+"${RDT_WT[@]}"}) prot=()
  if ((wtany)); then
    wtm=1
    for ((k = 0; k < np; k++)); do
      ((${RDT_P_WT[k]:-0})) || continue
      word="${RDT_P_TEXT[k]//\\//}"
      while [[ "$word" == ?*/ ]]; do word="${word%/}"; done
      [[ -n "$word" ]] || continue
      g=0
      ((${RDT_P_Q[k]:-0} != 2)) && [[ "$word" == *[*?[]* ]] && g=1
      for c in ${wts[@]+"${wts[@]}"}; do
        # shellcheck disable=SC2053  # the operand is meant to glob when g is 1
        if [[ "${c,,}" == "${word,,}" || "${c,,}" == */"${word,,}" ]] ||
          { ((g)) && [[ "${c,,}" == ${word,,} || "${c,,}" == */${word,,} ]]; }; then
          rdt_add_pair "$c" whole "" "${RDT_P_TEXT[k]}"
        fi
      done
    done
  fi
  ((${#tp[@]})) || return 0
  local trees="${CLAUDE_PLUGIN_OPTION_BLOCK_ROOT_DELETE_TARGET_PROTECTED_TREES:-}"
  while [[ -n "$trees" ]]; do
    c="${trees%%,*}"
    if [[ "$c" == "$trees" ]]; then trees=""; else trees="${trees#*,}"; fi
    [[ "$c" != *[$'\n\r']* ]] || continue
    c="${c#"${c%%[![:space:]]*}"}"
    c="${c%"${c##*[![:space:]]}"}"
    c="${c//\\//}"
    x="${c//[^\/]/}"
    [[ -n "$c" && "$c" != *[*?[]* && "/$c/" != */../* ]] || continue
    ((${#c} <= MAX_OPERAND_LEN && ${#x} <= MAX_OPERAND_DEPTH)) || continue
    rdt_is_abs "$c" || continue
    ((RDT_WIN)) || [[ ! "$c" =~ ^[A-Za-z]: ]] || continue
    prot+=("$c")
  done

  rdt_resolve_all ${tp[@]+"${tp[@]}"} ${temps[@]+"${temps[@]}"} "$sp" "$tree" ${allow[@]+"${allow[@]}"} ${pdir[@]+"${pdir[@]}"} \
    ${sdir[@]+"${sdir[@]}"} "$home" \
    ${wts[@]+"${wts[@]}"} "$hcl" ${prot[@]+"${prot[@]}"}
  local n0=${#tp[@]} l
  for ((k = 0; k < n0; k++)); do
    [[ -n "${te[k]}" ]] || continue
    rdt_deadline
    rdt_enum_links "${RDT_RES[${tp[k]}]}" "${te[k]}"
    for l in ${RDT_LINKS[@]+"${RDT_LINKS[@]}"}; do
      tp+=("$l")
      tn+=("")
      td+=(0)
      tw+=("${tw[k]}")
      tg+=("")
      tx+=("${tx[k]}")
      ((${#tp[@]} > MAX_TARGETS)) && rdt_block "too-many-targets"
    done
  done
  ((${#tp[@]} > n0)) && rdt_resolve_all "${tp[@]:n0}"
  rdt_deadline
  local -a targets=()
  for ((k = 0; k < ${#tp[@]}; k++)); do
    rdt_join_to p "${RDT_RES[${tp[k]}]}" "${tn[k]}"
    targets[k]="$p"
  done
  local -a others=()
  for c in ${temps[@]+"${temps[@]}"} "$sp" "$tree" ${allow[@]+"${allow[@]}"} ${pdir[@]+"${pdir[@]}"} \
    ${sdir[@]+"${sdir[@]}"} "$home" ${wts[@]+"${wts[@]}"} "$hcl" ${prot[@]+"${prot[@]}"}; do
    [[ -n "$c" ]] && others+=("${RDT_RES[$c]}")
  done
  rdt_winmap_all ${targets[@]+"${targets[@]}"} ${others[@]+"${others[@]}"}
  rdt_deadline
  RDT_TEMPC=()
  for c in ${temps[@]+"${temps[@]}"}; do
    rdt_compared_to t "$c"
    rdt_root_like "$t" || RDT_TEMPC+=("$t")
  done
  RDT_SPC=""
  if [[ -n "$sp" ]]; then
    rdt_compared_to c "$sp"
    for t in ${RDT_TEMPC[@]+"${RDT_TEMPC[@]}"}; do
      [[ "$c" == "$t"/* ]] && RDT_SPC="$c" && break
    done
  fi
  RDT_TREEC=""
  if [[ -n "$tree" ]]; then
    rdt_compared_to t "$tree"
    rdt_root_like "$t" || RDT_TREEC="$t"
  fi
  RDT_ALLOWC=()
  RDT_PDIRC=()
  RDT_PNAME=()
  RDT_SDIRC=()
  RDT_SNAME=()
  RDT_HOMEC=""
  if [[ -n "$home" ]]; then
    rdt_compared_to RDT_HOMEC "$home"
    for c in ${allow[@]+"${allow[@]}"}; do
      rdt_allowed_root_to t "$c" && RDT_ALLOWC+=("$t")
    done
    for ((k = 0; k < ${#pdir[@]}; k++)); do
      rdt_allowed_root_to t "${pdir[k]}" || continue
      RDT_PDIRC+=("$t")
      RDT_PNAME+=("${pname[k]}")
    done
    for ((k = 0; k < ${#sdir[@]}; k++)); do
      rdt_allowed_root_to t "${sdir[k]}" || continue
      RDT_SDIRC+=("$t")
      RDT_SNAME+=("${sname[k]}")
    done
  fi
  RDT_PROT_B=()
  RDT_PROT_BW=()
  if [[ -n "$RDT_TREEC" ]]; then
    RDT_PROT_B+=("$RDT_TREEC")
    RDT_PROT_BW+=("the git toplevel of the working directory")
  fi
  for c in ${wts[@]+"${wts[@]}"}; do
    rdt_compared_to t "$c"
    rdt_root_like "$t" && continue
    RDT_PROT_B+=("$t")
    RDT_PROT_BW+=("a worktree root git has registered")
  done
  RDT_PROT_A=()
  RDT_PROT_AW=()
  if [[ -n "$hcl" ]]; then
    rdt_compared_to t "$hcl"
    RDT_PROT_A+=("$t")
    # shellcheck disable=SC2088  # the label names the directory, nothing expands it
    RDT_PROT_AW+=("~/.claude")
  fi
  for c in ${prot[@]+"${prot[@]}"}; do
    rdt_compared_to t "$c"
    { rdt_root_like "$t" || rdt_is_root "${t,,}"; } && continue
    RDT_PROT_A+=("$t")
    RDT_PROT_AW+=("a tree in block_root_delete_target_protected_trees")
  done
  RDT_DOTS=0
  [[ "$TOOL_NAME" == PowerShell ]] && ((RDT_P_PSDOT)) && RDT_DOTS=1
  case "${COMMAND,,}" in
  *dotglob* | *globignore* | *globdots* | *glob_dots*) RDT_DOTS=1 ;;
  *) ;;
  esac
  RDT_CLAUDEC=()
  if [[ "$RDT_SPC" == */scratchpad ]]; then
    t="${RDT_SPC%/*}"
    t="${t%/*}"
    t="${t%/*}"
    [[ "${t##*/}" == claude || "${t##*/}" == claude-?* ]] && RDT_CLAUDEC+=("$t")
  fi
  for t in ${RDT_TEMPC[@]+"${RDT_TEMPC[@]}"}; do
    if ((RDT_WIN)); then RDT_CLAUDEC+=("${t%/}/claude"); else RDT_CLAUDEC+=("${t%/}/claude-$UID"); fi
  done
  for ((k = 0; k < ${#tp[@]}; k++)); do
    rdt_deadline
    p="${RDT_WMAP[${targets[k]}]}"
    rdt_canon_to c "$p"
    l=0
    [[ -L "${targets[k]}" ]] && l=1
    [[ ! -e "${targets[k]}" && "${tw[k]}" =~ [/\\]\.?$ ]] && l=1
    if rdt_protected "$c" "${targets[k]}" "${td[k]}" "${tg[k]}" "$l" "${tx[k]}"; then
      rdt_block "protected-tree" "'$p' (the operand '${tw[k]}'), $RDT_PROT"
      continue
    fi
    rdt_allowed "$c" "${td[k]}" "$l" || rdt_block "outside-tree" "'$p' (the operand '${tw[k]}')"
  done
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_sink_check() {
  local k=$(($1 + 1)) b w c=0 s=0 last=$((n - 1)) split=0 open=0
  local -a herestr=() q0=()
  ((${rdt_flat:-1})) || open=1
  [[ "${words[last]}" == *'$' && "${HOOK_SEG_WORD_QUOTED[last]:-0}" == 0 ]] && split=$open
  if (($1 == last && split)); then
    rdt_sink=1
    return 0
  fi
  b="${words[$1]##*/}"
  b="${b,,}"
  b="${b%.exe}"
  case "$b" in
  eval)
    ((open && (k >= n || split))) && rdt_sink=1
    return 0
    ;;
  source | .) ;;
  bash | sh | zsh | dash | ksh | mksh)
    while ((k < n)); do
      w="${words[k]}"
      case "$w" in
      -- | -)
        k=$((k + 1))
        break
        ;;
      -o | +o | -O | +O | --rcfile | --init-file) k=$((k + 2)) ;;
      [-+]?*)
        if [[ "$w" =~ ^-[A-Za-z]+$ ]]; then
          [[ "$w" == *c* ]] && c=1
          [[ "$w" == *s* ]] && s=1
        fi
        k=$((k + 1))
        ;;
      *) break ;;
      esac
    done
    if ((c)); then
      ((open && (k >= n || (split && k == last)))) && rdt_sink=1
      return 0
    fi
    ;;
  *) return 0 ;;
  esac
  ((s || k >= n)) || [[ "${words[k]}" == /dev/stdin || "${words[k]}" == /dev/fd/0 || "${words[k]}" == /proc/self/fd/0 ]] || return 0
  ((${rdt_dec_feed:-0})) && rdt_block "decoder-sink"
  ((open && k >= n)) && rdt_sink=1
  local r hd prog="" has=0 dec=0
  rdt_stdin_redir
  r=$RDT_IN_R hd=$RDT_IN_HD
  if ((r >= 0)); then
    case "${HOOK_SEG_REDIR_OP[r]}" in
    '<<' | '<<-') [[ -n "${rdt_hd_at-}" ]] && rdt_hd_prog "$((rdt_hd_at + hd))" "${HOOK_SEG_REDIR_TARGET[r]-}" sh ;;
    '<<<')
      prog="${HOOK_SEG_REDIR_TARGET[r]-}"
      has=1
      ;;
    *) ;;
    esac
  else
    case "${rdt_text_feed:-}" in
    [et]*)
      prog="${rdt_text_feed:1}"
      has=1
      [[ "$rdt_text_feed" == e* ]] && dec=1
      ;;
    h*)
      w="${rdt_text_feed:1}"
      rdt_hd_prog "${w%%:*}" "${w#*:}" sh
      ;;
    x) rdt_block "eval-too-long" ;;
    *) ;;
    esac
  fi
  for ((c = 0; c < ${#HOOK_SEG_REDIR_OP[@]}; c++)); do
    ((c == r && has)) && continue
    [[ "${HOOK_SEG_REDIR_OP[c]}" == '<<<' && "${HOOK_SEG_REDIR_FD[c]:-0}" == 0 ]] || continue
    # shellcheck disable=SC2016  # a literal `$(` and backtick, not an expansion
    case "${HOOK_SEG_REDIR_TARGET[c]}" in
    *'$('* | *'`'*) herestr+=("${HOOK_SEG_REDIR_TARGET[c]}") ;;
    *) ;;
    esac
  done
  ((${#herestr[@]} || has)) || return 0
  q0=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"})
  for w in ${herestr[@]+"${herestr[@]}"}; do
    rdt_scanned=$((rdt_scanned + ${#w}))
    ((rdt_scanned > MAX_COMMAND_LEN)) && rdt_block "eval-too-long"
    rdt_parse "$w"
  done
  ((has)) && rdt_shell_prog "$prog" "$dec"
  HOOK_SEG_WORD_QUOTED=(${q0[@]+"${q0[@]}"})
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_sink_check and rdt_interp_check
rdt_stdin_redir() {
  local c nh=0
  RDT_IN_R=-1 RDT_IN_HD=-1
  for ((c = 0; c < ${#HOOK_SEG_REDIR_OP[@]}; c++)); do
    [[ "${HOOK_SEG_REDIR_OP[c]}" == '<<' || "${HOOK_SEG_REDIR_OP[c]}" == '<<-' ]] && nh=$((nh + 1))
    [[ "${HOOK_SEG_REDIR_OP[c]}" == '<'* && "${HOOK_SEG_REDIR_FD[c]:-0}" == 0 ]] || continue
    RDT_IN_R=$c
    RDT_IN_HD=$((nh - 1))
  done
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_sink_check and rdt_interp_check
rdt_hd_prog() {
  rdt_hd_lang[$1]="$3"
  rdt_hd_st[$1]="${#RDT_ORIGINS[@]} $rdt_cd_unknown $rdt_cd_refuse $2"
}

# shellcheck disable=SC2329  # invoked from rdt_sink_check and rdt_ix_heredocs
rdt_shell_prog() {
  local rdt_text_feed="" rdt_seg_feed=none rdt_dec_feed=0 t="$1" d
  # shellcheck disable=SC2034  # read by hook::_bps_refuse through dynamic scope
  local HOOK_BPS_SPAN="$RDT_BPS_SPAN"
  rdt_scanned=$((rdt_scanned + ${#t}))
  ((rdt_scanned > MAX_COMMAND_LEN)) && rdt_block "eval-too-long"
  rdt_scan_substitutions "$t" nested
  rdt_parse "$t"
  if (($2)) && [[ "$t" == *\\* ]]; then
    printf -v d '%b' "$t"
    [[ "$d" == "$t" ]] || rdt_shell_prog "$d" 0
  fi
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_check_segment
rdt_env_split_check() {
  hook::env_s_split "$1"
  HOOK_SEG_WORD_QUOTED=()
  rdt_check_segment ${HOOK_ENV_S_WORDS[@]+"${HOOK_ENV_S_WORDS[@]}"} \
    ${words[@]+"${words[@]:$2}"}
}

# shellcheck disable=SC2329  # invoked from rdt_check_segment and rdt_watch_check
rdt_parse_words() {
  local j text
  local -a ev=()
  for ((j = $1; j < n; j++)); do
    if [[ -z "${words[j]}" ]] && ((${HOOK_SEG_WORD_QUOTED[j]:-0} == 1)); then
      # shellcheck disable=SC1003  # a literal backslash character, not a quote escape
      ev+=('\')
    else
      ev+=("${words[j]}")
    fi
  done
  text="${ev[*]}"
  rdt_scanned=$((rdt_scanned + ${#text}))
  ((rdt_scanned > MAX_COMMAND_LEN)) && rdt_block "eval-too-long"
  rdt_parse "$text"
}

# shellcheck disable=SC2329  # invoked from rdt_segment, the hook::bash_parse_segments callback
rdt_check_segment() {
  local rdt_depth=$((rdt_depth + 1))
  ((rdt_depth > MAX_SEGMENT_DEPTH)) && rdt_block "nesting-too-deep-launcher"
  ((RDT_T0 >= 0)) && rdt_deadline
  if ((rdt_depth > 1)); then
    rdt_segments=$((rdt_segments + 1))
    ((rdt_segments > MAX_SEGMENTS)) && rdt_block "too-many-readings"
  fi
  local -a words=("$@")
  local n=$# i=0 j w base sval optarg consume_bare
  local abbr_forked=0

  while ((i < n)); do
    w="${words[i]}"
    if [[ "$w" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      rdt_note_cdpath "$w"
      i=$((i + 1))
      continue
    fi
    case "$w" in
    '{' | '}' | '!' | then | do | else | elif | if | while | until)
      i=$((i + 1))
      continue
      ;;
    function)
      i=$((i + 2))
      continue
      ;;
    coproc)
      i=$((i + 1))
      if ((i + 1 < n)) && [[ "${words[i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        case "${words[i + 1]}" in
        '{' | if | while | until | for | case | select | '[[') i=$((i + 1)) ;;
        *) ;;
        esac
      fi
      continue
      ;;
    *) ;;
    esac
    base="${w##*/}"
    base="${base,,}"
    base="${base%.exe}"
    consume_bare=0
    case "$base" in
    sudo | doas) optarg=" -u --user -g --group -p --prompt -C --close-from -D --chdir -r --role -t --type -T --command-timeout -U --other-user -h --host " ;;
    taskset)
      optarg=""
      consume_bare=1
      ;;
    chrt)
      optarg=" -D --sched-deadline -P --sched-period -T --sched-runtime -U --clamp-min -X --clamp-max "
      consume_bare=1
      ;;
    flock)
      optarg=" -w --wait --timeout -E --conflict-exit-code --start --length --fd "
      consume_bare=1
      ;;
    unshare) optarg=" -R --root -w --wd -S --setuid -G --setgid -l --load-interp --map-user --map-users --map-group --map-groups --owner --propagation --setgroups --monotonic --boottime --whitelist-env " ;;
    nsenter) optarg=" -t --target -N --net-socket -S --setuid -G --setgid " ;;
    numactl) optarg=" -i --interleave -w --weighted-interleave -p --preferred -P --preferred-many -c --cpubind -N --cpunodebind -C --physcpubind -m --membind -S --shm -f --file -o --offset -L --length -M --shmmode -I --shmid " ;;
    chroot)
      optarg=" --userspec --groups "
      consume_bare=1
      ;;
    setpriv) optarg=" --inh-caps --ambient-caps --ruid --euid --rgid --egid --reuid --regid --groups --bounding-set --securebits --pdeathsig --ptracer --selinux-label --apparmor-profile --landlock-access --landlock-rule --list-landlock-rights --seccomp-filter " ;; # spellchecker:disable-line
    prlimit) optarg=" -p --pid -o --output " ;;
    systemd-run) optarg=" -H --host -M --machine -C --capsule -u --unit -p --property --description --slice --expand-environment --service-type --uid --gid --nice --working-directory --root-directory -E --setenv --output --json --job-mode --background --path-property --socket-property --timer-property --on-active --on-boot --on-startup --on-unit-active --on-unit-inactive --on-calendar " ;;
    sg)
      j=$((i + 1))
      if ((j < n)) && [[ "${words[j]}" == - || "${words[j]}" == -l ]]; then
        ((RDT_ARM)) && rdt_cd_unknown=1
        j=$((j + 1))
      fi
      ((j < n)) && [[ "${words[j]}" != -* ]] || return 0
      j=$((j + 1))
      ((j + 1 < n)) && [[ "${words[j]}" == -c ]] && j=$((j + 1))
      ((j < n)) && rdt_parse "${words[j]}"
      return 0
      ;;
    runuser)
      ((RDT_ARM)) && rdt_note_login ${words[@]+"${words[@]:i+1}"}
      local -a ru_cmds=() ru_argv=() ru_quoted=() ru_q0=()
      local ru_u ru_cmd ru_posix ru_key ru_seen=""
      ru_q0=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"})
      for ru_posix in 0 1; do
        HOOK_SEG_WORD_QUOTED=(${ru_q0[@]+"${ru_q0[@]}"})
        RDT_RU_POSIX=$ru_posix
        rdt_runuser_argv "$((i + 1))" ${words[@]+"${words[@]:i+1}"}
        RDT_RU_POSIX=0
        rdt_ru_key_to ru_key
        [[ "$ru_key" == "$ru_seen" ]] && break
        ru_seen=$ru_key
        ru_u="$RDT_RU_U"
        ru_cmds=(${RDT_RU_CMDS[@]+"${RDT_RU_CMDS[@]}"})
        ru_argv=(${RDT_RU_ARGV[@]+"${RDT_RU_ARGV[@]}"})
        ru_quoted=(${RDT_RU_QUOTED[@]+"${RDT_RU_QUOTED[@]}"})
        rdt_su_shell_run
        for ru_cmd in ${ru_cmds[@]+"${ru_cmds[@]}"}; do
          rdt_parse "$ru_cmd"
        done
        if ((ru_u)); then
          HOOK_SEG_WORD_QUOTED=(${ru_quoted[@]+"${ru_quoted[@]}"})
          ((${#ru_argv[@]})) && rdt_check_segment "${ru_argv[@]}"
        elif ((${#ru_argv[@]} > 1)); then
          HOOK_SEG_WORD_QUOTED=()
          rdt_check_segment su "${ru_argv[@]:1}"
        fi
      done
      return 0
      ;;
    env) optarg=" -u --unset -C --chdir " ;;
    timeout)
      optarg=" -s --signal -k --kill-after "
      consume_bare=1
      ;;
    nice | ionice) optarg=" -n --adjustment -c --class --classdata -p --pid " ;;
    stdbuf) optarg=" -i -o -e --input --output --error " ;;
    time) optarg=" -f --format -o --output " ;;
    exec) optarg=" -a " ;;
    command | nohup | setsid | busybox) optarg="" ;;
    *) break ;;
    esac
    i=$((i + 1))
    while ((i < n)); do
      w="${words[i]}"
      case "$w" in
      --)
        i=$((i + 1))
        if ((consume_bare && i < n)); then
          case "$base" in
          chrt) [[ "${words[i]}" =~ ^[0-9]+$ ]] && i=$((i + 1)) ;;
          timeout) [[ "${words[i]}" =~ ^[[:space:]]*[+-]?([0-9.]|[iI][nN][fF]|[nN][aA][nN]) ]] && i=$((i + 1)) ;;
          *) i=$((i + 1)) ;;
          esac
          if [[ "$base" == "flock" ]] && ((i < n)) && [[ "${words[i]}" == "-c" || "${words[i]}" == "--command" ]]; then
            ((i + 1 < n)) && rdt_parse "${words[i + 1]}"
            return 0
          fi
        fi
        break
        ;;
      -*)
        if ((RDT_ARM)); then
          rdt_note_launcher_dir "$base" "$w" "$((i + 1 < n))" "${words[i + 1]-}" \
            "${HOOK_SEG_WORD_QUOTED[i]:-0}" "${HOOK_SEG_WORD_QUOTED[i + 1]:-0}"
        fi
        if [[ "$base" == "flock" && ("$w" == "-c" || "$w" == "--command") ]]; then
          ((i + 1 < n)) && rdt_parse "${words[i + 1]}"
          return 0
        fi
        [[ "$base" == "flock" && ("$w" == "--fd" || "$w" == --fd=*) ]] && consume_bare=0
        if [[ "$base" == "env" ]]; then
          case "$w" in
          -S | --split-string)
            rdt_env_split_check "${words[i + 1]-}" "$((i + 2))"
            return 0
            ;;
          -S* | --split-string=*)
            sval="${w#-S}"
            rdt_env_split_check "${sval#--split-string=}" "$((i + 1))"
            return 0
            ;;
          --s*)
            sval="${w#--}"
            if [[ "split-string" == "${sval%%=*}"* ]]; then
              local -a env_q=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"})
              if [[ "$w" == *=* ]]; then
                rdt_env_split_check "${w#*=}" "$((i + 1))"
              elif ((i + 1 < n)); then
                rdt_env_split_check "${words[i + 1]}" "$((i + 2))"
              fi
              HOOK_SEG_WORD_QUOTED=(${env_q[@]+"${env_q[@]}"})
            fi
            ;;
          *) ;;
          esac
        fi
        if ((i + 1 < n)) && [[ "$w" == --?* && "$w" != *=* && "$optarg" != *" $w "* ]] &&
          rdt_long_takes_arg "$base" "${w#--}"; then
          if ((rdt_abbr)); then
            i=$((i + 2))
            continue
          fi
          if ((abbr_forked == 0)); then
            abbr_forked=1
            rdt_resolved_walk ${words[@]+"${words[@]}"}
          fi
        fi
        if [[ "$w" =~ ^-[A-Za-z]+$ && "$optarg" != *" $w "* ]] && rdt_short_cluster_arg "$base" "$w"; then
          if ((rdt_abbr)); then
            i=$((i + 1 + RDT_SC_NEXT))
            continue
          fi
          if ((abbr_forked == 0)); then
            abbr_forked=1
            rdt_resolved_walk ${words[@]+"${words[@]}"}
          fi
        fi
        if [[ -n "$optarg" && "$optarg" == *" $w "* ]]; then
          i=$((i + 2))
        else
          i=$((i + 1))
        fi
        ;;
      *)
        ((consume_bare)) || break
        [[ "$base" == "chrt" && ! "$w" =~ ^[0-9]+$ ]] && break
        consume_bare=0
        i=$((i + 1))
        ;;
      esac
    done
  done
  ((i < n)) || return 0

  rdt_sink_check "$i"

  if hook::shell_c_operand "${words[@]:i}"; then
    rdt_parse "$HOOK_SHELL_C_OPERAND"
    return 0
  fi
  # shellcheck disable=SC2016  # the literal text the tokenizer hands over
  case "${words[i]}" in
  '$SHELL' | '${SHELL}' | '$BASH' | '${BASH}')
    if hook::shell_c_operand sh ${words[@]+"${words[@]:i+1}"}; then
      rdt_parse "$HOOK_SHELL_C_OPERAND"
      return 0
    fi
    ;;
  *) ;;
  esac

  base="${words[i]##*/}"
  base="${base,,}"
  base="${base%.exe}"

  if ((RDT_ARM)); then
    case "$base" in
    cd | pushd | popd)
      rdt_note_cd "$base" "$((i + 1))" ${words[@]+"${words[@]:i+1}"}
      return 0
      ;;
    export | declare | typeset | readonly | local)
      for w in ${words[@]+"${words[@]:i+1}"}; do
        rdt_note_cdpath "$w"
      done
      return 0
      ;;
    su) rdt_note_login ${words[@]+"${words[@]:i+1}"} ;;
    *) ;;
    esac
  fi

  if [[ "$base" == "su" ]]; then
    local k
    local sulong su_key su_q0=()
    su_q0=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"})
    rdt_runuser_argv "$((i + 1))" ${words[@]+"${words[@]:i+1}"}
    rdt_ru_key_to su_key
    rdt_su_shell_run
    HOOK_SEG_WORD_QUOTED=(${su_q0[@]+"${su_q0[@]}"})
    RDT_RU_POSIX=1
    rdt_runuser_argv "$((i + 1))" ${words[@]+"${words[@]:i+1}"}
    RDT_RU_POSIX=0
    rdt_ru_key_to sulong
    [[ "$sulong" != "$su_key" ]] && rdt_su_shell_run
    for ((k = i + 1; k < n; k++)); do
      case "${words[k]}" in
      --?*)
        sulong="${words[k]#--}"
        sulong="${sulong%%=*}"
        if [[ -n "$sulong" && ("command" == "$sulong"* || ("${#sulong}" -ge 2 && "session-command" == "$sulong"*)) ]]; then
          if [[ "${words[k]}" == *=* ]]; then
            rdt_parse "${words[k]#*=}"
            ((k + 1 < n)) && [[ "${words[k]#*=}" == "--" ]] && rdt_parse "${words[k + 1]}"
          else
            ((k + 1 < n)) && rdt_parse "${words[k + 1]}"
            ((k + 2 < n)) && [[ "${words[k + 1]}" == "--" ]] && rdt_parse "${words[k + 2]}"
          fi
        fi
        ;;
      -*)
        if [[ "${words[k]}" =~ ^-[A-Za-z]+$ && "${words[k]}" == *c* ]]; then
          ((k + 1 < n)) && rdt_parse "${words[k + 1]}"
          ((k + 2 < n)) && [[ "${words[k + 1]}" == "--" ]] && rdt_parse "${words[k + 2]}"
        fi
        if [[ "${words[k]}" =~ ^-[A-Zabd-z]*c. ]]; then
          sulong="${words[k]#-}"
          rdt_parse "${sulong#*c}"
          ((k + 1 < n)) && [[ "${sulong#*c}" == "--" ]] && rdt_parse "${words[k + 1]}"
        fi
        ;;
      *) ;;
      esac
    done
    return 0
  fi

  if [[ "$base" == "eval" ]] && ((i + 1 < n)); then
    rdt_parse_words "$((i + 1))"
    return 0
  fi

  case "$base" in
  mv | truncate | shred | dd)
    rdt_content_check "$i" "$base"
    return 0
    ;;
  watch)
    rdt_watch_check "$i"
    return 0
    ;;
  cmd)
    rdt_cmd_check "$i"
    return 0
    ;;
  python | python[0-9]* | py | pypy | pypy[0-9]* | node | nodejs | perl | perl[0-9]* | ruby | ruby[0-9]*)
    rdt_interp_check "$i" "$base"
    return 0
    ;;
  find)
    rdt_find_check "$i"
    return 0
    ;;
  rsync)
    rdt_rsync_check "$i"
    return 0
    ;;
  robocopy)
    rdt_robocopy_check "$i"
    return 0
    ;;
  git)
    rdt_git_worktree_check "$i"
    return 0
    ;;
  xargs)
    rdt_xargs_check "$i"
    return 0
    ;;
  parallel)
    rdt_parallel_check "$i"
    return 0
    ;;
  *) ;;
  esac

  [[ "$base" == "rm" ]] || return 0

  local recursive=0 no_preserve=0 end_of_opts=0 long
  local -a operand_idx=()
  for ((j = i + 1; j < n; j++)); do
    w="${words[j]}"
    if ((end_of_opts == 0)); then
      case "$w" in
      --)
        end_of_opts=1
        continue
        ;;
      --?*)
        long="${w#--}"
        if [[ "recursive" == "$long"* ]]; then
          recursive=1
        elif [[ "no-preserve-root" == "$long"* ]]; then
          no_preserve=1
        fi
        continue
        ;;
      -?*)
        if [[ "$w" =~ ^-[A-Za-z]+$ && "$w" == *[rR]* ]]; then
          recursive=1
        fi
        continue
        ;;
      *) ;;
      esac
    fi
    operand_idx+=("$j")
  done

  ((recursive)) || return 0
  rdt_deleter=1
  ((no_preserve)) && rdt_block "no-preserve-root"

  for j in ${operand_idx[@]+"${operand_idx[@]}"}; do
    rdt_delete_operand "${words[j]}" "${HOOK_SEG_WORD_QUOTED[j]:-0}"
  done
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_delete_operand() {
  local w="$1" q="$2" x rc
  local -a bx=()
  if [[ "$w" == "$RDT_IX_HOLE" ]]; then
    rdt_block "interp-unplaceable" "a path the code computes"
    return 0
  fi
  if [[ -z "$w" ]]; then
    ((q == 1)) && rdt_block "root-operand" "/"
    rdt_block "empty-operand"
  fi
  ((${#w} > MAX_OPERAND_LEN)) && rdt_block "operand-too-long" "an operand of ${#w} bytes"
  x="${w//[^\/\\]/}"
  ((${#x} > MAX_OPERAND_DEPTH)) && rdt_block "operand-too-long" "an operand with ${#x} path separators"
  if [[ "$w" == *'{'* ]] && ((q != 2 && q != 3)); then
    x="${w//[^\{]/}"
    ((${#w} > MAX_BRACE_WORD || ${#x} > MAX_BRACE_OPEN)) && rdt_block "brace-too-large" "of ${#w} bytes with ${#x} braces"
    rc=0
    rdt_brace_expand "$w" || rc=$?
    if ((rc != 0)); then
      rdt_block "brace" "'$w'"
      return 0
    fi
    if ((${#RDT_BX[@]} != 1)) || [[ "${RDT_BX[0]}" != "$w" ]]; then
      ((q == 1)) && rdt_block "brace" "'$w'"
      bx=(${RDT_BX[@]+"${RDT_BX[@]}"})
      for x in ${bx[@]+"${bx[@]}"}; do
        [[ -n "$x" ]] && rdt_check_operand "$x" 0
      done
      return 0
    fi
  fi
  rdt_check_operand "$w" "$q"
}

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_watch_check() {
  local k=$(($1 + 1)) x=0 w j c l hit
  local -a q0=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"})
  while ((k < n)); do
    w="${words[k]}"
    case "$w" in
    --)
      k=$((k + 1))
      break
      ;;
    --?*)
      l="${w#--}"
      if [[ "$l" != *=* ]]; then
        hit=""
        for c in beep color no-color differences errexit follow chgexit equexit exec help interval precise \
          no-rerun shotsdir no-title no-wrap version; do
          if [[ "$c" == "$l" ]]; then
            hit=$c
            break
          fi
          [[ "$c" == "$l"* ]] && hit+="$c "
        done
        case "${hit% }" in
        exec) x=1 ;;
        interval | equexit | shotsdir) k=$((k + 1)) ;;
        *) ;;
        esac
      fi
      ;;
    -?*)
      for ((j = 1; j < ${#w}; j++)); do
        c="${w:j:1}"
        case "$c" in
        x) x=1 ;;
        d) break ;;
        n | q | s)
          ((j + 1 < ${#w})) || k=$((k + 1))
          break
          ;;
        *) ;;
        esac
      done
      ;;
    *) break ;;
    esac
    k=$((k + 1))
  done
  ((k < n)) || return 0
  if ((x)); then
    HOOK_SEG_WORD_QUOTED=(${q0[@]+"${q0[@]:k}"})
    rdt_check_segment "${words[@]:k}"
  else
    rdt_parse_words "$k"
  fi
  HOOK_SEG_WORD_QUOTED=(${q0[@]+"${q0[@]}"})
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_cmd_check() {
  local k o w j s
  local -a cw=() st=() q0=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"})
  for ((k = $1 + 1; k < n; k++)); do
    o="${words[k]}"
    [[ "$o" =~ ^//[^/] ]] && o="${o:1}"
    case "${o,,}" in
    /c | /k) break ;;
    /c?* | /k?*)
      rdt_ps_cmd_split_to cw "${o:2}"
      break
      ;;
    *) ;;
    esac
  done
  k=$((k + 1))
  if ((${#cw[@]} == 0 && k < n - 1)); then
    s=$k
    for ((j = k; j <= n; j++)); do
      w='&'
      ((j < n)) && w="${words[j]}"
      case "$w" in
      '&' | '&&' | '|' | '||')
        if ((j > s)); then
          HOOK_SEG_WORD_QUOTED=(${q0[@]+"${q0[@]:s:j-s}"})
          rdt_check_segment "${words[@]:s:j-s}"
          HOOK_SEG_WORD_QUOTED=(${q0[@]+"${q0[@]}"})
          rdt_cmd_rd_bash "$s" "$j"
        fi
        s=$((j + 1))
        ;;
      *) ;;
      esac
    done
    return 0
  fi
  if ((${#cw[@]} == 0 && k == n - 1)); then
    rdt_ps_cmd_split_to cw "${words[k]}"
  elif ((${#cw[@]} && k < n)); then
    for w in "${words[@]:k}"; do
      [[ "$w" =~ ^//[^/]+$ ]] && w="${w:1}"
      cw+=("$w")
    done
  fi
  for w in ${cw[@]+"${cw[@]}"} '&'; do
    case "$w" in
    '&' | '&&' | '|' | '||')
      ((${#st[@]})) && rdt_ps_cmd_rd "${st[@]}"
      st=()
      ;;
    *)
      rdt_cmd_pct_to w "$w"
      st+=("$w")
      ;;
    esac
  done
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_cmd_check
rdt_cmd_rd_bash() {
  local j b lw p q sw='^(/[sq?]+)+$' rec=0 dl=0
  local -a pi=()
  b="${words[$1]##*[\\/]}"
  b="${b,,}"
  case "${b%.exe}" in
  rd | rmdir) ;;
  del | erase)
    sw='^(/[sqpf?]+)+$'
    dl=1
    ;;
  *) return 0 ;;
  esac
  for ((j = $1 + 1; j < $2; j++)); do
    lw="${words[j],,}"
    if [[ "$lw" =~ ^//[^/]+$ || "$lw" =~ $sw ]]; then
      [[ "${lw//\//}" == *s* ]] && rec=1
    else
      pi+=("$j")
    fi
  done
  ((rec)) || return 0
  ((${#pi[@]} || dl)) || rdt_block "empty-operand"
  for j in ${pi[@]+"${pi[@]}"}; do
    rdt_cmd_pct_to p "${words[j]}"
    q=0
    [[ "$p" == "${words[j]}" ]] && q="${q0[j]:-0}"
    rdt_delete_operand "$p" "$q"
  done
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_find_check() {
  local k
  rdt_find_scan "$1"
  ((RDT_FIND_DEL)) || return 0
  rdt_deleter=1
  local -a sw=(${RDT_FIND_SW[@]+"${RDT_FIND_SW[@]}"}) sq=(${RDT_FIND_SQ[@]+"${RDT_FIND_SQ[@]}"})
  for ((k = 0; k < ${#sw[@]}; k++)); do
    rdt_delete_operand "${sw[k]}" "${sq[k]}"
  done
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_rsync_check() {
  local k c w pre del=0 rsf=0 eoo=0 last
  local -a op=() tg=()
  for ((k = $1 + 1; k < n; k++)); do
    w="${words[k]}"
    if ((eoo == 0)); then
      case "$w" in
      --)
        eoo=1
        continue
        ;;
      --del | --delete | --delete-*)
        del=1
        continue
        ;;
      --remove-source-files | --remove-sent-files)
        rsf=1
        continue
        ;;
      --*=*) continue ;;
      --?*)
        case "${w#--}" in
        info | debug | stderr | checksum-choice | chmod | chown | rsh | rsync-path | backup-dir | suffix | \
          partial-dir | temp-dir | compare-dest | copy-dest | link-dest | filter | exclude | exclude-from | \
          include | include-from | files-from | log-file | log-file-format | password-file | early-input | \
          max-delete | max-size | min-size | max-alloc | usermap | groupmap | timeout | contimeout | \
          compress-choice | compress-level | compress-threads | skip-compress | copy-as | address | port | \
          sockopts | outbuf | out-format | bwlimit | stop-after | stop-at | write-batch | only-write-batch | \
          read-batch | protocol | iconv | checksum-seed | block-size | remote-option | modify-window | \
          config | dparam | log-format | time-limit | cc | zc | zl | zt)
          k=$((k + 1))
          ;;
        *) ;;
        esac
        continue
        ;;
      -?*)
        for ((c = 1; c < ${#w}; c++)); do
          case "${w:c:1}" in
          [efTBM@])
            ((c + 1 < ${#w})) || k=$((k + 1))
            break
            ;;
          *) ;;
          esac
        done
        continue
        ;;
      *) ;;
      esac
    fi
    op+=("$k")
  done
  ((del || rsf)) || return 0
  rdt_deleter=1
  for k in ${op[@]+"${op[@]}"}; do
    w="${words[k]}"
    ((${HOOK_SEG_WORD_QUOTED[k]:-0} == 2)) && continue
    if [[ "$w" == *['{*?[']* ]]; then
      tg=("${op[@]}")
      break
    fi
  done
  if ((${#tg[@]} == 0)); then
    ((${#op[@]} > 1)) || return 0
    last="${op[${#op[@]} - 1]}"
    ((del)) && tg+=("$last")
    if ((rsf)); then
      for k in "${op[@]}"; do
        ((k == last)) || tg+=("$k")
      done
    fi
  fi
  for k in "${tg[@]}"; do
    w="${words[k]}"
    pre="${w%%:*}"
    if [[ "$w" == rsync://* ]] ||
      [[ "$pre" != "$w" && "$pre" != */* && ${#pre} -ge 2 &&
        "$pre" != *'$'* && "$pre" != *'`'* && "$pre" != *'{'* ]]; then
      continue
    fi
    rdt_delete_operand "$w" "${HOOK_SEG_WORD_QUOTED[k]:-0}"
  done
  return 0
}

rdt_msys_excluded() {
  local e rest="$2;"
  while [[ -n "$rest" ]]; do
    e="${rest%%;*}"
    rest="${rest#*;}"
    [[ "$e" == '*' || (-n "$e" && "$1" == "$e"*) ]] && return 0
  done
  return 1
}

rdt_robocopy_scan() {
  local k w msys="$1" excl="$2" list=0
  shift 2
  RDT_RC_DEST=0 RDT_RC_SRC=0
  RDT_RC_OP=()
  for ((k = 1; k <= $#; k++)); do
    w="${!k}"
    if ((msys)) && [[ "$w" =~ ^/[A-Za-z]$ ]] && ! rdt_msys_excluded "$w" "$excl"; then
      ((list)) || RDT_RC_OP+=("$((k - 1))")
      continue
    fi
    w="${w,,}"
    [[ "$w" == //* ]] && w="${w#/}"
    [[ "$w" == -?* ]] && w="/${w#-}"
    case "${w%%:*}" in
    /mir | /purge) RDT_RC_DEST=1 list=0 ;;
    /move | /mov) RDT_RC_SRC=1 list=0 ;;
    /xf | /xd | /if) list=1 ;;
    /s | /e | /lev | /z | /b | /zb | /j | /efsraw | /copy | /dcopy | /sec | /copyall | /nocopy | \
      /secfix | /timfix | /a+ | /a- | /create | /fat | /256 | /mon | /mot | /rh | /pf | /ipg | /sj | \
      /sl | /mt | /nodcopy | /nooffload | /compress | /sparse | /noclone | /iomaxsize | /iorate | \
      /threshold | /a | /m | /ia | /xa | /xc | /xn | /xo | /xx | /xl | /im | /is | /it | /max | /min | \
      /maxage | /minage | /maxlad | /minlad | /xj | /fft | /dst | /xjd | /xjf | /r | /w | /reg | /tbd | \
      /lfsm | /l | /x | /v | /ts | /fp | /bytes | /ns | /nc | /nfl | /ndl | /np | /eta | /log | /log+ | \
      /unilog | /unilog+ | /tee | /njh | /njs | /unicode | /job | /save | /quit | /nosd | /nodd)
      list=0
      ;;
    *) ((list)) || RDT_RC_OP+=("$((k - 1))") ;;
    esac
  done
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_robocopy_check and rdt_content_check
rdt_may_split() {
  [[ "${words[$1]}" == *'$@'* || "${words[$1]}" == *'[@]}'* ]] ||
    { ((${HOOK_SEG_WORD_QUOTED[$1]:-0} != 2)) && [[ "${words[$1]}" == *['{*?[$`']* ]]; }
}

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_robocopy_check() {
  local k w msys=1 excl='' unknown=0 envw=0
  local -a op=() tg=()
  for ((k = 0; k < $1; k++)); do
    w="${words[k]}"
    case "$w" in
    MSYS_NO_PATHCONV=* | MSYS2_ARG_CONV_EXCL=*)
      [[ "${w#*=}" == *['$`']* ]] && unknown=1
      if [[ "$w" == MSYS_NO_PATHCONV=* ]]; then
        msys=0
      else
        excl="${w#*=}"
      fi
      ;;
    *)
      w="${w##*/}"
      w="${w,,}"
      if [[ "${w%.exe}" == env ]]; then
        envw=1
      elif ((envw)) && [[ "${words[k]}" == -* ]]; then
        unknown=1
      fi
      ;;
    esac
  done
  if ((unknown)); then
    msys=1 excl=''
  fi
  rdt_robocopy_scan "$msys" "$excl" ${words[@]+"${words[@]:$1+1}"}
  ((RDT_RC_DEST || RDT_RC_SRC)) || return 0
  rdt_deleter=1
  for k in ${RDT_RC_OP[@]+"${RDT_RC_OP[@]}"}; do
    op+=("$((k + $1 + 1))")
  done
  ((unknown)) && tg=(${op[@]+"${op[@]}"})
  for k in ${op[@]+"${op[@]}"}; do
    if rdt_may_split "$k"; then
      tg=("${op[@]}")
      break
    fi
  done
  if ((${#tg[@]} == 0)); then
    ((RDT_RC_SRC && ${#op[@]} > 0)) && tg+=("${op[0]}")
    ((RDT_RC_DEST && ${#op[@]} > 1)) && tg+=("${op[1]}")
  fi
  for k in ${tg[@]+"${tg[@]}"}; do
    rdt_delete_operand "${words[k]}" "${HOOK_SEG_WORD_QUOTED[k]:-0}"
  done
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_git_worktree_check() {
  local k w force=0 eoo=0 rel=0
  local -a op=()
  for ((k = 0; k < $1; k++)); do
    case "${words[k]}" in
    GIT_DIR=* | GIT_WORK_TREE=* | GIT_COMMON_DIR=*) rel=1 ;;
    *) ;;
    esac
  done
  for ((k = $1 + 1; k < n; k++)); do
    w="${words[k]}"
    case "$w" in
    -C | --git-dir | --work-tree) rel=1 k=$((k + 1)) ;;
    --git-dir=* | --work-tree=*) rel=1 ;;
    -c | --namespace | --config-env | --super-prefix | --attr-source) k=$((k + 1)) ;;
    -*) ;;
    *) break ;;
    esac
  done
  [[ "${words[k]-}" == worktree && "${words[k + 1]-}" == remove ]] || return 0
  for ((k = k + 2; k < n; k++)); do
    w="${words[k]}"
    if ((eoo == 0)); then
      case "$w" in
      --)
        eoo=1
        continue
        ;;
      --?*)
        [[ "force" == "${w#--}"* ]] && force=1
        continue
        ;;
      -?*)
        [[ "$w" =~ ^-[A-Za-z]+$ && "$w" == *f* ]] && force=1
        continue
        ;;
      *) ;;
      esac
    fi
    op+=("$k")
  done
  ((force)) || return 0
  rdt_deleter=1
  RDT_WTRM=1
  ((RDT_ARM && (${#RDT_ORIGINS[@]} > 1 || rdt_cd_unknown || rdt_cd_refuse))) && rel=1
  for k in ${op[@]+"${op[@]}"}; do
    w="${words[k]//\\//}"
    if ((rel && RDT_ARM)); then
      # shellcheck disable=SC2016,SC2088  # matching the literal text of the operand
      case "$w" in
      '~' | '~/'* | '$HOME' | '$HOME/'* | '${HOME}' | '${HOME}/'*) ;;
      *) rdt_is_abs "$w" || rdt_block "unplaceable" "'${words[k]}' (a worktree named relative to a repository the command selects)" ;;
      esac
    fi
    rdt_delete_operand "${words[k]}" "${HOOK_SEG_WORD_QUOTED[k]:-0}"
  done
  RDT_WTRM=0
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_content_check, under a parser callback
rdt_gnu_scan() {
  local k=$1 c w x long letters="$2" eoo=0 take
  shift 2
  RDT_GNU_OP=()
  RDT_GNU_SEEN=""
  for ((k = k + 1; k < n; k++)); do
    w="${words[k]}"
    if ((eoo == 0)); then
      take=0
      case "$w" in
      --)
        eoo=1
        continue
        ;;
      --?*)
        long="${w#--}"
        long="${long%%=*}"
        for x in "$@"; do
          if [[ "${x#?:}" == "$long"* ]]; then
            RDT_GNU_SEEN+="${x%%:*}"
            [[ "$w" == *=* ]] || take=1
            break
          fi
        done
        ;;
      -?*)
        for ((c = 1; c < ${#w}; c++)); do
          x="${w:c:1}"
          if [[ "$letters" == *"$x"* ]]; then
            RDT_GNU_SEEN+="$x"
            ((c + 1 < ${#w})) || take=1
            break
          fi
        done
        ;;
      *)
        RDT_GNU_OP+=("$k")
        continue
        ;;
      esac
      if ((take)); then
        k=$((k + 1))
        ((k < n && ${#RDT_GNU_OP[@]})) && RDT_GNU_OP+=("$k")
      fi
      continue
    fi
    RDT_GNU_OP+=("$k")
  done
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_content_check() {
  local k w of=0
  local -a tg=()
  if [[ "$2" == dd ]]; then
    for ((k = $1 + 1; k < n; k++)); do
      w="${words[k]}"
      [[ "$w" == of=* ]] || continue
      of=1
      case "${w#of=}" in
      /dev/null | /dev/stdout | /dev/stderr) continue ;;
      '')
        rdt_block "empty-operand"
        continue
        ;;
      *) ;;
      esac
      rdt_deleter=1
      rdt_delete_operand "${w#of=}" "${HOOK_SEG_WORD_QUOTED[k]:-0}"
    done
    ((of)) || rdt_deleter=1
    return 0
  fi
  rdt_deleter=1
  case "$2" in
  mv) rdt_gnu_scan "$1" tS t:target-directory S:suffix ;;
  truncate) rdt_gnu_scan "$1" rs r:reference s:size ;;
  *) rdt_gnu_scan "$1" ns n:iterations _:random-source s:size ;;
  esac
  tg=(${RDT_GNU_OP[@]+"${RDT_GNU_OP[@]}"})
  if [[ "$2" == mv && "$RDT_GNU_SEEN" != *t* ]] && ((${#tg[@]} > 1 && rdt_fed == 0)); then
    rdt_may_split "${tg[${#tg[@]} - 1]}" || unset "tg[$((${#tg[@]} - 1))]"
  fi
  for k in ${tg[@]+"${tg[@]}"}; do
    rdt_delete_operand "${words[k]}" "${HOOK_SEG_WORD_QUOTED[k]:-0}"
  done
  return 0
}

RDT_IX_HOLE=$'\001hole\002'
RDT_IX_PH_RE=$'^\001([scxud])([0-9]+)\002$'
RDT_IX_PH_ANY=$'\001([scxud])([0-9]+)\002'
RDT_IX_KWARG_RE=$'^([A-Za-z_][A-Za-z0-9_]*:([^:]|$)|:[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=>|\001[sx][0-9]+\002[[:space:]]*=>)'

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_interp_check() {
  local lang k j w c rest stdin=1 stop=0 last
  local -a code=() q0=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"})
  case "$2" in
  py | python* | pypy*) lang=py ;;
  node | nodejs) lang=js ;;
  perl*) lang=pl ;;
  *) lang=rb ;;
  esac
  for ((k = $1 + 1; k < n && stop == 0; k++)); do
    w="${words[k]}"
    case "$w" in
    -) break ;;
    --)
      ((k + 1 < n)) && stdin=0
      break
      ;;
    --?*)
      case "$lang:$w" in
      js:--eval | js:--print)
        code+=("${words[k + 1]-}")
        k=$((k + 1))
        stdin=0
        ;;
      js:--eval=* | js:--print=*)
        code+=("${w#*=}")
        stdin=0
        ;;
      py:--check-hash-based-pycs | js:--require | js:--import | js:--loader | js:--experimental-loader | js:--conditions | js:--input-type | js:--env-file | js:--title | rb:--encoding | rb:--external-encoding | rb:--internal-encoding)
        k=$((k + 1))
        ;;
      *) ;;
      esac
      ;;
    -?*)
      if [[ "$lang" == js ]]; then
        case "$w" in
        -e | -p | -pe | -ep)
          code+=("${words[k + 1]-}")
          k=$((k + 1))
          stdin=0
          ;;
        -r | -C) k=$((k + 1)) ;;
        *) ;;
        esac
        continue
      fi
      for ((j = 1; j < ${#w} && j < 32; j++)); do
        c="${w:j:1}"
        rest="${w:j+1}"
        case "$lang:$c" in
        py:c | pl:e | pl:E | rb:e)
          if [[ -n "$rest" ]]; then
            code+=("$rest")
          else
            code+=("${words[k + 1]-}")
            k=$((k + 1))
          fi
          stdin=0
          [[ "$lang" == py ]] && stop=1
          break
          ;;
        py:m)
          stdin=0
          stop=1
          break
          ;;
        py:W | py:X | pl:I | pl:M | pl:m | rb:r | rb:I | rb:C | rb:E)
          [[ -z "$rest" ]] && k=$((k + 1))
          break
          ;;
        pl:l | pl:0)
          [[ "$rest" =~ ^(x[0-9A-Fa-f]*|[0-7]*) ]]
          j=$((j + ${#BASH_REMATCH[0]}))
          ;;
        pl:[ixdDCVF] | rb:[xiWKTF0]) break ;;
        *) ;;
        esac
      done
      ((j >= 32 && j < ${#w})) && rdt_block "interp-unplaceable" "code after an option cluster too long to read (${w:0:40}...)"
      ;;
    *)
      if ((${#code[@]} == 0)) && [[ "$w" != /dev/stdin ]]; then stdin=0; fi
      break
      ;;
    esac
  done
  if ((stdin && ${#code[@]} == 0)); then
    rdt_stdin_redir
    last=$RDT_IN_R
    if ((last >= 0)); then
      case "${HOOK_SEG_REDIR_OP[last]}" in
      '<<<') code+=("${HOOK_SEG_REDIR_TARGET[last]-}") ;;
      '<<' | '<<-') [[ -n "${rdt_hd_at-}" ]] && rdt_hd_prog "$((rdt_hd_at + RDT_IN_HD))" "${HOOK_SEG_REDIR_TARGET[last]-}" "$lang" ;;
      *) ;;
      esac
    fi
  fi
  local d0="$rdt_deleter"
  for c in ${code[@]+"${code[@]}"}; do
    rdt_ix_code "$lang" "$c"
  done
  rdt_deleter="$d0"
  HOOK_SEG_WORD_QUOTED=(${q0[@]+"${q0[@]}"})
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_parse
rdt_ix_heredocs() {
  local k m st no d0="$rdt_deleter" unk0="$rdt_cd_unknown" ref0="$rdt_cd_refuse"
  local -a hdb=(${HOOK_HEREDOC_BODIES[@]+"${HOOK_HEREDOC_BODIES[@]}"}) ix=() lg=() sts=() bodies=() orig=()
  for k in "${!rdt_hd_lang[@]}"; do
    for ((m = 0; m < ${#hdb[@]}; m++)); do
      ix+=("$m")
      lg+=("${rdt_hd_lang[k]}")
      sts+=("${rdt_hd_st[k]-}")
    done
  done
  ((${#ix[@]})) || return 0
  RDT_IX_BODIES=()
  hook::_c_locale rdt_ix_slice "$1" "${ix[@]}"
  bodies=(${RDT_IX_BODIES[@]+"${RDT_IX_BODIES[@]}"})
  orig=(${RDT_ORIGINS[@]+"${RDT_ORIGINS[@]}"})
  for ((k = 0; k < ${#lg[@]}; k++)); do
    st="${sts[k]}"
    no="${st%% *}"
    st="${st#* }"
    rdt_cd_unknown="${st%% *}"
    st="${st#* }"
    rdt_cd_refuse="${st%% *}"
    [[ "$no" =~ ^[0-9]+$ ]] || no=${#orig[@]}
    [[ "$rdt_cd_unknown" =~ ^[01]$ ]] || rdt_cd_unknown="$unk0"
    [[ "$rdt_cd_refuse" =~ ^[01]$ ]] || rdt_cd_refuse="$ref0"
    if [[ "${lg[k]}" == sh ]]; then
      rdt_shell_prog "${bodies[k]-}" 0
      orig=(${RDT_ORIGINS[@]+"${RDT_ORIGINS[@]}"})
      continue
    fi
    RDT_ORIGINS=(${orig[@]+"${orig[@]:0:no}"})
    rdt_ix_code "${lg[k]}" "${bodies[k]-}"
    RDT_ORIGINS=(${orig[@]+"${orig[@]}"})
  done
  rdt_cd_unknown="$unk0"
  rdt_cd_refuse="$ref0"
  rdt_deleter="$d0"
  return 0
}

# shellcheck disable=SC1003,SC2329  # '\' is a literal backslash; invoked through hook::_c_locale
rdt_ix_slice() {
  local t="$1" e s u q c b m bs='\' dl='$' bt='`'
  shift
  for m in "$@"; do
    e="${hdb[m]}"
    s="${e%% *}"
    e="${e#* }"
    u="${e%% *}"
    e="${e#* }"
    q="${e%% *}"
    e="${e#* }"
    c="${e%% *}"
    b="${t:s:u-s}"
    if [[ "$c" == 1 ]]; then
      b="${b%$'\n'}"
      if [[ "$b" == *$'\n'* ]]; then b="${b%$'\n'*}"$'\n'; else b=""; fi
    fi
    if [[ "$q" == 0 ]]; then
      b="${b//"$bs$bs"/$'\001'}"
      b="${b//"$bs"$'\n'/}"
      b="${b//"$bs$dl"/"$dl"}"
      b="${b//"$bs$bt"/"$bt"}"
      b="${b//$'\001'/"$bs"}"
    fi
    RDT_IX_BODIES+=("$b")
  done
}

# shellcheck disable=SC2016,SC2329  # literal regex text; invoked from rdt_interp_check
rdt_ix_code() {
  local lang="$1" ix_m="" ix_cm="" ix_ri k
  local -a ix_v=() ix_k=() ix_re=()
  case "${2,,}" in
  *rm* | *-delete* | *.delete* | *unlink* | *rsync* | *robocopy* | *worktree* | *remove* | *mv* | *truncate* | \
    *shred* | *of=* | *base64* | *base32* | *basenc* | *xxd* | *cmd*rd*) ;;
  *) return 0 ;;
  esac
  rdt_ix_lex "$2"
  case "$lang" in
  py)
    ix_re=(del '(^|[^A-Za-z0-9_])(rmtree|os\.remove|os\.unlink|os\.rmdir|os\.removedirs)'
      run '(^|[^A-Za-z0-9_])(system|popen|run|call|check_call|check_output|Popen|getoutput|getstatusoutput)')
    ;;
  js)
    ix_re=(del '(^|[^A-Za-z0-9_$])(rmSync|rmdirSync|unlinkSync)'
      del '(\.)(rm|rmdir|unlink)'
      run '(^|[^A-Za-z0-9_$])(exec|execSync|spawn|spawnSync|execFile|execFileSync)')
    ;;
  rb)
    ix_re=(del '(^|[^A-Za-z0-9_])((FileUtils\.)?(rm_rf|rm_r|rmtree|remove_dir|remove_entry|remove_entry_secure)|FileUtils\.(rm|rm_f|remove|rmdir|remove_file|safe_unlink)|(File|Dir)\.(delete|unlink|rmdir))'
      run '(^|[^A-Za-z0-9_])(system|exec|spawn|popen|popen2|popen2e|popen3|capture2|capture2e|capture3)')
    ;;
  *)
    ix_re=(del '(^|[^A-Za-z0-9_$@%>])(rmtree|remove_tree|unlink|rmdir)'
      run '(^|[^A-Za-z0-9_$@%>])(system|exec)')
    ;;
  esac
  for ((ix_ri = 0; ix_ri < ${#ix_re[@]}; ix_ri += 2)); do
    rdt_ix_calls "${ix_re[ix_ri]}" "${ix_re[ix_ri + 1]}"
  done
  if [[ -n "$ix_cm" ]]; then
    for ((ix_ri = 1; ix_ri < ${#ix_re[@]}; ix_ri += 2)); do
      if [[ "$ix_cm" =~ ${ix_re[ix_ri]} ]]; then
        rdt_ix_unplaceable "${BASH_REMATCH[2]}" "a call after a comment character that may sit in a regex literal, to"
        break
      fi
    done
    case "$lang" in
    rb) ix_ri='(`)|(%x)([^A-Za-z0-9]|$)' ;;
    pl) ix_ri='(`)|(^|[^A-Za-z0-9_$@%>])(qx)([^A-Za-z0-9_]|$)' ;;
    *) ix_ri="" ;;
    esac
    if [[ -n "$ix_ri" && "$ix_cm" =~ $ix_ri ]]; then
      if [[ -n "${BASH_REMATCH[1]}" ]]; then
        ix_ri='`'
      elif [[ "$lang" == rb ]]; then
        ix_ri='%x'
      else
        ix_ri='qx'
      fi
      rdt_ix_unplaceable "$ix_ri" "a shell command after a comment character that may sit in a regex literal, run by"
    fi
  fi
  for ((k = 0; k < ${#ix_k[@]}; k++)); do
    case "${ix_k[k]}" in
    c) rdt_ix_shell "${ix_v[k]}" ;;
    d) rdt_ix_unplaceable $'\001'"d$k"$'\002' "the command given as" ;;
    *) ;;
    esac
  done
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_ix_code
rdt_ix_lex() {
  local r="$1" out="" ch re pfx raw kind mode ip tq cl apos="'" dq='"' bt='`' ce='*/'
  local re_pct='^([xqQwWiI]?)([([{<])' re_q='^([qwx]?)([([{</|!~])'
  r="${r//$'\001'/}"
  r="${r//$'\002'/}"
  case "$lang" in
  py) re="^([^${dq}${apos}#]*)([${dq}${apos}#])" ;;
  js) re="^([^${dq}${apos}${bt}/]*)([${dq}${apos}${bt}/])" ;;
  rb) re="^([^${dq}${apos}${bt}#%]*)([${dq}${apos}${bt}#%])" ;;
  *) re="^([^${dq}${apos}${bt}#q]*)([${dq}${apos}${bt}#q])" ;;
  esac
  while [[ "$r" =~ $re ]]; do
    rdt_deadline
    out+="${BASH_REMATCH[1]}"
    ch="${BASH_REMATCH[2]}"
    r="${r:${#BASH_REMATCH[0]}}"
    kind=s mode=2 ip=n raw="" cl="$ch"
    case "$ch" in
    '#')
      if [[ "$lang" == pl && "$out" == *'$' ]]; then
        out+='#'
        continue
      fi
      [[ "$lang" != py && "${out##*$'\n'}" == */* ]] && ix_cm+="${r%%$'\n'*}"$'\n'
      if [[ "$r" == *$'\n'* ]]; then r="${r#*$'\n'}"; else r=""; fi
      out+=$'\n'
      continue
      ;;
    /)
      if [[ "$r" == /* ]]; then
        [[ "${out##*$'\n'}" == */* ]] && ix_cm+="${r%%$'\n'*}"$'\n'
        if [[ "$r" == *$'\n'* ]]; then r="${r#*$'\n'}"; else r=""; fi
        out+=$'\n'
      elif [[ "$r" == '*'* ]]; then
        r="${r:1}"
        [[ "${out##*$'\n'}" == */* ]] && ix_cm+="${r%%"$ce"*}"$'\n'
        if [[ "$r" == *"$ce"* ]]; then r="${r#*"$ce"}"; else r=""; fi
        out+=' '
      else
        out+=/
      fi
      continue
      ;;
    %)
      if ! [[ "$r" =~ $re_pct ]]; then
        out+=%
        continue
      fi
      pfx="${BASH_REMATCH[1]}"
      cl="${BASH_REMATCH[2]}"
      r="${r:${#BASH_REMATCH[0]}}"
      case "$pfx" in
      x) kind=c ip=h ;;
      q) mode=1 ;;
      Q | '') ip=h ;;
      *) kind=x ;;
      esac
      ;;
    q)
      if [[ -n "$out" && "${out: -1}" == [A-Za-z0-9_\$@%\&\>:] ]] || ! [[ "$r" =~ $re_q ]]; then # portability-ok: a bash pattern bracket holding an escaped >, not a GNU grep word boundary
        out+=q
        continue
      fi
      pfx="${BASH_REMATCH[1]}"
      cl="${BASH_REMATCH[2]}"
      r="${r:${#BASH_REMATCH[0]}}"
      case "$pfx" in
      x) kind=c ip=p ;;
      '') mode=1 ;;
      q) ip=p ;;
      *) kind=x ;;
      esac
      ;;
    *)
      case "$lang:$ch" in
      py:*)
        tq="${out: -3}"
        ((${#out} < 3)) && tq="$out"
        if [[ "$tq" =~ (^|[^A-Za-z0-9_])([rRbBuUfF]{1,2})$ ]]; then
          pfx="${BASH_REMATCH[2]}"
          out="${out%"$pfx"}"
          [[ "$pfx" == *[rR]* ]] && mode=r
          [[ "$pfx" == *[fF]* ]] && ip=f
        fi
        if [[ "$r" == "$ch$ch"* ]]; then
          r="${r:2}"
          tq="$ch$ch$ch"
          raw="${r%%"$tq"*}"
          if [[ "$raw" == "$r" ]]; then r=""; else r="${r:${#raw}+3}"; fi
          cl=""
        fi
        ;;
      js:"$bt") ip=t ;;
      rb:"$apos" | pl:"$apos") mode=1 ;;
      rb:"$bt") kind=c ip=h ;;
      pl:"$bt") kind=c ip=p ;;
      rb:*) ip=h ;;
      pl:*) ip=p ;;
      *) ;;
      esac
      ;;
    esac
    case "$cl" in
    '(') cl=')' ;;
    '[') cl=']' ;;
    '{') cl='}' ;;
    '<') cl='>' ;;
    *) ;;
    esac
    if [[ -n "$cl" ]]; then
      rdt_ix_until "$cl"
      raw="$RDT_IX_S"
    fi
    rdt_ix_decode "$mode" "$ip" "$raw"
    case "$kind:$RDT_IX_DK" in
    s:*) kind="$RDT_IX_DK" ;;
    c:u) kind=d ;;
    *) ;;
    esac
    out+=$'\001'"$kind${#ix_v[@]}"$'\002'
    ix_v+=("$RDT_IX_DV")
    ix_k+=("$kind")
  done
  ix_m="$out$r"
}

# shellcheck disable=SC1003,SC2329  # '\' is a literal backslash; invoked from rdt_ix_lex
rdt_ix_until() {
  local seg esc bs='\'
  RDT_IX_S=""
  while [[ -n "$r" ]]; do
    seg="${r%%"$1"*}"
    esc="${r%%"$bs"*}"
    ((${#esc} < ${#seg})) && seg="$esc"
    RDT_IX_S+="$seg"
    r="${r:${#seg}}"
    [[ -n "$r" ]] || return 0
    if [[ "$r" == "$bs"* ]]; then
      RDT_IX_S+="${r:0:2}"
      r="${r:2}"
    else
      r="${r:1}"
      return 0
    fi
  done
  return 0
}

# shellcheck disable=SC1003,SC2016,SC2329  # literal text and backslash; invoked from rdt_ix_lex
rdt_ix_decode() {
  local v="$3" bs='\' apos="'" dq='"' bt='`' sl='/' dl='$' ob='{' hs='#' k=s
  case "$1" in
  r) ;;
  1)
    v="${v//"$bs$bs"/$'\001'}"
    v="${v//"$bs$apos"/"$apos"}"
    v="${v//$'\001'/"$bs"}"
    ;;
  *)
    v="${v//"$bs$bs"/$'\001'}"
    v="${v//"$bs$apos"/"$apos"}"
    v="${v//"$bs$dq"/"$dq"}"
    v="${v//"$bs$bt"/"$bt"}"
    v="${v//"$bs$sl"/"$sl"}"
    v="${v//"$bs"$'\n'/}"
    v="${v//"${bs}t"/$'\t'}"
    v="${v//"${bs}n"/$'\n'}"
    v="${v//"${bs}r"/$'\r'}"
    [[ "$v" == *"$bs"* ]] && k=u
    v="${v//$'\001'/"$bs"}"
    ;;
  esac
  case "$2" in
  f)
    if [[ "$v" == *"$ob"* ]]; then
      [[ "$k" == u ]] || k=x
      v="${v//"$ob"/"$dl$ob"}"
    fi
    ;;
  t) [[ "$v" == *"$dl$ob"* && "$k" != u ]] && k=x ;;
  h)
    if [[ "$v" == *"$hs$ob"* || "$v" == *"$hs@"* || "$v" == *"$hs$dl"* ]]; then
      [[ "$k" == u ]] || k=x
      v="${v//"$hs$ob"/"$dl$ob"}"
      v="${v//"$hs@"/"$dl"}"
      v="${v//"$hs$dl"/"$dl"}"
    fi
    ;;
  p)
    if [[ "$v" == *[\$@]* ]]; then
      [[ "$k" == u ]] || k=x
      v="${v//@/"$dl"}"
    fi
    ;;
  *) ;;
  esac
  RDT_IX_DV="$v"
  RDT_IX_DK="$k"
}

# shellcheck disable=SC2016,SC2329  # `$_` is literal text; invoked from rdt_ix_code
rdt_ix_calls() {
  local re="$2" m="$ix_m" name t pl imp
  local re_open='^[[:space:]]*\(' re_bare='^[[:blank:]]+[^][:space:]=,.;)}|&?+*/<>!~{-]'
  local re_end=$'^[[:blank:]]*([;}\n]|$)'
  while [[ "$m" =~ $re ]]; do
    rdt_deadline
    name="${BASH_REMATCH[2]}"
    m="${m#*"${BASH_REMATCH[0]}"}"
    imp=0
    [[ "$lang:$1:$name" == pl:del:unlink || "$lang:$1:$name" == pl:del:rmdir ]] && imp=1
    if [[ "$m" =~ $re_open ]]; then
      t="${m#*"("}"
      pl=0
    elif [[ "$lang" == rb || "$lang" == pl ]] && [[ "$m" =~ $re_bare ]]; then
      t="$m"
      pl=1
    elif ((imp)) && [[ "$m" =~ $re_end ]]; then
      t=""
      pl=1
    else
      continue
    fi
    rdt_ix_split "$t" "$pl"
    if ((imp && ${#RDT_IX_ARGS[@]} == 0)); then
      rdt_ix_unplaceable '$_'
    elif [[ "$1" == del ]]; then
      rdt_ix_del ${RDT_IX_ARGS[@]+"${RDT_IX_ARGS[@]}"}
    else
      rdt_ix_run "$name" ${RDT_IX_ARGS[@]+"${RDT_IX_ARGS[@]}"}
    fi
  done
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_ix_calls
rdt_ix_split() {
  local r="$1" pl="$2" d=0 argbuf="" ch re a kw
  local -a pieces=()
  if ((pl)); then re=$'^([^][(){},;\n]*)([][(){},;\n])'; else re='^([^][(){},]*)([][(){},])'; fi
  while [[ "$r" =~ $re ]]; do
    argbuf+="${BASH_REMATCH[1]}"
    ch="${BASH_REMATCH[2]}"
    r="${r:${#BASH_REMATCH[0]}}"
    case "$ch" in
    '(' | '[' | '{')
      d=$((d + 1))
      argbuf+="$ch"
      ;;
    ',')
      if ((d)); then
        argbuf+="$ch"
      else
        pieces+=("$argbuf")
        argbuf=""
      fi
      ;;
    *)
      if ((d == 0)); then
        r=""
        break
      fi
      if [[ "$ch" != ';' && "$ch" != $'\n' ]]; then d=$((d - 1)); fi
      argbuf+="$ch"
      ;;
    esac
  done
  pieces+=("$argbuf$r")
  RDT_IX_ARGS=()
  for a in "${pieces[@]}"; do
    a="${a#"${a%%[![:space:]]*}"}"
    if ((pl)); then
      a="${a%%&&*}"
      a="${a%%||*}"
      for kw in 'if' 'unless' 'or' 'and' 'while' 'until' 'for' 'foreach' 'do'; do
        [[ "$a" == "$kw" || "$a" == "$kw"[[:blank:]]* ]] && a=""
        a="${a%%[[:blank:]]"$kw"[[:blank:]]*}"
        a="${a%[[:blank:]]"$kw"}"
      done
    fi
    a="${a%"${a##*[![:space:]]}"}"
    [[ -n "$a" ]] && RDT_IX_ARGS+=("$a")
  done
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_ix_calls
rdt_ix_del() {
  local a k=0
  for a in "$@"; do
    k=$((k + 1))
    case "$lang" in
    py | js) ((k > 1)) && break ;;
    rb) [[ "$a" =~ $RDT_IX_KWARG_RE ]] && continue ;;
    *)
      [[ "$a" =~ ^[0-9]+$ ]] && continue
      ((k == $#)) && [[ "$a" == '{'*'}' || "$a" =~ ^\\%[A-Za-z_][A-Za-z0-9_]*$ ]] && continue
      ;;
    esac
    rdt_ix_target "$a"
  done
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_ix_del
rdt_ix_target() {
  local e
  local -a el=("$1")
  if [[ "$1" == '['*']' ]]; then
    rdt_ix_split "${1:1:${#1}-2}" 0
    el=(${RDT_IX_ARGS[@]+"${RDT_IX_ARGS[@]}"})
  fi
  for e in ${el[@]+"${el[@]}"}; do
    if [[ "$e" =~ $RDT_IX_PH_RE ]] && [[ "${BASH_REMATCH[1]}" == s ]]; then
      rdt_ix_path "${ix_v[BASH_REMATCH[2]]}"
    else
      rdt_ix_unplaceable "$e"
    fi
  done
  return 0
}

# shellcheck disable=SC2016,SC2329  # literal text; invoked from rdt_ix_target
rdt_ix_path() {
  local v="$1" h
  case "$v" in
  *'$'* | *'`'*)
    h="${v#\$HOME}"
    [[ "$h" == "$v" ]] && h="${v#\$\{HOME\}}"
    if [[ "$h" != "$v" && (-z "$h" || "$h" == /*) && "$h" != *[\$\`]* ]]; then
      rdt_delete_operand "$v" 2
    else
      rdt_ix_unplaceable "'$v'"
    fi
    ;;
  *) rdt_delete_operand "$v" 3 ;;
  esac
}

# shellcheck disable=SC2329  # invoked from rdt_ix_target, rdt_ix_path, rdt_ix_code and rdt_ix_run
rdt_ix_unplaceable() {
  local s="$1" what="${2:-the path given as}" apos="'"
  while [[ "$s" =~ $RDT_IX_PH_ANY ]]; do
    s="${s/"${BASH_REMATCH[0]}"/"$apos${ix_v[BASH_REMATCH[2]]}$apos"}"
  done
  ((${#s} > 120)) && s="${s:0:120}..."
  rdt_block "interp-unplaceable" "$what $s"
}

# shellcheck disable=SC2329  # invoked from rdt_ix_calls
rdt_ix_run() {
  local name="$1" a w rc
  shift
  local -a ra=() argv=()
  for a in "$@"; do
    if [[ "$lang" == rb ]]; then
      [[ "$a" == '{'*'}' && ${#ra[@]} -eq 0 ]] && continue
      [[ "$a" =~ $RDT_IX_KWARG_RE ]] && continue
    fi
    ra+=("$a")
  done
  ((${#ra[@]})) || return 0
  case "$lang:$name" in
  js:spawn* | js:execFile*)
    rc=0
    rdt_ix_word_to w "${ra[0]}" || rc=$?
    if ((rc == 2)); then
      rdt_ix_unplaceable "${ra[0]}" "the command given as"
      return 0
    fi
    ((rc == 0)) || return 0
    rdt_ix_shell "$w"
    argv=("$w")
    if ((${#ra[@]} > 1)) && [[ "${ra[1]}" == '['*']' ]]; then
      rdt_ix_list "${ra[1]}"
      argv+=(${RDT_IX_L[@]+"${RDT_IX_L[@]}"})
    fi
    rdt_ix_argv "${argv[@]}"
    return 0
    ;;
  rb:* | pl:*)
    if ((${#ra[@]} > 1)); then
      for a in "${ra[@]}"; do
        if rdt_ix_word_to w "$a"; then
          argv+=("$w")
        elif [[ "$a" == '['*']' ]]; then
          rdt_ix_list "$a"
          argv+=(${RDT_IX_L[@]+"${RDT_IX_L[@]}"})
        else
          argv+=("$RDT_IX_HOLE")
        fi
      done
      rdt_ix_argv "${argv[@]}"
      return 0
    fi
    ;;
  *) ;;
  esac
  a="${ra[0]}"
  rc=0
  rdt_ix_word_to w "$a" || rc=$?
  if ((rc == 0)); then
    rdt_ix_shell "$w"
  elif ((rc == 2)); then
    rdt_ix_unplaceable "$a" "the command given as"
  elif [[ "$a" == '['*']' ]]; then
    rdt_ix_list "$a"
    rdt_ix_argv ${RDT_IX_L[@]+"${RDT_IX_L[@]}"}
  fi
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_ix_run and rdt_ix_list
rdt_ix_word_to() {
  [[ "$2" =~ $RDT_IX_PH_RE ]] || return 1
  [[ "${BASH_REMATCH[1]}" == [ud] ]] && return 2
  printf -v "$1" '%s' "${ix_v[BASH_REMATCH[2]]}"
}

# shellcheck disable=SC2329  # invoked from rdt_ix_run
rdt_ix_list() {
  local e w
  rdt_ix_split "${1:1:${#1}-2}" 0
  RDT_IX_L=()
  for e in ${RDT_IX_ARGS[@]+"${RDT_IX_ARGS[@]}"}; do
    if rdt_ix_word_to w "$e"; then RDT_IX_L+=("$w"); else RDT_IX_L+=("$RDT_IX_HOLE"); fi
  done
}

# shellcheck disable=SC2329  # invoked from rdt_ix_run
rdt_ix_argv() {
  (($#)) || return 0
  local k
  local -a q0=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"}) op=(${HOOK_SEG_REDIR_OP[@]+"${HOOK_SEG_REDIR_OP[@]}"})
  HOOK_SEG_WORD_QUOTED=()
  for ((k = 0; k < $#; k++)); do HOOK_SEG_WORD_QUOTED+=(2); done
  HOOK_SEG_REDIR_OP=()
  rdt_check_segment "$@"
  HOOK_SEG_WORD_QUOTED=(${q0[@]+"${q0[@]}"})
  HOOK_SEG_REDIR_OP=(${op[@]+"${op[@]}"})
}

# shellcheck disable=SC2329  # invoked from rdt_ix_code and rdt_ix_run
rdt_ix_shell() {
  local rdt_seg_feed=open
  rdt_scanned=$((rdt_scanned + ${#1}))
  ((rdt_scanned > MAX_COMMAND_LEN)) && rdt_block "eval-too-long"
  rdt_parse "$1"
}

# shellcheck disable=SC2329  # invoked from rdt_find_check and rdt_feed_class
rdt_find_scan() {
  local k w c key del=0 files0=0 follow=0
  local -a sw=() sq=()
  local -A seen=()
  RDT_FIND_OUT=1
  for ((k = $1 + 1; k < n; k++)); do
    case "${words[k]}" in
    -delete) del=1 ;;
    -files0-from) files0=1 RDT_FIND_OUT=0 ;;
    -printf | -fprintf | -ls | -fls) RDT_FIND_OUT=0 ;;
    -H | -L | -follow) follow=1 ;;
    -exec | -execdir | -ok | -okdir)
      RDT_FIND_OUT=0
      k=$((k + 1))
      c="${words[k]-}"
      c="${c##*/}"
      c="${c,,}"
      case "${c%.exe}" in
      rm | rmdir | unlink) del=1 ;;
      *) ;;
      esac
      while ((k < n)) && [[ "${words[k]}" != ';' ]] &&
        [[ "${words[k]}" != '+' || "${words[k - 1]}" != '{}' ]]; do
        k=$((k + 1))
      done
      ;;
    *) [[ "${words[k]}" =~ ^-[EHLPXdsx]*[HL] ]] && follow=1 ;;
    esac
  done
  RDT_FIND_DEL=$del

  k=$(($1 + 1))
  while ((k < n)); do
    case "${words[k]}" in
    -H | -L | -P | -O*) k=$((k + 1)) ;;
    -D) k=$((k + 2)) ;;
    --)
      k=$((k + 1))
      break
      ;;
    *) break ;;
    esac
  done
  while ((k < n)); do
    w="${words[k]}"
    [[ "$w" == -* || "$w" == '(' || "$w" == '!' ]] && break
    sw+=("$w")
    sq+=("${HOOK_SEG_WORD_QUOTED[k]:-0}")
    k=$((k + 1))
  done
  if ((${#sw[@]} == 0 && files0 == 0)); then
    sw+=(.)
    sq+=(0)
  fi

  k=$(($1 + 1))
  while ((k < n)); do
    w="${words[k]}"
    if [[ "$w" == -- ]]; then
      k=$((k + 1))
      break
    elif [[ "$w" =~ ^-[EHLPXdsx]*f(.*)$ ]]; then
      if [[ -n "${BASH_REMATCH[1]}" ]]; then
        sw+=("${BASH_REMATCH[1]}")
        sq+=("${HOOK_SEG_WORD_QUOTED[k]:-0}")
        k=$((k + 1))
      else
        if ((k + 1 < n)); then
          sw+=("${words[k + 1]}")
          sq+=("${HOOK_SEG_WORD_QUOTED[k + 1]:-0}")
        fi
        k=$((k + 2))
      fi
    elif [[ "$w" =~ ^-[EHLPXdsx]+$ ]]; then
      k=$((k + 1))
    else
      break
    fi
  done
  while ((k < n)); do
    w="${words[k]}"
    [[ "$w" == -* || "$w" == '(' || "$w" == '!' ]] && break
    sw+=("$w")
    sq+=("${HOOK_SEG_WORD_QUOTED[k]:-0}")
    k=$((k + 1))
  done

  RDT_FIND_SW=()
  RDT_FIND_SQ=()
  for ((k = 0; k < ${#sw[@]}; k++)); do
    w="${sw[k]}"
    ((follow)) && [[ -n "$w" && "$w" != */ ]] && w+=/
    key="${sq[k]}|$w"
    [[ -n "${seen[$key]+x}" ]] && continue
    seen[$key]=1
    RDT_FIND_SW+=("$w")
    RDT_FIND_SQ+=("${sq[k]}")
  done
  return 0
}

RDT_FW=()
RDT_FQ=()
RDT_LS_ENTRY='(a file git ls-files lists)'
rdt_seg_feed=none
rdt_feed_in=none
rdt_prev=""
rdt_flat=1
rdt_deleter=0
rdt_fed=0

rdt_parse() {
  local rdt_feed_in="$rdt_seg_feed" rdt_prev="" rdt_flat=1 b=$'\\' t="$1" rdt_hd_n=0
  local rdt_dec_prev="${rdt_dec_feed:-0}" rdt_sink=0 rdt_text_prev="${rdt_text_feed:-}"
  [[ "$rdt_text_prev" == h* ]] && rdt_text_prev=""
  local rdt_bq=$'(^|[;&|(\n])[[:space:]]*((then|do|else|elif|if|while|until|!|\\{)[[:space:]]+)*`'
  local -a rdt_hd_lang=() rdt_hd_st=()
  [[ "$1" =~ $rdt_bq ]] && rdt_sink=1
  if [[ "$t" == *"$b"* ]]; then
    t="${t//"$b$b"/}"
    t="${t//"$b("/}"
    t="${t//"$b)"/}"
  fi
  case "$t" in
  *[\(\)\`]*)
    rdt_flat=0
    rdt_feed_in=open
    ;;
  *) ;;
  esac
  local rdt_grp=$'(^|[;&|(\n])[[:space:]]*\\{[[:space:]]'
  if [[ "$t" =~ $rdt_grp ]]; then
    rdt_flat=0
    rdt_feed_in=open
  fi
  hook::bash_parse_segments "$1" rdt_segment
  ((${#rdt_hd_lang[@]} == 0)) || rdt_ix_heredocs "$1"
  return 0
}

# shellcheck disable=SC2329  # invoked as the hook::bash_parse_segments callback
rdt_segment() {
  local -a rdt_sw=() rdt_sq=()
  local rdt_si rdt_sx rdt_sqv
  for ((rdt_si = 1; rdt_si <= $#; rdt_si++)); do
    rdt_sx=${!rdt_si}
    rdt_sqv=${HOOK_SEG_WORD_QUOTED[rdt_si - 1]:-0}
    if [[ "$rdt_sqv" != 2 ]]; then
      # shellcheck disable=SC2016  # literal substitution openers, not expansions
      case "$rdt_sx" in
      '<('* | '>('*) continue ;;
      *'$('*) rdt_sx="${rdt_sx%%'$('*}\$" ;;
      *'`'*)
        rdt_sx="${rdt_sx%%'`'*}"
        [[ -n "$rdt_sx" ]] || continue
        ;;
      *) ;;
      esac
    fi
    rdt_sw+=("$rdt_sx")
    rdt_sq+=("$rdt_sqv")
  done
  HOOK_SEG_WORD_QUOTED=(${rdt_sq[@]+"${rdt_sq[@]}"})
  set -- ${rdt_sw[@]+"${rdt_sw[@]}"}
  local rdt_seg_feed="$rdt_feed_in" j rdt_hd_at="$rdt_hd_n" rdt_dec_feed="$rdt_dec_prev" rdt_dec_out=0
  local rdt_text_feed="$rdt_text_prev" rdt_text_out=""
  if ((rdt_flat == 0)); then
    rdt_seg_feed=open
  elif [[ -n "$rdt_prev" ]]; then
    rdt_seg_feed="$rdt_prev"
    [[ "$rdt_feed_in" == none || "$rdt_feed_in" == "$rdt_prev" ]] || rdt_seg_feed=open
  fi
  for ((j = 0; j < ${#HOOK_SEG_REDIR_OP[@]}; j++)); do
    [[ "${HOOK_SEG_REDIR_OP[j]}" == '<<' || "${HOOK_SEG_REDIR_OP[j]}" == '<<-' ]] && rdt_hd_n=$((rdt_hd_n + 1))
    if [[ "${HOOK_SEG_REDIR_OP[j]}" == '<'* && "${HOOK_SEG_REDIR_FD[j]:-0}" == 0 ]]; then
      rdt_seg_feed=open
      rdt_dec_feed=0
      rdt_text_feed=""
    fi
  done
  rdt_dec_class "$@"
  ((rdt_dec_out && rdt_sink)) && rdt_block "decoder-sink"
  rdt_feed_class "$@"
  rdt_text_class "$@"
  rdt_check_segment "$@"
  rdt_dec_prev=$rdt_dec_out
  rdt_text_prev=$rdt_text_out
}

# shellcheck disable=SC2329  # invoked from rdt_segment
rdt_text_class() {
  rdt_text_out=""
  case "${*,,}" in
  *echo* | *printf* | *cat*) ;;
  *) return 0 ;;
  esac
  local -a words=("$@")
  local n=$# i=0 b k w out nh=0 hd=0 r=-1
  while ((i < n)) && [[ "${words[i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
    i=$((i + 1))
  done
  ((i < n)) || return 0
  b="${words[i]##*/}"
  b="${b,,}"
  b="${b%.exe}"
  case "$b" in
  echo | printf | cat) ;;
  *) return 0 ;;
  esac
  for ((k = 0; k < ${#HOOK_SEG_REDIR_OP[@]}; k++)); do
    [[ "${HOOK_SEG_REDIR_OP[k]}" == '>'* && "${HOOK_SEG_REDIR_FD[k]:-1}" == 1 ]] && return 0
    [[ "${HOOK_SEG_REDIR_OP[k]}" == '<<' || "${HOOK_SEG_REDIR_OP[k]}" == '<<-' ]] && nh=$((nh + 1))
    [[ "${HOOK_SEG_REDIR_OP[k]}" == '<'* && "${HOOK_SEG_REDIR_FD[k]:-0}" == 0 ]] || continue
    r=$k
    hd=$((nh - 1))
  done
  i=$((i + 1))
  case "$b" in
  echo)
    while ((i < n)) && [[ "${words[i]}" =~ ^-[neE]+$ ]]; do
      i=$((i + 1))
    done
    rdt_text_out="e${words[*]:i}"
    ;;
  printf)
    [[ "${words[i]-}" == -- ]] && i=$((i + 1))
    ((i < n)) || return 0
    w="${words[i]}"
    [[ "$w" == -* || "$w" =~ %[^sb%] || "$w" =~ %$ ]] && return 0
    if ((${#w} * (n - i) + ${#*} > MAX_COMMAND_LEN)); then
      rdt_text_out=x
      return 0
    fi
    # shellcheck disable=SC2059  # the command's own format, written out as that printf would
    printf -v out -- "$w" ${words[@]+"${words[@]:i+1}"} 2>/dev/null || return 0
    rdt_text_out="t$out"
    ;;
  *)
    for ((; i < n; i++)); do
      [[ "${words[i]}" == - ]] || return 0
    done
    ((r >= 0)) || return 0
    case "${HOOK_SEG_REDIR_OP[r]}" in
    '<<' | '<<-') [[ -n "${rdt_hd_at-}" ]] && rdt_text_out="h$((rdt_hd_at + hd)):${HOOK_SEG_REDIR_TARGET[r]-}" ;;
    '<<<') rdt_text_out="t${HOOK_SEG_REDIR_TARGET[r]-}" ;;
    *) ;;
    esac
    ;;
  esac
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_segment
rdt_dec_class() {
  if ((rdt_dec_feed == 0)); then
    case "${*,,}" in
    *base64* | *base32* | *basenc* | *xxd*) ;;
    *) return 0 ;;
    esac
  fi
  local -a words=("$@")
  local n=$# i=0 b k w c dec=0 ops=0
  while ((i < n)) && [[ "${words[i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
    i=$((i + 1))
  done
  ((i < n)) || return 0
  for ((k = 0; k < ${#HOOK_SEG_REDIR_OP[@]}; k++)); do
    [[ "${HOOK_SEG_REDIR_OP[k]}" == '>'* && "${HOOK_SEG_REDIR_FD[k]:-1}" == 1 ]] && return 0
  done
  b="${words[i]##*/}"
  b="${b,,}"
  b="${b%.exe}"
  case "$b" in
  base64 | base32 | basenc)
    for ((k = i + 1; k < n; k++)); do
      w="${words[k]}"
      case "$w" in
      --) break ;;
      --d*) dec=1 ;;
      --o*) return 0 ;;
      --*) ;;
      -?*)
        for ((c = 1; c < ${#w}; c++)); do
          case "${w:c:1}" in
          [dD]) dec=1 ;;
          o) return 0 ;;
          [bw]) break ;;
          *) ;;
          esac
        done
        ;;
      *) ;;
      esac
    done
    ;;
  xxd)
    for ((k = i + 1; k < n; k++)); do
      w="${words[k]}"
      if ((ops == 0)) && [[ "$w" == -?* ]]; then
        case "$w" in
        -r*) dec=1 ;;
        -[cglosnR] | -cols | -groupsize | -len | -offset | -seek | -name) k=$((k + 1)) ;;
        *) ;;
        esac
      else
        ops=$((ops + 1))
        ((ops == 2)) && [[ "$w" != - ]] && return 0
      fi
    done
    ;;
  less | more | most) ;;
  *) dec="$rdt_dec_feed" ;;
  esac
  rdt_dec_out=$dec
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_segment
rdt_feed_class() {
  rdt_prev=open
  ((rdt_flat)) || return 0
  local -a words=("$@")
  local n=$# i=0 base w
  while ((i < n)) && [[ "${words[i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
    i=$((i + 1))
  done
  ((i < n)) || return 0
  base="${words[i]##*/}"
  base="${base,,}"
  base="${base%.exe}"
  case "$base" in
  find)
    rdt_find_scan "$i"
    ((RDT_FIND_OUT)) || return 0
    rdt_prev="f${#RDT_FW[@]}:${#RDT_FIND_SW[@]}"
    RDT_FW+=(${RDT_FIND_SW[@]+"${RDT_FIND_SW[@]}"})
    RDT_FQ+=(${RDT_FIND_SQ[@]+"${RDT_FIND_SQ[@]}"})
    ;;
  git)
    [[ "${words[i + 1]-}" == ls-files ]] || return 0
    for ((i = i + 2; i < n; i++)); do
      [[ "${words[i]}" == --f[o]* ]] && return 0
    done
    rdt_prev=g
    ;;
  *) rdt_line_filter "${words[@]:i}" && rdt_prev="$rdt_seg_feed" ;;
  esac
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_feed_class
rdt_line_filter() {
  local c="${1##*/}" f="" a="" w k=2 e=0 max=0
  c="${c,,}"
  c="${c%.exe}"
  case "$c" in
  grep | egrep | fgrep) f=vixwEFGPsqz a=ef max=1 ;;
  sort) f=bdfghiMnRrsuVz a=kt ;;
  uniq) f=diuz ;;
  head | tail) f=z a=n ;;
  *) return 1 ;;
  esac
  while ((k <= $#)); do
    w="${!k}"
    if [[ "$w" == -- ]]; then
      k=$((k + 1))
      break
    elif [[ "$w" =~ ^-[$f]+$ ]]; then
      :
    elif [[ -n "$a" && "$w" =~ ^-[$f]*[$a](.*)$ ]]; then
      e=1
      [[ -n "${BASH_REMATCH[1]}" ]] || k=$((k + 1))
    elif [[ "$c" == head || "$c" == tail ]] && [[ "$w" =~ ^-[0-9]+$ ]]; then
      :
    elif [[ "$w" == -* ]]; then
      return 1
    else
      break
    fi
    k=$((k + 1))
  done
  ((e)) && max=0
  (($# - k + 1 <= max))
}

# shellcheck disable=SC2329  # invoked from rdt_xargs_check and rdt_parallel_check
rdt_feed_judge() {
  local o l k
  case "$1" in
  f*:*)
    o="${1#f}"
    l="${o#*:}"
    o="${o%%:*}"
    for ((k = o; k < o + l; k++)); do
      rdt_delete_operand "${RDT_FW[k]}" "${RDT_FQ[k]}"
    done
    ;;
  g) rdt_delete_operand "$RDT_LS_ENTRY" 2 ;;
  *) rdt_block "pipeline-feed" ;;
  esac
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_xargs_check() {
  local k=$(($1 + 1)) c w x name hit src="$rdt_seg_feed" rdt_deleter=0 rdt_fed=1
  local -a q0=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"})
  while ((k < n)); do
    w="${words[k]}"
    case "$w" in
    --)
      k=$((k + 1))
      break
      ;;
    --?*)
      name="${w#--}"
      name="${name%%=*}"
      hit=""
      for x in arg-file delimiter max-args max-chars max-procs process-slot-var eof replace max-lines null open-tty interactive no-run-if-empty verbose show-limits exit version help; do
        if [[ "$x" == "$name" ]]; then
          hit="$x"
          break
        fi
        if [[ "$x" == "$name"* ]]; then
          [[ -z "$hit" ]] || return 0
          hit="$x"
        fi
      done
      [[ -n "$hit" ]] || return 0
      [[ "$hit" == arg-file ]] && src=open
      case "$hit" in
      arg-file | delimiter | max-args | max-chars | max-procs | process-slot-var)
        [[ "$w" == *=* ]] || k=$((k + 1))
        ;;
      *) ;;
      esac
      ;;
    -?*)
      for ((c = 1; c < ${#w}; c++)); do
        x="${w:c:1}"
        case "$x" in
        [0oprtx]) ;;
        [eil]) break ;;
        [adEIJLnPRSs])
          [[ "$x" == a ]] && src=open
          ((c + 1 < ${#w})) || k=$((k + 1))
          break
          ;;
        *) return 0 ;;
        esac
      done
      ;;
    *) break ;;
    esac
    k=$((k + 1))
  done
  ((k < n)) || return 0
  HOOK_SEG_WORD_QUOTED=(${q0[@]+"${q0[@]:k}"})
  rdt_check_segment "${words[@]:k}"
  HOOK_SEG_WORD_QUOTED=(${q0[@]+"${q0[@]}"})
  ((rdt_deleter)) && rdt_feed_judge "$src"
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_parallel_check() {
  local k j e=$n w pk=p text args=0 files=0 rdt_deleter=0 rdt_fed=1
  local -a starts=() q0=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"})
  for ((k = $1 + 1; k < n; k++)); do
    case "${words[k]}" in
    ::: | :::+)
      ((k < e)) && e=$k
      args=1
      ;;
    :::: | ::::+)
      ((k < e)) && e=$k
      files=1
      ;;
    *) ;;
    esac
  done
  for ((k = $1 + 1; k < e; k++)); do
    w="${words[k]}"
    if [[ "$w" == -- ]]; then
      pk=p
    elif [[ "$w" == -?* ]]; then
      [[ "$w" == --a* || "$w" =~ ^-[^-]*a ]] && files=1
      pk=o
    else
      starts+=("$k")
      [[ "$pk" == o ]] || break
      pk=a
    fi
  done
  for k in ${starts[@]+"${starts[@]}"}; do
    text="${words[k]}"
    for ((j = k + 1; j < e; j++)); do
      text+=" ${words[j]}"
    done
    rdt_scanned=$((rdt_scanned + ${#text}))
    ((rdt_scanned > MAX_COMMAND_LEN)) && rdt_block "eval-too-long"
    rdt_parse "$text"
  done
  if ((rdt_deleter)); then
    if ((files)); then
      rdt_feed_judge open
    elif ((args)); then
      for ((k = e + 1; k < n; k++)); do
        case "${words[k]}" in
        ::: | :::+) ;;
        *) rdt_delete_operand "${words[k]}" "${q0[k]:-0}" ;;
        esac
      done
    else
      rdt_feed_judge "$rdt_seg_feed"
    fi
  fi
  for ((k = e + 1; k < n; k++)); do
    case "${words[k],,}" in
    ::: | :::+ | :::: | ::::+) ;;
    *rm* | *-delete* | *.delete* | *unlink* | *rsync* | *robocopy* | *worktree* | *remove* | *mv* | *truncate* | \
      *shred* | *of=* | *base64* | *base32* | *basenc* | *xxd* | *cmd*rd*) rdt_parse "${words[k]}" ;;
    *) ;;
    esac
  done
  HOOK_SEG_WORD_QUOTED=(${q0[@]+"${q0[@]}"})
  return 0
}

# shellcheck disable=SC2329  # invoked from rdt_check_operand
rdt_strip_tail_to() {
  rdt_strip_nameless_to "$1" "$2" 1
}

RDT_LIT_CH='[A-Za-z0-9_.@%+,:/-]'
RDT_LIT_RESERVED_RE='(^|[[:space:];])(if|then|elif|else|while|until|do|case|repeat)([[:space:];]|$)'
RDT_LIT_MAX_STMTS=64
RDT_LIT_FORBID_RE='(^|[^A-Za-z0-9_])(declare|typeset|local|readonly|export|set|shopt|setopt|alias|trap|printf|read|mapfile|readarray|eval|source|function|IFS|unset|for|select|getopts|let|wait|coproc|enable|compgen|foreach|vared|zparseopts|zstat|stat|integer|float|private|print|sysread|sysopen|strftime|zstyle|zformat|zregexparse|zselect|getln|zmodload|autoload)([^A-Za-z0-9_]|$)|(^|[;&|({[:space:]])\.([[:space:]]|$)|\(\)|\$\{!|<<<|\(\(|\$\[|\{[A-Za-z_][A-Za-z0-9_]*\}[<>]'
RDT_LIT_SPECIAL_RE='^(_.*|.*PATH|.*path|BASH.*|ZSH.*|zsh.*|LC_.*|COMP.*|READLINE.*|HIST.*|hist.*|PROMPT.*|prompt|R?PS[0-9]|dis_.*|IFS|HOME|PWD|OLDPWD|ENV|SHELL|SHELLOPTS|SHLVL|POSIXLY_CORRECT|GLOBIGNORE|EXECIGNORE|FIGNORE|fignore|TMPDIR|TMPPREFIX|DIRSTACK|dirstack|FUNCNAME|FUNCNEST|GROUPS|UID|EUID|GID|EGID|PPID|RANDOM|SRANDOM|SECONDS|LINENO|EPOCHSECONDS|EPOCHREALTIME|epochtime|OPTARG|OPTIND|REPLY|reply|MAPFILE|mapfile|PIPESTATUS|pipestatus|status|argv|ARGC|ARGV0|ERRNO|errnos|signals|options|parameters|commands|functions|aliases|builtins|modules|history|historywords|jobstates|jobtexts|jobdirs|nameddirs|userdirs|funcstack|funcfiletrace|funcsourcetrace|functrace|match|mbegin|mend|MATCH|MBEGIN|MEND|psvar|watch|sysparams|langinfo|terminfo|termcap|widgets|keymaps|patchars|reswords|USERNAME|LOGNAME|TTY|HOST|HOSTNAME|NULLCMD|READNULLCMD|TRY_BLOCK_ERROR|TRY_BLOCK_INTERRUPT|WORDCHARS|ZDOTDIR|LANG|TERM|TMOUT)$'
RDT_LIT_NAME=""
RDT_LIT_VAL=""
rdt_lit_bind() {
  local c="$1" ch="$RDT_LIT_CH" lit n t u re
  lit="(${ch}+|'${ch}+'|\"${ch}+\")"
  re="^([A-Za-z_][A-Za-z0-9_]*)=${lit}[[:blank:]]*(&&|;|"$'\n'")"
  [[ "$c" =~ $re ]] || return 1
  n="${BASH_REMATCH[1]}"
  lit="${BASH_REMATCH[2]}"
  t="${c#"${BASH_REMATCH[0]}"}"
  [[ "$n" =~ $RDT_LIT_SPECIAL_RE ]] && return 1
  re="(^|[^A-Za-z0-9_])${n}(\\[|\\+?=|:=)"
  [[ "$t" =~ $re ]] && return 1
  u="\\\$(${n}|\\{${n}\\})(/${ch}*)?"
  re="(^|[[:space:];&|(])(\"${u}\"|${u})([[:space:];&|)]|\$)"
  while [[ "$t" =~ $re ]]; do
    t="${t/"${BASH_REMATCH[0]}"/"${BASH_REMATCH[1]} ${BASH_REMATCH[7]}"}"
  done
  [[ "$t" == *[\\\'\"\$\`*?[{}]* ]] && return 1
  [[ "$lit" == [\'\"]* ]] && lit="${lit:1:${#lit}-2}"
  [[ "$lit" == -* ]] && return 1
  RDT_LIT_NAME="$n"
  RDT_LIT_VAL="$lit"
}
rdt_lit_shape() {
  local c="$COMMAND" stmt re i
  re="^[^;"$'\n'"]*[;"$'\n'"][[:space:]]*"
  c="${c#"${c%%[![:space:]]*}"}"
  c="${c%"${c##*[![:space:]]}"}"
  [[ "$TOOL_NAME" != "PowerShell" && ! "$c" =~ $RDT_LIT_FORBID_RE ]] || return 0
  for ((i = 0; i <= RDT_LIT_MAX_STMTS; i++)); do
    rdt_lit_bind "$c" && return 0
    [[ "$c" =~ $re ]] || return 0
    stmt="${BASH_REMATCH[0]}"
    [[ "$stmt" == *[\&\|#\(\)\\\'\"\$\`*?[{}!]* || "$stmt" == *'<<'* || "$stmt" =~ $RDT_LIT_RESERVED_RE ]] && return 0
    c="${c#"$stmt"}"
  done
}
rdt_lit_shape

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_check_operand() {
  local w="$1" norm raw
  if [[ -n "$RDT_LIT_NAME" ]] && ((rdt_depth == 1 && rdt_in_subst == 0)); then
    case "$w" in
    "\$$RDT_LIT_NAME" | "\$$RDT_LIT_NAME"/*) w="$RDT_LIT_VAL${w#"\$$RDT_LIT_NAME"}" ;;
    "\${$RDT_LIT_NAME}" | "\${$RDT_LIT_NAME}"/*) w="$RDT_LIT_VAL${w#"\${$RDT_LIT_NAME}"}" ;;
    *) ;;
    esac
  fi
  rdt_normalize_to norm "$w"
  if rdt_is_root "$norm"; then
    rdt_block "root-operand" "$norm"
  fi
  rdt_strip_tail_to raw "${w,,}"
  if rdt_bare_var "$norm" || rdt_bare_var "$raw"; then
    rdt_block "bare-variable" "$w"
  fi
  if ((${2:-0} < 2)) && { [[ "$TOOL_NAME" != "PowerShell" ]] || ((RDT_PS_BASHC)); } && rdt_led_by_unbound "$w"; then
    rdt_block "bare-variable" "$w"
  fi
  if ((RDT_ARM)); then
    ((RDT_CWD_NUL)) && rdt_block "nul-field" "cwd"
    rdt_deadline
    RDT_P_TEXT+=("$w")
    RDT_P_Q+=("$2")
    RDT_P_NORIG+=("${#RDT_ORIGINS[@]}")
    RDT_P_UNK+=("$rdt_cd_unknown")
    RDT_P_REF+=("$rdt_cd_refuse")
    RDT_P_SUB+=("$rdt_in_subst")
    RDT_P_WT+=("$RDT_WTRM")
    ((RDT_PS_BASHC)) || RDT_P_PSDOT=1
  fi
  return 0
}

MAX_BRACE=64
MAX_BRACE_WORD=4096
MAX_BRACE_OPEN=128
MAX_OPERAND_LEN=4096
MAX_OPERAND_DEPTH=128

# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_brace_expand() {
  RDT_BX=()
  rdt_brace_rec "$1"
}
# shellcheck disable=SC2329  # invoked from rdt_brace_expand and itself
rdt_brace_rec() {
  local s="$1" n=${#1} i=0 j d st c pre post
  local -a parts=()
  local re_seq='^(-?[0-9]+\.\.-?[0-9]+|[A-Za-z]\.\.[A-Za-z])(\.\.-?[0-9]+)?$'
  while ((i < n)); do
    c="${s:i:1}"
    if [[ "$c" == '$' && "${s:i+1:1}" == '{' ]]; then
      d=0
      for ((j = i + 1; j < n; j++)); do
        case "${s:j:1}" in
        '{') d=$((d + 1)) ;;
        '}')
          d=$((d - 1))
          ((d == 0)) && break
          ;;
        *) ;;
        esac
      done
      ((j < n)) || break
      i=$j
    elif [[ "$c" == '{' ]]; then
      rdt_deadline
      d=0
      parts=()
      st=$((i + 1))
      for ((j = i; j < n; j++)); do
        case "${s:j:1}" in
        '{') d=$((d + 1)) ;;
        '}')
          d=$((d - 1))
          if ((d == 0)); then
            parts+=("${s:st:j-st}")
            break
          fi
          ;;
        ,)
          if ((d == 1)); then
            parts+=("${s:st:j-st}")
            st=$((j + 1))
          fi
          ;;
        *) ;;
        esac
      done
      if ((j < n)); then
        if ((${#parts[@]} > 1)); then
          pre="${s:0:i}"
          post="${s:j+1}"
          for c in "${parts[@]}"; do
            rdt_brace_rec "$pre$c$post" || return 2
          done
          return 0
        fi
        [[ "${parts[0]}" =~ $re_seq ]] && return 2
      fi
    fi
    i=$((i + 1))
  done
  RDT_BX+=("$s")
  ((${#RDT_BX[@]} <= MAX_BRACE)) || return 2
  return 0
}

rdt_scanned=0
RDT_BPS_SPAN="block-root-delete-target: a substitution or heredoc body, or a program a shell reads, lifted from the command"
rdt_scan_body() {
  local b="$1" rdt_seg_feed=open rdt_dec_feed=0 rdt_text_feed=""
  [[ -n "$b" ]] || return 0
  # shellcheck disable=SC2034  # read by hook::_bps_refuse through dynamic scope
  local HOOK_BPS_SPAN="$RDT_BPS_SPAN"
  case "${b,,}" in
  *rm* | *-delete* | *.delete* | *unlink* | *rsync* | *robocopy* | *worktree* | *remove* | *mv* | *truncate* | \
    *shred* | *of=* | *base64* | *base32* | *basenc* | *xxd* | *cmd*rd*) ;;
  *) return 0 ;;
  esac
  [[ "${rdt_span_gate:-}" == word ]] && rdt_span_prose "$b" && return 0
  local rdt_span_gate=
  rdt_scanned=$((rdt_scanned + ${#b}))
  ((rdt_scanned > MAX_COMMAND_LEN)) && rdt_block "bodies-too-long"
  rdt_parse "$b"
}

rdt_span_prose() {
  local lb="${1,,}" st
  local meta_re='[]$|<>{}[*?~!@^]' esc_re='\\([^ntr]|$|.[a-z0-9_])'
  local word_re='(^|[^a-z0-9_])(rm|unlink|rsync|robocopy|worktree|remove|mv|truncate|shred|delete|base64|base32|basenc|xxd|cmd|(sh|bash|zsh|dash|ksh|mksh|eval|source|python|pypy|py|node|nodejs|perl|ruby|php|lua|deno|bun|tclsh|awk|gawk|mawk|nawk|osascript|pwsh|powershell)[0-9.]*([^a-z0-9_]|$))|of='
  [[ "$lb" =~ $meta_re || "$lb" =~ $esc_re ]] && return 1
  st="${lb//[\'\"\`\\]/}"
  [[ "$lb"$'\n'"$st"$'\n'"${st//[$'\n\r']/}" =~ $word_re ]] && return 1
  return 0
}

rdt_hd_plain() {
  case "$1" in
  *[\;\&\|\(\)\`\$\<\>]*) return 1 ;; # portability-ok: a bash case-pattern bracket of escaped operators, not a GNU grep word boundary
  *) return 0 ;;
  esac
}

rdt_hd_reader() {
  local -a hr_words
  local -i j
  read -r -a hr_words <<<"$1"
  case "${hr_words[0]:-}" in
  cat) return 0 ;;
  gh)
    case "${hr_words[1]:-}" in
    pr | issue | api | release) return 0 ;;
    *) return 1 ;;
    esac
    ;;
  git)
    [[ "$1" == *[\'\"\\]* ]] && return 1
    case "${hr_words[1]:-}" in
    commit | tag)
      for ((j = 2; j + 1 < ${#hr_words[@]}; j++)); do
        [[ "${hr_words[j]}" == -- ]] && return 1
        [[ "${hr_words[j]}" == -F && "${hr_words[j + 1]}" == - ]] && return 0
      done
      return 1
      ;;
    *) return 1 ;;
    esac
    ;;
  *) return 1 ;;
  esac
}

rdt_hd_interp() {
  local t="$1" stmt before bq w0
  local rebind_re='(^|[^A-Za-z0-9_])(hash|exec)([^A-Za-z0-9_]|$)'
  stmt="${t##*$'\n'}"
  stmt="${stmt##*[;&|]}"
  before="${t:0:${#t}-${#stmt}}"
  if [[ "$stmt" =~ ^[[:blank:]]*(python|python3|python3\.[0-9]+)([[:blank:]]+-[BEIOPqRsSuv]+)*([[:blank:]]+-)?[[:blank:]]*$ ]] ||
    [[ "$stmt" =~ ^[[:blank:]]*(node|nodejs)([[:blank:]]+-)?[[:blank:]]*$ ]]; then
    w0="${BASH_REMATCH[1]}"
  else
    return 1
  fi
  [[ "$before" == *[\\\<\>\{\}\(\)]* ]] && return 1 # portability-ok: a bash case-pattern bracket of escaped characters, not a GNU grep word boundary
  bq="${before//\$[\'\"]/}"
  bq="$before"$'\n'"${bq//[\'\"\`]/}"
  [[ "$bq" == *PATH* || "$bq" == *"$w0"* ]] && return 1
  [[ "$bq" =~ $rebind_re || "$bq" =~ $RDT_LIT_RESERVED_RE || "$bq" =~ $RDT_LIT_FORBID_RE ]] && return 1
  return 0
}

rdt_scan_gated() {
  local rdt_span_gate=word
  rdt_scan_substitutions "$1" nested
}

# shellcheck disable=SC1003  # '\' compares a literal backslash char, not a quote escape
rdt_scan_substitutions() {
  local s="$1" q="" c nx
  local -i len=${#s} i=0 pd=0 sd=0 k st ansi=0 hok hs hq hi
  local -a st_start=() st_q=() st_kind=() hd_delim=() hd_strip=() hd_quoted=() hd_sfx=() hd_interp=()
  local hd line lc body pre hfull nested="${2:-}"
  local hd_word_re="^('[A-Za-z0-9_]+'|\"[A-Za-z0-9_]+\"|\\\\[A-Za-z0-9_]+)$"
  local -i hstart hend hcmt=-1
  local -a hd_body=()
  while ((i < len)); do
    c="${s:i:1}"
    if [[ -z "$q" && "$c" == $'\n' ]] && ((${#hd_delim[@]})); then
      for ((k = 0; k < ${#hd_delim[@]}; k++)); do
        hend=$i
        ((hcmt >= hd_sfx[k])) && hend=$hcmt
        rdt_hd_plain "${s:hd_sfx[k]:hend - hd_sfx[k]}" || hd_quoted[k]=0
        [[ "${s:hd_sfx[k]:hend - hd_sfx[k]}" == *[![:space:]]* ]] && hd_interp[k]=0
      done
      i=$((i + 1))
      hd_body=()
      for ((k = 0; k < ${#hd_delim[@]}; k++)); do
        body=""
        while ((i < len)); do
          line="${s:i}"
          line="${line%%$'\n'*}"
          i=$((i + ${#line} + 1))
          lc="$line"
          if ((hd_strip[k])); then
            while [[ "$lc" == $'\t'* ]]; do lc="${lc#?}"; done
          fi
          [[ "$lc" == "${hd_delim[k]}" ]] && break
          body+="$line"$'\n'
        done
        hd_body+=("$body")
      done
      [[ "${s:i}" == *[![:space:]]* ]] && hd_quoted=()
      for ((k = 0; k < ${#hd_body[@]}; k++)); do
        if ((${hd_quoted[k]:-0})); then
          :
        elif ((${hd_interp[k]:-0})); then
          rdt_scan_gated "${hd_body[k]}"
        else
          rdt_scan_substitutions "${hd_body[k]}" nested
        fi
      done
      hd_delim=()
      hd_strip=()
      hd_quoted=()
      hd_sfx=()
      hd_interp=()
      hcmt=-1
      continue
    fi
    if [[ -z "$q" && "$c" == '<' && "${s:i+1:1}" == '<' && "${s:i+2:1}" != '<' ]] &&
      { ((i == 0)) || [[ "${s:i-1:1}" != '<' ]]; }; then
      hok=1
      for ((k = 0; k < pd; k++)); do
        ((st_kind[k] == 1)) || {
          hok=0
          break
        }
      done
      if ((hok)); then
        hfull="${s:0:i}"
        pre="${hfull##*$'\n'}"
        i=$((i + 2))
        hs=0
        hq=0
        hd=""
        if [[ "${s:i:1}" == '-' ]]; then
          hs=1
          i=$((i + 1))
        fi
        while [[ "${s:i:1}" == ' ' || "${s:i:1}" == $'\t' ]]; do i=$((i + 1)); done
        hstart=$i
        while ((i < len)); do
          c="${s:i:1}"
          case "$c" in
          ' ' | $'\t' | $'\n' | ';' | '&' | '|' | '<' | '>' | '(' | ')' | '`') break ;;
          "'" | '"')
            hq=1
            i=$((i + 1))
            while ((i < len)) && [[ "${s:i:1}" != "$c" ]]; do
              hd+="${s:i:1}"
              i=$((i + 1))
            done
            i=$((i + 1))
            ;;
          '\')
            hq=1
            hd+="${s:i+1:1}"
            i=$((i + 2))
            ;;
          *)
            hd+="$c"
            i=$((i + 1))
            ;;
          esac
        done
        if ! [[ -z "$nested" && hcmt -lt 0 && "$pre" == "$hfull" && "${s:hstart:i-hstart}" =~ $hd_word_re ]] ||
          ! { ((pd == 0)) && rdt_hd_plain "$pre" && rdt_hd_reader "$pre"; }; then
          hq=0
        fi
        hi=0
        if [[ -z "$nested" && hcmt -lt 0 && "${s:hstart:i-hstart}" =~ $hd_word_re ]] &&
          ((pd == 0)) && rdt_hd_interp "$hfull"; then
          hi=1
        fi
        hd_delim+=("$hd")
        hd_strip+=("$hs")
        hd_quoted+=("$hq")
        hd_sfx+=("$i")
        hd_interp+=("$hi")
        continue
      fi
    fi
    if [[ "$q" == "'" ]]; then
      if ((ansi)) && [[ "$c" == '\' ]]; then
        i=$((i + 2))
        continue
      fi
      if [[ "$c" == "'" ]]; then
        q=""
        ansi=0
      fi
      i=$((i + 1))
      continue
    fi
    if [[ "$c" == '\' ]]; then
      if [[ "$q" == '"' ]]; then
        nx="${s:i+1:1}"
        case "$nx" in
        '"' | '$' | '`' | '\') i=$((i + 2)) ;;
        *) i=$((i + 1)) ;;
        esac
      else
        i=$((i + 2))
      fi
      continue
    fi
    if [[ -z "$q" ]]; then
      if [[ "$c" == '#' ]] && ((hcmt < 0)) &&
        { ((i == 0)) || [[ "${s:i-1:1}" == [[:space:]\;\&\|\(\)] ]]; }; then
        hcmt=$i
      elif [[ "$c" == $'\n' ]]; then
        hcmt=-1
      fi
    fi
    case "$c" in
    '"')
      if [[ "$q" == '"' ]]; then q=""; else q='"'; fi
      ;;
    "'")
      if [[ "$q" != '"' ]]; then
        q="'"
        ((i > 0)) && [[ "${s:i-1:1}" == '$' ]] && ansi=1
      fi
      ;;
    '$')
      if [[ "${s:i+1:1}" == '(' ]]; then
        if [[ "${s:i+2:1}" == '(' ]]; then
          i=$((i + 1))
          continue
        fi
        sd=$((sd + 1))
        ((sd > MAX_SUBST_DEPTH)) && rdt_block "nesting-too-deep"
        st_kind[pd]=1
        st_start[pd]=$((i + 2))
        st_q[pd]="$q"
        pd=$((pd + 1))
        q=""
        i=$((i + 2))
        continue
      fi
      ;;
    '(')
      if [[ "$q" != '"' ]]; then
        st_kind[pd]=0
        st_start[pd]=-1
        st_q[pd]="$q"
        pd=$((pd + 1))
      fi
      ;;
    ')')
      if [[ "$q" != '"' ]] && ((pd > 0)) && ((st_kind[pd - 1] != 2)); then
        pd=$((pd - 1))
        q="${st_q[pd]}"
        if ((st_kind[pd] == 1)); then
          sd=$((sd - 1))
          st=${st_start[pd]}
          rdt_scan_body "${s:st:i - st}"
        fi
      fi
      ;;
    '`')
      if ((pd > 0)) && ((st_kind[pd - 1] == 2)); then
        pd=$((pd - 1))
        q="${st_q[pd]}"
        sd=$((sd - 1))
        st=${st_start[pd]}
        rdt_scan_body "${s:st:i - st}"
      else
        sd=$((sd + 1))
        ((sd > MAX_SUBST_DEPTH)) && rdt_block "nesting-too-deep"
        st_kind[pd]=2
        st_start[pd]=$((i + 1))
        st_q[pd]="$q"
        pd=$((pd + 1))
        q=""
      fi
      ;;
    *) ;;
    esac
    i=$((i + 1))
  done
  for ((k = 0; k < pd; k++)); do
    ((st_kind[k] == 0)) && continue
    st=${st_start[k]}
    rdt_scan_body "${s:st}"
  done
}

rdt_ps_piped=0
RDT_PS_LIT=""
for rdt_b in $'\002' $'\003' $'\004' $'\005' $'\006' $'\007' $'\010' $'\013' \
  $'\014' $'\016' $'\017' $'\020' $'\021' $'\022' $'\023' $'\024' $'\025' \
  $'\026' $'\027' $'\030' $'\031' $'\032' $'\033' $'\034' $'\035' $'\036' $'\037'; do
  if [[ "$COMMAND" != *"$rdt_b"* ]]; then
    RDT_PS_LIT="$rdt_b"
    break
  fi
done
rdt_ps_lit_kept=1
# shellcheck disable=SC2329  # invoked through hook::_c_locale
rdt_ps_quote_gap() {
  [[ "$COMMAND" == *'<#'* || "$COMMAND" == *'@"'* || "$COMMAND" == *"@'"* || "$COMMAND" == *[![:ascii:]]* ]] ||
    [[ ( "$COMMAND" == *\$\(* || "$COMMAND" == *\$\{* ) && "$COMMAND" == *'"'* ]]
}
hook::_c_locale rdt_ps_quote_gap && rdt_ps_lit_kept=0

rdt_ps_cmd_split_to() {
  local -n __cs_out="$1"
  local __s="$2" __n=${#2} __i=0 __w="" __q=0 __in=0 __c
  __cs_out=()
  while ((__i < __n)); do
    __c="${__s:__i:1}"
    if ((__q)); then
      if [[ "$__c" == '"' ]]; then
        __q=0
      else
        __w+="$__c"
      fi
      __in=1
    else
      case "$__c" in
      '"')
        __q=1
        __in=1
        ;;
      [[:space:]])
        if ((__in)); then
          __cs_out+=("$__w")
          __w=""
          __in=0
        fi
        ;;
      *)
        __w+="$__c"
        __in=1
        ;;
      esac
    fi
    __i=$((__i + 1))
  done
  if ((__in)); then
    __cs_out+=("$__w")
  fi
}

rdt_ps_operand() {
  local w="$1" lit="" re_stream
  [[ -z "$RDT_PS_LIT" && "$w" == *'$'* ]] && rdt_block "control-bytes" "$w"
  if [[ -n "$RDT_PS_LIT" && "$w" == *"$RDT_PS_LIT"* ]]; then
    if [[ "$w" != *'$'* ]]; then
      lit="$w"
      re_stream='^(.+):[^:/\\]*:'"$RDT_PS_LIT"'[A-Za-z0-9_]+$'
      if [[ "$lit" =~ $re_stream ]]; then
        lit="${BASH_REMATCH[1]}"
        [[ "$lit" =~ ^[A-Za-z]$ ]] && lit+=":"
      fi
      lit="${lit//"$RDT_PS_LIT"/\$}"
      if ((rdt_ps_lit_kept)); then
        rdt_check_operand "$lit" 4
        return 0
      fi
    fi
    w="${w//"$RDT_PS_LIT"/\$}"
  fi
  [[ -n "$lit" ]] && rdt_check_operand "$lit" 4
  w="${w//\$\{[eE][nN][vV]:/\$\{}"
  w="${w//\$[eE][nN][vV]:/\$}"
  rdt_check_operand "$w" 0
}

rdt_ps_robocopy_check() {
  local -a __w=() __tg=()
  local __p __k
  for __p in "$@"; do
    [[ "$__p" == "--%" ]] || __w+=("$__p")
  done
  rdt_robocopy_scan 0 '' ${__w[@]+"${__w[@]}"}
  ((RDT_RC_DEST || RDT_RC_SRC)) || return 0
  for __k in ${RDT_RC_OP[@]+"${RDT_RC_OP[@]}"}; do
    case "${__w[__k]}" in
    *'$'* | '(' | '{' | '('* | '@('*)
      for __p in "${RDT_RC_OP[@]}"; do
        __tg+=("${__w[__p]}")
      done
      break
      ;;
    *) ;;
    esac
  done
  if ((${#__tg[@]} == 0)); then
    ((RDT_RC_SRC && ${#RDT_RC_OP[@]} > 0)) && __tg+=("${__w[RDT_RC_OP[0]]}")
    ((RDT_RC_DEST && ${#RDT_RC_OP[@]} > 1)) && __tg+=("${__w[RDT_RC_OP[1]]}")
  fi
  for __p in ${__tg[@]+"${__tg[@]}"}; do
    [[ -z "$__p" ]] && rdt_block "empty-operand"
    # shellcheck disable=SC2016  # a literal `$(` grouping
    case "$__p" in
    '(' | '{' | '('* | '$('* | '@('*) rdt_block "pipeline-target" "$__p" ;;
    *) ;;
    esac
    rdt_ps_operand "$__p"
  done
  return 0
}

rdt_ps_cmd_rd() {
  local -a __cw=("$@")
  ((${#__cw[@]})) || return 0
  local __base="${__cw[0],,}" __i __rec=0 __del=0
  __base="${__base##*[\\/]}"
  __base="${__base%.exe}"
  case "$__base" in
  rd | rmdir) ;;
  del | erase) __del=1 ;;
  robocopy)
    rdt_ps_robocopy_check "${__cw[@]:1}"
    return 0
    ;;
  *) return 0 ;;
  esac
  local -a __paths=()
  for ((__i = 1; __i < ${#__cw[@]}; __i++)); do
    if ((__del)); then
      case "${__cw[__i]}" in
      /*) [[ "${__cw[__i],,}" =~ (^|/)[^a/]*s ]] && __rec=1 ;;
      *) __paths+=("${__cw[__i]}") ;;
      esac
      continue
    fi
    case "${__cw[__i],,}" in
    /s | /s/q | /q/s | /sq | /qs) __rec=1 ;;
    /q | /f) ;;
    /*)
      [[ "${__cw[__i],,}" == /s* ]] && __rec=1
      ;;
    *) __paths+=("${__cw[__i]}") ;;
    esac
  done
  ((__rec)) || return 0
  ((__del && ${#__paths[@]} == 0)) && return 0
  ((${#__paths[@]})) || rdt_block "empty-operand"
  local __p
  for __p in "${__paths[@]}"; do
    [[ -n "$__p" ]] || rdt_block "empty-operand"
    rdt_ps_operand "$__p"
  done
}

rdt_cmd_pct_to() {
  local __pw="$2" __po="" __pm __re='%([A-Za-z_][A-Za-z0-9_]*)%'
  while [[ "$__pw" =~ $__re ]]; do
    __pm="${BASH_REMATCH[0]}"
    __po+="${__pw%%"$__pm"*}\${${BASH_REMATCH[1]}}"
    __pw="${__pw#*"$__pm"}"
  done
  printf -v "$1" '%s' "$__po$__pw"
}

rdt_ps_cmd_line() {
  local __w __b
  local -a __st=()
  for __w in "$@" '&'; do
    case "$__w" in
    '&' | '&&' | '|' | '||')
      if ((${#__st[@]})); then
        __b="${__st[0],,}"
        __b="${__b##*[\\/]}"
        __b="${__b%.exe}"
        case "$__b" in
        pwsh | powershell) rdt_ps_shell_from "${__st[@]:1}" ;;
        bash | sh | zsh | dash | ksh | mksh | wsl) rdt_ps_bash_from "$__b" "${__st[@]:1}" ;;
        *) rdt_ps_cmd_rd "${__st[@]}" ;;
        esac
      fi
      __st=()
      ;;
    *)
      rdt_cmd_pct_to __w "$__w"
      __st+=("$__w")
      ;;
    esac
  done
  return 0
}

rdt_ps_bash_from() {
  local -a __bw=("$@")
  local __k
  if [[ -n "$RDT_PS_LIT" ]]; then
    for ((__k = 0; __k < ${#__bw[@]}; __k++)); do
      __bw[__k]="${__bw[__k]//"$RDT_PS_LIT"/\$}"
    done
  fi
  hook::shell_c_operand "${__bw[@]}" || return 0
  local rdt_depth=$((rdt_depth + 1))
  ((rdt_depth > MAX_SEGMENT_DEPTH)) && rdt_block "nesting-too-deep-launcher"
  local RDT_PS_BASHC=$RDT_PS_BASHC
  case "$1" in
  bash | sh | dash | mksh) RDT_PS_BASHC=1 ;;
  *) ;;
  esac
  rdt_shell_prog "$HOOK_SHELL_C_OPERAND" 0
}

rdt_ps_cmd_from() {
  local -a __a=("$@")
  local __i=0 __t
  local -a __parts=()
  while ((__i < ${#__a[@]})); do
    __t="${__a[__i],,}"
    case "$__t" in
    /c | /k)
      __i=$((__i + 1))
      ((__i < ${#__a[@]})) || return 0
      if ((__i == ${#__a[@]} - 1)); then
        rdt_ps_cmd_split_to __parts "${__a[__i]}"
        rdt_ps_cmd_line ${__parts[@]+"${__parts[@]}"}
      else
        rdt_ps_cmd_line "${__a[@]:__i}"
      fi
      return 0
      ;;
    /c?* | /k?*)
      rdt_ps_cmd_split_to __parts "${__a[__i]:2}"
      rdt_ps_cmd_line ${__parts[@]+"${__parts[@]}"}
      return 0
      ;;
    *) ;;
    esac
    __i=$((__i + 1))
  done
}

# rdt_ps_ri_check <word>...: the words after a Remove-Item family command word.
# shellcheck disable=SC2016,SC2329  # literal `$(` grouping; invoked from rdt_ps_statement
rdt_ps_ri_check() {
  local -a __w=("$@")
  local __i=0 __rec=0 __param __att __vm
  local -a __paths=()
  while ((__i < ${#__w[@]})); do
    local __v="${__w[__i]}"
    if [[ "$__v" == -* && "$__v" != - ]]; then
      rdt_ps_pick_to __param "$__v" confirm credential debug erroraction errorvariable \
        exclude filter force include informationaction informationvariable literalpath \
        outbuffer outvariable pipelinevariable path recurse stream usetransaction verbose \
        warningaction warningvariable whatif
      case "${__v,,}" in
      -rf | -fr | -rf:* | -fr:*) __rec=1 ;;
      *) ;;
      esac
      case "$__param" in
      recurse)
        if [[ "$__v" == *:* ]]; then
          __att="${__v#*:}"
          [[ -n "$RDT_PS_LIT" ]] && __att="${__att//"$RDT_PS_LIT"/\$}"
          __att="${__att,,}"
          __att="${__att#\$}"
          if [[ "$__att" != "false" && "$__att" != "0" ]]; then
            __rec=1
          fi
        else
          __rec=1
        fi
        ;;
      path | literalpath)
        if [[ "$__v" == *:* && "$__v" != *: ]]; then
          __paths+=("${__v#*:}")
        else
          __i=$((__i + 1))
          while ((__i < ${#__w[@]})) && { [[ "${__w[__i]}" != -* ]] || [[ "${__w[__i]}" == - ]]; }; do
            __paths+=("${__w[__i]}")
            __i=$((__i + 1))
          done
          __i=$((__i - 1))
        fi
        ;;
      filter | include | exclude | credential | stream | erroraction | warningaction | \
        informationaction | errorvariable | warningvariable | informationvariable | \
        outvariable | outbuffer | pipelinevariable)
        [[ "$__v" == *:* ]] || __i=$((__i + 1))
        ;;
      *) ;;
      esac
    else
      __vm="$__v"
      [[ -n "$RDT_PS_LIT" ]] && ((!rdt_ps_lit_kept)) && __vm="${__v//"$RDT_PS_LIT"/\$}"
      case "$__vm" in
      /s | /s/q | /q/s | /sq | /qs) ;;
      '('* | '$('*) rdt_block "pipeline-target" "$__vm" ;;
      *) __paths+=("$__v") ;;
      esac
    fi
    __i=$((__i + 1))
  done
  local __p
  for __p in ${__paths[@]+"${__paths[@]}"}; do
    case "${__p,,}" in
    '$_' | '$_.'* | '$psitem' | '$psitem.'*) rdt_ps_lvl_item=1 ;;
    *) ;;
    esac
  done
  if ((${#__paths[@]} == 0 && rdt_ps_piped)); then
    rdt_ps_list_judge "$rdt_ps_feed_in" ${rdt_ps_feed[@]+"${rdt_ps_feed[@]}"} && return 0
    ((__rec)) && rdt_block "pipeline-target"
    return 0
  fi
  ((__rec)) || return 0
  ((${#__paths[@]})) || rdt_block "empty-operand"
  for __p in "${__paths[@]}"; do
    [[ -n "$__p" ]] || rdt_block "empty-operand"
    [[ "$__p" == "(" || "$__p" == "{" ]] && rdt_block "pipeline-target" "$__p"
    rdt_ps_operand "$__p"
  done
}

rdt_ps_take() {
  RDT_PS_ARG="${__w[__i]}"
  while ((__i + 1 < ${#__w[@]})) && [[ "$RDT_PS_ARG" == *, || "$RDT_PS_ARG" == @ || "${__w[__i + 1]}" == ,* ]]; do
    __i=$((__i + 1))
    RDT_PS_ARG+="${__w[__i]}"
  done
}

# shellcheck disable=SC2016  # a literal `$(` grouping
rdt_ps_move_check() {
  local __kind="$1" __i __n __v __e __fp="" __pos=0 __multi=0
  shift
  local -a __w=("$@") __names=() __pv=() __pw=()
  case "$__kind" in
  move) __names=(path literalpath pspath lp destination force filter include exclude passthru credential whatif confirm) ;;
  clear) __names=(path literalpath pspath lp filter include exclude force credential whatif confirm stream) ;;
  *) __names=(path literalpath pspath lp value passthru filter include exclude force credential whatif confirm nonewline encoding asbytestream stream) ;;
  esac
  for ((__i = 0; __i < ${#__w[@]}; __i++)); do
    if [[ "${__w[__i]}" == -?* ]]; then
      __v="${__w[__i]}"
      rdt_ps_pick_to __n "$__v" "${__names[@]}" "${RDT_PS_COMMON[@]}"
      case "$__n" in
      path | literalpath | pspath | lp | destination | value | filter | include | exclude | credential | stream | encoding) ;;
      *) rdt_ps_common_val "$__n" || continue ;;
      esac
      if [[ "$__v" == *:?* ]]; then
        RDT_PS_ARG="${__v#*:}"
      elif ((__i + 1 < ${#__w[@]})); then
        __i=$((__i + 1))
        rdt_ps_take
      else
        continue
      fi
      case "$__n" in
      path) __pv+=("$RDT_PS_ARG") __pw+=(1) ;;
      literalpath | pspath | lp) __pv+=("$RDT_PS_ARG") __pw+=(0) ;;
      *) ;;
      esac
      continue
    fi
    rdt_ps_take
    __pos=$((__pos + 1))
    ((__pos == 1)) && __fp="$RDT_PS_ARG"
  done
  if ((${#__pv[@]} == 0 && __pos > 0)); then
    __pv=("$__fp")
    __pw=(1)
  fi
  if ((${#__pv[@]} == 0)); then
    ((rdt_ps_piped)) || return 0
    rdt_ps_list_judge "$rdt_ps_feed_in" ${rdt_ps_feed[@]+"${rdt_ps_feed[@]}"} && return 0
    [[ "$__kind" == move ]] && rdt_block "pipeline-target"
    return 0
  fi
  local -a __el=()
  for ((__i = 0; __i < ${#__pv[@]}; __i++)); do
    __v="${__pv[__i]}"
    if [[ -z "$__v" ]]; then
      __el+=("")
      continue
    fi
    while [[ -n "$__v" ]]; do
      __e="${__v%%,*}"
      if [[ "$__v" == *,* ]]; then
        __v="${__v#*,}"
      else
        __v=""
      fi
      [[ -n "$__e" ]] || continue
      ((__pw[__i])) && [[ "$__e" == *['*?[']* ]] && __multi=1
      __el+=("$__e")
    done
  done
  ((${#__el[@]} > 1)) && __multi=1
  for __e in ${__el[@]+"${__el[@]}"}; do
    case "${__e,,}" in
    '$_' | '$_.'* | '$psitem' | '$psitem.'*) __multi=2 ;;
    *) ;;
    esac
  done
  [[ "$__kind" == set ]] && ((__multi == 0)) && return 0
  ((__multi == 2)) && rdt_ps_lvl_item=1
  for __e in ${__el[@]+"${__el[@]}"}; do
    if [[ -z "$__e" ]]; then
      rdt_block "empty-operand"
      continue
    fi
    case "$__e" in
    '(' | '{' | '@' | '('* | '$('* | '@('*) rdt_block "pipeline-target" "$__e" ;;
    *) ;;
    esac
    rdt_ps_operand "$__e"
  done
  return 0
}

RDT_PS_COMMON=(debug verbose erroraction warningaction informationaction progressaction
  errorvariable warningvariable informationvariable outvariable outbuffer pipelinevariable
  db vb ea wa infa proga ev wv iv ov ob pv)
rdt_ps_common_val() {
  case "$1" in
  erroraction | warningaction | informationaction | progressaction | errorvariable | \
    warningvariable | informationvariable | outvariable | outbuffer | pipelinevariable | \
    ea | wa | infa | proga | ev | wv | iv | ov | ob | pv) return 0 ;;
  *) return 1 ;;
  esac
}

rdt_ps_pick_to() {
  local __pk_dest="$1" __pk_t="${2#-}" __pk_hit="" __pk_hits=0 __pk_n
  __pk_t="${__pk_t%%:*}"
  __pk_t="${__pk_t,,}"
  shift 2
  for __pk_n in "$@"; do
    if [[ "$__pk_n" == "$__pk_t" ]]; then
      printf -v "$__pk_dest" '%s' "$__pk_n"
      return 0
    fi
    if [[ -n "$__pk_t" && "$__pk_n" == "$__pk_t"* ]]; then
      __pk_hit="$__pk_n"
      __pk_hits=$((__pk_hits + 1))
    fi
  done
  ((__pk_hits == 1)) || __pk_hit=""
  printf -v "$__pk_dest" '%s' "$__pk_hit"
}

rdt_ps_list_judge() {
  local __lin="$1"
  shift
  local -a __lw=("$@") __lp=()
  local __i=0 __c __v __e __n="" __pos=0 __gci=0 __join=0 __dest=0
  while ((__i < ${#__lw[@]})) && [[ "${__lw[__i]}" == "&" ]]; do
    __i=$((__i + 1))
  done
  ((__i < ${#__lw[@]})) || return 1
  __c="${__lw[__i],,}"
  __c="${__c##*[\\/]}"
  __c="${__c%.exe}"
  case "$__c" in
  get-childitem | gci | dir | ls) __gci=1 ;;
  get-item | gi) ;;
  *) return 1 ;;
  esac
  for ((__i = __i + 1; __i < ${#__lw[@]}; __i++)); do
    __v="${__lw[__i]}"
    if ((__join == 0)) && [[ "$__v" == -?* ]]; then
      rdt_ps_pick_to __n "$__v" path literalpath lp pspath filter include exclude depth \
        attributes stream credential recurse force name directory file hidden readonly system \
        followsymlink "${RDT_PS_COMMON[@]}"
      case "$__n" in
      path | literalpath | lp | pspath) __dest=1 ;;
      filter | include | exclude | depth | attributes | stream | credential) __dest=0 ;;
      *)
        rdt_ps_common_val "$__n" || continue
        __dest=0
        ;;
      esac
      if [[ "$__v" == *:?* ]]; then
        __v="${__v#*:}"
      elif ((__i + 1 < ${#__lw[@]})); then
        __i=$((__i + 1))
        __v="${__lw[__i]}"
      else
        continue
      fi
    elif ((__join == 0)); then
      __pos=$((__pos + 1))
      __dest=0
      ((__pos == 1 || __gci == 0)) && __dest=1
    fi
    __join=0
    [[ "$__v" == *, || "$__v" == @ || "${__lw[__i + 1]-}" == ,* ]] && __join=1
    ((__dest)) && __lp+=("$__v")
  done
  if ((${#__lp[@]} == 0)); then
    ((__lin)) && return 1
    __lp=(".")
  fi
  for __v in "${__lp[@]}"; do
    if [[ -z "$__v" ]]; then
      rdt_block "empty-operand"
      continue
    fi
    while [[ -n "$__v" ]]; do
      __e="${__v%%,*}"
      if [[ "$__v" == *,* ]]; then
        __v="${__v#*,}"
      else
        __v=""
      fi
      [[ -n "$__e" ]] || continue
      # shellcheck disable=SC2016  # a literal `$(` grouping
      case "$__e" in
      '(' | '{' | '@' | '('* | '$('* | '@('*) rdt_block "pipeline-target" "$__e" ;;
      *) rdt_ps_operand "$__e" ;;
      esac
    done
  done
  return 0
}

rdt_ps_wd() {
  ((RDT_ARM)) || return 0
  local __wd_u=$rdt_cd_unknown
  rdt_add_origin "$1" 0
  rdt_cd_unknown=$__wd_u
}

rdt_ps_select() {
  local __v __n="" __re='^[0-9,]+$'
  for __v in "$@"; do
    [[ "$__v" =~ $__re ]] && continue
    [[ "$__v" == -?* ]] || return 1
    rdt_ps_pick_to __n "$__v" first last skip skiplast unique index wait
    [[ -n "$__n" ]] || return 1
  done
  return 0
}

rdt_ps_call_arg() {
  local __ca="$1"
  # shellcheck disable=SC2016  # a literal `$(` grouping
  case "$__ca" in
  '(' | '{' | '@' | '('* | '$('* | '@('*)
    rdt_block "pipeline-target" "$__ca"
    return 0
    ;;
  *) ;;
  esac
  if [[ "$__ca" != *,* && "${2-}" == "(" ]]; then
    rdt_block "pipeline-target" "$__ca"
    return 0
  fi
  __ca="${__ca%%,*}"
  if [[ -z "$__ca" ]]; then
    rdt_block "empty-operand"
    return 0
  fi
  rdt_ps_operand "$__ca"
}

rdt_ps_nested() {
  local __t="$1" rdt_ps_lit_kept=0
  [[ -n "$RDT_PS_LIT" ]] && __t="${__t//"$RDT_PS_LIT"/\$}"
  local rdt_depth=$((rdt_depth + 1))
  ((rdt_depth > MAX_SEGMENT_DEPTH)) && rdt_block "nesting-too-deep-launcher"
  rdt_scanned=$((rdt_scanned + ${#__t}))
  ((rdt_scanned > MAX_COMMAND_LEN)) && rdt_block "eval-too-long"
  rdt_ps_walk "$__t"
}

rdt_ps_b64_utf16_to() {
  local __bd_dest="$1" __bd_in="${2//[[:space:]]/}" __bd_out="" __bd_c __bd_pre __bd_x
  local __bd_al='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  local __bd_re='^[A-Za-z0-9+/]+={0,2}$'
  local -i __bd_acc=0 __bd_bits=0 __bd_lo=-1 __bd_b=0 __bd_i
  [[ "$__bd_in" =~ $__bd_re ]] || return 1
  __bd_in="${__bd_in%%=*}"
  for ((__bd_i = 0; __bd_i < ${#__bd_in}; __bd_i++)); do
    __bd_c="${__bd_in:__bd_i:1}"
    __bd_pre="${__bd_al%%"$__bd_c"*}"
    ((${#__bd_pre} < 64)) || return 1
    __bd_acc=$(((__bd_acc << 6) | ${#__bd_pre}))
    __bd_bits=$((__bd_bits + 6))
    ((__bd_bits >= 8)) || continue
    __bd_bits=$((__bd_bits - 8))
    __bd_b=$(((__bd_acc >> __bd_bits) & 255))
    __bd_acc=$((__bd_acc & ((1 << __bd_bits) - 1)))
    if ((__bd_lo < 0)); then
      __bd_lo=$__bd_b
      continue
    fi
    ((__bd_b == 0 && ((__bd_lo >= 32 && __bd_lo < 127) || __bd_lo == 9 || __bd_lo == 10 || __bd_lo == 13))) || return 1
    printf -v __bd_x '%02x' "$__bd_lo"
    # shellcheck disable=SC2059  # the format is the one byte's \x escape
    printf -v __bd_c "\\x$__bd_x"
    __bd_out+="$__bd_c"
    __bd_lo=-1
  done
  ((__bd_lo < 0)) || return 1
  printf -v "$__bd_dest" '%s' "$__bd_out"
}

rdt_ps_shell_from() {
  local -a __sa=("$@")
  local __k=0 __v __n __t="" __full __pos=0
  while ((__k < ${#__sa[@]})); do
    __v="${__sa[__k]}"
    if [[ "$__v" != -* && "$__v" != /?* ]]; then
      if ((__pos == 0)); then
        __pos=1
        __t=""
        for __full in "${__sa[@]:__k}"; do
          __t+="${__t:+ }$__full"
        done
        rdt_ps_nested "$__t"
      fi
      __k=$((__k + 1))
      continue
    fi
    __n="${__v#/}"
    __n="${__n#-}"
    __n="${__n#-}"
    __n="${__n%%:*}"
    __n="${__n,,}"
    __k=$((__k + 1))
    [[ -z "$__n" || "$__n" == "%" ]] && continue
    if [[ "$__n" == cwa || ("$__n" == commandw* && "commandwithargs" == "$__n"*) ]]; then
      ((__k < ${#__sa[@]})) && rdt_ps_nested "${__sa[__k]}"
      return 0
    fi
    if [[ "command" == "$__n"* ]]; then
      __t=""
      for __full in ${__sa[@]+"${__sa[@]:__k}"}; do
        __t+="${__t:+ }$__full"
      done
      [[ -n "$__t" ]] && rdt_ps_nested "$__t"
      return 0
    fi
    if [[ "$__n" == ec || "encodedcommand" == "$__n"* ]]; then
      ((__k < ${#__sa[@]})) || return 0
      rdt_ps_b64_utf16_to __t "${__sa[__k]}" || rdt_block "encoded-unreadable"
      rdt_ps_nested "$__t"
      return 0
    fi
    [[ "file" == "$__n"* ]] && return 0
    if [[ "$__n" == wd || ("$__n" == wo* && "workingdirectory" == "$__n"*) ]]; then
      if ((__k < ${#__sa[@]})); then
        rdt_ps_wd "${__sa[__k]}"
        __k=$((__k + 1))
      fi
      continue
    fi
    case "$__n" in
    ex | ep | w | o | of | inp | if | config | settings | v) __k=$((__k + 1)) ;;
    *)
      for __full in executionpolicy windowstyle outputformat inputformat configurationname \
        configurationfile custompipename settingsfile psconsolefile version encodedarguments; do
        if ((${#__n} >= 3)) && [[ "$__full" == "$__n"* ]]; then
          __k=$((__k + 1))
          break
        fi
      done
      ;;
    esac
  done
  return 0
}

rdt_ps_iex_run() {
  if [[ "$1" != "(" ]]; then
    rdt_ps_nested "$1"
  elif ((${#rdt_ps_grp[@]} == 1)); then
    rdt_ps_nested "${rdt_ps_grp[0]}"
  fi
  return 0
}
rdt_ps_iex() {
  local -a __ia=("$@") __f=()
  local __k=0 __v __n=""
  while ((__k < ${#__ia[@]})); do
    __v="${__ia[__k]}"
    __k=$((__k + 1))
    if [[ "$__v" != -?* ]]; then
      rdt_ps_iex_run "$__v"
      return 0
    fi
    rdt_ps_pick_to __n "$__v" command "${RDT_PS_COMMON[@]}"
    if [[ "$__n" == command ]]; then
      if [[ "$__v" == *:?* ]]; then
        rdt_ps_iex_run "${__v#*:}"
      elif ((__k < ${#__ia[@]})); then
        rdt_ps_iex_run "${__ia[__k]}"
      fi
      return 0
    fi
    rdt_ps_common_val "$__n" && [[ "$__v" != *:* ]] && __k=$((__k + 1))
  done
  ((rdt_ps_piped)) || return 0
  __f=(${rdt_ps_feed[@]+"${rdt_ps_feed[@]}"})
  if ((${#__f[@]} == 1)); then
    rdt_ps_nested "${__f[0]}"
  elif ((${#__f[@]} == 2)); then
    case "${__f[0],,}" in
    write-output | echo | write) rdt_ps_nested "${__f[1]}" ;;
    *) ;;
    esac
  fi
  return 0
}

rdt_ps_start() {
  local rdt_depth=$((rdt_depth + 1))
  ((rdt_depth > MAX_SEGMENT_DEPTH)) && rdt_block "nesting-too-deep-launcher"
  local -a __pa=("$@") __pr=() __pp=()
  local __k=0 __v __n __fp=0 __al=0 __prog="" __line="" rdt_ps_piped=0 rdt_ps_item=0
  local __re='^-[A-Za-z][A-Za-z0-9]*(:|$)'
  while ((__k < ${#__pa[@]})); do
    __v="${__pa[__k]}"
    __k=$((__k + 1))
    __n=""
    if [[ "$__v" =~ $__re ]]; then
      rdt_ps_pick_to __n "$__v" filepath path pspath argumentlist args workingdirectory \
        credential redirectstandarderror redirectstandardinput redirectstandardoutput rse rsi rso \
        windowstyle verb environment wait nonewwindow nnw passthru loaduserprofile lup \
        usenewenvironment whatif wi confirm cf "${RDT_PS_COMMON[@]}"
      case "$__n" in
      filepath | path | pspath | argumentlist | args | workingdirectory) ;;
      credential | redirectstandard* | rse | rsi | rso | windowstyle | verb | environment)
        [[ "$__v" == *:* ]] || __k=$((__k + 1))
        continue
        ;;
      *)
        rdt_ps_common_val "$__n" && [[ "$__v" != *:* ]] && __k=$((__k + 1))
        continue
        ;;
      esac
      if [[ "$__v" == *:?* ]]; then
        __v="${__v#*:}"
      elif ((__k < ${#__pa[@]})); then
        __v="${__pa[__k]}"
        __k=$((__k + 1))
      else
        continue
      fi
    else
      if ((!__fp)); then
        __n=filepath
      elif ((!__al)); then
        __n=argumentlist
      fi
    fi
    case "$__n" in
    filepath | path | pspath)
      __prog="$__v"
      __fp=1
      ;;
    workingdirectory) rdt_ps_wd "$__v" ;;
    argumentlist | args)
      __al=1
      __pr+=("$__v")
      while ((__k < ${#__pa[@]})) && [[ "${__pr[${#__pr[@]} - 1]}" == *, || "${__pa[__k]}" == ,* ]]; do
        __pr+=("${__pa[__k]}")
        __k=$((__k + 1))
      done
      ;;
    *) ;;
    esac
  done
  [[ -n "$__prog" ]] || return 0
  for __v in ${__pr[@]+"${__pr[@]}"}; do
    __line+="${__line:+ }${__v//,/ }"
  done
  rdt_ps_cmd_split_to __pp "$__line"
  rdt_ps_statement "$__prog" ${__pp[@]+"${__pp[@]}"}
}

rdt_ps_statement() {
  local -a __w=("$@")
  ((${#__w[@]})) || return 0
  if ((rdt_ps_item && rdt_ps_piped)); then
    rdt_ps_list_judge "$rdt_ps_feed_in" ${rdt_ps_feed[@]+"${rdt_ps_feed[@]}"} || rdt_block "pipeline-target"
  fi
  local __i=0 __cmd
  while ((__i < ${#__w[@]})) && [[ "${__w[__i]}" == "&" ]]; do
    __i=$((__i + 1))
  done
  ((__i < ${#__w[@]})) || return 0
  __cmd="${__w[__i]}"
  __cmd="${__cmd##*\\}"
  __cmd="${__cmd##*/}"
  __cmd="${__cmd,,}"
  __cmd="${__cmd%.exe}"
  __i=$((__i + 1))
  case "$__cmd" in
  remove-item | ri | rm | del | erase) rdt_ps_ri_check "${__w[@]:__i}" ;;
  rd | rmdir)
    rdt_ps_ri_check "${__w[@]:__i}"
    rdt_ps_cmd_rd "$__cmd" "${__w[@]:__i}"
    ;;
  cmd) rdt_ps_cmd_from "${__w[@]:__i}" ;;
  robocopy)
    if ((__i < ${#__w[@]})); then
      rdt_ps_robocopy_check "${__w[@]:__i}"
    fi
    ;;
  move-item | mi | move | mv) rdt_ps_move_check move "${__w[@]:__i}" ;;
  clear-content | clc) rdt_ps_move_check clear "${__w[@]:__i}" ;;
  set-content) rdt_ps_move_check set "${__w[@]:__i}" ;;
  invoke-expression | iex) rdt_ps_iex "${__w[@]:__i}" ;;
  start-process | saps | start) rdt_ps_start "${__w[@]:__i}" ;;
  pwsh | powershell) rdt_ps_shell_from "${__w[@]:__i}" ;;
  bash | sh | zsh | dash | ksh | mksh | wsl) rdt_ps_bash_from "$__cmd" "${__w[@]:__i}" ;;
  where-object | where | '?' | sort-object | sort) ((rdt_ps_piped)) && rdt_ps_pass=1 ;;
  select-object | select) ((rdt_ps_piped)) && rdt_ps_select "${__w[@]:__i}" && rdt_ps_pass=1 ;;
  *) ;;
  esac
  return 0
}

rdt_ps_decoded() {
  local d=$rdt_ps_dec w c=""
  rdt_ps_dec=0
  ((rdt_ps_after_pipe && rdt_ps_pipe_dec)) && d=1
  rdt_ps_after_pipe=0
  for w in "$@"; do
    case "${w,,}" in
    '[convert]::frombase64string' | '[system.convert]::frombase64string') d=1 ;;
    *) ;;
    esac
    [[ -z "$c" && "$w" != "&" ]] && c="$w"
  done
  rdt_ps_pipe_dec=$d
  ((d)) || return 0
  rdt_ps_lvl_dec=1
  c="${c##*\\}"
  c="${c##*/}"
  c="${c,,}"
  c="${c%.exe}"
  [[ "$c" == iex || "$c" == invoke-expression ]] && rdt_block "decoder-sink"
  return 0
}

rdt_ps_walk() {
  local __s="$1" __n=${#1} __i=0
  local -a __words=() __sv=() __svn=() __svp=() __svk=() __svd=() __sf=() __sfn=()
  local __word="" __in=0 __q="" __c __nxt __cont=0
  local rdt_ps_piped=0 rdt_ps_dec=0 rdt_ps_lvl_dec=0 rdt_ps_pipe_dec=0 rdt_ps_after_pipe=0
  local rdt_ps_item=0 rdt_ps_lvl_item=0 rdt_ps_call=0 rdt_ps_nst=0 rdt_ps_pass=0 rdt_ps_feed_in=0
  local -a rdt_ps_feed=() rdt_ps_grp=()

  rdt_ps_flush_word() {
    if ((__in)); then
      __words+=("$__word")
    fi
    __word=""
    __in=0
  }
  rdt_ps_end_stmt() {
    rdt_ps_flush_word
    if ((${#__words[@]})); then
      if ((rdt_ps_call)); then
        rdt_ps_call=0
        rdt_ps_call_arg "${__words[0]}" "${__words[1]-}"
      fi
      rdt_ps_decoded "${__words[@]}"
      rdt_ps_statement "${__words[@]}"
      if ((!rdt_ps_pass)); then
        rdt_ps_feed=("${__words[@]}")
        rdt_ps_feed_in=$rdt_ps_piped
      fi
      ((rdt_ps_item && !rdt_ps_piped)) && rdt_ps_lvl_item=1
      ((rdt_ps_nst < 2)) && rdt_ps_nst=$((rdt_ps_nst + 1))
      __words=()
      rdt_ps_piped=0 rdt_ps_item=0 rdt_ps_pass=0
    fi
  }
  rdt_ps_open() {
    rdt_ps_flush_word
    ((${#__svn[@]} < MAX_SUBST_DEPTH)) || rdt_block "nesting-too-deep"
    local __call=0 __nw=${#__words[@]}
    if [[ "$1" == "(" ]] && ((__nw)); then
      # shellcheck disable=SC2016  # literal `$_` and `$PSItem` member calls
      case "${__words[__nw - 1],,}" in
      *']::delete') __call=1 ;;
      '$_.delete' | '$psitem.delete') rdt_ps_lvl_item=1 ;;
      .delete)
        if ((__nw > 1)) && [[ "${__words[__nw - 2]}" == "(" ]]; then
          rdt_ps_list_judge 0 ${rdt_ps_grp[@]+"${rdt_ps_grp[@]}"} || rdt_block "pipeline-target"
        fi
        ;;
      *) ;;
      esac
    fi
    if ((__nw)); then
      __sv+=("${__words[@]}")
    fi
    __svn+=("$__nw")
    __svp+=("$rdt_ps_piped")
    __svk+=("$1")
    __svd+=("$rdt_ps_dec$rdt_ps_lvl_dec$rdt_ps_pipe_dec$rdt_ps_after_pipe$rdt_ps_item$rdt_ps_lvl_item$rdt_ps_call$rdt_ps_nst$rdt_ps_feed_in")
    __sfn+=("${#rdt_ps_feed[@]}")
    if ((${#rdt_ps_feed[@]})); then
      __sf+=("${rdt_ps_feed[@]}")
    fi
    __words=()
    rdt_ps_feed=()
    rdt_ps_piped=0
    rdt_ps_dec=0 rdt_ps_lvl_dec=0 rdt_ps_pipe_dec=0 rdt_ps_after_pipe=0
    rdt_ps_item=0 rdt_ps_lvl_item=0 rdt_ps_call=$__call rdt_ps_nst=0 rdt_ps_feed_in=0
  }
  rdt_ps_close() {
    rdt_ps_end_stmt
    local __k=${#__svn[@]} __cnt __tot __kind __d
    ((__k)) || return 0
    rdt_ps_grp=()
    ((rdt_ps_nst == 1)) && rdt_ps_grp=(${rdt_ps_feed[@]+"${rdt_ps_feed[@]}"})
    __cnt=${__svn[__k - 1]}
    __kind=${__svk[__k - 1]}
    __tot=${#__sv[@]}
    if ((__cnt)); then
      __words=("${__sv[@]:__tot-__cnt:__cnt}")
      __sv=("${__sv[@]:0:__tot-__cnt}")
    else
      __words=()
    fi
    __cnt=${__sfn[__k - 1]}
    __tot=${#__sf[@]}
    if ((__cnt)); then
      rdt_ps_feed=("${__sf[@]:__tot-__cnt:__cnt}")
      __sf=("${__sf[@]:0:__tot-__cnt}")
    else
      rdt_ps_feed=()
    fi
    rdt_ps_piped=${__svp[__k - 1]}
    __d=${__svd[__k - 1]}
    rdt_ps_dec=$((${__d:0:1} | rdt_ps_lvl_dec))
    rdt_ps_item=$((${__d:4:1} | rdt_ps_lvl_item))
    rdt_ps_lvl_dec=${__d:1:1}
    rdt_ps_pipe_dec=${__d:2:1}
    rdt_ps_after_pipe=${__d:3:1}
    rdt_ps_lvl_item=${__d:5:1}
    rdt_ps_call=${__d:6:1}
    rdt_ps_nst=${__d:7:1}
    rdt_ps_feed_in=${__d:8:1}
    unset "__svn[__k - 1]" "__svp[__k - 1]" "__svk[__k - 1]" "__svd[__k - 1]" "__sfn[__k - 1]"
    __words+=("$__kind")
    if [[ "$__kind" == "{" ]]; then
      case "${__words[0],,}" in
      if | elseif | else | foreach | for | while | do | until | switch | try | catch | finally | \
        trap | function | filter | workflow | param | begin | process | end | dynamicparam)
        rdt_ps_end_stmt
        ;;
      *) ;;
      esac
    fi
  }

  while ((__i < __n)); do
    __c="${__s:__i:1}"
    if ((__i + 1 < __n)); then
      __nxt="${__s:__i+1:1}"
    else
      __nxt=""
    fi
    if [[ -n "$__q" ]]; then
      if [[ "$__q" == "'" ]]; then
        if [[ "$__c" == "'" ]]; then
          if [[ "$__nxt" == "'" ]]; then
            __word+="'"
            __i=$((__i + 1))
          else
            __q=""
          fi
        elif [[ "$__c" == '$' && -n "$RDT_PS_LIT" ]]; then
          __word+="$RDT_PS_LIT"
        else
          __word+="$__c"
        fi
      elif [[ "$__q" == '}' ]]; then
        if [[ "$__c" == '`' ]] && ((__i + 1 < __n)); then
          __word+="$__nxt"
          __i=$((__i + 1))
        else
          __word+="$__c"
          [[ "$__c" == '}' ]] && __q=""
        fi
      else
        if [[ "$__c" == '`' ]] && ((__i + 1 < __n)); then
          if [[ "$__nxt" == '$' && -n "$RDT_PS_LIT" ]]; then
            __word+="$RDT_PS_LIT"
          else
            __word+="$__nxt"
          fi
          __i=$((__i + 1))
        elif [[ "$__c" == '"' ]]; then
          __q=""
        else
          __word+="$__c"
        fi
      fi
      __in=1
      __i=$((__i + 1))
      continue
    fi
    if [[ "$__c" == '`' ]] && ((__i + 1 < __n)); then
      if [[ "$__nxt" == $'\n' || "$__nxt" == $'\r' ]]; then
        __i=$((__i + 2))
        [[ "$__nxt" == $'\r' && "${__s:__i:1}" == $'\n' ]] && __i=$((__i + 1))
        continue
      fi
      if [[ "$__nxt" == '$' && -n "$RDT_PS_LIT" ]]; then
        __word+="$RDT_PS_LIT"
      else
        __word+="$__nxt"
      fi
      __in=1
      __cont=0
      __i=$((__i + 2))
      continue
    fi
    [[ "$__c" == [[:space:]] ]] || __cont=0
    case "$__c" in
    "'")
      __q="'"
      __in=1
      ;;
    '"')
      __q='"'
      __in=1
      ;;
    '#')
      if ((__in == 0)); then
        while ((__i < __n)) && [[ "${__s:__i:1}" != $'\n' && "${__s:__i:1}" != $'\r' ]]; do
          __i=$((__i + 1))
        done
        continue
      else
        __word+="#"
      fi
      ;;
    '$')
      if [[ "$__nxt" != '(' ]]; then
        __in=1
        if [[ "$__nxt" == '{' ]]; then
          __word+="\${"
          __q='}'
          __i=$((__i + 1))
        else
          __word+='$'
        fi
      fi
      ;;
    ',')
      __word+=","
      __in=1
      __cont=1
      ;;
    '(' | '{')
      rdt_ps_open "$__c"
      ;;
    ')' | '}')
      rdt_ps_close
      ;;
    $'\n' | $'\r')
      if ((__cont)); then
        rdt_ps_flush_word
      else
        rdt_ps_end_stmt
      fi
      ;;
    '|')
      if [[ "$__nxt" == '|' ]]; then
        rdt_ps_end_stmt
        rdt_ps_piped=0
        __i=$((__i + 1))
      else
        rdt_ps_end_stmt
        rdt_ps_piped=1
        rdt_ps_after_pipe=1
      fi
      ;;
    '&')
      if ((__in == 0)) && { [[ -z "$__nxt" ]] || [[ "$__nxt" == [[:space:]] ]] || [[ "$__nxt" == "'" ]] || [[ "$__nxt" == '"' ]]; }; then
        rdt_ps_flush_word
        __words+=("&")
      elif [[ "$__nxt" == '&' ]]; then
        rdt_ps_end_stmt
        rdt_ps_piped=0
        __i=$((__i + 1))
      else
        rdt_ps_end_stmt
        rdt_ps_piped=0
      fi
      ;;
    ';')
      rdt_ps_end_stmt
      rdt_ps_piped=0
      ;;
    [[:space:]])
      rdt_ps_flush_word
      ;;
    *)
      __word+="$__c"
      __in=1
      ;;
    esac
    __i=$((__i + 1))
  done
  rdt_ps_end_stmt
  while ((${#__svn[@]})); do
    rdt_ps_close
    rdt_ps_end_stmt
  done
}

rdt_ps_run() {
  rdt_ps_walk "$COMMAND"
}

PAYLOAD_CWD="${PAYLOAD_CWD//\\//}"
if ((RDT_CWD_NUL)); then
  RDT_ARM=1
  RDT_ORIGINS=("/")
elif rdt_is_abs "$PAYLOAD_CWD"; then
  RDT_ARM=1
  _rdt_origin=""
  rdt_lex_to _rdt_origin "$PAYLOAD_CWD"
  RDT_ORIGINS=("$_rdt_origin")
fi
if [[ "$TOOL_NAME" == "PowerShell" ]]; then
  rdt_ps_run
else
  rdt_in_subst=1
  rdt_scan_substitutions "$COMMAND"
  rdt_in_subst=0
  rdt_parse "$COMMAND"
fi
if ((${#RDT_P_TEXT[@]})); then
  rdt_judge_rc=0
  rdt_judge_ask=$(
    HOOK_REFUSE_PENDING=()
    rdt_judge_pending || exit
    ((${#HOOK_REFUSE_PENDING[@]})) || exit 0
    printf '%s\x1e' "${HOOK_REFUSE_PENDING[@]}"
    exit 3
  ) || rdt_judge_rc=$?
  ((rdt_judge_rc == 2)) && exit 2
  if ((rdt_judge_rc == 3)) && [[ -n "$rdt_judge_ask" ]]; then
    while [[ "$rdt_judge_ask" == *$'\x1e'* ]]; do
      hook::refuse "${rdt_judge_ask%%$'\x1e'*}"
      rdt_judge_ask="${rdt_judge_ask#*$'\x1e'}"
    done
    rdt_judge_rc=0
  fi
  ((rdt_judge_rc == 0)) || rdt_block "judge-error"
fi

hook::refuse_flush
rdt_emit_tel "ok" ""
exit 0
