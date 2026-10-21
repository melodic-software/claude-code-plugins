#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-EvidenceWindow.ps1'

    # 2026-06-26T00:00:00Z: 20630 days after the Unix epoch, times 86400.
    $script:InstallSeconds = 1782432000
    $script:InstalledAt = [datetime]::new(2026, 6, 26, 0, 0, 0, [DateTimeKind]::Utc)
    $script:ProfileAt = [datetime]::new(2026, 6, 27, 1, 52, 48, [DateTimeKind]::Utc)
}

Describe 'Get-EvidenceWindow' -Tag 'lib' {
    It 'starts at the later of the OS install and the profile creation' {
        Mock Get-ItemProperty { [pscustomobject]@{ InstallDate = $script:InstallSeconds } }
        Mock Get-Item { [pscustomobject]@{ CreationTimeUtc = $script:ProfileAt } }

        $window = Get-EvidenceWindow

        $window.ReadState | Should -Be 'ok'
        $window.Start | Should -Be $script:ProfileAt
        @($window.Sources.Name) | Should -Be @('os-install', 'profile-created')
        ($window.Sources | Where-Object Name -EQ 'os-install').Start | Should -Be $script:InstalledAt
    }

    It 'counts whole days from the start to now' {
        $tenAndAHalfDaysAgo = [datetime]::UtcNow.AddDays(-10.5)
        Mock Get-ItemProperty { [pscustomobject]@{ InstallDate = 0 } }
        Mock Get-Item ({ [pscustomobject]@{ CreationTimeUtc = $tenAndAHalfDaysAgo } }.GetNewClosure())

        (Get-EvidenceWindow).Days | Should -Be 10
    }

    It 'reports error and keeps the readable source when one input fails' {
        Mock Get-ItemProperty { throw [System.Security.SecurityException]::new('denied') }
        Mock Get-Item { [pscustomobject]@{ CreationTimeUtc = $script:ProfileAt } }

        $window = Get-EvidenceWindow

        $window.ReadState | Should -Be 'error'
        $window.Start | Should -Be $script:ProfileAt
        @($window.Sources).Count | Should -Be 1
    }

    It 'leaves Start and Days empty when neither input reads' {
        Mock Get-ItemProperty { throw 'unreadable' }
        Mock Get-Item { throw 'unreadable' }

        $window = Get-EvidenceWindow

        $window.ReadState | Should -Be 'error'
        $window.Start | Should -BeNullOrEmpty
        $window.Days | Should -BeNullOrEmpty
    }
}
