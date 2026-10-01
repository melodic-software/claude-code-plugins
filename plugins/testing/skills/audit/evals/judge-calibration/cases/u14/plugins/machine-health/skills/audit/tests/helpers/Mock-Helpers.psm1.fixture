#Requires -Version 7.4
<#
.SYNOPSIS
Reusable mock factories for machine-health Pester tests.

.DESCRIPTION
Each New-Mock* function returns a PSCustomObject shaped like the corresponding
real Win32 / MSFT class. Property names match what the skill's checks read --
adding a property here that doesn't appear in the real class is a design smell.

These factories exist so tests consistently use the same object shapes without
copy-pasting [pscustomobject]@{} blobs.
#>

function New-MockVolume {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [char] $DriveLetter = [char]0,
        [ValidateSet('NTFS', 'ReFS', 'FAT32', 'exFAT', '')] [string] $FileSystem = 'NTFS',
        [string] $FileSystemLabel = '',
        [ValidateSet('Fixed', 'Removable', 'Network', 'CD-ROM')] [string] $DriveType = 'Fixed',
        [double] $SizeGB = 500,
        [double] $FreeGB = 100,
        [string] $UniqueId = '\\?\Volume{00000000-0000-0000-0000-000000000000}\'
    )
    [pscustomobject]@{
        DriveLetter     = if ($DriveLetter -eq [char]0) { $null } else { $DriveLetter }
        FileSystem      = $FileSystem
        FileSystemLabel = $FileSystemLabel
        DriveType       = $DriveType
        Size            = [long]($SizeGB * 1GB)
        SizeRemaining   = [long]($FreeGB * 1GB)
        UniqueId        = $UniqueId
    }
}

function New-MockPartition {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateSet('Basic', 'System', 'Reserved', 'Recovery', 'ESP', 'MSR', 'IFS', 'Unknown')]
        [string] $Type = 'Basic',
        [char] $DriveLetter = [char]0,
        [int] $PartitionNumber = 1,
        [int] $DiskNumber = 0,
        [string] $UniqueId = '{00000000-0000-0000-0000-000000000000}'
    )
    [pscustomobject]@{
        Type            = $Type
        DriveLetter     = if ($DriveLetter -eq [char]0) { $null } else { $DriveLetter }
        PartitionNumber = $PartitionNumber
        DiskNumber      = $DiskNumber
        UniqueId        = $UniqueId
    }
}

function New-MockPhysicalDisk {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $FriendlyName = 'Mock NVMe',
        [ValidateSet('SSD', 'HDD', 'SCM', 'Unspecified')] [string] $MediaType = 'SSD',
        [ValidateSet('Healthy', 'Warning', 'Unhealthy', 'Unknown')] [string] $HealthStatus = 'Healthy',
        [string[]] $OperationalStatus = @('OK')
    )
    [pscustomobject]@{
        FriendlyName      = $FriendlyName
        MediaType         = $MediaType
        HealthStatus      = $HealthStatus
        OperationalStatus = $OperationalStatus
    }
}

function New-MockReliabilityCounter {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [int] $Temperature = 35,
        [int] $TemperatureMax = 70,
        [int] $Wear = 0,
        [long] $ReadErrorsTotal = 0,
        [long] $WriteErrorsTotal = 0
    )
    [pscustomobject]@{
        Temperature      = $Temperature
        TemperatureMax   = $TemperatureMax
        Wear             = $Wear
        ReadErrorsTotal  = $ReadErrorsTotal
        WriteErrorsTotal = $WriteErrorsTotal
    }
}

function New-MockService {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [string] $DisplayName = '',
        [ValidateSet('Running', 'Stopped', 'Paused', 'StartPending', 'StopPending')]
        [string] $Status = 'Running',
        [ValidateSet('Automatic', 'AutomaticDelayedStart', 'Manual', 'Disabled', 'Boot', 'System')]
        [string] $StartType = 'Automatic'
    )
    [pscustomobject]@{
        Name        = $Name
        DisplayName = if ($DisplayName) { $DisplayName } else { $Name }
        Status      = $Status
        StartType   = $StartType
    }
}

function New-MockEventLogRecord {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $ProviderName,
        [Parameter(Mandatory)] [int] $Id,
        [ValidateSet('Critical', 'Error', 'Warning', 'Information', 'Verbose')]
        [string] $LevelDisplayName = 'Error',
        [datetime] $TimeCreated = (Get-Date),
        [string] $Message = '(mock message)'
    )
    [pscustomobject]@{
        ProviderName     = $ProviderName
        Id               = $Id
        LevelDisplayName = $LevelDisplayName
        TimeCreated      = $TimeCreated
        Message          = $Message
    }
}

function New-MockDefenderComputerStatus {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [int] $AntivirusSignatureAge = 1,
        [bool] $RealTimeProtectionEnabled = $true,
        [bool] $IsTamperProtected = $true,
        [bool] $AMServiceEnabled = $true,
        [bool] $AntispywareEnabled = $true,
        [string] $AMRunningMode = 'Normal',
        [datetime] $QuickScanEndTime = (Get-Date).AddDays(-1),
        [datetime] $FullScanEndTime = (Get-Date).AddDays(-7)
    )
    [pscustomobject]@{
        AntivirusSignatureAge     = $AntivirusSignatureAge
        RealTimeProtectionEnabled = $RealTimeProtectionEnabled
        IsTamperProtected         = $IsTamperProtected
        AMServiceEnabled          = $AMServiceEnabled
        AntispywareEnabled        = $AntispywareEnabled
        AMRunningMode             = $AMRunningMode
        QuickScanEndTime          = $QuickScanEndTime
        FullScanEndTime           = $FullScanEndTime
    }
}

function New-MockBattery {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $Name = 'Mock Battery',
        [string] $Chemistry = 'LIon',
        [int] $Status = 2,
        [int] $EstimatedChargeRemaining = 100
    )
    [pscustomobject]@{
        Name                     = $Name
        Chemistry                = $Chemistry
        Status                   = $Status
        EstimatedChargeRemaining = $EstimatedChargeRemaining
    }
}

function New-MockDriver {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $DeviceName,
        [string] $DriverVersion = '1.0.0.0',
        [datetime] $DriverDate = (Get-Date).AddYears(-1),
        [string] $Manufacturer = 'Mock Vendor',
        [bool] $IsSigned = $true
    )
    [pscustomobject]@{
        DeviceName    = $DeviceName
        DriverVersion = $DriverVersion
        DriverDate    = $DriverDate
        Manufacturer  = $Manufacturer
        IsSigned      = $IsSigned
    }
}

function New-MockReliabilityStabilityMetric {
    # Shape matches Win32_ReliabilityStabilityMetrics output.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [datetime] $TimeGenerated = (Get-Date).Date,
        [double] $SystemStabilityIndex = 9.5
    )
    [pscustomobject]@{
        TimeGenerated        = $TimeGenerated
        SystemStabilityIndex = $SystemStabilityIndex
    }
}

function New-MockReliabilityRecord {
    # Shape matches Win32_ReliabilityRecords output.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $SourceName = 'Application Error',
        [int] $EventIdentifier = 1000,
        [string] $ProductName = 'MockApp',
        [datetime] $TimeGenerated = (Get-Date).AddHours(-1),
        [string] $Message = '(mock crash)'
    )
    [pscustomobject]@{
        SourceName      = $SourceName
        EventIdentifier = $EventIdentifier
        ProductName     = $ProductName
        TimeGenerated   = $TimeGenerated
        Message         = $Message
    }
}

function New-MockWinGetPackage {
    # Shape matches Microsoft.WinGet.Client 1.12+ Get-WinGetPackage output.
    # IsUpdateAvailable is the boolean gate the check filters on; AvailableVersions
    # is newest-first. Tests that mock Get-WinGetPackage itself use this factory.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Id,
        [string] $InstalledVersion = '1.0.0',
        [string[]] $AvailableVersions = @('1.1.0'),
        [string] $Source = 'winget',
        [bool] $IsUpdateAvailable = $true
    )
    [pscustomobject]@{
        Name              = $Name
        Id                = $Id
        InstalledVersion  = $InstalledVersion
        AvailableVersions = $AvailableVersions
        Source            = $Source
        IsUpdateAvailable = $IsUpdateAvailable
    }
}

function New-MachineHealthTempDir {
    # Creates a uniquely-named scratch directory under the system temp root and
    # returns its path. Centralizes the pattern repeated across tests that need
    # a per-test workspace (egress logs, fake history dirs, snapshot fixtures).
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Prefix = 'machine-health-test')
    $tmpRoot = [System.IO.Path]::GetTempPath()
    $path = Join-Path $tmpRoot ("$Prefix-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Remove-MachineHealthTempDir {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param([Parameter(Mandatory)] [string] $Path)
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        if ($PSCmdlet.ShouldProcess($Path, 'Remove temp directory')) {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Export-ModuleMember -Function @(
    'New-MachineHealthTempDir'
    'New-MockBattery'
    'New-MockDefenderComputerStatus'
    'New-MockDriver'
    'New-MockEventLogRecord'
    'New-MockPartition'
    'New-MockPhysicalDisk'
    'New-MockReliabilityCounter'
    'New-MockReliabilityRecord'
    'New-MockReliabilityStabilityMetric'
    'New-MockService'
    'New-MockVolume'
    'New-MockWinGetPackage'
    'Remove-MachineHealthTempDir'
)
