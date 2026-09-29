# DLSS5-Feeder route (unverified guidance, #4592)

The shipped `gaming:dlss5` skill implements the **in-process OptiScaler DLSS-NR** route only:
`apply`, `remove`, `status`, and byte-exact manifests target that path. Games with **no built-in
temporal upscaler** can still get DLSS 5 through the community
[DLSS5-Feeder](https://github.com/jlrouzies-fr/DLSS5-Feeder) ReShade add-on route. That workflow is
**out of scope for `apply`/`remove`** and unverified here: it is a manual pattern from field
reports, and `assess` does not check it.

## Anti-cheat and multiplayer

The Feeder route does not lower anti-cheat risk. It needs ReShade's add-on build, which is unsigned,
and it needs a working ReShade depth buffer, which ReShade disables during multiplayer. It gets the
same refuse-by-default gate as the in-process route ([`anticheat-posture.md`](anticheat-posture.md)):
`assess` names it only when `antiCheat.status` is `none-disclosed`, and then only with "play modded
only solo or offline". The plugin never suggests disabling or bypassing an anti-cheat.

## When Feeder applies

| Game shape | Feeder pattern (manual today) |
|---|---|
| 32-bit exe, no upscaler | x86 ReShade + `dlss5-feed.addon32` + `host64\` helper stack (upstream labels it beta) |
| 64-bit exe, no upscaler | ReShade as `dxgi.dll` + `dlss5-feed.addon64` + a neural consumer add-on |

The 32-bit dead end (NVIDIA ships no 32-bit NGX, so in-process OptiScaler NR cannot load in a
32-bit process, and an upscaler mod does not change that) applies to the in-process route only.
The 32-bit row is a separate, unverified manual pattern that runs NGX in a 64-bit helper process.
`assess` cannot verify or install it, and it is under the same anti-cheat gate.

Feeder also needs a motion-vector provider (upstream recommends LumeniteFX Kernel), chosen with the
`DLSS5_MV_PROVIDER` preprocessor definition and enabled above `DLSS5_Feed` in the technique order.
`DLSS5_Feed.fx` includes `ReShade.fxh`. Run the Feeder's `Verify-DLSS5Feeder.ps1` after a manual
install; read `dlss5-feed.log` for consumer and motion-vector health.
A reporter's #4592 list also named `ReShadeUI.fxh`, `DrawText.fxh` and `FontAtlas.png` as required
headers: single reporter, not verified upstream (neither the README nor the shaders at the pinned
commit reference them), so do not tell a user to fetch them.

## How `assess` should talk about it

When `verdict` is `not-a-candidate` because **no upscaler DLL** was found:

1. State plainly that the **OptiScaler in-process route** cannot help without an upscaler to hook.
2. When `bitness` is `32-bit`, state the 32-bit dead end above and that it covers the in-process
   route only.
3. Name **DLSS5-Feeder** only when `antiCheat.status` is `none-disclosed`. Then name it as the
   documented, unverified manual alternative and point here (for a 32-bit title, as a separate
   unverified path); do not imply `apply` will install it. Repeat the `antiCheat.note` (no kernel
   anti-cheat was disclosed, not proof the game has none) and tell the user to play modded only
   solo or offline. When the status is `signals` or `unknown`, do not point here: say the Feeder
   route does not lower anti-cheat risk, and never suggest bypassing or disabling an anti-cheat.

## Field reports (single reporter, not verified upstream)

Every item below comes from the live installs reported in #4592 (Alien: Isolation, Mass Effect
Legendary Edition) and none is confirmed by the Feeder README. `assess` does not read
`dlss5-feed.log`, so it surfaces none of them.

- **Alien: Isolation as a 32-bit example, working with OptiScaler as `host64\winmm.dll`.** The
  README describes that layout in general (OptiScaler renamed `winmm.dll` in `host64\` for a 32-bit
  game) but names no such game.
- **Luma add-on on the 64-bit route.** In Mass Effect Legendary Edition the log showed
  `NVSDK_NGX_D3D12_Init raised exception 0xC0000005` in the Luma add-on; a RenoDX HDR consumer
  worked instead. The README documents a different Luma crash (Metro 2033 Redux under Smooth
  Motion) and lists BioShock Remastered, a 32-bit title, as a Luma HDR success.
- **Flat depth after the first launch.** The log showed `depth is FLAT while the scene moves:
  ReShade's Generic Depth is on the wrong buffer`. The reporter found this common and silent. The
  README says only that a depth probe warns when sampled depth is flat and that the warning is
  diagnostic; it makes no claim about how common the condition is.

## Tracking

Full manifest-backed Feeder support (route detection, apply/remove/status, verifier integration)
is `#4592`. Whether to adopt it or scope it down is an open decision there; until it is made, this
file is unverified operator guidance.

## Verification record

Upstream: `jlrouzies-fr/DLSS5-Feeder` at commit `d2a7229` (2026-09-29), README blob `fb2a43d`,
fetched 2026-09-29 with `gh api repos/jlrouzies-fr/DLSS5-Feeder/contents`. The README is that
project's own description, not independent evidence, and it changes often (releases land every one
to three days). No artifact hash is pinned or attested here.

| Claim | Basis | As of | Recheck trigger |
|---|---|---|---|
| ReShade's add-on build is unsigned, and ReShade disables depth during multiplayer | https://reshade.me/: depth is "automatically disabled during multiplayer to prevent exploitation"; the add-on API is "only enabled in the ReShade build with full add-on support, which is unsigned" | 2026-09-29 | reshade.me drops either statement, or ships a signed add-on build |
| The Feeder needs ReShade's depth buffer | README at `d2a7229`: "any D3D11, D3D12, Vulkan or OpenGL game with a working ReShade depth buffer and a motion vector provider should work" | 2026-09-29 | A Feeder release or README change to that sentence |
| A 32-bit game uses `dlss5-feed.addon32` next to the exe plus a `host64\` folder holding `dlss5-feed-host64.exe` and a 64-bit ReShade `dxgi.dll`; NGX is 64-bit only; upstream labels the route beta | README at `d2a7229`, "Install for a 32-bit game (beta)" | 2026-09-29 | A Feeder release or README change to that section |
| A 64-bit game uses `dlss5-feed.addon64` next to the exe with ReShade installed as `dxgi.dll` (its installer's "DirectX 10/11/12" choice) | README at `d2a7229`, "Install for a 64-bit game" | 2026-09-29 | A Feeder release or README change to that section |
| The Feeder needs a neural consumer add-on beside the feed add-on (Deep Fried Chicken or `renodx-dlss5.addon64`, exactly one) | README at `d2a7229`, requirements table | 2026-09-29 | A Feeder release or README change to that table |
| A motion-vector provider is chosen with `DLSS5_MV_PROVIDER` and enabled above `DLSS5_Feed`; LumeniteFX Kernel is the recommended one | README at `d2a7229`, "0.6.1: read this before installing" and the 64-bit install steps | 2026-09-29 | A Feeder release or README change to the provider section |
| `DLSS5_Feed.fx` includes `ReShade.fxh`, which ReShade's standard shader package normally provides | `shaders/DLSS5_Feed.fx` line 60 at `d2a7229`; README at `d2a7229`, 64-bit install step 2 | 2026-09-29 | A Feeder release or README change to the shader includes |
| `Verify-DLSS5Feeder.ps1` ships in the Feeder, checks the whole layout and reads the logs | `tools/Verify-DLSS5Feeder.ps1` in the tree at `d2a7229`; README at `d2a7229`, 32-bit and RenoDX passages | 2026-09-29 | A Feeder release or README change to the verifier |
| `dlss5-feed.log` sits next to the game exe and reports feature creation, delivered frames and the motion-vector probe | README at `d2a7229`, "Check `dlss5-feed.log`" and the guide-probe passage | 2026-09-29 | A Feeder release or README change to the log lines |
