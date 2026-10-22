#Requires -Version 7.4

<#
.SYNOPSIS
Keep the decision pages of the newest runs in <StateBase>/views and delete the
older runs' files by their exact paths.

.DESCRIPTION
A run's page is three files: checkup-<runStamp>.html, .json and .ids.json.
Runs are the stamps of file names that match that shape exactly; any other
file in the folder is never touched. The newest -Keep runs stay, counting the
current run. For every older run the three paths are computed from its stamp
and each one present is deleted with -LiteralPath; nothing is deleted by
wildcard.

Nothing is deleted unless all three files of -CurrentStamp exist, so a failed
or partial build leaves every older page in place. The orchestrator calls this
after a successful build; the builder never deletes.

Returns the deleted paths.
#>

function Remove-OldCheckupView {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)] [string] $ViewsDir,
        [Parameter(Mandatory = $true)] [ValidatePattern('^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{9}Z$')] [string] $CurrentStamp,
        [ValidateRange(1, 1000)] [int] $Keep = 12
    )

    $suffixes = @('.html', '.json', '.ids.json')
    $pathsOf = { param($Stamp) foreach ($s in $suffixes) { Join-Path $ViewsDir "checkup-$Stamp$s" } }
    foreach ($path in & $pathsOf $CurrentStamp) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    }

    $stamps = [System.Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    foreach ($file in Get-ChildItem -LiteralPath $ViewsDir -File) {
        if ($file.Name -cmatch '^checkup-([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{9}Z)\.(html|json|ids\.json)$') { [void]$stamps.Add($Matches[1]) }
    }
    $older = @($stamps.Reverse() | Select-Object -Skip $Keep | Where-Object { $_ -cne $CurrentStamp })
    foreach ($stamp in $older) {
        foreach ($path in & $pathsOf $stamp) {
            if ((Test-Path -LiteralPath $path -PathType Leaf) -and $PSCmdlet.ShouldProcess($path, 'Remove')) {
                Remove-Item -LiteralPath $path -Force -ErrorAction Stop
                $path
            }
        }
    }
}
