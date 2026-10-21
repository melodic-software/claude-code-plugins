#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/New-FindingItem.ps1 -- FindingKey, the
FindingItem shape, the ReadState closed set and the unmuted severity fold.

.DESCRIPTION
The golden keys are one-way: a stored mute names an item by its key, so a key
that changes orphans the mute. Each expected key was computed outside this
code with sha256sum over the lowercased "kind|identity|..." text, keeping its
first 16 hex characters.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'New-FindingItem.ps1'
    $script:MutesSchemaPath = Join-Path $script:SkillRoot 'catalog\schemas\mutes.schema.json'

    # A key is only useful if it can be stored: validate it inside a mutes.json.
    function Test-MuteKeyAgainstSchema([string] $Key) {
        $json = [ordered]@{
            schema_version = '1.0'
            checks         = @{ 'startup-items' = @{ muted_findings = @(@{ key = $Key; added_at = '2026-10-21T12:00:00Z' }) } }
        } | ConvertTo-Json -Depth 6
        Test-Json -Json $json -SchemaFile $script:MutesSchemaPath -ErrorAction SilentlyContinue
    }
}

Describe 'Get-FindingKey' -Tag 'lib' {
    It 'gives the golden key for kind <Kind>' -ForEach @(
        @{ Kind = 'startup'; Identity = @('hkcu', 'onedrive'); Expected = 'startup:fcc8fa5615ab65c8' }
        @{ Kind = 'task'; Identity = @('\microsoft\office\', 'officetelemetryagentlogon'); Expected = 'task:9a27d2507f423245' }
        @{ Kind = 'folder'; Identity = @('c:\users\example\appdata\local\temp'); Expected = 'folder:bfdb67d05f9288e4' }
        @{ Kind = 'app'; Identity = @('microsoft.windowsterminal_8wekyb3d8bbwe'); Expected = 'app:8768b91e77945758' }
        @{ Kind = 'ext'; Identity = @('chrome', 'default', 'nmmhkkegccagdldgiimedpiccmgmieda'); Expected = 'ext:dfe36cc7950bcbf3' }
        @{ Kind = 'listener'; Identity = @('c:\program files\example\server.exe', 'tcp', '8080'); Expected = 'listener:7dd0accad0ed96bf' }
        @{ Kind = 'exclusion'; Identity = @('path', 'c:\dev'); Expected = 'exclusion:d77aa3a2d460b8f4' }
        @{ Kind = 'detection'; Identity = @('2147735505', 'file:_c:\users\example\downloads\tool.exe'); Expected = 'detection:085a185a736c71d6' }
        @{ Kind = 'firewall'; Identity = @('{2b6a2c4e-0000-4000-8000-000000000001}'); Expected = 'firewall:20ec02ae1e9457e3' }
        @{ Kind = 'process'; Identity = @('msedge.exe'); Expected = 'process:c35c0053dbcf9f6b' }
    ) {
        $key = Get-FindingKey -Kind $Kind -Identity $Identity
        $key | Should -BeExactly $Expected
        Test-MuteKeyAgainstSchema $key | Should -BeTrue
    }

    It 'gives every kind it accepts a key that mutes.schema.json accepts' {
        $kinds = @((Get-Command Get-FindingKey).Parameters['Kind'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
                ForEach-Object ValidValues)
        $kinds.Count | Should -BeGreaterThan 0
        foreach ($kind in $kinds) {
            Test-MuteKeyAgainstSchema (Get-FindingKey -Kind $kind -Identity @('example')) |
                Should -BeTrue -Because "kind '$kind' must produce a storable key"
        }
    }

    It 'lowercases the identity before hashing, so case never changes the key' {
        Get-FindingKey -Kind 'startup' -Identity @('HKCU', 'OneDrive') | Should -BeExactly 'startup:fcc8fa5615ab65c8'
    }

    It 'joins identity fields in order, so swapping two fields changes the key' {
        Get-FindingKey -Kind 'startup' -Identity @('onedrive', 'hkcu') | Should -Not -Be 'startup:fcc8fa5615ab65c8'
    }

    It 'accepts a non-string identity field as its text' {
        Get-FindingKey -Kind 'listener' -Identity @('c:\program files\example\server.exe', 'tcp', 8080) |
            Should -BeExactly 'listener:7dd0accad0ed96bf'
    }

    It 'rejects a kind outside the closed set' {
        { Get-FindingKey -Kind 'service' -Identity @('spooler') } | Should -Throw
    }

    It 'rejects a kind in the wrong case' {
        { Get-FindingKey -Kind 'Startup' -Identity @('hkcu', 'onedrive') } | Should -Throw
    }

    It 'rejects an empty identity field' {
        { Get-FindingKey -Kind 'startup' -Identity @('hkcu', '') } | Should -Throw
    }
}

Describe 'New-FindingItem' -Tag 'lib' {
    It 'builds an item with its key, severity, muted flag and title' {
        $item = New-FindingItem -Kind 'startup' -Identity @('hkcu', 'OneDrive') -Severity 'INFO' -Title 'OneDrive'
        $item.key | Should -BeExactly 'startup:fcc8fa5615ab65c8'
        $item.severity | Should -BeExactly 'INFO'
        $item.muted | Should -BeFalse
        $item.title | Should -BeExactly 'OneDrive'
    }

    It 'marks the item muted when its key is in -MutedKeys' {
        $item = New-FindingItem -Kind 'startup' -Identity @('hkcu', 'OneDrive') -Severity 'WARN' -Title 'OneDrive' `
            -MutedKeys @('ext:dfe36cc7950bcbf3', 'startup:fcc8fa5615ab65c8')
        $item.muted | Should -BeTrue
        $item.severity | Should -BeExactly 'WARN'
    }

    It 'leaves the item unmuted when -MutedKeys holds only other keys' {
        $item = New-FindingItem -Kind 'startup' -Identity @('hkcu', 'OneDrive') -Severity 'WARN' -Title 'OneDrive' `
            -MutedKeys @('startup:7eef5f7d094fe8c0')
        $item.muted | Should -BeFalse
    }

    It 'carries the check-specific fields beside the shared ones' {
        $item = New-FindingItem -Kind 'startup' -Identity @('hkcu', 'OneDrive') -Severity 'INFO' -Title 'OneDrive' `
            -Fields @{ scope = 'hkcu'; approved_state = 'enabled' }
        $item.scope | Should -BeExactly 'hkcu'
        $item.approved_state | Should -BeExactly 'enabled'
    }

    It 'refuses a field that would overwrite a shared one' {
        { New-FindingItem -Kind 'startup' -Identity @('hkcu', 'OneDrive') -Severity 'INFO' -Title 'OneDrive' `
                -Fields @{ muted = $true } } | Should -Throw '*muted*'
    }

    It 'rejects a severity outside the ladder' {
        { New-FindingItem -Kind 'startup' -Identity @('hkcu', 'OneDrive') -Severity 'HIGH' -Title 'OneDrive' } |
            Should -Throw
    }
}

Describe 'Assert-ReadState' -Tag 'lib' {
    It 'accepts <_>' -ForEach @('ok', 'absent', 'masked', 'denied', 'false-zero', 'error') {
        Assert-ReadState $_ | Should -BeTrue
    }

    It 'rejects <_>' -ForEach @('unknown', 'OK', 'partial', '') {
        { Assert-ReadState $_ } | Should -Throw
    }
}

Describe 'Get-UnmutedSeverity' -Tag 'lib' {
    BeforeAll {
        function Get-TestItem([string] $Severity, [bool] $Muted) {
            [pscustomobject]@{ key = 'startup:fcc8fa5615ab65c8'; severity = $Severity; muted = $Muted; title = 't' }
        }
    }

    It 'ignores a muted item: a muted WARN beside an unmuted INFO folds to INFO' {
        Get-UnmutedSeverity -Items @((Get-TestItem 'WARN' $true), (Get-TestItem 'INFO' $false)) |
            Should -BeExactly 'INFO'
    }

    It 'folds to the worst unmuted severity' {
        Get-UnmutedSeverity -Items @((Get-TestItem 'INFO' $false), (Get-TestItem 'CRIT' $false), (Get-TestItem 'WARN' $false)) |
            Should -BeExactly 'CRIT'
    }

    It 'folds to OK when every item is muted' {
        Get-UnmutedSeverity -Items @((Get-TestItem 'CRIT' $true)) | Should -BeExactly 'OK'
    }

    It 'folds to OK with no items and every read ok or absent' {
        Get-UnmutedSeverity -Items @() -ReadState @('ok', 'absent') | Should -BeExactly 'OK'
    }

    It 'never folds to OK when a read was <_>' -ForEach @('masked', 'denied', 'false-zero', 'error') {
        Get-UnmutedSeverity -Items @() -ReadState @('ok', $_) | Should -Not -Be 'OK'
    }

    It 'never folds to OK when a read was masked, even with every item muted' {
        Get-UnmutedSeverity -Items @((Get-TestItem 'WARN' $true)) -ReadState @('masked') | Should -Not -Be 'OK'
    }

    It 'rejects an unknown read state' {
        { Get-UnmutedSeverity -Items @() -ReadState @('partial') } | Should -Throw
    }
}

Describe 'Test-ReadStateUsable' -Tag 'lib' {
    It 'accepts <_>' -ForEach @('ok', 'absent') {
        Test-ReadStateUsable -ReadState $_ | Should -BeTrue
    }

    It 'refuses <_>' -ForEach @('masked', 'denied', 'false-zero', 'error') {
        Test-ReadStateUsable -ReadState $_ | Should -BeFalse
    }

    It 'rejects a state outside the closed set' {
        { Test-ReadStateUsable -ReadState 'partial' } | Should -Throw
    }
}
