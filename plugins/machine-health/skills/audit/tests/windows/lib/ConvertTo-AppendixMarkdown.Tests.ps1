#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'ConvertTo-AppendixMarkdown.ps1'
}

Describe 'ConvertTo-AppendixMarkdown' -Tag 'lib' {
    It 'returns placeholder when no checks' {
        ConvertTo-AppendixMarkdown -CheckResults @() | Should -Match 'No data'
    }

    It 'renders a winget upgrades details block' {
        $check = [pscustomobject]@{
            id     = 'winget-upgrades'
            detail = [pscustomobject]@{
                upgrades = @(
                    [pscustomobject]@{
                        name              = 'Git'
                        id                = 'Git.Git'
                        current_version   = '2.0'
                        available_version = '2.1'
                    }
                )
            }
        }
        $md = ConvertTo-AppendixMarkdown -CheckResults @($check)
        $md | Should -Match 'winget upgrades \(1\)'
        $md | Should -Match '<details>'
        $md | Should -Match 'Git\.Git'
    }

    It 'renders driver + event-log + hotfix blocks when present' {
        $checks = @(
            [pscustomobject]@{
                id     = 'drivers'
                detail = [pscustomobject]@{
                    total_drivers  = 300
                    oldest_drivers = @(
                        [pscustomobject]@{
                            device_name    = 'Mock'
                            manufacturer   = 'Intel'
                            driver_version = '1.0'
                            driver_date    = '2020-01-01T00:00:00'
                        }
                    )
                }
            }
            [pscustomobject]@{
                id     = 'event-log-errors'
                detail = [pscustomobject]@{
                    top_sources = @(
                        [pscustomobject]@{
                            provider_and_id = 'Microsoft/20'
                            count           = 9
                            first_seen      = '2026-04-22T01:00:00.000-04:00'
                            last_seen       = '2026-04-23T04:00:00.000-04:00'
                        }
                    )
                }
            }
            [pscustomobject]@{
                id     = 'windows-update'
                detail = [pscustomobject]@{
                    recent_hotfixes = @(
                        [pscustomobject]@{
                            hotfix_id    = 'KB12345'
                            description  = 'Security Update'
                            installed_on = '2026-04-10T00:00:00'
                        }
                    )
                }
            }
        )
        $md = ConvertTo-AppendixMarkdown -CheckResults $checks
        $md | Should -Match 'oldest drivers'
        $md | Should -Match 'event-log top sources'
        $md | Should -Match 'recent hotfixes'
        $md | Should -Match 'KB12345'
    }

    It 'returns placeholder when no checks have renderable inventories' {
        $check = [pscustomobject]@{
            id     = 'services'
            detail = [pscustomobject]@{
                stopped_auto_services = @()
                startup_inventory     = @()
            }
        }
        $md = ConvertTo-AppendixMarkdown -CheckResults @($check)
        $md | Should -Match 'No inventories'
    }

    It 'renders the KEV matches that justify a winget-upgrades finding' {
        $check = [pscustomobject]@{
            id     = 'winget-upgrades'
            detail = [pscustomobject]@{
                upgrades    = @()
                kev_matches = @(
                    [pscustomobject]@{
                        upgrade_id  = 'Google.Chrome'
                        upgrade     = 'Google Chrome (Google.Chrome) 153.0 -> 154.0'
                        cve_id      = 'CVE-2020-16017'
                        vendor      = 'Google'
                        product     = 'Chrome'
                        match_basis = 'name-only'
                    }
                )
            }
        }
        $md = ConvertTo-AppendixMarkdown -CheckResults @($check)
        $md | Should -Match 'CISA KEV matches \(1\)'
        $md | Should -Match '\| `Google\.Chrome` \| CVE-2020-16017 \| Google / Chrome \| name-only \|'
    }

    It 'renders the CodeIntegrity events that justify a drivers finding, pipes escaped' {
        $check = [pscustomobject]@{
            id     = 'drivers'
            detail = [pscustomobject]@{
                code_integrity_event_count = 12
                code_integrity_events      = @(
                    [pscustomobject]@{
                        provider_name = 'Microsoft-Windows-CodeIntegrity'
                        id            = 3004
                        time_created  = [datetime]'2026-09-20T10:00:00'
                        message       = "file x.sys | hash`r`nmissing"
                    }
                )
            }
        }
        $md = ConvertTo-AppendixMarkdown -CheckResults @($check)
        $md | Should -Match 'CodeIntegrity events \(1 of 12\)'
        $md | Should -Match '\| 3004 \| file x\.sys \\\| hash missing \|'
        $md | Should -Not -Match 'oldest drivers'
    }
}
