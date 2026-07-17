#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/remediations/Restart-StoppedService.ps1.

.DESCRIPTION
Pins three behaviors of the service-restart remediation:

1. Stdin contract replaced with a -Finding parameter. The previous
   code used [System.Console]::In.ReadToEnd() which is unreliable
   under Start-Job isolation and certain PowerShell hosts. The
   orchestrator now passes findings explicitly as either a JSON
   string or a PSCustomObject.

2. Each target gets exactly one Start-Service attempt; already-
   running services are treated as success (idempotent).

3. Missing services produce an error result rather than throwing,
   so one bad entry doesn't break the whole remediation.
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:ScriptPath = Join-Path $script:SkillRoot 'scripts\windows\remediations\Restart-StoppedService.ps1'

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
        } elseif ($Finding) {
            & $script:ScriptPath -Finding $Finding
        } else {
            & $script:ScriptPath
        }
        $json = ($raw | Where-Object { $_ }) -join "`n"
        if (-not $json) { return @() }
        return $json | ConvertFrom-Json
    }
}

Describe 'Restart-StoppedService -- -ServiceName parameter' -Tag 'remediation' {
    BeforeEach {
        Mock Start-Service {}
        Mock Start-Sleep {}
    }

    It 'starts a stopped service and reports success' {
        # Closure-captured counter: Pester mock bodies execute in a scope where
        # $script:* from the test file isn't visible under strict mode, so use
        # a hashtable captured via GetNewClosure() instead.
        $state = @{ count = 0 }
        Mock Get-Service ({
                $state.count++
                if ($state.count -le 1) {
                    [pscustomobject]@{ Name = 'Spooler'; Status = 'Stopped'; StartType = 'Automatic' }
                } else {
                    [pscustomobject]@{ Name = 'Spooler'; Status = 'Running'; StartType = 'Automatic' }
                }
            }.GetNewClosure())

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
        $state = @{ count = 0 }
        Mock Get-Service ({
                $state.count++
                if ($state.count -le 2) {
                    [pscustomobject]@{ Name = $Name; Status = 'Stopped'; StartType = 'Automatic' }
                } else {
                    [pscustomobject]@{ Name = $Name; Status = 'Running'; StartType = 'Automatic' }
                }
            }.GetNewClosure())

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
        $state = @{ count = 0 }
        Mock Get-Service ({
                $state.count++
                if ($state.count -le 1) {
                    [pscustomobject]@{ Name = $Name; Status = 'Stopped'; StartType = 'Automatic' }
                } else {
                    [pscustomobject]@{ Name = $Name; Status = 'Running'; StartType = 'Automatic' }
                }
            }.GetNewClosure())

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
