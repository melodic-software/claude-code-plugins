#Requires -Version 7.4

<#
.SYNOPSIS
Parse pnputil /enum-devices /problem output into structured device records.

.DESCRIPTION
Returns an array of { instance_id, device_description, class_name,
manufacturer, problem_code, problem_status }. Output format differs between
Windows 10 2004 and Windows 11 23H2+; this parser tolerates both.

Admin strongly preferred -- non-elevated runs get incomplete output. The
caller decides whether to emit UNKNOWN or INFO on empty results.

Windows-specific. Locale-fragile -- parser targets English "Instance ID"
labels. Unknown layout returns @() with a Write-Verbose note rather than
throwing. A missing pnputil or a failed start is that same empty result.
#>

. (Join-Path $PSScriptRoot 'Invoke-NativeCommand.ps1')

function Get-PnpProblemDevice {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    $invoked = Invoke-NativeCommand -Name 'pnputil' -ArgumentList @('/enum-devices', '/problem')
    if ($invoked.status -eq 'Absent') {
        Write-Verbose 'Get-PnpProblemDevice: pnputil not on PATH.'
        return @()
    }
    # A non-zero exit is still parsed, as before the adapter: pnputil's exit
    # code is not documented as a no-problem-devices signal.
    if ($invoked.status -eq 'Failed') {
        Write-Verbose "Get-PnpProblemDevice: pnputil invocation failed. $($invoked.error)"
        return @()
    }
    $raw = $invoked.output
    if (-not $raw) { return @() }

    # The first split element is always the pre-"Instance ID:" banner preamble, or
    # the whole output when no device has a problem, so skip it.
    $blocks = @($raw -split '(?m)^Instance ID:' | Select-Object -Skip 1 | Where-Object { $_.Trim() })
    $out = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($block in $blocks) {
        # Rejoin the "Instance ID:" prefix for the first field.
        $text = 'Instance ID:' + $block
        $fields = @{}
        foreach ($line in $text -split "`r?`n") {
            if ($line -match '^\s*(?<k>[^:]+?):\s*(?<v>.*?)\s*$') {
                $fields[$Matches['k']] = $Matches['v']
            }
        }
        if (-not $fields.ContainsKey('Instance ID')) { continue }

        $code = 0
        if ($fields['Problem Code'] -match '(\d+)') {
            $code = [int]$Matches[1]
        }
        $out.Add([pscustomobject]@{
                instance_id        = $fields['Instance ID']
                device_description = $fields['Device Description']
                class_name         = $fields['Class Name']
                manufacturer       = $fields['Manufacturer Name']
                problem_code       = $code
                problem_status     = $fields['Problem Status']
            })
    }
    return $out.ToArray()
}
