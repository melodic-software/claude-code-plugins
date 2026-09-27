#Requires -Version 7.4

<#
.SYNOPSIS
Returns the audit skill root directory.

.DESCRIPTION
The orchestrator sits at scripts/windows/ and the checks one level deeper at
scripts/windows/checks/, so a caller deriving the root from its own
$PSScriptRoot needs a different number of Split-Path hops depending on where it
lives. $PSScriptRoot inside a dot-sourced function is the directory of the file
that DEFINES the function, so resolving from this library's own location gives
every caller the same answer and the hop count is written once.
#>

function Resolve-SkillRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # lib -> windows -> scripts -> skill root
    return Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent | Split-Path -Parent
}
