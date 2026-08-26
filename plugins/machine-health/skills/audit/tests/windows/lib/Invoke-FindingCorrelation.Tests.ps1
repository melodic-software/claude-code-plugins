#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:LibRoot = Join-Path (Split-Path -Parent $script:TestsRoot) 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Invoke-FindingCorrelation.ps1')

    function New-WindowsUpdateResult {
        # windows-update check result with reboot_pending set, the state the
        # WUClient/20 correlation rule pairs against.
        param([string] $Severity = 'INFO')
        [pscustomobject]@{
            id       = 'windows-update'
            severity = $Severity
            notes    = $null
            detail   = [pscustomobject]@{ reboot_pending = $true }
        }
    }

    function New-EventLogResult {
        # event-log-errors check result whose only top source is the
        # WindowsUpdateClient/20 provider with the given event count.
        param([int] $WuClientEventCount)
        [pscustomobject]@{
            id       = 'event-log-errors'
            severity = 'WARN'
            notes    = $null
            detail   = [pscustomobject]@{
                top_sources = @(
                    [pscustomobject]@{
                        provider_and_id = 'Microsoft-Windows-WindowsUpdateClient/20'
                        count           = $WuClientEventCount
                    }
                )
            }
        }
    }
}

Describe 'Invoke-FindingCorrelation' -Tag 'lib' {
    It 'upgrades windows-update INFO to WARN when paired with >=5 WUClient/20 events' {
        $wu = New-WindowsUpdateResult
        $ev = New-EventLogResult -WuClientEventCount 9

        $r = @(Invoke-FindingCorrelation -CheckResults @($wu, $ev))
        ($r | Where-Object id -EQ 'windows-update').severity | Should -Be 'WARN'
        ($r | Where-Object id -EQ 'windows-update').notes | Should -Match 'WUClient/20'
        ($r | Where-Object id -EQ 'event-log-errors').notes | Should -Match 'windows-update'
    }

    It 'does not fire when count < 5' {
        $wu = New-WindowsUpdateResult
        $ev = New-EventLogResult -WuClientEventCount 3
        $r = @(Invoke-FindingCorrelation -CheckResults @($wu, $ev))
        ($r | Where-Object id -EQ 'windows-update').severity | Should -Be 'INFO'
    }

    It 'does not downgrade when current severity is already higher than target' {
        $wu = New-WindowsUpdateResult -Severity 'CRIT'
        $ev = New-EventLogResult -WuClientEventCount 10
        $r = @(Invoke-FindingCorrelation -CheckResults @($wu, $ev))
        ($r | Where-Object id -EQ 'windows-update').severity | Should -Be 'CRIT'
    }

    It 'no-ops when empty' {
        $r = Invoke-FindingCorrelation -CheckResults @()
        @($r).Count | Should -Be 0
    }
}
