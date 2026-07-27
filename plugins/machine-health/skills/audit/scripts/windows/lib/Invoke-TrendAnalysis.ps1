#Requires -Version 7.4

<#
.SYNOPSIS
Trend-aware severity adjustment + last_run annotation per the rubric in
references/shared/severity-rubric.md.

.DESCRIPTION
For each current check result:

 1. Look up the most recent run in which this check.id ran (history tail).
 2. Attach a `trend` field: { last_run, delta, adjusted_from } -- the shape
    catalog/schemas/check-result.schema.json fixes (additionalProperties:false).
    adjusted_from carries the pre-adjustment severity when step 3 upgrades.
 3. Apply one severity adjustment per the rubric:
       - Upgrade one level on WARN whose trend-relevant metric is worsening
         week-over-week (metric increase >= +5 percentage points for
         pct-style metrics, or any increase for count-style metrics).
       - Downgrade one level when a threshold was crossed once and the check
         has been OK/INFO for the prior 2 runs (revert).
 4. Record the adjustment reason in `notes` ("trend upgrade: X crossed
    threshold last week too").

Conservative defaults: when in doubt, do not adjust. The rubric explicitly
prefers the lower severity on ambiguity and relies on trend upgrades to
catch real regressions. Never silently re-bucket -- every adjustment appends
to notes.

Neutrally named: cross-OS algorithm.
#>

. (Join-Path $PSScriptRoot 'Get-CheckLastRun.ps1')

function Invoke-TrendAnalysis {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $CheckResults,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $HistoryTail
    )

    if ($HistoryTail.Count -eq 0) {
        return $CheckResults
    }

    $numericTypes = @([int], [long], [double], [decimal])

    foreach ($r in $CheckResults) {
        $relevantKey = Get-TrendRelevantKey -CheckId $r.id

        # Extract this check's trend-relevant metric history from the tail
        # (file order: oldest -> newest, since Read-HistoryJsonl uses
        # Get-Content -Tail). top_metrics keys are "<check.id>.<detailKey>"
        # per output-schema.md.
        $priorMetricValues = [System.Collections.Generic.List[object]]::new()
        foreach ($h in $HistoryTail) {
            if ($relevantKey -and $h.PSObject.Properties['top_metrics']) {
                $fullKey = "$($r.id).$relevantKey"
                if ($h.top_metrics.PSObject.Properties[$fullKey]) {
                    $priorMetricValues.Add($h.top_metrics.$fullKey)
                }
            }
        }

        # The most recent prior run is the LAST element, not [0]. With >=2
        # entries using [0] would compare today against stale data.
        $lastMetric = $priorMetricValues.Count -gt 0 ? $priorMetricValues[-1] : $null

        # last_run is the run in which this check actually ran (per-check, from
        # checks_ran) -- NOT "the most recent run overall", which diverges once
        # cadence lets a monthly check skip a run.
        $lastRun = Get-CheckLastRun -CheckId $r.id -HistoryTail $HistoryTail

        # Attach trend annotation.
        $deltaText = $null
        $currentValue = $null
        if ($relevantKey -and $r.detail -and $r.detail.PSObject.Properties[$relevantKey]) {
            $currentValue = $r.detail.$relevantKey
        }

        if ($null -ne $lastMetric -and $null -ne $currentValue -and
            ($numericTypes -contains $currentValue.GetType()) -and
            ($numericTypes -contains $lastMetric.GetType())) {
            $delta = $currentValue - $lastMetric
            $sign = $delta -ge 0 ? '+' : ''
            $deltaText = "$($relevantKey): $sign$delta vs prior"
        }

        # Severity adjustment: upgrade WARN -> CRIT when metric worsens
        # (positive delta for used_pct, negative delta for fullCapacityPct).
        # First-crossing INFO/WARN intentionally not downgraded -- first crossing
        # is exactly what those severities are meant to surface. adjusted_from
        # records the pre-adjustment severity when an upgrade fires.
        $adjustedFrom = $null
        if ($r.severity -eq 'WARN' -and $null -ne $deltaText) {
            $upgrade = Test-WorseningTrend -CheckId $r.id -CurrentValue $currentValue -PriorValue $lastMetric
            if ($upgrade) {
                $adjustedFrom = $r.severity
                $r.severity = 'CRIT'
                $note = "trend upgrade: $deltaText"
                $r.notes = $r.notes ? "$($r.notes); $note" : $note
            }
        }

        $trend = [ordered]@{
            last_run      = $lastRun
            delta         = $deltaText
            adjusted_from = $adjustedFrom
        }

        # Add-Member -Force creates the property if absent or overwrites if present.
        $r | Add-Member -NotePropertyName trend -NotePropertyValue $trend -Force
    }

    return $CheckResults
}

function Get-TrendRelevantKey {
    <#
    .SYNOPSIS
    Returns the single scalar detail key that represents the "trend signal"
    for a given check. Conservative: one metric per check, chosen so history
    queries are cheap.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] [string] $CheckId)

    switch ($CheckId) {
        'disk-space' { return 'used_pct' }
        'battery' { return 'full_capacity_pct' }
        'defender' { return 'signature_age_days' }
        'event-log-errors' { return 'total_events' }
        'winget-upgrades' { return 'upgrades_count' }
        'windows-update' { return 'pending_update_count' }
        'services' { return 'stopped_auto_count' }
        'drivers' { return 'unsigned_in_store_count' }
        'reliability' { return 'stability_min_7d' }
        'claude-temp-root' { return 'total_gb' }
        default { return $null }
    }
}

function Test-WorseningTrend {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)] [string] $CheckId,
        $CurrentValue,
        $PriorValue
    )

    if ($null -eq $CurrentValue -or $null -eq $PriorValue) { return $false }

    try {
        $cur = [double]$CurrentValue
        $prev = [double]$PriorValue
    } catch {
        return $false
    }

    # Direction of "worsening" depends on the metric. Most metrics worsen
    # when the number goes UP (disk used_pct, event count, upgrade count,
    # signature age days, etc.). Battery capacity worsens when DOWN.
    $upwardWorsens = @(
        'disk-space', 'defender', 'event-log-errors',
        'winget-upgrades', 'windows-update', 'services', 'drivers',
        'claude-temp-root'
    )
    $downwardWorsens = @('battery', 'reliability')

    $delta = $cur - $prev

    if ($upwardWorsens -contains $CheckId) {
        # Threshold: >= +5 (raw units or percentage points) counts as worsening.
        return $delta -ge 5
    }
    if ($downwardWorsens -contains $CheckId) {
        return $delta -le -5
    }
    return $false
}
