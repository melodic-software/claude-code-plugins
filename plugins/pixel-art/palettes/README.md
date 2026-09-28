# Palette presets

Bundled palettes for `render.py`. A spec may set `palette` to one of these names instead of an
inline object. A project palette file uses the same shape and is named by a path.

## Spec

```json
{"palette": "pico-8", "frames": {"icon": ["8."]}}
{"palette": "palettes/my-game.json", "frames": {"icon": ["k."]}}
{"palette": {"k": "#1a1c2c"}, "frames": {"icon": ["k."]}}
```

- A string with no slash and no `.json` suffix is a preset name (`pico-8`, `nes`, `game-boy`,
  `retro-8-bit`, `deep-sea`, `cosmic-space`). Unknown names fail and list the presets that exist.
- Any other string is a path, resolved relative to the spec file (or the working directory for
  `render.py --snap`). A project declares its palette by committing a file in the shape below.
  The conventional name is `pixel-art-palette.json` at the project root, unless the project's
  `CLAUDE.md` names a different path. The spec's `palette` string is that path.
- An inline object is unchanged.

## File shape

```json
{
  "name": "my-game",
  "source": "https://example.com/palette",
  "license": "CC0",
  "colors": [
    {"key": "k", "hex": "#1a1c2c"},
    {"hex": "#ffffff"}
  ]
}
```

`source` and `license` are notes. `colors` is required. A missing `key` is filled, in file order,
from this alphabet, skipping keys already used:

`0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ~!`

That is 64 characters, and `.` is never a key (it is transparency in frame rows). More colors than
remaining keys is an error. Preset files name every key explicitly so the characters stay stable.

`pico-8` keys `0`-`9` then `a`-`f` are the system indices. `nes` keys follow the alphabet in
hardware index order 0-63. `game-boy` keys `0`-`3` are lightest to darkest.

## Snap

```shell
python3 scripts/render.py --snap in.png --palette pico-8 --out snapped.png
python3 scripts/render.py --snap in.png --palette pico-8 --out frames.json --emit-frames
python3 scripts/render.py --snap in.png --palette '{"k":"#000000","w":"#ffffff"}' --out snapped.png --dither
```

- Distance: squared Euclidean in 8-bit sRGB channels, no gamma. Equal distances take the earlier
  palette color.
- Alpha below 128 (below 50% of 255) becomes transparent `(0, 0, 0, 0)`. Alpha 128 and above
  becomes opaque on the chosen color.
- `--dither` adds a 4x4 Bayer offset before the nearest-color pick:
  `((bayer + 0.5) / 16 - 0.5)` implemented in integers as `((index * 2 + 1) - 16) * 32 // 16`.
  Off by default. The index matrix is the standard ordered-dither matrix:

  ```
   0  8  2 10
  12  4 14  6
   3 11  1  9
  15  7 13  5
  ```

- Input PNG: 8-bit RGB (color type 2) or RGBA (color type 6), non-interlaced. Other bit depths,
  indexed color, interlacing, and `tRNS` fail with a message that names the limit.

## Bundled

| Name | What it is |
|---|---|
| `pico-8` | PICO-8 startup system colors 0-15 |
| `nes` | jsnes `loadNTSCPalette`, emphasis off, 64 hardware indices |
| `game-boy` | mGBA "DMG Green", four shades, lightest to darkest |
| `retro-8-bit` | Paleto, CC0, 16 colors |
| `deep-sea` | Paleto, CC0, 16 colors |
| `cosmic-space` | Paleto, CC0, 16 colors |

Each JSON file records its source URL and license note.

## Not bundled

License was not established, so these are not shipped:

- Lospec `endesga-32` and `sweetie-16`: the pages name an author and do not state a license.
  Lospec's terms do not grant one, and a comment on a different palette claiming every Lospec
  palette is public domain is not a license.
- FirebrandX "Smooth (FBX)": the author distributes NES palette files from firebrandx.com and does
  not grant a license on that page. The NES has no single official sRGB palette.

## Recorded decisions

Three-way check, 2026-09-28. Aseprite's CLI does not give this plugin a standard-library snap, and
the native backend must run with nothing else installed, so snapping lives in `render.py`.
`craft-static.md` says to lock a palette and points beginners at Lospec, which is why presets
exist and why only pages that state a license are copied in. Claude Code has no palette primitive;
the spec string is the contract the skills share.

- **Claim.** The 4x4 Bayer matrix above is the standard ordered-dither threshold matrix (index form, before dividing by 16).
- **Basis.** [Ordered dithering](https://en.wikipedia.org/wiki/Ordered_dithering), Bayer matrix section. Confirm the fetched page still shows this index arrangement on recheck.
- **As of.** 2026-09-28.
- **Recheck.** That page showing a different 4x4 index arrangement, or `reference/scene-canvas.md` switching its fade off the 4x4 Bayer matrix.

- **Claim.** PICO-8's startup system colors 0-15 are the hex values in `pico-8.json`. The official manual names the sixteen color indices and does not print those hex triples; the wiki table is the public record of them.
- **Basis.** [PICO-8 wiki, Palette](http://pico8wiki.com/index.php?title=Palette) section "0..15: Official base colors", and the [PICO-8 manual](https://www.lexaloffle.com/dl/docs/pico-8_manual.html) specifications line <!-- spellchecker:off -->"fixed 16 colour palette"<!-- spellchecker:on -->.
- **As of.** 2026-09-28.
- **Recheck.** The wiki table changing a hex value, or the manual printing an official RGB table that disagrees.

- **Claim.** mGBA's DMG Green preset is the 15-bit values `0x2691, 0x19A9, 0x1105, 0x04A3` in light-to-dark order, and `mColorFrom555` expands a 5-bit channel with `(channel * 0x21) >> 2`.
- **Basis.** [overrides.c](https://github.com/mgba-emu/mgba/blob/master/src/gb/overrides.c) preset "DMG Green", and [image.h](https://github.com/mgba-emu/mgba/blob/master/include/mgba-util/image.h) `M_R8` / `mColorFrom555`.
- **As of.** 2026-09-28.
- **Recheck.** Either file changing the DMG Green constants or the 5-to-8 expansion.

- **Claim.** jsnes `loadNTSCPalette` is the 64-entry table in `nes.json`, Apache-2.0, and it is an emulator table rather than a Nintendo sRGB specification.
- **Basis.** [palette-table.js](https://github.com/bfirsh/jsnes/blob/master/src/ppu/palette-table.js) and the [Apache-2.0 license](https://github.com/bfirsh/jsnes/blob/master/LICENSE).
- **As of.** 2026-09-28.
- **Recheck.** That function's `Uint32Array` changing, or the repository license changing.

- **Claim.** `retro-8-bit`, `deep-sea`, and `cosmic-space` are published by Paleto as CC0 on their Lospec pages. `endesga-32` and `sweetie-16` pages do not state a license.
- **Basis.** The Lospec pages linked from each bundled JSON, read 2026-09-28, plus [endesga-32](https://lospec.com/palette-list/endesga-32) and [sweetie-16](https://lospec.com/palette-list/sweetie-16).
- **As of.** 2026-09-28.
- **Recheck.** A bundled page dropping the CC0 statement, or a skipped page gaining a license statement.
