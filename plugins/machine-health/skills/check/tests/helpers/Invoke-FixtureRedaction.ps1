#Requires -Version 7.4
<#
.SYNOPSIS
Scrubs machine-specific values from a captured object before it becomes a test fixture.

.DESCRIPTION
Recursively walks the object graph and replaces values that would vary across
machines (username, hostname, drive letters, serials, MAC addresses) with stable
placeholders. Preserves shape and data types.

Intended input is the deserialized output of Export-Clixml (hashtable,
pscustomobject, array) from Get-* cmdlets.

.PARAMETER InputObject
Object graph to redact.

.PARAMETER PreserveDriveLetter
Drive letter that is the intentional subject of the fixture (e.g., 'C' when
capturing a C:-drive scenario). Kept verbatim; all other drive letters are
replaced with __DRIVE__.
#>

function Invoke-FixtureRedaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline = $true)] $InputObject,
        [char] $PreserveDriveLetter = [char]0
    )

    process {
        $context = [pscustomobject]@{
            UsernamePattern = "$env:USERNAME"
            HostnamePattern = "$env:COMPUTERNAME"
            UsernameReplace = '__USERNAME__'
            HostnameReplace = '__HOSTNAME__'
            DriveReplace    = '__DRIVE__'
            MacReplace      = '00-00-00-00-00-00'
            MacRegex        = '(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}'
            DriveRegex      = '(?<![A-Za-z])[A-Za-z](?=:[\\/])'
            PreserveDrive   = $PreserveDriveLetter
        }
        $visited = [System.Collections.Generic.HashSet[object]]::new()
        Edit-RedactedValue -Value $InputObject -Context $context -Visited $visited
    }
}

function Edit-RedactedValue {
    [CmdletBinding()]
    [OutputType([string], [System.Collections.Specialized.OrderedDictionary], [object[]], [pscustomobject])]
    param(
        $Value,
        [Parameter(Mandatory)] $Context,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[object]] $Visited
    )

    if ($null -eq $Value) { return $null }

    if ($Value -is [string]) {
        $out = $Value
        if ($Context.UsernamePattern -and $out.Contains($Context.UsernamePattern)) {
            $out = $out.Replace($Context.UsernamePattern, $Context.UsernameReplace)
        }
        if ($Context.HostnamePattern -and $out.Contains($Context.HostnamePattern)) {
            $out = $out.Replace($Context.HostnamePattern, $Context.HostnameReplace)
        }
        $out = [regex]::Replace($out, $Context.MacRegex, $Context.MacReplace)
        $preserve = $Context.PreserveDrive
        $driveReplace = $Context.DriveReplace
        $out = [regex]::Replace($out, $Context.DriveRegex, {
                param($match)
                if ($preserve -ne [char]0 -and ([char]$match.Value[0] -eq $preserve)) {
                    return $match.Value
                }
                return $driveReplace
            })
        return $out
    }

    if ($Value -is [System.Collections.IDictionary]) {
        if ($Visited.Contains($Value)) { return $Value }
        [void]$Visited.Add($Value)
        $out = [ordered]@{}
        foreach ($k in $Value.Keys) {
            $out[$k] = Edit-RedactedValue -Value $Value[$k] -Context $Context -Visited $Visited
        }
        return $out
    }

    if ($Value -is [array] -or $Value -is [System.Collections.IList]) {
        if ($Visited.Contains($Value)) { return $Value }
        [void]$Visited.Add($Value)
        return @($Value | ForEach-Object { Edit-RedactedValue -Value $_ -Context $Context -Visited $Visited })
    }

    if ($Value -is [pscustomobject]) {
        if ($Visited.Contains($Value)) { return $Value }
        [void]$Visited.Add($Value)
        $props = [ordered]@{}
        foreach ($p in $Value.PSObject.Properties) {
            $props[$p.Name] = Edit-RedactedValue -Value $p.Value -Context $Context -Visited $Visited
        }
        return [pscustomobject]$props
    }

    return $Value
}
