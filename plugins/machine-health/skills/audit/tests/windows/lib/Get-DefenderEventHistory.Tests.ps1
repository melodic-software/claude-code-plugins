#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Get-DefenderEventHistory.ps1.

.DESCRIPTION
Canned events carry the EventData field names read from a live Defender
Operational log (Threat ID, Threat Name, Path, Action ID on 1116/1117; Old Value
and New Value on 5007) and listed in Microsoft's Defender Antivirus event
reference. Values are placeholders. Action IDs follow the Set-MpPreference
remediation action table: 2 Quarantine, 6 Allow, 9 NoAction.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-DefenderEventHistory.ps1'

    function New-DefenderEvent {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test fixture constructor: builds an object, changes no system state.')]
        param(
            [Parameter(Mandatory)] [int] $Id,
            [Parameter(Mandatory)] [datetime] $TimeCreated,
            [Parameter(Mandatory)] [hashtable] $Data
        )
        $fields = foreach ($name in $Data.Keys) {
            "<Data Name='$name'>$([System.Security.SecurityElement]::Escape([string]$Data[$name]))</Data>"
        }
        $xml = "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><System><EventID>$Id</EventID></System>" +
            "<EventData>$($fields -join '')</EventData></Event>"
        $record = [pscustomobject]@{ Id = $Id; TimeCreated = $TimeCreated }
        $record | Add-Member -MemberType ScriptMethod -Name ToXml -Value { $xml }.GetNewClosure()
        return $record
    }

    function New-Detection {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test fixture constructor: builds an object, changes no system state.')]
        param([int] $Id, [datetime] $At, [string] $ThreatId = '2147000001', [string] $Resource = 'file:_<drive>:\Profile\Downloads\sample.exe', [int] $ActionId = 9)
        New-DefenderEvent -Id $Id -TimeCreated $At -Data @{
            'Threat ID'   = $ThreatId
            'Threat Name' = 'Placeholder:Win32/Sample'
            'Path'        = $Resource
            'Action ID'   = $ActionId
        }
    }

    function New-ConfigChange {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test fixture constructor: builds an object, changes no system state.')]
        param([datetime] $At, [string] $Old = '', [string] $New = '')
        New-DefenderEvent -Id 5007 -TimeCreated $At -Data @{ 'Old Value' = $Old; 'New Value' = $New }
    }

    $script:Now = Get-Date
    $script:Oldest = $script:Now.AddDays(-90)
    $script:ExclusionRoot = 'HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions'
}

Describe 'Get-DefenderEventHistory -- read state' -Tag 'lib' {
    BeforeEach {
        Mock Get-WinEvent { [pscustomobject]@{ TimeCreated = $script:Oldest } } -ParameterFilter { $Oldest }
    }

    It 'maps "No events were found" to absent with empty lists, not an error' {
        Mock Get-WinEvent {
            Write-Error -ErrorId 'NoMatchingEventsFound' -Message 'No events were found that match the specified selection criteria.' -Category ObjectNotFound
        } -ParameterFilter { $FilterHashtable }

        $history = Get-DefenderEventHistory
        $history.ReadState | Should -Be 'absent'
        @($history.Detections).Count | Should -Be 0
        @($history.ExclusionChanges).Count | Should -Be 0
        $history.LogOldestRecord | Should -Be $script:Oldest
    }

    It 'maps a missing log to error so it cannot pass as zero' {
        Mock Get-WinEvent {
            Write-Error -ErrorId 'NoMatchingLogsFound' -Message 'There is not an event log on the localhost computer that matches.' -Category ObjectNotFound
        } -ParameterFilter { $FilterHashtable }

        (Get-DefenderEventHistory).ReadState | Should -Be 'error'
    }

    It 'maps access denied to denied' {
        Mock Get-WinEvent { throw [System.UnauthorizedAccessException]::new('Attempted to perform an unauthorized operation.') } -ParameterFilter { $FilterHashtable }

        (Get-DefenderEventHistory).ReadState | Should -Be 'denied'
    }

    It 'returns a null oldest record when the oldest-record read fails' {
        Mock Get-WinEvent { @(New-Detection -Id 1116 -At $script:Now.AddDays(-1)) } -ParameterFilter { $FilterHashtable }
        Mock Get-WinEvent { throw 'log unavailable' } -ParameterFilter { $Oldest }

        $history = Get-DefenderEventHistory
        $history.ReadState | Should -Be 'ok'
        $history.LogOldestRecord | Should -BeNullOrEmpty
    }
}

Describe 'Get-DefenderEventHistory -- detections' -Tag 'lib' {
    BeforeEach {
        Mock Get-WinEvent { [pscustomobject]@{ TimeCreated = $script:Oldest } } -ParameterFilter { $Oldest }
    }

    It 'marks a 1116 followed by a Quarantine 1117 for the same threat and resource as succeeded' {
        $at = $script:Now.AddDays(-2)
        Mock Get-WinEvent {
            @(
                New-Detection -Id 1117 -At $at.AddSeconds(5) -ActionId 2
                New-Detection -Id 1116 -At $at
            )
        } -ParameterFilter { $FilterHashtable }

        $d = @((Get-DefenderEventHistory).Detections)
        $d.Count | Should -Be 1
        $d[0].ThreatId | Should -Be '2147000001'
        $d[0].ThreatName | Should -Be 'Placeholder:Win32/Sample'
        $d[0].Resource | Should -Be 'file:_<drive>:\Profile\Downloads\sample.exe'
        $d[0].DetectedAt | Should -Be $at
        $d[0].ActionSucceeded | Should -BeTrue
    }

    It 'leaves ActionSucceeded null when no 1117 matched' {
        Mock Get-WinEvent { @(New-Detection -Id 1116 -At $script:Now.AddDays(-1)) } -ParameterFilter { $FilterHashtable }

        $d = @((Get-DefenderEventHistory).Detections)
        $d.Count | Should -Be 1
        $d[0].ActionSucceeded | Should -BeNullOrEmpty
    }

    It 'marks a 1117 with Allow (6) as not succeeded' {
        $at = $script:Now.AddDays(-1)
        Mock Get-WinEvent {
            @(
                New-Detection -Id 1116 -At $at
                New-Detection -Id 1117 -At $at.AddSeconds(5) -ActionId 6
            )
        } -ParameterFilter { $FilterHashtable }

        (@((Get-DefenderEventHistory).Detections))[0].ActionSucceeded | Should -BeFalse
    }

    It 'does not let one resource''s 1117 vouch for another resource with the same threat id' {
        $at = $script:Now.AddDays(-1)
        Mock Get-WinEvent {
            @(
                New-Detection -Id 1116 -At $at -Resource 'file:_<drive>:\a.exe'
                New-Detection -Id 1116 -At $at -Resource 'file:_<drive>:\b.exe'
                New-Detection -Id 1117 -At $at.AddSeconds(5) -Resource 'file:_<drive>:\a.exe' -ActionId 2
            )
        } -ParameterFilter { $FilterHashtable }

        $d = @((Get-DefenderEventHistory).Detections)
        $d.Count | Should -Be 2
        ($d | Where-Object Resource -EQ 'file:_<drive>:\a.exe').ActionSucceeded | Should -BeTrue
        ($d | Where-Object Resource -EQ 'file:_<drive>:\b.exe').ActionSucceeded | Should -BeNullOrEmpty
    }

    It 'collapses repeated 1116s for one threat and resource into one detection at the latest time' {
        $first = $script:Now.AddDays(-20)
        $latest = $script:Now.AddDays(-1)
        Mock Get-WinEvent {
            @(
                New-Detection -Id 1116 -At $latest
                New-Detection -Id 1117 -At $first.AddSeconds(5) -ActionId 2
                New-Detection -Id 1116 -At $first
                New-Detection -Id 1116 -At $first
            )
        } -ParameterFilter { $FilterHashtable }

        $d = @((Get-DefenderEventHistory).Detections)
        $d.Count | Should -Be 1
        $d[0].DetectedAt | Should -Be $latest
        # The only 1117 predates the latest 1116: the threat came back and nothing acted on it.
        $d[0].ActionSucceeded | Should -BeNullOrEmpty
    }
}

Describe 'Get-DefenderEventHistory -- exclusion changes (5007)' -Tag 'lib' {
    BeforeEach {
        Mock Get-WinEvent { [pscustomobject]@{ TimeCreated = $script:Oldest } } -ParameterFilter { $Oldest }
    }

    It 'reads added and removed exclusions of each type and ignores other configuration changes' {
        $at = $script:Now.AddDays(-3)
        Mock Get-WinEvent {
            @(
                New-ConfigChange -At $at -New "$script:ExclusionRoot\Paths\<drive>:\build = 0x0"
                New-ConfigChange -At $at -Old "$script:ExclusionRoot\Processes\tool.exe = 0x0"
                New-ConfigChange -At $at -New "$script:ExclusionRoot\Extensions\.tmp = 0x0"
                New-ConfigChange -At $at -Old 'HKLM\SOFTWARE\Microsoft\Windows Defender\Features\TamperProtection = 0x5' `
                    -New 'HKLM\SOFTWARE\Microsoft\Windows Defender\Features\TamperProtection = 0x4'
            )
        } -ParameterFilter { $FilterHashtable }

        $changes = @((Get-DefenderEventHistory).ExclusionChanges)
        $changes.Count | Should -Be 3
        $path = $changes | Where-Object Type -EQ 'path'
        $path.Value | Should -Be '<drive>:\build'
        $path.Change | Should -Be 'added'
        $path.ChangedAt | Should -Be $at
        $proc = $changes | Where-Object Type -EQ 'process'
        $proc.Value | Should -Be 'tool.exe'
        $proc.Change | Should -Be 'removed'
        ($changes | Where-Object Type -EQ 'extension').Value | Should -Be '.tmp'
    }

    It 'keeps an exclusion value that itself contains " = "' {
        Mock Get-WinEvent {
            @(New-ConfigChange -At $script:Now -New "$script:ExclusionRoot\Paths\<drive>:\a = b = 0x0")
        } -ParameterFilter { $FilterHashtable }

        (@((Get-DefenderEventHistory).ExclusionChanges))[0].Value | Should -Be '<drive>:\a = b'
    }
}
