#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-ElevationMatrix.ps1'
}

Describe 'Get-ElevationMatrix' -Tag 'lib' {
    It 'returns at least one entry' {
        (Get-ElevationMatrix).Count | Should -BeGreaterThan 0
    }

    It 'every entry has Feature/CheckId/AdminRequired/Fields/Reason' {
        foreach ($entry in Get-ElevationMatrix) {
            $entry.PSObject.Properties['Feature'] | Should -Not -BeNullOrEmpty
            $entry.PSObject.Properties['CheckId'] | Should -Not -BeNullOrEmpty
            $entry.PSObject.Properties['AdminRequired'] | Should -Not -BeNullOrEmpty
            $entry.PSObject.Properties['Fields'] | Should -Not -BeNullOrEmpty
            $entry.PSObject.Properties['Reason'] | Should -Not -BeNullOrEmpty
        }
    }

    It 'every entry AdminRequired is $true (non-admin entries are not tracked here)' {
        foreach ($entry in Get-ElevationMatrix) {
            $entry.AdminRequired | Should -BeTrue
        }
    }

    It 'includes defender-exclusions (admin-gated for Get-MpPreference)' {
        $entry = Get-ElevationMatrix | Where-Object { $_.CheckId -eq 'defender-exclusions' }
        $entry | Should -Not -BeNullOrEmpty
        $entry.AdminRequired | Should -BeTrue
        $entry.Fields | Should -Contain 'unexpected_path_count'
    }
}
