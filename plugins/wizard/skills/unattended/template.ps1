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
$script:Irreversible = @()
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

# A guard that skips a destructive step when a name is absent from a parsed
# listing must not read an empty parse as absent: the read may have failed.
function Assert-ParsedState {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyCollection()][AllowEmptyString()] $Value
    )
    $items = @($Value | ForEach-Object { "$_" -split '\r?\n' } | Where-Object { $_.Trim() })
    if ($items.Count -eq 0) {
        throw "could not read ${Name}: parsed listing is empty. Unknown state is a stop, not 'already absent'"
    }
    Write-Host "read ${Name}: $($items.Count) item(s)"
}

# wsl.exe writes UTF-16 unless WSL_UTF8=1, and a PowerShell capture decodes that
# as text with embedded NULs. Prefer a CLI's --json over parsing human output.
function Invoke-NativeUtf8 {
    param([Parameter(Mandatory = $true)][scriptblock] $Block)
    $priorVariable = $env:WSL_UTF8
    $priorEncoding = [Console]::OutputEncoding
    $env:WSL_UTF8 = '1'
    # A host with no attached console throws on the setter; the pin then rests on WSL_UTF8.
    try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }
    try {
        & $Block
    } finally {
        $env:WSL_UTF8 = $priorVariable
        try { [Console]::OutputEncoding = $priorEncoding } catch { }
    }
}

# Polls an outcome instead of trusting the exit code of the request that caused
# it. The predicate must assert a non-empty observation first: an empty set
# satisfies "all of them are done".
function Wait-ForState {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][scriptblock] $Predicate,
        [int] $TimeoutSeconds = 300,
        [double] $IntervalSeconds = 5
    )
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            $observed = @(& $Predicate)
            if ($observed.Count -gt 0 -and $observed[-1]) {
                break
            }
            $last = if ($observed.Count -eq 0) { 'no output' } else { "value $($observed[-1])" }
        } catch {
            $last = "error $($_.Exception.Message)"
        }
        $elapsed = $clock.Elapsed.TotalSeconds
        Write-Host ('waiting for {0}: attempt {1}, {2:N0}s elapsed' -f $Name, $attempt, $elapsed)
        if ($elapsed -ge $TimeoutSeconds) {
            throw "timed out waiting for $Name after ${TimeoutSeconds}s; last: $last"
        }
        Start-Sleep -Seconds ([Math]::Min($IntervalSeconds, $TimeoutSeconds - $elapsed))
    }
    $script:Steps.Add([pscustomobject]@{
            name   = "wait $Name"
            status = 'ok'
            detail = ('reached after {0:N1}s' -f $clock.Elapsed.TotalSeconds)
        })
    # Emitting $true lets Wait-ForState stand alone as a Use-GuardedResource Prove block.
    $true
}

function Use-GuardedResource {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][scriptblock] $Take,
        [Parameter(Mandatory = $true)][scriptblock] $Prove,
        [Parameter(Mandatory = $true)][scriptblock] $Release,
        [switch] $TolerateTakeExit
    )
    # Listed before Take runs: a Take that fails partway may already hold the resource.
    $script:Held.Add($Name) | Out-Null
    if ($TolerateTakeExit) {
        # A thrown exception still fails; only the native exit code is deferred to Prove.
        $global:LASTEXITCODE = 0
        & $Take
        if ($LASTEXITCODE -ne 0) {
            $script:Warnings.Add("take $Name exited $LASTEXITCODE; state is proven by the next step") | Out-Null
        }
    } else {
        Invoke-Checked "take $Name" $Take
    }
    $global:LASTEXITCODE = 0
    $proof = @(& $Prove)
    if ($LASTEXITCODE -ne 0) {
        throw "prove $Name failed: native command exited $LASTEXITCODE"
    }
    if ($proof.Count -eq 0 -or -not $proof[-1]) {
        throw "prove $Name failed: proof failed"
    }
    Invoke-Checked "release $Name" $Release
    $script:Held.Remove($Name) | Out-Null
}

# Refuses before prompting, so no irreversible action precedes proof and release
# of every guarded resource.
function Confirm-Irreversible {
    param([Parameter(Mandatory = $true)][string] $Name)
    if ($Name -notin $script:Irreversible) {
        throw "irreversible step $Name was not declared"
    }
    if ($script:Held.Count -gt 0) {
        throw "refusing irreversible step $Name while resources are held: $($script:Held -join ', ')"
    }
    $answer = Read-Host -Prompt "Type $Name to confirm this irreversible step"
    if ($answer -ne $Name) {
        throw "confirmation declined for $Name"
    }
    $script:Steps.Add([pscustomobject]@{
            name   = "irreversible $Name"
            status = 'ok'
            detail = 'confirmed'
        })
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
        schema               = 'cutover.result/1'
        status               = $Status
        steps                = @($script:Steps)
        warnings             = @($script:Warnings)
        held_resources       = @($script:Held)
        irreversible_actions = @($script:Irreversible)
        transcript           = $script:TranscriptPath
        redacted             = $true
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
        [Parameter(Mandatory = $true)][scriptblock] $Stages,
        [string[]] $Irreversible = @()
    )
    Initialize-UnattendedResult -ResultDirectory $ResultDirectory
    $script:Irreversible = @($Irreversible)
    Write-Host ('irreversible actions: ' + $(if ($Irreversible.Count) { $Irreversible -join '; ' } else { 'none' }))
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
