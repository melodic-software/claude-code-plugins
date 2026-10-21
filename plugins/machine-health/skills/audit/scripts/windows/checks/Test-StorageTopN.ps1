#Requires -Version 7.4
<#
.SYNOPSIS
Check: the largest folders under the user profile and the reclaim locations.
Emits a CheckResult JSON on stdout.

See reference/windows/check-catalog.md#20-storage-top-n for rubric.

.DESCRIPTION
Sizes the folders directly under each root through Measure-FolderSize and
lists the largest per root as FindingItems of kind 'folder'. The roots, the
never-descend rule and the budget are stated in that catalog section.
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = '$FailureSummary, $PassThru, $CheckBody and $result are read by the dot-sourced Invoke-HealthCheckEnvelope.ps1.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter', '',
    Justification = '-Human is read by the dot-sourced envelope and -MutedKeys inside $CheckBody, which the analyzer does not follow.')]
param(
    [switch]$Human,
    [AllowNull()] [AllowEmptyCollection()] [string[]]$MutedKeys = @(),
    # Test-only: replaces the default roots, which then carry no reclaim hint.
    # The orchestrator never passes it (Get-CheckArgument does not offer it).
    [string[]]$RootPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')
. (Join-Path $PSScriptRoot '..\lib\New-FindingItem.ps1')
. (Join-Path $PSScriptRoot '..\lib\Measure-FolderSize.ps1')

function Get-StorageRoot {
    <#
    .SYNOPSIS
    The roots to size, in scan order, each with its reclaim hint. Path is the
    exact string passed to Measure-FolderSize, which hands it back as `input`.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $candidates = @(
        @{ Base = $env:TEMP; Child = $null; Hint = 'temp' }
        @{ Base = $env:SystemDrive; Child = "`$Recycle.Bin\$sid"; Hint = 'recycle-bin' }
        @{ Base = $env:ProgramData; Child = 'Package Cache'; Hint = 'package-cache' }
        @{ Base = $env:SystemDrive; Child = 'Windows.old'; Hint = 'windows-old' }
        @{ Base = $env:USERPROFILE; Child = $null; Hint = $null }
    )
    foreach ($c in $candidates) {
        if ([string]::IsNullOrWhiteSpace($c.Base)) { continue }
        $base = $c.Base.EndsWith(':') ? "$($c.Base)\" : $c.Base
        [pscustomobject]@{ Path = ($c.Child ? (Join-Path $base $c.Child) : $base); Hint = $c.Hint }
    }
}

function Format-ByteSize {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] [long] $Bytes)
    if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} MB' -f ($Bytes / 1MB) }
    return '{0:N0} KB' -f [math]::Ceiling($Bytes / 1KB)
}

$id = 'storage-top-n'
$category = 'storage'
# The scan's three limits, held here once and passed to Measure-FolderSize.
$budgetMs = 60000
$topN = 15
$allocatedFileCap = 10000
$commands = @(
    ("[System.IO.DirectoryInfo]::new(`$env:USERPROFILE).EnumerateFileSystemInfos('*', `$opts)" +
        "  # manual stack, AttributesToSkip 0x{0:X}, top {1} per root" -f [long]$script:PlaceholderSkipMask, $topN)
    "GetCompressedFileSizeW(<file>)  # allocated pass, listed folders of at most $allocatedFileCap files"
)

$FailureSummary = 'Storage top-N check failed.'
$PassThru = $false
$CheckBody = {
    $rootList = if ($RootPath) {
        @($RootPath | ForEach-Object { [pscustomobject]@{ Path = $_; Hint = $null } })
    } else {
        @(Get-StorageRoot)
    }
    # Keyed by the exact string passed in, which every record returns as `input`.
    $hintByInput = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($r in $rootList) { $hintByInput[$r.Path] = $r.Hint }

    $scan = Measure-FolderSize -Root @($rootList.Path) -Top $topN -AllocatedFileCap $allocatedFileCap `
        -Budget (New-ScanBudget -Milliseconds $budgetMs)

    $items = foreach ($f in $scan.folders) {
        $hint = $hintByInput.ContainsKey($f.input) ? $hintByInput[$f.input] : $null
        $title = $f.skip_reason ? "$($f.path) (skipped: cloud sync root)" : "$($f.path) ($(Format-ByteSize $f.logical_bytes))"
        New-FindingItem -Kind 'folder' -Identity @($f.path) -Severity 'INFO' -Title $title -MutedKeys $MutedKeys -Fields @{
            path            = $f.path
            root            = $f.root
            logical_bytes   = $f.logical_bytes
            allocated_bytes = $f.allocated_bytes
            file_count      = $f.file_count
            complete        = $f.complete
            reclaim_hint    = $hint
            skip_reason     = $f.skip_reason
        }
    }
    $items = @($items)

    # A root nested in another scanned root (%TEMP% under the profile) is
    # already inside that root's total, so it is left out of scanned_bytes.
    $scanned = @($scan.roots | Where-Object { $_.status -eq 'scanned' })
    $scannedBytes = [long]0
    foreach ($r in $scanned) {
        $nested = @($scanned | Where-Object { $_.path -ne $r.path -and (Test-PathUnder -Path $r.path -Parent $_.path) })
        if ($nested.Count -eq 0) { $scannedBytes += $r.logical_bytes }
    }
    $sized = @($items | Where-Object { $null -ne $_.logical_bytes } | Sort-Object -Property logical_bytes -Descending)
    $top1 = $sized.Count -gt 0 ? $sized[0] : $null

    $detail = @{
        scanned_bytes        = $scannedBytes
        top1_bytes           = $top1 ? [long]$top1.logical_bytes : [long]0
        scan_complete        = [bool]$scan.scan_complete
        allocated_complete   = [bool]$scan.allocated_complete
        inaccessible_count   = [int]$scan.inaccessible_count
        skipped_reparse_dirs = [int]$scan.skipped_reparse_dirs
        skipped_sync_roots   = [int]$scan.skipped_sync_roots
        items_count          = $items.Count
        muted_count          = @($items | Where-Object { $_.muted }).Count
        roots                = @($scan.roots | ForEach-Object {
                [ordered]@{
                    path          = $_.path
                    status        = $_.status
                    logical_bytes = $_.logical_bytes
                    file_count    = $_.file_count
                    complete      = $_.complete
                    reclaim_hint  = $hintByInput.ContainsKey($_.input) ? $hintByInput[$_.input] : $null
                }
            })
        items                = $items
    }

    # Every item is INFO, so an unmuted item makes the check INFO. With every
    # item muted, a scan the budget cut cannot vouch for OK.
    $severity = Get-UnmutedSeverity -Items $items
    if ($severity -eq 'OK' -and -not $scan.scan_complete) { $severity = 'UNKNOWN' }

    $state = $scan.scan_complete ? 'scan complete' : "scan cut at the $($budgetMs / 1000) s budget"
    $summary = if ($top1) {
        $lead = "Largest folder $(Format-ByteSize $top1.logical_bytes): "
        $tail = "; $($items.Count) item(s) listed, $state."
        $room = 240 - $lead.Length - $tail.Length
        $name = $top1.path.Length -le $room ? $top1.path : ('...' + $top1.path.Substring($top1.path.Length - ($room - 3)))
        "$lead$name$tail"
    } else {
        "No folders sized; $($items.Count) item(s) listed, $state."
    }

    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity $severity -Summary $summary -Commands $commands -Detail $detail `
        -NeedsAdmin $false -RanSuccessfully $true
}
. (Join-Path $PSScriptRoot '..\lib\Invoke-HealthCheckEnvelope.ps1')
