---
bump: minor
---

### Changed

- **`/explainer-video:produce` normalizes narrated loudness.** `render.py` runs ffmpeg `loudnorm` in two passes on the narration before the mux, measures the muxed file again, and fails it when its integrated loudness is off the target or its true peak is over the ceiling (`loudness` in the new `scripts/defaults.json`). `report.json` records the source and delivered measurements and whether linear or dynamic normalization ran.
- **Captions are timed to be read.** Each sentence splits into the fewest balanced cues, so no cue is a one-word tail; a cue too short to stand joins its neighbour; each cue stays up for the minimum and the reading time per word where the next cue allows. A cue still under the minimum fails the render; one read faster than the per-word time is a `FLAG:` line (`captions` in `scripts/defaults.json`).
- **Still spans are reported.** Every render lists each span with no change in picture (ffmpeg `freezedetect`) and, when narrated, the words spoken during it, as `STILL:` lines and `stills` in `report.json`. They never fail a render.
- The skill states the read-back frame cap and the summary line says how many animation ends the frame list covers.
