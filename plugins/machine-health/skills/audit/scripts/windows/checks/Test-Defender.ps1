#Requires -Version 7.4
<#
.SYNOPSIS
Check: Defender status + threats. Emits a CheckResult JSON on stdout.

See reference/windows/check-catalog.md#5-defender-status--threats for rubric.
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'MutedKeys',
    Justification = 'Read inside $CheckBody, which Invoke-HealthCheckEnvelope invokes.')]
param(
    [switch]$Human,
    [string[]]$MutedKeys = @()
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-WorstSeverity.ps1')
. (Join-Path $PSScriptRoot '..\lib\New-FindingItem.ps1')
. (Join-Path $PSScriptRoot '..\lib\New-DefenderExclusionItem.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-DefenderEventHistory.ps1')

$id = 'defender'
$category = 'security'
$commands = @(
    'Get-MpComputerStatus'
    "Get-WinEvent -FilterHashtable @{ LogName = '$script:DefenderEventLogName'; Id = $($script:DefenderEventIds -join ', ') }"
)

# The recent window for detections and exclusion additions; rubric in check-catalog.md section 5.
$recentDays = 30

$FailureSummary = 'Defender check failed.'
$PassThru = $false
$CheckBody = {
    if (-not (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue)) {
        $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
            -Severity 'UNKNOWN' -Summary 'Defender cmdlets unavailable.' -Commands $commands `
            -RanSuccessfully $false `
            -ErrorMessage 'Get-MpComputerStatus not found. Is the Defender PowerShell module present?' `
            -Notes 'Module may be blocked by policy or absent on Windows Server Core.'
    } else {
        $status = Get-MpComputerStatus -ErrorAction Stop

        # AMRunningMode values (per MSFT_MpComputerStatus docs): 'Normal',
        # 'Passive Mode', 'SxS Passive Mode', 'EDR Block Mode', 'Unknown'.
        # Modern Windows reports 'SxS Passive Mode' when a third-party AV is
        # the active protection; older builds used 'Passive Mode'. Both mean
        # Defender is NOT the primary AV.
        $passiveMode = $status.AMRunningMode -in 'Passive Mode', 'SxS Passive Mode'

        $history = Get-DefenderEventHistory
        $eventsFloor = Get-UnmutedSeverity -ReadState $history.ReadState
        $threatQueryError = $eventsFloor -eq 'OK' ? $null : "Defender event log read state '$($history.ReadState)'."
        $cutoff = (Get-Date).AddDays(-$recentDays)
        $oldestText = $history.LogOldestRecord ? ([datetime]$history.LogOldestRecord).ToString('o') : $null
        $coverageGap = $null -eq $history.LogOldestRecord -or [datetime]$history.LogOldestRecord -gt $cutoff

        $detectionItems = @(foreach ($d in $history.Detections) {
            $itemSeverity = if ($d.DetectedAt -lt $cutoff) { 'INFO' } elseif ($d.ActionSucceeded -eq $true) { 'WARN' } else { 'CRIT' }
            New-FindingItem -Kind 'detection' -Identity @($d.ThreatId, $d.Resource, $d.DetectionId) -MutedKeys $MutedKeys `
                -Severity $itemSeverity -Title "$($d.ThreatName) at $($d.Resource)" -Fields @{
                threat_name      = $d.ThreatName
                resource         = $d.Resource
                detected_at      = ([datetime]$d.DetectedAt).ToString('o')
                action_succeeded = $d.ActionSucceeded
            }
        })
        $exclusionItems = @(foreach ($c in $history.ExclusionChanges) {
            # A recent path addition outside the known-safe list is the one change worth a WARN.
            $suspect = $c.Change -eq 'added' -and $c.Type -eq 'path' -and $c.ChangedAt -ge $cutoff -and
                -not (Test-DefenderKnownSafePath -Path $c.Value)
            New-DefenderExclusionItem -Type $c.Type -Value $c.Value -MutedKeys $MutedKeys `
                -Severity ($suspect ? 'WARN' : 'INFO') -Title "$($c.Type) exclusion $($c.Change): $($c.Value)" -Fields @{
                change     = $c.Change
                changed_at = ([datetime]$c.ChangedAt).ToString('o')
                label      = "history within log retention since $oldestText"
            }
        })
        $items = $detectionItems + $exclusionItems
        $recentThreats = @($detectionItems | Where-Object severity -In 'WARN', 'CRIT')
        $unremediated = @($detectionItems | Where-Object severity -EQ 'CRIT')
        $suspectAdds = @($exclusionItems | Where-Object severity -EQ 'WARN')

        $severities = [System.Collections.Generic.List[string]]::new()
        $severities.Add('OK')
        $reasons = [System.Collections.Generic.List[string]]::new()

        if ($passiveMode) {
            # Passive mode is itself informational: Defender isn't the active
            # AV, so the human reviewing this report should know a third-party
            # product is expected to be protecting the machine. WARN/CRIT
            # findings below still win via Get-WorstSeverity.
            $severities.Add('INFO')
        }

        $sigAge = $null -ne $status.AntivirusSignatureAge ? [int]$status.AntivirusSignatureAge : $null
        if ($null -ne $sigAge) {
            # In passive mode, stale Defender signatures are expected --
            # the third-party AV is responsible for detection, so downgrade
            # these findings to INFO rather than WARN/CRIT.
            $sigSev = 'OK'
            if ($passiveMode) {
                if ($sigAge -gt 3) { $sigSev = 'INFO' }
            } elseif ($sigAge -gt 7) {
                $sigSev = 'CRIT'
            } elseif ($sigAge -gt 3) {
                $sigSev = 'WARN'
            }
            if ($sigSev -ne 'OK') {
                $severities.Add($sigSev)
                $reasons.Add("signature age $sigAge days")
            }
        }

        $rtp = [bool]$status.RealTimeProtectionEnabled
        if (-not $rtp -and -not $passiveMode) {
            # RTP off in Normal mode is CRIT. In passive mode RTP is
            # EXPECTED to be off (the other AV is active) -- not a finding.
            $severities.Add('CRIT')
            $reasons.Add('real-time protection disabled')
        }

        $tamper = [bool]$status.IsTamperProtected
        if (-not $tamper) {
            # Tamper protection is enforced regardless of passive mode; it
            # protects Defender's own settings from unauthorized changes.
            # Downgraded to WARN (not CRIT) because recent Windows images
            # may ship with it disabled until the user signs into MSA.
            $severities.Add('WARN')
            $reasons.Add('tamper protection disabled')
        }

        if (-not [bool]$status.AMServiceEnabled) {
            # AMServiceEnabled=false means the Defender kernel component
            # isn't loaded at all -- different from passive mode (another
            # AV is active) and different from RTP-off. This is a real gap.
            $severities.Add('CRIT')
            $reasons.Add('Defender service disabled')
        }

        # Detections keep their severity even in passive mode. Summary and
        # notes carry counts only, never exclusion values.
        if ($recentThreats.Count -gt 0) {
            $reasons.Add("$($recentThreats.Count) threat detection(s) in last $recentDays days, $($unremediated.Count) without a recorded remediation")
        }
        if ($suspectAdds.Count -gt 0) {
            $reasons.Add("$($suspectAdds.Count) path exclusion(s) added in last $recentDays days outside the known-safe list")
        }
        if ($exclusionItems.Count -gt 0) {
            $reasons.Add("$($exclusionItems.Count) exclusion change(s) in the event log")
        }

        $severities.Add((Get-UnmutedSeverity -Items $items))
        $severity = Get-WorstSeverity $severities
        # An unreadable history is never hidden behind OK or INFO, and never outranks a real WARN or CRIT.
        if ($severity -in 'OK', 'INFO' -and $eventsFloor -ne 'OK') { $severity = $eventsFloor }
        if ($severity -eq 'OK' -and $coverageGap) { $severity = 'INFO' }

        $notesParts = [System.Collections.Generic.List[string]]::new()
        if ($passiveMode) {
            $notesParts.Add('Defender in passive mode (third-party AV likely active).')
        }
        if ($threatQueryError) {
            $notesParts.Add("Could not query threat history: $threatQueryError")
        }
        if ($history.SkippedRecords -gt 0) {
            $notesParts.Add("$($history.SkippedRecords) Defender event record(s) could not be parsed.")
        }
        if ($coverageGap) {
            $notesParts.Add("The Defender event log does not reach back the full $recentDays days (oldest record: $(if ($oldestText) { $oldestText } else { 'unreadable' })); older detections are not visible.")
        }
        $noteAppend = $notesParts.Count -gt 0 ? ($notesParts -join ' ') : $null

        $summary = $reasons.Count -gt 0 ? ('Defender: ' + ($reasons -join ', ') + '.') : 'Defender healthy.'

        $detail = @{
            signature_age_days   = $sigAge
            real_time_protection = $rtp
            tamper_protection    = $tamper
            running_mode         = $status.AMRunningMode
            am_service_enabled   = [bool]$status.AMServiceEnabled
            antispyware_enabled  = [bool]$status.AntispywareEnabled
            recent_threat_count  = $recentThreats.Count
            last_quick_scan      = $status.QuickScanEndTime ? $status.QuickScanEndTime.ToString('o') : $null
            last_full_scan       = $status.FullScanEndTime ? $status.FullScanEndTime.ToString('o') : $null
            threat_query_error   = $threatQueryError
            events_read_state    = $history.ReadState
            log_oldest_record    = $oldestText
            exclusion_change_count = $exclusionItems.Count
            events_skipped_count = $history.SkippedRecords
            coverage_gap         = $coverageGap
            items_count          = $items.Count
            muted_count          = @($items | Where-Object muted).Count
            items                = $items
        }

        $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
            -Severity $severity -Summary $summary -Detail $detail -Commands $commands `
            -NeedsAdmin $false -RanSuccessfully $true `
            -Notes $noteAppend
    }
}
. (Join-Path $PSScriptRoot '..\lib\Invoke-HealthCheckEnvelope.ps1')
