#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Get-CheckArgument.ps1 -- the per-check argument
splat the orchestrator injects when dispatching a check.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript @(
        'Get-CheckArgument.ps1', 'Invoke-CheckWithTimeout.ps1')
    $script:ChecksRoot = Join-Path $script:SkillRoot 'scripts\windows\checks'

    function Write-FixtureCheck {
        param([Parameter(Mandatory)] [string] $Name, [Parameter(Mandatory)] [string] $Body)
        $path = Join-Path $TestDrive "$Name.ps1"
        Set-Content -LiteralPath $path -Value $Body -Encoding utf8
        return $path
    }
}

Describe 'Get-CheckArgument' -Tag 'lib' {
    It 'gives the battery check a -ReportPath so capacity analysis can run' {
        $splat = Get-CheckArgument -CheckId 'battery' -ScriptPath (Join-Path $script:ChecksRoot 'Test-Battery.ps1') `
            -RunLog 'C:\logs\run.log' -BatteryReportPath 'C:\logs\battery.html'
        $splat.ContainsKey('ReportPath') | Should -BeTrue
        $splat['ReportPath'] | Should -Be 'C:\logs\battery.html'
    }

    It 'gives the winget check a -LogPath so the KEV fetch is logged' {
        $splat = Get-CheckArgument -CheckId 'winget-upgrades' -ScriptPath (Join-Path $script:ChecksRoot 'Test-WingetUpgrades.ps1') `
            -RunLog 'C:\logs\run.log' -BatteryReportPath 'C:\logs\battery.html'
        $splat.ContainsKey('LogPath') | Should -BeTrue
        $splat['LogPath'] | Should -Be 'C:\logs\run.log'
    }

    It 'returns an empty hashtable for a check that takes no run-scoped arguments' {
        $splat = Get-CheckArgument -CheckId 'disk-health' -ScriptPath (Join-Path $script:ChecksRoot 'Test-DiskHealth.ps1') `
            -RunLog 'C:\logs\run.log' -BatteryReportPath 'C:\logs\battery.html' -MutedKeys @('startup:7eef5f7d094fe8c0')
        $splat | Should -BeOfType [hashtable]
        $splat.Count | Should -Be 0
    }

    Context 'muted finding keys follow the script''s declared parameters' {
        BeforeAll {
            $script:declaring = Write-FixtureCheck -Name 'declares-muted' -Body @'
param([string[]] $MutedKeys = @('unset'))
ConvertTo-Json -Compress -InputObject @{ count = $MutedKeys.Count; keys = @($MutedKeys) }
'@
            $script:notDeclaring = Write-FixtureCheck -Name 'no-muted' -Body @'
param([switch] $Human)
'{"ran":true}'
'@
        }

        It 'gives a script that declares -MutedKeys its keys as a string[]' {
            $splat = Get-CheckArgument -CheckId 'startup-items' -ScriptPath $script:declaring `
                -MutedKeys @('startup:7eef5f7d094fe8c0', 'ext:dfe36cc7950bcbf3')
            @($splat.Keys) | Should -Be @('MutedKeys')
            , $splat['MutedKeys'] | Should -BeOfType [string[]]
            $splat['MutedKeys'] | Should -Be @('startup:7eef5f7d094fe8c0', 'ext:dfe36cc7950bcbf3')
        }

        It 'gives a declaring script an empty string[] when nothing is muted' {
            $splat = Get-CheckArgument -CheckId 'startup-items' -ScriptPath $script:declaring -MutedKeys $null
            , $splat['MutedKeys'] | Should -BeOfType [string[]]
            $splat['MutedKeys'].Count | Should -Be 0
        }

        It 'leaves -MutedKeys out for a script that does not declare it, and that script still dispatches' {
            $splat = Get-CheckArgument -CheckId 'startup-items' -ScriptPath $script:notDeclaring `
                -MutedKeys @('startup:7eef5f7d094fe8c0')
            $splat.ContainsKey('MutedKeys') | Should -BeFalse
            $dispatch = Invoke-CheckWithTimeout -ScriptPath $script:notDeclaring -TimeoutSec 60 -Arguments $splat
            $dispatch.ok | Should -BeTrue
            $dispatch.result.ran | Should -BeTrue
        }

        It 'gives a list-style battery check both -ReportPath and -MutedKeys' {
            $both = Write-FixtureCheck -Name 'battery-with-items' -Body 'param([string] $ReportPath, [string[]] $MutedKeys)'
            $splat = Get-CheckArgument -CheckId 'battery' -ScriptPath $both -BatteryReportPath 'C:\logs\battery.html' `
                -MutedKeys @('startup:7eef5f7d094fe8c0')
            $splat['ReportPath'] | Should -Be 'C:\logs\battery.html'
            $splat['MutedKeys'] | Should -Be @('startup:7eef5f7d094fe8c0')
        }
    }

    Context 'the run''s sampling window' {
        It 'gives top-processes the run''s -SampleSeconds' {
            $splat = Get-CheckArgument -CheckId 'top-processes' `
                -ScriptPath (Join-Path $script:ChecksRoot 'Test-TopProcesses.ps1') -SampleSeconds 60
            $splat['SampleSeconds'] | Should -Be 60
        }

        It 'leaves -SampleSeconds out when the orchestrator passes none, so the script default stands' {
            $splat = Get-CheckArgument -CheckId 'top-processes' `
                -ScriptPath (Join-Path $script:ChecksRoot 'Test-TopProcesses.ps1')
            $splat.ContainsKey('SampleSeconds') | Should -BeFalse
        }

        It 'keeps the base dispatch timeout for a check that does not sample' {
            Get-CheckTimeoutSec -Arguments @{ MutedKeys = [string[]]@() } | Should -Be 90
            Get-CheckTimeoutSec -Arguments @{ SampleSeconds = 15 } | Should -Be 90
        }

        It 'stretches the dispatch timeout to the window plus its margin when that is longer' {
            Get-CheckTimeoutSec -Arguments @{ SampleSeconds = 75 } | Should -Be 105
        }

        It 'allows a window that reaches the sustained window and fits under its timeout' {
            $orchestrator = Join-Path $script:SkillRoot 'scripts\windows\Invoke-MachineHealthCheck.ps1'
            $range = (Get-Command -Name $orchestrator -CommandType ExternalScript).Parameters['SampleSeconds'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $max = [int]$range.MaxRange
            $check = Join-Path $script:ChecksRoot 'Test-TopProcesses.ps1'
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($check, [ref]$null, [ref]$null)
            $assign = $ast.Find({
                    param($n)
                    $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $n.Left.Extent.Text -ceq '$SustainedSeconds'
                }, $false)
            $sustained = [int]$assign.Right.Extent.Text
            $max | Should -BeGreaterOrEqual $sustained
            Get-CheckTimeoutSec -Arguments @{ SampleSeconds = $max } | Should -BeGreaterThan $max
        }

        It 'never gives -SampleSeconds to a check that does not declare it' {
            $splat = Get-CheckArgument -CheckId 'disk-health' `
                -ScriptPath (Join-Path $script:ChecksRoot 'Test-DiskHealth.ps1') -SampleSeconds 60
            $splat.ContainsKey('SampleSeconds') | Should -BeFalse
        }
    }
}
