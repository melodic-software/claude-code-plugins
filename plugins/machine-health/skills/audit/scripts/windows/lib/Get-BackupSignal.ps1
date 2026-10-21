#Requires -Version 7.4

<#
.SYNOPSIS
Read every backup signal on the machine and return one source record per signal.

.DESCRIPTION
The source list and what each state means for the check:
reference/windows/check-catalog.md section 27. Every read below takes its
channel, class, path, log or key from $BackupSignalSource.

Backup channel event ids: 4 success, 14 completed, 7 completed with errors,
5 failed, 8 canceled, 9 VSS failure. LastSuccess is the newest event 4's
BackupTime data field. Message text is never read; event ids, XML data fields
and counts are. wbadmin's output is read only as a count of version-id-shaped
lines.

Each record: Source, State (present | absent | needs-admin | unknown),
LastSuccess (ISO or null), LastResultEvent (int or null), Signal, Basis
(one-line label naming the signal), Count (restore points, or wbadmin version
ids; null when not read).
#>

. (Join-Path $PSScriptRoot 'Invoke-NativeCommand.ps1')

# Source ids, named once; checks read rows by these.
$script:BackupSourceId = [pscustomobject]@{
    SystemImage   = 'system-image'
    RestorePoints = 'restore-points'
    FileHistory   = 'file-history'
    WindowsBackup = 'windows-backup'
    OneDriveKfm   = 'onedrive-kfm'
}

# Where each signal is read; the check's commands list is built from these.
$script:BackupSignalSource = [pscustomobject]@{
    BackupChannel      = 'Microsoft-Windows-Backup'
    BackupEventIds     = @(4, 5, 7, 8, 9, 14)
    BackupSuccessIds   = @(4, 14, 7)
    BackupNewestId     = 4
    WbadminArguments   = @('get', 'versions')
    WbadminVersionId   = '\d{2}/\d{2}/\d{4}-\d{2}:\d{2}'
    RestoreNamespace   = 'root/default'
    RestoreClass       = 'SystemRestore'
    FileHistoryFolder  = 'Microsoft\Windows\FileHistory\Configuration'
    FileHistoryFilter  = 'Config*.xml'
    WindowsBackupLog   = 'Microsoft-Windows-UserSettingsBackup-Orchestrator/Operational'
    OneDrivePolicyKeys = @('HKLM:\SOFTWARE\Policies\Microsoft\OneDrive', 'HKCU:\SOFTWARE\Policies\Microsoft\OneDrive')
    KfmOptInValues     = @('KFMSilentOptIn', 'KFMSilentOptInWithNotification', 'KFMSilentOptInDesktop',
        'KFMSilentOptInDocuments', 'KFMSilentOptInPictures', 'KFMOptInWithWizard')
}

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

    $src = $script:BackupSignalSource
    $id = $script:BackupSourceId.SystemImage
    $events = @()
    $eventsRead = $true
    try {
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = $src.BackupChannel; Id = $src.BackupEventIds } `
                -ErrorAction Stop | Sort-Object TimeCreated -Descending)
    } catch {
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*' -and
            $_.FullyQualifiedErrorId -notlike 'NoMatchingLogsFound*') { $eventsRead = $false }
    }

    $count = $null
    $exitCode = $null
    if ($Elevated) {
        $run = Invoke-NativeCommand -Name 'wbadmin' -ArgumentList $src.WbadminArguments
        if ($run.status -in 'Ok', 'NonZero') {
            $exitCode = $run.exit_code
            $count = @([regex]::Matches($run.output, $src.WbadminVersionId)).Count
        }
    }

    if ($events.Count -gt 0) {
        $newestSuccess = $events | Where-Object { $_.Id -eq $src.BackupNewestId } | Select-Object -First 1
        $lastSuccess = $newestSuccess ? (Get-BackupEventTime -Record $newestSuccess) : $null
        $succeeded = @($events | Where-Object { $_.Id -in $src.BackupSuccessIds }).Count -gt 0
        return New-BackupSource -Source $id -State ($succeeded ? 'present' : 'absent') `
            -Signal 'backup-event' -LastSuccess $lastSuccess -LastResultEvent $events[0].Id -Count $count `
            -Basis ($succeeded ? 'Backup channel success event' : 'Backup channel shows only failed runs')
    }
    if ($null -ne $count -and $count -gt 0) {
        return New-BackupSource -Source $id -State 'present' -Signal 'wbadmin-count' -Count $count `
            -Basis "wbadmin exit $exitCode, $count version id(s)"
    }
    $basis = $eventsRead ? 'no Backup events (emission on Windows 11 unverified)' : 'Backup channel unreadable'
    if ($null -ne $count) { $basis += "; wbadmin exit $exitCode, no version id" }
    return New-BackupSource -Source $id -State 'unknown' -Signal 'backup-event' -Count $count -Basis $basis
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

    $src = $script:BackupSignalSource
    $id = $script:BackupSourceId.RestorePoints
    if (-not $Elevated) {
        return New-BackupSource -Source $id -State 'needs-admin' -Signal 'cim' `
            -Basis 'restore points are readable elevated only'
    }
    try {
        $read = @(Get-CimInstance -Namespace $src.RestoreNamespace -ClassName $src.RestoreClass -ErrorAction Stop)
    } catch {
        return New-BackupSource -Source $id -State 'unknown' -Signal 'cim' -Basis 'restore point read failed'
    }
    # A text value (an error string some hosts return as data) is not a restore point.
    if (@($read | Where-Object { $_ -is [string] }).Count -gt 0) {
        return New-BackupSource -Source $id -State 'unknown' -Signal 'cim' `
            -Basis 'restore point read returned text, not restore points'
    }
    return New-BackupSource -Source $id -State ($read.Count -gt 0 ? 'present' : 'absent') `
        -Signal 'cim' -Count $read.Count -Basis "$($read.Count) restore point(s)"
}

function Get-FileHistorySignal {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $src = $script:BackupSignalSource
    $id = $script:BackupSourceId.FileHistory
    $folder = Join-Path $env:LOCALAPPDATA $src.FileHistoryFolder
    try {
        $configs = (Test-Path -LiteralPath $folder) ?
            @(Get-ChildItem -LiteralPath $folder -Filter $src.FileHistoryFilter -File -ErrorAction Stop) : @()
    } catch {
        return New-BackupSource -Source $id -State 'unknown' -Signal 'config-folder' `
            -Basis 'File History configuration folder unreadable'
    }
    return New-BackupSource -Source $id -State ($configs.Count -gt 0 ? 'present' : 'absent') `
        -Signal 'config-folder' -Basis ($configs.Count -gt 0 ? 'File History configured' : 'no File History configuration')
}

function Get-WindowsBackupSignal {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $id = $script:BackupSourceId.WindowsBackup
    $basis = 'undocumented event log count'
    try {
        $records = [long](Get-WinEvent -ListLog $script:BackupSignalSource.WindowsBackupLog -ErrorAction Stop).RecordCount
    } catch {
        $state = $_.FullyQualifiedErrorId -like 'NoMatchingLogsFound*' ? 'absent' : 'unknown'
        return New-BackupSource -Source $id -State $state -Signal 'log-count' -Basis $basis
    }
    return New-BackupSource -Source $id -State ($records -gt 0 ? 'present' : 'absent') `
        -Signal 'log-count' -Count $records -Basis $basis
}

function Get-KnownFolderMoveSignal {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $src = $script:BackupSignalSource
    $id = $script:BackupSourceId.OneDriveKfm
    $found = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $src.OneDrivePolicyKeys) {
        try {
            if (-not (Test-Path -LiteralPath $key)) { continue }
            $names = @((Get-Item -LiteralPath $key -ErrorAction Stop).Property)
        } catch {
            return New-BackupSource -Source $id -State 'unknown' -Signal 'policy-key' `
                -Basis 'OneDrive policy key unreadable'
        }
        $hive = $key.Split(':')[0]
        foreach ($n in $names) { if ($n -in $src.KfmOptInValues) { $found.Add("$hive $n") } }
    }
    return New-BackupSource -Source $id -State ($found.Count -gt 0 ? 'present' : 'absent') `
        -Signal 'policy-key' -Basis ($found.Count -gt 0 ? "Known Folder Move policy: $($found -join ', ')" :
            'no Known Folder Move policy value')
}
