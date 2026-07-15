#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Unit tests for Merge-CatalogOverlay (machine-local catalog overlay merge).
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:LibRoot = Join-Path $script:SkillRoot 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Merge-CatalogOverlay.ps1')

    function New-BaseEntry {
        param([string] $Id = 'disk-space', [bool] $Enabled = $true)
        return [pscustomobject]@{
            id               = $Id
            category         = 'storage'
            os               = @('windows')
            script           = 'scripts/windows/checks/Test-DiskHealth.ps1'
            severity_rules   = 'references/windows/check-catalog.md#x'
            needs_admin      = $false
            enabled          = $Enabled
            deprecated       = $false
            added_on         = '2026-04-22'
            crash_count      = 0
            identical_streak = 0
        }
    }
}

Describe 'Merge-CatalogOverlay' {
    Context 'no overlay content' {
        It 'returns base checks unchanged when overlay is null' {
            $out = Merge-CatalogOverlay -BaseChecks @((New-BaseEntry)) -Overlay $null
            @($out).Count | Should -Be 1
            $out[0].id | Should -Be 'disk-space'
            $out[0].enabled | Should -BeTrue
        }

        It 'returns base checks unchanged when overlay has no checks property' {
            $out = Merge-CatalogOverlay -BaseChecks @((New-BaseEntry)) -Overlay ([pscustomobject]@{ note = 'x' })
            @($out).Count | Should -Be 1
        }

        It 'handles an empty base catalog' {
            $overlay = [pscustomobject]@{ checks = @() }
            $out = Merge-CatalogOverlay -BaseChecks @() -Overlay $overlay
            @($out).Count | Should -Be 0
        }
    }

    Context 'property override by id' {
        It 'applies overlay properties onto the matching shipped entry' {
            $overlay = [pscustomobject]@{
                checks = @([pscustomobject]@{ id = 'disk-space'; enabled = $false })
            }
            $out = Merge-CatalogOverlay -BaseChecks @((New-BaseEntry)) -Overlay $overlay
            @($out).Count | Should -Be 1
            $out[0].enabled | Should -BeFalse
            $out[0].category | Should -Be 'storage'
        }

        It 'adds properties the shipped entry lacks (e.g. cadence demotion)' {
            $overlay = [pscustomobject]@{
                checks = @([pscustomobject]@{ id = 'disk-space'; cadence = 'monthly' })
            }
            $out = Merge-CatalogOverlay -BaseChecks @((New-BaseEntry)) -Overlay $overlay
            $out[0].cadence | Should -Be 'monthly'
        }

        It 'supports deprecation with a reason' {
            $overlay = [pscustomobject]@{
                checks = @([pscustomobject]@{
                        id                 = 'disk-space'
                        deprecated         = $true
                        deprecation_reason = 'meaningless on this host'
                    })
            }
            $out = Merge-CatalogOverlay -BaseChecks @((New-BaseEntry)) -Overlay $overlay
            $out[0].deprecated | Should -BeTrue
            $out[0].deprecation_reason | Should -Be 'meaningless on this host'
        }

        It 'does not mutate the caller-supplied base entry' {
            $base = New-BaseEntry
            $overlay = [pscustomobject]@{
                checks = @([pscustomobject]@{ id = 'disk-space'; enabled = $false })
            }
            [void](Merge-CatalogOverlay -BaseChecks @($base) -Overlay $overlay)
            $base.enabled | Should -BeTrue
        }
    }

    Context 'custom check append' {
        It 'appends an overlay entry with a new id' {
            $custom = [pscustomobject]@{
                id               = 'my-custom-check'
                category         = 'storage'
                os               = @('windows')
                script           = 'scripts/windows/checks/Test-MyCustomCheck.ps1'
                severity_rules   = 'catalog/checks.local.jsonc'
                needs_admin      = $false
                enabled          = $true
                deprecated       = $false
                added_on         = '2026-07-12'
                crash_count      = 0
                identical_streak = 0
            }
            $overlay = [pscustomobject]@{ checks = @($custom) }
            $out = Merge-CatalogOverlay -BaseChecks @((New-BaseEntry)) -Overlay $overlay
            @($out).Count | Should -Be 2
            @($out | Where-Object id -EQ 'my-custom-check').Count | Should -Be 1
        }
    }

    Context 'malformed overlay entries' {
        It 'skips an overlay entry without an id' {
            $overlay = [pscustomobject]@{
                checks = @([pscustomobject]@{ enabled = $false })
            }
            $out = Merge-CatalogOverlay -BaseChecks @((New-BaseEntry)) -Overlay $overlay -WarningAction SilentlyContinue
            @($out).Count | Should -Be 1
            $out[0].enabled | Should -BeTrue
        }
    }
}
