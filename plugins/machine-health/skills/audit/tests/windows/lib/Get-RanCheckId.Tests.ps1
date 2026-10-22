#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Get-RanCheckId.ps1: the history.jsonl checks_ran
list is the dispatched or imported checks whose final result ran successfully.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-RanCheckId.ps1'

    function Get-ResultFixture {
        param([string] $Id, [bool] $Ran = $true)
        [pscustomobject]@{ id = $Id; ran_successfully = $Ran }
    }
}

Describe 'Get-RanCheckId' -Tag 'lib' {
    It 'lists a dispatched check that ran and leaves out one that failed' {
        $ids = Get-RanCheckId -CheckResults @((Get-ResultFixture 'disk-space'), (Get-ResultFixture 'services' -Ran $false)) `
            -DispatchedIds @('disk-space', 'services')

        @($ids) | Should -Be @('disk-space')
    }

    It 'lists an imported elevated check the run did not dispatch' {
        $ids = Get-RanCheckId -CheckResults @((Get-ResultFixture 'disk-space'), (Get-ResultFixture 'tpm-bitlocker')) `
            -DispatchedIds @('disk-space') -ImportedIds @('tpm-bitlocker')

        @($ids) | Should -Be @('disk-space', 'tpm-bitlocker')
    }

    It 'leaves out a result whose id is neither dispatched nor imported' {
        $ids = Get-RanCheckId -CheckResults @((Get-ResultFixture 'elevated-pass'), (Get-ResultFixture 'state-location'), (Get-ResultFixture 'drivers')) `
            -DispatchedIds @('drivers') -ImportedIds @()

        @($ids) | Should -Be @('drivers')
    }

    It 'lists an id once when two results carry it' {
        $ids = Get-RanCheckId -CheckResults @((Get-ResultFixture 'drivers'), (Get-ResultFixture 'drivers')) -DispatchedIds @('drivers')

        @($ids) | Should -Be @('drivers')
    }

    It 'returns an empty list when nothing ran' {
        $ids = Get-RanCheckId -CheckResults @() -DispatchedIds @('drivers')

        @($ids).Count | Should -Be 0
    }
}
