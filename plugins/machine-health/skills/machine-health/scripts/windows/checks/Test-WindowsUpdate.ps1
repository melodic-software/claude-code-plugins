#Requires -Version 7.4
<#
.SYNOPSIS
Check: Windows Update + pending reboot. Emits a CheckResult JSON on stdout.

See references/windows/check-catalog.md#1-windows-update--pending-reboot for rubric.
#>
[CmdletBinding()]
param([switch]$Human)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$id = 'windows-update'
$category = 'updates'
$commands = @(
    'Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 20'
    "Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'"
    "Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'"
    ("Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' " +
    '-Name PendingFileRenameOperations')
)

function Test-PfroPending {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # The registry property exists on most systems but usually holds an
    # empty value array. The previous check used `$null -ne (Get-ItemProperty ...)`
    # which was true even for empty arrays -- producing a permanent
    # reboot_pending=true. Authoritative check: the VALUE is a non-empty
    # string array.
    try {
        $prop = Get-ItemProperty `
            'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
            -Name PendingFileRenameOperations -ErrorAction Stop
        $value = $prop.PendingFileRenameOperations
        if ($null -eq $value) { return $false }
        $entries = @($value | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        return $entries.Count -gt 0
    } catch {
        Write-Verbose "Test-PfroPending: property not present. $($_.Exception.Message)"
        return $false
    }
}

try {
    $recentHotfixes = @()
    try {
        $recentHotfixes = @(Get-HotFix -ErrorAction Stop |
                Sort-Object InstalledOn -Descending |
                Select-Object -First 20 |
                ForEach-Object {
                    [pscustomobject]@{
                        hotfix_id    = $_.HotFixID
                        description  = $_.Description
                        installed_on = $_.InstalledOn ? $_.InstalledOn.ToString('o') : $null
                    }
                })
    } catch {
        Write-Verbose "Test-WindowsUpdate: Get-HotFix failed. $($_.Exception.Message)"
    }

    $cbsPending = [bool](Test-Path ('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\' +
            'Component Based Servicing\RebootPending'))
    $wuPending = [bool](Test-Path ('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\' +
            'WindowsUpdate\Auto Update\RebootRequired'))
    $pfroPending = Test-PfroPending

    $rebootPending = $cbsPending -or $wuPending -or $pfroPending

    $pswuPresent = $null -ne (Get-Module -ListAvailable PSWindowsUpdate -ErrorAction SilentlyContinue)
    $pendingUpdates = @()
    # Distinguish "module absent" (documented reboot-signals-only fallback) from
    # "module present but the query failed" (a degraded run: we genuinely do not
    # know whether updates are pending, so OK 'no pending updates' would lie).
    $pswuQueryFailed = $false
    $pendingUpdatesNote = $pswuPresent ? $null : 'PSWindowsUpdate not installed -- reboot signals only.'
    if ($pswuPresent) {
        try {
            $pendingUpdates = @(Get-WUList -ErrorAction Stop)
        } catch {
            $pswuQueryFailed = $true
            $pendingUpdatesNote = "PSWindowsUpdate present but Get-WUList failed: $($_.Exception.Message)"
        }
    }

    # Pending-reboot age: compute days since most recent hotfix. When paired
    # with a reboot-pending flag, a large age implies the user has been
    # ignoring a post-update reboot and should escalate severity.
    $hotfixAgeDays = $null
    if ($recentHotfixes.Count -gt 0 -and $recentHotfixes[0].installed_on) {
        try {
            $d = [datetime]$recentHotfixes[0].installed_on
            $hotfixAgeDays = [int]([math]::Floor(((Get-Date) - $d).TotalDays))
        } catch {
            Write-Verbose 'Test-WindowsUpdate: hotfix age parse failed.'
        }
    }

    $severity = 'OK'
    $summary = 'No pending updates detected.'

    $oldestPendingDays = $null
    if ($pendingUpdates.Count -gt 0) {
        $severity = 'WARN'
        $summary = "$($pendingUpdates.Count) pending update(s)."
        $firstInstall = $pendingUpdates |
            Where-Object { $_.LastDeploymentChangeTime } |
            Sort-Object LastDeploymentChangeTime |
            Select-Object -First 1
        if ($firstInstall -and $firstInstall.LastDeploymentChangeTime) {
            $oldestPendingDays = (New-TimeSpan `
                    -Start $firstInstall.LastDeploymentChangeTime `
                    -End (Get-Date)).TotalDays
            if ($oldestPendingDays -gt 14) {
                $severity = 'CRIT'
                $summary = ("$($pendingUpdates.Count) pending update(s); " +
                    "oldest $([int]$oldestPendingDays) days old.")
            }
        }
    } elseif ($rebootPending) {
        # Escalate INFO -> WARN -> CRIT based on how long the reboot has been
        # pending (proxied by hotfix install age since the reboot flag persists
        # until the machine reboots).
        if ($null -ne $hotfixAgeDays -and $hotfixAgeDays -gt 14) {
            $severity = 'CRIT'
            $summary = "Reboot pending for $hotfixAgeDays days (last hotfix install age)."
        } elseif ($null -ne $hotfixAgeDays -and $hotfixAgeDays -gt 7) {
            $severity = 'WARN'
            $summary = "Reboot pending for $hotfixAgeDays days (last hotfix install age)."
        } else {
            $severity = 'INFO'
            $summary = 'Reboot pending, no old updates detected.'
        }
    }

    # A failed enumeration must not read as a clean OK. Surface it as INFO
    # (reboot signals are still valid, so the check itself ran successfully).
    if ($severity -eq 'OK' -and $pswuQueryFailed) {
        $severity = 'INFO'
        $summary = 'Update enumeration degraded (Get-WUList failed); reboot signals only.'
    }

    $detail = @{
        reboot_pending          = $rebootPending
        reboot_sources          = @{
            cbs  = $cbsPending
            wu   = $wuPending
            pfro = $pfroPending
        }
        recent_hotfixes         = $recentHotfixes
        pending_update_count    = $pendingUpdates.Count
        pswindowsupdate_present = $pswuPresent
        update_enum_degraded    = $pswuQueryFailed
        oldest_pending_days     = $null -ne $oldestPendingDays ? [int]$oldestPendingDays : $null
        hotfix_age_days         = $hotfixAgeDays
    }

    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity $severity -Summary $summary -Detail $detail -Commands $commands `
        -NeedsAdmin $false -RanSuccessfully $true -DurationMs ([int]$sw.ElapsedMilliseconds) `
        -Notes $pendingUpdatesNote
} catch {
    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity 'UNKNOWN' -Summary 'Windows Update check failed.' -Commands $commands `
        -RanSuccessfully $false -ErrorMessage $_.Exception.Message `
        -DurationMs ([int]$sw.ElapsedMilliseconds)
}

$sw.Stop()
$result.duration_ms = [int]$sw.ElapsedMilliseconds
$result | Write-HealthResult -Human:$Human
