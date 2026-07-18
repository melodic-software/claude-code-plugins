#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:LibRoot = Join-Path (Split-Path -Parent $script:TestsRoot) 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Invoke-TrendAnalysis.ps1')
    # New-HealthResult builds a full schema-valid result and dot-sources
    # Assert-CheckResult -- both used by the schema-conformance test below.
    . (Join-Path $script:LibRoot 'Write-HealthResult.ps1')

    function New-HistoryEntry {
        param(
            [hashtable] $SeverityByCategory = @{},
            [hashtable] $TopMetrics = @{},
            [string[]] $ChecksRan = @(),
            [string] $RunId = '2026-04-22T00:00:00-04:00'
        )
        [pscustomobject]@{
            run_id          = $RunId
            severity_counts = [pscustomobject]$SeverityByCategory
            top_metrics     = [pscustomobject]$TopMetrics
            checks_ran      = $ChecksRan
        }
    }

    function New-CheckStub {
        param(
            [string] $Id,
            [string] $Category,
            [string] $Severity,
            [hashtable] $Detail = @{},
            [string] $Notes
        )
        [pscustomobject]@{
            id       = $Id
            category = $Category
            severity = $Severity
            detail   = [pscustomobject]$Detail
            notes    = $Notes
            trend    = $null
        }
    }
}

Describe 'Invoke-TrendAnalysis' -Tag 'lib' {
    It 'returns results unchanged when history is empty' {
        $checks = @(New-CheckStub -Id 'disk-space' -Category 'storage' -Severity 'OK')
        $result = Invoke-TrendAnalysis -CheckResults $checks -HistoryTail @()
        $result[0].severity | Should -Be 'OK'
    }

    It 'attaches trend.last_run from the most recent run in which the check ran' {
        $history = @(
            New-HistoryEntry `
                -SeverityByCategory @{ storage = [pscustomobject]@{ OK = 0; WARN = 1 } } `
                -ChecksRan @('disk-space') `
                -RunId '2026-04-22T00:00:00-04:00'
        )
        $checks = @(New-CheckStub -Id 'disk-space' -Category 'storage' -Severity 'WARN' -Detail @{ used_pct = 88 })
        $result = Invoke-TrendAnalysis -CheckResults $checks -HistoryTail $history
        $result[0].trend.last_run | Should -Be '2026-04-22T00:00:00-04:00'
        # last_severity was removed; the schema forbids it (additionalProperties:false).
        $result[0].trend.PSObject.Properties.Name | Should -Not -Contain 'last_severity'
    }

    It 'leaves trend.last_run null when no history entry recorded this check running' {
        $history = @(
            New-HistoryEntry `
                -SeverityByCategory @{ storage = [pscustomobject]@{ WARN = 1 } } `
                -ChecksRan @('battery')
        )
        $checks = @(New-CheckStub -Id 'disk-space' -Category 'storage' -Severity 'WARN' -Detail @{ used_pct = 88 })
        $result = Invoke-TrendAnalysis -CheckResults $checks -HistoryTail $history
        $result[0].trend.last_run | Should -BeNullOrEmpty
    }

    It 'attaches delta text when metric is in history top_metrics' {
        $history = @(
            New-HistoryEntry `
                -SeverityByCategory @{ storage = [pscustomobject]@{ WARN = 1 } } `
                -TopMetrics @{ 'disk-space.used_pct' = 80 }
        )
        $checks = @(New-CheckStub -Id 'disk-space' -Category 'storage' -Severity 'WARN' -Detail @{ used_pct = 87 })
        $result = Invoke-TrendAnalysis -CheckResults $checks -HistoryTail $history
        $result[0].trend.delta | Should -Match 'used_pct'
        $result[0].trend.delta | Should -Match '\+7'
    }

    It 'upgrades WARN to CRIT when trend-relevant metric worsens by 5+ and records adjusted_from' {
        $history = @(
            New-HistoryEntry `
                -SeverityByCategory @{ storage = [pscustomobject]@{ WARN = 1 } } `
                -TopMetrics @{ 'disk-space.used_pct' = 80 }
        )
        $checks = @(New-CheckStub -Id 'disk-space' -Category 'storage' -Severity 'WARN' -Detail @{ used_pct = 87 })
        $result = Invoke-TrendAnalysis -CheckResults $checks -HistoryTail $history
        $result[0].severity | Should -Be 'CRIT'
        $result[0].notes | Should -Match 'trend upgrade'
        $result[0].trend.adjusted_from | Should -Be 'WARN'
    }

    It 'does not upgrade WARN when delta is <5 and leaves adjusted_from null' {
        $history = @(
            New-HistoryEntry `
                -SeverityByCategory @{ storage = [pscustomobject]@{ WARN = 1 } } `
                -TopMetrics @{ 'disk-space.used_pct' = 85 }
        )
        $checks = @(New-CheckStub -Id 'disk-space' -Category 'storage' -Severity 'WARN' -Detail @{ used_pct = 87 })
        $result = Invoke-TrendAnalysis -CheckResults $checks -HistoryTail $history
        $result[0].severity | Should -Be 'WARN'
        $result[0].trend.adjusted_from | Should -BeNullOrEmpty
    }

    It 'produces a trend object that passes Assert-CheckResult (schema sub-shape)' {
        # Mirror production: the check emits JSON, the orchestrator ingests it
        # (detail becomes a pscustomobject) before trend analysis runs.
        $base = New-HealthResult -Id 'disk-space' -Category 'storage' -Os 'windows' `
            -Severity 'WARN' -Summary 'C: at 87% used' -Detail @{ used_pct = 87 } `
            -Commands @('Get-Volume') -NeedsAdmin $false -RanSuccessfully $true -DurationMs 10 |
            ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $history = @(
            New-HistoryEntry `
                -TopMetrics @{ 'disk-space.used_pct' = 80 } `
                -ChecksRan @('disk-space')
        )
        $result = Invoke-TrendAnalysis -CheckResults @($base) -HistoryTail $history
        { Assert-CheckResult $result[0] } | Should -Not -Throw
        $result[0].trend.last_run | Should -Not -BeNullOrEmpty
        $result[0].trend.adjusted_from | Should -Be 'WARN'
    }

    It 'treats battery downward drop as worsening (fullCapacityPct going down)' {
        $history = @(
            New-HistoryEntry `
                -SeverityByCategory @{ power = [pscustomobject]@{ WARN = 1 } } `
                -TopMetrics @{ 'battery.full_capacity_pct' = 75 }
        )
        $checks = @(New-CheckStub -Id 'battery' -Category 'power' -Severity 'WARN' -Detail @{ full_capacity_pct = 69 })
        $result = Invoke-TrendAnalysis -CheckResults $checks -HistoryTail $history
        $result[0].severity | Should -Be 'CRIT'
    }

    It 'uses the most recent (last) history entry as baseline, not the oldest (regression)' {
        # Read-HistoryJsonl returns Get-Content -Tail output (oldest -> newest).
        # With 2+ entries, the baseline must come from the LAST element, not [0].
        # Here: oldest=20, newest=85; current=87. Correct delta = +2 (no upgrade).
        # If code incorrectly uses [0], delta would be +67 (triggers CRIT upgrade).
        $history = @(
            New-HistoryEntry `
                -SeverityByCategory @{ storage = [pscustomobject]@{ WARN = 1 } } `
                -TopMetrics @{ 'disk-space.used_pct' = 20 } `
                -RunId '2026-04-20T00:00:00-04:00'
            New-HistoryEntry `
                -SeverityByCategory @{ storage = [pscustomobject]@{ WARN = 1 } } `
                -TopMetrics @{ 'disk-space.used_pct' = 85 } `
                -RunId '2026-04-23T00:00:00-04:00'
        )
        $checks = @(New-CheckStub -Id 'disk-space' -Category 'storage' -Severity 'WARN' -Detail @{ used_pct = 87 })
        $result = Invoke-TrendAnalysis -CheckResults $checks -HistoryTail $history
        $result[0].severity | Should -Be 'WARN' -Because 'delta vs newest (+2) is <5; upgrade must NOT fire'
        $result[0].trend.delta | Should -Match '\+2'
    }
}
