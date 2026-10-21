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
. (Join-Path $PSScriptRoot '..\lib\Get-DefenderEventHistory.ps1')

$id = 'defender'
$category = 'security'
$commands = @(
    'Get-MpComputerStatus'
    "Get-WinEvent -FilterHashtable @{ LogName = '$script:DefenderEventLogName'; Id = $($script:DefenderEventIds -join ', ') }"
)

# A detection inside this window is current (CRIT or WARN); older ones are history (INFO).
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
        $threatQueryError = $history.ReadState -in 'ok', 'absent' ? $null : "Defender event log read state '$($history.ReadState)'."
        $cutoff = (Get-Date).AddDays(-$recentDays)
        $oldestText = $history.LogOldestRecord ? ([datetime]$history.LogOldestRecord).ToString('o') : $null

        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($d in $history.Detections) {
            $itemSeverity = if ($d.DetectedAt -lt $cutoff) { 'INFO' } elseif ($d.ActionSucceeded -eq $true) { 'WARN' } else { 'CRIT' }
            $items.Add((New-FindingItem -Kind 'detection' -Identity @($d.ThreatId, $d.Resource) -MutedKeys $MutedKeys `
                        -Severity $itemSeverity -Title "$($d.ThreatName) at $($d.Resource)" -Fields @{
                        threat_name      = $d.ThreatName
                        resource         = $d.Resource
                        detected_at      = ([datetime]$d.DetectedAt).ToString('o')
                        action_succeeded = $d.ActionSucceeded
                    }))
        }
        foreach ($c in $history.ExclusionChanges) {
            $items.Add((New-FindingItem -Kind 'exclusion' -Identity @($c.Type, $c.Value) -MutedKeys $MutedKeys `
                        -Severity 'INFO' -Title "$($c.Type) exclusion $($c.Change): $($c.Value)" -Fields @{
                        exclusion_type = $c.Type
                        change         = $c.Change
                        value          = $c.Value
                        changed_at     = ([datetime]$c.ChangedAt).ToString('o')
                        label          = "history within log retention since $oldestText"
                    }))
        }
        $recentThreats = @($history.Detections | Where-Object { $_.DetectedAt -ge $cutoff })
        $unremediated = @($recentThreats | Where-Object { $_.ActionSucceeded -ne $true })

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

        if ($recentThreats.Count -gt 0) {
            # Detections keep their severity even in passive mode: a logged
            # threat is something the user should inspect. The items carry the
            # level, so a muted detection does not count.
            $reasons.Add("$($recentThreats.Count) threat detection(s) in last $recentDays days, $($unremediated.Count) without a recorded remediation")
        }
        if ($history.ExclusionChanges.Count -gt 0) {
            # Counts only: exclusion values stay out of the summary and notes.
            $reasons.Add("$($history.ExclusionChanges.Count) exclusion change(s) in the event log")
        }

        $severities.Add((Get-UnmutedSeverity -Items $items.ToArray()))
        $severity = Get-WorstSeverity $severities
        if ($severity -eq 'OK') {
            # An unreadable history cannot leave the check OK, and never
            # outranks a real finding.
            $severity = Get-UnmutedSeverity -ReadState $history.ReadState
        }

        $notesParts = [System.Collections.Generic.List[string]]::new()
        if ($passiveMode) {
            $notesParts.Add('Defender in passive mode (third-party AV likely active).')
        }
        if ($threatQueryError) {
            $notesParts.Add("Could not query threat history: $threatQueryError")
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
            exclusion_change_count = $history.ExclusionChanges.Count
            items_count          = $items.Count
            muted_count          = @($items | Where-Object muted).Count
            items                = $items.ToArray()
        }

        $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
            -Severity $severity -Summary $summary -Detail $detail -Commands $commands `
            -NeedsAdmin $false -RanSuccessfully $true `
            -Notes $noteAppend
    }
}
. (Join-Path $PSScriptRoot '..\lib\Invoke-HealthCheckEnvelope.ps1')
