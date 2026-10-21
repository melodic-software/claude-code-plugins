#Requires -Version 7.4

<#
.SYNOPSIS
Report whether a folder is under a cloud sync root, where plugin state must not
be written.

.DESCRIPTION
A path is under a sync root when one of $env:OneDrive, $env:OneDriveConsumer or
$env:OneDriveCommercial is the path or one of its ancestors, or when the path or
an existing ancestor carries ReparsePoint plus a cloud attribute bit (0x40000
RECALL_ON_OPEN, 0x80000 PINNED, 0x100000 UNPINNED, 0x400000
RECALL_ON_DATA_ACCESS). The attribute half catches a folder moved into a sync
root without the variables pointing at it.

A path under a reparse point with no cloud bit (an ordinary junction or
symlink) is not flagged; it gets one warning naming that reparse point.

Returns { Path, Synced, Rule, Folder }: Rule names the matching variable or
attribute bit, Folder the sync root or flagged ancestor. Never throws for a path
that does not exist yet; callers decide what a synced path refuses.
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
    $plainReparse = $null
    for ($dir = [System.IO.DirectoryInfo]::new($full); $null -ne $dir; $dir = $dir.Parent) {
        if (-not $dir.Exists) { continue }
        $attributes = [int]$dir.Attributes
        if (($attributes -band $reparsePoint) -eq 0) { continue }
        foreach ($bit in $cloudBits) {
            if ($attributes -band $bit) {
                return (& $result ('ReparsePoint + cloud attribute 0x{0:X}' -f $bit) $dir.FullName.TrimEnd($separators))
            }
        }
        if ($null -eq $plainReparse) { $plainReparse = $dir.FullName.TrimEnd($separators) }
    }

    if ($null -ne $plainReparse) {
        Write-Warning ("Assert-StateBaseLocation: '$full' is under the reparse point '$plainReparse', " +
            'which carries no cloud attribute; not treated as a sync root.')
    }
    return (& $result $null $null)
}
