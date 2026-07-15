#Requires -Version 7.4
<#
.SYNOPSIS
Remediation: delete files older than 7 days from user/system temp paths.

.DESCRIPTION
Targets $env:TEMP, $env:LOCALAPPDATA\Temp, C:\Windows\Temp. Emits a
RemediationAttempt JSON object on stdout.

Reparse-point directories (junctions and symlinks) are skipped at descent
time -- see Get-NonReparseFile for why a post-enumeration filter is unsafe.

Locked files are counted in detail.skipped_locked and don't fail the
remediation. Directories are never removed; empty directories remain.
Files in Documents, Desktop, or OneDrive are not in temp paths and
therefore never considered.

Policy: references/windows/remediation-policy.md#2-clear-tempfiles
#>
[CmdletBinding()]
param(
    [int]$AgeDays = 7,
    [switch]$Human
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'

function Test-IsReparsePoint {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory = $true)] $Entry)

    if (-not $Entry.Attributes) { return $false }
    return [bool]([int]$Entry.Attributes -band [int][System.IO.FileAttributes]::ReparsePoint)
}

function Get-NonReparseFile {
    # Manual recursion that refuses to descend into reparse-point directories
    # (junctions and symlinks). Get-ChildItem -Recurse applies its pipeline
    # filter AFTER enumeration, so reparse-point children are already yielded
    # by the time a Where-Object guard sees them. On pwsh 7+, symlinks are
    # gated by -FollowSymlink, but junctions are followed by default -- they
    # are mount points, not symbolic links, and share the same FileAttributes
    # flag. Skipping reparse-point directories at descent time prevents a
    # junction under %TEMP% pointing at, say, C:\Windows from exposing system
    # files as deletion candidates.
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter()] [ref] $ReparseSkipCount
    )

    $queue = [System.Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($Path)
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        try {
            $entries = Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop
        } catch {
            Write-Verbose "Get-NonReparseFile: enumeration failed for '$current'. $($_.Exception.Message)"
            continue
        }
        foreach ($entry in $entries) {
            if (Test-IsReparsePoint -Entry $entry) {
                if ($ReparseSkipCount) { $ReparseSkipCount.Value++ }
                continue
            }
            # Safe container check — Set-StrictMode -Version 3.0 throws on
            # absent properties, and test mocks (pscustomobject fixtures)
            # don't always expose PSIsContainer. A missing property is
            # treated as "not a container" (a plain file), which matches
            # the test mocks' intent.
            $isContainer = $false
            if ($entry.PSObject.Properties['PSIsContainer']) {
                $isContainer = [bool]$entry.PSIsContainer
            }
            if ($isContainer) {
                $queue.Enqueue($entry.FullName)
            } else {
                $entry
            }
        }
    }
}

function Measure-PathUsage {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory = $true)] [string] $Path)

    $total = 0L
    $count = 0
    try {
        Get-NonReparseFile -Path $Path | ForEach-Object {
            $total += $_.Length
            $count++
        }
    } catch {
        Write-Verbose "Measure-PathUsage: enumeration failed for '$Path'. $($_.Exception.Message)"
    }
    return @{ bytes = $total; count = $count }
}

$rawPaths = [System.Collections.Generic.List[string]]::new()
if ($env:TEMP) { $rawPaths.Add($env:TEMP) }
if ($env:LOCALAPPDATA) { $rawPaths.Add((Join-Path $env:LOCALAPPDATA 'Temp')) }
$rawPaths.Add('C:\Windows\Temp')

$paths = @($rawPaths | Sort-Object -Unique | Where-Object { Test-Path -LiteralPath $_ })

$before = @{}
foreach ($p in $paths) { $before[$p] = Measure-PathUsage -Path $p }

$cutoff = (Get-Date).AddDays(-$AgeDays)
$skippedLocked = 0
$skippedReparse = 0
$deletedCount = 0
$deletedBytes = 0L
$errorMessages = [System.Collections.Generic.List[string]]::new()

$skipCounter = [ref]$skippedReparse
foreach ($p in $paths) {
    try {
        Get-NonReparseFile -Path $p -ReparseSkipCount $skipCounter |
            Where-Object { $_.LastWriteTime -lt $cutoff } |
            ForEach-Object {
                $size = $_.Length
                try {
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                    $deletedCount++
                    $deletedBytes += $size
                } catch {
                    $skippedLocked++
                }
            }
    } catch {
        $errorMessages.Add("Scan of '$p' failed: $($_.Exception.Message)")
    }
}
$skippedReparse = $skipCounter.Value

$after = @{}
foreach ($p in $paths) { $after[$p] = Measure-PathUsage -Path $p }

$attempt = [ordered]@{
    id           = 'clear-temp-files'
    target       = ($paths -join ';')
    finding_id   = 'disk-space'
    attempted_at = (Get-Date).ToString('o')
    succeeded    = ($errorMessages.Count -eq 0)
    before       = @{ paths = $before }
    after        = @{
        paths           = $after
        skipped_locked  = $skippedLocked
        skipped_reparse = $skippedReparse
        deleted_count   = $deletedCount
    }
    bytes_freed  = [int64]$deletedBytes
    error        = if ($errorMessages.Count -gt 0) {
        $errorMessages -join '; '
    } else { $null }
}

if ($Human) {
    $mb = [math]::Round($deletedBytes / 1MB, 1)
    Write-Output ("[clear-temp-files] deleted $deletedCount files ($mb MB); " +
        "skipped-locked $skippedLocked; skipped-reparse $skippedReparse")
    foreach ($p in $paths) {
        $b = $before[$p].bytes
        $a = $after[$p].bytes
        $bmb = [math]::Round($b / 1MB, 1)
        $amb = [math]::Round($a / 1MB, 1)
        Write-Output "  $p : $bmb MB -> $amb MB"
    }
} else {
    $attempt | ConvertTo-Json -Depth 10 -Compress
}
