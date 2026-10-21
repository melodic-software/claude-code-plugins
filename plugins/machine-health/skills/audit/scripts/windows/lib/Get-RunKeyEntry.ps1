#Requires -Version 7.4

<#
.SYNOPSIS
Lists what one startup location starts at logon: a Run or RunOnce registry key,
or a Startup folder.

.DESCRIPTION
Returns { ReadState, Entries }, each entry { Kind, Scope, Name, Command }:

  Kind    : run | runonce | startup-folder
  Scope   : hkcu | hklm | hklm-wow64 (registry), user-folder | common-folder
  Name    : the registry value name, or the Startup-folder file name
  Command : the registry value data, or the Startup-folder file's full path

The keys and folders are read directly. A shortcut in a Startup folder is not
opened, so its target is not resolved; the shortcut path is the command.
Win32_StartupCommand is not used: it reports a location string per entry
rather than the scopes StartupApproved is keyed by.
#>

$script:RunKeyParent = @{
    'hkcu'       = 'HKCU:\Software\Microsoft\Windows\CurrentVersion'
    'hklm'       = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion'
    'hklm-wow64' = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion'
}

$script:StartupFolder = @{
    'user-folder'   = [Environment+SpecialFolder]::Startup
    'common-folder' = [Environment+SpecialFolder]::CommonStartup
}

# Get-ItemProperty adds the provider properties; '(default)' is the key's unnamed value, never an entry.
$script:RunKeySkippedProperty = @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider', '(default)')

function Get-RunKeyEntry {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('hkcu', 'hklm', 'hklm-wow64', 'user-folder', 'common-folder')]
        [string] $Scope,
        [ValidateSet('Run', 'RunOnce')]
        [string] $Key = 'Run'
    )

    $entries = [System.Collections.Generic.List[pscustomobject]]::new()
    $isFolder = $script:StartupFolder.ContainsKey($Scope)
    try {
        if ($isFolder) {
            $folder = Get-StartupFolderPath -Scope $Scope
            if (-not $folder) { return [pscustomobject]@{ ReadState = 'absent'; Entries = @() } }
            foreach ($file in @(Get-ChildItem -LiteralPath $folder -ErrorAction Stop | Where-Object { -not $_.PSIsContainer })) {
                $entries.Add([pscustomobject]@{
                        Kind = 'startup-folder'; Scope = $Scope; Name = $file.Name; Command = $file.FullName
                    })
            }
        } else {
            $values = Get-ItemProperty -LiteralPath (Join-Path $script:RunKeyParent[$Scope] $Key) -ErrorAction Stop
            foreach ($property in @($values | ForEach-Object { $_.PSObject.Properties })) {
                if ($property.Name -in $script:RunKeySkippedProperty) { continue }
                $entries.Add([pscustomobject]@{
                        Kind = $Key.ToLowerInvariant(); Scope = $Scope; Name = $property.Name; Command = [string]$property.Value
                    })
            }
        }
    } catch [System.Management.Automation.ItemNotFoundException] {
        return [pscustomobject]@{ ReadState = 'absent'; Entries = @() }
    } catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
        return [pscustomobject]@{ ReadState = 'denied'; Entries = @() }
    } catch {
        Write-Verbose "Get-RunKeyEntry: $Scope $Key unreadable. $($_.Exception.Message)"
        return [pscustomobject]@{ ReadState = 'error'; Entries = @() }
    }
    return [pscustomobject]@{ ReadState = 'ok'; Entries = $entries.ToArray() }
}

function Get-StartupFolderPath {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] [string] $Scope)
    return [Environment]::GetFolderPath($script:StartupFolder[$Scope])
}
