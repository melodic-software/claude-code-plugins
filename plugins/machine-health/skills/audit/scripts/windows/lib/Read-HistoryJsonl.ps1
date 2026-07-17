#Requires -Version 7.4

<#
.SYNOPSIS
Read the tail of state/history.jsonl and return parsed run summaries.

.DESCRIPTION
history.jsonl is append-only. Each line is one compact run summary per
output-schema.md. This helper reads the last N lines, parses each as JSON,
and returns an array. Returns an empty array if the file is missing (first
run) -- do not throw. Malformed lines are skipped with a warning.
#>

function Read-HistoryJsonl {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [int] $Tail = 8
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    try {
        $lines = Get-Content -LiteralPath $Path -Tail $Tail -ErrorAction Stop
    } catch {
        Write-Warning "Read-HistoryJsonl: unable to read '$Path' - $($_.Exception.Message)"
        return @()
    }

    $parsed = [System.Collections.Generic.List[object]]::new()
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $parsed.Add(($line | ConvertFrom-Json -ErrorAction Stop))
        } catch {
            Write-Warning "Read-HistoryJsonl: skipping malformed line - $($_.Exception.Message)"
        }
    }
    return $parsed.ToArray()
}
