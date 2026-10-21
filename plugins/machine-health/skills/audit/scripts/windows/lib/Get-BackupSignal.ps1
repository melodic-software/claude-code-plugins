#Requires -Version 7.4

<#
.SYNOPSIS
Read every backup signal on the machine and return one source record per signal.

.DESCRIPTION
Each source's State is present | absent | needs-admin | unknown:

  system-image    Microsoft-Windows-Backup channel by numeric event id, read
                  unelevated: 4 success, 14 completed, 7 completed with errors,
                  5/8/9 failed, canceled, VSS failure. LastSuccess is the newest
                  event 4's BackupTime. No events at all is unknown, never absent
                  (whether a Windows 11 client job logs there is unverified).
                  Elevated only: wbadmin's exit code and the count of
                  version-identifier-shaped lines; no label text is read, and a
                  zero count settles nothing.
  restore-points  CIM root/default SystemRestore, elevated only. A value that
                  is not a restore point object (a string such as an error text)
                  is not counted.
  file-history    a Config*.xml file in the user's File History configuration folder.
  windows-backup  record count of the Windows Backup app's own log.
  onedrive-kfm    Known Folder Move opt-in values under the OneDrive policy keys.

Message text is never read; event ids, XML data fields and counts are.

Each record: Source, State, LastSuccess (ISO or null), LastResultEvent (int or
null), Signal, Basis (one-line label naming the signal), Count (restore points,
or wbadmin version identifiers; null when not read).
#>

. (Join-Path $PSScriptRoot 'Invoke-NativeCommand.ps1')

function Get-BackupSignal {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)] [bool] $Elevated
    )

    return @(
        Get-SystemImageSignal -Elevated $Elevated
        Get-RestorePointSignal -Elevated $Elevated
        Get-FileHistorySignal
        Get-WindowsBackupSignal
        Get-KnownFolderMoveSignal
    )
}

function New-BackupSource {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure constructor: builds and returns an object, changes no system state.')]
    param(
        [Parameter(Mandatory = $true)] [string] $Source,
        [Parameter(Mandatory = $true)] [ValidateSet('present', 'absent', 'needs-admin', 'unknown')] [string] $State,
        [Parameter(Mandatory = $true)] [string] $Signal,
        [Parameter(Mandatory = $true)] [string] $Basis,
        [AllowNull()] [string] $LastSuccess = $null,
        [AllowNull()] $LastResultEvent = $null,
        [AllowNull()] $Count = $null
    )
    return [pscustomobject]@{
        Source          = $Source
        State           = $State
        LastSuccess     = $LastSuccess ? $LastSuccess : $null
        LastResultEvent = $LastResultEvent
        Signal          = $Signal
        Basis           = $Basis
        Count           = $Count
    }
}

function Get-SystemImageSignal {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory = $true)] [bool] $Elevated)

    $successIds = @(4, 14, 7)
    $events = @()
    $eventsRead = $true
    try {
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Backup'; Id = 4, 5, 7, 8, 9, 14 } `
                -ErrorAction Stop | Sort-Object TimeCreated -Descending)
    } catch {
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*' -and
            $_.FullyQualifiedErrorId -notlike 'NoMatchingLogsFound*') { $eventsRead = $false }
    }

    $count = $null
    $exitCode = $null
    if ($Elevated) {
        $run = Invoke-NativeCommand -Name 'wbadmin' -ArgumentList @('get', 'versions')
        if ($run.status -in 'Ok', 'NonZero') {
            $exitCode = $run.exit_code
            $count = @([regex]::Matches($run.output, '\d{2}/\d{2}/\d{4}-\d{2}:\d{2}')).Count
        }
    }

    if ($events.Count -gt 0) {
        $newestSuccess = $events | Where-Object { $_.Id -eq 4 } | Select-Object -First 1
        $lastSuccess = $newestSuccess ? (Get-BackupEventTime -Record $newestSuccess) : $null
        $succeeded = @($events | Where-Object { $_.Id -in $successIds }).Count -gt 0
        return New-BackupSource -Source 'system-image' -State ($succeeded ? 'present' : 'absent') `
            -Signal 'backup-event' -LastSuccess $lastSuccess -LastResultEvent $events[0].Id -Count $count `
            -Basis ($succeeded ? 'Backup channel success event' : 'Backup channel shows only failed runs')
    }
    if ($null -ne $count -and $count -gt 0) {
        return New-BackupSource -Source 'system-image' -State 'present' -Signal 'wbadmin-count' -Count $count `
            -Basis "wbadmin exit $exitCode, $count version identifier(s)"
    }
    $basis = $eventsRead ? 'no Backup events (emission on Windows 11 unverified)' : 'Backup channel unreadable'
    if ($null -ne $count) { $basis += "; wbadmin exit $exitCode, no version identifier" }
    return New-BackupSource -Source 'system-image' -State 'unknown' -Signal 'backup-event' -Count $count -Basis $basis
}

function Get-BackupEventTime {
    <#
    .SYNOPSIS
    The event's BackupTime data field as ISO UTC, falling back to the event time.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] $Record)

    $raw = try {
        ([xml]$Record.ToXml()).Event.EventData.Data | Where-Object { $_.Name -eq 'BackupTime' } |
            Select-Object -First 1 -ExpandProperty '#text'
    } catch { $null }
    $parsed = [datetime]::MinValue
    $fileTime = [long]0
    if ($raw -and [datetime]::TryParse($raw, [cultureinfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$parsed)) {
        return $parsed.ToString('o')
    }
    if ($raw -and [long]::TryParse($raw, [ref]$fileTime)) {
        return [datetime]::FromFileTimeUtc($fileTime).ToString('o')
    }
    return $Record.TimeCreated.ToUniversalTime().ToString('o')
}

function Get-RestorePointSignal {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory = $true)] [bool] $Elevated)

    if (-not $Elevated) {
        return New-BackupSource -Source 'restore-points' -State 'needs-admin' -Signal 'cim' `
            -Basis 'restore points are readable elevated only'
    }
    try {
        $read = @(Get-CimInstance -Namespace 'root/default' -ClassName 'SystemRestore' -ErrorAction Stop)
    } catch {
        return New-BackupSource -Source 'restore-points' -State 'unknown' -Signal 'cim' -Basis 'restore point read failed'
    }
    if (@($read | Where-Object { $_ -is [string] }).Count -gt 0) {
        return New-BackupSource -Source 'restore-points' -State 'unknown' -Signal 'cim' `
            -Basis 'restore point read returned text, not restore points'
    }
    return New-BackupSource -Source 'restore-points' -State ($read.Count -gt 0 ? 'present' : 'absent') `
        -Signal 'cim' -Count $read.Count -Basis "$($read.Count) restore point(s)"
}

function Get-FileHistorySignal {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $folder = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\FileHistory\Configuration'
    try {
        $configs = (Test-Path -LiteralPath $folder) ?
            @(Get-ChildItem -LiteralPath $folder -Filter 'Config*.xml' -File -ErrorAction Stop) : @()
    } catch {
        return New-BackupSource -Source 'file-history' -State 'unknown' -Signal 'config-folder' `
            -Basis 'File History configuration folder unreadable'
    }
    return New-BackupSource -Source 'file-history' -State ($configs.Count -gt 0 ? 'present' : 'absent') `
        -Signal 'config-folder' -Basis ($configs.Count -gt 0 ? 'File History configured' : 'no File History configuration')
}

function Get-WindowsBackupSignal {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $basis = 'undocumented event log count'
    try {
        $records = [long](Get-WinEvent -ListLog 'Microsoft-Windows-UserSettingsBackup-Orchestrator/Operational' `
                -ErrorAction Stop).RecordCount
    } catch {
        $state = $_.FullyQualifiedErrorId -like 'NoMatchingLogsFound*' ? 'absent' : 'unknown'
        return New-BackupSource -Source 'windows-backup' -State $state -Signal 'log-count' -Basis $basis
    }
    return New-BackupSource -Source 'windows-backup' -State ($records -gt 0 ? 'present' : 'absent') `
        -Signal 'log-count' -Count $records -Basis $basis
}

function Get-KnownFolderMoveSignal {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $optIn = @('KFMSilentOptIn', 'KFMSilentOptInWithNotification', 'KFMSilentOptInDesktop',
        'KFMSilentOptInDocuments', 'KFMSilentOptInPictures', 'KFMOptInWithWizard')
    $found = [System.Collections.Generic.List[string]]::new()
    foreach ($hive in 'HKLM', 'HKCU') {
        $key = "${hive}:\SOFTWARE\Policies\Microsoft\OneDrive"
        try {
            if (-not (Test-Path -LiteralPath $key)) { continue }
            $names = @((Get-Item -LiteralPath $key -ErrorAction Stop).Property)
        } catch {
            return New-BackupSource -Source 'onedrive-kfm' -State 'unknown' -Signal 'policy-key' `
                -Basis 'OneDrive policy key unreadable'
        }
        foreach ($n in $names) { if ($n -in $optIn) { $found.Add("$hive $n") } }
    }
    return New-BackupSource -Source 'onedrive-kfm' -State ($found.Count -gt 0 ? 'present' : 'absent') `
        -Signal 'policy-key' -Basis ($found.Count -gt 0 ? "Known Folder Move policy: $($found -join ', ')" :
            'no Known Folder Move policy value')
}
