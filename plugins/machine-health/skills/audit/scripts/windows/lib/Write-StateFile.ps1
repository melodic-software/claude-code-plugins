#Requires -Version 7.4

<#
.SYNOPSIS
Atomically replace one machine-health state file (approvals.json, mutes.json).

.DESCRIPTION
Who may write these files, and what they guarantee, is stated once in
reference/shared/approvals.md, "Writing approvals and mutes". This is the
replace recipe both writers use.

-Update receives the file's current text ($null when the file does not exist)
and returns the new text, or $null to leave the file as it is. Returns $true
when the file was written.

The new text goes to a temp file in the same directory, is flushed to disk
(Flush($true)) and closed, and File.Replace swaps it in, so a reader sees the
old file or the new one and never a partial write. File.Replace needs an
existing destination, so the first write uses File.Move without overwrite.
When the destination appeared in the meantime, the file is re-read, -Update
runs once more on it and the result replaces it; a second failure throws.
Nothing here ever moves over an existing file.

A sharing violation (a reader that opened the file without FileShare.Delete) is
retried 5 times, waiting 100 ms and doubling. Every replace failure throws
naming the file and the temp file, which is left in place.
#>

. (Join-Path $PSScriptRoot 'Read-SharedText.ps1')
. (Join-Path $PSScriptRoot 'Get-InnerHResult.ps1')

function Write-StateFile {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [scriptblock] $Update
    )

    $alreadyExists = @(0x800700B7, 0x80070050)
    $destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $tempPath = Join-Path ([System.IO.Path]::GetDirectoryName($destination)) (
        '{0}.{1}.tmp' -f [System.IO.Path]::GetFileName($destination), [guid]::NewGuid().ToString('N'))

    $readCurrent = {
        if ([System.IO.File]::Exists($destination)) { Read-SharedText -Path $destination } else { $null }
    }
    $writeTemp = {
        param([string] $Text)
        $stream = [System.IO.FileStream]::new($tempPath, 'Create', 'Write', 'None')
        try {
            $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        } finally {
            $stream.Dispose()
        }
    }
    $replace = {
        $delayMs = 100
        for ($retry = 0; ; $retry++) {
            try {
                [System.IO.File]::Replace($tempPath, $destination, [NullString]::Value)
                return
            } catch {
                $reason = $_.Exception.Message
                if ((Get-InnerHResult $_) -ne $script:SharingViolationHResult) {
                    throw "Write-StateFile: replacing '$destination' failed; the new content is in '$tempPath'. $reason"
                }
                if ($retry -ge 5) {
                    throw ("Write-StateFile: '$destination' is held open by another process without " +
                        "FileShare.Delete; gave up after 5 retries. The new content is in '$tempPath'.")
                }
            }
            Start-Sleep -Milliseconds $delayMs
            $delayMs *= 2
        }
    }

    $existed = [System.IO.File]::Exists($destination)
    $newText = & $Update (& $readCurrent)
    if ($null -eq $newText) { return $false }
    & $writeTemp $newText

    if ($existed) {
        & $replace
        return $true
    }

    try {
        [System.IO.File]::Move($tempPath, $destination)
        return $true
    } catch {
        if ((Get-InnerHResult $_) -notin $alreadyExists) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
            throw
        }
    }

    # The destination appeared after the existence test: apply the change to it instead.
    try {
        $newText = & $Update (& $readCurrent)
    } catch {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        throw
    }
    if ($null -eq $newText) {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        return $false
    }
    & $writeTemp $newText
    & $replace
    return $true
}
