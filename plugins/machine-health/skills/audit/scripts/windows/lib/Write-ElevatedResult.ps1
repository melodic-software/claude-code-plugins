#Requires -Version 7.4

<#
.SYNOPSIS
Write the elevated pass's result document into the result file the standard
session pre-created, and nowhere else.

.DESCRIPTION
The elevated side of the elevated pass (reference/windows/elevation-matrix.md,
"How to run elevated"). The file is opened without following reparse points
and must already exist; a reparse point, a directory, or a file whose ID is not
-FileId (the ID New-ElevatedLaunch recorded at pre-create time) is refused
before a byte is written. The document is then written through that same
handle, so the checked file is the written file.

Document: { "format": "elevated-result/1", "ran_at": "<ISO>", "elevated": <bool>,
"results": [<CheckResult>...], "log": ["<line>"...] }
#>

. (Join-Path $PSScriptRoot 'Open-NoFollowFile.ps1')

function Write-ElevatedResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [ValidatePattern('^[0-9A-F]{8}-[0-9A-F]{16}$')] [string] $FileId,
        [AllowEmptyCollection()] [object[]] $Results = @(),
        [AllowEmptyCollection()] [string[]] $Log = @(),
        [bool] $Elevated
    )

    $document = [ordered]@{
        format   = 'elevated-result/1'
        ran_at   = (Get-Date).ToString('o')
        elevated = $Elevated
        results  = @($Results)
        log      = @($Log)
    }
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes(($document | ConvertTo-Json -Depth 20))

    $handle = Open-NoFollowFile -Path $Path -Access ReadWrite
    try {
        $identity = Get-FileIdentity -Handle $handle
        if ($identity.IsReparsePoint -or $identity.IsDirectory) {
            throw "Refused '$Path': it is a reparse point or a directory, not the pre-created result file."
        }
        if ($identity.FileId -cne $FileId) {
            throw "Refused '$Path': its file ID $($identity.FileId) is not the pre-created file's ID $FileId."
        }
        $stream = [System.IO.FileStream]::new($handle, [System.IO.FileAccess]::ReadWrite)
        try {
            $stream.SetLength(0)
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        } finally {
            $stream.Dispose()
        }
    } finally {
        $handle.Dispose()
    }
}
