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
# closes with U+2018 to U+201B.
function Assert-ScheduleRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $PluginRoot,
        [string] $StateBase
    )

    foreach ($root in @{ Name = 'plugin root'; Value = $PluginRoot }, @{ Name = 'state folder'; Value = $StateBase }) {
        if ($root.Value -match "[\x00-\x1f\x7f'\u2018-\u201b]") {
            throw "The $($root.Name) holds a single quote (' or U+2018 to U+201B), a control character or a line break, which a scheduled run cannot type inside single quotes."
        }
    }
}

# The wrapper text with the plugin root written in, as setup installs it.
function Get-MonthlyRunText {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $PluginRoot)

    Assert-ScheduleRoot -PluginRoot $PluginRoot
    [System.IO.File]::ReadAllText((Join-Path $script:MonthlyRunTemplates 'monthly-run.ps1')).Replace('__PLUGIN_ROOT__', $PluginRoot)
}

function Install-MonthlyRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $PluginRoot,
        [Parameter(Mandatory)] [string] $StateBase
    )

    Assert-ScheduleRoot -PluginRoot $PluginRoot -StateBase $StateBase
    $text = Get-MonthlyRunText -PluginRoot $PluginRoot
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
        [Parameter(Mandatory)] [string] $StateBase
    )

    $dir = Join-Path $StateBase 'scheduler'
    $wrapper = Join-Path $dir 'monthly-run.ps1'
    $settings = Join-Path $dir 'scheduled-settings.json'
    $hash = { param($Path) (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
    [pscustomobject]@{
        WrapperCurrent  = (Test-Path -LiteralPath $wrapper -PathType Leaf) -and
            [System.IO.File]::ReadAllText($wrapper) -ceq (Get-MonthlyRunText -PluginRoot $PluginRoot)
        SettingsCurrent = (Test-Path -LiteralPath $settings -PathType Leaf) -and
            (& $hash $settings) -eq (& $hash (Join-Path $script:MonthlyRunTemplates 'scheduled-settings.json'))
    }
}
