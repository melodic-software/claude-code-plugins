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
