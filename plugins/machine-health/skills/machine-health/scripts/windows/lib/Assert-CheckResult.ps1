#Requires -Version 7.4
<#
.SYNOPSIS
Validates that an object conforms to the CheckResult JSON Schema.

.DESCRIPTION
Enforces the contract every check script must honor. Covers the fields and
conditional rules from catalog/schemas/check-result.schema.json without a
first-class JSON Schema library (PowerShell has no stable option).

Called from two places:
- Write-HealthResult (production emit) - throws before ConvertTo-Json so a
  broken check crashes inside Start-Job and the orchestrator records UNKNOWN
  instead of ingesting malformed JSON.
- Pester tests - fails the test with a readable assertion message.

Accepts pscustomobject or hashtable/ordered-dictionary (both are how tests and
New-HealthResult produce candidates). Returns $true on success; throws on
violation so callers can wrap in try/catch or let Pester surface the message.
#>

function Assert-CheckResult {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)] $Result,
        [string] $Because
    )

    if ($null -eq $Result) {
        throw 'CheckResult is null.'
    }

    $ctx = if ($Because) { " ($Because)" } else { '' }

    if ($Result -is [System.Collections.IDictionary]) {
        $getField = { param($n) if ($Result.Contains($n)) { $Result[$n] } else { $null } }
        $hasField = { param($n) $Result.Contains($n) }
    } else {
        $getField = { param($n) $Result.PSObject.Properties[$n].Value }
        $hasField = { param($n) $null -ne $Result.PSObject.Properties[$n] }
    }

    $requiredKeys = @(
        'category', 'commands', 'detail', 'duration_ms', 'error', 'id',
        'needs_admin', 'notes', 'os', 'ran_at', 'ran_successfully',
        'severity', 'summary', 'trend'
    )
    foreach ($k in $requiredKeys) {
        if (-not (& $hasField $k)) {
            throw "CheckResult missing required field '$k'$ctx."
        }
    }

    $id = & $getField 'id'
    if ($id -cnotmatch '^[a-z][a-z0-9-]*[a-z0-9]$') {
        throw "CheckResult.id '$id' is not valid kebab-case$ctx."
    }

    $validCategories = @(
        'drivers', 'network', 'power', 'reliability',
        'security', 'services', 'storage', 'updates'
    )
    $category = & $getField 'category'
    if ($category -notin $validCategories) {
        throw "CheckResult.category '$category' not in allowed set$ctx."
    }

    $os = & $getField 'os'
    if ($os -notin @('linux', 'macos', 'windows')) {
        throw "CheckResult.os '$os' not in allowed set$ctx."
    }

    $validSeverities = @('CRIT', 'INFO', 'OK', 'UNKNOWN', 'WARN')
    $severity = & $getField 'severity'
    if ($severity -notin $validSeverities) {
        throw "CheckResult.severity '$severity' not in allowed set$ctx."
    }

    $summary = & $getField 'summary'
    if ([string]::IsNullOrWhiteSpace($summary)) {
        throw "CheckResult.summary is empty$ctx."
    }
    if ($summary.Length -gt 240) {
        throw "CheckResult.summary exceeds 240 chars ($($summary.Length))$ctx."
    }

    $duration = & $getField 'duration_ms'
    if ($duration -lt 0 -or $duration -gt 90000) {
        throw "CheckResult.duration_ms out of range [0,90000]: $duration$ctx."
    }

    $ranSuccessfully = & $getField 'ran_successfully'
    $errorField = & $getField 'error'
    if (-not $ranSuccessfully) {
        if ($severity -ne 'UNKNOWN') {
            throw "When ran_successfully is false, severity must be UNKNOWN (got '$severity')$ctx."
        }
        if ([string]::IsNullOrWhiteSpace($errorField)) {
            throw "When ran_successfully is false, error must be set$ctx."
        }
    }

    $commands = & $getField 'commands'
    foreach ($cmd in $commands) {
        if ([string]::IsNullOrWhiteSpace($cmd)) {
            throw "CheckResult.commands contains empty or whitespace entry$ctx."
        }
    }

    # trend is object-or-null with additionalProperties:false in the schema.
    # Enforce the sub-shape here so an emitter drift (e.g. a stray last_severity)
    # fails loudly instead of silently diverging from check-result.schema.json.
    $trend = & $getField 'trend'
    if ($null -ne $trend) {
        $allowedTrendKeys = @('last_run', 'delta', 'adjusted_from')
        if ($trend -is [System.Collections.IDictionary]) {
            $trendKeys = @($trend.Keys)
            $adjustedFrom = if ($trend.Contains('adjusted_from')) { $trend['adjusted_from'] } else { $null }
        } else {
            $trendKeys = @($trend.PSObject.Properties.Name)
            $afProp = $trend.PSObject.Properties['adjusted_from']
            $adjustedFrom = if ($afProp) { $afProp.Value } else { $null }
        }
        foreach ($tk in $trendKeys) {
            if ($tk -notin $allowedTrendKeys) {
                throw "CheckResult.trend has unexpected key '$tk' (allowed: $($allowedTrendKeys -join ', '))$ctx."
            }
        }
        if ($null -ne $adjustedFrom -and $adjustedFrom -notin $validSeverities) {
            throw "CheckResult.trend.adjusted_from '$adjustedFrom' is not a valid severity$ctx."
        }
    }

    return $true
}
