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

5. Get-MpThreatDetection failures are noted, not silently swallowed. The
   threat-history query can fail on machines with cleared event logs; the
   current state should be visible.
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:ScriptPath = Join-Path $script:SkillRoot 'scripts\windows\checks\Test-Defender.ps1'
    $script:LibRoot = Join-Path $script:SkillRoot 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Assert-CheckResult.ps1')
    Import-Module (Join-Path $script:TestsRoot 'helpers\Mock-Helpers.psm1') -Force

    if (-not (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue)) {
        throw ('Get-MpComputerStatus is not available on this host. ' +
            'Defender module required for Test-Defender.Tests.ps1.')
    }

    function Invoke-DefenderAsObject {
        param([switch]$Human)
        if ($Human) {
            $raw = & $script:ScriptPath -Human
            return $raw
        }
        $raw = & $script:ScriptPath
        $json = ($raw | Where-Object { $_ }) -join "`n"
        return $json | ConvertFrom-Json
    }
}

Describe 'Test-Defender -- healthy baseline' -Tag 'check' {
    BeforeAll {
        Mock Get-MpComputerStatus { New-MockDefenderComputerStatus }
        Mock Get-MpThreatDetection { @() }
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
        Mock Get-MpThreatDetection { @() }

        $result = Invoke-DefenderAsObject
        $result.severity | Should -Be 'WARN'
    }

    It 'CRITs when signature age exceeds 7 days' {
        Mock Get-MpComputerStatus { New-MockDefenderComputerStatus -AntivirusSignatureAge 10 }
        Mock Get-MpThreatDetection { @() }

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
        Mock Get-MpThreatDetection { @() }

        $result = Invoke-DefenderAsObject
        # Third-party AV handles detection; Defender signatures going stale is expected.
        $result.severity | Should -Be 'INFO'
    }

    It 'reports INFO at the >7 boundary in passive mode (sigAge=8)' {
        # Boundary regression guard for the if/elseif refactor in Test-Defender.ps1.
        # Original code branched on $sigAge -gt 7 first; the refactor collapses passive
        # mode into a single $sigAge -gt 3 check. Both produce INFO here, but pin the
        # behavior at the original >7 threshold so a future regression is caught.
        Mock Get-MpComputerStatus {
            New-MockDefenderComputerStatus `
                -AntivirusSignatureAge 8 `
                -AMRunningMode 'Passive Mode' `
                -RealTimeProtectionEnabled $false
        }
        Mock Get-MpThreatDetection { @() }

        $result = Invoke-DefenderAsObject
        $result.severity | Should -Be 'INFO'
    }
}

Describe 'Test-Defender -- real-time protection' -Tag 'check' {
    It 'CRITs when RTP is off in Normal mode' {
        Mock Get-MpComputerStatus {
            New-MockDefenderComputerStatus -RealTimeProtectionEnabled $false -AMRunningMode 'Normal'
        }
        Mock Get-MpThreatDetection { @() }

        $result = Invoke-DefenderAsObject
        $result.severity | Should -Be 'CRIT'
    }

    It 'does not flag RTP off when Defender is in Passive Mode' {
        Mock Get-MpComputerStatus {
            New-MockDefenderComputerStatus -RealTimeProtectionEnabled $false -AMRunningMode 'Passive Mode'
        }
        Mock Get-MpThreatDetection { @() }

        $result = Invoke-DefenderAsObject
        # RTP=off in passive mode is normal -- third-party AV is the active protection.
        $result.severity | Should -Be 'INFO'
        $result.notes | Should -Match 'passive'
    }

    It 'recognizes SxS Passive Mode as passive (modern value)' {
        Mock Get-MpComputerStatus {
            New-MockDefenderComputerStatus -RealTimeProtectionEnabled $false -AMRunningMode 'SxS Passive Mode'
        }
        Mock Get-MpThreatDetection { @() }

        $result = Invoke-DefenderAsObject
        $result.severity | Should -Be 'INFO'
    }
}

Describe 'Test-Defender -- tamper protection' -Tag 'check' {
    It 'WARNs when tamper protection is off (Normal mode)' {
        Mock Get-MpComputerStatus {
            New-MockDefenderComputerStatus -IsTamperProtected $false
        }
        Mock Get-MpThreatDetection { @() }

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
        Mock Get-MpThreatDetection { @() }

        $result = Invoke-DefenderAsObject
        # Previous code collapsed the whole severity to INFO when passive+RTP-off,
        # masking a concurrent tamper-protection finding. Tamper protection is
        # enforced regardless of passive mode -- keep the WARN.
        $result.severity | Should -Be 'WARN'
    }
}

Describe 'Test-Defender -- AM service disabled' -Tag 'check' {
    It 'CRITs when AMServiceEnabled is false (Defender not running at all)' {
        Mock Get-MpComputerStatus {
            New-MockDefenderComputerStatus -AMServiceEnabled $false
        }
        Mock Get-MpThreatDetection { @() }

        $result = Invoke-DefenderAsObject
        # AM service off means Defender is not loaded -- different from passive
        # mode (another AV is active) and different from just RTP off.
        $result.severity | Should -Be 'CRIT'
    }
}

Describe 'Test-Defender -- threat detections' -Tag 'check' {
    It 'CRITs when Get-MpThreatDetection returns recent threats' {
        $recent = [pscustomobject]@{
            InitialDetectionTime = (Get-Date).AddDays(-1)
            ThreatName           = 'Mock.Threat'
        }
        Mock Get-MpComputerStatus { New-MockDefenderComputerStatus }
        Mock Get-MpThreatDetection { @($recent) }

        $result = Invoke-DefenderAsObject
        $result.severity | Should -Be 'CRIT'
        $result.detail.recent_threat_count | Should -Be 1
    }

    It 'CRITs on recent threats even when Defender is in passive mode' {
        $recent = [pscustomobject]@{
            InitialDetectionTime = (Get-Date).AddDays(-1)
            ThreatName           = 'Mock.Threat'
        }
        Mock Get-MpComputerStatus {
            New-MockDefenderComputerStatus -AMRunningMode 'Passive Mode' -RealTimeProtectionEnabled $false
        }
        Mock Get-MpThreatDetection { @($recent) }

        $result = Invoke-DefenderAsObject
        # Even when Defender isn't the active AV, if it logged detections
        # those are real events the user should see.
        $result.severity | Should -Be 'CRIT'
    }

    It 'ignores threats older than the 30-day cutoff' {
        $old = [pscustomobject]@{
            InitialDetectionTime = (Get-Date).AddDays(-40)
            ThreatName           = 'Old.Threat'
        }
        Mock Get-MpComputerStatus { New-MockDefenderComputerStatus }
        Mock Get-MpThreatDetection { @($old) }

        $result = Invoke-DefenderAsObject
        $result.detail.recent_threat_count | Should -Be 0
        $result.severity | Should -Be 'OK'
    }

    It 'records a note when Get-MpThreatDetection fails' {
        Mock Get-MpComputerStatus { New-MockDefenderComputerStatus }
        Mock Get-MpThreatDetection { throw 'WMI query failed' }

        $result = Invoke-DefenderAsObject
        # The Defender-status check should still succeed overall -- threat
        # history is supplementary. But the failure must be visible.
        $result.notes | Should -Match 'threat history'
        $result.detail.recent_threat_count | Should -Be 0
    }
}

Describe 'Test-Defender -- failure modes' -Tag 'check' {
    It 'emits UNKNOWN when Get-MpComputerStatus throws' {
        Mock Get-MpComputerStatus { throw 'Access denied' }
        Mock Get-MpThreatDetection { @() }

        $result = Invoke-DefenderAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.severity | Should -Be 'UNKNOWN'
        $result.ran_successfully | Should -BeFalse
    }
}
