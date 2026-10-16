# powershell-format: one PSScriptAnalyzer run over the files one settings file governs.
# Run by git-hooks/powershell-check.sh (pre-commit and end of turn) and by
# hooks/powershell-format.sh (the PostToolBatch row). Everything it reports goes
# to stdout, one record per line, and the exit code says what happened.
#
# Environment:
#   PSSA_SETTINGS    the PSScriptAnalyzerSettings.psd1 that governs every listed file
#   PSSA_ROOT        the repository root the listed paths are relative to
#   PSSA_LIST        a UTF-8 file with one repo-relative path per line
#   PSSA_MODE        analyze (findings only) or both (rewrite, then findings)
#   PSSA_STATE_BASE  the directory that holds trust approvals
#   PSSA_REPO_ROOT   the root text that the trust signature is bound to
#
# Exit codes:
#   0  clean
#   1  findings, printed as "<path>:<line>: [<severity>] <rule>: <message>"
#   3  the PSScriptAnalyzer module is not installed
#   4  Invoke-Formatter or Invoke-ScriptAnalyzer threw ("PSSA_ERROR ..." lines)
#   6  the settings declare CustomRulePath (or could not be verified code-free)
#      and this settings-content state is unapproved ("PSSA_TRUST ..." line)
#
# A file that is neither BOM'd nor valid UTF-8 (legacy ANSI) is skipped whole:
# its bytes cannot round-trip through a rewrite.

# Importing the module is both the presence probe and the load the formatter
# needs; a -ListAvailable scan of every module path costs extra.
try {
    Import-Module PSScriptAnalyzer -ErrorAction Stop
} catch {
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
                "Import-PowerShellDataFile", "Invoke-Command", "Start-Job")
            # Invoke-Expression is its own case: its argument is CODE, not a
            # path, so even a constant string cannot be pinned - the code it
            # evaluates may itself load a file this scan never sees, a
            # dot-source spelled inside the evaluated text. Listing it as a
            # loader pins the code STRING as if it named a file, so
            # `Invoke-Expression 'Import-Module ./evil.psm1'` reads as pinned
            # while the load it really performs is never seen. Binding it
            # would mean recursively parsing evaluated text, so the state is
            # refused instead. A linter rule has no reason to evaluate text.
            $evaluators = @("Invoke-Expression", "iex")
            $cmdAsts = $fileAst.FindAll({
                    param($n) $n -is [System.Management.Automation.Language.CommandAst]
                }, $true)
            foreach ($cmdAst in $cmdAsts) {
                $cmdName = $cmdAst.GetCommandName()
                # A module-qualified name resolves to the same command:
                # `Microsoft.PowerShell.Core\Import-Module` IS Import-Module.
                # GetCommandName returns the qualified spelling as written, so
                # an exact-name membership test never matches it and the load
                # is skipped outright. The bare name after the last qualifier
                # separator is what the membership tests below must see.
                $bareName = $cmdName
                if (-not [string]::IsNullOrEmpty($bareName)) {
                    $bareName = ($bareName -split "[\\/]")[-1]
                }
                if ($evaluators -contains $bareName) {
                    Write-Output "PSSA_TRUST UNPINNABLE"
                    exit 6
                }
                $isLoad = $cmdAst.InvocationOperator -ne
                    [System.Management.Automation.Language.TokenKind]::Unknown
                if (-not $isLoad) {
                    $isLoad = [string]::IsNullOrEmpty($cmdName) -or
                        $loaders -contains $bareName
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
            # `using module ./deps/helper.psm1` and `using assembly
            # ./deps/helper.dll` both load repository code, but are
            # UsingStatementAst nodes rather than commands, so the loop above
            # never sees them - and neither form needs quotes, so the text
            # scan does not either. `using namespace` and `using type` name
            # no repository file and are left alone. The path must be a
            # constant (PowerShell requires one), so a hashtable module
            # specification cannot be pinned and refuses approval.
            $loadKinds = @(
                [System.Management.Automation.Language.UsingStatementKind]::Module,
                [System.Management.Automation.Language.UsingStatementKind]::Assembly)
            $usingAsts = $fileAst.FindAll({
                    param($n) $n -is [System.Management.Automation.Language.UsingStatementAst]
                }, $true)
            foreach ($useAst in $usingAsts) {
                if ($loadKinds -notcontains $useAst.UsingStatementKind) {
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

$settings = $env:PSSA_SETTINGS
$mode = $env:PSSA_MODE
$failed = $false
$found = $false

# Relative CustomRulePath entries in the settings file resolve from the current
# PowerShell location, so anchor at the settings directory and the rule paths
# resolve the way the repository intended.
Set-Location -LiteralPath (Split-Path -Parent $settings)

foreach ($rel in [System.IO.File]::ReadAllLines($env:PSSA_LIST)) {
    if ([string]::IsNullOrWhiteSpace($rel)) { continue }
    $file = Join-Path $env:PSSA_ROOT $rel
    try {
        # Read with BOM detection and remember the encoding so the write-back
        # keeps the original byte shape (UTF-8 with or without BOM, UTF-16).
        # Strict UTF-8 is the BOM-less fallback: a file that fails it cannot be
        # round-tripped safely, so it is skipped.
        $sr = $null
        try {
            $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
            $sr = [System.IO.StreamReader]::new($file, $strictUtf8, $true)
            $original = $sr.ReadToEnd()
            $enc = $sr.CurrentEncoding
        } catch [System.Text.DecoderFallbackException] {
            continue
        } finally {
            if ($sr) { $sr.Dispose() }
        }
        if ($null -eq $original) { $original = "" }

        if ($mode -ne "analyze") {
            $formatted = Invoke-Formatter -ScriptDefinition $original -Settings $settings
            # -cne (case-SENSITIVE) is load-bearing: -ne is case-insensitive, so
            # a casing-only reformat (get-childitem -> Get-ChildItem) would
            # compare equal and never be written back.
            if ($formatted -cne $original) {
                if (-not $formatted.EndsWith("`n")) {
                    $formatted += "`n"
                }
                [System.IO.File]::WriteAllText($file, $formatted, $enc)
            }
        }

        # Invoke-ScriptAnalyzer has no -LiteralPath; -Path treats wildcard
        # metacharacters ([ ] * ?) in a filename as a pattern, so escape the
        # path to match it literally.
        $litFile = [System.Management.Automation.WildcardPattern]::Escape($file)
        foreach ($r in @(Invoke-ScriptAnalyzer -Path $litFile -Settings $settings)) {
            $text = ($r.Message -replace "\s+", " ").Trim()
            Write-Output "${rel}:$($r.Line): [$($r.Severity)] $($r.RuleName): $text"
            $found = $true
        }
    } catch {
        $oneLine = ($_.Exception.Message -replace "\s+", " ").Trim()
        Write-Output "PSSA_ERROR ${rel}: $oneLine"
        $failed = $true
    }
}
if ($failed) { exit 4 }
if ($found) { exit 1 }
exit 0
