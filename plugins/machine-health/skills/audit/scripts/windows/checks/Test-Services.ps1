#Requires -Version 7.4
<#
.SYNOPSIS
Check: Services + startup items. Emits a CheckResult JSON on stdout.

See reference/windows/check-catalog.md#4-services--startup-items for rubric.
#>
[CmdletBinding()]
param([switch]$Human)

Set-StrictMode -Version 3.0
# Continue so non-terminating errors cannot abort the JSON envelope; the outer
# try/catch turns catastrophic failures into UNKNOWN.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')
. (Join-Path $PSScriptRoot '..\lib\Test-ServiceTriggerStart.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$id = 'services'
$category = 'services'
$commands = @(
    "Get-Service | Where-Object { `$_.StartType -eq 'Automatic' -and `$_.Status -ne 'Running' }"
    "Get-CimInstance Win32_Service | Where-Object { `$_.StartMode -eq 'Auto' }"
    'Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User'
)

try {
    $uptime = $null
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        if ($os.LastBootUpTime) {
            $uptime = (Get-Date) - $os.LastBootUpTime
        }
    } catch {
        Write-Verbose "Test-Services: Win32_OperatingSystem query failed. $($_.Exception.Message)"
    }

    $win32ByName = @{}
    try {
        $win32Services = @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop |
                Where-Object { $_.StartMode -eq 'Auto' })
        foreach ($svc in $win32Services) {
            if ($svc.Name) { $win32ByName[$svc.Name] = $svc }
        }
    } catch {
        Write-Verbose "Test-Services: Win32_Service query failed. $($_.Exception.Message)"
    }

    # Stopped Automatic services: trigger_start (TriggerInfo key, stopped is normal),
    # delayed_pending (DelayedAutoStart, uptime < 10 min), else unexpected_stopped (WARN).
    $unexpectedStopped = [System.Collections.Generic.List[pscustomobject]]::new()
    $triggerStartStopped = [System.Collections.Generic.List[pscustomobject]]::new()
    $delayedPending = [System.Collections.Generic.List[pscustomobject]]::new()

    # SilentlyContinue so a per-service permission error (WaaSMedicSvc) cannot drop the check
    # to UNKNOWN; zero services back is a catastrophic SCM/RPC failure, reported with svcErrs.
    $svcErrs = $null
    $allServices = @(Get-Service -ErrorAction SilentlyContinue -ErrorVariable svcErrs)
    if ($allServices.Count -eq 0) {
        $errCount = @($svcErrs).Count
        $firstMsg = if ($errCount -gt 0) { $svcErrs[0].Exception.Message } else { 'no recorded errors' }
        throw "Get-Service returned 0 services ($errCount errors: $firstMsg)"
    }
    $stoppedAutoServices = @($allServices | Where-Object {
            $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running'
        })

    foreach ($svc in $stoppedAutoServices) {
        $win32 = $win32ByName[$svc.Name]
        $delayed = if ($win32) { [bool]$win32.DelayedAutoStart } else { $false }
        $triggerStart = Test-ServiceTriggerStart -Name $svc.Name

        $entry = [pscustomobject]@{
            name               = $svc.Name
            display_name       = $svc.DisplayName
            status             = $svc.Status.ToString()
            start_type         = $svc.StartType.ToString()
            delayed_auto_start = $delayed
            trigger_start      = $triggerStart
        }

        if ($triggerStart) {
            $triggerStartStopped.Add($entry)
        } elseif ($delayed -and $uptime -and $uptime.TotalMinutes -lt 10) {
            $delayedPending.Add($entry)
        } else {
            $unexpectedStopped.Add($entry)
        }
    }

    $startupInventory = @()
    try {
        $startupInventory = @(Get-CimInstance -ClassName Win32_StartupCommand -ErrorAction Stop |
                Select-Object Name, Command, Location, User)
    } catch {
        Write-Verbose "Test-Services: Win32_StartupCommand query failed. $($_.Exception.Message)"
    }

    $severity = 'OK'
    $summary = 'No unexpected stopped Automatic services.'
    if ($unexpectedStopped.Count -gt 0) {
        $severity = 'WARN'
        $summary = "$($unexpectedStopped.Count) Automatic service(s) stopped."
    } elseif ($delayedPending.Count -gt 0) {
        $severity = 'INFO'
        $uptimeMin = $uptime ? [int]$uptime.TotalMinutes : 0
        $summary = ("$($delayedPending.Count) delayed-auto service(s) not yet started; " +
            "uptime $uptimeMin min.")
    } elseif ($triggerStartStopped.Count -gt 0) {
        $summary = "$($triggerStartStopped.Count) trigger-start service(s) idle (expected)."
    }

    $detail = @{
        stopped_auto_services = $unexpectedStopped
        trigger_start_stopped = $triggerStartStopped
        delayed_pending       = $delayedPending
        startup_inventory     = $startupInventory
        uptime_minutes        = $uptime ? [int]$uptime.TotalMinutes : $null
    }

    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity $severity -Summary $summary -Detail $detail -Commands $commands `
        -NeedsAdmin $false -RanSuccessfully $true
} catch {
    $result = New-HealthFailureResult -Id $id -Category $category `
        -Summary 'Services check failed.' -Commands $commands -ErrorRecord $_
}

Complete-HealthCheck -Result $result -Stopwatch $sw -Human:$Human
