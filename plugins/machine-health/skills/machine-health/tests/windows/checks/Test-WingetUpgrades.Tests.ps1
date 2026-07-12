#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/checks/Test-WingetUpgrades.ps1.

.DESCRIPTION
Pins the Batch 1 hotfix landing:

1. The check reads upgrades via the Get-WingetPackageUpdate lib wrapper.
   The wrapper returns a tuple @{ upgrades; error } (new contract). The
   module path calls Get-WinGetPackage | Where IsUpdateAvailable (the
   previous Get-WinGetPackageUpdate cmdlet does not exist).

2. KEV correlation is ID-based. Matching on display-name substrings was
   flagging "Windows Subsystem for Linux" against every Microsoft/Windows
   CVE -- 170 false positives. The fix matches on the winget Id
   (case-insensitive "<vendor>.<product>$" or prefix).

3. Wrapper returning upgrades=$null surfaces the specific wrapper error
   (not a generic "winget not available").
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:ScriptPath = Join-Path $script:SkillRoot 'scripts\windows\checks\Test-WingetUpgrades.ps1'
    $script:LibRoot = Join-Path $script:SkillRoot 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Assert-CheckResult.ps1')
    . (Join-Path $script:LibRoot 'Get-WingetPackageUpdate.ps1')
    . (Join-Path $script:LibRoot 'Get-CisaKevCache.ps1')
    Import-Module (Join-Path $script:TestsRoot 'helpers\Mock-Helpers.psm1') -Force

    function Invoke-WingetUpgradesAsObject {
        $raw = & $script:ScriptPath
        $json = ($raw | Where-Object { $_ }) -join "`n"
        return $json | ConvertFrom-Json
    }

    function New-UpgradeRecord {
        param(
            [string] $Name = 'Some App',
            [string] $Id = 'Some.App',
            [string] $Current = '1.0',
            [string] $Available = '1.1',
            [string] $Source = 'winget'
        )
        [pscustomobject]@{
            name              = $Name
            id                = $Id
            current_version   = $Current
            available_version = $Available
            source            = $Source
        }
    }

    function New-WingetResult {
        param(
            [object[]] $Upgrades = @(),
            [string] $ErrorMessage = $null
        )
        # The wrapper's contract is a hashtable tuple. Emit it as such; the
        # comma operator + explicit [hashtable[]] cast would normally be
        # required to keep a single-hashtable return from being unwrapped,
        # but since Pester mocks forward the entire return value verbatim,
        # a bare hashtable works here.
        return @{ upgrades = $Upgrades; error = $ErrorMessage }
    }

    function New-KevRecord {
        param(
            [string] $CveId = 'CVE-2025-00001',
            [string] $VendorProject = 'Mock',
            [string] $Product = 'App'
        )
        [pscustomobject]@{
            cveID         = $CveId
            vendorProject = $VendorProject
            product       = $Product
        }
    }
}

Describe 'Test-WingetUpgrades -- baseline' -Tag 'check' {
    BeforeAll {
        Mock Get-WingetPackageUpdate { New-WingetResult -Upgrades @() }
        Mock Get-CisaKevCache { [pscustomobject]@{ vulnerabilities = @() } }
    }

    It 'emits a schema-valid CheckResult' {
        $result = Invoke-WingetUpgradesAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.id | Should -Be 'winget-upgrades'
    }

    It 'reports OK when no upgrades are pending' {
        $result = Invoke-WingetUpgradesAsObject
        $result.severity | Should -Be 'OK'
    }
}

Describe 'Test-WingetUpgrades -- upgrade count severity' -Tag 'check' {
    It 'reports INFO for a small number of upgrades' {
        Mock Get-WingetPackageUpdate {
            New-WingetResult -Upgrades @(
                New-UpgradeRecord -Name 'Git' -Id 'Git.Git'
                New-UpgradeRecord -Name 'Node' -Id 'OpenJS.NodeJS'
            )
        }
        Mock Get-CisaKevCache { [pscustomobject]@{ vulnerabilities = @() } }

        $result = Invoke-WingetUpgradesAsObject
        $result.severity | Should -Be 'INFO'
        $result.detail.upgrades_count | Should -Be 2
    }

    It 'reports WARN when more than 10 apps are behind' {
        Mock Get-WingetPackageUpdate {
            $upgrades = 1..15 | ForEach-Object {
                New-UpgradeRecord -Name "App$_" -Id "Pub.App$_"
            }
            New-WingetResult -Upgrades @($upgrades)
        }
        Mock Get-CisaKevCache { [pscustomobject]@{ vulnerabilities = @() } }

        $result = Invoke-WingetUpgradesAsObject
        $result.severity | Should -Be 'WARN'
    }
}

Describe 'Test-WingetUpgrades -- CISA KEV correlation (ID-based match)' -Tag 'check' {
    It 'CRITs on a single ID match regardless of upgrade count' {
        Mock Get-WingetPackageUpdate {
            New-WingetResult -Upgrades @(
                New-UpgradeRecord -Name 'Mock App' -Id 'Mock.App'
                New-UpgradeRecord -Name 'Other' -Id 'Other.Other'
            )
        }
        Mock Get-CisaKevCache {
            [pscustomobject]@{
                vulnerabilities = @(
                    New-KevRecord -CveId 'CVE-2025-12345' -VendorProject 'Mock' -Product 'App'
                )
            }
        }

        $result = Invoke-WingetUpgradesAsObject
        $result.severity | Should -Be 'CRIT'
        $result.detail.kev_match_count | Should -Be 1
        $result.detail.kev_matches[0].cve_id | Should -Be 'CVE-2025-12345'
    }

    It 'does NOT match "WSL" against Microsoft/Windows KEV (regression for the 170-false-positive bug)' {
        Mock Get-WingetPackageUpdate {
            New-WingetResult -Upgrades @(
                New-UpgradeRecord -Name 'Windows Subsystem for Linux' -Id 'Microsoft.WSL'
            )
        }
        Mock Get-CisaKevCache {
            [pscustomobject]@{
                vulnerabilities = @(
                    New-KevRecord -CveId 'CVE-2025-60710' -VendorProject 'Microsoft' -Product 'Windows'
                    New-KevRecord -CveId 'CVE-2023-36424' -VendorProject 'Microsoft' -Product 'Windows'
                    New-KevRecord -CveId 'CVE-2008-0015' -VendorProject 'Microsoft' -Product 'Windows'
                )
            }
        }

        $result = Invoke-WingetUpgradesAsObject
        $result.severity | Should -Be 'INFO'
        $result.detail.kev_match_count | Should -Be 0
        $result.detail.upgrades_count | Should -Be 1
    }

    It 'matches Microsoft.Teams against Microsoft/Teams KEV' {
        Mock Get-WingetPackageUpdate {
            New-WingetResult -Upgrades @(
                New-UpgradeRecord -Name 'Microsoft Teams' -Id 'Microsoft.Teams'
            )
        }
        Mock Get-CisaKevCache {
            [pscustomobject]@{
                vulnerabilities = @(
                    New-KevRecord -CveId 'CVE-2025-TEAMS' -VendorProject 'Microsoft' -Product 'Teams'
                )
            }
        }

        $result = Invoke-WingetUpgradesAsObject
        $result.severity | Should -Be 'CRIT'
        $result.detail.kev_match_count | Should -Be 1
    }

    It 'matches Microsoft.Teams.Free against Microsoft/Teams KEV (prefix case)' {
        Mock Get-WingetPackageUpdate {
            New-WingetResult -Upgrades @(
                New-UpgradeRecord -Name 'Microsoft Teams (personal)' -Id 'Microsoft.Teams.Free'
            )
        }
        Mock Get-CisaKevCache {
            [pscustomobject]@{
                vulnerabilities = @(
                    New-KevRecord -CveId 'CVE-2025-TEAMS' -VendorProject 'Microsoft' -Product 'Teams'
                )
            }
        }

        $result = Invoke-WingetUpgradesAsObject
        $result.severity | Should -Be 'CRIT'
        $result.detail.kev_match_count | Should -Be 1
    }

    It 'matches case-insensitively (GitHub.cli vs GitHub/CLI)' {
        Mock Get-WingetPackageUpdate {
            New-WingetResult -Upgrades @(
                New-UpgradeRecord -Name 'GitHub CLI' -Id 'GitHub.cli'
            )
        }
        Mock Get-CisaKevCache {
            [pscustomobject]@{
                vulnerabilities = @(
                    New-KevRecord -CveId 'CVE-2025-GHCLI' -VendorProject 'GitHub' -Product 'CLI'
                )
            }
        }

        $result = Invoke-WingetUpgradesAsObject
        $result.severity | Should -Be 'CRIT'
        $result.detail.kev_match_count | Should -Be 1
    }

    It 'does not match a prefix-collision (Microsoft.TeamsExtra vs Microsoft/Teams)' {
        Mock Get-WingetPackageUpdate {
            New-WingetResult -Upgrades @(
                New-UpgradeRecord -Name 'Teams Extra' -Id 'Microsoft.TeamsExtra'
            )
        }
        Mock Get-CisaKevCache {
            [pscustomobject]@{
                vulnerabilities = @(
                    New-KevRecord -CveId 'CVE-X' -VendorProject 'Microsoft' -Product 'Teams'
                )
            }
        }

        $result = Invoke-WingetUpgradesAsObject
        $result.severity | Should -Be 'INFO'
        $result.detail.kev_match_count | Should -Be 0
    }

    It 'flags non-conforming IDs (no dot) in notes and skips KEV for them' {
        Mock Get-WingetPackageUpdate {
            New-WingetResult -Upgrades @(
                New-UpgradeRecord -Name 'Legacy' -Id 'SingleToken'
            )
        }
        Mock Get-CisaKevCache {
            [pscustomobject]@{
                vulnerabilities = @(
                    New-KevRecord -CveId 'CVE-Y' -VendorProject 'Single' -Product 'Token'
                )
            }
        }

        $result = Invoke-WingetUpgradesAsObject
        $result.severity | Should -Be 'INFO'
        $result.detail.kev_match_count | Should -Be 0
        $result.detail.non_conforming_id_count | Should -Be 1
        $result.notes | Should -Match 'non-conforming Id'
    }

    It 'falls back to count-based severity when KEV cache is empty/unusable' {
        Mock Get-WingetPackageUpdate {
            New-WingetResult -Upgrades @(New-UpgradeRecord)
        }
        Mock Get-CisaKevCache { $null }

        $result = Invoke-WingetUpgradesAsObject
        $result.severity | Should -Be 'INFO'
        $result.notes | Should -Match 'KEV'
    }
}

Describe 'Test-WingetUpgrades -- failure modes' -Tag 'check' {
    It 'emits UNKNOWN when the wrapper returns upgrades=$null with an error' {
        Mock Get-WingetPackageUpdate {
            New-WingetResult -Upgrades $null -ErrorMessage 'module import failed: FOO'
        }
        Mock Get-CisaKevCache { [pscustomobject]@{ vulnerabilities = @() } }

        $result = Invoke-WingetUpgradesAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.severity | Should -Be 'UNKNOWN'
        $result.ran_successfully | Should -BeFalse
        $result.summary | Should -Match 'FOO'
        $result.error | Should -Match 'FOO'
    }

    It 'emits UNKNOWN when the wrapper violates its hashtable contract (returns $null)' {
        Mock Get-WingetPackageUpdate { $null }
        Mock Get-CisaKevCache { [pscustomobject]@{ vulnerabilities = @() } }

        $result = Invoke-WingetUpgradesAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.severity | Should -Be 'UNKNOWN'
        $result.ran_successfully | Should -BeFalse
    }
}
