# Frame QC

`qc.py` decodes the rendered MP4 and decides every check from the frames. The camera rect of each
frame is measured by registering the frame against the capture it samples (normalized
cross-correlation over zoom and position, caption band left out), never read from the EDL; the
render log only names which capture a frame samples, and a frame that does not match it fails
`capture-match`. This is the answer to producer metrics that disagreed with the frames.

All thresholds live in one place, `scripts/defaults.json` (`qc` and `motion`, with `camera` and
`captions` for the geometry). Override any of them with `--config FILE` holding the same shape
(`build_edl.py` takes the same flag; unknown keys are refused). The values come from the
independent review of the prototype video, which set the acceptance rules this QC enforces.

| Check | Rule | Thresholds |
|---|---|---|
| `zoom-share` | Share of runtime (title excluded) at or above the zoom threshold | `qc.zoom_share_min` 0.6, `qc.zoom_threshold` 1.2 |
| `edge-clip` | On settled zoomed frames, every frame edge that is not the page edge lies in a gutter of the capture under it | `qc.edge_ink_max`, `qc.edge_band`; the plan uses the wider `camera.gutter_band` |
| `target-headroom` | Each click target is in shot with headroom at its click | `camera.safe_margin` (half of it in QC) |
| `caption-anchor` | Captions use only the primary anchor or the one fixed fallback | `captions.anchors` (first two) |
| `stillness` | No still stretch (caption band masked) longer than the limit | `qc.still_max` 1.5 s |
| `motion` | Each move's peak zoom and pan speed and acceleration, from its measured 10-90% duration and total change | `motion.max_zoom_rate` 0.8/s, `max_zoom_accel` 4.0/s², `max_pan_speed` 0.5 frame widths/s, `max_pan_accel` 2.5/s², tolerance `qc.motion_tolerance`; the plan also keeps moves at or above `motion.min_move_duration` 0.55 s |
| `nav-cuts` | Each page cut has the camera still across it and is taken at 1.0x, or with clean edges | `qc.nav_zoom_max`, `qc.nav_change_min` |
| `crossfade` | No frame near a page change is a blend of its neighbors | `qc.crossfade_gain` |
| `blank` | No flat, white or black frame after the title | `qc.blank_std`, `qc.white_luma` |
| `capture-match` | Every page frame matches its capture | `qc.match_min` |

Checks that depend on the camera report `SKIP` in the plain style.

Outputs in the QC directory: `qc.json` (every check, its detail, and the measured zoom per frame),
`sheet-key-moments.png` (cuts, zoom peaks, the longest still) and, on a failure,
`sheet-failures.png`. Hand the sheets and the video to the independent reviewer.

Where the numbers came from: the motion limits were set while tuning the prototype for motion
comfort, the 60% at 1.2x zoom share, the gutter rule, the 1.5 s stillness limit, the 0.55 s
minimum move and the 1.0x navigation cut are the fixes the independent frame review of the fifth
prototype cut required.
