# shellcheck shell=bash
# PowerShell command classification for guardrails git/commit/write guards.
#
# WHY THIS EXISTS: the git/commit/write guards parse the tool command with a
# Bash-grammar-faithful tokenizer (hook-utils.sh). Claude Code's opt-in
# PowerShell tool (CLAUDE_CODE_USE_POWERSHELL_TOOL=1) surfaces its command in the
# SAME `tool_input.command` field but with PowerShell grammar, so a naive widen
# of the PreToolUse matcher to `Bash|PowerShell` would feed PowerShell text to a
# Bash tokenizer. This library bridges that gap with a CORE, fail-closed scope;
# faithful parsing of the full PowerShell grammar (here-strings beyond the
# canonical commit form, backticks, `--%`, subexpressions) is a deferred
# follow-up.
#
# THE BAR IS BASH-PARITY, NOT AIRTIGHT. These guards are accidental-destruction
# friction, not a boundary against deliberate evasion — and the Bash guard this
# extends does not stop deliberate evasion either. The PowerShell surface is held
# to what the Bash guard already sees through, no higher: the `sh -c`/`bash -c`
# see-through has PS analogs in `pwsh`/`powershell -Command` and the nested-shell
# launchers; the `nice`/`sudo`/`env` launcher transparency has its analog in
# `Start-Process`. Vectors the Bash guard ALSO misses are shared Bash+PS residuals,
# documented, not bugs: a command word supplied entirely by an unexpanded variable
# (`& $tool commit`, `iex $var`); deep nested-shell / `cmd /c` quoting; .NET
# reflection beyond the common [IO.File]/StreamWriter writes; and any shell
# variable / command substitution (never evaluated, the same residual as Bash).
#
# STRATEGY (git/commit guards): reduce a PowerShell command to a form the Bash
# tokenizer handles faithfully, or fail closed.
#   1. Blank properly-delimited here-strings (@'...'@ / @"..."@) to an inert
#      placeholder. This both neutralizes the one construct the canonical commit
#      form relies on AND makes the canonical form parse naturally: the
#      here-string-pipe equivalent of `git commit -F -`
#          @'
#          <subject>
#          '@ | git commit -F -
#      reduces to `<placeholder> | git commit -F -`, which the Bash parser reads
#      as a pipeline whose second segment is `git commit -F -` (stdin form) —
#      allowed exactly as the Bash canonical form is.
#   2. On the here-string-blanked, quote-stripped text, detect the PowerShell
#      constructs the Bash tokenizer cannot faithfully handle (backtick, `--%`,
#      and `(`/`)`/`{`/`}` grouping) and any unbalanced here-string. Quoted spans
#      are stripped first so a construct that lives inside commit-message text
#      does not count.
#   3. If such a construct is present, the command is not faithfully tokenizable,
#      so it is BLOCKED fail-closed UNLESS it is provably git-free. Crucially the
#      allow decision is NOT a negative `commit`/`push` shape match on the mangled
#      scan — the very construct that defeats the tokenizer also mangles that scan
#      (backtick splits `com`+`mit`, quote-stripping erases `'commit'`), so a
#      negative match is not evidence of safety (the #740/#903 fail-open class).
#      Instead ps::might_invoke_git asks the mangle-resistant question "could this
#      reach git at all?" — backticks recovered, scan quote-INTACT (except a
#      literal in comparison-operand position, which is data; see
#      ps::might_invoke_git), plus dynamic invocation (iex / call / dot-source) —
#      and blocks unless the answer is no.
#      Otherwise the reduced command is Bash-tokenizer-faithful and handed to the
#      existing parser.
#
# OVER-BLOCK, NEVER UNDER-BLOCK is the invariant. For the blanker: an ambiguous
# here-string extent is treated as unbalanced (unsafe) rather than blanked, so a
# trailing `| git commit --no-verify` can never be swallowed into the inert
# placeholder and escape detection. For the sink: an unparsable command that
# might reach git is blocked even at the cost of over-blocking an exotic non-git
# git-touching command (e.g. `git log | ForEach { … }`).
#
# RESIDUAL (documented, deferred to A2b): a git invocation whose command word
# comes entirely from an unexpanded variable with NO structural construct present
# (`& $tool commit`, where `$tool` holds `git`) takes the parser path and is not
# caught — the same "variable / command substitution is not evaluated" residual
# the Bash guards carry. Faithful PowerShell tokenization is the A2b follow-up.

[[ -n "${_GUARDRAILS_PS_COMMAND_LOADED:-}" ]] && return 0
_GUARDRAILS_PS_COMMAND_LOADED=1

# Inert bareword substituted for a blanked here-string body. It occupies a single
# argv word in the reduced command so the Bash tokenizer treats a blanked
# here-string exactly as the option value or pipeline input it was.
readonly PS_HERESTRING_PLACEHOLDER="__GUARDRAILS_PS_HERESTRING__"

# Set by ps::blank_herestrings.
PS_BLANKED=""
PS_HERESTRING_UNBALANCED=0
# The quote character of the UNBALANCED opener (`'` or `"`), empty when the
# command carried no unbalanced here-string. PowerShell pairs `@'` with `'@` and
# `@"` with `"@`, so the remediation line can only name the right terminator if
# it knows which opener was left hanging — naming `'@` for a `@"` body sends the
# operator to a terminator PowerShell will not accept.
PS_HERESTRING_QUOTE=""
# 1 when a properly-delimited EXPANDABLE here-string (`@"` … `"@`) was blanked out
# of the command. A verbatim `@'` … `'@` body is inert text, but an expandable
# body is evaluated where it is written, so a `$( … )` inside it is a COMMAND
# POSITION that the placeholder hides. Read by ps::classify_git_command, which
# will not accept a git-freedom proof taken over text with that body removed.
PS_HERESTRING_EXPANDABLE=0
# 1 when a DROPPED expandable here-string body line carried the literal `$(`.
# Inside an expandable body the only construct that reaches a command position is
# `$( … )`: `${name}` is a variable reference, `@( … )` is not expanded there, and
# a backtick before `$` makes the `$` literal. Gating on the two characters `$(`
# therefore OVER-approximates (it also matches the backtick-escaped spelling),
# which is the fail-closed direction and the one this library takes rather than
# modeling escapes inside text it has already decided it cannot parse. Read by
# ps::classify_git_command, where it is the trigger of last resort.
PS_HERESTRING_EXPANDABLE_SUBEXPR=0
# 1 when the here-string reduction cannot be trusted: the lines it dropped may be
# live commands, or the text carries a CR this library does not split on. The
# first shape that tripped it is in PS_REDUCTION_UNTRUSTED_REASON. Reasons, none
# with an allow token:
#   herestring-comment-char     — `#` on a confirmed opener prefix
#   herestring-opener-untrusted — `'`, `"`, `\`, or backtick on that prefix
#   herestring-comment-span     — a `<#` appears earlier in the command
#   herestring-orphan-closer    — `'@` / `"@` at column zero with no confirmed opener
#   bare-cr                     — a CR not followed by LF
#
# The comment-char reason, which the others generalize: a line this library
# CONFIRMED as a here-string opener also carries a `#` anywhere before the
# two-character opener suffix. PowerShell's own tokenizer reads `#` outside a
# quoted string as the start of a line comment, so the `@"` of
# `Write-Output x # @"` is comment TEXT and opens nothing: the next line is a
# live command. This library reads the same line as an opener and DROPS that next
# line as here-string body, which is how `Write-Output x # @"` /
# `git push --force` / `"@ fine"` reaches the parser with the git command already
# gone.
#
# The test is a plain substring test on the RAW line. It does not decide whether
# the `#` is a comment, sits inside a string, or is glued to a token, and it
# pairs no quotes: pairing is what this defect class keeps defeating, and a
# pairing walk that is wrong in one direction ALLOWS a command. So the shape is
# refused whole. ACCEPTED OVER-BLOCK: `Write-Output "#1" @"` and `a#b @"` open a
# real here-string in PowerShell and are refused here anyway.
#
# THESE SHAPES HAVE NO ALLOW TOKEN, and cannot be given one. Every token-granted
# sink round spends the caller's shared `_ps_sink_attempts` budget, so a sixth
# grantable trigger pushes a command that settles in four rounds past the cap,
# where block-dangerous-git.sh refuses as budget-exhausted without ever reading
# the destructive sibling. The refusal is therefore unconditional in every
# reader, and names the shape rather than the budget.
#
# Read by ps::classify_git_command (which turns it into a sink trigger named for
# the reason), by ps::write_bypass, and by each guard that classifies a
# PowerShell command: block-dangerous-git.sh and block-no-verify.sh refuse on it
# at the top of their sink loops so the shape never enters a token-granted round,
# and the two commit guards refuse on it instead of deferring.
PS_REDUCTION_UNTRUSTED=0
PS_REDUCTION_UNTRUSTED_REASON=""
# 1 when the last ps::_walk_quoted_spans_to pass crossed a DOUBLE-quote opener,
# i.e. the walked text carries an expandable string. Written by the walk and read
# by its IMMEDIATE caller; any later walk overwrites it.
PS_QUOTED_SPAN_SAW_EXPANDABLE=0
# Set by ps::classify_git_command when a command routes to the fail-closed sink:
# which of the five triggers fired (`herestring-unbalanced`, `special-construct`,
# `dynamic-invocation`, `launcher`, `herestring-subexpr`), empty otherwise. Read
# by the block messages
# (so they name the construct actually present) and by the callers' telemetry (so
# the five sink shapes are distinguishable in aggregate rather than collapsed into
# one `powershell-unparsable` token that hides which one over-blocks).
# `herestring-comment-char` and the other PS_REDUCTION_UNTRUSTED reasons are
# extra trigger names, reported the same way but carrying NO allow token.
PS_SINK_TRIGGER=""
# Set by ps::classify_git_command — the command the caller should parse. Read by
# the sourcing guard, not within this library.
# shellcheck disable=SC2034
PS_SAFE_COMMAND=""

# --- fork-free primitives -----------------------------------------------------
#
# Six guards load this file on the hot path of every PowerShell tool call, and
# on Windows Git Bash a command substitution is one process creation while an
# external command in a pipeline is two more. So nothing here reaches a result
# through `$(…)` or `printf | sed`: a helper whose answer is a string takes the
# caller's variable NAME and assigns it with `printf -v` (the `_to` convention
# lib/hook-utils.sh uses), and the substitutions below are done in bash.
#
# TWO RULES MAKE A `_to` HELPER A DROP-IN FOR THE `$(…)` IT REPLACES. It ends by
# chomping the trailing newline run a capture would have eaten (ps::_chomp_to).
# And its own locals are name-prefixed wherever a caller might pass one of them
# as the out-parameter — `printf -v` would otherwise assign the callee's local
# and leave the caller's variable untouched, which is a silent wrong answer
# rather than an error.

# ps::_chomp_to <varname> <text>
#
# TEXT without the trailing newline run `$(…)` would have removed.
#
# A trailing CRLF goes WHOLE, not just its LF. Measured on the Windows Git Bash
# these guards run under: `$(printf 'a\r\n')` is `a`, `$(printf 'a\r\r\n')` is
# `a` plus one CR, and an INTERIOR CRLF survives (`$(printf 'a\r\nb')` keeps
# both bytes). A helper that dropped only the LF would hand its caller a
# trailing `\r` the captured form never had — and PS_SAFE_COMMAND goes on to a
# Bash tokenizer, where that CR joins the final token.
ps::_chomp_to() {
  local __ch_s="$2"
  while [[ "$__ch_s" == *$'\n' ]]; do
    __ch_s="${__ch_s%$'\n'}"
    __ch_s="${__ch_s%$'\r'}"
  done
  printf -v "$1" '%s' "$__ch_s"
}

# First untrusted reason wins so attribution is stable across a command that
# trips more than one predicate.
ps::_mark_untrusted() {
  ((PS_REDUCTION_UNTRUSTED)) && return 0
  PS_REDUCTION_UNTRUSTED=1
  PS_REDUCTION_UNTRUSTED_REASON="$1"
}

# True when TEXT contains a CR not immediately followed by LF. PowerShell ends
# a statement at a bare CR; this library splits on LF only. Deleting every CRLF
# pair leaves exactly the CRs that no LF follows.
ps::has_bare_cr() {
  local s="${1//$'\r\n'/}"
  [[ "$s" == *$'\r'* ]]
}

# True when a PreToolUse JSON payload encodes a bare CR: a literal CR byte not
# followed by LF, or a JSON `\r` escape that is not `\r\n`. hook::jq_fields
# strips every CR from the extracted command, so classify must look at INPUT.
ps::payload_has_bare_cr() {
  local s="${1-}" t
  [[ -n "$s" ]] || return 1
  ps::has_bare_cr "$s" && return 0
  [[ "$s" == *"\\r"* ]] || return 1
  t="${s//\\\\/}"
  while [[ "$t" == *"\\r"* ]]; do
    t="${t#*"\\r"}"
    [[ "$t" == "\\n"* ]] || return 0
  done
  return 1
}

# True when LINE is a confirmed here-string opener: `@'` / `@"` survives as the
# last two characters after paired quote spans are stripped. Same predicate
# blank_herestrings uses; the private copy in block-convention-violation.sh
# calls this instead of testing the raw suffix.
ps::line_confirms_herestring_opener() {
  local opener_scan
  ps::_gsub_to opener_scan "$1" "'[^']*'" ''
  ps::_gsub_to opener_scan "$opener_scan" '"([^"\\]|\\.)*"' ''
  [[ "$opener_scan" == *"@'" || "$opener_scan" == *'@"' ]]
}

# ps::_split_lines_to <array name> <text>
#
# The newline-separated parts of TEXT, in the named array — what
# `while IFS= read -r line; do … done < <(printf '%s\n' "$text")` yielded, minus
# the process substitution. `printf '%s\n'` appends one newline, so the reader
# saw exactly these parts, including the trailing EMPTY part of a TEXT that
# already ended in a newline.
ps::_split_lines_to() {
  local -n __sl_out="$1"
  local __sl_rest="$2"
  __sl_out=()
  while [[ "$__sl_rest" == *$'\n'* ]]; do
    __sl_out+=("${__sl_rest%%$'\n'*}")
    __sl_rest="${__sl_rest#*$'\n'}"
  done
  __sl_out+=("$__sl_rest")
}

# ps::_gsub_to <varname> <text> <ere> <replacement>
#
# `sed -E "s/<ere>/<replacement>/g"` over TEXT, in bash.
#
# PER LINE, because that is what sed does: it hands its regex one line at a time
# with the newline already stripped, so in sed `[[:space:]]` can never match a
# newline and `.` never spans one, while bash's engine is handed the whole string
# and both would. Within a line the two agree — both resolve an ambiguous match
# POSIX leftmost-longest — so the per-line match set is identical.
#
# A CRLF LINE ENDING LOSES ITS CR, because this host's sed reads in text mode:
# measured, `printf 'a\r\nb\r\n' | sed …` writes `a\nb\n`, while a CR that ends
# no line survives (`a\rb`, and a final unterminated `a\r`). PowerShell commands
# arrive with Windows line endings, and PS_SAFE_COMMAND goes on to a Bash
# tokenizer, so leaving those CRs in would attach one to a token the captured
# form never had.
#
# The match POSITION comes from `${line%%"$m"*}`, the first LITERAL occurrence of
# the matched text. That is this match's own position: were the same text to
# occur earlier, the regex would have matched THERE instead, since no pattern in
# this file is anchored. An empty match would not advance, so it ends the line
# rather than looping forever; no pattern here can produce one, each requiring at
# least one literal character.
ps::_gsub_to() {
  local __gs_re="$3" __gs_repl="$4" __gs_out="" __gs_line __gs_acc __gs_pre __gs_m __gs_i
  local -a __gs_lines=()
  ps::_split_lines_to __gs_lines "$2"
  for ((__gs_i = 0; __gs_i < ${#__gs_lines[@]}; __gs_i++)); do
    __gs_line="${__gs_lines[__gs_i]}"
    ((__gs_i + 1 < ${#__gs_lines[@]})) && __gs_line="${__gs_line%$'\r'}"
    __gs_acc=""
    while [[ "$__gs_line" =~ $__gs_re ]]; do
      __gs_m="${BASH_REMATCH[0]}"
      [[ -n "$__gs_m" ]] || break
      __gs_pre="${__gs_line%%"$__gs_m"*}"
      __gs_acc+="${__gs_pre}${__gs_repl}"
      __gs_line="${__gs_line:${#__gs_pre}+${#__gs_m}}"
    done
    ((__gs_i)) && __gs_out+=$'\n'
    __gs_out+="${__gs_acc}${__gs_line}"
  done
  ps::_chomp_to "$1" "$__gs_out"
}

# Unicode code points PowerShell's tokenizer treats as TOKEN-SEPARATING
# whitespace but bash's `[[:space:]]` does not. Spelled as raw UTF-8 byte
# sequences via `$'\xNN'`, which is byte-literal and therefore identical under a
# UTF-8 locale and the C locale — the guards do not pin one, so a fix that only
# worked under one of them would fail OPEN under the other.
#
# Derived by MEASUREMENT, not from a Unicode category table: each candidate was
# parsed with `[System.Management.Automation.Language.Parser]::ParseInput` and
# kept only when `& $w<CH>f.txt x` produced ONE command of THREE elements
# (`$w`, `f.txt`, `x`) — i.e. the character really does split a working
# `Set-Content <path> <value>` call that `[[:space:]]` would have kept glued
# together. U+200B (zero-width space) and U+FEFF are excluded because they
# measured TWO elements: they do not separate, they sit inside the token, so the
# call target never resolves and there is nothing to hide. U+2028/U+2029 are
# included and mapped to a SPACE rather than a newline: both measured as one
# command, so PowerShell treats them as intra-statement whitespace here, and
# turning them into newlines would instead reshape the here-string line scan.
#
# NORMALIZING is the fix rather than adding these bytes to the `[[:space:]]`
# character classes. Under a single-byte locale a multi-byte sequence inside a
# bracket expression decomposes into INDEPENDENT byte members, so `\xc2` and
# `\xa0` would each match on their own — and `\xa0` is the second byte of `à`
# (U+00E0 = `\xc3\xa0`), so `& $py café.py`-shaped commands would start splitting
# into two positionals and blocking. That is an over-block of exactly the class
# #2848 exists to keep closed. A whole-sequence substitution cannot do that:
# `\xc2` is only ever a LEAD byte in well-formed UTF-8, so the pair `\xc2\xa0`
# occurs only as U+00A0 itself.
PS_TOKEN_SEPARATING_SPACES=(
  $'\xc2\x85'     # U+0085 NEXT LINE
  $'\xc2\xa0'     # U+00A0 NO-BREAK SPACE
  $'\xe1\x9a\x80' # U+1680 OGHAM SPACE MARK
  $'\xe2\x80\x80' # U+2000 EN QUAD
  $'\xe2\x80\x81' # U+2001 EM QUAD
  $'\xe2\x80\x82' # U+2002 EN SPACE
  $'\xe2\x80\x83' # U+2003 EM SPACE
  $'\xe2\x80\x84' # U+2004 THREE-PER-EM SPACE
  $'\xe2\x80\x85' # U+2005 FOUR-PER-EM SPACE
  $'\xe2\x80\x86' # U+2006 SIX-PER-EM SPACE
  $'\xe2\x80\x87' # U+2007 FIGURE SPACE
  $'\xe2\x80\x88' # U+2008 PUNCTUATION SPACE
  $'\xe2\x80\x89' # U+2009 THIN SPACE
  $'\xe2\x80\x8a' # U+200A HAIR SPACE
  $'\xe2\x80\xa8' # U+2028 LINE SEPARATOR
  $'\xe2\x80\xa9' # U+2029 PARAGRAPH SEPARATOR
  $'\xe2\x80\xaf' # U+202F NARROW NO-BREAK SPACE
  $'\xe2\x81\x9f' # U+205F MEDIUM MATHEMATICAL SPACE
  $'\xe3\x80\x80' # U+3000 IDEOGRAPHIC SPACE
)

# Replace every token-separating Unicode space with an ASCII space, so the whole
# library's `[[:space:]]` boundaries mean what PowerShell's tokenizer means.
# Applied ONCE, at intake (`ps::blank_herestrings`), rather than at each of the
# eight separator classes: a per-class fix would have to be repeated correctly in
# every copy, and a copy that silently stopped matching fails OPEN.
#
# The substitution pattern is QUOTED (`${s//"$ws"/ }`), which makes it a literal
# match. That is deliberately the opposite of the pattern-position hazard the
# call-target block comment below warns about — here we want no glob semantics at
# all, and quoting is what guarantees it.
#
# The result is published on PS_NORMALIZED rather than stdout: a command
# substitution would fork a subshell on the hot path of every PowerShell tool
# call (expensive under Git Bash's fork() emulation, which this guard already
# budgets for) and would silently eat a trailing newline that the here-string
# line scan below is entitled to see.
PS_NORMALIZED=""
ps::normalize_token_separating_spaces() {
  local ws
  PS_NORMALIZED="$1"
  for ws in "${PS_TOKEN_SEPARATING_SPACES[@]}"; do
    PS_NORMALIZED="${PS_NORMALIZED//"$ws"/ }"
  done
}

# Blank properly-delimited PowerShell here-strings to PS_HERESTRING_PLACEHOLDER.
# PowerShell here-string rules (about_Quoting_Rules): the opener `@'`/`@"` is the
# last token on its line (followed by a newline); the closer `'@`/`"@` is at the
# start of a line (column zero). Text after the closer on the same line (the
# `| git commit -F -` of the canonical form) is preserved.
#
# Sets PS_BLANKED (the reduced command) and PS_HERESTRING_UNBALANCED (1 when an
# opener has no column-zero closer — the extent is ambiguous, so PS_BLANKED is
# left as the original command and the caller fails closed).
ps::blank_herestrings() {
  ps::normalize_token_separating_spaces "$1"
  local cmd="$PS_NORMALIZED"
  local line out="" pending="" in_hs=0 hs_quote="" first2 prefix
  local saw_block_comment=0
  local -a hs_lines=()
  PS_HERESTRING_UNBALANCED=0
  PS_HERESTRING_QUOTE=""
  PS_HERESTRING_EXPANDABLE=0
  PS_HERESTRING_EXPANDABLE_SUBEXPR=0
  PS_REDUCTION_UNTRUSTED=0
  PS_REDUCTION_UNTRUSTED_REASON=""
  ps::has_bare_cr "$1" && ps::_mark_untrusted bare-cr
  [[ -n "${INPUT:-}" ]] && ps::payload_has_bare_cr "$INPUT" && ps::_mark_untrusted bare-cr

  ps::_split_lines_to hs_lines "$cmd"
  for line in "${hs_lines[@]}"; do
    line="${line%$'\r'}"
    if ((in_hs)); then
      if [[ "${line:0:2}" == "${hs_quote}@" ]]; then
        out+="${pending}${line:2}"$'\n'
        pending=""
        in_hs=0
        hs_quote=""
      elif [[ "$hs_quote" == '"' && "$line" == *"\$("* ]]; then
        PS_HERESTRING_EXPANDABLE_SUBEXPR=1
      fi
      continue
    fi
    first2="${line:0:2}"
    if [[ "$first2" == "'@" || "$first2" == '"@' ]]; then
      ps::_mark_untrusted herestring-orphan-closer
    fi
    [[ "$line" == *'<#'* ]] && saw_block_comment=1
    if ps::line_confirms_herestring_opener "$line"; then
      prefix="${line%??}"
      if [[ "$prefix" == *"#"* ]]; then
        ps::_mark_untrusted herestring-comment-char
      elif [[ "$prefix" == *"'"* || "$prefix" == *'"'* || "$prefix" == *"\\"* || "$prefix" == *'`'* ]]; then
        ps::_mark_untrusted herestring-opener-untrusted
      fi
      ((saw_block_comment)) && ps::_mark_untrusted herestring-comment-span
      hs_quote="${line: -1}" # ' or "
      # `@"` opens an EXPANDABLE body, evaluated where it is written, so the
      # placeholder about to replace it stands for text that can contain a
      # command position. `@'` opens a verbatim body and stands for inert text.
      [[ "$hs_quote" == '"' ]] && PS_HERESTRING_EXPANDABLE=1
      pending="${prefix}${PS_HERESTRING_PLACEHOLDER}"
      in_hs=1
      continue
    fi
    out+="${line}"$'\n'
  done

  if ((in_hs)); then
    PS_HERESTRING_UNBALANCED=1
    PS_HERESTRING_QUOTE="$hs_quote"
    PS_BLANKED="$cmd"
    PS_HERESTRING_EXPANDABLE=0
    PS_HERESTRING_EXPANDABLE_SUBEXPR=0
    return 0
  fi
  PS_BLANKED="${out%$'\n'}"
}

# The single left-to-right quoted-span walk behind ps::blank_quoted_spans_to,
# ps::opaque_quoted_spans_to and ps::_blank_comparison_operand_literals_to. MODE is
# `blank` (a found span is deleted), `opaque` (a found span becomes a classified
# placeholder, per the classification the opaque wrapper documents) or
# `cmpoperand` (a found span in comparison-operand position becomes the inert
# bareword `_q_` and every other span is emitted verbatim). WHERE a span starts
# and ends, and every ambiguity resolution, is identical for all three and
# therefore stated once here: two
# hand-maintained copies of this pairing walk are exactly the drift this file's
# other SSOT notes warn about, and a copy that silently stopped pairing the same
# way would fail OPEN in one lane while the other stayed closed.
#
# LEFT TO RIGHT, FIRST OPENER OWNS ITS SPAN. Two independent per-style strips
# (`s/'[^']*'//g` then `s/"[^"]*"//g`) have no notion of which quote style
# opened first. An apostrophe inside a DOUBLE-quoted string is a literal
# character to PowerShell, but a per-style single-quote expression treats it as
# a delimiter, so the span it deletes runs from the apostrophe in one
# double-quoted string to the apostrophe in the next, taking everything between
# them with it:
#
#   in:  Write-Host "a'b"; & ('g'+'it') push --force; Write-Host "c'd"
#   out: Write-Host
#
# That is not a measurement error, it is the ERASURE of the command every
# sink-trigger scan is about to look at. With the `(` gone, has_special_constructs
# sees no construct, has_dynamic_invocation sees no call, has_launcher sees no
# launcher: classify_git_command never enters the fail-closed sink at all, and
# the same deletion hides a computed writer call from write_bypass. Two
# ordinary strings that happen to contain apostrophes ("Kyle's build") become a
# general bypass of all three blocking hooks (#2965).
#
# A single walk fixes the pairing: whichever quote character opens first owns
# everything up to its own next occurrence, so an apostrophe inside a
# double-quoted span is ordinary text and a quote character inside a
# single-quoted span is ordinary text.
#
# AMBIGUITY RESOLVES TOWARD NOT DELETING. This is an ENTRY scan: leaving text in
# view can only cause an over-block, while deleting it is the fail-open above. So
#   - an UNTERMINATED opener emits the rest of its line verbatim rather than
#     swallowing it;
#   - a span never crosses a NEWLINE (matching the old per-line `sed` semantics),
#     because a multi-line double-quoted string would otherwise let
#     `"a\n& ('g'+'it') push --force\n"` blank the middle line;
#   - PowerShell's DOUBLED-quote escape (`'it''s'`, `"say ""hi"""`) makes a
#     candidate closer ambiguous, so it too resolves to deleting nothing on the
#     line. A lone empty string (`""`, `''`) is NOT doubled — its closer is
#     followed by something other than the same quote — so it still blanks
#     normally and `& $py $script ""` is unaffected.
#   - SMART quotes (U+2018/U+2019/U+201C/U+201D), which PowerShell's tokenizer
#     does accept as delimiters, are NOT treated as delimiters. Not deleting
#     leaves their contents in view: over-block, not bypass.
#
# A BACKTICK inside a would-be DOUBLE-quoted span makes the pairing ambiguous,
# and ambiguity here means DELETE NOTHING ON THIS LINE. Neither available answer
# is safe on its own, which is why the resolution is to refuse the question:
#
#   - HONORING the escape (what `ps::_skip_double_quote_to` does, correctly, in the
#     sink BLANKING path that runs after the entry decision) extends the span
#     past `` `" `` to the next real quote, so
#     `Write-Host "a`"; & ('g'+'it') push --force; Write-Host "b"` becomes one
#     span and blanks the git command — this issue's own bug in a new spelling.
#   - NOT honoring it ends the span at the backticked quote, which leaves the
#     string's REAL closer behind as a stray opener that pairs with a quote far
#     to the right. ``"a`""; & ('g'+'it') push --force; 'b"c'`` then reduces to
#     `c'` and all three hooks returned 0 (caught in review of this change).
#
# Emitting the rest of the line verbatim costs nothing that is not already paid:
# a surviving backtick trips has_special_constructs' backtick arm and routes to
# the fail-closed sink anyway. It cannot do that if the span containing it is
# deleted, which is the deeper reason this branch exists. SINGLE-quoted spans are
# exempt: PowerShell gives them no escape at all, so a backtick inside one is an
# ordinary character and the pairing is genuinely unambiguous.
ps::_walk_quoted_spans_to() {
  local __wq_text="$2" __wq_mode="$3" __wq_out="" __wq_i=0 __wq_n __wq_j __wq_q __wq_found __wq_c __wq_inner
  __wq_n=${#__wq_text}
  PS_QUOTED_SPAN_SAW_EXPANDABLE=0
  while ((__wq_i < __wq_n)); do
    __wq_q="${__wq_text:__wq_i:1}"
    if [[ "$__wq_q" == "'" || "$__wq_q" == '"' ]]; then
      [[ "$__wq_q" == '"' ]] && PS_QUOTED_SPAN_SAW_EXPANDABLE=1
      __wq_found=0
      for ((__wq_j = __wq_i + 1; __wq_j < __wq_n; __wq_j++)); do
        __wq_c="${__wq_text:__wq_j:1}"
        [[ "$__wq_c" == $'\n' ]] && break
        if [[ "$__wq_q" == '"' && "$__wq_c" == '`' ]] ||
          [[ "$__wq_c" == "$__wq_q" && "${__wq_text:__wq_j+1:1}" == "$__wq_q" ]]; then
          for (( ; __wq_j < __wq_n; __wq_j++)); do [[ "${__wq_text:__wq_j:1}" == $'\n' ]] && break; done
          break
        fi
        if [[ "$__wq_c" == "$__wq_q" ]]; then
          __wq_found=1
          break
        fi
      done
      if ((__wq_found)); then
        if [[ "$__wq_mode" == "opaque" ]]; then
          __wq_inner="${__wq_text:__wq_i+1:__wq_j-__wq_i-1}"
          if [[ -n "$__wq_inner" ]]; then
            if [[ "$__wq_inner" == -* && "$__wq_q" == '"' && "$__wq_inner" == *'$'* ]]; then
              __wq_out+='-_q_'
            elif [[ "$__wq_q" == '"' && "$__wq_inner" == *'$'* ]]; then
              __wq_out+="\$q"
            else
              __wq_out+='_q_'
            fi
          fi
        elif [[ "$__wq_mode" == "cmpoperand" ]]; then
          if ps::_is_comparison_operand_context "$__wq_out"; then
            __wq_out+='_q_'
          else
            __wq_out+="${__wq_text:__wq_i:__wq_j-__wq_i+1}"
          fi
        fi
        __wq_i=$((__wq_j + 1))
        continue
      fi
      __wq_out+="${__wq_text:__wq_i:__wq_j-__wq_i}"
      __wq_i=$__wq_j
      continue
    fi
    __wq_out+="$__wq_q"
    __wq_i=$((__wq_i + 1))
  done
  ps::_chomp_to "$1" "$__wq_out"
}

# Crude, SCAN-ONLY strip of single- and double-quoted spans, so that structural
# detection and commit/push shaping ignore characters inside message text. Never
# fed to a parser.
ps::blank_quoted_spans_to() {
  ps::_walk_quoted_spans_to "$1" "$2" blank
}

# True (0) when PREFIX — the already-walked text standing in front of a quoted
# string literal — puts that literal in COMPARISON-OPERAND position: the nearest
# preceding non-whitespace token is a PowerShell comparison operator, reached
# through an optional opening `(` / `@(` and through `,`-separated earlier
# elements of that same list. The `c`/`i` case prefixes count (`-ceq`, `-ilike`).
#
# RIGHT-HAND OPERANDS ONLY. A literal on the LEFT of the operator is not decidable
# here: `& 'git' -eq $x` is a CALL of git with `-eq` as its first argument, not a
# comparison, and nothing in the prefix distinguishes the two. So `'git' -in $names`
# and `@('git') -contains $_.Name` keep the quote-intact probe.
#
# The operator's left boundary excludes alphanumerics, `_` and `-`, so a cmdlet or
# parameter name that merely ENDS in an operator spelling is not one.
#
# The hop count is BOUNDED. A list long enough to exhaust it falls through to
# "not an operand", which keeps the quote-intact probe — the over-block
# direction, matching the file's invariant.
ps::_is_comparison_operand_context() {
  local p="$1" hops
  for ((hops = 0; hops < 16; hops++)); do
    if [[ "$p" =~ ^(.*[^[:space:]])[[:space:]]*$ ]]; then p="${BASH_REMATCH[1]}"; else p=""; fi
    [[ "$p" =~ (^|[^[:alnum:]_-])-[ci]?(eq|ne|in|notin|contains|notcontains|like|notlike|match|notmatch|lt|le|gt|ge)$ ]] && return 0
    case "$p" in
    *'(')
      p="${p%?}"
      if [[ "$p" =~ ^(.*[^[:space:]])[[:space:]]*$ ]]; then p="${BASH_REMATCH[1]}"; else p=""; fi
      [[ "$p" == *'@' ]] && p="${p%?}"
      ;;
    *',')
      p="${p%?}"
      if [[ "$p" =~ ^(.*[,()[:space:]])[^,()[:space:]]*$ ]]; then p="${BASH_REMATCH[1]}"; else p=""; fi
      ;;
    *) return 1 ;;
    esac
  done
  return 1
}

# Replace every quoted string literal that ps::_is_comparison_operand_context
# accepts with the inert bareword `_q_`, leaving every other span verbatim.
# The one consumer is ps::might_invoke_git's data-literal exemption; the rule and
# why it cannot reach execution are documented there.
ps::_blank_comparison_operand_literals_to() {
  ps::_walk_quoted_spans_to "$1" "$2" cmpoperand
}

# True (0) when TOK is a read-only cmdlet, alias or keyword — the allowlist
# ps::_is_readonly_cmdlet_pipeline admits at a command position. Every entry
# INTERROGATES: it reports, filters, formats, converts or compares, and none of
# them runs a program named by its input. Any Get-* verb is admitted as a class
# (`Get-Process`, `Get-CimInstance`, `Get-Content`, `Get-Command`), because Get
# is defined as retrieval and a PowerShell command name is verb-qualified.
ps::_is_readonly_cmdlet() {
  case "$1" in
  gps | ps | gcim | gwmi | gci | ls | dir | gi | gc | cat | type | gsv | gcm | gmo | gv | gl | pwd) return 0 ;;
  where-object | where | '?') return 0 ;;
  select-object | select) return 0 ;;
  foreach-object | foreach | '%') return 0 ;;
  sort-object | sort | measure-object | measure | group-object | group) return 0 ;; # portability-ok: cmdlet names in a case pattern, not a sort -V invocation
  format-table | ft | format-list | fl | format-wide | fw) return 0 ;;
  out-string | out-host | oh | out-null) return 0 ;;
  write-output | write | echo | write-host) return 0 ;;
  select-string | sls) return 0 ;;
  test-path | resolve-path | rvpa | split-path | join-path) return 0 ;;
  compare-object | compare | diff) return 0 ;;
  convertto-json | convertfrom-json | convertto-csv) return 0 ;;
  if | else | elseif | in | return) return 0 ;;
  *) ;;
  esac
  [[ "$1" =~ ^get-[a-z0-9]+$ ]]
}

# True (0) when the whole command is provably a READ-ONLY CMDLET PIPELINE: every
# token standing at a command position is an allowlisted interrogator, and the
# command carries none of the constructs that turn a value into a command. This
# is ps::might_invoke_git's gate on the comparison-operand exemption.
#
# DENY BY DEFAULT, AND THAT IS THE POINT. Asking instead whether a known executor
# is PRESENT is structurally under-inclusive: PowerShell reaches a program
# through `[Diagnostics.Process]::Start(…)`,
# `$ExecutionContext.InvokeCommand.InvokeScript(…)`,
# `[scriptblock]::Create(…).Invoke()`, an alias minted at run time
# (`Set-Alias zz $_.Name; zz push --force`), WMI/CIM `Win32_Process Create`, a
# scheduled-task action, a service binary path, and every launcher that happens
# to be on PATH (`npx`, `dotnet`, `cscript`, `explorer`, `ssh`, `wmic`,
# `schtasks`) — a set no enumeration converges on. Inverted, an unrecognized
# command word is REFUSED rather than admitted, so a new executor costs an
# over-block instead of a bypass.
#
# AN EXPANDABLE STRING IS A COMMAND POSITION, so its presence anywhere in the
# command refuses. A double-quoted `"…"` span (and the `@"…"@` here-string form)
# is EVALUATED where it is written: `"$( … )"` runs the subexpression to build
# the string, so `-eq "$(cmd /c git push --force)"` executes a program before any
# comparison happens. The walk blanks that span to an inert placeholder, which is
# exactly what makes the executor invisible to a token scan of the blanked text.
# A security review reproduced the whole executor family through it (`cmd /c`,
# `bash -c`, `powershell -c`, `Start-Process`, `& 'git'`, `Start-Job`,
# `Invoke-Item`, `New-Object`, `node -e`, a bare `git`, `schtasks`), under `-eq`,
# `-like`, `-in` and a second `Where-Object`, and inside an interpolated
# `"${env:ComSpec} $( … )"`. A VERBATIM `'…'` string has no such evaluation
# (about_Quoting_Rules), so the single-quoted operands the exemption exists for
# stay exempt. The witness is the walk's own opener, not the raw text and not the
# placeholder kind: `_q_` is shared by `'git'` and `"git"`, and a raw `"` scan
# would misread the `"` inside `'he said "hi"'`.
#
# THE SCAN, in order, over the command with every quoted string replaced by an
# opaque placeholder (so a `[` or an `&` inside message text is data, not a
# construct):
#   0. refuse when the walk that produced the placeholders crossed a DOUBLE-quote
#      opener, the expandable-string disqualifier above;
#   1. refuse outright on a construct no token scan can settle — a surviving
#      BACKTICK (escape), `<#` (block comment), `--%` (stop-parsing), `::`
#      (static member, the `[Type]::Method` executor family), `[` (type
#      literal), `&` (call operator), and a `.` immediately before `(` (a method
#      call such as `.Invoke(` / `.InvokeScript(`);
#   2. walk the remainder token by token, tracking COMMAND POSITION — the start
#      of input, and anything after `|`, `;`, `{`, `}`, `(`, `=` or a newline;
#   3. at a command position the token must be allowlisted. A `$variable` or
#      property chain, a `-parameter` or operator, an opaque string placeholder
#      and a bare number are inert and skipped; anything else at a command
#      position refuses — `zz`, `npx`, `iwmi`, `nsv`, `schtasks`, `wmic`,
#      `set-alias`, `new-object`, `iex`, a `.` dot-source, a `.\path.exe`, and
#      `git` itself.
#
# ARGUMENTS ARE NOT COMMAND WORDS, so a token away from a command position is
# skipped and `Get-CimInstance Win32_Process`, `Select-Object ProcessId` and
# `Select-Object Id` stay admissible. An argument cannot execute on its own:
# reaching a program through one takes a command word that accepts it, and that
# command word sits at a command position and must be allowlisted.
#
# FAIL CLOSED ON DOUBT. An over-long command is refused rather than scanned. The
# walk is per-character and the exemption is a convenience, so the ceiling costs
# an over-block on a command that keeps the quote-intact probe it had anyway.
ps::_is_readonly_cmdlet_pipeline() {
  local lc i n ch tok="" cmdpos=1
  ps::opaque_quoted_spans_to lc "$1"
  ((PS_QUOTED_SPAN_SAW_EXPANDABLE)) && return 1
  lc="${lc,,}"
  case "$lc" in
  *'`'* | *'<#'* | *'--%'* | *'::'* | *'['* | *'&'*) return 1 ;;
  *) ;;
  esac
  [[ "$lc" =~ \.[a-z0-9_]*\( ]] && return 1
  ((${#lc} > 4096)) && return 1
  lc+=$'\n'
  n=${#lc}
  for ((i = 0; i < n; i++)); do
    ch="${lc:i:1}"
    case "$ch" in
    '|' | ';' | '{' | '}' | '(' | '=' | $'\n' | ' ' | $'\t' | $'\r' | ',' | '@' | ')' | '>' | '<' | '+' | '*') ;;
    *)
      tok+="$ch"
      continue
      ;;
    esac
    if [[ -n "$tok" ]]; then
      case "$tok" in
      '$'* | -* | '_q_') ;;
      *)
        if [[ "$tok" =~ ^[0-9]+$ ]]; then
          :
        elif ((cmdpos)); then
          ps::_is_readonly_cmdlet "$tok" || return 1
        fi
        ;;
      esac
      tok=""
      cmdpos=0
    fi
    case "$ch" in
    '|' | ';' | '{' | '}' | '(' | '=' | $'\n') cmdpos=1 ;;
    *) ;;
    esac
  done
  return 0
}

# Sibling of ps::blank_quoted_spans_to for the two consumers that need a string
# to stay PRESENT while its content stays opaque:
# ps::computed_call_has_positional_write_signal and
# ps::_is_readonly_cmdlet_pipeline. Same left-to-right pairing —
# first opener owns its span, ambiguity copies the rest of the line verbatim —
# but a FOUND span is replaced by a classified placeholder instead of deleted.
#
# Deletion is what made quoting a general evasion of the two-positional arm
# (#2906): `& $w 'f.txt' 'x'` is a complete Set-Content <path> <value> call, and
# blanking both operands left the probe with nothing to count. The placeholder
# keeps the operand PRESENT so it still counts, while its content stays OPAQUE
# so a quoted `>` or `-value` in message text cannot become a different signal.
# That is why this string never reaches the redirect and `-va*` probes, which
# still need the deletion semantics. The read-only-pipeline gate wants the same
# property for the same reason: a string has to stay a TOKEN so the walk can tell
# a command word from an argument, while its content stays out of the scan.
#
# Classification, interpolating-dash FIRST (about_Quoting_Rules + about_Parsing):
#   1. DOUBLE-quoted, starts with `-`, AND contains `$` → `-_q_`
#      Only this shape is treated as a flag. `"-Path$x"` matches the unquoted
#      `-Path$x` stop. Evaluating interpolation first was a prototype bug: it
#      classified that token as computed and let the scan continue.
#      A merely dash-prefixed quoted literal (`'-file.txt'`, `"-file.txt"`)
#      is still an ARGUMENT in PowerShell (quoted strings are never parameters)
#      and must stay an opaque literal — otherwise quoting a hyphen-prefixed
#      path reopens the #2906 evasion.
#   2. DOUBLE-quoted and contains `$` → `$q`
#      Expandable string (about_Quoting_Rules). Counts as a positional, not a
#      visible literal — same class as `$path`. A SINGLE-quoted `$x` is
#      verbatim, so it falls through to the literal placeholder.
#   3. otherwise → `_q_`
#      Present-but-opaque visible literal.
#
# An EMPTY span (`""`, `''`) is still deleted, matching blank_quoted_spans_to.
# `& $py $script ""` must stay allowed (#2965); counting the empty string as a
# literal would turn that pin into an over-block.
ps::opaque_quoted_spans_to() {
  ps::_walk_quoted_spans_to "$1" "$2" opaque
}

# Fold a BACKTICK-ESCAPED closing brace to `_`, left to right, BEFORE any caller
# deletes backticks to recover an obfuscated name.
#
# A braced variable name may contain a `}` by escaping it: `${my`}writer}` names
# the variable `my}writer` (about_Variables). Deleting the backtick first turns
# that into `${my}writer}` — text that is genuinely INDISTINGUISHABLE from a
# `${my}` reference followed by the literal `writer}`. No regex applied after the
# deletion can tell them apart, so the braced-target scanner's `[^}]*` stopped at
# the injected brace, failed the whitespace boundary, and located no call site at
# all. Both measuring probes then returned false, every arm of the computed-target
# gate stayed silent, and `& ${my`}writer} f.txt x` fell through ALLOWED — the
# same computed-writer fail-open the braced-target fix exists to close (review of
# #2848). The escape context therefore has to be consumed HERE, while it still
# exists.
#
# The name's exact text is irrelevant to locating a call site, so the two-char
# escape is replaced by one ordinary name character rather than preserved.
#
# An escaped BACKTICK (```` `` ````) is emitted UNCHANGED and consumed as a unit, so
# it cannot lend its second backtick to a brace that follows, and so the callers'
# obfuscation recovery (`& "Set``-Content"` -> `set-content`) is untouched. Only
# the escaped closer is folded: an escaped OPENING brace needs no handling —
# `${my`{writer}` deletes to `${my{writer}`, where `[^}]*` matches the name and
# the real closer still terminates it — and removing a `{` other probes count
# would be a change outside this finding.
ps::fold_escaped_brace_closers_to() {
  local __fb_s="$2" __fb_out="" __fb_i __fb_n __fb_ch
  __fb_n=${#__fb_s}
  for ((__fb_i = 0; __fb_i < __fb_n; __fb_i++)); do
    __fb_ch="${__fb_s:__fb_i:1}"
    if [[ "$__fb_ch" == '`' ]] && ((__fb_i + 1 < __fb_n)); then
      case "${__fb_s:__fb_i+1:1}" in
      '}')
        __fb_out+='_'
        __fb_i=$((__fb_i + 1))
        continue
        ;;
      '`')
        __fb_out+='``'
        __fb_i=$((__fb_i + 1))
        continue
        ;;
      *)
        ;;
      esac
    fi
    __fb_out+="$__fb_ch"
  done
  ps::_chomp_to "$1" "$__fb_out"
}

# True (0) when the (quote-stripped) text carries a PowerShell construct the Bash
# tokenizer cannot faithfully handle: backtick (escape / line continuation, which
# the Bash tokenizer would read as command substitution and use to swallow
# adjacent tokens), `--%` (stop-parsing), and `(`/`)`/`{`/`}` grouping
# (subexpression, array subexpression, script block, hashtable — any of which can
# seat a git invocation where the Bash parser will not find it). Their presence
# routes the command to the fail-closed sink rather than a best-effort Bash parse.
# Quoted spans are stripped by the caller first, so a construct inside message
# text does not trip this — only structural constructs do.
ps::has_special_constructs() {
  local scan="$1"
  # The single-quoted needles are literal glob patterns, not expansions.
  # shellcheck disable=SC2016
  case "$scan" in
  *'`'*) return 0 ;;
  *'--%'*) return 0 ;;
  *'('* | *')'*) return 0 ;;
  *'{'* | *'}'*) return 0 ;;
  *) return 1 ;;
  esac
}

# True (0) when the call/dot-source target is a bare variable or subexpression —
# `& $tool …`, `& ('g'+'it') …`, `. (Get-Path) …`. The target is computed at run
# time and cannot be resolved statically.
ps::call_target_is_bare_computed() {
  local lc="${1//\`/}"
  lc="${lc,,}"
  [[ "$lc" =~ (^|[[:space:]\;\{\}\(\|\&=])[.\&][[:space:]]*[\$\(] ]]
}

# The SUBEXPRESSION half of the predicate above — `& ('g'+'it') …`, `. (Get-Path)`
# — with the bare-VARIABLE half (`& $tool …`) deliberately excluded.
#
# BOTH SPELLINGS of the subexpression operator are matched: the grouping form
# `(…)` and the dollar form `$(…)`. They are the same construct — each evaluates
# an expression into the command name — and PowerShell's about_Operators lists
# them side by side. Recognizing only `(` let `& $(…)` ENTER the computed-target
# gate through `ps::call_target_is_bare_computed` (which matches `[.&][[:space:]]*[$(]`,
# so the `$` admits it) and then match no call site in any measuring probe:
# `ps::computed_call_has_positional_write_signal` and
# `ps::computed_call_has_splat_operand` both require a `$name` or `${name}`
# target, and `$(` is neither. Every arm stayed silent and the command fell
# through ALLOWED — `& $($w) f.txt x` was waved past while the identical
# `& ($w) f.txt x` blocked (#2924). Same "gate admits, probes cannot see"
# mechanism as the braced spelling (#2922), one construct over.
#
# The `$` is OPTIONAL, not required, so the paren spelling keeps matching
# exactly as before; the widened target token only decides where the shape
# refusal fires, never what it refuses. Unlike the braced-name fix (#2908) there
# is nothing to consume upstream: `$(` survives backtick deletion, quote
# blanking, and lowercasing intact, so the evidence is still here and the
# refusal belongs in this predicate rather than in a pre-deletion pass.
#
# The split exists because the two halves are NOT equally decidable, and the
# library already treats them differently everywhere else (#2848). A
# subexpression ASSEMBLES a command name at run time out of fragments that need
# never contain the name — `('g'+'it')` carries no `git` token for any literal
# probe to see — so it can only ever be refused by shape. A bare variable is the
# variable-COMMAND-WORD residual `ps::has_dynamic_invocation` documents and
# deliberately does not route to the sink: the guards already allow `& $tool …`
# whenever nothing else routes the command, and grouping elsewhere in the command
# does not make `$tool` any more resolvable. Blocking the bare-variable form ONLY
# when an unrelated grouping construct co-occurs was over-blocking ordinary
# PowerShell (resolve an interpreter into a variable, then loop) while leaving the
# identical construct-free command allowed.
#
# The pattern is spelled out literally here rather than derived from the sibling
# above, for the fail-OPEN reason stated in the block comment above: a predicate
# assembled from a variable in pattern position that silently stops matching
# would wave a computed call target through.
ps::call_target_is_bare_subexpression() {
  local lc="${1//\`/}"
  lc="${lc,,}"
  [[ "$lc" =~ (^|[[:space:]\;\{\}\(\|\&=])[.\&][[:space:]]*\$?\( ]]
}

# True (0) when a bare computed *variable* call carries a positional write
# shape that the named-parameter probes miss. Set-Content/Add-Content take
# Path+Value positionally (`& $w f.txt x`); Out-File commonly takes pipeline
# input plus a path (`$data | & $w out.txt`). Count *leading* non-flag tokens
# after the target (stop at the first dash-flag) so `& $py script.py` (one
# positional) and `& $python -m unittest discover` (flag-first) stay allowed
# while two leading positionals still fail closed. A pipeline into the call
# needs only one leading positional — the content arrives via `|`.
# Subexpression targets (`& ('Set-'+'Content') …`) do not need this probe: they
# are refused by shape, by `ps::call_target_is_bare_subexpression` at the gate.
#
# EVERY `& $var` / `. $var` site in the command is measured, not just the
# leftmost (#2848). Until this branch's gate named its shapes, a blanket
# `ps::has_special_constructs` stood in front of it and any command with a script
# block was already refused, so measuring the first site only was invisible.
# Without that blanket, `& $ic -ScriptBlock { & $w f.txt $x }` would be measured
# at `& $ic` — whose leading token `-ScriptBlock` is a flag, so zero positionals
# — and the nested `& $w f.txt $x` would never be reached.
#
# Operands are CLASSIFIED, not merely counted (#2848). A parenthesized
# subexpression is one operand however many words it spans, and the
# two-positional arm fires only when at least one counted operand is a VISIBLE
# LITERAL — a token that is not a `$variable`, not a `(subexpression)`, not a
# `@splat`, and not a `{scriptblock}`. The Path+Value shape this probe exists
# for (`& $w f.txt x`) always shows at least one of its halves as literal text
# on the command line; when EVERY operand is itself computed
# (`& $py $script (Join-Path $dir …)`), the command is argument plumbing
# between expressions — the ordinary interpreter-over-computed-paths loop this
# issue de-blocks — and the write hypothesis rests on nothing visible. The
# residual this concedes (writer name, path, AND value all staged into
# variables inside one command string) is a deliberately evasive shape of the
# same class as the `node -e` writes the hook's scope note already excludes; a
# pipeline into the call still fails closed on ANY operand, computed or not,
# because the content demonstrably arrives via `|`.
#
# A call site whose variable RESOLVES to a non-writer literal is not measured by
# this probe at all (see ps::computed_call_var_resolves_to_literal):
# `$sh='C:/Program Files/Git/bin/bash.exe'; & $sh x.sh record dir` is the same
# call as `& 'C:/Program Files/Git/bin/bash.exe' x.sh record dir`, which never
# enters this gate. Each call site is resolved through its OWN variable, so
# resolving `$sh` never exempts an `& $w` elsewhere in the command. Only this
# positional arm (count and pipeline) is skipped; the splat, redirect, `-va*`,
# subexpression and `--%` arms in ps::write_bypass still apply to the call.

# True (0) when lowercased, backtick-deleted TEXT calls or dot-sources a QUOTED
# writer or iex name, optionally module-qualified (`& 'Set-Content' …`,
# `. "Microsoft.PowerShell.Management\Set-Content" …`). The name is matched as a
# prefix, so a quoted program whose name merely starts with one (`& 'nightly.exe'`)
# is refused too — the safe direction.
ps::quoted_call_names_writer() {
  local q="\"'"
  [[ "$1" =~ (^|[[:space:]\;\{\}\(\|\&=])[.\&][[:space:]]*[$q]([a-z.]+\\)?(set-content|add-content|out-file|tee-object|ac|tee|iex|invoke-expression|new-item|ni|epcsv|export-[a-z]+) ]]
}

# True (0) when variable NAME (lowercase, no `$`) provably holds a single-quoted
# literal whose command name is not a writer at every point it is called in TEXT
# (the lowercased, quote-intact command). Anything this cannot prove returns 1,
# which keeps the positional arm's verdict.
#
# Every `$name` occurrence in TEXT must be one of two whitelisted forms:
#   - a call target: `& $name` / `. $name`;
#   - an assignment of exactly one single-quoted literal, `$name = '<literal>'`,
#     followed by `;`, a newline or the end of the command. The terminator is what
#     rejects `'Set-'+'Content'`, `'x'.Replace(…)`, `'x' | …` and `'a''b'`.
# Any other occurrence — a read, `+=`, `++`, `foreach ($name in …)`,
# `[ref]$name`, a double-quoted or computed right-hand side — is unresolvable.
# Whitelisting occurrences rather than listing write channels keeps a channel
# nobody thought of on the blocked side.
#
# The FIRST occurrence must be the assignment, at depth zero in statement
# position (start of command, or after `;` or a newline, with no unclosed `{` or
# `(` in the quote-blanked text before it), so it runs unconditionally in the
# caller's scope before any call. A later assignment must repeat the same literal.
#
# Channels that set a variable by NAME rather than by `$name` make every variable
# unresolvable: Set-/New-/Get-/Clear-/Remove-Variable and their aliases,
# Set-Item, the `variable:` drive, PSVariable, the `-*Variable` common
# parameters, and scope-qualified or braced spellings (`$script:name`,
# `${name}`), which this does not model. Automatic variables PowerShell rebinds
# on its own (`$_`, `$args`, `$matches`, …) and any backtick in the command
# (escape context shifts quote pairing and the depth check) are unresolvable too.
#
# The literal's command name — everything after the last `/`, `\` or `:` (which
# drops the directory, drive and any `Module\` qualifier), minus one
# .exe/.cmd/.bat/.ps1 — is then checked with the quoted-writer matcher
# ps::write_bypass applies to `& '<name>'`, so a resolved target is refused
# exactly when the equivalent literal call is. `sc` is refused as well: it is
# Set-Content's alias in Windows PowerShell 5.1. A wildcard or whitespace in the
# name fails closed.
ps::computed_call_var_resolves_to_literal() {
  local v="$1" s="$2" rest head="" tail lit="" have=0 blanked i ch depth base
  local re_asg=$'^[ \t]*=[ \t]*\'([^\']*)\'[ \t]*([;\r\n]|$)'
  local re_stmt=$'(^|[;\r\n])[ \t]*$'
  local re_call='(^|[[:space:]\;\{\}\(\|\&=])[.\&][[:space:]]*$'
  local re_byname='(^|[^a-z0-9_-])(set-variable|set|sv|new-variable|nv|get-variable|gv|clear-variable|clv|remove-variable|rv|set-item|si)([^a-z0-9_-]|$)'
  local re_commonvar='[[:space:]]-(outvariable|ov|pipelinevariable|pv|errorvariable|ev|warningvariable|wv|informationvariable|iv)([[:space:]]|:|$)'
  [[ "$v" =~ ^[a-z_][a-z0-9_]*$ ]] || return 1
  case "$v" in
  _ | psitem | args | input | this | matches | foreach | switch | sender | event | eventargs | eventsubscriber | lastexitcode | error | myinvocation | psboundparameters | pscmdlet) return 1 ;;
  *) ;;
  esac
  [[ "$s" == *'`'* ]] && return 1
  [[ "$s" =~ $re_byname || "$s" =~ $re_commonvar ]] && return 1
  [[ "$s" == *variable:* || "$s" == *psvariable* || "$s" == *":$v"* ]] && return 1
  [[ "$s" == *"\${"* && "$s" == *"$v}"* ]] && return 1
  rest="$s"
  while [[ "$rest" == *"\$$v"* ]]; do
    head+="${rest%%"\$$v"*}"
    tail="${rest#*"\$$v"}"
    rest="$tail"
    if [[ "$tail" == [a-z0-9_?:]* ]]; then
      head+="\$$v"
      continue
    fi
    if [[ "$tail" =~ $re_asg ]]; then
      if ((have)); then
        [[ "${BASH_REMATCH[1]}" == "$lit" ]] || return 1
      else
        lit="${BASH_REMATCH[1]}"
        [[ "$head" =~ $re_stmt ]] || return 1
        ps::blank_quoted_spans_to blanked "$head"
        depth=0
        for ((i = 0; i < ${#blanked}; i++)); do
          ch="${blanked:i:1}"
          case "$ch" in
          '{' | '(') depth=$((depth + 1)) ;;
          '}' | ')') depth=$((depth - 1)) ;;
          *) ;;
          esac
          ((depth < 0)) && return 1
        done
        ((depth == 0)) || return 1
        have=1
      fi
    elif ((!have)) || [[ ! "$head" =~ $re_call ]]; then
      return 1
    fi
    head+="\$$v"
  done
  ((have)) || return 1
  base="${lit##*[/\\:]}"
  case "$base" in
  *.exe | *.cmd | *.bat | *.ps1) base="${base%.*}" ;;
  *) ;;
  esac
  [[ "$base" == *[\*\?\[[:space:]]* || "$base" == sc ]] && return 1
  ! ps::quoted_call_names_writer "& '$base'"
}

# The OPERAND REGION of one call site: everything following the call target that
# still belongs to this call. Emitted on stdout.
#
# Two things end the region, and telling them apart is the whole point:
#   - a statement / pipeline separator (`;` `|` `&`) at bracket depth ZERO. Inside
#     a hashtable literal or a script block those characters are ordinary interior
#     punctuation (`& $w @{a=1;b=2}`), not the end of the call;
#   - an UNMATCHED closer (`}` or `)`), which closes an ENCLOSING construct — the
#     `}` ending the `foreach` block around `foreach (…) { & $w @p }`. A closer
#     that matches an opener seen inside the region closes one of this call's OWN
#     operands and is kept.
#
# Only `()` and `{}` drive depth. `[]` is left as ordinary text because ending the
# region is the FAIL-OPEN direction — an unmatched `]` in an operand (a type
# literal or an index written oddly) would cut the scan short and hide a real
# write signal, whereas carrying `[`/`]` through at most keeps extra text in view.
#
# This replaced a pair of first-match string strips (`${rest%%[\;\|\&]*}` and
# `${rest%%\}*}`). Cutting at the FIRST `}` anywhere assumed no `}` can occur
# inside the call's own operands before a token of interest, which is false:
# `${scope:name}`, a `{…}` script block, and a `@{…}` hashtable literal are all
# ordinary operands containing `}`. The strip therefore dropped everything from
# such an operand onward, and `& $w ${script:Path} @Body` — a working
# Set-Content-by-splat — went unseen by both probes below (review of #2848).
#
# An unmatched OPENER (a genuinely unbalanced command) leaves the region running
# to end of string; the callers stay conservative on what they can still see, and
# such a command does not parse in PowerShell to begin with.
ps::call_site_operand_region_to() {
  local __cs_s="$2" __cs_out="" __cs_i __cs_ch __cs_depth=0
  for ((__cs_i = 0; __cs_i < ${#__cs_s}; __cs_i++)); do
    __cs_ch="${__cs_s:__cs_i:1}"
    case "$__cs_ch" in
    '{' | '(')
      __cs_depth=$((__cs_depth + 1))
      ;;
    '}' | ')')
      ((__cs_depth == 0)) && break
      __cs_depth=$((__cs_depth - 1))
      ;;
    ';' | '|' | '&')
      ((__cs_depth == 0)) && break
      ;;
    *)
      ;;
    esac
    __cs_out+="$__cs_ch"
  done
  ps::_chomp_to "$1" "$__cs_out"
}

# Blank the INTERIOR of every balanced bracket group in a call's operand region,
# keeping the delimiters. Used by the splat probe so a nested construct's contents
# are not read as operands of the enclosing call: the splat inside
# `& $ic -ScriptBlock { & $w @p }` belongs to the inner `& $w`, which the call-site
# walk reaches on its own iteration, and the interior of `${script:Path}` holds no
# operands at all.
ps::blank_bracket_interiors_to() {
  local __bb_s="$2" __bb_out="" __bb_i __bb_ch __bb_depth=0
  for ((__bb_i = 0; __bb_i < ${#__bb_s}; __bb_i++)); do
    __bb_ch="${__bb_s:__bb_i:1}"
    case "$__bb_ch" in
    '{' | '(')
      __bb_out+="$__bb_ch"
      __bb_depth=$((__bb_depth + 1))
      continue
      ;;
    '}' | ')')
      ((__bb_depth > 0)) && __bb_depth=$((__bb_depth - 1))
      __bb_out+="$__bb_ch"
      continue
      ;;
    *)
      ;;
    esac
    if ((__bb_depth > 0)); then __bb_out+=" "; else __bb_out+="$__bb_ch"; fi
  done
  ps::_chomp_to "$1" "$__bb_out"
}

ps::computed_call_has_positional_write_signal() {
  local lc="$1" resolve_text="${2-}" rest="" tok count count_lit piped=0 scan depth opens closes target
  local re_var='(^|[[:space:]\;\{\}\(\|\&=])[.\&][[:space:]]*(\$\{[^}]*\}[^[:space:]]*|\$[a-z0-9_:?]+)([[:space:]]+|$)(.*)'
  local re_pipe='^(.*)[.\&][[:space:]]*\$'
  lc="${lc//\`/}"
  lc="${lc,,}"
  if [[ "$lc" =~ $re_pipe ]]; then
    [[ "${BASH_REMATCH[1]}" == *'|'* ]] && piped=1
  fi
  scan="$lc"
  while [[ "$scan" =~ $re_var ]]; do
    rest="${BASH_REMATCH[4]}"
    target="${BASH_REMATCH[2]}"
    scan="$rest"
    if [[ -n "$resolve_text" ]] &&
      ps::computed_call_var_resolves_to_literal "${target#\$}" "$resolve_text"; then
      continue
    fi
    count=0
    count_lit=0
    depth=0
    ps::call_site_operand_region_to rest "$rest"
    ps::_gsub_to rest "$rest" '[0-9*]*>+[^[:space:]]*' ''
    ps::_gsub_to rest "$rest" '[0-9*]*<+[^[:space:]]*' ''
    # shellcheck disable=SC2086 # intentional word-split on PowerShell tokens
    for tok in $rest; do
      [[ -z "$tok" ]] && continue
      opens="${tok//[^\(\{]/}"
      closes="${tok//[^\)\}]/}"
      if ((depth > 0)); then
        depth=$((depth + ${#opens} - ${#closes}))
        ((depth < 0)) && depth=0
        continue
      fi
      [[ "$tok" == -* ]] && break
      count=$((count + 1))
      depth=$((${#opens} - ${#closes}))
      ((depth < 0)) && depth=0
      if [[ "$tok" == [\(\{]* ]] || ((depth > 0)); then
        continue
      fi
      if [[ "$tok" != \$* && "$tok" != @* ]]; then
        count_lit=$((count_lit + 1))
      fi
    done
    ((count >= 2 && count_lit >= 1 || piped == 1 && count >= 1)) && return 0
  done
  return 1
}

# True (0) when a bare computed *variable* call is handed a SPLAT — `& $w @p`,
# where `@p` expands a hashtable into -Path/-Value that no probe here can see.
#
# Scoped to the operands of each `& $var` / `. $var` site rather than matched
# anywhere in the command (review of #2848). A whole-command `@name` scan made
# an UNRELATED splat the write signal for a call it has nothing to do with:
# `Write-Output @args; & $py script.py` blocked while the identical command
# without `@args` was allowed, and neither statement writes a file — the same
# class of signal-detected-anywhere over-block this issue exists to close, so
# leaving it would have re-opened it one shape narrower. Every call site is
# walked, and truncation at a statement/pipeline separator or a closing brace
# keeps a later statement's splat out of an earlier call's operands, exactly as
# ps::computed_call_has_positional_write_signal scopes its own count.
#
# Deliberately DIVERGES from that sibling in one respect: it does not stop at
# the first dash-flag. A splat is a parameter supplier wherever it sits, so
# `& $w -Encoding utf8 @p` is the same write hypothesis as `& $w @p`, whereas a
# positional count is only meaningful before the first flag.
#
# `@{…}` (a hashtable literal) and `@(…)` (an array literal) are NOT splats and
# do not match: the token class requires a word character after `@`. That is what
# keeps `foreach ($x in @('a')) { & $w f.txt }` off this arm — the array literal
# is not a splat, and it sits before the call site besides.
ps::computed_call_has_splat_operand() {
  local lc="$1" rest scan
  local re_var='(^|[[:space:]\;\{\}\(\|\&=])[.\&][[:space:]]*(\$\{[^}]*\}[^[:space:]]*|\$[a-z0-9_:?]+)([[:space:]]+|$)(.*)'
  lc="${lc//\`/}"
  lc="${lc,,}"
  scan="$lc"
  while [[ "$scan" =~ $re_var ]]; do
    rest="${BASH_REMATCH[4]}"
    scan="$rest"
    ps::call_site_operand_region_to rest "$rest"
    ps::blank_bracket_interiors_to rest "$rest"
    if [[ "$rest" =~ (^|[[:space:]])@[a-z0-9_:]+ ]]; then
      return 0
    fi
  done
  return 1
}

# True (0) when the call/dot-source target is a DOUBLE-quoted string that
# INTERPOLATES a variable or subexpression — `& "$tool" …`, `& "$(Get-Tool)" …`,
# `& "C:\tools\$ver\x.exe" …`. Grounded in PowerShell `about_Quoting_Rules`:
# a double-quoted string expands `$`-prefixed expressions, so such a target is
# computed; a `$`-free double-quoted string and ANY single-quoted string are
# compile-time constants ("& '$x'" is the literal program name `$x`).
#
# Deliberately does NOT match a constant literal. That is the whole point: a
# blanket quote match makes every `& "script.ps1"` — the ordinary PowerShell
# script-invocation idiom — indistinguishable from `& "$tool"`.
ps::call_target_is_interpolating_string() {
  local lc="${1//\`/}"
  lc="${lc,,}"
  [[ "$lc" =~ (^|[[:space:]\;\{\}\(\|\&=])[.\&][[:space:]]*\"[^\"]*\$ ]]
}

# True (0) when the text MIGHT invoke git and cannot be proven otherwise. This is
# the fail-closed sink's positive test: because the constructs that route here can
# obfuscate the command, we do not trust a negative `commit`/`push` shape match on
# a mangled scan (that is exactly the #740/#903 fail-open class). Instead we ask
# the weaker, mangle-resistant question "could this reach git at all?" and block
# unless the answer is provably no.
#
# Backticks are deleted first (PowerShell's escape char, so `g``it com``mit`
# recovers to `git commit`), and the scan is quote-INTACT so a quoted command word
# (`& 'git' commit`, `git 'commit'`) is still seen. A dynamic-invocation operator
# whose target cannot be resolved statically (`iex`/`invoke-expression`, or a call
# `&` / dot-source `.` of a variable or subexpression) is likewise treated as
# possibly-git. Over-inclusive by construction — it only gates the fail-closed
# branch, so a false positive costs at most an over-block on a command that also
# carries an unparsable construct.
#
# The literal `git` probe is COMMAND-POSITION, not a substring scan (#2592). A
# predecessor of any non-alnum (the earlier shape) fired on hyphenated identifiers
# (`block-dangerous-git`, `NO-GIT`) and on an intermediate path directory
# (`…\Git\bin\bash.exe`), engaging the fail-closed sink for PowerShell that never
# invokes git. Command-position predecessors are statement/pipeline boundaries,
# path separators, and quotes (so `& 'git'` / `C:\…\git.exe` still count); the
# trailing boundary excludes a further `/` or `\` so `git` must be the final path
# component, not a directory name. `.git` stays inert because `.` is not a
# command-position predecessor.
#
# ONE EXEMPTION, AND IT IS NARROW: a quoted string literal in COMPARISON-OPERAND
# position is DATA, and is blanked to `_q_` before the probe re-runs — but only in
# a command that carries no way to execute a computed value at all. Both halves
# are required, and the second is what makes the first safe.
#   (a) the literal's nearest preceding non-whitespace token is a PowerShell
#       comparison operator, reached through an optional `(` / `@(` and through
#       `,`-separated earlier elements of the same list
#       (ps::_is_comparison_operand_context; right-hand operands only);
#   (b) the whole command is provably a READ-ONLY CMDLET PIPELINE — every token at
#       a command position is an allowlisted interrogator, the command carries no
#       EXPANDABLE `"…"` span (whose `$( … )` is itself a command position), and
#       no construct turns a value into a command
#       (ps::_is_readonly_cmdlet_pipeline), which is an allowlist, not a list of
#       known executors.
# The other expandable form, a `@"…"@` here-string, never reaches (b): it is
# blanked out of the command at intake, so ps::classify_git_command refuses it at
# the sink instead, where the blanking happened.
# Under (b) the only thing the matched text can DO with the string is compare it:
# `Get-Process | Where-Object { $_.Name -eq 'git' }` filters objects, and nothing
# in what remains turns the filtered value back into a command word. The
# false-positive class this retires is read-only PowerShell that merely NAMES git
# in a VERBATIM literal (`-eq 'git'`, `-ceq 'git'`, `-in @('git.exe','bash.exe')`,
# `-notin @('git','node')`, `-like 'git*'`), which the script block alone had
# already routed to the sink.
#
# WHAT KEEPS THE QUOTE-INTACT PROBE, and why each one must:
#   `& 'git' commit`, `git 'commit'`      the literal is a call target or an
#                                        argument, never a comparison operand;
#   `'git' -in $names`                    a LEFT-hand operand, which `& 'git' -eq $x`
#                                        makes undecidable, so it is not exempt;
#   `Start-Process 'git' …`, `saps 'git'` likewise, and (b) refuses the command word;
#   `cmd /c 'git push --force'`           (b) refuses the nested shell;
#   and every shape that turns the compared value back into a command word, each
#   refused by (b) because its command word is not an interrogator or its
#   construct is not a pipeline at all:
#     `| % { & $_.Name … }`, `| % { . $_.Name … }`, `| % { iex $_.Name }`,
#     `| % { cmd /c $_.Name }`, `| % { bash -c $_.Name }`, `| % { npx $_.Name }`,
#     `| % { dotnet/cscript/explorer/ssh … $_.Name }`,
#     `| % { Invoke-Item $_.Name }` and its `ii` alias, `Start-Job`, `New-Object`,
#     `New-Service`/`nsv`, `Register-ScheduledTask`/`New-ScheduledTaskAction`,
#     `iwmi`/`Invoke-CimMethod` Win32_Process Create, `schtasks /tr`, `wmic
#     process call create`, `Set-Alias zz $_.Name; zz push --force`,
#     `[Diagnostics.Process]::Start($_.Name, …)`,
#     `[scriptblock]::Create($_.Name).Invoke()`,
#     `$ExecutionContext.InvokeCommand.InvokeScript($_.Name)`;
#   `$n = 'git'; & $n push -f`            `=` is not a comparison operator, and (b)
#                                        refuses the call operator;
#   `-eq "$(cmd /c git push --force)"`    the operand is EXPANDABLE, so building
#                                        it runs a program, and (b) refuses the
#                                        whole command on the `"` alone. The
#                                        executor inside is never the thing being
#                                        recognized.
ps::might_invoke_git() {
  local recovered="${1//\`/}" lc narrowed
  lc="${recovered,,}"
  if [[ "$lc" =~ (^|[[:space:]\;\|\&\(\{\}\"\'/\\:=])git([.]exe)?([^[:alnum:]_/\\]|$) ]]; then
    ps::_is_readonly_cmdlet_pipeline "$1" || return 0
    ps::_blank_comparison_operand_literals_to narrowed "$lc"
    [[ "$narrowed" =~ (^|[[:space:]\;\|\&\(\{\}\"\'/\\:=])git([.]exe)?([^[:alnum:]_/\\]|$) ]] && return 0
  fi
  [[ "$lc" =~ (^|[^[:alnum:]_-])(iex|invoke-expression)([^[:alnum:]_-]|$) ]] && return 0
  ps::call_target_is_bare_subexpression "$recovered" && return 0
  ps::call_target_is_interpolating_string "$recovered" && return 0
  [[ "$lc" =~ (^|[[:space:]\;\|\&\(=])(start-process|saps|start|pwsh|powershell|cmd|wsl)(\.exe)?[[:space:]]+(-[a-z]+[[:space:]]+)?[\(\$] ]] && return 0
  return 1
}

# True (0) when every git invocation in the text is plausibly read-only — fetch,
# log, status, rev-list, merge-base, etc. — with no mutating subcommand visible.
# Used to narrow the fail-closed sink for guards that only care about mutating
# git (#1415): `git fetch | ForEach-Object { }` must not block just because `git`
# appears alongside `{}` grouping.
#
# THE PREDICATE, stated so the list below is derivable rather than remembered. A
# subcommand is NOT read-only when it can create, modify, delete, or overwrite
# content in the working tree or the index; create, delete, move, or rewrite
# local refs or history; alter the stash, the configuration, or repository
# administrative state (object store, reflog, sparse-checkout, submodules); or
# publish to a remote. Everything else stays read-only: the interrogators
# (log/status/diff/show/grep/blame/rev-list/rev-parse/ls-files/ls-tree/ls-remote/
# cat-file/merge-base/describe/shortlog/cherry/range-diff/fsck/verify-*/
# fast-export), the artifact producers that never touch REPOSITORY state
# (archive, bundle, format-patch, request-pull, send-email, mailsplit, diagnose,
# bugreport), the create-only plumbing that can neither overwrite nor delete
# (write-tree, hash-object, commit-tree, merge-tree, pack-objects, index-pack,
# unpack-objects, unpack-file, mktree, mktag), the lossless representation
# rewrite (pack-refs), and the repo-creating forms that cannot destroy existing
# work (clone refuses a non-empty target; init on an existing repo
# re-initializes without data loss).
#
# "ARTIFACT PRODUCER" MEANS REPOSITORY STATE, NOT THE FILESYSTEM. Several of the
# omitted forms take an operator-named output path and will happily truncate it:
# `git archive -o README.md HEAD`, `git diff --output=README.md`,
# `git format-patch -o <dir>`. That is a WRITE, but it is not git mutating the
# repository — it is the operator naming a destination, exactly as `>` would.
# This predicate is about repository state, so those stay read-only BY DESIGN;
# clobbering an explicitly-named output file is out of scope here and belongs to
# the write-side guards, not to a git-subcommand classifier. Recorded so a future
# reader does not mistake the omission for an oversight.
#
# DUAL-MODE SUBCOMMANDS ARE BLOCKED WHOLE, EXCEPT `remote` AND `stash`. `tag` and
# `notes` are listed despite having read-only list forms (`git tag`, `git notes
# list`), so the policy is "a subcommand with any mutating mode is not read-only".
# `remote` and `stash` are judged by their arguments instead, because their
# read-only spellings are routine: bare `git remote`, `remote -v`/`--verbose`
# ending the statement, `remote show`, `remote get-url`, `stash list` and `stash
# show` are cut from the text before the stem tests run. Every other spelling
# (`remote add`/`rename`/`set-url`/`prune`, `stash push`/`pop`/`drop`, bare
# `git stash`, which means push) keeps its stem and blocks, and a mutating form
# anywhere in the command blocks the whole command.
# `branch`, `config`, `bisect`, `reflog`, `rerere`, `submodule`,
# `sparse-checkout`, `commit-graph`, `multi-pack-index`, `worktree`, `subtree`,
# `credential`, `interpret-trailers` (mutating only under `--in-place`), the
# foreign-SCM bridges `svn`/`p4`/`cvsexportcommit`, and the widely-installed
# third-party subcommands `filter-repo`/`lfs`/`annex` follow that precedent
# rather than a fresh argument each — `git svn dcommit`, `git p4 submit`,
# `git filter-repo --force`, `git lfs prune` and `git annex drop` all destroy or
# publish, so each is listed even though every one of them has an interrogator
# mode (`git svn log`, `git lfs ls-files`).
#
# SYNONYMS COUNT AS SEPARATE SPELLINGS. `stage` is git's own documented synonym
# for `add` (git-stage(1): "This is a synonym for git-add"), so listing `add`
# alone left the identical index write reachable under another name. Likewise
# `send-pack` and `http-push` are the plumbing beneath `push` — and crucially
# `send-pack` does NOT run the pre-push hook that `push` runs, so omitting it
# left this guard's own subject matter (hook bypass) wide open. Note the boundary
# class means `--staged` does NOT match `stage` (the trailing `d` is alphanumeric),
# so `git diff --staged` stays read-only.
#
# THE BOUNDARY CLASS EXCLUDES `-` ON PURPOSE, and that is load-bearing in both
# directions. A hyphen neither opens nor closes a token, so an option that merely
# spells a listed word is NOT matched (`--add`, `--prune`, `--force`, PowerShell's
# `-replace`) and neither is a hyphenated sibling (`ls-remote` does not match
# `remote`, `merge-base`/`--no-merges` do not match `merge`, `--tags` does not
# match `tag`) — which is exactly what keeps the #1415 read-only allowance intact.
# The same rule is why `checkout-index`, `sparse-checkout`, `merge-file`,
# `merge-index`, `merge-one-file`, `filter-branch`, `fast-import`,
# `commit-graph`, `multi-pack-index`, `update-index`, `update-ref` and
# `update-server-info` each need their OWN entry instead of riding on
# `checkout`/`merge`/`branch`/`commit`/`update-*`.
#
# THE SCAN IS WHOLE-COMMAND, NOT ARGV-AWARE, so a listed word matches ANYWHERE in
# the text — not only in subcommand position. Three distinct shapes hit this:
#   1. outside the git call entirely — PowerShell's `switch` keyword, a `config`
#      variable name, `git log | Where-Object { $_ -match 'clean' }`;
#   2. INSIDE the git call as a pathspec or ref — `git log -- config/`,
#      `git diff -- src/remote/`, `git show HEAD:docs/notes/a.md`,
#      `git ls-files -- tests/clean/`. Directory names like `add/`, `config/`,
#      `remote/`, `clean/` and `rm/` are common, so this is the widest friction
#      class and the one most likely to surprise;
#   3. as a flag VALUE — `git log --grep clean`.
# All three are fail-SAFE: they route to the fail-closed sink and BLOCK, costing
# friction rather than safety. Narrowing them requires argv-aware parsing of a
# string this function is only ever handed BECAUSE it could not be parsed — so it
# is the same redesign the residual below defers to, not a separate fix.
#
# `fetch` IS A DELIBERATE, DOCUMENTED EXCEPTION. It writes the object store and
# remote-tracking refs, and `git fetch <remote> +<src>:<dst>` can even force-update
# a LOCAL ref, so the allowance is not airtight. It is kept because it is the exact
# case #1415 exists for; listing it would retire that allowance rather than fix it.
#
# RESIDUAL (documented, deferred — same class as the file-header residuals). This
# is a NEGATIVE shape match on SPELLINGS, so three families defeat it and no
# addition to the list above can close any of them:
#   a. THE SUBCOMMAND IS OBSCURED. It only ever runs on commands that ALREADY
#      carry a construct the Bash tokenizer cannot read, so that construct can
#      also hide the subcommand — `git ('cle'+'an') -fdx`, `git $sub -fdx`, a
#      subcommand assembled inside an `iex` payload.
#   b. THE SUBCOMMAND IS NOT IN THE TEXT AT ALL. A user alias resolves at runtime
#      from `.gitconfig`: `git co`, `git ci -m x`, `git unstage f`, `git pf`, or
#      an `!`-shell alias running anything. Nothing in the string names the
#      mutating operation, so un-mangling cannot recover it. This is a strictly
#      DIFFERENT class from (a) and a blocklist can never converge on it.
#   c. THE SUBCOMMAND IS IRRELEVANT. `-c core.pager=./x`, `-c core.editor=./x`,
#      `-c alias.z=!./x`, `--exec-path=.` turn a read-only `git log` into
#      arbitrary local execution.
# The mangle-resistant fix for all three is an allowlist — read-only iff every git
# occurrence is followed by a known interrogator — which is
# ps::git_command_is_interrogation_only below. This blocklist stays the test for
# the `readonly-ok` scope (block-no-verify), so all three residuals still apply
# there, on a best-effort basis. block-dangerous-git owns the destructive forms
# and never consults this function: its `interrogation-ok` scope reads the
# allowlist, which refuses all three. What neither closes is the repository's own
# config: `core.pager` or `core.fsmonitor` in its `.git/config` still runs under
# `git log` or `git status`, the same as in the Bash tool.
ps::git_command_is_readonly() {
  local recovered="${1//\`/}" lc
  lc="${recovered,,}"
  [[ "$lc" =~ (^|[[:space:]\;\|\&\(\{\}\"\'/\\:=])git([.]exe)?([^[:alnum:]_/\\]|$) ]] || return 1
  while [[ "$lc" =~ (^|[^[:alnum:]_.-])(remote([[:space:]]+(-v|--verbose))?[[:space:]]*([\;\|\}\)]|$)|remote[[:space:]]+(show|get-url)|stash[[:space:]]+(list|show))([^[:alnum:]_.-]|$) ]]; do
    lc="${lc/"${BASH_REMATCH[0]}"/ }"
  done
  [[ "$lc" =~ (^|[^[:alnum:]_.-])(add|am|annex|apply|bisect|branch|checkout|checkout-index|cherry-pick|citool|clean|commit)([^[:alnum:]_.-]|$) ]] && return 1
  [[ "$lc" =~ (^|[^[:alnum:]_.-])(commit-graph|config|credential|credential-cache|credential-store|cvsexportcommit|fast-import|filter-branch|filter-repo|gc|gui|http-push|interpret-trailers|lfs)([^[:alnum:]_.-]|$) ]] && return 1
  [[ "$lc" =~ (^|[^[:alnum:]_.-])(maintenance|merge|merge-file|merge-index|merge-one-file|mergetool|multi-pack-index|mv|notes|p4|prune)([^[:alnum:]_.-]|$) ]] && return 1
  [[ "$lc" =~ (^|[^[:alnum:]_.-])(prune-packed|pull|push|quiltimport|read-tree|rebase|receive-pack|reflog|remote|repack)([^[:alnum:]_.-]|$) ]] && return 1
  [[ "$lc" =~ (^|[^[:alnum:]_.-])(replace|rerere|reset|restore|revert|rm|send-pack|sparse-checkout|stage|stash)([^[:alnum:]_.-]|$) ]] && return 1
  [[ "$lc" =~ (^|[^[:alnum:]_.-])(submodule|subtree|svn|switch|symbolic-ref|tag|update-index|update-ref|update-server-info|worktree)([^[:alnum:]_.-]|$) ]] && return 1
  return 0
}

# True (0) when TOK is a plain literal word: characters that cannot carry a
# variable, subexpression, splat, list or concatenation. A quoted string reaches
# the caller as the opaque placeholder `_q_`, which is one.
ps::_is_plain_word() {
  [[ "$1" =~ ^[a-z0-9_.:\\/~*?-]+$ ]]
}

# Judge the operands of one command, given as the tokens after its command word
# (ps::has_unprovable_env_write's tokens). Assigns the number of plain-word
# operands to the variable named by $1 and returns 1 when any operand is not one.
# A `;` or an unmatched `)` ends the command. The value of `-Value` is content,
# not a target, so it is skipped (a parenthesized value whole); every other
# operand, named or positional, may be the path.
ps::_operands_plain_to() {
  local __op_out="$1" __op_a __op_name __op_val __op_depth __op_lit=0 __op_skip=0 __op_rc=0
  shift
  while (($#)); do
    __op_a="$1"
    shift
    [[ "$__op_a" == ';' ]] && break
    if ((__op_skip)); then
      __op_skip=0
      if [[ "$__op_a" == '(' ]]; then
        __op_depth=1
        while (($# && __op_depth > 0)); do
          [[ "$1" == '(' ]] && __op_depth=$((__op_depth + 1))
          [[ "$1" == ')' ]] && __op_depth=$((__op_depth - 1))
          shift
        done
      fi
      continue
    fi
    case "$__op_a" in
    ')') break ;;
    -*)
      __op_name="${__op_a#-}"
      __op_val=""
      if [[ "$__op_name" == *:* ]]; then
        __op_val="${__op_name#*:}"
        __op_name="${__op_name%%:*}"
      fi
      if [[ "$__op_name" == va* ]]; then
        [[ -n "$__op_val" ]] || __op_skip=1
      elif [[ -n "$__op_val" ]]; then
        ps::_is_plain_word "$__op_val" || __op_rc=1
        __op_lit=$((__op_lit + 1))
      fi
      ;;
    *)
      ps::_is_plain_word "$__op_a" || __op_rc=1
      __op_lit=$((__op_lit + 1))
      ;;
    esac
  done
  printf -v "$__op_out" '%s' "$__op_lit"
  return "$__op_rc"
}

# True (0) when the text can write the process environment, or rebind `git`,
# through a target this scan cannot prove is a plain literal. It refuses whatever
# it cannot prove, so a target that is computed, held in a variable, splatted,
# piped in or reached by reflection counts as a write.
#
# Syntax decides, not the spelling of a name: a name built at run time from
# pieces (`'E'+'nv:'`, `'GI'+'T_PAGER'`) is in no text a search could match. The
# ways a command reaches the environment, each read off the syntax:
#   - an assignment to `$env:NAME` or `${env:NAME}`, alone, in a target list
#     (`$env:X, $y = ...`) or as a foreach variable;
#   - a provider cmdlet that stores a value (Set-, New-, Add-, Copy-, Move- and
#     Rename- Item, Content and ItemProperty, their aliases, and `mkdir`, which
#     wraps New-Item). Every operand except the value of `-Value` must be a
#     plain word, and at least one must be present, so a path that is computed,
#     held in a variable, splatted or arriving on the pipeline refuses.
#     Delete-only verbs are left out: they cannot introduce a value. Out-File,
#     `>` and Tee-Object cannot write the Env: drive at all;
#   - a literal provider path into the Env:, Function: or Alias: drive, or a
#     provider-qualified `Environment::`, anywhere in the text. A relative path
#     resolves against the current location, so a write beside a location change
#     (Set-Location, cd, Push-Location) whose target is not a plain word, or is
#     piped in, refuses too;
#   - a word spliced from quoted parts (`Set'-'Item`, `E'nv':X`), which names
#     what the parts spell and not what was written;
#   - a static member (`::`) or a method call (`.Name(`, however the name is
#     spelled and whatever separates the dot from it), which reach
#     SetEnvironmentVariable, InvokeMember and `Invoke`;
#   - ForEach-Object with a member name (`-MemberName`, or a bare word or
#     variable where the script block goes), which calls a method by name;
#   - a call whose target is computed (`& $c`, `& (...)`), and the definition of
#     a function, filter or alias, which rebinds what a command word means;
#   - Add-Type, New-PSDrive and Invoke-Command, which compile code, rename a
#     drive and run a script block the scan cannot read;
#   - a native `env` or `env.exe` command word, bare or by path, which sets the
#     named variables for the command it runs: the write spelled as program
#     arguments instead of a provider path;
#   - a `$( ... )` inside an expandable string, which runs where it is written.
# Not seen: code in a file, and a script block held in a variable and run by a
# cmdlet that accepts one. This guards against a computed write, not against
# every in-process code path.
ps::has_unprovable_env_write() {
  local IFS=$' \t\n'
  local recovered="${1//\`/}" lc opaque s ch head a k j n nlit env_lhs write_head=0 dyn_cd=0
  local -a t=()
  lc="${recovered,,}"
  # shellcheck disable=SC2016  # literal PowerShell `$env:` text, not expansions
  local env_assign='\$\{?env:[^[:space:]=]+[[:space:]]*((\?\?|[-+*/%])?=)'
  [[ "$lc" =~ $env_assign ]] && return 0
  ps::call_target_is_bare_computed "$recovered" && return 0
  ps::opaque_quoted_spans_to opaque "$recovered"
  # shellcheck disable=SC2016  # literal PowerShell `$(` text
  ((PS_QUOTED_SPAN_SAW_EXPANDABLE)) && [[ "$lc" == *'$('* ]] && return 0
  opaque="${opaque,,}"
  for s in "$lc" "$opaque"; do
    s="${s//\$\{env:/}"
    s="${s//\$env:/}"
    [[ "$s" == *env:* || "$s" == *environment:* || "$s" == *function:* || "$s" == *alias:* ]] && return 0
  done
  [[ "$opaque" == *::* || "$opaque" == *'[ref]'* || "$opaque" =~ \.[[:space:]]*[\$a-z0-9_{}:]*\( ]] && return 0
  s="$opaque"
  while [[ "$s" =~ ^(.*)\$\{env:([^\}]*)\}(.*)$ ]]; do
    s="${BASH_REMATCH[1]}\$env:${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
  done
  for ch in ';' '|' '&' '{' '}' $'\n'; do s="${s//"$ch"/ ; }"; done
  for ch in '(' ')' ',' '='; do s="${s//"$ch"/ $ch }"; done
  read -ra t <<<"$s"
  n=${#t[@]}
  for ((k = 0; k < n; k++)); do
    if ((k == 0)) || [[ "${t[k - 1]}" == ';' || "${t[k - 1]}" == '(' ]]; then
      env_lhs=0
      for ((j = k; j < n; j++)); do
        # shellcheck disable=SC2016  # literal PowerShell `$env:` text
        case "${t[j]}" in
        *'$env:'*) env_lhs=1 ;;
        '$'* | '['* | ',' | '(' | ')') ;;
        '=' | in)
          ((env_lhs)) && return 0
          break
          ;;
        *) break ;;
        esac
      done
    fi
    head="${t[k]}"
    [[ "$head" != _q_ && "$head" =~ ^[a-z0-9_.:\\/~*?-]*_q_[a-z0-9_.:\\/~*?-]*$ ]] && return 0
    [[ "$head" =~ ^[a-z0-9_.]+\\([a-z-]+)$ ]] && head="${BASH_REMATCH[1]}"
    a="${t[k + 1]-;}"
    case "$head" in
    function | filter | set-alias | sal | new-alias | nal | add-type | new-psdrive | ndr | mount | invoke-command | icm) return 0 ;;
    env | env.exe | */env | */env.exe | *\\env | *\\env.exe) return 0 ;;
    set-location | sl | cd | chdir | push-location | pushd) ps::_operands_plain_to nlit "${t[@]:k+1}" && ((nlit)) || dyn_cd=1 ;;
    foreach-object | foreach | '%') [[ "$a" == ';' || "$a" == '(' || ("$a" == -* && "$a" != -m*) ]] || return 0 ;;
    set-item | si | new-item | ni | mkdir | md | set-content | sc | add-content | ac | copy-item | cpi | copy | cp | move-item | mi | move | mv | rename-item | rni | ren | set-itemproperty | sp | new-itemproperty | copy-itemproperty | cpp | move-itemproperty | mp | rename-itemproperty | rnp)
      write_head=1
      ps::_operands_plain_to nlit "${t[@]:k+1}" && ((nlit)) || return 0
      ;;
    *) ;;
    esac
  done
  ((write_head && dyn_cd))
}

# True (0) when every git invocation in the text is a built-in INTERROGATOR, read
# off the argv rather than off a list of spellings to refuse. This is the
# allowlist the residual note above ps::git_command_is_readonly names, and it is
# what block-dangerous-git consults (sink scope `interrogation-ok`, #4235): that
# guard owns destructive forms, so it cannot take the blocklist's residuals.
#
# Each git token must be a bare command word, optionally behind `-C <path>`,
# `--no-pager`/`-P`, `--no-optional-locks` or `--literal-pathspecs`, and followed
# by one of the built-ins below as a literal word. That closes the blocklist's
# three residual families:
#   a. an OBSCURED subcommand (`git ('cle'+'an')`, `git $sub`) is not a literal
#      word, so it is not on the list;
#   b. an ALIAS (`git co`) is not on the list, and git never lets an alias shadow
#      a built-in, so `git status` always means status;
#   c. `-c <name>=<value>`, `--exec-path`, `--git-dir` and every other global
#      option outside the four above stop the walk, and what they leave in
#      subcommand position is not on the list;
#   d. an environment WRITE, or a rebinding of `git` itself, refuses, because
#      GIT_PAGER / GIT_EXTERNAL_DIFF turn a read into execution, a changed PATH
#      swaps the git that runs, and a function or alias named `git` runs instead
#      of it. ps::has_unprovable_env_write decides this from the syntax of each
#      write, so a name built at run time from pieces cannot slip past.
# `-C` is compared case-sensitively: git reads `-c` as a config override.
#
# Dual-mode verbs are argument-aware, as in the blocklist's carve-out: `remote`
# alone or `remote -v`/`--verbose` ending the statement, `remote show`, `remote
# get-url`, `stash list`, `stash show`. `grep` (whose `-O` opens files in a
# named program), `ls-remote` and `fetch` (whose `--upload-pack` runs a named
# program against a local repository) and `help` (which can launch a browser)
# are left off on purpose.
#
# A git token inside a quoted string is not a bare command word: the count of
# git tokens the quote-INTACT probe sees must equal the count found in the
# argv, so `& 'git' reset --hard` and `Write-Host 'git clean'; git status` both
# refuse. Every other way ps::might_invoke_git can say yes without a literal git
# token (iex, a quoted or subexpression call target, a launcher) refuses here as
# well, since those can run anything.
ps::git_command_is_interrogation_only() {
  local recovered="${1//\`/}" lc opaque s tok ch i k j sub next n_probe=0 n_git=0
  local -a toks=()
  lc="${recovered,,}"
  ps::has_unprovable_env_write "$1" && return 1
  ps::has_dynamic_invocation "$1" && return 1
  ps::has_launcher "$1" && return 1
  ps::call_target_is_interpolating_string "$recovered" && return 1
  s="$lc"
  while [[ "$s" =~ (^|[[:space:]\;\|\&\(\{\}\"\'/\\:=])git([.]exe)?([^[:alnum:]_/\\]|$) ]]; do
    n_probe=$((n_probe + 1))
    s="${s#*"${BASH_REMATCH[0]}"}"
  done
  ((n_probe > 0)) || return 1
  ps::opaque_quoted_spans_to opaque "$recovered"
  tok=""
  for ((i = 0; i < ${#opaque}; i++)); do
    ch="${opaque:i:1}"
    case "$ch" in
    [[:space:]] | '=')
      [[ -n "$tok" ]] && toks+=("$tok")
      tok=""
      ;;
    ';' | '|' | '&' | '{' | '}' | '(' | ')' | ',')
      [[ -n "$tok" ]] && toks+=("$tok")
      tok=""
      toks+=(';')
      ;;
    *) tok+="$ch" ;;
    esac
  done
  [[ -n "$tok" ]] && toks+=("$tok")
  for ((k = 0; k < ${#toks[@]}; k++)); do
    [[ "${toks[k],,}" =~ (^|[/\\:])git([.]exe)?$ ]] || continue
    n_git=$((n_git + 1))
    j=$((k + 1))
    while ((j < ${#toks[@]})); do
      case "${toks[j]}" in
      -C)
        [[ "${toks[j + 1]-;}" != ';' ]] || return 1
        j=$((j + 2))
        ;;
      --no-pager | -P | --no-optional-locks | --literal-pathspecs) j=$((j + 1)) ;;
      *) break ;;
      esac
    done
    sub="${toks[j]-}"
    next="${toks[j + 1]-;}"
    case "$sub" in
    status | log | show | diff | rev-parse | ls-files | ls-tree | cat-file | describe | blame | shortlog | for-each-ref | show-ref | merge-base | rev-list | name-rev | count-objects | version | cherry | range-diff | check-ignore | check-attr) ;;
    remote)
      case "$next" in
      ';' | show | get-url) ;;
      -v | --verbose) [[ "${toks[j + 2]-;}" == ';' ]] || return 1 ;;
      *) return 1 ;;
      esac
      ;;
    stash)
      case "$next" in
      list | show) ;;
      *) return 1 ;;
      esac
      ;;
    *) return 1 ;;
    esac
  done
  ((n_git == n_probe))
}

# True (0) when the command both names a python3 interpreter TOKEN and carries a
# `-c` inline-code flag. Paired with a raw write indicator by the caller, this is
# the mangle-resistant sink for the interpreter-write lane under the PowerShell
# tool — the python3 analogue of ps::might_invoke_git, following the same SINK
# DOCTRINE: PowerShell is not faithfully bash-tokenizable, so rather than trust a
# precise `python3 -c` scan that successive review rounds defeated (path-qualified
# target, `&{python3}` script block, quoted-`#` comment truncation, block comments,
# arg-splitting), ask the weaker question "could an inline-code python3 write be
# here at all?" and let the caller block on the co-occurrence.
#
# `q` carries the two quote characters so neither appears literally in the regex.
# Both probes run on the quote-INTACT, backtick-recovered text so a quoted
# (`& 'python3'`), path-qualified (`…\python3.exe`), brace-glued (`&{python3`), or
# comment-adjacent python3 — and a `-c` split from it or hidden in an arg list
# (`-ArgumentList '-c',…`) — are all seen; a python3 token inside a here-string is
# not (the caller blanks here-strings first). The `-c` boundary admits whitespace
# or a quote on each side, so `'-c'` matches while a longer token (`-Command`,
# `-Confirm`) does not.
#
# The interpreter token was the LITERAL `python3`, which made this lane a
# spelling floor rather than a rule and carried the Bash lane's #2217 gap here
# too: `python -c`, `py -c`, `py3 -c`, `python2 -c` and `python3.11 -c` all run
# the same inline write. The token is now the python family — `py`/`python`/
# `pypy` plus an optional version suffix — still boundary-anchored on both sides,
# so `mypy`, `spy`, `happy`, `pytest`, `notpython3` and a dotted `os.python3`
# stay inert. This remains the WEAKER sink question by design (see SINK DOCTRINE
# above); the caller still gates on a raw write indicator.
#
# RESIDUAL, restated at its real width: a stdin heredoc (`python3 - <<PY … PY`,
# no `-c`) is a Bash-tool construct. It is covered in the Bash lane as of #2217,
# and remains out of scope here — PowerShell has no heredoc, and its here-string
# analogue is blanked by the caller before this runs.
ps::might_write_via_python3() {
  local recovered="${1//\`/}" lc q="\"'" blanked
  lc="${recovered,,}"
  ps::blank_quoted_spans_to blanked "$1"
  ps::has_launcher "$recovered" && [[ "$blanked" == *'$'* || "$blanked" == *'('* ]] && return 0
  ps::call_target_is_interpolating_string "$recovered" && return 0
  [[ "$lc" =~ (^|[^[:alnum:]_.])(pypy|python|py)[0-9]*([.][0-9]+)*([.]exe)?([^[:alnum:]_.]|$) ]] || return 1
  [[ "$lc" =~ (^|[[:space:]$q])-c([[:space:]$q]|$) ]] && return 0
  [[ "$lc" =~ (^|[[:space:]$q])-c[\$\(] ]] && return 0
  ps::has_special_constructs "$blanked" && return 0
  return 1
}

# True (0) when the command uses a dynamic-invocation form that runs an arbitrary
# string as a command: `iex`/`invoke-expression` (of anything), or a call `&` /
# dot-source `.` of a STRING LITERAL (`& 'git commit …'`, `. "…"`). These defeat
# faithful Bash tokenization exactly as the structural constructs do — the run
# string is opaque to the tokenizer — so they must route to the fail-closed sink
# even when no bracket/backtick construct is present (the fail-open class the
# re-review found: a construct-free `iex '…'` otherwise reached the Bash parser,
# which sees command word `iex`, not git, and passed). A call/dot-source of a bare
# VARIABLE (`& $tool …`) is the genuinely-deferred variable-command-word residual
# and is deliberately NOT routed here. Operates on the quote-INTACT command
# (backticks recovered) so the string-literal forms stay visible.
#
# An unspaced assignment whose RHS is a string-literal call (`$a=& "$tool"`)
# must enter this sink, or the measuring predicates never run (#2984) — the
# mirror image of #2922/#2924, where entry was BROADER than measurement.
# `=` is NOT a generic separator here. about_Assignment_Operators: `=` assigns
# to a variable (`$name = …`, `$scope:name = …`). Putting `=` in the same
# class as `;` `|` `&` also matches data inside quotes (about_Quoting_Rules:
# quoted text is a literal string) and git(1) `-c <name>=<value>` config
# overrides. Those are not assignments. The assignment arm is a separate
# `$name=` / `$scope:name=` alternative, scanned quote-blanked so a quoted
# `$a=& "…"` stays data. Spelled out literally, never shared through a
# variable, for the quote-removal reason the block comment above states.
ps::has_dynamic_invocation() {
  # `q` carries the two quote characters so neither appears literally inside the
  # [[ =~ ]] test (which would derail shellcheck's parser).
  local recovered="${1//\`/}" lc q="\"'" blanked
  lc="${recovered,,}"
  [[ "$lc" =~ (^|[^[:alnum:]_-])(iex|invoke-expression)([^[:alnum:]_-]|$) ]] && return 0
  [[ "$recovered" =~ (^|[[:space:]\;\{\}\(\|\&])[.\&][[:space:]]*[$q] ]] && return 0
  [[ "$recovered" =~ (^|[[:space:]\;\{\}\(\|\&])\$[A-Za-z_][A-Za-z0-9_]*(:[A-Za-z_][A-Za-z0-9_]*)?[[:space:]]*=[[:space:]]*[.\&][[:space:]]*[$q] ]] || return 1
  ps::blank_quoted_spans_to blanked "$recovered"
  [[ "$blanked" =~ \$[A-Za-z_][A-Za-z0-9_]*(:[A-Za-z_][A-Za-z0-9_]*)?[[:space:]]*=[[:space:]]*[.\&] ]]
}

# True (0) when a process launcher / nested shell sits at a command position:
# Start-Process (alias saps) launches a program the same way the Bash guard sees
# through `nice`/`nohup`/`sudo`/`env`; pwsh/powershell/cmd run a nested command
# string, the parity analog of the Bash guard's `sh -c`/`bash -c` see-through,
# and wsl runs its command line inside a Linux distribution (the Bash lane's
# hook::wsl_operand).
# Routed to the sink so ps::might_invoke_git decides — it blocks only when the
# literal `git` is present in the launched argv / command string (`Start-Process
# git -ArgumentList …`, `pwsh -Command 'git …'`), and passes a launcher with no
# git (`Start-Process notepad`, `pwsh -File build.ps1`). This is Bash-PARITY, not
# an airtight boundary; deeper nested-shell escaping (and `cmd /c`'s own quoting)
# is a shared Bash+PS residual.
ps::has_launcher() {
  local lc="${1//\`/}" blanked
  lc="${lc,,}"
  [[ "$lc" =~ (^|[[:space:]\;\|\&\(])(start-process|saps|start|pwsh|powershell|cmd|wsl)(\.exe)?([[:space:]]|$) ]] && return 0
  ps::blank_quoted_spans_to blanked "$lc"
  [[ "$blanked" =~ (^|[[:space:]\;\|\&\(])\$[A-Za-z_][A-Za-z0-9_]*(:[A-Za-z_][A-Za-z0-9_]*)?[[:space:]]*=[[:space:]]*(start-process|saps|start|pwsh|powershell|cmd|wsl)(\.exe)?([[:space:]]|$) ]]
}

# Classify a git/commit-guard command for the resolved tool. Sets PS_SAFE_COMMAND
# (the command the caller should hand to its Bash parser) and returns:
#   0  proceed — parse PS_SAFE_COMMAND (== the original command for the Bash tool)
#   1  allow/skip — a PowerShell command that carries an A2b-deferred construct but
#      is PROVABLY git-free, so none of the git guards' concerns can be present
#   2  block fail-closed — carries a construct the Bash tokenizer cannot faithfully
#      parse AND might reach git; refused by shape rather than guessed safe
#
# Optional third argument `sink_scope`:
#   `mutating` (default) — block when ps::might_invoke_git is true
#   `readonly-ok` — block only when git might be reached AND the visible git use is
#      not read-only (commit/push/reset-class). Lets routine read-only PowerShell
#      through the fail-closed branch (#1415).
#   `interrogation-ok` — for a guard that owns destructive forms (block-dangerous-git,
#      #4235). Relieves ONLY the `special-construct` trigger (`{}`/`()` grouping,
#      backtick, `--%`), and only when every git invocation is a built-in
#      interrogator on ps::git_command_is_interrogation_only's allowlist. Dynamic
#      invocation, launcher and here-string triggers still refuse.
ps::classify_git_command() {
  local tool="$1" cmd="$2" sink_scope="${3:-mutating}" scan
  PS_SAFE_COMMAND="$cmd"
  PS_SINK_TRIGGER=""
  [[ "$tool" == "PowerShell" ]] || return 0

  ps::blank_herestrings "$cmd"
  ps::blank_quoted_spans_to scan "$PS_BLANKED"
  if ((PS_HERESTRING_UNBALANCED)); then
    PS_SINK_TRIGGER="herestring-unbalanced"
  elif ps::has_special_constructs "$scan"; then
    PS_SINK_TRIGGER="special-construct"
  elif ps::has_dynamic_invocation "$PS_BLANKED"; then
    PS_SINK_TRIGGER="dynamic-invocation"
  elif ps::has_launcher "$PS_BLANKED"; then
    PS_SINK_TRIGGER="launcher"
  elif ((PS_HERESTRING_EXPANDABLE_SUBEXPR)); then
    PS_SINK_TRIGGER="herestring-subexpr"
  fi
  if [[ -n "$PS_SINK_TRIGGER" ]]; then
    ((PS_REDUCTION_UNTRUSTED)) && return 2
    #
    # A BLANKED EXPANDABLE HERE-STRING SUSPENDS THE PROOF. `@"` … `"@` is
    # evaluated where it is written, so `$( … )` in its body is a command
    # position: `-eq @"` / `$(cmd /c git push --force)` / `"@` runs git at
    # construction time. The body is gone from PS_BLANKED, so a NO from
    # ps::might_invoke_git is a statement about text the command does not have,
    # not a proof of git-freedom. Refuse by shape instead, exactly as for every
    # other construct this sink cannot settle. A verbatim `@'` … `'@` body is
    # inert text and is unaffected.
    ((PS_HERESTRING_EXPANDABLE)) && return 2
    ps::might_invoke_git "$PS_BLANKED" || return 1
    if [[ "$sink_scope" == "readonly-ok" ]] && ps::git_command_is_readonly "$PS_BLANKED"; then
      return 1
    fi
    if [[ "$sink_scope" == "interrogation-ok" && "$PS_SINK_TRIGGER" == "special-construct" ]] &&
      ps::git_command_is_interrogation_only "$PS_BLANKED"; then
      return 1
    fi
    return 2
  fi
  if ((PS_REDUCTION_UNTRUSTED)); then
    PS_SINK_TRIGGER="${PS_REDUCTION_UNTRUSTED_REASON:-herestring-comment-char}"
    return 2
  fi
  local reduced="${PS_BLANKED//\\//}"
  ps::_gsub_to reduced "$reduced" '[Gg][Ii][Tt]\.[Ee][Xx][Ee]' git
  ps::_gsub_to reduced "$reduced" '\$[A-Za-z_][A-Za-z0-9_]*(:[A-Za-z_][A-Za-z0-9_]*)?[[:space:]]*(\+=|-=|\*=|/=|%=|=)[[:space:]]*' ' '
  # Read by the sourcing guard, not within this library.
  # shellcheck disable=SC2034
  ps::_bash_ready_to PS_SAFE_COMMAND "$reduced"
  return 0
}

# Blank opaque regions for an allowlisted sink trigger so the caller can keep
# checking independently visible command text. Writes the remainder to
# PS_SAFE_COMMAND. An allow token must not fail-open a compound command whose
# sibling segments are ordinary destructive git forms (Codex review on #2667).
#
# Blanking is trigger-shaped:
#   dynamic-invocation — iex / Invoke-Expression / & '…' / . "…" statements
#   launcher           — Start-Process / pwsh / powershell / cmd statements
#   special-construct  — `--%` tails, `{}`/`()` groups, backtick escapes
#   herestring-unbalanced — from the hanging opener through end of input
#   herestring-subexpr: every BALANCED here-string body, which is wider than the
#     trigger itself: a verbatim `@'` body goes too, because the reduction is
#     ps::blank_herestrings rather than a region walk of its own
#
# Statement tails stop at top-level `;` / newline / `|` / `&&` / `||` so a
# pipeline consumer or following statement remains for normal checks.
#
# The no-token family (`herestring-comment-char`, `herestring-opener-untrusted`,
# `herestring-comment-span`, `herestring-orphan-closer`, `bare-cr`) has NO arm
# here and must never reach this function: none of them carries an allow token,
# and block-dangerous-git.sh refuses on PS_REDUCTION_UNTRUSTED at the top of its
# sink loop, ahead of the allow-list question. The `*` default below blanks an unrecognized
# trigger's command to nothing and the caller then exits 0, so an arm-less
# trigger that DID reach a token-granted round would be a general bypass;
# refusing before the question is what keeps that unreachable.
ps::blank_sink_opaque_regions() {
  local cmd="$1" trigger="$2"
  case "$trigger" in
  dynamic-invocation) ps::_blank_cmd_statements "$cmd" "dynamic" ;;
  launcher) ps::_blank_cmd_statements "$cmd" "launcher" ;;
  special-construct) ps::_blank_special_construct_regions "$cmd" ;;
  herestring-unbalanced) ps::_blank_unbalanced_herestring_tail "$cmd" ;;
  herestring-subexpr)
    # The opaque region IS the here-string body, and blanking it is exactly what
    # ps::blank_herestrings already does, so the reduced command keeps every
    # sibling segment the caller must still check. The region walks above cannot
    # stand in for this: ps::_skip_double_quote_to pairs the `"` of an `@"`
    # opener with the `"` of its `"@` closer, so a here-string body is copied
    # through untouched and the caller's bounded re-classification loop makes no
    # progress at all: it would exhaust its attempt budget with a visible
    # `git reset --hard` sibling never checked.
    #
    # WHAT THIS ARM DOES NOT FIX. The same no-progress loop is still reachable
    # through the `special-construct` arm above, for a here-string this function
    # does not recognize as one (an opener with trailing whitespace) or a second
    # opener sitting on a closer line, which the opener scan never rescans. Under
    # an `ps-unparsable-special-construct` token those shapes now spend the
    # caller's budget and are refused as budget-exhausted, rather than read; the
    # opener model is what would let them be read.
    ps::blank_herestrings "$cmd"
    # shellcheck disable=SC2034
    PS_SAFE_COMMAND="$PS_BLANKED"
    ;;
  *)
    # shellcheck disable=SC2034
    PS_SAFE_COMMAND=""
    ;;
  esac
}

# True when CMD at index IDX is a statement/pipeline boundary predecessor
# (start, whitespace, or `;|&{}()`), so a following word is in command position.
ps::_at_command_position() {
  local cmd="$1" idx="$2" prev
  ((idx == 0)) && return 0
  prev="${cmd:idx-1:1}"
  [[ "$prev" == [[:space:]\;\|\&\{\}\(\)] ]]
}

# Consume a double-quoted span starting at IDX (points at "); assigns the end
# index (one past the closer, or past end of string if unbalanced) to VARNAME.
ps::_skip_double_quote_to() {
  local __dq_cmd="$2" __dq_i="$3" __dq_n=${#2} __dq_c
  __dq_i=$((__dq_i + 1))
  while ((__dq_i < __dq_n)); do
    __dq_c="${__dq_cmd:__dq_i:1}"
    if [[ "$__dq_c" == '`' ]]; then
      __dq_i=$((__dq_i + 2))
      continue
    fi
    if [[ "$__dq_c" == '"' ]]; then
      printf -v "$1" '%s' "$((__dq_i + 1))"
      return 0
    fi
    __dq_i=$((__dq_i + 1))
  done
  printf -v "$1" '%s' "$__dq_n"
}

# Consume a single-quoted span starting at IDX (points at ').
ps::_skip_single_quote_to() {
  local __sq_cmd="$2" __sq_i="$3" __sq_n=${#2} __sq_c
  __sq_i=$((__sq_i + 1))
  while ((__sq_i < __sq_n)); do
    __sq_c="${__sq_cmd:__sq_i:1}"
    if [[ "$__sq_c" == "'" ]]; then
      printf -v "$1" '%s' "$((__sq_i + 1))"
      return 0
    fi
    __sq_i=$((__sq_i + 1))
  done
  printf -v "$1" '%s' "$__sq_n"
}

# Advance IDX to the end of the current statement/pipeline element at depth 0
# (stop before top-level `;`, newline, `|`, `&&`, `||`). Quote- and depth-aware.
ps::_skip_statement_tail_to() {
  local __st_cmd="$2" __st_i="$3" __st_n=${#2} __st_depth=0 __st_c
  while ((__st_i < __st_n)); do
    __st_c="${__st_cmd:__st_i:1}"
    if ((__st_depth == 0)); then
      if [[ "$__st_c" == "'" ]]; then
        ps::_skip_single_quote_to __st_i "$__st_cmd" "$__st_i"
        continue
      fi
      if [[ "$__st_c" == '"' ]]; then
        ps::_skip_double_quote_to __st_i "$__st_cmd" "$__st_i"
        continue
      fi
      if [[ "$__st_c" == ';' || "$__st_c" == $'\n' || "$__st_c" == '|' ]] ||
        [[ "$__st_c" == '&' && "${__st_cmd:__st_i+1:1}" == '&' ]]; then
        printf -v "$1" '%s' "$__st_i"
        return 0
      fi
    fi
    case "$__st_c" in
    '{' | '(') __st_depth=$((__st_depth + 1)) ;;
    '}' | ')') ((__st_depth > 0)) && __st_depth=$((__st_depth - 1)) ;;
    *) ;;
    esac
    __st_i=$((__st_i + 1))
  done
  printf -v "$1" '%s' "$__st_n"
}

# ps::_bash_ready_to <varname> <text>: TEXT with each `;` or `&` that opens a
# statement dropped. PowerShell reads both there (an empty statement, and the
# `&` call operator, as in `& $py script.py`); bash's grammar has neither, so the
# shfmt reader would refuse the reduced text. A blanked statement leaves the
# first kind, as in `Write-Host  ;  ; git status`. What runs is unchanged:
# `& $py x` calls the command `$py` names, which is the segment `$py x`. Quoted
# spans and `#` comments are copied as they are; `&&` and a `&` after a word are
# kept.
ps::_bash_ready_to() {
  local __br_cmd="$2" __br_i=0 __br_n=${#2} __br_c __br_end __br_out="" __br_word=0
  while ((__br_i < __br_n)); do
    __br_c="${__br_cmd:__br_i:1}"
    case "$__br_c" in
    "'" | '"')
      if [[ "$__br_c" == "'" ]]; then
        ps::_skip_single_quote_to __br_end "$__br_cmd" "$__br_i"
      else
        ps::_skip_double_quote_to __br_end "$__br_cmd" "$__br_i"
      fi
      __br_out+="${__br_cmd:__br_i:__br_end-__br_i}"
      __br_i=$__br_end
      __br_word=1
      continue
      ;;
    '#')
      if [[ "${__br_out: -1}" == '' || "${__br_out: -1}" == [[:space:]\;\|\&] ]]; then
        __br_end="${__br_cmd:__br_i}"
        __br_end="${__br_end%%$'\n'*}"
        __br_out+="$__br_end"
        __br_i=$((__br_i + ${#__br_end}))
        continue
      fi
      __br_word=1
      ;;
    ';' | $'\n')
      if [[ "$__br_c" == ';' ]] && ((!__br_word)); then
        __br_out+=' '
        __br_i=$((__br_i + 1))
        continue
      fi
      __br_word=0
      ;;
    '&' | '|')
      if [[ "${__br_cmd:__br_i+1:1}" == "$__br_c" ]]; then
        __br_out+="$__br_c$__br_c"
        __br_i=$((__br_i + 2))
        __br_word=0
        continue
      fi
      if [[ "$__br_c" == '&' ]] && ((!__br_word)); then
        __br_out+=' '
        __br_i=$((__br_i + 1))
        continue
      fi
      __br_word=0
      ;;
    [[:space:]]) ;;
    *) __br_word=1 ;;
    esac
    __br_out+="$__br_c"
    __br_i=$((__br_i + 1))
  done
  printf -v "$1" '%s' "$__br_out"
}

# Blank dynamic-invocation or launcher statements in CMD. KIND is `dynamic` or
# `launcher`. Writes PS_SAFE_COMMAND.
ps::_blank_cmd_statements() {
  local cmd="$1" kind="$2" n=${#1} i=0 out="" c lc end blank_from j
  while ((i < n)); do
    c="${cmd:i:1}"
    if [[ "$c" == "'" || "$c" == '"' ]]; then
      if [[ "$c" == "'" ]]; then
        ps::_skip_single_quote_to end "$cmd" "$i"
      else
        ps::_skip_double_quote_to end "$cmd" "$i"
      fi
      out+="${cmd:i:end-i}"
      i=$end
      continue
    fi
    blank_from=-1
    if ps::_at_command_position "$cmd" "$i"; then
      lc="${cmd:i}"
      lc="${lc,,}"
      case "$kind" in
      dynamic)
        if [[ "$lc" =~ ^(iex|invoke-expression)([^a-z0-9_-]|$) ]]; then
          if [[ "$lc" == iex* ]]; then blank_from=$((i + 3)); else blank_from=$((i + 18)); fi
        elif [[ "$c" == '&' || "$c" == '.' ]]; then
          j=$((i + 1))
          while ((j < n)) && [[ "${cmd:j:1}" == [[:space:]] ]]; do j=$((j + 1)); done
          if ((j < n)) && [[ "${cmd:j:1}" == "'" || "${cmd:j:1}" == '"' ]]; then
            blank_from=$i
          fi
        fi
        ;;
      launcher)
        if [[ "$lc" =~ ^(start-process|saps|start|pwsh|powershell|cmd|wsl)(\.exe)?([^a-z0-9_-]|$) ]]; then
          blank_from=$i
        fi
        ;;
      *) ;;
      esac
    fi
    if ((blank_from >= 0)); then
      ps::_skip_statement_tail_to i "$cmd" "$blank_from"
      out+=" "
      continue
    fi
    out+="$c"
    i=$((i + 1))
  done
  # shellcheck disable=SC2034
  PS_SAFE_COMMAND="$out"
}

# Blank special-construct opaque regions: `--%` through statement end, matched
# `{}`/`()` groups, and backtick escapes. Writes PS_SAFE_COMMAND.
ps::_blank_special_construct_regions() {
  local cmd="$1" n=${#1} i=0 out="" c end depth open close
  while ((i < n)); do
    c="${cmd:i:1}"
    if [[ "$c" == "'" || "$c" == '"' ]]; then
      if [[ "$c" == "'" ]]; then
        ps::_skip_single_quote_to end "$cmd" "$i"
      else
        ps::_skip_double_quote_to end "$cmd" "$i"
      fi
      out+="${cmd:i:end-i}"
      i=$end
      continue
    fi
    if [[ "$c" == '`' ]]; then
      i=$((i + 2))
      out+=" "
      continue
    fi
    if [[ "${cmd:i:3}" == '--%' ]]; then
      ps::_skip_statement_tail_to end "$cmd" "$i"
      i=$end
      out+=" "
      continue
    fi
    if [[ "$c" == '{' || "$c" == '(' ]]; then
      open="$c"
      if [[ "$open" == '{' ]]; then close='}'; else close=')'; fi
      depth=1
      i=$((i + 1))
      while ((i < n && depth > 0)); do
        c="${cmd:i:1}"
        if [[ "$c" == "'" ]]; then
          ps::_skip_single_quote_to i "$cmd" "$i"
          continue
        fi
        if [[ "$c" == '"' ]]; then
          ps::_skip_double_quote_to i "$cmd" "$i"
          continue
        fi
        if [[ "$c" == '`' ]]; then
          i=$((i + 2))
          continue
        fi
        if [[ "$c" == "$open" ]]; then
          depth=$((depth + 1))
        elif [[ "$c" == "$close" ]]; then
          depth=$((depth - 1))
        fi
        i=$((i + 1))
      done
      out+=" "
      continue
    fi
    out+="$c"
    i=$((i + 1))
  done
  # shellcheck disable=SC2034
  PS_SAFE_COMMAND="$out"
}

# Blank from an unbalanced here-string opener through end of input. Writes
# PS_SAFE_COMMAND (prefix before the hanging opener, if any).
ps::_blank_unbalanced_herestring_tail() {
  local cmd="$1" line out="" pending="" in_hs=0 hs_quote=""
  local -a hs_lines=()
  ps::_split_lines_to hs_lines "$cmd"
  for line in "${hs_lines[@]}"; do
    line="${line%$'\r'}"
    if ((in_hs)); then
      if [[ "${line:0:2}" == "${hs_quote}@" ]]; then
        out+="${pending}${line:2}"$'\n'
        pending=""
        in_hs=0
        hs_quote=""
      fi
      continue
    fi
    if ps::line_confirms_herestring_opener "$line"; then
      hs_quote="${line: -1}"
      pending="${line%??}"
      in_hs=1
      continue
    fi
    out+="${line}"$'\n'
  done
  if ((in_hs)); then
    # Hanging opener: keep only the prefix before it; drop the opaque tail.
    # shellcheck disable=SC2034
    PS_SAFE_COMMAND="$out$pending"
    return 0
  fi
  # shellcheck disable=SC2034
  PS_SAFE_COMMAND="${out%$'\n'}"
}

# One line naming the construct that actually routed this command to the sink,
# plus what to do about it. Each of the five triggers needs different advice:
# "remove the unparsable construct" is unactionable for a launcher or a dynamic
# invocation, because there is no such construct to remove (#1968). Each line
# must also stay true of every command that reaches it — advice that describes
# only part of a trigger's shape space is the same unactionable dead end in a
# different disguise.
ps::print_sink_trigger_line() {
  local closer
  case "$PS_SINK_TRIGGER" in
  herestring-unbalanced)
    case "$PS_HERESTRING_QUOTE" in
    "'") closer="the '@ terminator" ;;
    '"') closer="the \"@ terminator" ;;
    *) closer="the terminator matching the opener (@' closes with '@, @\" closes with \"@)" ;;
    esac
    echo "Trigger: an unbalanced here-string. Close it: $closer must start at column 0." >&2
    ;;
  special-construct)
    echo "Trigger: a construct the guard cannot tokenize (backtick, '--%', subexpression, or {}/() grouping). Rewrite it as flat statements (unroll the loop or grouping, one command per line), or use the Bash tool." >&2
    ;;
  dynamic-invocation)
    echo "Trigger: a dynamic invocation (iex/Invoke-Expression, or a call '&' / dot-source '.' with a quoted-string target, a constant one included). Drop the iex/'&'/'.' and write the program as a plain command word, or use the Bash tool." >&2
    ;;
  launcher)
    echo "Trigger: a process launcher or nested shell (Start-Process/saps/start, pwsh, powershell, cmd). Run the launched command directly ('git status', not \"pwsh -Command 'git status'\"; for a repo script, 'Set-Location <dir>; & ./<script>.ps1'), or use the Bash tool." >&2
    ;;
  herestring-subexpr)
    echo "Trigger: an expandable here-string (@\" … \"@) containing '\$( … )'. Use a verbatim here-string (@' … '@) or compute the value into a variable first, or use the Bash tool." >&2
    ;;
  herestring-comment-char)
    echo "Trigger: a here-string opener (@' or @\") on a line that also contains a '#'. Drop the comment or move the opener to a line of its own, or use the Bash tool." >&2
    ;;
  herestring-opener-untrusted)
    echo "Trigger: a here-string opener (@' or @\") on a line that also contains a quote, backslash, or backtick. Move the opener to a line of its own, or use the Bash tool." >&2
    ;;
  herestring-comment-span)
    echo "Trigger: a here-string opener (@' or @\") after a '<#' block-comment opener. Close the block comment before the here-string, or use the Bash tool." >&2
    ;;
  herestring-orphan-closer)
    echo "Trigger: a here-string closer ('@ or \"@) at column zero with no confirmed opener. Write a balanced here-string, or use the Bash tool." >&2
    ;;
  bare-cr)
    echo "Trigger: a carriage return that is not part of a CRLF pair. Use LF or CRLF line endings, or use the Bash tool." >&2
    ;;
  *)
    echo "Rewrite the command in PowerShell without the unparsable construct, or run it via the Bash tool." >&2
    ;;
  esac
}

# Shell-agnostic block text for a PowerShell command the guard cannot parse with
# confidence. The sink is gated by ps::might_invoke_git (possibly-git, not is-git),
# so the headline must not claim a git command is present — iex / a computed call
# / a computed launcher can reach here with no git token at all (#2662).
# Printed to stderr by the caller before it exits 2.
ps::print_unparsable_block_message() {
  ps::_sink_once || return 0
  local lc="${1,,}"
  echo "BLOCKED: this PowerShell command cannot be parsed with confidence." >&2
  ps::print_sink_trigger_line
  if (($# == 0)) || [[ "$lc" =~ (^|[^a-z0-9_-])git[[:space:]]([^\;\|\&]*[[:space:]])?commit([^a-z0-9_-]|$) ]]; then
    echo "The canonical PowerShell commit form (a here-string piped to 'git commit -F -') is:" >&2
    echo "  @'" >&2
    echo "  <subject>" >&2
    echo "  '@ | git commit -F -" >&2
    echo "or commit via the Bash tool (/source-control:commit)." >&2
  fi
  # Honor the same ps-unparsable-<trigger> tokens the git-guard message names, so
  # following that printed advice also clears this guard on a mutating shape (#4252).
  ps::print_sink_token_line block-dangerous-git
}

# The last line of both sink messages: the user's allow token for this trigger,
# which block-no-verify and block-dangerous-git both honor, or none.
# $1 = the other guard the token also clears. The grantable tokens are
# ps-unparsable-dynamic-invocation, ps-unparsable-launcher,
# ps-unparsable-special-construct, ps-unparsable-herestring-unbalanced and
# ps-unparsable-herestring-subexpr; scripts/check-guardrails-ps-differential.sh
# reads them from this file.
ps::print_sink_token_line() {
  case "$PS_SINK_TRIGGER" in
  herestring-comment-char | herestring-opener-untrusted | herestring-comment-span | herestring-orphan-closer | bare-cr)
    echo "No allow token exists for this shape; rewrite it." >&2
    return
    ;;
  *) ;;
  esac
  echo "False positive: the user adds ps-unparsable-${PS_SINK_TRIGGER:-<trigger>} to block_dangerous_git_allow; it clears $1 too." >&2
}

# The sink messages are printed once per call and trigger. Under run-guards.sh
# the guards that print them share one shell and one deny reason, and on the
# same trigger they name the same token, so a second copy adds nothing. Two
# guards that refuse on different triggers each print theirs: one token would
# not clear both. $1 = the key: "budget", or empty for the current trigger.
_PS_SINK_SAID=" "
ps::_sink_once() {
  local key="${1:-trigger:${PS_SINK_TRIGGER:-}}"
  [[ "$_PS_SINK_SAID" == *" $key "* ]] && return 1
  _PS_SINK_SAID+="$key "
}

# A PowerShell command still unreadable after the caller set aside five
# allowed sink shapes. Printed to stderr by the caller before it exits 2.
ps::print_sink_budget_message() {
  ps::_sink_once budget || return 0
  echo "BLOCKED: this PowerShell command is still unparsable after five allowed sink shapes were set aside, and could reach git. No allow token clears this; split it into smaller commands." >&2
}

# Shell-agnostic block text for a PowerShell command block-dangerous-git cannot
# parse with confidence and that could reach git. That guard also owns destructive
# non-commit forms, so its message names them rather than the commit form. The
# headline does not assert that a git command is present — the sink is possibly-git
# (#2662). Printed to stderr by the caller before it exits 2.
ps::print_unparsable_git_block_message() {
  ps::_sink_once || return 0
  echo "BLOCKED: this PowerShell command cannot be parsed with confidence and could reach git." >&2
  ps::print_sink_trigger_line
  # Sink-shape allow tokens (ps-unparsable-<trigger>) are distinct from destructive
  # form tokens so an existing allow-list value cannot silently open this branch (#2664).
  ps::print_sink_token_line block-no-verify
}

# True (0) when a PowerShell command authors file content in a way that bypasses
# the Write/Edit hook gate. Covered surface:
#   - content-authoring cmdlets: Set-Content, Add-Content, Out-File, Tee-Object
#     (and the `ac` / `tee` aliases; `sc` only in its Set-Content form, since it is
#     sc.exe in PS 7);
#   - New-Item (alias `ni`) with -Value; the Export-* serialize-to-file family
#     (alias `epcsv`);
#   - .NET file writes: [IO.File]::WriteAllText/AppendAllText/WriteAllLines and
#     StreamWriter;
#   - a stdout redirect (`>`/`>>`, not the `$null` discard) whose producer is a
#     content emitter (echo / Write-Output / Write-Host, a bare string /
#     here-string literal, or a `$variable` / subexpression value) — producer-
#     scoped to match the Bash guard, which allows `<tool> ... > out` (the
#     producer is the tool, not a content author);
#   - iex / invoke-expression, whose run string is opaque here — fail closed,
#     mirroring the git guards' sink;
#   - a call/dot-source of a COMPUTED target (`& ('Set-'+'Content') …`,
#     `& $w -Value …`, `& $w > f`, `& $w @p`) when a write indicator is also
#     present — not the bare `& $tool …` / `. $PROFILE` residual (#2722), and not
#     a bare-variable target merely accompanied by grouping (#2848).
# Backticks are deleted before matching so an escape-obfuscated name (`Set``-Content`)
# resolves to its real form.
#
# SCOPE: this covers the write-GATE bypass only. Secret-pattern and hardcoded-path
# CONTENT scanning of PowerShell writes stays on the Write|Edit-matched guards;
# scanning PowerShell write content is deferred to A2b.
# PS_WRITE_BYPASS_ARM names the arm behind the last 0 return when a caller needs a
# message specific to it: "computed-positional" for the positional-operand probe,
# empty for every other arm.
PS_WRITE_BYPASS_ARM=""
ps::write_bypass() {
  local cmd="$1" scan lcs seg head lcq lcq_bt blanked_gate opaque_gate
  PS_WRITE_BYPASS_ARM=""
  ps::blank_herestrings "$cmd"
  ((PS_REDUCTION_UNTRUSTED)) && return 0

  ps::fold_escaped_brace_closers_to lcq "$PS_BLANKED"
  lcq_bt="${lcq,,}"
  lcq="${lcq//\`/}"
  lcq="${lcq,,}"
  ps::quoted_call_names_writer "$lcq" && return 0
  if ps::call_target_is_bare_computed "$lcq"; then
    ps::blank_quoted_spans_to blanked_gate "$lcq_bt"
    blanked_gate="${blanked_gate//\`/}"
    ps::_gsub_to blanked_gate "$blanked_gate" '[0-9*]*>&[0-9]+' ''
    ps::opaque_quoted_spans_to opaque_gate "$lcq_bt"
    opaque_gate="${opaque_gate//\`/}"
    ps::_gsub_to opaque_gate "$opaque_gate" '[0-9*]*>&[0-9]+' ''
    if ps::call_target_is_bare_subexpression "$blanked_gate" ||
      [[ "$blanked_gate" == *'--%'* ]] ||
      ps::computed_call_has_splat_operand "$blanked_gate" ||
      [[ "$blanked_gate" == *'>'* ]] ||
      [[ "$blanked_gate" =~ [[:space:]]-va[a-z]*([[:space:]]|:) ]]; then
      return 0
    fi
    if ps::computed_call_has_positional_write_signal "$opaque_gate" "$lcq_bt"; then
      # shellcheck disable=SC2034 # read by the sourcing guard
      PS_WRITE_BYPASS_ARM="computed-positional"
      return 0
    fi
  fi

  ps::blank_quoted_spans_to scan "$PS_BLANKED"
  scan="${scan//\`/}"
  lcs="${scan,,}"

  if [[ "$lcs" =~ (^|[[:space:]\;\|\&\(\\])(set-content|add-content|out-file|tee-object|ac|tee)([[:space:]]|$) ]]; then
    return 0
  fi
  if [[ "$lcs" =~ (^|[[:space:]\;\|\&\(])sc[[:space:]] ]] &&
    [[ "$lcs" =~ [[:space:]]-(va[a-z]*|path|literalpath|lp|stream)([[:space:]]|:) ]]; then
    return 0
  fi

  if [[ "$lcs" =~ (^|[[:space:]\;\|\&\(\\])(iex|invoke-expression)([[:space:]]|$) ]]; then
    return 0
  fi
  if [[ "$lcs" =~ (^|[[:space:]\;\|\&\(\\])(new-item|ni)([[:space:]]) ]] &&
    [[ "$lcs" =~ [[:space:]]-va[a-z]*([[:space:]]|:) ]]; then
    return 0
  fi
  if [[ "$lcs" =~ (^|[[:space:]\;\|\&\(\\])(export-[a-z]+|epcsv)([[:space:]]|$) ]]; then
    return 0
  fi
  if [[ "$lcs" =~ io\.file\][^:]*::[[:space:]]*(writeall|appendall) ]] ||
    [[ "$lcs" =~ streamwriter ]]; then
    return 0
  fi

  ps::_gsub_to lcs "$lcs" '[0-9*]*>&[0-9]+' ''
  local norm="${lcs//[|;&]/$'\n'}"
  local -a seg_lines=()
  ps::_split_lines_to seg_lines "$norm"
  for seg in "${seg_lines[@]}"; do
    seg="${seg#"${seg%%[![:space:]]*}"}"
    [[ "$seg" == *'>'* ]] || continue
    # Exclude the `$null` discard (PowerShell's /dev/null).
    # portability-ok: `\>` escapes a literal `>` inside a bash [[ =~ ]] ERE, it
    # is not GNU grep's `\>` word-boundary — no external grep/sed is involved.
    [[ "$seg" =~ \>\>?[[:space:]]*\$null([[:space:]]|$) ]] && continue
    seg="${seg//[()]/}"
    seg="${seg//\{/}"
    seg="${seg//\}/}"
    seg="${seg#"${seg%%[![:space:]]*}"}"
    head="${seg%%[[:space:]]*}"
    head="${head##*\\}"
    [[ "$seg" == '>'* ]] && return 0
    case "$head" in
    echo | write | write-output | write-host | write-error | write-warning | \
      write-verbose | write-debug | write-information | \
      "${PS_HERESTRING_PLACEHOLDER,,}") return 0 ;;
    '$'*) return 0 ;;
    '['*) return 0 ;;
    *) ;;
    esac
    [[ "$head" =~ ^[0-9]+([.][0-9]+)?$ ]] && return 0
  done
  return 1
}
