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
#      reach git at all?" — backticks recovered, scan quote-INTACT, plus dynamic
#      invocation (iex / call / dot-source) — and blocks unless the answer is no.
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

# Guard against double-sourcing.
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
# Set by ps::classify_git_command when a command routes to the fail-closed sink:
# which of the four triggers fired (`herestring-unbalanced`, `special-construct`,
# `dynamic-invocation`, `launcher`), empty otherwise. Read by the block messages
# (so they name the construct actually present) and by the callers' telemetry (so
# the four sink shapes are distinguishable in aggregate rather than collapsed into
# one `powershell-unparsable` token that hides which one over-blocks).
PS_SINK_TRIGGER=""
# Set by ps::classify_git_command — the command the caller should parse. Read by
# the sourcing guard, not within this library.
# shellcheck disable=SC2034
PS_SAFE_COMMAND=""

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
  # INTAKE NORMALIZATION. Every PowerShell lane in every guard reaches the
  # library through this function (`ps::classify_git_command` and
  # `ps::write_bypass` both call it first, and the one direct caller reads
  # PS_BLANKED), so normalizing here is what makes the whole file's
  # `[[:space:]]` boundaries agree with PowerShell's tokenizer. Without it
  # `& $w<U+00A0>f.txt x` — a working, parse-clean `Set-Content <path> <value>` —
  # matched no call site in any measuring probe and fell through ALLOWED (#2928).
  ps::normalize_token_separating_spaces "$1"
  local cmd="$PS_NORMALIZED"
  local line out="" pending="" in_hs=0 hs_quote="" first2 rest closer opener_scan
  PS_HERESTRING_UNBALANCED=0
  PS_HERESTRING_QUOTE=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if ((in_hs)); then
      first2="${line:0:2}"
      closer="${hs_quote}@" # '@ or "@
      if [[ "$first2" == "$closer" ]]; then
        # Column-zero closer. Keep the text after the two-char closer on the same
        # logical line as the opener's prefix + placeholder.
        rest="${line:2}"
        out+="${pending}${rest}"$'\n'
        pending=""
        in_hs=0
        hs_quote=""
      fi
      # A body line (no column-zero closer) is dropped.
      continue
    fi
    # An opener is `@'` or `@"` as the final two characters of the line — as a
    # TOKEN, not as the tail of an ordinary quoted string (`Write-Output '@'`
    # ends in the characters @' but is a plain string; treating it as an opener
    # would swallow following code lines into a phantom here-string body).
    # Distinguish by stripping PAIRED quote spans first: a real opener's quote
    # is unpaired, so its `@'` survives, while `'@'` / `'foo@'` disappear.
    # One `sed` per line, not two: the expressions apply in order, so the
    # double-quote strip still sees the single-quote-stripped line.
    opener_scan=$(printf '%s' "$line" | sed -E -e "s/'[^']*'//g" -e 's/"([^"\\]|\\.)*"//g')
    if [[ "$opener_scan" == *"@'" || "$opener_scan" == *'@"' ]]; then
      hs_quote="${line: -1}" # ' or "
      pending="${line%??}${PS_HERESTRING_PLACEHOLDER}"
      in_hs=1
      continue
    fi
    out+="${line}"$'\n'
  done < <(printf '%s\n' "$cmd") # not <<<: a >=64KiB here-string deadlocks (see hardcoded-path-patterns.sh)

  if ((in_hs)); then
    # Opener with no column-zero closer: ambiguous extent. Blanking to end could
    # swallow a trailing command (e.g. `| git commit --no-verify`) into the inert
    # placeholder, so surface the raw command and flag unbalanced instead.
    PS_HERESTRING_UNBALANCED=1
    PS_HERESTRING_QUOTE="$hs_quote"
    PS_BLANKED="$cmd"
    return 0
  fi
  PS_BLANKED="${out%$'\n'}"
}

# Crude, SCAN-ONLY strip of single- and double-quoted spans, so that structural
# detection and commit/push shaping ignore characters inside message text. Never
# fed to a parser.
#
# LEFT TO RIGHT, FIRST OPENER OWNS ITS SPAN. This used to be a `sed` with two
# independent expressions — `s/'[^']*'//g` then `s/"[^"]*"//g` — neither of which
# had any notion of which quote style opened first. An apostrophe inside a
# DOUBLE-quoted string is a literal character to PowerShell, but the single-quote
# expression treated it as a delimiter, so the span it deleted ran from the
# apostrophe in one double-quoted string to the apostrophe in the next — taking
# everything between them with it:
#
#   in:  Write-Host "a'b"; & ('g'+'it') push --force; Write-Host "c'd"
#   out: Write-Host
#
# That is not a measurement error, it is the ERASURE of the command every
# sink-trigger scan is about to look at. With the `(` gone, has_special_constructs
# saw no construct, has_dynamic_invocation saw no call, has_launcher saw no
# launcher — so classify_git_command never entered the fail-closed sink at all,
# and the same deletion hid a computed writer call from write_bypass. Two
# ordinary strings that happen to contain apostrophes ("Kyle's build") were a
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
#   - HONORING the escape (what `ps::_skip_double_quote` does, correctly, in the
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
ps::blank_quoted_spans() {
  local text="$1" out="" i=0 n j q found c
  n=${#text}
  while ((i < n)); do
    q="${text:i:1}"
    if [[ "$q" == "'" || "$q" == '"' ]]; then
      found=0
      for ((j = i + 1; j < n; j++)); do
        c="${text:j:1}"
        [[ "$c" == $'\n' ]] && break
        # Ambiguous escape context in a double-quoted span — stop looking and
        # fall through to the delete-nothing branch below.
        if [[ "$q" == '"' && "$c" == '`' ]]; then
          for ((; j < n; j++)); do [[ "${text:j:1}" == $'\n' ]] && break; done
          break
        fi
        if [[ "$c" == "$q" ]]; then
          # A DOUBLED quote is PowerShell's other escape for a delimiter
          # (`'it''s'`, `"say ""hi"""`), so this candidate closer may not be one.
          # Same resolution as the backtick: refuse the question, delete nothing.
          if [[ "${text:j+1:1}" == "$q" ]]; then
            for ((; j < n; j++)); do [[ "${text:j:1}" == $'\n' ]] && break; done
            break
          fi
          found=1
          break
        fi
      done
      if ((found)); then
        i=$((j + 1))
        continue
      fi
      # Unterminated (or escape-ambiguous) on this line: extent is ambiguous, so
      # delete nothing. `j` already sits on the newline (or at the end), so copy
      # the rest verbatim in one slice — this also keeps the walk linear.
      out+="${text:i:j-i}"
      i=$j
      continue
    fi
    out+="$q"
    i=$((i + 1))
  done
  printf '%s' "$out"
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
ps::fold_escaped_brace_closers() {
  local s="$1" out="" i n ch
  n=${#s}
  for ((i = 0; i < n; i++)); do
    ch="${s:i:1}"
    if [[ "$ch" == '`' ]] && ((i + 1 < n)); then
      case "${s:i+1:1}" in
      '}')
        out+='_'
        i=$((i + 1))
        continue
        ;;
      '`')
        out+='``'
        i=$((i + 1))
        continue
        ;;
      *)
        # Any other escape (`` `n ``, `` `- ``) is left for the caller's backtick
        # deletion to resolve, exactly as before.
        ;;
      esac
    fi
    out+="$ch"
  done
  printf '%s' "$out"
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
  *'`'*) return 0 ;;         # backtick: escape / line continuation
  *'--%'*) return 0 ;;       # stop-parsing token
  *'('* | *')'*) return 0 ;; # subexpression / array subexpression / grouping
  *'{'* | *'}'*) return 0 ;; # script block / hashtable grouping
  *) return 1 ;;
  esac
}

# --- call-target computedness (shared by the git and python-write lanes) -------
#
# Both lanes ask the same question of a call `&` / dot-source `.`: is the target
# COMPUTED (so it could resolve to anything, including the program the lane
# guards) or a compile-time CONSTANT (so it is statically decidable)? They used to
# answer it with two different regexes — the git lane matching any quote character
# and the python lane only an interpolating double quote — which is how the git
# lane came to block `& "publish.ps1"`, a provably git-free literal path (#1968).
# The separator class and the operator shape now live in one place; the two lanes
# differ only in WHICH of the two computed shapes each admits, stated at the call
# site rather than duplicated in a regex.
#
# A call operator is valid immediately after a statement/block separator
# (`;& …`, `{& …}`, `|& …`) or after an ASSIGNMENT operator (`$a=& …`), not only
# after whitespace — hence the separator class `(^|[[:space:]\;\{\}\(\|\&=])`
# rather than a bare `[[:space:]]`.
#
# `=` is in the class because assigning a command's output with no space around
# the operator is idiomatic PowerShell, and omitting it made `$a=& $w f.txt x` — a
# working `Set-Content <path> <value>` — never enter the gate at all, while the
# identical spaced `$a = & $w f.txt x` blocked (#2928). `ps::might_invoke_git`
# already carried `=` in its own command-position class for the same reason
# (#2592 review); this brings the call-target predicates level with it.
#
# `,` is deliberately NOT in the class. `,& $w f.txt x` was raised as a possible
# third member of the same family, but it does not parse:
# `[System.Management.Automation.Language.Parser]::ParseInput` reports "Missing
# expression after unary operator ','." So it is not a reachable spelling, and
# widening for it would only add over-block surface.
#
# WIDENING THE CLASS MEANS WIDENING EVERY COPY OF IT. #2922 and #2924 were both
# cases of the gate ENTRY predicate matching a shape no MEASURING probe could
# see, so the gate was entered, every arm stayed silent, and the command fell
# through ALLOWED. Entry (`ps::call_target_is_bare_computed`) and measurement
# (the `re_var` in `ps::computed_call_has_positional_write_signal` and
# `ps::computed_call_has_splat_operand`, plus the quoted-writer regex in
# `ps::write_bypass`) have to move together or the widening manufactures a third
# instance of that bug.
#
# The operator prefix is spelled out literally in each predicate rather than
# factored into a shared variable and concatenated into the `[[ =~ ]]` pattern.
# Mixing an unquoted variable with adjacent literal regex text in a pattern
# position is the one bash construct whose quote-removal behavior is genuinely
# version-sensitive, and a predicate that silently stops matching here fails
# OPEN — the guard would wave through a computed call target. The SSOT that
# matters is these two named functions being the only place either lane asks the
# question; a shared string constant would buy nothing and risk that.

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
# blanking, and lowercasing intact, so the evidence is still here and the fix
# belongs in this predicate rather than in a pre-deletion pass.
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
  # The `\$` is ESCAPED. An unescaped `$?` in this position is a parameter
  # expansion of the last exit status, which would silently rewrite the pattern
  # and stop it matching the paren spelling too — a fail-OPEN on
  # `& ('Set-'+'Content') f.txt x`, the very shape this predicate exists for.
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
ps::call_site_operand_region() {
  local s="$1" out="" i ch depth=0
  for ((i = 0; i < ${#s}; i++)); do
    ch="${s:i:1}"
    case "$ch" in
    '{' | '(')
      depth=$((depth + 1))
      ;;
    '}' | ')')
      ((depth == 0)) && break
      depth=$((depth - 1))
      ;;
    ';' | '|' | '&')
      ((depth == 0)) && break
      ;;
    *)
      # Ordinary operand text — copied through with no depth effect.
      ;;
    esac
    out+="$ch"
  done
  printf '%s' "$out"
}

# Blank the INTERIOR of every balanced bracket group in a call's operand region,
# keeping the delimiters. Used by the splat probe so a nested construct's contents
# are not read as operands of the enclosing call: the splat inside
# `& $ic -ScriptBlock { & $w @p }` belongs to the inner `& $w`, which the call-site
# walk reaches on its own iteration, and the interior of `${script:Path}` holds no
# operands at all.
ps::blank_bracket_interiors() {
  local s="$1" out="" i ch depth=0
  for ((i = 0; i < ${#s}; i++)); do
    ch="${s:i:1}"
    case "$ch" in
    '{' | '(')
      out+="$ch"
      depth=$((depth + 1))
      continue
      ;;
    '}' | ')')
      ((depth > 0)) && depth=$((depth - 1))
      out+="$ch"
      continue
      ;;
    *)
      # Ordinary text — kept at depth 0, blanked inside a group.
      ;;
    esac
    if ((depth > 0)); then out+=" "; else out+="$ch"; fi
  done
  printf '%s' "$out"
}

ps::computed_call_has_positional_write_signal() {
  local lc="$1" rest="" tok count count_lit piped=0 scan depth opens closes
  # The BRACED spelling of a variable reference (`& ${env:w} …`, `${my name}`)
  # is matched alongside the bare one. PowerShell's about_Variables makes them the
  # same reference — `${env:t} -eq $env:t` is True — and `ps::call_target_is_bare_computed`
  # admits both, since it only looks for the `$`. Recognizing just the bare form
  # here let a braced target ENTER the computed-target gate and then match no call
  # site at all, so every arm stayed silent and the command fell through allowed:
  # `& ${env:w} f.txt x` was waved past while the identical `& $env:w f.txt x`
  # blocked. The gate entry is deliberately NOT narrowed to match — teaching the
  # measuring probes closes the hole, narrowing entry would open a second one.
  # The braced alternative is listed FIRST so it wins on a `${…}` target, and it
  # allows NON-SPACE text glued after the closing brace (`[^[:space:]]*`). A target
  # token does not have to end at the brace: `& ${my``}writer} f.txt x` closes the
  # reference at the escaped-backtick name `my``` and carries `writer}` on the same
  # token, and `& ${py}script.py` concatenates. Requiring whitespace immediately
  # after `}` made the whole call site disappear on those, which is a fail-OPEN —
  # the operands are still measured normally once the site is found, so widening
  # the TARGET token only decides where measuring starts, never the verdict.
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
    # Advance past this call site before measuring it, so the next iteration
    # starts inside the remainder and a nested call cannot be skipped.
    scan="$rest"
    count=0
    count_lit=0
    depth=0
    # Keep only this call's own operands: a trailing clause must not inflate the
    # count, and the `}` ending an ENCLOSING script block is not an operand —
    # while a `}` that closes one of this call's own operands must not truncate
    # past the operands after it (review of #2848).
    rest=$(ps::call_site_operand_region "$rest")
    # Drop redirect operands (`> f`, `2> err`) — those are covered by the
    # redirect probe; they are not Path+Value positionals.
    rest=$(printf '%s' "$rest" | sed -E 's/[0-9*]*>+[^[:space:]]*//g; s/[0-9*]*<+[^[:space:]]*//g')
    # shellcheck disable=SC2086 # intentional word-split on PowerShell tokens
    for tok in $rest; do
      [[ -z "$tok" ]] && continue
      # Every bracket character is BACKSLASH-ESCAPED inside these classes. An
      # unescaped `}` terminates the `${var//pattern/}` expansion itself, so
      # `${tok//[^)}]/}` silently parses as a different pattern and keeps the
      # whole token — parsed wrongly while still reading as a correct class.
      opens="${tok//[^\(\{]/}"
      closes="${tok//[^\)\}]/}"
      if ((depth > 0)); then
        # Inside a bracketed operand: track balance only. Its words are not
        # operands of the call, and a `-word` here must not end the outer scan.
        depth=$((depth + ${#opens} - ${#closes}))
        ((depth < 0)) && depth=0
        continue
      fi
      if [[ "$tok" == -* ]]; then
        break
      fi
      count=$((count + 1))
      # One bracketed operand, however many words it spans — a subexpression
      # `(Join-Path …)` or a script block `{ … }`. Braces are tracked alongside
      # parens because the operand region no longer truncates at the first `}`
      # (review of #2848); without this a multi-word script-block operand would
      # be counted one word at a time.
      if [[ "$tok" == [\(\{]* ]]; then
        depth=$((${#opens} - ${#closes}))
        ((depth < 0)) && depth=0
        continue
      fi
      # A token that merely CONTAINS brackets — `${scope:name}`, `logs[0].txt` —
      # is a single operand. Only an unbalanced one opens a multi-word span.
      depth=$((${#opens} - ${#closes}))
      ((depth < 0)) && depth=0
      ((depth > 0)) && continue
      if [[ "$tok" != \$* && "$tok" != @* && "$tok" != \{* ]]; then
        count_lit=$((count_lit + 1))
      fi
    done
    if ((count >= 2 && count_lit >= 1)); then
      return 0
    fi
    if ((piped == 1 && count >= 1)); then
      return 0
    fi
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
  # The BRACED spelling of a variable reference (`& ${env:w} …`, `${my name}`)
  # is matched alongside the bare one. PowerShell's about_Variables makes them the
  # same reference — `${env:t} -eq $env:t` is True — and `ps::call_target_is_bare_computed`
  # admits both, since it only looks for the `$`. Recognizing just the bare form
  # here let a braced target ENTER the computed-target gate and then match no call
  # site at all, so every arm stayed silent and the command fell through allowed:
  # `& ${env:w} f.txt x` was waved past while the identical `& $env:w f.txt x`
  # blocked. The gate entry is deliberately NOT narrowed to match — teaching the
  # measuring probes closes the hole, narrowing entry would open a second one.
  # The braced alternative is listed FIRST so it wins on a `${…}` target, and it
  # allows NON-SPACE text glued after the closing brace (`[^[:space:]]*`). A target
  # token does not have to end at the brace: `& ${my``}writer} f.txt x` closes the
  # reference at the escaped-backtick name `my``` and carries `writer}` on the same
  # token, and `& ${py}script.py` concatenates. Requiring whitespace immediately
  # after `}` made the whole call site disappear on those, which is a fail-OPEN —
  # the operands are still measured normally once the site is found, so widening
  # the TARGET token only decides where measuring starts, never the verdict.
  local re_var='(^|[[:space:]\;\{\}\(\|\&=])[.\&][[:space:]]*(\$\{[^}]*\}[^[:space:]]*|\$[a-z0-9_:?]+)([[:space:]]+|$)(.*)'
  lc="${lc//\`/}"
  lc="${lc,,}"
  scan="$lc"
  while [[ "$scan" =~ $re_var ]]; do
    rest="${BASH_REMATCH[4]}"
    # Advance past this call site before measuring it, so a nested call
    # (`& $ic -ScriptBlock { & $w @p }`) is reached on the next iteration.
    scan="$rest"
    # This call's own operands, with the interior of every balanced bracket group
    # blanked: a `}` closing one of THIS call's operands must not truncate away a
    # real splat after it (`& $w ${script:Path} @Body`), while a splat nested
    # inside a script block belongs to the inner call the walk reaches next.
    rest=$(ps::call_site_operand_region "$rest")
    rest=$(ps::blank_bracket_interiors "$rest")
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
ps::might_invoke_git() {
  local recovered="${1//\`/}" lc
  lc="${recovered,,}"
  # Predecessor class includes `:` so a drive-relative `& 'C:git.exe'` still
  # counts (Codex #2592 review) and `=` so `$x=git …` (no space) still counts
  # (Claude #2592 review), while `.git` stays inert (`.` is not listed).
  [[ "$lc" =~ (^|[[:space:]\;\|\&\(\{\}\"\'/\\:=])git([.]exe)?([^[:alnum:]_/\\]|$) ]] && return 0
  [[ "$lc" =~ (^|[^[:alnum:]_-])(iex|invoke-expression)([^[:alnum:]_-]|$) ]] && return 0
  # Call / dot-source of a COMPUTED target — `& (…)`, `& "$x" …` — which could
  # resolve to git. A CONSTANT target (`& 'git' …`, `& "C:\Git\cmd\git.exe" …`)
  # is not matched here and does not need to be: the literal-git probe above runs
  # quote-INTACT, so a quoted git command word is already caught by name. Matching
  # constants here as well is what over-blocked `& "publish.ps1"` (#1968) — a
  # target statically decidable as non-git.
  #
  # The BARE-VARIABLE half (`& $tool …`, `. $tool …`) is deliberately NOT matched
  # (#2848). It is the variable-command-word residual has_dynamic_invocation
  # documents and does not route: `& $tool reset --hard` with no sink trigger is
  # already allowed by this guard, so matching it here only ever fired on the
  # CONJUNCTION of that residual with an unrelated grouping construct — blocking
  # `foreach ($x in @(…)) { & $py run.py $x }` while the same call without the
  # loop was waved through. Grouping does not hide a git token from the literal
  # probe above (that probe scans the whole text, quote-intact and backtick-
  # recovered), so it adds nothing to the "could this reach git?" answer for a
  # bare variable. A SUBEXPRESSION target still blocks, because `('g'+'it')`
  # assembles a name the literal probe can never see.
  ps::call_target_is_bare_subexpression "$recovered" && return 0
  ps::call_target_is_interpolating_string "$recovered" && return 0
  # A launcher whose program is a computed expression or variable —
  # `Start-Process ('g'+'it') …`, `saps $tool …`, optionally behind one named
  # parameter (`-FilePath (…)`) — may evaluate to git; it cannot be proven
  # git-free, so it stays in the fail-closed branch (review round 5).
  # `=` is in the predecessor class for the same reason the literal-git probe
  # above carries it: `$p=saps $tool …` assigns the launcher's result with no
  # space around the operator, which is ordinary PowerShell (#2928).
  [[ "$lc" =~ (^|[[:space:]\;\|\&\(=])(start-process|saps|start|pwsh|powershell|cmd)(\.exe)?[[:space:]]+(-[a-z]+[[:space:]]+)?[\(\$] ]] && return 0
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
# DUAL-MODE SUBCOMMANDS ARE BLOCKED WHOLE. `tag` and `notes` were already listed
# despite having read-only list forms (`git tag`, `git notes list`), so the
# established policy is "a subcommand with any mutating mode is not read-only".
# `branch`, `config`, `remote`, `bisect`, `reflog`, `rerere`, `submodule`,
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
# The mangle-resistant fix for all three is to INVERT this into an allowlist —
# read-only iff every git occurrence is followed by a known interrogator — which
# is a redesign of the #1415 allowance, not a widening of this list. Until then
# this narrows the sink on a best-effort basis and is never the only thing between
# a destructive form and the repository: the DEFAULT `mutating` sink scope (what
# block-dangerous-git uses) does not consult this function at all.
ps::git_command_is_readonly() {
  local recovered="${1//\`/}" lc
  lc="${recovered,,}"
  # Same command-position git probe as ps::might_invoke_git (#2592).
  [[ "$lc" =~ (^|[[:space:]\;\|\&\(\{\}\"\'/\\:=])git([.]exe)?([^[:alnum:]_/\\]|$) ]] || return 1
  # Mutating subcommands, alphabetical, split across six tests purely for
  # reviewability. Each alternation stays a LITERAL in pattern position — never a
  # variable spliced into the pattern (see the call-target note above for why a
  # silently-non-matching predicate here would fail OPEN).
  #
  # A HYPHENATED SIBLING NEEDS ITS OWN ENTRY. The token boundary excludes `-`
  # (load-bearing, so `--prune` and `--tags` stay read-only), which means a
  # listed stem never matches its hyphenated relatives: `commit` does not cover
  # `commit-graph`, and `credential` does not cover `credential-cache` /
  # `credential-store`. Both of those write credentials to disk or manage a
  # caching daemon, so each is spelled out rather than left to the stem.
  [[ "$lc" =~ (^|[^[:alnum:]_.-])(add|am|annex|apply|bisect|branch|checkout|checkout-index|cherry-pick|citool|clean|commit)([^[:alnum:]_.-]|$) ]] && return 1
  [[ "$lc" =~ (^|[^[:alnum:]_.-])(commit-graph|config|credential|credential-cache|credential-store|cvsexportcommit|fast-import|filter-branch|filter-repo|gc|gui|http-push|interpret-trailers|lfs)([^[:alnum:]_.-]|$) ]] && return 1
  [[ "$lc" =~ (^|[^[:alnum:]_.-])(maintenance|merge|merge-file|merge-index|merge-one-file|mergetool|multi-pack-index|mv|notes|p4|prune)([^[:alnum:]_.-]|$) ]] && return 1
  [[ "$lc" =~ (^|[^[:alnum:]_.-])(prune-packed|pull|push|quiltimport|read-tree|rebase|receive-pack|reflog|remote|repack)([^[:alnum:]_.-]|$) ]] && return 1
  [[ "$lc" =~ (^|[^[:alnum:]_.-])(replace|rerere|reset|restore|revert|rm|send-pack|sparse-checkout|stage|stash)([^[:alnum:]_.-]|$) ]] && return 1
  [[ "$lc" =~ (^|[^[:alnum:]_.-])(submodule|subtree|svn|switch|symbolic-ref|tag|update-index|update-ref|update-server-info|worktree)([^[:alnum:]_.-]|$) ]] && return 1
  return 0
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
  # The quote-BLANKED command: an `open(` or a quoted mention inside the write
  # payload is removed, so an UNQUOTED `(` (subexpression) or `$` (variable) that
  # survives here is a genuine computed construct, not payload text.
  blanked=$(ps::blank_quoted_spans "$1")
  # A launcher (Start-Process/saps/start/pwsh/powershell/cmd) whose PROGRAM name is
  # COMPUTED cannot be proven non-python. Rather than model parameter ordering /
  # binding with a regex (which successive rounds defeated — one preceding option,
  # then colon binding, then multiple options), fail closed CONSERVATIVELY: any
  # launcher present together with an unquoted computed construct (`$` or `(`) →
  # block (the caller still gates on a write indicator). This runs FIRST because a
  # computed program has no literal python3 token for the test below to see. A
  # launcher with only LITERAL args (`Start-Process notepad …`) carries no such
  # construct and falls through to the token test, so a non-python launch stays
  # allowed. (ps::might_invoke_git models this with a narrower per-parameter regex;
  # a matching hardening there is tracked separately, out of this PR's scope.)
  if ps::has_launcher "$recovered" && [[ "$blanked" == *'$'* || "$blanked" == *'('* ]]; then
    return 0
  fi
  # A call `&` / dot-source `.` of a DOUBLE-QUOTED target that INTERPOLATES a
  # variable or subexpression (`& "$env:PYTHON_BIN" …`, `& "$(…)" …`) runs a
  # COMPUTED program that could resolve to python3. blank_quoted_spans erases the
  # target (so the launcher/token tests miss it) and it is not a launcher, so match
  # it here on the quote-INTACT text and fail closed. A SINGLE-quoted target does
  # NOT interpolate in PowerShell (`& '$x'` is the literal name `$x`), so it is not
# matched. ps::write_bypass catches an UNQUOTED `& $`/`& (` only together with a
# write indicator or special construct (#2722); this closes the
# quoted-interpolated form for the python-write lane — which is why this lane
# takes only the interpolating-string half of the shared call-target predicate
# and not the bare-computed half.
  ps::call_target_is_interpolating_string "$recovered" && return 0
  # Must name a python interpreter token at all (quote-intact, backtick-recovered).
  [[ "$lc" =~ (^|[^[:alnum:]_.])(pypy|python|py)[0-9]*([.][0-9]+)*([.]exe)?([^[:alnum:]_.]|$) ]] || return 1
  # A literal `-c` inline-code flag settles it (quote-bounded, so an arg-split
  # `-ArgumentList '-c',…` counts; a longer token like `-Command`/`-Confirm` does not).
  [[ "$lc" =~ (^|[[:space:]$q])-c([[:space:]$q]|$) ]] && return 0
  # `-c` immediately concatenated with a variable / subexpression is a COMPUTED
  # inline-code flag: PowerShell joins the adjacent expansion into the same
  # `-c<source>` argument (`python3 -c$code`, `python3 -c(…)`). The literal check
  # above requires a whitespace/quote boundary after `-c`, so this adjacency slips
  # it — fail closed.
  [[ "$lc" =~ (^|[[:space:]$q])-c[\$\(] ]] && return 0
  # No literal `-c`: PowerShell evaluates expression-valued arguments before launching,
  # so `python3 ('-'+'c') …` / `-ArgumentList ('-'+'c'),…` construct the flag with no
  # literal token. A computed `-c` cannot be ruled out when the args carry a
  # non-tokenizable construct — reuse the git lane's un-parsable test on the
  # quote-BLANKED text. Fail closed, exactly as the git lane refuses a computed target.
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
  # Assignment-glued call of a string literal. Quote-intact keeps the
  # following quote visible (`& "…"` / `. '…'`). Quote-blanked confirms the
  # `$name=` itself is not inside a string.
  [[ "$recovered" =~ (^|[[:space:]\;\{\}\(\|\&])\$[A-Za-z_][A-Za-z0-9_]*(:[A-Za-z_][A-Za-z0-9_]*)?[[:space:]]*=[[:space:]]*[.\&][[:space:]]*[$q] ]] || return 1
  blanked=$(ps::blank_quoted_spans "$recovered")
  [[ "$blanked" =~ \$[A-Za-z_][A-Za-z0-9_]*(:[A-Za-z_][A-Za-z0-9_]*)?[[:space:]]*=[[:space:]]*[.\&] ]]
}

# True (0) when a process launcher / nested shell sits at a command position:
# Start-Process (alias saps) launches a program the same way the Bash guard sees
# through `nice`/`nohup`/`sudo`/`env`; pwsh/powershell/cmd run a nested command
# string, the parity analog of the Bash guard's `sh -c`/`bash -c` see-through.
# Routed to the sink so ps::might_invoke_git decides — it blocks only when the
# literal `git` is present in the launched argv / command string (`Start-Process
# git -ArgumentList …`, `pwsh -Command 'git …'`), and passes a launcher with no
# git (`Start-Process notepad`, `pwsh -File build.ps1`). This is Bash-PARITY, not
# an airtight boundary; deeper nested-shell escaping (and `cmd /c`'s own quoting)
# is a shared Bash+PS residual.
ps::has_launcher() {
  local lc="${1//\`/}" blanked
  lc="${lc,,}"
  # The .exe-suffixed spellings (cmd.exe, powershell.exe, pwsh.exe) and the
  # `start` alias of Start-Process are the same launchers, not a new class —
  # a spelling gap here would skip the sink entirely (review round 4).
  [[ "$lc" =~ (^|[[:space:]\;\|\&\(])(start-process|saps|start|pwsh|powershell|cmd)(\.exe)?([[:space:]]|$) ]] && return 0
  # Assignment-glued launcher (`$out=pwsh $script`). Same `$name=` /
  # `$scope:name=` LHS as has_dynamic_invocation — about_Assignment_Operators,
  # not a generic `=` separator. Quote-BLANKED so `Write-Host "shell=pwsh $x"`
  # and a quoted `$out=pwsh` stay data (about_Quoting_Rules). `git -c
  # section.key=cmd` is git(1) `-c <name>=<value>`, not an assignment, and
  # does not match. Spelled out literally, never shared through a variable.
  blanked=$(ps::blank_quoted_spans "$lc")
  [[ "$blanked" =~ (^|[[:space:]\;\|\&\(])\$[A-Za-z_][A-Za-z0-9_]*(:[A-Za-z_][A-Za-z0-9_]*)?[[:space:]]*=[[:space:]]*(start-process|saps|start|pwsh|powershell|cmd)(\.exe)?([[:space:]]|$) ]]
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
ps::classify_git_command() {
  local tool="$1" cmd="$2" sink_scope="${3:-mutating}" scan
  PS_SAFE_COMMAND="$cmd"
  PS_SINK_TRIGGER=""
  [[ "$tool" == "PowerShell" ]] || return 0

  ps::blank_herestrings "$cmd"
  scan=$(ps::blank_quoted_spans "$PS_BLANKED")
  # Record WHICH trigger routed the command here. Four distinct shapes reach this
  # sink and they need different remediation: an operator told to "remove the
  # unparsable construct" when the trigger was a launcher or a computed call
  # target has nothing to remove (#1968). The order matches the test order below,
  # so the recorded trigger is the one that actually fired first.
  if ((PS_HERESTRING_UNBALANCED)); then
    PS_SINK_TRIGGER="herestring-unbalanced"
  elif ps::has_special_constructs "$scan"; then
    PS_SINK_TRIGGER="special-construct"
  elif ps::has_dynamic_invocation "$PS_BLANKED"; then
    PS_SINK_TRIGGER="dynamic-invocation"
  elif ps::has_launcher "$PS_BLANKED"; then
    PS_SINK_TRIGGER="launcher"
  fi
  if [[ -n "$PS_SINK_TRIGGER" ]]; then
    # Not faithfully tokenizable. Fail closed unless provably git-free. The git
    # probe runs on PS_BLANKED (quotes INTACT, backticks recovered inside the
    # probe) so a quoted or backtick-obfuscated `git` is still seen; an unbalanced
    # here-string leaves PS_BLANKED as the raw command so a trailing pipeline is
    # scanned, not swallowed.
    ps::might_invoke_git "$PS_BLANKED" || return 1
    if [[ "$sink_scope" == "readonly-ok" ]] && ps::git_command_is_readonly "$PS_BLANKED"; then
      return 1
    fi
    return 2
  fi
  # Backslash is a PATH SEPARATOR in PowerShell (its escape char is the
  # backtick, which already routes to the sink above), but the Bash tokenizer
  # this reduced command is handed to consumes `\` as an escape — so a
  # path-qualified `C:\Git\cmd\git.exe reset --hard` would tokenize to a word
  # whose basename never matches git. Normalize to forward slashes so
  # hook::git_is_bin sees the real basename (and a safe `…\git.exe status`
  # stays allowed rather than blanket-blocked). The `.exe` suffix (any case)
  # normalizes away here too: a PowerShell command carries Windows spellings
  # regardless of which OS the HOOK runs on, and hook::git_is_bin strips
  # `.exe` only on its msys/cygwin branch.
  local reduced="${PS_BLANKED//\\//}"
  reduced=$(printf '%s' "$reduced" | sed -E 's/[Gg][Ii][Tt]\.[Ee][Xx][Ee]/git/g')
  # PowerShell `$var=cmd` / `$var+=cmd` begins a new pipeline on the RHS without
  # requiring whitespace. Bash expands `$var` and leaves `=cmd` as a non-git
  # word, so strip the assignment prefix so the RHS command word is visible
  # (Claude review on #2592: `$x=git reset --hard`).
  reduced=$(printf '%s' "$reduced" | sed -E 's/\$[A-Za-z_][A-Za-z0-9_]*(:[A-Za-z_][A-Za-z0-9_]*)?[[:space:]]*(\+=|-=|\*=|\/=|%=|=)[[:space:]]*/ /g')
  # Read by the sourcing guard, not within this library.
  # shellcheck disable=SC2034
  PS_SAFE_COMMAND="$reduced"
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
#
# Statement tails stop at top-level `;` / newline / `|` / `&&` / `||` so a
# pipeline consumer or following statement remains for normal checks.
ps::blank_sink_opaque_regions() {
  local cmd="$1" trigger="$2"
  case "$trigger" in
  dynamic-invocation) ps::_blank_cmd_statements "$cmd" "dynamic" ;;
  launcher) ps::_blank_cmd_statements "$cmd" "launcher" ;;
  special-construct) ps::_blank_special_construct_regions "$cmd" ;;
  herestring-unbalanced) ps::_blank_unbalanced_herestring_tail "$cmd" ;;
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

# Consume a double-quoted span starting at IDX (points at "); returns end index
# (one past the closer, or past end of string if unbalanced).
ps::_skip_double_quote() {
  local cmd="$1" i="$2" n=${#1} c
  i=$((i + 1))
  while ((i < n)); do
    c="${cmd:i:1}"
    if [[ "$c" == '`' ]]; then
      i=$((i + 2))
      continue
    fi
    if [[ "$c" == '"' ]]; then
      echo $((i + 1))
      return 0
    fi
    i=$((i + 1))
  done
  echo "$n"
}

# Consume a single-quoted span starting at IDX (points at ').
ps::_skip_single_quote() {
  local cmd="$1" i="$2" n=${#1} c
  i=$((i + 1))
  while ((i < n)); do
    c="${cmd:i:1}"
    if [[ "$c" == "'" ]]; then
      echo $((i + 1))
      return 0
    fi
    i=$((i + 1))
  done
  echo "$n"
}

# Advance IDX to the end of the current statement/pipeline element at depth 0
# (stop before top-level `;`, newline, `|`, `&&`, `||`). Quote- and depth-aware.
ps::_skip_statement_tail() {
  local cmd="$1" i="$2" n=${#1} depth=0 c
  while ((i < n)); do
    c="${cmd:i:1}"
    if ((depth == 0)); then
      if [[ "$c" == "'" ]]; then
        i=$(ps::_skip_single_quote "$cmd" "$i")
        continue
      fi
      if [[ "$c" == '"' ]]; then
        i=$(ps::_skip_double_quote "$cmd" "$i")
        continue
      fi
      if [[ "$c" == ';' || "$c" == $'\n' ]]; then
        echo "$i"
        return 0
      fi
      if [[ "$c" == '|' ]]; then
        # `|` and `||` both end this pipeline element / statement.
        echo "$i"
        return 0
      fi
      if [[ "$c" == '&' && "${cmd:i+1:1}" == '&' ]]; then
        echo "$i"
        return 0
      fi
      # Bare `&` is the call operator (or background) — part of this statement.
    fi
    case "$c" in
    '{') depth=$((depth + 1)) ;;
    '}') ((depth > 0)) && depth=$((depth - 1)) ;;
    '(') depth=$((depth + 1)) ;;
    ')') ((depth > 0)) && depth=$((depth - 1)) ;;
    *) ;;
    esac
    i=$((i + 1))
  done
  echo "$n"
}

# Blank dynamic-invocation or launcher statements in CMD. KIND is `dynamic` or
# `launcher`. Writes PS_SAFE_COMMAND.
ps::_blank_cmd_statements() {
  local cmd="$1" kind="$2" n=${#1} i=0 out="" c rest lc matched end word j
  while ((i < n)); do
    c="${cmd:i:1}"
    if [[ "$c" == "'" ]]; then
      end=$(ps::_skip_single_quote "$cmd" "$i")
      out+="${cmd:i:end-i}"
      i=$end
      continue
    fi
    if [[ "$c" == '"' ]]; then
      end=$(ps::_skip_double_quote "$cmd" "$i")
      out+="${cmd:i:end-i}"
      i=$end
      continue
    fi
    matched=0
    if ps::_at_command_position "$cmd" "$i"; then
      rest="${cmd:i}"
      lc="${rest,,}"
      case "$kind" in
      dynamic)
        if [[ "$lc" =~ ^(iex|invoke-expression)([^a-z0-9_-]|$) ]]; then
          if [[ "$lc" == iex* ]]; then word=3; else word=18; fi
          # iex / Invoke-Expression — blank through end of this pipeline element.
          end=$(ps::_skip_statement_tail "$cmd" $((i + word)))
          i=$end
          out+=" "
          matched=1
        elif [[ "$c" == '&' || "$c" == '.' ]]; then
          # Call / dot-source of a STRING LITERAL — same dynamic-invocation shape.
          j=$((i + 1))
          while ((j < n)) && [[ "${cmd:j:1}" == [[:space:]] ]]; do j=$((j + 1)); done
          if ((j < n)) && [[ "${cmd:j:1}" == "'" || "${cmd:j:1}" == '"' ]]; then
            end=$(ps::_skip_statement_tail "$cmd" "$i")
            i=$end
            out+=" "
            matched=1
          fi
        fi
        ;;
      launcher)
        if [[ "$lc" =~ ^(start-process|saps|start|pwsh|powershell|cmd)(\.exe)?([^a-z0-9_-]|$) ]]; then
          end=$(ps::_skip_statement_tail "$cmd" "$i")
          i=$end
          out+=" "
          matched=1
        fi
        ;;
      *) ;;
      esac
    fi
    if ((matched)); then
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
    if [[ "$c" == "'" ]]; then
      end=$(ps::_skip_single_quote "$cmd" "$i")
      out+="${cmd:i:end-i}"
      i=$end
      continue
    fi
    if [[ "$c" == '"' ]]; then
      end=$(ps::_skip_double_quote "$cmd" "$i")
      out+="${cmd:i:end-i}"
      i=$end
      continue
    fi
    if [[ "$c" == '`' ]]; then
      # Backtick escape / line-continuation — drop the escape and its follower.
      i=$((i + 2))
      out+=" "
      continue
    fi
    if [[ "${cmd:i:3}" == '--%' ]]; then
      end=$(ps::_skip_statement_tail "$cmd" "$i")
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
          i=$(ps::_skip_single_quote "$cmd" "$i")
          continue
        fi
        if [[ "$c" == '"' ]]; then
          i=$(ps::_skip_double_quote "$cmd" "$i")
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
  local cmd="$1" line out="" pending="" in_hs=0 hs_quote="" first2 closer opener_scan
  # Mirror ps::blank_herestrings' opener detection; once an opener has no closer,
  # drop it and everything after (extent unknown — trailing code may be inside).
  while IFS= read -r line || [[ -n "$line" ]]; do
    if ((in_hs)); then
      first2="${line:0:2}"
      closer="${hs_quote}@"
      if [[ "$first2" == "$closer" ]]; then
        out+="${pending}${line:2}"$'\n'
        pending=""
        in_hs=0
        hs_quote=""
      fi
      continue
    fi
    opener_scan=$(printf '%s' "$line" | sed -E -e "s/'[^']*'//g" -e 's/"([^"\\]|\\.)*"//g')
    if [[ "$opener_scan" == *"@'" || "$opener_scan" == *'@"' ]]; then
      hs_quote="${line: -1}"
      pending="${line%??}"
      in_hs=1
      continue
    fi
    out+="${line}"$'\n'
  done < <(printf '%s\n' "$cmd")
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
# plus what to do about it. Each of the four triggers needs different advice:
# "remove the unparsable construct" is unactionable for a launcher or a dynamic
# invocation, because there is no such construct to remove (#1968). Each line
# must also stay true of every command that reaches it — advice that describes
# only part of a trigger's shape space is the same unactionable dead end in a
# different disguise.
ps::print_sink_trigger_line() {
  local closer
  case "$PS_SINK_TRIGGER" in
  herestring-unbalanced)
    # PowerShell pairs the opener with its OWN quote: `@'` closes with `'@` and
    # `@"` closes with `"@`. Naming the wrong one leaves the rewritten command
    # still unbalanced and still blocked, so name the terminator that matches
    # the opener actually left hanging; name both only when the opener is not
    # recorded (a caller that printed this line without a preceding
    # ps::blank_herestrings run).
    case "$PS_HERESTRING_QUOTE" in
    "'") closer="the '@ terminator" ;;
    '"') closer="the \"@ terminator" ;;
    *) closer="the terminator matching the opener (@' closes with '@, @\" closes with \"@)" ;;
    esac
    echo "Trigger: an unbalanced here-string — its extent cannot be determined, so a trailing pipeline could be hidden inside it. Close the here-string ($closer must start at column 0)." >&2
    ;;
  special-construct)
    echo "Trigger: a construct the guard cannot faithfully tokenize (backtick, '--%', subexpression, or {}/() grouping). Remove it, or run the command via the Bash tool." >&2
    ;;
  dynamic-invocation)
    # The INVOCATION FORM is what routes here, not the decidability of the
    # target: `& 'git' reset --hard` names its program literally and is still
    # blocked, because `&` plus a quoted string is what the guard's Bash
    # tokenizer cannot read. Telling that operator to "invoke the target by its
    # literal name" describes the form they already used, so the advice has to
    # be to drop the invocation operator instead. A call/dot-source of a bare
    # variable (`& $tool`) never reaches this branch.
    echo "Trigger: a dynamic invocation — iex/Invoke-Expression, or a call '&' / dot-source '.' whose target is a quoted string. The form itself routes here, a constant literal target included; a target that cannot reach git is then allowed, and this one could. Drop the iex/'&'/'.' and write the program as a plain command word, or run the command via the Bash tool." >&2
    ;;
  launcher)
    echo "Trigger: a process launcher or nested shell (Start-Process/saps/start, pwsh, powershell, cmd), which the guard must see through the way it sees through 'bash -c'. Run the program directly, or run the command via the Bash tool." >&2
    ;;
  *)
    echo "Run the command via the Bash tool, or rewrite it without the unparsable construct." >&2
    ;;
  esac
}

# Shell-agnostic block text for a PowerShell command the guard cannot parse with
# confidence. The sink is gated by ps::might_invoke_git (possibly-git, not is-git),
# so the headline must not claim a git command is present — iex / a computed call
# / a computed launcher can reach here with no git token at all (#2662).
# Printed to stderr by the caller before it exits 2.
ps::print_unparsable_block_message() {
  echo "BLOCKED: this PowerShell command cannot be parsed with confidence — blocked (fail-closed)." >&2
  ps::print_sink_trigger_line
  echo "The canonical PowerShell commit form (a here-string piped to 'git commit -F -') is:" >&2
  echo "  @'" >&2
  echo "  <subject>" >&2
  echo "  '@ | git commit -F -" >&2
  echo "or run the commit via the Bash tool (the /commit skill's canonical form)." >&2
  echo "If this is a false positive, set the guardrails block_no_verify_enabled option to false (/plugin configure) to bypass." >&2
}

# Shell-agnostic block text for a PowerShell command block-dangerous-git cannot
# parse with confidence and that could reach git. That guard also owns destructive
# non-commit forms, so its message names them rather than the commit form. The
# headline does not assert that a git command is present — the sink is possibly-git
# (#2662). Printed to stderr by the caller before it exits 2.
ps::print_unparsable_git_block_message() {
  echo "BLOCKED: this PowerShell command cannot be parsed with confidence and could reach git — blocked (fail-closed)." >&2
  echo "A command the guard cannot faithfully tokenize could hide a destructive git form (reset --hard, clean -fd, checkout/restore), so it is blocked rather than waved through." >&2
  ps::print_sink_trigger_line
  # Sink-shape allow tokens (ps-unparsable-<trigger>) are distinct from destructive
  # form tokens so an existing allow-list value cannot silently open this branch (#2664).
  echo "If this is a false positive for the sink shape named above, allow it via the block_dangerous_git_allow option (add ps-unparsable-<trigger>: ps-unparsable-dynamic-invocation, ps-unparsable-launcher, ps-unparsable-special-construct, or ps-unparsable-herestring-unbalanced), or set the guardrails block_dangerous_git_enabled option to false (/plugin configure) to bypass." >&2
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
ps::write_bypass() {
  local cmd="$1" scan lcs seg lc head lcq lcq_bt q="\"'" blanked_gate
  ps::blank_herestrings "$cmd"

  # A call `&` / dot-source `.` of a QUOTED writer name runs that string as the
  # command (about_Operators, call operator) — quote-blanking below would erase
  # exactly the evidence, so detect it on the quote-INTACT text first. Only
  # writer/iex names (optionally module-qualified) are matched: a quoted path to
  # an arbitrary program (`& 'C:\Program Files\x.exe'`) stays allowed, the same
  # quoted-command-word residual the Bash guard carries.
  # Consume the backtick escape of a closing brace BEFORE the deletion below
  # destroys the evidence — the deletion is what made `${my`}w}` read as `${my}w}`
  # and vanish from the braced-target scanner entirely (review of #2848). This is
  # the load-bearing position: the probes cannot do it themselves, because by the
  # time they are called the backticks are already gone.
  lcq=$(ps::fold_escaped_brace_closers "$PS_BLANKED")
  # Keep a backtick-INTACT copy for the quote-blanking below, for the same reason
  # the brace fold has to run before the deletion: a backtick-escaped QUOTE is an
  # escape context that the deletion destroys. `"say `"hi"` is one string, but
  # once the backtick is gone it reads as `"say "` + `hi` + a dangling `"` whose
  # pairing runs forward to the next literal quote anywhere on the line — which
  # swallowed `& ('set-'+'content') f.txt x` and returned 0 (review of #2965).
  # ps::blank_quoted_spans can only resolve that toward NOT deleting while the
  # backtick still exists, so it must see this copy; the result is stripped
  # afterwards, which still recovers an obfuscated `Set``-Content` name.
  lcq_bt="${lcq,,}"
  lcq="${lcq//\`/}"
  lcq="${lcq,,}"
  if [[ "$lcq" =~ (^|[[:space:]\;\{\}\(\|\&=])[.\&][[:space:]]*[$q]([a-z.]+\\)?(set-content|add-content|out-file|tee-object|ac|tee|iex|invoke-expression|new-item|ni|epcsv|export-[a-z]+) ]]; then
    return 0
  fi
  # A call/dot-source of a COMPUTED target — `& ('Set-'+'Content') …`, `& $w …`
  # — evaluates an expression into the command name; it cannot be proven
  # non-writer, so it fails closed like iex WHEN a write signal is also present
  # (review round 5, narrowed in #2722). Mirrors the git lane: ps::might_invoke_git's
  # computed-target probe only runs after ps::has_special_constructs (or another
  # sink trigger) has already routed the command. A construct-free `& $tool …` /
  # `. $PROFILE` with no redirect and no -Value is the same deferred
  # variable-command-word residual has_dynamic_invocation documents for git.
  # Both this and the quoted-writer check above accept a statement/block separator
  # boundary (`;& …`), not only whitespace (review round 6).
  if ps::call_target_is_bare_computed "$lcq"; then
    blanked_gate=$(ps::blank_quoted_spans "$lcq_bt")
    blanked_gate="${blanked_gate//\`/}"
    # fd-dup merges (`2>&1`) are plumbing, not file writes — strip them before
    # ANY probe in this branch runs, so `& $tool 2>&1` does not look like a
    # producer redirect AND the `&` of the merge is not read as a statement
    # separator by the call-site walk.
    #
    # The strip used to feed only the `>` redirect probe, via a separate `gate`
    # variable, while the two MEASURING probes were handed the unstripped
    # `blanked_gate`. `ps::call_site_operand_region` ends a call's operand region
    # at a depth-zero `;` `|` `&`, and the `&` inside `2>&1` is at depth zero, so
    # `& $w 2>&1 f.txt x` — a working `Set-Content <path> <value>`, verified as a
    # real write under pwsh — had its region truncated to `" 2>"`. Both measuring
    # probes went silent and the command fell through ALLOWED (#2927). One text
    # for every probe in the branch is what keeps that from recurring: the
    # divergence between what the gate stripped and what the probes measured WAS
    # the bug.
    #
    # Deleting the merge cannot manufacture a signal. The pattern requires a `>`
    # immediately before the `&` and a digit after it, so it never consumes the
    # `&`/`(` of a call target, and deletion can only remove text, never create a
    # `-va*`, a splat, or a `>`.
    #
    # Redirect / -va* probes run on quote-blanked text so a quoted `>` or
    # `-value` substring in message text is not a write signal (#2722 review).
    blanked_gate=$(printf '%s' "$blanked_gate" | sed -E 's/[0-9*]*>&[0-9]+//g')
    # The gate used to be a blanket ps::has_special_constructs, which treated ANY
    # grouping anywhere in the command as a write signal — so an ordinary
    # `foreach (…) { & $py run.py $x }` was reported as a "file-write cmdlet
    # bypass" for a command that writes nothing (#2848). Grouping is not a write
    # signal; the three shapes that gate actually needed to carry are named
    # directly instead, each strictly more precise than the construct it replaces:
    #   - the CALL TARGET itself is a subexpression (`& ('Set-'+'Content') …`) —
    #     the writer name is assembled at run time and cannot be proven otherwise;
    #   - `--%` (stop-parsing), which makes the remaining argv opaque to every
    #     probe below, so the -Value / positional shapes cannot be ruled out;
    #   - a SPLAT (`& $w @p`), which supplies -Path/-Value from a hashtable the
    #     probes below cannot see. Previously this was caught only by accident,
    #     and only when the hashtable literal happened to sit in the same command
    #     (`$p = @{…}; & $w @p`); naming it closes the pre-built-`$p` form too.
    #     The splat is measured PER CALL SITE, the same way the positional probe
    #     measures its operands — a whole-command `@name` scan would make an
    #     unrelated splat the write signal for a call it has nothing to do with
    #     (`Write-Output @args; & $py script.py`), which is this issue's own
    #     over-block class in miniature (see ps::computed_call_has_splat_operand).
    # Accounting for the arms of has_special_constructs this replaces: its
    # backtick arm was already DEAD here (`lcq` strips backticks above), its
    # `--%` arm is carried verbatim, and its `(`/`)` arm is carried for the one
    # position that matters — the call target. What is deliberately dropped is
    # grouping ANYWHERE ELSE in the command, which is the over-block this closes.
    # The `>` redirect and `-va*` probes below stay at WHOLE-COMMAND scope: they
    # are pre-existing precedent, not shapes this issue reopened, and narrowing
    # either one is a fail-OPEN change to a different signal.
    # The one blocking shape that relied on the dropped arms —
    # `& $ic -ScriptBlock { & $w f.txt $x }`, where the outer target's first
    # token is a flag — is recovered by measuring every call site rather than the
    # first (see ps::computed_call_has_positional_write_signal).
    if ps::call_target_is_bare_subexpression "$blanked_gate" ||
      [[ "$blanked_gate" == *'--%'* ]] ||
      ps::computed_call_has_splat_operand "$blanked_gate" ||
      [[ "$blanked_gate" == *'>'* ]] ||
      [[ "$blanked_gate" =~ [[:space:]]-va[a-z]*([[:space:]]|:) ]] ||
      ps::computed_call_has_positional_write_signal "$blanked_gate"; then
      return 0
    fi
  fi

  scan=$(ps::blank_quoted_spans "$PS_BLANKED")
  # Delete backticks before matching so a name obfuscated by PowerShell's escape
  # char (`Set``-Content`) resolves to its real form.
  scan="${scan//\`/}"
  lcs="${scan,,}"

  # Content-authoring cmdlets are a write by nature. Detected on the quote-stripped
  # text so a cmdlet named inside message text is inert. Aliases are matched too:
  # `ac` (Add-Content) and `tee` (Tee-Object). Out-File has no built-in alias.
  # `sc` is handled separately below — it is Set-Content's alias in Windows
  # PowerShell 5.1 but sc.exe (the service controller) in PowerShell 7, so it is
  # matched only in its unambiguous Set-Content form.
  # `\\` in the boundary class admits module-qualified spellings
  # (`Microsoft.PowerShell.Management\Set-Content`) — same cmdlet, same write.
  if [[ "$lcs" =~ (^|[[:space:]\;\|\&\(\\])(set-content|add-content|out-file|tee-object|ac|tee)([[:space:]]|$) ]]; then
    return 0
  fi
  # `sc` in its Set-Content form: only when a Set-Content-only parameter follows
  # (`-Value`/`-Path`/`-LiteralPath`/`-LP`/`-Stream`). sc.exe (PS 7) takes bare
  # subcommands (`sc query`, `sc start …`) and none of these dash-parameters, so
  # this never fires on a genuine service-controller call — while a 5.1
  # `sc -Path f -Value x` (the Set-Content alias) is caught. The bare positional
  # form (`sc f 'x'`) on 5.1 is a documented residual.
  if [[ "$lcs" =~ (^|[[:space:]\;\|\&\(])sc[[:space:]] ]] &&
    [[ "$lcs" =~ [[:space:]]-(va[a-z]*|path|literalpath|lp|stream)([[:space:]]|:) ]]; then
    return 0
  fi

  # iex / invoke-expression authors content via the arbitrary string it runs — its
  # payload is opaque here, so fail closed (mirrors the git guards' sink).
  if [[ "$lcs" =~ (^|[[:space:]\;\|\&\(\\])(iex|invoke-expression)([[:space:]]|$) ]]; then
    return 0
  fi
  # New-Item (alias `ni`) authoring content via -Value. `-va` is the shortest
  # unambiguous abbreviation (New-Item has no other -va* parameter); `-Value:x`
  # attaches with a colon. Directory/empty-file creation with no -Value is not a
  # content author.
  if [[ "$lcs" =~ (^|[[:space:]\;\|\&\(\\])(new-item|ni)([[:space:]]) ]] &&
    [[ "$lcs" =~ [[:space:]]-va[a-z]*([[:space:]]|:) ]]; then
    return 0
  fi
  # Serialize-to-file cmdlets: the Export-* family (Export-Csv, Export-Clixml, …),
  # including the `epcsv` (Export-Csv) alias. ConvertTo-*/format cmdlets piped into
  # Out-File/Set-Content are already caught by those sinks above. The broad
  # `export-*` match also catches the few non-file-writing members (notably
  # Export-ModuleMember) — a safe-direction over-block, never an under-block, and
  # tolerated friction: those are authored inside .psm1 module files, not run as
  # ad hoc tool commands.
  if [[ "$lcs" =~ (^|[[:space:]\;\|\&\(\\])(export-[a-z]+|epcsv)([[:space:]]|$) ]]; then
    return 0
  fi
  # .NET file-write APIs: [IO.File]::WriteAllText/AppendAllText/WriteAllLines/
  # WriteAllBytes and StreamWriter.
  if [[ "$lcs" =~ io\.file\][^:]*::[[:space:]]*(writeall|appendall) ]] ||
    [[ "$lcs" =~ streamwriter ]]; then
    return 0
  fi

  # Producer-scoped redirect. Split the quote-stripped text into pipeline /
  # statement segments; a stripped leading string literal leaves the segment
  # starting at its `>`, which is itself the content-emitter signal.
  # fd-dup merge redirects (`2>&1`, `*>&1`) are plumbing, not producers — strip
  # them BEFORE splitting, or the `&` inside `2>&1` cuts a phantom `1 > file`
  # segment that the numeric-producer test would wrongly block
  # (`git status 2>&1 > out.txt` is a tool capture, not a content write).
  lcs=$(printf '%s' "$lcs" | sed -E 's/[0-9*]*>&[0-9]+//g')
  local norm="${lcs//[|;&]/$'\n'}"
  while IFS= read -r seg; do
    seg="${seg#"${seg%%[![:space:]]*}"}" # ltrim
    [[ "$seg" == *'>'* ]] || continue
    # Exclude the `$null` discard (PowerShell's /dev/null).
    # portability-ok: `\>` escapes a literal `>` inside a bash [[ =~ ]] ERE, it
    # is not GNU grep's `\>` word-boundary — no external grep/sed is involved.
    [[ "$seg" =~ \>\>?[[:space:]]*\$null([[:space:]]|$) ]] && continue
    # Unwrap grouping parens AND script-block braces so a grouped producer is
    # judged by what it produces: `('secret') > f` (quote-stripped to `() > f`)
    # reduces to the leading-literal case, `(write-output x) > f` and
    # `& { write-output x } > f` to their real heads, and a grouped tool run
    # (`(git diff) > f`, `& { git diff } > f`) stays the tool-producer allow.
    seg="${seg//[()]/}"
    seg="${seg//\{/}"
    seg="${seg//\}/}"
    seg="${seg#"${seg%%[![:space:]]*}"}" # re-ltrim after unwrap
    head="${seg%%[[:space:]]*}"
    # A module-qualified producer (`Microsoft.PowerShell.Utility\Write-Output`)
    # is the same cmdlet — compare its basename.
    head="${head##*\\}"
    case "$seg" in
    '>'*) return 0 ;; # leading literal (string stripped away) was the producer
    *) ;;
    esac
    case "$head" in
    # Producer cmdlets for EVERY stream — a non-success stream redirected to a
    # file (`Write-Error secret 2> creds.txt`, `Write-Warning x 3> f`) writes
    # that stream's content exactly as a success-stream redirect does.
    echo | write | write-output | write-host | write-error | write-warning | \
      write-verbose | write-debug | write-information | \
      "${PS_HERESTRING_PLACEHOLDER,,}") return 0 ;;
    '$'*) return 0 ;; # a variable / subexpression value redirected to a file
    '['*) return 0 ;; # a cast/type expression value ([char]65 > f)
    *) ;;
    esac
    # A bare numeric expression is a value write (`36 > out.txt` writes "36").
    # Only the SPACED form — an attached digit prefix (`2>err.txt`, `2>&1`) is a
    # stream redirect whose producer is the preceding tool, not a value.
    [[ "$head" =~ ^[0-9]+([.][0-9]+)?$ ]] && return 0
  done < <(printf '%s\n' "$norm") # not <<<: a >=64KiB here-string deadlocks (see hardcoded-path-patterns.sh)
  return 1
}
