# Tuning guide

Tuning happens in the fork's in-game overlay, opened with Insert unless a preset rebinds
`[Menu] ShortcutKey`. Its Save Settings rewrites `OptiScaler.ini` in the game folder, and `status`
treats that change as expected; `capture` then keeps the allow-listed changes as the game's local
preset. Change one thing at a time and record it in the ledger row.

## Proof it runs

- `<game-dir>\OptiScaler.log` gains lines like `DlssNr_Dx12::Dispatch DLSS-NR cost: ~7.4 ms total`.
  `apply` turns file logging on for this.
- The overlay's Neural Rendering section shows `Running - N ms per frame`.
- The cost scales with output resolution, not internal render resolution. 7.4 ms was Cyberpunk 2077
  at 3840x2160 on an RTX 5090.

## Baseline: start here

Verified live in Cyberpunk 2077 on the proving-ground machine; the same starting point applies to
any title.

| Setting | Value | Why |
|---|---|---|
| Output resolution | Native (3840x2160 there) | NR cost follows output resolution |
| In-game DLSS mode | **Quality, not Auto** | Auto picked Performance (1080p internal at 4K). The overlay's `Target Res: 5760x3240 (3.00)` line was Output Scaling's disabled preview, and `3.00` was the tell; the fix was DLSS Quality, not a resolution change |
| Model controls | Defaults: Detail 1.0, Color 1.0 | The fork's README: 1.0 is the model's picture, and above 1 is exaggeration |
| Model resolution (`WorkingScale`) | 100% (1.0) | Above 1.0 supersamples, and cost grows with area |
| `[DlssNr] AutoCapture` | `false`, always | Its default writes uncompressed frame captures into the game folder. `apply` sets it; keep it |
| Reversible proxy | Hybrid proxy + composed | The fork author's stated recommendation; the default is Off |
| White point source | Paper white, set by eye | The exposure scan is opt-in, off by default, and fails on some titles |
| Neural Rendering toggle key | Bind one under Keybinds, or set `ToggleKey` in the local base preset for every game | Unbound by default; it lets the user A/B without the menu. `reference/presets.md` recommends F13 to F24 |
| When to enable NR | After the game has loaded | Enabling it during a load crashed RE Engine titles (fork issues #22, #7); in-game enabling did not |

## Per title

| Title | Notes |
|---|---|
| Cyberpunk 2077 | Proxy `dxgi.dll`, never `dbghelp.dll` (`bin\x64\dbghelp.dll` is a stock game file). Leave the exposure scan off: it cannot find this game's exposure. Do not enable Output Scaling: OptiScaler's menu marks the game incompatible. `RestoreComputeSignature` stays `auto` |
| 007 First Light | Apply with the `007-first-light` preset, which sets `RestoreComputeSignature=true`: upstream's wiki says NVIDIA users need it "to avoid crashes when overriding sharpness, using Output Scaling". Turn forced sharpness down with Sharpness Override before judging NR. Start with path tracing and Ray Reconstruction off, then enable them one at a time: the only Blackwell report for this title (fork issue #50, Linux) faulted on the first NR frame with RR on |
| Dying Light: The Beast | Ships DX11 and DX12 renderers; run DX12. The overlay does not receive mouse clicks here; use the keyboard |
| Ready or Not | Use the in-game resolution scale slider to set the input resolution |

## Troubleshooting

| Symptom | Try | Source |
|---|---|---|
| NR looks inert: the log shows `DLSS-NR cost` lines, the picture does not change | Switch White point source to the other setting, manual paper white or game exposure, and compare. Reports conflict on which one fixes it | wilsjo2 #34 (`v0.7.6`, fixed by manual paper white); wilsjo2 #96 (`v0.8.7`, fixed by game exposure) |

## What to record

Per game in the ledger: ini deltas from stock, driver, DLL version, FPS before and after in the
same scene at the same settings, a visual verdict, and crashes with where they happened.

## Verification record

| Claim | Basis | As of | Recheck trigger |
|---|---|---|---|
| Cyberpunk baseline and the 7.4 ms cost | Live session on an RTX 5090, driver 616.92, Dagherbou `v0.2.0-patch1` | 2026-09-20 | A new build or driver |
| Per-title notes | Upstream OptiScaler wiki pages (Cyberpunk 2077 last tested 0.9.3, 007 First Light 0.9.4), fork release notes and source, fork issues #7, #22, #50 | 2026-09-20 | A new build, or the title's wiki page changes |
| NR-inert white point row | `gh api` on wilsjo2 issues #34 and #96 and their comments | 2026-09-23 | A fork release changes White point source |
| 007 First Light gained path tracing and Ray Reconstruction on 2026-09-15, after both pinned builds | NVIDIA's 616.92 driver announcement | 2026-09-20 | A fork release that names the title |
