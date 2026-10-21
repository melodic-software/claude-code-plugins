#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/checks/Test-Defender.ps1.

.DESCRIPTION
Pins these rubric fixes:

1. Passive-mode semantics. When Defender is the secondary AV (a third-party
   product is the active protection), RTP=off is the DESIGNED state, not an
   emergency. The check should report INFO with a note, not CRIT. But
   tamper protection and active threats are still real findings regardless
   of mode. The previous code collapsed the whole severity to INFO when RTP
   was off -- which masked a concurrent tamper-protection-off finding.

2. AMRunningMode value parity. Modern Windows reports "SxS Passive Mode"
   (Side-by-Side) in addition to "Passive Mode". The previous code only
   matched "Passive Mode" literally.

3. AMServiceEnabled=false is "Defender is not loaded" -- not the same as
   passive mode. The previous code didn't check this at all; an AV-disabled
   machine would report OK as long as signatures were fresh.

4. Null-comparison ordering (PSSA rule PSPossibleIncorrectComparisonWithNull).
   Previous code used `$x -ne $null`; new code uses `$null -ne $x`.

5. Detection history comes from the Defender event log (Get-DefenderEventHistory),
   because Get-MpThreatDetection forgets detections after the scan-history
   purge. A failed history read is noted and can never leave the check OK.

6. Detection severity: a detection in the recent window with no successful
   remediation is CRIT, one whose remediation succeeded is WARN, an older one
   is INFO. A muted item never raises the check's severity.

7. Exclusion changes (event 5007) are listed as items, but their values stay
   out of the summary and notes.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -Check 'Test-Defender' -AsObject 'Invoke-DefenderAsObject' `
        -LibScript 'Get-DefenderEventHistory.ps1', 'New-FindingItem.ps1' -MockHelpers

    if (-not (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue)) {
        throw ('Get-MpComputerStatus is not available on this host. ' +
            'Defender module required for Test-Defender.Tests.ps1.')
    }

    function New-EventHistory {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test fixture constructor: builds an object, changes no system state.')]
        param(
            [string] $ReadState = 'absent',
            [object[]] $Detections = @(),
            [object[]] $ExclusionChanges = @()
        )
        [pscustomobject]@{
            ReadState        = $ReadState
            LogOldestRecord  = (Get-Date).AddDays(-90)
            Detections       = $Detections
            ExclusionChanges = $ExclusionChanges
        }
    }

    function New-Detection {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test fixture constructor: builds an object, changes no system state.')]
        param([int] $DaysAgo, [AllowNull()] $ActionSucceeded, [string] $Resource = 'file:_<drive>:\Profile\sample.exe')
        [pscustomobject]@{
            ThreatId        = '2147000001'
            ThreatName      = 'Placeholder:Win32/Sample'
            Resource        = $Resource
            DetectedAt      = (Get-Date).AddDays(-$DaysAgo)
            ActionSucceeded = $ActionSucceeded
        }
    }

    function Invoke-DefenderWithMuteList {
        param([string[]] $MutedKeys)
        ConvertFrom-CheckOutput (& $script:ScriptPath -MutedKeys $MutedKeys)
    }
}

Describe 'Test-Defender -- healthy baseline' -Tag 'check' {
    BeforeAll {
        Mock Get-MpComputerStatus { New-MockDefenderComputerStatus }
        Mock Get-DefenderEventHistory { New-EventHistory }
    }

    It 'emits a schema-valid CheckResult' {
        $result = Invoke-DefenderAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.id | Should -Be 'defender'
    }

    It 'reports OK for a normally-configured Defender' {
        $result = Invoke-DefenderAsObject
        $result.severity | Should -Be 'OK'
    }

    It 'populates the expected detail fields' {
        $result = Invoke-DefenderAsObject
        $result.detail.signature_age_days | Should -Be 1
        $result.detail.real_time_protection | Should -BeTrue
        $result.detail.tamper_protection | Should -BeTrue
        $result.detail.running_mode | Should -Be 'Normal'
    }
}

Describe 'Test-Defender -- signature age' -Tag 'check' {
    It 'WARNs when signature age is between 4 and 7 days' {
        Mock Get-MpComputerStatus { New-MockDefenderComputerStatus -AntivirusSignatureAge 5 }
        Mock Get-DefenderEventHistory { New-EventHistory }

        $result = Invoke-DefenderAsObject
        $result.severity | Should -Be 'WARN'
    }

    It 'CRITs when signature age exceeds 7 days' {
        Mock Get-MpComputerStatus { New-MockDefenderComputerStatus -AntivirusSignatureAge 10 }
        Mock Get-DefenderEventHistory { New-EventHistory }

        $result = Invoke-DefenderAsObject
        $result.severity | Should -Be 'CRIT'
    }

    It 'downgrades stale signatures to INFO when Defender is in passive mode' {
        Mock Get-MpComputerStatus {
            New-MockDefenderComputerStatus `
                -AntivirusSignatureAge 10 `
                -AMRunningMode 'Passive Mode' `
                -RealTimeProtectionEnabled $false
        }
        Mock Get-DefenderEventHistory { New-EventHistory }

        $result = Invoke-DefenderAsObject
        # Third-party AV handles detection; Defender signatures going stale is expected.
        $result.severity | Should -Be 'INFO'
    }

    It 'reports INFO at the >7 boundary in passive mode (sigAge=8)' {
        # Boundary regression guard: passive mode checks $sigAge -gt 3, so pin the
        # behavior at the >7 threshold too.
        Mock Get-MpComputerStatus {
            New-MockDefenderComputerStatus `
                -AntivirusSignatureAge 8 `
                -AMRunningMode 'Passive Mode' `
                -RealTimeProtectionEnabled $false
        }
        Mock Get-DefenderEventHistory { New-EventHistory }

        $result = Invoke-DefenderAsObject
        $result.severity | Should -Be 'INFO'
    }
}

Describe 'Test-Defender -- real-time protection' -Tag 'check' {
    It 'CRITs when RTP is off in Normal mode' {
        Mock Get-MpComputerStatus {
            New-MockDefenderComputerStatus -RealTimeProtectionEnabled $false -AMRunningMode 'Normal'
        }
        Mock Get-DefenderEventHistory { New-EventHistory }

        $result = Invoke-DefenderAsObject
        $result.severity | Should -Be 'CRIT'
    }

    It 'does not flag RTP off when Defender is in Passive Mode' {
        Mock Get-MpComputerStatus {
            New-MockDefenderComputerStatus -RealTimeProtectionEnabled $false -AMRunningMode 'Passive Mode'
        }
        Mock Get-DefenderEventHistory { New-EventHistory }

        $result = Invoke-DefenderAsObject
        # RTP=off in passive mode is normal -- third-party AV is the active protection.
        $result.severity | Should -Be 'INFO'
        $result.notes | Should -Match 'passive'
    }

    It 'recognizes SxS Passive Mode as passive (modern value)' {
        Mock Get-MpComputerStatus {
            New-MockDefenderComputerStatus -RealTimeProtectionEnabled $false -AMRunningMode 'SxS Passive Mode'
        }
        Mock Get-DefenderEventHistory { New-EventHistory }

        $result = Invoke-DefenderAsObject
        $result.severity | Should -Be 'INFO'
    }
}

Describe 'Test-Defender -- tamper protection' -Tag 'check' {
    It 'WARNs when tamper protection is off (Normal mode)' {
        Mock Get-MpComputerStatus {
            New-MockDefenderComputerStatus -IsTamperProtected $false
        }
        Mock Get-DefenderEventHistory { New-EventHistory }

        $result = Invoke-DefenderAsObject
        $result.severity | Should -Be 'WARN'
    }

    It 'still WARNs about tamper protection in passive mode (regression)' {
        Mock Get-MpComputerStatus {
            New-MockDefenderComputerStatus `
                -RealTimeProtectionEnabled $false `
                -IsTamperProtected $false `
                -AMRunningMode 'Passive Mode'
        }
        Mock Get-DefenderEventHistory { New-EventHistory }

        $result = Invoke-DefenderAsObject
        # Passive mode with RTP off must not collapse severity to INFO and mask a concurrent
        # tamper-protection finding: tamper protection applies regardless of passive mode.
        $result.severity | Should -Be 'WARN'
    }
}

Describe 'Test-Defender -- AM service disabled' -Tag 'check' {
    It 'CRITs when AMServiceEnabled is false (Defender not running at all)' {
        Mock Get-MpComputerStatus {
            New-MockDefenderComputerStatus -AMServiceEnabled $false
        }
        Mock Get-DefenderEventHistory { New-EventHistory }

        $result = Invoke-DefenderAsObject
        # AM service off means Defender is not loaded -- different from passive
        # mode (another AV is active) and different from just RTP off.
        $result.severity | Should -Be 'CRIT'
    }
}

Describe 'Test-Defender -- detections from events' -Tag 'check' {
    BeforeEach {
        Mock Get-MpComputerStatus { New-MockDefenderComputerStatus }
    }

    It 'CRITs on a recent detection with no remediation recorded' {
        Mock Get-DefenderEventHistory { New-EventHistory -ReadState 'ok' -Detections @(New-Detection -DaysAgo 1 -ActionSucceeded $null) }

        $result = Invoke-DefenderAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.severity | Should -Be 'CRIT'
        $result.detail.recent_threat_count | Should -Be 1
        $item = @($result.detail.items)[0]
        $item.severity | Should -Be 'CRIT'
        $item.key | Should -Be (Get-FindingKey -Kind 'detection' -Identity '2147000001', 'file:_<drive>:\Profile\sample.exe')
        $item.threat_name | Should -Be 'Placeholder:Win32/Sample'
        $item.action_succeeded | Should -BeNullOrEmpty
    }

    It 'CRITs on a recent detection whose recorded action did not remediate' {
        Mock Get-DefenderEventHistory { New-EventHistory -ReadState 'ok' -Detections @(New-Detection -DaysAgo 1 -ActionSucceeded $false) }

        (Invoke-DefenderAsObject).severity | Should -Be 'CRIT'
    }

    It 'WARNs when every recent detection was remediated' {
        Mock Get-DefenderEventHistory {
            New-EventHistory -ReadState 'ok' -Detections @(
                New-Detection -DaysAgo 1 -ActionSucceeded $true
                New-Detection -DaysAgo 2 -ActionSucceeded $true -Resource 'file:_<drive>:\Profile\other.exe'
            )
        }

        $result = Invoke-DefenderAsObject
        $result.severity | Should -Be 'WARN'
        $result.detail.recent_threat_count | Should -Be 2
    }

    It 'lists a detection older than 30 days as INFO history' {
        Mock Get-DefenderEventHistory { New-EventHistory -ReadState 'ok' -Detections @(New-Detection -DaysAgo 31 -ActionSucceeded $null) }

        $result = Invoke-DefenderAsObject
        $result.severity | Should -Be 'INFO'
        $result.detail.recent_threat_count | Should -Be 0
        @($result.detail.items)[0].severity | Should -Be 'INFO'
    }

    It 'CRITs on recent unremediated detections even when Defender is in passive mode' {
        Mock Get-MpComputerStatus {
            New-MockDefenderComputerStatus -AMRunningMode 'Passive Mode' -RealTimeProtectionEnabled $false
        }
        Mock Get-DefenderEventHistory { New-EventHistory -ReadState 'ok' -Detections @(New-Detection -DaysAgo 1 -ActionSucceeded $null) }

        (Invoke-DefenderAsObject).severity | Should -Be 'CRIT'
    }

    It 'keeps a muted detection listed without raising severity' {
        Mock Get-DefenderEventHistory { New-EventHistory -ReadState 'ok' -Detections @(New-Detection -DaysAgo 1 -ActionSucceeded $null) }
        $key = Get-FindingKey -Kind 'detection' -Identity '2147000001', 'file:_<drive>:\Profile\sample.exe'

        $result = Invoke-DefenderWithMuteList -MutedKeys @($key)
        $result.severity | Should -Be 'OK'
        $result.detail.items_count | Should -Be 1
        $result.detail.muted_count | Should -Be 1
        @($result.detail.items)[0].muted | Should -BeTrue
    }

    It 'reports OK with zero counts when the log holds no matching events' {
        Mock Get-DefenderEventHistory { New-EventHistory -ReadState 'absent' }

        $result = Invoke-DefenderAsObject
        $result.severity | Should -Be 'OK'
        $result.detail.events_read_state | Should -Be 'absent'
        $result.detail.recent_threat_count | Should -Be 0
        $result.detail.items_count | Should -Be 0
        $result.detail.muted_count | Should -Be 0
        $result.detail.exclusion_change_count | Should -Be 0
        $result.detail.log_oldest_record | Should -Not -BeNullOrEmpty
    }

    It 'never reports OK when the event history could not be read, and says so' {
        Mock Get-DefenderEventHistory { New-EventHistory -ReadState 'error' }

        $result = Invoke-DefenderAsObject
        $result.severity | Should -Be 'UNKNOWN'
        $result.notes | Should -Match 'threat history'
        $result.detail.events_read_state | Should -Be 'error'
        $result.detail.threat_query_error | Should -Not -BeNullOrEmpty
    }

    It 'keeps a system CRIT when the event history could not be read' {
        Mock Get-MpComputerStatus { New-MockDefenderComputerStatus -RealTimeProtectionEnabled $false }
        Mock Get-DefenderEventHistory { New-EventHistory -ReadState 'denied' }

        (Invoke-DefenderAsObject).severity | Should -Be 'CRIT'
    }
}

Describe 'Test-Defender -- exclusion change history (5007)' -Tag 'check' {
    BeforeAll {
        $script:Sentinel = '<drive>:\Sentinel-5007-value'
    }

    BeforeEach {
        Mock Get-MpComputerStatus { New-MockDefenderComputerStatus }
        # Mock bodies do not reliably see $script: variables, so the sentinel is repeated here.
        Mock Get-DefenderEventHistory {
            New-EventHistory -ReadState 'ok' -ExclusionChanges @(
                [pscustomobject]@{ Type = 'path'; Value = '<drive>:\Sentinel-5007-value'; Change = 'added'; ChangedAt = (Get-Date).AddDays(-3) }
            )
        }
    }

    It 'lists the change as an INFO exclusion item labeled as history within retention' {
        $result = Invoke-DefenderAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.severity | Should -Be 'INFO'
        $result.detail.exclusion_change_count | Should -Be 1
        $item = @($result.detail.items)[0]
        $item.key | Should -Be (Get-FindingKey -Kind 'exclusion' -Identity 'path', $script:Sentinel)
        $item.severity | Should -Be 'INFO'
        $item.exclusion_type | Should -Be 'path'
        $item.change | Should -Be 'added'
        $item.value | Should -Be $script:Sentinel
        $item.label | Should -Match 'history within log retention since'
    }

    It 'keeps the exclusion value out of the summary and notes' {
        $result = Invoke-DefenderAsObject
        $result.summary | Should -Not -Match ([regex]::Escape($script:Sentinel))
        "$($result.notes)" | Should -Not -Match ([regex]::Escape($script:Sentinel))
    }

    It 'does not raise severity for a muted exclusion change' {
        $result = Invoke-DefenderWithMuteList -MutedKeys @(Get-FindingKey -Kind 'exclusion' -Identity 'path', $script:Sentinel)
        $result.severity | Should -Be 'OK'
        $result.detail.muted_count | Should -Be 1
    }
}

Describe 'Test-Defender -- failure modes' -Tag 'check' {
    It 'emits UNKNOWN when Get-MpComputerStatus throws' {
        Mock Get-MpComputerStatus { throw 'Access denied' }
        Mock Get-DefenderEventHistory { New-EventHistory }

        $result = Invoke-DefenderAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.severity | Should -Be 'UNKNOWN'
        $result.ran_successfully | Should -BeFalse
    }
}
