#!/usr/bin/env bash
# PreToolUse hook: block Bash workarounds that bypass Write/Edit hook gates.
# Triggered on Bash and PowerShell tool calls.
#
# Catches common file-write bypass patterns:
#   cat > path
#   echo ... > path      (and printf ... > path)
#   python3 -c ... file write
#   same-command staged write: <producer> > tmp && mv|cp tmp dest
#     (effective redirect target reused as mv/cp source; #2731)
#
# Detection runs over the PARSED command — one pass of the shared tokenizer
# (hook::bash_parse_segments), which gives every simple command its argv words
# AND its redirections, so the command word and the write's destination are both
# read from the grammar rather than matched out of the text. See "The segment
# model this guard decides on" below. The python write INDICATORS are the one
# thing scanned on the RAW command: they legitimately live inside a quoted `-c`
# payload or a heredoc body, neither of which is argv.
#
# The echo/printf redirect is PRODUCER-SCOPED (see producer_redirect_bypass): it
# fires only when the echo/printf is itself the command whose stdout is
# redirected into a real file, NOT when an `echo` word and a `>` merely co-occur
# in one compound command (`bash x.sh > out.json && echo done` — the redirect's
# producer is `bash`) or survive only inside a quoted argument.
#
# SCOPE (documented residual): a command substitution is not evaluated, so a
# write inside one in double quotes
# (`echo "$(python3 -c 'import pathlib ...')"`) is NOT caught — the whole span is
# one argv word, and running the inner command to find out is not something a
# guard may do. An LLM never emits this form; the deny-list plus human oversight
# are the adversarial layers.
# The supported deliberate bypasses are the kill switch
# (block_hook_bypass_enabled set to false) and the scratch-root exemption
# (block_hook_bypass_scratch_roots). The option's own list is still empty by
# default; since #3719 it composes with ONE root the guard ships exempt — the
# host temp trees, which the harness scratchpad sits under — gated on a project
# root outside the temp tree and confirmed through symlink resolution. See the
# block above scratch_target_exempt for why exempting that gives up no
# protection, and why the memory tier is deliberately not a second one.
#
# BLOCKING: exits 2 on any detected bypass form.

set -uo pipefail

# Kill switch FIRST, above every source: a disabled guard must not pay to parse
# hook-utils.sh before finding out it is off.
#
# Only the DISABLED arm is hoisted, and that split is the whole point. This
# guard's switch is strict-and-loud (#3130 F7): a value that is neither `true`
# nor `false` keeps the guard on and SAYS so, through hook::emit_channels — a
# library function, so that arm cannot run before the library exists. An exact
# `false` needs nothing from the library, so it exits here; every other value
# falls through to the unchanged strict-and-loud block below, which the library
# is loaded in time for. scripts/check-killswitch-hoist.sh knows this shape.
[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_HOOK_BYPASS_ENABLED:-true}" == "false" ]] && exit 0

# The hook's own directory is derived with parameter expansion rather than
# `dirname`. GNU Bash forks a subshell for every command substitution even when
# the body is a builtin (Command Substitution, Bash Reference Manual;
# https://mywiki.wooledge.org/CommandSubstitution). On Windows Git Bash that
# fork is a process, and this line runs on every fire — including inside the
# dispatcher, where the include guard makes `source` cheap but `$(dirname …)`
# still execs. `${BASH_SOURCE[0]%/*}` equals `dirname` for every shape
# BASH_SOURCE takes; the fallback covers a bare filename, where the strip is a
# no-op and dirname answers `.`.
_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
# Crash posture (#3130 F5, now the shared boundary of #3528): fail-open. This
# guard sits on every Bash/PowerShell call. An internal error must not take the
# session down, and it must not look like a clean allow. EXIT converts any
# status other than the two this guard chooses, 0 (allow) and 2 (block), to 0
# after a dual-channel "guard did not run" notice.
guard::abort_boundary block-hook-bypass PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

# Strict-and-loud enable (#3130 F7). hook::check_enabled treats any value other
# than exact "true" as off, so a typo would silently disable a blocking safety
# control. Only true/false (unset → true) are accepted; anything else keeps the
# guard on and says so.
_bbh_enabled="${CLAUDE_PLUGIN_OPTION_BLOCK_HOOK_BYPASS_ENABLED:-true}"
case "$_bbh_enabled" in
true) ;;
false) exit 0 ;;
*)
  _bbh_bad="guardrails block-hook-bypass: block_hook_bypass_enabled=${_bbh_enabled} is not exactly true or false; treating as enabled (a safety switch does not silently disable)"
  echo "$_bbh_bad" >&2
  hook::emit_channels PreToolUse "$_bbh_bad" "$_bbh_bad"
  ;;
esac

# High-res start stamp for the telemetry envelope. EPOCHREALTIME is Bash 5.0+;
# on older bash it is unset, so default to empty and skip telemetry (the block
# still fires). Referencing it bare under `set -u` would abort before exit.
start=${EPOCHREALTIME:-}

# hook::buffer_stdin encapsulates the Win32-pipe-safe bounded fd0 read. rc 1
# (empty stdin) skips like the empty-COMMAND guard below; rc 2 (text that is
# not JSON, or a pipe that stayed open and went quiet before the document was
# complete) FAILS CLOSED — the guard cannot evaluate the tool call, and a
# silent skip would pass exactly the traffic this guard exists to stop.
# buffer_stdin already printed the BLOCKED reason to stderr. rc 3 is the one
# other way a payload can be unreadable: a well-formed JSON prefix arrived
# and the pipe then CLOSED. That is a transport fault the agent cannot cause
# — the harness serializes the payload and owns the pipe's close — and it
# says nothing about the command, so it is not a block; it is a loud allow
# (dual-channel notice plus a `skipped` telemetry envelope). A STALL on such
# a prefix is deliberately not rc 3: payload size and host load both move
# it, so it stays a block. Buffering does not require jq
# (hook::buffer_stdin's own JSON-completeness check is jq-optional), so it
# runs before the jq gate below — hook::require_jq needs the buffered input
# for its once-per-session notice scoping.
hook::buffer_stdin_to INPUT || {
  rc=$?
  ((rc == 2)) && exit 2
  if ((rc == 3)); then
    hook::stdin_cut_short_notice PreToolUse "guardrails block-hook-bypass"
    if [[ -n "$start" ]] && hook::telemetry_enabled; then
      # Declared before the call because hook::json_str_object_to assigns
      # through a nameref; without this, shellcheck reads the variable at the
      # next line as never assigned (SC2154). The sibling emit_tel below gets
      # the same effect from its `local data`, which this site cannot use: it
      # runs at top level, inside hook::buffer_stdin's failure block.
      _bbh_tel=""
      hook::json_str_object_to _bbh_tel tool "" subject "" form "" reason "stdin-cut-short"
      hook::emit_telemetry "block-hook-bypass" "PreToolUse" "skipped" "$start" "$_bbh_tel" "${CLAUDE_PROJECT_DIR:-}"
    fi
  fi
  exit 0
}

# jq is required to parse the tool payload. hook::require_jq fails OPEN
# (advisory hooks never block over a missing prerequisite) but makes the
# degraded state visible to both the user (systemMessage) and the agent
# (additionalContext), once per session — see docs/conventions/hook-observability/.
hook::require_jq "PreToolUse" "guardrails-block-hook-bypass" "$INPUT"

# All three payload fields in ONE jq process (hook::jq_fields), not three. A jq spawn is
# fork() emulation on Windows Git Bash and this guard runs on every Bash/PowerShell
# call. Failure semantics are unchanged: a missing jq or an unparsable payload
# yields rc 1 here, which exits 0 exactly as the empty-COMMAND skip below did —
# hook::require_jq above has already made the degraded state visible once per
# session. The `// "Bash"` default moves to the bash-side expansion, matching
# block-dangerous-git.
hook::jq_fields "$INPUT" '.tool_input.command' '.tool_name' '.cwd' || exit 0

# A NUL byte in ANY field read above is fail-CLOSED (#2136): the helper strips NUL
# bytes before matching, so a clean verdict would not reflect the bytes carried.
if ((HOOK_JQ_FIELDS_NUL)); then
  echo "BLOCKED: the payload carries a NUL byte, which a command cannot reliably carry." >&2
  echo "What a guard can read is not dependably what would run, so this is refused rather than matched." >&2
  echo "Fix: reissue the tool call without the embedded NUL." >&2
  exit 2
fi

COMMAND="${HOOK_JQ_FIELDS[0]}"
[[ -n "$COMMAND" ]] || exit 0
TOOL_NAME="${HOOK_JQ_FIELDS[1]:-Bash}"
# The directory the TOOL CALL runs in, which is not this hook process's own —
# the hook starts at the session root and the tool call routinely does not. It is
# read for ONE purpose: resolving a relative redirect target against it in the
# scratch-root axis below, which can only ever GRANT an exemption. `.cwd` is
# already in run-guards.sh's PRIME_FILTERS, so under the dispatcher this field
# costs a cache lookup rather than a jq process.
HOOK_CWD="${HOOK_JQ_FIELDS[2]:-}"

# Emit one telemetry envelope: $1 status, $2 form ("" when not blocked). Gated
# on the high-res start stamp and the opt-in sink, so the unwired default path
# spawns no telemetry-only subprocess.
#
# The privacy-safe subject (`Bash:<first-token>` with leading `sudo` /
# env-assignment prefixes stripped and the token basenamed, never the full
# command) is derived HERE, behind both gates, not at file scope. The shared
# helper answers through a command substitution, and that is a fork on every
# fire; only the envelope reads the subject, and the envelope is off by default,
# so deriving it eagerly spent a process on every Bash call for a value nothing
# consumed (#3513). The verdict never reads it. The shared helper is still used
# rather than a local copy so the aborts that keep an assignment VALUE out of
# the subject (a quoted value spanning the whitespace the tokenizer splits on,
# and a bare/trailing `NAME=value` no following command consumed) hold here
# too (#3372).
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data subject
  subject=$(hook::extract_bash_subject "$TOOL_NAME" "$COMMAND")
  hook::json_str_object_to data tool "$TOOL_NAME" subject "$subject" form "$2"
  hook::emit_telemetry "block-hook-bypass" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# --- The segment model this guard decides on ---------------------------------
#
# The command is tokenized ONCE, by the shared parser (hook::bash_parse_segments),
# which hands every simple command both halves of its grammar: the argv words,
# and the redirections bash removes from argv. This guard's subject IS the
# redirect target, so the second half is the half that matters, and reading it
# from the shared parse is what keeps one tokenizer in the repository instead of
# two disagreeing ones over the same string.
#
# What the parse settles that a text scan could not:
#
#   - A quoted operand is ONE pathname to bash, whitespace and separators
#     included. `echo x > "/dev/null ../../etc/pw"` yields the whole path as the
#     target, so no fragment of it can stand in for the whole (#2226).
#   - A quoted span anywhere else is ONE argv word, so prose or a commit message
#     mentioning `echo > file` carries no redirection at all.
#   - An escaped separator (`echo x \; > f`) is an argument, not a boundary, and
#     a backslash-newline continuation joins a word rather than splitting one.
#   - A here-doc body is stdin, not commands; a here-string is neither.
#
# Every word and every target arrives with its QUOTING PROVENANCE, which is what
# the target-scoped exemptions are keyed on: an operand whose written text is not
# the text bash uses (it was quoted, or an escape produced it) exempts nothing,
# and one the parse could not resolve at all is OPAQUE and exempts nothing
# either. Case is folded on the way in, so every scan below is
# case-insensitive — the documented residual the scratch-root axis carries.

# One row per simple command, in source order. Words are stored flat with a
# per-segment offset and length rather than as nested arrays, which bash has no
# form for.
SEG_COUNT=0
SEG_W=()       # every segment's argv words, lowercased, concatenated
SEG_WQ=()      # parallel quoting provenance: 0 literal, 1 partly quoted, 2 wholly quoted
SEG_WOFF=()    # index into SEG_W where segment i's words start
SEG_WLEN=()    # how many words segment i has
SEG_TGT=()     # segment i's EFFECTIVE stdout target, lowercased
SEG_TGT_Q=()   # 1 when quoting or an escape produced that target text
SEG_TGT_OPQ=() # 1 when the target is not resolvable from this command string
SEG_TGT_SET=() # 1 when segment i redirects stdout to a file at all

# 1 when this command carries a directory change, which moves the directory a
# RELATIVE redirect target resolves against. Only the scratch-root axis reads it,
# and only to REFUSE a relative target it can no longer place (see
# _scratch_abs_target) — so an over-eager match costs an exemption, never a
# missed block, and the failure direction is the guard's shipped behaviour.
#
# The cd TARGET is deliberately not evaluated: resolving it would mean evaluating
# arbitrary shell word expansion, which this guard does not do (see
# block-dangerous-git.sh's treatment of the same relocation).
_BBH_CWD_MOVED=0

# hook::bash_parse_segments callback: record one simple command.
#
# Bash applies redirections LEFT TO RIGHT, so the LAST stdout-to-file one is the
# effective target: `cat > /dev/null > real.txt` writes to real.txt, and
# `cat > /dev/null 1>real.txt` does too. A check that exempted a segment on
# merely CONTAINING a `/dev/null` redirect would hand an attacker a one-token
# bypass of this whole guard — write the discard first, the real file second.
# An fd-qualified redirect (`2>err`) is not stdout, and a dup or close (`>&2`,
# `>&-`) names an fd rather than a file, so neither is a write.
# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
collect_segment() {
  local w j
  SEG_WOFF+=("${#SEG_W[@]}")
  SEG_WLEN+=("$#")
  for w in "$@"; do SEG_W+=("${w,,}"); done
  for j in "${HOOK_SEG_WORD_QUOTED[@]}"; do SEG_WQ+=("$j"); done
  local tgt="" tset=0 tq=0 topq=0
  for ((j = 0; j < ${#HOOK_SEG_REDIR_OP[@]}; j++)); do
    case "${HOOK_SEG_REDIR_OP[j]}" in
    '>' | '>>') ;;
    *) continue ;;
    esac
    case "${HOOK_SEG_REDIR_FD[j]}" in
    '' | 1) ;;
    *) continue ;;
    esac
    tgt="${HOOK_SEG_REDIR_TARGET[j],,}"
    tset=1
    tq="${HOOK_SEG_REDIR_QUOTED[j]}"
    topq="${HOOK_SEG_REDIR_OPAQUE[j]}"
  done
  SEG_TGT+=("$tgt")
  SEG_TGT_SET+=("$tset")
  SEG_TGT_Q+=("$tq")
  SEG_TGT_OPQ+=("$topq")
  ((SEG_COUNT++))
  # Anchored at the command word, so `git checkout -- cd` and a `--cd-to` flag
  # do not trip it.
  case "${1,,}" in
  cd | pushd | popd | chdir) _BBH_CWD_MOVED=1 ;;
  *) ;; # every other command word leaves the redirect origin where it was
  esac
}

COMMAND_LC="${COMMAND,,}"

# Command-prefix words that legitimately precede the real command word in a
# simple command: environment assignments (`FOO=bar cmd`) and the command-name
# modifiers `command` / `builtin` / `exec` / `env`. Peeling them (see
# peel_command_word) exposes an echo/printf hidden behind a valid prefix
# (`command echo x > f`, `FOO=bar echo x > f`) so the producer scan still sees it.
# A bare `coproc` is a command header that can precede the producer of a simple
# command (`coproc echo x > f`), so it is peeled too. Only the bare keyword is
# peeled: the optional NAME form is `coproc NAME compound-command`, so eating a
# second word would swallow the real command word in `coproc echo …`.
# The compound-command header keywords / group opener / pipeline negation that put
# a producer inside a loop, conditional, or negated command
# (`if`/`elif`/`while`/`until`/`do`/`then`/`else`/`{`/`!`) are peeled by the same
# pass. Peeling is safe: the producer gate still requires echo/printf, so
# revealing a NON-echo command word can never cause a block.
#
# A leading REDIRECTION needs no peel of its own: bash removes it from argv and
# the shared parse does too, so `> real.txt echo x` arrives with `echo` already
# as its command word while its redirection stays the write signal.
_cmd_assign_re='^[A-Za-z_][A-Za-z0-9_]*='
# python file-write indicators that are unambiguous on their own. `pathlib` /
# `path(` are identifier-boundary anchored so they match the write-capable
# `pathlib.Path(` producer but NOT the read-only `os.path.*path(` helpers
# (`normpath(`, `abspath(`, `realpath(`, …) whose trailing `path(` would
# otherwise substring-match and false-positive.
_py_write='\.write[[:space:]]*\(|(^|[^[:alnum:]_])pathlib|(^|[^[:alnum:]_])path[[:space:]]*\('
# `open(` is NOT one of them: `open(f,'w')` writes and `open(f)` reads, and the
# two differ only by an argument. A bare `open(` therefore says nothing about
# direction, and matching it blocked every read-mode inline `open()`.
# DISCRIMINATION BOUNDARY (see py_write_indicator): `open(` counts as a write
# indicator only when a python WRITE-MODE LITERAL also occurs somewhere in the
# same command — a quoted token built solely from mode characters that contains
# at least one of `w` / `a` / `x` / `+`, in an argument position (after a comma,
# or after `mode=`). Read modes (`'r'`, `'rb'`, `'rt'`) carry none of those
# characters and no longer trip it.
#
# CO-OCCURRENCE, not position — deliberately. Bash ERE has no lazy quantifier, so
# a positional `open\([^)]*'w'` stops at the first `)` and would fail OPEN on a
# real write with a nested call (`open(os.path.join(a,b),'w')`), while a greedy
# `.*` reaches into unrelated text anyway. This is the same mangle-resistant
# co-occurrence shape the PowerShell lane below already uses.
#
# ACCEPTED RESIDUAL (the fail-CLOSED direction): a read-only `open()` in a
# command that separately contains an argument-position `'w'`/`'a'`/`'x'`/`'+'`
# literal (e.g. `print(open('f').read(), 'a')`) still blocks. The argument-position
# requirement is what keeps the common read shapes clear — a dict subscript
# (`json.load(open('p'))['a']`) is preceded by `[`, not by a comma.
_py_open='open[[:space:]]*\('
_py_write_mode='(,|mode[[:space:]]*=)[[:space:]]*['\''"][rwaxbtu+]*[wax+][rwaxbtu+]*['\''"]'

# True when the (lowercased) command carries a python file-write indicator.
py_write_indicator() {
  local cmd_lc="$1"
  [[ "$cmd_lc" =~ $_py_write ]] && return 0
  [[ "$cmd_lc" =~ $_py_open && "$cmd_lc" =~ $_py_write_mode ]] && return 0
  return 1
}

# Flag ONLY when the producer being redirected into a real file is echo/printf
# authoring content — not any command string that merely co-mentions an `echo`
# token and a `>` token. Split the literal-stripped command into simple-command
# segments on shell separators (`; | & ( )` and newlines), then require, WITHIN
# one segment, that the command token is echo/printf AND that same segment
# redirects stdout to a real file. This passes `bash x.sh > out.json && echo done`
# (the redirect's producer is `bash`, not the trailing `echo`) and a bounded poll
# loop `... > poll.json; echo "..."`, while still blocking `echo "x" > file`.
#
# SCOPE (documented residual): a redirect applied to a GROUP rather than to the
# echo itself — `{ echo x; } > file` / `( echo x ) > file` — is NOT caught. The
# closing `}` / `)` are separators, so the redirect lands in a different segment
# from the echo inside the group. Catching it needs brace/paren-depth tracking,
# out of scope for a false-positive fix; the form is structurally unusual for LLM
# output and covered by an accepted-floor test.
#
# SCOPE (documented residual): the command-prefix peel (see peel_command_word)
# covers the bounded shell-grammar set — env assignments and
# `command`/`builtin`/`exec`/bare `env`. External command-runner utilities that
# take their own options and a
# command argument — `nohup`/`nice`/`time`/`timeout N`/`sudo`/`stdbuf -oL`/`xargs`,
# and non-bare `env` (`env -i echo …`, `/usr/bin/env echo …`) — are NOT peeled, so
# `nohup echo x > f` and friends are not caught. Peeling them correctly requires
# per-utility argument parsing (each has a different option grammar), out of scope
# for this false-positive fix; the forms are structurally unusual for LLM output
# and covered by an accepted-floor test.
#
# SCOPE (documented residual): only the BARE `coproc echo …` header is peeled.
# The named form `coproc NAME { echo x > f; }` is not, because NAME is
# indistinguishable from a command word by prefix-peeling alone, and the redirect
# there is group-level (same brace-group floor as above). Structurally unusual for
# LLM output and covered by an accepted-floor test.

# The command word of segment $1 (offset) / $2 (length), into PEELED_IDX as an
# index into SEG_W. Returns 1 when the segment has no command word to judge, or
# when it is a `command -v`/`-V` LOOKUP: those DESCRIBE the argument rather than
# running it, so a following echo/printf is a bareword being looked up, not a
# content producer (`command -v echo > f` writes the word "echo", not echo's
# output) and the segment is skipped rather than blocked.
#
# Options belong only to the option-taking modifiers command/exec (bash built-in
# help: `command [-pVv]`, `exec [-cl] [-a name]`); env/builtin keep their
# bare-only floor, so option grammar is not widened past those two. The
# arg-taking form (exec's `-a name`, a short-option cluster ending in `a`) is
# peeled first so its NAME word is consumed too, else the plain-cluster peel
# would stop at `-a` and leave NAME masking the producer. `--` ends options
# (`exec -- echo x > f`).
PEELED_IDX=-1
peel_command_word() {
  local off="$1" len="$2" k=0 w prev_mod="" optw optn
  PEELED_IDX=-1
  while ((k < len)); do
    w="${SEG_W[off + k]}"
    case "$w" in
    command | builtin | exec | env | coproc | if | elif | then | else | while | until | do | '!' | '{')
      prev_mod="$w"
      ((k++))
      continue
      ;;
    *) ;; # not a modifier keyword; the assignment and option tests decide
    esac
    if [[ "$w" =~ $_cmd_assign_re ]]; then
      prev_mod="$w"
      ((k++))
      continue
    fi
    if [[ "$prev_mod" == command || "$prev_mod" == exec ]]; then
      optw=""
      optn=0
      if [[ "$w" =~ ^-[a-z]*a$ ]] && ((k + 1 < len)); then
        optw="$w ${SEG_W[off + k + 1]}"
        optn=2
      elif [[ "$w" =~ ^-[a-z]+$ || "$w" == "--" ]]; then
        optw="$w"
        optn=1
      fi
      if ((optn)); then
        [[ "$prev_mod" == command && "$optw" == *v* ]] && return 1
        ((k += optn))
        continue
      fi
    fi
    break
  done
  ((k < len)) || return 1
  PEELED_IDX=$((off + k))
  return 0
}

# 0 when segment $1's effective stdout target is the stdout DISCARD. Quoting is
# transparent here — `> "/dev/null"` and `> /dev/"null"` are the same discard —
# but an OPAQUE operand is not: `> "/dev/null ../../etc/pw"` is one pathname to
# bash and it is not `/dev/null`, which is exactly the bypass #2226 reported.
devnull_target_exempt() {
  ((SEG_TGT_OPQ[$1] == 0)) && [[ "${SEG_TGT[$1]}" == "/dev/null" ]]
}

# --- Scratch-root exemption (opt-in; TARGET-PATH axis) ------------------------
#
# This guard is PRODUCER-scoped: it fires on echo/printf/cat/python3 -c as the
# command whose stdout reaches a file, wherever that file lives. The exemption
# below is the guard's first TARGET-scoped axis, and it is deliberately narrow.
# Read this block before widening it.
#
# WHY: a read-only investigation that writes a throwaway probe under a session
# or job temp root is blocked exactly like a repo-file write, and none of the
# Write/Edit hooks this guard protects (formatters, secret scanning, path
# checking) would ever process such a file. See #2210.
#
# WHY OPT-IN AND EMPTY BY DEFAULT: the last target-based exemption of this shape
# (`/dev/null`) shipped a one-token bypass of the whole guard — write the discard
# first, the real file second — fixed by resolving the EFFECTIVE target
# left-to-right in set_last_stdout_target above. Shipping an empty list keeps the
# default trust surface byte-for-byte what it was, and confines the new axis to
# operators who name their own roots.
#
# HOW THE MATCH IS MADE, and why it is not a prefix compare: both the target and
# each configured root are lexically normalized first (Windows separators and
# drive letters folded to the Git Bash spelling, `.` and `..` resolved by
# COMPONENT, duplicate and trailing slashes dropped). Only then is containment
# decided, and it requires the target to continue with `/` past the root's last
# component — so `/tmp/scratchevil/f` is NOT under `/tmp/scratch`, while a bare
# string prefix would have exempted it. `..` that escapes above the root is
# resolved away before the compare, so `/tmp/scratch/../../etc/passwd` normalizes
# to `/etc/passwd` and blocks.
#
# WHAT FAILS CLOSED (blocks, no exemption considered): a relative target (the cwd
# a redirect resolves against is not knowable from the payload — an earlier `cd`
# in the same command can move it); a target still carrying `$`, a backtick or
# `~` (the written text is not the path that gets written); and a target carrying
# `*`, `?` or `[` (a glob names a set, not a path).
#
# SCOPE (documented residual): normalization is LEXICAL, not filesystem
# resolution. Symlinks are not followed — a symlink inside a configured root that
# points outside it is exempted. Resolving them needs a subprocess per segment,
# which this file's hot path deliberately refuses, and the target frequently
# does not exist yet. An operator naming a root is accepting that root's
# contents.
#
# SCOPE (documented residual): the comparison is CASE-INSENSITIVE, because the
# segment model stores every word and target lowercased (see collect_segment).
# On a case-sensitive filesystem a sibling directory differing from a configured
# root only in case is therefore also exempt.
#
# A QUOTED OR ESCAPED redirect operand is never exempt — see the fail-closed
# tests at the top of scratch_target_exempt. That decision is made on the
# OPERAND, from the provenance the shared parse carries with it, not on the raw
# command: an operand quoting or an escape produced is refused by this axis on
# its shipped floor, and one the parse could not resolve is refused outright.
# The truncation that made such an operand compare as a safe-looking prefix of
# itself also reached the `/dev/null` exemption (#2226); a whole-operand parse
# closes both, and devnull_target_exempt is where the discard half decides.
#
# SCOPE: Bash lane only. The PowerShell lane classifies on cmdlet/redirect
# CO-OCCURRENCE and never resolves a single effective target, so there is no
# well-defined target to exempt there; its `$null` discard is unchanged.
_SCRATCH_ROOTS="${CLAUDE_PLUGIN_OPTION_BLOCK_HOOK_BYPASS_SCRATCH_ROOTS:-}"

# --- Shipped default, in ADDITION to the configured list (#3719) -------------
#
# The paragraph above shipped this axis empty, and the emptiness is what the
# ablation measured: five blocks in one day across four sessions, zero true
# positives. ADR 0003 clause 4 calls that a WRONG SCOPE, remedied by rescoping
# rather than by deleting a sound oracle, so the oracle is untouched and one
# default root is added under it.
#
# The default names a target that NO Write|Edit gate would have processed, so
# exempting it removes no protection — which is the only reason a default is
# defensible here at all. The guard exists to stop a Bash write from reaching a
# file that Write|Edit would have run a content gate over; a target those gates
# decline is not a bypass of anything. That argument is load-bearing, and it is
# what disqualified the second default this block originally carried.
#
#   TEMP TREE — hook::read_file_path, the library entry every Write|Edit content
#   guard reads its file through, DECLINES a file under a host temp root when the
#   project root lies outside that tree. The harness's own per-session scratchpad
#   lives there. The exemption's width is therefore exactly the width of the
#   protection it is scoped out of, and hook::under_temp_root is the same
#   candidate set (TMPDIR/TMP/TEMP plus the POSIX defaults, never a hardcoded
#   platform assumption) that the decline is decided on.
#
# THE MEMORY TIER IS DELIBERATELY NOT A DEFAULT, and the reason is worth keeping
# because it is the obvious second entry. `<memory_dir>/` (default `.work/`) was
# exempted here in review and removed again: the "gives up no protection"
# argument above does NOT carry to it. hook::read_file_path has no `.work/`
# decline, so `secret-pattern-detection` scans a Write to `.work/notes.md` today
# (verified — the tier is not in its allowlist). Exempting Bash redirects there
# would have let `printf '<secret>' >> .work/notes.md` reach disk unscanned while
# the identical Write stayed blocked, which is the same content-guard bypass this
# plugin's MCP lane exists to close.
#
# The tension is real and is NOT resolved here: docs/conventions/topic-docs/
# states as normative that raw output — explicitly including credentials — stays
# in the memory tier, which reads as an argument for exempting it from secret
# scanning too. Making the two guards symmetric that way is a widening of a
# default-on security guard, and ADR 0003 wants firing evidence before one of
# those moves. Filed rather than decided.
#
# The consequence is that `printf '*' >> .work/.gitignore` still blocks. That
# command is session-flow's own documented procedure, so the conflict routes back
# to the skill (fix the procedure to use Write, which is scanned) rather than to
# the guard, which is where the filed issue puts it.
#
# THE TEMP DEFAULT is not spelled as a static plugin.json default, because it has
# no fixed spelling: the scratchpad path carries a session id. It resolves at run
# time instead, and the option's own default stays empty — it configures
# ADDITIONAL roots, and the temp default is not removable through it (the kill
# switch is the whole-guard lever, as it was).
#
# GATED ON A KNOWN PROJECT ROOT. With CLAUDE_PROJECT_DIR unset the default does
# not fire: without it hook::read_file_path falls back to git-working-tree
# membership, under which a temp file inside a fixture checkout IS processed.
# Unknown project, no exemption.
# The pieces that implement this sit below _norm_path, which they resolve
# through: _bbh_temp_default_applies and _scratch_abs_target.
_BBH_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"

# Lexically normalize an absolute path into `/`-joined canonical form in
# _NORM_PATH. Returns 1 for every shape the compare must not be trusted with
# (see "WHAT FAILS CLOSED" above); returns 0 with _NORM_PATH empty only for `/`
# itself, which is never a usable root.
_NORM_PATH=""
_norm_path() {
  local p="$1" out="" comp rest
  case "$p" in
  *'$'* | *'`'* | *'~'* | *'*'* | *'?'* | *'['*) return 1 ;;
  *) ;; # every other shape proceeds to normalization below
  esac
  p="${p//\\//}"
  # `C:/x` and `c:` -> the Git Bash spelling `/c/x`, so both spellings compare
  # equal after normalization.
  if [[ "$p" =~ ^([A-Za-z]):(/.*)?$ ]]; then
    p="/${BASH_REMATCH[1]}${BASH_REMATCH[2]:-/}"
  fi
  [[ "$p" == /* ]] || return 1
  # Split on `/` by hand rather than by word-splitting with IFS: an unquoted
  # expansion would also glob against the cwd.
  rest="$p"
  while [[ -n "$rest" ]]; do
    comp="${rest%%/*}"
    if [[ "$comp" == "$rest" ]]; then rest=""; else rest="${rest#*/}"; fi
    case "$comp" in
    '' | '.') continue ;;
    '..')
      # An escape above the root is not a path this guard can reason about.
      [[ -n "$out" ]] || return 1
      out="${out%/*}"
      ;;
    *) out="$out/$comp" ;;
    esac
  done
  _NORM_PATH="$out"
  return 0
}

# --- the pieces of the shipped default (see the block above) -----------------

# The project root, normalized, or empty when there is no usable one. Kept in its
# ORIGINAL case: hook::under_temp_root compares against this host's real temp
# directories, whose own case it preserves, so lowercasing would miss a temp root
# spelled with capitals and wrongly conclude a temp-rooted project was not one.
_BBH_PROJECT_NORM=""
if [[ -n "$_BBH_PROJECT_DIR" ]] && _norm_path "$_BBH_PROJECT_DIR" && [[ -n "$_NORM_PATH" ]]; then
  _BBH_PROJECT_NORM="$_NORM_PATH"
fi

# 0 when the temp-tree default applies to this session: a project root that is
# known and does NOT itself sit under a temp tree. When the project root IS
# temp-rooted, a temp file is project content and the Write|Edit gates do process
# it — the shape this repo's own hook fixtures take (`mktemp -d` checkouts) — so
# the default must not fire. Evaluated once, lazily, on the first matched target,
# because hook::under_temp_root can spend a resolver process.
_BBH_TEMP_DEFAULT=-1
_bbh_temp_default_applies() {
  ((_BBH_TEMP_DEFAULT >= 0)) && return "$_BBH_TEMP_DEFAULT"
  _BBH_TEMP_DEFAULT=1
  if [[ -n "$_BBH_PROJECT_NORM" ]]; then
    hook::under_temp_root "$_BBH_PROJECT_NORM" || _BBH_TEMP_DEFAULT=0
  fi
  return "$_BBH_TEMP_DEFAULT"
}

# Echo the ABSOLUTE spelling of a redirect target, or nothing when it cannot be
# placed. An already-absolute target (POSIX `/x` or the Windows `C:/x` drive
# form, both of which _norm_path folds to one spelling) is returned unchanged; a
# RELATIVE one is joined onto the payload cwd, which is the directory the tool
# call runs in.
#
# A relative target is refused outright when the command carries a directory
# change (_BBH_CWD_MOVED) or the payload names no absolute cwd: in both cases the
# directory the redirect actually resolves against is not the one this guard can
# see, and an exemption granted from the wrong origin is a bypass. That refusal
# is why every existing relative-target assertion still blocks — the payloads
# they are built from carry no `.cwd` at all.
# Physically resolve <absolute path> in _BBH_PHYS, following symlinks. The target
# of a redirect usually does not exist yet, so this walks up to the NEAREST
# EXISTING ancestor, resolves that, and re-appends the components below it —
# those cannot be symlinks, because they do not exist.
#
# A path with NO existing component resolves to itself, and that is sound rather
# than a shortcut: a symlink is a filesystem object, so a path where nothing
# exists holds none, and the lexical answer is already the physical one. Failing
# closed there would refuse on ambient facts about the host (whether `/srv`
# happens to exist) rather than on the command, which is not a property a guard's
# verdict should have.
#
# Returns 1 only when a component exists but the resolver could not read it.
_BBH_PHYS=""
_bbh_physical_path() {
  local p="$1" suffix="" phys
  _BBH_PHYS=""
  while [[ -n "$p" && "$p" != "/" ]]; do
    if [[ -e "$p" || -L "$p" ]]; then
      hook::physical_path_to phys "$p" || return 1
      _BBH_PHYS="${phys%/}$suffix"
      return 0
    fi
    suffix="/${p##*/}$suffix"
    p="${p%/*}"
  done
  _BBH_PHYS="$1"
  return 0
}

# 0 when <lexically-matched target> really lands under the shipped default named
# by $2 ("memory" or "temp"), resolved through symlinks.
#
# WHY THIS EXISTS, and why only the SHIPPED defaults pay for it. The compare
# above is lexical, which the configured-root axis documents as a residual on an
# explicit ground: "an operator naming a root is accepting that root's contents".
# A shipped default has no operator to accept anything, so that ground does not
# carry it — and without this, a symlink under a temp root pointing INTO the
# repository (`/tmp/to-repo -> /home/<user>/repo`) exempts
# `echo <secret> > /tmp/to-repo/tracked.py` while the identical direct path
# blocks. Reported as a P1 on #3727 and reproduced before this was written.
#
# The configured-root axis keeps its documented lexical residual: an operator who
# names a root still accepts that root's contents, which is the ground this
# function exists because the defaults lack.
#
# Cost is confined to the GRANT path. Callers run the lexical test first and only
# reach here when they are about to exempt, so a command that was going to block
# spends no resolver process — and a hook that resolved every target would pay a
# subprocess on the hottest guard in the fleet for nothing.
#
# SCOPE (documented residual): this inherits the axis's case-folding. The target
# arrives from the LOWERCASED segment scan, so on a case-sensitive filesystem a
# path whose real spelling carries capitals does not exist under the folded name,
# the walk stops at the deepest ancestor that does, and a symlink below that
# point is never examined. `/tmp/ToRepo -> <repo>` is therefore still exempt
# where `/tmp/torepo -> <repo>` is not. Closing it needs the target in its
# original case, which this guard does not carry — the whole producer/redirect
# scan runs on the folded stream — so it is recorded here rather than papered
# over. The residual predates this function and is the same one the configured
# roots document; what this function removes is the far commoner all-lowercase
# case, which was live by default.
_bbh_default_confirmed() {
  local target="$1" phys
  _bbh_physical_path "$target" || return 1
  phys="${_BBH_PHYS,,}"
  # hook::under_temp_root resolves its own candidates, so both sides are physical
  # here and a symlinked temp root (macOS /tmp) still matches.
  hook::under_temp_root "$phys"
}

_scratch_abs_target() {
  local t="$1"
  case "$t" in
  /* | [A-Za-z]:/* | [A-Za-z]:)
    printf '%s' "$t"
    return 0
    ;;
  *) ;; # relative — placeable only against a cwd this guard can trust
  esac
  ((_BBH_CWD_MOVED)) && return 1
  # The joined path is case-folded by the caller, along with the already-absolute
  # spelling, so a cwd carrying capitals still matches the lowercased roots.
  case "$HOOK_CWD" in
  /* | [A-Za-z]:/*) printf '%s/%s' "${HOOK_CWD%/}" "$t" ;;
  *) return 1 ;;
  esac
}

# 0 when the target <$1> lies strictly under a configured scratch root or a
# shipped default. $2 is 1 when quoting or an escape produced that text, $3 when
# the parse could not resolve it at all. Called only after a segment has already
# matched a producer + real-file redirect, so it adds no work to the per-call hot
# path, and it returns on the first line when no root is configured.
scratch_target_exempt() {
  local target="$1" tgt_quoted="$2" tgt_opaque="$3" norm_target root roots abs
  # Nothing to compare against: no configured root AND no usable project root,
  # which is the only state in which the shipped default cannot fire either.
  # Keeps the unconfigured, project-less path returning on the first line as it
  # always did.
  [[ -n "$_SCRATCH_ROOTS" || -n "$_BBH_PROJECT_NORM" ]] || return 1
  # FAIL CLOSED on an operand whose pathname is not dependably what reaches the
  # compare, before anything else. All three tests are keyed on the OPERAND, from
  # the provenance the shared parse carries with it — not on the raw command.
  #
  #   OPAQUE  — the parse could not resolve the operand at all (a quote that
  #             never closed, an operand a control operator cut short). The
  #             pathname is not recoverable, so no exemption may be granted.
  #   QUOTED  — quoting or a backslash escape produced the text. It IS recoverable
  #             here, and this axis still refuses it: the shipped floor since
  #             0.25.0 is that such an operand is never scratch-exempt, and
  #             keeping it holds the grant surface to targets proven bare.
  #             `> "/tmp/scratch/a;/../../etc/passwd"` is ONE pathname to bash and
  #             exempting its `/tmp/scratch/a` prefix is precisely the one-token
  #             bypass the `/dev/null` precedent warns about.
  #   `\`     — a residual belt. A raw backslash survives only inside a quoted
  #             span, which the test above already refused, and _norm_path folds
  #             `\` to `/`, so refuse rather than compare a path that folding
  #             invented.
  #
  # 0.25.0 could do none of this and read `${COMMAND#*>}` instead — any quote or
  # backslash after the first `>` CHARACTER, anywhere in the command. That was
  # blunt in two directions (#2236): it was not segment-scoped, so a quote in an
  # unrelated later segment cost an earlier unambiguous write its exemption, and
  # it was not keyed on the redirect OPERATOR, so a `>` inside quoted content
  # started the scanned tail early. Both are gone; both narrowings GRANT the
  # exemption where it was refused, and both land only on a target the parse
  # proves was bare — `echo x > /tmp/scratch/f && grep foo "notes.txt"` and
  # `echo "a > b" > /tmp/scratch/f` are exempt again.
  ((tgt_opaque)) && return 1
  ((tgt_quoted)) && return 1
  [[ "$target" == *\\* ]] && return 1
  # Place the target absolutely before normalizing. Until #3719 this axis refused
  # every relative target outright; it now resolves one against the payload cwd
  # when — and only when — that cwd is the directory the redirect demonstrably
  # runs in. _scratch_abs_target owns that judgement and still refuses everything
  # it cannot place, so the fail-closed set only ever shrinks by targets proven
  # placeable.
  abs=$(_scratch_abs_target "$target") || return 1
  [[ -n "$abs" ]] || return 1
  _norm_path "$abs" || return 1
  [[ -n "$_NORM_PATH" ]] || return 1
  # Case-folded once here rather than at each comparison: the configured roots are
  # lowercased below, the memory-tier default is lowercased at its assignment, and
  # a target that arrived absolute came off the lowercased command stream already.
  norm_target="${_NORM_PATH,,}"
  # THE SHIPPED DEFAULT — the host temp trees, including the harness scratchpad,
  # once this session is one the default applies to.
  #
  # LEXICALLY matched first and then CONFIRMED through symlink resolution, so a
  # lexical near-miss costs no resolver process and a lexical match cannot exempt
  # a path that really lands elsewhere. See _bbh_default_confirmed for why the
  # shipped default carries this and the configured roots keep their documented
  # lexical residual.
  if [[ -n "$_BBH_PROJECT_NORM" ]] && _bbh_temp_default_applies &&
    hook::under_temp_root "$norm_target"; then
    _bbh_default_confirmed "$norm_target" && return 0
  fi
  roots="$_SCRATCH_ROOTS"
  while [[ -n "$roots" ]]; do
    root="${roots%%,*}"
    if [[ "$root" == "$roots" ]]; then roots=""; else roots="${roots#*,}"; fi
    root="${root#"${root%%[![:space:]]*}"}"
    root="${root%"${root##*[![:space:]]}"}"
    [[ -n "$root" ]] || continue
    _norm_path "${root,,}" || continue
    # `/` normalizes to the empty string; exempting it would exempt every path.
    [[ -n "$_NORM_PATH" ]] || continue
    # Component-boundary containment on two normalized paths — the trailing `/`
    # is what makes this a component compare and not a string prefix.
    [[ "$norm_target" == "$_NORM_PATH"/* ]] && return 0
  done
  return 1
}

# --- Same-command staged-write move (#2731) ----------------------------------
#
# Narrow detector for `<producer> > <tmp> && mv|cp <tmp> <dest>` when the
# producer is unmodeled (`jq`, `curl`, …): the redirect alone is allowed by the
# producer-scoped lanes above, and the later move places authored content into
# a repo path while skipping Write|Edit-matched content guards. Path-identity
# with a prior effective stdout target is what keeps ordinary renames and
# data-pipeline moves unblocked (never-hard-block tier).
#
# SCOPE (documented residual): same command string only — cross-tool-call
# staging (write in one Bash call, move in another), variable-carried paths
# (`t=/tmp/x; jq … > "$t"; mv "$t" dest`), and other movers (`install`,
# `rsync`, `dd`) are not seen. Path identity runs on the lowercased segment
# model, so on a case-sensitive filesystem distinct paths that differ only by
# case can collide — matching the rest of this guard's case-folded command-word
# scan; preserving original operand case would need a second, case-preserved
# collection pass.
# A broad any-redirect-into-repo lane was assessed and rejected (blocks
# legitimate data-processing redirects).
#
# Destination outside configured scratch roots: with no roots configured
# (shipped default), every destination is outside, so any matched staged move
# blocks. A dest under a configured scratch root is exempt — still staging.

# 0 when $1 and $2 name the same path under the same lexical rules as the
# scratch-root axis. Absolute paths go through _norm_path; relative or
# unnormalizable paths compare as separator-folded strings. An empty operand
# never matches (cannot establish identity → cannot block), and an unresolvable
# redirect target is never recorded as a prior staging path in the first place.
paths_identical() {
  local a="$1" b="$2" na nb
  [[ -n "$a" && -n "$b" ]] || return 1
  if _norm_path "$a"; then
    na="$_NORM_PATH"
    if _norm_path "$b"; then
      nb="$_NORM_PATH"
      [[ -n "$na" && -n "$nb" && "$na" == "$nb" ]] && return 0
      return 1
    fi
    return 1
  fi
  # Both relative / unexpanded: identity is literal after separator fold.
  a="${a//\\//}"
  b="${b//\\//}"
  [[ "$a" == "$b" ]]
}

# Parse segment $1 (offset) / $2 (length) into MOVE_SOURCES (array), MOVE_DEST
# and MOVE_DEST_Q (the destination's quoting provenance).
# Supports GNU `-t DIR` / `--target-directory=DIR` (dest in the option; remaining
# non-options are sources) and the common `sources… dest` form. Returns 1 when
# the segment is not an mv|cp simple command or operands are incomplete.
MOVE_SOURCES=()
MOVE_DEST=""
MOVE_DEST_Q=0
parse_mv_cp_operands() {
  local off="$1" len="$2" k tok expect_t=0
  local -a srcs=() srcq=()
  MOVE_SOURCES=()
  MOVE_DEST=""
  MOVE_DEST_Q=0
  # The same prefix peel the producer lane uses, so `env mv /tmp/x dest` still
  # classifies.
  peel_command_word "$off" "$len" || return 1
  k=$((PEELED_IDX - off))
  case "${SEG_W[off + k]}" in
  mv | cp | mv.exe | cp.exe) ;;
  *) return 1 ;;
  esac
  ((k++))
  while ((k < len)); do
    tok="${SEG_W[off + k]}"
    if ((expect_t)); then
      MOVE_DEST="$tok"
      MOVE_DEST_Q="${SEG_WQ[off + k]}"
      expect_t=0
      ((k++))
      continue
    fi
    case "$tok" in
    --)
      ((k++))
      while ((k < len)); do
        srcs+=("${SEG_W[off + k]}")
        srcq+=("${SEG_WQ[off + k]}")
        ((k++))
      done
      break
      ;;
    --target-directory=* | -t=*)
      MOVE_DEST="${tok#*=}"
      MOVE_DEST_Q="${SEG_WQ[off + k]}"
      ;;
    -t | --target-directory)
      expect_t=1
      ;;
    -*) ;; # short/long options with no separate dest operand (including clustered
    # `-fv`). Value-taking options other than `-t` are not modeled — residual.
    *)
      srcs+=("$tok")
      srcq+=("${SEG_WQ[off + k]}")
      ;;
    esac
    ((k++))
  done
  ((expect_t)) && return 1 # `-t` without its directory operand
  if [[ -n "$MOVE_DEST" ]]; then
    ((${#srcs[@]} >= 1)) || return 1
    MOVE_SOURCES=("${srcs[@]}")
    return 0
  fi
  # Classic form (including after `--`): last operand is dest, earlier are sources.
  ((${#srcs[@]} >= 2)) || return 1
  MOVE_DEST="${srcs[-1]}"
  MOVE_DEST_Q="${srcq[-1]}"
  unset 'srcs[-1]'
  ((${#srcs[@]} >= 1)) || return 1
  MOVE_SOURCES=("${srcs[@]}")
  return 0
}

# 0 when a prior effective stdout target is reused as an mv|cp SOURCE with a
# destination that is not scratch-exempt.
staged_write_move_bypass() {
  local s off len src seen="" prior rest dq
  for ((s = 0; s < SEG_COUNT; s++)); do
    off="${SEG_WOFF[s]}"
    len="${SEG_WLEN[s]}"
    if parse_mv_cp_operands "$off" "$len"; then
      # A destination whose written text is not the path that gets written
      # cannot prove scratch containment, so it reads as outside scratch (fail
      # closed toward blocking a staged move).
      dq=0
      ((MOVE_DEST_Q)) && dq=1
      if ! scratch_target_exempt "$MOVE_DEST" "$dq" 0; then
        for src in "${MOVE_SOURCES[@]}"; do
          [[ -n "$src" ]] || continue
          rest="$seen"
          while [[ -n "$rest" ]]; do
            prior="${rest%%$'\n'*}"
            if [[ "$prior" == "$rest" ]]; then rest=""; else rest="${rest#*$'\n'}"; fi
            [[ -n "$prior" ]] || continue
            if paths_identical "$src" "$prior"; then
              return 0
            fi
          done
        done
      fi
    fi
    # Record this segment's effective stdout target for later segments.
    ((SEG_TGT_SET[s])) || continue
    # An unrecoverable target cannot establish identity.
    ((SEG_TGT_OPQ[s])) && continue
    [[ -n "${SEG_TGT[s]}" ]] || continue
    # Discard is never a staging file worth tracking.
    [[ "${SEG_TGT[s]}" == "/dev/null" ]] && continue
    seen+="${SEG_TGT[s]}"$'\n'
  done
  return 1
}

# 0 when segment $1's stdout write is exempt: the DISCARD, or a scratch root.
# Both are decided on the EFFECTIVE target, so `> /allowed/tmp/f > real.txt`
# still blocks.
target_exempt() {
  devnull_target_exempt "$1" && return 0
  scratch_target_exempt "${SEG_TGT[$1]}" "${SEG_TGT_Q[$1]}" "${SEG_TGT_OPQ[$1]}"
}

# `cat >` with no input file is content authoring redirected into a file — the
# heredoc/typed-content Write bypass. Per segment, so the /dev/null DISCARD
# exemption cannot leak across a compound command: `cat > /dev/null &&
# cat > real.txt` still blocks on its second segment.
#
# The lane fires when `cat` is the LAST word bash would still see between the
# command word and the redirection — an operand after it (`cat a.txt > c.txt`)
# makes the command a copy of that file, not stdin authoring. A wholly quoted
# operand does NOT clear the lane: that is the shipped floor (`cat "a" > f`
# blocks), kept as it is rather than widened here. `cat1>file` is an unrelated
# binary with an ordinary redirect and never matches, because `cat1` is one word.
cat_redirect_bypass() {
  local s off len k
  for ((s = 0; s < SEG_COUNT; s++)); do
    # No stdout FILE target means no file write: `cat 1>&2` duplicates stdout
    # onto stderr and `cat 1>&-` closes it, and neither is a write.
    ((SEG_TGT_SET[s])) || continue
    off="${SEG_WOFF[s]}"
    len="${SEG_WLEN[s]}"
    for ((k = len - 1; k >= 0; k--)); do
      ((SEG_WQ[off + k] == 2)) && continue
      [[ "${SEG_W[off + k]}" == cat ]] || continue 2
      break
    done
    ((k >= 0)) || continue
    target_exempt "$s" && continue
    return 0
  done
  return 1
}

# 0 when the producer redirected into a real file is echo/printf authoring
# content. The command word is the one bash would run (see peel_command_word),
# never an `echo` mention among a segment's arguments.
producer_redirect_bypass() {
  local s head
  for ((s = 0; s < SEG_COUNT; s++)); do
    ((SEG_TGT_SET[s])) || continue
    peel_command_word "${SEG_WOFF[s]}" "${SEG_WLEN[s]}" || continue
    head="${SEG_W[PEELED_IDX]}"
    # A command word differing from a producer name only by embedded newlines is
    # not a runnable command, so reading it as that producer costs nothing and
    # keeps a quote-spliced spelling (`ec"<newline>"ho x > f`) from passing as
    # some other program.
    head="${head//$'\n'/}"
    [[ "$head" == echo || "$head" == printf ]] || continue
    target_exempt "$s" && continue
    return 0
  done
  return 1
}

# 0 when a segment invokes an inline python program: the python FAMILY as a
# command word — `py`/`python`/`pypy` with an optional version suffix, optionally
# path-qualified and `.exe`-suffixed, so `notpython3`, `mypy`, `spy`, `happy` and
# `pytest` stay inert — followed IMMEDIATELY by `-c` (inline code) or `-` (the
# program read from stdin, the heredoc form). No gap is allowed between the two
# except `py -3`, the Windows launcher's version selector, which cannot be a
# script path; admitting an arbitrary option-shaped word there is what would let
# a SCRIPT path through as one, so a script or module run (`python3 build.py`,
# `python3 -m tool …`) that merely touches an `open(`-like path is not matched.
py_inline_invocation() {
  local s off len k w nxt
  for ((s = 0; s < SEG_COUNT; s++)); do
    off="${SEG_WOFF[s]}"
    len="${SEG_WLEN[s]}"
    for ((k = 0; k + 1 < len; k++)); do
      w="${SEG_W[off + k]##*/}"
      [[ "$w" =~ ^(pypy|python|py)[0-9]*(\.[0-9]+)*(\.exe)?$ ]] || continue
      nxt="${SEG_W[off + k + 1]}"
      if [[ "$nxt" =~ ^-[0-9]+(\.[0-9]+)?$ ]] && ((k + 2 < len)); then
        nxt="${SEG_W[off + k + 2]}"
      fi
      [[ "$nxt" == "-c" || "$nxt" == "-" ]] && return 0
    done
  done
  return 1
}

# The scope this guard actually has, stated where a reader meets it. Without it
# the block reads as "shell file writes are blocked" and is over-trusted in both
# directions: an agent contorts around a restriction a script file does not
# have, and a human credits the guard with coverage it never claimed. The guard
# is a speed bump against specific accidental write-workaround forms in one
# command string, not a boundary — and it is deliberately producer-scoped, so
# ordinary data-processing redirects (`sort f > out`, `curl … > page.html`) and
# other unmodeled Bash write utilities (POSIX `tee`, inline `node -e`, …) are
# allowed by design too, not only writes inside an invoked script.
# These notes state the ENFORCED surface to the operator, so they are part of the
# detector's contract, not commentary: understating it invites the "guard says it
# cannot see this" contortion the paragraph above describes, and overstating it is
# the false-assurance failure. #2217 widened the python lane from the literal
# `python3 -c` to the interpreter family plus a stdin heredoc, and left both notes
# saying `inline python3 -c only` — materially wrong about a safety guard's own
# reach. Restated at the shipped width, with the residuals named at theirs.
_BYPASS_SCOPE_NOTE_BASH="Scope: only this command string is inspected — known shell \
file-write forms plus inline python code (python/python3/py/pypy with -c, or a \
program read from stdin as python3 - <<PY) only, plus a same-command staged \
move (effective redirect target reused as mv|cp source with dest outside \
configured scratch roots). POSIX tee pipe writes, other inline-interpreter \
writes (e.g. node -e, sed -i), a stdin heredoc with no - argument (python3 <<PY), \
writes inside an invoked script file or a program's own opaque code, redirects \
produced by another program that are not later mv|cp-moved in the same command, \
cross-tool-call staging, variable-carried staging paths, and other movers \
(install, rsync, dd), are not seen."
_BYPASS_SCOPE_NOTE_PWSH="Scope: only this command string is inspected — known PowerShell \
file-write cmdlets and content-producer redirects (including Tee-Object and the \
tee alias) plus inline python code (python/python3/py/pypy with -c) only. Other \
inline-interpreter writes (e.g. node -e), writes inside an invoked script file or \
a program's own opaque code, and redirects produced by another program, are not \
seen."

block_bypass() {
  local form="$1" reason="$2"
  # Operator levers live on stderr. systemMessage is an exit-0 JSON field
  # (docs/conventions/hook-observability); Claude Code discards it on exit 2.
  # Keep the same text on systemMessage for any host that does parse it.
  local operator_msg="guardrails block-hook-bypass blocked a shell file-write. The blocked agent cannot toggle this guard (the switch is not actionable by the blocked agent). Narrower levers, in order: (1) block_hook_bypass_scratch_roots for a target-scoped scratch exemption; (2) session-scoped claude --settings; (3) user-global block_hook_bypass_enabled via /plugin configure — that option is user-scoped and persists in every repository where guardrails is enabled. Re-enable it when the bypass is no longer needed."
  echo "BLOCKED: $reason" >&2
  echo "Use the Write or Edit tool instead of a shell file-write workaround." >&2
  echo "If Write or Edit is refused for a path in the main checkout (isolated session / worktree), write under a directory listed in block_hook_bypass_scratch_roots, or ask the operator for a session-scoped disable via claude --settings. The user-global block_hook_bypass_enabled switch is last resort — it persists across every repository." >&2
  echo "$operator_msg" >&2
  if [[ "$TOOL_NAME" == "PowerShell" ]]; then
    echo "$_BYPASS_SCOPE_NOTE_PWSH" >&2
  else
    echo "$_BYPASS_SCOPE_NOTE_BASH" >&2
  fi
  hook::emit_channels PreToolUse "" "$operator_msg"
  emit_tel "blocked" "$form"
  exit 2
}

# PowerShell tool: the Bash strip / producer scan below does not model the
# PowerShell write surface. Detect PowerShell file-write forms (Set-Content /
# Add-Content / Out-File / Tee-Object, or a content-producer `>`/`>>` redirect)
# and skip the Bash-specific scans. SCOPE: this closes the write-GATE bypass;
# secret-pattern and hardcoded-path CONTENT scanning of PowerShell writes stays
# on the Write|Edit-matched guards (deferred to A2b).
#
# The PowerShell classifier (~41 KB) is sourced only on this lane (#2663) —
# every ps:: call lives inside this branch, and Bash tool calls must not pay
# the parse tax. Resolved under the plugin root (CC sets CLAUDE_PLUGIN_ROOT;
# the BASH_SOURCE fallback keeps the contract tests working when it is unset).
if [[ "$TOOL_NAME" == "PowerShell" ]]; then
  PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$_HOOK_SELF/.." && pwd)}"
  # shellcheck source=../lib/powershell/ps-command.sh
  source "$PLUGIN_ROOT/lib/powershell/ps-command.sh"
  if ps::write_bypass "$COMMAND"; then
    block_bypass "powershell-write" "PowerShell file-write cmdlet/redirect bypasses Write/Edit hooks"
  fi
  # Interpreter-producer writes (`python3 -c "<inline code that writes>"`) route
  # around Write/Edit whichever tool launches them, and ps::write_bypass models only
  # PowerShell cmdlet/redirect forms. On the BASH tool the precise `python3 -c` scan
  # (further below) is reliable: the shared parse is genuinely quote-aware, and Bash
  # has no `<# #>` block comments or `&{}` script blocks. PowerShell is NOT
  # faithfully bash-tokenizable, and successive review rounds proved that a precise
  # regex/normalize stack cannot keep up — each round exposed a fresh evasion
  # (path-qualified target, `&{python3}` script block, quoted-`#` comment
  # truncation, with block comments and `-ArgumentList` arg-splitting still open).
  # So this lane CONSCIOUSLY DIVERGES from the Bash lane (justified above) and
  # follows the repo's SINK DOCTRINE (ps::classify_git_command / ps::might_invoke_git):
  # do not trust a precise negative on a mangled command — block on the
  # mangle-resistant CO-OCCURRENCE of
  #   (a) a write INDICATOR in the raw command (_py_write — the tokens live in the
  #       quoted `-c` payload, so the scan is raw, exactly as the Bash lane), AND
  #   (b) a python interpreter TOKEN plus a `-c` inline-code flag both present
  #       (ps::might_write_via_python3, quote-INTACT + backtick-recovered) — where a
  #       COMPUTED `-c` (`python3 ('-'+'c') …`) is caught by fail-closing on a
  #       non-tokenizable arg construct when no literal `-c` is present.
  # `-c` is REQUIRED and position-independent, so a legitimate script/module run
  # (`python3 build.py`, `python3 -m tool …`) that merely touches an `open(`-like
  # path is NOT blocked — only inline-code writes are. ACCEPTED OVER-BLOCK (the
  # fail-closed choice the user approved for this lane): a command that only MENTIONS
  # `python3 … -c` + a write indicator in prose, a line/block comment, or a quoted
  # string now blocks; here-string mentions stay inert (blanked first, like the git
  # lane).
  #
  # The interpreter TOKEN is the python FAMILY in both lanes (#2217): `python -c`,
  # `py -c`, `py3 -c`, `python2 -c` and `python3.11 -c` are the same write as
  # `python3 -c`. Heredoc stdin is a Bash-tool construct covered in the Bash lane
  # (see the reopening note there); it stays out of scope here because PowerShell
  # has no heredoc.
  ps::blank_herestrings "$COMMAND"
  if py_write_indicator "$COMMAND_LC" && ps::might_write_via_python3 "$PS_BLANKED"; then
    block_bypass "python-write" "python inline-code file write bypasses Write/Edit hooks"
  fi
  emit_tel "ok" ""
  exit 0
fi

# Tokenize once into simple-command segments; every lane below reads that model
# (see collect_segment). Words arrive lowercased, which is what makes each lane's
# command-word test case-insensitive.
hook::bash_parse_segments "$COMMAND" collect_segment

# SCOPE (documented residual): Bash lane only. POSIX `tee` / `tee -a` pipe-to-file
# writes are NOT caught — the guard models cat/echo/printf redirects and
# python3 -c, not every POSIX write utility. The PowerShell lane blocks
# Tee-Object and its `tee` alias via ps::write_bypass. Catching POSIX tee needs a
# separate Bash lane; covered by an accepted-floor test.
#
# cat > file (allow cat without redirect, and allow a `> /dev/null` discard).
if cat_redirect_bypass; then
  block_bypass "cat-redirect" "cat > file write bypasses Write/Edit hooks"
fi

# echo/printf ... > file — only when the echo/printf IS the producer redirected
# into a real file (stdout-to-real-file only; not stderr/fd redirects, /dev/null,
# a co-located but unrelated echo, or tokens inside a quoted argument).
if producer_redirect_bypass; then
  block_bypass "echo-redirect" "echo/printf > file write bypasses Write/Edit hooks"
fi

# Same-command staged write: unmodeled producer redirects into a path that a
# later mv|cp in THIS command reuses as SOURCE toward a non-scratch dest
# (#2731). Ordinary renames (no prior redirect of that source) stay allowed.
if staged_write_move_bypass; then
  block_bypass "staged-write-move" \
    "same-command staged write (redirect target reused as mv|cp source) bypasses Write/Edit hooks"
fi

# SCOPE (documented residual): inline writes via interpreters other than
# python3 -c — `node -e`, `perl -e`, `ruby -e`, `sed -i`, `dd of=`, `awk >`,
# and similar — are NOT caught. Only the python3 -c lane is modeled; each other
# interpreter has its own spelling and write surface. Covered by accepted-floor
# tests.
#
# Inline python code with file-write indicators. The INVOCATION is decided on the
# PARSED segments (see py_inline_invocation), so prose or commit text merely
# mentioning it is one quoted argv word and never a command word; the write
# INDICATORS are scanned on the RAW command (COMMAND_LC), because they
# legitimately live inside the quoted `-c` payload or the heredoc body, neither
# of which is argv.
#
# REOPENED ACCEPTED RESIDUAL (#2217 / AD-12). A stdin heredoc — `python3 - <<PY
# … PY`, no `-c` — was documented as uncovered and accepted. It is covered now,
# on new reachability evidence: this repo's own session record shows an agent
# reaching for exactly that form to patch a file
# (`.work/handoffs/20260809T082720Z-handoff-post-2008-followups.md:211`,
# `python - <<'PY'`), and widening the `-c` arm raises the pressure toward it,
# since a refused `python -c` write reroutes most naturally to the heredoc.
#
# The `-` (read the program from stdin) is what makes this an INLINE write: the
# code is in the command string, not in an opaque script file. The parse gives
# the heredoc body to stdin rather than to argv, so `python3 -` is the whole
# invocation and the body's write indicators are still visible in COMMAND_LC.
#
# NARROWED RESIDUAL, restated at its real width: `python3 <<PY … PY` (stdin with
# NO `-` argument) stays uncovered. Matching a bare trailing interpreter word
# would flip `echo "pathlib" | python3` and `cat s.py | python3` to blocked —
# verified rc=0 both before and after — so the exemption those keep costs this
# one spelling.
if py_inline_invocation && py_write_indicator "$COMMAND_LC"; then
  block_bypass "python-write" "python inline-code file write bypasses Write/Edit hooks"
fi

emit_tel "ok" ""
exit 0
