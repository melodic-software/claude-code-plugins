#Requires -Version 7.4

<#
.SYNOPSIS
The format string of the elevated pass's result document, shared by
Write-ElevatedResult and Import-ElevatedResult.
#>

function Get-ElevatedResultFormat {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return 'elevated-result/1'
}
