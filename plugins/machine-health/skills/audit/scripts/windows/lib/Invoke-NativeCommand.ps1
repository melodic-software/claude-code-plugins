#Requires -Version 7.4

<#
.SYNOPSIS
Invoke an external tool by name with an argument array.

.DESCRIPTION
The only Windows lib seam that starts a native binary. Callers pass the tool
name and one string per argv entry. A comma inside a string stays inside that
entry; argument-mode parsing is what split `--query-gpu=name,driver_version`
into four entries.

The result is always a record, never a throw for a missing tool or a non-zero
exit:

  status     Ok | Absent | NonZero | Failed
  source     the tool name when it was started; the literal `absent` when it
             is not on PATH. `absent` is this record's field. Callers that
             already stamp a data source on their own records (nvidia-smi
             versus Win32_VideoController) keep those values and do not copy
             `absent` onto a CheckResult.
  exit_code  the process exit code, or $null when the process did not start
  output     merged stdout (and stderr unless -DiscardStdErr), trailing
             newline removed
  error      the exception message when status is Failed; otherwise $null

Any status other than Ok is the signal to take the caller's existing
fallback (empty inventory, WMI, the winget module path). CheckResult's
schema is unchanged.
#>

function Invoke-NativeCommand {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [AllowEmptyCollection()]
        [string[]] $ArgumentList = @(),

        [switch] $DiscardStdErr
    )

    # Non-zero exits stay a status on the result when the session would
    # otherwise turn them into terminating errors.
    $PSNativeCommandUseErrorActionPreference = $false

    $command = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $command) {
        Write-Verbose "Invoke-NativeCommand: $Name is not on PATH."
        return [pscustomobject]@{
            status    = 'Absent'
            source    = 'absent'
            exit_code = $null
            output    = ''
            error     = $null
        }
    }

    $path = [string] $command.Source
    try {
        if ($DiscardStdErr) {
            $raw = & $path @ArgumentList 2>$null
        } else {
            $raw = & $path @ArgumentList 2>&1
        }
        $code = $LASTEXITCODE
    } catch {
        return [pscustomobject]@{
            status    = 'Failed'
            source    = $Name
            exit_code = $null
            output    = ''
            error     = $_.Exception.Message
        }
    }

    $text = if ($null -eq $raw) {
        ''
    } else {
        (($raw | Out-String) -replace '\r?\n$', '')
    }
    $status = if ($null -ne $code -and $code -eq 0) { 'Ok' } else { 'NonZero' }
    return [pscustomobject]@{
        status    = $status
        source    = $Name
        exit_code = $code
        output    = $text
        error     = $null
    }
}
