#Requires -Version 7.4

<#
.SYNOPSIS
Folder-size adapter for storage-top-n: sizes the folders directly under each
root without hydrating a cloud file, and returns the top N per root.

.DESCRIPTION
The walk is a manual directory stack over DirectoryInfo.EnumerateFileSystemInfos
with RecurseSubdirectories off, so every descent is decided here:

 - A directory at or under a cloud sync root (Test-CloudSyncRoot) is never
   descended. It comes back as one folder entry with skip_reason
   'cloud-sync-root' and no size.
 - Any other reparse directory (junction, directory symlink) is never descended
   and is counted in skipped_reparse_dirs. No link is resolved.
 - AttributesToSkip is Offline | RECALL_ON_OPEN | RECALL_ON_DATA_ACCESS
   (0x441000), set explicitly so Hidden and System entries (AppData) are
   counted and placeholder entries are never seen.
 - A directory that cannot be listed is counted in inaccessible_count.
 - No enumerated file is opened. The one exception is the allocated-size pass,
   whose GetCompressedFileSizeW call opens a handle; it sees only files the skip
   let through, and never a file that is itself a reparse point, since opening
   a file symlink would reach its target.

One budget covers the scan and the allocated pass. The scan tests it before
each directory and each entry, the allocated pass before each file. A folder
the budget cuts keeps allocated_bytes $null, as does a folder over the
allocated file cap.
#>

if (-not ('MachineHealth.FolderSizeNative' -as [type])) {
    Add-Type -Namespace 'MachineHealth' -Name 'FolderSizeNative' -MemberDefinition @'
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern uint GetCompressedFileSizeW(string lpFileName, out uint lpFileSizeHigh);
'@
}

function New-ScanBudget {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure constructor: builds and returns an object, changes no system state.')]
    param(
        [Parameter(Mandatory = $true)] [ValidateRange('NonNegative')] [long] $Milliseconds
    )

    return [pscustomobject]@{
        Clock   = [System.Diagnostics.Stopwatch]::StartNew()
        LimitMs = $Milliseconds
    }
}

function Get-CloudSyncPrefix {
    <#
    .SYNOPSIS
    The set OneDrive variables, read at call time, as full paths without a
    trailing separator.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $prefixes = foreach ($name in @('OneDrive', 'OneDriveConsumer', 'OneDriveCommercial')) {
        $value = [System.Environment]::GetEnvironmentVariable($name)
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        [System.IO.Path]::GetFullPath($value).TrimEnd('\', '/')
    }
    return [string[]]@($prefixes | Select-Object -Unique)
}

function Test-CloudSyncRoot {
    <#
    .SYNOPSIS
    True when a directory is at or under a cloud sync root: a set OneDrive
    variable prefixes its path, or it carries ReparsePoint plus a cloud bit
    (RECALL_ON_OPEN 0x40000, PINNED 0x80000, UNPINNED 0x100000,
    RECALL_ON_DATA_ACCESS 0x400000).

    .DESCRIPTION
    Pure: the caller passes the attributes it already holds from enumeration,
    and the ancestors of a starting root are tested by calling this once per
    ancestor. A walk never reaches below a sync root, so a directory found by
    the walk needs only its own test.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [System.IO.FileAttributes] $Attributes,
        [AllowEmptyCollection()] [string[]] $Prefix = (Get-CloudSyncPrefix)
    )

    $full = $Path.TrimEnd('\', '/')
    foreach ($p in $Prefix) {
        if ($full.Equals($p, [System.StringComparison]::OrdinalIgnoreCase) -or
            $full.StartsWith($p + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    $bits = [long]$Attributes
    return (($bits -band 0x400) -ne 0) -and (($bits -band 0x5C0000) -ne 0)
}

function Get-AllocatedSize {
    <#
    .SYNOPSIS
    Allocated bytes of one file from GetCompressedFileSizeW, or $null when the
    call fails.
    #>
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory = $true)] [string] $Path
    )

    $target = ($Path.Length -ge 260 -and -not $Path.StartsWith('\\')) ? "\\?\$Path" : $Path
    $high = [uint32]0
    $low = [MachineHealth.FolderSizeNative]::GetCompressedFileSizeW($target, [ref]$high)
    if ($low -eq [uint32]::MaxValue -and [System.Runtime.InteropServices.Marshal]::GetLastPInvokeError() -ne 0) {
        return $null
    }
    return ([long]$high -shl 32) -bor [long]$low
}

function Test-ScanBudgetSpent {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory = $true)] [pscustomobject] $Budget)
    return $Budget.Clock.ElapsedMilliseconds -ge $Budget.LimitMs
}

function Test-FolderDescent {
    <#
    .SYNOPSIS
    The never-descend rule for one enumerated directory: $false for a cloud
    sync root (recorded once with its root) or any other reparse directory
    (counted), $true otherwise. Recording is off for the allocated re-walk.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)] [System.IO.DirectoryInfo] $Entry,
        [Parameter(Mandatory = $true)] [pscustomobject] $Context,
        [bool] $Record = $true
    )

    $attributes = $Entry.Attributes
    if (Test-CloudSyncRoot -Path $Entry.FullName -Attributes $attributes -Prefix $Context.Prefix) {
        if ($Record -and -not $Context.SyncRoots.Contains($Entry.FullName)) {
            $Context.SyncRoots[$Entry.FullName] = $Context.CurrentRoot
        }
        return $false
    }
    if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        if ($Record) { $Context.SkippedReparse++ }
        return $false
    }
    return $true
}

function Invoke-FolderWalk {
    <#
    .SYNOPSIS
    Walks one directory subtree with a manual stack and returns its byte and
    file totals; Allocated mode sums GetCompressedFileSizeW instead of Length.

    .DESCRIPTION
    Logical mode records skipped sync roots, skipped reparse directories and
    unlistable directories on $Context. Allocated mode re-walks a folder the
    logical pass already counted, records nothing, and reports Bytes = $null
    when the budget cuts it or any file's size cannot be read.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [System.IO.DirectoryInfo] $Directory,
        [Parameter(Mandatory = $true)] [pscustomobject] $Context,
        [ValidateSet('Logical', 'Allocated')] [string] $Mode = 'Logical'
    )

    # The budget test is inlined in the per-entry loop: it runs once per file.
    # The walk stops at the budget's limit or at this root's share of it.
    $budget = $Context.Budget
    $logical = $Mode -eq 'Logical'
    $bytes = [long]0
    $files = 0
    $complete = $true
    $failed = $false
    $stack = [System.Collections.Generic.Stack[System.IO.DirectoryInfo]]::new()
    $stack.Push($Directory)

    while ($stack.Count -gt 0) {
        if ($budget.Clock.ElapsedMilliseconds -ge [math]::Min($budget.LimitMs, $Context.DeadlineMs)) { $complete = $false; break }
        $dir = $stack.Pop()
        try {
            foreach ($entry in $dir.EnumerateFileSystemInfos('*', $Context.Options)) {
                if ($budget.Clock.ElapsedMilliseconds -ge [math]::Min($budget.LimitMs, $Context.DeadlineMs)) { $complete = $false; break }
                if ($entry -is [System.IO.DirectoryInfo]) {
                    if (Test-FolderDescent -Entry $entry -Context $Context -Record $logical) { $stack.Push($entry) }
                    continue
                }
                $files++
                if ($logical) {
                    $bytes += $entry.Length
                } elseif (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
                    $size = Get-AllocatedSize -Path $entry.FullName
                    if ($null -eq $size) { $failed = $true } else { $bytes += $size }
                }
            }
        } catch [System.UnauthorizedAccessException], [System.IO.IOException], [System.Security.SecurityException] {
            if ($logical) { $Context.Inaccessible++ } else { $failed = $true }
        }
    }

    return [pscustomobject]@{
        Bytes     = ($logical -or ($complete -and -not $failed)) ? $bytes : $null
        FileCount = $files
        Complete  = $complete
    }
}

function Measure-FolderSize {
    <#
    .SYNOPSIS
    Sizes the folders directly under each root and returns the top N per root,
    with the skipped cloud sync roots as size-less entries.

    .OUTPUTS
    One record: roots[], folders[], scan_complete, allocated_complete,
    inaccessible_count, skipped_reparse_dirs, skipped_sync_roots. A root's
    status is scanned, absent, inaccessible, reparse or cloud-sync-root.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [AllowEmptyString()] [string[]] $Root,
        [ValidateRange(1, 1000)] [int] $Top = 15,
        [ValidateRange('NonNegative')] [int] $AllocatedFileCap = 10000,
        [pscustomobject] $Budget = (New-ScanBudget -Milliseconds 60000)
    )

    $options = [System.IO.EnumerationOptions]::new()
    $options.RecurseSubdirectories = $false
    $options.IgnoreInaccessible = $false
    $options.ReturnSpecialDirectories = $false
    # PowerShell refuses a cast to undefined flag bits; the two RECALL bits are
    # not named FileAttributes members, so the value is built with ToObject.
    $options.AttributesToSkip = [System.Enum]::ToObject([System.IO.FileAttributes], 0x441000)

    $context = [pscustomobject]@{
        Options        = $options
        Budget         = $Budget
        Prefix         = Get-CloudSyncPrefix
        CurrentRoot    = $null
        DeadlineMs     = [long]::MaxValue
        SyncRoots      = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::OrdinalIgnoreCase)
        SkippedReparse = 0
        Inaccessible   = 0
    }

    $roots = [System.Collections.Generic.List[pscustomobject]]::new()
    $folders = [System.Collections.Generic.List[pscustomobject]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $pending = [System.Collections.Generic.List[pscustomobject]]::new()
    $scanComplete = $true

    foreach ($raw in $Root) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        # GetFullPath also expands an 8.3 short name, so a root reached through
        # %TEMP% keys and compares the same as its long form.
        $path = [System.IO.Path]::GetFullPath($raw)
        if ($path.Length -gt 3) { $path = $path.TrimEnd('\', '/') }
        $info = [System.IO.DirectoryInfo]::new($path)
        if (-not $seen.Add($path)) { continue }
        $context.CurrentRoot = $path
        $record = [ordered]@{ path = $path; status = 'scanned'; logical_bytes = $null; file_count = $null; complete = $true }
        $roots.Add([pscustomobject]$record)

        if (-not $info.Exists) {
            $roots[-1].status = 'absent'
            continue
        }
        $underSyncRoot = $false
        for ($a = $info; $null -ne $a; $a = $a.Parent) {
            if (Test-CloudSyncRoot -Path $a.FullName -Attributes $a.Attributes -Prefix $context.Prefix) {
                $underSyncRoot = $true
                break
            }
        }
        if ($underSyncRoot) {
            if (-not $context.SyncRoots.Contains($path)) { $context.SyncRoots[$path] = $path }
            $roots[-1].status = 'cloud-sync-root'
            continue
        }
        if (($info.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            $context.SkippedReparse++
            $roots[-1].status = 'reparse'
            continue
        }

        # The root's own level, listed for every root before any walk: loose
        # files count toward the root, each directory becomes one folder entry,
        # and a sync root directly under a root is recorded whatever the budget
        # does later.
        $listed = [pscustomobject]@{
            Record   = $roots[-1]
            Bytes    = [long]0
            Files    = 0
            Complete = $true
            Children = [System.Collections.Generic.List[System.IO.DirectoryInfo]]::new()
        }
        try {
            if (Test-ScanBudgetSpent $Budget) { $listed.Complete = $false; $listing = @() }
            else { $listing = $info.EnumerateFileSystemInfos('*', $options) }
            foreach ($entry in $listing) {
                if (Test-ScanBudgetSpent $Budget) { $listed.Complete = $false; break }
                if ($entry -is [System.IO.DirectoryInfo]) {
                    if (Test-FolderDescent -Entry $entry -Context $context) { $listed.Children.Add($entry) }
                    continue
                }
                $listed.Bytes += $entry.Length
                $listed.Files++
            }
        } catch [System.UnauthorizedAccessException], [System.IO.IOException], [System.Security.SecurityException] {
            $context.Inaccessible++
            $listed.Record.status = 'inaccessible'
        }
        $pending.Add($listed)
    }

    # Each root's walk gets an equal share of the budget left, counting the
    # allocated pass as one more claimant; time a root leaves unused passes on.
    for ($i = 0; $i -lt $pending.Count; $i++) {
        $p = $pending[$i]
        $elapsed = $Budget.Clock.ElapsedMilliseconds
        $context.DeadlineMs = $elapsed + [math]::Max(0, ($Budget.LimitMs - $elapsed)) / ($pending.Count - $i + 1)
        $context.CurrentRoot = $p.Record.path
        $sized = foreach ($child in $p.Children) {
            $walk = Invoke-FolderWalk -Directory $child -Context $context
            $p.Bytes += $walk.Bytes
            $p.Files += $walk.FileCount
            if (-not $walk.Complete) { $p.Complete = $false }
            [pscustomobject]@{
                root            = $p.Record.path
                path            = $child.FullName
                logical_bytes   = $walk.Bytes
                allocated_bytes = $null
                file_count      = $walk.FileCount
                complete        = $walk.Complete
                skip_reason     = $null
            }
        }
        $ranked = @($sized | Sort-Object -Property @{ Expression = 'logical_bytes'; Descending = $true }, path)
        foreach ($f in @($ranked | Select-Object -First $Top)) { $folders.Add($f) }

        if (-not $p.Complete) { $scanComplete = $false }
        $p.Record.logical_bytes = $p.Bytes
        $p.Record.file_count = $p.Files
        $p.Record.complete = $p.Complete
    }

    # Allocated pass over the kept folders only, inside the same budget.
    $context.DeadlineMs = [long]::MaxValue
    $allocatedComplete = $true
    foreach ($f in $folders) {
        if ((Test-ScanBudgetSpent $Budget) -or -not $f.complete -or $f.file_count -gt $AllocatedFileCap) {
            $allocatedComplete = $false
            continue
        }
        $walk = Invoke-FolderWalk -Directory ([System.IO.DirectoryInfo]::new($f.path)) -Context $context -Mode 'Allocated'
        $f.allocated_bytes = $walk.Bytes
        if ($null -eq $walk.Bytes) { $allocatedComplete = $false }
    }

    foreach ($syncPath in @($context.SyncRoots.Keys)) {
        $folders.Add([pscustomobject]@{
                root            = $context.SyncRoots[$syncPath]
                path            = $syncPath
                logical_bytes   = $null
                allocated_bytes = $null
                file_count      = $null
                complete        = $null
                skip_reason     = 'cloud-sync-root'
            })
    }

    return [pscustomobject]@{
        roots                = @($roots)
        folders              = @($folders)
        scan_complete        = $scanComplete
        allocated_complete   = $allocatedComplete
        inaccessible_count   = $context.Inaccessible
        skipped_reparse_dirs = $context.SkippedReparse
        skipped_sync_roots   = $context.SyncRoots.Count
    }
}
