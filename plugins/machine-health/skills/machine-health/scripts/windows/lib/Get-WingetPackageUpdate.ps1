#Requires -Version 7.4

<#
.SYNOPSIS
Returns pending winget upgrades as structured records wrapped in a result tuple.

.DESCRIPTION
Two-path implementation:

1. Preferred: Microsoft.WinGet.Client PowerShell module (v1.12+). The
   authoritative cmdlet is Get-WinGetPackage; update candidates are filtered
   with the IsUpdateAvailable property. (The previous design targeted a
   Get-WinGetPackageUpdate cmdlet that does not exist in the module --
   verified empirically against 1.12.440. Calling it throws
   CommandNotFoundException and the wrapper fell through to text parsing
   silently.) This path is localization-safe and version-aware.

2. Fallback: parse the fixed-width text output of `winget upgrade`.
   Localization-fragile and breaks on non-English Windows. Used only when
   the module isn't installed but the winget CLI is on PATH.

Return contract: always a hashtable `@{ upgrades = [array|$null]; error = [string|$null] }`.
- Success (any count, including 0): upgrades is an array, error is $null.
- Failure: upgrades is $null, error names the specific failure mode. Callers
  surface error to users instead of collapsing every $null to a generic
  "winget not available" message.

Tests mock this wrapper to control upgrade data without installing winget
or the module.
#>

function ConvertFrom-WingetTextOutput {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]] $Lines
    )

    $headerIdx = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*Name\s+Id\s+Version\s+Available') {
            $headerIdx = $i
            break
        }
    }
    if ($headerIdx -lt 0) { return @() }

    $header = $Lines[$headerIdx]
    $idxId = $header.IndexOf('Id')
    $idxVer = $header.IndexOf('Version')
    $idxAvail = $header.IndexOf('Available')
    $idxSource = $header.IndexOf('Source')

    $items = [System.Collections.Generic.List[pscustomobject]]::new()
    for ($i = $headerIdx + 2; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match 'upgrades available') { break }
        if ($line.Length -lt $idxVer) { continue }

        try {
            $name = $line.Substring(0, $idxId).Trim()
            $ident = if ($line.Length -ge $idxVer) {
                $line.Substring($idxId, $idxVer - $idxId).Trim()
            } else { '' }
            $ver = if ($line.Length -ge $idxAvail) {
                $line.Substring($idxVer, $idxAvail - $idxVer).Trim()
            } else { '' }
            $avail = if ($idxSource -gt 0 -and $line.Length -ge $idxSource) {
                $line.Substring($idxAvail, $idxSource - $idxAvail).Trim()
            } else { $line.Substring($idxAvail).Trim() }
            $src = if ($idxSource -gt 0 -and $line.Length -gt $idxSource) {
                $line.Substring($idxSource).Trim()
            } else { '' }

            if ($name -and $ident) {
                $items.Add([pscustomobject]@{
                        name              = $name
                        id                = $ident
                        current_version   = $ver
                        available_version = $avail
                        source            = $src
                    })
            }
        } catch {
            Write-Verbose "ConvertFrom-WingetTextOutput: row parse failed. $($_.Exception.Message)"
        }
    }
    return $items.ToArray()
}

function New-WingetUpgradeResult {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowNull()] [object[]] $Upgrades,
        [AllowNull()] [string] $ErrorMessage
    )
    return @{ upgrades = $Upgrades; error = $ErrorMessage }
}

function Get-WingetPackageUpdate {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    # Preferred path: Microsoft.WinGet.Client module.
    $module = Get-Module -ListAvailable Microsoft.WinGet.Client -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($module) {
        try {
            Import-Module Microsoft.WinGet.Client -ErrorAction Stop
            # Get-WinGetPackage returns installed packages; IsUpdateAvailable
            # is the boolean gate for "upgrade is pending". AvailableVersions
            # is an array ordered newest-first.
            $candidates = @(Get-WinGetPackage -ErrorAction Stop |
                    Where-Object { $_.IsUpdateAvailable })
            $mapped = @($candidates | ForEach-Object {
                    [pscustomobject]@{
                        name              = $_.Name
                        id                = $_.Id
                        current_version   = $_.InstalledVersion
                        available_version = $_.AvailableVersions?[0]
                        source            = $_.Source
                    }
                })
            return (New-WingetUpgradeResult -Upgrades $mapped -ErrorMessage $null)
        } catch {
            $msg = "Microsoft.WinGet.Client module path failed: $($_.Exception.Message)"
            Write-Verbose "Get-WingetPackageUpdate: $msg"
            # Fall through to text-parse fallback; the error is only surfaced
            # if the fallback also fails.
        }
    }

    # Fallback: text parse.
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        $err = if ($module) {
            'Microsoft.WinGet.Client module present but failed; winget CLI also not on PATH.'
        } else {
            'winget CLI not on PATH and Microsoft.WinGet.Client module not installed.'
        }
        return (New-WingetUpgradeResult -Upgrades $null -ErrorMessage $err)
    }

    try {
        $raw = winget upgrade --include-unknown --accept-source-agreements 2>&1 | Out-String
        $lines = $raw -split "`r?`n"
        $parsed = ConvertFrom-WingetTextOutput -Lines $lines
        return (New-WingetUpgradeResult -Upgrades @($parsed) -ErrorMessage $null)
    } catch {
        $msg = "winget text-parse fallback failed: $($_.Exception.Message)"
        Write-Verbose "Get-WingetPackageUpdate: $msg"
        return (New-WingetUpgradeResult -Upgrades $null -ErrorMessage $msg)
    }
}
