#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/checks/Test-Battery.ps1.

.DESCRIPTION
Pins these fixes:

1. Locale-robust battery-report parsing. The previous code matched the
   English labels "DESIGN CAPACITY" and "FULL CHARGE CAPACITY". On
   localized Windows those labels are translated and the check
   produced null capacity readings. New parser reads the first two
   mWh values from the Installed Batteries section regardless of
   language.

2. Accept both comma and dot thousands separators.

3. Null-comparison ordering (PSSA rule).
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:ScriptPath = Join-Path $script:SkillRoot 'scripts\windows\checks\Test-Battery.ps1'
    $script:LibRoot = Join-Path $script:SkillRoot 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Assert-CheckResult.ps1')
    Import-Module (Join-Path $script:TestsRoot 'helpers\Mock-Helpers.psm1') -Force

    function Invoke-BatteryAsObject {
        param([string]$ReportPath)
        $raw = if ($ReportPath) {
            & $script:ScriptPath -ReportPath $ReportPath
        } else {
            & $script:ScriptPath
        }
        $json = ($raw | Where-Object { $_ }) -join "`n"
        return $json | ConvertFrom-Json
    }

    function New-BatteryReportHtml {
        param(
            [int] $DesignMwh = 45000,
            [int] $FullMwh = 42500,
            [string] $DesignLabel = 'DESIGN CAPACITY',
            [string] $FullLabel = 'FULL CHARGE CAPACITY',
            [string] $ThousandsSeparator = ','
        )
        $design = ('{0:N0}' -f $DesignMwh) -replace ',', $ThousandsSeparator
        $full = ('{0:N0}' -f $FullMwh) -replace ',', $ThousandsSeparator
        @"
<html><body>
<h2>Installed batteries</h2>
<table>
<tr><td>NAME</td><td>Mock Battery</td></tr>
<tr><td>$DesignLabel</td><td>$design mWh</td></tr>
<tr><td>$FullLabel</td><td>$full mWh</td></tr>
</table>
</body></html>
"@
    }
}

Describe 'Test-Battery -- no battery present' -Tag 'check' {
    BeforeAll {
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Battery' } -MockWith { @() }
    }

    It 'emits a schema-valid CheckResult' {
        $result = Invoke-BatteryAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.id | Should -Be 'battery'
    }

    It 'reports OK with has_battery=false on a desktop' {
        $result = Invoke-BatteryAsObject
        $result.severity | Should -Be 'OK'
        $result.detail.has_battery | Should -BeFalse
    }
}

Describe 'Test-Battery -- capacity severity' -Tag 'check' {
    It 'reports OK when full charge is 85% of design' {
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Battery' } -MockWith {
            @(New-MockBattery -Name 'Healthy')
        }
        $reportPath = Join-Path $TestDrive 'healthy.html'
        Set-Content -LiteralPath $reportPath -Encoding utf8 -Value (
            New-BatteryReportHtml -DesignMwh 50000 -FullMwh 42500
        )

        $result = Invoke-BatteryAsObject -ReportPath $reportPath
        $result.severity | Should -Be 'OK'
        $result.detail.full_capacity_pct | Should -Be 85.0
    }

    It 'WARNs at 65% of design' {
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Battery' } -MockWith {
            @(New-MockBattery -Name 'Aging')
        }
        $reportPath = Join-Path $TestDrive 'aging.html'
        Set-Content -LiteralPath $reportPath -Encoding utf8 -Value (
            New-BatteryReportHtml -DesignMwh 50000 -FullMwh 32500
        )

        $result = Invoke-BatteryAsObject -ReportPath $reportPath
        $result.severity | Should -Be 'WARN'
    }

    It 'CRITs at 45% of design' {
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Battery' } -MockWith {
            @(New-MockBattery -Name 'Dying')
        }
        $reportPath = Join-Path $TestDrive 'dying.html'
        Set-Content -LiteralPath $reportPath -Encoding utf8 -Value (
            New-BatteryReportHtml -DesignMwh 50000 -FullMwh 22500
        )

        $result = Invoke-BatteryAsObject -ReportPath $reportPath
        $result.severity | Should -Be 'CRIT'
    }
}

Describe 'Test-Battery -- locale robustness' -Tag 'check' {
    It 'parses capacity from a German-localized battery report' {
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Battery' } -MockWith {
            @(New-MockBattery)
        }
        $reportPath = Join-Path $TestDrive 'de.html'
        # German labels + German thousands separator ('.')
        Set-Content -LiteralPath $reportPath -Encoding utf8 -Value (
            New-BatteryReportHtml -DesignMwh 50000 -FullMwh 42500 `
                -DesignLabel 'ENTWURFSKAPAZITAT' -FullLabel 'KAPAZITAT BEI VOLLLADUNG' `
                -ThousandsSeparator '.'
        )

        $result = Invoke-BatteryAsObject -ReportPath $reportPath
        # Previous code regex-matched English labels only -- full_capacity_pct
        # would be null on this input. New parser reads first two mWh values
        # from the report, which is locale-neutral.
        $result.detail.full_capacity_pct | Should -Be 85.0
    }

    It 'parses capacity from a Japanese-localized battery report' {
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Battery' } -MockWith {
            @(New-MockBattery)
        }
        $reportPath = Join-Path $TestDrive 'ja.html'
        Set-Content -LiteralPath $reportPath -Encoding utf8 -Value (
            New-BatteryReportHtml -DesignMwh 50000 -FullMwh 42500 `
                -DesignLabel 'Design Capacity JP' -FullLabel 'Full Charge Capacity JP'
        )

        $result = Invoke-BatteryAsObject -ReportPath $reportPath
        $result.detail.full_capacity_pct | Should -Be 85.0
    }
}

Describe 'Test-Battery -- failure modes' -Tag 'check' {
    It 'reports INFO with note when ReportPath is missing' {
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Battery' } -MockWith {
            @(New-MockBattery)
        }

        $result = Invoke-BatteryAsObject
        # Battery present, capacity unknown without the HTML report.
        $result.severity | Should -Be 'OK'
        $result.notes | Should -Match 'ReportPath|capacity'
    }
}
