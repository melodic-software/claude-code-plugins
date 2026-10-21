#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Get-NonElevatedCoverage.ps1.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-NonElevatedCoverage.ps1'

    $script:Catalog = @(
        [pscustomobject]@{ id = 'zeta-check'; needs_admin = $false }
        [pscustomobject]@{ id = 'admin-check'; needs_admin = $true }
        [pscustomobject]@{ id = 'my-custom-check'; needs_admin = $false }
        [pscustomobject]@{ id = 'alpha-check'; needs_admin = $false }
    )
}

Describe 'Get-NonElevatedCoverage' -Tag 'lib' {
    It 'lists the non-admin entries of the run set in catalog order' {
        $labels = @(Get-NonElevatedCoverage -Catalog $script:Catalog)
        ($labels -join '|') | Should -BeExactly 'zeta-check|my-custom-check|alpha-check'
    }

    It 'marks custom entries the way the report does' {
        $labels = @(Get-NonElevatedCoverage -Catalog $script:Catalog -CustomIds @('my-custom-check'))
        ($labels -join '|') | Should -BeExactly 'zeta-check|my-custom-check [custom]|alpha-check'
    }

    It 'returns an empty list for an empty catalog' {
        @(Get-NonElevatedCoverage -Catalog @()).Count | Should -Be 0
    }
}
