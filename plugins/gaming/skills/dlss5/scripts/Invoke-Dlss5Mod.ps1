#Requires -Version 7
# Install/remove the OptiScaler DLSS-NR mod in a game exe dir, with a pre-install snapshot and a
# file manifest so removal leaves the folder byte-identical. All state lives under -DataDir.
param(
    [Parameter(Mandatory)][ValidateSet('assess', 'discover', 'provision', 'apply', 'status', 'remove', 'refetch', 'selftest')][string]$Verb,
    [Parameter(Position = 0)][string]$GameDir,
    [string]$Build = 'dagherbou',
    [string]$Proxy = 'dxgi.dll',
    [string]$DataDir,
    [string]$RuntimeDll,
    [string]$RuntimeSource,
    [string[]]$ScanRoots,
    [string]$Preset,
    [string]$AcceptAntiCheatRisk,
    [string]$AntiCheatResearch,
    [string[]]$AntiCheatSources,
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
# Upscaler DLLs OptiScaler hooks by name (upstream OptiScaler/DllNames.h). Exact names: the frame
# generation, ray reconstruction and NR runtime DLLs (nvngx_dlssg, nvngx_dlssd, nvngx_dlssnr,
# libxess_fg, amd_fidelityfx_framegeneration_dx12) are not upscalers. Mirrors
# reference/candidate-selection.md; change both together.
$UpscalerDlls = @{
    'nvngx_dlss.dll' = 'DLSS'
    'ffx_fsr2_api_x64.dll' = 'FSR'; 'ffx_fsr2_api_dx12_x64.dll' = 'FSR'; 'ffx_fsr3upscaler_x64.dll' = 'FSR'
    'amd_fidelityfx_dx12.dll' = 'FSR'; 'amd_fidelityfx_loader_dx12.dll' = 'FSR'
    'amd_fidelityfx_upscaler_dx12.dll' = 'FSR'; 'amd_fidelityfx_vk.dll' = 'FSR'
    'libxess.dll' = 'XeSS'; 'libxess_dx11.dll' = 'XeSS'
}
# The only OptiScaler.ini keys a preset may set, with their section in both pinned builds. The
# baseline edits (Enabled, AutoCapture, logging) and every safety behavior stay off this list.
# Mirrors reference/presets.md; change both together.
$PresetKeys = @{ Dx11Upscaler = 'Upscalers'; RestoreComputeSignature = 'Hotfix'; RestoreGraphicSignature = 'Hotfix' }
$script:PresetDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\presets'))
$WindowsApps = 'refusing: the folder is under WindowsApps, a protected package folder where installing a proxy DLL is unverified. Xbox app and Game Pass installs under XboxGames are supported; see reference/launchers.md'
$NoUpscaler = 'not a candidate: no DLSS, FSR 2+ or XeSS DLL in the game tree, so the mod has no upscaler to hook and will not change the picture. See reference/candidate-selection.md'
$script:fails = 0
$script:FaultAfter = 0   # selftest hook: throw after this many copies
# Discovery and anti-cheat sources. The selftest swaps each for a fixture, so it never reads the
# real registry, real drives or the network.
$script:Reg = $null   # $null = the live registry; else a hashtable of key path -> @{ value = data }
$script:ProgramData = $env:ProgramData
$script:EaRoots = @(Join-Path $env:ProgramFiles 'EA Games')
$script:Drives = $null   # $null = every ready fixed drive
$script:HttpGet = {
    param($url, $headers)
    $r = Invoke-WebRequest -Uri $url -Headers ($headers ?? @{}) -UseBasicParsing -TimeoutSec 30
    [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
}
$AwacyRepo = 'AreWeAntiCheatYet/AreWeAntiCheatYet'
$SteamCookie = 'birthtime=0; wants_mature_content=1; lastagecheckage=1-0-1900'

# An unset userConfig option arrives empty or as its own literal ${user_config.KEY} token.
function Resolve-Opt([string]$v) { if (-not $v -or $v.StartsWith('${user_config.')) { $null } else { $v } }
function Resolve-PathOpt([string]$v) {
    $v = Resolve-Opt $v
    if (-not $v) { return $null }
    $full = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($v), (Get-Location).ProviderPath)
    if ($full.Length -gt 3) { $full.TrimEnd('\') } else { $full }
}
function Resolve-DataDir([string]$v, [string]$docs = [Environment]::GetFolderPath('MyDocuments')) {
    (Resolve-PathOpt $v) ?? (Join-Path $docs 'Gaming\dlss5')
}
# Documents\Gaming is the legacy default. Its manifests are the only way to undo the mod, so refuse
# rather than start an empty state tree beside them; moving them is the user's call. "Empty" rather
# than "absent", because setup apply creates <data-dir>\state before it calls this script.
function HasEntries($p) { [bool](Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | Select-Object -First 1) }
function Assert-NoLegacyState([string]$docs) {
    $old = Join-Path $docs 'Gaming'; $new = Resolve-DataDir '' $docs
    if ((HasEntries "$old\state") -and -not (HasEntries "$new\state")) {
        throw "legacy data directory $old holds state\, but the default data_dir is now $new. Move runtime\, state\, builds\, cache\ and LEDGER.md from $old into $new, then rerun. Nothing was changed."
    }
}
function Resolve-Source([string]$v) {
    $v = Resolve-Opt $v
    if (-not $v) { return $null }
    # Signed-URL credentials ride in the query string, and this value sits in plain-text settings.
    if ($v -match '\?') { throw 'runtime_source must not carry a query string (signed-URL credentials live there); use a path or a plain https:// URL' }
    if ($v -match '^https://') { return $v }
    if ($v -match '^[A-Za-z][A-Za-z0-9+.-]*://') { throw "runtime_source must be an https:// URL or a path: $v" }
    Resolve-PathOpt $v
}
function Init-Paths {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $script:DataDir = Resolve-DataDir $DataDir
    # Keyed on the resolved path, so a caller that passes the default explicitly is gated too.
    if ($Verb -notin 'selftest', 'refetch', 'discover' -and $script:DataDir -eq (Resolve-DataDir '' $docs)) { Assert-NoLegacyState $docs }
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
# Keep ISO timestamps as strings where pwsh (7.5+) allows it, so a merged cache round-trips unchanged.
$JsonOpts = @{}; if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $JsonOpts.DateKind = 'String' }
function LoadJson($p) { if (Test-Path -LiteralPath $p) { Get-Content -LiteralPath $p -Raw | ConvertFrom-Json @JsonOpts } }
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
    foreach ($t in $AntiCheatTokens) { if ($b -eq $t -or $b -like "${t}_*" -or $b -like "${t}-*") { return $true } }
    $false
}
# Scans from the game root, not the exe dir: EasyAntiCheat\ sits beside the root while the exe is
# two or three levels down. ponytail: name match with capped depth; server-side or
# launcher-delivered anti-cheat leaves nothing on disk, which Get-AntiCheat's web sources cover.
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

# Steam: the common\<X> root. Non-Steam Unreal: the install root three levels above
# <Project>\Binaries\Win64, since the upscaler plugins live under Engine\Plugins. Else the exe dir.
function Get-GameRoot($root) {
    if ($root -match '^(.*\\steamapps\\common\\[^\\]+)') { $Matches[1] }
    elseif ($root -match '^(.*)\\[^\\]+\\Binaries\\Win64$') { $Matches[1] }
    else { $root }
}
# The mod's own files never count: the fork's OptiScaler\ folder ships FSR and XeSS copies. Skipped:
# anything under a $ModDirs folder, and every file this exe dir's manifest or pending.json names.
function Find-Upscalers($root) {
    $gameRoot = Get-GameRoot $root
    $ours = @{}
    try { foreach ($e in @((Load-Manifest $root).files)) { if ($e) { $ours[(Join-Path $root $e.Path)] = $true } } }
    catch { Write-Warning "state for $root unreadable, manifest files not excluded: $($_.Exception.Message)" }
    @(Get-ChildItem -LiteralPath $gameRoot -Recurse -Filter '*.dll' -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $UpscalerDlls.ContainsKey($_.Name) -and -not $ours[$_.FullName] } | ForEach-Object {
                $rel = $_.FullName.Substring($gameRoot.Length).TrimStart('\')
                if (-not (($rel -split '\\' | Select-Object -SkipLast 1) | Where-Object { $_ -in $ModDirs })) {
                    [pscustomobject]@{ family = $UpscalerDlls[$_.Name]; file = $rel; version = $_.VersionInfo.FileVersion }
                } } | Sort-Object file -Unique)
}

# Numeric parts, not the FileVersion string: NVIDIA's runtime reports "310,8,0,0" there.
function FileVer($path) {
    $v = (Get-Item -LiteralPath $path).VersionInfo
    if ($v.FileMajorPart -or $v.FileMinorPart) { [version]::new($v.FileMajorPart, $v.FileMinorPart, $v.FileBuildPart, $v.FilePrivatePart) }
}
# Known hash passes. An unknown hash passes only with a valid NVIDIA signature at or above the
# minimum version AND -AllowUnknownRuntime.
function Test-Runtime($path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @{ Ok = $false; Reason = "missing: $path" } }
    $h = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($h -eq $script:ModelHash) { return @{ Ok = $true; Hash = $h; Known = $true } }
    $sig = Get-AuthenticodeSignature -LiteralPath $path
    $ver = FileVer $path
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'CN=NVIDIA Corporation' -or -not $ver -or $ver -lt $MinRuntimeVersion) {
        return @{ Ok = $false; Hash = $h; Reason = "unknown hash $h without a valid NVIDIA signature at $MinRuntimeVersion or later" }
    }
    if (-not $AllowUnknownRuntime) {
        return @{ Ok = $false; Hash = $h; Reason = "unknown hash $h (NVIDIA-signed, version $ver); pass -AllowUnknownRuntime to accept it" }
    }
    @{ Ok = $true; Hash = $h; Known = $false }
}

function Acf($t, $key) { if ($t -match "`"$key`"\s+`"([^`"]*)`"") { $Matches[1] } }
function SteamAcf($root) {
    if ($root -notmatch '^(.*\\steamapps)\\common\\([^\\]+)') { return }
    $dir = $Matches[2]
    foreach ($acf in Get-ChildItem -LiteralPath $Matches[1] -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue) {
        $t = Get-Content -LiteralPath $acf.FullName -Raw -Encoding utf8
        if ((Acf $t 'installdir') -eq $dir -and (Acf $t 'appid') -match '^\d+$') { return @{ appid = (Acf $t 'appid'); name = (Acf $t 'name') } }
    }
}
function SteamAppId($root) { (SteamAcf $root).appid }

# --- Launcher discovery. Each finder returns Game records and adds what it could not read to
# $script:Unchecked. Locations: reference/launchers.md.
function RegProps($key) {
    if ($null -ne $script:Reg) { return $script:Reg[$key] }
    $p = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
    if (-not $p) { return }
    $h = @{}
    foreach ($x in $p.PSObject.Properties) { if ($x.Name -notin 'PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider') { $h[$x.Name] = $x.Value } }
    $h
}
function RegKids($key) {
    if ($null -ne $script:Reg) { return @($script:Reg.Keys | Where-Object { $_.StartsWith("$key\") -and $_.Substring($key.Length + 1) -notmatch '\\' } | Sort-Object) }
    @(Get-ChildItem -LiteralPath $key -ErrorAction SilentlyContinue | ForEach-Object { "$key\$($_.PSChildName)" })
}
# A record whose folder is empty, quoted, relative or malformed is skipped, never resolved against the cwd.
function Game($launcher, $name, $dir, $source) {
    $dir = "$dir".Trim().Trim('"') -replace '/', '\'
    if (-not $dir -or $dir.Contains([char]0) -or -not [IO.Path]::IsPathFullyQualified($dir)) { return }
    $d = [IO.Path]::GetFullPath($dir)
    if ($d.Length -gt 3) { $d = $d.TrimEnd('\') }
    [pscustomobject]@{ launcher = $launcher; name = "$name".Trim(); installDir = $d; source = $source }
}
function Find-SteamGames {
    $steam = (RegProps 'HKCU:\Software\Valve\Steam').SteamPath
    if (-not $steam) { $script:Unchecked += 'Steam: no SteamPath under HKCU\Software\Valve\Steam'; return }
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    $libs = @($steam)
    if (Test-Path -LiteralPath $vdf) {
        $libs += [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\', '\' }
    }
    foreach ($lib in @($libs | ForEach-Object { Join-Path ($_ -replace '/', '\') 'steamapps' } | Sort-Object -Unique)) {
        foreach ($acf in Get-ChildItem -LiteralPath $lib -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue) {
            $t = Get-Content -LiteralPath $acf.FullName -Raw -Encoding utf8
            if ($i = Acf $t 'installdir') { Game 'Steam' (Acf $t 'name') (Join-Path $lib "common\$i") $acf.Name }
        }
    }
}
function Find-EpicGames {
    $dir = (RegProps 'HKCU:\Software\Epic Games\EOS').ModSdkMetadataDir
    if (-not $dir) { $dir = Join-Path $script:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests' }
    foreach ($f in Get-ChildItem -LiteralPath $dir -Filter '*.item' -File -ErrorAction SilentlyContinue) {
        try { $j = LoadJson $f.FullName; Game 'Epic Games Launcher' ($j.DisplayName ?? $j.AppName) $j.InstallLocation $f.Name }
        catch { $script:Unchecked += "Epic Games Launcher: $($f.FullName) unreadable: $($_.Exception.Message)" }
    }
    $dat = Join-Path $script:ProgramData 'Epic\UnrealEngineLauncher\LauncherInstalled.dat'
    try { foreach ($e in @((LoadJson $dat).InstallationList)) { if ($e) { Game 'Epic Games Launcher' $e.AppName $e.InstallLocation 'LauncherInstalled.dat' } } }
    catch { $script:Unchecked += "Epic Games Launcher: $dat unreadable: $($_.Exception.Message)" }
}
# The EA app's own list (the IS file) is encrypted with a hardware-derived key and is never read.
function Find-EaGames {
    $script:Unchecked += "EA app: the encrypted install list is not read; scanned $(@($script:EaRoots) -join ', ') for __Installer\installerdata.xml. An EA game elsewhere is recognized when assess is pointed at it"
    foreach ($r in @($script:EaRoots)) {
        foreach ($d in Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue) {
            if (Test-Path -LiteralPath (Join-Path $d.FullName '__Installer\installerdata.xml')) { Game 'EA app' $d.Name $d.FullName '__Installer\installerdata.xml' }
        }
    }
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $script:ProgramData 'Origin\LocalContent') -Recurse -Filter '*.mfst' -File -ErrorAction SilentlyContinue) {
        $q = [Web.HttpUtility]::ParseQueryString((Get-Content -LiteralPath $f.FullName -Raw).Trim().TrimStart('?'))
        if ($p = $q['dipInstallPath']) { Game 'Origin' (Split-Path $p.TrimEnd('\') -Leaf) $p $f.Name }
    }
}
function Find-BattleNetGames {
    $script:Unchecked += 'Battle.net: Uninstall registry entries only; product.db is not parsed, and the client writes no entry for some games'
    foreach ($u in 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall') {
        foreach ($k in RegKids $u) {
            $p = RegProps $k
            if ("$($p.UninstallString)" -match 'Battle\.net.*--uid=') { Game 'Battle.net' $p.DisplayName $p.InstallLocation 'Uninstall registry' }
        }
    }
}
function Find-GogGames {
    foreach ($k in RegKids 'HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games') { $p = RegProps $k; Game 'GOG Galaxy' $p.gameName $p.path 'GOG.com\Games registry' }
}
function Find-UbisoftGames {
    foreach ($u in 'HKLM:\SOFTWARE\WOW6432Node\ubisoft\Launcher\Installs', 'HKLM:\SOFTWARE\ubisoft\Launcher\Installs') {
        foreach ($k in RegKids $u) {
            $d = "$((RegProps $k).InstallDir)" -replace '/', '\'
            if (-not $d.Trim()) { continue }
            Game 'Ubisoft Connect' (Split-Path $d.TrimEnd('\') -Leaf) $d 'ubisoft\Launcher\Installs registry'
        }
    }
}
# .GamingRoot: magic 0x58424752, a UInt32 folder count, then UTF-16 null-terminated folder names
# relative to the drive root. Undocumented by Microsoft, so any parse failure falls back.
function Read-GamingRoot($path) {
    $b = [IO.File]::ReadAllBytes($path)
    if ($b.Length -lt 8 -or [BitConverter]::ToUInt32($b, 0) -ne 0x58424752) { throw 'file magic does not match' }
    $n = [BitConverter]::ToUInt32($b, 4)
    if ($n -ge 255) { throw "folder count $n exceeds the limit" }
    $names = @([Text.Encoding]::Unicode.GetString($b, 8, $b.Length - 8).Split([char]0) | Where-Object { $_ } | Select-Object -First $n)
    if ($names.Count -ne $n) { throw "expected $n folder names, read $($names.Count)" }
    $names | ForEach-Object { Join-Path (Split-Path $path -Parent) $_ }
}
function Find-XboxGames {
    $drives = $script:Drives ?? @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object { $_.RootDirectory.FullName })
    foreach ($d in $drives) {
        $roots = @()
        $gr = Join-Path $d '.GamingRoot'
        $parsed = $false
        if (Test-Path -LiteralPath $gr -PathType Leaf) {
            try { $roots += Read-GamingRoot $gr; $parsed = $true }
            catch { $script:Unchecked += "Xbox app: $gr unreadable ($($_.Exception.Message)); fell back to $(Join-Path $d 'XboxGames')" }
        }
        if (-not $parsed) { $roots += Join-Path $d 'XboxGames' }
        $roots += Join-Path $d 'Program Files\ModifiableWindowsApps'
        foreach ($r in $roots) {
            foreach ($g in Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue) {
                $m = @((Join-Path $g.FullName 'appxmanifest.xml'), (Join-Path $g.FullName 'Content\appxmanifest.xml')) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
                if (-not $m) { continue }
                $n = try { "$(([xml](Get-Content -LiteralPath $m -Raw)).Package.Properties.DisplayName)" } catch { '' }
                if (-not $n -or $n -like 'ms-resource:*') { $n = $g.Name }
                Game 'Xbox app' $n (Split-Path $m -Parent) 'appxmanifest.xml'
            }
        }
    }
}
function Find-Games {
    $script:Unchecked = @()
    @(foreach ($f in 'Find-SteamGames', 'Find-EpicGames', 'Find-EaGames', 'Find-BattleNetGames', 'Find-GogGames', 'Find-UbisoftGames', 'Find-XboxGames') {
            try { & $f } catch { $script:Unchecked += "$($f -replace '^Find-|Games$'): $($_.Exception.Message)" }
        })
}
# The launcher a game directory came from: the deepest discovered install that contains it, then an
# on-disk marker in the directory or an ancestor. Neither is 'unknown'.
$GenericLeaves = @('Win64', 'x64', 'bin', 'Binaries', 'Retail', 'Content', 'Game')
function Get-Launcher($root) {
    if ($root -match '\\WindowsApps(\\|$)') { return Game 'Xbox app' (Split-Path $root -Leaf) $root 'WindowsApps path' }
    $hit = Find-Games | Where-Object { "$root\".StartsWith("$($_.installDir)\", 'OrdinalIgnoreCase') } | Sort-Object { $_.installDir.Length } -Descending | Select-Object -First 1
    if ($hit) { return $hit }
    for ($p = $root; $p -and $p.Length -gt 3; $p = Split-Path $p -Parent) {
        if ($p -match '\\steamapps\\common\\[^\\]+$') { return Game 'Steam' ((SteamAcf $p).name ?? (Split-Path $p -Leaf)) $p 'steamapps\common path' }
        if (Test-Path -LiteralPath (Join-Path $p '.egstore') -PathType Container) { return Game 'Epic Games Launcher' (Split-Path $p -Leaf) $p '.egstore' }
        if (Test-Path -LiteralPath (Join-Path $p '__Installer\installerdata.xml')) { return Game 'EA app' (Split-Path $p -Leaf) $p '__Installer\installerdata.xml' }
        if (Get-ChildItem -LiteralPath $p -Filter 'goggame-*.info' -File -ErrorAction SilentlyContinue) { return Game 'GOG Galaxy' (Split-Path $p -Leaf) $p 'goggame-*.info' }
        if (Test-Path -LiteralPath (Join-Path $p 'appxmanifest.xml')) { return Game 'Xbox app' (Split-Path $p -Leaf) $p 'appxmanifest.xml' }
    }
    # ponytail: name from the folder, skipping generic exe-dir leaves; a wrong guess only changes
    # what the user types to acknowledge.
    $p = Get-GameRoot $root
    while ((Split-Path $p -Leaf) -in $GenericLeaves -and (Split-Path $p -Parent).Length -gt 3) { $p = Split-Path $p -Parent }
    Game 'unknown' (Split-Path $p -Leaf) $p 'no launcher record or marker'
}

# --- Anti-cheat signals. Status: 'signals' (a source names anti-cheat), 'unknown' (a source could
# not be checked, or the launcher has none), 'none-disclosed' (Steam only: every source was read
# and none named one). None of the three means "no anti-cheat". Posture: reference/anticheat-posture.md.
# Names compare case-insensitively with punctuation, spacing and the (TM), (R) and curly-apostrophe glyphs removed.
function NormName($s) { "$s".ToLowerInvariant() -replace '[^\p{L}\p{N}]', '' }
function Get-AntiCheat($root, $launch, $appId) {
    $signals = @(Find-AntiCheat $root | ForEach-Object { "on disk: $_" })
    $unchecked = @()
    if ($launch.launcher -eq 'Battle.net') {
        $signals += 'Battle.net title: Blizzard EULA sections 1.C.i and 1.C.ii bar modifying the Platform and unauthorized software that changes its functionality (full text in reference/anticheat-posture.md)'
    }
    $aw = [ordered]@{ repo = $AwacyRepo; commit = $null; entries = @(); error = $null }
    try {
        $sha = ((& $script:HttpGet "https://api.github.com/repos/$AwacyRepo/commits/HEAD") | ConvertFrom-Json).sha
        if ("$sha" -notmatch '\A[0-9a-f]{40}\z') { throw 'no commit SHA in the GitHub response' }
        $all = (& $script:HttpGet "https://raw.githubusercontent.com/$AwacyRepo/$sha/games.json") | ConvertFrom-Json
        if (-not @($all).Count) { throw 'games.json is empty' }
        $aw.commit = $sha
        $n = NormName $launch.name
        # AWACY's status field is Linux support, not presence; only a non-empty anticheats list counts.
        $aw.entries = @($all | Where-Object { ($appId -and "$($_.storeIds.steam)" -eq $appId) -or ($n -and (NormName $_.name) -eq $n) } |
                ForEach-Object { [pscustomobject]@{ name = $_.name; anticheats = @($_.anticheats | Where-Object { $_ }) } })
        # No entry means nobody recorded the title, not that it has no anti-cheat.
        if (-not $aw.entries) { $unchecked += "AreWeAntiCheatYet (commit $($sha.Substring(0, 7))): no entry for this title, so this source is unknown" }
        foreach ($e in $aw.entries) { if ($e.anticheats) { $signals += "AreWeAntiCheatYet (commit $($sha.Substring(0, 7))) lists $($e.name): $($e.anticheats -join ', ')" } }
    }
    catch { $aw.error = $_.Exception.Message; $unchecked += "AreWeAntiCheatYet: fetch failed ($($aw.error)), so this source is unknown" }
    $st = $null
    if ($appId) {
        $st = [ordered]@{ appId = $appId; url = "https://store.steampowered.com/app/$appId/?l=english"; storeName = $null; anticheats = @(); error = $null }
        try {
            $t = & $script:HttpGet $st.url @{ Cookie = $SteamCookie }
            if ($t -match 'agecheck') { throw 'the age gate came back instead of the store page' }
            if ($t -notmatch 'apphub_AppName">([^<]*)') { throw 'no store page for this app id' }
            $st.storeName = [Net.WebUtility]::HtmlDecode($Matches[1])
            if ($t -match 'anticheat_section') {
                $st.anticheats = @([regex]::Matches($t, 'class="anticheat_name"[^>]*>\s*([^<]+?)\s*<') | ForEach-Object { [Net.WebUtility]::HtmlDecode($_.Groups[1].Value) })
                $signals += "Steam store page discloses anti-cheat: $(if ($st.anticheats) { $st.anticheats -join ', ' } else { '(section present, names unreadable)' })"
            }
        }
        catch { $st.error = $_.Exception.Message; $unchecked += "Steam store page: $($st.error)" }
    }
    elseif ($launch.launcher -eq 'Steam') { $unchecked += 'Steam: no appmanifest names this folder, so the store page was not read' }
    else { $unchecked += "$($launch.launcher): no first-party per-game anti-cheat disclosure exists for this launcher" }
    $status = if ($signals) { 'signals' } elseif ($unchecked) { 'unknown' } else { 'none-disclosed' }
    [pscustomobject]@{
        status = $status; signals = $signals; unchecked = $unchecked
        note = if ($status -eq 'none-disclosed') { 'Steam requires disclosure of kernel-mode anti-cheat only; user-mode and server-side anti-cheat need not be disclosed. AreWeAntiCheatYet has an entry for the title listing no anti-cheat, and nothing matched on disk. This is not proof of no anti-cheat.' }
        awacy = [pscustomobject]$aw; steam = if ($st) { [pscustomobject]$st }
    }
}
# Any status but none-disclosed needs the user's typed game name plus the ban and block research
# the router ran, and all of it lands in the manifest. Nothing here touches the anti-cheat itself.
function Assert-Acknowledged($acr, $name) {
    if ($acr.status -eq 'none-disclosed') { return }
    $found = "anti-cheat status '$($acr.status)'. Signals: $(if ($acr.signals) { $acr.signals -join '; ' } else { 'none' }). Not checked: $(if ($acr.unchecked) { $acr.unchecked -join '; ' } else { 'none' })"
    if (-not $AcceptAntiCheatRisk) { throw "refusing: $found. Installing anyway is at the user's own risk and needs -AcceptAntiCheatRisk '$name' with -AntiCheatResearch and -AntiCheatSources; nothing was changed" }
    if (-not (NormName $name) -or (NormName $AcceptAntiCheatRisk) -ne (NormName $name)) { throw "refusing: acknowledgement '$AcceptAntiCheatRisk' does not match the game name '$name'; nothing was changed" }
    # pwsh -File hands a list over as one comma-separated string.
    $src = @($AntiCheatSources -split ',\s*(?=https?://)' | ForEach-Object Trim | Where-Object { $_ })
    if (-not "$AntiCheatResearch".Trim() -or -not $src -or @($src | Where-Object { $_ -notmatch '^https://\S+$' }).Count) {
        throw 'refusing: an acknowledgement needs -AntiCheatResearch (the ban and block research summary) and -AntiCheatSources with one or more https:// URLs; nothing was changed'
    }
    [pscustomobject]@{ typed = $AcceptAntiCheatRisk; gameName = $name; date = (Get-Date).ToString('o'); research = $AntiCheatResearch.Trim(); sources = $src }
}

# Presets: shipped under skills\dlss5\presets, local overrides under <DataDir>\presets, both
# <key>.json. Format and merge rule: reference/presets.md.
function Read-PresetFile($p) {
    $j = LoadJson $p
    foreach ($e in @($j.ini)) {
        if (-not $e) { continue }
        # Refused by name whatever its value: capture stays off, and no preset can say otherwise.
        if ($e.key -eq 'AutoCapture') { throw "preset $p sets AutoCapture; AutoCapture is never settable by a preset" }
        if ("$($e.key)" -cnotin $PresetKeys.Keys) { throw "preset $p sets '$($e.key)', which is not on the preset allow-list ($($PresetKeys.Keys -join ', '))" }
        # \A..\z, not ^..$: a trailing newline would let a value inject its own ini line.
        if ("$($e.value)" -cnotmatch '\A[A-Za-z0-9_.]+\z') { throw "preset $p value for $($e.key) must be a plain token: '$($e.value)'" }
    }
    if ($j.proxy -and $j.proxy -notin $ProxyNames) { throw "preset $p proxy '$($j.proxy)' is not one of $($ProxyNames -join ', ')" }
    $j
}
# Shipped and local merged: a local ini key wins over the shipped one, and each key keeps its source.
function Get-Preset($key) {
    if ($key -cnotmatch '\A[a-z0-9-]+\z') { throw "preset key must be lowercase letters, digits and hyphens: '$key'" }
    $files = [ordered]@{ shipped = Join-Path $script:PresetDir "$key.json"; local = Join-Path $script:DataDir "presets\$key.json" }
    $got = [ordered]@{}
    foreach ($src in $files.Keys) { if (Test-Path -LiteralPath $files[$src] -PathType Leaf) { $got[$src] = Read-PresetFile $files[$src] } }
    if (-not $got.Count) { throw "no preset '$key': neither $($files.shipped) nor $($files.local) exists" }
    $ini = [ordered]@{}
    foreach ($src in $got.Keys) {
        foreach ($e in @($got[$src].ini)) {
            if ($e) { $ini["$($e.key)"] = [pscustomobject]@{ section = $PresetKeys["$($e.key)"]; key = "$($e.key)"; value = "$($e.value)"; why = $e.why; source = $src } }
        }
    }
    $l = $got['local']; $s = $got['shipped']
    [pscustomobject]@{
        key = $key; title = $l.title ?? $s.title; proxy = $l.proxy ?? $s.proxy
        ini = @($ini.Values)
        manual = @(($l.manual ?? $s.manual) | Where-Object { $_ }); manualSource = if ($l.manual) { 'local' } elseif ($s.manual) { 'shipped' }
        sources = @(@($s.sources) + @($l.sources) | Where-Object { $_ }); recheck = $l.recheck ?? $s.recheck
        from = @($got.Keys | ForEach-Object { "$_ $($files[$_])" })
    }
}
# First preset whose match rule fits this exe dir: Steam app id, or an exe name present in it. Local first.
function Find-Preset($root) {
    $app = SteamAppId $root
    foreach ($d in (Join-Path $script:DataDir 'presets'), $script:PresetDir) {
        foreach ($f in Get-ChildItem -LiteralPath $d -Filter '*.json' -File -ErrorAction SilentlyContinue) {
            $m = (LoadJson $f.FullName).match
            if (($app -and "$($m.steamAppId)" -eq $app) -or @(@($m.exe) | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $root $_) -PathType Leaf) })) { return $f.BaseName }
        }
    }
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
        if ($seen["$($e.Section)/$($e.Key)"]) { continue }
        # AutoCapture left on dumps frames into the game folder, so its absence aborts the apply.
        if ($e.Key -eq 'AutoCapture') { throw "ini key not found: [$($e.Section)] AutoCapture; refusing to leave frame capture on" }
        # A preset key the manifest would record as set, but that never landed.
        if ($e.Required) { throw "ini key not found: [$($e.Section)] $($e.Key); the preset cannot be applied to this build" }
        Write-Warning "ini key not found, not set: [$($e.Section)] $($e.Key)=$($e.Value)"
    }
    [IO.File]::WriteAllText($path, ($lines -join "`n"), [Text.UTF8Encoding]::new($hadBom))
}

function Do-Snapshot($root) {
    $sp = Join-Path (StateDir $root) 'snapshot.json'
    $t = Tree $root
    [pscustomobject]@{
        gameDir = $root; taken = (Get-Date).ToString('o')
        dirs    = @($ModDirs | Where-Object { Test-Path -LiteralPath (Join-Path $root $_) -PathType Container })
        files   =@($t.Keys | Sort-Object | ForEach-Object { [pscustomobject]@{ Path = $_; Length = $t[$_].Length; Sha256 = $t[$_].Sha256 } })
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $sp -Encoding utf8
    "snapshot: $($t.Count) files -> $sp"
}

function Remove-EmptyModDirs($root, $snap) {
    foreach ($d in $ModDirs) {
        $dp = Join-Path $root $d
        if (-not (Test-Path -LiteralPath $dp -PathType Container)) { continue }
        if ($snap.dirs -contains $d) { continue }   # dir predates the mod
        if (Get-ChildItem -LiteralPath $dp -Recurse -File -Force) { continue }   # unknown leftovers
        Remove-Item -LiteralPath $dp -Recurse -Force
    }
}

function Do-Apply($root) {
    $sd = StateDir $root
    if ((Test-Path -LiteralPath "$sd\manifest.json") -or (Test-Path -LiteralPath "$sd\pending.json")) { throw 'already applied, run remove first' }
    $files = $BuildFiles[$Build]
    if (-not $files) { throw "unknown build '$Build' (have: $($BuildFiles.Keys -join ', '))" }
    if ($Proxy -notin $ProxyNames) { throw "unknown proxy '$Proxy' (have: $($ProxyNames -join ', '))" }

    # Refusal gates. All run before any write, the state directory included.
    if ($root -match '\\WindowsApps(\\|$)') { throw $WindowsApps }
    if (-not (Get-ChildItem -LiteralPath $root -Filter *.exe -File)) { throw "no *.exe in $root; pass the directory that holds the game executable" }
    $opts = [IO.EnumerationOptions]@{ RecurseSubdirectories = $true; IgnoreInaccessible = $true; AttributesToSkip = 0 }
    $n = @([IO.Directory]::EnumerateFiles($root, '*', $opts) | Select-Object -First 2001).Count
    # 2000 is judgment, not measured: it catches a library or game root passed by mistake.
    if ($n -gt 2000 -and -not $Force) { throw "over 2000 files under $root; is this a game or library root rather than the exe directory? Pass -Force only after the user confirms it is the exe directory" }
    if (-not (Find-Upscalers $root)) { throw $NoUpscaler }
    if ("$($script:DataDir)\".StartsWith("$root\", 'OrdinalIgnoreCase')) { throw "data_dir $($script:DataDir) is inside $root; state files would land in the tree the snapshot restores. Move data_dir outside the game directory" }
    $pr = if ($Preset) { Get-Preset $Preset }

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
    # The anti-cheat gate goes last: it is the only one that reads the network.
    $launch = Get-Launcher $root
    $acr = Get-AntiCheat $root $launch (SteamAppId $root)
    $ack = Assert-Acknowledged $acr $launch.name
    # Write probe: an Xbox app folder (or any protected one) fails here, not midway through the copy.
    $probe = Join-Path $root ('.dlss5-write-probe-' + [guid]::NewGuid().ToString('N'))
    try { [IO.File]::WriteAllBytes($probe, [byte[]]@()) }
    catch { throw "$root is not writable ($($_.Exception.Message)); nothing was changed" }
    finally { Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $probe) { throw "write probe $probe could not be removed; nothing was installed. Delete it, then rerun" }

    # Always a fresh snapshot: with no manifest the tree is pre-install, and an old snapshot may
    # predate a game update.
    New-Item -ItemType Directory -Force -Path $sd | Out-Null
    Do-Snapshot $root
    $added = @($plan | ForEach-Object { $_.To } | Sort-Object)
    $pp = Join-Path $sd 'pending.json'
    # pending.json names only files whose copy has started, so a hard kill never leaves it naming a
    # path a later game update could create and remove would then delete.
    $done = [Collections.ArrayList]::new()
    $savePending = {
        [pscustomobject]@{ gameDir = $root; build = $Build; files = @($done | ForEach-Object { [pscustomobject]@{ Path = $_ } }) } |
            ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $pp -Encoding utf8
    }
    & $savePending
    $copied = [Collections.ArrayList]::new()
    try {
        foreach ($e in $plan) {
            if ($script:FaultAfter -and $copied.Count -ge $script:FaultAfter) { throw 'injected copy fault' }
            $d = Join-Path $root $e.To
            New-Item -ItemType Directory -Force -Path (Split-Path $d -Parent) | Out-Null
            # Before the copy: a partial file must roll back too; the collision gate proved it was absent.
            [void]$copied.Add($d); [void]$done.Add($e.To); & $savePending
            Copy-Item -LiteralPath $e.From -Destination $d
        }
        # One edit per key, later wins: baseline, then preset, then the explicit switch. The
        # allow-list keeps a preset off the baseline keys, so AutoCapture=false always stands.
        $edits = [ordered]@{}
        @(
            @{ Section = 'DlssNr'; Key = 'Enabled'; Value = 'true' }
            @{ Section = 'DlssNr'; Key = 'AutoCapture'; Value = 'false' }
            @{ Section = 'Log'; Key = 'LogToFile'; Value = 'true' }
            @{ Section = 'Log'; Key = 'LogLevel'; Value = '2' }
            @($pr.ini) | Where-Object { $_ } | ForEach-Object { @{ Section = $_.section; Key = $_.key; Value = $_.value; Required = $true } }
            if ($RestoreComputeSignature) { @{ Section = 'Hotfix'; Key = 'RestoreComputeSignature'; Value = 'true' } }
        ) | ForEach-Object { $edits[$_.Key] = $_ }
        Edit-Ini (Join-Path $root 'OptiScaler.ini') @($edits.Values)
    }
    catch {
        $copied | ForEach-Object { Remove-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue }
        Remove-EmptyModDirs $root (Load-Snapshot $root)
        # Keep pending.json while anything it names survives, so remove can still find it.
        if (-not ($copied | Where-Object { Test-Path -LiteralPath $_ })) { Remove-Item -LiteralPath $pp -Force }
        throw
    }

    $drv = try { (& nvidia-smi --query-gpu=driver_version --format=csv,noheader | Select-Object -First 1).Trim() } catch { 'unknown' }
    [pscustomobject]@{
        gameDir = $root; build = $Build; proxy = $Proxy; applied = (Get-Date).ToString('o'); driver = $drv
        launcher = $launch; antiCheat = $acr; acknowledgement = $ack
        restoreComputeSignature = [bool]$RestoreComputeSignature
        iniEdits = @($edits.Values | ForEach-Object { [pscustomobject]@{ section = $_.Section; key = $_.Key; value = $_.Value } })
        preset = $pr
        runtimeHash = $rt.Hash; runtimeKnown = $rt.Known
        files = @($added | ForEach-Object {
                [pscustomobject]@{ Path = $_; Sha256 = (Get-FileHash -LiteralPath (Join-Path $root $_) -Algorithm SHA256).Hash } })
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $sd 'manifest.json') -Encoding utf8
    Remove-Item -LiteralPath $pp -Force

    "applied $Build (proxy $Proxy, driver $drv) -> $root"
    "launcher $($launch.launcher); anti-cheat $($acr.status)$(if ($ack) { "; risk acknowledged as '$($ack.typed)'" })"
    $added | ForEach-Object { "  + $_" }
    if ($pr) {
        "preset $($pr.key) ($($pr.title)):"
        $pr.ini | ForEach-Object { "  ini [$($_.section)] $($_.key)=$($_.value)  ($($_.source))" }
        if ($pr.manual) { "  manual settings ($($pr.manualSource)):"; $pr.manual | ForEach-Object { "    - $_" } }
    }
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
    Remove-EmptyModDirs $root (Load-Snapshot $root)
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

# Read-only eligibility probe: on-disk facts, the launcher, and the anti-cheat sources (on disk,
# AreWeAntiCheatYet, the Steam store page). Writes nothing.
function Do-Assess($root) {
    # A WindowsApps folder is usually unreadable, so nothing past the refusal is probed.
    if ($root -match '\\WindowsApps(\\|$)') {
        return [pscustomobject]@{ gameDir = $root; launcher = 'Xbox app'; launcherSource = 'WindowsApps path'; gameName = (Split-Path $root -Leaf); verdict = 'refused'; refusals = @($WindowsApps) } | ConvertTo-Json
    }
    $gameRoot = Get-GameRoot $root
    $hasExe = [bool](Get-ChildItem -LiteralPath $root -Filter *.exe -File)
    $collisions = @($ProxyNames | Where-Object { Test-Path -LiteralPath (Join-Path $root $_) })
    $free = @($ProxyNames | Where-Object { $_ -notin $collisions })
    $ups = @(Find-Upscalers $root)
    $appId = SteamAppId $root
    $launch = Get-Launcher $root
    $acr = Get-AntiCheat $root $launch $appId
    # A broken preset file must not hide the verdict, so its error rides in the JSON instead.
    $pr = $null; $prErr = $null
    try { if ($k = Find-Preset $root) { $pr = Get-Preset $k } } catch { $prErr = $_.Exception.Message }
    $refusals = @()
    if (-not $hasExe) { $refusals += "no *.exe in $root; pass the directory that holds the game executable" }
    elseif (-not $ups) { $refusals += $NoUpscaler }
    $verdict = if (-not $hasExe) { 'unknown' } elseif (-not $ups) { 'not-a-candidate' } elseif ($free) { 'eligible' } else { 'unknown' }
    [pscustomobject]@{
        gameDir = $root; gameRoot = $gameRoot; gameKey = (GameKey $root)
        launcher = $launch.launcher; launcherSource = $launch.source; gameName = $launch.name
        verdict = $verdict; antiCheat = $acr; acknowledgementRequired = ($acr.status -ne 'none-disclosed')
        refusals = $refusals; upscalers = $ups
        dx12 = [bool](Get-ChildItem -LiteralPath $root -Filter 'd3d12*.dll' -File) -or ($root -match '\\Binaries\\Win64$')
        proxyCollisions = $collisions; freeProxies = $free; steamAppId = $appId
        preset = $pr; presetError = $prErr
    } | ConvertTo-Json -Depth 8
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

# Every discovered game's install folder, from all launchers.
function Get-ScanRoots {
    if ($null -ne $script:ScanRoots) { return @($script:ScanRoots) }
    @(Find-Games | ForEach-Object installDir | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | Sort-Object -Unique)
}
function Find-RuntimeCandidates {
    # A missing drive has no FileSystem provider, where Get-ChildItem -File does not exist.
    @(Get-ScanRoots | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -Filter 'nvngx_dlssnr.dll' -File -Force -ErrorAction SilentlyContinue } | Sort-Object FullName -Unique)
}
# Read-only: installed games per launcher, what could not be read, and runtime DLL candidates with
# their gate result. setup check reads this.
function Do-Discover {
    $games = Find-Games
    $unchecked = $script:Unchecked
    if ($null -eq $script:ScanRoots) { $script:ScanRoots = @($games | ForEach-Object installDir | Sort-Object -Unique) }
    [pscustomobject]@{
        games = @($games | Sort-Object launcher, name); unchecked = $unchecked
        runtimeCandidates = @(Find-RuntimeCandidates | ForEach-Object {
                $t = Test-Runtime $_.FullName
                [pscustomobject]@{ path = $_.FullName; version = "$(FileVer $_.FullName)"; sha256 = $t.Hash; passes = $t.Ok; known = [bool]$t.Known; reason = $t.Reason
                    besideOptiScalerIni = (Test-Path -LiteralPath (Join-Path $_.DirectoryName 'OptiScaler.ini')) }
            })
    } | ConvertTo-Json -Depth 5
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
    $cands = Find-RuntimeCandidates
    $ok = @()
    foreach ($c in $cands) {
        $t = Test-Runtime $c.FullName
        if ($t.Ok) { $ok += [pscustomobject]@{ Path = $c.FullName; Known = $t.Known; Version = (FileVer $c.FullName) ?? [version]'0.0' } }
        else { $notes += "scan candidate refused: $($c.FullName): $($t.Reason)" }
    }
    $best = $ok | Sort-Object @{ e = { -not $_.Known } }, @{ e = { $_.Version }; Descending = $true } | Select-Object -First 1
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
            $shown = $src
            try {
                Invoke-WebRequest -Uri $src -OutFile $tmp
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

# Shell-resolvable upstream facts only; page-backed items stay in the skill. The cache MERGES: an
# item that fails keeps its previous found/checked and carries the new error, so one offline run
# never erases the baseline.
$script:Gh = 'gh'; $script:Smi = 'nvidia-smi'   # selftest points these at missing commands
function Probe($item, $source, [scriptblock]$get) {
    try {
        $v = & $get
        if (-not $v) { throw 'no value returned' }
        [pscustomobject]@{ item = $item; found = $v; source = $source; checked = (Get-Date).ToString('o'); error = $null }
    }
    catch { [pscustomobject]@{ item = $item; found = $null; source = $source; checked = $null; error = $_.Exception.Message } }
}
function Tool($name) { if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "$name not on PATH" }; $name }
function GhApi($path, $jq) {
    $gh = Tool $script:Gh
    $o = & $gh api $path --jq $jq 2>&1
    if ($LASTEXITCODE) { throw "gh api $path failed: $($o | Select-Object -First 1)" }
    @($o | Select-Object -First 5) -join '; '
}
function Do-Refetch {
    $cp = Join-Path $script:DataDir 'cache\upstream.json'
    $prev = @{}; foreach ($i in @((LoadJson $cp).items)) { if ($i) { $prev[$i.item] = $i } }
    $rel = '.[] | "\(.tag_name)\(if .prerelease then " (prerelease)" else "" end)"'
    $items = @(
        Probe 'Dagherbou/OptiScaler_DLSSNR' 'gh api releases' { GhApi 'repos/Dagherbou/OptiScaler_DLSSNR/releases' $rel }
        Probe 'wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass' 'gh api releases' { GhApi 'repos/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass/releases' $rel }
        Probe 'optiscaler/OptiScaler' 'gh api releases/latest' { GhApi 'repos/optiscaler/OptiScaler/releases/latest' '.tag_name' }
        Probe 'GeForce driver' 'nvidia-smi' { $s = Tool $script:Smi; (& $s --query-gpu=driver_version --format=csv,noheader | Select-Object -First 1).Trim() }
        Probe 'Runtime DLL' 'file version' {
            if (-not (Test-Path -LiteralPath $script:RuntimeDll)) { throw "missing: $($script:RuntimeDll)" }
            $v = FileVer $script:RuntimeDll
            if (-not $v) { throw "no version resource: $($script:RuntimeDll)" }
            "$v"
        }
    ) | ForEach-Object {
        $p = $prev[$_.item]
        if ($_.error -and $p -and $p.found) { $_.found = $p.found; $_.checked = $p.checked }
        $_
    }
    $out = [pscustomobject]@{ checked = (Get-Date).ToString('o'); items = $items } | ConvertTo-Json -Depth 4
    New-Item -ItemType Directory -Force -Path (Split-Path $cp -Parent) | Out-Null
    Set-Content -LiteralPath $cp -Value $out -Encoding utf8
    $out
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
    # Every discovery and anti-cheat source is a fixture: an empty registry, no drives, and an
    # HTTP stub serving a fixed AreWeAntiCheatYet commit and games.json plus per-app Steam pages.
    $script:Reg = @{}; $script:ProgramData = "$tmp\pd"; $script:EaRoots = @("$tmp\ea"); $script:Drives = @()
    $script:AwacySha = 'a' * 40
    $script:AwacyGames = '[{"name":"EA SPORTS FC™ 26","anticheats":["EA anticheat"],"status":"Denied","storeIds":{}},{"name":"Listed Game","anticheats":["Easy Anti-Cheat"],"status":"Supported","storeIds":{"steam":"333"}},{"name":"Clean Game","anticheats":[],"status":"Supported","storeIds":{"steam":"222"}}]'
    $script:SteamPages = @{}
    $script:HttpGet = {
        param($url, $headers)
        if ($url -like 'https://api.github.com/*') { return "{`"sha`":`"$($script:AwacySha)`"}" }
        if ($url -like 'https://raw.githubusercontent.com/*') { return $script:AwacyGames }
        if ($url -match '/app/(\d+)/' -and $script:SteamPages[$Matches[1]] -and $headers.Cookie -eq $SteamCookie) { return $script:SteamPages[$Matches[1]] }
        throw "offline fixture: $url"
    }
    # A fixture's acknowledgement: its own game name, a research summary and one source.
    function Ack($d) { $script:AcceptAntiCheatRisk = (Get-Launcher $d).name; $script:AntiCheatResearch = 'fixture research'; $script:AntiCheatSources = @('https://example.com/r') }
    try {
        $docs =Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Gaming\dlss5'
        Assert 'empty DataDir uses the default' ((Resolve-DataDir '') -eq $docs)
        Assert 'literal ${user_config.data_dir} uses the default' ((Resolve-DataDir '${user_config.data_dir}') -eq $docs)
        Assert 'no legacy state passes' (-not (Throws { Assert-NoLegacyState "$tmp\docs" } '*'))
        New-Item -ItemType Directory -Force -Path "$tmp\docs\Gaming\state" | Out-Null
        Assert 'empty legacy state passes' (-not (Throws { Assert-NoLegacyState "$tmp\docs" } '*'))
        $move = "*Move runtime\, state\, builds\, cache\ and LEDGER.md from $tmp\docs\Gaming into $tmp\docs\Gaming\dlss5*"
        New-Item -ItemType Directory -Force -Path "$tmp\docs\Gaming\state\g_1" | Out-Null
        Assert 'legacy state with no new state refuses and names the move' (Throws { Assert-NoLegacyState "$tmp\docs" } $move)
        Assert 'legacy refusal creates nothing' (-not (Test-Path -LiteralPath "$tmp\docs\Gaming\dlss5"))
        New-Item -ItemType Directory -Force -Path "$tmp\docs\Gaming\dlss5\state" | Out-Null
        Assert 'legacy state beside an empty new state still refuses' (Throws { Assert-NoLegacyState "$tmp\docs" } $move)
        New-Item -ItemType Directory -Force -Path "$tmp\docs\Gaming\dlss5\state\g_1" | Out-Null
        Assert 'state at the new default passes' (-not (Throws { Assert-NoLegacyState "$tmp\docs" } '*'))
        Assert 'relative DataDir resolves to absolute' ((Resolve-DataDir 'rel') -eq "$tmp\rel")
        Assert 'trailing backslash trimmed' ((Resolve-DataDir "$tmp\x\") -eq "$tmp\x")
        Assert 'runtime_source with a query string refused' (Throws { Resolve-Source 'https://example.com/nvngx_dlssnr.dll?token=x' } '*query string*')
        Assert 'runtime_source rejects a non-https URL' (Throws { Resolve-Source 'http://example.com/nvngx_dlssnr.dll' } '*https*')
        Assert 'Win64 twins get distinct GameKeys' ((GameKey "$tmp\a\Win64") -ne (GameKey "$tmp\b\Win64"))

        $script:DataDir = "$tmp\data"
        $script:RuntimeDll = "$tmp\nvngx_dlssnr.dll"
        Put $script:RuntimeDll 'fakemodel'
        $script:ModelHash = (Get-FileHash -LiteralPath $script:RuntimeDll -Algorithm SHA256).Hash
        $bs = "$tmp\data\builds\selftest"
        Put "$bs\OptiScaler.dll" 'fakeproxy'; Put "$bs\OptiScaler\plugin.dll" 'plug'; Put "$bs\Licenses\LICENSE.txt" 'lic'
        $ini = "[Upscalers]`nEnabled=auto`nDx11Upscaler=auto`n[Log]`nLogToFile=auto`nLogLevel=auto`n[Hotfix]`nRestoreComputeSignature=auto`nRestoreGraphicSignature=auto`n[DlssNr]`nEnabled=auto`nAutoCapture=auto`n"
        [IO.File]::WriteAllText("$bs\OptiScaler.ini", ($ini -replace "`n", "`r`n"), [Text.UTF8Encoding]::new($true))
        $BuildFiles['selftest'] = @('OptiScaler.dll', 'OptiScaler.ini', 'OptiScaler', 'Licenses')
        $script:Build = 'selftest'; $script:Proxy = 'dxgi.dll'; $script:RestoreComputeSignature = $true

        # Fixtures sit three levels deep so the non-Steam ancestor scan never leaves $tmp.
        $w = "$tmp\w\x\y"
        $g = "$w\g\Win64"
        Put "$g\game.exe" 'exe'; Put "$g\data\pak.bin" 'pak'; Put "$g\dbghelp.dll" 'stock'; Put "$g\nvngx_dlss.dll" 'dlss'
        New-Item -ItemType Directory -Force -Path "$g\OptiScalerProfiles" | Out-Null
        $script:DataDir = "$g\state"
        Assert 'data_dir inside the game dir refuses' (Throws { Do-Apply $g } '*inside*')
        $script:DataDir = "$tmp\data"
        Assert 'data_dir refusal writes nothing' (-not (Test-Path -LiteralPath "$g\state"))
        Ack $g
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
        Assert '[Hotfix] RestoreComputeSignature=true' ((IniVal $gi 'Hotfix' 'RestoreComputeSignature') -eq 'true')
        Assert 'no preset: RestoreGraphicSignature untouched' ((IniVal $gi 'Hotfix' 'RestoreGraphicSignature') -eq 'auto')
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
        Assert 'pre-existing empty mod dir kept' (Test-Path -LiteralPath "$g\OptiScalerProfiles" -PathType Container)
        Assert 'manifest deleted, snapshot kept' (-not (Test-Path -LiteralPath "$sd\manifest.json") -and (Test-Path -LiteralPath "$sd\snapshot.json"))

        # Presets: every shipped file validates, then fixture presets with a local override
        foreach ($f in Get-ChildItem -LiteralPath $script:PresetDir -Filter '*.json' -File) {
            Assert "shipped preset validates: $($f.BaseName)" (-not (Throws { Get-Preset $f.BaseName } '*'))
        }
        $script:PresetDir = "$tmp\presets"
        Put "$tmp\presets\fx.json" '{"title":"Fx","match":{"exe":["fxgame.exe"]},"ini":[{"key":"RestoreGraphicSignature","value":"true"},{"key":"Dx11Upscaler","value":"fsr22"}],"manual":["DLSS Quality"],"sources":[{"url":"https://example.com","asOf":"2026-09-23"}],"recheck":"x"}'
        Put "$tmp\data\presets\fx.json" '{"ini":[{"key":"Dx11Upscaler","value":"dlss_12"}]}'
        $pg = "$w\preset\Win64"; Put "$pg\fxgame.exe" 'exe'; Put "$pg\nvngx_dlss.dll" 'dlss'
        $pa = ((Do-Assess $pg) | ConvertFrom-Json).preset
        $dx = @($pa.ini | Where-Object key -eq 'Dx11Upscaler'); $rgs = @($pa.ini | Where-Object key -eq 'RestoreGraphicSignature')
        Assert 'assess matches a preset by exe name; the local key wins and names its source' ($pa.key -eq 'fx' -and $dx.Count -eq 1 -and $dx[0].value -eq 'dlss_12' -and $dx[0].source -eq 'local' -and $rgs[0].source -eq 'shipped' -and $pa.manualSource -eq 'shipped')
        $before = Tree $pg
        $script:Preset = 'fx'
        Ack $pg
        Do-Apply $pg | Out-Null
        $pgi = "$pg\OptiScaler.ini"
        Assert 'preset keys applied' ((IniVal $pgi 'Hotfix' 'RestoreGraphicSignature') -eq 'true' -and (IniVal $pgi 'Upscalers' 'Dx11Upscaler') -eq 'dlss_12')
        Assert 'AutoCapture=false with a preset' ((IniVal $pgi 'DlssNr' 'AutoCapture') -eq 'false')
        $pm = LoadJson "$(StateDir $pg)\manifest.json"
        Assert 'preset keys recorded in the manifest with their source' ($pm.preset.key -eq 'fx' -and @($pm.preset.ini | Where-Object { $_.key -eq 'Dx11Upscaler' -and $_.value -eq 'dlss_12' -and $_.source -eq 'local' }).Count -eq 1 -and @($pm.iniEdits | Where-Object { $_.key -eq 'RestoreGraphicSignature' -and $_.value -eq 'true' }).Count -eq 1)
        Do-Remove $pg | Out-Null
        Assert 'remove after a preset apply is byte-exact' ((SameTree (Tree $pg) $before) -and -not (Test-Path -LiteralPath "$(StateDir $pg)\manifest.json"))
        $rg = "$w\refuse\Win64"; Put "$rg\game.exe" 'exe'; Put "$rg\nvngx_dlss.dll" 'dlss'
        $before = Tree $rg
        Put "$tmp\presets\bad.json" '{"ini":[{"key":"LogLevel","value":"0"}]}'
        $script:Preset = 'bad'
        Assert 'preset key off the allow-list refused' (Throws { Do-Apply $rg } '*not on the preset allow-list*')
        Put "$tmp\presets\cap.json" '{"ini":[{"key":"AutoCapture","value":"true"}]}'
        $script:Preset = 'cap'
        Assert 'AutoCapture=true in a preset refused' (Throws { Do-Apply $rg } '*AutoCapture is never settable*')
        Put "$tmp\presets\inj.json" '{"ini":[{"key":"Dx11Upscaler","value":"dlss_12\n[DlssNr]\nAutoCapture=true"}]}'
        $script:Preset = 'inj'
        Assert 'preset value carrying a newline refused' (Throws { Do-Apply $rg } '*plain token*')
        $script:Preset = '..\fx'
        Assert 'preset key with a path refused' (Throws { Do-Apply $rg } '*lowercase letters*')
        $script:Preset = $null
        Assert 'preset refusals write nothing' ((SameTree (Tree $rg) $before) -and -not (Test-Path -LiteralPath (StateDir $rg)))

        # The mod's own upscaler copies under OptiScaler\ do not make a game a candidate
        $os = "$w\ownonly\Win64"; Put "$os\game.exe" 'exe'; Put "$os\OptiScaler\amd_fidelityfx_dx12.dll" 'fsr'; Put "$os\OptiScaler\libxess.dll" 'xess'
        Assert 'assess: upscaler DLLs only under OptiScaler\ is not-a-candidate' (((Do-Assess $os) | ConvertFrom-Json).verdict -eq 'not-a-candidate')

        $c = "$w\c\Win64"; Put "$c\game.exe" 'exe'; Put "$c\dxgi.dll" 'game-own-dxgi'; Put "$c\libxess.dll" 'xess'
        Assert 'collision fails before copying' (Throws { Do-Apply $c } '*collision*')
        Assert 'collision dir untouched, no state' (@(Get-ChildItem -LiteralPath $c -Recurse -File).Count -eq 3 -and -not (Test-Path -LiteralPath (StateDir $c)))

        # No hookable upscaler: frame generation, ray reconstruction and the NR runtime do not count
        $nc = "$w\nc\Win64"; Put "$nc\game.exe" 'exe'
        foreach ($d in 'nvngx_dlssnr.dll', 'nvngx_dlssg.dll', 'nvngx_dlssd.dll', 'libxess_fg.dll', 'amd_fidelityfx_framegeneration_dx12.dll') { Put "$nc\$d" 'x' }
        $before = Tree $nc
        Assert 'no upscaler DLL: apply refuses as not a candidate' (Throws { Do-Apply $nc } '*not a candidate*')
        Assert 'not-a-candidate refusal writes nothing' ((SameTree (Tree $nc) $before) -and -not (Test-Path -LiteralPath (StateDir $nc)))
        $nca = (Do-Assess $nc) | ConvertFrom-Json
        Assert 'assess: no upscaler DLL is not-a-candidate with a reason' ($nca.verdict -eq 'not-a-candidate' -and@($nca.refusals | Where-Object { $_ -like '*no upscaler to hook*' }).Count -eq 1 -and @($nca.upscalers).Count -eq 0)
        $fs = "$w\fsr\Win64"; Put "$fs\game.exe" 'exe'; Put "$fs\AMD_FidelityFX_DX12.dll" 'fsr'
        $fsa = (Do-Assess $fs) | ConvertFrom-Json
        Assert 'assess: FSR-only fixture is eligible' ($fsa.verdict -eq 'eligible' -and @($fsa.upscalers).Count -eq 1 -and $fsa.upscalers[0].family -eq 'FSR')
        $xs = "$w\xess\Win64"; Put "$xs\game.exe" 'exe'; Put "$xs\sub\libxess.dll" 'xess'
        $xsa = (Do-Assess $xs) | ConvertFrom-Json
        Assert 'assess: XeSS-only fixture is eligible' ($xsa.verdict -eq 'eligible' -and $xsa.upscalers[0].family -eq 'XeSS' -and $xsa.upscalers[0].file -eq 'sub\libxess.dll')
        $un = "$w\unreal\Proj\Binaries\Win64"; Put "$un\Proj-Win64-Shipping.exe" 'exe'
        Put "$w\unreal\Engine\Plugins\Runtime\Nvidia\DLSS\Binaries\ThirdParty\Win64\nvngx_dlss.dll" 'dlss'
        Assert 'assess: non-Steam Unreal finds DLSS under Engine\Plugins' (((Do-Assess $un) | ConvertFrom-Json).verdict -eq 'eligible')

        $a = "$tmp\ac\a\b\c"; Put "$a\game.exe" 'exe'; Put "$a\nvngx_dlss.dll" 'dlss'
        New-Item -ItemType Directory -Force -Path "$tmp\ac\EasyAntiCheat" | Out-Null
        $script:AcceptAntiCheatRisk = $null
        Assert 'EasyAntiCheat three levels above the exe dir refuses without an acknowledgement' (Throws { Do-Apply $a } "*anti-cheat status 'signals'*on disk*EasyAntiCheat*")
        Assert 'anti-cheat refusal copies nothing' (@(Get-ChildItem -LiteralPath $a -Recurse -File).Count -eq 2 -and -not (Test-Path -LiteralPath (StateDir $a)))

        $x = "$w\noexe"; Put "$x\readme.txt" 'r'
        Assert 'directory with no *.exe refuses' (Throws { Do-Apply $x } '*no `*.exe*')

        $f = "$w\f\Win64"; Put "$f\game.exe" 'exe'; Put "$f\nvngx_dlss.dll" 'dlss'
        $before = Tree $f
        $script:Proxy = '..\escape.dll'
        Assert 'proxy outside the allow-list refuses' (Throws { Do-Apply $f } '*unknown proxy*')
        $script:Proxy = 'dxgi.dll'
        Assert 'proxy refusal writes nothing' (-not (Test-Path -LiteralPath "$w\f\escape.dll") -and -not (Test-Path -LiteralPath (StateDir $f)))
        $script:FaultAfter = 3
        Ack $f
        Assert 'copy fault midway rethrows' (Throws { Do-Apply $f } '*injected*')
        $script:FaultAfter = 0
        Assert 'copy fault leaves tree byte-identical' ((SameTree (Tree $f) $before) -and -not (Test-Path -LiteralPath "$f\OptiScaler"))
        Assert 'copy fault leaves no pending.json or manifest' (-not (Test-Path -LiteralPath "$(StateDir $f)\pending.json") -and -not (Test-Path -LiteralPath "$(StateDir $f)\manifest.json"))

        # Launcher discovery: one fixture per launcher's own record format
        $sp = "$tmp\steam"; $l2 = "$tmp\lib2"
        $script:Reg['HKCU:\Software\Valve\Steam'] = @{ SteamPath = ($sp -replace '\\', '/') }
        Put "$sp\steamapps\libraryfolders.vdf" "`"libraryfolders`"`n{`n`t`"0`"`n`t{`n`t`t`"path`"`t`t`"$($sp -replace '\\', '\\')`"`n`t}`n`t`"1`"`n`t{`n`t`t`"path`"`t`t`"$($l2 -replace '\\', '\\')`"`n`t}`n}"
        $acf = { param($id, $name, $dir) "`"AppState`"`n{`n`t`"appid`"`t`t`"$id`"`n`t`"name`"`t`t`"$name`"`n`t`"installdir`"`t`t`"$dir`"`n}" }
        Put "$l2\steamapps\appmanifest_111.acf" (& $acf 111 "Tom Clancy`u{2019}s Ack Game" 'Ack Game')
        Put "$l2\steamapps\appmanifest_222.acf" (& $acf 222 'Clean Game' 'Clean Game')
        Put "$l2\steamapps\appmanifest_333.acf" (& $acf 333 'Listed Game' 'Listed')
        Put "$tmp\pd\Epic\EpicGamesLauncher\Data\Manifests\A1.item" (@{ DisplayName = 'Epic Game'; AppName = 'Ep'; InstallLocation = "$tmp\epic\EpicGame" } | ConvertTo-Json)
        Put "$tmp\pd\Epic\UnrealEngineLauncher\LauncherInstalled.dat" (@{ InstallationList = @(@{ AppName = 'EpicTwo'; InstallLocation = "$tmp\epic\Two" }) } | ConvertTo-Json -Depth 3)
        Put "$tmp\ea\EA SPORTS FC 26\__Installer\installerdata.xml" '<DiPManifest><contentIDs><contentID>1</contentID></contentIDs></DiPManifest>'
        Put "$tmp\pd\Origin\LocalContent\Old\OFB-1.mfst" ('?id=OFB-1&dipInstallPath=' + [uri]::EscapeDataString("$tmp\origin\Old Game\"))
        $un = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        $script:Reg["$un\Overwatch"] = @{ DisplayName = 'Overwatch'; InstallLocation = "$tmp\bnet\Overwatch"; UninstallString = '"C:\Program Files (x86)\Battle.net\Battle.net.exe" --uid=prometheus' }
        $script:Reg["$un\Quoted"] = @{ DisplayName = 'Quoted'; InstallLocation = "`"$tmp\bnet\Quoted`""; UninstallString = 'Battle.net.exe --uid=q' }
        $script:Reg["$un\Relative"] = @{ DisplayName = 'Relative'; InstallLocation = 'C:'; UninstallString = 'Battle.net.exe --uid=r' }
        $script:Reg['HKLM:\SOFTWARE\WOW6432Node\ubisoft\Launcher\Installs\999'] = @{}
        $script:Reg["$un\Other"] =@{ DisplayName = 'Other'; InstallLocation = "$tmp\other"; UninstallString = '"C:\Other\unins000.exe"' }
        $script:Reg['HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games\1207658924'] = @{ gameName = 'The Witcher 3'; path = "$tmp\gog\Witcher 3" }
        $script:Reg['HKLM:\SOFTWARE\WOW6432Node\ubisoft\Launcher\Installs\635'] = @{ InstallDir = ("$tmp\ubi\Siege\" -replace '\\', '/') }
        $d1 = "$tmp\d1\"; $d2 = "$tmp\d2\"; $script:Drives = @($d1, $d2)
        $appx = { param($n) "<Package xmlns=`"http://schemas.microsoft.com/appx/manifest/foundation/windows10`"><Properties><DisplayName>$n</DisplayName></Properties></Package>" }
        Put "$($d1)Games\Forza\Content\appxmanifest.xml" (& $appx 'Forza Fixture')
        [IO.File]::WriteAllBytes("$($d1).GamingRoot", [byte[]](@(0x52, 0x47, 0x42, 0x58) + [BitConverter]::GetBytes([uint32]1) + [Text.Encoding]::Unicode.GetBytes("Games`0")))
        Put "$($d1)Program Files\ModifiableWindowsApps\Gears\appxmanifest.xml" (& $appx 'ms-resource:AppName')
        Put "$($d2).GamingRoot" 'garbage'
        Put "$($d2)XboxGames\Halo\appxmanifest.xml" (& $appx 'Halo Fixture')
        $found = Find-Games
        $has = { param($l, $nm, $d) [bool]@($found | Where-Object { $_.launcher -eq $l -and $_.name -eq $nm -and $_.installDir -eq $d }).Count }
        Assert 'discover Steam: registry, libraryfolders.vdf, appmanifest' (& $has 'Steam' "Tom Clancy`u{2019}s Ack Game" "$l2\steamapps\common\Ack Game")
        Assert 'discover Epic: .item manifest' (& $has 'Epic Games Launcher' 'Epic Game' "$tmp\epic\EpicGame")
        Assert 'discover Epic: LauncherInstalled.dat' (& $has 'Epic Games Launcher' 'EpicTwo' "$tmp\epic\Two")
        Assert 'discover EA app: installerdata.xml under an EA root' (& $has 'EA app' 'EA SPORTS FC 26' "$tmp\ea\EA SPORTS FC 26")
        Assert 'discover Origin: .mfst dipInstallPath' (& $has 'Origin' 'Old Game' "$tmp\origin\Old Game")
        Assert 'discover Battle.net: Uninstall entries with --uid only' ((& $has 'Battle.net' 'Overwatch' "$tmp\bnet\Overwatch") -and -not @($found | Where-Object name -eq 'Other').Count)
        Assert 'discover: a quoted folder is unquoted; a drive-relative one is skipped' ((& $has 'Battle.net' 'Quoted' "$tmp\bnet\Quoted") -and -not @($found | Where-Object name -eq 'Relative').Count)
        Assert 'discover: a stale Ubisoft key does not stop the rest' (-not @($script:Unchecked | Where-Object { $_ -like 'Ubisoft*' }).Count)
        Assert 'discover GOG: GOG.com\Games registry' (& $has 'GOG Galaxy' 'The Witcher 3' "$tmp\gog\Witcher 3")
        Assert 'discover Ubisoft: InstallDir with forward slashes' (& $has 'Ubisoft Connect' 'Siege' "$tmp\ubi\Siege")
        Assert 'discover Xbox: .GamingRoot folder, manifest under Content' (& $has 'Xbox app' 'Forza Fixture' "$($d1)Games\Forza\Content")
        Assert 'discover Xbox: ModifiableWindowsApps; an ms-resource name falls back to the folder' (& $has 'Xbox app' 'Gears' "$($d1)Program Files\ModifiableWindowsApps\Gears")
        Assert 'discover Xbox: malformed .GamingRoot falls back to XboxGames and says so' ((& $has 'Xbox app' 'Halo Fixture' "$($d2)XboxGames\Halo") -and @($script:Unchecked | Where-Object { $_ -like '*d2\.GamingRoot unreadable*fell back*' }).Count -eq 1)
        Assert 'discover names what it cannot read (EA install list, Battle.net product.db)' (@($script:Unchecked | Where-Object { $_ -like 'EA app:*not read*' -or $_ -like 'Battle.net:*product.db*' }).Count -eq 2)
        $dj = (Do-Discover) | ConvertFrom-Json
        Assert 'discover verb prints every launcher' (@($dj.games.launcher | Sort-Object -Unique).Count -eq 8)

        $wg = "$tmp\gog\Witcher 3\bin\x64"; Put "$wg\witcher3.exe" 'exe'; Put "$wg\nvngx_dlss.dll" 'dlss'
        $wa = (Do-Assess $wg) | ConvertFrom-Json
        Assert 'assess names the launcher and game from the GOG record; best case unknown' ($wa.launcher -eq 'GOG Galaxy' -and $wa.gameName -eq 'The Witcher 3' -and $wa.antiCheat.status -eq 'unknown' -and $wa.acknowledgementRequired)
        $eg = "$tmp\m\EgsGame\Binaries"; Put "$tmp\m\EgsGame\.egstore\x.manifest" 'm'; Put "$eg\g.exe" 'exe'
        Assert 'assess names Epic from the .egstore marker' (((Do-Assess $eg) | ConvertFrom-Json).launcher -eq 'Epic Games Launcher')
        $bg = "$tmp\bnet\Overwatch\_retail_"; Put "$bg\Overwatch.exe" 'exe'
        $bn = (Do-Assess $bg) | ConvertFrom-Json
        Assert 'Battle.net title is a signal citing EULA 1.C.i and 1.C.ii' ($bn.launcher -eq 'Battle.net' -and $bn.antiCheat.status -eq 'signals' -and @($bn.antiCheat.signals | Where-Object { $_ -like '*EULA sections 1.C.i and 1.C.ii*' }).Count -eq 1)
        $fc = "$tmp\ea\EA SPORTS FC 26"; Put "$fc\FC26.exe" 'exe'
        $fa = (Do-Assess $fc) | ConvertFrom-Json
        Assert 'AWACY match by name ignores the trademark glyph' ($fa.launcher -eq 'EA app' -and $fa.antiCheat.status -eq 'signals' -and @($fa.antiCheat.signals | Where-Object { $_ -like 'AreWeAntiCheatYet (commit aaaaaaa) lists EA SPORTS FC*26: EA anticheat' }).Count -eq 1)
        $lg = "$l2\steamapps\common\Listed"; Put "$lg\l.exe" 'exe'
        $script:SteamPages['333'] = '<div class="apphub_AppName">Listed Game</div>'
        Assert 'AWACY match by Steam app id' (@(((Do-Assess $lg) | ConvertFrom-Json).antiCheat.signals | Where-Object { $_ -like '*lists Listed Game: Easy Anti-Cheat' }).Count -eq 1)

        # Acknowledgement: required, mismatched, missing research, accepted and recorded
        $script:SteamPages['111'] = '<div class="apphub_AppName">Tom Clancy&#8217;s Ack Game</div><div class="anticheat_section DRM_notice"><div class="anticheat_name">Easy Anti-Cheat</div></div>'
        $ag = "$l2\steamapps\common\Ack Game\bin"; Put "$ag\ack.exe" 'exe'; Put "$ag\nvngx_dlss.dll" 'dlss'
        $aa = (Do-Assess $ag) | ConvertFrom-Json
        Assert 'Steam store anti-cheat section is a signal' ($aa.launcher -eq 'Steam' -and $aa.steamAppId -eq '111' -and $aa.antiCheat.steam.storeName -eq "Tom Clancy`u{2019}s Ack Game" -and @($aa.antiCheat.signals | Where-Object { $_ -eq 'Steam store page discloses anti-cheat: Easy Anti-Cheat' }).Count -eq 1)
        $before = Tree $ag
        $script:AcceptAntiCheatRisk = $null
        Assert 'ack required: a signal refuses without an acknowledgement' (Throws { Do-Apply $ag } "*anti-cheat status 'signals'*-AcceptAntiCheatRisk*")
        $script:AcceptAntiCheatRisk = 'Ack Game'; $script:AntiCheatResearch = 'r'; $script:AntiCheatSources = @('https://example.com/r')
        Assert 'ack mismatched: another name refuses' (Throws { Do-Apply $ag } '*does not match the game name*')
        $script:AcceptAntiCheatRisk = "tom clancy's ack game"; $script:AntiCheatResearch = ' '
        Assert 'ack without research refuses' (Throws { Do-Apply $ag } '*-AntiCheatResearch*')
        $script:AntiCheatResearch = 'No ban reports found'; $script:AntiCheatSources = @('http://insecure.example')
        Assert 'ack without an https source refuses' (Throws { Do-Apply $ag } '*-AntiCheatSources*')
        Assert 'ack refusals write nothing' ((SameTree (Tree $ag) $before) -and -not (Test-Path -LiteralPath (StateDir $ag)))
        $script:AntiCheatSources = @('https://example.com/r, https://example.com/s')   # the one-string form pwsh -File delivers
        Do-Apply $ag | Out-Null
        $am = LoadJson "$(StateDir $ag)\manifest.json"
        Assert 'ack accepted: manifest records the typed name, research, sources, date, signals and AWACY commit' ($am.acknowledgement.typed -eq "tom clancy's ack game" -and $am.acknowledgement.research -eq 'No ban reports found' -and "$($am.acknowledgement.sources)" -eq 'https://example.com/r https://example.com/s' -and $am.acknowledgement.date -and $am.antiCheat.status -eq 'signals' -and $am.antiCheat.awacy.commit -eq $script:AwacySha -and $am.launcher.launcher -eq 'Steam')
        Do-Remove $ag | Out-Null
        Assert 'remove after an acknowledged apply is byte-exact' ((SameTree (Tree $ag) $before) -and -not (Test-Path -LiteralPath "$(StateDir $ag)\manifest.json"))

        $script:SteamPages['222'] = '<div class="apphub_AppName">Clean Game</div>'
        $cg = "$l2\steamapps\common\Clean Game"; Put "$cg\clean.exe" 'exe'; Put "$cg\nvngx_dlss.dll" 'dlss'
        $cga = (Do-Assess $cg) | ConvertFrom-Json
        Assert 'Steam with nothing disclosed anywhere: none-disclosed, no acknowledgement, caveat stated' ($cga.antiCheat.status -eq 'none-disclosed' -and -not $cga.acknowledgementRequired -and $cga.antiCheat.note -like '*not proof of no anti-cheat*')
        $script:SteamPages['444'] = '<div class="apphub_AppName">Unlisted Game</div>'
        Put "$l2\steamapps\appmanifest_444.acf" (& $acf 444 'Unlisted Game' 'Unlisted')
        $ul = "$l2\steamapps\common\Unlisted"; Put "$ul\u.exe" 'exe'
        $ula = (Do-Assess $ul) | ConvertFrom-Json
        Assert 'Steam with a clean page but no AWACY entry is unknown, not none-disclosed' ($ula.antiCheat.status -eq 'unknown' -and @($ula.antiCheat.unchecked | Where-Object { $_ -like '*no entry for this title*' }).Count -eq 1)
        $script:SteamPages['222'] = '<div id="agecheck">'
        Assert 'Steam age gate is unknown, not none-disclosed' (((Do-Assess $cg) | ConvertFrom-Json).antiCheat.status -eq 'unknown')
        $script:SteamPages['222'] = '<div class="apphub_AppName">Clean Game</div>'
        $ok = $script:HttpGet
        $script:HttpGet = { param($url, $headers) if ($url -like 'https://api.github.com/*') { throw 'offline' }; & $ok $url $headers }
        $ua = (Do-Assess $cg) | ConvertFrom-Json
        Assert 'AWACY fetch failure: unknown, never none-disclosed' ($ua.antiCheat.status -eq 'unknown' -and $null -eq $ua.antiCheat.awacy.commit -and @($ua.antiCheat.unchecked | Where-Object { $_ -like 'AreWeAntiCheatYet: fetch failed*' }).Count -eq 1)
        $script:AcceptAntiCheatRisk = $null
        Assert 'AWACY fetch failure: apply refuses without an acknowledgement' (Throws { Do-Apply $cg } "*anti-cheat status 'unknown'*AreWeAntiCheatYet*")
        $script:HttpGet = $ok

        # Xbox: WindowsApps refused before any write; an XboxGames install applies and the write probe leaves nothing
        $wx = "$tmp\WindowsApps\Pkg_1.0_x64\Game"; Put "$wx\g.exe" 'exe'; Put "$wx\nvngx_dlss.dll" 'dlss'
        $before = Tree $wx
        Assert 'WindowsApps: apply refuses and writes nothing' ((Throws { Do-Apply $wx } '*WindowsApps*') -and (SameTree (Tree $wx) $before) -and -not (Test-Path -LiteralPath (StateDir $wx)))
        $wxa = (Do-Assess $wx) | ConvertFrom-Json
        Assert 'WindowsApps: assess verdict refused, launcher Xbox app' ($wxa.verdict -eq 'refused' -and $wxa.launcher -eq 'Xbox app')
        $xg = "$($d1)Games\Forza\Content"; Put "$xg\forza.exe" 'exe'; Put "$xg\nvngx_dlss.dll" 'dlss'
        $before = Tree $xg
        Ack $xg
        Do-Apply $xg | Out-Null
        Assert 'Xbox XboxGames install applies; the write probe is not in the snapshot' ((LoadJson "$(StateDir $xg)\manifest.json").launcher.launcher -eq 'Xbox app' -and -not @((Load-Snapshot $xg).files | Where-Object { $_.Path -like '.dlss5-write-probe-*' }).Count)
        Do-Remove $xg | Out-Null
        Assert 'Xbox remove is byte-exact' (SameTree (Tree $xg) $before)

        $script:RuntimeDll = "$tmp\other.dll"; Put $script:RuntimeDll 'unknown-runtime'
        Assert 'unknown-hash runtime refused' (Throws { Do-Apply $f } '*runtime DLL refused*')

        # assess: read-only verdicts
        $aa = (Do-Assess $a) | ConvertFrom-Json
        Assert 'assess reports on-disk anti-cheat as a signal needing acknowledgement' ($aa.antiCheat.status -eq 'signals' -and $aa.acknowledgementRequired -and @($aa.antiCheat.signals | Where-Object { $_ -like 'on disk:*EasyAntiCheat' }).Count -eq 1)
        $ca = (Do-Assess $c) | ConvertFrom-Json
        Assert 'assess lists dxgi.dll collision, not as a free proxy' ('dxgi.dll' -in $ca.proxyCollisions -and 'dxgi.dll' -notin $ca.freeProxies)
        $k = "$w\clean\Win64"; Put "$k\game.exe" 'exe'; Put "$k\nvngx_dlss.dll" 'dlss'
        $ka = (Do-Assess $k) | ConvertFrom-Json
        Assert 'assess: clean fixture from no known launcher is eligible, anti-cheat unknown' ($ka.verdict -eq 'eligible' -and $ka.launcher -eq 'unknown' -and $ka.gameName -eq 'clean' -and $ka.antiCheat.status -eq 'unknown' -and $ka.acknowledgementRequired)
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
        $script:RuntimeSource = 'https://example.com/nvngx_dlssnr.dll?token=x'
        Assert 'provision -Runtime refuses a query-string source before any fetch' (Throws { Do-ProvisionRuntime } '*query string*')
        Put "$tmp\src\nvngx_dlssnr.dll" 'fakemodel'; $script:RuntimeSource = "$tmp\src\nvngx_dlssnr.dll"
        Do-ProvisionRuntime | Out-Null
        Assert 'runtime_source path is placed' ((LoadJson "$tmp\data\runtime\.provisioned.json").source -eq 'runtime_source')

        # A build whose ini lacks [DlssNr] AutoCapture rolls back instead of leaving capture on
        $BuildFiles['noac'] = @('OptiScaler.dll', 'OptiScaler.ini')
        Put "$tmp\data\builds\noac\OptiScaler.dll" 'p'; Put "$tmp\data\builds\noac\OptiScaler.ini" "[DlssNr]`nEnabled=auto`n"
        $script:Build = 'noac'
        $n = "$w\noac\Win64"; Put "$n\game.exe" 'exe'; Put "$n\nvngx_dlss.dll" 'dlss'
        $before = Tree $n
        Ack $n
        Assert 'missing AutoCapture key aborts apply' (Throws { Do-Apply $n } '*AutoCapture*')
        Assert 'aborted apply leaves the tree byte-identical' ((SameTree (Tree $n) $before) -and -not (Test-Path -LiteralPath "$(StateDir $n)\manifest.json"))

        # refetch: no gh or nvidia-smi available, and the cache merges rather than overwrites
        $script:Gh = 'gh-missing-selftest'; $script:Smi = 'nvidia-smi-missing-selftest'
        $uc = "$tmp\data\cache\upstream.json"
        Put $uc '{"checked":"x","items":[{"item":"GeForce driver","found":"616.92","source":"nvidia-smi","checked":"2026-09-22T00:00:00Z","error":null}]}'
        Do-Refetch | Out-Null
        $u = LoadJson $uc
        Assert 'refetch writes a parseable cache without gh' ($u -and @($u.items).Count -eq 5)
        $dg = @($u.items) | Where-Object item -eq 'Dagherbou/OptiScaler_DLSSNR'
        Assert 'refetch records a missing gh as an error, not a failure' ($null -eq $dg.found -and $dg.error -like '*not on PATH*')
        $dr = @($u.items) | Where-Object item -eq 'GeForce driver'
        Assert 'refetch keeps the previous value when a probe fails' ($dr.found -eq '616.92' -and $dr.checked -eq '2026-09-22T00:00:00Z' -and $dr.error)
        $rd = @($u.items) | Where-Object item -eq 'Runtime DLL'
        Assert 'refetch reports an unversioned runtime DLL as an error' ($null -eq $rd.found -and $rd.error -like '*no version resource*')
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
    'refetch' { Do-Refetch }
    'discover' { Do-Discover }
    'selftest' { Do-Selftest; exit ([int]$script:fails) }
}
