#Requires -Version 7.4

<#
.SYNOPSIS
Read Defender detections (events 1116/1117) and exclusion changes (event 5007)
from the Defender Operational log, which a standard user can read.

.DESCRIPTION
Defender's threat-detection cmdlets forget detections after the scan-history purge delay, so
detection history comes from the event log instead, back to the log's oldest
retained record.

Returns { ReadState, LogOldestRecord, Detections, ExclusionChanges }:

 - ReadState: ok | absent | denied | error. A query that finds no matching
   event is absent (zero), not an error; a missing log is an error.
 - Detections: one per (threat id, resource), at its latest 1116. A 1117 pairs
   with it when it carries the same threat id and resource and is no older.
   ActionSucceeded is true when that 1117's action remediates (Clean,
   Quarantine, Remove, Block), false for any other action, and $null when no
   1117 paired.
 - ExclusionChanges: 5007 changes under the Defender Exclusions registry keys,
   with Type path | extension | process and Change added | removed.

EventData is read by field name from ToXml(); localized message and action text
never leaves this file.
#>

$script:DefenderEventLogName = 'Microsoft-Windows-Windows Defender/Operational'
$script:DefenderEventIds = @(1116, 1117, 5007)

# Remediating action ids: the Set-MpPreference threat action table.
$script:DefenderRemediatingActionIds = @(1, 2, 3, 10)

$script:DefenderExclusionTypes = @{ Paths = 'path'; Extensions = 'extension'; Processes = 'process' }

function Get-DefenderEventData {
    param([Parameter(Mandatory)] $Record)
    $data = @{}
    foreach ($node in @(([xml]$Record.ToXml()).Event.EventData.Data)) {
        if ($node -and $node.Name) { $data[$node.Name] = $node.InnerText }
    }
    return $data
}

function ConvertFrom-DefenderExclusionValue {
    param([AllowEmptyString()] [string] $Text)
    if ($Text -match '\\Exclusions\\(?<kind>Paths|Extensions|Processes)\\(?<value>.+) = \S+$') {
        return [pscustomobject]@{ Type = $script:DefenderExclusionTypes[$Matches.kind]; Value = $Matches.value }
    }
    return $null
}

function Get-DefenderEventHistory {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $readState = 'ok'
    $records = @()
    try {
        $records = @(Get-WinEvent -FilterHashtable @{ LogName = $script:DefenderEventLogName; Id = $script:DefenderEventIds } -ErrorAction Stop)
    } catch [System.UnauthorizedAccessException] {
        $readState = 'denied'
    } catch {
        $readState = $_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*' ? 'absent' : 'error'
        Write-Verbose "Get-DefenderEventHistory: $($_.FullyQualifiedErrorId)"
    }

    $oldest = $null
    try {
        $oldest = (Get-WinEvent -LogName $script:DefenderEventLogName -Oldest -MaxEvents 1 -ErrorAction Stop).TimeCreated
    } catch {
        Write-Verbose "Get-DefenderEventHistory: oldest record unreadable. $($_.Exception.Message)"
    }

    $detected = @{}
    $actions = [System.Collections.Generic.List[object]]::new()
    $changes = [System.Collections.Generic.List[object]]::new()
    foreach ($record in $records) {
        $data = Get-DefenderEventData -Record $record
        switch ($record.Id) {
            1116 {
                $pairKey = "$($data['Threat ID'])|$($data['Path'])"
                $prior = $detected[$pairKey]
                if ($null -eq $prior -or $record.TimeCreated -gt $prior.DetectedAt) {
                    $detected[$pairKey] = [pscustomobject]@{
                        ThreatId   = $data['Threat ID']
                        ThreatName = $data['Threat Name']
                        Resource   = $data['Path']
                        DetectedAt = $record.TimeCreated
                    }
                }
            }
            1117 {
                $actions.Add([pscustomobject]@{
                        PairKey   = "$($data['Threat ID'])|$($data['Path'])"
                        At        = $record.TimeCreated
                        Succeeded = [int]$data['Action ID'] -in $script:DefenderRemediatingActionIds
                    })
            }
            5007 {
                $added = ConvertFrom-DefenderExclusionValue -Text $data['New Value']
                $removed = ConvertFrom-DefenderExclusionValue -Text $data['Old Value']
                $entry = $added ?? $removed
                if ($entry) {
                    $changes.Add([pscustomobject]@{
                            Type      = $entry.Type
                            Value     = $entry.Value
                            Change    = $added ? 'added' : 'removed'
                            ChangedAt = $record.TimeCreated
                        })
                }
            }
        }
    }

    $detections = foreach ($pairKey in $detected.Keys) {
        $detection = $detected[$pairKey]
        $paired = @($actions | Where-Object { $_.PairKey -eq $pairKey -and $_.At -ge $detection.DetectedAt })
        $succeeded = if ($paired.Count -eq 0) { $null } else { [bool]($paired | Where-Object Succeeded) }
        [pscustomobject]@{
            ThreatId        = $detection.ThreatId
            ThreatName      = $detection.ThreatName
            Resource        = $detection.Resource
            DetectedAt      = $detection.DetectedAt
            ActionSucceeded = $succeeded
        }
    }

    return [pscustomobject]@{
        ReadState        = $readState
        LogOldestRecord  = $oldest
        Detections       = @($detections | Sort-Object DetectedAt -Descending)
        ExclusionChanges = @($changes | Sort-Object ChangedAt -Descending)
    }
}
