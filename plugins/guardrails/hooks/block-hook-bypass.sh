#!/usr/bin/env bash
# PreToolUse hook: block Bash workarounds that bypass Write/Edit hook gates.
# Triggered on Bash tool calls.
#
# Catches common file-write bypass patterns:
#   cat > path
#   echo ... > path      (and printf ... > path)
#   python3 -c ... file write
#
# Detection runs over the LITERAL-STRIPPED command for the executable token
# (so prose/commit text merely MENTIONING the pattern is not a false positive),
# and over the RAW command for the python write indicators (they legitimately
# live inside the quoted `-c` payload the strip removes).
#
# The echo/printf redirect is PRODUCER-SCOPED (see producer_redirect_bypass): it
# fires only when the echo/printf is itself the command whose stdout is
# redirected into a real file, NOT when an `echo` token and a `>` token merely
# co-occur in one compound command (`bash x.sh > out.json && echo done` — the
# redirect's producer is `bash`) or survive only inside a quoted argument.
#
# SCOPE (documented residual): the strip treats a quoted span as inert, so a
# write inside a command substitution in double quotes
# (`echo "$(python3 -c 'import pathlib ...')"`) is NOT caught — catching it needs
# a shell parser, and neutralizing quotes re-blocks inert prose. An LLM never
# emits this form; the deny-list plus human oversight are the adversarial layers.
# The only supported deliberate bypass is the kill switch
# (block_hook_bypass_enabled userConfig option set to false).
#
# BLOCKING: exits 2 on any detected bypass form.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "BLOCK_HOOK_BYPASS"

# Bundled PowerShell-command classifier — this guard is matched on both the Bash
# and the (opt-in) PowerShell tool. Resolved under the plugin root (CC sets
# CLAUDE_PLUGIN_ROOT; the BASH_SOURCE fallback keeps the contract tests working
# when it is unset).
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/powershell/ps-command.sh
source "$PLUGIN_ROOT/lib/powershell/ps-command.sh"

# High-res start stamp for the telemetry envelope. EPOCHREALTIME is Bash 5.0+;
# on older bash it is unset, so default to empty and skip telemetry (the block
# still fires). Referencing it bare under `set -u` would abort before exit.
start=${EPOCHREALTIME:-}

# hook::buffer_stdin encapsulates the Win32-pipe-safe bounded fd0 read. rc 1
# (empty stdin) skips like the empty-COMMAND guard below; rc 2 (read timed out
# before a complete payload) FAILS CLOSED — the guard cannot evaluate the tool
# call, and a silent skip would pass exactly the traffic this guard exists to
# stop. buffer_stdin already printed the BLOCKED reason to stderr. Buffering
# does not require jq (hook::buffer_stdin's own JSON-completeness check is
# jq-optional), so it runs before the jq gate below — hook::require_jq needs
# the buffered input for its once-per-session notice scoping.
INPUT=$(hook::buffer_stdin) || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}

# jq is required to parse the tool payload. hook::require_jq fails OPEN
# (advisory hooks never block over a missing prerequisite) but makes the
# degraded state visible to both the user (systemMessage) and the agent
# (additionalContext), once per session — see docs/conventions/hook-observability/.
hook::require_jq "PreToolUse" "guardrails-block-hook-bypass" "$INPUT"

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null | tr -d '\r')
[[ -n "$COMMAND" ]] || exit 0
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // "Bash"' 2>/dev/null | tr -d '\r')

# Privacy-safe telemetry subject: `Bash:<first-token>` with leading `sudo` /
# env-assignment prefixes stripped and the token basenamed. Never the full
# command.
bash_subject() {
  local cmd="$1" tok
  tok="${cmd%%[[:space:]]*}"
  while [[ "$tok" == "sudo" || "$tok" == *=* ]] &&
    [[ -n "$cmd" && "$cmd" == *[[:space:]]* ]]; do
    cmd="${cmd#*[[:space:]]}"
    cmd="${cmd#"${cmd%%[![:space:]]*}"}"
    tok="${cmd%%[[:space:]]*}"
  done
  printf 'Bash:%s' "${tok##*/}"
}

if [[ "$TOOL_NAME" == "Bash" ]]; then
  SUBJECT=$(bash_subject "$COMMAND")
else
  SUBJECT="$TOOL_NAME"
fi

# Emit one telemetry envelope: $1 status, $2 form ("" when not blocked). Gated
# on the high-res start stamp and the opt-in sink, so the unwired default path
# spawns no telemetry-only subprocess.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  data=$(jq -n --arg tool "$TOOL_NAME" --arg subject "$SUBJECT" --arg form "$2" \
    '{tool:$tool,subject:$subject,form:$form}' 2>/dev/null) || data='{"tool":"Bash","subject":"","form":""}'
  hook::emit_telemetry "block-hook-bypass" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# Strip single- and double-quoted literal spans so the executable-token scan
# sees only shell syntax, not payload text. Heredoc bodies are dropped wholesale
# (their content is data, not a command). The quote strip carries an OPEN quote
# across physical lines, so a quoted argument spanning newlines (a `--body "..."`
# payload whose text merely mentions `echo`/`>`) stays inert end-to-end instead
# of leaking its tokens from the second line on. An unquoted `#` comment is dropped
# to end-of-line without carrying quote state, so an unmatched quote inside a
# comment cannot leak a span onto the next line (see the `#` case below).
strip_literals() {
  local cmd="$1" line result="" in_heredoc=0 delim="" trimmed
  # `open_quote` carries a single- or double-quote span across lines: "" outside
  # any quote, "'" or '"' inside one that opened on an earlier line. `open_keep`
  # carries, alongside it, whether that span is a REDIRECT OPERAND (a quoted
  # target: the char before the opening quote is `>`) — those are kept as literal
  # content instead of dropped, so a quoted write target survives the strip.
  local open_quote="" open_keep="" out i n c prev tail
  # `(^|[^<])` before `<<` excludes a here-string `<<<` — matching `<<` inside
  # `<<<` would capture a bogus delimiter and strand the stripper in-heredoc,
  # swallowing every later line (a here-string bypass). The delimiter body
  # excludes `<` for the same reason, and `>` so a redirect glued to the
  # delimiter (`cat <<EOF>file`) terminates the token — bash ends the delimiter
  # word at `>`, so the `>file` is a real redirect that must reach the scan
  # instead of being swallowed into a bogus `EOF>file` delimiter.
  local heredoc_start_re='(^|[^<])<<-?[[:space:]]*([^[:space:]<>]+)'

  while IFS= read -r line || [[ -n "$line" ]]; do
    if ((in_heredoc)); then
      # Trim + literal compare, NOT `=~ "$delim"`: inside a bash regex the
      # delimiter would be treated as a pattern, so a metachar delim (EOF+,
      # BODY[1], …) would never match its own terminator — leaving in_heredoc
      # set and silently swallowing every later line (a crafted-heredoc bypass).
      trimmed="${line#"${line%%[![:space:]]*}"}"
      trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
      [[ "$trimmed" == "$delim" ]] && in_heredoc=0
      continue
    fi
    # A heredoc opener is shell syntax only OUTSIDE a quoted span — a `<<EOF`
    # that survives inside a carried multi-line quote is payload text, not an
    # operator, and must not strand the stripper in-heredoc.
    if [[ -z "$open_quote" && "$line" =~ $heredoc_start_re ]]; then
      delim="${BASH_REMATCH[2]}"
      # `<<\EOF` backslash-quotes the delimiter (same effect as `<<'EOF'`) — the
      # terminator line is bare `EOF`, so strip the leading backslash too.
      delim="${delim#\\}"
      delim="${delim#\'}"
      delim="${delim%\'}"
      delim="${delim#\"}"
      delim="${delim%\"}"
      # Drop only the heredoc operator + delimiter token, keeping the text before
      # `<<` AND any text after the delimiter on the opener line — a trailing
      # stdout redirect (`cat <<EOF > file`) must still reach the redirect scan
      # rather than being truncated away with the body.
      line="${line%%<<*}${line#*"${BASH_REMATCH[0]}"}"
      in_heredoc=1
    fi
    # Char-by-char literal strip honoring bash quoting, resuming from `open_quote`
    # so a span opened on an earlier line is still inert here. Single quotes take
    # no escapes; inside double quotes a backslash escapes the next char (so `\"`
    # does not close). Unquoted text — command tokens, redirects, separators — is
    # kept; quoted spans are dropped.
    out=""
    i=0
    n=${#line}
    while ((i < n)); do
      c="${line:i:1}"
      if [[ "$open_quote" == "'" ]]; then
        if [[ "$c" == "'" ]]; then
          open_quote=""
          open_keep=""
        elif [[ -n "$open_keep" ]]; then
          out+="$c"
        fi
        ((i += 1))
      elif [[ "$open_quote" == '"' ]]; then
        if [[ "$c" == $'\\' ]]; then
          # Inside double quotes a backslash escapes the next char; when this span
          # is a kept redirect operand, keep that escaped char literally.
          [[ -n "$open_keep" ]] && out+="${line:i+1:1}"
          ((i += 2))
        else
          if [[ "$c" == '"' ]]; then
            open_quote=""
            open_keep=""
          elif [[ -n "$open_keep" ]]; then
            out+="$c"
          fi
          ((i += 1))
        fi
      else
        case "$c" in
        "'" | '"')
          # Open a quote span. Keep its inner content (as a literal, quote marks
          # dropped) ONLY when it belongs to a REDIRECT-OPERAND word — the word the
          # quote sits in began right after a `>`. This preserves a quoted write
          # target (`echo x > "$out"` -> `echo x > $out`, still a detectable write;
          # partial `echo x > /dev/"null"` -> `echo x > /dev/null`, still exempt),
          # while a quoted span anywhere else (prose, `--body "..."`, a quoted echo
          # argument) is dropped as before so its tokens stay inert. Boundary: strip
          # the current trailing operand word (chars up to the last whitespace or
          # shell metachar), then the whitespace before it, and test for `>`.
          open_quote="$c"
          tail="${out%"${out##*[[:space:]<>|&\;()]}"}"
          tail="${tail%"${tail##*[![:space:]]}"}"
          [[ "${tail: -1}" == ">" ]] && open_keep=1 || open_keep=""
          ((i += 1))
          ;;
        '#')
          # `#` starts a comment only at a word boundary — start of line, or
          # after an unquoted blank or shell metacharacter (`;|&()<>`). The rest
          # of the physical line is comment text and is dropped WITHOUT touching
          # `open_quote`, so an unmatched quote inside a comment (`true # "`)
          # cannot leak a quote span onto the next line and silently strip a real
          # producer there. Mid-word (`echo a#b`, `${v#x}`) the `#` is literal and
          # kept, so a genuine `a#b > file` write still reaches the scan. A
          # backslash-escaped `#` never lands here — the `\` case above consumes it.
          if ((i == 0)) ||
            {
              prev="${line:i-1:1}"
              # portability-ok: `\<` and `\>` here are backslash-escaped literals
              # inside a Bash bracket PATTERN, not GNU grep/sed word-boundary
              # operators; Bash pattern matching is identical on BSD userland.
              [[ "$prev" == [[:space:]] || "$prev" == [\;\|\&\(\)\<\>] ]]
            }; then
            break
          fi
          out+="$c"
          ((i += 1))
          ;;
        $'\\')
          out+="${line:i:2}"
          ((i += 2))
          ;;
        *)
          out+="$c"
          ((i += 1))
          ;;
        esac
      fi
    done
    result+="${out}"$'\n'
  done <<<"$cmd"
  printf '%s' "${result%$'\n'}"
}

EXECUTABLE=$(strip_literals "$COMMAND")
EXEC_LC="${EXECUTABLE,,}"
COMMAND_LC="${COMMAND,,}"

# `cat` immediately before a redirect, with or without a space (`cat>file`).
# Scanned PER SEGMENT (see cat_redirect_bypass), so `;|&()` never reach it — the
# leading class is kept for the pre-segmentation shape and costs nothing.
# Two spellings, deliberately NOT collapsed into `cat[[:space:]]*1?>`: the fd
# digit needs a COMMAND BOUNDARY before it, or `cat1>file` — an unrelated binary
# named `cat1` with an ordinary redirect — reads as `cat` plus an fd marker and
# blocks. `cat>file` keeps zero-space (no digit to confuse), while the explicit
# `1>` form requires whitespace after the command word, the same word-boundary
# discipline `_producer_head` already applies to echo/printf. Other fds cannot
# reach either branch: `cat 2>err` matches neither `cat[[:space:]]*>` nor
# `cat[[:space:]]+1>`.
_cat_redir='(^|[[:space:];|&()]+)cat([[:space:]]*>|[[:space:]]+1>)'
# Runs on a NORMALIZED segment. normalize_segments sentinels `>&` / `<&` / `&>`
# as `\x01` (and escaped separators as `\x02`) so an fd dup is not split as a
# control operator, then restores them before storing NORMALIZED_SEGMENTS — the
# text both call sites read. A segment therefore reaches this scan with a literal
# `&`, and the `&` in the target class is what keeps `cat 1>&2` and `cat 1>&-`
# out: a dup leaves NO file target, and cat_redirect_bypass skips a segment whose
# target came back empty.
# Both SENTINELS are excluded as well, and that is not redundant. The restore was
# silently version-dependent until it was fixed: on bash >= 5.2 an unquoted `&` in
# a substitution replacement means "the text just matched", so the sentinel was
# restored to itself and survived into the segment (see the `\&` note in
# normalize_segments). Excluding both bytes means a dup is rejected whichever one
# arrives, so a regression in the restore cannot silently turn one into a write.
# One stdout redirect and its target word. `[^0-9&]` before the operator keeps
# other-fd (`2>`, `21>`) and combined (`&>`) redirects out, while the optional
# `1` admits the EXPLICIT stdout spelling — `1>file` is stdout exactly as `>file`
# is, and omitting it left `cat >/dev/null 1>real.txt` reading as a discard. The
# target class excludes `&`, so an fd dup (`>&1`) is not mistaken for a file.
# Used by set_last_stdout_target, never matched alone: the PRESENCE of a
# `/dev/null` redirect proves nothing (see below).
_redir_scan=$'(^|[^0-9&])1?>>?[[:space:]]*([^|&>[:space:]\x01\x02]+)'
# A simple-command segment whose command token is `echo` or `printf` — the
# content producers a `> file` redirect turns into a Write/Edit bypass. Anchored
# to the segment start (see producer_redirect_bypass), so it never matches an
# `echo`/`printf` mention buried mid-command.
_producer_head='^(echo|printf)([[:space:]]|>)'
# Command-prefix tokens that legitimately precede the real command word in a
# simple command: environment assignments (`FOO=bar cmd`) and the command-name
# modifiers `command` / `builtin` / `exec` / `env`. Peeling them (see
# producer_redirect_bypass) exposes an echo/printf hidden behind a valid prefix
# (`command echo x > f`, `FOO=bar echo x > f`) so the producer scan still sees it.
# A bare `coproc` is a command header that can precede the producer of a simple
# command (`coproc echo x > f`), so it is peeled too. Only the bare keyword is
# peeled: the optional NAME form is `coproc NAME compound-command`, so eating a
# second token would swallow the real command word in `coproc echo …`.
# The compound-command header keywords / group opener / pipeline negation that put
# a producer inside a loop, conditional, or negated command
# (`if`/`elif`/`while`/`until`/`do`/`then`/`else`/`{`/`!`) are peeled by the same
# pass. Peeling is safe: the `_producer_head` gate still requires echo/printf, so
# revealing a NON-echo command word can never cause a block.
_cmd_prefix='^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|command|builtin|exec|env|coproc|if|elif|then|else|while|until|do|!|\{)([[:space:]]|$)'
# Options of the two command-name modifiers that take options (bash built-in help:
# `command [-pVv]`, `exec [-cl] [-a name]`). A modifier alone is peeled by
# _cmd_prefix, but its options otherwise sit between the modifier and the producer
# (`command -p echo x > f`, `exec -a name echo x > f`) and hide it. Peeled in the
# same loop, on the already-lowercased segment, and ONLY when `command`/`exec` was
# the immediately preceding modifier — `env`/`builtin` keep their bare-only floor
# (see the SCOPE note below), so option grammar is not widened past those two.
# `_modifier_opt_arg` covers the one value-taking option — exec's `-a name` (a
# short-option cluster ending in `a`) — and consumes the NAME word too;
# `_modifier_opt` covers no-argument clusters; `_modifier_optend` peels a lone `--`
# end-of-options marker (`exec -- echo x > f` writes the file). Safe like the
# modifier peel: `_producer_head` still gates, so exposing a non-producer word
# never blocks. Only leading (post-modifier) options match, so a real command word
# — which never starts with `-` — is untouched. EXCEPTION: `command -v`/`-V` (lower-
# cased to `v`) flip `command` to DESCRIBE its argument rather than run it, so a
# following `echo`/`printf` is a bareword being looked up, not a content producer
# (`command -v echo > f` writes the word "echo", not echo's output) — that segment
# is skipped, not blocked, keeping the producer-scoped contract.
_modifier_opt_arg='^-[a-z]*a[[:space:]]+[^[:space:]]+([[:space:]]|$)'
_modifier_opt='^-[a-z]+([[:space:]]|$)'
_modifier_optend='^--([[:space:]]|$)'
# A leading redirection element (`> file cmd`, `< in cmd`, `2> f cmd`, `>& n cmd`):
# bash permits redirections before the command word, so a producer can hide behind
# one (`> real.txt echo x`). Peeled (operator + its target word) — like _cmd_prefix
# — to expose the producer for _producer_head, while _echo_file_out and the
# still run on the UN-peeled segment so the redirect itself remains the write
# signal. Not anchored to stdout-to-file: any leading redirect is peeled for
# producer exposure; whether a real file write exists is decided by _echo_file_out.
_leading_redir='^([0-9]*(>>?|<)&?|&>>?)[[:space:]]*'
# stdout-to-file redirect: `>` / `>>` NOT preceded by an fd digit or `&`, so
# stderr/fd redirects (`2>/dev/null`, `2>&1`, `&>`) do not trip. A stdout discard
# is exempt — that's not a Write/Edit bypass — but the exemption is decided by
# set_last_stdout_target, not by this pattern: the discard must be the EFFECTIVE
# target, not merely present somewhere in the segment.
_echo_file_out='(^|[^0-9&])1?>>?[[:space:]]*[^|&>[:space:]]'
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
# SCOPE (documented residual): the command-prefix peel (see _cmd_prefix) covers
# the bounded shell-grammar set — env assignments and `command`/`builtin`/`exec`/
# bare `env`. External command-runner utilities that take their own options and a
# command argument — `nohup`/`nice`/`time`/`timeout N`/`sudo`/`stdbuf -oL`/`xargs`,
# and non-bare `env` (`env -i echo …`, `/usr/bin/env echo …`) — are NOT peeled, so
# `nohup echo x > f` and friends are not caught. Peeling them correctly requires
# per-utility argument parsing (each has a different option grammar), out of scope
# for this false-positive fix; the forms are structurally unusual for LLM output
# and covered by an accepted-floor test.
#
# SCOPE (documented residual): only the BARE `coproc echo …` header is peeled (see
# _cmd_prefix). The named form `coproc NAME { echo x > f; }` is not, because NAME is
# indistinguishable from a command word by prefix-peeling alone, and the redirect
# there is group-level (same brace-group floor as above). Structurally unusual for
# LLM output and covered by an accepted-floor test.
#
# Segmentation is shared with the `cat >` scan (cat_redirect_bypass) through
# normalize_segments, so both lanes agree on escaped separators and on the
# fd-duplication sentinel instead of drifting apart behind two splitters.
normalize_segments() {
  local exec_lc="$1" seps=$';\n|&()' soh=$'\x01' esc=$'\x02' normalized s i
  # Protect backslash-escaped separators (`echo x \; > file`, an escaped-newline
  # line continuation `echo x \<newline> > file`) before the split: bash keeps an
  # escaped separator inside the SAME simple command (`\;` is a literal argument,
  # `\<newline>` is removed as a continuation), so it must not cut the producer
  # away from its redirect. strip_literals preserves the escaping backslash, so an
  # escaped separator reaches here as `\<sep>`. Sentinel each, then restore to an
  # inert space after the split — its only role is to stay non-splitting; its
  # literal value never feeds the producer/redirect scan.
  normalized="$exec_lc"
  for ((i = 0; i < ${#seps}; i++)); do
    s="${seps:i:1}"
    normalized="${normalized//\\"$s"/$esc}"
  done
  # Protect fd-duplication / both-streams redirect ampersands (`2>&1`, `>&2`,
  # `&>file`) with a sentinel before the `&` control-operator split below, so a
  # redirect `&` never cuts a producer away from a LATER stdout redirect —
  # `echo x 2>&1 > file` and `echo x >&2 > file` must stay ONE segment so the
  # trailing `> file` is still scanned as the echo's own. Restored right after the
  # split, before the per-segment scan. `&&` and a background `&` carry no
  # adjacent `<`/`>`, so they are untouched here and still split as separators.
  normalized="${normalized//>&/>$soh}"
  normalized="${normalized//<&/<$soh}"
  normalized="${normalized//&>/$soh>}"
  # Each remaining separator becomes a segment boundary; args cannot contain a raw
  # separator (quoted spans are already stripped), so a segment holds at most one
  # simple command and the redirect in it is that command's own.
  normalized="${normalized//[$seps]/$'\n'}"
  # `\&`, not a bare `&`: since bash 5.2 an UNQUOTED `&` in a substitution
  # REPLACEMENT expands to the text the pattern just matched (the sed rule), so
  # `${normalized//"$soh"/&}` restored the sentinel to itself — a silent no-op on
  # every bash >= 5.2, while still restoring correctly on older ones. That left
  # the surviving `\x01` for the per-segment scans to trip over, which is why
  # _redir_scan's target class excludes the sentinel as well as `&`.
  normalized="${normalized//"$soh"/\&}"
  normalized="${normalized//"$esc"/ }"
  NORMALIZED_SEGMENTS="$normalized"
}

# The EFFECTIVE stdout destination of a segment, into LAST_STDOUT_TARGET (empty
# when the segment redirects stdout nowhere).
#
# Bash applies redirections LEFT TO RIGHT, so the last one wins: `cat >
# /dev/null > real.txt` writes to real.txt, and `cat > /dev/null 1>real.txt`
# does too. A check that exempted a segment on merely CONTAINING a `/dev/null`
# redirect would hand an attacker a one-token bypass of this whole guard — write
# the discard first, the real file second. Only the final target may exempt.
#
# Sets a global rather than echoing: this runs per segment on every Bash call,
# and a command substitution would add a fork to each one.
LAST_STDOUT_TARGET=""
set_last_stdout_target() {
  local rest="$1"
  LAST_STDOUT_TARGET=""
  while [[ "$rest" =~ $_redir_scan ]]; do
    LAST_STDOUT_TARGET="${BASH_REMATCH[2]}"
    # Quoted so the consumed text is stripped literally — a target may hold glob
    # metacharacters, and an unquoted pattern would eat the wrong span.
    rest="${rest#*"${BASH_REMATCH[0]}"}"
  done
}

# `cat >` with no input file is content authoring redirected into a file — the
# heredoc/typed-content Write bypass. Scanned per segment so the /dev/null
# DISCARD exemption cannot leak across a compound command: `cat > /dev/null &&
# cat > real.txt` still blocks on its second segment.
cat_redirect_bypass() {
  local seg
  while IFS= read -r seg || [[ -n "$seg" ]]; do
    [[ "$seg" =~ $_cat_redir ]] || continue
    set_last_stdout_target "$seg"
    # No FILE operand means no file write: `cat 1>&2` duplicates stdout onto
    # stderr and `cat 1>&-` closes it. _redir_scan rejects `&` targets, so both
    # leave the target empty — which must read as "nothing to block", never as a
    # write. Checked before the /dev/null test so an empty value cannot fall
    # through to `return 0`.
    [[ -n "$LAST_STDOUT_TARGET" ]] || continue
    [[ "$LAST_STDOUT_TARGET" == "/dev/null" ]] && continue
    return 0
  done <<<"$NORMALIZED_SEGMENTS"
  return 1
}

producer_redirect_bypass() {
  local seg
  while IFS= read -r seg || [[ -n "$seg" ]]; do
    seg="${seg#"${seg%%[![:space:]]*}"}"
    # Peel leading command-prefix tokens (see _cmd_prefix) and leading redirections
    # (see _leading_redir) into `head` so a producer hidden behind an env assignment
    # (`FOO=bar echo x > f`), a command-name modifier (`command echo ...`, `builtin
    # printf ...`, `exec echo ...`, `env echo ...`, `coproc echo ...`), a
    # compound-command header / group opener / negation (`; do echo x > f`, `if echo
    # x > f`, `while echo ...`, `! echo ...`, `{ echo ...`), or a leading redirect
    # (`> real.txt echo x`) is still seen as the segment's command word. The redirect
    # itself is left in `seg`: _echo_file_out and set_last_stdout_target below decide whether a
    # real file write exists, so a leading redirect stays the write signal.
    local head="$seg" tgt prev_mod=""
    while :; do
      if [[ "$head" =~ $_cmd_prefix ]]; then
        prev_mod="${BASH_REMATCH[1]}"
        head="${head#"${BASH_REMATCH[1]}"}"
        head="${head#"${head%%[![:space:]]*}"}"
        continue
      fi
      if [[ "$head" =~ $_leading_redir ]]; then
        prev_mod=""
        head="${head#"${BASH_REMATCH[0]}"}"
        tgt="${head%%[[:space:]]*}"
        head="${head#"$tgt"}"
        head="${head#"${head%%[![:space:]]*}"}"
        continue
      fi
      # Options belong only to the option-taking modifiers command/exec (see
      # _modifier_opt*); env/builtin keep their bare-only floor. The arg-taking
      # form (exec's `-a name`) is peeled first so its NAME word is consumed too,
      # else the plain-cluster peel would stop at `-a` and leave NAME masking the
      # producer. `--` ends options (`exec -- echo x > f`).
      if [[ "$prev_mod" == command || "$prev_mod" == exec ]]; then
        if [[ "$head" =~ $_modifier_opt_arg || "$head" =~ $_modifier_opt ||
          "$head" =~ $_modifier_optend ]]; then
          # `command -v`/`-V` describes its argument instead of running it, so the
          # echo/printf after it is a looked-up bareword, not a producer — skip the
          # whole segment rather than exposing it (would be a false block).
          [[ "$prev_mod" == command && "${BASH_REMATCH[0]}" == *v* ]] && continue 2
          head="${head#"${BASH_REMATCH[0]}"}"
          head="${head#"${head%%[![:space:]]*}"}"
          continue
        fi
      fi
      break
    done
    [[ "$head" =~ $_producer_head ]] || continue
    [[ "$seg" =~ $_echo_file_out ]] || continue
    # Same left-to-right rule as the cat lane: `echo x > /dev/null > real.txt`
    # writes to real.txt. The old presence test exempted it.
    set_last_stdout_target "$seg"
    [[ "$LAST_STDOUT_TARGET" == "/dev/null" ]] && continue
    return 0
  done <<<"$NORMALIZED_SEGMENTS"
  return 1
}

# The scope this guard actually has, stated where a reader meets it. Without it
# the block reads as "shell file writes are blocked" and is over-trusted in both
# directions: an agent contorts around a restriction a script file does not
# have, and a human credits the guard with coverage it never claimed. The guard
# is a speed bump against specific accidental write-workaround forms in one
# command string, not a boundary — and it is deliberately producer-scoped, so
# ordinary data-processing redirects (`sort f > out`, `curl … > page.html`) are
# allowed by design too, not only writes inside an invoked script.
_BYPASS_SCOPE_NOTE="Scope: only this command string is inspected — known shell \
file-write forms plus recognized inline interpreter code (e.g. python -c). Writes \
inside an invoked script file or a program's own opaque code, and redirects \
produced by another program, are not seen."

block_bypass() {
  local form="$1" reason="$2"
  echo "BLOCKED: $reason" >&2
  echo "Use the Write or Edit tool instead of a shell file-write workaround." >&2
  echo "$_BYPASS_SCOPE_NOTE" >&2
  emit_tel "blocked" "$form"
  exit 2
}

# PowerShell tool: the Bash strip / producer scan below does not model the
# PowerShell write surface. Detect PowerShell file-write forms (Set-Content /
# Add-Content / Out-File / Tee-Object, or a content-producer `>`/`>>` redirect)
# and skip the Bash-specific scans. SCOPE: this closes the write-GATE bypass;
# secret-pattern and hardcoded-path CONTENT scanning of PowerShell writes stays
# on the Write|Edit-matched guards (deferred to A2b).
if [[ "$TOOL_NAME" == "PowerShell" ]]; then
  if ps::write_bypass "$COMMAND"; then
    block_bypass "powershell-write" "PowerShell file-write cmdlet/redirect bypasses Write/Edit hooks"
  fi
  # Interpreter-producer writes (`python3 -c "<inline code that writes>"`) route
  # around Write/Edit whichever tool launches them, and ps::write_bypass models only
  # PowerShell cmdlet/redirect forms. On the BASH tool the precise `python3 -c` scan
  # (further below) is reliable: strip_literals is genuinely quote-aware, and Bash
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
  #   (b) a python3 interpreter TOKEN plus a `-c` inline-code flag both present
  #       (ps::might_write_via_python3, quote-INTACT + backtick-recovered) — where a
  #       COMPUTED `-c` (`python3 ('-'+'c') …`) is caught by fail-closing on a
  #       non-tokenizable arg construct when no literal `-c` is present.
  # `-c` is REQUIRED and position-independent, so a legitimate script/module run
  # (`python3 build.py`, `python3 -m tool …`) that merely touches an `open(`-like
  # path is NOT blocked — only inline-code writes are. ACCEPTED OVER-BLOCK (the
  # fail-closed choice the user approved for this lane): a command that only MENTIONS
  # `python3 … -c` + a write indicator in prose, a line/block comment, or a quoted
  # string now blocks; here-string mentions stay inert (blanked first, like the git
  # lane). ACCEPTED RESIDUAL: a stdin heredoc (`python3 - <<PY … PY`, no `-c`) is
  # uncovered here, as it is today.
  ps::blank_herestrings "$COMMAND"
  if py_write_indicator "$COMMAND_LC" && ps::might_write_via_python3 "$PS_BLANKED"; then
    block_bypass "python-write" "python3 -c inline-code file write bypasses Write/Edit hooks"
  fi
  emit_tel "ok" ""
  exit 0
fi

# Split once into simple-command segments; both redirect scans below read it.
# EXEC_LC (lowercased stripped form) gives case-insensitive command-token
# detection.
normalize_segments "$EXEC_LC"

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

# python3 -c with file-write indicators. Detect the `python3 -c` INVOCATION in
# the literal-stripped form (EXEC_LC) so prose/commit text merely mentioning it
# is not a false positive; scan the RAW command (COMMAND_LC) for the write
# indicators — they legitimately live inside the quoted `-c` payload the strip removes.
# The command-word boundary admits a leading path (`/` `\` in the class) and an
# optional `.exe`, so a path-qualified interpreter (`/usr/bin/python3 -c`,
# `/c/Python313/python3.exe -c`) is the same write — anchored on the python3
# basename, so `notpython3` (no separator before it) stays inert.
if [[ "$EXEC_LC" =~ (^|[[:space:];|&()/\\]+)python3(\.exe)?[[:space:]]+-c ]] &&
  py_write_indicator "$COMMAND_LC"; then
  block_bypass "python-write" "python3 -c file write bypasses Write/Edit hooks"
fi

emit_tel "ok" ""
exit 0
