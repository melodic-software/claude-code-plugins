#Requires -Version 7.4

<#
.SYNOPSIS
Write the elevated pass's result document into the pre-created result file.

.DESCRIPTION
Opens -Path through Open-NoFollowFile and refuses a reparse point or a file
whose ID is not -FileId before writing a byte; the document is then written
through that same handle. Mechanism: reference/windows/elevation-matrix.md,
"How to run elevated".

Document: { "format": <Get-ElevatedResultFormat>, "ran_at": "<ISO>",
"elevated": <bool>, "user_sid": "<SID>", "results": [<CheckResult>...],
"log": ["<line>"...] }
#>

. (Join-Path $PSScriptRoot 'Open-NoFollowFile.ps1')

function Get-ElevatedResultFormat {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return 'elevated-result/1'
}

function Write-ElevatedResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [ValidateScript({ Test-FileIdFormat $_ })] [string] $FileId,
        [AllowEmptyCollection()] [object[]] $Results = @(),
        [AllowEmptyCollection()] [string[]] $Log = @(),
        [bool] $Elevated,
        [string] $UserSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    )

    $document = [ordered]@{
        format   = Get-ElevatedResultFormat
        ran_at   = (Get-Date).ToString('o')
        elevated = $Elevated
        user_sid = $UserSid
        results  = @($Results)
        log      = @($Log)
    }
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes(($document | ConvertTo-Json -Depth 20))

    $handle = Open-NoFollowFile -Path $Path -Access ReadWrite
    try {
        $identity = Get-FileIdentity -Handle $handle
        if ($identity.IsReparsePoint) {
            throw "Refused '$Path': it is a reparse point, not the pre-created result file."
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
