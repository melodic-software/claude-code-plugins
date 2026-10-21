#Requires -Version 7.4

<#
.SYNOPSIS
Read a whole text file while letting other handles keep writing, renaming or
deleting it.

.DESCRIPTION
Opens with FileShare.ReadWrite | FileShare.Delete, so a writer replacing the
file never blocks the read. A UTF-8 or other byte-order mark is honored. Throws
when the file is missing or cannot be opened; callers decide the fallback.
#>

function Read-SharedText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)] [string] $Path
    )

    $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $stream = [System.IO.File]::Open($fullPath, 'Open', 'Read', [System.IO.FileShare]'ReadWrite, Delete')
    try {
        return [System.IO.StreamReader]::new($stream).ReadToEnd()
    } finally {
        $stream.Dispose()
    }
}
