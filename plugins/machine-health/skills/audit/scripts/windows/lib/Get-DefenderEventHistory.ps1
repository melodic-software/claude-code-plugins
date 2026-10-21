#Requires -Version 7.4

<#
.SYNOPSIS
Read Defender detections (events 1116/1117) and exclusion changes (event 5007)
from the Defender Operational log, which a standard user can read.

.DESCRIPTION
Defender's threat-detection cmdlets forget detections after the scan-history
purge delay (Set-MpPreference -ScanPurgeItemsAfterDelay), so detection history
comes from the event log instead, back to the log's oldest retained record.
EventData is read by field name from ToXml(); localized message and action text
never leaves this file.

Returns { ReadState, LogOldestRecord, SkippedRecords, Detections, ExclusionChanges }:

 - ReadState: ok | absent | denied | error. A query that finds no matching
   event is absent (zero), not an error; a missing log is an error. A record
   that cannot be parsed is skipped and counted in SkippedRecords, and any skip
   makes the read error while the parsed records still count.
 - Detections: one per (threat id, resource, detection id), at that
   detection's latest 1116. A 1117 pairs with it by threat id and detection id;
   a 1117's Path can differ from its 1116's, so the resource is not part of the
   pair. ActionSucceeded is true when a paired 1117's action id is a
   remediating action in the Set-MpPreference threat action table (verified
   against 1117 events whose Action Name matched), false for any other action,
   and $null when no 1117 paired. An empty threat id or path reads as a fixed
   marker, and an empty detection id falls back to the detection time, so
   sparse events never share an identity. ThreatName and Resource are machine
   text: control characters become spaces and the length is capped.
 - ExclusionChanges: the latest 5007 change per (type, value) under the
   Defender Exclusions registry keys, with Type from the shared exclusion type
   map and Change added | removed. Only the Paths, Extensions and Processes
   keys are read; TemporaryPaths and IpAddresses are out of scope.

Event ids and fields: the Defender Antivirus event reference,
https://learn.microsoft.com/en-us/defender-endpoint/troubleshoot-microsoft-defender-antivirus#event-id-1116
(as of 2026-10-21; recheck when a Defender platform release renames these
EventData fields or adds a remediating action).
#>

. (Join-Path $PSScriptRoot 'New-DefenderExclusionItem.ps1')

$script:DefenderEventLogName = 'Microsoft-Windows-Windows Defender/Operational'
$script:DefenderEventIds = @(1116, 1117, 5007)

# Remediating action ids (Clean, Quarantine, Remove, Block): the Set-MpPreference threat action table.
$script:DefenderRemediatingActionIds = @(1, 2, 3, 10)

# Stands in for an empty Threat ID or Path, so a sparse event still yields a usable item key.
$script:DefenderMissingField = '(not recorded)'

# Longest threat name or resource carried out of this file (judgment: the classic Windows MAX_PATH).
$script:DefenderTextMaxLength = 260

function ConvertTo-DefenderText {
    param([AllowNull()] [AllowEmptyString()] [string] $Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $clean = [regex]::Replace($Text, '[\p{Cc}\p{Cf}]', ' ')
    if ($clean.Length -gt $script:DefenderTextMaxLength) { $clean = $clean.Substring(0, $script:DefenderTextMaxLength) }
    return $clean
}

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
    $keys = $script:DefenderExclusionTypes.Keys -join '|'
    if ($Text -match "\\Exclusions\\(?<kind>$keys)\\(?<value>.+) = \S+$") {
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
    $skipped = 0
    foreach ($record in $records) {
        try {
            $data = Get-DefenderEventData -Record $record
            switch ($record.Id) {
                1116 {
                    $threatId = $data['Threat ID'] ? $data['Threat ID'] : $script:DefenderMissingField
                    $resource = $data['Path'] ? (ConvertTo-DefenderText $data['Path']) : $script:DefenderMissingField
                    $detectionId = $data['Detection ID'] ? $data['Detection ID'] : ([datetime]$record.TimeCreated).ToString('o')
                    $groupKey = "$threatId|$resource|$detectionId"
                    $prior = $detected[$groupKey]
                    if ($null -eq $prior -or $record.TimeCreated -gt $prior.DetectedAt) {
                        $detected[$groupKey] = [pscustomobject]@{
                            ThreatId    = $threatId
                            ThreatName  = ConvertTo-DefenderText $data['Threat Name']
                            Resource    = $resource
                            DetectionId = $detectionId
                            DetectedAt  = [datetime]$record.TimeCreated
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
                        $changes[$changeKey] = [pscustomobject]@{
                            Type      = $entry.Type
                            Value     = $entry.Value
                            Change    = $added ? 'added' : 'removed'
                            ChangedAt = [datetime]$record.TimeCreated
                        }
                    }
                }
            }
        } catch {
            $skipped++
            Write-Verbose "Get-DefenderEventHistory: skipped a record. $($_.Exception.Message)"
        }
    }
    if ($skipped -gt 0) { $readState = 'error' }

    $detections = foreach ($detection in $detected.Values) {
        $paired = @($actions | Where-Object {
                $_.DetectionId -and $_.DetectionId -eq $detection.DetectionId -and $_.ThreatId -eq $detection.ThreatId
            })
        $succeeded = if ($paired.Count -eq 0) { $null } else { [bool]($paired | Where-Object Succeeded) }
        [pscustomobject]@{
            ThreatId        = $detection.ThreatId
            ThreatName      = $detection.ThreatName
            Resource        = $detection.Resource
            DetectionId     = $detection.DetectionId
            DetectedAt      = $detection.DetectedAt
            ActionSucceeded = $succeeded
        }
    }

    return [pscustomobject]@{
        ReadState        = $readState
        LogOldestRecord  = $oldest
        SkippedRecords   = $skipped
        Detections       = @($detections | Sort-Object DetectedAt -Descending)
        ExclusionChanges = @($changes.Values | Sort-Object ChangedAt -Descending)
    }
}
