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
# not choose. A settings file that declares CustomRulePath would make the analyzer
# execute repository-supplied rule modules, so that state is further gated on an
# explicit per-content trust approval (see the trust gate below).
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

INPUT=$(hook::buffer_stdin) || exit 0

# jq-free applicability pre-filter: never emit the jq notice for an edit this
# hook would not process anyway (the Write|Edit matcher is broader than the
# PowerShell-file filter).
RAW_FILE=$(hook::raw_file_path "$INPUT") || exit 0
case "$RAW_FILE" in
*.ps1 | *.psm1 | *.psd1) ;;
*) exit 0 ;;
esac

# jq is load-bearing for input parsing; absent → visible once-per-session skip
# notice instead of a silent no-op (dim-9 doctrine). pwsh absence below stays
# QUIET by design: a machine without PowerShell is a platform N/A, not a gap.
hook::require_jq PostToolUse powershell-format "$INPUT"

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
# and a settings file that declares CustomRulePath is gated on explicit trust
# approval before analysis (see README "Trust model"). The git-root ceiling is
# the fallback when unset.
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
# silent-skip-ok: not-applicable classification — absent pwsh is a by-design
# quiet skip on hosts without PowerShell; telemetry still records the skip.
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

# Trust gate state base for the code-loading settings check inside the pwsh
# block below. A settings file may declare CustomRulePath, and PSScriptAnalyzer
# loads and RUNS those rule modules during analysis — repository-supplied code
# must never execute on the strength of a PowerShell edit alone. Approval is an
# explicit marker directory the user creates after reviewing the settings file
# and every rule module it references. CLAUDE_PLUGIN_DATA is the official
# persistent plugin-state location and survives plugin updates. The approval
# signature itself is computed inside pwsh, because only the restricted data
# parser can resolve WHAT the settings load: it is content-addressed over the
# repo root, the settings file, and every file reachable under each declared
# CustomRulePath entry, so a change to the settings OR to any referenced rule
# module yields a new marker directory and revokes a prior approval — a
# settings-only signature would keep honoring an approval after a branch
# switch replaced the rule module bytes. The exit-6 arm fails CLOSED whenever
# the signature cannot be computed. (Same shape as markdown-format's trust
# gate; a future refactor could hoist the shared primitive into the hook-utils
# library.)
PSSA_STATE_BASE_ARG=""
if [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
  PSSA_STATE_BASE_ARG="$(to_pwsh_path "$CLAUDE_PLUGIN_DATA")"
fi

# Single pwsh invocation — probe the module, gate code-loading settings, format
# in place, then lint. File and settings pass via env vars to avoid pwsh
# argument parsing issues.
#   exit 3  PSScriptAnalyzer module not installed -> clean skip (no findings)
#   exit 0  clean
#   exit 1  findings (written to stderr, one line each)
#   exit 4  Invoke-Formatter / Invoke-ScriptAnalyzer threw -> tool break
#   exit 5  file is neither BOM'd nor valid UTF-8 (legacy ANSI) -> clean skip
#           (cannot round-trip the bytes safely, so never rewrite)
#   exit 6  settings declare CustomRulePath (or could not be verified code-free)
#           and this settings-content state is unapproved -> trust-gate skip
# SC2016: PowerShell uses $env:VAR syntax inside single quotes — not bash expansion.
# shellcheck disable=SC2016
PSSA_OUTPUT=$(PSSA_FILE="$PSSA_FILE_ARG" PSSA_SETTINGS="$PSSA_SETTINGS_ARG" \
  PSSA_STATE_BASE="$PSSA_STATE_BASE_ARG" PSSA_REPO_ROOT="$REPO_ROOT" \
  pwsh -NoProfile -NonInteractive -Command '
    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
        exit 3
    }

    # Trust gate: a settings file may declare CustomRulePath, which makes
    # Invoke-ScriptAnalyzer load and execute repository-supplied rule modules.
    # Detect the key via the restricted data-file parser PowerShell itself
    # provides — a textual grep is evadable through quoting and escape
    # sequences (e.g. a backtick escape inside a double-quoted key still
    # evaluates to CustomRulePath). A settings file the restricted parser
    # rejects cannot be proven code-free (PSScriptAnalyzer settings parsing is
    # more lenient, for example taking the first hashtable of a
    # multi-statement file), so it gates too: fail closed.
    #
    # The approval signature covers the settings file AND every file reachable
    # under each declared CustomRulePath entry (recursively for directories,
    # matching -RecurseCustomRulePath reach), so approval binds to the rule
    # module content that would execute, not just to the text that names it.
    # An entry that does not resolve, or a state base that is unusable, makes
    # the state unverifiable: exit 6 with no approval route (fail closed).
    # Structured PSSA_TRUST lines on stdout hand the verdict to the shell.
    $sd = $null
    try {
        $sd = Import-PowerShellDataFile -LiteralPath $env:PSSA_SETTINGS -ErrorAction Stop
    } catch {
        $sd = $null
    }
    if (-not ($sd -is [hashtable])) {
        Write-Output "PSSA_TRUST UNVERIFIABLE"
        exit 6
    }
    if ($sd.ContainsKey("CustomRulePath")) {
        $settingsDir = Split-Path -Parent $env:PSSA_SETTINGS
        $ruleFiles = [System.Collections.Generic.List[string]]::new()
        $unverifiable = $false
        foreach ($entry in @($sd["CustomRulePath"])) {
            if (-not ($entry -is [string]) -or [string]::IsNullOrWhiteSpace($entry)) {
                $unverifiable = $true; break
            }
            $resolvedPath = $entry
            if (-not [System.IO.Path]::IsPathRooted($resolvedPath)) {
                $resolvedPath = Join-Path $settingsDir $resolvedPath
            }
            if (Test-Path -LiteralPath $resolvedPath -PathType Leaf) {
                $ruleFiles.Add((Convert-Path -LiteralPath $resolvedPath))
            } elseif (Test-Path -LiteralPath $resolvedPath -PathType Container) {
                foreach ($f in Get-ChildItem -LiteralPath $resolvedPath -Recurse -File -Force) {
                    $ruleFiles.Add($f.FullName)
                }
            } else {
                $unverifiable = $true; break
            }
        }
        if ($unverifiable -or $ruleFiles.Count -gt 512) {
            Write-Output "PSSA_TRUST UNVERIFIABLE"
            exit 6
        }
        # Transitive code-loading inputs: a declared leaf module may dot-source
        # or Import-Module further repository files, and those execute with it,
        # so they must be pinned too. Enumerating PowerShell resolution exactly
        # would mean evaluating the module - the very thing being gated - so
        # approximate from text: collect every string literal in each collected
        # file, resolve it against the containing directory and the settings
        # directory, take existing files, and rescan those the same way,
        # bounded. Overflow or an unreadable file makes the state unverifiable.
        $sq = [char]39
        $dq = [char]34
        $litPattern = "$sq([^$sq]+)$sq|$dq([^$dq]+)$dq"
        # Substitute the automatic variables whose values are known here -
        # anywhere in the reference, not just as a leading prefix - so the
        # standard interpolated dependency . "$PSScriptRoot/x.ps1" resolves.
        # Without it Join-Path reads PSScriptRoot as a directory name and the
        # helper escapes the signature. Shared by the parser and text passes so
        # both judge and resolve the same string.
        # The name is BOUNDED, so a longer variable that merely starts with the
        # same text is not mistaken for it: PowerShell continues a variable name
        # through [A-Za-z0-9_] and reads a colon as a scope qualifier, so an
        # unbounded pattern would rewrite $PSScriptRootFoo to <dir>Foo and the
        # caller would then judge that reference pinnable and never pin it.
        function expandKnownVars([string]$value, [string]$scriptRoot, [string]$commandPath) {
            $out = [regex]::Replace(
                $value,
                "(?i)\`$(?:\{PSScriptRoot\}|PSScriptRoot(?![A-Za-z0-9_:]))",
                $scriptRoot.Replace("`$", "`$`$"))
            [regex]::Replace(
                $out,
                "(?i)\`$(?:\{PSCommandPath\}|PSCommandPath(?![A-Za-z0-9_:]))",
                $commandPath.Replace("`$", "`$`$"))
        }
        $seen = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase)
        $allFiles = [System.Collections.Generic.List[string]]::new()
        $scanQueue = [System.Collections.Generic.Queue[string]]::new()
        foreach ($rf in $ruleFiles) {
            if ($seen.Add($rf)) { $allFiles.Add($rf); $scanQueue.Enqueue($rf) }
        }
        $scanned = 0
        while ($scanQueue.Count -gt 0) {
            $cur = $scanQueue.Dequeue()
            $scanned++
            if ($scanned -gt 256 -or $allFiles.Count -gt 512) {
                Write-Output "PSSA_TRUST UNVERIFIABLE"
                exit 6
            }
            $curDir = Split-Path -Parent $cur
            try { $text = [System.IO.File]::ReadAllText($cur) } catch {
                Write-Output "PSSA_TRUST UNVERIFIABLE"
                exit 6
            }
            # Candidate paths to resolve for this file: every load target the
            # parser reports plus every quoted literal the text scan finds.
            $pending = [System.Collections.Generic.List[string]]::new()

            # Refuse a load whose target cannot be pinned to a file. A COMPOSED
            # target - a variable, an env lookup, or an expression such as
            # . (Join-Path $PSScriptRoot "deps" "helper.ps1") - names a
            # dependency that could never enter the signature, and an approval
            # would then survive arbitrary edits to it. The PowerShell parser
            # decides pinnability exactly: the target must be a constant string,
            # or an interpolated string whose every variable this scan can
            # expand. Unlike a text pattern it cannot be evaded by quoting or
            # comment placement, and it needs no file-extension guessing, so the
            # extensionless Import-Module "$root/MyModule" form is caught too.
            #
            # A target the parser accepts is queued HERE rather than left to the
            # quoted-literal scan below, which sees only quoted text: PowerShell
            # does not require quotes around a command argument, so
            # . $PSScriptRoot\helper.ps1 and Import-Module ./rules/helper.ps1
            # would otherwise be judged pinnable and then never pinned - the one
            # direction this gate must not fail in.
            #
            # Scoped to PowerShell source because the collector also pins
            # non-code data files, which the parser would reject wholesale.
            if ($cur -match "\.ps(m|d)?1$") {
                $perrs = $null
                $fileAst = [System.Management.Automation.Language.Parser]::ParseInput(
                    $text, [ref]$null, [ref]$perrs)
                if ($null -eq $fileAst -or ($null -ne $perrs -and $perrs.Count -gt 0)) {
                    Write-Output "PSSA_TRUST UNVERIFIABLE"
                    exit 6
                }
                # Named code-loading commands. The dot-source and call-operator
                # forms need no name match: InvocationOperator identifies them,
                # and their element 0 IS the target, so it is checked too.
                $loaders = @("Import-Module", "ipmo", "Add-Type", "New-Module",
                    "Invoke-Expression", "iex", "Import-PowerShellDataFile")
                $cmdAsts = $fileAst.FindAll({
                        param($n) $n -is [System.Management.Automation.Language.CommandAst]
                    }, $true)
                foreach ($cmdAst in $cmdAsts) {
                    $cmdName = $cmdAst.GetCommandName()
                    $isLoad = $cmdAst.InvocationOperator -ne
                        [System.Management.Automation.Language.TokenKind]::Unknown
                    if (-not $isLoad) {
                        $isLoad = [string]::IsNullOrEmpty($cmdName) -or
                            $loaders -contains $cmdName
                    }
                    if (-not $isLoad) { continue }
                    # A loader fed by a PIPELINE takes its source from the
                    # upstream element, not from its own arguments, so the loop
                    # below would see only a constant command name and accept:
                    # Get-Content (Join-Path $PSScriptRoot deps helper.ps1) | iex
                    # executes a file this scan never reconstructs, and
                    # Get-ChildItem *.psm1 | Import-Module has the same shape.
                    # Anything but the first element of its own pipeline is
                    # refused.
                    if ($null -ne $cmdAst.Parent -and
                        $cmdAst.Parent -is [System.Management.Automation.Language.PipelineAst] -and
                        $cmdAst.Parent.PipelineElements.Count -gt 1 -and
                        -not [object]::ReferenceEquals($cmdAst.Parent.PipelineElements[0], $cmdAst)) {
                        Write-Output "PSSA_TRUST UNPINNABLE"
                        exit 6
                    }
                    foreach ($el in $cmdAst.CommandElements) {
                        if ($el -is [System.Management.Automation.Language.CommandParameterAst]) { continue }
                        if ($el -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                            [void]$pending.Add($el.Value)
                            continue
                        }
                        # An inline script block is part of the text already
                        # hashed here; FindAll recursed into it, so a composed
                        # load nested inside is still judged on its own.
                        if ($el -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { continue }
                        if ($el -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
                            $target = expandKnownVars $el.Value $curDir $cur
                            if (-not $target.Contains("`$")) {
                                [void]$pending.Add($target)
                                continue
                            }
                        }
                        Write-Output "PSSA_TRUST UNPINNABLE"
                        exit 6
                    }
                }
                # `using module ./deps/helper.psm1` loads code but is a
                # UsingStatementAst, not a CommandAst, so the loop above never
                # sees it - and the form needs no quotes, so the text scan does
                # not either. Only the Module kind loads repository code; a
                # `using namespace` or `using assembly` statement names no
                # repository file and is left alone. The path must be a constant
                # (PowerShell requires one), so a hashtable module specification
                # cannot be pinned and refuses approval.
                $usingAsts = $fileAst.FindAll({
                        param($n) $n -is [System.Management.Automation.Language.UsingStatementAst]
                    }, $true)
                foreach ($useAst in $usingAsts) {
                    if ($useAst.UsingStatementKind -ne
                        [System.Management.Automation.Language.UsingStatementKind]::Module) {
                        continue
                    }
                    if ($useAst.Name -is
                        [System.Management.Automation.Language.StringConstantExpressionAst]) {
                        [void]$pending.Add($useAst.Name.Value)
                        continue
                    }
                    Write-Output "PSSA_TRUST UNPINNABLE"
                    exit 6
                }
            }
            foreach ($hit in [regex]::Matches($text, $litPattern)) {
                $lit = if ($hit.Groups[1].Success) { $hit.Groups[1].Value } else { $hit.Groups[2].Value }
                if ([string]::IsNullOrWhiteSpace($lit) -or $lit.Contains("`n")) { continue }
                # The raw literal AND its expansion are both candidates: a file
                # whose name genuinely contains the text still resolves, and the
                # standard interpolated dependency resolves too.
                [void]$pending.Add($lit)
                if ($lit.Contains("`$")) {
                    $expanded = expandKnownVars $lit $curDir $cur
                    if ($expanded -ne $lit) { [void]$pending.Add($expanded) }
                }
            }
            # An extensionless reference resolves through PowerShell module
            # resolution, so pinning only the exact leaf would miss the file that
            # actually executes: Import-Module "$PSScriptRoot/MyModule" loads
            # MyModule.psd1/.psm1, or MyModule/MyModule.psd1 when the reference
            # names a module directory. Every candidate is tried; whatever exists
            # is pinned, which over-collects at worst.
            foreach ($cand0 in $pending) {
                if ([string]::IsNullOrWhiteSpace($cand0)) { continue }
                foreach ($baseDir in @($curDir, $settingsDir)) {
                    $base = $cand0
                    try {
                        if (-not [System.IO.Path]::IsPathRooted($base)) {
                            $base = Join-Path $baseDir $base
                        }
                    } catch { continue }
                    $cands = @($base)
                    foreach ($ext in @(".psd1", ".psm1", ".ps1", ".dll")) {
                        $cands += "$base$ext"
                    }
                    try {
                        if (Test-Path -LiteralPath $base -PathType Container) {
                            $leaf = Split-Path -Leaf $base
                            foreach ($ext in @(".psd1", ".psm1")) {
                                $cands += (Join-Path $base "$leaf$ext")
                            }
                            # The versioned layout PowerShell also loads:
                            # MyModule/<version>/MyModule.psd1. Every immediate
                            # subdirectory is tried rather than version strings
                            # being parsed - a non-version directory simply has
                            # no manifest to find.
                            foreach ($sub in Get-ChildItem -LiteralPath $base -Directory -Force -ErrorAction SilentlyContinue) {
                                foreach ($ext in @(".psd1", ".psm1")) {
                                    $cands += (Join-Path $sub.FullName "$leaf$ext")
                                }
                            }
                        }
                    } catch { }
                    foreach ($cand in $cands) {
                        try {
                            if (Test-Path -LiteralPath $cand -PathType Leaf) {
                                $full = Convert-Path -LiteralPath $cand
                                if ($seen.Add($full)) { $allFiles.Add($full); $scanQueue.Enqueue($full) }
                            }
                        } catch { continue }
                    }
                }
            }
        }
        $manifest = [System.Text.StringBuilder]::new()
        [void]$manifest.AppendLine($env:PSSA_REPO_ROOT)
        $digestTargets = @($env:PSSA_SETTINGS) + (@($allFiles) | Sort-Object)
        foreach ($target in $digestTargets) {
            try {
                $h = (Get-FileHash -LiteralPath $target -Algorithm SHA256 -ErrorAction Stop).Hash
            } catch {
                Write-Output "PSSA_TRUST UNVERIFIABLE"
                exit 6
            }
            [void]$manifest.AppendLine("$target`t$h")
        }
        if ([string]::IsNullOrEmpty($env:PSSA_STATE_BASE)) {
            Write-Output "PSSA_TRUST NOSTORE"
            exit 6
        }
        # Instance SHA256 + x2 formatting: the static SHA256.HashData /
        # Convert.ToHexString shortcuts are .NET 5+, absent on the PowerShell
        # 7.0 (.NET Core 3.1) floor this hook supports. Any failure is
        # UNVERIFIABLE - an empty signature must never mint a shared marker.
        $signature = ""
        try {
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                $sigBytes = $sha.ComputeHash(
                    [System.Text.Encoding]::UTF8.GetBytes($manifest.ToString()))
            } finally {
                $sha.Dispose()
            }
            $hex = [System.Text.StringBuilder]::new()
            foreach ($b in $sigBytes) { [void]$hex.Append($b.ToString("x2")) }
            $signature = $hex.ToString()
        } catch {
            $signature = ""
        }
        if ([string]::IsNullOrEmpty($signature)) {
            Write-Output "PSSA_TRUST UNVERIFIABLE"
            exit 6
        }
        # Emit the marker NAME, not a path: the shell rebuilds the directory in
        # its own path form so the approval hint matches the POSIX shell the
        # user runs mkdir in, while Test-Path here uses the native form — both
        # views name the same physical directory.
        $trustDir = Join-Path $env:PSSA_STATE_BASE "trust-approvals" "pssa-$signature"
        if (-not (Test-Path -LiteralPath $trustDir -PathType Container)) {
            Write-Output "PSSA_TRUST GATE pssa-$signature"
            exit 6
        }
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
6)
  # Trust gate — the settings file can make the analyzer execute
  # repository-supplied code (CustomRulePath), or could not be verified
  # code-free, and this exact settings-plus-rule-module content state carries
  # no approval marker. Skip the run with a visible once-per-session notice on
  # both channels; the notice key carries the state signature so a settings or
  # rule-module change re-notices within the same session. When the approval
  # store is unavailable or the state is unverifiable the gate fails closed:
  # analysis stays disabled rather than trusted. The pwsh block reports the
  # verdict as a structured PSSA_TRUST line: "GATE <marker-name>" (approvable —
  # the marker directory is rebuilt here from CLAUDE_PLUGIN_DATA in shell path
  # form so the mkdir hint runs as printed), "NOSTORE" (no state base),
  # "UNVERIFIABLE" (settings unparsable, a CustomRulePath entry unresolvable,
  # or rule content undigestable), or "UNPINNABLE" (a rule module loads code
  # through a target that cannot be resolved to a file, so no approval can
  # bind to what would execute).
  SETTINGS_REL="$SETTINGS_FOUND"
  [[ -n "$root" ]] && SETTINGS_REL="${SETTINGS_FOUND#"$root"/}"
  TRUST_VERDICT=""
  TRUST_MARKER_NAME=""
  TRUST_DIR=""
  while IFS= read -r line; do
    case "$line" in
    "PSSA_TRUST GATE "*)
      TRUST_VERDICT="GATE"
      TRUST_MARKER_NAME="${line#PSSA_TRUST GATE }"
      ;;
    "PSSA_TRUST NOSTORE") TRUST_VERDICT="NOSTORE" ;;
    "PSSA_TRUST UNVERIFIABLE") TRUST_VERDICT="UNVERIFIABLE" ;;
    "PSSA_TRUST UNPINNABLE") TRUST_VERDICT="UNPINNABLE" ;;
    *) ;;
    esac
  done <<<"$PSSA_OUTPUT"
  if [[ "$TRUST_VERDICT" == "GATE" && -n "$TRUST_MARKER_NAME" ]]; then
    trust_state_base="${CLAUDE_PLUGIN_DATA:-}"
    if command -v cygpath >/dev/null 2>&1 && [[ "$trust_state_base" == [A-Za-z]:\\* ]]; then
      trust_state_base="$(cygpath -u "$trust_state_base" 2>/dev/null)" || trust_state_base=""
    fi
    [[ -n "$trust_state_base" ]] &&
      TRUST_DIR="${trust_state_base%/}/trust-approvals/$TRUST_MARKER_NAME"
  fi
  if [[ "$TRUST_VERDICT" == "GATE" && -n "$TRUST_DIR" ]]; then
    APPROVE_HINT="Review that file and every rule module it references; to approve this exact settings-and-rule-module content state and enable analysis, run: mkdir -p '$TRUST_DIR' (any change to the settings or a referenced rule module revokes the approval)."
    NOTICE_KEY="powershell-format-trust-${TRUST_DIR##*[/\\]}"
  elif [[ "$TRUST_VERDICT" == "UNVERIFIABLE" ]]; then
    APPROVE_HINT="The settings state cannot be verified (settings unparsable by the restricted data parser, or a declared CustomRulePath entry does not resolve to hashable content), so analysis stays disabled for this repository."
    NOTICE_KEY="powershell-format-trust-unverifiable"
  elif [[ "$TRUST_VERDICT" == "UNPINNABLE" ]]; then
    APPROVE_HINT="A rule module loads code through a target this hook cannot pin to a file (a variable, an env lookup, a composed expression, or an interpolated string it cannot expand), so the code that would execute cannot be bound to an approval and analysis stays disabled for this repository."
    NOTICE_KEY="powershell-format-trust-unpinnable"
  else
    APPROVE_HINT="Approval state is unavailable (CLAUDE_PLUGIN_DATA unset or unusable), so analysis stays disabled for this repository."
    NOTICE_KEY="powershell-format-trust-nostore"
  fi
  if hook::notice_once "$NOTICE_KEY" "$INPUT"; then
    hook::emit_skip_notice PostToolUse \
      "powershell-format trust gate: PSScriptAnalyzer run skipped — $SETTINGS_REL declares CustomRulePath (analysis would load and execute repository-supplied rule modules) or cannot be verified code-free. $APPROVE_HINT"
  fi
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
