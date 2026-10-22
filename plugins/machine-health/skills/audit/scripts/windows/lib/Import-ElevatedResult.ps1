#Requires -Version 7.4

<#
.SYNOPSIS
Merge an elevated pass's result file into a standard run's check results.

.DESCRIPTION
The standard side of the elevated pass (reference/windows/elevation-matrix.md,
"How to run elevated"). The file is accepted only when:

 - its format is exactly 'elevated-result/1';
 - its ran_at is later than the file's CreationTimeUtc, the moment
   New-ElevatedLaunch pre-created it, so a document written before the launch
   is refused;
 - every result passes Assert-CheckResult and no check id repeats.

An accepted file replaces the standard result for each check id both runs hold;
an elevated result for an id the standard run lacks is dropped. A refused file
changes no result and adds one UNKNOWN 'elevated-pass' result naming why.

Returns Results (the merged list), ElevatedChecks (the ids replaced) and
Rejected (the refusal reason, or $null).
#>

. (Join-Path $PSScriptRoot 'Assert-CheckResult.ps1')
. (Join-Path $PSScriptRoot 'Read-SharedText.ps1')

function Import-ElevatedResult {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [AllowEmptyCollection()] [object[]] $CheckResults = @()
    )

    $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $elevatedById = [ordered]@{}
    $reason = $null
    try {
        if (-not [System.IO.File]::Exists($fullPath)) { throw 'the file does not exist.' }
        $createdUtc = [System.IO.File]::GetCreationTimeUtc($fullPath)
        $raw = Read-SharedText -Path $fullPath
        if ([string]::IsNullOrWhiteSpace($raw)) { throw 'the file is empty; the elevated pass wrote nothing.' }
        $document = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($document -isnot [pscustomobject]) { throw 'the file is not a JSON object.' }

        $format = $document.PSObject.Properties['format']
        if ($null -eq $format -or $format.Value -isnot [string] -or $format.Value -cne 'elevated-result/1') {
            throw "format is not 'elevated-result/1'."
        }

        $ranAtProperty = $document.PSObject.Properties['ran_at']
        $ranAt = if ($null -eq $ranAtProperty) {
            $null
        } elseif ($ranAtProperty.Value -is [datetime]) {
            [DateTimeOffset]$ranAtProperty.Value
        } elseif ($ranAtProperty.Value -is [string]) {
            $parsed = [DateTimeOffset]::MinValue
            if ([DateTimeOffset]::TryParse($ranAtProperty.Value, [cultureinfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) { $parsed } else { $null }
        }
        if ($null -eq $ranAt) { throw 'ran_at is missing or not a date-time.' }
        if ($ranAt.UtcDateTime -le $createdUtc) {
            throw "ran_at $($ranAt.ToString('o')) is not later than the file's creation time $($createdUtc.ToString('o'))."
        }

        $resultsProperty = $document.PSObject.Properties['results']
        if ($null -eq $resultsProperty -or $null -eq $resultsProperty.Value) { throw 'results is missing.' }
        foreach ($result in @($resultsProperty.Value)) {
            [void](Assert-CheckResult $result -Because 'elevated pass result')
            if ($elevatedById.Contains([string]$result.id)) { throw "check id '$($result.id)' appears twice." }
            $elevatedById[[string]$result.id] = $result
        }
    } catch {
        $reason = $_.Exception.Message
    }

    if ($null -ne $reason) {
        $summary = "Elevated pass result not imported: $reason"
        if ($summary.Length -gt 240) { $summary = $summary.Substring(0, 237) + '...' }
        $note = [pscustomobject]@{
            id               = 'elevated-pass'
            category         = 'config'
            os               = 'windows'
            ran_at           = (Get-Date).ToString('o')
            severity         = 'UNKNOWN'
            summary          = $summary
            detail           = [pscustomobject]@{ result_path = $fullPath }
            commands         = @()
            needs_admin      = $true
            ran_successfully = $false
            duration_ms      = 0
            trend            = $null
            notes            = $null
            error            = 'elevated_result_rejected'
        }
        return [pscustomobject]@{
            Results        = @($CheckResults) + @($note)
            ElevatedChecks = [string[]]@()
            Rejected       = $reason
        }
    }

    $replaced = [System.Collections.Generic.List[string]]::new()
    $merged = [System.Collections.Generic.List[object]]::new()
    foreach ($result in $CheckResults) {
        $id = [string]$result.id
        if ($elevatedById.Contains($id)) {
            $replaced.Add($id)
            $merged.Add($elevatedById[$id])
        } else {
            $merged.Add($result)
        }
    }
    return [pscustomobject]@{
        Results        = $merged.ToArray()
        ElevatedChecks = [string[]]$replaced.ToArray()
        Rejected       = $null
    }
}
