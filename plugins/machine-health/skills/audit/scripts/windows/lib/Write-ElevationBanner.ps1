#Requires -Version 7.4

<#
.SYNOPSIS
Renders the pre-run elevation awareness banner to stderr so interactive users
know up front what coverage they'll get and how to re-run elevated if desired.

.DESCRIPTION
Per SKILL.md: no interactive prompts, ever. This is a loud one-way
communication, not a y/n. The user either acts on it (re-runs elevated) or
ignores it (the skill continues with reduced coverage).

Output goes to stderr via [Console]::Error.WriteLine so stdout JSON is never
contaminated. Callers that need silence pass -Quiet, which is also how the
orchestrator's -SkipBanner flag cascades here.

Neutrally named. The renderer is OS-agnostic: it consumes whatever matrix
Get-ElevationMatrix returns. Windows entries today, macOS/Linux entries
when those ship.

Banner structure:

   ================================================================
    machine-health - <hostname> - NON-ELEVATED
   ================================================================
    Running as <user> without admin.

    Covered non-elevated:
      - <labels from Get-NonElevatedCoverage>

    Admin-only (will emit UNKNOWN with needs_admin: true):
      - <Feature> [<CheckId>]
          <Reason>

    To run elevated:
      Ask the session that ran this audit for the elevated pass. It shows
      the launcher script and its SHA-256, and launches it behind UAC
      only after you say yes.

    Suppress this banner with -SkipBanner.
   ================================================================
#>

function Write-ElevationBanner {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [bool] $Elevated,
        [Parameter(Mandatory = $true)] [string] $HostName,
        [Parameter(Mandatory = $true)] [string] $UserName,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Matrix,
        [AllowEmptyCollection()]
        [object[]] $NonElevatedCoverage = @(),
        [switch] $Quiet
    )

    if ($Quiet -or $Elevated) { return }

    $sep = '=' * 78
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('')
    $lines.Add($sep)
    $lines.Add(" machine-health - $HostName - NON-ELEVATED")
    $lines.Add($sep)
    $lines.Add(" Running as $UserName without admin.")
    $lines.Add('')

    if ($NonElevatedCoverage.Count -gt 0) {
        $lines.Add(' Covered non-elevated:')
        foreach ($c in $NonElevatedCoverage) {
            $lines.Add("   - $c")
        }
        $lines.Add('')
    }

    if ($Matrix -and $Matrix.Count -gt 0) {
        $lines.Add(' Admin-only (will emit UNKNOWN with needs_admin: true):')
        foreach ($m in $Matrix) {
            $lines.Add("   - $($m.Feature) [$($m.CheckId)]")
            $lines.Add("       $($m.Reason)")
        }
        $lines.Add('')
    }

    $lines.Add(' To run elevated:')
    $lines.Add('   Ask the session that ran this audit for the elevated pass. It shows')
    $lines.Add('   the launcher script and its SHA-256, and launches it behind UAC')
    $lines.Add('   only after you say yes.')
    $lines.Add('')
    $lines.Add(' Suppress this banner with -SkipBanner.')
    $lines.Add($sep)
    $lines.Add('')

    foreach ($line in $lines) {
        [Console]::Error.WriteLine($line)
    }
}

function Get-ElevationCoverageMarkdown {
    <#
    .SYNOPSIS
    Returns the markdown block rendered into the report's {{elevation_coverage}}
    token. Non-elevated runs get a collapsed <details> section enumerating
    what was skipped; elevated runs get a terse "Elevated - full coverage" line.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)] [bool] $Elevated,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Matrix
    )

    if ($Elevated) {
        return '_Elevated run - full coverage._'
    }

    if (-not $Matrix -or $Matrix.Count -eq 0) {
        return '_Non-elevated run. No admin-gated checks registered._'
    }

    $body = [System.Collections.Generic.List[string]]::new()
    $body.Add('<details>')
    $body.Add("<summary>Non-elevated - $($Matrix.Count) admin-gated capabilities skipped</summary>")
    $body.Add('')
    $body.Add('| Feature | Check | Populates when elevated | Reason |')
    $body.Add('|---|---|---|---|')
    foreach ($m in $Matrix) {
        $body.Add("| $($m.Feature) | $($m.CheckId) | $($m.Fields -join ', ') | $($m.Reason) |")
    }
    $body.Add('')
    $body.Add('To populate these: ask the audit session for the elevated pass. It shows the launcher script and its SHA-256, launches it behind UAC only after the owner says yes, and imports its results into a standard run.')
    $body.Add('</details>')
    return ($body -join "`n")
}
