#!/usr/bin/env bash
# Symmetric working-tree EOL normalization driven by .gitattributes `eol=`.
# Sourced (never executed) by the plugin's PostToolUse hook (eol-normalizer.sh).
#
# Resolution is `git check-attr eol` — the single authoritative source that
# honors the consuming repo's .gitattributes precedence (a narrow `eol=lf`
# rule wins over a broader `*.txt eol=crlf`). NO fast-path extension list:
# a hardcoded list re-introduces the very bug this lib removes.
#
# Dispatch (both arms run on every OS — the hook compensates for tool writes
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

# Returns 0 when <file> looks binary: any NUL byte in the first 8000 bytes —
# the same window git's buffer_is_binary() uses for text=auto detection.
normalize_eol_is_binary() {
  local file="$1" nul_count
  nul_count=$(head -c 8000 <"$file" | LC_ALL=C tr -dc '\0' | wc -c) || return 1
  [[ "$nul_count" -gt 0 ]]
}

# Normalize <file>'s working-tree EOL to its .gitattributes `eol=` value.
# <root> anchors `git -C <root> check-attr` so resolution is CWD-independent
# (hook process CWD is not guaranteed to be the repo root — hooks/quirks.md).
# Echoes the action performed (lf | crlf | skip); ALWAYS returns 0 — best-effort,
# and safe under `set -e` in the pre-commit consumer's staged-file loop.
normalize_eol_file() {
  local root="$1" file="$2"
  [[ -f "$file" ]] || {
    printf 'skip'
    return 0
  }

  local eol
  eol=$(git -C "$root" check-attr eol -- "$file" 2>/dev/null | tr -d '\r')
  # Output is `<path>: eol: <value>`; the path may contain ':' (Windows drive)
  # or spaces, so take the last whitespace token, never a ':' split.
  eol="${eol##* }"

  case "$eol" in
    lf | crlf) ;;
    *)
      printf 'skip'
      return 0
      ;;
  esac

  # Binary guard (see header). `unspecified` falls to the `set` arm: eol on a
  # path with no text attr implicitly sets text, so git itself would convert.
  local text
  text=$(git -C "$root" check-attr text -- "$file" 2>/dev/null | tr -d '\r')
  text="${text##* }"
  case "$text" in
    unset)
      printf 'skip'
      return 0
      ;;
    auto)
      if normalize_eol_is_binary "$file"; then
        printf 'skip'
        return 0
      fi
      ;;
    *) ;;
  esac

  case "$eol" in
    lf)
      normalize_eol_to_lf "$file"
      printf 'lf'
      ;;
    crlf)
      normalize_eol_to_crlf "$file"
      printf 'crlf'
      ;;
    *)
      # Unreachable — eol was vetted lf|crlf above.
      printf 'skip'
      ;;
  esac
  return 0
}

# CRLF -> LF (unconditional, idempotent on already-LF input).
normalize_eol_to_lf() {
  local file="$1"
  if command -v perl >/dev/null 2>&1; then
    perl -pi -e 's/\r\n/\n/g' -- "$file"
  else
    # Portable fallback: strip all CR (text files carry no lone CR). Stage into a
    # same-dir mktemp file (unpredictable name — CWE-377) then atomically mv.
    # `cp -p` first so the staged file carries the original's mode (chmod
    # --reference is GNU-only); the redirect then replaces its content.
    local tmp
    tmp=$(mktemp "${file}.XXXXXX") || return 0
    cp -p -- "$file" "$tmp" 2>/dev/null || true
    if tr -d '\r' <"$file" >"$tmp"; then
      mv -- "$tmp" "$file"
    else
      rm -f -- "$tmp"
    fi
  fi
}

# LF -> CRLF (idempotent; bare LF only, never turns CRLF into CRCRLF).
normalize_eol_to_crlf() {
  local file="$1"
  if command -v perl >/dev/null 2>&1; then
    perl -pi -e 's/(?<!\r)\n/\r\n/g' -- "$file"
  else
    # Stage into a same-dir mktemp file (unpredictable name — CWE-377) then mv.
    # `cp -p` first so the staged file carries the original's mode (chmod
    # --reference is GNU-only); the redirect then replaces its content.
    local tmp
    tmp=$(mktemp "${file}.XXXXXX") || return 0
    cp -p -- "$file" "$tmp" 2>/dev/null || true
    if awk 'BEGIN{RS="\r?\n"; ORS="\r\n"} {print}' "$file" >"$tmp"; then
      mv -- "$tmp" "$file"
    else
      rm -f -- "$tmp"
    fi
  fi
}
