# DLSS 5 mod ledger

One row per game the DLSS 5 Neural Rendering mod is applied to. `/gaming:dlss5` writes these rows
with the model's Edit tool; `Invoke-Dlss5Mod.ps1` writes the machine-readable half to
`manifest.json` in the game's key folder under `state` in the data directory.

Columns: **Game** title. **Exe dir** the directory the mod is injected into (the `-GameDir`
argument). **Anti-cheat** the status (`signals`, `unknown` or `none-disclosed`, never "none") and each
signal; when the user acknowledged the risk, the date, the name they typed, the research summary
and its source URLs.
**Build** which OptiScaler DLSS-NR fork is installed (`dagherbou` or `wilsjo2`) and its tag, both
from the manifest (`build`, `tag`).
**Proxy** the DLL name `OptiScaler.dll` is renamed to. **ini deltas** the `OptiScaler.ini` keys
changed from stock. **Driver** GeForce driver version at apply time. **DLL** `nvngx_dlssnr.dll`
runtime version. **Applied** date applied. **FPS before / after** same scene, same settings,
measured. **Visual verdict** subjective quality call. **Crashes** count and where. **Notes**
anything a future apply or remove needs to know, including the launcher, the preset key, each key's source
(`shipped-base`, `shipped`, `local-base` or `local`), the sources' as-of date, and any `capture`.

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
| nvngx_dlssnr.dll | | | `$v = (Get-Item -LiteralPath '<data-dir>\runtime\nvngx_dlssnr.dll').VersionInfo; '{0}.{1}.{2}.{3}' -f $v.FileMajorPart, $v.FileMinorPart, $v.FileBuildPart, $v.FilePrivatePart` (not `FileVersion`, which reads `310,8,0,0`) |
| GeForce driver | | | `nvidia-smi --query-gpu=driver_version --format=csv,noheader` vs https://www.nvidia.com/download/index.aspx |
| NVIDIA native DLSS 5 games | | | https://www.nvidia.com/en-us/geforce/news/ |
| Upstream OptiScaler | | | `gh api repos/optiscaler/OptiScaler/releases/latest --jq .tag_name`; Neural Rendering merge PRs: `gh api repos/optiscaler/OptiScaler/pulls/1116 --jq .merged` and the same for `1158` |
