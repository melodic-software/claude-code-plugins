#!/usr/bin/env bash
# Symmetric working-tree EOL normalization driven by .gitattributes `eol=`.
# Sourced (never executed) by the plugin's PostToolUse hook (eol-normalizer.sh).
#
# Resolution is `git check-attr eol` — the single authoritative source that
# honors the consuming repo's .gitattributes precedence (a narrow `eol=lf`
# rule wins over a broader `*.txt eol=crlf`). NO fast-path extension list:
# a hardcoded list re-introduces the very bug this lib removes.
#
# Dispatch:
#   lf          -> CRLF->LF, unconditional + idempotent. LF is correct on every
#                  platform; a CRLF-contaminated .sh / requirements.txt breaks
#                  shebangs / pip parsing everywhere, so this arm is NOT gated.
#   crlf        -> LF->CRLF, Windows-only. git smudge already yields CRLF on a
#                  Linux/macOS checkout for eol=crlf paths; the only way such a
#                  file lands as LF on disk is a Windows Write that bypasses
#                  smudge, so the arm gates on normalize_eol_platform_crlf.
#   unspecified -> no-op.

# Returns 0 when this platform should enforce CRLF on disk (Windows Git Bash).
normalize_eol_platform_crlf() {
  case "$(uname -s)" in
    MINGW* | MSYS*) return 0 ;;
    *) return 1 ;;
  esac
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
    lf)
      normalize_eol_to_lf "$file"
      printf 'lf'
      ;;
    crlf)
      if normalize_eol_platform_crlf; then
        normalize_eol_to_crlf "$file"
        printf 'crlf'
      else
        printf 'skip'
      fi
      ;;
    *)
      printf 'skip'
      ;;
  esac
  return 0
}

# CRLF -> LF (unconditional, idempotent on already-LF input).
normalize_eol_to_lf() {
  local file="$1"
  if command -v perl >/dev/null 2>&1; then
    perl -pi -e 's/\r\n/\n/g' "$file"
  else
    # Portable fallback: strip all CR (text files carry no lone CR).
    if tr -d '\r' <"$file" >"${file}.lf.tmp"; then
      mv "${file}.lf.tmp" "$file"
    else
      rm -f "${file}.lf.tmp"
    fi
  fi
}

# LF -> CRLF (idempotent; bare LF only, never turns CRLF into CRCRLF).
normalize_eol_to_crlf() {
  local file="$1"
  if command -v perl >/dev/null 2>&1; then
    perl -pi -e 's/(?<!\r)\n/\r\n/g' "$file"
  else
    if awk 'BEGIN{RS="\r?\n"; ORS="\r\n"} {print}' "$file" >"${file}.crlf.tmp"; then
      mv "${file}.crlf.tmp" "$file"
    else
      rm -f "${file}.crlf.tmp"
    fi
  fi
}
