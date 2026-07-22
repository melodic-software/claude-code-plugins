# shellcheck shell=bash
# PowerShell command classification for guardrails git/commit/write guards.
#
# WHY THIS EXISTS: the git/commit/write guards parse the tool command with a
# Bash-grammar-faithful tokenizer (hook-utils.sh). Claude Code's opt-in
# PowerShell tool (CLAUDE_CODE_USE_POWERSHELL_TOOL=1) surfaces its command in the
# SAME `tool_input.command` field but with PowerShell grammar, so a naive widen
# of the PreToolUse matcher to `Bash|PowerShell` would feed PowerShell text to a
# Bash tokenizer. This library bridges that gap for the CORE, fail-closed scope
# of issue #915; faithful parsing of the full PowerShell grammar (here-strings
# beyond the canonical commit form, backticks, `--%`, subexpressions) is the
# deferred follow-up A2b.
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
#      constructs the Bash tokenizer cannot faithfully handle (backtick,
#      `--%`, subexpression `$(`/`@(`, script-block/grouping `{`/`}`) and any
#      unbalanced here-string. Quoted spans are stripped first so a construct
#      that lives inside commit-message text does not count.
#   3. If such a construct is present AND the command is `git commit`/`git push`
#      shaped, BLOCK fail-closed — the guard cannot confidently parse it. If it
#      is not commit/push shaped, defer to A2b (allow; not this issue's proven
#      bypass surface). Otherwise the reduced command is Bash-tokenizer-faithful
#      and is handed to the existing parser.
#
# OVER-BLOCK, NEVER UNDER-BLOCK is the invariant for the blanker: an ambiguous
# here-string extent is treated as unbalanced (unsafe) rather than blanked, so a
# trailing `| git commit --no-verify` can never be swallowed into the inert
# placeholder and thereby escape detection.
#
# RESIDUAL (documented, deferred to A2b): backtick-escaped quotes and doubled
# `""` inside a double-quoted string diverge between Bash and PowerShell
# tokenization; here they only ever cause an over-block (fail-closed), never an
# under-block. Shell variable / command substitution is not evaluated (same
# residual the Bash guards carry).

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
  local line out="" pending="" in_hs=0 hs_quote="" first2 rest closer
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
    # An opener is `@'` or `@"` as the final two characters of the line.
    if [[ "$line" == *"@'" || "$line" == *'@"' ]]; then
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
# tokenizer cannot faithfully handle. These are exactly the constructs deferred
# to A2b; their presence on a commit/push-shaped command forces a fail-closed
# block rather than a best-effort Bash parse.
ps::has_special_constructs() {
  local scan="$1"
  # The single-quoted needles are literal glob patterns, not expansions.
  # shellcheck disable=SC2016
  case "$scan" in
  *'`'*) return 0 ;;         # backtick: escape / line continuation
  *'--%'*) return 0 ;;       # stop-parsing token
  *'$('*) return 0 ;;        # subexpression
  *'@('*) return 0 ;;        # array subexpression
  *'{'* | *'}'*) return 0 ;; # script block / hashtable grouping
  *) return 1 ;;
  esac
}

# True (0) when the (quote-stripped) text is `git commit`/`git push` shaped: a
# `git` (optionally `git.exe`) command word and a `commit` or `push` word. Coarse
# and deliberately generous — it only gates the fail-closed branch, so
# over-inclusiveness costs at most an over-block on a command that also carries an
# unparseable construct.
ps::is_commit_or_push_shaped() {
  local lc="${1,,}"
  [[ "$lc" =~ (^|[^[:alnum:]_.])git([.]exe)?([^[:alnum:]_]|$) ]] || return 1
  [[ "$lc" =~ (^|[^[:alnum:]_-])(commit|push)([^[:alnum:]_-]|$) ]] || return 1
  return 0
}

# Classify a git/commit-guard command for the resolved tool. Sets PS_SAFE_COMMAND
# (the command the caller should hand to its Bash parser) and returns:
#   0  proceed — parse PS_SAFE_COMMAND (== the original command for the Bash tool)
#   1  allow/skip — a non-commit PowerShell command with a construct deferred to
#      A2b; the guard's concern is not confidently present, so do not block
#   2  block fail-closed — commit/push shaped but not confidently parseable
ps::classify_git_command() {
  local tool="$1" cmd="$2" scan
  PS_SAFE_COMMAND="$cmd"
  [[ "$tool" == "PowerShell" ]] || return 0

  ps::blank_herestrings "$cmd"
  scan=$(ps::blank_quoted_spans "$PS_BLANKED")
  if ((PS_HERESTRING_UNBALANCED)) || ps::has_special_constructs "$scan"; then
    ps::is_commit_or_push_shaped "$scan" && return 2
    return 1
  fi
  # Read by the sourcing guard, not within this library.
  # shellcheck disable=SC2034
  PS_SAFE_COMMAND="$PS_BLANKED"
  return 0
}

# Shell-agnostic block text for a PowerShell commit/push the guard cannot parse
# with confidence. Printed to stderr by the caller before it exits 2.
ps::print_unparseable_block_message() {
  echo "BLOCKED: this PowerShell 'git commit'/'git push' cannot be parsed with confidence — blocked (fail-closed)." >&2
  echo "Use the canonical PowerShell commit form (a here-string piped to 'git commit -F -'):" >&2
  echo "  @'" >&2
  echo "  <subject>" >&2
  echo "  '@ | git commit -F -" >&2
  echo "or run the commit via the Bash tool (the /commit skill's canonical form)." >&2
}

# True (0) when a PowerShell command authors file content in a way that bypasses
# the Write/Edit hook gate: a content-authoring cmdlet (Set-Content, Add-Content,
# Out-File, Tee-Object), or a stdout redirect (`>`/`>>`, not the `$null` discard)
# whose producer is a content emitter (echo / Write-Output / Write-Host or a bare
# string / here-string literal). Producer-scoped to match the Bash guard, which
# allows `<tool> ... > out` (the producer is the tool, not a content author).
#
# SCOPE: this covers the write-GATE bypass only. Secret-pattern and hardcoded-path
# CONTENT scanning of PowerShell writes stays on the Write|Edit-matched guards;
# scanning PowerShell write content is deferred to A2b.
ps::write_bypass() {
  local cmd="$1" scan lcs seg lc head
  ps::blank_herestrings "$cmd"
  scan=$(ps::blank_quoted_spans "$PS_BLANKED")
  lcs="${scan,,}"

  # Content-authoring cmdlets are a write by nature. Detected on the quote-stripped
  # text so a cmdlet named inside message text is inert.
  if [[ "$lcs" =~ (^|[[:space:]\;\|\&\(])(set-content|add-content|out-file|tee-object)([[:space:]]|$) ]]; then
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
    head="${seg%%[[:space:]]*}"
    case "$seg" in
    '>'*) return 0 ;; # leading literal (string stripped away) was the producer
    *) ;;
    esac
    case "$head" in
    echo | write-output | write-host | "${PS_HERESTRING_PLACEHOLDER,,}") return 0 ;;
    *) ;;
    esac
  done <<<"$norm"
  return 1
}
