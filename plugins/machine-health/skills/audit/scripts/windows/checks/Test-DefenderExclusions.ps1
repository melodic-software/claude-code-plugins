#Requires -Version 7.4
<#
.SYNOPSIS
Check: Windows Defender exclusion audit. Emits a CheckResult JSON on stdout.
#>
[CmdletBinding()]
param([switch]$Human)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')
. (Join-Path $PSScriptRoot '..\lib\Test-IsElevated.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$id = 'defender-exclusions'
$category = 'security'
$commands = @(
    'Get-MpPreference | Select-Object ExclusionPath, ExclusionExtension, ExclusionProcess'
)

# Well-known benign exclusions common on dev machines (.NET, Node, Python
# test runners, build caches). The aim is to WARN only on unexpected entries.
$knownSafePaths = @(
    '*\NuGetScratch*'
    '*\node_modules*'
    '*\.dotnet*'
    '*\dotnet-install*'
    '*\.cache*'
    '*\Visual Studio\Packages*'
)

# Admin-gated detail fields. Declared once and reused across the three
# UNKNOWN result paths so adding a field updates one list, not three.
$adminFieldList = @(
    'exclusion_path_count'
    'exclusion_extension_count'
    'exclusion_process_count'
    'unexpected_path_count'
)

try {
    # Non-elevated Get-MpPreference returns "N/A: Must be administrator..." as
    # a literal string for the exclusion fields -- gate stops it being counted.
    $elevated = Test-IsElevated
    if (-not $elevated) {
        $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
            -Severity 'UNKNOWN' `
            -Summary 'Defender exclusions require admin (re-run elevated).' `
            -Detail @{ elevated = $false } `
            -Commands $commands `
            -NeedsAdmin $true -RanSuccessfully $false `
            -ErrorMessage 'needs_admin' `
            -DurationMs ([int]$sw.ElapsedMilliseconds) `
            -AdminFields $adminFieldList
    } else {
        $pref = $null
        try { $pref = Get-MpPreference -ErrorAction Stop } catch {
            Write-Verbose "Test-DefenderExclusions: Get-MpPreference failed ($($_.Exception.Message))."
        }

        if ($null -eq $pref) {
            $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
                -Severity 'UNKNOWN' -Summary 'Get-MpPreference unavailable (third-party AV?).' `
                -Commands $commands -RanSuccessfully $false `
                -NeedsAdmin $true `
                -ErrorMessage 'Defender preference API not accessible.' `
                -DurationMs ([int]$sw.ElapsedMilliseconds) `
                -AdminFields $adminFieldList
        } else {
            $paths = @($pref.ExclusionPath)
            $exts = @($pref.ExclusionExtension)
            $procs = @($pref.ExclusionProcess)

            $unexpectedPaths = @($paths | Where-Object {
                    $p = $_
                    $matched = $false
                    foreach ($pattern in $knownSafePaths) {
                        if ($p -like $pattern) { $matched = $true; break }
                    }
                    -not $matched
                })

            $severity = 'OK'
            $summary = "$($paths.Count) path exclusion(s), $($exts.Count) extension(s), $($procs.Count) process(es)."
            if ($unexpectedPaths.Count -gt 0) {
                $severity = 'WARN'
                $summary = "$($unexpectedPaths.Count) unexpected Defender path exclusion(s)."
            } elseif ($paths.Count -gt 0 -or $exts.Count -gt 0 -or $procs.Count -gt 0) {
                $severity = 'INFO'
            }

            $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
                -Severity $severity -Summary $summary -Commands $commands `
                -Detail @{
                exclusion_path_count      = $paths.Count
                exclusion_extension_count = $exts.Count
                exclusion_process_count   = $procs.Count
                unexpected_path_count     = $unexpectedPaths.Count
                unexpected_paths          = @($unexpectedPaths | Select-Object -First 20)
            } `
                -NeedsAdmin $true -RanSuccessfully $true `
                -DurationMs ([int]$sw.ElapsedMilliseconds)
        }
    }
} catch {
    # Outer-catch fallback must keep admin-gate metadata so unexpected
    # failures don't get misclassified as non-admin downstream.
    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity 'UNKNOWN' -Summary 'Defender exclusion check failed.' -Commands $commands `
        -RanSuccessfully $false -ErrorMessage $_.Exception.Message `
        -NeedsAdmin $true `
        -DurationMs ([int]$sw.ElapsedMilliseconds) `
        -AdminFields $adminFieldList
}

$sw.Stop()
$result.duration_ms = [int]$sw.ElapsedMilliseconds
$result | Write-HealthResult -Human:$Human
