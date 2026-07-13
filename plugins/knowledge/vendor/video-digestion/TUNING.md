# Pipeline tuning defaults (D9)

Starting values from RESEARCH lane 2 and `design-threads.md` D9. Host e2e on driver
(`7zZy1QTvokM`, 2026-06-11): dynamic coverage plan replaces soft cap; stratified + cue-anchor
frames merged with scene-detect. Variation smokes in `evals/fixtures/variation-matrix-backlog.json`.

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

## Densification (`youtube-extraction/watching/densification.js`)

| Constant | Default | Module export |
| --- | --- | --- |
| Window padding (sec) | `5` | `DEFAULT_WINDOW_PADDING_SEC` |
| Dense multiplier | `3` | `DEFAULT_DENSITY_MULTIPLIER` |
| Sparse multiplier | `1` | `DEFAULT_SPARSE_MULTIPLIER` |

Keyword signals: `DENSIFICATION_SIGNALS` (code/slide/demo/terminal patterns).

**Tune signal:** driver video is mixed talking-head + on-screen prompts — expect moderate densification, not screencast-density.

## Dynamic coverage (`youtube-extraction/watching/compute-coverage-plan.js`)

| Constant | Default | Module export |
| --- | --- | --- |
| Short video max (sec) | `90` | `SHORT_VIDEO_MAX_SEC` |
| Short stratified interval (sec) | `5` | `SHORT_STRATIFIED_INTERVAL_SEC` |
| Medium stratified interval (sec) | `45` | `MEDIUM_STRATIFIED_INTERVAL_SEC` |
| Long stratified interval (sec) | `60` | `LONG_STRATIFIED_INTERVAL_SEC` |
| Scene sparse ratio | `120` | `SCENE_SPARSE_RATIO` |

No hard frame cap — `summarizeFrameSelection` sets `highVolume` when count > `targetMinFrames * 3`.

## Post-watch retune checklist (host)

After `/youtube watch` on driver video:

1. Compare selected frame count vs soft cap.
2. Note false-negative scene cuts (missed slide transitions) → adjust `DEFAULT_SCENE_THRESHOLD`.
3. Note duplicate-heavy contact sheets → tighten `DEFAULT_MAX_HAMMING_DISTANCE`.
4. Note missed code windows → extend `DENSIFICATION_SIGNALS` or raise `DEFAULT_DENSITY_MULTIPLIER`.
5. Record final values in this file and export constants if changed.
