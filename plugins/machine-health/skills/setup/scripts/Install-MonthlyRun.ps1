#Requires -Version 7.4
<#
.SYNOPSIS
Copies the monthly wrapper into <StateBase>/scheduler/, and tells whether an
existing copy is current.

.DESCRIPTION
setup's schedule step writes the copy with Install-MonthlyRun, and its check step
compares the copy with Test-MonthlyRunCurrent: a plugin update that changes the
wrapper template leaves the copy stale until schedule runs again.
#>

Set-StrictMode -Version 3.0

$script:MonthlyRunTemplate = Join-Path (Split-Path -Parent $PSScriptRoot) 'templates/monthly-run.ps1'

function Install-MonthlyRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $StateBase
    )

    $dir = New-Item -ItemType Directory -Force -Path (Join-Path $StateBase 'scheduler')
    $wrapper = Join-Path $dir.FullName 'monthly-run.ps1'
    Copy-Item -LiteralPath $script:MonthlyRunTemplate -Destination $wrapper -Force
    # Earlier builds installed a deny settings file beside the wrapper; the wrapper no longer reads it.
    Remove-Item -LiteralPath (Join-Path $dir.FullName 'scheduled-settings.json') -ErrorAction Ignore
    [pscustomobject]@{ WrapperPath = $wrapper }
}

function Test-MonthlyRunCurrent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $StateBase
    )

    $wrapper = Join-Path $StateBase 'scheduler/monthly-run.ps1'
    [pscustomobject]@{
        WrapperCurrent = (Test-Path -LiteralPath $wrapper -PathType Leaf) -and
            [System.IO.File]::ReadAllText($wrapper) -ceq [System.IO.File]::ReadAllText($script:MonthlyRunTemplate)
    }
}
