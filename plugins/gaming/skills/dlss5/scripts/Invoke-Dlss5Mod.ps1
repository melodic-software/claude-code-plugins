#Requires -Version 7
# Install/remove the OptiScaler DLSS-NR mod in a game exe dir, with a pre-install snapshot and a
# file manifest so removal leaves the folder byte-identical. All state lives under -DataDir.
param(
    [Parameter(Mandatory)][ValidateSet('assess', 'provision', 'apply', 'status', 'remove', 'selftest')][string]$Verb,
    [Parameter(Position = 0)][string]$GameDir,
    [string]$Build = 'dagherbou',
    [string]$Proxy = 'dxgi.dll',
    [string]$DataDir,
    [string]$RuntimeDll,
    [string]$RuntimeSource,
    [string[]]$ScanRoots,
    [switch]$Runtime,
    [switch]$RestoreComputeSignature,
    [switch]$AllowUnknownRuntime,
    [switch]$Finish,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'

$ModelHash = 'E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E'
$MinRuntimeVersion = [version]'310.8.0.0'
$BuildFiles = @{
    dagherbou = @('OptiScaler.dll', 'OptiScaler.ini', 'OptiScaler', 'Licenses', 'nvngx.dll_dlssnr.dll')
    wilsjo2   = @('OptiScaler.dll', 'OptiScaler.ini', 'OptiScaler', 'Licenses')
}
# Pinned release assets. The dagherbou hash is a local-copy attestation (the release publishes no
# checksum); the wilsjo2 hash matches the release's own .sha256 sidecar.
$BuildPins = @{
    dagherbou = @{
        Tag = 'v0.2.0-patch1'; Asset = 'OptiScaler-DLSSNR-v0.2.0-onimusha-fix.zip'
        Url = 'https://github.com/Dagherbou/OptiScaler_DLSSNR/releases/download/v0.2.0-patch1/OptiScaler-DLSSNR-v0.2.0-onimusha-fix.zip'
        Sha256 = '5DB547216FA8A7DBD8AB0A193DA1E3BCE0EA4BD71F91189AFA4ED2EDE8BB9561'
    }
    wilsjo2   = @{
        Tag = 'v0.8.3'; Asset = 'OptiScaler-NR-v0.8.3.zip'
        Url = 'https://github.com/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass/releases/download/v0.8.3/OptiScaler-NR-v0.8.3.zip'
        Sha256 = '3F2D26FB136D964A394BF50896D082156173153A2A55B88E1995277B4DABE3C8'
    }
}
$ProxyNames = @('dxgi.dll', 'dbghelp.dll', 'winmm.dll', 'version.dll')
# Mirrors reference/anticheat-posture.md; change both together.
$AntiCheatTokens = @('EasyAntiCheat', 'EasyAntiCheat_EOS', 'BattlEye', 'BEService', 'ACE')
$ModDirs = @('OptiScaler', 'Licenses', 'dlssnr-capture', 'OptiScalerProfiles')
$script:fails = 0
$script:FaultAfter = 0   # selftest hook: throw after this many copies

# An unset userConfig option arrives empty or as its own literal ${user_config.KEY} token.
function Resolve-Opt([string]$v) { if (-not $v -or $v.StartsWith('${user_config.')) { $null } else { $v } }
function Resolve-PathOpt([string]$v) {
    $v = Resolve-Opt $v
    if (-not $v) { return $null }
    $full = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($v), (Get-Location).ProviderPath)
    if ($full.Length -gt 3) { $full.TrimEnd('\') } else { $full }
}
function Resolve-DataDir([string]$v) {
    (Resolve-PathOpt $v) ?? (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Gaming')
}
function Resolve-Source([string]$v) {
    $v = Resolve-Opt $v
    if (-not $v) { return $null }
    if ($v -match '[?&]sig=') { throw 'runtime_source carries a SAS token (sig=); use the plain URL and az login instead' }
    if ($v -match '^https://') { return $v }
    if ($v -match '^[A-Za-z][A-Za-z0-9+.-]*://') { throw "runtime_source must be an https:// URL or a path: $v" }
    Resolve-PathOpt $v
}
function Init-Paths {
    $script:DataDir = Resolve-DataDir $DataDir
    $script:RuntimeDllConfigured = [bool](Resolve-PathOpt $RuntimeDll)
    $script:RuntimeDll = (Resolve-PathOpt $RuntimeDll) ?? (Join-Path $script:DataDir 'runtime\nvngx_dlssnr.dll')
    # runtime_source is resolved only by provision -Runtime, so a bad value never blocks status or remove.
}

function Root($d) {
    if (-not $d) { throw 'GameDir required' }
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { throw "not a directory: $d" }
    [IO.Path]::GetFullPath($d).TrimEnd('\')
}
# Readable prefix (steamapps\common\<X> segment, else leaf) plus a path hash, so two exe dirs
# both named Win64 never share state.
function GameKey($root) {
    $prefix = if ($root -match '\\steamapps\\common\\([^\\]+)') { $Matches[1] } else { Split-Path $root -Leaf }
    $h = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant())))
    ($prefix -replace '[^A-Za-z0-9_-]', '_') + '_' + $h.Substring(0, 8).ToLowerInvariant()
}
function StateDir($root) { Join-Path $script:DataDir ('state\' + (GameKey $root)) }
function LoadJson($p) { if (Test-Path -LiteralPath $p) { Get-Content -LiteralPath $p -Raw | ConvertFrom-Json } }
function Load-Snapshot($root) {
    $s = LoadJson (Join-Path (StateDir $root) 'snapshot.json')
    if ($s -and $s.gameDir -ne $root) { throw "state records gameDir '$($s.gameDir)', not '$root'; refusing" }
    $s
}
# manifest.json, or pending.json left by an interrupted apply.
function Load-Manifest($root) {
    foreach ($n in 'manifest.json', 'pending.json') {
        $m = LoadJson (Join-Path (StateDir $root) $n)
        if ($m) {
            if ($m.gameDir -ne $root) { throw "state records gameDir '$($m.gameDir)', not '$root'; refusing" }
            return $m
        }
    }
}

# ponytail: re-hashes the whole tree on every snapshot/status/remove. Fine up to a few GB;
# if it drags, gate on Length+LastWriteTime and only hash when those differ.
function Tree($root) {
    $t = @{}   # plain hashtable = case-insensitive keys
    foreach ($f in Get-ChildItem -LiteralPath $root -Recurse -File -Force) {
        $t[$f.FullName.Substring($root.Length + 1)] = @{
            Length = $f.Length; Sha256 = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
        }
    }
    $t
}
# Mirrors the byproduct rows of reference/reversal-matrix.md; change both together.
function IsByproduct($rel) {
    $rel -in 'OptiScaler.log', 'OptiScaler.asi' -or $rel -like 'dlssnr-capture\*' -or $rel -like 'OptiScalerProfiles\*'
}

function IsAntiCheatName($name) {
    $b = [IO.Path]::GetFileNameWithoutExtension($name)
    foreach ($t in $AntiCheatTokens) { if ($b -eq $t -or $b -like "${t}_*") { return $true } }
    $false
}
# Scans from the game root, not the exe dir: EasyAntiCheat\ sits beside the root while the exe is
# two or three levels down. ponytail: name match with capped depth; server-side or
# launcher-delivered anti-cheat leaves nothing on disk, which assess's store-page check covers.
function Find-AntiCheat($root) {
    $items = if ($root -match '^(.*\\steamapps\\common\\[^\\]+)') {
        Get-ChildItem -LiteralPath $Matches[1] -Recurse -Depth 4 -Force -ErrorAction SilentlyContinue
    }
    else {
        Get-ChildItem -LiteralPath $root -Recurse -Depth 4 -Force -ErrorAction SilentlyContinue
        $p = $root
        for ($i = 0; $i -lt 4; $i++) {
            $p = Split-Path $p -Parent
            if (-not $p -or $p.Length -le 3) { break }   # stop at the drive root
            Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue
        }
    }
    @($items | Where-Object { IsAntiCheatName $_.Name } | ForEach-Object FullName | Sort-Object -Unique)
}

# Known hash passes. An unknown hash passes only with a valid NVIDIA signature at or above the
# minimum version AND -AllowUnknownRuntime.
function Test-Runtime($path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @{ Ok = $false; Reason = "missing: $path" } }
    $h = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($h -eq $script:ModelHash) { return @{ Ok = $true; Hash = $h; Known = $true } }
    $sig = Get-AuthenticodeSignature -LiteralPath $path
    $ver = if ((Get-Item -LiteralPath $path).VersionInfo.FileVersion -match '^\d+(\.\d+){1,3}') { [version]$Matches[0] }
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'CN=NVIDIA Corporation' -or -not $ver -or $ver -lt $MinRuntimeVersion) {
        return @{ Ok = $false; Hash = $h; Reason = "unknown hash $h without a valid NVIDIA signature at $MinRuntimeVersion or later" }
    }
    if (-not $AllowUnknownRuntime) {
        return @{ Ok = $false; Hash = $h; Reason = "unknown hash $h (NVIDIA-signed, version $ver); pass -AllowUnknownRuntime to accept it" }
    }
    @{ Ok = $true; Hash = $h; Known = $false }
}

# Section-aware ini value replace, preserving BOM and per-line CR.
function Edit-Ini($path, $edits) {
    $hadBom = $false
    $b = [IO.File]::ReadAllBytes($path)
    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { $hadBom = $true }
    $lines = [IO.File]::ReadAllText($path) -split "`n"
    $sec = ''; $seen = @{}
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[([^\]]+)\]') { $sec = $Matches[1]; continue }
        foreach ($e in $edits) {
            if (($null -eq $e.Section -or $e.Section -eq $sec) -and $lines[$i] -match "^\s*$($e.Key)\s*=") {
                $lines[$i] = $lines[$i] -replace "^(\s*$($e.Key)\s*=)[^\r]*", "`${1}$($e.Value)"
                $seen["$($e.Section)/$($e.Key)"] = $true
                break
            }
        }
    }
    foreach ($e in $edits) {
        if (-not $seen["$($e.Section)/$($e.Key)"]) { Write-Warning "ini key not found, not set: [$($e.Section)] $($e.Key)=$($e.Value)" }
    }
    [IO.File]::WriteAllText($path, ($lines -join "`n"), [Text.UTF8Encoding]::new($hadBom))
}

function Do-Snapshot($root) {
    $sp = Join-Path (StateDir $root) 'snapshot.json'
    $t = Tree $root
    [pscustomobject]@{
        gameDir = $root; taken = (Get-Date).ToString('o')
        files   = @($t.Keys | Sort-Object | ForEach-Object { [pscustomobject]@{ Path = $_; Length = $t[$_].Length; Sha256 = $t[$_].Sha256 } })
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $sp -Encoding utf8
    "snapshot: $($t.Count) files -> $sp"
}

function Remove-EmptyModDirs($root, $snapPaths) {
    foreach ($d in $ModDirs) {
        $dp = Join-Path $root $d
        if (-not (Test-Path -LiteralPath $dp -PathType Container)) { continue }
        if ($snapPaths | Where-Object { $_ -like "$d\*" }) { continue }   # dir predates the mod
        if (Get-ChildItem -LiteralPath $dp -Recurse -File -Force) { continue }   # unknown leftovers
        Remove-Item -LiteralPath $dp -Recurse -Force
    }
}

function Do-Apply($root) {
    $sd = StateDir $root
    if ((Test-Path -LiteralPath "$sd\manifest.json") -or (Test-Path -LiteralPath "$sd\pending.json")) { throw 'already applied, run remove first' }
    $files = $BuildFiles[$Build]
    if (-not $files) { throw "unknown build '$Build' (have: $($BuildFiles.Keys -join ', '))" }

    # Refusal gates. All run before any write, the state directory included.
    if (-not (Get-ChildItem -LiteralPath $root -Filter *.exe -File)) { throw "no *.exe in $root; pass the directory that holds the game executable" }
    $opts = [IO.EnumerationOptions]@{ RecurseSubdirectories = $true; IgnoreInaccessible = $true; AttributesToSkip = 0 }
    $n = @([IO.Directory]::EnumerateFiles($root, '*', $opts) | Select-Object -First 2001).Count
    # 2000 is judgment, not measured: it catches a library or game root passed by mistake.
    if ($n -gt 2000 -and -not $Force) { throw "over 2000 files under $root; is this a game or library root rather than the exe directory? Pass -Force if it is right" }
    $ac = Find-AntiCheat $root
    if ($ac) { throw "anti-cheat on disk, refusing: $($ac -join ', ')" }

    $src = Join-Path $script:DataDir "builds\$Build"
    $plan = [Collections.ArrayList]::new()
    foreach ($item in $files) {
        $p = Join-Path $src $item
        if (-not (Test-Path -LiteralPath $p)) { throw "missing build file: $p (run /gaming:setup apply)" }
        if (Test-Path -LiteralPath $p -PathType Container) {
            foreach ($f in Get-ChildItem -LiteralPath $p -Recurse -File) {
                [void]$plan.Add(@{ From = $f.FullName; To = $f.FullName.Substring($src.Length + 1) })
            }
        }
        else {
            $to = if ($item -eq 'OptiScaler.dll') { $Proxy } else { $item }
            [void]$plan.Add(@{ From = $p; To = $to })
        }
    }
    [void]$plan.Add(@{ From = $script:RuntimeDll; To = 'nvngx_dlssnr.dll' })
    $hit = @($plan | Where-Object { Test-Path -LiteralPath (Join-Path $root $_.To) } | ForEach-Object { $_.To })
    if ($hit) { throw "destination collision, nothing copied: $($hit -join ', ')" }
    $rt = Test-Runtime $script:RuntimeDll
    if (-not $rt.Ok) { throw "runtime DLL refused: $($rt.Reason)" }

    # Always a fresh snapshot: with no manifest the tree is pre-install, and an old snapshot may
    # predate a game update.
    New-Item -ItemType Directory -Force -Path $sd | Out-Null
    Do-Snapshot $root
    $added = @($plan | ForEach-Object { $_.To } | Sort-Object)
    $pp = Join-Path $sd 'pending.json'
    [pscustomobject]@{ gameDir = $root; build = $Build; files = @($added | ForEach-Object { [pscustomobject]@{ Path = $_ } }) } |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $pp -Encoding utf8
    $copied = [Collections.ArrayList]::new()
    try {
        foreach ($e in $plan) {
            if ($script:FaultAfter -and $copied.Count -ge $script:FaultAfter) { throw 'injected copy fault' }
            $d = Join-Path $root $e.To
            New-Item -ItemType Directory -Force -Path (Split-Path $d -Parent) | Out-Null
            [void]$copied.Add($d)   # before the copy: a partial file must roll back too; the collision gate proved it was absent
            Copy-Item -LiteralPath $e.From -Destination $d
        }
        $edits = @(
            @{ Section = 'DlssNr'; Key = 'Enabled'; Value = 'true' }
            @{ Section = 'DlssNr'; Key = 'AutoCapture'; Value = 'false' }
            @{ Section = 'Log'; Key = 'LogToFile'; Value = 'true' }
            @{ Section = 'Log'; Key = 'LogLevel'; Value = '2' }
        )
        if ($RestoreComputeSignature) { $edits += @{ Section = $null; Key = 'RestoreComputeSignature'; Value = 'true' } }
        Edit-Ini (Join-Path $root 'OptiScaler.ini') $edits
    }
    catch {
        $copied | ForEach-Object { Remove-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue }
        Remove-EmptyModDirs $root @((Load-Snapshot $root).files.Path)
        # Keep pending.json while anything it names survives, so remove can still find it.
        if (-not ($copied | Where-Object { Test-Path -LiteralPath $_ })) { Remove-Item -LiteralPath $pp -Force }
        throw
    }

    $drv = try { (& nvidia-smi --query-gpu=driver_version --format=csv,noheader | Select-Object -First 1).Trim() } catch { 'unknown' }
    [pscustomobject]@{
        gameDir = $root; build = $Build; proxy = $Proxy; applied = (Get-Date).ToString('o'); driver = $drv
        restoreComputeSignature = [bool]$RestoreComputeSignature
        runtimeHash = $rt.Hash; runtimeKnown = $rt.Known
        files = @($added | ForEach-Object {
                [pscustomobject]@{ Path = $_; Sha256 = (Get-FileHash -LiteralPath (Join-Path $root $_) -Algorithm SHA256).Hash } })
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $sd 'manifest.json') -Encoding utf8
    Remove-Item -LiteralPath $pp -Force

    "applied $Build (proxy $Proxy, driver $drv) -> $root"
    $added | ForEach-Object { "  + $_" }
}

# Bad = drift that is not expected: a changed or removed pre-install file, or a manifest file
# missing or changed. OptiScaler.ini is rewritten by the overlay's Save Settings, so its drift is expected.
function Get-Stat($root) {
    $sn = Load-Snapshot $root
    if (-not $sn) { throw "no snapshot for $root; nothing has been applied here" }
    $snap = @{}; foreach ($e in @($sn.files)) { $snap[$e.Path] = $e.Sha256 }
    $mj = Load-Manifest $root
    $man = @{}; if ($mj) { foreach ($e in @($mj.files)) { $man[$e.Path] = $e.Sha256 } }
    $now = Tree $root
    $added = @(); $mod = @(); $rem = @(); $mMiss = @(); $mMod = @()
    foreach ($k in $now.Keys) {
        if ($snap.ContainsKey($k)) {
            if ($snap[$k] -ne $now[$k].Sha256) { $mod += $k }
        }
        else {
            $kind = if ($man.ContainsKey($k)) { 'manifest' } elseif (IsByproduct $k) { 'byproduct' } else { 'unknown' }
            $added += [pscustomobject]@{ Path = $k; Kind = $kind }
        }
    }
    foreach ($k in $snap.Keys) { if (-not $now.ContainsKey($k)) { $rem += $k } }
    foreach ($k in $man.Keys) {
        if (-not $now.ContainsKey($k)) { $mMiss += $k }
        elseif ($man[$k] -and $k -ne 'OptiScaler.ini' -and $man[$k] -ne $now[$k].Sha256) { $mMod += $k }
    }
    [pscustomobject]@{
        Added = @($added | Sort-Object Path); Modified = @($mod | Sort-Object); Removed = @($rem | Sort-Object)
        ManifestMissing = @($mMiss | Sort-Object); ManifestModified = @($mMod | Sort-Object)
        Pending = [bool]($mj -and -not $mj.applied)
        Bad = [bool]($mod.Count + $rem.Count + $mMiss.Count + $mMod.Count)
    }
}
function Show-Stat($s, [switch]$NoManifest) {
    if ($s.Pending) { 'INTERRUPTED APPLY: pending.json present; run remove to roll it back' }
    "ADDED ($($s.Added.Count))"; $s.Added | ForEach-Object { "  $($_.Path)  [$($_.Kind)]" }
    "MODIFIED ($($s.Modified.Count))"; $s.Modified | ForEach-Object { "  $_" }
    "REMOVED ($($s.Removed.Count))"; $s.Removed | ForEach-Object { "  $_" }
    if (-not $NoManifest) {
        if ($s.ManifestMissing) { "MANIFEST FILES MISSING ($($s.ManifestMissing.Count))"; $s.ManifestMissing | ForEach-Object { "  $_" } }
        if ($s.ManifestModified) { "MANIFEST FILES CHANGED ($($s.ManifestModified.Count))"; $s.ManifestModified | ForEach-Object { "  $_" } }
    }
}

function Do-Remove($root) {
    $sd = StateDir $root
    $mj = Load-Manifest $root
    if (-not $mj) { throw "no manifest for $root, nothing to remove" }
    $s0 = Get-Stat $root
    $del = @($mj.files | ForEach-Object Path) + @($s0.Added | Where-Object Kind -eq 'byproduct' | ForEach-Object Path)
    foreach ($p in $del) {
        $f = Join-Path $root $p
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force }
    }
    $unknown = @($s0.Added | Where-Object Kind -eq 'unknown' | ForEach-Object Path)
    if ($unknown) { 'kept (unknown, not ours):'; $unknown | ForEach-Object { "  ? $_" } }
    Remove-EmptyModDirs $root @((Load-Snapshot $root).files.Path)
    $s = Get-Stat $root
    Show-Stat $s -NoManifest
    if (($s.Modified.Count -or $s.Removed.Count) -and -not $Finish) {
        'Run Steam > Verify integrity of game files, then remove again (or remove -Finish to drop the manifest as is)'
    }
    else {
        'manifest.json', 'pending.json' | ForEach-Object { Remove-Item -LiteralPath (Join-Path $sd $_) -Force -ErrorAction SilentlyContinue }
        'removed: manifest deleted, snapshot kept'
    }
}

# Read-only eligibility probe. On-disk facts only; the Steam store page's anti-cheat section is the
# skill's job, so a clean scan is 'eligible' with requiresWebCheck set, never a final yes.
function Do-Assess($root) {
    $gameRoot = if ($root -match '^(.*\\steamapps\\common\\[^\\]+)') { $Matches[1] } else { $root }
    $ac = Find-AntiCheat $root
    $hasExe = [bool](Get-ChildItem -LiteralPath $root -Filter *.exe -File)
    $collisions = @($ProxyNames | Where-Object { Test-Path -LiteralPath (Join-Path $root $_) })
    $free = @($ProxyNames | Where-Object { $_ -notin $collisions })
    $dlss = @(Get-ChildItem -LiteralPath $gameRoot -Recurse -Filter 'nvngx_dlss*.dll' -File -Force -ErrorAction SilentlyContinue |
            ForEach-Object { [pscustomobject]@{ file = $_.FullName.Substring($gameRoot.Length).TrimStart('\'); version = $_.VersionInfo.FileVersion } })
    $appId = $null
    if ($root -match '^(.*\\steamapps)\\common\\([^\\]+)') {
        $dir = $Matches[2]
        foreach ($acf in Get-ChildItem -LiteralPath $Matches[1] -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue) {
            $t = Get-Content -LiteralPath $acf.FullName -Raw
            if ($t -match '"installdir"\s+"([^"]+)"' -and $Matches[1] -eq $dir -and $t -match '"appid"\s+"(\d+)"') { $appId = $Matches[1]; break }
        }
    }
    $refusals = @($ac | ForEach-Object { "anti-cheat on disk: $_" })
    if (-not $hasExe) { $refusals += "no *.exe in $root; pass the directory that holds the game executable" }
    $verdict = if ($ac) { 'refused' } elseif ($hasExe -and $free) { 'eligible' } else { 'unknown' }
    [pscustomobject]@{
        gameDir = $root; gameRoot = $gameRoot; gameKey = (GameKey $root)
        verdict = $verdict; requiresWebCheck = ($verdict -eq 'eligible')
        refusals = $refusals; dlss = $dlss
        dx12 = [bool](Get-ChildItem -LiteralPath $root -Filter 'd3d12*.dll' -File) -or ($root -match '\\Binaries\\Win64$')
        proxyCollisions = $collisions; freeProxies = $free; steamAppId = $appId
    } | ConvertTo-Json -Depth 4
}

# Verifies a downloaded fork zip against its pin, then extracts ONLY the build's allow-list into
# <DataDir>\builds\<build>\. setup_windows.bat and the rest never reach disk.
function Install-Build($build, $zip, $pin) {
    $h = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    if ($h -ne $pin.Sha256) { throw "hash mismatch for $($pin.Asset): got $h, expected $($pin.Sha256); nothing extracted" }
    $allow = $BuildFiles[$build]
    $dest = Join-Path $script:DataDir "builds\$build"
    $stage = "$dest.staging"
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $a = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        try {
        foreach ($e in $a.Entries) {
            $rel = $e.FullName -replace '/', '\'
            if (-not $e.Name -or ($rel -split '\\')[0] -notin $allow) { continue }   # dirs, and anything off the allow-list
            $to = [IO.Path]::GetFullPath((Join-Path $stage $rel))
            if (-not $to.StartsWith("$stage\")) { throw "zip entry escapes the build dir: $($e.FullName)" }
            New-Item -ItemType Directory -Force -Path (Split-Path $to -Parent) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $to)
        }
        }
        catch { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue; throw }
    }
    finally { $a.Dispose() }
    $missing = @($allow | Where-Object { -not (Test-Path -LiteralPath (Join-Path $stage $_)) })
    if ($missing) { Remove-Item -LiteralPath $stage -Recurse -Force; throw "zip lacks allow-listed entries: $($missing -join ', ')" }
    [pscustomobject]@{ tag = $pin.Tag; asset = $pin.Asset; url = $pin.Url; sha256 = $h; provisioned = (Get-Date).ToString('o') } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stage '.provisioned.json') -Encoding utf8
    # Stop on a failed delete: Move-Item into a surviving $dest would nest the new build inside the old.
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction Stop }
    Move-Item -LiteralPath $stage -Destination $dest
    "provisioned $build ($($pin.Tag)) -> $dest"
}
function Do-ProvisionBuild($build) {
    $pin = $BuildPins[$build]
    if (-not $pin) { throw "unknown build '$build' (have: $($BuildPins.Keys -join ', '))" }
    $marker = LoadJson (Join-Path $script:DataDir "builds\$build\.provisioned.json")
    if ($marker -and $marker.sha256 -eq $pin.Sha256) { return "already provisioned: $build ($($pin.Tag))" }
    $zip = Join-Path ([IO.Path]::GetTempPath()) ("dlss5-" + [guid]::NewGuid().ToString('N') + '.zip')
    try {
        Invoke-WebRequest -Uri $pin.Url -OutFile $zip
        Install-Build $build $zip $pin
    }
    finally { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue }
}

# Steam library roots from libraryfolders.vdf (text VDF). ponytail: Steam only; add Epic/Xbox
# discovery when a user reports a DLSS 5 title installed there.
function Get-ScanRoots {
    if ($null -ne $script:ScanRoots) { return @($script:ScanRoots) }
    $steam = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue).SteamPath
    if (-not $steam) { return @() }
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    $libs = @($steam)
    if (Test-Path -LiteralPath $vdf) {
        $libs += [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\', '\' }
    }
    @($libs | ForEach-Object { Join-Path ($_ -replace '/', '\') 'steamapps\common' } | Where-Object { Test-Path -LiteralPath $_ } | Sort-Object -Unique)
}
function Place-Runtime($file, $kind, $from) {
    $dest = Join-Path $script:DataDir 'runtime\nvngx_dlssnr.dll'
    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
    Copy-Item -LiteralPath $file -Destination $dest -Force
    $rt = Test-Runtime $dest
    [pscustomobject]@{ source = $kind; from = $from; sha256 = $rt.Hash; known = $rt.Known; provisioned = (Get-Date).ToString('o') } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $script:DataDir 'runtime\.provisioned.json') -Encoding utf8
    "runtime placed from $kind ($from) -> $dest"
}
# First source that passes the runtime gate wins: configured path, local scan, runtime_source.
function Do-ProvisionRuntime {
    $rt = Test-Runtime $script:RuntimeDll
    if ($rt.Ok) { return "runtime ok: $($script:RuntimeDll)" }
    if ($script:RuntimeDllConfigured) { throw "configured runtime_dll refused: $($rt.Reason). Fix or unset runtime_dll." }
    $notes = @()
    $cands = @(Get-ScanRoots | ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -Filter 'nvngx_dlssnr.dll' -File -Force -ErrorAction SilentlyContinue })
    $ok = @()
    foreach ($c in $cands) {
        $t = Test-Runtime $c.FullName
        if ($t.Ok) { $ok += [pscustomobject]@{ Path = $c.FullName; Known = $t.Known; Version = $c.VersionInfo.FileVersion } }
        else { $notes += "scan candidate refused: $($c.FullName): $($t.Reason)" }
    }
    $best = $ok | Sort-Object @{ e = { -not $_.Known } }, @{ e = { if ($_.Version -match '^\d+(\.\d+){1,3}') { [version]$Matches[0] } else { [version]'0.0' } }; Descending = $true } | Select-Object -First 1
    if ($best) { return Place-Runtime $best.Path 'local scan' $best.Path }
    $src = Resolve-Source $script:RuntimeSource
    if ($src) {
        if ($src -notmatch '^https://') {
            $t = Test-Runtime $src
            if ($t.Ok) { return Place-Runtime $src 'runtime_source' $src }
            $notes += "runtime_source refused: $($t.Reason)"
        }
        else {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ("dlss5-" + [guid]::NewGuid().ToString('N') + '.dll')
            $shown = ($src -split '\?')[0]
            try {
                if (([uri]$src).Host -like '*.blob.core.windows.net' -and (Get-Command az -ErrorAction SilentlyContinue)) {
                    & az storage blob download --blob-url $src --auth-mode login --file $tmp --only-show-errors | Out-Null
                    if ($LASTEXITCODE) { throw "az storage blob download failed ($LASTEXITCODE) for $shown; is az logged in with Storage Blob Data Reader?" }
                }
                else { Invoke-WebRequest -Uri $src -OutFile $tmp }
                $t = Test-Runtime $tmp
                if ($t.Ok) { return Place-Runtime $tmp 'runtime_source' $shown }
                $notes += "runtime_source refused: $($t.Reason)"
            }
            catch { $notes += "runtime_source download failed ($shown): $($_.Exception.Message)" }
            finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        }
    }
    $msg = @('no DLSS 5 runtime found. Remedies:'
        '  1. set runtime_dll to your own nvngx_dlssnr.dll'
        '  2. install a DLSS 5 title (it ships data\streamline\nvngx_dlssnr.dll or similar), then rerun'
        '  3. set runtime_source to a copy you control (https:// URL or path)') + $notes
    throw ($msg -join "`n")
}

function Assert($name, $cond) { if ($cond) { "PASS  $name" } else { $script:fails++; "FAIL  $name" } }
function Throws($block, $like) { try { & $block | Out-Null; $false } catch { $_.Exception.Message -like $like } }
function IniVal($path, $section, $key) {
    $sec = ''
    foreach ($l in ([IO.File]::ReadAllText($path) -split "`n")) {
        if ($l -match '^\s*\[([^\]]+)\]') { $sec = $Matches[1]; continue }
        if ($sec -eq $section -and $l -match "^\s*$key\s*=\s*(.*?)\s*$") { return $Matches[1] }
    }
    $null
}
function SameTree($a, $b) {
    if ($a.Count -ne $b.Count) { return $false }
    foreach ($k in $a.Keys) { if (-not $b.ContainsKey($k) -or $a[$k].Sha256 -ne $b[$k].Sha256) { return $false } }
    $true
}
function Put($path, $text) {
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
    Set-Content -LiteralPath $path -Value $text -NoNewline
}

# Self-contained: a temp data dir, temp game fixtures and a fake runtime DLL. Nothing is written
# under $PSScriptRoot or the user's real data_dir.
function Do-Selftest {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('dlss5-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $tmp = (Get-Item -LiteralPath $tmp).FullName.TrimEnd('\')
    Push-Location $tmp
    try {
        $docs = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Gaming'
        Assert 'empty DataDir uses the default' ((Resolve-DataDir '') -eq $docs)
        Assert 'literal ${user_config.data_dir} uses the default' ((Resolve-DataDir '${user_config.data_dir}') -eq $docs)
        Assert 'relative DataDir resolves to absolute' ((Resolve-DataDir 'rel') -eq "$tmp\rel")
        Assert 'trailing backslash trimmed' ((Resolve-DataDir "$tmp\x\") -eq "$tmp\x")
        Assert 'runtime_source with SAS token refused' (Throws { Resolve-Source 'https://a.blob.core.windows.net/c/b?sv=1&sig=x' } '*SAS*')
        Assert 'Win64 twins get distinct GameKeys' ((GameKey "$tmp\a\Win64") -ne (GameKey "$tmp\b\Win64"))

        $script:DataDir = "$tmp\data"
        $script:RuntimeDll = "$tmp\nvngx_dlssnr.dll"
        Put $script:RuntimeDll 'fakemodel'
        $script:ModelHash = (Get-FileHash -LiteralPath $script:RuntimeDll -Algorithm SHA256).Hash
        $bs = "$tmp\data\builds\selftest"
        Put "$bs\OptiScaler.dll" 'fakeproxy'; Put "$bs\OptiScaler\plugin.dll" 'plug'; Put "$bs\Licenses\LICENSE.txt" 'lic'
        $ini = "[Upscalers]`nEnabled=auto`n[Log]`nLogToFile=auto`nLogLevel=auto`n[DlssNr]`nEnabled=auto`nAutoCapture=auto`nRestoreComputeSignature=auto`n"
        [IO.File]::WriteAllText("$bs\OptiScaler.ini", ($ini -replace "`n", "`r`n"), [Text.UTF8Encoding]::new($true))
        $BuildFiles['selftest'] = @('OptiScaler.dll', 'OptiScaler.ini', 'OptiScaler', 'Licenses')
        $script:Build = 'selftest'; $script:Proxy = 'dxgi.dll'; $script:RestoreComputeSignature = $true

        # Fixtures sit three levels deep so the non-Steam ancestor scan never leaves $tmp.
        $w = "$tmp\w\x\y"
        $g = "$w\g\Win64"
        Put "$g\game.exe" 'exe'; Put "$g\data\pak.bin" 'pak'; Put "$g\dbghelp.dll" 'stock'
        Do-Apply $g | Out-Null
        $sd = StateDir $g
        Assert 'apply with no prior snapshot snapshots first' (Test-Path -LiteralPath "$sd\snapshot.json")
        Assert 'state lands under DataDir' ($sd.StartsWith("$tmp\data\state\") -and (Test-Path -LiteralPath "$sd\manifest.json"))
        Assert 'nothing written under the script dir' (-not (Get-ChildItem -LiteralPath $PSScriptRoot -Directory))
        Assert 'no pending.json after success' (-not (Test-Path -LiteralPath "$sd\pending.json"))
        $gi = "$g\OptiScaler.ini"
        Assert 'proxy dxgi.dll placed' (Test-Path -LiteralPath "$g\dxgi.dll")
        Assert 'model nvngx_dlssnr.dll placed' (Test-Path -LiteralPath "$g\nvngx_dlssnr.dll")
        Assert 'subdir file copied' (Test-Path -LiteralPath "$g\OptiScaler\plugin.dll")
        Assert '[DlssNr] Enabled=true' ((IniVal $gi 'DlssNr' 'Enabled') -eq 'true')
        Assert '[Upscalers] Enabled still auto' ((IniVal $gi 'Upscalers' 'Enabled') -eq 'auto')
        Assert '[DlssNr] AutoCapture=false' ((IniVal $gi 'DlssNr' 'AutoCapture') -eq 'false')
        Assert '[Log] LogToFile=true' ((IniVal $gi 'Log' 'LogToFile') -eq 'true')
        Assert '[Log] LogLevel=2' ((IniVal $gi 'Log' 'LogLevel') -eq '2')
        Assert 'RestoreComputeSignature=true' ((IniVal $gi 'DlssNr' 'RestoreComputeSignature') -eq 'true')
        $by = [IO.File]::ReadAllBytes($gi)
        Assert 'BOM preserved' ($by[0] -eq 0xEF -and $by[1] -eq 0xBB -and $by[2] -eq 0xBF)
        $raw = [Text.Encoding]::UTF8.GetString($by)
        Assert 'CRLF preserved' (($raw -match "`r`n") -and ($raw -notmatch "(?<!`r)`n"))

        foreach ($b in 'OptiScaler.log', 'OptiScaler.asi', 'dlssnr-capture\x.png', 'OptiScalerProfiles\p.ini') {
            Put "$g\$b" 'by'
            Assert "byproduct: $b" (@((Get-Stat $g).Added | Where-Object { $_.Path -eq $b -and $_.Kind -eq 'byproduct' }).Count -eq 1)
        }
        $s = Get-Stat $g
        Assert 'no unknown added files' (@($s.Added | Where-Object Kind -eq 'unknown').Count -eq 0)
        Assert 'status clean after apply' (-not $s.Bad)
        Add-Content -LiteralPath $gi -Value 'Saved=1'
        Assert 'OptiScaler.ini drift is expected, not bad' (-not (Get-Stat $g).Bad)
        Put "$g\dxgi.dll" 'tampered'
        Assert 'changed manifest file is bad' ((Get-Stat $g).Bad)
        Put "$g\dxgi.dll" 'fakeproxy'

        Assert 're-apply fails: already applied' (Throws { Do-Apply $g } '*already applied*')
        $sj = Get-Content -LiteralPath "$sd\snapshot.json" -Raw
        ($sj | ConvertFrom-Json | ForEach-Object { $_.gameDir = 'X:\elsewhere'; $_ } | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath "$sd\snapshot.json"
        Assert 'recorded gameDir mismatch refuses' (Throws { Get-Stat $g } '*refusing*')
        Set-Content -LiteralPath "$sd\snapshot.json" -Value $sj -NoNewline

        Do-Remove $g | Out-Null
        $snap = @{}; foreach ($e in @((Load-Snapshot $g).files)) { $snap[$e.Path] = @{ Sha256 = $e.Sha256 } }
        Assert 'tree restored byte-identical to snapshot' (SameTree (Tree $g) $snap)
        Assert 'mod dirs removed' (-not (Test-Path -LiteralPath "$g\OptiScaler") -and -not (Test-Path -LiteralPath "$g\dlssnr-capture"))
        Assert 'manifest deleted, snapshot kept' (-not (Test-Path -LiteralPath "$sd\manifest.json") -and (Test-Path -LiteralPath "$sd\snapshot.json"))

        $c = "$w\c\Win64"; Put "$c\game.exe" 'exe'; Put "$c\dxgi.dll" 'game-own-dxgi'
        Assert 'collision fails before copying' (Throws { Do-Apply $c } '*collision*')
        Assert 'collision dir untouched, no state' (@(Get-ChildItem -LiteralPath $c -Recurse -File).Count -eq 2 -and -not (Test-Path -LiteralPath (StateDir $c)))

        $a = "$tmp\ac\a\b\c"; Put "$a\game.exe" 'exe'
        New-Item -ItemType Directory -Force -Path "$tmp\ac\EasyAntiCheat" | Out-Null
        Assert 'EasyAntiCheat three levels above the exe dir refuses' (Throws { Do-Apply $a } '*anti-cheat*')
        Assert 'anti-cheat refusal copies nothing' (@(Get-ChildItem -LiteralPath $a -Recurse -File).Count -eq 1 -and -not (Test-Path -LiteralPath (StateDir $a)))

        $x = "$w\noexe"; Put "$x\readme.txt" 'r'
        Assert 'directory with no *.exe refuses' (Throws { Do-Apply $x } '*no `*.exe*')

        $f = "$w\f\Win64"; Put "$f\game.exe" 'exe'
        $before = Tree $f
        $script:FaultAfter = 3
        Assert 'copy fault midway rethrows' (Throws { Do-Apply $f } '*injected*')
        $script:FaultAfter = 0
        Assert 'copy fault leaves tree byte-identical' ((SameTree (Tree $f) $before) -and -not (Test-Path -LiteralPath "$f\OptiScaler"))
        Assert 'copy fault leaves no pending.json or manifest' (-not (Test-Path -LiteralPath "$(StateDir $f)\pending.json") -and -not (Test-Path -LiteralPath "$(StateDir $f)\manifest.json"))

        $script:RuntimeDll = "$tmp\other.dll"; Put $script:RuntimeDll 'unknown-runtime'
        Assert 'unknown-hash runtime refused' (Throws { Do-Apply $f } '*runtime DLL refused*')

        # assess: read-only verdicts
        Assert 'assess refuses anti-cheat fixture' (((Do-Assess $a) | ConvertFrom-Json).verdict -eq 'refused')
        $ca = (Do-Assess $c) | ConvertFrom-Json
        Assert 'assess lists dxgi.dll collision, not as a free proxy' ('dxgi.dll' -in $ca.proxyCollisions -and 'dxgi.dll' -notin $ca.freeProxies)
        $k = "$w\clean\Win64"; Put "$k\game.exe" 'exe'
        $ka = (Do-Assess $k) | ConvertFrom-Json
        Assert 'assess clean fixture is eligible with requiresWebCheck' ($ka.verdict -eq 'eligible' -and $ka.requiresWebCheck)
        Assert 'assess creates no state dir' (-not (Test-Path -LiteralPath (StateDir $k)))

        # provision: verify-and-extract over a local zip, no network
        $zs = "$tmp\zipsrc"
        Put "$zs\OptiScaler.dll" 'p'; Put "$zs\OptiScaler.ini" 'i'; Put "$zs\OptiScaler\x.dll" 'x'; Put "$zs\Licenses\L.txt" 'l'
        Put "$zs\setup_windows.bat" 'pause'; Put "$zs\README.md" 'r'; Put "$zs\docs\a.md" 'd'
        Compress-Archive -Path "$zs\*" -DestinationPath "$tmp\fx.zip"
        $pin = @{ Tag = 't1'; Asset = 'fx.zip'; Url = 'local'; Sha256 = (Get-FileHash -LiteralPath "$tmp\fx.zip" -Algorithm SHA256).Hash }
        Install-Build 'selftest' "$tmp\fx.zip" $pin | Out-Null
        $bd = "$tmp\data\builds\selftest"
        Assert 'provision extracts the allow-list' ((Test-Path -LiteralPath "$bd\OptiScaler\x.dll") -and (Test-Path -LiteralPath "$bd\Licenses\L.txt") -and (Test-Path -LiteralPath "$bd\OptiScaler.dll"))
        Assert 'provision skips setup_windows.bat' (-not (Test-Path -LiteralPath "$bd\setup_windows.bat") -and -not (Test-Path -LiteralPath "$bd\README.md") -and -not (Test-Path -LiteralPath "$bd\docs"))
        Assert 'provision marker names the verified hash' ((LoadJson "$bd\.provisioned.json").sha256 -eq $pin.Sha256)
        $BuildFiles['selftest2'] = $BuildFiles['selftest']
        Assert 'provision wrong hash throws' (Throws { Install-Build 'selftest2' "$tmp\fx.zip" @{ Asset = 'fx.zip'; Sha256 = '00' } } '*hash mismatch*')
        Assert 'provision wrong hash extracts nothing' (-not (Test-Path -LiteralPath "$tmp\data\builds\selftest2") -and -not (Test-Path -LiteralPath "$tmp\data\builds\selftest2.staging"))

        # provision -Runtime: scan fixture, no registry read, no network
        $script:RuntimeDll = "$tmp\data\runtime\nvngx_dlssnr.dll"; $script:RuntimeDllConfigured = $false; $script:RuntimeSource = $null
        $lib = "$tmp\lib\steamapps\common"; $script:ScanRoots = @($lib)
        Put "$lib\X\data\streamline\nvngx_dlssnr.dll" 'unsigned'
        Assert 'runtime scan refuses unsigned candidate' (Throws { Do-ProvisionRuntime } '*scan candidate refused*X\data\streamline*')
        Assert 'refused candidate places nothing' (-not (Test-Path -LiteralPath $script:RuntimeDll))
        Put "$lib\Y\nvngx_dlssnr.dll" 'fakemodel'
        Do-ProvisionRuntime | Out-Null
        Assert 'runtime scan places a known-hash candidate' ((Test-Runtime $script:RuntimeDll).Known -and (LoadJson "$tmp\data\runtime\.provisioned.json").source -eq 'local scan')
        Remove-Item -LiteralPath "$tmp\data\runtime" -Recurse -Force
        $script:ScanRoots = @()
        Assert 'no scan roots and no source prints all three remedies' (Throws { Do-ProvisionRuntime } '*runtime_dll*install a DLSS 5 title*runtime_source*')
        $script:RuntimeSource = 'https://a.blob.core.windows.net/c/b?sv=1&sig=x'
        Assert 'provision -Runtime refuses a SAS source before any fetch' (Throws { Do-ProvisionRuntime } '*SAS*')
        Put "$tmp\src\nvngx_dlssnr.dll" 'fakemodel'; $script:RuntimeSource = "$tmp\src\nvngx_dlssnr.dll"
        Do-ProvisionRuntime | Out-Null
        Assert 'runtime_source path is placed' ((LoadJson "$tmp\data\runtime\.provisioned.json").source -eq 'runtime_source')
    }
    finally {
        Pop-Location
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($script:fails) { "SELFTEST FAILED ($script:fails)" } else { 'SELFTEST OK' }
}

Init-Paths
switch ($Verb) {
    'assess' { Do-Assess (Root $GameDir) }
    'provision' { if ($Runtime) { Do-ProvisionRuntime } else { Do-ProvisionBuild $Build } }
    'apply' { Do-Apply (Root $GameDir) }
    'status' {
        $s = Get-Stat (Root $GameDir); Show-Stat $s
        if ($s.Bad) { exit 1 }
    }
    'remove' { Do-Remove (Root $GameDir) }
    'selftest' { Do-Selftest; exit ([int]$script:fails) }
}
