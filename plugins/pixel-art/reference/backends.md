# Backends

Skills depend on one artifact contract, not on a tool. The native backend always works; every
other backend is an optional adapter behind a presence gate.

## Artifact contract (every backend honors it)

- In: a spec (`palette`, `frames`, `animations`, optional `sheet.columns` and `sheet.order`) as
  documented in the `scripts/render.py` docstring, or a procedural generator that emits one.
- Out, in one output directory: `sheet.png` (1x engine asset), `sheet.json` (frame rects,
  durations, tags; Aseprite-shaped, see `engine-layouts.md`), `preview.png` (nearest-neighbor
  upscale), and one looping `<animation>.gif` per animation.
- Palette: every output pixel is a spec palette color or fully transparent. No partial alpha.
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
- Cost and license: none beyond the plugin's own.
- Contract: defines it.

## Aseprite CLI

- Adds: layers, slices, real Aseprite JSON (`from`/`to` tags, `layers`, `slices`, `properties`,
  `zIndex`), packed sheets, `.aseprite` source files a human can open and edit.
- Verified: `--batch` (`-b`, do not start the UI), `--script <filename>` (run a Lua script),
  `--version` (print the version and exit), `--sheet`, `--data`, `--sheet-type`,
  `--format json-hash|json-array`, `--split-layers|--split-tags|--split-slices`, `--tag`,
  `--filename-format`. Claim: those flags. Basis:
  [CLI docs](https://www.aseprite.org/docs/cli/). As of 2026-09-28. Recheck when that page drops
  one of them.
- Detect: `aseprite --version` succeeds (same record).
- Cost and license: paid download under the Aseprite EULA, which replaced GPLv2 in August 2016 and
  forbids redistributing compiled builds; source can still be compiled for personal use, and art
  made with it can be sold. Claim: that license shape. Basis:
  [Aseprite FAQ, Licensing & Commercial](https://www.aseprite.org/faq/). As of 2026-09-28.
  Recheck when that section stops saying the EULA replaced the GPL. Do not copy the FAQ's pledge
  amount into a reply.
- Contract: build the sprite from the spec (script or import of the native `sheet.png`), export
  with `--sheet sheet.png --data sheet.json --format json-hash`, then render `preview.png` and GIFs
  natively from the same spec. Document that its `sheet.json` is the real Aseprite shape.

## PixelLab (API / MCP)

- Adds: nothing this file states. Rotations, animation frames, endpoint names, the MCP server
  name, auth, prices, and the output license are not claimed here (judgment). Open the vendor page
  the user names and confirm each of those before any call.
- Detect: only a server or key the user has already configured. Do not invent an endpoint.
- Contract: treat whatever comes back as raw pixels. Run the image-model pipeline below, then
  render natively.

## Retro Diffusion (API / MCP)

- Adds: nothing this file states. Palette controls, size controls, endpoints, MCP availability,
  auth, credit prices, and the output license are not claimed here (judgment). Open the vendor
  page the user names and confirm each of those before any call.
- Detect: only a server or key the user has already configured. Do not invent an endpoint.
- Contract: image-model pipeline below, then native render.

## General image models

- Adds: concept or reference images; rarely grid-true pixel art.
- Detect: an image-generation tool present in the session.
- Cost and license: per the provider; state it or say it is unknown.
- Contract: image-model pipeline below is mandatory; raw output never ships as an asset.

## Image-model pipeline (all model-generated pixels)

1. Downscale to the target frame size with nearest-neighbor; estimate the source pixel scale
   first so one output pixel maps to one source cell (judgment).
2. Snap with `scripts/render.py --snap <image.png> --palette <preset, file, or inline JSON> --out <snapped.png>`
   (add `--emit-frames` to write spec rows, `--dither` for 4x4 Bayer). Nearest color is squared
   Euclidean distance in 8-bit sRGB; alpha below 128 becomes transparent and the rest opaque.
   See `palettes/README.md`.
3. Use the emitted frame rows (one character per palette key, `.` for transparent), or the snapped PNG.
4. Clean up per `craft-static.md`: orphan pixels, jaggies, doubles, outer-edge AA.
5. Render with `scripts/render.py` so outputs match the native contract byte-for-byte in shape.

Cross-frame consistency (same silhouette, same palette use) is not guaranteed by any model; check
each animation's frames side by side before shipping (judgment).

## Audio

No adapter. Audio is optional input to HTML scenes (`scene-canvas.md`): a WAV file the user
supplies, or WebAudio synthesis in the scene. GIF, APNG and animated WebP carry no audio.
