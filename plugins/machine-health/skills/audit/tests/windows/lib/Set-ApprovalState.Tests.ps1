#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Set-ApprovalState.ps1 -- the sole writer of
approvals.json and mutes.json (actions mute, unmute, approve, revoke).

.DESCRIPTION
Expected values come from the plan's "Resolver and state write" table: the
mute entry shape, the approve entry shape, unmute under every check id, revoke
setting approved = false, and the validation column. Check ids used here are
shipped catalog ids on this branch.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Set-ApprovalState.ps1' -MockHelpers
    $script:LibFile = Join-Path $script:LibRoot 'Set-ApprovalState.ps1'
    $script:vars = @('OneDrive', 'OneDriveConsumer', 'OneDriveCommercial')
    $script:saved = @{}
    foreach ($v in $script:vars) { $script:saved[$v] = [Environment]::GetEnvironmentVariable($v) }
    $script:keyA = 'ext:3f9a0c1d2e4b5a67'
    $script:keyB = 'startup:7eef5f7d094fe8c0'

    function Read-State {
        param([string] $Name)
        Get-Content -LiteralPath (Join-Path $script:stateDir $Name) -Raw | ConvertFrom-Json
    }

    # ConvertFrom-Json turns ISO strings into DateTime; read timestamps as the stored text.
    function Read-StateString {
        param([string] $Name, [string[]] $Pointer)
        $node = [System.Text.Json.Nodes.JsonNode]::Parse([System.IO.File]::ReadAllText((Join-Path $script:stateDir $Name)))
        foreach ($p in $Pointer) {
            # Assign inside each branch: an if expression would enumerate a JsonObject.
            if ($p -match '^\d+$') { $node = $node[[int]$p] } else { $node = $node[$p] }
        }
        return $node.GetValue[string]()
    }
}

AfterAll {
    foreach ($v in $script:vars) { [Environment]::SetEnvironmentVariable($v, $script:saved[$v]) }
}

Describe 'Set-ApprovalState' -Tag 'lib' {
    BeforeEach {
        foreach ($v in $script:vars) { [Environment]::SetEnvironmentVariable($v, $null) }
        $script:base = New-MachineHealthTempDir -Prefix 'machine-health-setstate'
        $script:stateDir = Join-Path $script:base 'state'
    }

    AfterEach {
        Remove-MachineHealthTempDir -Path $script:base
    }

    Context 'mute' {
        It 'appends the documented entry to mutes.json' {
            $out = Set-ApprovalState -StateBase $script:base -Action mute -CheckId 'services' `
                -FindingKey $script:keyA -Label 'Updater' -Notes 'expected' -RunId 'run-1'

            $out.Changed | Should -BeTrue
            $doc = Read-State 'mutes.json'
            $doc.schema_version | Should -Be '1.0'
            $entries = @($doc.checks.services.muted_findings)
            $entries.Count | Should -Be 1
            $entries[0].key | Should -Be $script:keyA
            $entries[0].label | Should -Be 'Updater'
            $entries[0].reason | Should -Be 'expected'
            $entries[0].run_id | Should -Be 'run-1'
            Read-StateString 'mutes.json' @('checks', 'services', 'muted_findings', '0', 'added_at') |
                Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'
        }

        It 'writes null for an omitted label, reason and run id' {
            $null = Set-ApprovalState -StateBase $script:base -Action mute -CheckId 'services' -FindingKey $script:keyA

            $entry = @((Read-State 'mutes.json').checks.services.muted_findings)[0]
            $entry.PSObject.Properties['label'].Value | Should -BeNullOrEmpty
            $entry.PSObject.Properties['reason'].Value | Should -BeNullOrEmpty
            $entry.PSObject.Properties['run_id'].Value | Should -BeNullOrEmpty
        }

        It 'skips a key already muted under that check' {
            $null = Set-ApprovalState -StateBase $script:base -Action mute -CheckId 'services' -FindingKey $script:keyA -Label 'first'

            $out = Set-ApprovalState -StateBase $script:base -Action mute -CheckId 'services' -FindingKey $script:keyA -Label 'second'

            $out.Changed | Should -BeFalse
            $entries = @((Read-State 'mutes.json').checks.services.muted_findings)
            $entries.Count | Should -Be 1
            $entries[0].label | Should -Be 'first'
        }

        It 'keeps a run id that looks like a date exactly as given' {
            $runId = '2026-10-21T08:00:00.0000000-04:00'
            $null = Set-ApprovalState -StateBase $script:base -Action mute -CheckId 'services' -FindingKey $script:keyA -RunId $runId
            $null = Set-ApprovalState -StateBase $script:base -Action mute -CheckId 'disk-space' -FindingKey $script:keyB

            Read-StateString 'mutes.json' @('checks', 'services', 'muted_findings', '0', 'run_id') | Should -Be $runId
        }

        It 'refuses <Case>' -ForEach @(
            @{ Case = 'an unknown check id'; CheckId = 'not-a-check'; Key = 'ext:3f9a0c1d2e4b5a67' }
            @{ Case = 'a key without 16 hex characters'; CheckId = 'services'; Key = 'ext:3f9a0c1d' }
            @{ Case = 'a key with an uppercase kind'; CheckId = 'services'; Key = 'EXT:3f9a0c1d2e4b5a67' }
        ) {
            { Set-ApprovalState -StateBase $script:base -Action mute -CheckId $CheckId -FindingKey $Key } | Should -Throw
            Test-Path -LiteralPath (Join-Path $script:stateDir 'mutes.json') | Should -BeFalse
        }

        It 'validates the schema before replacing, leaving an invalid file and no temp file' {
            New-Item -ItemType Directory -Path $script:stateDir -Force | Out-Null
            $mutesPath = Join-Path $script:stateDir 'mutes.json'
            $invalid = '{"schema_version":"1.0","checks":{"services":{"muted_findings":[{"key":"ext:dfe36cc7950bcbf3","added_at":"2026-10-21T12:00:00Z","approved":true}]}}}'
            [System.IO.File]::WriteAllText($mutesPath, $invalid)

            { Set-ApprovalState -StateBase $script:base -Action mute -CheckId 'services' -FindingKey $script:keyA } |
                Should -Throw -ExpectedMessage '*mutes.schema.json*'

            [System.IO.File]::ReadAllText($mutesPath) | Should -Be $invalid
            @(Get-ChildItem -LiteralPath $script:stateDir -Filter '*.tmp').Count | Should -Be 0
        }
    }

    Context 'unmute' {
        It 'removes the key under every check id and keeps other keys' {
            $null = Set-ApprovalState -StateBase $script:base -Action mute -CheckId 'services' -FindingKey $script:keyA
            $null = Set-ApprovalState -StateBase $script:base -Action mute -CheckId 'disk-space' -FindingKey $script:keyA
            $null = Set-ApprovalState -StateBase $script:base -Action mute -CheckId 'disk-space' -FindingKey $script:keyB

            $out = Set-ApprovalState -StateBase $script:base -Action unmute -FindingKey $script:keyA

            $out.Changed | Should -BeTrue
            $doc = Read-State 'mutes.json'
            @($doc.checks.services.muted_findings).Count | Should -Be 0
            @($doc.checks.'disk-space'.muted_findings | ForEach-Object key) | Should -Be @($script:keyB)
        }

        It 'refuses a key that is not muted' {
            $null = Set-ApprovalState -StateBase $script:base -Action mute -CheckId 'services' -FindingKey $script:keyB
            $before = [System.IO.File]::ReadAllText((Join-Path $script:stateDir 'mutes.json'))

            { Set-ApprovalState -StateBase $script:base -Action unmute -FindingKey $script:keyA } | Should -Throw -ExpectedMessage "*$($script:keyA)*"

            [System.IO.File]::ReadAllText((Join-Path $script:stateDir 'mutes.json')) | Should -Be $before
        }

        It 'refuses a malformed key' {
            { Set-ApprovalState -StateBase $script:base -Action unmute -FindingKey 'nope' } | Should -Throw
        }
    }

    Context 'approve and revoke' {
        It 'approves <Id> with the documented entry' -ForEach @(
            @{ Id = 'restart-stopped-service' }
            @{ Id = 'clear-temp-files' }
        ) {
            $null = Set-ApprovalState -StateBase $script:base -Action approve -RemediationId $Id -RunId 'run-7' -Notes 'reviewed'

            $entry = (Read-State 'approvals.json').remediations.$Id
            $entry.approved | Should -BeTrue
            $entry.approved_by | Should -Be 'setup picks run-7'
            $entry.notes | Should -Be 'reviewed'
            Read-StateString 'approvals.json' @('remediations', $Id, 'approved_at') | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }

        It 'records approved_by "setup apply" when no run id is given' {
            $null = Set-ApprovalState -StateBase $script:base -Action approve -RemediationId 'clear-temp-files'

            $entry = (Read-State 'approvals.json').remediations.'clear-temp-files'
            $entry.approved_by | Should -Be 'setup apply'
            $entry.PSObject.Properties['notes'].Value | Should -BeNullOrEmpty
        }

        It 'revokes <Id>: approved false, approved_at refreshed, other remediations kept' -ForEach @(
            @{ Id = 'restart-stopped-service'; Other = 'clear-temp-files' }
            @{ Id = 'clear-temp-files'; Other = 'restart-stopped-service' }
        ) {
            New-Item -ItemType Directory -Path $script:stateDir -Force | Out-Null
            $seed = '{"schema_version":"1.0","remediations":{"' + $Id + '":{"approved":true,"approved_at":"2026-01-01T00:00:00Z","approved_by":"me","notes":"n"},"' + $Other + '":{"approved":true}}}'
            [System.IO.File]::WriteAllText((Join-Path $script:stateDir 'approvals.json'), $seed)

            $null = Set-ApprovalState -StateBase $script:base -Action revoke -RemediationId $Id

            $doc = Read-State 'approvals.json'
            $doc.remediations.$Id.approved | Should -BeFalse
            Read-StateString 'approvals.json' @('remediations', $Id, 'approved_at') | Should -Match '^\d{4}-\d{2}-\d{2}T'
            Read-StateString 'approvals.json' @('remediations', $Id, 'approved_at') | Should -Not -Be '2026-01-01T00:00:00Z'
            $doc.remediations.$Id.approved_by | Should -Be 'me'
            $doc.remediations.$Other.approved | Should -BeTrue
        }

        It 'refuses <Action> for an unknown remediation id' -ForEach @(
            @{ Action = 'approve' }
            @{ Action = 'revoke' }
        ) {
            { Set-ApprovalState -StateBase $script:base -Action $Action -RemediationId 'format-disk' } | Should -Throw
            Test-Path -LiteralPath (Join-Path $script:stateDir 'approvals.json') | Should -BeFalse
        }

        It 'keeps check_overrides and migration blocks it does not touch' {
            New-Item -ItemType Directory -Path $script:stateDir -Force | Out-Null
            $seed = '{"schema_version":"1.0","remediations":{},"check_overrides":{"services":{"service_exclusions":["Spooler"]}}}'
            [System.IO.File]::WriteAllText((Join-Path $script:stateDir 'approvals.json'), $seed)

            $null = Set-ApprovalState -StateBase $script:base -Action approve -RemediationId 'clear-temp-files'

            @((Read-State 'approvals.json').check_overrides.services.service_exclusions) | Should -Be @('Spooler')
        }
    }

    Context 'locking' {
        It 'waits while another writer holds approvals.lock, then applies its change to the fresh file' {
            New-Item -ItemType Directory -Path $script:stateDir -Force | Out-Null
            $lock = Enter-RunLock -StateDir $script:stateDir -Name 'approvals'
            try {
                $libFile = $script:LibFile
                $base = $script:base
                $key = $script:keyA
                $job = Start-ThreadJob -ScriptBlock {
                    . $using:libFile
                    Set-ApprovalState -StateBase $using:base -Action mute -CheckId 'services' -FindingKey $using:key -LockTimeoutSeconds 30
                }
                Start-Sleep -Milliseconds 700
                $job.State | Should -Be 'Running'
                Test-Path -LiteralPath (Join-Path $script:stateDir 'mutes.json') | Should -BeFalse

                # The lock holder's own change lands while the second writer waits.
                $first = '{"schema_version":"1.0","checks":{"disk-space":{"muted_findings":[{"key":"' + $script:keyB + '","added_at":"2026-10-21T12:00:00Z"}]}}}'
                [System.IO.File]::WriteAllText((Join-Path $script:stateDir 'mutes.json'), $first)
            } finally {
                $lock.Dispose()
            }

            $null = Wait-Job -Job $job -Timeout 30
            $out = Receive-Job -Job $job -ErrorAction Stop
            Remove-Job -Job $job -Force

            $out.Changed | Should -BeTrue
            $doc = Read-State 'mutes.json'
            @($doc.checks.'disk-space'.muted_findings | ForEach-Object key) | Should -Be @($script:keyB)
            @($doc.checks.services.muted_findings | ForEach-Object key) | Should -Be @($script:keyA)
        }

        It 'throws naming approvals.lock when the lock stays held past the timeout' {
            New-Item -ItemType Directory -Path $script:stateDir -Force | Out-Null
            $lock = Enter-RunLock -StateDir $script:stateDir -Name 'approvals'
            try {
                { Set-ApprovalState -StateBase $script:base -Action approve -RemediationId 'clear-temp-files' -LockTimeoutSeconds 0 } |
                    Should -Throw -ExpectedMessage '*approvals.lock*'
            } finally {
                $lock.Dispose()
            }
        }
    }

    Context 'synced StateBase' {
        It 'refuses to write under a OneDrive folder and creates nothing' {
            $env:OneDrive = $script:base

            { Set-ApprovalState -StateBase $script:base -Action approve -RemediationId 'clear-temp-files' } |
                Should -Throw -ExpectedMessage '*sync root*'

            Test-Path -LiteralPath $script:stateDir | Should -BeFalse
        }
    }
}
