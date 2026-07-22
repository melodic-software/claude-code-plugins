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
# Set by ps::classify_git_command — the command the caller should parse. Read by
# the sourcing guard, not within this library.
# shellcheck disable=SC2034
PS_SAFE_COMMAND=""

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
  local cmd="$1"
  local line out="" pending="" in_hs=0 hs_quote="" first2 rest closer opener_scan
  PS_HERESTRING_UNBALANCED=0

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
    opener_scan=$(printf '%s' "$line" | sed "s/'[^']*'//g" | sed -E 's/"([^"\\]|\\.)*"//g')
    if [[ "$opener_scan" == *"@'" || "$opener_scan" == *'@"' ]]; then
      hs_quote="${line: -1}" # ' or "
      pending="${line%??}${PS_HERESTRING_PLACEHOLDER}"
      in_hs=1
      continue
    fi
    out+="${line}"$'\n'
  done <<<"$cmd"

  if ((in_hs)); then
    # Opener with no column-zero closer: ambiguous extent. Blanking to end could
    # swallow a trailing command (e.g. `| git commit --no-verify`) into the inert
    # placeholder, so surface the raw command and flag unbalanced instead.
    PS_HERESTRING_UNBALANCED=1
    PS_BLANKED="$cmd"
    return 0
  fi
  PS_BLANKED="${out%$'\n'}"
}

# Crude, SCAN-ONLY strip of single- and double-quoted spans, so that structural
# detection and commit/push shaping ignore characters inside message text. Never
# fed to a parser. Backtick-escaped quotes are not honored — a backtick anywhere
# already forces the fail-closed branch, so this crudeness cannot open a gap.
ps::blank_quoted_spans() {
  local text="$1"
  text=$(printf '%s' "$text" | sed "s/'[^']*'//g")
  text=$(printf '%s' "$text" | sed -E 's/"[^"]*"//g')
  printf '%s' "$text"
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
ps::might_invoke_git() {
  # `q` carries the two quote characters so neither appears literally inside the
  # [[ =~ ]] test (which would derail shellcheck's parser).
  local recovered="${1//\`/}" lc q="\"'"
  lc="${recovered,,}"
  [[ "$lc" =~ (^|[^[:alnum:]_.])git([.]exe)?([^[:alnum:]_]|$) ]] && return 0
  [[ "$lc" =~ (^|[^[:alnum:]_-])(iex|invoke-expression)([^[:alnum:]_-]|$) ]] && return 0
  # Call / dot-source of a variable, subexpression, or string literal:
  # `& $x …`, `& (…)`, `& 'git …'`, `. $x …` — the target runs as a command.
  # The call operator is also valid immediately after a statement/block
  # separator (`;& …`, `{& …}`, `|& …`), not only after whitespace.
  [[ "$lc" =~ (^|[[:space:]\;\{\}\(\|\&])[.\&][[:space:]]*[\$\($q] ]] && return 0
  # A launcher whose program is a computed expression or variable —
  # `Start-Process ('g'+'it') …`, `saps $tool …`, optionally behind one named
  # parameter (`-FilePath (…)`) — may evaluate to git; it cannot be proven
  # git-free, so it stays in the fail-closed branch (review round 5).
  [[ "$lc" =~ (^|[[:space:]\;\|\&\(])(start-process|saps|start|pwsh|powershell|cmd)(\.exe)?[[:space:]]+(-[a-z]+[[:space:]]+)?[\(\$] ]] && return 0
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
ps::has_dynamic_invocation() {
  # `q` carries the two quote characters so neither appears literally inside the
  # [[ =~ ]] test (which would derail shellcheck's parser).
  local recovered="${1//\`/}" lc q="\"'"
  lc="${recovered,,}"
  [[ "$lc" =~ (^|[^[:alnum:]_-])(iex|invoke-expression)([^[:alnum:]_-]|$) ]] && return 0
  [[ "$recovered" =~ (^|[[:space:]\;\{\}\(\|\&])[.\&][[:space:]]*[$q] ]] && return 0
  return 1
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
  local lc="${1//\`/}"
  lc="${lc,,}"
  # The .exe-suffixed spellings (cmd.exe, powershell.exe, pwsh.exe) and the
  # `start` alias of Start-Process are the same launchers, not a new class —
  # a spelling gap here would skip the sink entirely (review round 4).
  [[ "$lc" =~ (^|[[:space:]\;\|\&\(])(start-process|saps|start|pwsh|powershell|cmd)(\.exe)?([[:space:]]|$) ]]
}

# Classify a git/commit-guard command for the resolved tool. Sets PS_SAFE_COMMAND
# (the command the caller should hand to its Bash parser) and returns:
#   0  proceed — parse PS_SAFE_COMMAND (== the original command for the Bash tool)
#   1  allow/skip — a PowerShell command that carries an A2b-deferred construct but
#      is PROVABLY git-free, so none of the git guards' concerns can be present
#   2  block fail-closed — carries a construct the Bash tokenizer cannot faithfully
#      parse AND might reach git; refused by shape rather than guessed safe
#
# SINK DOCTRINE (the #740/#903 lesson): when the command is not faithfully
# Bash-tokenizable, do NOT resolve-then-trust-a-negative — the same construct that
# defeats the tokenizer also mangles any shape scan, so a negative `commit`/`push`
# match is not evidence of safety. Block unless the command is provably git-free.
ps::classify_git_command() {
  local tool="$1" cmd="$2" scan
  PS_SAFE_COMMAND="$cmd"
  [[ "$tool" == "PowerShell" ]] || return 0

  ps::blank_herestrings "$cmd"
  scan=$(ps::blank_quoted_spans "$PS_BLANKED")
  if ((PS_HERESTRING_UNBALANCED)) ||
    ps::has_special_constructs "$scan" ||
    ps::has_dynamic_invocation "$PS_BLANKED" ||
    ps::has_launcher "$PS_BLANKED"; then
    # Not faithfully tokenizable. Fail closed unless provably git-free. The git
    # probe runs on PS_BLANKED (quotes INTACT, backticks recovered inside the
    # probe) so a quoted or backtick-obfuscated `git` is still seen; an unbalanced
    # here-string leaves PS_BLANKED as the raw command so a trailing pipeline is
    # scanned, not swallowed.
    ps::might_invoke_git "$PS_BLANKED" && return 2
    return 1
  fi
  # Backslash is a PATH SEPARATOR in PowerShell (its escape char is the
  # backtick, which already routes to the sink above), but the Bash tokenizer
  # this reduced command is handed to consumes `\` as an escape — so a
  # path-qualified `C:\Git\cmd\git.exe reset --hard` would tokenize to a word
  # whose basename never matches git. Normalize to forward slashes so
  # hook::git_is_bin sees the real basename (and a safe `…\git.exe status`
  # stays allowed rather than blanket-blocked).
  # Read by the sourcing guard, not within this library.
  # shellcheck disable=SC2034
  PS_SAFE_COMMAND="${PS_BLANKED//\\//}"
  return 0
}

# Shell-agnostic block text for a PowerShell git command the guard cannot parse
# with confidence. Printed to stderr by the caller before it exits 2.
ps::print_unparsable_block_message() {
  echo "BLOCKED: this PowerShell git command cannot be parsed with confidence — blocked (fail-closed)." >&2
  echo "Remove the obfuscating construct (backtick, --%, subexpression, or {}/() grouping)." >&2
  echo "The canonical PowerShell commit form (a here-string piped to 'git commit -F -') is:" >&2
  echo "  @'" >&2
  echo "  <subject>" >&2
  echo "  '@ | git commit -F -" >&2
  echo "or run the commit via the Bash tool (the /commit skill's canonical form)." >&2
}

# Shell-agnostic block text for a PowerShell git command block-dangerous-git
# cannot parse with confidence. That guard also owns destructive non-commit forms,
# so its message names them rather than the commit form. Printed to stderr by the
# caller before it exits 2.
ps::print_unparsable_git_block_message() {
  echo "BLOCKED: this PowerShell 'git' command cannot be parsed with confidence — blocked (fail-closed)." >&2
  echo "A git command carrying a PowerShell construct the guard cannot faithfully tokenize (backtick, '--%', subexpression, script-block grouping, or an unbalanced here-string) could hide a destructive form (reset --hard, clean -fd, checkout/restore), so it is blocked rather than waved through." >&2
  echo "Run the command via the Bash tool, or rewrite it without the unparsable construct." >&2
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
#     mirroring the git guards' sink.
# Backticks are deleted before matching so an escape-obfuscated name (`Set``-Content`)
# resolves to its real form.
#
# SCOPE: this covers the write-GATE bypass only. Secret-pattern and hardcoded-path
# CONTENT scanning of PowerShell writes stays on the Write|Edit-matched guards;
# scanning PowerShell write content is deferred to A2b.
ps::write_bypass() {
  local cmd="$1" scan lcs seg lc head lcq q="\"'"
  ps::blank_herestrings "$cmd"

  # A call `&` / dot-source `.` of a QUOTED writer name runs that string as the
  # command (about_Operators, call operator) — quote-blanking below would erase
  # exactly the evidence, so detect it on the quote-INTACT text first. Only
  # writer/iex names (optionally module-qualified) are matched: a quoted path to
  # an arbitrary program (`& 'C:\Program Files\x.exe'`) stays allowed, the same
  # quoted-command-word residual the Bash guard carries.
  lcq="${PS_BLANKED//\`/}"
  lcq="${lcq,,}"
  if [[ "$lcq" =~ (^|[[:space:]\;\{\}\(\|\&])[.\&][[:space:]]*[$q]([a-z.]+\\)?(set-content|add-content|out-file|tee-object|ac|tee|iex|invoke-expression|new-item|ni|epcsv|export-[a-z]+) ]]; then
    return 0
  fi
  # A call/dot-source of a COMPUTED target — `& ('Set-'+'Content') …`, `& $w …`
  # — evaluates an expression into the command name; it cannot be proven
  # non-writer, so it fails closed like iex (review round 5). Mirrors
  # ps::might_invoke_git's treatment of the same shape on the git side. Both
  # this and the quoted-writer check above accept a statement/block separator
  # boundary (`;& …`), not only whitespace (review round 6).
  if [[ "$lcq" =~ (^|[[:space:]\;\{\}\(\|\&])[.\&][[:space:]]*[\(\$] ]]; then
    return 0
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
  local norm="${lcs//[|;&]/$'\n'}"
  while IFS= read -r seg; do
    seg="${seg#"${seg%%[![:space:]]*}"}" # ltrim
    [[ "$seg" == *'>'* ]] || continue
    # Exclude the `$null` discard (PowerShell's /dev/null).
    [[ "$seg" =~ \>\>?[[:space:]]*\$null([[:space:]]|$) ]] && continue
    # Unwrap grouping parens so a parenthesized producer is judged by what it
    # produces: `('secret') > f` (quote-stripped to `() > f`) reduces to the
    # leading-literal case, `(write-output x) > f` to its real head, and a
    # grouped tool run (`(git diff) > f`) stays the tool-producer allow.
    seg="${seg//[()]/}"
    seg="${seg#"${seg%%[![:space:]]*}"}" # re-ltrim after unwrap
    head="${seg%%[[:space:]]*}"
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
  done <<<"$norm"
  return 1
}
