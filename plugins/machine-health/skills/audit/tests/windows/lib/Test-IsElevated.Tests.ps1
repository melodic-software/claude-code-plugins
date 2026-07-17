#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Test-IsElevated.ps1.

.DESCRIPTION
Test-IsElevated consults .NET static types (WindowsIdentity.GetCurrent,
WindowsPrincipal.IsInRole) which cannot be mocked at module boundaries. These
tests cover what we can actually assert without OS-level privilege mutation:
return shape, exception-safety, and consistency with an independent probe of
the running process.
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:LibRoot = Join-Path (Split-Path -Parent $script:TestsRoot) 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Test-IsElevated.ps1')
}

Describe 'Test-IsElevated' -Tag 'lib' {
    Context 'contract' {
        It 'returns a boolean' {
            $result = Test-IsElevated
            $result | Should -BeOfType [bool]
        }

        It 'does not throw under normal execution' {
            { Test-IsElevated } | Should -Not -Throw
        }

        It 'is side-effect free (repeatable)' {
            $first = Test-IsElevated
            $second = Test-IsElevated
            $first | Should -Be $second
        }
    }

    Context 'platform gating' {
        It 'matches an independent probe of current process elevation on Windows' -Skip:(-not $IsWindows) {
            $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
            $expected = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

            Test-IsElevated | Should -Be $expected
        }

        It 'returns false on non-Windows platforms' -Skip:($IsWindows) {
            Test-IsElevated | Should -BeFalse
        }
    }
}
