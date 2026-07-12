#Requires -Version 7.4
<#
.SYNOPSIS
Check: Defender status + threats. Emits a CheckResult JSON on stdout.

See references/windows/check-catalog.md#5-defender-status--threats for rubric.
#>
[CmdletBinding()]
param([switch]$Human)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-WorstSeverity.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$id = 'defender'
$category = 'security'
$commands = @(
    'Get-MpComputerStatus'
    'Get-MpThreatDetection'
)

try {
    if (-not (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue)) {
        $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
            -Severity 'UNKNOWN' -Summary 'Defender cmdlets unavailable.' -Commands $commands `
            -RanSuccessfully $false `
            -ErrorMessage 'Get-MpComputerStatus not found. Is the Defender PowerShell module present?' `
            -DurationMs ([int]$sw.ElapsedMilliseconds) `
            -Notes 'Module may be blocked by policy or absent on Windows Server Core.'
    } else {
        $status = Get-MpComputerStatus -ErrorAction Stop

        # AMRunningMode values (per MSFT_MpComputerStatus docs): 'Normal',
        # 'Passive Mode', 'SxS Passive Mode', 'EDR Block Mode', 'Unknown'.
        # Modern Windows reports 'SxS Passive Mode' when a third-party AV is
        # the active protection; older builds used 'Passive Mode'. Both mean
        # Defender is NOT the primary AV.
        $passiveMode = $status.AMRunningMode -in 'Passive Mode', 'SxS Passive Mode'

        $threats = @()
        $threatQueryError = $null
        try {
            $cutoff = (Get-Date).AddDays(-30)
            $threats = @(Get-MpThreatDetection -ErrorAction Stop |
                    Where-Object { $_.InitialDetectionTime -ge $cutoff })
        } catch {
            $threatQueryError = $_.Exception.Message
            Write-Verbose "Test-Defender: Get-MpThreatDetection failed. $threatQueryError"
        }

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

        if ($threats.Count -gt 0) {
            # Recorded detections are always CRIT -- even in passive mode,
            # a logged threat is something the user should inspect.
            $severities.Add('CRIT')
            $reasons.Add("$($threats.Count) threat detection(s) in last 30 days")
        }

        $severity = Get-WorstSeverity $severities

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
            recent_threat_count  = $threats.Count
            last_quick_scan      = $status.QuickScanEndTime ? $status.QuickScanEndTime.ToString('o') : $null
            last_full_scan       = $status.FullScanEndTime ? $status.FullScanEndTime.ToString('o') : $null
            threat_query_error   = $threatQueryError
        }

        $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
            -Severity $severity -Summary $summary -Detail $detail -Commands $commands `
            -NeedsAdmin $false -RanSuccessfully $true `
            -DurationMs ([int]$sw.ElapsedMilliseconds) `
            -Notes $noteAppend
    }
} catch {
    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity 'UNKNOWN' -Summary 'Defender check failed.' -Commands $commands `
        -RanSuccessfully $false -ErrorMessage $_.Exception.Message `
        -DurationMs ([int]$sw.ElapsedMilliseconds)
}

$sw.Stop()
$result.duration_ms = [int]$sw.ElapsedMilliseconds
$result | Write-HealthResult -Human:$Human
