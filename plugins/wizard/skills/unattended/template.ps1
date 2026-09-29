#requires -Version 7.0
<#
  Unattended procedure library. The agent authors the block below # STAGES.
  The human launches this script. The agent never launches the real run.
  -WhatIf narrates the plan and -Test reports what would change. Neither
  invokes a helper's block, and both write only the result directory.
  Result JSON is cutover.result/1, plus result-latest.json
  (result-dry-latest.json for -WhatIf and -Test).
#>
[CmdletBinding(SupportsShouldProcess)]
param([switch] $Test)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Helpers read $script:Mode, never $Test: Add-Preflight has its own -Test parameter.
$script:Mode = if ($Test) { 'test' } elseif ($WhatIfPreference) { 'whatif' } else { 'run' }
# -Test also skips any cmdlet outside a helper that honors -WhatIf.
if ($script:Mode -eq 'test') { $WhatIfPreference = $true }

$script:Steps = [System.Collections.Generic.List[object]]::new()
$script:Warnings = [System.Collections.Generic.List[string]]::new()
$script:Held = [System.Collections.Generic.List[string]]::new()
$script:Secrets = [System.Collections.Generic.List[string]]::new()
$script:PlannedResources = [System.Collections.Generic.List[string]]::new()
$script:Irreversible = @()
$script:ResultDirectory = $null
$script:TranscriptPath = $null

# -WhatIf:$false on the result writes: a dry run still writes its result directory.
function Initialize-UnattendedResult {
    param([Parameter(Mandatory = $true)][string] $ResultDirectory)
    $script:ResultDirectory = $ResultDirectory
    New-Item -ItemType Directory -Force -Path $ResultDirectory -WhatIf:$false | Out-Null
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $script:TranscriptPath = Join-Path $ResultDirectory "transcript-$stamp.log"
    Start-Transcript -LiteralPath $script:TranscriptPath -Force -WhatIf:$false | Out-Null
}

function Add-UnattendedStep {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $Status,
        [string] $Detail = ''
    )
    $script:Steps.Add([pscustomobject]@{
            name   = $Name
            status = $Status
            detail = $Detail
        })
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
    if (-not $value -and $script:Mode -ne 'run') {
        Add-UnattendedStep "secret $Name" 'would-run' 'would prompt: not in the environment or the file'
        return "<$Name>"
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
        Add-UnattendedStep $Name 'failed' "fix: $Fix"
        throw "preflight failed: $Name. Fix: $Fix"
    }
    Add-UnattendedStep $Name 'ok' 'preflight'
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
        Add-UnattendedStep $Name 'skipped' 'already done'
        return
    }
    if ($script:Mode -ne 'run') {
        Add-UnattendedStep $Name 'would-run' 'would run the action'
        return
    }
    Invoke-Checked "step $Name" $Action
    Add-UnattendedStep $Name 'ok'
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
    if ($script:Mode -ne 'test') {
        Write-Host "read ${Name}: $($items.Count) item(s)"
    }
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
    # The state it waits for follows a mutation a dry run skipped, so polling would only time out.
    if ($script:Mode -ne 'run') {
        Add-UnattendedStep "wait $Name" 'would-run' "would poll for up to ${TimeoutSeconds}s"
        return $true
    }
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
    Add-UnattendedStep "wait $Name" 'ok' ('reached after {0:N1}s' -f $clock.Elapsed.TotalSeconds)
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
    if ($script:Mode -ne 'run') {
        $script:PlannedResources.Add($Name) | Out-Null
        Add-UnattendedStep "guard $Name" 'would-run' 'would take it out of service, prove the state, then release it'
        return
    }
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
    if ($script:Mode -ne 'run') {
        Add-UnattendedStep "irreversible $Name" 'would-run' 'would ask the human to type the name'
        return
    }
    $answer = Read-Host -Prompt "Type $Name to confirm this irreversible step"
    if ($answer -ne $Name) {
        throw "confirmation declined for $Name"
    }
    Add-UnattendedStep "irreversible $Name" 'ok' 'confirmed'
}

function Complete-UnattendedResult {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('ok', 'failed')]
        [string] $Status
    )
    $dry = $script:Mode -ne 'run'
    $prefix = if ($dry) { 'result-dry' } else { 'result' }
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $out = Join-Path $script:ResultDirectory "$prefix-$stamp.json"
    $latest = Join-Path $script:ResultDirectory "$prefix-latest.json"
    $planned = [ordered]@{
        steps        = @($script:Steps | Where-Object status -eq 'would-run').Count
        resources    = $script:PlannedResources.Count
        irreversible = $script:Irreversible.Count
    }
    $counts = '{0} step(s) would run, {1} resource(s) would be taken out of service, {2} declared irreversible action(s)' -f $planned.steps, $planned.resources, $planned.irreversible
    if ($script:Mode -eq 'whatif') {
        foreach ($step in $script:Steps) {
            Write-Host "What if: $($step.name) [$($step.status)] $($step.detail)"
        }
        Write-Host "What if: blast radius: $counts"
    } elseif ($script:Mode -eq 'test') {
        Write-Host "Test: $counts. Delta: $latest"
    }
    try { Stop-Transcript -WhatIf:$false | Out-Null } catch { }
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
        mode                 = $script:Mode
        status               = $Status
        steps                = @($script:Steps)
        warnings             = @($script:Warnings)
        held_resources       = @($script:Held)
        irreversible_actions = @($script:Irreversible)
        transcript           = $script:TranscriptPath
        redacted             = $true
    }
    if ($dry) {
        $payload['planned'] = $planned
        # The synthetic 'run' step records the throw; a failed preflight is the finding.
        $payload['delta'] = @($script:Steps | Where-Object { $_.status -eq 'would-run' -or ($_.status -eq 'failed' -and $_.name -ne 'run') })
    }
    $json = $payload | ConvertTo-Json -Depth 6
    foreach ($secret in $script:Secrets) {
        if ($secret) {
            # A step detail or error message can carry a secret too; escape it as JSON does.
            $escaped = ($secret | ConvertTo-Json).Trim('"')
            $json = $json.Replace($escaped, '***')
        }
    }
    Set-Content -LiteralPath $out -Value $json -Encoding utf8 -WhatIf:$false
    Set-Content -LiteralPath $latest -Value $json -Encoding utf8 -WhatIf:$false
}

function Invoke-UnattendedRun {
    param(
        [Parameter(Mandatory = $true)][string] $ResultDirectory,
        [Parameter(Mandatory = $true)][scriptblock] $Stages,
        [string[]] $Irreversible = @()
    )
    Initialize-UnattendedResult -ResultDirectory $ResultDirectory
    $script:Irreversible = @($Irreversible)
    if ($script:Mode -ne 'test') {
        Write-Host ('irreversible actions: ' + $(if ($Irreversible.Count) { $Irreversible -join '; ' } else { 'none' }))
    }
    try {
        & $Stages
        Complete-UnattendedResult -Status ok
    } catch {
        Add-UnattendedStep 'run' 'failed' $_.Exception.Message
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
