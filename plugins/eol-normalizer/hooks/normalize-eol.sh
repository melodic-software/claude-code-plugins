#!/usr/bin/env bash
# Symmetric working-tree EOL normalization driven by .gitattributes `eol=`.
# Sourced (never executed) by the plugin's PostToolBatch hook (eol-normalizer.sh).
#
# Resolution is `git check-attr eol`, the single authoritative source that
# honors the consuming repo's .gitattributes precedence (a narrow `eol=lf`
# rule wins over a broader `*.txt eol=crlf`). NO fast-path extension list:
# a hardcoded list re-introduces the very bug this lib removes.
#
# Dispatch (both arms run on every OS: the hook compensates for tool writes
# that bypass git's checkout smudge, and such writes happen on any platform):
#   lf          -> CRLF->LF, idempotent.
#   crlf        -> LF->CRLF, idempotent.
#   unspecified -> no-op.
#
# Binary guard: `eol` alone is not proof of text. Under `* text=auto eol=lf`,
# check-attr reports `eol: lf` for binaries too, while git's own conversion
# stays guarded by content detection. The guard mirrors gitattributes
# semantics: explicit `text` is trusted, `-text` skips, `text=auto` content-
# sniffs; `eol` with `text` unspecified sets text implicitly (per the
# gitattributes doc), so it converts like explicit `text`.
#
# PLAN / APPLY SPLIT. The decision (which arm, and whether the file actually
# needs touching) is separated from the rewrite so the caller can skip the
# rewrite AND everything that guards it. The action a plan reports is the arm
# that APPLIES to the file, not a report of what was written: an already-LF
# file under `eol=lf` plans `lf` with nothing to do, so normalize_eol_file
# reports the same action whether or not it rewrote any bytes.
#
# COST. On the Windows Git Bash host this plugin is tuned for, an exec costs
# about a process spawn and a bash command substitution costs half of one, and
# this library runs on every Write and Edit of every file in the repository. The
# probes below are written as shell builtins for that reason, with a subprocess
# pipeline as the fallback wherever a builtin needs a bash feature that may be
# absent.

# True when this bash can read a fixed character count (`read -N`, bash 4.1+).
# The builtin probes below need it; without it they defer to their subprocess
# fallbacks rather than guessing.
normalize_eol_read_supports_nchars() {
  ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 1)))
}

# Run <command> with LC_ALL=C, put the caller's LC_ALL back (set or unset), and
# return <command>'s status. The builtin probes need it because `read` counts
# CHARACTERS, and only in the C locale is one character one byte. An explicit
# save and restore, so sourcing this library never changes the caller's locale.
normalize_eol_c_locale() {
  local had_lc=${LC_ALL+x} old_lc=${LC_ALL-} rc=0
  LC_ALL=C
  "$@" || rc=$?
  if [[ -n "$had_lc" ]]; then LC_ALL=$old_lc; else unset LC_ALL; fi
  return "$rc"
}

# Read up to 8000 bytes of <file> into the caller's `chunk`, stopping at a NUL.
normalize_eol_read_window() {
  IFS= read -r -d '' -n 8000 chunk <"$1"
}

# Returns 0 when <file> looks binary: any NUL byte in the first 8000 bytes,
# the same window git's buffer_is_binary() uses for text=auto detection.
#
# The builtin path reads that window with NUL as the read delimiter, which makes
# the three states distinguishable without a subprocess:
#   read succeeded and stopped short of the window  -> it stopped ON a NUL
#   read succeeded having filled the window         -> no NUL in the window
#   read failed (EOF inside the window)             -> no NUL in the file
# The count flag must be `-n`, never `-N`: `-N` is documented to ignore the
# delimiter, which would collapse the first two states into one and report every
# binary file as text.
normalize_eol_is_binary() {
  local file="$1" nul_count chunk=""
  if normalize_eol_read_supports_nchars; then
    normalize_eol_c_locale normalize_eol_read_window "$file" && ((${#chunk} < 8000))
    return
  fi
  nul_count=$(head -c 8000 <"$file" | LC_ALL=C tr -dc '\0' | wc -c) || return 1
  [[ "$nul_count" -gt 0 ]]
}

# True when <file> contains a CR anywhere, which is the only way the LF arm can
# have work to do (its rewrite maps CRLF to LF and leaves every other byte
# alone). Pure builtin: the file is walked in 64 KiB chunks with `read -N`,
# which, unlike `-n`, ignores delimiters and hands back the raw bytes, newlines
# included.
#
# Two properties make chunking safe here. The probe looks for a SINGLE byte, so
# no match can straddle a chunk boundary. And it is deliberately BROADER than
# the rewrite: a lone CR that the CRLF-to-LF substitution would not touch still
# answers true, which costs one needless rewrite of a file that has one, and
# never misses a file that needs one.
#
# NUL bytes cannot be held in a bash variable and are dropped from the chunk.
# They are still consumed from the stream, so they cannot hide a CR, and the
# binary guard has already excluded the files where NULs are expected.
#
# Without `read -N` the probe cannot run, and it answers true so the caller
# takes the unconditional rewrite.
normalize_eol_has_cr() {
  normalize_eol_read_supports_nchars || return 0
  normalize_eol_c_locale normalize_eol_scan_cr "$1"
}

# The chunk walk normalize_eol_has_cr runs under the C locale.
normalize_eol_scan_cr() {
  local chunk=""
  while IFS= read -r -N 65536 chunk || [[ -n "$chunk" ]]; do
    [[ "$chunk" == *$'\r'* ]] && return 0
    [[ -n "$chunk" ]] || break
  done <"$1"
  return 1
}

# Resolve <file>'s `eol` and `text` attributes under <root> in ONE check-attr
# call. Sets NORMALIZE_EOL_ATTR_EOL and NORMALIZE_EOL_ATTR_TEXT; both are empty
# when git cannot answer.
#
# `git check-attr eol text -- <path>` prints one `<path>: <attr>: <value>` line
# per attribute. The path itself may contain colons (a Windows drive letter),
# spaces, or the literal text of an attribute name, so each line is read from
# the RIGHT: the value is the last whitespace token and the attribute name is
# the one before it. That is stable whatever the path looks like, and does not
# depend on git emitting the attributes in the order they were requested.
normalize_eol_resolve_attrs() {
  NORMALIZE_EOL_ATTR_EOL=""
  NORMALIZE_EOL_ATTR_TEXT=""
  local raw line attr
  raw=$(git -C "$1" check-attr eol text -- "$2" 2>/dev/null) || return 0
  while IFS= read -r line; do
    attr="${line% *}"
    case "${attr##* }" in
    eol:) NORMALIZE_EOL_ATTR_EOL="${line##* }" ;;
    text:) NORMALIZE_EOL_ATTR_TEXT="${line##* }" ;;
    *) ;;
    esac
  done <<<"${raw//$'\r'/}"
  return 0
}

# Decide what should happen to <file> under <root> WITHOUT touching it.
# Echoes `<action> <needed>`: action is lf | crlf | skip, and needed is 1 when
# the rewrite would actually have work to do, 0 when the file is already in the
# target shape. ALWAYS returns 0.
#
# A `skip` action always carries 0. An `lf` action carries 0 for a file with no
# CR in it, which is the overwhelmingly common case on a repository whose
# .gitattributes says `eol=lf` and whose files are already LF. The `crlf` arm
# always carries 1: proving a file needs no LF-to-CRLF pass means finding a
# newline NOT preceded by a CR, which a chunked builtin probe cannot answer
# without straddling logic, so that arm keeps its unconditional rewrite.
normalize_eol_plan() {
  local file="$2" action=skip needed=1
  if [[ -f "$file" ]]; then
    normalize_eol_resolve_attrs "$1" "$file"
    case "$NORMALIZE_EOL_ATTR_EOL" in
    lf | crlf)
      # Binary guard (see header). An unspecified `text` falls to the last arm:
      # eol on a path with no text attr implicitly sets text, so git converts.
      case "$NORMALIZE_EOL_ATTR_TEXT" in
      unset) ;;
      auto) normalize_eol_is_binary "$file" || action="$NORMALIZE_EOL_ATTR_EOL" ;;
      *) action="$NORMALIZE_EOL_ATTR_EOL" ;;
      esac
      ;;
    *) ;;
    esac
  fi
  case "$action" in
  lf) normalize_eol_has_cr "$file" || needed=0 ;;
  skip) needed=0 ;;
  *) ;;
  esac
  printf '%s %s' "$action" "$needed"
  return 0
}

# Perform the rewrite a plan called for: <action> is lf or crlf, <file> is the
# target. Anything else is a no-op. ALWAYS returns 0.
normalize_eol_apply() {
  case "$1" in
  lf) normalize_eol_to_lf "$2" ;;
  crlf) normalize_eol_to_crlf "$2" ;;
  *) ;;
  esac
  return 0
}

# Normalize <file>'s working-tree EOL to its .gitattributes `eol=` value.
# <root> anchors `git -C <root> check-attr` so resolution is CWD-independent
# (hook process CWD is not guaranteed to be the repo root).
# Echoes the action performed (lf | crlf | skip); ALWAYS returns 0: best-effort,
# and safe under `set -e`.
#
# Plan and apply in one call, for a caller that does not need to know whether a
# rewrite was needed before it happens. The hook uses the two halves directly so
# it can skip its gitignore check on a file with nothing to rewrite.
normalize_eol_file() {
  local plan
  plan=$(normalize_eol_plan "$1" "$2")
  [[ "${plan##* }" == 1 ]] && normalize_eol_apply "${plan%% *}" "$2"
  printf '%s' "${plan%% *}"
  return 0
}

# Replace <file> with the output of <command> run on it, staged in a same-dir
# mktemp file (unpredictable name, CWE-377) and then moved over it. `cp -p`
# first so the staged file carries the original's mode (chmod --reference is
# GNU-only); the redirect then replaces its content.
normalize_eol_rewrite_with() {
  local file="$1" tmp
  shift
  tmp=$(mktemp "${file}.XXXXXX") || return 0
  cp -p -- "$file" "$tmp" 2>/dev/null || true
  if "$@" <"$file" >"$tmp"; then
    mv -- "$tmp" "$file"
  else
    rm -f -- "$tmp"
  fi
}

# CRLF -> LF (unconditional, idempotent on already-LF input).
normalize_eol_to_lf() {
  if command -v perl >/dev/null 2>&1; then
    perl -pi -e 's/\r\n/\n/g' -- "$1"
  else
    # Portable fallback: strip all CR (text files carry no lone CR).
    normalize_eol_rewrite_with "$1" tr -d '\r'
  fi
}

# LF -> CRLF (idempotent; bare LF only, never turns CRLF into CRCRLF).
normalize_eol_to_crlf() {
  if command -v perl >/dev/null 2>&1; then
    perl -pi -e 's/(?<!\r)\n/\r\n/g' -- "$1"
  else
    normalize_eol_rewrite_with "$1" awk 'BEGIN{RS="\r?\n"; ORS="\r\n"} {print}'
  fi
}
