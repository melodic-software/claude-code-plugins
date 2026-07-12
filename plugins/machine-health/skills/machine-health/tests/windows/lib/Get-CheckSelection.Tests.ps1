#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Get-CheckSelection.ps1 -- cadence-aware selection.
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:LibRoot = Join-Path (Split-Path -Parent $script:TestsRoot) 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Get-CheckSelection.ps1')

    $script:Now = [datetime]::new(2026, 7, 12, 12, 0, 0, [System.DateTimeKind]::Utc)

    function New-Check {
        param([string] $Id, [string] $Cadence)
        $o = [ordered]@{ id = $Id }
        if ($Cadence) { $o['cadence'] = $Cadence }
        [pscustomobject]$o
    }

    function New-HistEntry {
        param([string] $RunId, [string[]] $ChecksRan)
        [pscustomobject]@{ run_id = $RunId; checks_ran = $ChecksRan }
    }

    function Get-DueId { param($Result) @($Result.due | ForEach-Object { $_.id }) }
}

Describe 'Get-CheckSelection -- non-weekly run modes run everything' -Tag 'lib' {
    It 'runs a recently-run monthly check on-demand' {
        $checks = @(New-Check -Id 'cert-expiry' -Cadence 'monthly')
        $hist = @(New-HistEntry -RunId '2026-07-11T12:00:00Z' -ChecksRan @('cert-expiry'))
        $result = Get-CheckSelection -Checks $checks -RunMode 'on-demand' -HistoryTail $hist -Now $script:Now
        Get-DueId $result | Should -Contain 'cert-expiry'
        @($result.skipped).Count | Should -Be 0
    }

    It 'runs a recently-run monthly check on first-run' {
        $checks = @(New-Check -Id 'cert-expiry' -Cadence 'monthly')
        $hist = @(New-HistEntry -RunId '2026-07-11T12:00:00Z' -ChecksRan @('cert-expiry'))
        $result = Get-CheckSelection -Checks $checks -RunMode 'first-run' -HistoryTail $hist -Now $script:Now
        Get-DueId $result | Should -Contain 'cert-expiry'
    }
}

Describe 'Get-CheckSelection -- weekly run cadence gating' -Tag 'lib' {
    It 'always runs a weekly-cadence (or cadence-absent) check' {
        $checks = @(New-Check -Id 'disk-space')  # no cadence -> weekly default
        $hist = @(New-HistEntry -RunId '2026-07-11T12:00:00Z' -ChecksRan @('disk-space'))
        $result = Get-CheckSelection -Checks $checks -RunMode 'weekly' -HistoryTail $hist -Now $script:Now
        Get-DueId $result | Should -Contain 'disk-space'
    }

    It 'defers a monthly check that ran within the monthly interval' {
        $checks = @(New-Check -Id 'cert-expiry' -Cadence 'monthly')  # 10 days ago
        $hist = @(New-HistEntry -RunId '2026-07-02T12:00:00Z' -ChecksRan @('cert-expiry'))
        $result = Get-CheckSelection -Checks $checks -RunMode 'weekly' -HistoryTail $hist -Now $script:Now
        Get-DueId $result | Should -Not -Contain 'cert-expiry'
        @($result.skipped).Count | Should -Be 1
        $result.skipped[0].id | Should -Be 'cert-expiry'
        $result.skipped[0].cadence | Should -Be 'monthly'
        $result.skipped[0].last_run | Should -Be '2026-07-02T12:00:00Z'
        $result.skipped[0].elapsed_days | Should -Be 10
    }

    It 'runs a monthly check whose last run is past the monthly interval' {
        $checks = @(New-Check -Id 'cert-expiry' -Cadence 'monthly')  # 32 days ago
        $hist = @(New-HistEntry -RunId '2026-06-10T12:00:00Z' -ChecksRan @('cert-expiry'))
        $result = Get-CheckSelection -Checks $checks -RunMode 'weekly' -HistoryTail $hist -Now $script:Now
        Get-DueId $result | Should -Contain 'cert-expiry'
        @($result.skipped).Count | Should -Be 0
    }

    It 'runs a monthly check with no recorded last run (safe default)' {
        $checks = @(New-Check -Id 'cert-expiry' -Cadence 'monthly')
        $hist = @(New-HistEntry -RunId '2026-07-02T12:00:00Z' -ChecksRan @('disk-space'))
        $result = Get-CheckSelection -Checks $checks -RunMode 'weekly' -HistoryTail $hist -Now $script:Now
        Get-DueId $result | Should -Contain 'cert-expiry'
    }

    It 'runs a monthly check when the recorded last run is unparseable' {
        $checks = @(New-Check -Id 'cert-expiry' -Cadence 'monthly')
        $hist = @(New-HistEntry -RunId 'not-a-timestamp' -ChecksRan @('cert-expiry'))
        $result = Get-CheckSelection -Checks $checks -RunMode 'weekly' -HistoryTail $hist -Now $script:Now
        Get-DueId $result | Should -Contain 'cert-expiry'
    }

    It 'partitions a mixed set (weekly runs, monthly defers)' {
        $checks = @(
            New-Check -Id 'disk-space'
            New-Check -Id 'cert-expiry' -Cadence 'monthly'
        )
        $hist = @(New-HistEntry -RunId '2026-07-05T12:00:00Z' -ChecksRan @('disk-space', 'cert-expiry'))
        $result = Get-CheckSelection -Checks $checks -RunMode 'weekly' -HistoryTail $hist -Now $script:Now
        Get-DueId $result | Should -Contain 'disk-space'
        Get-DueId $result | Should -Not -Contain 'cert-expiry'
    }
}
