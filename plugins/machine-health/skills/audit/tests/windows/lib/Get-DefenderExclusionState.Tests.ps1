#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Get-DefenderExclusionState.ps1.

.DESCRIPTION
The masked placeholder is the one a standard-user MSFT_MpPreference read
returned on a fleet host: each exclusion list holds a single "N/A: ..." string.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-DefenderExclusionState.ps1'

    if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
        function Get-CimInstance {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSAvoidOverwritingBuiltInCmdlets', '',
                Justification = 'Defined only when the Cim cmdlets are absent so Pester can mock the call.')]
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSReviewUnusedParameter', 'Namespace',
                Justification = 'Declared so the mocks'' ParameterFilter can bind it; the stub only throws.')]
            param([string] $Namespace, [string] $ClassName)
            throw "Get-CimInstance is not available ($ClassName)"
        }
    }

    $script:Placeholder = 'N/A: Must be an administrator to view exclusions'
}

Describe 'Get-DefenderExclusionState' -Tag 'lib' {
    It 'reports masked with empty lists and reads nothing when not elevated' {
        Mock Test-IsElevated { $false }
        Mock Get-CimInstance { throw 'must not be read unelevated' }

        $state = Get-DefenderExclusionState
        $state.ReadState | Should -Be 'masked'
        @($state.Paths).Count | Should -Be 0
        @($state.Extensions).Count | Should -Be 0
        @($state.Processes).Count | Should -Be 0
        Should -Invoke Get-CimInstance -Times 0
    }

    It 'reports masked when an elevated read still returns the placeholder' {
        Mock Test-IsElevated { $true }
        Mock Get-CimInstance {
            [pscustomobject]@{
                ExclusionPath      = @($script:Placeholder)
                ExclusionExtension = @($script:Placeholder)
                ExclusionProcess   = @($script:Placeholder)
            }
        }

        $state = Get-DefenderExclusionState
        $state.ReadState | Should -Be 'masked'
        @($state.Paths).Count | Should -Be 0
    }

    It 'reads the native Defender CIM class elevated and drops null and blank entries' {
        Mock Test-IsElevated { $true }
        Mock Get-CimInstance {
            [pscustomobject]@{
                ExclusionPath      = @('X:\build', '', '   ')
                ExclusionExtension = $null
                ExclusionProcess   = @('tool.exe')
            }
        } -ParameterFilter { $Namespace -eq 'root/Microsoft/Windows/Defender' -and $ClassName -eq 'MSFT_MpPreference' }

        $state = Get-DefenderExclusionState
        $state.ReadState | Should -Be 'ok'
        $state.Paths | Should -Be @('X:\build')
        @($state.Extensions).Count | Should -Be 0
        $state.Processes | Should -Be @('tool.exe')
    }

    It 'reports masked by shape when the placeholder is in another language' {
        Mock Test-IsElevated { $true }
        Mock Get-CimInstance {
            [pscustomobject]@{
                ExclusionPath      = @('N/D: Se requieren permisos de administrador')
                ExclusionExtension = $null
                ExclusionProcess   = $null
            }
        }

        (Get-DefenderExclusionState).ReadState | Should -Be 'masked'
    }

    It 'keeps a single real entry of each shape: rooted path, environment-variable path, extension, file name' {
        Mock Test-IsElevated { $true }
        Mock Get-CimInstance {
            [pscustomobject]@{
                ExclusionPath      = @('%ProgramData%\build')
                ExclusionExtension = @('.tmp')
                ExclusionProcess   = @('X:\tools\tool.exe')
            }
        }

        $state = Get-DefenderExclusionState
        $state.ReadState | Should -Be 'ok'
        $state.Paths | Should -Be @('%ProgramData%\build')
        $state.Extensions | Should -Be @('.tmp')
    }

    It 'reports error when the class returns no instance' {
        Mock Test-IsElevated { $true }
        Mock Get-CimInstance { $null }

        $state = Get-DefenderExclusionState
        $state.ReadState | Should -Be 'error'
        @($state.Paths).Count | Should -Be 0
    }

    It 'reports denied on access denied' {
        Mock Test-IsElevated { $true }
        Mock Get-CimInstance { throw [System.UnauthorizedAccessException]::new('Access denied') }

        (Get-DefenderExclusionState).ReadState | Should -Be 'denied'
    }

    It 'reports error when the class cannot be read' {
        Mock Test-IsElevated { $true }
        Mock Get-CimInstance { throw 'Invalid namespace' }

        $state = Get-DefenderExclusionState
        $state.ReadState | Should -Be 'error'
        @($state.Paths).Count | Should -Be 0
    }
}
