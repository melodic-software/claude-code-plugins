#!/bin/sh
# shellcheck shell=bash
# powershell-format's side of lib/git-hooks/resolve-tool.sh: the ecosystem id
# whose record setup reports (hooks never run it), the files it acts on, and its
# PSScriptAnalyzer adapter. Sourced by both git-hook entries.
#
# The adapter governs a file only when a PSScriptAnalyzerSettings.psd1 sits in
# its directory or above it, up to the repository root; the closest one supplies
# the rules. The adapter runs from that settings file's directory, so the files
# one settings file governs share one pwsh process (psscriptanalyzer.ps1). Format
# runs Invoke-Formatter; lint runs Invoke-ScriptAnalyzer and fixes nothing.
#
# A settings file that declares CustomRulePath would make PSScriptAnalyzer run
# repository-supplied rule modules, so psscriptanalyzer.ps1 skips that state
# (exit 6) until the user approves its exact content: a marker directory under
# powershell-format/ in the repository's git common directory, the one store
# every commit and the Stop row read (CLAUDE_PLUGIN_DATA is not used, since an
# agent's shell can carry another plugin's value). An agent is told the verdict
# and never the command that grants the approval.

# shellcheck disable=SC2034 # read by resolve-tool.sh
RT_PLUGIN=powershell-format
# shellcheck disable=SC2034 # read by resolve-tool.sh
RT_IDS=powershell
PSF_SETTINGS=PSScriptAnalyzerSettings.psd1
PSF_INSTALL='see https://learn.microsoft.com/powershell/scripting/install/installing-powershell'
PSF_INSTALL_MOD='pwsh -Command Install-Module PSScriptAnalyzer -Scope CurrentUser'
case "${BASH_SOURCE[0]}" in
*/*) PSF_HERE="${BASH_SOURCE[0]%/*}" ;;
*) PSF_HERE=. ;;
esac

rt_wants() {
  case "$1" in
  .githooks/* | */.githooks/* | *$'\n'*) return 1 ;;
  *.ps1 | *.psm1 | *.psd1) return 0 ;;
  *) return 1 ;;
  esac
}

# psf__walk <dir> <root>: 0 when a settings file sits at <dir> or above it, up
# to <root>; PSF_DIR is where.
psf__walk() {
  local dir="$1"
  while :; do
    if [[ -f "$dir/$PSF_SETTINGS" ]]; then
      PSF_DIR="$dir"
      return 0
    fi
    [[ "$dir" == "$2" || "$dir" != */* ]] && return 1
    dir="${dir%/*}"
    [[ -n "$dir" ]] || return 1
  done
}

psf__detail() { # <settings dir> <root>
  local rel="${1#"$2"}"
  rel="${rel#/}"
  RT_DETAIL="config ${rel:+$rel/}$PSF_SETTINGS; binary pwsh on PATH"
}

# shellcheck disable=SC2034 # RT_* are read by resolve-tool.sh and the entries
rt_adapter() { # <concern> <file> <root>
  local f="$2"
  [[ "$f" == /* || "$f" == [A-Za-z]:[\\/]* ]] || f="$3/$f"
  f="${f%/*}"
  psf__walk "$f" "$3" || return 1
  RT_ADAPTER=psscriptanalyzer RT_TOOL=pwsh RT_BIN=pwsh RT_DIR="$PSF_DIR" RT_INSTALL="$PSF_INSTALL"
  RT_CONFIGS="$PSF_SETTINGS"
  psf__detail "$PSF_DIR" "$3"
  # shellcheck disable=SC2016 # the command text sh -c expands, with RT_BIN, PSF_PS1 and the files
  RT_SCRIPT='"$RT_BIN" -NoProfile -NonInteractive -File "$PSF_PS1" '"$1"' "$@"'
}

# shellcheck disable=SC2034 # RT_* are read by resolve-tool.sh
rt_adapter_in_repo() { # <concern> <root>
  local f dir="$2"
  if [[ ! -f "$2/$PSF_SETTINGS" ]]; then
    f="$(git -C "$2" ls-files -- ":(glob)**/$PSF_SETTINGS" 2>/dev/null | head -1)"
    if [[ -z "$f" ]]; then
      RT_DETAIL="no $PSF_SETTINGS"
      return 1
    fi
    dir="$2/${f%/*}"
  fi
  RT_ADAPTER=psscriptanalyzer RT_TOOL=pwsh RT_BIN=pwsh
  psf__detail "$dir" "$2"
}

# psf_pwsh_path <path>: PowerShell on Windows does not understand MSYS mount
# paths (/d/...), so a Windows bash with cygpath passes the drive-letter form.
psf_pwsh_path() {
  case "${OSTYPE:-}" in
  msys* | cygwin* | win32) command -v cygpath >/dev/null 2>&1 && cygpath -m "$1" 2>/dev/null && return ;;
  *) ;;
  esac
  printf '%s' "$1"
}

# psf_init <root>: the approval store and the paths every run passes to pwsh.
# The trust signature binds PSSA_REPO_ROOT and PSSA_SETTINGS as text, so their
# form must not change between releases, or every approval is revoked.
psf_init() {
  local common
  PSF_ROOT="$1"
  PSF_STATE=""
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  [[ -z "$common" ]] || PSF_STATE="$common/powershell-format"
  if [[ "$PSF_STATE" == [A-Za-z]:\\* ]] && command -v cygpath >/dev/null 2>&1; then
    PSF_STATE="$(cygpath -u "$PSF_STATE" 2>/dev/null || printf '%s' "$PSF_STATE")"
  fi
  PSF_STATE_ARG=""
  [[ -z "$PSF_STATE" ]] || PSF_STATE_ARG="$(psf_pwsh_path "$PSF_STATE")"
  PSF_ROOT_ARG="$(psf_pwsh_path "$1")"
  # rt_run starts pwsh from the settings directory, so the script path is absolute.
  [[ "$PSF_HERE" == /* || "$PSF_HERE" == [A-Za-z]:[\\/]* ]] || PSF_HERE="$PWD/$PSF_HERE"
  PSF_PS1_ARG="$(psf_pwsh_path "$PSF_HERE/psscriptanalyzer.ps1")"
}

# psf_settings_rel: the current group's settings file, repo-relative.
psf_settings_rel() {
  local rel="${RT_DIR#"$PSF_ROOT"}"
  rel="${rel#/}"
  printf '%s' "${rel:+$rel/}$PSF_SETTINGS"
}

# psf_run <run dir> <files...>: rt_run for the current group from <run dir>
# (the settings directory, or its mirror holding index copies), with the
# environment psscriptanalyzer.ps1 reads; the settings file stays the group's.
psf_run() {
  local dir="$RT_DIR" rc
  RT_DIR="$1"
  shift
  PSF_PS1="$PSF_PS1_ARG" PSSA_SETTINGS="$(psf_pwsh_path "$dir/$PSF_SETTINGS")" \
    PSSA_REPO_ROOT="$PSF_ROOT_ARG" PSSA_STATE_BASE="$PSF_STATE_ARG" rt_run "$@"
  rc=$?
  RT_DIR="$dir"
  return "$rc"
}

# psf_module_missing: the missing-tool rule for the PSScriptAnalyzer module
# (exit 3 from psscriptanalyzer.ps1), as a status: 1 skip, 2 fail the entry.
psf_module_missing() {
  if checks_skip_listed PSScriptAnalyzer; then
    printf 'SKIPPED: PSScriptAnalyzer (missing)\n' >&2
    return 1
  fi
  if checks_is_agent; then
    printf 'FAIL: PSScriptAnalyzer missing. Install: %s\n' "$PSF_INSTALL_MOD" >&2
    printf 'To skip only while PSScriptAnalyzer is missing: git -c checks.skipmissing=PSScriptAnalyzer %s ...\n' "$(checks_git_verb)" >&2
    return 2
  fi
  printf 'NOTICE: PSScriptAnalyzer missing, so this check did not run. Install: %s\n' "$PSF_INSTALL_MOD" >&2
  return 1
}

# psf_trust_notice <pwsh output> <concern word>: say why the concern was
# skipped for the current group's settings file (exit 6).
psf_trust_notice() {
  local line verdict="" marker="" msg settings
  settings="$(psf_settings_rel)"
  while IFS= read -r line; do
    line="${line%$'\r'}"
    case "$line" in
    "PSSA_TRUST GATE "*)
      verdict=GATE
      marker="${line#PSSA_TRUST GATE }"
      ;;
    "PSSA_TRUST NOSTORE") verdict=NOSTORE ;;
    "PSSA_TRUST UNVERIFIABLE") verdict=UNVERIFIABLE ;;
    "PSSA_TRUST UNPINNABLE") verdict=UNPINNABLE ;;
    *) ;;
    esac
  done <"$1"
  msg="powershell-format trust gate: $2 skipped for files under $settings;"
  case "$verdict" in
  GATE)
    msg="$msg it loads repository rule modules and is not approved. Approval is the user's."
    if ! checks_is_agent && [[ -n "$PSF_STATE" && -n "$marker" ]]; then
      msg="$msg Review that file and every rule module it references, then run: mkdir -p '${PSF_STATE%/}/trust-approvals/$marker' (any change to them revokes the approval)."
    fi
    ;;
  UNVERIFIABLE) msg="$msg it cannot be verified free of repository rule modules, so $2 stays off." ;;
  UNPINNABLE) msg="$msg a rule module it references loads code no approval can pin, so $2 stays off." ;;
  *) msg="$msg it loads repository rule modules and there is no approval store, so $2 stays off." ;;
  esac
  printf '%s\n' "$msg" >&2
}

# psf_broken <pwsh output> <cmdlet>: show why a run failed.
psf_broken() {
  printf 'powershell-format: %s failed under %s:\n' "$2" "$(psf_settings_rel)" >&2
  sed -e 's/^PSSA_ERROR //' -e 's/\r$//' "$1" >&2
}
