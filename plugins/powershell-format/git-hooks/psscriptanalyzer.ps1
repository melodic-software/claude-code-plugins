# Exit codes:
#   0  clean
#   3  the PSScriptAnalyzer module is not installed
#   4  Invoke-Formatter or Invoke-ScriptAnalyzer threw ("PSSA_ERROR ..." lines)
#   6  the settings declare CustomRulePath (or could not be verified code-free)
#      and this settings-content state is unapproved ("PSSA_TRUST ..." line)

$mode = $args[0]
$targets = @($args | Select-Object -Skip 1)
$runDir = (Get-Location).ProviderPath

try {
    Import-Module PSScriptAnalyzer -ErrorAction Stop
} catch {
    exit 3
}

function exitTrust([string]$verdict) {
    Write-Output "PSSA_TRUST $verdict"
    exit 6
}
try {
    $sd = Import-PowerShellDataFile -LiteralPath $env:PSSA_SETTINGS -ErrorAction Stop
} catch {
    $sd = $null
}
if (-not ($sd -is [hashtable])) { exitTrust UNVERIFIABLE }
$settingsDir = Split-Path -Parent $env:PSSA_SETTINGS
if ($sd.ContainsKey("CustomRulePath")) {
    $ruleFiles = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in @($sd["CustomRulePath"])) {
        if (-not ($entry -is [string]) -or [string]::IsNullOrWhiteSpace($entry)) {
            exitTrust UNVERIFIABLE
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
            exitTrust UNVERIFIABLE
        }
    }
    if ($ruleFiles.Count -gt 512) { exitTrust UNVERIFIABLE }
    $sq = [char]39
    $dq = [char]34
    $litPattern = "$sq([^$sq]+)$sq|$dq([^$dq]+)$dq"
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
    $loaders = @("Import-Module", "ipmo", "Add-Type", "New-Module",
        "Import-PowerShellDataFile", "Invoke-Command", "Start-Job")
    $evaluators = @("Invoke-Expression", "iex")
    $loadKinds = @(
        [System.Management.Automation.Language.UsingStatementKind]::Module,
        [System.Management.Automation.Language.UsingStatementKind]::Assembly)
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
        if ($scanned -gt 256 -or $allFiles.Count -gt 512) { exitTrust UNVERIFIABLE }
        $curDir = Split-Path -Parent $cur
        try { $text = [System.IO.File]::ReadAllText($cur) } catch { exitTrust UNVERIFIABLE }
        $pending = [System.Collections.Generic.List[string]]::new()

        if ($cur -match "\.ps(m|d)?1$") {
            $perrs = $null
            $fileAst = [System.Management.Automation.Language.Parser]::ParseInput(
                $text, [ref]$null, [ref]$perrs)
            if ($null -eq $fileAst -or ($null -ne $perrs -and $perrs.Count -gt 0)) {
                exitTrust UNVERIFIABLE
            }
            $cmdAsts = $fileAst.FindAll({
                    param($n) $n -is [System.Management.Automation.Language.CommandAst]
                }, $true)
            foreach ($cmdAst in $cmdAsts) {
                $cmdName = $cmdAst.GetCommandName()
                $bareName = $cmdName
                if (-not [string]::IsNullOrEmpty($bareName)) {
                    $bareName = ($bareName -split "[\\/]")[-1]
                }
                if ($evaluators -contains $bareName) { exitTrust UNPINNABLE }
                $isLoad = $cmdAst.InvocationOperator -ne
                    [System.Management.Automation.Language.TokenKind]::Unknown
                if (-not $isLoad) {
                    $isLoad = [string]::IsNullOrEmpty($cmdName) -or
                        $loaders -contains $bareName
                }
                if (-not $isLoad) { continue }
                if ($cmdAst.Parent -is [System.Management.Automation.Language.PipelineAst] -and
                    $cmdAst.Parent.PipelineElements.Count -gt 1 -and
                    -not [object]::ReferenceEquals($cmdAst.Parent.PipelineElements[0], $cmdAst)) {
                    exitTrust UNPINNABLE
                }
                foreach ($el in $cmdAst.CommandElements) {
                    if ($el -is [System.Management.Automation.Language.CommandParameterAst]) { continue }
                    if ($el -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                        [void]$pending.Add($el.Value)
                        continue
                    }
                    if ($el -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { continue }
                    if ($el -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
                        $target = expandKnownVars $el.Value $curDir $cur
                        if (-not $target.Contains("`$")) {
                            [void]$pending.Add($target)
                            continue
                        }
                    }
                    exitTrust UNPINNABLE
                }
            }
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
                exitTrust UNPINNABLE
            }
        }
        foreach ($hit in [regex]::Matches($text, $litPattern)) {
            $lit = if ($hit.Groups[1].Success) { $hit.Groups[1].Value } else { $hit.Groups[2].Value }
            if ([string]::IsNullOrWhiteSpace($lit) -or $lit.Contains("`n")) { continue }
            [void]$pending.Add($lit)
            if ($lit.Contains("`$")) {
                $expanded = expandKnownVars $lit $curDir $cur
                if ($expanded -ne $lit) { [void]$pending.Add($expanded) }
            }
        }
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
        } catch { exitTrust UNVERIFIABLE }
        [void]$manifest.AppendLine("$target`t$h")
    }
    if ([string]::IsNullOrEmpty($env:PSSA_STATE_BASE)) { exitTrust NOSTORE }
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $sigBytes = $sha.ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes($manifest.ToString()))
        } finally {
            $sha.Dispose()
        }
        $signature = -join ($sigBytes | ForEach-Object { $_.ToString("x2") })
    } catch {
        $signature = ""
    }
    if ([string]::IsNullOrEmpty($signature)) { exitTrust UNVERIFIABLE }
    $trustDir = Join-Path $env:PSSA_STATE_BASE "trust-approvals" "pssa-$signature"
    if (-not (Test-Path -LiteralPath $trustDir -PathType Container)) {
        exitTrust "GATE pssa-$signature"
    }
}

$settings = $env:PSSA_SETTINGS
$lintOut = if ($mode -eq "format") { $env:PSSA_LINT_OUT } else { "" }

Set-Location -LiteralPath $settingsDir

function readSource([string]$file) {
    $sr = $null
    try {
        $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
        $detectBom = $true
        $sr = [System.IO.StreamReader]::new($file, $strictUtf8, $detectBom)
        $text = $sr.ReadToEnd()
        if ($null -eq $text) { $text = "" }
        return @{ Text = $text; Encoding = $sr.CurrentEncoding }
    } catch [System.Text.DecoderFallbackException] {
        return $null
    } finally {
        if ($sr) { $sr.Dispose() }
    }
}

function formatFile([string]$file) {
    $src = readSource $file
    if ($null -eq $src) { return }
    $formatted = Invoke-Formatter -ScriptDefinition $src.Text -Settings $settings
    $changedEvenInCaseOnly = $formatted -cne $src.Text
    if ($changedEvenInCaseOnly) {
        if (-not $formatted.EndsWith("`n")) {
            $formatted += "`n"
        }
        [System.IO.File]::WriteAllText($file, $formatted, $src.Encoding)
    }
}

function lintFile([string]$file, [string]$rel) {
    if ($null -eq (readSource $file)) { return }
    $pathNotWildcard = [System.Management.Automation.WildcardPattern]::Escape($file)
    foreach ($r in @(Invoke-ScriptAnalyzer -Path $pathNotWildcard -Settings $settings)) {
        $text = ($r.Message -replace "\s+", " ").Trim()
        "${rel}:$($r.Line): [$($r.Severity)] $($r.RuleName): $text"
    }
}

function errorLine([string]$rel, $err) {
    $oneLine = ($err.Exception.Message -replace "\s+", " ").Trim()
    "PSSA_ERROR ${rel}: $oneLine"
}

$files = [System.Collections.Generic.List[object]]::new()
foreach ($rel in $targets) {
    if ([string]::IsNullOrWhiteSpace($rel)) { continue }
    $file = $rel
    if (-not [System.IO.Path]::IsPathRooted($file)) { $file = Join-Path $runDir $rel }
    $files.Add(@{ Rel = $rel; File = $file })
}

$formatFailed = $false
if ($mode -eq "format") {
    foreach ($t in $files) {
        try {
            formatFile $t.File
        } catch {
            Write-Output (errorLine $t.Rel $_)
            $formatFailed = $true
        }
    }
    $settingsFull = [System.IO.Path]::GetFullPath($settings)
    $settingsFormatted = @($files | Where-Object {
            [string]::Equals([System.IO.Path]::GetFullPath($_.File), $settingsFull,
                [System.StringComparison]::OrdinalIgnoreCase)
        }).Count -gt 0
    $gateSignedBytesFormatMayHaveChanged = $sd.ContainsKey("CustomRulePath") -or $settingsFormatted
    if ($gateSignedBytesFormatMayHaveChanged) { $lintOut = "" }
}

$lintLines = [System.Collections.Generic.List[string]]::new()
$lintFailed = $false
$lintFound = $false
foreach ($t in $files) {
    if ($mode -eq "format" -and -not $lintOut) { break }
    $rel = $t.Rel
    $file = $t.File
    try {
        foreach ($line in @(lintFile $file $rel)) {
            $lintLines.Add($line)
            $lintFound = $true
        }
    } catch {
        $lintLines.Add((errorLine $rel $_))
        $lintFailed = $true
    }
}
$lintRc = if ($lintFailed) { 4 } elseif ($lintFound) { 1 } else { 0 }
if ($mode -ne "format") {
    $lintLines
    exit $lintRc
}
if ($lintOut) {
    [System.IO.File]::AppendAllLines($lintOut, $lintLines)
    [System.IO.File]::AppendAllText("$lintOut.rc", "$lintRc`n")
}
if ($formatFailed) { exit 4 }
exit 0
