#Requires -Version 7.4

<#
.SYNOPSIS
Report whether a folder is under a cloud sync root, where plugin state must not
be written.

.DESCRIPTION
A path is flagged (Synced = $true) when one of $env:OneDrive,
$env:OneDriveConsumer or $env:OneDriveCommercial is the path or one of its
ancestors. Only this rule refuses state writes.

The path or an existing ancestor carrying ReparsePoint plus a cloud attribute
bit (0x40000 RECALL_ON_OPEN, 0x80000 PINNED, 0x100000 UNPINNED, 0x400000
RECALL_ON_DATA_ACCESS) gets one warning naming that folder and bit, and is not
flagged: a real OneDrive folder has been observed carrying ReparsePoint with no
cloud bit, so the attribute signal is not reliable enough to refuse on. A path
under a reparse point with no cloud bit (an ordinary junction or symlink) gets
one warning too.

Returns { Path, Synced, Rule, Folder }: Rule names the matching variable,
Folder the sync root. Never throws for a path that does not exist yet; callers
decide what a synced path refuses.
#>

function Assert-StateBaseLocation {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string] $Path
    )

    $separators = [char[]]@('\', '/')
    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd($separators)
    $result = { param($Rule, $Folder) [pscustomobject]@{ Path = $full; Synced = $null -ne $Rule; Rule = $Rule; Folder = $Folder } }

    foreach ($name in @('OneDrive', 'OneDriveConsumer', 'OneDriveCommercial')) {
        $root = [Environment]::GetEnvironmentVariable($name)
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        $root = [System.IO.Path]::GetFullPath($root).TrimEnd($separators)
        if ($full.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or
            $full.StartsWith("$root\", [StringComparison]::OrdinalIgnoreCase)) {
            return (& $result "`$env:$name" $root)
        }
    }

    $reparsePoint = [int][System.IO.FileAttributes]::ReparsePoint
    $cloudBits = @(0x40000, 0x80000, 0x100000, 0x400000)
    $cloudFolder = $null
    $cloudBit = $null
    $plainFolder = $null
    for ($dir = [System.IO.DirectoryInfo]::new($full); $null -ne $dir -and $null -eq $cloudFolder; $dir = $dir.Parent) {
        if (-not $dir.Exists) { continue }
        $attributes = [int]$dir.Attributes
        if (($attributes -band $reparsePoint) -eq 0) { continue }
        $cloudBit = $cloudBits | Where-Object { $attributes -band $_ } | Select-Object -First 1
        if ($null -ne $cloudBit) {
            $cloudFolder = $dir.FullName.TrimEnd($separators)
        } elseif ($null -eq $plainFolder) {
            $plainFolder = $dir.FullName.TrimEnd($separators)
        }
    }
    if ($null -ne $cloudFolder) {
        Write-Warning ("Assert-StateBaseLocation: '$full' is under '$cloudFolder', a reparse point carrying cloud " +
            ('attribute 0x{0:X}; it may be a sync root no OneDrive variable names.' -f $cloudBit))
    } elseif ($null -ne $plainFolder) {
        Write-Warning ("Assert-StateBaseLocation: '$full' is under the reparse point '$plainFolder', " +
            'which carries no cloud attribute; not treated as a sync root.')
    }
    return (& $result $null $null)
}
