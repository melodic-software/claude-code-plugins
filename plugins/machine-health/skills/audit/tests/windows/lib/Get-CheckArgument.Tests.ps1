#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Get-CheckArgument.ps1 -- the per-check argument
splat the orchestrator injects when dispatching a check.
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:LibRoot = Join-Path (Split-Path -Parent $script:TestsRoot) 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Get-CheckArgument.ps1')
}

Describe 'Get-CheckArgument' -Tag 'lib' {
    It 'gives the battery check a -ReportPath so capacity analysis can run' {
        $splat = Get-CheckArgument -CheckId 'battery' -RunLog 'C:\logs\run.log' -BatteryReportPath 'C:\logs\battery.html'
        $splat.ContainsKey('ReportPath') | Should -BeTrue
        $splat['ReportPath'] | Should -Be 'C:\logs\battery.html'
    }

    It 'gives the winget check a -LogPath so the KEV fetch is logged' {
        $splat = Get-CheckArgument -CheckId 'winget-upgrades' -RunLog 'C:\logs\run.log' -BatteryReportPath 'C:\logs\battery.html'
        $splat.ContainsKey('LogPath') | Should -BeTrue
        $splat['LogPath'] | Should -Be 'C:\logs\run.log'
    }

    It 'returns an empty hashtable for a check that takes no run-scoped arguments' {
        $splat = Get-CheckArgument -CheckId 'disk-space' -RunLog 'C:\logs\run.log' -BatteryReportPath 'C:\logs\battery.html'
        $splat | Should -BeOfType [hashtable]
        $splat.Count | Should -Be 0
    }
}
