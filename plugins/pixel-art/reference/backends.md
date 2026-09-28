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
- Verified: `--sheet`, `--data`, `--sheet-type`, `--format json-hash|json-array`,
  `--split-layers|--split-tags|--split-slices`, `--tag`, `--filename-format`
  ([CLI docs](https://www.aseprite.org/docs/cli/); as-of 2026-09-23; recheck trigger: an Aseprite
  release past v1.3.18.6 whose notes touch CLI export).
- `--batch` does not start the UI. `--script <filename>` runs that Lua file. `--script-param
  name=value` is `app.params` inside the script. `--version` prints the version and exits.
  Basis: [CLI docs](https://www.aseprite.org/docs/cli/). As-of 2026-09-28. Recheck trigger: an
  Aseprite release whose CLI page drops one of those options.
- A script that builds a sprite from a spec can use `Sprite`, `Image:drawPixel`,
  `app.pixelColor.rgba`, `Sprite:newTag`, `Sprite:saveAs`, and `json.decode`. Basis:
  [Sprite](https://www.aseprite.org/api/sprite),
  [Image:drawPixel](https://www.aseprite.org/api/image#imagedrawpixel),
  [pixelColor](https://www.aseprite.org/api/pixelcolor),
  [json](https://www.aseprite.org/api/json). As-of 2026-09-28. Recheck trigger: one of those
  pages renaming a function named here.
- Detect: `aseprite --version` exits 0 (same CLI page).
- Cost and license: the CLI page does not state a price. Do not quote one. The
  [EULA](https://github.com/aseprite/aseprite/blob/main/EULA.txt) licenses the program and
  forbids distributing copies of it; it is not an OSI license grant. As-of 2026-09-28.
  Recheck trigger: that EULA gaining a price or an open-source grant.
- Contract: build the sprite from the spec (script or import of the native `sheet.png`), export
  with `--sheet sheet.png --data sheet.json --format json-hash`, then render `preview.png` and GIFs
  natively from the same spec. Document that its `sheet.json` is the real Aseprite shape.

## PixelLab (API / MCP)

- Adds: a text-to-image call. Rotations and animation are separate endpoints on the same API.
- Call: `POST https://api.pixellab.ai/v1/generate-image-pixflux` with `Authorization: Bearer` and
  a body of `description` plus `image_size` `{width, height}`. The image comes back as
  `image.base64` (a PNG data URL). `usage.usd` is the reported charge. The v1 docs put the area
  bounds on that call; do not send a canvas outside them.
- Detect: `PIXELLAB_API_TOKEN` (the docs call it the API token). The v1 docs page fetched for
  this record does not name an MCP package. If the session already has a PixelLab image, snap
  that file; do not call the API again.
- Cost and license: each successful call reports `usage.usd`. The API reference does not state
  an output license. Confirm before the first call in a session. Do not quote a price table.
- Verification record: claim = the endpoint, bearer scheme, body, `image.base64`, and `usage.usd`.
  Basis: [PixelLab API v1](https://api.pixellab.ai/v1/docs), Generate image (pixflux). As-of
  2026-09-28. Recheck trigger: that page renaming `generate-image-pixflux`, the bearer scheme, or
  `usage.usd`.
- Contract: treat output as raw pixels. Run the image-model pipeline below, then render natively.

## Retro Diffusion (API / MCP)

- Adds: text-to-image (and, on other styles, animation and tilesets) through the HTTP API.
- Call: `POST https://api.retrodiffusion.ai/v2/inferences` with header `X-RD-Token` and an
  `Idempotency-Key`. Body fields used here: `prompt`, `prompt_style`, `width`, `height`,
  `num_images`. The POST returns `task_id`. Poll `GET /v2/inferences/tasks/{task_id}` until
  `status` is `succeeded`. Images are raw base64 PNG in `result.base64_images`.
  `result.balance_cost` is the USD charge. The quick-start style id is `rd_plus__default`.
- Detect: `RD_API_KEY` (keys on that page start with `rdpk-`). Agent MCP is
  `https://mcp.retrodiffusion.ai/mcp` with `Authorization: Bearer` and the same key. An image
  that already came back from that server is snapped; it is not generated again.
- Cost and license: the call spends prepaid USD balance and the task reports `balance_cost`.
  Confirm before the first call in a session. Do not invent a credit-to-USD rate.
- Verification record: claim = the v2 URL, `X-RD-Token`, the idempotency header, the task poll,
  `base64_images`, `balance_cost`, and the MCP URL. Basis:
  [api-examples README](https://github.com/Retro-Diffusion/api-examples/blob/main/README.md).
  As-of 2026-09-28. Recheck trigger: that README moving the default base URL off `/v2` or
  renaming `X-RD-Token`.
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
