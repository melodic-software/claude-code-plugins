#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Get-CheckArgument.ps1 -- the per-check argument
splat the orchestrator injects when dispatching a check.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-CheckArgument.ps1'
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

    Context 'muted finding keys' {
        It 'gives <_> its muted keys as a string[]' -ForEach @(
            'top-processes', 'startup-items', 'storage-top-n', 'app-last-use',
            'browser-extensions', 'network-listeners', 'backup-status', 'firewall-rules'
        ) {
            $splat = Get-CheckArgument -CheckId $_ -RunLog 'C:\logs\run.log' -BatteryReportPath 'C:\logs\battery.html' `
                -MutedKeys @('startup:7eef5f7d094fe8c0', 'ext:dfe36cc7950bcbf3')
            @($splat.Keys) | Should -Be @('MutedKeys')
            , $splat['MutedKeys'] | Should -BeOfType [string[]]
            $splat['MutedKeys'] | Should -Be @('startup:7eef5f7d094fe8c0', 'ext:dfe36cc7950bcbf3')
        }

        It 'gives a listed check an empty string[] when nothing is muted' {
            $splat = Get-CheckArgument -CheckId 'startup-items' -RunLog 'C:\logs\run.log' -MutedKeys $null
            , $splat['MutedKeys'] | Should -BeOfType [string[]]
            $splat['MutedKeys'].Count | Should -Be 0
        }

        It 'never gives MutedKeys to <_>, which does not declare it' -ForEach @('disk-space', 'battery', 'winget-upgrades', 'defender') {
            $splat = Get-CheckArgument -CheckId $_ -RunLog 'C:\logs\run.log' -BatteryReportPath 'C:\logs\battery.html' `
                -MutedKeys @('startup:7eef5f7d094fe8c0')
            $splat.ContainsKey('MutedKeys') | Should -BeFalse
        }
    }
}
