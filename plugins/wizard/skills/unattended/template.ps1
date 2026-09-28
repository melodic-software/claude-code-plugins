#requires -Version 7.0
<#
  Unattended procedure library. The agent authors the block below # STAGES.
  The human launches this script. The agent does not run it.
  Result JSON is cutover.result/1, plus result-latest.json.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Steps = [System.Collections.Generic.List[object]]::new()
$script:Warnings = [System.Collections.Generic.List[string]]::new()
$script:Held = [System.Collections.Generic.List[string]]::new()
$script:Secrets = [System.Collections.Generic.List[string]]::new()
$script:ResultDirectory = $null
$script:TranscriptPath = $null

function Initialize-UnattendedResult {
    param([Parameter(Mandatory = $true)][string] $ResultDirectory)
    $script:ResultDirectory = $ResultDirectory
    New-Item -ItemType Directory -Force -Path $ResultDirectory | Out-Null
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $script:TranscriptPath = Join-Path $ResultDirectory "transcript-$stamp.log"
    Start-Transcript -LiteralPath $script:TranscriptPath -Force | Out-Null
}

function Test-UnattendedElevated {
    if ($IsWindows) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    $id = (& id -u).Trim()
    return $id -eq '0'
}

function Assert-Elevation {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Required', 'Forbidden')]
        [string] $Mode
    )
    $elevated = Test-UnattendedElevated
    if ($Mode -eq 'Required' -and -not $elevated) {
        throw 'refusing to run unelevated'
    }
    if ($Mode -eq 'Forbidden' -and $elevated) {
        throw 'refusing to run elevated'
    }
}

function Assert-NotInside {
    param([Parameter(Mandatory = $true)][string] $Name)
    $inside = $env:WSL_DISTRO_NAME
    if ($env:WIZARD_INSIDE_MARKER) {
        $inside = $env:WIZARD_INSIDE_MARKER
    }
    if ($inside -and $inside -eq $Name) {
        throw "refusing to run inside $Name"
    }
}

function Resolve-UnattendedSecret {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [string] $FilePath
    )
    $value = [Environment]::GetEnvironmentVariable($Name)
    if (-not $value -and $FilePath -and (Test-Path -LiteralPath $FilePath)) {
        $value = (Get-Content -LiteralPath $FilePath -Raw).Trim()
    }
    if (-not $value) {
        $secure = Read-Host -Prompt "Secret $Name" -AsSecureString
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try {
            $value = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        }
    }
    if (-not $value) {
        throw "secret $Name was not resolved"
    }
    $script:Secrets.Add($value) | Out-Null
    return $value
}

function Assert-PriorResult {
    param([Parameter(Mandatory = $true)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "prior result missing: $Path"
    }
    $prior = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($prior.status -ne 'ok') {
        throw "prior result is $($prior.status): $Path"
    }
}

function Add-Preflight {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][scriptblock] $Test,
        [Parameter(Mandatory = $true)][string] $Fix
    )
    if (-not (& $Test)) {
        $script:Steps.Add([pscustomobject]@{
                name   = $Name
                status = 'failed'
                detail = "fix: $Fix"
            })
        throw "preflight failed: $Name. Fix: $Fix"
    }
    $script:Steps.Add([pscustomobject]@{
            name   = $Name
            status = 'ok'
            detail = 'preflight'
        })
}

# A native command's nonzero exit is not a terminating error under
# $ErrorActionPreference = 'Stop', so every authored block is checked.
function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string] $Label,
        [Parameter(Mandatory = $true)][scriptblock] $Block
    )
    $global:LASTEXITCODE = 0
    & $Block
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed: native command exited $LASTEXITCODE"
    }
}

function Invoke-IdempotentStep {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][scriptblock] $Done,
        [Parameter(Mandatory = $true)][scriptblock] $Action
    )
    if (& $Done) {
        $script:Steps.Add([pscustomobject]@{
                name   = $Name
                status = 'skipped'
                detail = 'already done'
            })
        return
    }
    Invoke-Checked "step $Name" $Action
    $script:Steps.Add([pscustomobject]@{
            name   = $Name
            status = 'ok'
            detail = ''
        })
}

function Use-GuardedResource {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][scriptblock] $Take,
        [Parameter(Mandatory = $true)][scriptblock] $Prove,
        [Parameter(Mandatory = $true)][scriptblock] $Release
    )
    # Listed before Take runs: a Take that fails partway may already hold the resource.
    $script:Held.Add($Name) | Out-Null
    Invoke-Checked "take $Name" $Take
    Invoke-Checked "prove $Name" $Prove
    Invoke-Checked "release $Name" $Release
    $script:Held.Remove($Name) | Out-Null
}

function Confirm-Irreversible {
    param([Parameter(Mandatory = $true)][string] $Name)
    $answer = Read-Host -Prompt "Type $Name to confirm this irreversible step"
    if ($answer -ne $Name) {
        throw "confirmation declined for $Name"
    }
}

function Complete-UnattendedResult {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('ok', 'failed')]
        [string] $Status
    )
    try { Stop-Transcript | Out-Null } catch { }
    if ($script:TranscriptPath -and (Test-Path -LiteralPath $script:TranscriptPath)) {
        $text = [System.IO.File]::ReadAllText($script:TranscriptPath)
        foreach ($secret in $script:Secrets) {
            if ($secret) {
                $text = $text.Replace($secret, '***')
            }
        }
        [System.IO.File]::WriteAllText($script:TranscriptPath, $text)
    }
    $payload = [ordered]@{
        schema          = 'cutover.result/1'
        status          = $Status
        steps           = @($script:Steps)
        warnings        = @($script:Warnings)
        held_resources  = @($script:Held)
        transcript      = $script:TranscriptPath
        redacted        = $true
    }
    $json = $payload | ConvertTo-Json -Depth 6
    foreach ($secret in $script:Secrets) {
        if ($secret) {
            # A step detail or error message can carry a secret too; escape it as JSON does.
            $escaped = ($secret | ConvertTo-Json).Trim('"')
            $json = $json.Replace($escaped, '***')
        }
    }
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $out = Join-Path $script:ResultDirectory "result-$stamp.json"
    $latest = Join-Path $script:ResultDirectory 'result-latest.json'
    Set-Content -LiteralPath $out -Value $json -Encoding utf8
    Set-Content -LiteralPath $latest -Value $json -Encoding utf8
}

function Invoke-UnattendedRun {
    param(
        [Parameter(Mandatory = $true)][string] $ResultDirectory,
        [Parameter(Mandatory = $true)][scriptblock] $Stages
    )
    Initialize-UnattendedResult -ResultDirectory $ResultDirectory
    try {
        & $Stages
        Complete-UnattendedResult -Status ok
    } catch {
        $script:Steps.Add([pscustomobject]@{
                name   = 'run'
                status = 'failed'
                detail = $_.Exception.Message
            })
        Complete-UnattendedResult -Status failed
        throw
    }
}

if ($env:WIZARD_UNATTENDED_LIBRARY_ONLY -eq '1') {
    return
}

# STAGES
Invoke-UnattendedRun -ResultDirectory (Join-Path (Get-Location) 'unattended-results') -Stages {
    Assert-Elevation -Mode Forbidden
    Invoke-IdempotentStep -Name 'example' -Done { $true } -Action { }
}
