#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Write-CheckupPick.ps1 -- the picks the owner
confirmed by number, checked whole and then written through Set-ApprovalState.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Write-CheckupPick.ps1' -MockHelpers
    $script:vars = @('OneDrive', 'OneDriveConsumer', 'OneDriveCommercial')
    $script:saved = @{}
    foreach ($v in $script:vars) { $script:saved[$v] = [Environment]::GetEnvironmentVariable($v) }
    $script:Key = 'ext:3f9a0c1d2e4b5a67'
    $script:Payload = "checkup-picks`npicked: areas-1-items-1-mute-1 remediations-1 areas-9-items-1-mute-1`nrun: 2026-10-21t120000000z`nnotes: expected"
}

AfterAll {
    foreach ($v in $script:vars) { [Environment]::SetEnvironmentVariable($v, $script:saved[$v]) }
}

Describe 'Write-CheckupPick' -Tag 'lib' {
    BeforeEach {
        foreach ($v in $script:vars) { [Environment]::SetEnvironmentVariable($v, $null) }
        $script:Base = New-MachineHealthTempDir -Prefix 'machine-health-writepick'
        $views = New-Item -ItemType Directory -Path (Join-Path $script:Base 'views')
        @{
            format = 'checkup-ids/1'; run_id = '2026-10-21T07:00:00.0000000-05:00'
            rows   = @{
                'areas-1-items-1-mute-1' = @{ action = 'mute'; check_id = 'browser-extensions'; finding_key = $script:Key; label = 'Extension' }
                'remediations-1'         = @{ action = 'approve'; remediation_id = 'clear-temp-files' }
            }
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $views 'checkup-2026-10-21T120000000Z.ids.json')
        # Numbered as setup lists them: the same resolver call over the same payload.
        $script:Picks = @(Resolve-CheckupPick -ViewsDir $views.FullName -Payload $script:Payload)
        $script:N = @{}
        for ($i = 0; $i -lt $script:Picks.Count; $i++) {
            $p = $script:Picks[$i]
            $script:N[$(if ($p.Refused) { 'refused' } else { $p.Action })] = $i + 1
        }
        $script:Written = { Test-Path -LiteralPath (Join-Path $script:Base 'state') }
    }

    AfterEach {
        Remove-MachineHealthTempDir -Path $script:Base
    }

    It 'writes the confirmed mute and approval' {
        Write-CheckupPick -StateBase $script:Base -Payload $script:Payload -Mute $script:N.mute -Approve $script:N.approve | Out-Null

        $mutes = Get-Content -Raw -LiteralPath (Join-Path $script:Base 'state\mutes.json') | ConvertFrom-Json
        $mutes.checks.'browser-extensions'.muted_findings[0].key | Should -BeExactly $script:Key
        $approvals = Get-Content -Raw -LiteralPath (Join-Path $script:Base 'state\approvals.json') | ConvertFrom-Json
        $approvals.remediations.'clear-temp-files'.approved | Should -BeTrue
    }

    It 'writes nothing when a number is <Case>' -ForEach @(
        @{ Case = 'off the list'; Mute = { @($script:N.mute) }; Approve = { @(99) }; Message = '*pick 99 is not on the list*' }
        @{ Case = 'refused'; Mute = { @($script:N.mute, $script:N.refused) }; Approve = { @() }; Message = '*is refused*' }
        @{ Case = 'an approval on the mute list'; Mute = { @($script:N.mute, $script:N.approve) }; Approve = { @() }; Message = '*not on the mute list*' }
        @{ Case = 'a mute on the approve list'; Mute = { @() }; Approve = { @($script:N.approve, $script:N.mute) }; Message = '*not on the approve list*' }
    ) {
        { Write-CheckupPick -StateBase $script:Base -Payload $script:Payload -Mute (& $Mute) -Approve (& $Approve) } |
            Should -Throw $Message
        & $script:Written | Should -BeFalse
    }
}
