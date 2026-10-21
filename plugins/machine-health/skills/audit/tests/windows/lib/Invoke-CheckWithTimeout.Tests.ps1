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
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript @(
        'Invoke-CheckWithTimeout.ps1', 'Get-MutedFindingKey.ps1', 'Get-CheckArgument.ps1')

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

    Context 'end to end: a mute in mutes.json reaches a check through the job path' {
        BeforeAll {
            # The fixture check lists two startup items: Updater (WARN) and Notes (INFO).
            $libPath = (Join-Path $script:LibRoot 'New-FindingItem.ps1') -replace "'", "''"
            $script:fixturePath = Write-FixtureCheck -Name 'startup-fixture' -Body @"
param([string[]] `$MutedKeys = @('unset'))
. '$libPath'
`$items = @(
    New-FindingItem -Kind 'startup' -Identity @('hkcu', 'Updater') -MutedKeys `$MutedKeys -Severity 'WARN' -Title 'Updater'
    New-FindingItem -Kind 'startup' -Identity @('hkcu', 'Notes') -MutedKeys `$MutedKeys -Severity 'INFO' -Title 'Notes'
)
ConvertTo-Json -Depth 10 -Compress -InputObject ([ordered]@{
    id       = 'startup-items'
    severity = Get-UnmutedSeverity -Items `$items
    detail   = [ordered]@{
        items_count = `$items.Count
        muted_count = @(`$items | Where-Object muted).Count
        items       = `$items
    }
})
"@

            # Updater is muted under startup-items. Notes's key sits under another
            # check id, so it must not mute Notes here.
            $stateDir = Join-Path $TestDrive 'e2e\state'
            New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $stateDir 'mutes.json') -Encoding utf8 -Value @'
{
  "schema_version": "1.0",
  "checks": {
    "startup-items": {
      "muted_findings": [ { "key": "startup:7eef5f7d094fe8c0", "label": "Updater", "added_at": "2026-10-21T12:00:00Z" } ]
    },
    "browser-extensions": {
      "muted_findings": [ { "key": "startup:e32b6b01e9fa05ca", "added_at": "2026-10-21T12:00:00Z" } ]
    }
  }
}
'@

            $muteState = Get-MuteState -StateDir $stateDir
            $muted = Get-MutedFindingKey -State $muteState -CheckId 'startup-items'
            $checkArgs = Get-CheckArgument -CheckId 'startup-items' -RunLog (Join-Path $TestDrive 'run.log') `
                -BatteryReportPath (Join-Path $TestDrive 'battery.html') -MutedKeys $muted
            $script:dispatch = Invoke-CheckWithTimeout -ScriptPath $script:fixturePath -TimeoutSec 60 -Arguments $checkArgs
        }

        It 'returns the muted item with muted: true and the other with muted: false' {
            $script:dispatch.ok | Should -BeTrue
            $items = @($script:dispatch.result.detail.items)
            $items.Count | Should -Be 2
            ($items | Where-Object title -EQ 'Updater').muted | Should -BeTrue
            ($items | Where-Object title -EQ 'Updater').key | Should -BeExactly 'startup:7eef5f7d094fe8c0'
            ($items | Where-Object title -EQ 'Notes').muted | Should -BeFalse
        }

        It 'keeps the muted item listed but leaves it out of the check severity' {
            $script:dispatch.result.severity | Should -BeExactly 'INFO'
            $script:dispatch.result.detail.items_count | Should -Be 2
            $script:dispatch.result.detail.muted_count | Should -Be 1
        }
    }
}
