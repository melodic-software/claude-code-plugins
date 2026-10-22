#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/New-UnknownCheckResult.ps1. The required fields
and the ran_successfully/error rule come from catalog/schemas/check-result.schema.json,
enforced by Assert-CheckResult.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'New-UnknownCheckResult.ps1', 'Assert-CheckResult.ps1'
    $script:Entry = [pscustomobject]@{ id = 'disk-space'; category = 'storage'; needs_admin = $true }
}

Describe 'New-UnknownCheckResult' -Tag 'lib' {
    It 'builds a schema-valid UNKNOWN result from the entry, summary and reason' {
        $r = New-UnknownCheckResult -Entry $script:Entry -Summary 'Script not found: x.ps1' -ErrorReason 'script_missing' -DurationMs 12

        { Assert-CheckResult $r } | Should -Not -Throw
        $r.id | Should -BeExactly 'disk-space'
        $r.category | Should -BeExactly 'storage'
        $r.severity | Should -BeExactly 'UNKNOWN'
        $r.ran_successfully | Should -BeFalse
        $r.error | Should -BeExactly 'script_missing'
        $r.needs_admin | Should -BeTrue
        $r.duration_ms | Should -Be 12
        @($r.detail.Keys).Count | Should -Be 0
    }

    It 'carries -Detail when given' {
        $r = New-UnknownCheckResult -Entry $script:Entry -Summary 's' -ErrorReason 'e' -Detail @{ result_path = 'p' }

        $r.detail.result_path | Should -BeExactly 'p'
        { Assert-CheckResult $r } | Should -Not -Throw
    }
}
