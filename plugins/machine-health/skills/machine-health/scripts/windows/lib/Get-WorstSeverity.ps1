#Requires -Version 7.4

<#
.SYNOPSIS
Returns the worst severity level from a collection.

.DESCRIPTION
Severity ladder: OK < INFO < WARN < CRIT < UNKNOWN. Used by check scripts that
aggregate multiple sub-severities into one envelope severity.
#>

function Get-WorstSeverity {
    [CmdletBinding()]
    [OutputType([string])]
    param([string[]] $Levels)
    $order = @{ 'OK' = 0; 'INFO' = 1; 'WARN' = 2; 'CRIT' = 3; 'UNKNOWN' = 4 }
    $max = 'OK'
    foreach ($lvl in $Levels) {
        if ($order[$lvl] -gt $order[$max]) { $max = $lvl }
    }
    return $max
}
