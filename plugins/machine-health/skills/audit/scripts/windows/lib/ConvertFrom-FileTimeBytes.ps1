#Requires -Version 7.4

<#
.SYNOPSIS
Reads a little-endian FILETIME stored inside a registry byte value.

.DESCRIPTION
Returns the UTC time held in the 8 bytes at -Offset, or $null when the value is
too short to hold them, when they are zero or negative (no time recorded), or
when they fall outside the range DateTime can represent.
#>

function ConvertFrom-FileTimeBytes {
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [byte[]] $Bytes,
        [Parameter(Mandatory = $true)] [ValidateRange(0, [int]::MaxValue)] [int] $Offset
    )

    if ($Bytes.Length -lt $Offset + 8) { return $null }
    $fileTime = [BitConverter]::ToInt64($Bytes, $Offset)
    if ($fileTime -le 0) { return $null }
    try { return [datetime]::FromFileTimeUtc($fileTime) } catch { return $null }
}
