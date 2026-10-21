#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Orchestrator-level tests for scripts/windows/Invoke-MachineHealthCheck.ps1:
the run lock and the synced-StateBase mode.

.DESCRIPTION
Each run uses a StateBase whose catalog overlay disables every shipped check,
so the real orchestrator runs end to end in seconds. Required snapshot fields
come from reference/shared/output-schema.md, "RunSnapshot".
#>

BeforeAll {
    . "$PSScriptRoot\..\helpers\Initialize-CheckSuite.ps1" -LibScript @(
        'ConvertFrom-Jsonc.ps1', 'Enter-RunLock.ps1', 'Assert-CheckResult.ps1') -MockHelpers
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
        param([string] $OutputBase, [string] $StateBase)
        $stdout = & pwsh -NoProfile -NonInteractive -File $script:Orchestrator -OutputBase $OutputBase `
            -StateBase $StateBase -RunMode on-demand -DryRun -SkipBanner 2>$null
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
