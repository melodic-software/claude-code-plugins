#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Format-CheckLabel.ps1.
#>

BeforeDiscovery {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'ConvertFrom-Jsonc.ps1'
    $catalogText = Get-Content -LiteralPath (Join-Path $script:SkillRoot 'catalog\checks.jsonc') -Raw
    $script:ShippedIds = @((ConvertFrom-Jsonc -InputText $catalogText).checks |
            ForEach-Object { @{ Id = [string]$_.id } })
}

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Format-CheckLabel.ps1'
}

Describe 'Format-CheckLabel' -Tag 'lib' {
    It 'discovers the shipped catalog ids' -ForEach @(@{ Count = $script:ShippedIds.Count }) {
        $Count | Should -BeGreaterThan 0
    }

    It 'labels shipped check <Id> with its bare id' -ForEach $script:ShippedIds {
        Format-CheckLabel -Id $Id | Should -BeExactly $Id
    }

    It 'labels shipped check <Id> with its bare id when other ids are custom' -ForEach $script:ShippedIds {
        Format-CheckLabel -Id $Id -CustomIds @('my-custom-check') | Should -BeExactly $Id
    }

    It 'marks a custom check id' {
        Format-CheckLabel -Id 'my-custom-check' -CustomIds @('my-custom-check') |
            Should -BeExactly 'my-custom-check [custom]'
    }
}
