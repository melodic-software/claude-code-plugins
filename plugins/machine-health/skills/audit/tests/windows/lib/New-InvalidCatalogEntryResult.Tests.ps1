#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/New-InvalidCatalogEntryResult.ps1.

.DESCRIPTION
Pins the #2575 contract: an Assert-CatalogEntry failure becomes a schema-valid
UNKNOWN CheckResult that severity_counts / latest.json / the report can see.
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:LibRoot = Join-Path $script:SkillRoot 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Assert-CatalogEntry.ps1')
    . (Join-Path $script:LibRoot 'Assert-CheckResult.ps1')
    . (Join-Path $script:LibRoot 'New-InvalidCatalogEntryResult.ps1')

    function New-NearlyValidEntry {
        param([hashtable] $Overrides = @{})
        $base = [ordered]@{
            id               = 'chezmoi-drift'
            category         = 'config'
            os               = @('windows')
            script           = 'scripts/windows/checks/Test-ChezmoiDrift.ps1'
            severity_rules   = 'references/windows/check-catalog.md#custom'
            needs_admin      = $false
            enabled          = $true
            deprecated       = $false
            added_on         = '2026-08-01'
            crash_count      = 0
            identical_streak = 0
        }
        foreach ($k in $Overrides.Keys) { $base[$k] = $Overrides[$k] }
        return [pscustomobject]$base
    }
}

Describe 'New-InvalidCatalogEntryResult' -Tag 'lib' {
    Context 'id selection' {
        It 'keeps a kebab-valid entry id' {
            $entry = New-NearlyValidEntry -Overrides @{ category = 'hairdryers' }
            $result = New-InvalidCatalogEntryResult -Entry $entry -Index 3 `
                -ErrorMessage "CatalogEntry 'chezmoi-drift' category 'hairdryers' not in allowed set"
            $result.id | Should -Be 'chezmoi-drift'
            { Assert-CheckResult $result } | Should -Not -Throw
        }

        It 'falls back to invalid-catalog-entry-N when id is missing' {
            $entry = [pscustomobject]@{ category = 'storage' }
            $result = New-InvalidCatalogEntryResult -Entry $entry -Index 7 `
                -ErrorMessage 'CatalogEntry is missing required field id'
            $result.id | Should -Be 'invalid-catalog-entry-7'
            { Assert-CheckResult $result } | Should -Not -Throw
        }

        It 'falls back to invalid-catalog-entry-N when id is not kebab-case' {
            $entry = New-NearlyValidEntry -Overrides @{ id = 'DiskSpace' }
            $result = New-InvalidCatalogEntryResult -Entry $entry -Index 2 `
                -ErrorMessage "CatalogEntry.id 'DiskSpace' is not valid kebab-case"
            $result.id | Should -Be 'invalid-catalog-entry-2'
            { Assert-CheckResult $result } | Should -Not -Throw
        }

        It 'handles a null entry' {
            $result = New-InvalidCatalogEntryResult -Entry $null -Index 0 `
                -ErrorMessage 'CatalogEntry is null.'
            $result.id | Should -Be 'invalid-catalog-entry-0'
            $result.category | Should -Be 'reliability'
            { Assert-CheckResult $result } | Should -Not -Throw
        }

        It 'avoids colliding with an occupied fallback id' {
            $entry = New-NearlyValidEntry -Overrides @{ id = 'DiskSpace' }
            $result = New-InvalidCatalogEntryResult -Entry $entry -Index 2 `
                -ErrorMessage "CatalogEntry.id 'DiskSpace' is not valid kebab-case" `
                -OccupiedIds @('invalid-catalog-entry-2', 'other-check')
            $result.id | Should -Be 'invalid-catalog-entry-2-2'
            { Assert-CheckResult $result } | Should -Not -Throw
        }

        It 'keeps escalating the suffix until the fallback is free' {
            $entry = [pscustomobject]@{ category = 'storage' }
            $result = New-InvalidCatalogEntryResult -Entry $entry -Index 2 `
                -ErrorMessage 'missing id' `
                -OccupiedIds @(
                    'invalid-catalog-entry-2',
                    'invalid-catalog-entry-2-2',
                    'invalid-catalog-entry-2-3'
                )
            $result.id | Should -Be 'invalid-catalog-entry-2-4'
            { Assert-CheckResult $result } | Should -Not -Throw
        }
    }

    Context 'category fallback' {
        It 'keeps a legal declared category' {
            $entry = New-NearlyValidEntry -Overrides @{
                category = 'security'
                script   = 'checks/broken.ps1'
            }
            $result = New-InvalidCatalogEntryResult -Entry $entry -Index 1 `
                -ErrorMessage "CatalogEntry 'chezmoi-drift' script path is not scripts/<os>/checks/Name.ps1"
            $result.category | Should -Be 'security'
            { Assert-CheckResult $result } | Should -Not -Throw
        }

        It 'falls back to reliability when category is outside the enum' {
            # Covers any category typo: an invalid category must not make the
            # synthetic result itself fail Assert-CheckResult.
            $entry = New-NearlyValidEntry -Overrides @{ category = 'platform' }
            $result = New-InvalidCatalogEntryResult -Entry $entry -Index 4 `
                -ErrorMessage "CatalogEntry 'chezmoi-drift' category 'platform' not in allowed set"
            $result.category | Should -Be 'reliability'
            $result.severity | Should -Be 'UNKNOWN'
            $result.ran_successfully | Should -BeFalse
            { Assert-CheckResult $result } | Should -Not -Throw
        }
    }

    Context 'summary and error contract' {
        It 'sets ran_successfully false, UNKNOWN severity, and the full error' {
            $msg = "CatalogEntry 'chezmoi-drift' category 'platform' not in allowed set (checks.jsonc)"
            $entry = New-NearlyValidEntry -Overrides @{ category = 'platform' }
            $result = New-InvalidCatalogEntryResult -Entry $entry -Index 0 -ErrorMessage $msg
            $result.severity | Should -Be 'UNKNOWN'
            $result.ran_successfully | Should -BeFalse
            $result.error | Should -Be $msg
            $result.summary | Should -Match '^catalog entry invalid, check did not run:'
            $result.summary | Should -BeLike "*$($msg.Split("`n")[0])*"
            { Assert-CheckResult $result } | Should -Not -Throw
        }

        It 'truncates summary to 240 chars when the error line is long' {
            $long = 'x' * 300
            $result = New-InvalidCatalogEntryResult -Entry $null -Index 9 -ErrorMessage $long
            $result.summary.Length | Should -BeLessOrEqual 240
            { Assert-CheckResult $result } | Should -Not -Throw
        }
    }
}

Describe 'Orchestrator invalid-catalog loop contract' -Tag 'lib' {
    # Mirrors the validation loop in Invoke-MachineHealthCheck.ps1: continue
    # past bad entries for availability, but collect synthetic UNKNOWN results
    # for the reporting path.
    It 'collects UNKNOWN results for invalid entries and keeps valid ones' {
        $valid = New-NearlyValidEntry -Overrides @{
            id       = 'disk-space'
            category = 'storage'
            script   = 'scripts/windows/checks/Test-DiskHealth.ps1'
        }
        $invalidCategory = New-NearlyValidEntry -Overrides @{ category = 'platform' }
        $invalidId = New-NearlyValidEntry -Overrides @{ id = 'NotKebab' }
        # A valid custom check whose id occupies the synthetic fallback
        # namespace — synthetic ids must still be unique against it.
        $occupyingFallback = New-NearlyValidEntry -Overrides @{
            id       = 'invalid-catalog-entry-2'
            category = 'storage'
            script   = 'scripts/windows/checks/Test-DiskHealth.ps1'
        }

        $catalogEntries = @($valid, $invalidCategory, $invalidId, $occupyingFallback)
        $occupiedResultIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($seedEntry in $catalogEntries) {
            $seedId = [string]$seedEntry.id
            if ($seedId -cmatch '^[a-z][a-z0-9-]*[a-z0-9]$') {
                [void]$occupiedResultIds.Add($seedId)
            }
        }

        $validatedChecks = [System.Collections.Generic.List[object]]::new()
        $invalidCatalogResults = [System.Collections.Generic.List[object]]::new()
        $entryIndex = 0
        foreach ($entry in $catalogEntries) {
            try {
                [void](Assert-CatalogEntry $entry -Because 'unit-test-catalog')
                $validatedChecks.Add($entry)
            } catch {
                $invalidResult = New-InvalidCatalogEntryResult `
                    -Entry $entry `
                    -Index $entryIndex `
                    -ErrorMessage $_.Exception.Message `
                    -OccupiedIds @($occupiedResultIds)
                $invalidCatalogResults.Add($invalidResult)
                [void]$occupiedResultIds.Add([string]$invalidResult.id)
            }
            $entryIndex++
        }

        @($validatedChecks).Count | Should -Be 2
        $validatedChecks[0].id | Should -Be 'disk-space'
        $validatedChecks[1].id | Should -Be 'invalid-catalog-entry-2'

        @($invalidCatalogResults).Count | Should -Be 2
        $invalidCatalogResults[0].id | Should -Be 'chezmoi-drift'
        $invalidCatalogResults[0].severity | Should -Be 'UNKNOWN'
        $invalidCatalogResults[0].category | Should -Be 'reliability'
        # Index 2 would have been invalid-catalog-entry-2, but that id is taken.
        $invalidCatalogResults[1].id | Should -Be 'invalid-catalog-entry-2-2'
        $invalidCatalogResults[1].severity | Should -Be 'UNKNOWN'

        foreach ($r in $invalidCatalogResults) {
            { Assert-CheckResult $r } | Should -Not -Throw
        }

        # Severity counts must include the synthetic UNKNOWN findings — the defect was
        # that a skipped entry contributed nothing here.
        $severityCounts = @{ OK = 0; INFO = 0; WARN = 0; CRIT = 0; UNKNOWN = 0 }
        foreach ($r in $invalidCatalogResults) { $severityCounts[$r.severity]++ }
        $severityCounts.UNKNOWN | Should -Be 2
    }

    It 'orchestrator catch block calls New-InvalidCatalogEntryResult (wiring pin)' {
        $orchestrator = Join-Path $script:SkillRoot 'scripts\windows\Invoke-MachineHealthCheck.ps1'
        $text = Get-Content -LiteralPath $orchestrator -Raw
        $text | Should -Match 'New-InvalidCatalogEntryResult'
        $text | Should -Match '\$invalidCatalogResults'
        $text | Should -Match 'catalog_entry_invalid skip'
    }
}
