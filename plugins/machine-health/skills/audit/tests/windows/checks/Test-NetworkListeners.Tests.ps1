#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/checks/Test-NetworkListeners.ps1, with Get-ListenerOwner
mocked. Expected severities follow check-catalog.md section 24: unresolved
UNKNOWN, loopback INFO, exposed and unsigned or user-writable WARN.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -Check 'Test-NetworkListeners' `
        -LibScript 'New-FindingItem.ps1', 'Get-ListenerOwner.ps1'

    function Invoke-NetworkListenersAsObject {
        param([string[]] $MutedKeys = @())
        return ConvertFrom-CheckOutput (& $script:ScriptPath -MutedKeys $MutedKeys)
    }

    # Outside every user-writable folder (TestDrive sits under TEMP, which is one).
    $script:SignedPath = Join-Path $env:ProgramFiles 'Vendor\server.exe'

    function Get-TestListener {
        param([string] $Protocol = 'tcp', [int] $Port = 8080, [string] $Scope = 'any', [int] $ProcessId = 100,
            [string] $Name = 'server', [string] $Path = $script:SignedPath, [string] $Source = 'process',
            [string] $Status = 'Valid')
        [pscustomobject]@{
            Protocol = $Protocol; LocalAddress = ''; Port = $Port; BindScope = $Scope; Pid = $ProcessId
            ProcessName = $Name; Path = ($Source -in @('process', 'service') ? $Path : $null); PathSource = $Source
            SignatureStatus = ($Source -in @('process', 'service') ? $Status : $null); IsOsBinary = $false
        }
    }

    # Mock bodies run inside the check script, where $script: names the check's
    # scope, so the fake read lives in one table the mock reaches by closure.
    $script:Fake = @{}
    $fake = $script:Fake
    Set-Item -Path function:Get-FakeOwner -Value ({ $fake['read'] }.GetNewClosure())

    function Register-FakeOwner {
        param([object[]] $Listeners = @(), [string] $ReadState = 'ok', [string] $ServiceState = 'ok')
        $script:Fake['read'] = [pscustomobject]@{
            ReadState = $ReadState; ServiceState = $ServiceState; EstablishedCount = 3; Listeners = $Listeners
        }
    }
}

Describe 'Test-NetworkListeners' -Tag 'check' {
    BeforeEach {
        Register-FakeOwner
        Mock Get-ListenerOwner { Get-FakeOwner }
    }

    It 'reports OK with no listeners and the socket table read' {
        $r = Invoke-NetworkListenersAsObject
        { Assert-CheckResult $r } | Should -Not -Throw
        $r.error | Should -BeNullOrEmpty
        $r.id | Should -Be 'network-listeners'
        $r.category | Should -Be 'security'
        $r.needs_admin | Should -BeFalse
        $r.severity | Should -Be 'OK'
        $r.detail.established_count | Should -Be 3
    }

    It 'lists a loopback listener as INFO even when unsigned' {
        Register-FakeOwner -Listeners @(Get-TestListener -Scope 'loopback' -Status 'NotSigned')
        $r = Invoke-NetworkListenersAsObject
        $r.severity | Should -Be 'INFO'
        $r.detail.items[0].key | Should -Match '^listener:[0-9a-f]{16}$'
    }

    It 'lists an exposed, validly signed listener outside user folders as INFO' {
        Register-FakeOwner -Listeners @(Get-TestListener)
        (Invoke-NetworkListenersAsObject).severity | Should -Be 'INFO'
    }

    It 'warns on an exposed listener whose binary is <Case>' -TestCases @(
        @{ Case = 'unsigned'; Scope = 'any'; Status = 'NotSigned'; InProfile = $false }
        @{ Case = 'signed but under LOCALAPPDATA'; Scope = 'specific'; Status = 'Valid'; InProfile = $true }
    ) {
        $path = if ($InProfile) { Join-Path $env:LOCALAPPDATA 'Programs\tool\tool.exe' } else { $script:SignedPath }
        Register-FakeOwner -Listeners @(Get-TestListener -Scope $Scope -Status $Status -Path $path)
        $r = Invoke-NetworkListenersAsObject
        $r.severity | Should -Be 'WARN'
        $r.detail.exposed_unsigned_count | Should -Be 1
        $r.detail.items[0].user_writable_path | Should -Be $InProfile
    }

    It 'never calls a kernel listener unsigned' {
        Register-FakeOwner -Listeners @(Get-TestListener -Source 'kernel' -ProcessId 4 -Name 'System' -Port 445)
        $r = Invoke-NetworkListenersAsObject
        $r.severity | Should -Be 'INFO'
        $r.detail.items[0].key | Should -Match '^listener:'
    }

    It 'reports an unresolved listener as UNKNOWN with no key, and it cannot be muted' {
        Register-FakeOwner -Listeners @(Get-TestListener -Source 'unresolved' -Name 'mystery' -Port 7000)
        $r = Invoke-NetworkListenersAsObject
        { Assert-CheckResult $r } | Should -Not -Throw
        $r.severity | Should -Be 'UNKNOWN'
        $r.detail.items[0].key | Should -BeNullOrEmpty
        $r.detail.items[0].muted | Should -BeFalse
        $r.detail.unresolved_count | Should -Be 1
    }

    It 'merges one program on one port over IPv4 and IPv6 into one item at its widest bind' {
        Register-FakeOwner -Listeners @(
            (Get-TestListener -Scope 'loopback' -Status 'NotSigned')
            (Get-TestListener -Scope 'any' -Status 'NotSigned')
        )
        $r = Invoke-NetworkListenersAsObject
        $r.detail.items_count | Should -Be 1
        $r.detail.items[0].bind_scope | Should -Be 'any'
        $r.severity | Should -Be 'WARN'
    }

    It 'keys a listener by path, protocol and port, so a muted WARN stays listed and stops counting' {
        Register-FakeOwner -Listeners @(Get-TestListener -Status 'NotSigned')
        $key = Get-FindingKey -Kind 'listener' -Identity @($script:SignedPath, 'tcp', '8080')
        $r = Invoke-NetworkListenersAsObject -MutedKeys @($key)
        $r.detail.items[0].key | Should -Be $key
        $r.detail.items[0].muted | Should -BeTrue
        $r.detail.muted_count | Should -Be 1
        $r.severity | Should -Be 'OK'
    }

    It 'reports UNKNOWN, never OK, when the socket table cannot be read' {
        Register-FakeOwner -ReadState 'error'
        $r = Invoke-NetworkListenersAsObject
        { Assert-CheckResult $r } | Should -Not -Throw
        $r.severity | Should -Be 'UNKNOWN'
        $r.ran_successfully | Should -BeFalse
    }
}
