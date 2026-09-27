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

Single-source note, not a check: wilsjo2's README asks for "a supported 64-bit game". Neither
Dagherbou nor upstream states a bitness requirement, and `assess` does not test for one.

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

Known gaps, both judgment rather than sourced:

- **An upscaler compiled into the executable leaves no DLL.** Such a game reads as
  `not-a-candidate` even though it has an upscaler.
- **A DLL on disk is not proof the game calls it.** The real test is the `DLSS-NR cost` log line in
  `reference/tuning-guide.md`.

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
| Engine notes and config sources | OptiScaler wiki clone (HEAD `2803618`); wilsjo2 #6, #56, #85; Dagherbou #8, #52; independent verification pass | 2026-09-23 | The wiki page or issue changes |
