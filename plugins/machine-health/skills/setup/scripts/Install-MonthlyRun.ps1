#Requires -Version 7.4
<#
.SYNOPSIS
Writes the monthly wrapper and its deny settings into <StateBase>/scheduler/,
and tells whether an existing copy is current.

.DESCRIPTION
The wrapper template carries a placeholder for the plugin root, so its allow
rules name exactly the two audit scripts under that root. setup's schedule step
writes the copy with Install-MonthlyRun, and its check step compares the copy
with Test-MonthlyRunCurrent: a plugin update moves the root, which leaves the
copy stale until schedule runs again.
#>

Set-StrictMode -Version 3.0

$script:MonthlyRunTemplates = Join-Path (Split-Path -Parent $PSScriptRoot) 'templates'

# The wrapper and the scheduled audit type these roots inside single quotes, which PowerShell also
# closes with U+2018 to U+201B, and the wrapper refuses % & | < > ^ in any argument when claude is
# a .cmd, which cmd.exe re-parses.
function Assert-ScheduleRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $PluginRoot,
        [string] $StateBase,
        [string] $ReportRoot
    )

    foreach ($root in @{ Name = 'plugin root'; Value = $PluginRoot }, @{ Name = 'state folder'; Value = $StateBase },
        @{ Name = 'report folder'; Value = $ReportRoot }) {
        if ($root.Value -match "[\x00-\x1f\x7f'\u2018-\u201b]") {
            throw "The $($root.Name) holds a single quote (' or U+2018 to U+201B), a control character or a line break, which a scheduled run cannot type inside single quotes."
        }
        if ($root.Value -match '[%&|<>^]') {
            throw "The $($root.Name) holds one of % & | < > ^, which the monthly run refuses to pass through cmd.exe."
        }
    }
}

# The wrapper text with the roots written in, as setup installs it; its allow rules name them.
function Get-MonthlyRunText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $PluginRoot,
        [Parameter(Mandatory)] [string] $StateBase,
        [string] $ReportRoot
    )

    Assert-ScheduleRoot -PluginRoot $PluginRoot -StateBase $StateBase -ReportRoot $ReportRoot
    [System.IO.File]::ReadAllText((Join-Path $script:MonthlyRunTemplates 'monthly-run.ps1')).
    Replace('__PLUGIN_ROOT__', $PluginRoot).Replace('__STATE_ROOT__', $StateBase).Replace('__REPORT_ROOT__', $ReportRoot)
}

function Install-MonthlyRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $PluginRoot,
        [Parameter(Mandatory)] [string] $StateBase,
        [string] $ReportRoot
    )

    $text = Get-MonthlyRunText -PluginRoot $PluginRoot -StateBase $StateBase -ReportRoot $ReportRoot
    $dir =New-Item -ItemType Directory -Force -Path (Join-Path $StateBase 'scheduler')
    $wrapper = Join-Path $dir.FullName 'monthly-run.ps1'
    $settings = Join-Path $dir.FullName 'scheduled-settings.json'
    [System.IO.File]::WriteAllText($wrapper, $text)
    Copy-Item -LiteralPath (Join-Path $script:MonthlyRunTemplates 'scheduled-settings.json') -Destination $settings -Force
    [pscustomobject]@{ WrapperPath = $wrapper; SettingsPath = $settings }
}

function Test-MonthlyRunCurrent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $PluginRoot,
        [Parameter(Mandatory)] [string] $StateBase,
        [string] $ReportRoot
    )

    $dir = Join-Path $StateBase 'scheduler'
    $wrapper = Join-Path $dir 'monthly-run.ps1'
    $settings = Join-Path $dir 'scheduled-settings.json'
    $hash = { param($Path) (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
    [pscustomobject]@{
        WrapperCurrent  = (Test-Path -LiteralPath $wrapper -PathType Leaf) -and
            [System.IO.File]::ReadAllText($wrapper) -ceq (Get-MonthlyRunText -PluginRoot $PluginRoot -StateBase $StateBase -ReportRoot $ReportRoot)
        SettingsCurrent = (Test-Path -LiteralPath $settings -PathType Leaf) -and
            (& $hash $settings) -eq (& $hash (Join-Path $script:MonthlyRunTemplates 'scheduled-settings.json'))
    }
}
