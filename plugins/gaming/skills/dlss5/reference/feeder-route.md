# DLSS5-Feeder route (research park, #4592)

The shipped `gaming:dlss5` skill implements the **in-process OptiScaler DLSS-NR** route only:
`apply`, `remove`, `status`, and byte-exact manifests target that path. Live installs on games with
**no built-in temporal upscaler** can still get DLSS 5 through the community
[DLSS5-Feeder](https://github.com/jlrouzies-fr/DLSS5-Feeder) ReShade add-on route; that workflow is
**out of scope for `apply`/`remove` today** and is documented here so `assess` can steer operators
correctly until manifest support lands.

## When Feeder applies

| Game shape | Feeder pattern (manual today) |
|---|---|
| 32-bit exe, no upscaler | x86 ReShade add-on + `dlss5-feed.addon32` + `host64\` helper stack |
| 64-bit exe, no upscaler | ReShade add-on as `dxgi.dll` + `dlss5-feed.addon64` + in-process consumer add-on |

Feeder needs motion-vector provider add-ons, preprocessor defines, technique order, and shared ReShade
headers (`ReShade.fxh`, `ReShadeUI.fxh`, `DrawText.fxh`, `FontAtlas.png`). Run the Feeder's
`Verify-DLSS5Feeder.ps1` after a manual install; read `dlss5-feed.log` for depth and consumer health.

## How `assess` should talk about it

When `verdict` is `not-a-candidate` because **no upscaler DLL** was found:

1. State plainly that the **OptiScaler in-process route** cannot help without an upscaler to hook.
2. When `bitness` is `32-bit`, state that **NGX is 64-bit only**; in-process NR cannot load in the
   game process (Alien: Isolation class).
3. For 64-bit no-upscaler titles, name **DLSS5-Feeder** as the documented manual alternative and
   point here; do not imply `apply` will install it.
4. Surface known `assess` gaps from field reports (#4592): wrong `dx12` heuristics on some titles,
   Luma + 64-bit Feeder NGX crashes (suggest RenoDX HDR consumer where applicable), flat depth
   after first launch.

## Tracking

Full manifest-backed Feeder support (route detection, apply/remove/status, verifier integration) remains
#4592. This file is the research-settle park until that ships.
