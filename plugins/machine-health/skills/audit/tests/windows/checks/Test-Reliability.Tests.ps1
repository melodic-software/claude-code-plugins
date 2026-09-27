#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -Check 'Test-Reliability' -AsObject 'Invoke-ReliabilityAsObject' -MockHelpers
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

    It 'renders n/a when the stability average is null and records exist' {
        Mock Get-CimInstance {
            if ($ClassName -eq 'Win32_ReliabilityStabilityMetrics') {
                [pscustomobject]@{
                    TimeGenerated        = (Get-Date).AddDays(-1)
                    SystemStabilityIndex = $null
                }
            } else {
                @(
                    New-MockReliabilityRecord -SourceName 'Application Error' -ProductName 'MockApp'
                )
            }
        }
        $result = Invoke-ReliabilityAsObject
        $result.severity | Should -Be 'INFO'
        $result.summary | Should -Match 'stability avg n/a'
        $result.summary | Should -Not -Match 'avg  /'
    }
}
