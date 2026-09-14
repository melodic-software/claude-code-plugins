#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/checks/Test-Services.ps1.

.DESCRIPTION
Pins the rubric:

1. Trigger-start services stopped are EXPECTED, not a finding. Flagging
   any Automatic service in Stopped state as WARN would produce false
   positives for modern Windows trigger-start services (dnscache,
   WSearch, gupdate, edgeupdate, MapsBroker, and many more).

2. The DelayedAutoStart + uptime-based downgrade never masks a
   concurrent plain-Auto stopped service: the bucket structure sorts
   stopped services by kind before computing severity.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -Check 'Test-Services' `
        -AsObject 'Invoke-ServicesAsObject' -LibScript 'Test-ServiceTriggerStart.ps1' -MockHelpers

    function New-MockCimService {
        param(
            [Parameter(Mandatory)] [string] $Name,
            [string] $StartMode = 'Auto',
            [bool] $DelayedAutoStart = $false
        )
        [pscustomobject]@{
            Name             = $Name
            StartMode        = $StartMode
            DelayedAutoStart = $DelayedAutoStart
        }
    }

    function Set-UptimeMock {
        param([int] $Minutes)
        $bootTime = (Get-Date).AddMinutes(-$Minutes)
        $mockBody = {
            [pscustomobject]@{ LastBootUpTime = $bootTime }
        }.GetNewClosure()
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } -MockWith $mockBody
    }
}

Describe 'Test-Services -- healthy baseline' -Tag 'check' {
    BeforeAll {
        Set-UptimeMock -Minutes 120
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Service' } -MockWith {
            @(New-MockCimService -Name 'W32Time' -StartMode 'Auto')
        }
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_StartupCommand' } -MockWith { @() }
        Mock Get-Service {
            @(
                New-MockService -Name 'W32Time' -Status 'Running' -StartType 'Automatic'
                New-MockService -Name 'Spooler' -Status 'Running' -StartType 'Automatic'
            )
        }
        Mock Test-ServiceTriggerStart { $false }
    }

    It 'emits a schema-valid CheckResult' {
        $result = Invoke-ServicesAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.id | Should -Be 'services'
    }

    It 'reports OK when no Automatic services are stopped' {
        $result = Invoke-ServicesAsObject
        $result.severity | Should -Be 'OK'
    }
}

Describe 'Test-Services -- trigger-start services' -Tag 'check' {
    It 'does not flag a stopped trigger-start service' {
        Set-UptimeMock -Minutes 120
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Service' } -MockWith {
            @(New-MockCimService -Name 'dnscache' -StartMode 'Auto')
        }
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_StartupCommand' } -MockWith { @() }
        Mock Get-Service {
            @(New-MockService -Name 'dnscache' -Status 'Stopped' -StartType 'Automatic')
        }
        Mock Test-ServiceTriggerStart { $true }

        $result = Invoke-ServicesAsObject
        # Trigger-start services being stopped is designed behavior --
        # must not show up in the user-facing severity.
        $result.severity | Should -Be 'OK'
    }

    It 'still WARNs when a non-trigger-start service is stopped alongside trigger-start ones' {
        Set-UptimeMock -Minutes 120
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Service' } -MockWith {
            @(
                New-MockCimService -Name 'dnscache' -StartMode 'Auto'
                New-MockCimService -Name 'Spooler' -StartMode 'Auto'
            )
        }
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_StartupCommand' } -MockWith { @() }
        Mock Get-Service {
            @(
                New-MockService -Name 'dnscache' -Status 'Stopped' -StartType 'Automatic'
                New-MockService -Name 'Spooler' -Status 'Stopped' -StartType 'Automatic'
            )
        }
        Mock Test-ServiceTriggerStart {
            param($Name)
            $Name -eq 'dnscache'
        }

        $result = Invoke-ServicesAsObject
        $result.severity | Should -Be 'WARN'
        # Only the unexpected (non-trigger-start) service should surface.
        @($result.detail.stopped_auto_services).Count | Should -Be 1
        $result.detail.stopped_auto_services[0].name | Should -Be 'Spooler'
    }
}

Describe 'Test-Services -- delayed auto-start' -Tag 'check' {
    It 'downgrades to INFO when only DelayedAutoStart services are stopped within 10 min of boot' {
        Set-UptimeMock -Minutes 3
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Service' } -MockWith {
            @(New-MockCimService -Name 'Sense' -StartMode 'Auto' -DelayedAutoStart $true)
        }
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_StartupCommand' } -MockWith { @() }
        Mock Get-Service {
            @(New-MockService -Name 'Sense' -Status 'Stopped' -StartType 'Automatic')
        }
        Mock Test-ServiceTriggerStart { $false }

        $result = Invoke-ServicesAsObject
        $result.severity | Should -Be 'INFO'
    }

    It 'still WARNs when a DelayedAutoStart service is stopped well after boot' {
        Set-UptimeMock -Minutes 120
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Service' } -MockWith {
            @(New-MockCimService -Name 'Sense' -StartMode 'Auto' -DelayedAutoStart $true)
        }
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_StartupCommand' } -MockWith { @() }
        Mock Get-Service {
            @(New-MockService -Name 'Sense' -Status 'Stopped' -StartType 'Automatic')
        }
        Mock Test-ServiceTriggerStart { $false }

        $result = Invoke-ServicesAsObject
        # Uptime > 10 min: DelayedAutoStart has had time to kick in.
        $result.severity | Should -Be 'WARN'
    }

    It 'WARNs when plain-Auto + DelayedAutoStart are both stopped at boot (regression)' {
        Set-UptimeMock -Minutes 3
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Service' } -MockWith {
            @(
                New-MockCimService -Name 'Sense' -StartMode 'Auto' -DelayedAutoStart $true
                New-MockCimService -Name 'Spooler' -StartMode 'Auto' -DelayedAutoStart $false
            )
        }
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_StartupCommand' } -MockWith { @() }
        Mock Get-Service {
            @(
                New-MockService -Name 'Sense' -Status 'Stopped' -StartType 'Automatic'
                New-MockService -Name 'Spooler' -Status 'Stopped' -StartType 'Automatic'
            )
        }
        Mock Test-ServiceTriggerStart { $false }

        $result = Invoke-ServicesAsObject
        # The low-uptime DelayedAutoStart downgrade must not collapse the
        # whole severity to INFO; the plain-Auto Spooler still WARNs.
        $result.severity | Should -Be 'WARN'
    }
}

Describe 'Test-Services -- failure modes' -Tag 'check' {
    It 'emits UNKNOWN when Get-Service fails' {
        Set-UptimeMock -Minutes 120
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Service' } -MockWith { @() }
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_StartupCommand' } -MockWith { @() }
        Mock Get-Service { throw 'SCM unavailable' }
        Mock Test-ServiceTriggerStart { $false }

        $result = Invoke-ServicesAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.severity | Should -Be 'UNKNOWN'
        $result.ran_successfully | Should -BeFalse
    }

    It 'emits UNKNOWN when Get-Service returns zero entries (catastrophic SCM/RPC failure)' {
        # A healthy SCM always exposes hundreds of services; a
        # zero-result return is itself an UNKNOWN signal. If the
        # count-zero check reverts to bare SilentlyContinue, this
        # test fires.
        Set-UptimeMock -Minutes 120
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Service' } -MockWith { @() }
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_StartupCommand' } -MockWith { @() }
        Mock Get-Service { @() }
        Mock Test-ServiceTriggerStart { $false }

        $result = Invoke-ServicesAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.severity | Should -Be 'UNKNOWN'
        $result.ran_successfully | Should -BeFalse
    }

    It 'completes enumeration when Get-Service returns partial results (WaaSMedicSvc ACL class)' {
        # Documents the -ErrorAction SilentlyContinue contract:
        # services that deny query (e.g. WaaSMedicSvc with non-SYSTEM
        # caller) are silently skipped by the cmdlet, so a populated
        # but partial result must still produce a structured WARN/OK
        # outcome -- not UNKNOWN.
        Set-UptimeMock -Minutes 120
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Service' } -MockWith { @() }
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_StartupCommand' } -MockWith { @() }
        Mock Get-Service { @(New-MockService -Name 'Spooler' -Status 'Stopped' -StartType 'Automatic') }
        Mock Test-ServiceTriggerStart { $false }

        $result = Invoke-ServicesAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.ran_successfully | Should -BeTrue
        $result.severity | Should -Be 'WARN'
    }
}
