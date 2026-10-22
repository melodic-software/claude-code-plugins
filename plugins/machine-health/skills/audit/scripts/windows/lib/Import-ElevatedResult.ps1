#Requires -Version 7.4

<#
.SYNOPSIS
Merge an elevated pass's result file into a standard run's check results.

.DESCRIPTION
The acceptance rules are in reference/windows/elevation-matrix.md, "How to run
elevated". A refused file changes no result and adds one UNKNOWN
'elevated-pass' result naming why. An accepted file replaces the result for
each check id both the run and -AllowedCheckIds hold; a result for an id
outside -AllowedCheckIds is dropped and counted in one INFO 'elevated-pass'
result.

Returns Results (the merged list), ElevatedChecks (the ids replaced), Rejected
(the refusal reason, or $null) and Log (the document's log lines, each one
line and capped, at most 200; empty when refused).
#>

. (Join-Path $PSScriptRoot 'Get-ElevatedResultFormat.ps1')
. (Join-Path $PSScriptRoot 'Assert-CheckResult.ps1')
. (Join-Path $PSScriptRoot 'Read-SharedText.ps1')
. (Join-Path $PSScriptRoot 'New-UnknownCheckResult.ps1')
. (Join-Path $PSScriptRoot 'Get-ElevationMatrix.ps1')

function Import-ElevatedResult {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [AllowEmptyCollection()] [object[]] $CheckResults = @(),
        [string[]] $AllowedCheckIds = @(Get-ElevationMatrix | ForEach-Object { [string]$_.CheckId } | Select-Object -Unique),
        [string] $CurrentUserSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    )

    $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $noteEntry = [pscustomobject]@{ id = 'elevated-pass'; category = 'config'; needs_admin = $true }
    $elevatedById = [ordered]@{}
    $droppedIds = [System.Collections.Generic.List[string]]::new()
    $log = [System.Collections.Generic.List[string]]::new()
    $reason = $null
    try {
        if (-not [System.IO.File]::Exists($fullPath)) { throw 'the file does not exist.' }
        $createdUtc = [System.IO.File]::GetCreationTimeUtc($fullPath)
        $raw = Read-SharedText -Path $fullPath
        if ([string]::IsNullOrWhiteSpace($raw)) { throw 'the file is empty; the elevated pass wrote nothing.' }
        $document = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($document -isnot [pscustomobject]) { throw 'the file is not a JSON object.' }
        $field = { param($Name) $p = $document.PSObject.Properties[$Name]; if ($p) { $p.Value } }

        $format = & $field 'format'
        if ($format -isnot [string] -or $format -cne (Get-ElevatedResultFormat)) {
            throw "format is not '$(Get-ElevatedResultFormat)'."
        }
        if ((& $field 'elevated') -isnot [bool] -or -not (& $field 'elevated')) {
            throw 'elevated is not true; the pass did not run with an admin token.'
        }
        $sid = & $field 'user_sid'
        if ($sid -isnot [string] -or $sid -cne $CurrentUserSid) {
            throw "user_sid '$sid' is not this user's SID."
        }

        $ranAtValue = & $field 'ran_at'
        $ranAt = if ($ranAtValue -is [datetime]) {
            [DateTimeOffset]$ranAtValue
        } elseif ($ranAtValue -is [string]) {
            $parsed = [DateTimeOffset]::MinValue
            if ([DateTimeOffset]::TryParse($ranAtValue, [cultureinfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) { $parsed }
        }
        if ($null -eq $ranAt) { throw 'ran_at is missing or not a date-time.' }
        if ($ranAt.UtcDateTime -le $createdUtc) {
            throw "ran_at $($ranAt.ToString('o')) is not later than the file's creation time $($createdUtc.ToString('o'))."
        }

        $results = & $field 'results'
        if ($null -eq $results) { throw 'results is missing.' }
        foreach ($result in @($results)) {
            [void](Assert-CheckResult $result -Because 'elevated pass result')
            $id = [string]$result.id
            if ($elevatedById.Contains($id) -or $droppedIds.Contains($id)) { throw "check id '$id' appears twice." }
            if ($id -cin $AllowedCheckIds) { $elevatedById[$id] = $result } else { $droppedIds.Add($id) }
        }

        $logValue = & $field 'log'
        foreach ($line in @(if ($null -ne $logValue) { @($logValue) | Select-Object -First 200 })) {
            $one = ([string]$line) -replace '\p{C}', ' '
            if ($one.Length -gt 500) { $one = $one.Substring(0, 500) }
            $log.Add($one)
        }
    } catch {
        $reason = $_.Exception.Message
    }

    if ($null -ne $reason) {
        $summary = "Elevated pass result not imported: $reason"
        if ($summary.Length -gt 240) { $summary = $summary.Substring(0, 237) + '...' }
        $note = New-UnknownCheckResult -Entry $noteEntry -Summary $summary -ErrorReason 'elevated_result_rejected' `
            -Detail ([pscustomobject]@{ result_path = $fullPath })
        return [pscustomobject]@{
            Results        = @($CheckResults) + @($note)
            ElevatedChecks = [string[]]@()
            Rejected       = $reason
            Log            = [string[]]@()
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
    if ($droppedIds.Count -gt 0) {
        $note = New-UnknownCheckResult -Entry $noteEntry -ErrorReason 'none' `
            -Summary "Elevated pass: dropped $($droppedIds.Count) result(s) for checks without an elevation-matrix row." `
            -Detail ([pscustomobject]@{ result_path = $fullPath; dropped_check_ids = $droppedIds.ToArray() })
        $note.severity = 'INFO'
        $note.ran_successfully = $true
        $note.error = $null
        $merged.Add($note)
    }
    return [pscustomobject]@{
        Results        = $merged.ToArray()
        ElevatedChecks = [string[]]$replaced.ToArray()
        Rejected       = $null
        Log            = [string[]]$log.ToArray()
    }
}
