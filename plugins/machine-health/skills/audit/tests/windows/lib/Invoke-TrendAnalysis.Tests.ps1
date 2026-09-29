#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    # New-HealthResult builds a full schema-valid result and dot-sources
    # Assert-CheckResult -- both used by the schema-conformance test below.
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" `
        -LibScript 'Invoke-TrendAnalysis.ps1', 'Write-HealthResult.ps1'

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
            [hashtable] $Detail = @{}
        )
        [pscustomobject]@{
            id       = $Id
            category = $Category
            severity = $Severity
            detail   = [pscustomobject]$Detail
            notes    = ''
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
        # The schema forbids last_severity (additionalProperties:false).
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
                -TopMetrics @{ 'disk-space.used_pct' = 80 } `
                -ChecksRan @('disk-space')
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
                -TopMetrics @{ 'disk-space.used_pct' = 80 } `
                -ChecksRan @('disk-space')
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
                -TopMetrics @{ 'disk-space.used_pct' = 85 } `
                -ChecksRan @('disk-space')
        )
        $checks = @(New-CheckStub -Id 'disk-space' -Category 'storage' -Severity 'WARN' -Detail @{ used_pct = 87 })
        $result = Invoke-TrendAnalysis -CheckResults $checks -HistoryTail $history
        $result[0].severity | Should -Be 'WARN'
        $result[0].trend.adjusted_from | Should -BeNullOrEmpty
    }

    It 'ignores metrics from runs in which the check did not succeed' {
        # A failed or partial run's top_metrics is a lower bound absent from checks_ran; a
        # baseline on it (the newest entry here) would upgrade a WARN to CRIT on nothing.
        $history = @(
            New-HistoryEntry `
                -TopMetrics @{ 'claude-temp-root.total_gb' = 7.9 } `
                -ChecksRan @('claude-temp-root') `
                -RunId '2026-04-20T00:00:00-04:00'
            New-HistoryEntry `
                -TopMetrics @{ 'claude-temp-root.total_gb' = 1.2 } `
                -ChecksRan @() `
                -RunId '2026-04-23T00:00:00-04:00'
        )
        $checks = @(New-CheckStub -Id 'claude-temp-root' -Category 'storage' `
                -Severity 'WARN' -Detail @{ total_gb = 8.1 })
        $result = Invoke-TrendAnalysis -CheckResults $checks -HistoryTail $history
        $result[0].severity | Should -Be 'WARN' `
            -Because 'the only usable baseline is 7.9 (delta +0.2), not the partial 1.2'
        $result[0].trend.last_run | Should -Be '2026-04-20T00:00:00-04:00'
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

    It 'maps environment-health to user_path_length without a generic upward upgrade' {
        Get-TrendRelevantKey -CheckId 'environment-health' | Should -Be 'user_path_length'
        Test-WorseningTrend -CheckId 'environment-health' -CurrentValue 420 -PriorValue 400 |
            Should -BeFalse -Because 'composite WARN causes must not escalate on PATH growth'

        $history = @(
            New-HistoryEntry `
                -SeverityByCategory @{ config = [pscustomobject]@{ WARN = 1 } } `
                -TopMetrics @{ 'environment-health.user_path_length' = 400 } `
                -ChecksRan @('environment-health')
        )
        $checks = @(New-CheckStub -Id 'environment-health' -Category 'config' `
                -Severity 'WARN' -Detail @{ user_path_length = 420 })
        $result = Invoke-TrendAnalysis -CheckResults $checks -HistoryTail $history
        $result[0].trend.delta | Should -Match 'user_path_length'
        $result[0].trend.delta | Should -Match '\+20'
        $result[0].severity | Should -Be 'WARN'
        $result[0].trend.adjusted_from | Should -BeNullOrEmpty
    }

    It 'maps drive-root-litter to residue_count without a generic upward upgrade' {
        Get-TrendRelevantKey -CheckId 'drive-root-litter' | Should -Be 'residue_count'
        Test-WorseningTrend -CheckId 'drive-root-litter' -CurrentValue 15 -PriorValue 10 |
            Should -BeFalse -Because 'root litter is tidiness; its rubric caps at WARN'

        $history = @(
            New-HistoryEntry `
                -SeverityByCategory @{ storage = [pscustomobject]@{ WARN = 1 } } `
                -TopMetrics @{ 'drive-root-litter.residue_count' = 10 } `
                -ChecksRan @('drive-root-litter')
        )
        $checks = @(New-CheckStub -Id 'drive-root-litter' -Category 'storage' `
                -Severity 'WARN' -Detail @{ residue_count = 15 })
        $result = Invoke-TrendAnalysis -CheckResults $checks -HistoryTail $history
        $result[0].trend.delta | Should -Match 'residue_count'
        $result[0].severity | Should -Be 'WARN'
        $result[0].trend.adjusted_from | Should -BeNullOrEmpty
    }

    It 'does not raise a winget-upgrades KEV name-match WARN to CRIT on a count trend' {
        $history = @(
            New-HistoryEntry `
                -SeverityByCategory @{ software = [pscustomobject]@{ WARN = 1 } } `
                -TopMetrics @{ 'winget-upgrades.upgrades_count' = 12 } `
                -ChecksRan @('winget-upgrades')
        )
        $checks = @(New-CheckStub -Id 'winget-upgrades' -Category 'software' -Severity 'WARN' `
                -Detail @{ upgrades_count = 17; kev_match_count = 1 })
        $result = Invoke-TrendAnalysis -CheckResults $checks -HistoryTail $history
        $result[0].severity | Should -Be 'WARN'
        $result[0].trend.adjusted_from | Should -BeNullOrEmpty
        $result[0].trend.delta | Should -Be 'upgrades_count: +5 vs prior'
    }

    It 'still raises a winget-upgrades WARN with no KEV match to CRIT on a count trend' {
        $history = @(
            New-HistoryEntry `
                -SeverityByCategory @{ software = [pscustomobject]@{ WARN = 1 } } `
                -TopMetrics @{ 'winget-upgrades.upgrades_count' = 12 } `
                -ChecksRan @('winget-upgrades')
        )
        $checks = @(New-CheckStub -Id 'winget-upgrades' -Category 'software' -Severity 'WARN' `
                -Detail @{ upgrades_count = 17; kev_match_count = 0 })
        $result = Invoke-TrendAnalysis -CheckResults $checks -HistoryTail $history
        $result[0].severity | Should -Be 'CRIT'
        $result[0].trend.adjusted_from | Should -Be 'WARN'
    }

    It 'keeps the KEV name-match WARN after a JSON round trip of the result' {
        $history = @(
            New-HistoryEntry `
                -SeverityByCategory @{ software = [pscustomobject]@{ WARN = 1 } } `
                -TopMetrics @{ 'winget-upgrades.upgrades_count' = 12 } `
                -ChecksRan @('winget-upgrades')
        )
        $checks = @(New-CheckStub -Id 'winget-upgrades' -Category 'software' -Severity 'WARN' `
                -Detail @{ upgrades_count = 17; kev_match_count = 1 })
        $roundTripped = @($checks | ConvertTo-Json -Depth 6 -AsArray | ConvertFrom-Json)
        $result = Invoke-TrendAnalysis -CheckResults $roundTripped -HistoryTail $history
        $result[0].severity | Should -Be 'WARN'
        $result[0].trend.adjusted_from | Should -BeNullOrEmpty
        $result[0].trend.delta | Should -Be 'upgrades_count: +5 vs prior'
    }

    It 'treats battery downward drop as worsening (fullCapacityPct going down)' {
        $history = @(
            New-HistoryEntry `
                -SeverityByCategory @{ power = [pscustomobject]@{ WARN = 1 } } `
                -TopMetrics @{ 'battery.full_capacity_pct' = 75 } `
                -ChecksRan @('battery')
        )
        $checks = @(New-CheckStub -Id 'battery' -Category 'power' -Severity 'WARN' -Detail @{ full_capacity_pct = 69 })
        $result = Invoke-TrendAnalysis -CheckResults $checks -HistoryTail $history
        $result[0].severity | Should -Be 'CRIT'
    }

    It 'uses the most recent (last) history entry as baseline, not the oldest (regression)' {
        # The baseline must be the LAST (newest) entry: oldest=20, newest=85, current=87 gives
        # +2 (no upgrade); using [0] would give +67 and a CRIT upgrade.
        $history = @(
            New-HistoryEntry `
                -SeverityByCategory @{ storage = [pscustomobject]@{ WARN = 1 } } `
                -TopMetrics @{ 'disk-space.used_pct' = 20 } `
                -ChecksRan @('disk-space') `
                -RunId '2026-04-20T00:00:00-04:00'
            New-HistoryEntry `
                -SeverityByCategory @{ storage = [pscustomobject]@{ WARN = 1 } } `
                -TopMetrics @{ 'disk-space.used_pct' = 85 } `
                -ChecksRan @('disk-space') `
                -RunId '2026-04-23T00:00:00-04:00'
        )
        $checks = @(New-CheckStub -Id 'disk-space' -Category 'storage' -Severity 'WARN' -Detail @{ used_pct = 87 })
        $result = Invoke-TrendAnalysis -CheckResults $checks -HistoryTail $history
        $result[0].severity | Should -Be 'WARN' -Because 'delta vs newest (+2) is <5; upgrade must NOT fire'
        $result[0].trend.delta | Should -Match '\+2'
    }
}

Describe 'Invoke-TrendAnalysis -- drivers CodeIntegrity repeat' -Tag 'lib' {
    BeforeAll {
        function New-DriversPrior {
            param([int] $Count, $Newest, [string[]] $ChecksRan = @('drivers'))
            $metrics = @{ 'drivers.unsigned_in_store_count' = 0; 'drivers.code_integrity_event_count' = $Count }
            if ($null -ne $Newest) { $metrics['drivers.code_integrity_newest_event_unix'] = [long]$Newest }
            New-HistoryEntry -TopMetrics $metrics -ChecksRan $ChecksRan
        }
        function New-DriversNow {
            param([int] $Count, $Newest)
            New-CheckStub -Id 'drivers' -Category 'drivers' -Severity 'WARN' -Detail @{
                unsigned_in_store_count          = 0
                code_integrity_event_count       = $Count
                code_integrity_newest_event_unix = $Newest
            }
        }
    }

    It 'upgrades to CRIT when a newer event follows a prior run that also saw one' {
        $result = Invoke-TrendAnalysis -CheckResults @(New-DriversNow -Count 2 -Newest 2000) `
            -HistoryTail @(New-DriversPrior -Count 1 -Newest 1000)
        $result[0].severity | Should -Be 'CRIT'
        $result[0].trend.adjusted_from | Should -Be 'WARN'
        $result[0].notes | Should -Match 'trend upgrade: repeat: CodeIntegrity'
    }

    It 'stays WARN when the only event is the one the prior run already counted' {
        $result = Invoke-TrendAnalysis -CheckResults @(New-DriversNow -Count 1 -Newest 1000) `
            -HistoryTail @(New-DriversPrior -Count 1 -Newest 1000)
        $result[0].severity | Should -Be 'WARN' -Because 're-reading one event inside the 7-day window is not a repeat'
        $result[0].trend.adjusted_from | Should -BeNullOrEmpty
    }

    It 'stays WARN when the prior run saw no CodeIntegrity events' {
        $result = Invoke-TrendAnalysis -CheckResults @(New-DriversNow -Count 1 -Newest 2000) `
            -HistoryTail @(New-DriversPrior -Count 0 -Newest $null)
        $result[0].severity | Should -Be 'WARN'
    }

    It 'stays WARN when the prior run predates the newest-event marker' {
        $result = Invoke-TrendAnalysis -CheckResults @(New-DriversNow -Count 1 -Newest 2000) `
            -HistoryTail @(New-DriversPrior -Count 3 -Newest $null)
        $result[0].severity | Should -Be 'WARN'
    }

    It 'compares against the newest run where drivers ran, skipping runs where it did not' {
        $history = @(
            New-DriversPrior -Count 1 -Newest 1000
            New-DriversPrior -Count 0 -Newest $null
            New-DriversPrior -Count 5 -Newest 1500 -ChecksRan @('disk-space')
        )
        $result = Invoke-TrendAnalysis -CheckResults @(New-DriversNow -Count 1 -Newest 2000) -HistoryTail $history
        $result[0].severity | Should -Be 'WARN' -Because 'the newest run where drivers ran saw zero events'
    }

    It 'survives the history JSON round trip' {
        $history = @(New-DriversPrior -Count 1 -Newest 1790000000) |
            ForEach-Object { $_ | ConvertTo-Json -Depth 5 | ConvertFrom-Json }
        $now = New-DriversNow -Count 1 -Newest 1790003600 | ConvertTo-Json -Depth 5 | ConvertFrom-Json
        $result = Invoke-TrendAnalysis -CheckResults @($now) -HistoryTail $history
        $result[0].severity | Should -Be 'CRIT'
    }
}

Describe 'Format-TrendCell' -Tag 'lib' {
    It 'renders each trend shape as a short cell' {
        Format-TrendCell -Result ([pscustomobject]@{ id = 'x' }) | Should -Be '-'
        Format-TrendCell -Result ([pscustomobject]@{ trend = $null }) | Should -Be '-'
        $none = [pscustomobject]@{ trend = [pscustomobject]@{ last_run = $null; delta = $null; adjusted_from = $null } }
        Format-TrendCell -Result $none | Should -Be '·'
        $up = [pscustomobject]@{ trend = [pscustomobject]@{ last_run = 'r'; delta = 'used_pct: +8 vs prior'; adjusted_from = 'WARN' } }
        Format-TrendCell -Result $up | Should -Be '↑ +8'
        $flat = [pscustomobject]@{ trend = [pscustomobject]@{ last_run = 'r'; delta = 'used_pct: 0 vs prior'; adjusted_from = $null } }
        Format-TrendCell -Result $flat | Should -Be '0'
        $noMetric = [pscustomobject]@{ trend = [pscustomobject]@{ last_run = 'r'; delta = $null; adjusted_from = $null } }
        Format-TrendCell -Result $noMetric | Should -Be '-'
    }
}
