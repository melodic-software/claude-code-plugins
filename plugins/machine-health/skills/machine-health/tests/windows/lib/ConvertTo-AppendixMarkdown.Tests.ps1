#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:LibRoot = Join-Path (Split-Path -Parent $script:TestsRoot) 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'ConvertTo-AppendixMarkdown.ps1')
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
                            description = 'Security Update'
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
}
