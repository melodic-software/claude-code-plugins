#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Read-StartupApproved.ps1'

    # 2026-01-02T03:04:05Z as a FILETIME, computed by hand:
    # (1767323045 Unix seconds + 11644473600) * 10^7.
    $script:DisabledFileTime = [long]134117966450000000
    $script:DisabledAt = [datetime]::new(2026, 1, 2, 3, 4, 5, [DateTimeKind]::Utc)

    function New-ApprovedValue {
        param([byte] $First, [long] $FileTime = 0)
        $bytes = [byte[]]::new(12)
        $bytes[0] = $First
        [BitConverter]::GetBytes($FileTime).CopyTo($bytes, 4)
        return , $bytes
    }

    function New-RegistryValueSet {
        param([hashtable] $Values)
        $object = [ordered]@{ PSPath = 'Registry::fixture'; PSChildName = 'Run' }
        foreach ($name in $Values.Keys) { $object[$name] = $Values[$name] }
        return [pscustomobject]$object
    }
}

Describe 'Read-StartupApproved' -Tag 'lib' {
    It 'decodes 0x02 as enabled, 0x03 as disabled with its time, and any other byte as unknown' {
        Mock Get-ItemProperty {
            New-RegistryValueSet @{
                Enabled  = (New-ApprovedValue -First 2)
                Disabled = (New-ApprovedValue -First 3 -FileTime $script:DisabledFileTime)
                Other    = (New-ApprovedValue -First 1)
            }
        }

        $read = Read-StartupApproved -Scope 'hkcu'

        $read.ReadState | Should -Be 'ok'
        $read.Entries['Enabled'].State | Should -Be 'enabled'
        $read.Entries['Enabled'].RawByte | Should -BeNullOrEmpty
        $read.Entries['Disabled'].State | Should -Be 'disabled'
        $read.Entries['Disabled'].DisabledAt | Should -Be $script:DisabledAt
        $read.Entries['Other'].State | Should -Be 'unknown'
        $read.Entries['Other'].RawByte | Should -Be 1
        $read.Entries['Other'].DisabledAt | Should -BeNullOrEmpty
    }

    It 'leaves DisabledAt empty when a disabled value carries a zero time' {
        Mock Get-ItemProperty { New-RegistryValueSet @{ Off = (New-ApprovedValue -First 3) } }
        (Read-StartupApproved -Scope 'hklm').Entries['Off'].DisabledAt | Should -BeNullOrEmpty
    }

    It 'never returns the provider properties as entries' {
        Mock Get-ItemProperty { New-RegistryValueSet @{} }
        (Read-StartupApproved -Scope 'hkcu').Entries.Count | Should -Be 0
    }

    It 'reads <Scope> from <Expected>' -ForEach @(
        @{ Scope = 'hkcu'; Expected = 'HKCU:\*\StartupApproved\Run' }
        @{ Scope = 'hklm'; Expected = 'HKLM:\*\StartupApproved\Run' }
        @{ Scope = 'hklm-wow64'; Expected = 'HKLM:\*\StartupApproved\Run32' }
        @{ Scope = 'user-folder'; Expected = 'HKCU:\*\StartupApproved\StartupFolder' }
        @{ Scope = 'common-folder'; Expected = 'HKLM:\*\StartupApproved\StartupFolder' }
    ) {
        Mock Get-ItemProperty { New-RegistryValueSet @{} }
        [void](Read-StartupApproved -Scope $Scope)
        Should -Invoke Get-ItemProperty -Times 1 -Exactly -ParameterFilter { $LiteralPath -like $Expected }
    }

    It 'reports <State> when the read throws <Exception>' -ForEach @(
        @{ Exception = 'ItemNotFoundException'; State = 'absent' }
        @{ Exception = 'SecurityException'; State = 'denied' }
        @{ Exception = 'IOException'; State = 'error' }
    ) {
        $thrown = switch ($Exception) {
            'ItemNotFoundException' { [System.Management.Automation.ItemNotFoundException]::new('missing') }
            'SecurityException' { [System.Security.SecurityException]::new('denied') }
            default { [System.IO.IOException]::new('broken') }
        }
        Mock Get-ItemProperty ({ throw $thrown }.GetNewClosure())

        $read = Read-StartupApproved -Scope 'hkcu'

        $read.ReadState | Should -Be $State
        $read.Entries.Count | Should -Be 0
    }
}
