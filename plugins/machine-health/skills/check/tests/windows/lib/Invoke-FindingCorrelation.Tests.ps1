#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:LibRoot = Join-Path (Split-Path -Parent $script:TestsRoot) 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Invoke-FindingCorrelation.ps1')
}

Describe 'Invoke-FindingCorrelation' -Tag 'lib' {
    It 'upgrades windows-update INFO to WARN when paired with >=5 WUClient/20 events' {
        $wu = [pscustomobject]@{
            id       = 'windows-update'
            severity = 'INFO'
            notes    = $null
            detail   = [pscustomobject]@{ reboot_pending = $true }
        }
        $ev = [pscustomobject]@{
            id       = 'event-log-errors'
            severity = 'WARN'
            notes    = $null
            detail   = [pscustomobject]@{
                top_sources = @(
                    [pscustomobject]@{ provider_and_id = 'Microsoft-Windows-WindowsUpdateClient/20'; count = 9 }
                )
            }
        }

        $r = @(Invoke-FindingCorrelation -CheckResults @($wu, $ev))
        ($r | Where-Object id -EQ 'windows-update').severity | Should -Be 'WARN'
        ($r | Where-Object id -EQ 'windows-update').notes | Should -Match 'WUClient/20'
        ($r | Where-Object id -EQ 'event-log-errors').notes | Should -Match 'windows-update'
    }

    It 'does not fire when count < 5' {
        $wu = [pscustomobject]@{
            id       = 'windows-update'
            severity = 'INFO'
            notes    = $null
            detail   = [pscustomobject]@{ reboot_pending = $true }
        }
        $ev = [pscustomobject]@{
            id       = 'event-log-errors'
            severity = 'WARN'
            notes    = $null
            detail   = [pscustomobject]@{
                top_sources = @(
                    [pscustomobject]@{ provider_and_id = 'Microsoft-Windows-WindowsUpdateClient/20'; count = 3 }
                )
            }
        }
        $r = @(Invoke-FindingCorrelation -CheckResults @($wu, $ev))
        ($r | Where-Object id -EQ 'windows-update').severity | Should -Be 'INFO'
    }

    It 'does not downgrade when current severity is already higher than target' {
        $wu = [pscustomobject]@{
            id       = 'windows-update'
            severity = 'CRIT'
            notes    = $null
            detail   = [pscustomobject]@{ reboot_pending = $true }
        }
        $ev = [pscustomobject]@{
            id       = 'event-log-errors'
            severity = 'WARN'
            notes    = $null
            detail   = [pscustomobject]@{
                top_sources = @(
                    [pscustomobject]@{ provider_and_id = 'Microsoft-Windows-WindowsUpdateClient/20'; count = 10 }
                )
            }
        }
        $r = @(Invoke-FindingCorrelation -CheckResults @($wu, $ev))
        ($r | Where-Object id -EQ 'windows-update').severity | Should -Be 'CRIT'
    }

    It 'no-ops when empty' {
        $r = Invoke-FindingCorrelation -CheckResults @()
        @($r).Count | Should -Be 0
    }
}
