#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:ScriptPath = Join-Path $script:SkillRoot 'scripts\windows\checks\Test-Reliability.ps1'
    $script:LibRoot = Join-Path $script:SkillRoot 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Assert-CheckResult.ps1')
    Import-Module (Join-Path $script:TestsRoot 'helpers\Mock-Helpers.psm1') -Force

    function Invoke-ReliabilityAsObject {
        $raw = & $script:ScriptPath
        $json = ($raw | Where-Object { $_ }) -join "`n"
        return $json | ConvertFrom-Json
    }
}

Describe 'Test-Reliability -- baseline' -Tag 'check' {
    It 'emits INFO with note when RAC data is empty (both metrics + records)' {
        Mock Get-CimInstance { @() }
        $result = Invoke-ReliabilityAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.id | Should -Be 'reliability'
        $result.severity | Should -Be 'INFO'
        $result.notes | Should -Match 'RAC'
    }
}

Describe 'Test-Reliability -- severity rubric' -Tag 'check' {
    It 'reports OK when stability is high and no records' {
        Mock Get-CimInstance {
            if ($ClassName -eq 'Win32_ReliabilityStabilityMetrics') {
                1..7 | ForEach-Object {
                    New-MockReliabilityStabilityMetric -SystemStabilityIndex 9.8 -TimeGenerated (Get-Date).AddDays(-$_)
                }
            } else { @() }
        }
        $result = Invoke-ReliabilityAsObject
        $result.severity | Should -Be 'OK'
    }

    It 'reports WARN when average stability is < 7' {
        Mock Get-CimInstance {
            if ($ClassName -eq 'Win32_ReliabilityStabilityMetrics') {
                1..7 | ForEach-Object {
                    New-MockReliabilityStabilityMetric -SystemStabilityIndex 6.0 -TimeGenerated (Get-Date).AddDays(-$_)
                }
            } else { @() }
        }
        $result = Invoke-ReliabilityAsObject
        $result.severity | Should -Be 'WARN'
    }

    It 'reports CRIT when any daily stability drops below 3' {
        Mock Get-CimInstance {
            if ($ClassName -eq 'Win32_ReliabilityStabilityMetrics') {
                @(
                    New-MockReliabilityStabilityMetric -SystemStabilityIndex 9.0 -TimeGenerated (Get-Date).AddDays(-1)
                    New-MockReliabilityStabilityMetric -SystemStabilityIndex 2.1 -TimeGenerated (Get-Date).AddDays(-2)
                    New-MockReliabilityStabilityMetric -SystemStabilityIndex 9.0 -TimeGenerated (Get-Date).AddDays(-3)
                )
            } else { @() }
        }
        $result = Invoke-ReliabilityAsObject
        $result.severity | Should -Be 'CRIT'
        $result.summary | Should -Match 'dropped below 3'
    }

    It 'reports CRIT when a hardware-class record is present' {
        Mock Get-CimInstance {
            if ($ClassName -eq 'Win32_ReliabilityStabilityMetrics') {
                1..7 | ForEach-Object {
                    New-MockReliabilityStabilityMetric -SystemStabilityIndex 9.0 -TimeGenerated (Get-Date).AddDays(-$_)
                }
            } else {
                @(
                    New-MockReliabilityRecord -SourceName 'Disk' -ProductName 'Windows' -EventIdentifier 7 `
                        -TimeGenerated (Get-Date).AddHours(-2) -Message 'disk failure'
                )
            }
        }
        $result = Invoke-ReliabilityAsObject
        $result.severity | Should -Be 'CRIT'
    }
}
