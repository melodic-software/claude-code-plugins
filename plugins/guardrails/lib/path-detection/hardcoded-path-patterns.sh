# shellcheck shell=bash
# Shared hardcoded-path detection patterns for the hardcoded-path-check hook.
#
# This is a library — NOT executable. Pure-function apart from
# hpp::resolve_scan_root: no env reads, no stdin parsing, no exit calls.
# Callers handle I/O, exemptions, and exit-code mapping.
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

# hpp::prefilter <content> [project-root]
#
# The builtin half of hpp::scan_text's pre-filter gate, with no process: sets
# HPP_GATE to `clean` (no detailed pattern can match), `scan` (a literal is
# present: run the full scan) or `grep` (undecided: the gate greps decide), and
# HPP_GATE_ROOT to the project root's final segment. A caller may skip
# hpp::scan_text, and the command substitution around it, on `clean`: the scan
# would print nothing and return 0. A non-empty [project-root] only adds a way
# to reach `scan`, so `clean` with a root is `clean` without one.
hpp::prefilter() {
  # It answers "clean" only where hpp::scan_text's two gate greps would, and
  # hands everything else to them. Under LC_ALL=C:
  #   - A literal in the content means the scan runs. Byte substring presence is
  #     never tighter than grep's line match of the same literals, and a looser
  #     gate only costs a scan that finds nothing.
  #   - Otherwise the root segment is compared with ASCII case folding, but only
  #     when the content and the segment are ASCII and the segment holds no
  #     newline (grep -F reads a newline as a second pattern). Over ASCII text
  #     grep -i's locale folding can only match a subset of what ASCII folding
  #     matches, so "no match" here is "no match" there. Non-ASCII text goes to
  #     grep, whose locale folding (the Kelvin sign for k) is wider.
  # A case pattern, not a regex: Git Bash's regex decodes UTF-8 even under C.
  HPP_GATE=grep HPP_GATE_ROOT=""
  local content="$1" project_root="${2:-}" hpp_lc_set=${LC_ALL+x} hpp_lc=${LC_ALL-} hpp_nc=0
  local hpp_non_ascii=$'[!\x01-\x7f]' hpp_non_ascii_nl=$'[!\x01-\x09\x0b-\x7f]'
  if [[ -n "$project_root" ]]; then
    HPP_GATE_ROOT="${project_root//\\//}"
    HPP_GATE_ROOT="${HPP_GATE_ROOT%/}"
    HPP_GATE_ROOT="${HPP_GATE_ROOT##*/}"
  fi
  # Assigning a readonly LC_ALL would abort this function, so a readonly one
  # skips the pre-gate and the greps decide. So does bash before 4.4, which has
  # no ${var@a}; eval keeps that expansion out of such a bash's parse. The
  # expansion trips `set -u` on an unset LC_ALL, so nounset is lifted around it.
  local hpp_attr=r
  if ((BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] >= 404)); then
    case $- in
    *u*)
      set +u
      eval 'hpp_attr=${LC_ALL@a}'
      set -u
      ;;
    *) eval 'hpp_attr=${LC_ALL@a}' ;;
    esac
  fi
  if [[ $hpp_attr != *r* ]]; then
    LC_ALL=C
    case $content in
    *Users* | */home/* | *repos* | *Repos* | *projects* | *Projects* | *dev* | *Dev*) HPP_GATE=scan ;;
    *$hpp_non_ascii*) ;;
    *)
      case $HPP_GATE_ROOT in
      *$hpp_non_ascii_nl*) ;;
      "") HPP_GATE=clean ;;
      *)
        shopt -q nocasematch && hpp_nc=1
        shopt -s nocasematch
        HPP_GATE=clean
        [[ $content == *"$HPP_GATE_ROOT"* ]] && HPP_GATE=scan
        ((hpp_nc)) || shopt -u nocasematch
        ;;
      esac
      ;;
    esac
    # Restoring an LC_ALL that names a locale this host lacks makes bash warn
    # "setlocale: cannot change locale"; only the restore is silenced.
    { if [[ -n "$hpp_lc_set" ]]; then LC_ALL=$hpp_lc; else unset LC_ALL; fi; } 2>/dev/null
  fi
}

# hpp::_drop_exempt <candidates> <exempt> <defused> <regex>
#
# Prints up to 3 of <candidates> (`grep -n` lines that <regex> matched) that
# still match <regex> once every <exempt> token in them is defanged to
# <defused>; nothing when none survive. The exemption is match-level, not a
# line-level grep -v: one line can hold an exempt path AND a user-specific one,
# and dropping the whole line would silently pass the real violation. The
# defang boundary is any character that cannot CONTINUE a real directory name
# (word chars, dot, hyphen) — not an enumerated delimiter list, so shell and
# prose punctuation right after the value (";", a closing quote, a paren)
# counts as a boundary while a longer segment such as SharedStuff stays
# untouched and flagged. Basic-regex sed expressions (no in-group anchors) keep
# macOS stock sed compatibility; the ORIGINAL line is reported, never the
# defanged copy. Callers assemble <exempt> from pieces so this driver's own
# source never carries a contiguous home-root token for the write-scan hook
# that consumes these bodies to flag.
#
# The defang runs ONCE over the whole candidate block, not once per line, so
# the process count stays constant as candidates grow. `sed` is line-oriented
# here (no `N`/`H`; `$` anchors per line), so hoisting changes no line's
# result. A per-line loop escapes only through the trailing `head -3` when
# candidates SURVIVE, so an all-exempt block pays a `sed` plus a `grep` per
# line: on Git Bash it spawned 210 processes at 100 Shared-only lines and took
# 13x longer for 4x the input, against 12 spawns and a flat time hoisted. A
# guard killed at its hook timeout fails OPEN, so the bound is a correctness
# property, not merely a speed one. `grep -E` stays the sole matcher (`awk`
# only selects lines by index), so the shared HPP_* bodies stay the SSOT.
hpp::_drop_exempt() {
  local cands="$1" exempt="$2" defused="$3" regex="$4" keep
  if [[ "$cands" != *"$exempt"* ]]; then
    # No exempt token anywhere in the block, so the defang is a provable no-op
    # and every candidate survives it. This bash-builtin substring test keeps
    # the common case free; the branch below costs four more processes, and on
    # Git Bash spawn cost — not matching — dominates.
    printf '%s\n' "$cands" | head -3
    return 0
  fi
  # Block-relative indices of the candidates that still match once defanged,
  # then select those lines from the ORIGINAL block.
  #
  # The leading `s/^[0-9]*://` drops the line-number prefix the first `grep -n`
  # added, so this re-test sees the same bytes the first pass matched. Without
  # it a violation at COLUMN 0 reaches the re-test as `<n>:/Users/…` and can no
  # longer satisfy the boundary's `^` alternative — it would survive only
  # because the class happens to also accept ":", which is there for
  # yaml/docker value position and carries no obligation to this pipeline.
  # Stripping keeps the two passes' conditions identical. It costs no extra
  # process: the strip is another expression on the `sed` the defang runs.
  # Only the first 3 survivors are ever reported, so only their indices reach
  # awk: an uncapped list rides one argv string, and past the exec limit the
  # awk spawn fails and the scan reports nothing.
  keep=$(printf '%s\n' "$cands" |
    sed -e 's|^[0-9]*:||' -e "s|${exempt}\([^A-Za-z0-9._-]\)|${defused}\1|g" -e "s|${exempt}\$|${defused}|" |
    grep -nE "$regex" 2>/dev/null | cut -d: -f1 | head -3) || true
  printf '%s\n' "$cands" | awk -v keep="$keep" '
    BEGIN { n = split(keep, a, "\n"); for (i = 1; i <= n; i++) k[a[i]] = 1 }
    k[NR]' | head -3
}

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
  local violations="" match cands re nl=$'\n'

  # ---- Cheap pre-filter gate (perf; behavior-preserving) ----
  # On clean content (~99% of calls in a large scan) this skips the detailed
  # `grep` pipelines below. The alternation is a strict SUPERSET of every
  # detailed pattern's invariant literal: "Users" (Windows and macOS user),
  # "/home/" (Linux user), and every checkout-root token HPP_WIN_REPO_BODY and
  # HPP_ESCAPED_WIN_REPO_BODY accept, both spellings, so a widened body must
  # widen this list too. The project-root branch keys on the root's final
  # segment, present identically in the slash, backslash and escaped forms, and
  # matches case-insensitively like the detailed `grep -Fi`. A gate TIGHTER
  # than the detailed patterns is a guard bypass; a looser one only costs a
  # wasted scan.
  # The gate greps read the payload through PROCESS SUBSTITUTION, never:
  #   `<<<"$content"`, which deadlocks: bash delivers a here-string through a
  #     pipe plus a newline, so a content length of 65536-65663 lands 1-128
  #     bytes past the 65536-byte pipe capacity and blocks forever (129 or more
  #     over spills to a temp file and works), and the harness cancels the
  #     guard at its hook timeout with no verdict.
  #   `printf … | grep -q`, which INVERTS: `grep -q` exits at the first match
  #     and SIGPIPEs printf, `pipefail` reports printf's 141, and `if ! …` reads
  #     it as "no match", failing open on exactly the content that matched.
  # Same rule as hooks/hook-utils.sh's `printf | jq`: a pipe when the reader
  # drains its input, process substitution when it may exit early. `printf '%s'`
  # (no trailing newline) matches the detailed blocks, so gate and scan see
  # byte-identical input.
  hpp::prefilter "$content" "$project_root"
  local hpp_gate=$HPP_GATE gate_root=$HPP_GATE_ROOT
  [[ $hpp_gate == clean ]] && return 0
  # `--` on every grep whose pattern comes from the project root: a root whose
  # last segment starts with `-` (`-e`, `--help`) is a pattern, not an option.
  if [[ $hpp_gate == grep ]] && ! grep -qE -- 'Users|/home/|repos|Repos|projects|Projects|dev|Dev' < <(printf '%s' "$content") 2>/dev/null; then
    # Process substitution for the same two reasons as the gate above.
    if [[ -z "$gate_root" ]] || ! grep -qFi -- "$gate_root" < <(printf '%s' "$content") 2>/dev/null; then
      return 0
    fi
  fi
  # ---- end gate (clean content has returned; fall through to full scan) ----

  # Normalize file_path for OS-context matching: backslash→slash, lowercase.
  # tr, not ${var,,}: commit-time hooks source this lib under whatever bash a
  # fresh macOS clone has on PATH, which can be stock bash 3.2.
  local norm_file="${file_path//\\//}"
  norm_file=$(printf '%s' "$norm_file" | tr '[:upper:]' '[:lower:]')

  # OS-context flags — non-empty when file is unambiguously OS-scoped
  local windows_context="" macos_context="" linux_context=""
  case "$norm_file" in
  *.ps1 | *.psm1 | *.psd1 | *.cmd | *.bat | *.reg | */scripts/windows/* | */tests/windows/* | *-windows.* | *-win32.*)
    windows_context=1
    ;;
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
    [[ -n "$match" ]] && violations+="Windows user path detected:${nl}${match}${nl}${nl}"
  fi

  # Left boundary for the slash-rooted macOS/Linux bodies — the driver-owned
  # prefix the pattern lib's contract calls for, so a URL or relative-path
  # suffix (https://example.test + the home root) is not treated as a
  # filesystem root. Line start, whitespace, quote, backtick, paren, "=", ":"
  # (yaml/docker value position), or a file:// scheme. Mirrors the
  # ci-workflows/medley verification drivers' boundary, plus ":".
  local _posix_boundary="(^|[[:space:]\"'\`(=:]|file://)"

  # macOS user home paths (the Users root with a child segment).
  # Exclusions (replace Perl lookbehind/lookahead):
  #   grep -vE '[A-Za-z]:[/\\]' — Windows paths (caught above)
  #   Shared exclusion — the Users/Shared directory is legitimately shareable;
  #     hpp::_drop_exempt drops the lines whose sole matches are Shared.
  if [[ -z "$macos_context" ]]; then
    re="${_posix_boundary}${HPP_MACOS_USER_BODY}"
    # `|| true`: the trailing `grep -v` exits 1 when nothing survives (the
    # common clean case), and aborting the scan under a sourcing hook's
    # `set -e` would fail OPEN.
    cands=$(printf '%s' "$content" | grep -nE "$re" 2>/dev/null | grep -vE '[A-Za-z]:[/\\]') || true
    if [[ -n "$cands" ]]; then
      match=$(hpp::_drop_exempt "$cands" '/Use''rs/Shared' '/Use''rs-Shared' "$re")
      [[ -n "$match" ]] && violations+="macOS user path detected:${nl}${match}${nl}${nl}"
    fi
  fi

  # Linux user home paths (same driver-owned left boundary). The home of the
  # GitHub-hosted Linux runner is exempt the way Users/Shared is above: every
  # hosted runner has that same home, so it names no person and no machine.
  if [[ -z "$linux_context" ]]; then
    re="${_posix_boundary}${HPP_LINUX_USER_BODY}"
    cands=$(printf '%s' "$content" | grep -nE "$re" 2>/dev/null) || true
    if [[ -n "$cands" ]]; then
      match=$(hpp::_drop_exempt "$cands" '/ho''me/runner' '/ho''me-runner' "$re")
      [[ -n "$match" ]] && violations+="Linux user path detected:${nl}${match}${nl}${nl}"
    fi
  fi

  # Generic Windows repo checkout roots — suppressed in Windows context.
  if [[ -z "$windows_context" ]]; then
    match=$(printf '%s' "$content" | grep -nE "$HPP_WIN_REPO_BODY" 2>/dev/null | head -3)
    [[ -n "$match" ]] && violations+="Windows repo path detected:${nl}${match}${nl}${nl}"

    match=$(printf '%s' "$content" | grep -nE "$HPP_ESCAPED_WIN_REPO_BODY" 2>/dev/null | head -3)
    [[ -n "$match" ]] && violations+="Escaped Windows repo path detected:${nl}${match}${nl}${nl}"
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
      match=$(printf '%s' "$content" | grep -nFi -- "$candidate" 2>/dev/null | head -3)
      [[ -n "$match" ]] && violations+="Machine-specific repo path detected:${nl}${match}${nl}${nl}"
    done
  fi

  [[ -n "$violations" ]] || return 0
  printf '%s' "$violations"
  return 1
}

# hpp::resolve_scan_root <project root> [toplevel]
#
# Set SCAN_ROOT for hpp::scan_text's repo-path branch, from <project root>.
# The one helper here that reads the environment (HOME, USERPROFILE) and runs
# git; it needs hook-utils.sh's hook::normalize_path_to loaded.
#
# That branch matches the project root as a literal substring and is never
# OS-suppressed. It is a valid machine-specific marker ONLY when the root sits
# inside a genuine git checkout whose TOPLEVEL is not the user's home (nor an
# ancestor of it): a project dir can be a subdirectory of its checkout, and when
# home is itself a checkout (chezmoi-managed dotfiles) a project dir like
# $HOME/Desktop would clear a root-only home test and wrongly re-enable the
# branch, hard-denying every path under it. Empty is the lib's documented seam to
# skip the branch. Native Windows exposes home as %USERPROFILE%, not $HOME, so
# fall back to it; a missing home leaves the branch active (fail toward
# detection, never a false negative). A caller that already asked git for
# <root>'s toplevel passes the answer as $2, so git runs once, not twice.
# shellcheck disable=SC2034  # SCAN_ROOT is the caller's result
hpp::resolve_scan_root() {
  local root="$1" toplevel tl_norm="" home_norm=""
  SCAN_ROOT=""
  [[ -n "$root" ]] || return 0
  if (($# > 1)); then
    toplevel=$2
  else
    toplevel="$(exec git -C "$root" rev-parse --show-toplevel 2>/dev/null)"
  fi
  [[ -n "$toplevel" ]] || return 0
  hook::normalize_path_to tl_norm "$toplevel"
  tl_norm="${tl_norm%/}"
  hook::normalize_path_to home_norm "${HOME:-${USERPROFILE:-}}"
  home_norm="${home_norm%/}"
  # An enclosing checkout that is home or an ancestor of home keeps the branch off.
  [[ -n "$home_norm" && ("$tl_norm" == "$home_norm" || "$home_norm" == "$tl_norm"/*) ]] || SCAN_ROOT="$root"
}
