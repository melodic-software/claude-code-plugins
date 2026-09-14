#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/remediations/Restart-StoppedService.ps1.

.DESCRIPTION
Pins three behaviors of the service-restart remediation:

1. Findings arrive through the -Finding parameter, as either a JSON
   string or a PSCustomObject. Reading them from
   [System.Console]::In.ReadToEnd() is unreliable under Start-Job
   isolation and certain PowerShell hosts.

2. Each target gets exactly one Start-Service attempt; already-
   running services are treated as success (idempotent).

3. Missing services produce an error result rather than throwing,
   so one bad entry doesn't break the whole remediation.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -Remediation 'Restart-StoppedService'

    # Get-Service/Start-Service are Windows-only cmdlets, absent in Linux
    # pwsh, and Pester cannot mock a nonexistent command. Define stubs so
    # Mock can attach; the remediation resolves them from this (parent)
    # scope when invoked via `& $ScriptPath`. Every test mocks both, so
    # the stub bodies never run.
    function Get-Service { }
    function Start-Service { }

    # Get-Service mock body reporting the queried service Stopped for its
    # first $StoppedCalls calls and Running afterwards, so the remediation's
    # before/after reads straddle the restart. Pester mock bodies execute in
    # a scope where $script:* from the test file isn't visible under strict
    # mode, so the call counter rides along in a closure.
    function Get-StoppedThenRunningMock {
        param([Parameter(Mandatory)] [int] $StoppedCalls)
        $state = @{ count = 0; stopped = $StoppedCalls }
        return {
            $state.count++
            $status = if ($state.count -le $state.stopped) { 'Stopped' } else { 'Running' }
            [pscustomobject]@{ Name = $Name; Status = $status; StartType = 'Automatic' }
        }.GetNewClosure()
    }

    function Invoke-RestartAsObject {
        param(
            [string]$ServiceName,
            [string]$FindingJson,
            $Finding
        )
        $raw = if ($ServiceName) {
            & $script:ScriptPath -ServiceName $ServiceName
        } elseif ($FindingJson) {
            & $script:ScriptPath -Finding $FindingJson
        } else {
            & $script:ScriptPath -Finding $Finding
        }
        return ConvertFrom-CheckOutput $raw
    }
}

Describe 'Restart-StoppedService -- -ServiceName parameter' -Tag 'remediation' {
    BeforeEach {
        Mock Start-Service {}
        Mock Start-Sleep {}
    }

    It 'starts a stopped service and reports success' {
        Mock Get-Service (Get-StoppedThenRunningMock -StoppedCalls 1)

        $attempts = @(Invoke-RestartAsObject -ServiceName 'Spooler')
        @($attempts).Count | Should -Be 1
        $attempts[0].succeeded | Should -BeTrue
        Should -Invoke Start-Service -Times 1
    }

    It 'reports failure when Start-Service throws' {
        Mock Get-Service {
            [pscustomobject]@{ Name = 'BadService'; Status = 'Stopped'; StartType = 'Automatic' }
        }
        Mock Start-Service { throw 'Access denied' }

        $attempts = @(Invoke-RestartAsObject -ServiceName 'BadService')
        $attempts[0].succeeded | Should -BeFalse
        $attempts[0].error | Should -Match 'Access denied'
    }

    It 'treats already-running services as success (idempotent)' {
        Mock Get-Service {
            [pscustomobject]@{ Name = 'AlreadyRunning'; Status = 'Running'; StartType = 'Automatic' }
        }

        $attempts = @(Invoke-RestartAsObject -ServiceName 'AlreadyRunning')
        $attempts[0].succeeded | Should -BeTrue
        Should -Invoke Start-Service -Times 0
    }

    It 'reports an error when the service does not exist' {
        Mock Get-Service { throw 'Cannot find any service with service name' }

        $attempts = @(Invoke-RestartAsObject -ServiceName 'NoSuchService')
        $attempts[0].succeeded | Should -BeFalse
        $attempts[0].error | Should -Match 'does not exist|Cannot find'
    }
}

Describe 'Restart-StoppedService -- -Finding parameter contract' -Tag 'remediation' {
    BeforeEach {
        Mock Start-Service {}
        Mock Start-Sleep {}
    }

    It 'accepts a finding as JSON string and targets each stopped service' {
        Mock Get-Service (Get-StoppedThenRunningMock -StoppedCalls 2)

        $finding = @{
            id     = 'services'
            detail = @{
                stopped_auto_services = @(
                    @{ name = 'svc-a' }
                    @{ name = 'svc-b' }
                )
            }
        } | ConvertTo-Json -Depth 5

        $attempts = @(Invoke-RestartAsObject -FindingJson $finding)
        @($attempts).Count | Should -Be 2
        $attempts.target | Sort-Object | Should -Be @('svc-a', 'svc-b')
    }

    It 'accepts a finding as a PSCustomObject directly' {
        Mock Get-Service (Get-StoppedThenRunningMock -StoppedCalls 1)

        $finding = [pscustomobject]@{
            id     = 'services'
            detail = [pscustomobject]@{
                stopped_auto_services = @([pscustomobject]@{ name = 'svc-object' })
            }
        }

        $attempts = @(Invoke-RestartAsObject -Finding $finding)
        @($attempts).Count | Should -Be 1
        $attempts[0].target | Should -Be 'svc-object'
    }

    It 'produces zero attempts when the finding has no stopped services' {
        Mock Get-Service {}

        $finding = @{ id = 'services'; detail = @{ stopped_auto_services = @() } } |
            ConvertTo-Json -Depth 5

        $attempts = @(Invoke-RestartAsObject -FindingJson $finding)
        @($attempts).Count | Should -Be 0
    }

    It 'handles malformed finding JSON gracefully (empty attempts)' {
        Mock Get-Service {}

        $attempts = @(Invoke-RestartAsObject -FindingJson 'not valid json')
        @($attempts).Count | Should -Be 0
    }

    It 'handles structurally-malformed finding (empty object) under strict mode' {
        Mock Get-Service {}

        # Valid JSON, no .detail property -- under Set-StrictMode 3.0 a
        # bare property access throws. Defensive Get-PropertyValue must
        # return an empty target list instead.
        $attempts = @(Invoke-RestartAsObject -FindingJson '{}')
        @($attempts).Count | Should -Be 0
    }

    It 'handles finding missing stopped_auto_services under strict mode' {
        Mock Get-Service {}

        # .detail exists but lacks .stopped_auto_services -- still must
        # return an empty target list without throwing.
        $attempts = @(Invoke-RestartAsObject -FindingJson '{"detail":{"other":1}}')
        @($attempts).Count | Should -Be 0
    }
}
