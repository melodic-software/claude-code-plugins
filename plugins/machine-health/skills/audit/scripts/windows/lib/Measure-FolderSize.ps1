#Requires -Version 7.4

<#
.SYNOPSIS
Folder-size adapter for storage-top-n: sizes the folders directly under each
root without hydrating a cloud file.

.DESCRIPTION
The rules this walk holds (the never-descend rule, the skipped attributes, the
budget and its split across roots, the allocated pass) are stated in
reference/windows/check-catalog.md#20-storage-top-n. The walk is a manual
directory stack over DirectoryInfo.EnumerateFileSystemInfos with
RecurseSubdirectories off, so every descent is decided by Test-FolderDescent.
No link is resolved and no enumerated file is opened, except by
GetCompressedFileSizeW in the allocated pass.
#>

if (-not ('MachineHealth.FolderSizeNative' -as [type])) {
    Add-Type -Namespace 'MachineHealth' -Name 'FolderSizeNative' -MemberDefinition @'
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern uint GetCompressedFileSizeW(string lpFileName, out uint lpFileSizeHigh);
'@
}

# Offline | RECALL_ON_OPEN | RECALL_ON_DATA_ACCESS: a file carrying any of
# these is a placeholder and is skipped unread and uncounted; a directory
# carrying any is never descended (Test-FolderDescent). The enumeration itself
# skips nothing, so such a directory is still seen and reported. The
# two RECALL bits are not named FileAttributes members and PowerShell refuses a
# cast to undefined flag bits, so the value is built with ToObject.
$script:PlaceholderSkipMask = [System.Enum]::ToObject([System.IO.FileAttributes], 0x441000)

# RECALL_ON_OPEN | PINNED | UNPINNED | RECALL_ON_DATA_ACCESS: with ReparsePoint,
# any of these marks a directory as under a cloud sync root.
$script:CloudAttributeMask = [System.Enum]::ToObject([System.IO.FileAttributes], 0x5C0000)

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

function Test-ScanBudgetSpent {
    <#
    .SYNOPSIS
    True once the budget's limit or the current root's deadline has passed.
    Plain function: it runs once per enumerated entry.
    #>
    [OutputType([bool])]
    param([Parameter(Mandatory = $true)] [pscustomobject] $Context)
    $elapsed = $Context.Budget.Clock.ElapsedMilliseconds
    return ($elapsed -ge $Context.Budget.LimitMs) -or ($elapsed -ge $Context.DeadlineMs)
}

function Test-PathUnder {
    <#
    .SYNOPSIS
    True when Path equals Parent or lies below it, case-insensitively, with
    trailing separators ignored on both.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [string] $Parent
    )
    $p = $Path.TrimEnd('\', '/')
    $q = $Parent.TrimEnd('\', '/')
    return $p.Equals($q, [System.StringComparison]::OrdinalIgnoreCase) -or
        $p.StartsWith($q + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-CloudSyncPrefix {
    <#
    .SYNOPSIS
    The set OneDrive variables, read at call time, as full paths.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $prefixes = foreach ($name in @('OneDrive', 'OneDriveConsumer', 'OneDriveCommercial')) {
        $value = [System.Environment]::GetEnvironmentVariable($name)
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        [System.IO.Path]::GetFullPath($value)
    }
    return [string[]]@($prefixes | Select-Object -Unique)
}

function Test-CloudSyncRoot {
    <#
    .SYNOPSIS
    True when a directory is at or under a cloud sync root: a set OneDrive
    variable prefixes its path, or it carries ReparsePoint plus a bit of
    $script:CloudAttributeMask.

    .DESCRIPTION
    Pure: the caller passes the attributes it already holds and the prefixes
    from Get-CloudSyncPrefix. Ancestors of a starting root are tested by
    calling this once per ancestor; a walk never reaches below a sync root, so
    a directory found by the walk needs only its own test.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [System.IO.FileAttributes] $Attributes,
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [string[]] $Prefix
    )

    foreach ($p in $Prefix) {
        if (Test-PathUnder -Path $Path -Parent $p) { return $true }
    }
    return (($Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) -and
        (($Attributes -band $script:CloudAttributeMask) -ne 0)
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

function Test-FolderDescent {
    <#
    .SYNOPSIS
    The never-descend rule for one directory: $false for a cloud sync root
    (recorded once against the current root) or any other reparse or
    $script:PlaceholderSkipMask directory (counted in SkippedReparse), $true
    otherwise. Recording is off for the allocated re-walk.
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
    if ((($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) -or
        (($attributes -band $script:PlaceholderSkipMask) -ne 0)) {
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
    logical pass already counted, records nothing, skips a file that is itself
    a reparse point (opening a file symlink would reach its target), and
    reports Bytes = $null when the budget cuts it or any file's size cannot be
    read.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [System.IO.DirectoryInfo] $Directory,
        [Parameter(Mandatory = $true)] [pscustomobject] $Context,
        [ValidateSet('Logical', 'Allocated')] [string] $Mode = 'Logical'
    )

    $logical = $Mode -eq 'Logical'
    $bytes = [long]0
    $files = 0
    $complete = $true
    $failed = $false
    $stack = [System.Collections.Generic.Stack[System.IO.DirectoryInfo]]::new()
    $stack.Push($Directory)

    while ($stack.Count -gt 0) {
        if (Test-ScanBudgetSpent $Context) { $complete = $false; break }
        $dir = $stack.Pop()
        try {
            foreach ($entry in $dir.EnumerateFileSystemInfos('*', $Context.Options)) {
                if (Test-ScanBudgetSpent $Context) { $complete = $false; break }
                if ($entry -is [System.IO.DirectoryInfo]) {
                    if (Test-FolderDescent -Entry $entry -Context $Context -Record $logical) { $stack.Push($entry) }
                    continue
                }
                if (($entry.Attributes -band $script:PlaceholderSkipMask) -ne 0) { continue }
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
    with each skipped cloud sync root as a size-less entry.

    .OUTPUTS
    One record: roots[], folders[], scan_complete, allocated_complete,
    inaccessible_count, skipped_reparse_dirs, skipped_sync_roots. Each root
    record and folder entry carries `input`, the -Root string the caller
    passed, so the caller joins its own data without re-normalizing a path. A
    root's status is scanned, absent, inaccessible, reparse or cloud-sync-root.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [AllowEmptyString()] [string[]] $Root,
        [Parameter(Mandatory = $true)] [ValidateRange(1, 1000)] [int] $Top,
        [Parameter(Mandatory = $true)] [ValidateRange('NonNegative')] [int] $AllocatedFileCap,
        [Parameter(Mandatory = $true)] [pscustomobject] $Budget
    )

    $options = [System.IO.EnumerationOptions]::new()
    $options.RecurseSubdirectories = $false
    $options.IgnoreInaccessible = $false
    $options.ReturnSpecialDirectories = $false
    $options.AttributesToSkip = [System.IO.FileAttributes]::None

    $context = [pscustomobject]@{
        Options        = $options
        Budget         = $Budget
        DeadlineMs     = [long]::MaxValue
        Prefix         = [string[]]@(Get-CloudSyncPrefix)
        CurrentRoot    = $null
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
        # %TEMP% compares the same as its long form.
        $path = [System.IO.Path]::GetFullPath($raw)
        if ($path.Length -gt 3) { $path = $path.TrimEnd('\', '/') }
        if (-not $seen.Add($path)) { continue }
        $info = [System.IO.DirectoryInfo]::new($path)
        $record = [pscustomobject]@{ input = $raw; path = $path; status = 'scanned'; logical_bytes = $null; file_count = $null; complete = $true }
        $roots.Add($record)
        $context.CurrentRoot = $record

        if (-not $info.Exists) {
            $record.status = 'absent'
            continue
        }
        $underSyncRoot = $false
        for ($a = $info.Parent; $null -ne $a; $a = $a.Parent) {
            if (Test-CloudSyncRoot -Path $a.FullName -Attributes $a.Attributes -Prefix $context.Prefix) {
                $underSyncRoot = $true
                break
            }
        }
        if ($underSyncRoot) {
            if (-not $context.SyncRoots.Contains($path)) { $context.SyncRoots[$path] = $record }
            $record.status = 'cloud-sync-root'
            continue
        }
        if (-not (Test-FolderDescent -Entry $info -Context $context)) {
            $record.status = $context.SyncRoots.Contains($path) ? 'cloud-sync-root' : 'reparse'
            continue
        }

        # The root's own level, listed for every root before any walk: loose
        # files count toward the root, each directory becomes one folder entry,
        # and a sync root directly under a root is recorded whatever the budget
        # does later.
        $listed = [pscustomobject]@{
            Record   = $record
            Bytes    = [long]0
            Files    = 0
            Complete = $true
            Children = [System.Collections.Generic.List[System.IO.DirectoryInfo]]::new()
        }
        try {
            foreach ($entry in $info.EnumerateFileSystemInfos('*', $options)) {
                if (Test-ScanBudgetSpent $context) { $listed.Complete = $false; break }
                if ($entry -is [System.IO.DirectoryInfo]) {
                    if (Test-FolderDescent -Entry $entry -Context $context) { $listed.Children.Add($entry) }
                    continue
                }
                if (($entry.Attributes -band $script:PlaceholderSkipMask) -ne 0) { continue }
                $listed.Bytes += $entry.Length
                $listed.Files++
            }
        } catch [System.UnauthorizedAccessException], [System.IO.IOException], [System.Security.SecurityException] {
            $context.Inaccessible++
            $record.status = 'inaccessible'
        }
        $pending.Add($listed)
    }

    # Each root's walk gets an equal share of the budget left, counting the
    # allocated pass as one more claimant; time a root leaves unused passes on.
    for ($i = 0; $i -lt $pending.Count; $i++) {
        $p = $pending[$i]
        $elapsed = $Budget.Clock.ElapsedMilliseconds
        $context.DeadlineMs = $elapsed + [math]::Max(0, ($Budget.LimitMs - $elapsed)) / ($pending.Count - $i + 1)
        $context.CurrentRoot = $p.Record
        $sized = @(foreach ($child in $p.Children) {
            $walk = Invoke-FolderWalk -Directory $child -Context $context
            $p.Bytes += $walk.Bytes
            $p.Files += $walk.FileCount
            if (-not $walk.Complete) { $p.Complete = $false }
            [pscustomobject]@{
                input           = $p.Record.input
                root            = $p.Record.path
                path            = $child.FullName
                logical_bytes   = $walk.Bytes
                allocated_bytes = $null
                file_count      = $walk.FileCount
                complete        = $walk.Complete
                skip_reason     = $null
            }
        })
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
        if ((Test-ScanBudgetSpent $context) -or -not $f.complete -or $f.file_count -gt $AllocatedFileCap) {
            $allocatedComplete = $false
            continue
        }
        $walk = Invoke-FolderWalk -Directory ([System.IO.DirectoryInfo]::new($f.path)) -Context $context -Mode 'Allocated'
        $f.allocated_bytes = $walk.Bytes
        if ($null -eq $walk.Bytes) { $allocatedComplete = $false }
    }

    foreach ($syncPath in @($context.SyncRoots.Keys)) {
        $owner = $context.SyncRoots[$syncPath]
        $folders.Add([pscustomobject]@{
                input           = $owner.input
                root            = $owner.path
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
