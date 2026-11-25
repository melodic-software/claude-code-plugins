#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param([switch] $Test)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Mode = if ($Test) { 'test' } elseif ($WhatIfPreference) { 'whatif' } else { 'run' }
if ($script:Mode -eq 'test') { $WhatIfPreference = $true }

$script:Steps = [System.Collections.Generic.List[object]]::new()
$script:Warnings = [System.Collections.Generic.List[string]]::new()
$script:Held = [System.Collections.Generic.List[string]]::new()
$script:Secrets = [System.Collections.Generic.List[string]]::new()
$script:PlannedResources = [System.Collections.Generic.List[string]]::new()
$script:Irreversible = @()
$script:DeclaredSecrets = @()
$script:SecretCache = @{}
$script:ResultDirectory = $null
$script:TranscriptPath = $null

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
    return (& id -u).Trim() -eq '0'
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
    $inside = if ($env:WIZARD_INSIDE_MARKER) { $env:WIZARD_INSIDE_MARKER } else { $env:WSL_DISTRO_NAME }
    if ($inside -eq $Name) {
        throw "refusing to run inside $Name"
    }
}

function Get-UnattendedNativeSecret {
    param([Parameter(Mandatory = $true)][string] $Name)
    $PSNativeCommandUseErrorActionPreference = $false
    $platform = $env:WIZARD_PLATFORM
    if (-not $platform) {
        $platform = if ($IsMacOS) { 'macos' } elseif ($IsLinux) { 'linux' }
    }
    $lines = $null
    if ($platform -eq 'macos' -and (Get-Command security -CommandType Application -ErrorAction SilentlyContinue)) {
        $lines = & security find-generic-password -s $Name -w 2>$null
    } elseif ($platform -eq 'linux' -and (Get-Command pass -CommandType Application -ErrorAction SilentlyContinue)) {
        $store = if ($env:PASSWORD_STORE_DIR) { $env:PASSWORD_STORE_DIR } else { Join-Path $HOME '.password-store' }
        if (-not (Test-Path -LiteralPath (Join-Path $store "$Name.gpg") -PathType Leaf)) {
            return $null
        }
        $lines = & pass show -- $Name 2>$null
    } else {
        return $null
    }
    if ($LASTEXITCODE -ne 0) {
        return $null
    }
    $first = $lines | Select-Object -First 1
    if ($first -is [string] -and $first) {
        return $first
    }
    return $null
}

function Get-UnattendedStoreSecret {
    param([Parameter(Mandatory = $true)][string] $Name)
    if (Get-Command Get-Secret -ErrorAction SilentlyContinue) {
        try {
            $value = Get-Secret -Name $Name -AsPlainText -ErrorAction SilentlyContinue
        } catch {
            $value = $null
        }
        if ($value -is [string]) {
            return $value
        }
        if ($null -ne $value) {
            $script:Warnings.Add("store secret $Name is a $($value.GetType().Name), not a string; the store rung skipped it") | Out-Null
        }
    }
    return Get-UnattendedNativeSecret -Name $Name
}

function Find-UnattendedSecret {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [string] $FilePath
    )
    $value = [Environment]::GetEnvironmentVariable($Name)
    if (-not $value -and $FilePath -and (Test-Path -LiteralPath $FilePath)) {
        $value = (Get-Content -LiteralPath $FilePath -Raw).Trim()
    }
    if (-not $value) {
        $value = Get-UnattendedStoreSecret -Name $Name
    }
    $value
}

function Read-UnattendedSecretPrompt {
    param([Parameter(Mandatory = $true)][string] $Name)
    $secure = Read-Host -Prompt "Secret $Name" -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $value = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
    if (-not $value) {
        throw "secret $Name was not resolved"
    }
    $value
}

function Add-UnattendedSecretPromptStep {
    param([Parameter(Mandatory = $true)][string] $Name)
    Add-UnattendedStep "secret $Name" 'would-run' 'would prompt: not in the environment, the file or the credential store'
}

function Resolve-UnattendedSecret {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [string] $FilePath
    )
    if ($Name -in $script:DeclaredSecrets) {
        return $script:SecretCache[$Name]
    }
    $value = Find-UnattendedSecret -Name $Name -FilePath $FilePath
    if (-not $value) {
        if ($script:Mode -ne 'run') {
            Add-UnattendedSecretPromptStep -Name $Name
            return "<$Name>"
        }
        $value = Read-UnattendedSecretPrompt -Name $Name
    }
    $script:Secrets.Add($value) | Out-Null
    return $value
}

function Initialize-UnattendedSecrets {
    param([hashtable[]] $Secrets = @())
    $script:DeclaredSecrets = @()
    $script:SecretCache = @{}
    $unresolved = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $Secrets) {
        $name = $entry['Name']
        if (-not $name) {
            throw 'a declared secret needs a Name'
        }
        if ($name -in $script:DeclaredSecrets) {
            throw "secret $name is declared twice"
        }
        $script:DeclaredSecrets += $name
        $value = Find-UnattendedSecret -Name $name -FilePath ([string] $entry['FilePath'])
        if ($value) {
            $script:SecretCache[$name] = $value
            $script:Secrets.Add($value) | Out-Null
        } elseif ($script:Mode -ne 'run') {
            Add-UnattendedSecretPromptStep -Name $name
            $script:SecretCache[$name] = "<$name>"
        } else {
            $unresolved.Add($name)
        }
    }
    foreach ($name in $unresolved) {
        $value = Read-UnattendedSecretPrompt -Name $name
        $script:SecretCache[$name] = $value
        $script:Secrets.Add($value) | Out-Null
    }
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

function Invoke-NativeUtf8 {
    param([Parameter(Mandatory = $true)][scriptblock] $Block)
    $priorVariable = $env:WSL_UTF8
    $priorEncoding = [Console]::OutputEncoding
    $env:WSL_UTF8 = '1'
    try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }
    try {
        & $Block
    } finally {
        $env:WSL_UTF8 = $priorVariable
        try { [Console]::OutputEncoding = $priorEncoding } catch { }
    }
}

function Wait-ForState {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][scriptblock] $Predicate,
        [int] $TimeoutSeconds = 300,
        [double] $IntervalSeconds = 5
    )
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
    $script:Held.Add($Name) | Out-Null
    if ($TolerateTakeExit) {
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
        secrets      = $script:DeclaredSecrets.Count
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
        secrets              = @($script:DeclaredSecrets)
        transcript           = $script:TranscriptPath
        redacted             = $true
    }
    if ($dry) {
        $payload['planned'] = $planned
        $payload['delta'] = @($script:Steps | Where-Object { $_.status -eq 'would-run' -or ($_.status -eq 'failed' -and $_.name -ne 'run') })
    }
    $json = $payload | ConvertTo-Json -Depth 6
    foreach ($secret in $script:Secrets) {
        if ($secret) {
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
        [string[]] $Irreversible = @(),
        [hashtable[]] $Secrets = @()
    )
    Initialize-UnattendedResult -ResultDirectory $ResultDirectory
    $script:Irreversible = @($Irreversible)
    if ($script:Mode -ne 'test') {
        Write-Host ('irreversible actions: ' + $(if ($Irreversible.Count) { $Irreversible -join '; ' } else { 'none' }))
        $names = @($Secrets | ForEach-Object { $_['Name'] })
        Write-Host ('secrets: ' + $(if ($names.Count) { $names -join '; ' } else { 'none' }))
    }
    try {
        Initialize-UnattendedSecrets -Secrets $Secrets
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
