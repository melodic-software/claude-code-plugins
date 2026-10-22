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
    # The run stamp the orchestrator derives from that run id (UTC, yyyy-MM-ddTHHmmssfffZ).
    $script:Stamp = '2026-10-01T130000000Z'

    function New-Check([string] $Id, [string] $Category, [string] $Severity, [string] $Summary, [hashtable] $Detail = @{}) {
        [ordered]@{ id = $Id; category = $Category; os = 'windows'; severity = $Severity; summary = $Summary
            detail = $Detail; needs_admin = $false; ran_successfully = $true }
    }

    function New-Folder([string] $Path, $Bytes, [bool] $Muted) {
        [ordered]@{ key = 'folder:0123456789abcdef'; severity = 'INFO'; muted = $Muted
            title = ($null -eq $Bytes ? "$Path (skipped: cloud sync root)" : "$Path ($Bytes bytes)")
            path = $Path; logical_bytes = $Bytes }
    }

    # A full run: one CRIT, three WARN (only the first two by catalog order fit the worst three
    # after the CRIT), the three intruder checks, and a storage list whose largest folder is muted.
    function New-Snapshot([string] $HostName = 'TESTHOST', [string] $Summary = 'C: at 97% used', [string] $FolderPath = 'X:\Profile\Videos') {
        [ordered]@{
            run_id = $script:RunId; hostname = $HostName; os = 'windows'; os_version = '10.0'
            elevated = $false; run_mode = 'on-demand'; dry_run = $false
            checks = @(
                New-Check 'disk-space' 'storage' 'CRIT' $Summary
                New-Check 'os-updates' 'updates' 'WARN' '3 updates pending'
                New-Check 'winget-upgrades' 'updates' 'WARN' '5 upgrades available'
                New-Check 'services' 'services' 'WARN' '1 automatic service stopped'
                New-Check 'defender' 'security' 'OK' 'Defender healthy.' @{ recent_threat_count = 2; events_read_state = 'ok' }
                New-Check 'network-listeners' 'security' 'INFO' 'listeners' @{ exposed_unsigned_count = 1; read_state = 'ok' }
                New-Check 'defender-exclusions' 'security' 'UNKNOWN' 'needs admin' @{ list_state = 'masked' }
                New-Check 'storage-top-n' 'storage' 'INFO' 'top folders' @{ items = @(
                        New-Folder 'X:\Profile\Huge' 9000000000 $true
                        New-Folder $FolderPath 5000000000 $false
                        New-Folder 'X:\Profile\OneDrive' $null $false
                    ) }
            )
            remediations = @(); discovered_checks = @(); duration_seconds = 42
        }
    }

    # Writes the snapshot, a history whose prior run had WARN 2 (this run's own line, appended
    # after latest.json, has WARN 3), the report and the page. Returns the two bases.
    function New-RunFolder($Snapshot) {
        $base = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $state = New-Item -ItemType Directory -Path (Join-Path $base 'state')
        New-Item -ItemType Directory -Path (Join-Path $base 'views'), (Join-Path $base 'reports') | Out-Null
        $Snapshot | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $state 'latest.json') -Encoding utf8
        $prior = @{ run_id = '2026-09-01T09:00:00.0000000-04:00'
            severity_counts = @{ storage = @{ CRIT = 1; INFO = 1 }; updates = @{ WARN = 2 }; security = @{ OK = 1; INFO = 1; UNKNOWN = 1 } } }
        $self = @{ run_id = $script:RunId
            severity_counts = @{ storage = @{ CRIT = 1; INFO = 1 }; updates = @{ WARN = 2 }; services = @{ WARN = 1 }; security = @{ OK = 1; INFO = 1; UNKNOWN = 1 } } }
        Set-Content -LiteralPath (Join-Path $state 'history.jsonl') -Encoding utf8 -Value @(
            ($prior | ConvertTo-Json -Depth 5 -Compress), ($self | ConvertTo-Json -Depth 5 -Compress))
        Set-Content -LiteralPath (Join-Path $base "reports\health-$script:Stamp.md") -Value 'report'
        Set-Content -LiteralPath (Join-Path $base "views\checkup-$script:Stamp.html") -Value 'page'
        [pscustomobject]@{ Base = $base; Latest = Join-Path $state 'latest.json' }
    }

    function Invoke-ShortReport([string] $LatestPath, [string] $OutputBase) {
        $output = if ($OutputBase) { & $script:ScriptPath -LatestPath $LatestPath -OutputBase $OutputBase }
        else { & $script:ScriptPath -LatestPath $LatestPath }
        $text = @($output) -join "`n"
        [pscustomobject]@{ Text = $text; Lines = @($text -split "`n"); ExitCode = $LASTEXITCODE }
    }
}

Describe 'Format-ShortReport' -Tag 'lib' {
    Context 'a full run' {
        BeforeAll {
            $script:Run = New-RunFolder (New-Snapshot)
            $script:Out = Invoke-ShortReport $script:Run.Latest $script:Run.Base
        }

        It 'prints at most 12 lines, the first one fixed' {
            $script:Out.Lines.Count | Should -BeLessOrEqual 12
            $script:Out.Lines[0] | Should -BeExactly "machine-health checkup TESTHOST $script:RunId"
            $script:Out.ExitCode | Should -Be 0
        }

        It 'counts severities from the checks and compares with the prior run, not with its own history line' {
            $line = $script:Out.Lines | Where-Object { $_ -like 'severity:*' }
            $line | Should -Match 'CRIT 1, WARN 3, UNKNOWN 1, INFO 2, OK 1'
            $line | Should -Match 'WARN \+1'
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

        It 'prints the report and page paths of this run' {
            $script:Out.Text | Should -Match ([regex]::Escape("health-$script:Stamp.md"))
            $script:Out.Text | Should -Match ([regex]::Escape("checkup-$script:Stamp.html"))
        }
    }

    Context 'a run with no WARN or CRIT and no prior run' {
        It 'says so instead of listing findings' {
            $snap = New-Snapshot
            $snap.checks = @(New-Check 'disk-space' 'storage' 'OK' 'fine')
            $run = New-RunFolder $snap
            Remove-Item -LiteralPath (Join-Path $run.Base 'state\history.jsonl')
            $out = Invoke-ShortReport $run.Latest $run.Base
            $out.Text | Should -Match 'no WARN or CRIT findings'
            $out.Text | Should -Match 'no prior runs'
            $out.Text | Should -Match 'intruder: .*not read'
        }
    }

    Context 'machine strings holding line breaks and control characters' {
        It 'keeps the line count and lets no string forge a second first line' {
            $clean = Invoke-ShortReport (New-RunFolder (New-Snapshot)).Latest
            $hostile = New-Snapshot -HostName "EVIL`r`nmachine-health checkup forged" `
                -Summary "full$([char]0x2028)machine-health checkup x`nmore$([char]0x85)tail" `
                -FolderPath "X:\Profile\a`nmachine-health checkup y$([char]0x2029)z$([char]0x1B)[2J"
            $out = Invoke-ShortReport (New-RunFolder $hostile).Latest

            $out.Lines.Count | Should -Be $clean.Lines.Count
            @($out.Lines | Where-Object { $_.StartsWith($script:Marker) }).Count | Should -Be 1
            $out.Lines[0] | Should -BeLike "${script:Marker}EVIL  machine-health checkup forged *"
            foreach ($c in "`r", [char]0x2028, [char]0x2029, [char]0x85, [char]0x1B) {
                $out.Text.Contains([string]$c) | Should -BeFalse
            }
        }
    }

    Context 'no latest.json' {
        It 'prints the fixed first line and the reason, and exits non-zero' {
            $missing = Join-Path $TestDrive 'absent\state\latest.json'
            $out = Invoke-ShortReport $missing
            $out.Lines[0] | Should -BeLike "$script:Marker*"
            $out.Lines.Count | Should -BeLessOrEqual 12
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
