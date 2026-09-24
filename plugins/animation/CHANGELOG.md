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
