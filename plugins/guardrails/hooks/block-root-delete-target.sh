#!/usr/bin/env bash
# PreToolUse hook: block a recursive delete whose TARGET is a filesystem root.
# Triggered on Bash tool calls (a command string).
#
# THE GAP THIS CLOSES. Before 0.36.0 no guard in this plugin inspected the target of
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
# A COMMAND SUBSTITUTION is the one place that reasoning does not reach, and it
# is handled separately. `echo "$(rm -rf /)"` runs the delete before `echo` is
# ever invoked, while the tokenizer correctly keeps the substitution inside the
# enclosing word, so the segment callback only sees `echo`. Every `$( … )` and
# backtick body is therefore lifted out and parsed on its own. That scan HONORS
# QUOTING, both to find a substitution and to find where it ends: `'$(rm -rf /)'`
# is inert text, `"\$(…)"` is escaped, and a `)` inside a quoted span is not the
# terminator. Nesting is capped at MAX_SUBST_DEPTH and the cap REFUSES.
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
# inherit that objection: it reads a cheap substring first, so a command whose
# text does not contain `rm` never reaches the parse at all. The prefilter is a
# SUBSTRING match, not a token one, so `npm run format` does reach the
# tokenizer and is allowed there on its command word. The path question is
# asked only once a recursive `rm` is already established.
#
# DECLARED GAPS, stated rather than hidden, matching this family's convention:
#   * PowerShell. `Remove-Item -Recurse -Force C:\` and `rd /s` are the same
#     hazard through the other shell and are NOT covered. The guard exits on any
#     tool_name other than Bash, which also keeps it out of the shared
#     PowerShell classifier and its sink attempt budget. Tracked separately.
#   * Other delete verbs: `find -delete`, `rsync --delete`, `xargs rm`,
#     `shred`, and a delete performed from inside an interpreter.
#   * Expansion-built targets AND an expansion-built command word. Detection
#     never evaluates a shell expansion, so `rm -rf "$UNSET/"` is invisible
#     here, and so is `$(printf 'r%s' 'm') -rf /`, whose substitution body is
#     parsed (its command word is `printf`) but whose RESULT is not. `$HOME`
#     and `${HOME}` are matched as the literal text they are written as, not as
#     what they expand to.
#   * A target resolving ABOVE the session working directory. Out of scope: it
#     needs cwd resolution, and refusing `rm -rf ../build` is exactly the
#     breadth this guard's narrow trigger exists to avoid.
#   * A home directory named for another user (`rm -rf ~bob`). Only bare `~` is
#     matched.
#   * A root reached by MOVING the working directory rather than by naming it:
#     `cd / && rm -rf *` is allowed, because `*` names nothing on its own and
#     the guard deliberately does not track cwd.
#   * A child shell this guard does not recognize as one. `bash -c`, `sh -c`,
#     their siblings, `su`'s `-c` / `--command` / `--session-command` operand,
#     and GNU `env`'s `-S` / `--split-string` operand ARE unwrapped and
#     re-parsed; an interpreter that is not a shell (`python -c`, `perl -e`)
#     is not.
#   * A LAUNCHER that is not in the launcher table in rdt_check_segment. The
#     table is an allow-list of names, so an unlisted launcher ends the walk
#     and its own name is read as the command word. runuser is read by its own
#     helper, because its getopt permutes: its -c operands are commands (su's
#     grammar) and, with -u, its non-option words are the command.
#   * Three sudo spellings: `-R` / `--chroot`, a short cluster ending in an
#     operand-taking letter (`sudo -Eu bob …`), and an abbreviated long option
#     (`sudo --us bob …`). Each is read as a flag that takes no operand, so the
#     word after it becomes the command word. Reading them correctly changes
#     how sudo lines the guard refuses today are read (`sudo -R rm -rf /` would
#     take `rm` as the chroot directory), and this guard only ever adds
#     refusals, so they stay gaps.
#   * `chroot /mnt rm -rf /` is refused although it deletes `/mnt` on the host
#     rather than the host root: a known overblock, kept on the refusal side.
#   * A command word split across quoting so the RAW text never spells it.
#     `\rm` and `RM` are caught, because the cheap substring prefilter below
#     folds case and the raw text still reads `rm`; `r\m`, `r''m` and `"r"m`
#     are not, because the prefilter exits allow before the tokenizer rejoins
#     them. That is the price of not tokenizing every Bash call, and it is the
#     right trade here: this guard's threat model is an agent making the
#     mistake #92593 records, not one deliberately obfuscating a command word.
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

# Command substitutions may nest, and the scanner descends one level per `$(`.
# A payload well under MAX_COMMAND_LEN can spell thousands of levels, so the
# descent is capped and the cap REFUSES rather than allows: the guard's abort
# boundary is fail-OPEN, so a scanner that ran out of room would hand back an
# allow on exactly the input built to exhaust it.
MAX_SUBST_DEPTH=32

# Launcher, child-shell and eval nesting is recursion in rdt_check_segment,
# capped the same way and for the same reason: past the cap the guard REFUSES.
# 24 is far above any command a person writes and far below the depth where
# bash exhausts its stack (about 100 levels of runuser on Git Bash).
MAX_SEGMENT_DEPTH=24
rdt_depth=0

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
  nesting-too-deep)
    printf '%s\n' \
      "BLOCKED: substitution nesting deeper than $MAX_SUBST_DEPTH." \
      'Past that depth the scanner stops descending, so a recursive delete inside it cannot be ruled out, and an allow here would be an allow on exactly the input built to exhaust it.' \
      'Fix: flatten the command substitutions, or assign the inner results to variables in separate commands.' >&2
    ;;
  eval-too-long)
    printf '%s\n' \
      'BLOCKED: eval and substitution text exceeds MAX_COMMAND_LEN in total.' \
      'Each eval re-tokenizes the text it runs, so nested evals multiply the work, and a hook the harness cancels on its timeout is cancelled WITHOUT a block.' \
      'Fix: drop the nested evals, or run the inner command on its own.' >&2
    ;;
  nesting-too-deep-launcher)
    printf '%s\n' \
      "BLOCKED: launcher or eval nesting deeper than $MAX_SEGMENT_DEPTH; flatten the command." \
      'Each launcher, child shell and eval is judged by re-entering the parser, and past the limit a recursive delete inside it cannot be ruled out.' \
      'Fix: drop the repeated launchers, or run the inner command on its own.' >&2
    ;;
  too-many-abbreviations)
    printf '%s\n' \
      'BLOCKED: too many command segments with abbreviated launcher options to judge every reading; spell the options in full.' \
      'Each abbreviated long option (such as flock --wa) is judged both with and without taking the next word, and past the limit a recursive delete behind them cannot be ruled out.' \
      'Fix: spell the launcher options in full (flock --wait 5), or split the command into shorter ones.' >&2
    ;;
  bodies-too-long)
    printf '%s\n' \
      'BLOCKED: substitution bodies exceed MAX_COMMAND_LEN in total.' \
      'Nesting multiplies the text to tokenize, and a hook the harness cancels on its timeout is cancelled WITHOUT a block, so running past the budget would fail open on exactly the input built to reach it.' \
      'Fix: flatten the command substitutions, or assign the inner results to variables in separate commands.' >&2
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
# path, and a command whose TEXT does not contain `rm` cannot carry the one verb
# the matcher recognizes, so it must not pay for the parse. A substring is all
# this can be: `npm run format` contains `rm` and goes on to the tokenizer,
# which allows it on its command word.
#
# Folded to lower case, and that is load-bearing rather than tidy. The command
# word is compared case-insensitively below, and on the Windows host this guard
# was written for both the filesystem and the PATH lookup are case-insensitive,
# so `RM -rf /` runs rm. A case-SENSITIVE prefilter here would have exited
# allow before the matcher ever saw it, which is a bypass of the whole guard
# rather than a missed spelling.
case "${COMMAND,,}" in
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
  # A leading EXACTLY-two-slash prefix is preserved through the collapse,
  # because on Windows it introduces a UNC path and `//server/share` is a share
  # root, the same class of unrecoverable loss as a drive root. Every other run
  # of slashes collapses, so `\\` still reduces to `/` and is still refused.
  local __rdt_lead=""
  if [[ "$__rdt_s" == //* && "$__rdt_s" != ///* ]]; then
    __rdt_lead="/"
    __rdt_s="${__rdt_s#/}"
  fi
  while [[ "$__rdt_s" == *//* ]]; do
    __rdt_s="${__rdt_s//\/\//\/}"
  done
  __rdt_s="$__rdt_lead$__rdt_s"
  # Drop trailing path segments that carry no NAME. A segment holding no
  # alphanumeric and no underscore names nothing on its own: it is a glob, a
  # `.`, a `..`, or the empty segment a trailing slash leaves behind, so the
  # operand is still rooted where it started. Stripping ONE glob suffix was not
  # enough, because the residue can be another nameless segment: `/*/` keeps a
  # trailing slash, `/./*` keeps a dot, and `/.[!.]*`, the ordinary dotfile
  # idiom, keeps both. The loop reduces each of those to `/`.
  #
  # The name test is what bounds it. `/tmp*`, `~/proj*` and `/c/dev/*` stop at
  # their first named segment and stay ordinary deletes, and a directory
  # literally named `_` (`/_`) is named, so it is not a root.
  local __rdt_last
  while [[ "$__rdt_s" == */* ]]; do
    __rdt_last="${__rdt_s##*/}"
    [[ "$__rdt_last" == *[[:alnum:]_]* ]] && break
    __rdt_s="${__rdt_s%/*}"
    if [[ -z "$__rdt_s" ]]; then
      __rdt_s="/"
      break
    fi
  done
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
  # Every remaining slash run reduced to one, so a string of slashes alone is
  # the POSIX root however it was spelled (`/`, `\`, `\\`, `///`).
  [[ "$s" =~ ^/+$ ]] && return 0
  # A UNC share root: exactly two leading slashes, a host, a share, nothing more.
  [[ "$s" =~ ^//[^/]+/[^/]+$ ]] && return 0
  [[ "$s" =~ ^[a-z]:$ ]] && return 0
  [[ "$s" =~ ^/[a-z]$ ]] && return 0
  [[ "$s" =~ ^/cygdrive/[a-z]$ ]] && return 0
  [[ "$s" =~ ^/mnt/[a-z]$ ]] && return 0
  return 1
}

# rdt_runuser_argv <offset> <words after runuser>: read runuser's argv the way
# its getopt does. The optstring has no leading `+`, so getopt PERMUTES:
# options are recognized anywhere before the first `--`, and every non-option
# word, wherever it sits, is collected in order. Results, in globals the
# caller copies at once because a nested parse can re-enter this:
#   RDT_RU_CMDS   every -c / --command / --session-command operand (su's grammar)
#   RDT_RU_U      1 when -u / --user was given, which makes it a launcher;
#                 runuser-only (su has no -u)
#   RDT_RU_ARGV   the non-option words, then everything after the first `--`
#   RDT_RU_QUOTED the quoting provenance of each RDT_RU_ARGV word, copied from
#                 HOOK_SEG_WORD_QUOTED at <offset> plus its original position
#   RDT_RU_SHELL  the last -s / --shell operand, empty when none was given
# A short cluster holding a letter runuser rejects, or a long option it does
# not know or cannot resolve, makes runuser refuse the whole invocation. Once
# a non-option has been seen, that word is kept as one rather than read as
# options, so `runuser -u bob rm -rf /` still reads `-rf` as rm's flag and the
# words stay right when POSIXLY_CORRECT stops getopt at the first non-option.
# Ahead of every non-option it is dropped, so it never becomes the command
# word (`runuser -u root --foo rm -rf /`).
# su shares this option parser, so its arm reads su's argv here too, to find
# the words that follow a -s program that is not a shell.
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
      # getopt_long: an exact name wins, otherwise a UNIQUE prefix; an
      # ambiguous or unknown name is an error that consumes nothing more.
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
        # Never the command word, only an operand after it (see below).
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
        [[ "$hit" == "command" || "$hit" == "session-command" ]] && RDT_RU_CMDS+=("$val")
        # su builds `sh -c -- CMD` from an operand of `--`, so CMD is the next word.
        [[ ("$hit" == "command" || "$hit" == "session-command") && "$val" == "--" ]] && ((k < n)) && RDT_RU_CMDS+=("${a[k]}")
        [[ "$hit" == "user" ]] && RDT_RU_U=1
        [[ "$hit" == "shell" ]] && RDT_RU_SHELL="$val"
        ;;
      *) ;;
      esac
      continue
      ;;
    -?*)
      # A short cluster: flags, then at most one operand-taking letter, which
      # takes the rest of the word or, when it is last, the next word.
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
      # A rejected cluster, like an unknown long option, is never the
      # command word.
      if ((${#RDT_RU_ARGV[@]} == 0)); then
        k=$((k + 1))
        continue
      fi
      ;;
    *) ;;
    esac
    RDT_RU_ARGV+=("$w")
    RDT_RU_QUOTED+=("${HOOK_SEG_WORD_QUOTED[off + k]:-0}")
    k=$((k + 1))
  done
  return 0
}

# rdt_su_shell_run: su and runuser exec their -s / --shell program with the
# words after the user as its arguments. When that program is not a shell, it
# is the command itself (`su root -s /bin/rm -- -rf /`), so it is judged as
# one. Reads the RDT_RU_* results of the rdt_runuser_argv call just made, and
# must run before any parse re-enters it.
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

# rdt_short_cluster_arg <launcher> <cluster>: true when a short cluster such as
# `-nw` holds a letter that takes an operand. getopt walks the letters, and the
# FIRST operand-taking one takes the rest of the cluster, or the next word when
# it is the last letter; RDT_SC_NEXT is 1 in that second case. A letter whose
# operand is OPTIONAL (nsenter's `-m`) takes the rest of the cluster and never
# the next word, so it ends the walk with nothing to report. The letters come
# from each launcher's getopt string; sudo and doas are a declared gap, and
# taskset and chroot have no operand-taking short option.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_short_cluster_arg() {
  local w="$2" ops opt="" k ch
  RDT_SC_NEXT=0
  case "$1" in
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

# rdt_long_takes_arg <launcher> <name>: true when `--<name>`, written without
# `=`, takes the next word as its operand. getopt_long accepts any unambiguous
# prefix, so `flock --wa 5` is `flock --wait 5`; an ambiguous prefix is counted
# as taking one only when every candidate does. The walk judges this reading IN
# ADDITION to the plain one that steps over the word alone, and blocks if
# either does, so resolving a prefix can only add refusals.
# Each list is the launcher's operand-taking long names, then its flag names.
# The `ops` lists must stay in sync with each launcher's `optarg` long names.
# sudo and doas are absent: their abbreviations are a declared gap.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_long_takes_arg() {
  local name="$2" ops fls o nop=0 nfl=0
  [[ -n "$name" ]] || return 1
  case "$1" in
  env)
    ops="unset chdir"
    fls="ignore-environment null block-signal default-signal ignore-signal list-signal-handling debug help version"
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
    [[ "$o" == "$name"* ]] && nfl=$((nfl + 1))
  done
  ((nop > 0 && nfl == 0))
}

# rdt_abbr is 1 inside a RESOLVED walk, where an abbreviated launcher long
# option takes its operand; see that arm in rdt_check_segment. rdt_resolved
# counts those walks for the whole command, and past the cap the guard
# REFUSES rather than judging one reading only.
rdt_abbr=0
rdt_resolved=0
MAX_RESOLVED_WALKS=256

# rdt_resolved_walk <argv word>...: judge one segment with every abbreviated
# launcher long option taking its operand. The provenance array is restored
# afterwards, because a nested parse inside the walk rebuilds it.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_resolved_walk() {
  rdt_resolved=$((rdt_resolved + 1))
  ((rdt_resolved > MAX_RESOLVED_WALKS)) && rdt_block "too-many-abbreviations"
  local rdt_abbr=1
  local -a saved_q=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"})
  rdt_check_segment "$@"
  HOOK_SEG_WORD_QUOTED=(${saved_q[@]+"${saved_q[@]}"})
}

# rdt_check_segment <argv word>...: one simple command, as the shell would build
# it. Prefixed because guards share one process under run-guards.sh and two
# siblings already define a function named check_segment.
# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
rdt_check_segment() {
  # Every launcher, child shell and eval re-enters this function, so nesting
  # is bash recursion; deep enough, bash exhausts its stack and dies before a
  # block's `exit 2`. The depth is a dynamic local, so every return restores
  # the caller's count with no bookkeeping, and past MAX_SEGMENT_DEPTH the
  # guard REFUSES.
  local rdt_depth=$((rdt_depth + 1))
  ((rdt_depth > MAX_SEGMENT_DEPTH)) && rdt_block "nesting-too-deep-launcher"
  local -a words=("$@")
  local n=$# i=0 j w base sval optarg consume_bare
  local abbr_forked=0

  # Command word: step over leading NAME=value assignments and over a launcher
  # that takes the real command as its argument. A launcher's own options are
  # skipped, and the ones that CONSUME AN OPERAND are skipped with it: without
  # that, `sudo -u bob rm -rf /` reads `bob` as the command word and the whole
  # segment is waved through.
  while ((i < n)); do
    w="${words[i]}"
    if [[ "$w" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      i=$((i + 1))
      continue
    fi
    # A RESERVED WORD ahead of the command is not the command. The tokenizer
    # splits on `;`, `&`, `|`, `(` and `)`, so a compound command hands over
    # segments that OPEN with one of these: `{ rm -rf /; }` arrives as `{ rm
    # -rf /`, `if true; then rm -rf /; fi` as `then rm -rf /`, and every loop
    # body as `do rm -rf /`. Without this arm the reserved word IS read as the
    # command word and the whole segment is waved through. `function` also
    # names the definition that follows, so its name word is stepped over with
    # it; a `name()` opener needs no arm, because `(` is a segment separator
    # and the name has already closed its own segment by then.
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
      # `coproc [NAME] command`. Bash accepts the NAME only ahead of a COMPOUND
      # command; ahead of a SIMPLE one the first word IS the command, so
      # `coproc shredder rm -rf /` runs a command named `shredder` and
      # `coproc bash -c '…'` runs bash. Stepping over any identifier followed
      # by a word therefore swallowed the real command word. The NAME is now
      # stepped over only when a compound opener follows it.
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
    # Lowercased BEFORE the suffix strip: `.exe` is spelled in any case on a
    # case-insensitive filesystem, and stripping first left `rm.EXE` reading as
    # `rm.exe` rather than `rm`.
    base="${base,,}"
    base="${base%.exe}"
    # optarg lists the launcher's operand-taking options, space-delimited on
    # both sides so a prefix cannot match. Every short form carries its LONG
    # alias beside it: the separate-operand spelling is the one that moves the
    # command word, and listing `-u` alone read `sudo --user root rm -rf /` as a
    # command named `root`. The `--opt=value` spelling is deliberately absent,
    # because it carries its own operand and consumes no following word.
    # consume_bare marks a launcher whose first bare word is its own argument
    # rather than the command (`timeout` takes a duration).
    consume_bare=0
    case "$base" in
    sudo | doas) optarg=" -u --user -g --group -p --prompt -C --close-from -D --chdir -r --role -t --type -T --command-timeout -U --other-user -h --host " ;;
    # The util-linux launchers. Each operand list is read from the tool's own
    # getopt string; an option whose argument is OPTIONAL (nsenter's `-m`,
    # unshare's `--mount`) takes it only when attached, so it consumes no word.
    # taskset's mask, flock's lock file and chroot's NEWROOT always precede the
    # command, and chrt's priority does when it is all digits.
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
    # runuser has two grammars and both are judged, blocking if either does:
    # every -c / --command / --session-command operand is a command, and with
    # -u its non-option words are the command. Without -u the first non-option
    # is the user and the rest go to the shell, so they get su's scan. The
    # remapped provenance is saved first, because each parse rebuilds it.
    runuser)
      rdt_runuser_argv "$((i + 1))" ${words[@]+"${words[@]:i+1}"}
      local -a ru_cmds=() ru_argv=() ru_quoted=()
      local ru_u="$RDT_RU_U" ru_cmd
      ru_cmds=(${RDT_RU_CMDS[@]+"${RDT_RU_CMDS[@]}"})
      ru_argv=(${RDT_RU_ARGV[@]+"${RDT_RU_ARGV[@]}"})
      ru_quoted=(${RDT_RU_QUOTED[@]+"${RDT_RU_QUOTED[@]}"})
      rdt_su_shell_run
      for ru_cmd in ${ru_cmds[@]+"${ru_cmds[@]}"}; do
        hook::bash_parse_segments "$ru_cmd" rdt_check_segment
      done
      if ((ru_u)); then
        HOOK_SEG_WORD_QUOTED=(${ru_quoted[@]+"${ru_quoted[@]}"})
        ((${#ru_argv[@]})) && rdt_check_segment "${ru_argv[@]}"
      elif ((${#ru_argv[@]} > 1)); then
        HOOK_SEG_WORD_QUOTED=()
        rdt_check_segment su "${ru_argv[@]:1}"
      fi
      return 0
      ;;
    # `-S` / `--split-string` is absent on purpose: it is not an opaque option
    # argument but a COMMAND, and the arm below re-parses it.
    env) optarg=" -u --unset -C --chdir " ;;
    timeout)
      optarg=" -s --signal -k --kill-after "
      consume_bare=1
      ;;
    nice | ionice) optarg=" -n --adjustment -c --class --classdata -p --pid " ;;
    stdbuf) optarg=" -i -o -e --input --output --error " ;;
    # /usr/bin/time, not the bash keyword, takes a format and an output file.
    time) optarg=" -f --format -o --output " ;;
    exec) optarg=" -a " ;;
    # busybox is a multi-call binary: `busybox rm -rf /` runs its own rm.
    command | nohup | setsid | busybox) optarg="" ;;
    *) break ;;
    esac
    i=$((i + 1))
    while ((i < n)); do
      w="${words[i]}"
      case "$w" in
      --)
        i=$((i + 1))
        # `--` ends the options but not the positional: `taskset -- 1 rm` still
        # reads `1` as the mask. chrt's priority must be all digits, and
        # timeout's duration must start like a number, so `timeout -- rm -rf /`
        # keeps `rm` as the command word rather than reading it as a duration.
        # timeout's test follows strtod: leading space, a sign, then a digit,
        # a `.`, inf or nan in any case.
        if ((consume_bare && i < n)); then
          case "$base" in
          chrt) [[ "${words[i]}" =~ ^[0-9]+$ ]] && i=$((i + 1)) ;;
          timeout) [[ "${words[i]}" =~ ^[[:space:]]*[+-]?([0-9.]|[iI][nN][fF]|[nN][aA][nN]) ]] && i=$((i + 1)) ;;
          *) i=$((i + 1)) ;;
          esac
          # flock takes -c / --command right after its lock file, `--` or not.
          if [[ "$base" == "flock" ]] && ((i < n)) && [[ "${words[i]}" == "-c" || "${words[i]}" == "--command" ]]; then
            ((i + 1 < n)) && hook::bash_parse_segments "${words[i + 1]}" rdt_check_segment
            return 0
          fi
        fi
        break
        ;;
      -*)
        # flock runs a -c / --command operand through a shell, and demands it
        # be the last word, so the operand is the whole command.
        if [[ "$base" == "flock" && ("$w" == "-c" || "$w" == "--command") ]]; then
          ((i + 1 < n)) && hook::bash_parse_segments "${words[i + 1]}" rdt_check_segment
          return 0
        fi
        # With --fd the lock is an already-open descriptor, so there is no lock
        # file and flock's first positional is the command itself.
        [[ "$base" == "flock" && ("$w" == "--fd" || "$w" == --fd=*) ]] && consume_bare=0
        # GNU env's `-S` SPLITS its operand and RUNS the result, so the operand
        # is a command and not an option argument to step over. The split words
        # are spliced back in ahead of whatever followed, exactly as
        # block-no-verify's git resolver does, and the segment is judged again.
        # Bounded: the splice replaces the `-S` word AND its operand with the
        # operand's own words, so the argv's byte count strictly decreases.
        if [[ "$base" == "env" ]]; then
          case "$w" in
          -S | --split-string)
            sval=""
            ((i + 1 < n)) && sval="${words[i + 1]}"
            hook::env_s_split "$sval"
            # Cleared because the provenance array belongs to the OUTER parse
            # and its indices do not describe these words; a stale 1 here would
            # read an empty word as a dropped backslash.
            HOOK_SEG_WORD_QUOTED=()
            rdt_check_segment ${HOOK_ENV_S_WORDS[@]+"${HOOK_ENV_S_WORDS[@]}"} \
              ${words[@]+"${words[@]:i+2}"}
            return 0
            ;;
          -S* | --split-string=*)
            sval="${w#-S}"
            sval="${sval#--split-string=}"
            hook::env_s_split "$sval"
            HOOK_SEG_WORD_QUOTED=()
            rdt_check_segment ${HOOK_ENV_S_WORDS[@]+"${HOOK_ENV_S_WORDS[@]}"} \
              ${words[@]+"${words[@]:i+1}"}
            return 0
            ;;
          *) ;;
          esac
        fi
        # An abbreviated long option takes its operand exactly as the full name
        # does. Two readings are judged, and a block from either stands: the
        # PLAIN one, which steps over the word alone,
        # and the RESOLVED one, which takes the operand at every abbreviation.
        # The first abbreviation in a plain walk starts one resolved walk of the
        # whole segment; a resolved walk consumes and never starts another, so
        # the work is two walks per segment, not one per combination.
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
        # A short cluster ending in an operand-taking letter (`flock -nw 1`)
        # takes the next word as that letter's operand. It is judged on the
        # same two readings, through the same one resolved walk per segment.
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
        # chrt reads a priority only when the word is all digits; otherwise
        # that word is already the command.
        [[ "$base" == "chrt" && ! "$w" =~ ^[0-9]+$ ]] && break
        consume_bare=0
        i=$((i + 1))
        ;;
      esac
    done
  done
  ((i < n)) || return 0

  # A child shell runs its operand as a full command, so one process is every
  # command inside it. Re-parse that operand with the same tokenizer, which is
  # what block-no-verify.sh does for `git`. Asked AFTER the launcher walk, from
  # the resolved command word on, so `sudo bash -c '...'` is unwrapped too.
  # Re-entering the parser from its own callback is safe: its state is
  # dynamically scoped locals plus HOOK_SEG_* globals it rebuilds before every
  # call, and the only one this guard reads is rebuilt with them.
  if hook::shell_c_operand "${words[@]:i}"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" rdt_check_segment
    return 0
  fi

  base="${words[i]##*/}"
  # Lowercased before the suffix strip, for the reason given at the walk above.
  base="${base,,}"
  base="${base%.exe}"

  # `su` runs its `-c` operand through the target user's shell, so one process
  # is every command inside it, exactly as `bash -c` is. Resolved here rather
  # than in the shared hook::shell_c_operand because su's grammar differs: the
  # operand follows the FLAG, and a user name may sit ahead of it
  # (`su bob -c '…'`), where a shell takes its first bare word.
  #
  # FAIL-CLOSED rather than exact: EVERY word that follows a -c-like word is
  # parsed, not only the first. su takes the LAST -c it sees, and a word that
  # looks like -c may really be another option's operand (`su -w -c -c '…'`),
  # so parsing every candidate is what keeps both readings covered.
  if [[ "$base" == "su" ]]; then
    local k
    local sulong
    rdt_runuser_argv "$((i + 1))" ${words[@]+"${words[@]:i+1}"}
    rdt_su_shell_run
    for ((k = i + 1; k < n; k++)); do
      case "${words[k]}" in
      --?*)
        # getopt_long takes any unambiguous prefix. No other su option starts
        # with `c`, and `se` is the shortest prefix that separates
        # session-command from shell and supp-group.
        sulong="${words[k]#--}"
        sulong="${sulong%%=*}"
        if [[ -n "$sulong" && ("command" == "$sulong"* || ("${#sulong}" -ge 2 && "session-command" == "$sulong"*)) ]]; then
          if [[ "${words[k]}" == *=* ]]; then
            hook::bash_parse_segments "${words[k]#*=}" rdt_check_segment
            # su builds `sh -c -- CMD` from an operand of `--`, so CMD is next.
            ((k + 1 < n)) && [[ "${words[k]#*=}" == "--" ]] && hook::bash_parse_segments "${words[k + 1]}" rdt_check_segment
          else
            ((k + 1 < n)) && hook::bash_parse_segments "${words[k + 1]}" rdt_check_segment
            # A shell reads `-c -- '…'` as `-c '…'`, so the word after `--` too.
            ((k + 2 < n)) && [[ "${words[k + 1]}" == "--" ]] && hook::bash_parse_segments "${words[k + 2]}" rdt_check_segment
          fi
        fi
        ;;
      -*)
        if [[ "${words[k]}" =~ ^-[A-Za-z]+$ && "${words[k]}" == *c* ]]; then
          ((k + 1 < n)) && hook::bash_parse_segments "${words[k + 1]}" rdt_check_segment
          ((k + 2 < n)) && [[ "${words[k + 1]}" == "--" ]] && hook::bash_parse_segments "${words[k + 2]}" rdt_check_segment
        fi
        # An operand ATTACHED to the -c is the text after the first `c` that
        # only letters precede: `su -c'rm -rf /'` is the one word `-crm -rf /`.
        if [[ "${words[k]}" =~ ^-[A-Zabd-z]*c. ]]; then
          sulong="${words[k]#-}"
          hook::bash_parse_segments "${sulong#*c}" rdt_check_segment
          ((k + 1 < n)) && [[ "${sulong#*c}" == "--" ]] && hook::bash_parse_segments "${words[k + 1]}" rdt_check_segment
        fi
        ;;
      *) ;;
      esac
    done
    return 0
  fi

  # `eval` runs its arguments as a command in THIS shell, so the child-shell
  # unwrap above never applies to it: there is no `-c` and no new process. Its
  # arguments are joined with a space, exactly as eval joins them, and parsed.
  # Bounded because each level drops at least the `eval` word itself.
  #
  # An operand a trailing backslash produced arrives EMPTY (the tokenizer has
  # no character left to emit), so a join by text would hand the re-parse
  # `rm -rf ` with no operand at all and `eval rm -rf \` would pass. The
  # literal `\` is restored first, by the same provenance test the operand loop
  # below uses, and `HOOK_SEG_WORD_QUOTED` is read HERE because the re-parse
  # rebuilds it.
  if [[ "$base" == "eval" ]] && ((i + 1 < n)); then
    local -a ev=()
    for ((j = i + 1; j < n; j++)); do
      if [[ -z "${words[j]}" ]] && ((${HOOK_SEG_WORD_QUOTED[j]:-0} == 1)); then
        # shellcheck disable=SC1003  # a literal backslash character, not a quote escape
        ev+=('\')
      else
        ev+=("${words[j]}")
      fi
    done
    # The joined text is charged to the same tokenizing budget as a
    # substitution body: nested evals re-tokenize nearly the whole command at
    # every level, which is the same multiplication the budget exists to stop.
    local evtext="${ev[*]}"
    rdt_scanned=$((rdt_scanned + ${#evtext}))
    ((rdt_scanned > MAX_COMMAND_LEN)) && rdt_block "eval-too-long"
    hook::bash_parse_segments "$evtext" rdt_check_segment
    return 0
  fi

  [[ "$base" == "rm" ]] || return 0

  # Flags and operands. `--` ends option parsing, exactly as rm reads it.
  # Operands are kept as INDICES, not values, because the decision below needs
  # each one's quoting provenance as well as its text.
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
        # coreutils parses long options with getopt_long, which accepts any
        # UNAMBIGUOUS prefix, so `rm --r -f /` and `rm --no-p /` are the real
        # options spelled short. Of rm's long options only `--recursive` starts
        # with `r` and only `--no-preserve-root` starts with `n`, so every
        # non-empty prefix of either name is unambiguous and is treated as that
        # option. Matching the exact spelling alone left both a bypass.
        long="${w#--}"
        if [[ "recursive" == "$long"* ]]; then
          recursive=1
        elif [[ "no-preserve-root" == "$long"* ]]; then
          no_preserve=1
        fi
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
    operand_idx+=("$j")
  done

  # Every arm below needs recursion. A non-recursive `rm /` is refused by rm
  # itself and is not this guard's business.
  ((recursive)) || return 0
  ((no_preserve)) && rdt_block "no-preserve-root"

  local norm
  for j in ${operand_idx[@]+"${operand_idx[@]}"}; do
    w="${words[j]}"
    # An EMPTY operand that a BACKSLASH ESCAPE produced is a dropped trailing
    # backslash: bash passes a literal `\` when one ends the input, and MSYS
    # resolves that to the current drive root, which is the #92593 incident
    # minus its quotes. The tokenizer cannot represent it (it has no character
    # left to emit), so provenance is what separates it from `rm -rf ""`, whose
    # empty operand comes wholly from a quoted span (provenance 2) and is
    # correctly allowed.
    if [[ -z "$w" ]] && ((${HOOK_SEG_WORD_QUOTED[j]:-0} == 1)); then
      rdt_block "root-operand" "/"
    fi
    rdt_normalize_to norm "$w"
    if rdt_is_root "$norm"; then
      rdt_block "root-operand" "$norm"
    fi
  done
  return 0
}

# rdt_scan_substitutions <text>: check the body of every command substitution.
#
# A substitution RUNS before the word it builds is used, so the shell executes
# the inner command whatever the outer one is: `echo "$(rm -rf /)"` deletes the
# root and then echoes nothing. The shared tokenizer keeps a substitution INSIDE
# the enclosing argv word, which is correct for its own purpose and means the
# segment callback only ever sees `echo`. So each body is lifted out here and
# parsed on its own, and the stack below covers a body that holds another.
#
# QUOTING IS HONORED, because the shell honors it. A `$(` inside a SINGLE-quoted
# span is inert (`echo '$(rm -rf /)'` prints the text and runs nothing), and so
# is a `\$(` inside a double-quoted one; reading the raw characters called both
# a substitution and refused a command that deletes nothing. The same machine
# locates the CLOSE: a `)` inside a quoted span is not the terminator, so
# `echo "$(printf '%s\n' ')'; rm -rf /)"` ends where bash ends it rather than at
# the quoted paren, which had been cutting the body off before the delete.
#
# ONE LINEAR PASS, not a descent. Parens are tracked on a stack, and a body is
# parsed when its own `)` pops it, so a substitution inside another is reached
# by the same walk that reached the outer one. Each entry remembers the quoting
# state it interrupted, because a substitution body starts a FRESH quoting
# context (`"$(echo "x")"` has two independent double-quoted spans). `$((` is
# arithmetic: its `$` is stepped over and its two parens ride the stack as
# ordinary ones, so its `))` balances them instead of closing a substitution.
#
# The stack depth is capped, and past the cap the guard REFUSES; see
# MAX_SUBST_DEPTH. An unterminated substitution is parsed to end of text rather
# than dropped, so a payload that never closes still fails closed.

# rdt_scan_body <body>: tokenize one substitution body, under two budgets.
#
# A body whose TEXT does not contain `rm` cannot carry the one verb the matcher
# recognizes, so it is not tokenized at all: the same reasoning as the prefilter
# in front of the whole guard.
#
# The rest are charged against ONE MAX_COMMAND_LEN budget, because the depth cap
# bounds the nesting and not the WORK. Nesting multiplies the text to tokenize,
# so a command at the 16 KB ceiling nested 32 deep is half a megabyte of
# tokenizing, and a hook the harness cancels on its own timeout is cancelled
# WITHOUT a block. Running past the budget would therefore fail OPEN on exactly
# the input built to reach it, so the budget REFUSES instead.
#
# The budget counts SUBSTITUTION BODIES ONLY, and starts at zero. Charging the
# command's own length against it as well refused any command past about half
# the ceiling that carried one ordinary substitution, while leaving a flat
# command just under the ceiling alone: a size limit on the wrong thing.
# SIBLING bodies cannot exhaust this budget, because each one's text sits in
# the command and the command has its own ceiling. NESTING can, because a
# nested body's text is charged once per level enclosing it, and nesting is the
# shape that made the scan slow enough to reach the harness timeout.
rdt_scanned=0
rdt_scan_body() {
  local b="$1"
  [[ -n "$b" ]] || return 0
  case "${b,,}" in
  *rm*) ;;
  *) return 0 ;;
  esac
  rdt_scanned=$((rdt_scanned + ${#b}))
  ((rdt_scanned > MAX_COMMAND_LEN)) && rdt_block "bodies-too-long"
  hook::bash_parse_segments "$b" rdt_check_segment
}

# shellcheck disable=SC1003  # '\' compares a literal backslash char, not a quote escape
rdt_scan_substitutions() {
  local s="$1" q="" c nx
  # Each open paren rides the stack with its KIND: 0 an ordinary paren that
  # only balances, 1 a `$( )` substitution, 2 a backtick one. Only 1 and 2
  # carry a body to parse, and only they count toward the depth cap.
  local -i len=${#s} i=0 pd=0 sd=0 k st ansi=0
  local -a st_start=() st_q=() st_kind=()
  while ((i < len)); do
    c="${s:i:1}"
    # A single-quoted span performs no expansion at all; only its own closing
    # quote ends it. `$'…'` is the one spelling where a backslash still escapes.
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
    # Unquoted, a backslash escapes whatever follows. Inside double quotes it
    # escapes only the four characters bash lets it, and is literal otherwise.
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
    case "$c" in
    '"')
      if [[ "$q" == '"' ]]; then q=""; else q='"'; fi
      ;;
    "'")
      # Literal inside double quotes; an opener outside them.
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
      # An ordinary paren (a subshell, one half of an arithmetic pair) only
      # balances, so its `)` cannot be mistaken for a substitution's.
      if [[ "$q" != '"' ]]; then
        st_kind[pd]=0
        st_start[pd]=-1
        st_q[pd]="$q"
        pd=$((pd + 1))
      fi
      ;;
    ')')
      # Inside a backtick body a stray `)` closes nothing, so it is left alone.
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
      # Backticks do not nest, so the top of the stack is either this one's
      # opener or something it encloses.
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
  # A substitution that never closed is parsed to the end of the text: the
  # command would not run as written, but a guard that silently dropped it
  # would be answering a different question than the one it was asked.
  for ((k = 0; k < pd; k++)); do
    ((st_kind[k] == 0)) && continue
    st=${st_start[k]}
    rdt_scan_body "${s:st}"
  done
}

# The substitution scan runs FIRST, and the order is load-bearing rather than
# arbitrary. The tokenizer splits on unquoted `(`, `)` and `;`, so a deeply
# nested payload yields as many segments as a flat one of the same length and
# the top-level parse pays for every one of them. Scanning first lets the
# tokenizing budget refuse such a payload after the cheap character walk alone,
# instead of after the parse it was built to make expensive.
rdt_scan_substitutions "$COMMAND"
hook::bash_parse_segments "$COMMAND" rdt_check_segment

rdt_emit_tel "ok" ""
exit 0
