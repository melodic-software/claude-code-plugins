#!/usr/bin/env bash
# PreToolUse hook: block a recursive delete whose TARGET is a filesystem root.
# Triggered on Bash and PowerShell tool calls (a command string).
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
# THREE MORE TARGET CLASSES, each refused with its own message:
#   * An EMPTY operand (`rm -rf ""`, `rm -rf "" build`): a path that failed to
#     build. `rm -rf` with no operand has nothing to judge and stays allowed.
#   * A BARE VARIABLE operand: after normalization the word is made of
#     expansions and nothing else (`$NAME`, `${...}` in any form, a positional
#     or special parameter, `$X$Y`). Unset or empty, it reaches the working
#     directory or a root. Only `${X:?...}` aborts the command on an empty
#     value too, so an operand of that form alone, such as `"${X:?}/"`, stays
#     allowed. A nested `${...}` is one unit judged by its outermost operator:
#     `${X:-${Y:-/}}` is refused and `${X:?${Y}}` is allowed.
#   * A target OUTSIDE THE SESSION'S ALLOWED ROOTS, judged only when the
#     payload carries an absolute `cwd`. A target must resolve under the git
#     toplevel of the payload cwd, or strictly under a temp root or the payload
#     `scratchpad_dir` (honored only when it sits strictly under a temp root);
#     a temp root itself, its glob and the scratchpad itself are refused. The
#     userConfig key block_root_delete_target_allowed_roots, read from the
#     hook's own environment and never from the command text, adds roots on
#     the temp-root rule: comma-separated absolute directories, compared by
#     real path, so a target is allowed only strictly under one, and the root
#     itself and its glob stay refused. An entry ending in one `*` after a
#     literal name (`D:/worktrees/.tmp-*`) is a NAME PREFIX instead: only a
#     direct child of its directory whose name extends the prefix by at least
#     one character passes, and never one that is itself a symlink, ends in
#     a dot or a space (Win32 trims them), or is named with a trailing slash
#     before it exists (a link the same command creates). An entry
#     that is relative, empty, UNC, holds any other glob character, a line
#     break or a `..` component, or resolves
#     to a filesystem root or HOME grants nothing, and no listed root lets
#     through a filesystem root, HOME or a directory holding HOME. Every other
#     refusal in this guard runs before this judgment and ignores the key.
#     A directory a literal cd reaches is judged against the cwd's tree, never a
#     tree of its own. Unquoted braces are expanded the way bash expands them
#     and every alternative is judged as its own operand (a sequence, more
#     than 64 alternatives, a word over 4096 bytes or 128 braces, or a partly
#     quoted brace is refused). A glob before the last component is expanded
#     against the filesystem one component at a time and each match judged as
#     a literal path; every glob operand is also judged as its own literal
#     text, which bash passes when nothing matches; a `..` after a glob is
#     refused. An operand ending in `/` is resolved whole, because rm then
#     follows a symlink (a `*/` glob's symlink matches are read and judged by
#     where they point). `~name` and a newline in an operand are refused.
#     Operands are collected while the command is parsed and judged once at
#     the end, with one realpath, (on Windows) one cygpath and one git for the
#     whole command. Past 32 directories (counting the starting one), 512
#     directory-and-target pairs, 256 glob entries in total across the levels
#     of one glob, 25 seconds of wall time from this arm's first work (through
#     the rest of the parse and the judgment), or 50 seconds of the hook's
#     whole run once that work has begun, the guard refuses rather than risk
#     the hook timeout, and an unexpected error while judging refuses too.
#     The batched realpath and cygpath run under `timeout` for the time left
#     where `timeout` exists, and an operand over 4096 bytes or 128
#     separators is refused before any scan. Where `timeout` is absent
#     (stock macOS) a batch call cannot be cut short: the clock is checked
#     on both sides of it, and the operand caps are what keep one call short.
#     An
#     operand this guard cannot place (an expansion other than a leading HOME,
#     a drive-relative path) is left alone rather than guessed. A NUL byte in
#     the payload `cwd` or `scratchpad_dir` refuses a recursive delete this
#     arm must judge and leaves every other command alone; a NUL byte in the
#     command itself still refuses every call.
#
# KNOWN FALSE POSITIVES. These are refused although harmless, because the
# guard cannot tell them apart from a harmful spelling: a single-quoted `'$X'`
# (read as a bare variable), `~-` (read as `~name`), `cd sub && rm -rf ../x`
# and `(cd ..) ; rm -rf build` and `env -C /opt true; rm -rf build` (a
# relative operand must stay inside from every directory the command may run
# it from, because the guard does not assume a cd succeeded or which command a
# directory change applies to), `cd <worktree> && rm -rf .work/x`
# from a different checkout's cwd (every target is judged against the payload
# cwd's tree), a glob over directories of many entries (every entry read at
# every level of the glob counts toward the 256 cap, files included, so
# `rm -rf node_modules/*/` over a large directory and `rm -rf
# src/*/__pycache__` over a large `src` are refused), an operand over 4096
# bytes or 128 path separators, an expansion followed by a segment of
# punctuation alone (`${X:-{a,b}}/*` leaves a literal `}`, which names nothing
# here), a backslash-escaped brace (it reads as partly quoted), and the three
# launcher lines decided below.
#
# LAUNCHER LINES REFUSED BY DECISION (#4681). Each is refused although the
# launcher does not delete the host root, and each stays refused on purpose:
#   * `chrt -r rm -rf /`, `chrt -f rm -rf /` and a bare `chrt rm -rf /`
#     (round-robin by default). chrt reads the word after a realtime policy
#     as its priority, so it rejects these lines before exec: util-linux
#     2.39.3 through 2.41 exits 1 with "invalid priority argument", 2.42 on
#     with "policy <name> requires a priority argument". The same line
#     under `-o`, `-b`, `-i`, `-d` or `-e` does run `rm` from 2.42, where the
#     priority became optional for those policies, so a non-digit word after
#     chrt is always read as the command. The cost is one retry and never a
#     lost file.
#   * `runuser -u bob rm -rf /` without `--`. runuser's getopt permutes, so
#     `-rf` is read as its own option and the line exits 1 with "invalid
#     option -- 'r'". Under POSIXLY_CORRECT, which a command inherits without
#     showing it, options end at `rm` and the delete runs; the guard cannot
#     see the shell's environment, so it refuses on both readings.
#   * `chroot <dir> rm -rf /` and `rm -rf /*` under it. chroot's `/` is host
#     `<dir>`, so the bare `/` spelling empties `<dir>` and every host
#     directory bind-mounted inside it. An unquoted `/*` is expanded by the
#     invoking shell against the HOST root before chroot runs, so rm receives
#     the host's top-level names and resolves each under `<dir>`: still a
#     recursive delete inside `<dir>`, and still refused. Only GNU rm's
#     default --preserve-root stops the bare `/` spelling, and not those names
#     or `--no-preserve-root`. Not a harmless line, so kept on the refusal
#     side.
#
# SCOPE: this guard is friction against accidental or casual root deletes, not
# a sandbox (see the README Scope notes). The launcher grammar is not widened
# further without a filed bypass. Converging the PowerShell walker with
# lib/powershell/ps-command.sh stays deferred; any future convergence is
# checked against the delete lane in scripts/check-guardrails-ps-differential.sh.
#
# DECLARED GAPS, stated rather than hidden, matching this family's convention:
#   * PowerShell is covered for the same target classes as Bash, with its own
#     tokenizer (not lib/powershell/ps-command.sh, so this guard stays off the
#     classifier's sink-attempt budget). Matched: Remove-Item and its aliases
#     (ri, rm, del, erase, rd, rmdir) with -Recurse on any unambiguous prefix
#     (-r, -rec, -Recurse) or the bash-in-PS cluster -rf; cmd /c (and /k)
#     rd /s and rmdir /s; a pipeline into Remove-Item -Recurse with no path.
#     A statement ends at `; | & && ||` and at an unquoted newline (LF, CRLF or
#     a bare CR) that no backtick continues. An unquoted `(`, `$(` or `{`
#     opens a nested level whose statements are judged on their own, so a
#     delete after a newline or inside a scriptblock, a grouping or `$( )` is
#     caught; the closing `)` or `}` leaves one placeholder word in the
#     statement that was open, so that statement keeps its later arguments. A
#     target that is a `( )`, `$( )` or `@( )` grouping is refused, because its
#     value is not known: as a positional operand even without -Recurse, and
#     as a -Path value with it. So is a `{ }` scriptblock named as a target of
#     a recursive delete; as the value of -Filter, -Include or -Exclude it is
#     stepped over. The
#     operand `$env:NAME` or `${env:NAME}` is judged as the Bash lane judges
#     `$NAME` or `${NAME}`: refused bare or with only nameless segments after
#     it (`$env:TEMP`, `$env:TEMP\`, `$env:TEMP\*`), allowed with a named subpath
#     (`$env:TEMP\build`).
#     Still uncovered: Start-Process/iex wrapping a delete, a command word
#     supplied only by a variable (`& $cmd -Recurse C:\`), nested PowerShell
#     (`pwsh -Command '...'`), a `$( )` inside a double-quoted string, a
#     command that is not the first word of its statement (`$r = Remove-Item
#     -Recurse C:\`), a comma list of targets (`Remove-Item -Recurse ./x,C:\`),
#     and a here-string, which is read as ordinary quoting: its body is not
#     judged, and a quote character inside it ends the span early, so the code
#     after it is not judged either.
#   * Other delete verbs: `find -delete`, `rsync --delete`, `xargs rm`,
#     `shred`, and a delete performed from inside an interpreter.
#   * Expansion-built targets AND an expansion-built command word. Detection
#     never evaluates a shell expansion. A bare variable operand is refused
#     (above), but `rm -rf "$X/build"` is left alone, and so are an unquoted
#     `$X/{a,b}` (its alternatives `$X/a` and `$X/b` are each left alone the
#     same way; the quoted `"$X"/{a,b}` is refused as a partly quoted brace)
#     and `$(printf 'r%s' 'm') -rf /`, whose substitution body is parsed (its
#     command word is `printf`) but whose RESULT is not. The root arm matches
#     `$HOME` and `${HOME}` as the literal text they are written as; only the
#     outside-tree arm expands them, from the hook's own HOME.
#   * A TYPED operand whose real file name holds a literal `$`
#     (`rm -rf 'a$b/'`) is read as an expansion and left alone by the
#     outside-tree arm, because the tokenizer's quoting provenance cannot
#     separate it from `"$X"`; only a name that a glob MATCHED is judged
#     literally.
#   * `~name` is refused by the outside-tree arm and not matched by the root
#     arm, which matches bare `~` only. `~`, `$HOME` and `${HOME}` expand from
#     the hook's own HOME, not from an inline `HOME=` assignment.
#   * Directory changes the outside-tree arm cannot follow. A literal `cd`,
#     `pushd`, `env -C` or `sudo -D` adds a directory the delete may run from,
#     and a cd whose target globs is followed to its one match; `cd "$d"`,
#     `cd -`, `popd`, `pushd +N` and a login shell (`su -`, `su -l`,
#     `runuser -l`, `sudo -i`) are not followed, and a relative operand after
#     one is left alone. A cd the guard can place but not follow, a relative
#     `cd` once CDPATH is set (inherited, assigned, exported or as a prefix)
#     or a glob target with no match or several, makes a relative operand
#     after it refused instead. `builtin cd` is not seen at all, because
#     `builtin` is not in the launcher table. A literal directory is collapsed
#     lexically, so `cd link/..` is read as `cd .`.
#   * Differences from the user-level destructive-removal engine, on purpose:
#     the git toplevel itself, `.git`, another worktree's root and another
#     session's `<temp>/claude` directory are allowed here when they sit
#     inside an allowed root, and an unresolvable expansion is left alone
#     rather than refused. Like the engine, every target is judged against the
#     payload cwd's tree, so an absolute path into another worktree is refused.
#   * A glob is expanded against the filesystem as it is when the hook runs;
#     a directory the command creates before the delete is not seen.
#   * Where `realpath -m` is absent (BSD, macOS), a target's parent is
#     collapsed lexically before its nearest existing ancestor is resolved, so
#     `link/..` is read as the directory holding `link`.
#   * A child shell this guard does not recognize as one. `bash -c`, `sh -c`,
#     their siblings, `su`'s `-c` / `--command` / `--session-command` operand,
#     and GNU `env`'s `-S` / `--split-string` operand ARE unwrapped and
#     re-parsed; an interpreter that is not a shell (`python -c`, `perl -e`)
#     is not.
#   * A LAUNCHER that is not in the launcher table in rdt_check_segment. The
#     table is an allow-list of names, so an unlisted launcher ends the walk
#     and its own name is read as the command word. runuser is read by its own
#     helper, because its getopt permutes: its -c operands are commands (su's
#     grammar) and, with -u, its non-option words are the command. `builtin`,
#     `doas`'s short clusters and `systemd-run`'s working directory are not
#     modeled: a service unit runs from `/` (or the user's home) unless
#     `--scope`, `-d` or `--working-directory` says otherwise, and a relative
#     operand under it is judged from the payload cwd.
#   * An operand-taking option of a listed launcher that its table does not
#     carry ends the walk at that option's operand, which is then read as the
#     command word: uutils `env -f FILE` / `--file FILE` (uutils 0.10.0), so
#     `env -f x rm -rf /` is not refused.
#   * sudo's `-R` / `--chroot`, a short cluster ending in an operand-taking
#     letter (`sudo -Eu bob …`), and an abbreviated long option (`sudo --us bob
#     …`) are judged on two readings, blocking if either does: as a flag, so
#     the word after it stays the command word (`sudo -R rm -rf /`), and as
#     taking that word, so the one after is the command (`sudo -R /mnt rm -rf
#     /`) (#4685).
#   * A command word split across quoting so the RAW text never spells it.
#     `\rm` and `RM` are caught, because the cheap substring prefilter below
#     folds case and the raw text still reads `rm`; `r\m`, `r''m` and `"r"m`
#     are not, because the prefilter exits allow before the tokenizer rejoins
#     them. That is the price of not tokenizing every Bash call, and it is the
#     right trade here: this guard's threat model is an agent making the
#     mistake #92593 records, not one deliberately obfuscating a command word.
#
# BLOCKING: exits 2 on a recursive delete of a root, of an empty or
# bare-variable operand, or of a target outside the allowed roots.

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

# Two fields, one extraction, primed by the dispatcher. Never
# `.tool_input.content` or any write payload: this guard reads a command and
# where it runs, nothing else. `.cwd` is read after the `rm` prefilter, and
# `.scratchpad_dir` only when a target needs judging, each in its own call so
# a NUL byte in either is judged apart from the command's.
jq_rc=0
hook::jq_fields "$INPUT" '.tool_input.command' '.tool_name' || jq_rc=$?
if ((jq_rc == 2)); then
  guard::refuse_unparsable
  exit 2
fi
((jq_rc != 0)) && exit 0

# A NUL byte in the command or the tool name is fail-CLOSED, for every call:
# what a guard can read is then not dependably what would run, and a NUL in
# the command could hide an `rm` from the prefilter below.
if ((HOOK_JQ_FIELDS_NUL)); then
  guard::refuse_nul
  exit 2
fi

COMMAND="${HOOK_JQ_FIELDS[0]}"
TOOL_NAME="${HOOK_JQ_FIELDS[1]:-Bash}"
PAYLOAD_CWD=""
RDT_CWD_NUL=0

# Bash and PowerShell only. Exiting on every other tool keeps this guard off
# the classifier's load path. The PowerShell lane uses a dedicated tokenizer
# below and does not call the shared classifier.
[[ "$TOOL_NAME" == "Bash" || "$TOOL_NAME" == "PowerShell" ]] || exit 0

# hook::jq_fields drops every CR from a field, but PowerShell ends a statement
# at a bare CR as well as at LF, so `Get-Location<CR>Remove-Item ...` would
# read as one glued word. On the PowerShell tool the command is read again
# from the payload with a JSON CR escape (`\r`, `\u000d`) spelled as an LF and
# a CRLF pair as one LF, which is what the read above already made of it. The
# `\\` pairs are set aside first so an escaped backslash before an `r` (a
# Windows path such as `C:\\repos`) is not taken for a CR escape.
if [[ "$TOOL_NAME" == "PowerShell" && ("$INPUT" == *'\r'* || "$INPUT" == *'\u000'[dD]*) ]]; then
  rdt_bs=$'\\'
  rdt_cr="${rdt_bs}r" rdt_lf="${rdt_bs}n"
  rdt_in="${INPUT//"$rdt_bs$rdt_bs"/$'\001'}"
  rdt_in="${rdt_in//"${rdt_bs}u000d"/"$rdt_cr"}"
  rdt_in="${rdt_in//"${rdt_bs}u000D"/"$rdt_cr"}"
  rdt_in="${rdt_in//"${rdt_bs}u000a"/"$rdt_lf"}"
  rdt_in="${rdt_in//"${rdt_bs}u000A"/"$rdt_lf"}"
  rdt_in="${rdt_in//"$rdt_cr$rdt_lf"/"$rdt_lf"}"
  rdt_in="${rdt_in//"$rdt_cr"/"$rdt_lf"}"
  rdt_in="${rdt_in//$'\001'/"$rdt_bs$rdt_bs"}"
  if [[ "$rdt_in" != "$INPUT" ]] && hook::jq_fields "$rdt_in" '.tool_input.command'; then
    COMMAND="${HOOK_JQ_FIELDS[0]}"
  fi
fi

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

# The depth cap bounds how deep a reading goes, not how many there are. A
# launcher read two ways (runuser's -s program and its -u argv) doubles the
# segments at every level, so 20 levels are a million walks, and a hook the
# harness cancels on its timeout is cancelled WITHOUT a block. Every NESTED
# segment (one a launcher, child shell, eval or resolved walk re-enters) is
# counted for the whole command, and past the budget the guard REFUSES.
# Top-level segments are left out: the command's own length bounds them, and a
# 16 KB command of substitutions can hold several thousand. 1024 nested
# launcher segments cost about 2 s on Git Bash, well inside the hook timeout,
# and a realistic command nests a handful.
MAX_SEGMENTS=1024
rdt_segments=0

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
      'Fix: flatten the command substitutions, or assign the inner results to variables in separate commands.' >&2
    ;;
  eval-too-long)
    printf '%s\n' \
      'BLOCKED: eval and substitution text exceeds MAX_COMMAND_LEN in total.' \
      'Fix: drop the nested evals, or run the inner command on its own.' >&2
    ;;
  too-many-readings)
    printf '%s\n' \
      'BLOCKED: too many launcher readings to judge every one; flatten the command.' \
      'Fix: drop the repeated launchers, or run the inner command on its own.' >&2
    ;;
  nesting-too-deep-launcher)
    printf '%s\n' \
      "BLOCKED: launcher or eval nesting deeper than $MAX_SEGMENT_DEPTH; flatten the command." \
      'Fix: drop the repeated launchers, or run the inner command on its own.' >&2
    ;;
  too-many-abbreviations)
    printf '%s\n' \
      'BLOCKED: too many command segments with abbreviated launcher options to judge every reading; spell the options in full.' \
      'Fix: spell the launcher options in full (flock --wait 5), or split the command into shorter ones.' >&2
    ;;
  bodies-too-long)
    printf '%s\n' \
      'BLOCKED: substitution bodies exceed MAX_COMMAND_LEN in total.' \
      'Fix: flatten the command substitutions, or assign the inner results to variables in separate commands.' >&2
    ;;
  empty-operand)
    printf '%s\n' \
      'BLOCKED: this recursive delete has an empty operand ("").' \
      'Fix: name the directory to remove explicitly, or drop the empty word.' >&2
    ;;
  pipeline-target)
    printf '%s\n' \
      'BLOCKED: this recursive delete takes its target from the pipeline or a grouping, which this guard cannot name.' \
      'Fix: name the directory to remove as a -Path or -LiteralPath operand, written out literally.' >&2
    ;;
  bare-variable)
    # Single-quoted on purpose: the text shows a literal ${NAME:?}.
    # shellcheck disable=SC2016
    printf '%s\n' \
      "BLOCKED: this recursive delete targets a bare variable ('$target'), whose value is not known until it runs." \
      'Fix: write the path out literally, or use "${NAME:?}/sub" so an unset or empty value aborts the command before rm runs.' >&2
    ;;
  outside-tree)
    printf '%s\n' \
      "BLOCKED: recursive delete of $target, outside the working tree, the temp directories, the session scratchpad and the roots in block_root_delete_target_allowed_roots." \
      'Fix: delete only strictly under one of those (put scratch work in the session scratchpad), and do not retry the delete with another tool (find -delete, rmtree, git clean).' \
      'Otherwise the user runs it, or lists its root in block_root_delete_target_allowed_roots (only the user can).' >&2
    ;;
  too-many-origins)
    printf '%s\n' \
      "BLOCKED: too many directory changes to judge every place this delete may run from (more than $MAX_ORIGINS)." \
      'Fix: cd once to an absolute directory, or run the delete as its own command.' >&2
    ;;
  too-many-targets)
    printf '%s\n' \
      "BLOCKED: too many recursive delete targets to judge (more than $MAX_TARGETS directory-and-target pairs)." \
      'Fix: delete a parent directory, or split the delete into shorter commands.' >&2
    ;;
  too-many-glob-entries)
    printf '%s\n' \
      "BLOCKED: a glob in this recursive delete reads more than $MAX_GLOB directory entries, files included." \
      'Fix: narrow the glob to the names you mean, or delete the parent directory whole.' >&2
    ;;
  operand-too-long)
    printf '%s\n' \
      "BLOCKED: this recursive delete names $target." \
      'Fix: check how the command was built; name the directory to remove directly.' >&2
    ;;
  too-slow)
    printf '%s\n' \
      "BLOCKED: judging where this recursive delete lands ran out of time (a bound of $RDT_DEADLINE seconds for the judgment, $RDT_DEADLINE_ABS for the whole hook)." \
      'Fix: delete fewer targets per command, or cd once to an absolute directory first.' >&2
    ;;
  unplaceable)
    printf '%s\n' \
      "BLOCKED: recursive delete of $target, which cannot be judged (another user's home, a newline, \`..\` after a glob, or a cd CDPATH may redirect)." \
      'Fix: write the target as an absolute or working-tree-relative path.' >&2
    ;;
  brace)
    printf '%s\n' \
      "BLOCKED: this recursive delete has a brace expansion ($target) that cannot be judged alternative by alternative." \
      'Fix: write each target out as its own operand.' >&2
    ;;
  nul-field)
    printf '%s\n' \
      "BLOCKED: this recursive delete cannot be judged, because the hook payload's $target carries a NUL byte." \
      'Fix: reissue the tool call; if it repeats, report the malformed payload.' >&2
    ;;
  judge-error)
    printf '%s\n' \
      'BLOCKED: judging where this recursive delete lands failed unexpectedly.' \
      'Fix: simplify the command, or run the delete on its own.' >&2
    ;;
  *)
    # Single-quoted on purpose: the Fix line must show a literal $HOME to the
    # agent rather than expanding it in the hook process.
    # shellcheck disable=SC2016
    printf '%s\n' \
      "BLOCKED: recursive delete of a filesystem root (normalizes to '$target')." \
      'Fix: name the directory to remove, relative to the working tree. $HOME and ~ are matched as written, not expanded.' >&2
    ;;
  esac
  rdt_emit_tel "blocked" "$form"
  exit 2
}

if ((${#COMMAND} > MAX_COMMAND_LEN)); then
  rdt_block "too-long"
fi

# Cheap prefilter ahead of the character walk. A command whose TEXT cannot
# carry a verb this matcher recognizes must not pay for the parse. Folded to
# lower case: on Windows both the filesystem and the PATH lookup are
# case-insensitive, so `RM -rf /` and `REMOVE-ITEM -Recurse C:\` run.
# A case-SENSITIVE prefilter here would have exited allow first, a bypass of
# the whole guard rather than a missed spelling.
#
# Bash: a substring `rm` is all this can be (`npm run format` still reaches
# the tokenizer and is allowed on its command word). PowerShell: Remove-Item,
# rmdir, erase, cmd, rd, del, rm, and `ri` as a command word (not the `ri`
# inside Write/string). Over-inclusive on purpose; the tokenizer decides.
if [[ "$TOOL_NAME" == "PowerShell" ]]; then
  rdt_ps_pre="${COMMAND,,}"
  rdt_ps_hit=0
  case "$rdt_ps_pre" in
  *rm* | *remove-item* | *erase* | *cmd* | *rd* | *del*) rdt_ps_hit=1 ;;
  *) ;;
  esac
  if ((rdt_ps_hit == 0)) && [[ "$rdt_ps_pre" =~ (^|[^[:alnum:]_])ri([^[:alnum:]_]|$) ]]; then
    rdt_ps_hit=1
  fi
  ((rdt_ps_hit)) || exit 0
else
  case "${COMMAND,,}" in
  *rm*) ;;
  *) exit 0 ;;
  esac
fi

# The payload cwd, for the outside-tree arm. A NUL byte in it does not refuse
# the call here: only a recursive delete this arm must judge is refused
# (rdt_check_operand), and any other command is unaffected.
if hook::jq_fields "$INPUT" '.cwd'; then
  if ((HOOK_JQ_FIELDS_NUL)); then
    RDT_CWD_NUL=1
  else
    PAYLOAD_CWD="${HOOK_JQ_FIELDS[0]:-}"
  fi
fi

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
  #
  # A slash inside a `${...}` is part of the expansion, not a path separator,
  # so `${X:-/}` and `${X:-${Y:-/}}` are never cut open.
  rdt_strip_nameless_to __rdt_s "$__rdt_s" 0
  printf -v "$__rdt_dest" '%s' "$__rdt_s"
}

# rdt_strip_nameless_to <var> <text> <min cut>: <text> without its trailing
# path segments that carry no name (no letter, digit or underscore), cut only
# at a `/` outside every `${...}` whose index is at least <min cut>. With a min
# cut of 0 a text cut down to nothing becomes `/`. A `${...}` ends where bash
# ends it: only `${` nests, and the first `}` closes the innermost one, so a
# bare `{` inside counts for nothing.
#
# ONE pass over the text finds every outer slash, and the strip walks them
# from the end, so the cost is linear in the operand. Rescanning the text for
# each stripped segment was quadratic, and a 2 KB operand of `/*` segments
# behind a `${X}` took over 30 s: past the hook timeout the harness cancels
# the hook WITHOUT a block, which would fail open for the rest of the command.
# shellcheck disable=SC2016,SC2329  # literal `${` pattern; invoked from rdt_normalize_to and rdt_strip_tail_to
rdt_strip_nameless_to() {
  local __sn_s="$2" __sn_min="$3" __sn_i __sn_d=0 __sn_k __sn_cut __sn_end
  local -a __sn_cuts=()
  # No `%/*` shortcut: bash matches a suffix pattern by trying every start
  # position, so a loop of them over a long operand of short segments is
  # quadratic per strip and took over a minute at 4 KB.
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

# rdt_is_root <normalized>: true when the operand names a filesystem root.
# An operand that normalized to the EMPTY string is NOT a root: `rm -rf ""` is
# refused by the empty-operand arm ahead of this one, with its own message,
# while `rm -rf "\\"`, whose single backslash normalizes to `/`, is a root.
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
# options, so `runuser -u bob rm -rf /` still reads `-rf` as rm's flag.
# Ahead of every non-option it is dropped, so it never becomes the command
# word (`runuser -u root --foo rm -rf /`).
# With RDT_RU_POSIX=1 the words are read the way getopt reads them when
# POSIXLY_CORRECT is set, which no payload shows because it can be inherited:
# the first non-option ends the options and every word from it on is kept, so
# a later `-s env` is an argument, not the shell. Each caller judges both
# readings (#4685).
# su shares this option parser, so its arm reads su's argv here too, to find
# the words that follow a -s program that is not a shell.
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

# rdt_ru_key_to <var>: one string that differs whenever two rdt_runuser_argv
# results do, so a second reading identical to the first is not walked again.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_ru_key_to() {
  local -n _rk_out="$1"
  printf -v _rk_out '%q ' "$RDT_RU_U" "$RDT_RU_SHELL" "${#RDT_RU_CMDS[@]}" ${RDT_RU_CMDS[@]+"${RDT_RU_CMDS[@]}"} \
    "${#RDT_RU_ARGV[@]}" ${RDT_RU_ARGV[@]+"${RDT_RU_ARGV[@]}"} ${RDT_RU_QUOTED[@]+"${RDT_RU_QUOTED[@]}"}
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
# from each launcher's getopt string; doas is a declared gap, and taskset,
# chroot and setpriv have no operand-taking short option. sudo's `-R`, `-a`
# and `-c` alone are judged here too, because the plain walk steps over them
# (see the sudo row of the launcher table).
# env's `-S` is absent: its operand is a command, re-parsed by env's own arm.
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

# rdt_long_takes_arg <launcher> <name>: true when `--<name>`, written without
# `=`, takes the next word as its operand. getopt_long accepts any unambiguous
# prefix, so `flock --wa 5` is `flock --wait 5`. An ambiguous prefix makes the
# launcher refuse to run, and it is counted as taking one when any candidate
# does (`nsenter --t 1` could mean --target), because the walk judges this
# reading IN ADDITION to the plain one that steps over the word alone, and
# blocks if either does, so resolving a prefix can only add refusals.
# An exact flag name never takes one.
# Each list is the launcher's operand-taking long names, then its flag names.
# The `ops` lists hold every operand-taking long name. The ones missing from a
# launcher's `optarg` (sudo's `chroot`, `auth-type` and `login-class`, env's
# `argv0`, `env0-from` and `quoting-style`) are stepped over by the plain walk
# and taken only here (see the sudo row of the launcher table). doas is
# absent: it has no long options.
# env's names, fetched 2026-09-29. GNU coreutils src/env.c (last change
# f799b2f) lists `argv0`, `env0-from` and `quoting-style` as options taking an
# argument, beside `unset` and `chdir`; its NEWS puts `--argv0` in 9.5,
# `--env0-from` in 9.12 and `--quoting-style` after 9.12; the env manual at
# gnu.org/software/coreutils/manual/html_node/env-invocation.html lists
# `--argv0`, `--unset`, `--env0-from` and `--chdir`. uutils/coreutils
# src/uu/env/src/env.rs (last change b2480b2) implements `argv0`, `unset`,
# `chdir` and `split-string`, not `env0-from` or `quoting-style`. uutils 0.10.0's
# own `env --help` lists those four and also `-f, --file <PATH>`, which neither
# table here carries (see the operand-taking-option gap in the header). So
# `env0-from` and `quoting-style` exist only in newer GNU env, and are kept: a
# name an env lacks only adds a refusal, and removing one would loosen the
# guard. The sudo names above carry no source here. Recheck when a GNU
# coreutils or uutils release adds an `env` option that takes an argument.
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

# --- Empty, bare-variable and outside-tree targets ---------------------------
#
# rdt_bare_var <normalized operand>: true when the operand is made of
# expansions and nothing else, matched on the NORMALIZED form (lower case,
# trailing nameless segments dropped, so `"$X/"`, `"$X/*"` and `"$X"/*` all
# reduce to `$x`). The units are `$NAME`, a positional or special parameter,
# and any `${...}`. Only `${NAME:?...}` aborts the command on an empty value as
# well as an unset one, so an operand whose every unit is that form passes;
# `${NAME?}`, `${NAME%/}`, `${!NAME}` and a substring do not, and neither does
# `$X$Y`. A `${...}` unit ends where bash ends it: only `${` nests and the first
# `}` closes the innermost one, so `${X:-${Y:-/}}` is one unit, judged by its
# outermost operator. A `${` that never closes is refused: bash rejects it, and
# nothing here can say what it would expand to.
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
      # What follows the expansions names nothing when it holds no letter,
      # digit or underscore outside a bracket expression: a glob (`*`, `?*`,
      # `[a-z]*`) or dots. `"${X:-/}"*` with X unset is `/*`, so such a
      # remainder leaves the operand bare. Anything that names something
      # (`$X-build`, `${X}_old`) is a path that goes on past the expansion.
      local rem="$s" re_br='\[[^]]*\]'
      while [[ "$rem" =~ $re_br ]]; do rem="${rem/"${BASH_REMATCH[0]}"/}"; done
      [[ "$rem" == *[[:alnum:]_]* ]] && return 1
      break
    fi
    s="${s:${#unit}}"
  done
  ((safe == 0))
}

# The outside-tree arm. RDT_ARM is 1 when the payload carries an absolute cwd;
# without one the arm is skipped. Operands are recorded while the command is
# parsed and judged once, after both passes, by rdt_judge_pending.
#   RDT_ORIGINS    every directory the command may run a delete from: the
#                  payload cwd, then each literal cd / pushd / env -C / sudo -D
#                  target, lexically collapsed. Global, never saved or restored
#                  by the recursion, because a later segment runs where an
#                  earlier one left the shell.
#   rdt_cd_unknown 1 once a directory change this guard cannot follow is seen;
#                  a relative operand recorded after it is left alone.
#   rdt_in_subst   1 while the substitution scan runs. That scan precedes the
#                  main parse, so an operand it records is judged against every
#                  origin the whole command visits.
#   rdt_cdpath     1 once CDPATH is set (inherited, assigned or exported).
#   rdt_cd_refuse  1 once a cd is seen that the guard can read but not follow
#                  to one directory: a relative cd while CDPATH is set, which
#                  may land in any CDPATH entry the command itself chose, or a
#                  glob target with no match or several. A relative operand
#                  recorded after it is REFUSED rather than left alone.
# MAX_ORIGINS counts the starting directory among its 32. MAX_TARGETS bounds
# directory-and-target pairs, MAX_GLOB the entries one glob reads across all
# its levels. RDT_DEADLINE bounds the wall time (bash's SECONDS) of this arm's
# own work, from the moment it first has work to do (an operand to record, a
# brace or glob to expand) through the parse that follows and the judgment,
# and RDT_DEADLINE_ABS bounds the hook's whole run once that work has begun:
# the harness cancels a hook past its timeout WITHOUT a block, so running long
# would fail open, and the dispatcher shares one 60 s timeout across every
# guard it runs. A command this arm has nothing to do for is never timed, so a
# slow but harmless parse behaves as it did before the arm existed. Past any
# of them the guard refuses. 25 s and 50 s are sized for a busy host: under
# heavy load an everyday `rm -rf ./build` took 4 to 8 s end to end on Windows
# Git Bash, and a 12 s bound refused ordinary deletes; 50 s leaves 10 s of the
# shared 60 s timeout, with this guard last in the dispatcher chain.
MAX_ORIGINS=32
MAX_TARGETS=512
MAX_GLOB=256
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
RDT_WIN=0
case "${OSTYPE:-}" in
msys* | cygwin* | win32) RDT_WIN=1 ;;
*) ;;
esac
RDT_HOME="${HOME:-}"
RDT_HOME="${RDT_HOME//\\//}"

# rdt_deadline: start this arm's clock on the first call, and refuse once its
# work has run past RDT_DEADLINE seconds, or the hook past RDT_DEADLINE_ABS.
rdt_deadline() {
  ((RDT_T0 >= 0)) || RDT_T0=$SECONDS
  ((SECONDS - RDT_T0 < RDT_DEADLINE && SECONDS < RDT_DEADLINE_ABS)) || rdt_block "too-slow"
}

# rdt_remaining_to <var>: whole seconds left before rdt_deadline would refuse,
# at least 1. A batch process (realpath, cygpath) runs under `timeout` with
# this bound, because the deadline is otherwise checked only between steps and
# one slow process could carry the hook past the harness timeout.
rdt_remaining_to() {
  rdt_deadline
  local __rr_a=$((RDT_DEADLINE - (SECONDS - RDT_T0))) __rr_b=$((RDT_DEADLINE_ABS - SECONDS))
  ((__rr_b < __rr_a)) && __rr_a=$__rr_b
  ((__rr_a < 1)) && __rr_a=1
  printf -v "$1" '%s' "$__rr_a"
}

# rdt_is_unc <path>: a `//host/...` path, which is never touched on disk, so
# no lookup can wait on the network.
rdt_is_unc() {
  [[ "$1" == //* && "$1" != ///* ]]
}

# rdt_parent_to <var> <path>: <path> without its last component, kept a root:
# `/` rather than empty, `C:/` rather than `C:`.
rdt_parent_to() {
  local __rpt_p="${2%/*}"
  [[ -z "$__rpt_p" ]] && __rpt_p=/
  [[ "$__rpt_p" =~ ^[A-Za-z]:$ ]] && __rpt_p="$__rpt_p/"
  printf -v "$1" '%s' "$__rpt_p"
}

# rdt_nearest_to <var> <test> <path>: the nearest ancestor of <path> (itself
# included) for which `[[ <test> ]]` holds, `-e` or `-d`; empty when none. The
# walk stops at a root, because an unmapped drive (`Q:/`) never exists and
# stripping it again would give `Q:` back forever.
rdt_nearest_to() {
  local __rn_a="$3"
  while [[ -n "$__rn_a" && "$__rn_a" == */* && "$__rn_a" != / && ! "$__rn_a" =~ ^[A-Za-z]:/$ ]]; do
    rdt_deadline
    if [[ "$2" == -d ]]; then [[ -d "$__rn_a" ]] && break; else [[ -e "$__rn_a" ]] && break; fi
    rdt_parent_to __rn_a "$__rn_a"
  done
  if [[ "$2" == -d ]]; then [[ -d "$__rn_a" ]] || __rn_a=""; fi
  printf -v "$1" '%s' "$__rn_a"
}

# rdt_lines_to <array var> <want count> <command...>: run a batch command,
# strip CRs, and split its output into lines. Returns 1 when it fails or the
# line count differs from <want count>, so the caller keeps its own answer.
# Where `timeout` exists the command is bounded by the time left, and running
# out refuses: realpath took 90 s over one path of 2,000 missing components.
rdt_lines_to() {
  local __rb_dest="$1" __rb_want="$2" __rb_out __rb_left __rb_rc=0
  shift 2
  if command -v timeout >/dev/null 2>&1; then
    rdt_remaining_to __rb_left
    __rb_out=$(timeout "$__rb_left" "$@" 2>/dev/null) || __rb_rc=$?
    ((__rb_rc == 124)) && rdt_block "too-slow"
    ((__rb_rc == 0)) || return 1
  else
    # No `timeout` (stock macOS): the call cannot be cut short, so the clock
    # is checked on both sides of it and a slow call refuses once it returns.
    # The operand length and depth caps are what keep one call short here.
    rdt_deadline
    __rb_out=$("$@" 2>/dev/null) || __rb_rc=$?
    rdt_deadline
    ((__rb_rc == 0)) || return 1
  fi
  __rb_out="${__rb_out//$'\r'/}"
  mapfile -t "$__rb_dest" <<<"$__rb_out"
  local -n __rb_ref="$__rb_dest"
  ((${#__rb_ref[@]} == __rb_want))
}

# rdt_glob_on / rdt_glob_off: nullglob on for a glob read, and the caller's
# setting restored after it.
rdt_glob_on() {
  RDT_NG_WAS=0
  shopt -q nullglob && RDT_NG_WAS=1
  shopt -s nullglob
}
rdt_glob_off() {
  ((RDT_NG_WAS)) || shopt -u nullglob
}

# rdt_note_cdpath <word>: a `CDPATH=` assignment, as a prefix, a segment of
# its own or an argument of export and its kin, sets rdt_cdpath.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_note_cdpath() {
  [[ "$1" == CDPATH=* ]] && rdt_cdpath=1
  return 0
}

# rdt_is_abs <path>: absolute after backslashes became slashes: `/…`, `//…`,
# or a drive followed by a slash. A drive-relative `C:foo` is not.
rdt_is_abs() {
  [[ "$1" == /* || "$1" =~ ^[A-Za-z]:/ ]]
}

# rdt_lex_to <var> <absolute path>: `.` and `..` collapsed, slashes squeezed.
# A drive prefix and a UNC `//` lead are kept, and `..` stops at the top.
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

# rdt_join_to <var> <dir> <rest>: one slash between them, whatever <dir> ends
# with.
rdt_join_to() {
  if [[ -z "$3" ]]; then
    printf -v "$1" '%s' "$2"
  elif [[ "$2" == */ ]]; then
    printf -v "$1" '%s' "$2${3#/}"
  else
    printf -v "$1" '%s' "$2/${3#/}"
  fi
}

# rdt_canon_to <var> <path>: the spelling two paths are COMPARED in. Slashes
# squeezed, no trailing slash, a drive folded by hook::normalize_path_to, and
# on Windows the whole path lower-cased, since that filesystem folds case.
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

# rdt_root_like <canonical>: a filesystem root, which is never accepted as an
# allowed root: a tree, temp root or scratchpad there would allow everything.
rdt_root_like() {
  [[ "$1" == / || "$1" =~ ^[A-Za-z]:/?$ || "$1" =~ ^/[A-Za-z]$ ]]
}

# rdt_place_to <var> <operand> <provenance>: the operand as a path this arm
# can judge. Returns 0 when placed, 1 to leave it alone (an expansion other
# than a leading HOME, a drive-relative path), and 2 when it must be refused
# because it cannot be judged faithfully (`~name`, a newline). A leading `~`,
# `$HOME` or `${HOME}` expands from the hook's HOME and `~+` is the working
# directory; a fully quoted `~` is a literal name. A `\\?\` or `\\.\` device
# prefix on a drive path is read as the drive path. Sets:
#   RDT_PL_ABS   1 for an absolute path
#   RDT_PL_MODE  leaf: the parent is resolved and the name is appended as is,
#                because rm removes a symlink named last rather than following
#                it. whole: the path is resolved entirely, for a trailing slash
#                (rm then follows a symlink), a trailing `.` or `..`, and the
#                directory in front of a glob in the last component.
#                deep: a glob sits before the last component; the judgment
#                expands its directory part with real globbing and judges each
#                match, or, with no match, the literal directory in front of
#                the glob, below which the targets lie at least two levels.
#   RDT_PL_GLOB  1 when a glob was present
#   RDT_PL_FULL  the whole path text, after HOME expansion, with no trailing
#                slash; RDT_PL_SLASH 1 when one was stripped
#   RDT_PL_ENUM  the last-component glob of an operand ending in `/`, whose
#                matches are read so that a symlink among them is judged by
#                where it points
# Braces are expanded before this (rdt_brace_expand), so a `{` here is a
# literal character. A `..` after the first glob component returns 2.
# Provenance 3 is LITERAL mode, for a path the filesystem produced (a glob
# match) or one bash passes through unchanged (an unmatched glob): no `~`,
# HOME, `$` or glob is read in it.
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
  if ((__rp_q < 2)); then
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
  if ((__rp_q != 3)); then
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
    # A `..` after the first glob component climbs out of whatever the glob
    # matched, so the directory in front of the glob says nothing about it.
    local __rp_c __rp_seen=0 __rp_ifs="$IFS"
    local -a __rp_cs=()
    IFS=/ read -r -a __rp_cs <<<"$__rp_t"
    IFS="$__rp_ifs"
    for __rp_c in ${__rp_cs[@]+"${__rp_cs[@]}"}; do
      [[ "$__rp_c" == *[*?[]* ]] && __rp_seen=1
      ((__rp_seen)) && [[ "$__rp_c" == .. ]] && return 2
    done
    # Judged by the literal directory in front of the first glob.
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

# rdt_add_origin <directory operand> <provenance>: a directory a later delete
# may run from. A relative one is joined to every origin known so far. A
# fully quoted target is literal. An unquoted glob target is expanded with the
# bounded per-component glob from each origin, and followed when it matches
# exactly one directory there; with no match or several, and for a target the
# guard must refuse (`~name`, a `..` after a glob), a relative operand after
# it is refused. An expansion is not followed and leaves it alone.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_add_origin() {
  local t o c k have rc=0 q="$2"
  local -a add=() bases=()
  if [[ "$1" == *'{'* ]] && ((q != 2)); then
    rdt_cd_unknown=1
    return 0
  fi
  # A quoted target is literal, unless it carries a `$` or a backtick: the
  # tokenizer's provenance cannot tell "$d" from '$d', so that one is still
  # read as an expansion and left alone.
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

# rdt_note_cd <cd|pushd|popd> <offset> <words after it>: follow a directory
# change. Its options (`-L`, `-P`, `-e`, `-@`, pushd's `-n`) are stepped over;
# a bare `cd` goes home; `cd -`, `popd`, `pushd` alone and `pushd +N` are
# not followed.
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
  # With CDPATH set, a relative target that does not start with `.` or `..`
  # may land in any CDPATH entry, so it is not followed, and a relative
  # operand after it is refused.
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

# rdt_note_login <words after su or runuser>: a login shell starts in the
# target user's home, so a relative operand inside it is not followed.
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

# rdt_note_launcher_dir <launcher> <word> <has next> <next> <q word> <q next>:
# env -C / --chdir and sudo -D / --chdir run the command from a directory; an
# abbreviated env --ch is read the same way. sudo -i / --login runs it from the
# target user's home.
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

# RDT_RES maps a path to its resolved spelling for the whole judgment.
declare -A RDT_RES=()

# rdt_resolve_all <path>...: resolve every path physically in one process
# where the host allows, into RDT_RES. One `realpath -m` for all of them,
# which follows a symlink or `..` whether or not the tail exists. Without it
# (BSD, macOS), each is collapsed lexically and its nearest existing ancestor
# resolved through hook::physical_path_to. A UNC path, and a drive path on a
# host with no drives, is never touched on disk: it is collapsed lexically, so
# no lookup can wait on the network.
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
    todo+=("$p")
  done
  ((${#todo[@]})) || return 0
  local ok=0
  if [[ "${todo[*]}" != *$'\n'* ]] && rdt_lines_to lines "${#todo[@]}" realpath -m -- "${todo[@]}"; then
    ok=1
  fi
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

# RDT_WMAP maps a resolved path to its one Windows long form.
declare -A RDT_WMAP=()

# rdt_winmap_all <path>...: on Windows, one `cygpath -l -m` over each path's
# nearest existing ancestor maps the /tmp mount, the /c/... and C:/...
# spellings and 8.3 short names onto one long form, into RDT_WMAP. The
# nearest EXISTING ancestor, because cygpath leaves a path whose tail is
# missing unexpanded. A path it cannot map keeps its own spelling. Elsewhere
# every path maps to itself.
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
  # silent-skip-ok: cygpath is part of the Git Bash, MSYS2 and Cygwin runtime
  # this branch runs under, so its absence is not a real install. Without it
  # every path keeps the spelling realpath gave it, which refuses more (a short
  # or drive spelling no longer matches the tree); the one allow it can add is
  # the scratchpad itself named through the /tmp mount, which then reads as a
  # path strictly under /tmp.
  command -v cygpath >/dev/null 2>&1 || return 0
  for ((i = 0; i < ${#todo[@]}; i++)); do
    rdt_deadline
    rdt_split_existing a rem "${todo[i]}"
    # A leaf target that is itself a symlink is mapped by its parent, because
    # cygpath follows the link and rm removes the link, not what it points
    # at. Every other link on the path was already resolved by realpath.
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

# rdt_split_existing <ancestor var> <rest var> <path>: the nearest existing
# ancestor of <path>, and the tail below it.
rdt_split_existing() {
  local __rs_a __rs_r
  rdt_nearest_to __rs_a -e "$3"
  __rs_r="${3:${#__rs_a}}"
  [[ -n "$__rs_r" && "$__rs_r" != /* ]] && __rs_r="/$__rs_r"
  printf -v "$1" '%s' "$__rs_a"
  printf -v "$2" '%s' "$__rs_r"
}

# rdt_tree_to <var> <directory>: the git toplevel of a directory, or empty.
# Asked once, for the payload cwd, from its nearest existing directory, with
# the variables that redirect discovery unset. A git that fails, or is absent,
# gives no tree, so the failure lands on the refusal side.
declare -A RDT_TREE=()
rdt_tree_to() {
  local o="$2" d out rc=0
  if [[ -n "${RDT_TREE[$o]+x}" ]]; then
    printf -v "$1" '%s' "${RDT_TREE[$o]}"
    return 0
  fi
  d=""
  rdt_is_unc "$o" || rdt_nearest_to d -d "$o"
  out=""
  if [[ -n "$d" ]]; then
    # Bounded like the batch resolvers: a git that stalls (a slow network
    # mount, a locked repository) would otherwise carry the hook past the
    # harness timeout, which fails open. Running out of time refuses.
    local left="" tcmd=()
    if command -v timeout >/dev/null 2>&1; then
      rdt_remaining_to left
      tcmd=(timeout "$left")
    else
      rdt_deadline
    fi
    out=$(
      unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_CEILING_DIRECTORIES GIT_DISCOVERY_ACROSS_FILESYSTEM
      ${tcmd[@]+"${tcmd[@]}"} git -C "$d" rev-parse --show-toplevel 2>/dev/null
    ) || rc=$?
    ((rc == 124 && ${#tcmd[@]} > 0)) && rdt_block "too-slow"
    ((${#tcmd[@]} > 0)) || rdt_deadline
    out="${out//$'\r'/}"
    ((rc == 0)) || out=""
  fi
  RDT_TREE[$o]="$out"
  printf -v "$1" '%s' "$out"
}

# rdt_allowed <canonical target> <deep> <link>: the order the destructive-removal
# engine uses. The scratchpad itself, then a temp root itself, are refused
# first; then strictly under the scratchpad or a temp root, or under (or equal
# to) the payload cwd's tree, is allowed. With <deep> 1 the target is the
# literal directory in front of a glob before the last component, so what is
# deleted lies at least two levels below it, and equal to the scratchpad or a
# temp root is enough. Last, strictly under a user-listed allowed root (the
# same rule as a temp root), or a direct child of a name-prefix entry's
# directory whose name extends the prefix by at least one character and that
# is not itself a symlink (<link> 1), but never a root, HOME, or a directory
# holding HOME, whatever is listed.
rdt_allowed() {
  local t="$1" deep="$2" link="${3:-0}" c i rest
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
  ((${#RDT_ALLOWC[@]} + ${#RDT_PDIRC[@]})) || return 1
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
    # Win32 trims a trailing dot or space, so `.tmp-.` names `.tmp-` and
    # `.tmp-n.` names `.tmp-n` past the symlink test: such a name is refused.
    [[ "$rest" != */* && "$rest" != *[.\ ] && "$rest" == "${RDT_PNAME[i]}"?* ]] && return 0
  done
  return 1
}

# rdt_enum_links <directory> <pattern>: the matches of `<pattern>/` in
# <directory> that are symlinks, into RDT_LINKS. `rm -rf */` follows a symlink
# to a directory, so each such match is judged by where it points. Reads the
# directory only; nothing is expanded but the glob.
#
# Names first, with no trailing slash, and capped at MAX_GLOB before any entry
# is tested: a pattern ending in `/` makes bash stat every entry, and over a
# temp directory of 50,000 entries that ran past the hook timeout, which the
# harness answers WITHOUT a block. Past the cap the guard refuses.
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

# rdt_glob_dirs <base> <pattern>: the directories `<pattern>` matches, read
# from <base> (empty for an absolute pattern), into RDT_GLOB. Expanded ONE
# component at a time, each match a quoted literal for the next level, and
# every entry read, file or directory, counts toward one running total across
# all the levels: past MAX_GLOB the guard refuses at once instead of listing a
# whole tree, and the deadline is checked before every directory read.
# nullglob is on and dotglob off, as in a default bash; a literal component
# keeps only the directories that exist.
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
        # Names first, with no trailing slash, so the directory is read
        # without a stat per entry; the count is capped before any match is
        # tested for being a directory.
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

# rdt_add_pair <path> <mode> <enum> <operand>: one target for the judgment,
# appended to rdt_judge_pending's arrays (tp tn td te tw, deduplicated through
# tseen), which this reads through bash's dynamic scope.
# shellcheck disable=SC2034  # the arrays belong to the caller
rdt_add_pair() {
  local p="$1" mode="$2" last="" key
  if [[ "$mode" == leaf ]]; then
    last="${p##*/}"
    rdt_parent_to p "$p"
  else
    [[ -z "$p" ]] && p=/
    [[ "$p" =~ ^[A-Za-z]:$ ]] && p="$p/"
  fi
  key="$mode|$p|$last|$3"
  [[ -n "${tseen[$key]+x}" ]] && return 0
  tseen[$key]=1
  tp+=("$p")
  tn+=("$last")
  if [[ "$mode" == deep ]]; then td+=(1); else td+=(0); fi
  te+=("$3")
  tw+=("$4")
  ((${#tp[@]} > MAX_TARGETS)) && rdt_block "too-many-targets"
  return 0
}

# rdt_add_literal <path> <operand>: <path> placed in LITERAL mode (no `~`,
# HOME, `$` or glob read in it) and added as a target. Clobbers RDT_PL_*.
rdt_add_literal() {
  local t rc=0
  rdt_place_to t "$1" 3 || rc=$?
  ((rc == 2)) && rdt_block "unplaceable" "'$2'"
  ((rc == 0)) || return 0
  rdt_add_pair "$t" "$RDT_PL_MODE" "" "$2"
}

# rdt_judge_pending: the outside-tree judgment, once, after both passes.
rdt_judge_pending() {
  local np=${#RDT_P_TEXT[@]}
  ((np)) || return 0
  ((RDT_ORIGIN_OVERFLOW)) && rdt_block "too-many-origins"
  local k m no unk cdp t p sp c rc mode enum full slash abs glob base g t2 word lastc e
  local -a tp=() tn=() td=() te=() tw=() gl=()
  local -A tseen=()
  # Every target from every directory it may run from, each distinct one
  # once. In leaf mode the parent is resolved and the name appended as is;
  # otherwise the whole path is resolved (see rdt_place_to).
  for ((k = 0; k < np; k++)); do
    rdt_deadline
    word="${RDT_P_TEXT[k]}"
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
      ((cdp)) && rdt_block "unplaceable" "'$word' (after a cd that CDPATH may send anywhere)"
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
      # A glob that matches nothing reaches rm as its own text, so every
      # glob operand is also judged as that literal path.
      if ((glob)); then
        if ((abs)); then t2="$full"; else rdt_join_to t2 "${RDT_ORIGINS[m]}" "$full"; fi
        ((slash)) && t2+=/
        rdt_add_literal "$t2" "$word"
      fi
      if [[ "$mode" != deep ]]; then
        rdt_add_pair "$p" "$mode" "$enum" "$word"
        continue
      fi
      # A glob before the last component: its directory part is expanded
      # with real globbing from this directory, and each match is judged as
      # a concrete, LITERAL path, so a link it passes through is followed and
      # a `$` or bracket in a matched name is never read again. With no
      # match, the literal directory in front of the glob is judged.
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
          # The last component globs too: its matches are children of g, and
          # with a trailing slash the links among them are read.
          e=""
          ((slash)) && e="$lastc"
          rdt_add_pair "$g" whole "$e" "$word"
        else
          t2="$g/$lastc"
          ((slash)) && t2+=/
          rdt_add_literal "$t2" "$word"
        fi
      done
    done
  done
  ((${#tp[@]})) || return 0

  # The scratchpad, read only now so the dispatcher cache answers every other
  # call. A NUL byte in it refuses: there is a target to judge, and the
  # scratchpad it would be judged against cannot be read faithfully.
  sp=""
  if hook::jq_fields "$INPUT" '.scratchpad_dir'; then
    ((HOOK_JQ_FIELDS_NUL)) && rdt_block "nul-field" "scratchpad_dir"
    sp="${HOOK_JQ_FIELDS[0]:-}"
    sp="${sp//\\//}"
  fi
  rdt_is_abs "$sp" || sp=""
  hook::_temp_root_candidates
  local -a temps=()
  for c in ${_HOOK_TEMP_CANDS[@]+"${_HOOK_TEMP_CANDS[@]}"}; do temps+=("${c//\\//}"); done
  # ONE tree: the payload cwd's. A directory a cd reaches is judged against
  # it too, never against a tree of its own, so `cd <other checkout> && rm -rf
  # x` is outside.
  local tree=""
  rdt_tree_to tree "${RDT_ORIGINS[0]}"
  rdt_deadline
  # The user's allowed roots, from this hook's own environment (userConfig),
  # never from the command text. An entry that is empty, relative, UNC, a
  # drive path on a host without drives, over the operand bounds, or holds a
  # glob character, a line break or a `..` component grants nothing. One
  # trailing `*` after a literal name makes a NAME-PREFIX entry instead
  # (`D:/worktrees/.tmp-*`): its directory follows the same rules, and the name
  # before the `*` may hold no glob character. HOME is resolved with them, and
  # an unusable HOME leaves the whole list unused.
  local -a allow=() pdir=() pname=()
  local home="${HOME:-}" roots="${CLAUDE_PLUGIN_OPTION_BLOCK_ROOT_DELETE_TARGET_ALLOWED_ROOTS:-}" x pfx
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
    if [[ "$c" == */?*'*' ]]; then
      pfx="${c##*/}"
      pfx="${pfx%'*'}"
      c="${c%/*}"
      [[ -n "$pfx" && "$pfx" != *[*?[]* ]] || continue
    fi
    x="${c//[^\/]/}"
    [[ -n "$c" && "$c" != *[$'\n\r*?[']* && "/$c/" != */../* ]] || continue
    ((${#c} + ${#pfx} <= MAX_OPERAND_LEN && ${#x} <= MAX_OPERAND_DEPTH)) || continue
    if ! rdt_is_abs "$c" || rdt_is_unc "$c"; then continue; fi
    ((RDT_WIN)) || [[ ! "$c" =~ ^[A-Za-z]: ]] || continue
    if [[ -n "$pfx" ]]; then
      ((RDT_WIN)) && pfx="${pfx,,}"
      pdir+=("$c")
      pname+=("$pfx")
    else
      allow+=("$c")
    fi
  done
  ((${#allow[@]} + ${#pdir[@]})) || home=""

  # One realpath over the parents, the tree, the temp roots, the scratchpad,
  # the allowed roots and HOME. A `*/` operand then has its symlink matches
  # added, each resolved whole, and on Windows one cygpath maps every full
  # target and root onto one spelling.
  rdt_resolve_all ${tp[@]+"${tp[@]}"} ${temps[@]+"${temps[@]}"} "$sp" "$tree" ${allow[@]+"${allow[@]}"} ${pdir[@]+"${pdir[@]}"} "$home"
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
  for c in ${temps[@]+"${temps[@]}"} "$sp" "$tree" ${allow[@]+"${allow[@]}"} ${pdir[@]+"${pdir[@]}"} "$home"; do
    [[ -n "$c" ]] && others+=("${RDT_RES[$c]}")
  done
  rdt_winmap_all ${targets[@]+"${targets[@]}"} ${others[@]+"${others[@]}"}
  rdt_deadline
  RDT_TEMPC=()
  for c in ${temps[@]+"${temps[@]}"}; do
    rdt_canon_to t "${RDT_WMAP[${RDT_RES[$c]}]}"
    rdt_root_like "$t" || RDT_TEMPC+=("$t")
  done
  # The scratchpad counts only strictly under a temp root, where a harness
  # puts it; a payload naming anywhere else as its scratchpad is ignored.
  RDT_SPC=""
  if [[ -n "$sp" ]]; then
    rdt_canon_to c "${RDT_WMAP[${RDT_RES[$sp]}]}"
    for t in ${RDT_TEMPC[@]+"${RDT_TEMPC[@]}"}; do
      [[ "$c" == "$t"/* ]] && RDT_SPC="$c" && break
    done
  fi
  RDT_TREEC=""
  if [[ -n "$tree" ]]; then
    rdt_canon_to t "${RDT_WMAP[${RDT_RES[$tree]}]}"
    rdt_root_like "$t" || RDT_TREEC="$t"
  fi
  # An allowed root, or a name-prefix entry's directory, that is a filesystem
  # root or HOME itself is dropped.
  RDT_ALLOWC=()
  RDT_PDIRC=()
  RDT_PNAME=()
  RDT_HOMEC=""
  if [[ -n "$home" ]]; then
    rdt_canon_to RDT_HOMEC "${RDT_WMAP[${RDT_RES[$home]}]}"
    for c in ${allow[@]+"${allow[@]}"}; do
      rdt_canon_to t "${RDT_WMAP[${RDT_RES[$c]}]}"
      rdt_root_like "$t" || rdt_is_root "${t,,}" || [[ "$t" == "$RDT_HOMEC" ]] || RDT_ALLOWC+=("$t")
    done
    for ((k = 0; k < ${#pdir[@]}; k++)); do
      rdt_canon_to t "${RDT_WMAP[${RDT_RES[${pdir[k]}]}]}"
      { rdt_root_like "$t" || rdt_is_root "${t,,}" || [[ "$t" == "$RDT_HOMEC" ]]; } && continue
      RDT_PDIRC+=("$t")
      RDT_PNAME+=("${pname[k]}")
    done
  fi
  for ((k = 0; k < ${#tp[@]}; k++)); do
    rdt_deadline
    p="${RDT_WMAP[${targets[k]}]}"
    rdt_canon_to c "$p"
    # A symlink, or a leaf rm would follow through a trailing slash that does
    # not exist yet (a link the same command may create), never passes a
    # name-prefix entry.
    l=0
    [[ -L "${targets[k]}" ]] && l=1
    [[ ! -e "${targets[k]}" && "${tw[k]}" =~ [/\\]\.?$ ]] && l=1
    rdt_allowed "$c" "${td[k]}" "$l" || rdt_block "outside-tree" "'$p' (the operand '${tw[k]}')"
  done
  return 0
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
  # Once this arm has work, the rest of the parse counts against its deadline.
  ((RDT_T0 >= 0)) && rdt_deadline
  if ((rdt_depth > 1)); then
    rdt_segments=$((rdt_segments + 1))
    ((rdt_segments > MAX_SEGMENTS)) && rdt_block "too-many-readings"
  fi
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
      # A CDPATH assignment, as a prefix or a segment of its own, lets a later
      # relative cd land anywhere.
      rdt_note_cdpath "$w"
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
    # sudo's -R / --chroot, -a and -c take an operand too, and are absent on
    # purpose: reading `sudo -R rm -rf /` as chroot `rm` would drop a refusal.
    # The plain walk steps over them alone, and the resolved walk takes the
    # operand (rdt_short_cluster_arg, rdt_long_takes_arg), so both are judged.
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
    # setpriv's, prlimit's and systemd-run's getopt strings start with `+`, so
    # the first non-option is the command. setpriv's operand-taking options are
    # all long; prlimit's resource options (`--nofile=10`) take their limit
    # only when attached, so only -p and -o consume a word.
    setpriv) optarg=" --inh-caps --ambient-caps --ruid --euid --rgid --egid --reuid --regid --groups --bounding-set --securebits --pdeathsig --ptracer --selinux-label --apparmor-profile --landlock-access --landlock-rule --list-landlock-rights --seccomp-filter " ;; # spellchecker:disable-line
    prlimit) optarg=" -p --pid -o --output " ;;
    systemd-run) optarg=" -H --host -M --machine -C --capsule -u --unit -p --property --description --slice --expand-environment --service-type --uid --gid --nice --working-directory --root-directory -E --setenv --output --json --job-mode --background --path-property --socket-property --timer-property --on-active --on-boot --on-startup --on-unit-active --on-unit-inactive --on-calendar " ;;
    # shadow's `sg [-|-l] group [[-c] command]` runs exactly one word through
    # `sh -c`: the one after the group, or after a `-c` that has a word after
    # it. Later words are ignored, so that one word is re-parsed like su's -c
    # operand. Source: shadow-maint/shadow src/newgrp.c (sg is newgrp run under
    # that name; last change 10c5a20, fetched 2026-09-29): it reads `-` or `-l`
    # first, then the group (a word not starting with `-`), takes `command =
    # argv[1]` when `argv[0]` is `-c` and another word follows and `argv[0]`
    # otherwise, and runs `execl(SHELL, "sh", "-c", command)`; sg(1) on
    # man7.org says "The command will be executed with the /bin/sh shell". In
    # that source `-` and `-l` set initflag, whose chdir to the home directory
    # comes AFTER that execl, so a command runs from the current directory. The
    # guard still treats the directory as unknown, which only adds refusals.
    # Recheck when shadow's newgrp.c changes how `sg` builds its `sh -c`
    # command, or moves the home-directory chdir ahead of the execl.
    sg)
      j=$((i + 1))
      if ((j < n)) && [[ "${words[j]}" == - || "${words[j]}" == -l ]]; then
        ((RDT_ARM)) && rdt_cd_unknown=1
        j=$((j + 1))
      fi
      ((j < n)) && [[ "${words[j]}" != -* ]] || return 0
      j=$((j + 1))
      ((j + 1 < n)) && [[ "${words[j]}" == -c ]] && j=$((j + 1))
      ((j < n)) && hook::bash_parse_segments "${words[j]}" rdt_check_segment
      return 0
      ;;
    # runuser has two grammars and both are judged, blocking if either does:
    # every -c / --command / --session-command operand is a command, and with
    # -u its non-option words are the command. Without -u the first non-option
    # is the user and the rest go to the shell, so they get su's scan. The
    # remapped provenance is saved first, because each parse rebuilds it.
    # Both getopt readings are judged (see rdt_runuser_argv), the second only
    # when it differs from the first.
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
          hook::bash_parse_segments "$ru_cmd" rdt_check_segment
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
        # env -C and sudo -D run the command from another directory, and
        # sudo -i from the target user's home.
        if ((RDT_ARM)); then
          rdt_note_launcher_dir "$base" "$w" "$((i + 1 < n))" "${words[i + 1]-}" \
            "${HOOK_SEG_WORD_QUOTED[i]:-0}" "${HOOK_SEG_WORD_QUOTED[i + 1]:-0}"
        fi
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
          --s*)
            # No other env long option starts with `s`, so every prefix is
            # --split-string (`env --spl='rm -rf /'`). The split is judged as
            # an extra reading and the plain walk goes on, so reading the
            # prefix can only add refusals.
            sval="${w#--}"
            if [[ "split-string" == "${sval%%=*}"* ]]; then
              local -a env_q=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"})
              if [[ "$w" == *=* ]]; then
                hook::env_s_split "${w#*=}"
                HOOK_SEG_WORD_QUOTED=()
                rdt_check_segment ${HOOK_ENV_S_WORDS[@]+"${HOOK_ENV_S_WORDS[@]}"} \
                  ${words[@]+"${words[@]:i+1}"}
              elif ((i + 1 < n)); then
                hook::env_s_split "${words[i + 1]}"
                HOOK_SEG_WORD_QUOTED=()
                rdt_check_segment ${HOOK_ENV_S_WORDS[@]+"${HOOK_ENV_S_WORDS[@]}"} \
                  ${words[@]+"${words[@]:i+2}"}
              fi
              HOOK_SEG_WORD_QUOTED=(${env_q[@]+"${env_q[@]}"})
            fi
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

  # A directory change moves where a later relative operand lands. Followed
  # only for the outside-tree arm, which is off without a payload cwd.
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

  local q x rc
  local -a bx=()
  for j in ${operand_idx[@]+"${operand_idx[@]}"}; do
    w="${words[j]}"
    q="${HOOK_SEG_WORD_QUOTED[j]:-0}"
    # An EMPTY operand that a BACKSLASH ESCAPE produced is a dropped trailing
    # backslash: bash passes a literal `\` when one ends the input, and MSYS
    # resolves that to the current drive root, which is the #92593 incident
    # minus its quotes. The tokenizer cannot represent it (it has no character
    # left to emit), so provenance is what separates it from `rm -rf ""`, whose
    # empty operand comes wholly from a quoted span (provenance 2) and is
    # refused as an empty operand instead.
    if [[ -z "$w" ]]; then
      ((q == 1)) && rdt_block "root-operand" "/"
      rdt_block "empty-operand"
    fi
    # No path a filesystem accepts is longer than PATH_MAX (4096 on Linux, and
    # far less on Windows), so a longer operand names nothing rm could delete.
    # It is refused before any per-operand scan: the tail strip and the
    # normalization walk an operand's segments, and a 16 KB operand of `/*`
    # segments took 17 s on a Linux runner, near the hook timeout the harness
    # answers WITHOUT a block.
    ((${#w} > MAX_OPERAND_LEN)) && rdt_block "operand-too-long" "an operand of ${#w} bytes"
    # Resolving a path costs one lookup per component, and on Windows about
    # 10 ms each: 2,000 missing components took realpath 90 s. No path in real
    # use is this deep, so a deeper operand is refused unscanned.
    x="${w//[^\/\\]/}"
    ((${#x} > MAX_OPERAND_DEPTH)) && rdt_block "operand-too-long" "an operand with ${#x} path separators"
    # Brace expansion runs before rm sees its argv, so every alternative is
    # judged as an operand of its own. A fully quoted brace is literal; a
    # partly quoted one that would expand cannot be told apart from a literal
    # one by the tokenizer's provenance, so it is refused.
    if [[ "$w" == *'{'* ]] && ((q != 2)); then
      # Bounded before the walk: a word of thousands of braces makes the
      # expander's scan quadratic.
      x="${w//[^\{]/}"
      ((${#w} > MAX_BRACE_WORD || ${#x} > MAX_BRACE_OPEN)) && rdt_block "brace" "of ${#w} bytes with ${#x} braces"
      rc=0
      rdt_brace_expand "$w" || rc=$?
      ((rc == 0)) || rdt_block "brace" "'$w'"
      if ((${#RDT_BX[@]} != 1)) || [[ "${RDT_BX[0]}" != "$w" ]]; then
        ((q == 1)) && rdt_block "brace" "'$w'"
        bx=(${RDT_BX[@]+"${RDT_BX[@]}"})
        # An empty alternative is dropped, exactly as bash drops it.
        for x in ${bx[@]+"${bx[@]}"}; do
          [[ -n "$x" ]] && rdt_check_operand "$x" 0
        done
        continue
      fi
    fi
    rdt_check_operand "$w" "$q"
  done
  return 0
}

# rdt_strip_tail_to <var> <word>: <word> without its trailing path segments
# that carry no name (empty, `*`, `.`, and anything else holding no letter,
# digit or underscore), cut only at a slash that sits outside every `${...}`.
# shellcheck disable=SC2329  # invoked from rdt_check_operand
rdt_strip_tail_to() {
  rdt_strip_nameless_to "$1" "$2" 1
}

# rdt_check_operand <text> <provenance>: one operand through the root and
# bare-variable arms, then recorded BY VALUE for the outside-tree judgment at
# the end, with the directory-change state as it stands here.
# shellcheck disable=SC2329  # invoked from rdt_check_segment, itself a parser callback
rdt_check_operand() {
  local w="$1" norm raw
  rdt_normalize_to norm "$w"
  if rdt_is_root "$norm"; then
    rdt_block "root-operand" "$norm"
  fi
  # The raw word too, before backslashes turn into slashes and slash runs
  # collapse, with its trailing nameless segments stripped OUTSIDE any `${...}`.
  rdt_strip_tail_to raw "${w,,}"
  if rdt_bare_var "$norm" || rdt_bare_var "$raw"; then
    rdt_block "bare-variable" "$w"
  fi
  if ((RDT_ARM)); then
    # A NUL byte in the payload cwd leaves nothing faithful to judge with.
    ((RDT_CWD_NUL)) && rdt_block "nul-field" "cwd"
    rdt_deadline
    RDT_P_TEXT+=("$w")
    RDT_P_Q+=("$2")
    RDT_P_NORIG+=("${#RDT_ORIGINS[@]}")
    RDT_P_UNK+=("$rdt_cd_unknown")
    RDT_P_REF+=("$rdt_cd_refuse")
    RDT_P_SUB+=("$rdt_in_subst")
  fi
  return 0
}

# Brace bounds: MAX_BRACE results per operand, and a word over MAX_BRACE_WORD
# bytes or with more than MAX_BRACE_OPEN braces is refused before the walk.
MAX_BRACE=64
MAX_BRACE_WORD=4096
MAX_BRACE_OPEN=128
# One operand longer than PATH_MAX names no path, and one deeper than
# MAX_OPERAND_DEPTH components names none in real use; both are refused
# unscanned.
MAX_OPERAND_LEN=4096
MAX_OPERAND_DEPTH=128

# rdt_brace_expand <word>: the word's brace expansion into RDT_BX, the way
# bash performs it: the first `{...}` holding a top-level comma is expanded,
# each alternative spliced between the text before and after it, and the
# result expanded again, so nesting and `a{b,c}d` concatenation both work. A
# `{` that opens no such expression stays literal, and `${...}` is a parameter
# expansion, never a brace. Returns 2 for a sequence (`{1..3}`, `{a..c}`),
# which is refused rather than expanded, and past MAX_BRACE results.
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
      # Bash passes a `${...}` through whole, and finds its end by counting
      # every brace, bare ones included; one that never closes leaves the
      # rest of the word unexpanded.
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

# --- PowerShell Remove-Item / rd /s (#4516) ---------------------------------
# Own tokenizer, not lib/powershell/ps-command.sh: that classifier spends a
# shared sink-attempt budget this guard must not touch. Backslash is literal;
# backtick is the escape. Parameters match on any unambiguous prefix of
# Remove-Item's names. cmd /c rd /s and rmdir /s are judged as cmd grammar.
# A pipeline into Remove-Item -Recurse with no path is refused: the target
# arrived through the pipe and cannot be named. So is a target that is a
# `( )`, `$( )` or `@( )` grouping: its value is not known. A statement ends
# at `;`, `|`, `&`, `&&`, `||` and an unquoted newline (LF, CR or CRLF, unless a
# backtick continues the line). An unquoted `(`, `$(` or `{` opens a nested
# level: what is inside is judged as statements of its own, and the closing `)`
# or `}` puts one placeholder word (`(` or `{`) back into the statement that
# was open, so the arguments after a grouping still belong to their command
# (`Remove-Item -Path (Join-Path $a b) -Recurse`). A `}` after an if, foreach,
# try, function or similar keyword also ends that statement. `${name}` is one
# variable word.

rdt_ps_piped=0

# rdt_ps_param_to <var> <token>: canonical Remove-Item parameter name, empty
# when the token is not a unique prefix of one. Token includes the leading
# dash; a :value suffix is ignored for the name.
rdt_ps_param_to() {
  local __name="${2#-}"
  __name="${__name%%:*}"
  __name="${__name,,}"
  local __hit="" __hits=0 __p
  for __p in confirm credential debug erroraction errorvariable exclude filter \
    force include informationaction informationvariable literalpath outbuffer \
    outvariable pipelinevariable path recurse stream usetransaction verbose \
    warningaction warningvariable whatif; do
    if [[ "$__p" == "$__name" ]]; then
      printf -v "$1" '%s' "$__p"
      return 0
    fi
    if [[ -n "$__name" && "$__p" == "$__name"* ]]; then
      __hit="$__p"
      __hits=$((__hits + 1))
    fi
  done
  if ((__hits == 1)); then
    printf -v "$1" '%s' "$__hit"
  else
    printf -v "$1" '%s' ""
  fi
}

# rdt_ps_cmd_split_to <nameref> <text>: cmd.exe-ish whitespace split of one /c
# operand. Double quotes group; a backslash is literal; an empty quoted span
# is an empty word.
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

# rdt_ps_operand <word>: one PowerShell / cmd target through the same root,
# empty, bare-variable and outside-tree arms as Bash. `$env:NAME` and
# `${env:NAME}` are read as `$NAME` and `${NAME}`, so each spelling gets the
# answer the Bash lane gives: `$env:TEMP`, `$env:TEMP\` and `$env:TEMP\*` are
# refused as bare variables, and `$env:TEMP\build` is not.
rdt_ps_operand() {
  local w="$1"
  w="${w//\$\{[eE][nN][vV]:/\$\{}"
  w="${w//\$[eE][nN][vV]:/\$}"
  rdt_check_operand "$w" 0
}

# rdt_ps_cmd_rd: recursive cmd rd/rmdir. Remaining words are the command line.
rdt_ps_cmd_rd() {
  local -a __cw=("$@")
  ((${#__cw[@]})) || return 0
  local __base="${__cw[0],,}" __i __rec=0
  __base="${__base##*[\\/]}"
  __base="${__base%.exe}"
  case "$__base" in
  rd | rmdir) ;;
  *) return 0 ;;
  esac
  local -a __paths=()
  for ((__i = 1; __i < ${#__cw[@]}; __i++)); do
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
  if ((${#__paths[@]} == 0)); then
    rdt_block "empty-operand"
  fi
  local __p
  for __p in "${__paths[@]}"; do
    if [[ -z "$__p" ]]; then
      rdt_block "empty-operand"
    fi
    rdt_ps_operand "$__p"
  done
}

# rdt_ps_cmd_from: argv after a cmd/cmd.exe command word.
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
        rdt_ps_cmd_rd ${__parts[@]+"${__parts[@]}"}
      else
        rdt_ps_cmd_rd "${__a[@]:__i}"
      fi
      return 0
      ;;
    /c?* | /k?*)
      rdt_ps_cmd_split_to __parts "${__a[__i]:2}"
      rdt_ps_cmd_rd ${__parts[@]+"${__parts[@]}"}
      return 0
      ;;
    *) ;;
    esac
    __i=$((__i + 1))
  done
}

# rdt_ps_ri_args <start-index>: argv after a Remove-Item family command word,
# passed as the remainder of the statement array in "$@".
# shellcheck disable=SC2016,SC2329  # literal `$(` grouping; invoked from rdt_ps_statement
rdt_ps_ri_check() {
  local -a __w=("$@")
  local __i=0 __rec=0 __param __raw __att
  local -a __paths=()
  while ((__i < ${#__w[@]})); do
    local __v="${__w[__i]}"
    if [[ "$__v" == -* && "$__v" != - ]]; then
      rdt_ps_param_to __param "$__v"
      __raw="${__v#-}"
      __raw="${__raw%%:*}"
      __raw="${__raw,,}"
      if [[ "$__raw" == "rf" || "$__raw" == "fr" ]]; then
        __rec=1
      fi
      case "$__param" in
      recurse)
        if [[ "$__v" == *:* ]]; then
          __att="${__v#*:}"
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
      case "$__v" in
      /s | /s/q | /q/s | /sq | /qs) ;;
      '('* | '$('*) rdt_block "pipeline-target" "$__v" ;;
      *) __paths+=("$__v") ;;
      esac
    fi
    __i=$((__i + 1))
  done
  ((__rec)) || return 0
  if ((${#__paths[@]} == 0)); then
    ((rdt_ps_piped)) && rdt_block "pipeline-target"
    rdt_block "empty-operand"
  fi
  local __p
  for __p in "${__paths[@]}"; do
    if [[ -z "$__p" ]]; then
      rdt_block "empty-operand"
    fi
    # The walker's placeholder for a `( )` grouping or a `{ }` scriptblock
    # named as a target: what it evaluates to is not known.
    [[ "$__p" == "(" || "$__p" == "{" ]] && rdt_block "pipeline-target" "$__p"
    rdt_ps_operand "$__p"
  done
}

# rdt_ps_rest <i>: remaining words of "$@" from index <i>, possibly empty.
rdt_ps_rest() {
  local __off="$1"
  shift
  if ((__off < $#)); then
    rdt_ps_ri_check "${@:__off+1}"
  else
    rdt_ps_ri_check
  fi
}

# rdt_ps_statement: one pipeline stage's words.
rdt_ps_statement() {
  local -a __w=("$@")
  ((${#__w[@]})) || return 0
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
  remove-item | ri | rm | del | erase)
    rdt_ps_rest "$__i" ${__w[@]+"${__w[@]}"}
    ;;
  rd | rmdir)
    rdt_ps_rest "$__i" ${__w[@]+"${__w[@]}"}
    if ((__i < ${#__w[@]})); then
      rdt_ps_cmd_rd "$__cmd" "${__w[@]:__i}"
    else
      rdt_ps_cmd_rd "$__cmd"
    fi
    ;;
  cmd)
    if ((__i < ${#__w[@]})); then
      rdt_ps_cmd_from "${__w[@]:__i}"
    fi
    ;;
  *) ;;
  esac
}

# rdt_ps_walk <command>: PowerShell quoting (backtick escape, backslash
# literal) into statements split on the boundaries listed above, then judged.
# Judging a statement resets the pipeline state, so the stage right after a `|`
# keeps it across an empty boundary (a newline after the pipe). A newline after
# an unquoted comma does not end the statement: the array continues on the next
# line. The nested levels are parked in __sv (their words, flat), __svn (how
# many words each holds) and __svp (their pipeline state).
rdt_ps_walk() {
  local __s="$1" __n=${#1} __i=0
  local -a __words=() __sv=() __svn=() __svp=() __svk=()
  local __word="" __in=0 __q="" __c __nxt __cont=0
  rdt_ps_piped=0

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
      rdt_ps_statement "${__words[@]}"
      __words=()
      rdt_ps_piped=0
    fi
  }
  # A `(`, `$(` or `{` (its kind is the argument) opens a level: the statement
  # so far is parked and what follows is judged on its own.
  rdt_ps_open() {
    rdt_ps_flush_word
    ((${#__svn[@]} < MAX_SUBST_DEPTH)) || rdt_block "nesting-too-deep"
    if ((${#__words[@]})); then
      __sv+=("${__words[@]}")
    fi
    __svn+=("${#__words[@]}")
    __svp+=("$rdt_ps_piped")
    __svk+=("$1")
    __words=()
    rdt_ps_piped=0
  }
  # A `)` or `}` judges the innermost level and hands its parked statement back
  # with one placeholder word, the kind the level was opened with (`(` or
  # `{`), whichever closer ended it. Without an open level it only ends the
  # statement.
  rdt_ps_close() {
    rdt_ps_end_stmt
    local __k=${#__svn[@]} __cnt __tot __kind
    ((__k)) || return 0
    __cnt=${__svn[__k - 1]}
    __kind=${__svk[__k - 1]}
    __tot=${#__sv[@]}
    if ((__cnt)); then
      __words=("${__sv[@]:__tot-__cnt:__cnt}")
      __sv=("${__sv[@]:0:__tot-__cnt}")
    else
      __words=()
    fi
    rdt_ps_piped=${__svp[__k - 1]}
    unset "__svn[__k - 1]" "__svp[__k - 1]" "__svk[__k - 1]"
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
        else
          __word+="$__c"
        fi
      elif [[ "$__q" == '}' ]]; then
        # `${name}`: the name runs to the first unescaped `}` and stays in the
        # word, so `${env:ProgramFiles(x86)}` is one word and its `(` no boundary.
        if [[ "$__c" == '`' ]] && ((__i + 1 < __n)); then
          __word+="$__nxt"
          __i=$((__i + 1))
        else
          __word+="$__c"
          [[ "$__c" == '}' ]] && __q=""
        fi
      else
        if [[ "$__c" == '`' ]] && ((__i + 1 < __n)); then
          __word+="$__nxt"
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
      # A backtick before a line break (LF, CR or CRLF) continues the line.
      if [[ "$__nxt" == $'\n' || "$__nxt" == $'\r' ]]; then
        __i=$((__i + 2))
        [[ "$__nxt" == $'\r' && "${__s:__i:1}" == $'\n' ]] && __i=$((__i + 1))
        continue
      fi
      __word+="$__nxt"
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
      # `$(` opens a subexpression: its `(` below opens the level and the `$`
      # is not a word. `${` opens a braced variable name.
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
        rdt_ps_piped=0
        rdt_ps_end_stmt
        __i=$((__i + 1))
      else
        rdt_ps_piped=0
        rdt_ps_end_stmt
        rdt_ps_piped=1
      fi
      ;;
    '&')
      if ((__in == 0)) && { [[ -z "$__nxt" ]] || [[ "$__nxt" == [[:space:]] ]] || [[ "$__nxt" == "'" ]] || [[ "$__nxt" == '"' ]]; }; then
        rdt_ps_flush_word
        __words+=("&")
      elif [[ "$__nxt" == '&' ]]; then
        rdt_ps_piped=0
        rdt_ps_end_stmt
        __i=$((__i + 1))
      else
        rdt_ps_piped=0
        rdt_ps_end_stmt
      fi
      ;;
    ';')
      rdt_ps_piped=0
      rdt_ps_end_stmt
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
  # A level the text never closes is judged too.
  while ((${#__svn[@]})); do
    rdt_ps_close
    rdt_ps_end_stmt
  done
}

# rdt_ps_run: PowerShell lane. Does not load the classifier.
rdt_ps_run() {
  rdt_ps_walk "$COMMAND"
}

# The substitution scan runs FIRST, and the order is load-bearing rather than
# arbitrary. The tokenizer splits on unquoted `(`, `)` and `;`, so a deeply
# nested payload yields as many segments as a flat one of the same length and
# the top-level parse pays for every one of them. Scanning first lets the
# tokenizing budget refuse such a payload after the cheap character walk alone,
# instead of after the parse it was built to make expensive.
#
# The outside-tree arm starts from the payload cwd, and only an absolute one:
# a relative cwd names no place this hook can resolve. A cwd carrying a NUL
# byte arms it too, so that the first operand it would record is refused.
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
  hook::bash_parse_segments "$COMMAND" rdt_check_segment
fi
# The judgment runs in a subshell, so an error nobody anticipated inside it (an
# unset variable under `set -u`, say) ends the subshell with a status other
# than 0 or 2, and that status is refused here. Run in place, the same error
# would end the hook with 1, which the fail-open abort boundary passes.
if ((${#RDT_P_TEXT[@]})); then
  rdt_judge_rc=0
  (rdt_judge_pending) || rdt_judge_rc=$?
  ((rdt_judge_rc == 2)) && exit 2
  ((rdt_judge_rc == 0)) || rdt_block "judge-error"
fi

rdt_emit_tel "ok" ""
exit 0
