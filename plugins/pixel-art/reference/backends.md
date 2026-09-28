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

- Adds: a `.aseprite` file a person can open, and a `sheet.json` in Aseprite's own json-hash shape
  (`frameTags` use `from`/`to`; `layers` and `slices` are present when the export asks for them).
  `preview.png` and the GIFs still come from the native renderer.
- Adapter: `scripts/backends.py --backend aseprite`. It writes a Lua script and runs
  `aseprite --batch --script`, then `aseprite --batch <file.aseprite> --sheet --data --format json-hash --list-tags`.
- Detect: `ASEPRITE` if set, otherwise `aseprite` on `PATH`, and `aseprite --version` exits 0.
  Missing: one line, then native.
- The CLI page does not state a price. Do not quote one. A call does not spend a remote credit.
- Verification record: claim = `--batch` means do not start the UI, `--script` runs a Lua file,
  `--script-param` is read as `app.params`, `--version` prints the version, and the export flags
  above exist; the script uses `Sprite`, `Image:drawPixel`, `app.pixelColor.rgba`, `Sprite:newTag`,
  `Sprite:saveAs`, and `json.decode`. Basis =
  [CLI](https://www.aseprite.org/docs/cli/),
  [Sprite](https://www.aseprite.org/api/sprite),
  [Image:drawPixel](https://www.aseprite.org/api/image#imagedrawpixel),
  [app.pixelColor.rgba](https://www.aseprite.org/api/pixelcolor),
  [json.decode](https://www.aseprite.org/api/json). As-of 2026-09-28. Recheck trigger: an Aseprite
  release whose CLI or scripting docs rename one of those options or functions.

## PixelLab (API / MCP)

- Adds: a text-to-image call, then the image-model pipeline and a native render. The spec carries
  `generate.prompt`, `generate.width`, `generate.height`, and optional `generate.frames` (each with
  `name` and `prompt`).
- Adapter: `scripts/backends.py --backend pixellab`. The HTTP call is
  `POST https://api.pixellab.ai/v1/generate-image-pixflux` with `Authorization: Bearer`, body
  `description` and `image_size` `{width, height}`. The response image is `image.base64` (a PNG
  data URL) and `usage.usd` is the reported charge. Area must be at least 32x32 and at most 400x400.
- Detect: `PIXELLAB_API_TOKEN`. An MCP image (a session tool whose name contains `pixellab`) is not
  called again; pass that PNG to `backends.py --ingest`. The docs name a PixelLab MCP server and do
  not give a package name on the page fetched below.
- Confirm before the first call in a session (`--confirm` or `PIXEL_ART_BACKEND_CONFIRM=1`). Without
  it the adapter does not call the network. The API reference does not state an output license.
- Verification record: claim = the endpoint, bearer auth, body, response fields, and size limits in
  the previous bullets. Basis = [PixelLab API](https://api.pixellab.ai/v1/docs) (Generate image
  pixflux). As-of 2026-09-28. Recheck trigger: that page renaming `generate-image-pixflux`, the
  bearer scheme, or `usage.usd`.

## Retro Diffusion (API / MCP)

- Adds: a text-to-image call, then the same pipeline as PixelLab. The spec uses the same `generate`
  object. Default style sent by the adapter is `rd_plus__default`.
- Adapter: `scripts/backends.py --backend retrodiffusion`. It `POST`s
  `https://api.retrodiffusion.ai/v2/inferences` with header `X-RD-Token` and an `Idempotency-Key`,
  body `prompt`, `prompt_style`, `width`, `height`, `num_images`, then polls
  `GET /v2/inferences/tasks/{task_id}` until `status` is `succeeded`. Images are raw base64 PNG in
  `result.base64_images`. `result.balance_cost` is the USD charge.
- Detect: `RD_API_KEY` (keys start with `rdpk-`). MCP for agents is
  `https://mcp.retrodiffusion.ai/mcp` with `Authorization: Bearer`. An image that already came back
  from that server goes through `--ingest`, not a second paid call.
- Confirm before the first call, same switch as PixelLab. The API spends a prepaid USD balance.
  The marketing FAQ also describes a credit grant for new accounts and says generated art may be
  used commercially; those two pages use different units, so the adapter reports `balance_cost`
  and does not convert credits.
- Verification record: claim = the v2 URL, `X-RD-Token`, idempotency header, task poll, and
  `base64_images` / `balance_cost` fields; MCP URL as named. Basis =
  [api-examples README](https://github.com/Retro-Diffusion/api-examples/blob/main/README.md).
  As-of 2026-09-28. Recheck trigger: that README changing the default base URL away from
  `/v2` or renaming `X-RD-Token`. The FAQ credit sentence is a separate claim: basis =
  [retrodiffusion.ai](https://www.retrodiffusion.ai/); recheck trigger: that page no longer stating
  a free credit grant or commercial use.

## General image models

- Adds: concept or reference images; rarely grid-true pixel art.
- Detect: an image-generation tool present in the session.
- Cost and license: per the provider; state it or say it is unknown.
- Contract: image-model pipeline below is mandatory; raw output never ships as an asset.

## Image-model pipeline (all model-generated pixels)

1. Downscale to the target frame size with nearest-neighbor. When the source size is an integer
   multiple of the target, sample the center of each source cell (`scripts/image_pipeline.py`).
   Otherwise sample the nearest source pixel.
2. Snap with `scripts/render.py --snap <image.png> --palette <preset, file, or inline JSON> --out <snapped.png>`
   (add `--emit-frames` to write spec rows, `--dither` for 4x4 Bayer). Nearest color is squared
   Euclidean distance in 8-bit sRGB; alpha below 128 becomes transparent and the rest opaque.
   `backends.py` does this snap itself for PixelLab, Retro Diffusion, and `--ingest`.
   See `palettes/README.md`.
3. Use the emitted frame rows (one character per palette key, `.` for transparent), or the snapped PNG.
4. Clean up per `craft-static.md`: orphan pixels, jaggies, doubles, outer-edge AA.
5. Render with `scripts/render.py` so outputs match the native contract byte-for-byte in shape.

Cross-frame consistency (same silhouette, same palette use) is not guaranteed by any model; check
each animation's frames side by side before shipping (judgment).

## Audio

No adapter. Audio is optional input to HTML scenes (`scene-canvas.md`): a WAV file the user
supplies, or WebAudio synthesis in the scene. GIF, APNG and animated WebP carry no audio.
