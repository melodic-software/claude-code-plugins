#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -Check 'Test-ContainerDiskUsage' -AsObject 'Invoke-ContainerDiskAsObject'
}

Describe 'Test-ContainerDiskUsage -- baseline' -Tag 'check' {
    It 'emits a schema-valid CheckResult when docker and wsl are absent' {
        # Native commands can't be mocked reliably; simulate absence by
        # stubbing Get-Command to return $null for both.
        Mock Get-Command {
            param($Name)
            if ($Name -eq 'docker' -or $Name -eq 'wsl') { return $null }
            return (Microsoft.PowerShell.Core\Get-Command $Name -ErrorAction SilentlyContinue)
        }
        Mock Test-Path { return $false } -ParameterFilter {
            $LiteralPath -like '*Packages*'
        }
        $result = Invoke-ContainerDiskAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.id | Should -Be 'container-disk-usage'
        $result.severity | Should -Be 'OK'
        $result.summary | Should -Match 'No container disk signals'
    }
}
