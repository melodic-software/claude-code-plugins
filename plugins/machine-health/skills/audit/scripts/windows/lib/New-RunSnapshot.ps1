#Requires -Version 7.4

<#
.SYNOPSIS
Build the RunSnapshot the orchestrator writes to latest.json and prints on
stdout.

.DESCRIPTION
Shape: reference/shared/output-schema.md, "RunSnapshot". Every required field
is always present, so a run that stops early (a held run.lock) still emits a
complete snapshot: empty arrays and duration_seconds 0 by default. The run's
artifact fields (run_stamp, report_path, page_path) are null when not given.
new_finding_keys and discovery_path are present only when DiscoveryPath is
given, which the orchestrator does on a -Scheduled run.
#>

function New-RunSnapshot {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds an in-memory object; changes no system state.')]
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory = $true)] [string] $RunId,
        [Parameter(Mandatory = $true)] [string] $HostName,
        [Parameter(Mandatory = $true)] [string] $OsVersion,
        [Parameter(Mandatory = $true)] [bool] $Elevated,
        [Parameter(Mandatory = $true)] [string] $RunMode,
        [Parameter(Mandatory = $true)] [bool] $DryRun,
        [AllowEmptyCollection()] [object[]] $Checks = @(),
        [AllowEmptyCollection()] [object[]] $Remediations = @(),
        [AllowEmptyCollection()] [object[]] $DiscoveredChecks = @(),
        [AllowEmptyCollection()] [string[]] $UrlsCalled = @(),
        [double] $DurationSeconds = 0,
        [string] $RunStamp,
        [string] $ReportPath,
        [string] $PagePath,
        [int] $CadenceDeferredCount = 0,
        [AllowEmptyCollection()] [string[]] $NewFindingKeys = @(),
        [string] $DiscoveryPath
    )

    $snapshot = [ordered]@{
        run_id             = $RunId
        hostname           = $HostName
        os                 = 'windows'
        os_version         = $OsVersion
        elevated           = $Elevated
        run_mode           = $RunMode
        dry_run            = $DryRun
        powershell_version = $PSVersionTable.PSVersion.ToString()
        checks             = @($Checks)
        remediations       = @($Remediations)
        discovered_checks  = @($DiscoveredChecks)
        urls_called        = @($UrlsCalled)
        duration_seconds   = $DurationSeconds
        run_stamp          = $RunStamp ? $RunStamp : $null
        report_path        = $ReportPath ? $ReportPath : $null
        page_path          = $PagePath ? $PagePath : $null
        cadence_deferred_count = $CadenceDeferredCount
    }
    if ($DiscoveryPath) {
        $snapshot['new_finding_keys'] = $NewFindingKeys
        $snapshot['discovery_path'] = $DiscoveryPath
    }
    return $snapshot
}

# A JSON object's property value, or $null when it is absent; StrictMode 3.0 throws on a missing one.
function Get-SnapshotField($Object, [string] $Name) {
    if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) ? $Object[$Name] : $null }
    if ($null -eq $Object -or $Object -isnot [pscustomobject]) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { $prop.Value } else { $null }
}

# The non-null FindingKeys under each check's detail.items, by check id.
function Get-CheckItemKey {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([AllowNull()] $Check, [switch] $UnmutedOnly)

    $keys = [System.Collections.Generic.List[string]]::new()
    $items = Get-SnapshotField (Get-SnapshotField $Check 'detail') 'items'
    foreach ($item in @($items)) {
        $key = Get-SnapshotField $item 'key'
        if ($key -isnot [string] -or -not $key) { continue }
        if ($UnmutedOnly -and (Get-SnapshotField $item 'muted') -eq $true) { continue }
        $keys.Add($key)
    }
    return , $keys
}

<#
.SYNOPSIS
The FindingKeys this run lists that the previous latest.json did not.

.DESCRIPTION
A check's baseline is its previous checks[] entry, used only when that entry
lists detail.items and is not SKIPPED. An UNKNOWN entry that still listed items
counts: unelevated runs read some checks only in part. A key is new when this run lists it under a
check with a baseline, unmuted, and the baseline does not hold it. A check with
no baseline adds nothing, so a missing or unreadable previous file gives an
empty list. Read before latest.json is overwritten.
#>
function Get-NewFindingKey {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)] [string] $PreviousPath,
        [AllowEmptyCollection()] [object[]] $Checks = @()
    )

    $previous = $null
    try {
        $previous = [System.IO.File]::ReadAllText($PreviousPath) | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return [string[]]@()
    }
    $baseline = @{}
    foreach ($check in @(Get-SnapshotField $previous 'checks')) {
        $id = Get-SnapshotField $check 'id'
        $items = Get-SnapshotField (Get-SnapshotField $check 'detail') 'items'
        if ($id -isnot [string] -or $null -eq $items -or (Get-SnapshotField $check 'severity') -eq 'SKIPPED') { continue }
        $baseline[$id] = [System.Collections.Generic.HashSet[string]]::new([string[]](Get-CheckItemKey $check))
    }
    $new = [System.Collections.Generic.List[string]]::new()
    foreach ($check in $Checks) {
        $id = Get-SnapshotField $check 'id'
        if ($id -isnot [string] -or -not $baseline.ContainsKey($id)) { continue }
        foreach ($key in (Get-CheckItemKey $check -UnmutedOnly)) {
            if (-not $baseline[$id].Contains($key) -and -not $new.Contains($key)) { $new.Add($key) }
        }
    }
    return [string[]]$new.ToArray()
}
