#Requires -Version 7.4

<#
.SYNOPSIS
Reads the two launch records only an elevated token can see: Prefetch and the
Background Activity Moderator (BAM).

.DESCRIPTION
Returns two records, { Source, ReadState, Entries }:

  prefetch : Entries { ExeName, LastRun }, the latest LastWriteTimeUtc per
             executable over the Prefetch folder's .pf files. The folder is
             listed unfiltered first: a standard token gets an empty filtered
             listing with no error, which would read as no launches. No .pf
             file is opened.
  bam      : Entries { ExeName, Path, LastRun } from the current user's BAM
             values; Path drops the \Device\HarddiskVolumeN prefix, so it is
             rooted at the volume without a drive letter.

Without elevation both report denied; why is the app-last-use row of
Get-ElevationMatrix.ps1.
#>

. (Join-Path $PSScriptRoot 'ConvertFrom-FileTimeBytes.ps1')

$script:BamUserSettings = 'HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings'
$script:BamDevicePrefix = '^\\Device\\HarddiskVolume\d+'

function Get-ElevatedAppEvidence {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    return @(
        Read-PrefetchEvidence
        Read-BamEvidence
    )
}

function Read-PrefetchEvidence {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $folder = [System.IO.Path]::Join($env:SystemRoot, 'Prefetch')
    try {
        $listing = @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction Stop)
    } catch [System.UnauthorizedAccessException] {
        return [pscustomobject]@{ Source = 'prefetch'; ReadState = 'denied'; Entries = @() }
    } catch [System.Management.Automation.ItemNotFoundException] {
        return [pscustomobject]@{ Source = 'prefetch'; ReadState = 'absent'; Entries = @() }
    } catch {
        Write-Verbose "Get-ElevatedAppEvidence: Prefetch unreadable. $($_.Exception.Message)"
        return [pscustomobject]@{ Source = 'prefetch'; ReadState = 'error'; Entries = @() }
    }

    # APP.EXE-0123ABCD.pf: the executable name, a dash, a path hash.
    $entries = @($listing | Where-Object { $_.Name -match '^(.+)-[0-9A-Fa-f]{8}\.pf$' } |
            Group-Object { ($_.Name -replace '-[0-9A-Fa-f]{8}\.pf$', '').ToLowerInvariant() } |
            ForEach-Object {
                [pscustomobject]@{
                    ExeName = $_.Name
                    LastRun = ($_.Group | Measure-Object -Property LastWriteTimeUtc -Maximum).Maximum
                }
            })
    $state = if ($entries.Count -gt 0) { 'ok' } else { 'absent' }
    return [pscustomobject]@{ Source = 'prefetch'; ReadState = $state; Entries = $entries }
}

function Read-BamEvidence {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    try {
        $values = Get-ItemProperty -LiteralPath "$script:BamUserSettings\$sid" -ErrorAction Stop
    } catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
        return [pscustomobject]@{ Source = 'bam'; ReadState = 'denied'; Entries = @() }
    } catch [System.Management.Automation.ItemNotFoundException] {
        return [pscustomobject]@{ Source = 'bam'; ReadState = 'absent'; Entries = @() }
    } catch {
        Write-Verbose "Get-ElevatedAppEvidence: BAM unreadable. $($_.Exception.Message)"
        return [pscustomobject]@{ Source = 'bam'; ReadState = 'error'; Entries = @() }
    }

    $entries = foreach ($property in @($values | ForEach-Object { $_.PSObject.Properties })) {
        if ($property.Name -notmatch $script:BamDevicePrefix) { continue }
        if ($property.Value -isnot [byte[]]) { continue }
        $lastRun = ConvertFrom-FileTimeBytes -Bytes $property.Value -Offset 0
        if (-not $lastRun) { continue }
        $path = $property.Name -replace $script:BamDevicePrefix, ''
        [pscustomobject]@{
            ExeName = [System.IO.Path]::GetFileName($path).ToLowerInvariant()
            Path    = $path
            LastRun = $lastRun
        }
    }
    $entries = @($entries)
    $state = if ($entries.Count -gt 0) { 'ok' } else { 'absent' }
    return [pscustomobject]@{ Source = 'bam'; ReadState = $state; Entries = $entries }
}
