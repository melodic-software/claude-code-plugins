#!/usr/bin/env bash
# compose-statusline-wiring: compose guard shim wrappers into an existing
# Claude Code `statusLine` value.
#
# The pure function of the effective `statusLine` string whose contract
# ../skills/setup/reference/unwrap-before-compose.md states: peel every wrapper
# a previous run of a guard setup skill added, decide whether the recovered
# renderer needs an `sh -c` adapter, and print the composed value with each
# requested shim named exactly once.
#
# USAGE
#   compose-statusline-wiring.sh --wrap <prefix> [--wrap <prefix> ...] \
#       [--command <string> | --input <file> | -] \
#       [--block | --command-only] [--explain]
#
# ARGUMENTS
#   --wrap <prefix>     A shim prefix the composed wiring carries, OUTERMOST
#                       FIRST, repeatable. Each value must scan to exactly two
#                       words, `bash` plus a path ending in
#                       `/statusline-shim.sh`. Anything else is a usage error:
#                       a prefix the peel cannot recognize would stack a fresh
#                       layer on every re-run. Every shim the wiring should
#                       carry has to be listed, because the peel strips every
#                       shim and legacy-tee prefix it finds and an unlisted
#                       sibling shim is therefore dropped, not preserved.
#   --command <string>  The current `statusLine` command as a raw string. Skips
#                       JSON entirely, and with --command-only needs no jq.
#   --input <file>      Read the current `statusLine` VALUE as JSON from <file>.
#   -                   Read that same JSON from stdin. This is the default
#                       when neither --command nor --input is given.
#   --block             Print the composed value wrapped in a paste-ready
#                       `{ "statusLine": ... }` settings.json fragment.
#   --command-only      Print the bare composed command string, no JSON.
#   --explain           Write four `key: value` lines to stderr; stdout is
#                       unchanged. The keys are `renderer`, `layers-peeled`,
#                       `wrap`, and `idempotent`. `wrap` is `standalone`,
#                       `plain`, or `shell`, followed by its reason in
#                       parentheses: `no statusline configured`,
#                       `command word resolves as an executable`,
#                       `unquoted top-level shell syntax`, or
#                       `command word is a <builtin|function|alias>, not an
#                       executable`.
#   -h, --help          Print this usage summary and exit 0.
#
# INPUT SHAPES
#   A JSON object contributes its `.command`, and every other key it carries is
#   preserved in the output. A JSON string is the command itself. `null`, empty
#   input, and an object with no `.command` all mean no statusline is
#   configured, which composes the standalone wiring: the shims and nothing
#   else.
#
# OUTPUT
#   Default: the composed `statusLine` value as JSON, two-space indented, on
#   stdout. jq is required for every mode except `--command` with
#   `--command-only`.
#
# EXIT CODES
#   0  composed; the value is on stdout
#   1  a round-trip check failed. One line naming the check is on stderr and
#      stdout stays empty
#   2  usage error: unknown argument, missing --wrap, or a --wrap prefix the
#      peel would not recognize
#   3  the input could not be read, parsed as JSON, or scanned, which includes
#      unbalanced quoting in the current command
#   4  jq is required for the selected input or output mode and is not on PATH
#
# ROUND-TRIP CHECKS, both run before anything reaches stdout
#   1. Escape and unescape. The renderer is escaped for single-quote embedding
#      by replacing every `'` with `'\''`, and re-reading `'<escaped>'` as a
#      quoted shell word has to yield the renderer byte for byte. This is the
#      check the reference used to have the model run as
#      `printf '%s\n' '<escaped>'`, done here as pure string work so a renderer
#      carrying `$(...)` or a backtick never reaches a shell.
#   2. Idempotency. The whole pipeline runs a second time over the composed
#      command and the second result has to be byte-identical to the first.
#      That is the invariant behind re-running a setup check on already-correct
#      wiring and printing exactly what is already there.
#
# THE TRANSFORM
#   Peel, applied repeatedly until a pass strips nothing:
#     1. A leading `bash <path>/statusline-shim.sh` or
#        `bash <path>/statusline-tee.sh` prefix, in whatever order the shims
#        appear. The legacy tee is peeled but never composed back in.
#     2. A generated `sh -c '<single-quoted string>'` adapter, recognized only
#        when the whole remaining command is exactly those three words with
#        nothing after the closing quote AND the carried string is itself that
#        same shape (A), begins with a prefix from rule 1 (B), or carries
#        unquoted top-level shell syntax (C). Absent all three the `sh -c` is
#        the operator's own and is preserved.
#   Wrap: the recovered renderer takes an `sh -c` adapter when it carries,
#   unquoted and at the top level, syntax no ARGV word can express (an inline
#   env assignment, a redirection, or a control operator), or when its command
#   word resolves as a shell builtin, function, or alias rather than an
#   executable, which is `type -P` finding nothing while `type -t` reports one
#   of those three. Bare quoting is never a trigger.
#
#   Branch C tests the SYNTAX trigger alone, not the whole wrap decision. Both
#   readings produce the same composed command, because branch C's predicate is
#   the wrap predicate over the same string, so a peel branch C adds is undone
#   by the wrap that follows it. Syntax-only is the reading that keeps
#   `sh -c 'ulimit -n'` preserved, which is what the reference requires: the
#   carried string has no syntax, so nothing in it distinguishes a generated
#   adapter from an operator's own.
#
# Requires bash 4 or newer for arrays and `${var//}`, plus jq for the JSON
# modes. No `eval`, and no operator string is ever handed to a shell.
set -uo pipefail

me="$(basename "$0")"

die() { # <exit-code> <message...>
  local code="$1"
  shift
  printf '%s: %s\n' "$me" "$*" >&2
  exit "$code"
}

usage() {
  sed -n '2,/^set -uo pipefail$/p' "$0" | sed -e 's/^# \{0,1\}//' -e '$d'
}

need_jq() {
  command -v jq >/dev/null 2>&1 ||
    die 4 "jq is required for this input or output mode and is not on PATH"
}

# --- the scanner -------------------------------------------------------------

# scan <string>
# Split a command string into shell words with quote removal, and record
# whether any control operator or redirection appears unquoted at the top
# level. Sets SCAN_WORDS (quote-removed values), SCAN_RAW (source text per
# word), SCAN_STARTS (each word's offset in <string>) and SCAN_OP (the first
# top-level operator, empty when there is none). Returns 1 on unbalanced
# quoting, which makes the input a command no shell would run.
SCAN_WORDS=()
SCAN_RAW=()
SCAN_STARTS=()
SCAN_OP=""
scan() {
  local s="$1"
  local n=${#s}
  local i=0 c nxt
  local word="" raw="" start=0 have=0 closed=0
  SCAN_WORDS=()
  SCAN_RAW=()
  SCAN_STARTS=()
  SCAN_OP=""
  while [[ $i -lt $n ]]; do
    c="${s:i:1}"
    case "$c" in
    ' ' | $'\t')
      if [[ $have -eq 1 ]]; then
        SCAN_WORDS+=("$word")
        SCAN_RAW+=("$raw")
        SCAN_STARTS+=("$start")
        word=""
        raw=""
        have=0
      fi
      i=$((i + 1))
      ;;
    '|' | '&' | ';' | '<' | '>' | '(' | ')' | $'\n')
      # A control operator or redirection, unquoted and at the top level. The
      # first one is what the wrap guard tests; it also ends the current word.
      # `(` and `)` are POSIX grouping operators: `(printf hi)` is a valid
      # renderer and cannot be an ARGV word after the shim.
      [[ -n "$SCAN_OP" ]] || SCAN_OP="$c"
      if [[ $have -eq 1 ]]; then
        SCAN_WORDS+=("$word")
        SCAN_RAW+=("$raw")
        SCAN_STARTS+=("$start")
        word=""
        raw=""
        have=0
      fi
      i=$((i + 1))
      ;;
    \\)
      if [[ $have -eq 0 ]]; then
        start=$i
        have=1
      fi
      raw+="$c"
      i=$((i + 1))
      [[ $i -lt $n ]] || return 1
      word+="${s:i:1}"
      raw+="${s:i:1}"
      i=$((i + 1))
      ;;
    "'")
      if [[ $have -eq 0 ]]; then
        start=$i
        have=1
      fi
      raw+="$c"
      i=$((i + 1))
      closed=0
      while [[ $i -lt $n ]]; do
        c="${s:i:1}"
        raw+="$c"
        i=$((i + 1))
        if [[ "$c" == "'" ]]; then
          closed=1
          break
        fi
        word+="$c"
      done
      [[ $closed -eq 1 ]] || return 1
      ;;
    '"')
      if [[ $have -eq 0 ]]; then
        start=$i
        have=1
      fi
      raw+="$c"
      i=$((i + 1))
      closed=0
      while [[ $i -lt $n ]]; do
        c="${s:i:1}"
        raw+="$c"
        i=$((i + 1))
        if [[ "$c" == '"' ]]; then
          closed=1
          break
        fi
        if [[ "$c" == \\ && $i -lt $n ]]; then
          nxt="${s:i:1}"
          case "$nxt" in
          '$' | '`' | '"' | \\)
            word+="$nxt"
            raw+="$nxt"
            i=$((i + 1))
            ;;
          $'\n')
            # Line continuation inside double quotes: both characters vanish.
            raw+="$nxt"
            i=$((i + 1))
            ;;
          *)
            word+="$c"
            ;;
          esac
          continue
        fi
        word+="$c"
      done
      [[ $closed -eq 1 ]] || return 1
      ;;
    *)
      if [[ $have -eq 0 ]]; then
        start=$i
        have=1
      fi
      word+="$c"
      raw+="$c"
      i=$((i + 1))
      ;;
    esac
  done
  if [[ $have -eq 1 ]]; then
    SCAN_WORDS+=("$word")
    SCAN_RAW+=("$raw")
    SCAN_STARTS+=("$start")
  fi
  return 0
}

# --- peel rules --------------------------------------------------------------

# is_shim_word <word>: 0 when the word is a path the peel treats as a guard
# wrapper. The legacy tee is included because operators still carry
# version-pinned plugin-cache tee wiring from before the shim existed.
is_shim_word() {
  case "$1" in
  */statusline-shim.sh | */statusline-tee.sh) return 0 ;;
  *) return 1 ;;
  esac
}

# starts_with_shim_prefix <string>: 0 when <string> begins `bash <shim path>`.
starts_with_shim_prefix() {
  scan "$1" || return 1
  [[ ${#SCAN_WORDS[@]} -ge 2 ]] || return 1
  [[ "${SCAN_WORDS[0]}" == "bash" ]] || return 1
  is_shim_word "${SCAN_WORDS[1]}"
}

# peel_shim_prefix <string>: strip ONE leading `bash <shim path>` prefix. Sets
# PEELED to the remainder (empty when the shim was the whole command) and
# returns 0; returns 1 when there was no such prefix. The remainder is always
# strictly shorter, so a caller may loop on it.
PEELED=""
peel_shim_prefix() {
  local s="$1"
  scan "$s" || return 1
  [[ ${#SCAN_WORDS[@]} -ge 2 ]] || return 1
  [[ "${SCAN_WORDS[0]}" == "bash" ]] || return 1
  is_shim_word "${SCAN_WORDS[1]}" || return 1
  if [[ ${#SCAN_WORDS[@]} -ge 3 ]]; then
    PEELED="${s:${SCAN_STARTS[2]}}"
  else
    PEELED=""
  fi
  return 0
}

# adapter_payload <string>: 0 when <string> is exactly
# `sh -c '<single-quoted string>'` with nothing after the closing quote, and
# sets ADAPTER to the carried string. A trailing word or a top-level operator
# makes it a real command, not an adapter, and a double-quoted carrier is not
# the shape a guard setup skill ever emits.
ADAPTER=""
adapter_payload() {
  scan "$1" || return 1
  [[ -z "$SCAN_OP" ]] || return 1
  [[ ${#SCAN_WORDS[@]} -eq 3 ]] || return 1
  [[ "${SCAN_WORDS[0]}" == "sh" ]] || return 1
  [[ "${SCAN_WORDS[1]}" == "-c" ]] || return 1
  [[ "${SCAN_RAW[2]}" == "'"* ]] || return 1
  ADAPTER="${SCAN_WORDS[2]}"
  return 0
}

# has_top_level_syntax <string>: 0 when the string carries, unquoted and at the
# top level, syntax no ARGV word can express. An unscannable string needs a
# shell either way.
has_top_level_syntax() {
  scan "$1" || return 0
  [[ -z "$SCAN_OP" ]] || return 0
  [[ ${#SCAN_RAW[@]} -gt 0 ]] || return 1
  if [[ "${SCAN_RAW[0]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
    return 0
  fi
  return 1
}

# needs_shell <string>: 0 when the wrap guard fires. Sets WRAP_REASON.
WRAP_REASON=""
needs_shell() {
  local s="$1" word kind
  if has_top_level_syntax "$s"; then
    WRAP_REASON="unquoted top-level shell syntax"
    return 0
  fi
  scan "$s" || return 1
  [[ ${#SCAN_WORDS[@]} -gt 0 ]] || return 1
  word="${SCAN_WORDS[0]}"
  # A command word starting with a dash would be read as a flag by `type`, and
  # is not a shape any renderer has; treat it as an ordinary executable.
  case "$word" in
  -*) return 1 ;;
  *) ;;
  esac
  if [[ -n "$(type -P "$word" 2>/dev/null)" ]]; then
    return 1
  fi
  kind="$(type -t "$word" 2>/dev/null)"
  case "$kind" in
  builtin | function | alias | keyword)
    WRAP_REASON="command word is a $kind, not an executable"
    return 0
    ;;
  *) return 1 ;;
  esac
}

# peel <string>: sets RENDERER to the operator's own renderer and PEEL_LAYERS
# to the number of layers stripped. Both rules run repeatedly until a pass
# strips nothing, because an operator may already carry several layers from
# earlier re-runs and a single pass over three layers leaves two.
RENDERER=""
PEEL_LAYERS=0
peel() {
  local cur="$1" payload changed
  PEEL_LAYERS=0
  while :; do
    changed=0
    while peel_shim_prefix "$cur"; do
      cur="$PEELED"
      PEEL_LAYERS=$((PEEL_LAYERS + 1))
      changed=1
    done
    if adapter_payload "$cur"; then
      payload="$ADAPTER"
      if adapter_payload "$payload" ||
        starts_with_shim_prefix "$payload" ||
        has_top_level_syntax "$payload"; then
        cur="$payload"
        PEEL_LAYERS=$((PEEL_LAYERS + 1))
        changed=1
      fi
    fi
    [[ $changed -eq 1 ]] || break
  done
  RENDERER="$cur"
}

# --- escaping ----------------------------------------------------------------

ESCAPED=""
sq_escape() { # <string>: sets ESCAPED, the value safe to embed between '...'
  ESCAPED="${1//\'/\'\\\'\'}"
}

# sq_roundtrip <original> <escaped>: 0 when reading `'<escaped>'` back as one
# quoted shell word yields <original> byte for byte.
sq_roundtrip() {
  scan "'$2'" || return 1
  [[ ${#SCAN_WORDS[@]} -eq 1 ]] || return 1
  [[ "${SCAN_WORDS[0]}" == "$1" ]]
}

# --- compose -----------------------------------------------------------------

PREFIX=""
COMPOSED=""
WRAP_FORM=""
FAIL_REASON=""

# compose <command-string>: sets COMPOSED, WRAP_FORM, RENDERER, PEEL_LAYERS.
# Returns 1 on a failed escape round trip and 3 on an unscannable command, with
# FAIL_REASON set in both cases.
compose() {
  local cmd="$1"
  if ! scan "$cmd"; then
    FAIL_REASON="the current statusLine command has unbalanced quoting"
    return 3
  fi
  peel "$cmd"
  if [[ -z "$RENDERER" ]]; then
    WRAP_FORM="standalone"
    WRAP_REASON="no statusline configured"
    COMPOSED="$PREFIX"
    return 0
  fi
  if needs_shell "$RENDERER"; then
    WRAP_FORM="shell"
    sq_escape "$RENDERER"
    if ! sq_roundtrip "$RENDERER" "$ESCAPED"; then
      FAIL_REASON="single-quote escape round trip did not reproduce the recovered renderer"
      return 1
    fi
    COMPOSED="$PREFIX sh -c '$ESCAPED'"
  else
    WRAP_FORM="plain"
    WRAP_REASON="command word resolves as an executable"
    COMPOSED="$PREFIX $RENDERER"
  fi
  return 0
}

# --- arguments ---------------------------------------------------------------

wraps=()
input_mode="stdin"
input_file=""
raw_command=""
out_mode="value"
explain=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --wrap)
    [[ $# -ge 2 ]] || die 2 "--wrap needs a prefix"
    wraps+=("$2")
    shift 2
    ;;
  --command)
    [[ $# -ge 2 ]] || die 2 "--command needs a value"
    raw_command="$2"
    input_mode="command"
    shift 2
    ;;
  --input)
    [[ $# -ge 2 ]] || die 2 "--input needs a file"
    input_file="$2"
    input_mode="file"
    shift 2
    ;;
  -)
    input_mode="stdin"
    shift
    ;;
  --block)
    out_mode="block"
    shift
    ;;
  --command-only)
    out_mode="command"
    shift
    ;;
  --explain)
    explain=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    die 2 "unknown argument: $1"
    ;;
  esac
done

[[ ${#wraps[@]} -gt 0 ]] || die 2 "at least one --wrap <prefix> is required"

for wrap in "${wraps[@]}"; do
  scan "$wrap" || die 2 "--wrap prefix has unbalanced quoting: $wrap"
  if [[ ${#SCAN_WORDS[@]} -ne 2 || "${SCAN_WORDS[0]}" != "bash" ]]; then
    die 2 "--wrap prefix must be 'bash <path>/statusline-shim.sh', got: $wrap"
  fi
  case "${SCAN_WORDS[1]}" in
  */statusline-shim.sh) ;;
  *) die 2 "--wrap prefix must name a statusline-shim.sh path, got: $wrap" ;;
  esac
done
PREFIX="${wraps[*]}"

# --- input -------------------------------------------------------------------

json=""
kind=""
command_string=""

case "$input_mode" in
command)
  command_string="$raw_command"
  ;;
file | stdin)
  need_jq
  if [[ "$input_mode" == "file" ]]; then
    [[ -f "$input_file" ]] || die 3 "input file not found: $input_file"
    json="$(<"$input_file")"
  else
    json="$(cat)"
  fi
  if [[ -z "${json//[[:space:]]/}" ]]; then
    json="null"
  fi
  printf '%s' "$json" | jq . >/dev/null 2>&1 ||
    die 3 "the statusLine value is not valid JSON"
  kind="$(printf '%s' "$json" | jq -r 'type')"
  case "$kind" in
  string)
    command_string="$(printf '%s' "$json" | jq -r '.')"
    ;;
  object)
    if [[ "$(printf '%s' "$json" | jq -r 'if has("command") then (.command|type) else "string" end')" != "string" ]]; then
      die 3 "the statusLine object's .command must be a string"
    fi
    command_string="$(printf '%s' "$json" | jq -r '.command // ""')"
    ;;
  "null")
    command_string=""
    ;;
  *)
    die 3 "the statusLine value must be a JSON object, string, or null, got $kind"
    ;;
  esac
  ;;
*)
  die 2 "unreachable input mode: $input_mode"
  ;;
esac

# --- run, then re-run over the result ----------------------------------------

compose "$command_string"
status=$?
if [[ $status -ne 0 ]]; then
  die "$status" "$FAIL_REASON"
fi
first="$COMPOSED"
first_renderer="$RENDERER"
first_layers="$PEEL_LAYERS"
first_form="$WRAP_FORM"
first_reason="$WRAP_REASON"

compose "$first"
status=$?
if [[ $status -ne 0 ]]; then
  die "$status" "re-composing the composed wiring failed: $FAIL_REASON"
fi
if [[ "$COMPOSED" != "$first" ]]; then
  die 1 "idempotency round trip failed: re-composing changed the wiring"
fi

# --- output ------------------------------------------------------------------

if [[ $explain -eq 1 ]]; then
  printf 'renderer: %s\n' "$first_renderer" >&2
  printf 'layers-peeled: %s\n' "$first_layers" >&2
  printf 'wrap: %s (%s)\n' "$first_form" "$first_reason" >&2
  printf 'idempotent: yes\n' >&2
fi

case "$out_mode" in
command)
  printf '%s\n' "$first"
  ;;
value | block)
  need_jq
  base='{}'
  if [[ "$kind" == "object" ]]; then
    base="$json"
  fi
  value="$(printf '%s' "$base" |
    jq --arg c "$first" '. + {type: (.type // "command"), command: $c}')"
  if [[ "$out_mode" == "block" ]]; then
    printf '%s' "$value" | jq '{statusLine: .}'
  else
    printf '%s\n' "$value"
  fi
  ;;
*)
  die 2 "unreachable output mode: $out_mode"
  ;;
esac
