# Candidate selection

Which games the mod can change, what `assess` checks, and which sources to trust for per-game
settings.

## Requirements

| Requirement | Source |
|---|---|
| The game ships its own temporal upscaler: DLSS 2+, FSR 2+ or XeSS. Neural Rendering hooks that upscaler call, and the color, depth and motion vectors it runs on come from it. With no upscaler there is nothing to hook | Upstream OptiScaler README ("already support DLSS2+ / FSR2+ / XeSS"); Dagherbou `v0.2.0-dlssnr` notes ("A game that already uses an upscaler"); wilsjo2 `v0.8.3` notes ("An unreadable depth/motion frame is skipped") |
| A DX11 game runs NR only with `Dx11Upscaler=dlss_12`, the dx11on12 bridge | wilsjo2 `OptiScaler.ini`; Dagherbou `v0.2.0-dlssnr` notes. Upstream README puts the bridge's cost at "up to 10-ish %" |
| GeForce driver 616.56 or later | Dagherbou `v0.2.0-dlssnr` notes; wilsjo2 `INSTALL-DLSSNR.md` |
| No anti-cheat signal, or the user's typed at-own-risk acknowledgement after the anti-cheat review. Online games: solo or offline play only | `reference/anticheat-posture.md`; upstream README ("Do not use this mod with online games") |
| A 64-bit game exe. NVIDIA's DLSS SDK ships Windows NGX libraries for x86-64, ARM64 and ARM64EC only, and a 32-bit process cannot load a 64-bit DLL | NVIDIA/DLSS `lib/` (`Windows_x86_64`, `Windows_aarch64`, `Windows_arm64ec`; no 32-bit target); Microsoft, Process Interoperability ("a 32-bit process cannot load a 64-bit DLL"); wilsjo2 README ("a supported 64-bit game") |

## Bitness and DirectX 12

`assess` reads each `*.exe` in the exe directory as a PE image, per Microsoft's PE format spec, and
reports it in `executables`: `machine` (the COFF Machine field, such as `0x8664` for x64, `0x14C`
for x86 or `0xAA64` for ARM64), `format` (the optional-header magic: `0x10b` is `PE32`, `0x20b` is
`PE32+`), `managed`, `dx12` and `dx12Basis`.

- **`bitness`** is `32-bit` only when every exe is a native `PE32`. That is a refusal: verdict
  `not-a-candidate` in `assess`, and `apply` refuses before any write. `64-bit` means every exe is
  `PE32+`, which covers ARM64 as well as x64, so the check keys on the magic, not a machine list.
  `mixed` (a 32-bit helper beside a 64-bit game) is not refused. `unknown` covers an exe that is
  not a readable PE image and a managed (.NET) `PE32`, since an AnyCPU exe runs as a 64-bit
  process wherever it can.
- **`dx12`** is `true` when an exe has `d3d12.dll` in its import table or its delay-load import
  table, or exports `D3D12SDKVersion` (Microsoft's Agility SDK requires that export "from the main
  .exe"). It is `false` when every exe imports `d3d11.dll` with none of those. Otherwise it is
  `null`, unknown, with each exe's `dx12Basis` naming why. A `d3d12*.dll` file beside the exe and an
  Unreal `Binaries\Win64` path are not evidence either way: a proxy can carry that file name, and an
  Unreal game can be D3D11.

## What `assess` detects

`assess` looks for these DLLs under the game tree and reports them in `upscalers`. The names are
the upscaler libraries OptiScaler recognizes by name in its loader (`OptiScaler/DllNames.h`).

| Family | Files |
|---|---|
| DLSS | `nvngx_dlss.dll` |
| FSR 2+ | `ffx_fsr2_api_x64.dll`, `ffx_fsr2_api_dx12_x64.dll`, `ffx_fsr3upscaler_x64.dll`, `amd_fidelityfx_dx12.dll`, `amd_fidelityfx_loader_dx12.dll`, `amd_fidelityfx_upscaler_dx12.dll`, `amd_fidelityfx_vk.dll` |
| XeSS | `libxess.dll`, `libxess_dx11.dll` |

These are not upscalers and do not count: `nvngx_dlssg.dll` (frame generation), `nvngx_dlssd.dll`
(ray reconstruction), `nvngx_dlssnr.dll` (the NR runtime itself), `libxess_fg.dll`, `libxell.dll`,
and the `amd_fidelityfx_framegeneration_dx12.dll`, denoiser and radiance cache DLLs.

The game tree is the Steam `common` folder of the game; for a non-Steam Unreal game, the install
root three levels above the project's `Binaries` `Win64` folder, where `Engine` `Plugins` keeps the
upscaler plugins; otherwise the exe directory.

No DLL from the table gives the verdict `not-a-candidate`, and `apply` refuses it before any write.
There is no override flag.

Known gaps:

- **An upscaler compiled into the executable leaves no DLL.** Such a game reads as
  `not-a-candidate` even though it has an upscaler. Judgment, not sourced.
- **A DLL on disk is not proof the game calls it.** The real test is the `DLSS-NR cost` log line in
  `reference/tuning-guide.md`. Judgment, not sourced.
- **A renderer loaded at run time is in no PE table.** A game that loads D3D12 with `LoadLibrary`
  (Microsoft, Run-Time Dynamic Linking) and exports no `D3D12SDKVersion` reads `dx12: null`. So does
  one that imports only `dxgi.dll`, which D3D10 through D3D12 all use. Launch it on DX12 and check
  the log line above.

## Non-candidates

- **No temporal upscaler.** Most 2D, pixel-art and older titles, such as Stardew Valley. No source
  addresses 2D games directly; they fall under "no upscaler". The only no-upscaler path in the fork
  trackers is an unmerged proof of concept (wilsjo2 #6) that feeds constant depth and zero motion
  vectors. The plugin does not support it.
- **Anti-cheat.** Refused on disk and by the Steam store check; see
  `reference/anticheat-posture.md`.

A game with no upscaler of its own can become a candidate through a third-party upscaler mod. Use
one the OptiScaler wiki lists in the "Upscaler mods support" section of its compatibility list, and
read that game's compatibility entry. Install the mod as the user, then rerun `assess`. It clears
the gate only if the mod places one of the DLLs above. Do not add a second NR injector beside the
fork: wilsjo2's install guide warns that two NR injectors can conflict.

## Engine notes

The engine is not a gate. It changes setup.

| Engine | Note | Standing |
|---|---|---|
| Unreal | Use DLSS inputs: the Unreal XeSS plugin provides no depth | Upstream README |
| RE Engine | Needs REFramework | OptiScaler wiki Capcom RE Engine page; wilsjo2 #56 |
| RE Engine | If DLSS inputs keep crashing, or the GUI breaks, the wiki suggests `RestoreComputeSignature` or `RestoreGraphicSignature` | Conditional fallback, not a default |
| RE Engine | wilsjo2 #56: DEVICE_HUNG on `v0.8.3` | Only reported on Onimusha; open, no maintainer reply |
| 007 First Light (Glacier 2) | OptiScaler 0.9.3+ applies `RestoreComputeSignature` itself for AMD and Intel; on NVIDIA the wiki needs it only when overriding sharpness or using Output Scaling | Conditional, one title. The wiki's Hitman World of Assassination page, same engine, has no such entry |
| REDengine (Cyberpunk 2077) | Use the `dxgi.dll` proxy: a `d3d12.dll` hook conflicts with Streamline and greys out Ray Reconstruction | Dagherbou #8 owner reply; OptiScaler wiki Cyberpunk page |
| REDengine (Cyberpunk 2077) | Dagherbou's exposure scan cannot see this game's exposure | Single source: Dagherbou `v0.2.0-dlssnr` notes |
| Unreal 5 | One game (Unreal 5.6.1) lingered about 4 minutes after quit, then crashed | Single report: Dagherbou #52 |
| Snowdrop, Frostbite, Unity, id Tech | No reliable reports found | No data |

wilsjo2's install guide names `dbghelp.dll` as its validated Cyberpunk 2077 proxy. The plugin keeps
`dxgi.dll`: the game's own exe folder ships a stock Microsoft `dbghelp.dll`, and `apply` never
overwrites a game file, so the collision gate would refuse `dbghelp.dll` there anyway.

## Per-game config sources

| Source | Use |
|---|---|
| Upstream OptiScaler wiki per-game pages | Trusted for the OptiScaler layer: proxy name, inputs, known issues. No NR settings. Upstream's README names GitHub, Discord and Nitec's Nexus as its only legitimate sources |
| wilsjo2 `INSTALL-DLSSNR.md` game notes | Trusted primary, three games |
| edgarbatjr `OptiScaler_DLSSNR-THERMOTRON-multipass` `presets` | An unvetted third fork. Read its ini values for reference; never install its build |
| Fork issue threads | One user's values each; judge per comment |
| PCGamingWiki | Engine, API and upscaler facts only; it has no NR guidance |
| SEO mod sites (download mirrors, "DLSS 5 mod" landing pages, such as xmodhub) | **Untrusted.** Upstream's README names GitHub, Discord and Nitec's Nexus as its only legitimate sources, and the one engine and anti-cheat claim traced to such a site had no second source |
| Guide-style issues authored by FlashAust on the wilsjo2 tracker | **Untrusted.** Self-closed, no replies, implausible steps. #85 reports a failed attempt at an NGX registry signature-verification bypass. Copy nothing, and never apply NGX registry edits |

## Verification record

| Claim | Basis | As of | Recheck trigger |
|---|---|---|---|
| Upscaler requirement, DX11 `dlss_12`, driver 616.56 | Upstream README; Dagherbou `v0.2.0-dlssnr` notes; wilsjo2 `v0.8.3` notes, `OptiScaler.ini`, `INSTALL-DLSSNR.md`; independent verification pass | 2026-09-23 | A fork release changes its requirements |
| Upscaler DLL names | `gh api repos/optiscaler/OptiScaler/contents/OptiScaler/DllNames.h`, last changed in commit `3bae321` (2026-06-11) | 2026-09-23 | `DllNames.h` changes, or a game ships an upscaler under a new name |
| No 32-bit Windows NGX library | `gh api repos/NVIDIA/DLSS/contents/lib`: `Windows_x86_64`, `Windows_aarch64`, `Windows_arm64ec`, `Linux_x86_64`, `Linux_aarch64` (release `v310.9.1`, HEAD `3749594`); Microsoft, [Process Interoperability](https://learn.microsoft.com/en-us/windows/win32/winprog64/process-interoperability) | 2026-09-27 | An NVIDIA/DLSS release adds a 32-bit Windows `lib/` target |
| PE fields `assess` reads | Microsoft, [PE Format](https://learn.microsoft.com/en-us/windows/win32/debug/pe-format): signature offset at 0x3c, COFF Machine, optional-header magic, data directories 0 (export), 1 (import), 13 (delay import), 14 (CLR header), the delay-load RvaBased bit, and the lexically ordered export name pointer table | 2026-09-27 | The PE format page changes any of those fields |
| DX12 evidence rules | Microsoft, [Agility SDK getting started](https://devblogs.microsoft.com/directx/gettingstarted-dx12agility/) (`D3D12SDKVersion` "exported from the main .exe"); [Run-Time Dynamic Linking](https://learn.microsoft.com/en-us/windows/win32/dlls/run-time-dynamic-linking); [DXGI overview](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/d3d10-graphics-programming-guide-dxgi); C# [PlatformTarget](https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/compiler-options/output) (AnyCPU exes run as 64-bit processes) | 2026-09-27 | A live `assess` reads `dx12` wrong for a game whose API is known |
| Engine notes and config sources | OptiScaler wiki clone (HEAD `2803618`); wilsjo2 #6, #56, #85; Dagherbou #8, #52; independent verification pass | 2026-09-23 | The wiki page or issue changes |
