# Backends

Skills depend on one artifact contract, not on a tool. The native backend always works; every
other backend is an optional adapter behind a presence gate.

## Artifact contract (every backend honours it)

- In: a spec (`palette`, `frames`, `animations`, optional `sheet.columns` and `sheet.order`) as
  documented in the `scripts/render.py` docstring, or a procedural generator that emits one.
- Out, in one output directory: `sheet.png` (1x engine asset), `sheet.json` (frame rects,
  durations, tags; Aseprite-shaped, see `engine-layouts.md`), `preview.png` (nearest-neighbour
  upscale), and one looping `<animation>.gif` per animation.
- Palette: every output pixel is a spec palette colour or fully transparent. No partial alpha.
- Geometry: frame size and cell placement match the spec exactly; `null` cells stay blank.
- An adapter that cannot meet the contract reports why and falls back to native; it never ships a
  partial or differently shaped artifact.

## Selection rule

1. Default: native.
2. An adapter runs only when the user asked for it or configured it AND detection passes.
3. Detection fails: say so in one line ("Aseprite not found on PATH; rendered with the native
   backend"), render natively, continue. Never silent, never a hard stop.
4. Paid or remote adapters: state the cost basis and confirm before the first call in a session
   (judgment).

This follows the plugin rule for a prerequisite that serves an optional feature: warn visibly,
skip that feature, continue with the documented reduced result.

## Native (default)

- Adds: nothing to install. The model authors frame rows or a procedural Python generator that
  returns the spec; `scripts/render.py` (Python standard library only) writes the four outputs.
- Detect: `python3` on PATH.
- Cost and licence: none beyond the plugin's own.
- Contract: defines it.

## Aseprite CLI

- Adds: layers, slices, real Aseprite JSON (`from`/`to` tags, `layers`, `slices`, `properties`,
  `zIndex`), packed sheets, `.aseprite` source files a human can open and edit.
- Verified: `--sheet`, `--data`, `--sheet-type`, `--format json-hash|json-array`,
  `--split-layers|--split-tags|--split-slices`, `--tag`, `--filename-format`
  ([CLI docs](https://www.aseprite.org/docs/cli/); as-of 2026-09-23; recheck trigger: an Aseprite
  release past v1.3.18.6 whose notes touch CLI export).
- Unverified: `--batch` (headless run) and `--script <file.lua>` (Lua scripting to build a sprite
  from the spec) are unverified; see [CLI docs](https://www.aseprite.org/docs/cli/) and
  [scripting docs](https://www.aseprite.org/docs/scripting/) before use.
- Detect: `aseprite --version` succeeds (unverified flag; same URL).
- Cost and licence: paid, not open source under its own EULA (unverified; see
  [aseprite.org](https://www.aseprite.org/)). Do not quote a price.
- Contract: build the sprite from the spec (script or import of the native `sheet.png`), export
  with `--sheet sheet.png --data sheet.json --format json-hash`, then render `preview.png` and GIFs
  natively from the same spec. Document that its `sheet.json` is the real Aseprite shape.

## PixelLab (API / MCP)

- Adds: model-generated pixel art from text or a reference image, including rotations and
  animation frames (unverified; see [pixellab.ai](https://www.pixellab.ai/)).
- Detect: a PixelLab MCP server listed in the session's tools, or an API key the user configured.
  Endpoint names, MCP server name, and auth scheme: unverified (same URL).
- Cost and licence: paid tiers and output-licence terms unverified (same URL). Confirm before use.
- Contract: treat output as raw pixels. Run the image-model pipeline below, then render natively.

## Retro Diffusion (API / MCP)

- Adds: pixel-art image generation with palette and size controls (unverified; see
  [retrodiffusion.ai](https://www.retrodiffusion.ai/)).
- Detect: a Retro Diffusion MCP server in the session's tools, or a configured API key. Endpoints,
  MCP availability, and auth: unverified (same URL).
- Cost and licence: credit pricing and output licence unverified (same URL). Confirm before use.
- Contract: image-model pipeline below, then native render.

## General image models

- Adds: concept or reference images; rarely grid-true pixel art.
- Detect: an image-generation tool present in the session.
- Cost and licence: per the provider; state it or say it is unknown.
- Contract: image-model pipeline below is mandatory; raw output never ships as an asset.

## Image-model pipeline (all model-generated pixels)

1. Downscale to the target frame size with nearest-neighbour; estimate the source pixel scale
   first so one output pixel maps to one source cell (judgment).
2. Snap every pixel to the nearest locked-palette colour; alpha below 50% becomes transparent,
   the rest opaque (judgment).
3. Convert to spec `frames` rows (one character per palette key, `.` for transparent).
4. Clean up per `craft-static.md`: orphan pixels, jaggies, doubles, outer-edge AA.
5. Render with `scripts/render.py` so outputs match the native contract byte-for-byte in shape.

Cross-frame consistency (same silhouette, same palette use) is not guaranteed by any model; check
each animation's frames side by side before shipping (judgment).

## Audio

No adapter. Audio is optional input to HTML scenes (`scene-canvas.md`): a WAV file the user
supplies, or WebAudio synthesis in the scene. GIF, APNG and animated WebP carry no audio.
