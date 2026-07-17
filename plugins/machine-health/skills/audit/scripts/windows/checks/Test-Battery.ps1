#Requires -Version 7.4
<#
.SYNOPSIS
Check: Battery + power report. Emits a CheckResult JSON on stdout.

See references/windows/check-catalog.md#7-battery--power-report for rubric.

.PARAMETER ReportPath
Absolute path the battery HTML report should be written to. When omitted,
the report is skipped; severity is still computed from Win32_Battery
where possible.
#>
[CmdletBinding()]
param(
    [switch]$Human,
    [string]$ReportPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$id = 'battery'
$category = 'power'
$commands = @(
    'Get-CimInstance Win32_Battery'
    "powercfg /batteryreport /output '<path>' /duration 30"
)

function Get-CapacityFromBatteryReport {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory = $true)] [string] $HtmlPath)

    if (-not (Test-Path -LiteralPath $HtmlPath)) { return $null }
    try {
        $html = Get-Content -LiteralPath $HtmlPath -Raw -ErrorAction Stop
    } catch {
        Write-Verbose "Get-CapacityFromBatteryReport: read failed. $($_.Exception.Message)"
        return $null
    }

    # Locale-robust parser. Regex-matching the English labels "DESIGN
    # CAPACITY" and "FULL CHARGE CAPACITY" breaks on localized Windows
    # where they're translated. The HTML structure is stable across
    # locales: the Installed Batteries section lists design capacity
    # first, then full-charge capacity, each as a numeric value followed
    # by "mWh". Accepting comma or dot as thousands separator covers both
    # en-US (45,000) and de-DE (45.000) style numbers.
    $pattern = '([\d][\d.,]*)\s*mWh'
    $mwhMatches = [regex]::Matches($html, $pattern, 'IgnoreCase')
    if ($mwhMatches.Count -lt 2) {
        Write-Verbose ('Get-CapacityFromBatteryReport: expected at least 2 mWh values, ' +
            "found $($mwhMatches.Count).")
        return $null
    }

    $design = [int](($mwhMatches[0].Groups[1].Value -replace '[,.]', ''))
    $full = [int](($mwhMatches[1].Groups[1].Value -replace '[,.]', ''))
    return [pscustomobject]@{ design_mwh = $design; full_mwh = $full }
}

try {
    $batteries = @()
    try {
        $batteries = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop)
    } catch {
        Write-Verbose "Test-Battery: Win32_Battery query failed. $($_.Exception.Message)"
    }

    if ($batteries.Count -eq 0) {
        $detail = @{ has_battery = $false }
        $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
            -Severity 'OK' -Summary 'No battery present.' -Detail $detail -Commands $commands `
            -NeedsAdmin $false -RanSuccessfully $true `
            -DurationMs ([int]$sw.ElapsedMilliseconds)
    } else {
        $fullPct = $null
        $capacity = $null
        $reportGenerated = $false
        $reportNote = $null

        if ($ReportPath) {
            try {
                $reportDir = Split-Path -Path $ReportPath -Parent
                if ($reportDir -and -not (Test-Path -LiteralPath $reportDir)) {
                    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
                }
                # Only generate when the file doesn't already exist (tests
                # seed the HTML directly to avoid running powercfg).
                if (-not (Test-Path -LiteralPath $ReportPath)) {
                    $null = powercfg /batteryreport /output "$ReportPath" /duration 30 2>&1
                }
                if (Test-Path -LiteralPath $ReportPath) {
                    $reportGenerated = $true
                    $capacity = Get-CapacityFromBatteryReport -HtmlPath $ReportPath
                    if ($capacity -and $capacity.design_mwh -gt 0 -and $capacity.full_mwh -gt 0) {
                        $fullPct = [math]::Round(
                            ($capacity.full_mwh / $capacity.design_mwh) * 100, 1)
                    }
                }
            } catch {
                $reportNote = "powercfg /batteryreport failed: $($_.Exception.Message)"
            }
        }

        $severity = 'OK'
        $summary = 'Battery present.'
        if ($null -ne $fullPct) {
            $summary = "Battery full-charge $fullPct% of design."
            if ($fullPct -lt 50) { $severity = 'CRIT' }
            elseif ($fullPct -lt 70) { $severity = 'WARN' }
        } else {
            $reportNote = if ($reportNote) {
                $reportNote
            } elseif ($ReportPath) {
                'Battery HTML generated but capacity values not parseable.'
            } else {
                'No ReportPath provided; capacity analysis skipped.'
            }
        }

        $detail = @{
            has_battery       = $true
            batteries         = @($batteries | ForEach-Object {
                    [pscustomobject]@{
                        name             = $_.Name
                        chemistry        = $_.Chemistry
                        status           = $_.Status
                        estimated_charge = $_.EstimatedChargeRemaining
                    }
                })
            full_capacity_pct = $fullPct
            design_mwh        = if ($capacity) { $capacity.design_mwh } else { $null }
            full_mwh          = if ($capacity) { $capacity.full_mwh } else { $null }
            report_generated  = $reportGenerated
            report_path       = $ReportPath
        }

        $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
            -Severity $severity -Summary $summary -Detail $detail -Commands $commands `
            -NeedsAdmin $false -RanSuccessfully $true `
            -DurationMs ([int]$sw.ElapsedMilliseconds) `
            -Notes $reportNote
    }
} catch {
    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity 'UNKNOWN' -Summary 'Battery check failed.' -Commands $commands `
        -RanSuccessfully $false -ErrorMessage $_.Exception.Message `
        -DurationMs ([int]$sw.ElapsedMilliseconds)
}

$sw.Stop()
$result.duration_ms = [int]$sw.ElapsedMilliseconds
$result | Write-HealthResult -Human:$Human
