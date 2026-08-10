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
  # Feeds the payload through PROCESS SUBSTITUTION — not `<<<`, and not
  # `printf | grep -q`. Both alternatives are broken on whole-payload content:
  #   `<<<"$content"` deadlocks. Bash delivers a here-string through a pipe and
  #     appends a newline, so a content length of 65536-65663 puts the write
  #     1-128 bytes past the 65536-byte pipe capacity and bash blocks forever
  #     (at >=129 bytes over it spills to a temp file and works again). A
  #     blocking guard that never answers loses its verdict outright — the
  #     harness cancels it at the hook timeout.
  #   `printf … | grep -q` INVERTS. `grep -q` exits at the first match and
  #     SIGPIPEs printf; under `pipefail` the pipeline reports printf's 141, and
  #     `if ! …` reads a non-zero status as "no match" and early-returns clean —
  #     a fail-open on exactly the content that matched.
  # `grep -q … < <(printf …)` keeps the early exit, keeps the writer OUT of the
  # pipeline (so `pipefail` never sees its SIGPIPE), and never blocks. Same rule
  # as lib/hook-utils.sh's `printf | jq`: never feed a whole payload through
  # `<<<`; use a pipe when the reader drains its input (jq), and process
  # substitution when the reader may exit early (`grep -q`).
  # `printf '%s'` (no trailing newline) also matches the detailed blocks below,
  # so the gate and the scan see byte-identical input.
  if ! grep -qE 'Users|/home/|repos|Repos|projects|Projects|dev|Dev' < <(printf '%s' "$content") 2>/dev/null; then
    local gate_root=""
    if [[ -n "$project_root" ]]; then
      gate_root="${project_root//\\//}"
      gate_root="${gate_root%/}"
      gate_root="${gate_root##*/}"
    fi
    # Process substitution for the same two reasons as the gate above.
    if [[ -z "$gate_root" ]] || ! grep -qFi "$gate_root" < <(printf '%s' "$content") 2>/dev/null; then
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
  #
  # The defang runs ONCE over the whole candidate block, not once per candidate
  # line, so the subprocess count is constant rather than proportional to the
  # candidate count. `sed` is line-oriented in this pipeline — no `N`/`H`
  # multiline commands, and `$` is a per-line anchor in both shapes — so
  # hoisting cannot change any individual line's result. A per-line loop is
  # pathologically slow on exactly the innocent input this exclusion exists to
  # serve: the loop's only escape is the trailing `head -3`, which fires when
  # candidates SURVIVE, so an all-Shared block never short-circuits and pays a
  # `sed` plus a `grep` on every line. Measured through the hook on Git Bash
  # over the same corpora, swapping only this library: the per-line shape
  # spawned 210 `grep`/`sed` processes at 100 Shared-only lines and its wall
  # clock grew 13x for 4x the input (22s to 288s), against 12 spawns at either
  # size and a flat ~10s hoisted.
  # A guard killed at its hook timeout fails OPEN, so the bound is a correctness
  # property, not merely a speed one. `grep -E` stays the sole matcher — `awk`
  # only selects lines by index and does no regex work, so no second regex
  # dialect enters the pipeline and the shared HPP_* bodies stay the SSOT.
  if [[ -z "$macos_context" ]]; then
    local _shared _shared_defused _cands _keep
    _shared='/Use''rs/Shared'
    _shared_defused='/Use''rs-Shared'
    # `|| true`: the trailing `grep -v` exits 1 when nothing survives (the
    # common clean case). This lib is sourced by commit-time hooks whose shell
    # options it does not control, and aborting the scan under `set -e` would
    # fail OPEN — the very failure mode this block is shaped to avoid.
    _cands=$(printf '%s' "$content" | grep -nE "${_posix_boundary}${HPP_MACOS_USER_BODY}" 2>/dev/null |
      grep -vE '[A-Za-z]:[/\\]') || true
    if [[ -n "$_cands" ]]; then
      if [[ "$_cands" != *"$_shared"* ]]; then
        # No Shared token anywhere in the block, so the defang is a provable
        # no-op and every candidate survives it. This bash-builtin substring
        # test keeps the common case free; the branch below costs four more
        # processes, and on Git Bash spawn cost — not matching — dominates.
        match=$(printf '%s\n' "$_cands" | head -3)
      else
        # Block-relative indices of the candidates that still match once
        # defanged, then select those lines from the ORIGINAL block so the
        # reported line is never the defanged copy.
        #
        # The leading `s/^[0-9]*://` drops the line-number prefix the first
        # `grep -n` added, so this re-test sees the same bytes the first pass
        # matched. Without it a violation at COLUMN 0 reaches the re-test as
        # `<n>:/Users/…` and can no longer satisfy the boundary's `^`
        # alternative — it survives today only because the class happens to
        # also accept ":", which is there for yaml/docker value position and
        # carries no obligation to this pipeline. Stripping keeps the two
        # passes' conditions identical instead of coupling the second to an
        # unrelated member of the class. It costs no extra process: the strip
        # is another expression on the `sed` the defang already runs.
        _keep=$(printf '%s\n' "$_cands" |
          sed -e 's|^[0-9]*:||' -e "s|${_shared}\([^A-Za-z0-9._-]\)|${_shared_defused}\1|g" -e "s|${_shared}\$|${_shared_defused}|" |
          grep -nE "${_posix_boundary}${HPP_MACOS_USER_BODY}" 2>/dev/null | cut -d: -f1)
        match=$(printf '%s\n' "$_cands" | awk -v keep="$_keep" '
          BEGIN { n = split(keep, a, "\n"); for (i = 1; i <= n; i++) k[a[i]] = 1 }
          k[NR]' | head -3)
      fi
      [[ -n "$match" ]] && violations="${violations}macOS user path detected:${nl}${match}${nl}${nl}"
    fi
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
