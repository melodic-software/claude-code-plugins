#!/usr/bin/env bash
# PostToolUse hook: auto-format and lint PowerShell files via PSScriptAnalyzer.
# Triggered on Write|Edit of *.ps1, *.psm1, and *.psd1 files.
#
# ADVISORY: always exits 0. Invoke-Formatter applies the consumer's formatting
# in place; PSScriptAnalyzer findings surface via additionalContext but never
# block the edit. A commit hook or CI is the hard gate.
#
# Opt-in: PSScriptAnalyzer runs ONLY when a PSScriptAnalyzerSettings.psd1 governs
# the edited file — found by walking up from the file to the repo root, stopping
# at the closest one. PSScriptAnalyzer does not auto-discover a settings file
# (Invoke-Formatter / Invoke-ScriptAnalyzer take an explicit -Settings path), so
# the hook both gates on that file and passes it through. A repo that has not
# adopted a settings file is left untouched rather than formatted and linted with
# PSScriptAnalyzer's built-in defaults, so the plugin never imposes a style it did
# not choose.
#
# Graceful degrade: pwsh absent (pwsh-less contributor box, Linux cloud session
# without PowerShell) OR the PSScriptAnalyzer module not installed -> clean silent
# no-op (exit 0, no error spam). pwsh is resolved from PATH — never downloaded.

set -uo pipefail

# Read inherited fd0 directly (bare cat) — NEVER `</dev/stdin`: on Windows Git
# Bash, CC spawns hooks with stdin = a Win32 pipe that `/dev/stdin` cannot
# resolve (ENOENT -> silent no-op). stdin is read ONCE here and fed to both
# hook::read_file_path (file_path) and the tool_name parse below; reading fd0
# twice would drain the pipe on the second call.
# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "POWERSHELL_FORMAT"

# Capture $EPOCHREALTIME immediately after kill-switch so duration_ms covers the
# work below (pre-work exits do not emit telemetry). EPOCHREALTIME is Bash 5.0+;
# on older bash it is unset, so default to empty — referencing it bare under
# `set -u` would abort before the advisory exit 0, failing every edit.
start=${EPOCHREALTIME:-}

# Telemetry needs the high-res start stamp. When EPOCHREALTIME is unavailable
# (Bash < 5.0) the stamp is empty and telemetry is skipped, so the hook still
# formats and lints on older bash rather than aborting.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::emit_telemetry "$@"
}

INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | hook::read_file_path) || exit 0
case "$FILE" in
*.ps1 | *.psm1 | *.psd1) ;;
*) exit 0 ;;
esac

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Resolve repo root early — used to bound the settings opt-in walk and to compute
# the schema-required repo-relative path in data.file.
REPO_ROOT="$(hook::repo_root "$(dirname "$FILE")")"
# Repo-relative path: schema requires "relative to the consuming repo root".
# On Windows Git Bash, git rev-parse --show-toplevel returns a drive-letter path
# while FILE may be in POSIX mount form. Normalize both through cygpath -lm
# (long name, forward-slash mixed form) when available so the prefix strip
# compares the same representation. On Linux/macOS, cygpath is absent and both
# paths are already POSIX. Falls back to raw FILE on any normalization error.
FILE_REL="$FILE"
if command -v cygpath >/dev/null 2>&1; then
  _file_lm=$(cygpath -lm "$FILE" 2>/dev/null)
  _root_lm=$(cygpath -lm "$REPO_ROOT" 2>/dev/null)
  if [[ -n "$_file_lm" && -n "$_root_lm" ]]; then
    FILE_REL="${_file_lm#"$_root_lm"/}"
  fi
else
  FILE_REL="${FILE#"$REPO_ROOT"/}"
fi

# Build the telemetry data object for the current TOOL/FILE_REL. $1 is the
# findings JSON array. jq is authoritative. The fallback is a fixed empty-shape
# object — NOT an interpolation of TOOL/FILE_REL, which could inject quotes or
# backslashes from a path and corrupt the envelope. The fallback is essentially
# unreachable in practice (it fires only if `jq -n` fails, and when jq is absent
# hook::emit_telemetry drops the envelope anyway), so losing the values here is
# harmless and strictly safer than emitting malformed JSON.
build_data_json() {
  jq -n \
    --arg tool "$TOOL" \
    --arg file "$FILE_REL" \
    --argjson findings "$1" \
    '{tool:$tool,file:$file,findings:$findings}' 2>/dev/null ||
    printf '{"tool":"","file":"","findings":[]}'
}

emit_skipped() {
  local data_json
  data_json=$(build_data_json '[]')
  emit_tel "powershell-format" "PostToolUse" "skipped" "$start" "$data_json" "$REPO_ROOT"
  exit 0
}

# Resolve the file's directory and walk anchors as physical paths — same
# representation hook::read_file_path uses for membership — so a symlinked
# CLAUDE_PROJECT_DIR still matches the file's resolved directory at the ceiling.
FILE_DIR_POSIX="$(hook::normalize_path "$(hook::physical_path "$(dirname "$FILE")")")" || FILE_DIR_POSIX=""
root="$(hook::normalize_path "$(hook::physical_path "$REPO_ROOT")")" || root=""

# Ceiling for the settings walk-up. When CLAUDE_PROJECT_DIR is set the walk stops
# there, so the settings ceiling matches the file-membership ceiling that
# hook::read_file_path already enforced — a settings file above the project dir
# (which the agent was never allowed to write under) can never govern the edit,
# and a settings file discovered under CustomRulePath is executed during analysis
# (see README "Trust model"). The git-root ceiling is the fallback when unset.
CEILING="$root"
if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  CEILING="$(hook::normalize_path "$(hook::physical_path "$CLAUDE_PROJECT_DIR")")"
fi

# Consumer opt-in: a PSScriptAnalyzerSettings.psd1 that governs the edited file.
# Walk up from the file's directory to the ceiling, stopping at the FIRST
# (closest) settings file — a monorepo may keep per-module settings, and the
# closest one is the one that should govern this file. Absence of any settings
# file is the opt-out: the file is left untouched.
SETTINGS_FOUND=""
dir="$FILE_DIR_POSIX"
while [[ -n "$dir" ]]; do
  if [[ -f "$dir/PSScriptAnalyzerSettings.psd1" ]]; then
    SETTINGS_FOUND="$dir/PSScriptAnalyzerSettings.psd1"
    break
  fi
  [[ -n "$CEILING" && "$dir" == "$CEILING" ]] && break
  parent="$(dirname "$dir")"
  [[ "$parent" == "$dir" ]] && break # reached filesystem root
  dir="$parent"
done

[[ -n "$SETTINGS_FOUND" ]] || emit_skipped

# Resolve pwsh from PATH — never downloaded. Absent -> clean skip (a pwsh-less
# contributor box, or a Linux cloud session without PowerShell). CI's PowerShell
# job is the authoritative PSScriptAnalyzer gate, so nothing is lost locally.
command -v pwsh >/dev/null 2>&1 || emit_skipped

# PowerShell on Windows does not understand MSYS mount paths (/d/...). Convert
# both the file and the settings path to a mixed drive-letter form (D:/...) that
# pwsh consumes, when cygpath is available (Git Bash on Windows); on Linux/macOS
# cygpath is absent and the POSIX paths pwsh already understands pass through.
to_pwsh_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1" 2>/dev/null || printf '%s' "$1"
  else
    printf '%s' "$1"
  fi
}
PSSA_FILE_ARG="$(to_pwsh_path "$FILE")"
PSSA_SETTINGS_ARG="$(to_pwsh_path "$SETTINGS_FOUND")"

# Single pwsh invocation — probe the module, format in place, then lint. File
# and settings pass via env vars to avoid pwsh argument parsing issues.
#   exit 3  PSScriptAnalyzer module not installed -> clean skip (no findings)
#   exit 0  clean
#   exit 1  findings (written to stderr, one line each)
#   exit 4  Invoke-Formatter / Invoke-ScriptAnalyzer threw -> tool break
#   exit 5  file is neither BOM'd nor valid UTF-8 (legacy ANSI) -> clean skip
#           (cannot round-trip the bytes safely, so never rewrite)
# SC2016: PowerShell uses $env:VAR syntax inside single quotes — not bash expansion.
# shellcheck disable=SC2016
PSSA_OUTPUT=$(PSSA_FILE="$PSSA_FILE_ARG" PSSA_SETTINGS="$PSSA_SETTINGS_ARG" \
  pwsh -NoProfile -NonInteractive -Command '
    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
        exit 3
    }
    try {
        $file = $env:PSSA_FILE
        $settings = $env:PSSA_SETTINGS

        # Relative CustomRulePath entries in the settings file resolve from the
        # current PowerShell location, and the hook inherits whatever cwd the
        # agent happened to use — anchor at the settings directory so
        # repo-relative rule paths resolve the way the repo intended.
        Set-Location -LiteralPath (Split-Path -Parent $settings)

        # Read with BOM detection and remember the encoding so the write-back
        # preserves the original byte shape (UTF-8 with/without BOM, UTF-16
        # LE/BE). Get-Content/Set-Content would rewrite with the shell default
        # (utf8NoBOM on pwsh), stripping a BOM or transcoding UTF-16 on the
        # first auto-format. Strict UTF-8 is the BOM-less fallback: a file that
        # fails it (legacy ANSI) cannot be round-tripped safely -> exit 5.
        $sr = $null
        try {
            $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
            $sr = [System.IO.StreamReader]::new($file, $strictUtf8, $true)
            $original = $sr.ReadToEnd()
            $enc = $sr.CurrentEncoding
        } catch [System.Text.DecoderFallbackException] {
            exit 5
        } finally {
            if ($sr) { $sr.Dispose() }
        }
        if ($null -eq $original) { $original = "" }
        $formatted = Invoke-Formatter -ScriptDefinition $original -Settings $settings
        # -cne (case-SENSITIVE) is load-bearing: PowerShell string -ne is
        # case-insensitive, so a casing-only reformat (get-childitem ->
        # Get-ChildItem via PSUseCorrectCasing) would compare equal and the fix
        # would never be written back.
        if ($formatted -cne $original) {
            if (-not $formatted.EndsWith("`n")) {
                $formatted += "`n"
            }
            [System.IO.File]::WriteAllText($file, $formatted, $enc)
        }

        # Invoke-ScriptAnalyzer has no -LiteralPath (verified against module
        # 1.25.0); -Path treats wildcard metacharacters ([ ] * ?) in a filename
        # as a pattern. Escape the path so it is matched literally — the same
        # literal-path intent the Get-Content/Set-Content -LiteralPath calls above
        # carry, realized via the only mechanism -Path offers.
        $litFile = [System.Management.Automation.WildcardPattern]::Escape($file)
        $results = @(Invoke-ScriptAnalyzer -Path $litFile -Settings $settings)
        if ($results.Count -gt 0) {
            foreach ($r in $results) {
                [Console]::Error.WriteLine(
                    "PSScriptAnalyzer: L$($r.Line) [$($r.Severity)] $($r.RuleName): $($r.Message)"
                )
            }
            exit 1
        }
    } catch {
        [Console]::Error.WriteLine("powershell-format: $($_.Exception.Message)")
        exit 4
    }
    exit 0
' 2>&1)
PWSH_EXIT=$?

case $PWSH_EXIT in
0)
  # Clean — the analyzer ran to judgment with no findings.
  data_json=$(build_data_json '[]')
  emit_tel "powershell-format" "PostToolUse" "ok" "$start" "$data_json" "$REPO_ROOT"
  exit 0
  ;;
1)
  # Findings — advisory context, exit 0. Status "ok": the analyzer RAN and
  # produced a judgment (findings live in data.findings), mirroring the sibling
  # formatter plugins where status reflects whether the tool ran, not clean-ness.
  hook::ctx_reset
  hook::ctx_append "powershell-format: $(basename "$FILE") has PSScriptAnalyzer findings (advisory):"
  findings_raw=""
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    hook::ctx_append "  $line"
    findings_raw+="$line"$'\n'
  done <<<"$PSSA_OUTPUT"
  hook::ctx_flush PostToolUse

  FINDINGS_JSON='[]'
  if [[ -n "$findings_raw" ]]; then
    FINDINGS_JSON=$(printf '%s' "$findings_raw" | jq -R . | jq -s . 2>/dev/null) || FINDINGS_JSON='[]'
  fi
  data_json=$(build_data_json "$FINDINGS_JSON")
  emit_tel "powershell-format" "PostToolUse" "ok" "$start" "$data_json" "$REPO_ROOT"
  exit 0
  ;;
3)
  # PSScriptAnalyzer module not installed — the repo opted into a settings file
  # but the analyzer is not present; nothing to run. Clean silent skip, the same
  # status as the no-settings / no-pwsh paths.
  emit_skipped
  ;;
5)
  # File is neither BOM'd nor valid UTF-8 (legacy ANSI) — rewriting it would
  # transcode bytes the hook cannot round-trip. Clean silent skip; the repo's
  # commit hook / CI remains the gate for such files.
  emit_skipped
  ;;
*)
  # pwsh threw for non-lint reasons (bad settings file, internal error) — no
  # judgment was made. Surface via additionalContext (NOT stderr — an advisory
  # hook's exit-0 stderr can trip a false "Hook Error" label). Record as
  # "skipped" (the analyzer never ran to judgment).
  hook::ctx_reset
  hook::ctx_append "powershell-format: pwsh failed for $(basename "$FILE") (no diagnostics; tool break, not a finding):"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    hook::ctx_append "  $line"
  done <<<"$PSSA_OUTPUT"
  hook::ctx_flush PostToolUse
  data_json=$(build_data_json '[]')
  emit_tel "powershell-format" "PostToolUse" "skipped" "$start" "$data_json" "$REPO_ROOT"
  exit 0
  ;;
esac
