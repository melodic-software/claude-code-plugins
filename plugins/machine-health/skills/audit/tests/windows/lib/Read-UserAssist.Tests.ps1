#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Read-UserAssist.ps1'

    # 2026-03-04T05:06:07Z as a FILETIME, computed by hand:
    # (1772600767 Unix seconds + 11644473600) * 10^7.
    $script:LaunchFileTime = [long]134170743670000000
    $script:LaunchedAt = [datetime]::new(2026, 3, 4, 5, 6, 7, [DateTimeKind]::Utc)

    # Value names as the registry stores them, ROT13-encoded by hand.
    # spellchecker:off
    $script:EncodedExe = '{6Q809377-6NS0-444O-8957-N3773S02200R}\Iraqbe\Ncc\ncc.rkr'
    $script:EncodedAumid = 'Pbagbfb.Abgrf_nop123!Ncc'
    $script:EncodedSession = 'HRZR_PGYFRFFVBA'
    # spellchecker:on

    function New-LaunchRecord {
        param([long] $FileTime = 0, [int] $Length = 72)
        $bytes = [byte[]]::new($Length)
        if ($Length -ge 68) { [BitConverter]::GetBytes($FileTime).CopyTo($bytes, 60) }
        return , $bytes
    }

    function Set-UserAssistMock {
        param([hashtable] $Values)
        Mock Get-ChildItem { [pscustomobject]@{ PSPath = 'Registry::HKEY_CURRENT_USER\UA\{GUID}' } }
        $object = [ordered]@{ PSPath = 'Registry::HKEY_CURRENT_USER\UA\{GUID}\Count'; PSChildName = 'Count' }
        foreach ($name in $Values.Keys) { $object[$name] = $Values[$name] }
        $valueSet = [pscustomobject]$object
        Mock Get-ItemProperty ({ $valueSet }.GetNewClosure()) -ParameterFilter { $LiteralPath -like '*\Count' }
    }
}

Describe 'Read-UserAssist' -Tag 'lib' {
    BeforeEach {
        Mock Get-KnownFolderPath { 'X:\Program Files' } -ParameterFilter { $Folder -eq 'ProgramFiles' }
    }

    It 'decodes the name, expands the known folder, and reads the last-run time' {
        Set-UserAssistMock @{
            $script:EncodedExe   = (New-LaunchRecord -FileTime $script:LaunchFileTime)
            $script:EncodedAumid = (New-LaunchRecord)
        }

        $read = Read-UserAssist

        $read.ReadState | Should -Be 'ok'
        $exe = $read.Entries | Where-Object Name -Like '{6D809377-*'
        $exe.Name | Should -Be '{6D809377-6AF0-444B-8957-A3773F02200E}\Vendor\App\app.exe'
        $exe.Path | Should -Be 'X:\Program Files\Vendor\App\app.exe'
        $exe.LastRun | Should -Be $script:LaunchedAt

        $aumid = $read.Entries | Where-Object Name -EQ 'Contoso.Notes_abc123!App'
        $aumid.Path | Should -BeNullOrEmpty
        $aumid.LastRun | Should -BeNullOrEmpty
    }

    It 'never returns the run count' {
        Set-UserAssistMock @{ $script:EncodedExe = (New-LaunchRecord -FileTime $script:LaunchFileTime) }
        $entry = (Read-UserAssist).Entries[0]
        @($entry.PSObject.Properties.Name) | Should -Be @('Name', 'Path', 'LastRun')
    }

    It 'skips values of another length without failing the read' {
        Set-UserAssistMock @{
            $script:EncodedSession = (New-LaunchRecord -Length 16)
            $script:EncodedExe     = (New-LaunchRecord -FileTime $script:LaunchFileTime)
        }

        $read = Read-UserAssist

        $read.ReadState | Should -Be 'ok'
        @($read.Entries).Count | Should -Be 1
    }

    It 'reports error when values exist but none has the record layout' {
        Set-UserAssistMock @{ $script:EncodedSession = (New-LaunchRecord -Length 16) }

        $read = Read-UserAssist

        $read.ReadState | Should -Be 'error'
        @($read.Entries).Count | Should -Be 0
    }

    It 'reports absent when the Count keys hold no values' {
        Set-UserAssistMock @{}
        (Read-UserAssist).ReadState | Should -Be 'absent'
    }

    It 'reports absent when the UserAssist key does not exist' {
        Mock Get-ChildItem { throw [System.Management.Automation.ItemNotFoundException]::new('missing') }
        (Read-UserAssist).ReadState | Should -Be 'absent'
    }

    It 'leaves Path empty for a known-folder GUID it does not map' {
        # {00000000-...}\tool.exe, ROT13-encoded.
        Set-UserAssistMock @{ '{00000000-0000-0000-0000-000000000000}\gbby.rkr' = (New-LaunchRecord) }
        $entry = (Read-UserAssist).Entries[0]
        $entry.Name | Should -Be '{00000000-0000-0000-0000-000000000000}\tool.exe'
        $entry.Path | Should -BeNullOrEmpty
    }
}
