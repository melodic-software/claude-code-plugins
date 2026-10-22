#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Resolve-CheckupPick.ps1 -- a pasted checkup-picks
payload resolved against the one id map its run: line names.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Resolve-CheckupPick.ps1'

    $script:Views = Join-Path $TestDrive 'views'
    New-Item -ItemType Directory -Path $script:Views | Out-Null
    $script:KeyA = 'ext:3f9a0c1d2e4b5a67'
    $script:KeyX = 'exclusion:0011223344556677'
    $mapA = @{
        format = 'checkup-ids/1'; run_id = '2026-10-21T07:00:00.0000000-05:00'; built_at = 'x'; page_sha256 = 'x'
        rows   = @{
            'areas-1-items-1-mute-1' = @{ action = 'mute'; check_id = 'browser-extensions'; finding_key = $script:KeyA; label = "Bad`nExtension" }
            'areas-2-items-1-mute-1' = @{ action = 'mute'; check_id = 'defender-exclusions'; finding_key = $script:KeyX; label = 'C:\Tools' }
            'areas-3-items-1-mute-1' = @{ action = 'mute'; check_id = 'not-a-check'; finding_key = $script:KeyA; label = 'x' }
            'areas-4-items-1-mute-1' = @{ action = 'mute'; check_id = 'services'; finding_key = 'svc:nothex'; label = 'x' }
            'remediations-1'         = @{ action = 'approve'; remediation_id = 'clear-temp-files' }
            'remediations-9'         = @{ action = 'approve'; remediation_id = 'reboot-now' }
            'areas-5-items-1-mute-1' = @{ action = 'delete'; check_id = 'services' }
        }
    }
    $mapA | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $script:Views 'checkup-2026-10-21T120000000Z.ids.json')
    $mapB = @{
        format = 'checkup-ids/1'; run_id = 'run-b'
        rows   = @{ 'areas-9-items-9-mute-1' = @{ action = 'mute'; check_id = 'services'; finding_key = 'task:0011223344556677'; label = 'only in B' } }
    }
    $mapB | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $script:Views 'checkup-2026-10-20T120000000Z.ids.json')

    function Get-Payload([string] $Picked, [string] $Run = '2026-10-21t120000000z', [string] $Notes) {
        $lines = @('checkup-picks', "picked: $Picked", "run: $Run")
        if ($Notes) { $lines += "notes: $Notes" }
        $lines -join "`n"
    }
}

Describe 'Resolve-CheckupPick' -Tag 'lib' {
    Context 'a payload it accepts' {
        It 'resolves a mute pick to its check, key and label from the named map' {
            $p = @(Resolve-CheckupPick -ViewsDir $script:Views -Payload (Get-Payload 'areas-1-items-1-mute-1'))
            $p.Count | Should -Be 1
            $p[0].Action | Should -Be 'mute'
            $p[0].CheckId | Should -Be 'browser-extensions'
            $p[0].FindingKey | Should -Be $script:KeyA
            $p[0].Label | Should -Be 'Bad Extension'
            $p[0].RunId | Should -Be '2026-10-21T07:00:00.0000000-05:00'
            $p[0].Refused | Should -BeNullOrEmpty
        }

        It 'resolves an approve pick to a shipped remediation' {
            $p = Resolve-CheckupPick -ViewsDir $script:Views -Payload (Get-Payload 'remediations-1')
            $p.Action | Should -Be 'approve'
            $p.RemediationId | Should -Be 'clear-temp-files'
            $p.Refused | Should -BeNullOrEmpty
        }

        It 'mutes an exclusion key under both defender and defender-exclusions' {
            $p = @(Resolve-CheckupPick -ViewsDir $script:Views -Payload (Get-Payload 'areas-2-items-1-mute-1'))
            $p.CheckId | Should -Be @('defender', 'defender-exclusions')
            $p.FindingKey | Should -Be @($script:KeyX, $script:KeyX)
        }

        It 'keeps a multi-line note whole and never reads a run: or picked: line inside it' {
            $payload = (Get-Payload 'remediations-1') + "`nnotes: first line`nrun: 2026-10-20t120000000z`npicked: areas-9-items-9-mute-1"
            $p = @(Resolve-CheckupPick -ViewsDir $script:Views -Payload $payload)
            $p.Count | Should -Be 1
            $p[0].RowId | Should -Be 'remediations-1'
            $p[0].Notes | Should -Be "first line`nrun: 2026-10-20t120000000z`npicked: areas-9-items-9-mute-1"
        }

        It 'accepts CRLF line ends and surrounding blank lines, and returns nothing for picked: none' {
            $payload = "`r`n" + ((Get-Payload 'none') -replace "`n", "`r`n") + "`r`n"
            @(Resolve-CheckupPick -ViewsDir $script:Views -Payload $payload).Count | Should -Be 0
        }

        It 'returns one pick for an id picked twice' {
            @(Resolve-CheckupPick -ViewsDir $script:Views -Payload (Get-Payload 'remediations-1 remediations-1')).Count | Should -Be 1
        }
    }

    Context 'picks it refuses' {
        It 'refuses an id not in the map' {
            $p = Resolve-CheckupPick -ViewsDir $script:Views -Payload (Get-Payload 'areas-7-items-1-mute-1')
            $p.Refused | Should -Match 'not a row of run 2026-10-21T120000000Z'
        }

        It 'refuses an id present only in another kept map' {
            $p = Resolve-CheckupPick -ViewsDir $script:Views -Payload (Get-Payload 'areas-9-items-9-mute-1')
            $p.Refused | Should -Match 'not a row'
        }

        It 'refuses an id that does not match the row id pattern' -ForEach @(
            @{ Id = 'AREAS-1' }, @{ Id = 'areas_1' }, @{ Id = ('a' * 129) }, @{ Id = '../x' }
        ) {
            $p = Resolve-CheckupPick -ViewsDir $script:Views -Payload (Get-Payload $Id)
            $p.Refused | Should -Be 'not a row id'
            $p.Action | Should -BeNullOrEmpty
        }

        It 'refuses an approve id outside the shipped remediations' {
            (Resolve-CheckupPick -ViewsDir $script:Views -Payload (Get-Payload 'remediations-9')).Refused |
                Should -Match "'reboot-now' is not a shipped remediation"
        }

        It 'refuses a mute row whose check is not shipped or whose key is not a FindingKey' {
            (Resolve-CheckupPick -ViewsDir $script:Views -Payload (Get-Payload 'areas-3-items-1-mute-1')).Refused | Should -Match 'not a shipped check'
            (Resolve-CheckupPick -ViewsDir $script:Views -Payload (Get-Payload 'areas-4-items-1-mute-1')).Refused | Should -Match 'not a FindingKey'
        }

        It 'refuses a row whose action is neither mute nor approve' {
            (Resolve-CheckupPick -ViewsDir $script:Views -Payload (Get-Payload 'areas-5-items-1-mute-1')).Refused | Should -Match 'neither mute nor approve'
        }
    }

    Context 'a payload it refuses whole' {
        It 'refuses a payload with no run: line' {
            { Resolve-CheckupPick -ViewsDir $script:Views -Payload "checkup-picks`npicked: remediations-1" } |
                Should -Throw '*exactly one run: line*'
        }

        It 'refuses a payload naming a pruned map, with the run named' {
            { Resolve-CheckupPick -ViewsDir $script:Views -Payload (Get-Payload 'remediations-1' -Run '2026-01-01t000000000z') } |
                Should -Throw '*run 2026-01-01T000000000Z has no id map*'
        }

        It 'refuses <Why>' -ForEach @(
            @{ Why = 'a wrong first line'; Text = "picks`npicked: none`nrun: 2026-10-21t120000000z" }
            @{ Why = 'two run: lines'; Text = "checkup-picks`npicked: none`nrun: 2026-10-21t120000000z`nrun: 2026-10-20t120000000z" }
            @{ Why = 'two picked: lines'; Text = "checkup-picks`npicked: none`npicked: remediations-1`nrun: 2026-10-21t120000000z" }
            @{ Why = 'an unknown line before notes'; Text = "checkup-picks`npicked: none`nrun: 2026-10-21t120000000z`napprove: all" }
            @{ Why = 'a run stamp that is a path'; Text = "checkup-picks`npicked: none`nrun: ..\..\state\approvals" }
            @{ Why = 'an uppercase run stamp'; Text = "checkup-picks`npicked: none`nrun: 2026-10-21T120000000Z" }
        ) {
            { Resolve-CheckupPick -ViewsDir $script:Views -Payload $Text } | Should -Throw '*payload refused*'
        }

        It 'refuses a map that is not a checkup-ids/1 map' {
            '{"format":"other","rows":{}}' | Set-Content -LiteralPath (Join-Path $script:Views 'checkup-2026-10-19T120000000Z.ids.json')
            { Resolve-CheckupPick -ViewsDir $script:Views -Payload (Get-Payload 'none' -Run '2026-10-19t120000000z') } |
                Should -Throw '*not a checkup-ids/1 map*'
        }
    }
}
