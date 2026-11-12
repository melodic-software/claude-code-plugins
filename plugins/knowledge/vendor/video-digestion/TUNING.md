# Pipeline tuning defaults (D9)

Starting values from RESEARCH lane 2 and `design-threads.md` D9. Host e2e on driver
(`7zZy1QTvokM`, 2026-06-11): dynamic coverage plan replaces soft cap; stratified + cue-anchor
frames merged with scene-detect. Variation smokes in `skills/video-digest/reference/variation-matrix-backlog.json`.

**ffmpeg spawn:** local file inputs must omit `-user_agent`/`-headers` (ffmpeg 8+); remote
HLS/HTTP URLs keep them (`isRemoteVideoInput` in `frames/scene-detect.js`).

## Scene detect (`frames/scene-detect.js`)

| Constant | Default | Module export |
| --- | --- | --- |
| Scene threshold | `0.15` | `DEFAULT_SCENE_THRESHOLD` |
| Interval fallback fps | `1/30` | `DEFAULT_INTERVAL_FPS` |
| Min frames before fallback | `5` | `DEFAULT_MIN_FRAMES_FOR_SCENE` |
| Scale filter | `1280:-1` | `DEFAULT_SCALE_FILTER` |

**Tune signal:** screencasts may need lower threshold; talking-head may tolerate higher.

## Perceptual dedup (`frames/dedup.js`)

| Constant | Default | Module export |
| --- | --- | --- |
| Max Hamming distance | `8` | `DEFAULT_MAX_HAMMING_DISTANCE` |

**Tune signal:** slide decks with minor animation may need tighter distance; mixed demos may need looser.

## Densification (`video-extraction/watching/densification.js`)

| Constant | Default | Module export |
| --- | --- | --- |
| Window padding (sec) | `5` | `DEFAULT_WINDOW_PADDING_SEC` |
| Dense multiplier | `3` | `DEFAULT_DENSITY_MULTIPLIER` |
| Sparse multiplier | `1` | `DEFAULT_SPARSE_MULTIPLIER` |

Keyword signals: `DENSIFICATION_SIGNALS` (code/slide/demo/terminal patterns).

**Tune signal:** driver video is mixed talking-head + on-screen prompts, so expect moderate densification, not screencast-density.

## Dynamic coverage (`video-extraction/watching/compute-coverage-plan.js`)

| Constant | Default | Module export |
| --- | --- | --- |
| Short video max (sec) | `90` | `SHORT_VIDEO_MAX_SEC` |
| Short stratified interval (sec) | `5` | `SHORT_STRATIFIED_INTERVAL_SEC` |
| Medium stratified interval (sec) | `45` | `MEDIUM_STRATIFIED_INTERVAL_SEC` |
| Long stratified interval (sec) | `60` | `LONG_STRATIFIED_INTERVAL_SEC` |
| Scene sparse ratio | `120` | `SCENE_SPARSE_RATIO` |
| Max gap between timed frames, short (sec) | `5` | `SHORT_MAX_FRAME_GAP_SEC` |
| Max gap between timed frames, medium (sec) | `6` | `MEDIUM_MAX_FRAME_GAP_SEC` |
| Max gap between timed frames, long ceiling (sec) | `60` | `LONG_MAX_FRAME_GAP_SEC` |
| Gap-fill frame budget, long | `80` | `LONG_GAP_FILL_FRAME_BUDGET` |

`maxFrameGapForDuration` picks the cap by the stratified tiers: up to `SHORT_VIDEO_MAX_SEC` short,
up to `MEDIUM_DURATION_THRESHOLD_SEC` medium; longer videos get duration divided by
`LONG_GAP_FILL_FRAME_BUDGET`, rounded up, held between the medium cap and `LONG_MAX_FRAME_GAP_SEC`
(20 min: 15 s; 80 min and longer: 60 s). `run-watch.js --max-frame-gap-sec <sec>`
overrides it for one run, and the value used is recorded as `maxFrameGapSec` in
`coverage-plan.json` and `watch.json`.

Basis per tier (as of 2026-11-11; recheck when a digest misses visuals or a sheet count jumps):

- **Short (5 s):** the short stratified interval, so a short video with scene cuts is filled as
  densely as one without. At most 18 fill frames at 90 s.
- **Medium (6 s):** measured on a 3:28 presenter-plus-demo video (`C33hJGt-ySg`, 2026-11-11). The
  old 60 s default gave 27 frames on 2 sheets and missed demo screens shown in 14-29 s stretches
  between scene cuts; `--max-frame-gap-sec 6` gave 49 frames on 4 sheets, and 10 of the 12
  promoted frames existed only in that run. At most 50 fill frames (4 sheets) at 300 s, half of
  `HIGH_VOLUME_CONTACT_SHEET_MIN`.
- **Long (budget 80, 6-60 s):** removes the jump from 6 s to 60 s at 300 s, which left a 6-minute
  demo sampled like the old default. 49 frames filled 4 sheets on the medium run, so about 80 fill
  frames stay under `HIGH_VOLUME_CONTACT_SHEET_MIN` (8 sheets) before scene frames are added
  (judgment, unmeasured past 300 s: each fill frame costs vision tokens). Past 80 min the 60 s
  ceiling holds, one fill frame per minute, so a 2 h video stays at 120 or fewer.

**Tune signal:** a digest that misses visuals in a long stretch without scene cuts needs a lower
maximum gap; a talking-head video that gains many near-identical fill frames tolerates a higher one.

No hard frame cap. `isHighVolume` (`video-extraction/watching/frame-budget.js`) decides `highVolume`.

## Post-watch retune checklist (host)

After `/video-digest watch` on driver video:

1. Compare selected frame count vs soft cap.
2. Note false-negative scene cuts (missed slide transitions) → adjust `DEFAULT_SCENE_THRESHOLD`.
3. Note duplicate-heavy contact sheets → tighten `DEFAULT_MAX_HAMMING_DISTANCE`.
4. Note missed code windows → extend `DENSIFICATION_SIGNALS` or raise `DEFAULT_DENSITY_MULTIPLIER`.
5. Record final values in this file and export constants if changed.
