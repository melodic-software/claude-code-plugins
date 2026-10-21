#Requires -Version 7.4

<#
.SYNOPSIS
Reads the current user's Explorer UserAssist launch records.

.DESCRIPTION
Returns { ReadState, Entries }, each entry { Name, Path, LastRun }:

  Name    : the decoded value name: an executable or shortcut path, often led
            by a known-folder GUID, or a packaged app's AppUserModelID
            (PackageFamilyName!AppId)
  Path    : Name with a leading known-folder GUID expanded to the folder's
            path; Name itself when it is already a rooted path; else $null
  LastRun : the last-launch time in UTC, or $null when the record holds none

Value names are ROT13-encoded. A launch record is a value of
$script:UserAssistRecordLength bytes holding a FILETIME at
$script:UserAssistLastRunOffset; values of any other length are bookkeeping and
are skipped. The run count is never returned: it is not evidence of when an app
was last opened.

ReadState is absent when no Count key holds a value, and error when values
exist but none has the record length, which means the layout this adapter
decodes no longer holds. Microsoft does not document the layout.
#>

$script:UserAssistRoot = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist'
$script:UserAssistRecordLength = 72
$script:UserAssistLastRunOffset = 60
$script:UserAssistSkippedProperty = @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')

# Known-folder GUID -> the Environment.SpecialFolder it names, plus a sub-path
# where the folder has no SpecialFolder of its own.
$script:UserAssistKnownFolder = @{
    '{6D809377-6AF0-444B-8957-A3773F02200E}' = @('ProgramFiles', '')
    '{7C5A40EF-A0FB-4BFC-874A-C0F2E0B9FA8E}' = @('ProgramFilesX86', '')
    '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}' = @('System', '')
    '{D65231B0-B2F1-4857-A4CE-A8E7C6EA7D27}' = @('SystemX86', '')
    '{F38BF404-1D43-42F2-9305-67DE0B28FC23}' = @('Windows', '')
    '{F1B32785-6FBA-4FCF-9D55-7B8E7F157091}' = @('LocalApplicationData', '')
    '{5CD7AEE2-2219-4A67-B85D-6C9CE15660CB}' = @('LocalApplicationData', 'Programs')
    '{3EB685DB-65F9-4CF6-A03A-E3EF65729F3D}' = @('ApplicationData', '')
    '{5E6C858F-0E22-4760-9AFE-EA3317B67173}' = @('UserProfile', '')
    '{0139D44E-6AFE-49F2-8690-3DAFCAE6FFB8}' = @('CommonPrograms', '')
    '{A77F5D77-2E2B-44C3-A6A2-ABA601054A51}' = @('Programs', '')
}

function Read-UserAssist {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $entries = [System.Collections.Generic.List[pscustomobject]]::new()
    $valueCount = 0
    try {
        $guidKeys = @(Get-ChildItem -LiteralPath $script:UserAssistRoot -ErrorAction Stop)
        foreach ($guidKey in $guidKeys) {
            try {
                $values = Get-ItemProperty -LiteralPath (Join-Path $guidKey.PSPath 'Count') -ErrorAction Stop
            } catch [System.Management.Automation.ItemNotFoundException] {
                continue
            }
            foreach ($property in @($values | ForEach-Object { $_.PSObject.Properties })) {
                if ($property.Name -in $script:UserAssistSkippedProperty) { continue }
                $valueCount++
                if ($property.Value -isnot [byte[]] -or $property.Value.Length -ne $script:UserAssistRecordLength) {
                    continue
                }
                $name = ConvertFrom-Rot13 -Text $property.Name
                $entries.Add([pscustomobject]@{
                        Name    = $name
                        Path    = Resolve-UserAssistPath -Name $name
                        LastRun = ConvertFrom-UserAssistTime -Record $property.Value
                    })
            }
        }
    } catch [System.Management.Automation.ItemNotFoundException] {
        return [pscustomobject]@{ ReadState = 'absent'; Entries = @() }
    } catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
        return [pscustomobject]@{ ReadState = 'denied'; Entries = @() }
    } catch {
        Write-Verbose "Read-UserAssist: read failed. $($_.Exception.Message)"
        return [pscustomobject]@{ ReadState = 'error'; Entries = @() }
    }

    $state = if ($valueCount -eq 0) { 'absent' } elseif ($entries.Count -eq 0) { 'error' } else { 'ok' }
    return [pscustomobject]@{ ReadState = $state; Entries = $entries.ToArray() }
}

function ConvertFrom-Rot13 {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] [AllowEmptyString()] [string] $Text)

    $chars = $Text.ToCharArray()
    for ($i = 0; $i -lt $chars.Length; $i++) {
        $code = [int]$chars[$i]
        $base = if ($code -ge 97 -and $code -le 122) { 97 } elseif ($code -ge 65 -and $code -le 90) { 65 } else { 0 }
        if ($base) { $chars[$i] = [char]((($code - $base + 13) % 26) + $base) }
    }
    return [string]::new($chars)
}

function ConvertFrom-UserAssistTime {
    [CmdletBinding()]
    [OutputType([datetime])]
    param([Parameter(Mandatory = $true)] [byte[]] $Record)

    $fileTime = [BitConverter]::ToInt64($Record, $script:UserAssistLastRunOffset)
    if ($fileTime -le 0) { return $null }
    try { return [datetime]::FromFileTimeUtc($fileTime) } catch { return $null }
}

function Resolve-UserAssistPath {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] [string] $Name)

    if ($Name -match '^(\{[0-9A-Fa-f-]{36}\})\\(.+)$') {
        $folder = $script:UserAssistKnownFolder[$Matches[1].ToUpperInvariant()]
        if (-not $folder) { return $null }
        $base = Get-KnownFolderPath -Folder $folder[0]
        if (-not $base) { return $null }
        if ($folder[1]) { $base = [System.IO.Path]::Join($base, $folder[1]) }
        return [System.IO.Path]::Join($base, $Matches[2])
    }
    if ($Name -match '^[A-Za-z]:\\') { return $Name }
    return $null
}

function Get-KnownFolderPath {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] [string] $Folder)
    return [Environment]::GetFolderPath([Environment+SpecialFolder]$Folder)
}
