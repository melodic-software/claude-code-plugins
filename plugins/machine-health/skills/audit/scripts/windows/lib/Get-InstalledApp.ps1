#Requires -Version 7.4

<#
.SYNOPSIS
Lists installed apps from the three Uninstall keys and the user's packaged apps.

.DESCRIPTION
Returns { ReadState, Apps }, each app
{ Key, Name, Kind, InstallDate, InstallDir, ExePath, PackageFamilyName }:

  Key         : the Uninstall subkey name, or the package family name
  Kind        : win32 | store
  InstallDate : the recorded install date, or $null
  InstallDir  : InstallLocation without quotes or a trailing separator, or $null
  ExePath     : the .exe that DisplayIcon names, without quotes or an icon index,
                or $null

An Uninstall entry counts when it has a DisplayName, is not a SystemComponent,
and is not an update to another entry. A package counts when it is not a
framework, resource or system-signed package. The Windows Installer's WMI
product class is never queried: enumerating it can start installer repairs.

ReadState is ok when every source read; otherwise the first failing source's
state, with the apps the other sources returned.
#>

. (Join-Path $PSScriptRoot 'New-FindingItem.ps1')

$script:UninstallKey = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
)

function Get-InstalledApp {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $apps = [System.Collections.Generic.List[pscustomobject]]::new()
    $states = [System.Collections.Generic.List[string]]::new()

    foreach ($root in $script:UninstallKey) {
        try {
            foreach ($subkey in @(Get-ChildItem -LiteralPath $root -ErrorAction Stop)) {
                $values = Get-ItemProperty -LiteralPath $subkey.PSPath -ErrorAction SilentlyContinue
                $app = ConvertFrom-UninstallEntry -KeyName $subkey.PSChildName -Values $values
                if ($app) { $apps.Add($app) }
            }
            $states.Add('ok')
        } catch [System.Management.Automation.ItemNotFoundException] {
            $states.Add('absent')
        } catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
            $states.Add('denied')
        } catch {
            Write-Verbose "Get-InstalledApp: $root unreadable. $($_.Exception.Message)"
            $states.Add('error')
        }
    }

    try {
        $packages = @(Get-AppxPackage -ErrorAction Stop | Where-Object {
                -not $_.IsFramework -and -not $_.IsResourcePackage -and [string]$_.SignatureKind -ne 'System'
            })
        foreach ($package in $packages) {
            $apps.Add([pscustomobject]@{
                    Key               = $package.PackageFamilyName
                    Name              = $package.Name
                    Kind              = 'store'
                    InstallDate       = $null
                    InstallDir        = $null
                    ExePath           = $null
                    PackageFamilyName = $package.PackageFamilyName
                })
        }
        $states.Add('ok')
    } catch {
        Write-Verbose "Get-InstalledApp: Get-AppxPackage failed. $($_.Exception.Message)"
        $states.Add('error')
    }

    $failed = @($states | Where-Object { -not (Test-ReadStateUsable $_) })
    $state = if ($failed.Count -gt 0) { $failed[0] } else { 'ok' }
    return [pscustomobject]@{ ReadState = $state; Apps = $apps.ToArray() }
}

function ConvertFrom-UninstallEntry {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string] $KeyName,
        [AllowNull()] $Values
    )

    if ($null -eq $Values) { return $null }
    $get = { param($name) $p = $Values.PSObject.Properties[$name]; if ($p) { $p.Value } else { $null } }

    $name = [string](& $get 'DisplayName')
    if ([string]::IsNullOrWhiteSpace($name)) { return $null }
    if ((& $get 'SystemComponent') -eq 1) { return $null }
    if (& $get 'ParentKeyName') { return $null }

    $installDate = $null
    $rawDate = [string](& $get 'InstallDate')
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParseExact($rawDate, 'yyyyMMdd', [cultureinfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
        $installDate = $parsed
    }

    $installDir = ([string](& $get 'InstallLocation')).Trim().Trim('"').TrimEnd('\')
    $exePath = (([string](& $get 'DisplayIcon')).Trim() -replace ',\s*-?\d+$', '').Trim('"')
    if ($exePath -notmatch '\.exe$') { $exePath = '' }

    return [pscustomobject]@{
        Key               = $KeyName
        Name              = $name.Trim()
        Kind              = 'win32'
        InstallDate       = $installDate
        InstallDir        = $installDir ? $installDir : $null
        ExePath           = $exePath ? $exePath : $null
        PackageFamilyName = $null
    }
}
