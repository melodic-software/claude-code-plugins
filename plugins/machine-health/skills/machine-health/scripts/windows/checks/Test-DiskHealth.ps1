#Requires -Version 7.4
<#
.SYNOPSIS
Check: disk space + SMART health. Emits a CheckResult JSON on stdout.

See references/windows/check-catalog.md#2-disk-space--smart-health for rubric.
#>
[CmdletBinding()]
param([switch]$Human)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-PhysicalDiskReliability.ps1')
. (Join-Path $PSScriptRoot '..\lib\Test-IsElevated.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-WorstSeverity.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$id = 'disk-space'
$category = 'storage'
$commands = @(
    "Get-Volume | Where-Object { `$_.DriveType -eq 'Fixed' -and `$_.FileSystem -in 'NTFS','ReFS' -and `$_.DriveLetter }"
    'Get-PhysicalDisk | Select-Object FriendlyName, MediaType, HealthStatus, OperationalStatus'
    'Get-PhysicalDisk | Get-StorageReliabilityCounter | Select-Object Temperature, TemperatureMax, Wear'
)

function Get-TemperatureSeverity {
    param(
        [AllowNull()] $Temperature,
        [AllowNull()] $TemperatureMax
    )
    if ($null -eq $Temperature) { return 'OK' }

    # Device-relative thresholds when the drive reports its own max:
    #   CRIT -- at or above the vendor's maximum (entering throttle/damage territory)
    #   WARN -- within 90% of max (hot enough to notice)
    # Fallback to 55/65 C only when TemperatureMax is missing or nonsensical.
    if ($null -ne $TemperatureMax -and $TemperatureMax -gt 0) {
        if ($Temperature -ge $TemperatureMax) { return 'CRIT' }
        if ($Temperature -ge ($TemperatureMax * 0.9)) { return 'WARN' }
        return 'OK'
    }

    if ($Temperature -gt 65) { return 'CRIT' }
    if ($Temperature -gt 55) { return 'WARN' }
    return 'OK'
}

function Get-WearSeverity {
    param([AllowNull()] $Wear)
    if ($null -eq $Wear) { return 'OK' }
    if ($Wear -ge 85) { return 'CRIT' }
    if ($Wear -ge 70) { return 'WARN' }
    return 'OK'
}

try {
    $volumes = [System.Collections.Generic.List[pscustomobject]]::new()
    $volumeSeverities = [System.Collections.Generic.List[string]]::new()
    $volumeSeverities.Add('OK')

    try {
        Get-Volume -ErrorAction Stop |
            # The DriveLetter guard excludes the Windows Recovery Environment
            # partition and similar unlettered fixed volumes, which otherwise
            # showed up in reports with a blank drive and always-high used %.
            Where-Object { $_.DriveType -eq 'Fixed' -and $_.FileSystem -in 'NTFS', 'ReFS' -and $_.DriveLetter } |
            ForEach-Object {
                $sizeGB = if ($_.Size) { [math]::Round($_.Size / 1GB, 1) } else { 0 }
                $freeGB = if ($_.SizeRemaining) {
                    [math]::Round($_.SizeRemaining / 1GB, 1)
                } else { 0 }
                $usedPct = if ($_.Size -gt 0) {
                    [math]::Round((($_.Size - $_.SizeRemaining) / $_.Size) * 100, 1)
                } else { 0 }
                $freePct = 100 - $usedPct

                $sev = 'OK'
                if ($freePct -lt 5) { $sev = 'CRIT' }
                elseif ($freePct -lt 15) { $sev = 'WARN' }

                $volumeSeverities.Add($sev)
                $volumes.Add([pscustomobject]@{
                        drive      = [string]$_.DriveLetter
                        filesystem = $_.FileSystem
                        size_gb    = $sizeGB
                        free_gb    = $freeGB
                        used_pct   = $usedPct
                        severity   = $sev
                    })
            }
    } catch {
        Write-Verbose "Test-DiskHealth: Get-Volume failed. $($_.Exception.Message)"
    }

    $disks = [System.Collections.Generic.List[pscustomobject]]::new()
    $diskSeverities = [System.Collections.Generic.List[string]]::new()
    $diskSeverities.Add('OK')
    try {
        Get-PhysicalDisk -ErrorAction Stop | ForEach-Object {
            $disk = $_
            $healthSev = 'OK'
            if ($disk.HealthStatus -ne 'Healthy') { $healthSev = 'CRIT' }
            if ($disk.OperationalStatus -and $disk.OperationalStatus -notin @('OK', 'Online')) {
                $healthSev = 'CRIT'
            }

            $counter = Get-PhysicalDiskReliability -Disk $disk

            $temperature = $null
            $temperatureMax = $null
            $wear = $null
            if ($counter) {
                $temperature = $counter.Temperature
                $temperatureMax = $counter.PSObject.Properties['TemperatureMax'] ? $counter.TemperatureMax : $null
                $wear = $counter.Wear
            }

            $tempSev = Get-TemperatureSeverity -Temperature $temperature -TemperatureMax $temperatureMax
            $wearSev = Get-WearSeverity -Wear $wear

            $diskSev = Get-WorstSeverity @($healthSev, $tempSev, $wearSev)
            $diskSeverities.Add($diskSev)

            $disks.Add([pscustomobject]@{
                    friendly_name      = $disk.FriendlyName
                    media_type         = $disk.MediaType
                    health_status      = $disk.HealthStatus
                    operational_status = ($disk.OperationalStatus -join ',')
                    temperature_c      = $temperature
                    temperature_max_c  = $temperatureMax
                    wear_pct           = $wear
                    read_errors_total  = if ($counter) { $counter.ReadErrorsTotal } else { $null }
                    write_errors_total = if ($counter) { $counter.WriteErrorsTotal } else { $null }
                    severity           = $diskSev
                })
        }
    } catch {
        Write-Verbose "Test-DiskHealth: Get-PhysicalDisk failed. $($_.Exception.Message)"
    }

    $allSeverities = [System.Collections.Generic.List[string]]::new()
    $allSeverities.AddRange($volumeSeverities)
    $allSeverities.AddRange($diskSeverities)
    $overallSev = Get-WorstSeverity $allSeverities.ToArray()

    $summary = if ($volumes.Count -gt 0) {
        $worstVol = $volumes | Sort-Object used_pct -Descending | Select-Object -First 1
        $freePct = [math]::Round(100 - $worstVol.used_pct, 1)
        "$($worstVol.drive): at $($worstVol.used_pct)% used ($freePct% free)"
    } elseif ($disks.Count -gt 0) {
        "$($disks.Count) physical disk(s) inventoried; no fixed NTFS/ReFS volumes reported."
    } else {
        'No storage data available.'
    }

    $detail = @{
        volumes        = $volumes
        physical_disks = $disks
    }

    # Non-elevated runs silently miss Get-StorageReliabilityCounter data on
    # most drives. Make that visible: declare admin_fields so the elevation
    # banner + report block call it out, and append a note to the summary.
    $elevated = Test-IsElevated
    $adminFields = @()
    $adminNote = $null
    if (-not $elevated) {
        $adminFields = @('temp_c', 'wear_pct', 'read_errors', 'write_errors')
        $adminNote = 'SMART temp/wear counters require admin; re-run elevated for full coverage.'
        if ($summary) {
            $summary = "$summary (SMART skipped -- run elevated for wear/temp)"
        }
    }

    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity $overallSev -Summary $summary -Detail $detail -Commands $commands `
        -NeedsAdmin $false -RanSuccessfully $true `
        -DurationMs ([int]$sw.ElapsedMilliseconds) `
        -AdminFields $adminFields `
        -Notes $adminNote
} catch {
    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity 'UNKNOWN' -Summary 'Disk health check failed.' -Commands $commands `
        -RanSuccessfully $false -ErrorMessage $_.Exception.Message `
        -DurationMs ([int]$sw.ElapsedMilliseconds)
}

$sw.Stop()
$result.duration_ms = [int]$sw.ElapsedMilliseconds
$result | Write-HealthResult -Human:$Human
