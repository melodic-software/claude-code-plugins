# shellcheck shell=bash
# Shared hardcoded-path detection patterns for the hardcoded-path-check hook.
#
# This is a library — NOT executable. Pure-function: no env reads, no stdin
# parsing, no exit calls. Callers handle I/O, exemptions, and exit-code
# mapping.
#
# Cross-platform: detects Windows (C:\Users\, drive letters), macOS
# (/Users/), and Linux (/home/) hardcoded paths plus machine-specific repo
# checkout roots. Uses POSIX ERE only (grep -E) — NO grep -P. macOS BSD grep
# lacks -P entirely. Lookbehinds/lookaheads are replaced by grep -v
# pipe-stage exclusions.

# The per-OS regex BODIES live in machine-path-patterns.sh — the org-shared,
# standards-managed materialization — so a pattern change lands upstream once
# and reaches every scan driver in lockstep. This lib keeps only its own
# wrapping (the macOS/Linux pipe exclusions and OS-context suppression below).
# shellcheck source=machine-path-patterns.sh
source "${BASH_SOURCE[0]%/*}/machine-path-patterns.sh"

# hpp::scan_text <content> [project-root] [file-path]
#
# Scans <content> for hardcoded machine-specific paths. When [project-root]
# is non-empty, also matches the absolute repo path in slash, backslash, and
# double-escaped backslash forms.
#
# When [file-path] is non-empty, OS-specific detection blocks are suppressed
# for files unambiguously scoped to that OS:
#   Windows context — file ext .ps1/.psm1/.psd1/.cmd/.bat/.reg, OR path
#     matches */scripts/windows/* or */tests/windows/*, OR filename matches
#     *-windows.* or *-win32.*  → suppresses Win-user, Win-repo, escaped-
#     Win-repo blocks
#   macOS context — */scripts/macos/*, *-macos.*, *-osx.*, *-darwin.*
#     → suppresses macOS-user block
#   Linux context — */scripts/linux/*, *-linux.*
#     → suppresses Linux-user block
# Cross-OS detections (e.g. /Users/alice/ inside a .ps1) and project-root
# match (machine-specific repo path) are NEVER suppressed — these are leaks
# regardless of file context.
#
# Output (stdout): violation block(s). Each block:
#   <label>:
#   <up to 3 matched "lineno:line" entries>
#   <blank line>
#
# Exit: 0 = clean, 1 = violations found.
#
# Callers: capture stdout, then map the return code to whatever exit code
# their layer expects (a PreToolUse hook blocks via exit 2; a commit hook
# fails the commit via exit 1).
hpp::scan_text() {
  local content="$1" project_root="${2:-}" file_path="${3:-}"
  local violations="" match
  local nl=$'\n'

  # ---- Cheap pre-filter gate (perf; behavior-preserving) ----
  # On clean content (~99% of calls in a large scan) this skips the ~8-10
  # detailed `grep` pipelines below. The alternation is a strict SUPERSET
  # of every detailed pattern's invariant literal:
  #   Users   ⊇ Windows-user + macOS-user  (both forms contain "Users")
  #   /home/  ⊇ Linux-user
  #   checkout-root literals ⊇ Windows-repo + escaped-Windows-repo — the gate
  #     lists every root token HPP_WIN_REPO_BODY / HPP_ESCAPED_WIN_REPO_BODY
  #     accept (both spellings), so a widened body must widen this list too.
  # The project-root branch keys on the root's final path segment, which is
  # present identically in the slash, backslash, and escaped forms. When NONE of
  # these triggers fire, no detailed pattern below can match, so early-returning
  # 0 cannot drop a true positive. A false NEGATIVE here = guard bypass, so the
  # gate must never be TIGHTER than the detailed patterns (a looser gate only
  # costs a wasted full scan). The gate stays case-sensitive for the OS-path
  # alternation (matching the detailed patterns' literal "Users") and
  # case-insensitive for the root segment (matching the detailed `grep -Fi`).
  # Uses a here-string, NOT `printf | grep -q`: a pipe + `grep -q` early-exit
  # would SIGPIPE printf, and under `pipefail` the pipeline would report printf's
  # failure and invert the result.
  if ! grep -qE 'Users|/home/|repos|Repos|projects|Projects|dev|Dev' <<<"$content" 2>/dev/null; then
    local gate_root=""
    if [[ -n "$project_root" ]]; then
      gate_root="${project_root//\\//}"
      gate_root="${gate_root%/}"
      gate_root="${gate_root##*/}"
    fi
    if [[ -z "$gate_root" ]] || ! grep -qFi "$gate_root" <<<"$content" 2>/dev/null; then
      return 0
    fi
  fi
  # ---- end gate (clean content has returned; fall through to full scan) ----

  # Normalize file_path for OS-context matching: backslash→slash, lowercase.
  # Use tr for the lowercasing pass — bash-3.2-compatible (macOS stock bash
  # before brew install). This lib may be sourced by commit-time hooks running
  # under whatever bash a fresh macOS clone has on PATH; staying portable here
  # avoids commit-time failures.
  local norm_file="${file_path//\\//}"
  norm_file=$(printf '%s' "$norm_file" | tr '[:upper:]' '[:lower:]')

  # OS-context flags — non-empty when file is unambiguously OS-scoped
  local windows_context="" macos_context="" linux_context=""
  case "$norm_file" in
  *.ps1 | *.psm1 | *.psd1 | *.cmd | *.bat | *.reg) windows_context=1 ;;
  */scripts/windows/* | */tests/windows/*) windows_context=1 ;;
  *-windows.* | *-win32.*) windows_context=1 ;;
  *) ;;
  esac
  case "$norm_file" in
  */scripts/macos/* | *-macos.* | *-osx.* | *-darwin.*) macos_context=1 ;;
  *) ;;
  esac
  case "$norm_file" in
  */scripts/linux/* | *-linux.*) linux_context=1 ;;
  *) ;;
  esac

  # Windows user home paths: C:\Users\<name>\ or C:/Users/<name>/
  # Suppressed in Windows context (.ps1 etc). Cross-OS leaks (macOS/Linux
  # user paths in a .ps1) still fire from their own blocks below.
  if [[ -z "$windows_context" ]]; then
    match=$(printf '%s' "$content" | grep -nE "$HPP_WIN_USER_BODY" 2>/dev/null | head -3)
    [[ -n "$match" ]] && violations="${violations}Windows user path detected:${nl}${match}${nl}${nl}"
  fi

  # Left boundary for the slash-rooted macOS/Linux bodies — the driver-owned
  # prefix the pattern lib's contract calls for, so a URL or relative-path
  # suffix (https://example.test + the home root) is not treated as a
  # filesystem root. Line start, whitespace, quote, backtick, paren, "=", ":"
  # (yaml/docker value position), or a file:// scheme. Mirrors the
  # ci-workflows/medley verification drivers' boundary, plus ":".
  local _posix_boundary
  _posix_boundary="(^|[[:space:]\"'\`(=:]|file://)"

  # macOS user home paths (the Users root with a child segment).
  # Exclusions (replace Perl lookbehind/lookahead):
  #   grep -vE '[A-Za-z]:[/\\]' — Windows paths (caught above)
  #   Shared exclusion — the Users/Shared directory is legitimately shareable.
  #     NOT a line-level grep -v: one line can hold a Shared path AND a
  #     user-specific one, and dropping the whole line would silently pass the
  #     real violation. Each candidate line is re-tested with its Shared tokens
  #     defanged; only lines whose SOLE matches are Shared drop out. The defang
  #     boundary is any character that cannot CONTINUE a real directory name
  #     (word chars, dot, hyphen) — not an enumerated delimiter list, so shell
  #     and prose punctuation right after the value (";", a closing quote, a
  #     paren) counts as a boundary while a longer segment like SharedStuff
  #     stays untouched and flagged. Basic-regex sed expressions (no in-group
  #     anchors) keep macOS stock sed compatibility; the ORIGINAL line is
  #     reported, never the defanged copy.
  #     The Shared literal is assembled from pieces so this driver's own source
  #     never carries a contiguous Users-root token for the write-scan hook
  #     that consumes these bodies to flag.
  if [[ -z "$macos_context" ]]; then
    local _shared _shared_defused
    _shared='/Use''rs/Shared'
    _shared_defused='/Use''rs-Shared'
    match=$(printf '%s' "$content" | grep -nE "${_posix_boundary}${HPP_MACOS_USER_BODY}" 2>/dev/null | grep -vE '[A-Za-z]:[/\\]' |
      while IFS= read -r _line; do
        _defanged=$(printf '%s' "$_line" | sed -e "s|${_shared}\([^A-Za-z0-9._-]\)|${_shared_defused}\1|g" \
          -e "s|${_shared}\$|${_shared_defused}|")
        printf '%s' "$_defanged" | grep -qE "${_posix_boundary}${HPP_MACOS_USER_BODY}" && printf '%s\n' "$_line"
      done | head -3)
    [[ -n "$match" ]] && violations="${violations}macOS user path detected:${nl}${match}${nl}${nl}"
  fi

  # Linux user home paths (same driver-owned left boundary).
  if [[ -z "$linux_context" ]]; then
    match=$(printf '%s' "$content" | grep -nE "${_posix_boundary}${HPP_LINUX_USER_BODY}" 2>/dev/null | head -3)
    [[ -n "$match" ]] && violations="${violations}Linux user path detected:${nl}${match}${nl}${nl}"
  fi

  # Generic Windows repo checkout roots — suppressed in Windows context.
  if [[ -z "$windows_context" ]]; then
    match=$(printf '%s' "$content" | grep -nE "$HPP_WIN_REPO_BODY" 2>/dev/null | head -3)
    [[ -n "$match" ]] && violations="${violations}Windows repo path detected:${nl}${match}${nl}${nl}"

    match=$(printf '%s' "$content" | grep -nE "$HPP_ESCAPED_WIN_REPO_BODY" 2>/dev/null | head -3)
    [[ -n "$match" ]] && violations="${violations}Escaped Windows repo path detected:${nl}${match}${nl}${nl}"
  fi

  # Current repo absolute path in slash/backslash/escaped forms. ALWAYS
  # runs — machine-specific marker for THIS checkout, never suppressible by
  # OS context.
  if [[ -n "$project_root" ]]; then
    local root_fwd root_bslash root_escaped candidate
    root_fwd=${project_root//\\//}
    root_fwd=${root_fwd%/}
    # Bash expansion — `tr '/' '\\'` mishandles backslashes on Git Bash.
    root_bslash=${root_fwd//\//\\}
    root_escaped=${root_bslash//\\/\\\\}

    for candidate in "$root_fwd" "$root_bslash" "$root_escaped"; do
      [[ -n "$candidate" ]] || continue
      match=$(printf '%s' "$content" | grep -nFi "$candidate" 2>/dev/null | head -3)
      [[ -n "$match" ]] && violations="${violations}Machine-specific repo path detected:${nl}${match}${nl}${nl}"
    done
  fi

  if [[ -n "$violations" ]]; then
    printf '%s' "$violations"
    return 1
  fi
  return 0
}
