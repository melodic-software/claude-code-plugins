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

# High-res start stamp for the telemetry envelope. EPOCHREALTIME is Bash 5.0+;
# on older bash it is unset, so default to empty and skip telemetry (the block
# still fires). Referencing it bare under `set -u` would abort before exit.
start=${EPOCHREALTIME:-}

# jq is required to parse the tool payload. Fail OPEN when it is absent, but make
# the degraded state visible rather than silently disabling the guard.
if ! command -v jq >/dev/null 2>&1; then
  echo "guardrails/block-hook-bypass: jq not found on PATH — guard disabled (install jq to enable)." >&2
  exit 0
fi

# hook::buffer_stdin encapsulates the Win32-pipe-safe bounded fd0 read. rc 1
# (empty stdin) skips like the empty-COMMAND guard below; rc 2 (read timed out
# before a complete payload) FAILS CLOSED — the guard cannot evaluate the tool
# call, and a silent skip would pass exactly the traffic this guard exists to
# stop. buffer_stdin already printed the BLOCKED reason to stderr.
INPUT=$(hook::buffer_stdin) || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null | tr -d '\r')
[[ -n "$COMMAND" ]] || exit 0

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

SUBJECT=$(bash_subject "$COMMAND")

# Emit one telemetry envelope: $1 status, $2 form ("" when not blocked). Gated
# on the high-res start stamp and the opt-in sink, so the unwired default path
# spawns no telemetry-only subprocess.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  data=$(jq -n --arg subject "$SUBJECT" --arg form "$2" \
    '{tool:"Bash",subject:$subject,form:$form}' 2>/dev/null) || data='{"tool":"Bash","subject":"","form":""}'
  hook::emit_telemetry "block-hook-bypass" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# Strip single- and double-quoted literal spans so the executable-token scan
# sees only shell syntax, not payload text. Heredoc bodies are dropped wholesale
# (their content is data, not a command). The quote strip carries an OPEN quote
# across physical lines, so a quoted argument spanning newlines (a `--body "..."`
# payload whose text merely mentions `echo`/`>`) stays inert end-to-end instead
# of leaking its tokens from the second line on.
strip_literals() {
  local cmd="$1" line result="" in_heredoc=0 delim="" trimmed
  # `open_quote` carries a single- or double-quote span across lines: "" outside
  # any quote, "'" or '"' inside one that opened on an earlier line.
  local open_quote="" out i n c
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
        [[ "$c" == "'" ]] && open_quote=""
        ((i += 1))
      elif [[ "$open_quote" == '"' ]]; then
        if [[ "$c" == $'\\' ]]; then
          ((i += 2))
        else
          [[ "$c" == '"' ]] && open_quote=""
          ((i += 1))
        fi
      else
        case "$c" in
        "'")
          open_quote="'"
          ((i += 1))
          ;;
        '"')
          open_quote='"'
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
_cat_redir='(^|[[:space:];|&()]+)cat[[:space:]]*>'
# A simple-command segment whose command token is `echo` or `printf` — the
# content producers a `> file` redirect turns into a Write/Edit bypass. Anchored
# to the segment start (see producer_redirect_bypass), so it never matches an
# `echo`/`printf` mention buried mid-command.
_producer_head='^(echo|printf)([[:space:]]|>)'
# stdout-to-file redirect: `>` / `>>` NOT preceded by an fd digit or `&`, so
# stderr/fd redirects (`2>/dev/null`, `2>&1`, `&>`) do not trip. _echo_devnull
# exempts a stdout discard (`>/dev/null`) — that's not a Write/Edit bypass.
_echo_file_out='(^|[^0-9&])>>?[[:space:]]*[^|&>[:space:]]'
_echo_devnull='(^|[^0-9&])>>?[[:space:]]*/dev/null'
_py_write='open[[:space:]]*\(|\.write[[:space:]]*\(|pathlib|path[[:space:]]*\('

# Flag ONLY when the producer being redirected into a real file is echo/printf
# authoring content — not any command string that merely co-mentions an `echo`
# token and a `>` token. Split the literal-stripped command into simple-command
# segments on shell separators (`; | & ( )` and newlines), then require, WITHIN
# one segment, that the command token is echo/printf AND that same segment
# redirects stdout to a real file. This passes `bash x.sh > out.json && echo done`
# (the redirect's producer is `bash`, not the trailing `echo`) and a bounded poll
# loop `... > poll.json; echo "..."`, while still blocking `echo "x" > file`.
producer_redirect_bypass() {
  local exec_lc="$1" seps=$';\n|&()' normalized seg
  # Each separator becomes a segment boundary; args cannot contain a raw
  # separator (quoted spans are already stripped), so a segment holds at most one
  # simple command and the redirect in it is that command's own.
  normalized="${exec_lc//[$seps]/$'\n'}"
  while IFS= read -r seg || [[ -n "$seg" ]]; do
    seg="${seg#"${seg%%[![:space:]]*}"}"
    # Peel leading compound-command keywords / group openers so a producer in a
    # loop, conditional, or brace-group body is still seen as the command word
    # (`; do echo x > f`, `then echo ...`, `{ echo ...`) rather than being hidden
    # behind the `do`/`then`/`else`/`{` token at the segment head.
    while [[ "$seg" =~ ^(do|then|else|\{)([[:space:]]|$) ]]; do
      seg="${seg#"${BASH_REMATCH[1]}"}"
      seg="${seg#"${seg%%[![:space:]]*}"}"
    done
    [[ "$seg" =~ $_producer_head ]] || continue
    [[ "$seg" =~ $_echo_file_out ]] || continue
    [[ "$seg" =~ $_echo_devnull ]] && continue
    return 0
  done <<<"$normalized"
  return 1
}

block_bypass() {
  local form="$1" reason="$2"
  echo "BLOCKED: $reason" >&2
  echo "Use the Write or Edit tool instead of Bash file-write workarounds." >&2
  emit_tel "blocked" "$form"
  exit 2
}

# cat > file (allow cat without redirect). EXEC_LC (lowercased stripped form) for
# case-insensitive command-token detection.
if [[ "$EXEC_LC" =~ $_cat_redir ]]; then
  block_bypass "cat-redirect" "cat > file write bypasses Write/Edit hooks"
fi

# echo/printf ... > file — only when the echo/printf IS the producer redirected
# into a real file (stdout-to-real-file only; not stderr/fd redirects, /dev/null,
# a co-located but unrelated echo, or tokens inside a quoted argument).
if producer_redirect_bypass "$EXEC_LC"; then
  block_bypass "echo-redirect" "echo/printf > file write bypasses Write/Edit hooks"
fi

# python3 -c with file-write indicators. Detect the `python3 -c` INVOCATION in
# the literal-stripped form (EXEC_LC) so prose/commit text merely mentioning it
# is not a false positive; scan the RAW command (COMMAND_LC) for the write
# indicators — they legitimately live inside the quoted `-c` payload the strip removes.
if [[ "$EXEC_LC" =~ (^|[[:space:];|&()]+)python3[[:space:]]+-c ]] &&
  [[ "$COMMAND_LC" =~ $_py_write ]]; then
  block_bypass "python-write" "python3 -c file write bypasses Write/Edit hooks"
fi

emit_tel "ok" ""
exit 0
