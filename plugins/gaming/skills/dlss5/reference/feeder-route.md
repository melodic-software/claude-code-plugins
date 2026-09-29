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

| Claim | Basis | As of | Recheck trigger |
|---|---|---|---|
| ReShade's add-on build is unsigned, and ReShade disables depth during multiplayer | https://reshade.me/: depth is "automatically disabled during multiplayer to prevent exploitation"; the add-on API is "only enabled in the ReShade build with full add-on support, which is unsigned" | 2026-09-29 | reshade.me drops either statement, or ships a signed add-on build |
| The Feeder needs ReShade's depth buffer | DLSS5-Feeder README: "any D3D11, D3D12, Vulkan or OpenGL game with a working ReShade depth buffer and a motion vector provider should work" | 2026-09-29 | The README stops requiring ReShade depth |

## When Feeder applies

| Game shape | Feeder pattern (manual today) |
|---|---|
| 32-bit exe, no upscaler | x86 ReShade add-on + `dlss5-feed.addon32` + `host64\` helper stack |
| 64-bit exe, no upscaler | ReShade add-on as `dxgi.dll` + `dlss5-feed.addon64` + in-process consumer add-on |

The 32-bit dead end (NVIDIA ships no 32-bit NGX, so in-process OptiScaler NR cannot load in a
32-bit process, as in Alien: Isolation, and an upscaler mod does not change that) applies to the
in-process route only. The 32-bit row is a separate, unverified manual pattern that runs NGX in a
64-bit helper process. `assess` cannot verify or install it, and it is under the same anti-cheat
gate.

Feeder needs motion-vector provider add-ons, preprocessor defines, technique order, and shared ReShade
headers (`ReShade.fxh`, `ReShadeUI.fxh`, `DrawText.fxh`, `FontAtlas.png`). Run the Feeder's
`Verify-DLSS5Feeder.ps1` after a manual install; read `dlss5-feed.log` for depth and consumer health.

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

## Field reports (single reporter, not surfaced by assess)

Both come from the live installs reported in #4592 (Alien: Isolation, Mass Effect Legendary
Edition). `assess` does not read `dlss5-feed.log`, so it surfaces neither.

- **Luma add-on on the 64-bit route.** In Mass Effect Legendary Edition the log showed
  `NVSDK_NGX_D3D12_Init raised exception 0xC0000005` in the Luma add-on; a RenoDX HDR consumer
  worked instead. Luma's documented Feeder
  success (BioShock Remastered) is 32-bit, where NGX runs in the helper process.
- **Flat depth after the first launch.** The log showed `depth is FLAT while the scene moves:
  ReShade's Generic Depth is on the wrong buffer`. The reporter found this common and silent.

## Tracking

Full manifest-backed Feeder support (route detection, apply/remove/status, verifier integration)
is `#4592`. Whether to adopt it or scope it down is an open decision there; until it is made, this
file is unverified operator guidance.
