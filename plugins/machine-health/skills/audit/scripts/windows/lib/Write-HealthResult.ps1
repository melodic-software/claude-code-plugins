#Requires -Version 7.4

<#
.SYNOPSIS
Canonical builder + emitter for the CheckResult schema defined in
catalog/schemas/check-result.schema.json.

.DESCRIPTION
Every check script should build its result via New-HealthResult (or
New-HealthFailureResult from its outer catch) and emit via Complete-HealthCheck
rather than hand-constructing JSON. Guarantees consistent field names, ISO 8601
timestamps with offset, correct severity casing, and schema validation at emit
time.

Validation: Write-HealthResult calls Assert-CheckResult before serialization.
A broken check crashes inside its Start-Job and the orchestrator records
UNKNOWN instead of ingesting malformed JSON -- fail loudly rather than
silently corrupt state.

Output modes:
- Default: compact JSON on stdout (what the orchestrator captures).
- -Human:  plain "[SEV] id - summary" lines on stdout for interactive
           dev runs. Still passes through schema validation so bugs are
           caught whether the script is exercised manually or by the
           orchestrator.
#>

. (Join-Path $PSScriptRoot 'Assert-CheckResult.ps1')

function New-HealthResult {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string] $Id,
        [Parameter(Mandatory = $true)] [string] $Category,
        [Parameter(Mandatory = $true)] [ValidateSet('windows', 'macos', 'linux')] [string] $Os,
        [Parameter(Mandatory = $true)] [ValidateSet('OK', 'INFO', 'WARN', 'CRIT', 'UNKNOWN')] [string] $Severity,
        [Parameter(Mandatory = $true)] [string] $Summary,
        [hashtable] $Detail,
        [string[]] $Commands,
        [bool] $NeedsAdmin = $false,
        [bool] $RanSuccessfully = $true,
        [int] $DurationMs = 0,
        [hashtable] $Trend,
        [string] $Notes,
        [string] $ErrorMessage,
        [string[]] $AdminFields
    )

    # List[string] over [string[]] because ConvertTo-Json + pscustomobject conversions
    # auto-enumerate empty and single-element arrays into $null / scalar strings, producing
    # schema-invalid JSON. A generic List is preserved verbatim at every pipeline step.
    $commandsNormalized = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $Commands) { $commandsNormalized.AddRange($Commands) }
    $detailNormalized = if ($null -ne $Detail) { $Detail } else { @{} }

    if ($AdminFields -and $AdminFields.Count -gt 0) {
        # Admin-gated detail keys the check would populate only when elevated.
        # Consumed by the report's elevation-coverage block and by tests asserting
        # the admin_fields contract. Never mutates existing detail data --
        # additive only.
        $detailNormalized['admin_fields'] = @($AdminFields)
    }

    $ordered = [ordered]@{
        id               = $Id
        category         = $Category
        os               = $Os
        ran_at           = (Get-Date).ToString('o')
        severity         = $Severity
        summary          = $Summary
        detail           = $detailNormalized
        commands         = $commandsNormalized
        needs_admin      = $NeedsAdmin
        ran_successfully = $RanSuccessfully
        duration_ms      = $DurationMs
        trend            = $Trend
        notes            = $Notes
        error            = $ErrorMessage
    }
    return [pscustomobject]$ordered
}

function New-HealthFailureResult {
    <#
    .SYNOPSIS
    Builds the UNKNOWN result a check's outer catch reports.

    .DESCRIPTION
    Every Windows check ends in a catch that reports the same envelope: UNKNOWN
    severity, ran_successfully false, the exception message as the error field.
    Only the id, category, summary and (for admin-gated checks) the elevation
    metadata differ, so those are the parameters here. duration_ms is left at
    its default because Complete-HealthCheck stamps the elapsed time at emit.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string] $Id,
        [Parameter(Mandatory = $true)] [string] $Category,
        [Parameter(Mandatory = $true)] [string] $Summary,
        [Parameter(Mandatory = $true)] [System.Management.Automation.ErrorRecord] $ErrorRecord,
        [string[]] $Commands,
        [bool] $NeedsAdmin = $false,
        [string[]] $AdminFields
    )

    return New-HealthResult -Id $Id -Category $Category -Os 'windows' `
        -Severity 'UNKNOWN' -Summary $Summary -Commands $Commands `
        -NeedsAdmin $NeedsAdmin -RanSuccessfully $false `
        -ErrorMessage $ErrorRecord.Exception.Message `
        -AdminFields $AdminFields
}

function Complete-HealthCheck {
    <#
    .SYNOPSIS
    Stamps the measured duration onto a finished result and emits it.

    .DESCRIPTION
    The closing three lines of every check: stop the stopwatch started at the
    top of the script, record the elapsed milliseconds on the result, and write
    it in the mode the caller was invoked with.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)] $Result,
        [Parameter(Mandatory = $true)] [System.Diagnostics.Stopwatch] $Stopwatch,
        [switch] $Human
    )

    $Stopwatch.Stop()
    $Result.duration_ms = [int]$Stopwatch.ElapsedMilliseconds
    $Result | Write-HealthResult -Human:$Human
}

function Write-HealthResult {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] $Result,
        [switch] $Human
    )
    process {
        [void](Assert-CheckResult $Result -Because 'Write-HealthResult emit')

        if ($Human) {
            $line = "[$($Result.severity)] $($Result.id) - $($Result.summary)"
            Write-Output $line
            if ($Result.notes) { Write-Output "  note: $($Result.notes)" }
            if ($Result.error) { Write-Output "  error: $($Result.error)" }
        } else {
            Write-Output ($Result | ConvertTo-Json -Depth 10 -Compress)
        }
    }
}
