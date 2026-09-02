#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for ConvertFrom-WingetTextOutput short-row handling (#3437).
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:LibRoot = Join-Path (Split-Path -Parent $script:TestsRoot) 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Get-WingetPackageUpdate.ps1')
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
