#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/Format-ShortReport.ps1 -- the at most 12-line run
summary built from state/latest.json.
#>

BeforeAll {
    . "$PSScriptRoot\..\helpers\Initialize-CheckSuite.ps1"
    $script:ScriptPath = Join-Path $script:SkillRoot 'scripts\windows\Format-ShortReport.ps1'
    $script:Marker = 'machine-health checkup '
    $script:RunId = '2026-10-01T09:00:00.0000000-04:00'

    function Get-CheckFixture([string] $Id, [string] $Category, [string] $Severity, [string] $Summary, [hashtable] $Detail = @{}) {
        [ordered]@{ id = $Id; category = $Category; os = 'windows'; severity = $Severity; summary = $Summary
            detail = $Detail; needs_admin = $false; ran_successfully = $true }
    }

    function Get-FolderFixture([string] $Path, $Bytes, [bool] $Muted) {
        [ordered]@{ key = 'folder:0123456789abcdef'; severity = 'INFO'; muted = $Muted
            title = ($null -eq $Bytes ? "$Path (skipped: cloud sync root)" : "$Path ($Bytes bytes)")
            path = $Path; logical_bytes = $Bytes }
    }

    # A full run: one CRIT, three WARN (only the first two by catalog order fit the worst three
    # after the CRIT), the three intruder checks, a storage list whose largest folder is muted, and
    # two cadence-deferred checks.
    function Get-SnapshotFixture([string] $HostName = 'TESTHOST', [string] $Summary = 'C: at 97% used', [string] $FolderPath = 'X:\Profile\Videos') {
        [ordered]@{
            run_id = $script:RunId; hostname = $HostName; os = 'windows'; os_version = '10.0'
            elevated = $false; run_mode = 'on-demand'; dry_run = $false
            checks = @(
                Get-CheckFixture -Id 'disk-space' -Category 'storage' -Severity 'CRIT' -Summary $Summary
                Get-CheckFixture -Id 'os-updates' -Category 'updates' -Severity 'WARN' -Summary '3 updates pending'
                Get-CheckFixture -Id 'winget-upgrades' -Category 'updates' -Severity 'WARN' -Summary '5 upgrades available'
                Get-CheckFixture -Id 'services' -Category 'services' -Severity 'WARN' -Summary '1 automatic service stopped'
                Get-CheckFixture -Id 'defender' -Category 'security' -Severity 'OK' -Summary 'Defender healthy.' -Detail @{ recent_threat_count = 2; events_read_state = 'ok' }
                Get-CheckFixture -Id 'network-listeners' -Category 'security' -Severity 'INFO' -Summary 'listeners' -Detail @{ exposed_unsigned_count = 1; read_state = 'ok' }
                Get-CheckFixture -Id 'defender-exclusions' -Category 'security' -Severity 'UNKNOWN' -Summary 'needs admin' -Detail @{ list_state = 'masked' }
                Get-CheckFixture -Id 'storage-top-n' -Category 'storage' -Severity 'INFO' -Summary 'top folders' -Detail @{ items = @(
                        Get-FolderFixture -Path 'X:\Profile\Huge' -Bytes 9000000000 -Muted $true
                        Get-FolderFixture -Path $FolderPath -Bytes 5000000000 -Muted $false
                        Get-FolderFixture -Path 'X:\Profile\OneDrive' -Bytes $null -Muted $false
                    ) }
            )
            remediations = @(); discovered_checks = @(); duration_seconds = 42; cadence_deferred_count = 2
        }
    }

    # Writes the snapshot, a history whose prior run had WARN 2 (an older run had none; this run's
    # own line, appended after latest.json, has WARN 3), the report and the page. The report and
    # page names are arbitrary: the script prints the paths latest.json records, never rebuilt ones.
    function Initialize-RunFolder($Snapshot, [switch] $NoArtifacts) {
        $base = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $state = New-Item -ItemType Directory -Path (Join-Path $base 'state')
        New-Item -ItemType Directory -Path (Join-Path $base 'views'), (Join-Path $base 'reports') | Out-Null
        $report = Join-Path $base 'reports\health-fixture.md'
        $page = Join-Path $base 'views\checkup-fixture.html'
        if (-not $NoArtifacts) {
            $Snapshot.report_path = $report
            $Snapshot.page_path = $page
            Set-Content -LiteralPath $report -Value 'report'
            Set-Content -LiteralPath $page -Value 'page'
        }
        $Snapshot | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $state 'latest.json') -Encoding utf8
        $older = @{ run_id = '2026-08-01T09:00:00.0000000-04:00'; severity_counts = @{ storage = @{ CRIT = 1 } } }
        $prior = @{ run_id = '2026-09-01T09:00:00.0000000-04:00'
            severity_counts = @{ storage = @{ CRIT = 1; INFO = 1 }; updates = @{ WARN = 2 }; security = @{ OK = 1; INFO = 1; UNKNOWN = 1 } } }
        $self = @{ run_id = $script:RunId
            severity_counts = @{ storage = @{ CRIT = 1; INFO = 1 }; updates = @{ WARN = 2 }; services = @{ WARN = 1 }; security = @{ OK = 1; INFO = 1; UNKNOWN = 1 } } }
        Set-Content -LiteralPath (Join-Path $state 'history.jsonl') -Encoding utf8 -Value @(
            $older, $prior, $self | ForEach-Object { $_ | ConvertTo-Json -Depth 5 -Compress })
        [pscustomobject]@{ Base = $base; Latest = Join-Path $state 'latest.json'; Report = $report; Page = $page }
    }

    function Invoke-ShortReport([string] $LatestPath) {
        $output = & $script:ScriptPath -LatestPath $LatestPath
        $text = @($output) -join "`n"
        [pscustomobject]@{ Text = $text; Lines = @($text -split "`n"); ExitCode = $LASTEXITCODE }
    }
}

Describe 'Format-ShortReport' -Tag 'lib' {
    Context 'a full run' {
        BeforeAll {
            $script:Run = Initialize-RunFolder (Get-SnapshotFixture)
            $script:Out = Invoke-ShortReport $script:Run.Latest
        }

        It 'prints exactly these ten lines, the first one fixed' {
            $script:Out.Lines | Should -Be @(
                "machine-health checkup TESTHOST $script:RunId"
                'elevated: no, mode: on-demand'
                'severity: CRIT 1, WARN 3, UNKNOWN 1, INFO 2, OK 1 (delta: WARN +1 (2 cadence-deferred checks not compared))'
                '[CRIT] disk-space: C: at 97% used'
                '[WARN] os-updates: 3 updates pending'
                '[WARN] winget-upgrades: 5 upgrades available'
                'intruder: 2 Defender detections; 1 exposed listeners unsigned or user-writable; exclusions not read (masked)'
                'largest folder: X:\Profile\Videos (5000000000 bytes)'
                "report: $($script:Run.Report)"
                "page: $($script:Run.Page)")
            $script:Out.ExitCode | Should -Be 0
        }

        It 'counts severities from the checks and compares with the prior run, not with its own history line' {
            $line = $script:Out.Lines | Where-Object { $_ -like 'severity:*' }
            $line | Should -Match 'CRIT 1, WARN 3, UNKNOWN 1, INFO 2, OK 1'
            $line | Should -Match 'WARN \+1'
        }

        It 'discloses the cadence-deferred checks latest.json records' {
            $line = $script:Out.Lines | Where-Object { $_ -like 'severity:*' }
            $line | Should -Match '2 cadence-deferred checks not compared'
        }

        It 'lists the worst three: CRIT first, then WARN in check order' {
            $worst = @($script:Out.Lines | Where-Object { $_ -match '^\[(CRIT|WARN)\]' })
            $worst | Should -Be @(
                '[CRIT] disk-space: C: at 97% used'
                '[WARN] os-updates: 3 updates pending'
                '[WARN] winget-upgrades: 5 upgrades available')
        }

        It 'names detections and exposed listeners, and says the masked exclusion list was not read' {
            $line = $script:Out.Lines | Where-Object { $_ -like 'intruder:*' }
            $line | Should -Match '2 Defender detection'
            $line | Should -Match '1 exposed'
            $line | Should -Match 'exclusions not read \(masked\)'
            $line | Should -Not -Match '0 unexpected'
        }

        It 'names the largest unmuted sized folder' {
            $line = $script:Out.Lines | Where-Object { $_ -like 'largest folder:*' }
            $line | Should -Match ([regex]::Escape('X:\Profile\Videos'))
            $line | Should -Not -Match 'Huge'
        }

        It 'prints the report and page paths latest.json records' {
            $script:Out.Lines | Should -Contain "report: $($script:Run.Report)"
            $script:Out.Lines | Should -Contain "page: $($script:Run.Page)"
        }
    }

    Context 'a latest.json that records no report or page path' {
        It 'says the report was not recorded and the page not built' {
            $run = Initialize-RunFolder (Get-SnapshotFixture) -NoArtifacts
            $out = Invoke-ShortReport $run.Latest
            $out.Lines[-2..-1] | Should -Be @('report: not recorded', 'page: not built')
            $out.ExitCode | Should -Be 0
        }
    }

    Context 'recorded paths whose files are gone' {
        It 'says the report was not found and the page not built' {
            $run = Initialize-RunFolder (Get-SnapshotFixture)
            Remove-Item -LiteralPath $run.Report, $run.Page
            $out = Invoke-ShortReport $run.Latest
            $out.Lines[-2..-1] | Should -Be @('report: not found', 'page: not built')
        }
    }

    Context 'a run with no WARN or CRIT and no prior run' {
        It 'says so instead of listing findings' {
            $snap = Get-SnapshotFixture
            $snap.checks = @(Get-CheckFixture -Id 'disk-space' -Category 'storage' -Severity 'OK' -Summary 'fine')
            $snap.cadence_deferred_count = 0
            $run = Initialize-RunFolder $snap
            Remove-Item -LiteralPath (Join-Path $run.Base 'state\history.jsonl')
            $out = Invoke-ShortReport $run.Latest
            $out.Text | Should -Match 'no WARN or CRIT findings'
            $out.Text | Should -Match '\(delta: no prior runs\)'
            $out.Text | Should -Match 'intruder: .*not read'
        }
    }

    Context 'machine strings holding line breaks and control characters' {
        It 'keeps the line count and lets no string forge a second first line' {
            $clean = Invoke-ShortReport (Initialize-RunFolder (Get-SnapshotFixture)).Latest
            $hostile = Get-SnapshotFixture -HostName "EVIL`r`nmachine-health checkup forged" `
                -Summary "full$([char]0x2028)machine-health checkup x`nmore$([char]0x85)tail" `
                -FolderPath "X:\Profile\a`nmachine-health checkup y$([char]0x2029)z$([char]0x1B)[2J"
            $out = Invoke-ShortReport (Initialize-RunFolder $hostile).Latest

            $out.Lines.Count | Should -Be $clean.Lines.Count
            @($out.Lines | Where-Object { $_.StartsWith($script:Marker) }).Count | Should -Be 1
            $out.Lines[0] | Should -BeLike "${script:Marker}EVIL  machine-health checkup forged *"
            foreach ($c in "`r", [char]0x2028, [char]0x2029, [char]0x85, [char]0x1B) {
                $out.Text.Contains([string]$c) | Should -BeFalse
            }
        }
    }

    Context 'no latest.json' {
        It 'prints the fixed first line with this host and no run id, then the reason, and exits non-zero' {
            $missing = Join-Path $TestDrive 'absent\state\latest.json'
            $out = Invoke-ShortReport $missing
            $out.Lines[0] | Should -BeExactly "${script:Marker}$([System.Net.Dns]::GetHostName()) no-run-id"
            $out.Lines.Count | Should -Be 2
            $out.Text | Should -Match 'latest\.json not found'
            $out.ExitCode | Should -Be 1
        }

        It 'treats an unparsable latest.json the same way' {
            $dir = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'bad\state') -Force
            Set-Content -LiteralPath (Join-Path $dir 'latest.json') -Value '{ not json'
            $out = Invoke-ShortReport (Join-Path $dir 'latest.json')
            $out.Lines[0] | Should -BeLike "$script:Marker*"
            $out.Text | Should -Match 'latest\.json unreadable'
            $out.ExitCode | Should -Be 1
        }
    }
}
