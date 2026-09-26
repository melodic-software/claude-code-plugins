# Changelog

All notable changes to the `animation` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0]

### Added

- `rotoscope` skill: extract (distinct-drawing decode, supersampled tracing with tone layers, a
  raw frame border after the unsharp mask, warm-paper tint layers), render through ink.js, measure
  per drawing, bias fitting from the XOR balance, a review table with 1:1 crops, a tool-neutral
  override file, a learnings log with a retro step, and the shfred0 regression (239/239).
- Shared `ink.js` brush engine, `render.html` scene page and `capture.mjs` frame capture.
- `learn-style` skill: `learn.py` measures a rotoscope work directory into a style pack (palette,
  tone ramp, seven style knobs, statistic percentiles, bands set by held-out validation over the
  source's segments and capped by negative controls, checked statistics), keeping hand-written
  credit, brush defaults and judgment knobs across re-runs; a reference on which statistics
  separate styles, measured over nine films.
- Shared `inkstats.py`: style statistics of any film (video, frame folder or rotoscope work dir),
  per shot (`--cuts`) or per box (`--region`, `--t`), including flat-black share and dark-field
  texture, and a `--pack` check that takes the pack directory, checks each shot's largest dark
  field, prints a distance to source, and exits 1 on any failing row.
- `woodcut-ink` style pack, a study of @shfred0's clip: statistics only, with brush starting values
  not yet validated against its current check.
- `review.py` exits 1 when any drawing is flagged, and stops with a message when no replica is
  rendered.
- `scripts/render.py`: the one entry point for every render and encode (exit 0, 1 on a failed
  scene, 2 on a missing prerequisite), writing `render.json`; `reference/backends.md` records the
  native backend, the selection rule and the license rule for any other backend.
- `scripts/decode.py`: the one decode path for a video, frame folder or work dir, the repeat rule
  and the gray modes; it exits with a message when ffmpeg stops early or fails.
- `/animation:setup`: a check-only prerequisite table (`scripts/prereq.py`: ffmpeg with libx264 and
  `-fps_mode`, ffprobe, Node, playwright-core with Chromium, numpy and opencv); `requirements.txt`
  pins numpy and opencv; the `playwright_core` option reaches every render, including `measure.py`
  and `fit.py`.
- `regress.py --synthetic`: a committed fixture scene that checks the render, encode and decode
  contracts without unshipped input, wrapped by `test_regress.py`.
- `learn.py --base-fps` sets the rate holds are counted on; `extract.py` scales its repeat and
  tint pixel counts by frame area.
