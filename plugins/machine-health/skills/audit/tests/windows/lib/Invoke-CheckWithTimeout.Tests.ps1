#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Invoke-CheckWithTimeout.ps1 -- the Start-Job
dispatcher the orchestrator runs every check through.

.DESCRIPTION
Fixture checks are written to TestDrive at run time. The job runs in another
process, which has no TestDrive: drive, so every path handed to it is the
real $TestDrive path.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Invoke-CheckWithTimeout.ps1'

    function Write-FixtureCheck {
        param([Parameter(Mandatory)] [string] $Name, [Parameter(Mandatory)] [string] $Body)
        $path = Join-Path $TestDrive "$Name.ps1"
        Set-Content -LiteralPath $path -Value $Body -Encoding utf8
        return $path
    }
}

Describe 'Invoke-CheckWithTimeout' -Tag 'lib' {
    It 'returns the parsed JSON a check prints' {
        $path = Write-FixtureCheck -Name 'ok' -Body '''{"id":"fixture","severity":"INFO"}'''
        $dispatch = Invoke-CheckWithTimeout -ScriptPath $path -TimeoutSec 60
        $dispatch.ok | Should -BeTrue
        $dispatch.result.id | Should -Be 'fixture'
        $dispatch.result.severity | Should -Be 'INFO'
    }

    Context 'a string[] argument crosses the job boundary intact' {
        BeforeAll {
            $script:echoPath = Write-FixtureCheck -Name 'echo-names' -Body @'
param([string[]] $Names = @('unset'))
ConvertTo-Json -Compress -InputObject @{ count = $Names.Count; names = @($Names) }
'@
        }

        It 'keeps every element, including one holding a space' {
            $dispatch = Invoke-CheckWithTimeout -ScriptPath $script:echoPath -TimeoutSec 60 `
                -Arguments @{ Names = [string[]]@('startup:7eef5f7d094fe8c0', 'a b') }
            $dispatch.ok | Should -BeTrue
            $dispatch.result.count | Should -Be 2
            $dispatch.result.names | Should -Be @('startup:7eef5f7d094fe8c0', 'a b')
        }

        It 'keeps a one-element array an array' {
            $dispatch = Invoke-CheckWithTimeout -ScriptPath $script:echoPath -TimeoutSec 60 `
                -Arguments @{ Names = [string[]]@('ext:3f9a0c1d2e4b5a67') }
            $dispatch.result.count | Should -Be 1
            @($dispatch.result.names) | Should -Be @('ext:3f9a0c1d2e4b5a67')
        }

        It 'binds an empty array as empty, not as the parameter default' {
            $dispatch = Invoke-CheckWithTimeout -ScriptPath $script:echoPath -TimeoutSec 60 `
                -Arguments @{ Names = [string[]]@() }
            $dispatch.result.count | Should -Be 0
        }
    }

    Context 'failure reasons' {
        It 'reports timeout when the check outlives TimeoutSec' {
            $path = Write-FixtureCheck -Name 'slow' -Body 'Start-Sleep -Seconds 30; ''{}'''
            $dispatch = Invoke-CheckWithTimeout -ScriptPath $path -TimeoutSec 2
            $dispatch.ok | Should -BeFalse
            $dispatch.reason | Should -Be 'timeout'
            $dispatch.elapsed_ms | Should -BeLessThan 30000
        }

        It 'reports no_output when the check prints nothing' {
            $path = Write-FixtureCheck -Name 'silent' -Body '$null = 1'
            $dispatch = Invoke-CheckWithTimeout -ScriptPath $path -TimeoutSec 60
            $dispatch.ok | Should -BeFalse
            $dispatch.reason | Should -Be 'no_output'
        }

        It 'reports invalid_json with the raw output when the check prints non-JSON' {
            $path = Write-FixtureCheck -Name 'garbled' -Body '''not json'''
            $dispatch = Invoke-CheckWithTimeout -ScriptPath $path -TimeoutSec 60
            $dispatch.ok | Should -BeFalse
            $dispatch.reason | Should -Be 'invalid_json'
            $dispatch.raw_output | Should -Be 'not json'
        }
    }
}
