#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

<#
.SYNOPSIS
Tests for scripts/windows/lib/Get-BackupSignal.ps1. Event ids and the version
id shape come from the lib docblock and check-catalog.md section 27; the error ids are
the ones Get-WinEvent raised on a host with no Backup events and no such log.
wbadmin fixtures hold identifier-shaped lines only, never label text.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-BackupSignal.ps1'

    function New-WinEventError {
        param([string] $Id)
        [System.Management.Automation.ErrorRecord]::new([Exception]::new('none'),
            "$Id,Microsoft.PowerShell.Commands.GetWinEventCommand", 'ObjectNotFound', $null)
    }

    function New-BackupEvent {
        param([int] $Id, [datetime] $Time, [string] $BackupTime = $null)
        $data = $BackupTime ? '<Data Name="BackupTime">' + $BackupTime + '</Data>' : ''
        $xml = "<Event><EventData>$data</EventData></Event>"
        $record = [pscustomobject]@{ Id = $Id; TimeCreated = $Time }
        $record | Add-Member -MemberType ScriptMethod -Name ToXml -Value ([scriptblock]::Create("'$xml'"))
        return $record
    }

    function Get-Source {
        param($Sources, [string] $Name)
        return @($Sources | Where-Object { $_.Source -eq $Name })[0]
    }
}

Describe 'Get-BackupSignal' -Tag 'lib' {
    BeforeEach {
        Mock Get-WinEvent { throw (New-WinEventError 'NoMatchingEventsFound') } -ParameterFilter { $FilterHashtable }
        Mock Get-WinEvent { [pscustomobject]@{ RecordCount = 0 } } -ParameterFilter { $ListLog }
        Mock Invoke-NativeCommand { throw 'wbadmin must not run unelevated' }
        Mock Get-CimInstance { throw 'restore points must not be read unelevated' }
        Mock Test-Path { $false }
        Mock Get-Item { throw 'not expected' }
        Mock Get-ChildItem { @() }
    }

    Context 'system-image' {
        It 'returns system-image unknown when the Backup channel has no events' {
            $s = Get-Source (Get-BackupSignal -Elevated $false) 'system-image'
            $s.State | Should -Be 'unknown'
            $s.Signal | Should -Be 'backup-event'
            $s.Basis | Should -Match 'no Backup events'
            $s.Count | Should -BeNullOrEmpty
            Should -Invoke Invoke-NativeCommand -Times 0
        }

        It 'is present with the newest event 4 BackupTime as last success' {
            Mock Get-WinEvent {
                (New-BackupEvent -Id 4 -Time ([datetime]'2026-10-01T10:00:00Z') -BackupTime '2026-10-01T09:58:00.000Z')
                (New-BackupEvent -Id 5 -Time ([datetime]'2026-10-08T10:00:00Z'))
            } -ParameterFilter { $FilterHashtable }
            $s = Get-Source (Get-BackupSignal -Elevated $false) 'system-image'
            $s.State | Should -Be 'present'
            $s.LastSuccess | Should -Be '2026-10-01T09:58:00.0000000Z'
            $s.LastResultEvent | Should -Be 5
        }

        It 'is absent when the channel holds only failed runs' {
            Mock Get-WinEvent {
                New-BackupEvent -Id 9 -Time ([datetime]'2026-10-08T10:00:00Z')
            } -ParameterFilter { $FilterHashtable }
            $s = Get-Source (Get-BackupSignal -Elevated $false) 'system-image'
            $s.State | Should -Be 'absent'
            $s.LastSuccess | Should -BeNullOrEmpty
            $s.LastResultEvent | Should -Be 9
        }

        It 'is unknown, not absent, when the channel read fails' {
            Mock Get-WinEvent { throw (New-WinEventError 'AccessDenied') } -ParameterFilter { $FilterHashtable }
            (Get-Source (Get-BackupSignal -Elevated $false) 'system-image').State | Should -Be 'unknown'
        }

        It 'counts wbadmin version ids when elevated and the channel is empty' {
            Mock Invoke-NativeCommand {
                [pscustomobject]@{ status = 'Ok'; exit_code = 0; output = "01/06/2022-09:02`n02/03/2022-09:02`nx" }
            } -ParameterFilter { $Name -eq 'wbadmin' }
            Mock Get-CimInstance { @() }
            $s = Get-Source (Get-BackupSignal -Elevated $true) 'system-image'
            $s.State | Should -Be 'present'
            $s.Signal | Should -Be 'wbadmin-count'
            $s.Count | Should -Be 2
            Should -Invoke Invoke-NativeCommand -Times 1 -ParameterFilter {
                @($ArgumentList).Count -eq 2 -and $ArgumentList[0] -eq 'get' -and $ArgumentList[1] -eq 'versions'
            }
        }

        It 'stays unknown when elevated wbadmin exits -2 with no identifier' {
            Mock Invoke-NativeCommand {
                [pscustomobject]@{ status = 'NonZero'; exit_code = -2; output = 'text' }
            } -ParameterFilter { $Name -eq 'wbadmin' }
            Mock Get-CimInstance { @() }
            $s = Get-Source (Get-BackupSignal -Elevated $true) 'system-image'
            $s.State | Should -Be 'unknown'
            $s.Count | Should -Be 0
        }
    }

    Context 'restore-points' {
        It 'needs admin unelevated and is never read' {
            (Get-Source (Get-BackupSignal -Elevated $false) 'restore-points').State | Should -Be 'needs-admin'
            Should -Invoke Get-CimInstance -Times 0
        }

        It 'is present with its count when elevated and two restore points exist' {
            Mock Invoke-NativeCommand { [pscustomobject]@{ status = 'Absent'; exit_code = $null; output = '' } }
            Mock Get-CimInstance { [pscustomobject]@{ SequenceNumber = 1 }; [pscustomobject]@{ SequenceNumber = 2 } }
            $s = Get-Source (Get-BackupSignal -Elevated $true) 'restore-points'
            $s.State | Should -Be 'present'
            $s.Count | Should -Be 2
        }

        It 'does not count a text value as a restore point' {
            Mock Invoke-NativeCommand { [pscustomobject]@{ status = 'Absent'; exit_code = $null; output = '' } }
            Mock Get-CimInstance { 'ERR: Access denied' }
            (Get-Source (Get-BackupSignal -Elevated $true) 'restore-points').State | Should -Be 'unknown'
        }

        It 'is absent when elevated and none exist' {
            Mock Invoke-NativeCommand { [pscustomobject]@{ status = 'Absent'; exit_code = $null; output = '' } }
            Mock Get-CimInstance { }
            (Get-Source (Get-BackupSignal -Elevated $true) 'restore-points').State | Should -Be 'absent'
        }
    }

    Context 'file-history, windows-backup, onedrive-kfm' {
        It 'reports absent for every user-scope source on a machine with none' {
            $sources = Get-BackupSignal -Elevated $false
            foreach ($name in 'file-history', 'windows-backup', 'onedrive-kfm') {
                (Get-Source $sources $name).State | Should -Be 'absent' -Because $name
            }
        }

        It 'reads File History as present when a configuration file exists' {
            Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*FileHistory*' }
            Mock Get-ChildItem { [pscustomobject]@{ Name = 'Config1.xml' } }
            (Get-Source (Get-BackupSignal -Elevated $false) 'file-history').State | Should -Be 'present'
        }

        It 'reads Windows Backup as present from its log record count' {
            Mock Get-WinEvent { [pscustomobject]@{ RecordCount = 53 } } -ParameterFilter { $ListLog }
            $s = Get-Source (Get-BackupSignal -Elevated $false) 'windows-backup'
            $s.State | Should -Be 'present'
            $s.Count | Should -Be 53
        }

        It 'reads Windows Backup as absent when its log does not exist' {
            Mock Get-WinEvent { throw (New-WinEventError 'NoMatchingLogsFound') } -ParameterFilter { $ListLog }
            (Get-Source (Get-BackupSignal -Elevated $false) 'windows-backup').State | Should -Be 'absent'
        }

        It 'reads Known Folder Move as present from an opt-in policy value' {
            Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq 'HKLM:\SOFTWARE\Policies\Microsoft\OneDrive' }
            Mock Get-Item { [pscustomobject]@{ Property = @('KFMSilentOptIn', 'FilesOnDemandEnabled') } }
            $s = Get-Source (Get-BackupSignal -Elevated $false) 'onedrive-kfm'
            $s.State | Should -Be 'present'
            $s.Signal | Should -Be 'policy-key'
        }

        It 'does not read a block-opt-in policy value as Known Folder Move' {
            Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq 'HKLM:\SOFTWARE\Policies\Microsoft\OneDrive' }
            Mock Get-Item { [pscustomobject]@{ Property = @('KFMBlockOptIn') } }
            (Get-Source (Get-BackupSignal -Elevated $false) 'onedrive-kfm').State | Should -Be 'absent'
        }
    }
}
