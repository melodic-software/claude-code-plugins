#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Invoke-CustomCheckClamp.ps1'

    function New-Run {
        param([hashtable] $Severities = @{}, [string[]] $ChecksRan)
        if (-not $PSBoundParameters.ContainsKey('ChecksRan')) { $ChecksRan = @($Severities.Keys) }
        [pscustomobject]@{
            run_id           = '2026-09-01T00:00:00Z'
            checks_ran       = $ChecksRan
            check_severities = [pscustomobject]$Severities
            top_metrics      = [pscustomobject]@{}
        } | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    }

    function New-Result {
        param([string] $Id, [string] $Severity, $AdjustedFrom = $null)
        [pscustomobject]@{
            id       = $Id
            severity = $Severity
            notes    = ''
            trend    = [ordered]@{ last_run = $null; delta = $null; adjusted_from = $AdjustedFrom }
        }
    }
}

Describe 'Invoke-CustomCheckClamp' -Tag 'lib' {
    It 'caps a first-run custom CRIT at WARN and says why' {
        $out = Invoke-CustomCheckClamp -CheckResults @(New-Result -Id 'my-check' -Severity 'CRIT') `
            -CustomIds @('my-check') -HistoryTail @()
        $out[0].severity | Should -Be 'WARN'
        $out[0].notes | Should -Match 'custom check clamp: CRIT capped at WARN until it reports clean in 3 runs \(0 so far\)'
    }

    It 'never touches a shipped check' {
        $out = Invoke-CustomCheckClamp -CheckResults @(New-Result -Id 'drivers' -Severity 'CRIT') `
            -CustomIds @('my-check') -HistoryTail @()
        $out[0].severity | Should -Be 'CRIT'
        $out[0].notes | Should -BeNullOrEmpty
    }

    It 'leaves a custom WARN or lower alone' {
        $out = Invoke-CustomCheckClamp -CheckResults @(New-Result -Id 'my-check' -Severity 'WARN') `
            -CustomIds @('my-check') -HistoryTail @()
        $out[0].severity | Should -Be 'WARN'
        $out[0].notes | Should -BeNullOrEmpty
    }

    It 'lets CRIT through once the check has reported clean in 3 runs, not necessarily consecutive' {
        $history = @(
            New-Run -Severities @{ 'my-check' = 'OK' }
            New-Run -Severities @{ 'my-check' = 'WARN' }
            New-Run -Severities @{ 'my-check' = 'INFO' }
            New-Run -Severities @{ 'my-check' = 'OK' }
        )
        $out = Invoke-CustomCheckClamp -CheckResults @(New-Result -Id 'my-check' -Severity 'CRIT') `
            -CustomIds @('my-check') -HistoryTail $history
        $out[0].severity | Should -Be 'CRIT'
    }

    It 'counts only runs where the check ran and carries a recorded severity' {
        $history = @(
            New-Run -Severities @{ 'my-check' = 'OK' }
            New-Run -Severities @{ 'my-check' = 'OK' }
            New-Run -Severities @{ 'my-check' = 'OK' } -ChecksRan @('disk-space')
            ([pscustomobject]@{ run_id = 'old'; checks_ran = @('my-check'); top_metrics = [pscustomobject]@{} })
        )
        $out = Invoke-CustomCheckClamp -CheckResults @(New-Result -Id 'my-check' -Severity 'CRIT') `
            -CustomIds @('my-check') -HistoryTail $history
        $out[0].severity | Should -Be 'WARN'
        $out[0].notes | Should -Match '\(2 so far\)'
    }

    It 'clears a trend adjusted_from the clamp undid' {
        $out = Invoke-CustomCheckClamp -CheckResults @(New-Result -Id 'my-check' -Severity 'CRIT' -AdjustedFrom 'WARN') `
            -CustomIds @('my-check') -HistoryTail @()
        $out[0].severity | Should -Be 'WARN'
        $out[0].trend.adjusted_from | Should -BeNullOrEmpty
    }
}
