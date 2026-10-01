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
  It then rewrites `sheet.json` to the contract: `frames` keys become the spec frame names (mapped
  by position over the sheet cells, `null` cells dropped) and `meta.image` becomes `sheet.png`;
  `frameTags`, `layers` and `slices` stay as Aseprite wrote them. A frame count that differs from
  the sheet cell count, or an unreadable `sheet.json`, falls back to native with one line.
- Status: best-effort and unverified against a real Aseprite install. Any failure (a non-zero exit,
  missing or unreadable output, a frame-count mismatch) falls back to native with one line.
- Detect: `ASEPRITE` if set, otherwise `aseprite` on `PATH`, and `aseprite --version` exits 0.
  Missing: one line, then native.
- The CLI page does not state a price. Do not quote one. A call does not spend a remote credit.
- License: a paid download under the Aseprite EULA, which replaced GPLv2 in August 2016 and
  forbids redistributing compiled builds; source can still be compiled for personal use, and art
  made with it can be sold. Do not copy the FAQ's pledge amount into a reply.
- Verification record: claim = that license shape. Basis =
  [Aseprite FAQ, Licensing & Commercial](https://www.aseprite.org/faq/). As-of 2026-09-28.
  Recheck trigger: that section no longer saying the EULA replaced the GPL.
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
- Verification record: claim = the CLI documents `--filename-format` with a `{frame}` token, emits
  empty frames unless `--ignore-empty` is given, and does not state the default `json-hash` key
  format or the value of `meta.image`; the adapter therefore maps frames by position and sets
  `meta.image` itself. Basis = [CLI](https://www.aseprite.org/docs/cli/). As-of 2026-09-29. Recheck
  trigger: that page documenting the default key format or `meta.image`.

## General image models

- Adds: concept or reference images; rarely grid-true pixel art.
- Detect: an image-generation tool present in the session. Pass an image it already returned to
  `scripts/backends.py --ingest`.
- License: per the provider; state it or say it is unknown.
- Contract: image-model pipeline below is mandatory; raw output never ships as an asset.

## Image-model pipeline (all model-generated pixels)

1. Downscale to the target frame size with nearest-neighbor. When the source size is an integer
   multiple of the target, sample the center of each source cell (`scripts/image_pipeline.py`).
   Otherwise sample the nearest source pixel.
2. Snap with `scripts/render.py --snap <image.png> --palette <preset, file, or inline JSON> --out <snapped.png>`
   (add `--emit-frames` to write spec rows, `--dither` for 4x4 Bayer). Nearest color is squared
   Euclidean distance in 8-bit sRGB; alpha below 128 becomes transparent and the rest opaque.
   `backends.py` does this snap itself for `--ingest`.
   See `palettes/README.md`.
3. Use the emitted frame rows (one character per palette key, `.` for transparent), or the snapped PNG.
4. Clean up per `craft-static.md`: orphan pixels, jaggies, doubles, outer-edge AA.
5. Render with `scripts/render.py` so outputs match the native contract byte-for-byte in shape.

Cross-frame consistency (same silhouette, same palette use) is not guaranteed by any model; check
each animation's frames side by side before shipping (judgment).

## Audio

No adapter. Audio is optional input to HTML scenes (`scene-canvas.md`): a WAV file the user
supplies, or WebAudio synthesis in the scene. GIF, APNG and animated WebP carry no audio.
