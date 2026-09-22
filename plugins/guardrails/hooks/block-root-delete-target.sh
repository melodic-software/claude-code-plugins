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
#     their siblings, and `su`'s `-c` / `--command` / `--session-command`
#     operand ARE unwrapped and re-parsed; an interpreter that is not a shell
#     (`python -c`, `perl -e`) is not.
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

# rdt_check_segment <argv word>...: one simple command, as the shell would build
# it. Prefixed because guards share one process under run-guards.sh and two
# siblings already define a function named check_segment.
# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
rdt_check_segment() {
  local -a words=("$@")
  local n=$# i=0 j w base cn optarg consume_bare

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
      # `coproc [NAME] command`. The NAME is optional, so it is stepped over
      # only when a command still follows it and the NAME is not itself the
      # verb: that keeps `coproc rm -rf /` reading `rm` while
      # `coproc shredder rm -rf /` reads past the name to the same place.
      i=$((i + 1))
      if ((i + 1 < n)) && [[ "${words[i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        cn="${words[i],,}"
        cn="${cn%.exe}"
        [[ "$cn" != "rm" ]] && i=$((i + 1))
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
    env) optarg=" -u --unset -C --chdir -S --split-string " ;;
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
        break
        ;;
      -*)
        if [[ -n "$optarg" && "$optarg" == *" $w "* ]]; then
          i=$((i + 2))
        else
          i=$((i + 1))
        fi
        ;;
      *)
        ((consume_bare)) || break
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
  if [[ "$base" == "su" ]]; then
    local k
    for ((k = i + 1; k < n; k++)); do
      case "${words[k]}" in
      --command=* | --session-command=*)
        hook::bash_parse_segments "${words[k]#*=}" rdt_check_segment
        return 0
        ;;
      --command | --session-command)
        ((k + 1 < n)) && hook::bash_parse_segments "${words[k + 1]}" rdt_check_segment
        return 0
        ;;
      -*)
        if [[ "${words[k]}" =~ ^-[A-Za-z]+$ && "${words[k]}" == *c* ]]; then
          ((k + 1 < n)) && hook::bash_parse_segments "${words[k + 1]}" rdt_check_segment
          return 0
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
    hook::bash_parse_segments "${ev[*]}" rdt_check_segment
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
# parsed on its own, and recursion covers a body that holds another.
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
# shellcheck disable=SC1003  # '\' compares a literal backslash char, not a quote escape
rdt_scan_substitutions() {
  local s="$1" q="" c nx body
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
          body="${s:st:i - st}"
          [[ -n "$body" ]] && hook::bash_parse_segments "$body" rdt_check_segment
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
        body="${s:st:i - st}"
        [[ -n "$body" ]] && hook::bash_parse_segments "$body" rdt_check_segment
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
    body="${s:st}"
    [[ -n "$body" ]] && hook::bash_parse_segments "$body" rdt_check_segment
  done
}

hook::bash_parse_segments "$COMMAND" rdt_check_segment
rdt_scan_substitutions "$COMMAND"

rdt_emit_tel "ok" ""
exit 0
