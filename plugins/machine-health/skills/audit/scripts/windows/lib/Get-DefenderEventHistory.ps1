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
   with it when it carries that 1116's threat id and detection id; the 1117's
   Path can differ from the 1116's, so the resource is not part of the pair.
   ActionSucceeded is true when a paired 1117's action remediates, false for
   any other action, and $null when no 1117 paired. An empty threat id or path
   reads as a fixed marker.
 - ExclusionChanges: the latest 5007 change per (type, value) under the
   Defender Exclusions registry keys, with Type path | extension | process and
   Change added | removed.

EventData is read by field name from ToXml(); localized message and action text
never leaves this file.
#>

$script:DefenderEventLogName = 'Microsoft-Windows-Windows Defender/Operational'
$script:DefenderEventIds = @(1116, 1117, 5007)

# Remediating action ids: the Set-MpPreference threat action table.
$script:DefenderRemediatingActionIds = @(1, 2, 3, 10)

# Stands in for an empty Threat ID or Path, so a sparse event still yields a usable item key.
$script:DefenderMissingField = '(not recorded)'

$script:DefenderExclusionTypes =@{ Paths = 'path'; Extensions = 'extension'; Processes = 'process' }

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
    $changes = @{}
    foreach ($record in $records) {
        $data = Get-DefenderEventData -Record $record
        switch ($record.Id) {
            1116 {
                $threatId = $data['Threat ID'] ? $data['Threat ID'] : $script:DefenderMissingField
                $resource = $data['Path'] ? $data['Path'] : $script:DefenderMissingField
                $groupKey = "$threatId|$resource"
                $prior = $detected[$groupKey]
                if ($null -eq $prior -or $record.TimeCreated -gt $prior.DetectedAt) {
                    $detected[$groupKey] = [pscustomobject]@{
                        ThreatId    = $threatId
                        ThreatName  = $data['Threat Name']
                        Resource    = $resource
                        DetectedAt  = $record.TimeCreated
                        DetectionId = $data['Detection ID']
                    }
                }
            }
            1117 {
                $actions.Add([pscustomobject]@{
                        ThreatId    = $data['Threat ID']
                        DetectionId = $data['Detection ID']
                        Succeeded   = [int]$data['Action ID'] -in $script:DefenderRemediatingActionIds
                    })
            }
            5007 {
                $added = ConvertFrom-DefenderExclusionValue -Text $data['New Value']
                $removed = ConvertFrom-DefenderExclusionValue -Text $data['Old Value']
                $entry = $added ?? $removed
                $changeKey = $entry ? "$($entry.Type)|$($entry.Value)".ToLowerInvariant() : $null
                if ($entry -and ($null -eq $changes[$changeKey] -or $record.TimeCreated -gt $changes[$changeKey].ChangedAt)) {
                    $changes[$changeKey] = ([pscustomobject]@{
                            Type      = $entry.Type
                            Value     = $entry.Value
                            Change    = $added ? 'added' : 'removed'
                            ChangedAt = $record.TimeCreated
                        })
                }
            }
        }
    }

    $detections = foreach ($groupKey in $detected.Keys) {
        $detection = $detected[$groupKey]
        $paired = @($actions | Where-Object {
                $_.DetectionId -and $_.DetectionId -eq $detection.DetectionId -and $_.ThreatId -eq $detection.ThreatId
            })
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
        ExclusionChanges = @($changes.Values | Sort-Object ChangedAt -Descending)
    }
}
