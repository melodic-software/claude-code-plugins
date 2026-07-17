#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:ScriptPath = Join-Path $script:SkillRoot 'scripts\windows\checks\Test-ContainerDiskUsage.ps1'
    $script:LibRoot = Join-Path $script:SkillRoot 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Assert-CheckResult.ps1')

    function Invoke-ContainerDiskAsObject {
        $raw = & $script:ScriptPath
        $json = ($raw | Where-Object { $_ }) -join "`n"
        return $json | ConvertFrom-Json
    }
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
