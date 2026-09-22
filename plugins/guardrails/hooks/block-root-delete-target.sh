#!/usr/bin/env bash
# PreToolUse hook: block a recursive delete whose TARGET is a filesystem root.
# Triggered on Bash tool calls (a command string).
#
# THE GAP THIS CLOSES. Until now no guard in this plugin inspected the target of
# a delete at all: `rm -rf` appeared only in the suites, as fixture cleanup, and
# `rm -rf "\\"` passed all eight guards of the Bash dispatcher at rc 0. The
# motivating incident is anthropics/claude-code #92593, where a subagent ran
# `rm -rf "\\"` in Git Bash meaning to remove a stray directory named `\`. MSYS
# path translation resolved the bare backslash to the ROOT OF THE CURRENT DRIVE
# and the delete ran for about seven minutes before it was killed by PID.
#
# WHY A HOOK AND NOT A DENY RULE. The quoted-backslash form does not look like
# `rm -rf /*`, so a permission pattern keyed on the obvious spelling never
# matches it. Two harness behaviors the same issue reports make a PRE-execution
# control the only dependable one: a command past the Bash timeout is
# auto-backgrounded and keeps running unsupervised, and stopping the task ends
# the shell without the process tree. Once a runaway recursive delete starts,
# stopping it is not reliable, so the control point is before it runs.
#
# HOW IT DECIDES. Not on the shape of the command text. The command is parsed
# the way the shell builds argv (hook::bash_parse_segments, the same tokenizer
# block-no-verify and block-dangerous-git use), and each simple command is
# judged on three questions: is its COMMAND WORD `rm`, does it carry a
# RECURSIVE flag, and does any OPERAND normalize to a root. Quoting is already
# resolved by the time the matcher sees a word, which is what keeps
# `git commit -m "rm -rf /"` and `echo "rm -rf /"` allowed: there the whole text
# is one argv word of a `git` or `echo` command, and the command word is never
# `rm`. That is a consequence of parsing argv, not a special case for prose.
#
# NOT HOST GATED, deliberately, and this differs from block-windows-drive-tmp.sh
# next to it. That guard exits at once on a non-Windows host because a POSIX
# /tmp is the real temp directory there and it can have no opinion. Here `/`,
# `/*`, `~`, `$HOME` and `--no-preserve-root` are unrecoverable on every host
# this plugin runs on, and CI is Linux, so every arm is active everywhere. The
# drive-root arms simply never match on a host that has no drive letters. Do not
# "fix the inconsistency" by adding an OSTYPE gate.
#
# NARROW TRIGGER, ON PURPOSE. block-exported-msys-pathconv.sh records that a
# guard keyed on PATH SHAPE across every Bash command fired on 45.7% of 14,234
# real commands and was rejected on that measurement. This guard does not
# inherit that objection: it reads a cheap substring first, and a command with
# no `rm` token never reaches the parse at all. The path question is asked only
# once a recursive `rm` is already established.
#
# DECLARED GAPS, stated rather than hidden, matching this family's convention:
#   * PowerShell. `Remove-Item -Recurse -Force C:\` and `rd /s` are the same
#     hazard through the other shell and are NOT covered. The guard exits on any
#     tool_name other than Bash, which also keeps it out of the shared
#     PowerShell classifier and its sink attempt budget. Tracked separately.
#   * Other delete verbs: `find -delete`, `rsync --delete`, `xargs rm`,
#     `shred`, and a delete performed from inside an interpreter.
#   * Expansion-built targets. Detection never evaluates a shell expansion, so
#     `rm -rf "$UNSET/"` is invisible here. `$HOME` and `${HOME}` are matched as
#     the literal text they are written as, not as what they expand to.
#   * A target resolving ABOVE the session working directory. Out of scope: it
#     needs cwd resolution, and refusing `rm -rf ../build` is exactly the
#     breadth this guard's narrow trigger exists to avoid.
#   * A home directory named for another user (`rm -rf ~bob`). Only bare `~` is
#     matched.
#   * Nesting inside a child shell beyond what the shared tokenizer unwraps.
#
# BLOCKING: exits 2 on a recursive delete of a root.

set -uo pipefail

# Kill switch FIRST, above every source: a disabled guard must not pay to parse
# hook-utils.sh before finding out it is off. Inlined rather than read through
# hook::is_enabled because the library IS the cost the hoist avoids;
# scripts/check-killswitch-hoist.sh pins this line to that helper's semantics.
[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_ROOT_DELETE_TARGET_ENABLED:-true}" == "true" ]] || exit 0

# The hook's own directory, by parameter expansion rather than `dirname`: GNU
# Bash forks a subshell for every command substitution even when the body is a
# builtin (Command Substitution, Bash Reference Manual;
# https://mywiki.wooledge.org/CommandSubstitution), and on Windows Git Bash that
# fork is a process. The fallback covers a bare filename.
_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
# Could-not-run posture: fail-open with a dual-channel "guard did not run"
# notice; 0 (allow) and 2 (block) pass through unchanged.
guard::abort_boundary block-root-delete-target PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

# High-res start stamp for the telemetry envelope. EPOCHREALTIME is Bash 5.0+;
# on older bash it is unset, so default to empty and skip telemetry. Referencing
# it bare under `set -u` would abort before exit.
start=${EPOCHREALTIME:-}

# hook::buffer_stdin encapsulates the Win32-pipe-safe bounded fd0 read. rc 1
# (empty stdin) is a skip; rc 2 (text that is not JSON) FAILS CLOSED, because a
# guard that cannot evaluate the tool call must not pass exactly the traffic it
# exists to stop; rc 3 (a payload the pipe cut short) is a loud skip the
# dispatcher takes once and has already reported.
hook::buffer_stdin_to INPUT || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}

# jq parses the tool payload, and this guard FAILS CLOSED on its absence, the
# same posture as the other blocking Bash guards.
hook::require_jq_blocking "guardrails-block-root-delete-target" "block_root_delete_target_enabled"

# Two fields, one extraction. Never `.tool_input.content` or any write payload:
# this guard reads a command and nothing else.
jq_rc=0
hook::jq_fields "$INPUT" '.tool_input.command' '.tool_name' || jq_rc=$?
if ((jq_rc == 2)); then
  echo "BLOCKED: the hook payload could not be parsed." >&2
  exit 2
fi
((jq_rc != 0)) && exit 0

# A NUL byte in either field is fail-CLOSED: what a guard can read is then not
# dependably what would run.
if ((HOOK_JQ_FIELDS_NUL)); then
  echo "BLOCKED: the payload carries a NUL byte, which a command cannot reliably carry." >&2
  echo "What a guard can read is not dependably what would run, so this is refused rather than matched." >&2
  echo "Fix: reissue the tool call without the embedded NUL." >&2
  exit 2
fi

COMMAND="${HOOK_JQ_FIELDS[0]}"
TOOL_NAME="${HOOK_JQ_FIELDS[1]:-Bash}"

# The PowerShell lane is a declared gap, and exiting here is what keeps this
# guard off the classifier's load path entirely.
[[ "$TOOL_NAME" == "Bash" ]] || exit 0

# Nothing to inspect.
[[ -n "$COMMAND" ]] || exit 0

# Above this length the command is not parsed, and the guard fails closed: the
# same ceiling the other argv-faithful Bash guards carry, and the reason
# require-jq-posture.test.sh classes this guard with them.
MAX_COMMAND_LEN=16384

rdt_emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  # Resolved here, not at top level: the subject is a telemetry field, so it is
  # computed only when a sink is wired.
  local SUBJECT data
  hook::extract_bash_subject_to SUBJECT "$TOOL_NAME" "$COMMAND"
  hook::json_str_object_to data tool "$TOOL_NAME" subject "$SUBJECT" form "$2"
  hook::emit_telemetry "block-root-delete-target" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# rdt_block <form> [target]: refuse, say why, and exit 2. The target is echoed
# back as the guard NORMALIZED it, so the operator can see which word was read
# as a root rather than guessing.
rdt_block() {
  local form="$1" target="${2:-}"
  case "$form" in
  no-preserve-root)
    printf '%s\n' \
      'BLOCKED: this is a recursive delete carrying --no-preserve-root.' \
      'That flag exists only to switch off the one protection coreutils ships against deleting the filesystem root, so a command that sets it is refused whatever target it names.' \
      'Fix: drop --no-preserve-root and name the directory to remove explicitly, under the working tree.' >&2
    ;;
  too-long)
    printf '%s\n' \
      'BLOCKED: the command is too long to parse, so a recursive delete inside it cannot be ruled out.' \
      'Fix: split it into shorter commands, or write it to a script and run that.' >&2
    ;;
  *)
    # Single-quoted on purpose: the Fix line must show a literal $HOME to the
    # agent rather than expanding it in the hook process.
    # shellcheck disable=SC2016
    printf '%s\n' \
      "BLOCKED: this is a recursive delete whose target is a filesystem root (it normalizes to '$target')." \
      'A recursive delete of a root is not recoverable and, past the Bash timeout, not reliably stoppable either. On Windows a bare backslash reaches the delete as the root of the current drive, which is how a whole volume is lost to a command that looks like it names one directory.' \
      'Fix: name the directory to remove explicitly and relative to the working tree. If the target really is meant to be a root, do it outside the agent session. Note that $HOME and ~ are matched as written, not expanded.' >&2
    ;;
  esac
  rdt_emit_tel "blocked" "$form"
  exit 2
}

if ((${#COMMAND} > MAX_COMMAND_LEN)); then
  rdt_block "too-long"
fi

# Cheap prefilter ahead of the character walk. This guard is on the per-Bash-call
# path, and a command with no `rm` token anywhere cannot carry the one verb the
# matcher recognizes, so it must not pay for the parse.
case "$COMMAND" in
*rm*) ;;
*) exit 0 ;;
esac

# rdt_normalize_to <var> <operand>: the operand as this guard compares it.
# Backslashes become slashes so the Windows and MSYS spellings of one path share
# a matcher, the result is lowercased for a case-insensitive drive compare,
# runs of slashes collapse, ONE trailing glob suffix is dropped, and trailing
# slashes are trimmed unless the whole operand is slashes. Pure shell: a
# `printf | tr` pipeline would be a fork and an exec per operand.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_normalize_to() {
  local __rdt_dest="$1" __rdt_s="$2"
  __rdt_s="${__rdt_s//\\//}"
  __rdt_s="${__rdt_s,,}"
  while [[ "$__rdt_s" == *//* ]]; do
    __rdt_s="${__rdt_s//\/\//\/}"
  done
  if [[ "$__rdt_s" == *'/.*' ]]; then
    __rdt_s="${__rdt_s%'.*'}"
  elif [[ "$__rdt_s" == *'*' ]]; then
    __rdt_s="${__rdt_s%'*'}"
  fi
  if [[ "$__rdt_s" == "/" ]]; then
    :
  else
    while [[ "$__rdt_s" == */ ]]; do
      __rdt_s="${__rdt_s%/}"
    done
  fi
  printf -v "$__rdt_dest" '%s' "$__rdt_s"
}

# rdt_is_root <normalized>: true when the operand names a filesystem root.
# An operand that normalized to the EMPTY string is NOT a root, which is what
# keeps `rm -rf ""` allowed while `rm -rf "\\"`, whose single backslash
# normalizes to `/`, is refused.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_is_root() {
  local s="$1"
  [[ -n "$s" ]] || return 1
  # The two HOME spellings are single-quoted because they are LITERAL TEXT here:
  # the tokenizer hands over the characters the operator wrote, and this guard
  # never evaluates an expansion.
  # shellcheck disable=SC2016  # matching the literal text, not expanding it
  case "$s" in
  '/' | '~' | '$home' | '${home}') return 0 ;;
  *) ;;
  esac
  [[ "$s" =~ ^[a-z]:$ ]] && return 0
  [[ "$s" =~ ^/[a-z]$ ]] && return 0
  [[ "$s" =~ ^/cygdrive/[a-z]$ ]] && return 0
  [[ "$s" =~ ^/mnt/[a-z]$ ]] && return 0
  return 1
}

# rdt_check_segment <argv word>...: one simple command, as the shell would build
# it. Prefixed because guards share one process under run-guards.sh and two
# siblings already define a function named check_segment.
# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
rdt_check_segment() {
  local -a words=("$@")
  local n=$# i=0 w base

  # Command word: step over leading NAME=value assignments and over a launcher
  # that takes the real command as its argument, together with that launcher's
  # own option words.
  while ((i < n)); do
    w="${words[i]}"
    if [[ "$w" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      i=$((i + 1))
      continue
    fi
    base="${w##*/}"
    base="${base%.exe}"
    base="${base,,}"
    case "$base" in
    sudo | env | command | exec | time | nohup)
      i=$((i + 1))
      while ((i < n)) && [[ "${words[i]}" == -* ]]; do
        i=$((i + 1))
      done
      continue
      ;;
    *) ;;
    esac
    break
  done
  ((i < n)) || return 0

  base="${words[i]##*/}"
  base="${base%.exe}"
  base="${base,,}"
  [[ "$base" == "rm" ]] || return 0

  # Flags and operands. `--` ends option parsing, exactly as rm reads it.
  local recursive=0 no_preserve=0 end_of_opts=0 j
  local -a operands=()
  for ((j = i + 1; j < n; j++)); do
    w="${words[j]}"
    if ((end_of_opts == 0)); then
      case "$w" in
      --)
        end_of_opts=1
        continue
        ;;
      --no-preserve-root)
        no_preserve=1
        continue
        ;;
      --recursive)
        recursive=1
        continue
        ;;
      --*)
        continue
        ;;
      -?*)
        # A short cluster is letters only; anything else is not a flag rm reads.
        if [[ "$w" =~ ^-[A-Za-z]+$ && "$w" == *[rR]* ]]; then
          recursive=1
        fi
        continue
        ;;
      *) ;;
      esac
    fi
    operands+=("$w")
  done

  # Every arm below needs recursion. A non-recursive `rm /` is refused by rm
  # itself and is not this guard's business.
  ((recursive)) || return 0
  ((no_preserve)) && rdt_block "no-preserve-root"

  local op norm
  for op in ${operands[@]+"${operands[@]}"}; do
    rdt_normalize_to norm "$op"
    if rdt_is_root "$norm"; then
      rdt_block "root-operand" "$norm"
    fi
  done
  return 0
}

hook::bash_parse_segments "$COMMAND" rdt_check_segment

rdt_emit_tel "ok" ""
exit 0
