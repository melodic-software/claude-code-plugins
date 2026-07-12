#Requires -Version 7.4

<#
.SYNOPSIS
Parse pnputil /enum-devices /problem output into structured device records.

.DESCRIPTION
Returns an array of { instance_id, device_description, problem_code,
problem_status, class_name }. Output format differs slightly between
Windows 10 2004 and Windows 11 23H2+; this parser tolerates both.

Admin strongly preferred -- non-elevated runs get incomplete output. The
caller decides whether to emit UNKNOWN or INFO on empty results.

Windows-specific. Locale-fragile -- parser targets English "Instance ID"
labels. Unknown layout returns @() with a Write-Verbose note rather than
throwing.
#>

function Get-PnpProblemDevice {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    if (-not (Get-Command pnputil -ErrorAction SilentlyContinue)) {
        Write-Verbose 'Get-PnpProblemDevice: pnputil not on PATH.'
        return @()
    }

    $raw = $null
    try {
        $raw = (& pnputil /enum-devices /problem 2>&1) -join "`n"
    } catch {
        Write-Verbose "Get-PnpProblemDevice: pnputil invocation failed. $($_.Exception.Message)"
        return @()
    }
    if (-not $raw) { return @() }

    # Split into device blocks. Each block starts with "Instance ID:".
    # The FIRST element of the split is always pre-"Instance ID:" preamble
    # spellchecker:ignore-next-line
    # (banner text like "Microsoft PnP Utility" and, on healthy systems, any
    # "no devices have problems" message) -- drop it. When pnputil emits no
    # device blocks at all, the split produces a single preamble element and
    # we correctly return @().
    $split = $raw -split '(?m)^Instance ID:'
    $blocks = @()
    if ($split.Count -gt 1) {
        $blocks = @($split | Select-Object -Skip 1 | Where-Object { $_.Trim() })
    }
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
        if ($fields.ContainsKey('Problem Code')) {
            $codeRaw = $fields['Problem Code']
            if ($codeRaw -match '(\d+)') {
                $code = [int]$Matches[1]
            }
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
