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
      - <list of non-admin checks by category>

    Admin-only (will emit UNKNOWN with needs_admin: true):
      - <Feature> [<CheckId>]
          <Reason>

    To run elevated:
      Open Windows Terminal as Administrator, then:
        pwsh -NoProfile -Command "Start-Transcript -Path '<StateBase>\logs\elevated-run-<date>.log' -Force | Out-Null; & '<skill>\scripts\windows\Invoke-MachineHealthCheck.ps1' -OutputBase '<OutputBase>' -StateBase '<StateBase>'; Stop-Transcript | Out-Null"

    Suppress this banner with -SkipBanner.
   ================================================================
#>

function Write-ElevationBanner {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [bool] $Elevated,
        [Parameter(Mandatory = $true)] [string] $HostName,
        [Parameter(Mandatory = $true)] [string] $UserName,
        [Parameter(Mandatory = $true)] [string] $OutputBase,
        # Resolved state root. The elevated rerun command must pin it explicitly:
        # an elevated terminal usually lacks CLAUDE_PLUGIN_DATA, so an unpinned
        # rerun would fall back to OutputBase and split state across two roots.
        [string] $StateBase,
        [Parameter(Mandatory = $true)] [string] $SkillRoot,
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

    $invokeScript = Join-Path $SkillRoot 'scripts\windows\Invoke-MachineHealthCheck.ps1'
    $logBase = if ($StateBase) { $StateBase } else { $OutputBase }
    $transcript = "$($logBase.TrimEnd('\'))\logs\elevated-run-$(Get-Date -Format 'yyyy-MM-dd').log"
    $rerunArgs = "-OutputBase '$OutputBase'"
    if ($StateBase) { $rerunArgs += " -StateBase '$StateBase'" }
    $lines.Add(' To run elevated (the calling session cannot read an elevated console, so the run writes a transcript):')
    $lines.Add('   Open Windows Terminal as Administrator, then:')
    $lines.Add("     pwsh -NoProfile -Command ""Start-Transcript -Path '$transcript' -Force | Out-Null; & '$invokeScript' $rerunArgs; Stop-Transcript | Out-Null""")
    $lines.Add("   Transcript of the run's output stream, without its stderr banners: $transcript")
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
    $body.Add('To populate these: re-run the skill from an elevated Windows Terminal. The run banner prints the command; it writes a transcript of the run''s output stream (the summary lines, not the stderr banners) to `<StateBase>/logs/elevated-run-<date>.log`, which the calling session can read.')
    $body.Add('</details>')
    return ($body -join "`n")
}
