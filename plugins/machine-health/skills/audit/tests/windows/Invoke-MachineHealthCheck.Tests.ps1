#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Orchestrator-level tests for scripts/windows/Invoke-MachineHealthCheck.ps1:
the run lock, the synced-StateBase mode and both elevated-pass modes.

.DESCRIPTION
Each run uses a StateBase whose catalog overlay disables every shipped check,
so the real orchestrator runs end to end in seconds. Required snapshot fields
come from reference/shared/output-schema.md, "RunSnapshot".
#>

BeforeAll {
    . "$PSScriptRoot\..\helpers\Initialize-CheckSuite.ps1" -LibScript @(
        'ConvertFrom-Jsonc.ps1', 'Enter-RunLock.ps1', 'Assert-CheckResult.ps1', 'Open-NoFollowFile.ps1') -MockHelpers
    $script:Orchestrator = Join-Path $script:SkillRoot 'scripts\windows\Invoke-MachineHealthCheck.ps1'
    $script:RequiredSnapshotFields = @('run_id', 'hostname', 'os', 'os_version', 'elevated',
        'run_mode', 'checks', 'remediations', 'discovered_checks', 'duration_seconds')
    $script:SavedOneDrive = $env:OneDrive

    $catalog = Get-Content -LiteralPath (Join-Path $script:SkillRoot 'catalog\checks.jsonc') -Raw | ConvertFrom-Jsonc
    $script:QuietOverlay = @{ checks = @($catalog.checks | ForEach-Object { @{ id = $_.id; enabled = $false } }) } |
        ConvertTo-Json -Depth 5

    # A StateBase whose overlay disables every shipped check.
    function Initialize-QuietStateBase {
        param([string] $Path)
        $catalogDir = Join-Path $Path 'catalog'
        New-Item -ItemType Directory -Path $catalogDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $catalogDir 'checks.local.jsonc') -Value $script:QuietOverlay -Encoding utf8
        return $Path
    }

    # Entry names plus each file's size and write time, relative to $Root.
    function Get-TreeListing {
        param([string] $Root)
        if (-not (Test-Path -LiteralPath $Root)) { return @() }
        @(Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName | ForEach-Object {
                $rel = $_.FullName.Substring($Root.Length)
                if ($_.PSIsContainer) { "$rel\" } else { "$rel|$($_.Length)|$($_.LastWriteTimeUtc.ToString('o'))" }
            })
    }

    function Invoke-OrchestratorProcess {
        param([string] $OutputBase, [string] $StateBase, [string[]] $Extra = @('-DryRun'))
        $stdout = & pwsh -NoProfile -NonInteractive -File $script:Orchestrator -OutputBase $OutputBase `
            -StateBase $StateBase -RunMode on-demand -SkipBanner @Extra 2>$null
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Stdout = ($stdout -join "`n") }
    }
}

AfterAll {
    $env:OneDrive = $script:SavedOneDrive
}

Describe 'Invoke-MachineHealthCheck run lock' -Tag 'orchestrator' {
    BeforeEach {
        $script:root = New-MachineHealthTempDir -Prefix 'machine-health-orch'
        $script:stateBase = Initialize-QuietStateBase (Join-Path $script:root 'state-base')
        $script:outputBase = Join-Path $script:root 'output'
        $script:stateDir = Join-Path $script:stateBase 'state'
        New-Item -ItemType Directory -Path $script:stateDir -Force | Out-Null
    }

    AfterEach {
        Remove-MachineHealthTempDir -Path $script:root
    }

    It 'reports one run-lock UNKNOWN in a complete snapshot and writes nothing while run.lock is held' {
        $held = Enter-RunLock -StateDir $script:stateDir -Name 'run'
        try {
            $before = Get-TreeListing $script:stateBase
            $run = Invoke-OrchestratorProcess -OutputBase $script:outputBase -StateBase $script:stateBase
            $after = Get-TreeListing $script:stateBase
        } finally {
            $held.Dispose()
        }

        $run.ExitCode | Should -Be 0
        $snapshot = $run.Stdout | ConvertFrom-Json
        foreach ($field in $script:RequiredSnapshotFields) {
            $snapshot.PSObject.Properties.Name | Should -Contain $field
        }
        @($snapshot.checks).Count | Should -Be 1
        $snapshot.checks[0].id | Should -Be 'run-lock'
        $snapshot.checks[0].severity | Should -Be 'UNKNOWN'
        $snapshot.checks[0].summary | Should -BeLike '*run.lock*'
        { Assert-CheckResult $snapshot.checks[0] -Because 'run-lock result' } | Should -Not -Throw
        @($snapshot.remediations).Count | Should -Be 0
        $snapshot.duration_seconds | Should -Be 0
        Compare-Object $before $after | Should -BeNullOrEmpty
        @(Get-ChildItem -LiteralPath $script:outputBase -Recurse -File -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'releases run.lock when the run throws after taking it' {
        # A copy of the skill whose check selection throws, run in this process so only
        # the orchestrator's own finally can release the handle.
        $copy = Join-Path $script:root 'skill'
        New-Item -ItemType Directory -Path $copy | Out-Null
        foreach ($part in @('SKILL.md', 'catalog', 'reference', 'scripts')) {
            Copy-Item -LiteralPath (Join-Path $script:SkillRoot $part) -Destination $copy -Recurse
        }
        Set-Content -LiteralPath (Join-Path $copy 'scripts\windows\lib\Get-CheckSelection.ps1') -Encoding utf8 `
            -Value "function Get-CheckSelection { throw 'injected failure after the lock' }"
        $defaults = $PSDefaultParameterValues.Clone()
        $thrown = $null
        try {
            & (Join-Path $copy 'scripts\windows\Invoke-MachineHealthCheck.ps1') -OutputBase $script:outputBase `
                -StateBase $script:stateBase -RunMode on-demand -DryRun -SkipBanner 2>$null | Out-Null
        } catch {
            $thrown = $_.Exception.Message
        } finally {
            $PSDefaultParameterValues.Clear()
            foreach ($k in $defaults.Keys) { $PSDefaultParameterValues[$k] = $defaults[$k] }
        }

        $thrown | Should -BeLike '*injected failure after the lock*'
        $again = Enter-RunLock -StateDir $script:stateDir -Name 'run'
        try { $again | Should -Not -BeNullOrEmpty } finally { if ($again) { $again.Dispose() } }
    }
}

Describe 'Invoke-MachineHealthCheck with a synced StateBase' -Tag 'orchestrator' {
    BeforeEach {
        $script:root = New-MachineHealthTempDir -Prefix 'machine-health-orch-sync'
        $script:sync = Join-Path $script:root 'synced'
        $script:stateBase = Initialize-QuietStateBase (Join-Path $script:sync 'mh-state')
        Set-Content -LiteralPath (Join-Path $script:stateBase 'TODO.md') -Value '- [x] Enable Clear-TempFiles' -Encoding utf8
        $env:OneDrive = $script:sync
    }

    AfterEach {
        $env:OneDrive = $script:SavedOneDrive
        Remove-MachineHealthTempDir -Path $script:root
    }

    It 'runs, reports one state-location UNKNOWN, and leaves the synced folder untouched' {
        $outputBase = Join-Path $script:root 'output'
        $before = Get-TreeListing $script:sync

        $run = Invoke-OrchestratorProcess -OutputBase $outputBase -StateBase $script:stateBase

        $run.ExitCode | Should -Be 0
        Compare-Object $before (Get-TreeListing $script:sync) | Should -BeNullOrEmpty
        $snapshot = $run.Stdout | ConvertFrom-Json
        @($snapshot.checks | Where-Object id -EQ 'state-location').Count | Should -Be 1
        $reports = @(Get-ChildItem -LiteralPath (Join-Path $outputBase 'reports') -Filter 'health-*.md')
        $reports.Count | Should -Be 1
        @(Select-String -LiteralPath $reports[0].FullName -Pattern '\| state-location \| \*\*UNKNOWN\*\*').Count | Should -Be 1
    }

    It 'leaves no log default behind, so a writable run after a synced one in the same session writes its run log' {
        $writableBase = Initialize-QuietStateBase (Join-Path $script:root 'writable')
        $defaults = $PSDefaultParameterValues.Clone()
        try {
            & $script:Orchestrator -OutputBase (Join-Path $script:root 'out-1') -StateBase $script:stateBase `
                -RunMode on-demand -DryRun -SkipBanner 2>$null | Out-Null
            $PSDefaultParameterValues.Keys | Should -Not -Contain 'Write-MachineHealthLog:ToStderr'

            & $script:Orchestrator -OutputBase (Join-Path $script:root 'out-2') -StateBase $writableBase `
                -RunMode on-demand -DryRun -SkipBanner 2>$null | Out-Null
        } finally {
            $PSDefaultParameterValues.Clear()
            foreach ($k in $defaults.Keys) { $PSDefaultParameterValues[$k] = $defaults[$k] }
        }

        $logs = @(Get-ChildItem -LiteralPath (Join-Path $writableBase 'logs') -Filter 'run-*.log')
        $logs.Count | Should -Be 1
        Get-Content -LiteralPath $logs[0].FullName -Raw | Should -Match 'run_start .*state_writable=True'
    }

    It 'writes only the report when the output folder is inside the synced StateBase' {
        $outputBase = Join-Path $script:stateBase 'out'
        $before = Get-TreeListing $script:sync

        $run = Invoke-OrchestratorProcess -OutputBase $outputBase -StateBase $script:stateBase

        $run.ExitCode | Should -Be 0
        $added = @(Compare-Object $before (Get-TreeListing $script:sync) |
                ForEach-Object { if ($_.SideIndicator -eq '=>') { $_.InputObject } else { "removed: $($_.InputObject)" } })
        $added.Count | Should -Be 3
        $added | Should -Contain '\mh-state\out\'
        $added | Should -Contain '\mh-state\out\reports\'
        @($added | Where-Object { $_ -like '\mh-state\out\reports\health-*.md|*' }).Count | Should -Be 1
    }
}

Describe 'Invoke-MachineHealthCheck -ElevatedResultPath' -Tag 'orchestrator' {
    BeforeEach {
        $script:root = New-MachineHealthTempDir -Prefix 'machine-health-orch-import'
        $script:stateBase = Initialize-QuietStateBase (Join-Path $script:root 'state-base')
        $script:outputBase = Join-Path $script:root 'output'
    }

    AfterEach {
        Remove-MachineHealthTempDir -Path $script:root
    }

    It 'imports a matrix result the quiet run did not dispatch, lists it in elevated_checks and logs the import' {
        # Pre-created before the document is written, as New-ElevatedLaunch leaves it.
        $resultPath = Join-Path $script:root 'elevated-result.json'
        [System.IO.File]::Create($resultPath).Dispose()
        $created = [System.IO.File]::GetCreationTimeUtc($resultPath)
        $document = [ordered]@{
            format   = 'elevated-result/1'
            ran_at   = $created.AddSeconds(5).ToString('o')
            elevated = $true
            user_sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
            results  = @([ordered]@{
                    id = 'tpm-bitlocker'; category = 'security'; os = 'windows'; ran_at = $created.AddSeconds(4).ToString('o')
                    severity = 'OK'; summary = 'elevated tpm reading'; detail = @{}; commands = @(); needs_admin = $true
                    ran_successfully = $true; duration_ms = 5; trend = $null; notes = $null; error = $null
                })
            log      = @('check_ok id=tpm-bitlocker')
        }
        [System.IO.File]::WriteAllText($resultPath, ($document | ConvertTo-Json -Depth 10))

        $run = Invoke-OrchestratorProcess -OutputBase $script:outputBase -StateBase $script:stateBase `
            -Extra @('-DryRun', '-ElevatedResultPath', $resultPath)

        $run.ExitCode | Should -Be 0
        $latest = Get-Content -LiteralPath (Join-Path $script:stateBase 'state\latest.json') -Raw | ConvertFrom-Json
        @($latest.elevated_checks) | Should -Be @('tpm-bitlocker')
        ($latest.checks | Where-Object id -EQ 'tpm-bitlocker').summary | Should -BeExactly 'elevated tpm reading'
        $log = Get-Content -LiteralPath (Get-ChildItem -LiteralPath (Join-Path $script:stateBase 'logs') -Filter 'run-*.log')[0].FullName -Raw
        $log | Should -Match ([regex]::Escape("elevated_result path=$resultPath imported checks=tpm-bitlocker"))
        $log | Should -Match 'elevated: check_ok id=tpm-bitlocker'
    }
}

Describe 'Invoke-MachineHealthCheck -ResultPath' -Tag 'orchestrator' {
    BeforeEach {
        $script:root = New-MachineHealthTempDir -Prefix 'machine-health-orch-pass'
        $script:stateBase = Join-Path $script:root 'state-base'
        $script:marker = Join-Path $script:root 'stub-ran.txt'
        $stubDir = Join-Path $script:stateBase 'scripts\windows\checks'
        New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $stubDir 'Test-Stub.ps1') -Encoding utf8 `
            -Value "Set-Content -LiteralPath '$($script:marker)' -Value 'ran'"
        # Every check off except disk-space, whose script the overlay points at the stub.
        $overlay = $script:QuietOverlay | ConvertFrom-Json
        $disk = $overlay.checks | Where-Object id -EQ 'disk-space'
        $disk.enabled = $true
        $disk | Add-Member -NotePropertyName script -NotePropertyValue 'scripts/windows/checks/Test-Stub.ps1'
        New-Item -ItemType Directory -Path (Join-Path $script:stateBase 'catalog') | Out-Null
        Set-Content -LiteralPath (Join-Path $script:stateBase 'catalog\checks.local.jsonc') -Encoding utf8 `
            -Value ($overlay | ConvertTo-Json -Depth 5)
    }

    AfterEach {
        Remove-MachineHealthTempDir -Path $script:root
    }

    It 'runs the shipped script for a matrix check and never the script the overlay names' {
        $resultPath = Join-Path $script:root 'elevated-result.json'
        $created = [System.IO.File]::Open($resultPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None)
        try { $fileId = (Get-FileIdentity -Handle $created.SafeFileHandle).FileId } finally { $created.Dispose() }

        & pwsh -NoProfile -NonInteractive -File $script:Orchestrator -OutputBase (Join-Path $script:root 'output') `
            -StateBase $script:stateBase -RunMode on-demand -SkipBanner -ResultPath $resultPath -ResultFileId $fileId 2>$null |
            Out-Null

        $LASTEXITCODE | Should -Be 0
        Test-Path -LiteralPath $script:marker | Should -BeFalse
        $document = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        @($document.results.id) | Should -Be @('disk-space')
        $document.results[0].summary | Should -Not -BeLike 'Script not found*'
    }
}

Describe 'Invoke-MachineHealthCheck run artifacts in latest.json' -Tag 'orchestrator' {
    BeforeAll {
        $script:root = New-MachineHealthTempDir -Prefix 'machine-health-orch-stamp'
        $script:stateBase = Initialize-QuietStateBase (Join-Path $script:root 'state-base')
        $script:outputBase = Join-Path $script:root 'output'
        # Two checks re-enabled at monthly cadence that ran three days ago: a weekly run defers both.
        $deferred = @($script:QuietOverlay | ConvertFrom-Json).checks | Select-Object -First 2
        $overlay = $script:QuietOverlay | ConvertFrom-Json
        foreach ($c in $overlay.checks | Where-Object { $_.id -in $deferred.id }) {
            $c.enabled = $true
            $c | Add-Member -NotePropertyName cadence -NotePropertyValue 'monthly'
        }
        $overlay | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $script:stateBase 'catalog\checks.local.jsonc') -Encoding utf8
        $stateDir = New-Item -ItemType Directory -Path (Join-Path $script:stateBase 'state') -Force
        @{ run_id = (Get-Date).AddDays(-3).ToString('o'); checks_ran = @($deferred.id) } | ConvertTo-Json -Compress |
            Set-Content -LiteralPath (Join-Path $stateDir 'history.jsonl') -Encoding utf8
        # th-TH formats dates in the Buddhist calendar (Gregorian 2026 is 2569), so a culture-bound
        # stamp would name this run's files by the wrong year.
        $command = "[cultureinfo]::CurrentCulture = 'th-TH'; & '$script:Orchestrator' -OutputBase '$script:outputBase' " +
            "-StateBase '$script:stateBase' -RunMode weekly -DryRun -SkipBanner | Out-Null"
        & pwsh -NoProfile -NonInteractive -Command $command 2>$null
        $script:ExitCode = $LASTEXITCODE
        # JsonNode keeps run_id as written; ConvertFrom-Json would turn it into a DateTime.
        $script:Snapshot = [System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -Raw -LiteralPath (Join-Path $stateDir 'latest.json')))
        $script:Field = { param($Name) $script:Snapshot[$Name].GetValue[object]().ToString() }
    }

    AfterAll {
        Remove-MachineHealthTempDir -Path $script:root
    }

    It 'stamps the run in the Gregorian calendar whatever the current culture' {
        $script:ExitCode | Should -Be 0
        $stamp = & $script:Field 'run_stamp'
        $stamp | Should -Match '^\d{4}-\d{2}-\d{2}T\d{9}Z$'
        $gregorianYear = [DateTimeOffset]::Parse((& $script:Field 'run_id'), [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.Year
        [int]$stamp.Substring(0, 4) | Should -Be $gregorianYear
    }

    It 'records the path of the one report this run wrote' {
        $reports = @(Get-ChildItem -LiteralPath (Join-Path $script:outputBase 'reports') -File)
        $reports.Count | Should -Be 1
        & $script:Field 'report_path' | Should -BeExactly $reports[0].FullName
    }

    It 'records the decision page path under the state root views folder, named by the run stamp' {
        & $script:Field 'page_path' | Should -BeExactly (Join-Path $script:stateBase "views\checkup-$(& $script:Field 'run_stamp').html")
    }

    It 'records how many checks cadence deferred' {
        $script:Snapshot['cadence_deferred_count'].GetValue[int]() | Should -Be 2
    }

    It 'carries no scheduled-run field and its report names no research notes file without -Scheduled' {
        $script:Snapshot.AsObject().ContainsKey('new_finding_keys') | Should -BeFalse
        $script:Snapshot.AsObject().ContainsKey('discovery_path') | Should -BeFalse
        Get-ChildItem -LiteralPath (Join-Path $script:outputBase 'reports') -File | Get-Content -Raw | Should -Not -Match 'discovery-'
    }
}

Describe 'Invoke-MachineHealthCheck -Scheduled' -Tag 'orchestrator' {
    BeforeAll {
        $script:root = New-MachineHealthTempDir -Prefix 'machine-health-orch-scheduled'
        $script:stateBase = Initialize-QuietStateBase (Join-Path $script:root 'state-base')
        $script:outputBase = Join-Path $script:root 'output'
        $run = Invoke-OrchestratorProcess -OutputBase $script:outputBase -StateBase $script:stateBase -Extra @('-DryRun', '-Scheduled')
        $script:ExitCode = $run.ExitCode
        $script:Snapshot = [System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -Raw -LiteralPath (Join-Path $script:stateBase 'state\latest.json')))
    }

    AfterAll {
        Remove-MachineHealthTempDir -Path $script:root
    }

    It 'writes an empty new_finding_keys array on a run with no previous latest.json' {
        $script:ExitCode | Should -Be 0
        $script:Snapshot['new_finding_keys'].ToJsonString() | Should -Be '[]'
    }

    It 'names the research notes file beside the report, by the run stamp, in latest.json and the report' {
        $stamp = $script:Snapshot['run_stamp'].GetValue[string]()
        $expected = Join-Path $script:outputBase "reports\discovery-$stamp.md"
        $script:Snapshot['discovery_path'].GetValue[string]() | Should -BeExactly $expected
        $report = Get-Content -Raw -LiteralPath ($script:Snapshot['report_path'].GetValue[string]())
        $report | Should -Match ([regex]::Escape("``$expected``"))
        $report.IndexOf('## Newly discovered checks') | Should -BeLessThan $report.IndexOf("discovery-$stamp.md")
    }
}

Describe 'Invoke-MachineHealthCheck with a checked TODO.md and no approvals.json' -Tag 'orchestrator' {
    BeforeAll {
        $script:root = New-MachineHealthTempDir -Prefix 'machine-health-orch-todo'
        $script:stateBase = Initialize-QuietStateBase (Join-Path $script:root 'state-base')
        Set-Content -LiteralPath (Join-Path $script:stateBase 'TODO.md') -Encoding utf8 `
            -Value "- [x] restart-stopped-service`n- [x] Enable Clear-TempFiles"
        $script:Run = Invoke-OrchestratorProcess -OutputBase (Join-Path $script:root 'output') -StateBase $script:stateBase
    }

    AfterAll {
        Remove-MachineHealthTempDir -Path $script:root
    }

    It 'approves nothing: TODO.md text never becomes an approval' {
        $script:Run.ExitCode | Should -Be 0
        Join-Path $script:stateBase 'state\approvals.json' | Should -Not -Exist
        Get-Content -Raw -LiteralPath (Get-ChildItem -LiteralPath (Join-Path $script:stateBase 'logs') -Filter 'run-*.log')[0].FullName |
            Should -Not -Match 'approvals_migrated'
    }
}

Describe 'Invoke-MachineHealthCheck without -OutputBase' -Tag 'orchestrator' {
    BeforeAll {
        $script:root = New-MachineHealthTempDir -Prefix 'machine-health-orch-default'
        $script:stateBase = Initialize-QuietStateBase (Join-Path $script:root 'state-base')
        $script:profile = Join-Path $script:root 'profile'
        # A scheduled run omits -OutputBase when the report option is unset; the default must be
        # the one the audit SKILL.md roots block applies.
        $roots = (Get-Content -LiteralPath (Join-Path $script:SkillRoot 'SKILL.md') -Raw) -match "Join-Path \`$env:USERPROFILE '([^']+)'"
        $roots | Should -BeTrue
        $script:Expected = Join-Path $script:profile $Matches[1]
        $command = "`$env:USERPROFILE = '$script:profile'; & '$script:Orchestrator' -StateBase '$script:stateBase' " +
            '-RunMode on-demand -DryRun -SkipBanner | Out-Null'
        & pwsh -NoProfile -NonInteractive -Command $command 2>$null
        $script:ExitCode = $LASTEXITCODE
    }

    AfterAll {
        Remove-MachineHealthTempDir -Path $script:root
    }

    It 'writes the report under the roots block default' {
        $script:ExitCode | Should -Be 0
        @(Get-ChildItem -LiteralPath (Join-Path $script:Expected 'reports') -File).Count | Should -Be 1
    }
}
