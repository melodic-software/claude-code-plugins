#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for ConvertFrom-WingetTextOutput short-row handling (#3437).
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-WingetPackageUpdate.ps1'
}

Describe 'ConvertFrom-WingetTextOutput' -Tag 'lib' {
    It 'parses a full-width row' {
        $header = 'Name                 Id                 Version    Available  Source'
        $row = 'Git                  Git.Git            2.45.1     2.46.0     winget'
        $items = @(ConvertFrom-WingetTextOutput -Lines @($header, ('-' * $header.Length), $row))
        $items.Count | Should -Be 1
        $items[0].id | Should -Be 'Git.Git'
        $items[0].available_version | Should -Be '2.46.0'
    }

    It 'parses a short row instead of swallowing a Substring exception' {
        $header = 'Name                 Id                 Version    Available  Source'
        $idxAvail = $header.IndexOf('Available')
        # Row reaches the Version column but stops before Available, the shape
        # that used to throw in Substring($idxAvail) and disappear into catch.
        $row = 'ShortPkg             Short.Id           1.0'
        $row.Length | Should -BeLessThan $idxAvail
        $items = @(ConvertFrom-WingetTextOutput -Lines @($header, ('-' * $header.Length), $row))
        $items.Count | Should -Be 1
        $items[0].name | Should -Be 'ShortPkg'
        $items[0].id | Should -Be 'Short.Id'
        $items[0].current_version | Should -Be '1.0'
        $items[0].available_version | Should -Be ''
    }
}

Describe 'Get-WingetPackageUpdate CLI fallback' -Tag 'lib' {
    It 'passes upgrade flags as separate argv entries' {
        Mock Get-Module { $null }
        Mock Invoke-NativeCommand {
            [pscustomobject]@{
                status    = 'Ok'
                source    = 'winget'
                exit_code = 0
                output    = @(
                    'Name                 Id                 Version    Available  Source'
                    '-------------------- ------------------ ---------- ---------- ------'
                    'Git                  Git.Git            2.45.1     2.46.0     winget'
                ) -join "`n"
                error     = $null
            }
        } -ParameterFilter { $Name -eq 'winget' }

        $result = Get-WingetPackageUpdate
        $result.error | Should -BeNullOrEmpty
        @($result.upgrades).Count | Should -Be 1
        $result.upgrades[0].id | Should -Be 'Git.Git'

        Should -Invoke Invoke-NativeCommand -Times 1 -ParameterFilter {
            $Name -eq 'winget' -and
            @($ArgumentList).Count -eq 3 -and
            @($ArgumentList)[0] -eq 'upgrade' -and
            @($ArgumentList)[1] -eq '--include-unknown' -and
            @($ArgumentList)[2] -eq '--accept-source-agreements'
        }
    }

    It 'reports the CLI missing when winget is not on PATH' {
        Mock Get-Module { $null }
        Mock Invoke-NativeCommand {
            [pscustomobject]@{
                status    = 'Absent'
                source    = 'absent'
                exit_code = $null
                output    = ''
                error     = $null
            }
        } -ParameterFilter { $Name -eq 'winget' }

        $result = Get-WingetPackageUpdate
        $result.upgrades | Should -BeNullOrEmpty
        $result.error | Should -Match 'not on PATH'
    }
}
