# Unattended PowerShell procedure. The agent authors stages and never runs this
# file. The human launches it from a shell that is not inside the thing the
# procedure restarts (a Windows host, not the WSL distro being terminated).
#
# Elevation is checked both ways with WindowsPrincipal.IsInRole
# (https://learn.microsoft.com/en-us/dotnet/api/system.security.principal.windowsprincipal.isinrole).
# The transcript is Start-Transcript
# (https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.host/start-transcript)
# and secret values captured at runtime are removed from it before the JSON is final.
#
# Claim: a Windows elevated token is WindowsBuiltInRole.Administrator via IsInRole.
# Basis: the IsInRole page above, WindowsBuiltInRole.Administrator.
# As of: 2026-09-28.
# Recheck: that page stops naming WindowsBuiltInRole, or Start-Transcript stops writing the path it prints.
param()
$ErrorActionPreference = 'Stop'
if (-not $env:RESULT_DIR) { $env:RESULT_DIR = Join-Path (Get-Location) 'unattended-result' }
if (-not $env:RESULT_NAME) { $env:RESULT_NAME = 'result' }
New-Item -ItemType Directory -Force -Path $env:RESULT_DIR | Out-Null
$script:Overall = 'ok'
$script:Steps = @()
$script:Held = @()
$script:Secrets = @()
$script:Transcript = Join-Path $env:RESULT_DIR ($env:RESULT_NAME + '.log')

function Scrub([string]$Text) {
  foreach ($secret in $script:Secrets) {
    if ($secret) { $Text = $Text.Replace($secret, '[redacted]') }
  }
  return $Text
}

function Add-Step([string]$Id, [string]$Status, [string]$Detail) {
  $clean = Scrub $Detail
  $script:Steps += [pscustomobject]@{ id = $Id; status = $Status; detail = $clean }
  if ($Status -eq 'failed') { $script:Overall = 'failed' }
}

function Test-Administrator {
  if (-not $IsWindows) {
    return ((& id -u) -eq '0')
  }
  $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Require-Elevated {
  if (Test-Administrator) { Add-Step 'privilege' 'ok' 'elevated'; return }
  Add-Step 'privilege' 'failed' 'must run elevated'
  throw 'must run elevated'
}

function Refuse-Elevated {
  if (-not (Test-Administrator)) { Add-Step 'privilege' 'ok' 'not elevated'; return }
  Add-Step 'privilege' 'failed' 'must not run elevated'
  throw 'must not run elevated'
}

function Refuse-IfEnv([string]$Name, [string]$Banned) {
  $current = [Environment]::GetEnvironmentVariable($Name)
  if ($Banned -and $current -eq $Banned) {
    Add-Step 'not-inside' 'failed' "refusing to run inside ${Name}=$Banned"
    throw "inside $Name"
  }
  Add-Step 'not-inside' 'ok' "$Name is not $Banned"
}

function Resolve-Secret([string]$Name, [string]$File) {
  $fromEnv = [Environment]::GetEnvironmentVariable($Name)
  if ($fromEnv) { $script:Secrets += $fromEnv; return $fromEnv }
  if ($File -and (Test-Path -LiteralPath $File)) {
    foreach ($line in Get-Content -LiteralPath $File) {
      if ($line.StartsWith("$Name=")) {
        $value = $line.Substring($Name.Length + 1)
        $script:Secrets += $value
        return $value
      }
    }
  }
  $secure = Read-Host "Enter $Name" -AsSecureString
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    $value = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
  }
  $script:Secrets += $value
  return $value
}

function Assert-Preflight([string]$Name, [string]$Remedy) {
  if (Get-Command $Name -ErrorAction SilentlyContinue) {
    Add-Step "preflight-$Name" 'ok' 'present'
    return
  }
  Add-Step "preflight-$Name" 'failed' "missing $Name; $Remedy"
  throw "preflight $Name"
}

function Invoke-Step([string]$Id, [scriptblock]$Action) {
  $latest = Join-Path $env:RESULT_DIR ($env:RESULT_NAME + '-latest.json')
  if ($env:FORCE -ne '1' -and (Test-Path -LiteralPath $latest)) {
    $prior = Get-Content -LiteralPath $latest -Raw
    $pattern = '"id"\s*:\s*"' + [regex]::Escape($Id) + '"[\s\S]{0,120}"status"\s*:\s*"ok"'
    if ($prior -match $pattern) {
      Add-Step $Id 'skipped' 'already ok'
      return
    }
  }
  try {
    & $Action
    Add-Step $Id 'ok' 'done'
  } catch {
    Add-Step $Id 'failed' $_.Exception.Message
    throw
  }
}

function Hold([string]$Name) { $script:Held += $Name }
function Release([string]$Name) {
  $script:Held = @($script:Held | Where-Object { $_ -ne $Name })
}

function Write-Result {
  $doc = [pscustomobject]@{
    schema = 'wizard-unattended/1'
    status = $script:Overall
    transcript = $script:Transcript
    steps = $script:Steps
    held = $script:Held
  }
  $json = $doc | ConvertTo-Json -Depth 6
  $json = Scrub $json
  $path = Join-Path $env:RESULT_DIR ($env:RESULT_NAME + '.json')
  $latest = Join-Path $env:RESULT_DIR ($env:RESULT_NAME + '-latest.json')
  Set-Content -LiteralPath $path -Value $json -Encoding utf8
  Copy-Item -LiteralPath $path -Destination $latest -Force
}

if ($env:WIZARD_UNATTENDED_LIB -eq '1') { return }

Start-Transcript -LiteralPath $script:Transcript -Force | Out-Null
try {
  # --- STAGES (replace; do not edit above) ---
  Refuse-Elevated
  Add-Step 'example' 'ok' 'done'
} catch {
  if ($script:Overall -eq 'ok') { Add-Step 'uncaught' 'failed' $_.Exception.Message }
} finally {
  try { Stop-Transcript | Out-Null } catch { }
  Write-Result
}
if ($script:Overall -ne 'ok') { exit 1 }
