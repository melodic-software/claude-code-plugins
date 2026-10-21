#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Format-CheckLabel.ps1.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Format-CheckLabel.ps1'
}

Describe 'Format-CheckLabel' -Tag 'lib' {
    It 'labels a shipped check with its bare id' {
        Format-CheckLabel -Id 'disk-space' -CustomIds @() | Should -BeExactly 'disk-space'
    }

    It 'labels a shipped check with its bare id when another id is custom' {
        Format-CheckLabel -Id 'disk-space' -CustomIds @('my-custom-check') | Should -BeExactly 'disk-space'
    }

    It 'marks a custom check id' {
        Format-CheckLabel -Id 'my-custom-check' -CustomIds @('my-custom-check') |
            Should -BeExactly 'my-custom-check [custom]'
    }

    It 'fails when -CustomIds is omitted' {
        # A runspace with no host UI cannot prompt, so a missing mandatory
        # parameter fails instead of waiting for input.
        $ps = [powershell]::Create()
        try {
            [void]$ps.AddScript(". '$(Join-Path $script:LibRoot 'Format-CheckLabel.ps1')'; Format-CheckLabel -Id 'disk-space'")
            $output = $ps.Invoke()
            $output | Should -BeNullOrEmpty
            $ps.Streams.Error.Count | Should -Be 1
            $ps.Streams.Error[0].FullyQualifiedErrorId | Should -BeLike 'MissingMandatoryParameter*'
            $ps.Streams.Error[0].Exception.Message | Should -BeLike '*CustomIds*'
        } finally {
            $ps.Dispose()
        }
    }
}
