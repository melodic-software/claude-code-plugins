#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:LibPath = Join-Path $script:SkillRoot 'scripts\windows\lib\Get-VendorUpdateCli.ps1'
    . $script:LibPath
}

Describe 'Get-VendorUpdateCli' -Tag 'lib' {
    It 'returns empty array when no vendor CLIs are present' {
        Mock Test-Path { $false }
        Mock Get-AppxPackage { $null }
        $result = @(Get-VendorUpdateCli)
        $result.Count | Should -Be 0
    }

    It 'detects Dell Command Update when dcu-cli.exe exists' {
        Mock Test-Path {
            param($LiteralPath) $LiteralPath -like '*dcu-cli.exe'
        }
        Mock Get-AppxPackage { $null }
        $result = @(Get-VendorUpdateCli)
        $result.Count | Should -BeGreaterOrEqual 1
        ($result | Where-Object vendor -EQ 'Dell').Count | Should -Be 1
    }

    It 'detects MyASUS via AppxPackage' {
        Mock Test-Path { $false }
        Mock Get-AppxPackage {
            [pscustomobject]@{ Name = 'MyASUS'; InstallLocation = 'C:\MyASUS' }
        }
        $result = @(Get-VendorUpdateCli)
        ($result | Where-Object vendor -EQ 'ASUS').Count | Should -Be 1
    }

    It 'each record has required shape fields' {
        Mock Test-Path {
            param($LiteralPath) $LiteralPath -like '*dcu-cli.exe'
        }
        Mock Get-AppxPackage { $null }
        $result = @(Get-VendorUpdateCli)
        foreach ($r in $result) {
            $r.PSObject.Properties.Name | Should -Contain 'vendor'
            $r.PSObject.Properties.Name | Should -Contain 'cli_name'
            $r.PSObject.Properties.Name | Should -Contain 'path'
            $r.PSObject.Properties.Name | Should -Contain 'rationale'
        }
    }
}
