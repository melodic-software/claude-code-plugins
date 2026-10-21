#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-RunKeyEntry.ps1'
}

Describe 'Get-RunKeyEntry' -Tag 'lib' {
    Context 'registry keys' {
        It 'lists each Run value as an entry and drops the provider properties and the default value' {
            Mock Get-ItemProperty {
                [pscustomobject]@{
                    PSPath      = 'Registry::fixture'
                    PSChildName = 'Run'
                    '(default)' = ''
                    Updater     = '"X:\Apps\Updater\updater.exe" --background'
                }
            }

            $read = Get-RunKeyEntry -Scope 'hkcu' -Key 'Run'

            $read.ReadState | Should -Be 'ok'
            @($read.Entries).Count | Should -Be 1
            $read.Entries[0].Kind | Should -Be 'run'
            $read.Entries[0].Scope | Should -Be 'hkcu'
            $read.Entries[0].Name | Should -Be 'Updater'
            $read.Entries[0].Command | Should -Be '"X:\Apps\Updater\updater.exe" --background'
        }

        It 'reads <Scope> <Key> from <Expected>' -ForEach @(
            @{ Scope = 'hkcu'; Key = 'Run'; Expected = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' }
            @{ Scope = 'hklm'; Key = 'RunOnce'; Expected = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' }
            @{ Scope = 'hklm-wow64'; Key = 'Run'; Expected = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' }
        ) {
            Mock Get-ItemProperty { [pscustomobject]@{ Tool = 'tool.exe' } }

            $read = Get-RunKeyEntry -Scope $Scope -Key $Key

            Should -Invoke Get-ItemProperty -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq $Expected }
            $read.Entries[0].Kind | Should -Be $Key.ToLowerInvariant()
        }

        It 'reports <State> when the read throws <Exception>' -ForEach @(
            @{ Exception = 'ItemNotFoundException'; State = 'absent' }
            @{ Exception = 'UnauthorizedAccessException'; State = 'denied' }
            @{ Exception = 'IOException'; State = 'error' }
        ) {
            $thrown = switch ($Exception) {
                'ItemNotFoundException' { [System.Management.Automation.ItemNotFoundException]::new('missing') }
                'UnauthorizedAccessException' { [System.UnauthorizedAccessException]::new('denied') }
                default { [System.IO.IOException]::new('broken') }
            }
            Mock Get-ItemProperty ({ throw $thrown }.GetNewClosure())

            $read = Get-RunKeyEntry -Scope 'hklm' -Key 'Run'

            $read.ReadState | Should -Be $State
            @($read.Entries).Count | Should -Be 0
        }
    }

    Context 'Startup folders' {
        It 'lists each file, not subfolders, with its full path as the command' {
            Mock Get-StartupFolderPath { 'X:\Profile\Startup' }
            Mock Get-ChildItem {
                [pscustomobject]@{ Name = 'Notes.lnk'; FullName = 'X:\Profile\Startup\Notes.lnk'; PSIsContainer = $false }
                [pscustomobject]@{ Name = 'Archive'; FullName = 'X:\Profile\Startup\Archive'; PSIsContainer = $true }
            }

            $read = Get-RunKeyEntry -Scope 'user-folder'

            $read.ReadState | Should -Be 'ok'
            @($read.Entries).Count | Should -Be 1
            $read.Entries[0].Kind | Should -Be 'startup-folder'
            $read.Entries[0].Scope | Should -Be 'user-folder'
            $read.Entries[0].Name | Should -Be 'Notes.lnk'
            $read.Entries[0].Command | Should -Be 'X:\Profile\Startup\Notes.lnk'
            Should -Invoke Get-ChildItem -Times 1 -Exactly -ParameterFilter {
                $LiteralPath -eq 'X:\Profile\Startup'
            }
        }

        It 'reports absent when the folder is not defined' {
            Mock Get-StartupFolderPath { '' }
            Mock Get-ChildItem { throw 'must not list' }
            (Get-RunKeyEntry -Scope 'common-folder').ReadState | Should -Be 'absent'
        }

        It 'reports an empty folder as ok with no entries' {
            Mock Get-StartupFolderPath { 'X:\Common\Startup' }
            Mock Get-ChildItem { }
            $read = Get-RunKeyEntry -Scope 'common-folder'
            $read.ReadState | Should -Be 'ok'
            @($read.Entries).Count | Should -Be 0
        }
    }
}
