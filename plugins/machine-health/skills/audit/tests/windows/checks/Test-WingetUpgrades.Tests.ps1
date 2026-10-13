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

4. The check forwards its -LogPath to Get-CisaKevCache so the CISA fetch
   lands in the run's egress audit trail (urls_called).

5. A KEV match is name-only (the feed carries no affected-version range), so it
   reports WARN with the CVE list, never CRIT, and the summary counts distinct
   upgrades separately from matched CVE rows.

6. A KEV gap with upgrades pending (fetch failed with no cache, empty feed,
   lookup threw) reports UNKNOWN with ran_successfully false, never a
   count-only severity; a stale fallback list keeps its severity but is named
   in the summary, notes and detail.kev_cache_state.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -Check 'Test-WingetUpgrades' `
        -AsObject 'Invoke-WingetUpgradesAsObject' `
        -LibScript 'Get-WingetPackageUpdate.ps1', 'Get-CisaKevCache.ps1'

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
        # The wrapper's contract is a hashtable tuple. A bare hashtable is enough here: Pester
        # mocks forward the return value verbatim, so no comma-operator unwrap guard is needed.
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

    function New-KevCache {
        # Mirrors Get-CisaKevCache's return: the list plus its _cache_* annotations. The
        # default is a usable list that matches nothing, so count-based tests stay count-based.
        param(
            [object[]] $Vulnerabilities = @(New-KevRecord -CveId 'CVE-2000-0000' -VendorProject 'Unrelated' -Product 'Thing'),
            [string] $State = 'fresh',
            $AgeDays = 1,
            [string] $FetchError = $null
        )
        [pscustomobject]@{
            vulnerabilities = $Vulnerabilities
            _cache_state    = $State
            _cache_age_days = $AgeDays
            _fetch_error    = $FetchError
        }
    }
}

Describe 'Test-WingetUpgrades -- baseline' -Tag 'check' {
    BeforeAll {
        Mock Get-WingetPackageUpdate { New-WingetResult -Upgrades @() }
        Mock Get-CisaKevCache { New-KevCache }
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
        Mock Get-CisaKevCache { New-KevCache }

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
        Mock Get-CisaKevCache { New-KevCache }

        $result = Invoke-WingetUpgradesAsObject
        $result.severity | Should -Be 'WARN'
    }
}

Describe 'Test-WingetUpgrades -- CISA KEV correlation (ID-based match)' -Tag 'check' {
    It 'WARNs, never CRITs, on a single name-only ID match, listing the CVE' {
        Mock Get-WingetPackageUpdate {
            New-WingetResult -Upgrades @(
                New-UpgradeRecord -Name 'Mock App' -Id 'Mock.App'
                New-UpgradeRecord -Name 'Other' -Id 'Other.Other'
            )
        }
        Mock Get-CisaKevCache {
            New-KevCache -Vulnerabilities @(
                New-KevRecord -CveId 'CVE-2025-12345' -VendorProject 'Mock' -Product 'App'
            )
        }

        $result = Invoke-WingetUpgradesAsObject
        $result.severity | Should -Be 'WARN'
        $result.detail.kev_match_count | Should -Be 1
        $result.detail.kev_matches[0].cve_id | Should -Be 'CVE-2025-12345'
        $result.detail.kev_matches[0].match_basis | Should -Be 'name-only'
        $result.summary | Should -Match 'CVE-2025-12345'
        $result.summary | Should -Match 'installed versions not compared'
    }

    It 'counts one upgrade matched against three KEV rows as one upgrade and three CVE entries' {
        Mock Get-WingetPackageUpdate {
            New-WingetResult -Upgrades @(
                New-UpgradeRecord -Name 'Google Chrome' -Id 'Google.Chrome'
            )
        }
        Mock Get-CisaKevCache {
            New-KevCache -Vulnerabilities @(
                New-KevRecord -CveId 'CVE-2020-16017' -VendorProject 'Google' -Product 'Chrome'
                New-KevRecord -CveId 'CVE-2021-21166' -VendorProject 'Google' -Product 'Chrome'
                New-KevRecord -CveId 'CVE-2022-0609' -VendorProject 'Google' -Product 'Chrome'
            )
        }

        $result = Invoke-WingetUpgradesAsObject
        $result.severity | Should -Be 'WARN'
        $result.detail.kev_match_count | Should -Be 3
        $result.detail.kev_upgrade_count | Should -Be 1
        $result.summary | Should -Match '^1 upgrade\(s\) name-match CISA KEV \(3 matched CVE entries: '
        $result.summary | Should -Not -Match '3 upgrade'
    }

    It 'does NOT match "WSL" against Microsoft/Windows KEV (regression for the 170-false-positive bug)' {
        Mock Get-WingetPackageUpdate {
            New-WingetResult -Upgrades @(
                New-UpgradeRecord -Name 'Windows Subsystem for Linux' -Id 'Microsoft.WSL'
            )
        }
        Mock Get-CisaKevCache {
            New-KevCache -Vulnerabilities @(
                New-KevRecord -CveId 'CVE-2025-60710' -VendorProject 'Microsoft' -Product 'Windows'
                New-KevRecord -CveId 'CVE-2023-36424' -VendorProject 'Microsoft' -Product 'Windows'
                New-KevRecord -CveId 'CVE-2008-0015' -VendorProject 'Microsoft' -Product 'Windows'
            )
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
            New-KevCache -Vulnerabilities @(
                New-KevRecord -CveId 'CVE-2025-TEAMS' -VendorProject 'Microsoft' -Product 'Teams'
            )
        }

        $result = Invoke-WingetUpgradesAsObject
        $result.severity | Should -Be 'WARN'
        $result.detail.kev_match_count | Should -Be 1
    }

    It 'matches Microsoft.Teams.Free against Microsoft/Teams KEV (prefix case)' {
        Mock Get-WingetPackageUpdate {
            New-WingetResult -Upgrades @(
                New-UpgradeRecord -Name 'Microsoft Teams (personal)' -Id 'Microsoft.Teams.Free'
            )
        }
        Mock Get-CisaKevCache {
            New-KevCache -Vulnerabilities @(
                New-KevRecord -CveId 'CVE-2025-TEAMS' -VendorProject 'Microsoft' -Product 'Teams'
            )
        }

        $result = Invoke-WingetUpgradesAsObject
        $result.severity | Should -Be 'WARN'
        $result.detail.kev_match_count | Should -Be 1
    }

    It 'matches case-insensitively (GitHub.cli vs GitHub/CLI)' {
        Mock Get-WingetPackageUpdate {
            New-WingetResult -Upgrades @(
                New-UpgradeRecord -Name 'GitHub CLI' -Id 'GitHub.cli'
            )
        }
        Mock Get-CisaKevCache {
            New-KevCache -Vulnerabilities @(
                New-KevRecord -CveId 'CVE-2025-GHCLI' -VendorProject 'GitHub' -Product 'CLI'
            )
        }

        $result = Invoke-WingetUpgradesAsObject
        $result.severity | Should -Be 'WARN'
        $result.detail.kev_match_count | Should -Be 1
    }

    It 'does not match a prefix-collision (Microsoft.TeamsExtra vs Microsoft/Teams)' {
        Mock Get-WingetPackageUpdate {
            New-WingetResult -Upgrades @(
                New-UpgradeRecord -Name 'Teams Extra' -Id 'Microsoft.TeamsExtra'
            )
        }
        Mock Get-CisaKevCache {
            New-KevCache -Vulnerabilities @(
                New-KevRecord -CveId 'CVE-X' -VendorProject 'Microsoft' -Product 'Teams'
            )
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
            New-KevCache -Vulnerabilities @(
                New-KevRecord -CveId 'CVE-Y' -VendorProject 'Single' -Product 'Token'
            )
        }

        $result = Invoke-WingetUpgradesAsObject
        $result.severity | Should -Be 'INFO'
        $result.detail.kev_match_count | Should -Be 0
        $result.detail.non_conforming_id_count | Should -Be 1
        $result.notes | Should -Match 'non-conforming Id'
    }

}

Describe 'Test-WingetUpgrades -- KEV data gaps never read as a clean KEV check (#6505)' -Tag 'check' {
    It 'emits UNKNOWN, not the count-based WARN, when the KEV fetch failed with no cached list' {
        # The reported case: >10 upgrades would WARN on count alone and hide the KEV gap.
        Mock Get-WingetPackageUpdate {
            $upgrades = 1..15 | ForEach-Object { New-UpgradeRecord -Name "App$_" -Id "Pub.App$_" }
            New-WingetResult -Upgrades @($upgrades)
        }
        Mock Get-CisaKevCache {
            New-KevCache -Vulnerabilities @() -State 'unavailable' -AgeDays $null `
                -FetchError 'No such host is known.'
        }

        $result = Invoke-WingetUpgradesAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.severity | Should -Be 'UNKNOWN'
        $result.ran_successfully | Should -BeFalse
        $result.error | Should -Match 'No such host is known'
        $result.summary | Should -Match 'KEV exposure is unknown'
        $result.detail.upgrades_count | Should -Be 15
        $result.detail.kev_cache_state | Should -Be 'unavailable'
    }

    It 'emits UNKNOWN when the KEV feed came back empty' {
        Mock Get-WingetPackageUpdate { New-WingetResult -Upgrades @(New-UpgradeRecord) }
        Mock Get-CisaKevCache { New-KevCache -Vulnerabilities @() -State 'empty' -AgeDays $null }

        $result = Invoke-WingetUpgradesAsObject
        $result.severity | Should -Be 'UNKNOWN'
        $result.ran_successfully | Should -BeFalse
        $result.error | Should -Match 'no entries'
    }

    It 'emits UNKNOWN when the KEV lookup returns nothing at all' {
        Mock Get-WingetPackageUpdate { New-WingetResult -Upgrades @(New-UpgradeRecord) }
        Mock Get-CisaKevCache { $null }

        $result = Invoke-WingetUpgradesAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.severity | Should -Be 'UNKNOWN'
        $result.ran_successfully | Should -BeFalse
        $result.error | Should -Match 'empty or unparsable'
        $result.detail.kev_cache_state | Should -Be 'unknown'
    }

    It 'emits UNKNOWN when the KEV lookup throws' {
        Mock Get-WingetPackageUpdate { New-WingetResult -Upgrades @(New-UpgradeRecord) }
        Mock Get-CisaKevCache { throw 'cache dir access denied' }

        $result = Invoke-WingetUpgradesAsObject
        $result.severity | Should -Be 'UNKNOWN'
        $result.ran_successfully | Should -BeFalse
        $result.error | Should -Match 'cache dir access denied'
    }

    It 'stays OK with no upgrades even when KEV is unavailable, and notes the skip' {
        Mock Get-WingetPackageUpdate { New-WingetResult -Upgrades @() }
        Mock Get-CisaKevCache {
            New-KevCache -Vulnerabilities @() -State 'unavailable' -AgeDays $null -FetchError 'timeout'
        }

        $result = Invoke-WingetUpgradesAsObject
        $result.severity | Should -Be 'OK'
        $result.ran_successfully | Should -BeTrue
        $result.notes | Should -Match 'KEV correlation skipped'
    }

    It 'keeps the severity on a stale fallback list but marks the summary, notes and detail' {
        Mock Get-WingetPackageUpdate { New-WingetResult -Upgrades @(New-UpgradeRecord) }
        Mock Get-CisaKevCache { New-KevCache -State 'stale' -AgeDays 12.5 -FetchError 'TLS handshake failed' }

        $result = Invoke-WingetUpgradesAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.severity | Should -Be 'INFO'
        $result.ran_successfully | Should -BeTrue
        $result.summary | Should -Match 'KEV list stale'
        $result.notes | Should -Match 'TLS handshake failed'
        $result.notes | Should -Match '12\.5-day-old'
        $result.detail.kev_cache_state | Should -Be 'stale'
        $result.detail.kev_cache_age_days | Should -Be 12.5
    }

    It 'reports a fresh list without a stale caveat' {
        Mock Get-WingetPackageUpdate { New-WingetResult -Upgrades @(New-UpgradeRecord) }
        Mock Get-CisaKevCache { New-KevCache }

        $result = Invoke-WingetUpgradesAsObject
        $result.detail.kev_cache_state | Should -Be 'fresh'
        $result.summary | Should -Not -Match 'stale'
        $result.notes | Should -BeNullOrEmpty
    }
}

Describe 'Test-WingetUpgrades -- egress log threading' -Tag 'check' {
    It 'forwards its -LogPath to Get-CisaKevCache so the KEV fetch is logged' {
        Mock Get-WingetPackageUpdate { New-WingetResult -Upgrades @(New-UpgradeRecord) }
        Mock Get-CisaKevCache { New-KevCache }

        & $script:ScriptPath -LogPath 'C:\run\run-2026-07-12.log' | Out-Null

        Should -Invoke Get-CisaKevCache -Times 1 -ParameterFilter {
            $LogPath -eq 'C:\run\run-2026-07-12.log'
        }
    }
}

Describe 'Test-WingetUpgrades -- failure modes' -Tag 'check' {
    It 'emits UNKNOWN when the wrapper returns upgrades=$null with an error' {
        Mock Get-WingetPackageUpdate {
            New-WingetResult -Upgrades $null -ErrorMessage 'module import failed: FOO'
        }
        Mock Get-CisaKevCache { New-KevCache }

        $result = Invoke-WingetUpgradesAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.severity | Should -Be 'UNKNOWN'
        $result.ran_successfully | Should -BeFalse
        $result.summary | Should -Match 'FOO'
        $result.error | Should -Match 'FOO'
    }

    It 'emits UNKNOWN when the wrapper violates its hashtable contract (returns $null)' {
        Mock Get-WingetPackageUpdate { $null }
        Mock Get-CisaKevCache { New-KevCache }

        $result = Invoke-WingetUpgradesAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.severity | Should -Be 'UNKNOWN'
        $result.ran_successfully | Should -BeFalse
    }
}
