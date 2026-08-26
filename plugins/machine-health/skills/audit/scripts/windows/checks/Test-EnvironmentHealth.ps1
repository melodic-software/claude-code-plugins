#Requires -Version 7.4
<#
.SYNOPSIS
Check: persisted environment-variable and PATH health. Emits a CheckResult JSON
on stdout.

See references/windows/check-catalog.md#18-environment-and-path-health for rubric.

.DESCRIPTION
Detect-only. Reads HKCU:\Environment and (when readable)
HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment. Never
writes a registry value, never calls SetEnvironmentVariable, never rewrites
PATH. Credential-pattern variable values are never read.

Findings are mechanical shapes: DISABLE_AUTOUPDATER presence, missing PATH
directories, duplicate PATH entries, shadowed executables, User Path stored
as REG_SZ, User Path length against the 2047-character legacy-editor
ceiling, and credential-pattern variable names (name + scope only).
#>
[CmdletBinding()]
param([switch]$Human)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$id = 'environment-health'
$category = 'config'
$userKeyPath = 'HKCU:\Environment'
$machineKeyPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
$commands = @(
    "Get-Item -LiteralPath '$userKeyPath'"
    "(Get-Item -LiteralPath '$userKeyPath').GetValueKind('Path')"
    "[Environment]::GetEnvironmentVariable('Path', 'User').Length"
    "Get-ItemProperty -LiteralPath '$userKeyPath' -Name DISABLE_AUTOUPDATER"
    "Get-ChildItem Env: | Where-Object Name -match '(_TOKEN|_API_KEY|_SECRET|_PASSWORD)$' | Select-Object Name"
)

# Legacy System Properties editor truncates a User Path REG_SZ/REG_EXPAND_SZ
# at 2047 characters. WARN before that ceiling so a human can act; CRIT at
# the ceiling because further appends are silently lost.
$userPathWarnChars = 1800
$userPathCritChars = 2047

function Test-CredentialVariableName {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory = $true)] [string] $Name)

    return [bool]($Name -match '(?i)(_TOKEN|_API_KEY|_SECRET|_PASSWORD)$' -or
        $Name -in @('TOKEN', 'API_KEY', 'SECRET', 'PASSWORD'))
}

function Test-TruthyEnvValue {
    [CmdletBinding()]
    [OutputType([bool])]
    param([string] $Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return [bool]($Value.Trim() -match '^(?i:1|true|yes|on)$')
}

function Get-NormalizedPathEntry {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] [string] $PathEntry)

    return $PathEntry.Trim().TrimEnd('\', '/').ToLowerInvariant()
}

function Get-ExpandedPathEntry {
    <#
    .SYNOPSIS
    Expand %VAR% tokens in a persisted PATH entry for filesystem and scope use.

    .DESCRIPTION
    Read-PersistentEnvironment keeps REG_EXPAND_SZ values unexpanded so
    user_path_length measures the stored string (legacy-editor ceiling).
    Existence checks and Get-PathScope must expand first: a stock Machine
    Path stores `%SystemRoot%` plus a system32 fragment as a token, and
    Test-Path / live $env:PATH comparisons against that raw token
    false-positive as missing and mislabel scope as 'unknown'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] [string] $PathEntry)

    $expanded = [Environment]::ExpandEnvironmentVariables($PathEntry)
    if ([string]::IsNullOrWhiteSpace($expanded)) { return $PathEntry }
    return $expanded
}

function Split-PathEntries {
    [CmdletBinding()]
    [OutputType([string[]])]
    param([string] $Raw)

    if ([string]::IsNullOrWhiteSpace($Raw)) { return @() }
    return @($Raw -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-DefaultPathext {
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[string]])]
    param()

    $raw = $env:PATHEXT
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $raw = '.COM;.EXE;.BAT;.CMD;.VBS;.VBE;.JS;.JSE;.WSF;.WSH;.MSC;.CPL'
    }
    $list = [System.Collections.Generic.List[string]]::new()
    foreach ($e in @($raw -split ';')) {
        $t = $e.Trim().ToLowerInvariant()
        if ($t) { $list.Add($t) }
    }
    return , $list
}

function Read-PersistentEnvironment {
    <#
    .SYNOPSIS
    Read one Environment registry key as name/kind/value rows.

    .DESCRIPTION
    Credential-pattern names are recorded with value=$null and never passed
    to GetValue. That is the whole point of the check's safety rule: a
    later summary, notes, or exception message cannot leak a secret that
    was never loaded.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory = $true)] [string] $LiteralPath,
        [Parameter(Mandatory = $true)] [string] $Scope
    )

    $key = Get-Item -LiteralPath $LiteralPath -ErrorAction Stop
    $rows = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($name in @($key.GetValueNames())) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $isCredential = Test-CredentialVariableName $name
        $kind = $key.GetValueKind($name).ToString()
        $value = $null
        if (-not $isCredential) {
            # 1 = RegistryValueOptions.DoNotExpandEnvironmentNames. Numeric so
            # the check does not depend on Microsoft.Win32.Registry at parse
            # time (Pester on a non-Windows host still has to load this file).
            $raw = $key.GetValue($name, $null, 1)
            if ($raw -is [string[]]) { $value = ($raw -join ';') }
            elseif ($null -ne $raw) { $value = [string]$raw }
        }
        $rows.Add([pscustomobject]@{
                name       = $name
                scope      = $Scope
                kind       = $kind
                value      = $value
                credential = $isCredential
            })
    }
    return , $rows
}

function Get-PathScope {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)] [string] $Normalized,
        [Parameter(Mandatory = $true)] [hashtable] $UserNorm,
        [Parameter(Mandatory = $true)] [hashtable] $MachineNorm
    )

    $inUser = $UserNorm.ContainsKey($Normalized)
    $inMachine = $MachineNorm.ContainsKey($Normalized)
    if ($inUser -and -not $inMachine) { return 'user' }
    if ($inMachine -and -not $inUser) { return 'machine' }
    if ($inUser -and $inMachine) { return 'both' }
    return 'unknown'
}

function Test-ScopeLowerThanExpected {
    <#
    .SYNOPSIS
    True when the winning PATH entry is a lower-precedence scope than another
    copy of the same executable.

    .DESCRIPTION
    Persisted composition is User then Machine, so User is the higher
    precedence scope. A Machine (or unknown) winner while a User copy also
    exists means the live search order disagrees with that expectation --
    typically a process PATH that lists a system directory first.
    'both' counts as User-precedence (the directory is on the User Path).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)] [string] $WinnerScope,
        [Parameter(Mandatory = $true)] [string[]] $OtherScopes
    )

    $userPresent = $OtherScopes -contains 'user' -or $OtherScopes -contains 'both'
    if (-not $userPresent) { return $false }
    return $WinnerScope -in @('machine', 'unknown')
}

function New-FindingList {
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[object]])]
    param()
    # Unary comma: an empty List enumerates to nothing, so a bare return
    # would bind $null and the next .Count would throw under StrictMode.
    return , [System.Collections.Generic.List[object]]::new()
}

try {
    $machineVars = @()
    $machineReadable = $true
    $machineError = $null

    $userVars = Read-PersistentEnvironment -LiteralPath $userKeyPath -Scope 'user'

    try {
        $machineVars = Read-PersistentEnvironment -LiteralPath $machineKeyPath -Scope 'machine'
    } catch {
        $machineReadable = $false
        $machineError = $_.Exception.Message
        Write-Verbose "Test-EnvironmentHealth: machine Environment unreadable. $machineError"
    }

    $allVars = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($row in $userVars) { $allVars.Add($row) }
    foreach ($row in $machineVars) { $allVars.Add($row) }

    $disableFindings = New-FindingList
    foreach ($row in $allVars) {
        if ($row.name -ne 'DISABLE_AUTOUPDATER') { continue }
        $disableFindings.Add([pscustomobject]@{
                scope           = $row.scope
                set             = $true
                disables_updates = Test-TruthyEnvValue $row.value
            })
    }

    $credentialFindings = New-FindingList
    foreach ($row in $allVars) {
        if (-not $row.credential) { continue }
        $credentialFindings.Add([pscustomobject]@{
                name  = $row.name
                scope = $row.scope
            })
    }

    $userPathRow = $null
    foreach ($row in $userVars) {
        if ($row.name -eq 'Path') { $userPathRow = $row; break }
    }
    $machinePathRow = $null
    foreach ($row in $machineVars) {
        if ($row.name -eq 'Path') { $machinePathRow = $row; break }
    }

    $userPathKind = $null
    $userPathRaw = ''
    if ($null -ne $userPathRow) {
        $userPathKind = $userPathRow.kind
        $userPathRaw = [string]$userPathRow.value
    }
    $userPathIsExpand = $userPathKind -eq 'ExpandString'
    $userPathLength = $userPathRaw.Length

    $machinePathRaw = ''
    if ($null -ne $machinePathRow) { $machinePathRaw = [string]$machinePathRow.value }
    $userEntries = [System.Collections.Generic.List[string]]::new()
    foreach ($e in @(Split-PathEntries $userPathRaw)) { $userEntries.Add($e) }
    $machineEntries = [System.Collections.Generic.List[string]]::new()
    foreach ($e in @(Split-PathEntries $machinePathRaw)) { $machineEntries.Add($e) }

    $userNorm = @{}
    foreach ($e in $userEntries) {
        $userNorm[(Get-NormalizedPathEntry (Get-ExpandedPathEntry $e))] = $true
    }
    $machineNorm = @{}
    foreach ($e in $machineEntries) {
        $machineNorm[(Get-NormalizedPathEntry (Get-ExpandedPathEntry $e))] = $true
    }

    $persistedEntries = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($e in $userEntries) {
        $expanded = Get-ExpandedPathEntry $e
        $persistedEntries.Add([pscustomobject]@{
                path     = $e
                expanded = $expanded
                scope    = 'user'
                norm     = (Get-NormalizedPathEntry $expanded)
            })
    }
    foreach ($e in $machineEntries) {
        $expanded = Get-ExpandedPathEntry $e
        $persistedEntries.Add([pscustomobject]@{
                path     = $e
                expanded = $expanded
                scope    = 'machine'
                norm     = (Get-NormalizedPathEntry $expanded)
            })
    }

    $missingDirs = New-FindingList
    foreach ($e in $persistedEntries) {
        $exists = $false
        try {
            $exists = Test-Path -LiteralPath $e.expanded -PathType Container -ErrorAction Stop
        } catch {
            $exists = $false
        }
        if (-not $exists) {
            $missingDirs.Add([pscustomobject]@{ path = $e.path; scope = $e.scope })
        }
    }

    $duplicateFindings = New-FindingList
    $byNorm = $persistedEntries | Group-Object -Property norm
    foreach ($g in $byNorm) {
        if ($g.Count -lt 2) { continue }
        $scopes = @($g.Group | ForEach-Object { $_.scope } | Select-Object -Unique)
        $duplicateFindings.Add([pscustomobject]@{
                path   = $g.Group[0].path
                count  = $g.Count
                scopes = @($scopes)
            })
    }

    # Live search order is the process PATH (what CreateProcess actually
    # walks). Scope labels still come from the persisted User/Machine lists
    # so a conda-prepended directory is 'unknown' rather than mislabeled.
    $processEntries = [System.Collections.Generic.List[string]]::new()
    foreach ($p in @(Split-PathEntries $env:PATH)) { $processEntries.Add($p) }
    if ($processEntries.Count -eq 0) {
        foreach ($p in @($userEntries) + @($machineEntries)) {
            $processEntries.Add((Get-ExpandedPathEntry $p))
        }
    }

    $pathext = Get-DefaultPathext
    $nameToHits = @{}
    foreach ($dir in $processEntries) {
        $exists = $false
        try { $exists = Test-Path -LiteralPath $dir -PathType Container -ErrorAction SilentlyContinue } catch { $exists = $false }
        if (-not $exists) { continue }

        $files = @()
        try {
            $files = @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)
        } catch {
            Write-Verbose "Test-EnvironmentHealth: listing '$dir' failed. $($_.Exception.Message)"
            continue
        }

        $norm = Get-NormalizedPathEntry $dir
        $scope = Get-PathScope -Normalized $norm -UserNorm $userNorm -MachineNorm $machineNorm
        foreach ($f in $files) {
            $ext = $f.Extension.ToLowerInvariant()
            if ($ext -and $ext -notin $pathext) { continue }
            $exeName = $f.Name.ToLowerInvariant()
            if (-not $nameToHits.ContainsKey($exeName)) {
                $nameToHits[$exeName] = [System.Collections.Generic.List[pscustomobject]]::new()
            }
            $nameToHits[$exeName].Add([pscustomobject]@{
                    path  = $dir
                    scope = $scope
                    file  = $f.Name
                })
        }
    }

    $shadowed = New-FindingList
    foreach ($exeName in ($nameToHits.Keys | Sort-Object)) {
        $hits = $nameToHits[$exeName]
        $uniqueNorms = [System.Collections.Generic.List[string]]::new()
        foreach ($h in $hits) {
            $n = Get-NormalizedPathEntry $h.path
            if (-not $uniqueNorms.Contains($n)) { $uniqueNorms.Add($n) }
        }
        if ($uniqueNorms.Count -lt 2) { continue }
        $winner = $hits[0]
        $others = [System.Collections.Generic.List[pscustomobject]]::new()
        $otherScopes = [System.Collections.Generic.List[string]]::new()
        $otherPaths = [System.Collections.Generic.List[string]]::new()
        for ($i = 1; $i -lt $hits.Count; $i++) {
            $others.Add($hits[$i])
            $otherScopes.Add($hits[$i].scope)
            $otherPaths.Add($hits[$i].path)
        }
        $warn = Test-ScopeLowerThanExpected -WinnerScope $winner.scope -OtherScopes @($otherScopes)
        $shadowed.Add([pscustomobject]@{
                name         = $winner.file
                winner_path  = $winner.path
                winner_scope = $winner.scope
                other_paths  = $otherPaths
                warn         = $warn
            })
    }

    # Severity ladder (most severe first). No finding here writes anything;
    # CRIT is reserved for the User Path length ceiling because further
    # appends are silently discarded by the legacy editor. Everything else
    # is a shape a human decides what to do with.
    $severity = 'OK'
    $reasons = [System.Collections.Generic.List[string]]::new()

    if ($userPathLength -ge $userPathCritChars) {
        $severity = 'CRIT'
        $reasons.Add("User PATH length $userPathLength (legacy-editor ceiling $userPathCritChars)")
    } elseif ($userPathLength -ge $userPathWarnChars) {
        $severity = 'WARN'
        $reasons.Add("User PATH length $userPathLength (WARN at $userPathWarnChars)")
    }

    if ($userPathKind -eq 'String') {
        if ($severity -eq 'OK') { $severity = 'WARN' }
        $reasons.Add('User Path is REG_SZ (breaks %TOKEN% expansion)')
    }

    $truthyDisable = New-FindingList
    foreach ($d in $disableFindings) {
        if ($d.disables_updates) { $truthyDisable.Add($d) }
    }
    if ($truthyDisable.Count -gt 0) {
        if ($severity -eq 'OK') { $severity = 'WARN' }
        $scopes = [System.Collections.Generic.List[string]]::new()
        foreach ($d in $truthyDisable) { $scopes.Add($d.scope) }
        $reasons.Add("DISABLE_AUTOUPDATER set ($($scopes -join ', '))")
    }

    if ($credentialFindings.Count -gt 0) {
        if ($severity -eq 'OK') { $severity = 'WARN' }
        $reasons.Add("$($credentialFindings.Count) credential-named variable(s)")
    }

    $shadowWarns = New-FindingList
    foreach ($s in $shadowed) {
        if ($s.warn) { $shadowWarns.Add($s) }
    }
    if ($shadowWarns.Count -gt 0) {
        if ($severity -eq 'OK') { $severity = 'WARN' }
        $reasons.Add("$($shadowWarns.Count) shadowed executable(s) with lower-precedence winner")
    }

    $infoBits = [System.Collections.Generic.List[string]]::new()
    if ($missingDirs.Count -gt 0) { $infoBits.Add("$($missingDirs.Count) missing PATH dir(s)") }
    if ($duplicateFindings.Count -gt 0) { $infoBits.Add("$($duplicateFindings.Count) duplicate PATH entry group(s)") }
    $shadowInfo = $shadowed.Count - $shadowWarns.Count
    if ($shadowInfo -gt 0) { $infoBits.Add("$shadowInfo shadowed executable name(s)") }
    $falsyDisable = New-FindingList
    foreach ($d in $disableFindings) {
        if (-not $d.disables_updates) { $falsyDisable.Add($d) }
    }
    if ($falsyDisable.Count -gt 0) { $infoBits.Add('DISABLE_AUTOUPDATER set but not truthy') }

    if ($infoBits.Count -gt 0) {
        if ($severity -eq 'OK') { $severity = 'INFO' }
        foreach ($b in $infoBits) { $reasons.Add($b) }
    }

    if ($severity -eq 'OK') {
        $summary = 'Environment and PATH look healthy.'
    } else {
        $summary = ($reasons -join '; ')
        if ($summary.Length -gt 240) { $summary = $summary.Substring(0, 237) + '...' }
    }

    $notes = 'Detect-only. No remediation -- registry writes are never authorized.'
    if (-not $machineReadable) {
        $notes = "$notes Machine Environment unreadable; User-scope findings only."
    }

    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity $severity -Summary $summary -Commands $commands `
        -Detail @{
        disable_autoupdater      = $disableFindings
        missing_path_dirs        = $missingDirs
        duplicate_path_entries   = $duplicateFindings
        shadowed_executables     = $shadowed
        credential_named_vars    = $credentialFindings
        user_path_kind           = $userPathKind
        user_path_is_expand_sz   = $userPathIsExpand
        user_path_length         = $userPathLength
        machine_scope_readable   = $machineReadable
        process_path_entry_count = $processEntries.Count
    } `
        -NeedsAdmin $false -RanSuccessfully $true `
        -Notes $notes `
        -DurationMs ([int]$sw.ElapsedMilliseconds)
} catch {
    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity 'UNKNOWN' -Summary 'Environment and PATH health check failed.' -Commands $commands `
        -RanSuccessfully $false -ErrorMessage $_.Exception.Message `
        -DurationMs ([int]$sw.ElapsedMilliseconds)
}

$sw.Stop()
$result.duration_ms = [int]$sw.ElapsedMilliseconds
$result | Write-HealthResult -Human:$Human
