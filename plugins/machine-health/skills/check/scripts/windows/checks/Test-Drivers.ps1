#Requires -Version 7.4
<#
.SYNOPSIS
Check: Driver inventory + signature health. Emits a CheckResult JSON on stdout.

See references/windows/check-catalog.md#8-driver-inventory for rubric.
#>
[CmdletBinding()]
param([switch]$Human)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-DriverStoreInventory.ps1')
. (Join-Path $PSScriptRoot '..\lib\Test-IsElevated.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-PnpProblemDevices.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-GpuDriverInfo.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-VendorUpdateCli.ps1')

function Invoke-DriversCheck {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $id = 'drivers'
    $category = 'drivers'
    $commands = @(
        # spellchecker:ignore-next-line
        'Get-CimInstance Win32_PnPSignedDriver | Select-Object DeviceName, DriverVersion, DriverDate, Manufacturer'
        'pnputil /enum-drivers'
        'pnputil /enum-devices /problem  # requires admin for full output'
        'Get-WindowsUpdate -Category Drivers  # requires PSWindowsUpdate + admin'
        "Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-CodeIntegrity/Operational'; Id=3001,3004 }"
    )

    try {
        # Inventory + dates come from WMI.
        # spellchecker:ignore-next-line
        $drivers = @(Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction Stop |
                Select-Object DeviceName, DriverVersion, DriverDate, Manufacturer)

        # Authoritative signature source: driver store via pnputil. An empty
        # SignerName means the driver has no recorded signer -- the real
        # "unsigned" condition. WMI IsSigned=false is noise on modern Windows
        # because cross-signed / attestation-signed / user-mode drivers all
        # routinely return false.
        $driverStore = @(Get-DriverStoreInventory)
        $unsignedInStore = @($driverStore | Where-Object {
                -not $_.PSObject.Properties['SignerName'] -or
                [string]::IsNullOrWhiteSpace($_.SignerName)
            })

        # CodeIntegrity rejections: when the kernel refuses to load a driver
        # due to signature / catalog violations, it logs event 3001 or 3004
        # to Microsoft-Windows-CodeIntegrity/Operational. Any such event in
        # the last 7 days is a real finding.
        $ciCutoff = (Get-Date).AddDays(-7)
        $ciEvents = @()
        try {
            $ciEvents = @(Get-WinEvent -FilterHashtable @{
                    LogName      = 'Microsoft-Windows-CodeIntegrity/Operational'
                    Id           = 3001, 3004
                    StartTime    = $ciCutoff
                } -ErrorAction Stop)
        } catch {
            if ($_.Exception.Message -notmatch 'No events were found') {
                Write-Verbose ('Test-Drivers: CodeIntegrity query failed. ' + $_.Exception.Message)
            }
        }
        $ciEvents = @($ciEvents | Where-Object { $_.TimeCreated -ge $ciCutoff })

        # Age signal: stays INFO only. Many OEM drivers are old-but-correct.
        $threeYearsAgo = (Get-Date).AddYears(-3)
        $oldSignedCount = 0
        $inventory = foreach ($d in $drivers) {
            $driverDate = $null
            if ($d.DriverDate) {
                try { $driverDate = [datetime]$d.DriverDate } catch { $driverDate = $null }
            }
            if ($driverDate -and $driverDate -lt $threeYearsAgo) { $oldSignedCount++ }

            [pscustomobject]@{
                device_name    = $d.DeviceName
                manufacturer   = $d.Manufacturer
                driver_version = $d.DriverVersion
                driver_date    = $driverDate ? $driverDate.ToString('o') : $null
            }
        }

        # Admin-gated signals: pnputil /enum-devices /problem and PSWindowsUpdate
        # driver catalog. Non-elevated runs emit the fields as null with
        # needs_admin: true in the check result. See elevation-matrix.md.
        $elevated = Test-IsElevated
        $adminFields = [System.Collections.Generic.List[string]]::new()

        $problemDevices = @()
        if ($elevated) {
            try {
                $problemDevices = @(Get-PnpProblemDevice)
            } catch {
                Write-Verbose "Test-Drivers: pnputil problem probe failed. $($_.Exception.Message)"
            }
        } else {
            $adminFields.Add('problem_devices')
        }

        $pendingDriverUpdates = $null
        if ($elevated) {
            $pswuAvailable = $null -ne (Get-Module -ListAvailable PSWindowsUpdate -ErrorAction SilentlyContinue)
            if ($pswuAvailable) {
                try {
                    Import-Module PSWindowsUpdate -ErrorAction Stop
                    $pendingDriverUpdates = @(Get-WindowsUpdate -Category 'Drivers' -ErrorAction Stop |
                            ForEach-Object {
                                [pscustomobject]@{
                                    title   = $_.Title
                                    kb      = $_.KB
                                    size_mb = $_.Size ? [math]::Round($_.Size / 1MB, 1) : $null
                                }
                            })
                } catch {
                    Write-Verbose "Test-Drivers: PSWindowsUpdate query failed. $($_.Exception.Message)"
                }
            }
        } else {
            $adminFields.Add('pending_driver_updates')
        }

        # GPU info + vendor CLIs are not admin-gated.
        $gpus = @()
        try { $gpus = @(Get-GpuDriverInfo) } catch {
            Write-Verbose "Test-Drivers: GPU probe failed. $($_.Exception.Message)"
        }
        $vendorClis = @()
        try { $vendorClis = @(Get-VendorUpdateCli) } catch {
            Write-Verbose "Test-Drivers: vendor CLI probe failed. $($_.Exception.Message)"
        }

        # Severity rubric: pnputil problem devices + pending driver updates upgrade
        # severity even past the existing signing + age rules.
        $severity = 'OK'
        if ($ciEvents.Count -gt 0) {
            $severity = 'CRIT'
        } elseif ($unsignedInStore.Count -gt 0) {
            $severity = 'WARN'
        } elseif ($problemDevices.Count -gt 0) {
            $severity = 'WARN'
        } elseif ($null -ne $pendingDriverUpdates -and $pendingDriverUpdates.Count -gt 0) {
            $severity = 'INFO'
        } elseif ($oldSignedCount -gt 0) {
            $severity = 'INFO'
        }

        $summaryParts = [System.Collections.Generic.List[string]]::new()
        $summaryParts.Add("$($drivers.Count) drivers")
        $summaryParts.Add("$($unsignedInStore.Count) unsigned in store")
        $summaryParts.Add("$($ciEvents.Count) CodeIntegrity event(s) in 7d")
        $summaryParts.Add("$oldSignedCount signed >3yr old")
        if ($problemDevices.Count -gt 0) {
            $summaryParts.Add("$($problemDevices.Count) device(s) with problem codes")
        }
        if ($null -ne $pendingDriverUpdates -and $pendingDriverUpdates.Count -gt 0) {
            $summaryParts.Add("$($pendingDriverUpdates.Count) driver update(s) pending")
        }
        if ($vendorClis.Count -gt 0) {
            $summaryParts.Add("vendor update CLI: $($vendorClis[0].vendor)")
        }
        $summary = ($summaryParts -join '; ') + '.'

        $detail = @{
            total_drivers              = $drivers.Count
            unsigned_in_store_count    = $unsignedInStore.Count
            unsigned_in_store          = @($unsignedInStore | Select-Object -First 20)
            code_integrity_event_count = $ciEvents.Count
            code_integrity_events      = @($ciEvents | ForEach-Object {
                    [pscustomobject]@{
                        provider_name = $_.ProviderName
                        id            = $_.Id
                        time_created  = $_.TimeCreated ? $_.TimeCreated.ToString('o') : $null
                        message       = $_.Message
                    }
                } | Select-Object -First 10)
            old_signed_count           = $oldSignedCount
            oldest_drivers             = @($inventory | Where-Object { $_.driver_date } |
                    Sort-Object driver_date | Select-Object -First 5)
            total_in_driver_store      = $driverStore.Count
            problem_devices            = @($problemDevices | Select-Object -First 20)
            pending_driver_updates     = $pendingDriverUpdates
            gpus                       = $gpus
            vendor_update_clis         = $vendorClis
        }

        $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
            -Severity $severity -Summary $summary -Detail $detail -Commands $commands `
            -NeedsAdmin $false -RanSuccessfully $true `
            -DurationMs ([int]$sw.ElapsedMilliseconds) `
            -AdminFields $adminFields
    } catch {
        $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
            -Severity 'UNKNOWN' -Summary 'Driver inventory check failed.' -Commands $commands `
            -RanSuccessfully $false -ErrorMessage $_.Exception.Message `
            -DurationMs ([int]$sw.ElapsedMilliseconds)
    }

    $sw.Stop()
    $result.duration_ms = [int]$sw.ElapsedMilliseconds
    return $result
}

# Guard: skip main block when dot-sourced for testing. The test file dot-sources
# this script so Pester mocks of dot-sourced lib functions (Get-DriverStoreInventory,
# Get-PnpProblemDevice, etc.) apply inside Invoke-DriversCheck. Without this guard,
# dot-sourcing would execute the check at import time. See
# .claude/rules/powershell/testing.md "Mocks do NOT propagate through
# `&`-invoked .ps1 scripts".
if ($MyInvocation.InvocationName -eq '.') { return }

Invoke-DriversCheck | Write-HealthResult -Human:$Human
