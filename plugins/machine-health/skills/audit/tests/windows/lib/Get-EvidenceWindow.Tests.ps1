#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-EvidenceWindow.ps1'

    # 2026-06-26T00:00:00Z: 20630 days after the Unix epoch, times 86400.
    $script:InstallSeconds = 1782432000
    $script:InstalledAt = [datetime]::new(2026, 6, 26, 0, 0, 0, [DateTimeKind]::Utc)
    $script:ProfileAt = [datetime]::new(2026, 6, 27, 1, 52, 48, [DateTimeKind]::Utc)
    $script:EarlyProfileAt = [datetime]::new(2026, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
}

Describe 'Get-EvidenceWindow' -Tag 'lib' {
    It 'starts at the profile creation when the profile is newer than the OS install' {
        Mock Get-ItemProperty { [pscustomobject]@{ InstallDate = $script:InstallSeconds } }
        Mock Get-Item { [pscustomobject]@{ CreationTimeUtc = $script:ProfileAt } }

        $window = Get-EvidenceWindow

        $window.ReadState | Should -Be 'ok'
        $window.Start | Should -Be $script:ProfileAt
    }

    It 'starts at the OS install when the profile predates it' {
        Mock Get-ItemProperty { [pscustomobject]@{ InstallDate = $script:InstallSeconds } }
        Mock Get-Item { [pscustomobject]@{ CreationTimeUtc = $script:EarlyProfileAt } }

        (Get-EvidenceWindow).Start | Should -Be $script:InstalledAt
    }

    It 'reports error and keeps the readable input when one input fails' {
        Mock Get-ItemProperty { throw [System.Security.SecurityException]::new('denied') }
        Mock Get-Item { [pscustomobject]@{ CreationTimeUtc = $script:ProfileAt } }

        $window = Get-EvidenceWindow

        $window.ReadState | Should -Be 'error'
        $window.Start | Should -Be $script:ProfileAt
    }

    It 'leaves Start empty when neither input reads' {
        Mock Get-ItemProperty { throw 'unreadable' }
        Mock Get-Item { throw 'unreadable' }

        $window = Get-EvidenceWindow

        $window.ReadState | Should -Be 'error'
        $window.Start | Should -BeNullOrEmpty
    }
}
