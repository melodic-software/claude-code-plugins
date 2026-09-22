# DLSS 5 mod ledger

One row per game the DLSS 5 Neural Rendering mod is applied to. `/gaming:dlss5` writes these rows
with the model's Edit tool; `Invoke-Dlss5Mod.ps1` writes the machine-readable half to
`state\<GameKey>\manifest.json` under the data directory.

Columns: **Game** title. **Exe dir** the directory the mod is injected into (the `-GameDir`
argument). **Anti-cheat** kernel or user-mode anti-cheat present, `none` if safe to inject.
**Build** which OptiScaler DLSS-NR fork is installed (`dagherbou` or `wilsjo2`) and its tag.
**Proxy** the DLL name `OptiScaler.dll` is renamed to. **ini deltas** the `OptiScaler.ini` keys
changed from stock. **Driver** GeForce driver version at apply time. **DLL** `nvngx_dlssnr.dll`
runtime version. **Applied** date applied. **FPS before / after** same scene, same settings,
measured. **Visual verdict** subjective quality call. **Crashes** count and where. **Notes**
anything a future apply or remove needs to know.

| Game | Exe dir | Anti-cheat | Build | Proxy | ini deltas | Driver | DLL | Applied | FPS before | FPS after | Visual verdict | Crashes | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|

## Upstream watch

One row per upstream item `/gaming:dlss5 refetch` tracks. **Known version** the last version seen.
**Checked** the date of that check. **How to recheck** the command or page that answers it. The
first `refetch` fills the empty cells.

| Item | Known version | Checked | How to recheck |
|---|---|---|---|
| Dagherbou/OptiScaler_DLSSNR | | | `gh api repos/Dagherbou/OptiScaler_DLSSNR/releases --jq '.[].tag_name'` (the pinned release is a prerelease, so `releases/latest` skips it) |
| wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass | | | `gh api repos/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass/releases --jq '.[].tag_name'` |
| nvngx_dlssnr.dll | | | `(Get-Item '<data-dir>\runtime\nvngx_dlssnr.dll').VersionInfo.FileVersion` |
| GeForce driver | | | `nvidia-smi --query-gpu=driver_version --format=csv,noheader` vs https://www.nvidia.com/download/index.aspx |
| NVIDIA native DLSS 5 games | | | https://www.nvidia.com/en-us/geforce/news/ |
