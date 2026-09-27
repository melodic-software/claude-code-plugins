# Engine layouts

Exact sheet shapes per target and how to express each with the renderer spec in
`scripts/render.py`. Re-fetch the cited basis before relying on a number for a shipped asset.

## Renderer mapping rules

- `sheet.columns` = cells per row; `sheet.order` = frame names in row-major order; `null` = blank
  cell. Rows = ceil(len(order) / columns). Output `sheet.png` is 1x.
- Every frame in one spec has the same width and height (`validate()` rejects mixed sizes), so one
  spec per engine sheet: faces (144) and characters (48) never share a spec.
- Loop playback: the renderer copies `direction` into `sheet.json` but the GIF plays `frames`
  exactly as listed. For a 0-1-2-1 loop, list `[f0, f1, f2, f1]` with `direction: forward` so the
  GIF and JSON agree; one-shot 1-2-3 is `[f0, f1, f2]`, `forward`.
- `sheet.json` is Aseprite-shaped, not Aseprite-exact: a json-hash `frames` map (`frame`, `rotated`,
  `trimmed`, `spriteSourceSize`, `sourceSize`, `duration`) plus `meta.frameTags`, but each tag
  carries `frames` (names) and `durations_ms` instead of Aseprite's `from`/`to`, and there are no
  `layers`, `slices`, `properties`, or `zIndex`. A consumer expecting real Aseprite JSON needs the
  Aseprite adapter (see `backends.md`).
- GIF previews: GIF delay is in 1/100 s; the renderer rounds `ms / 10` with a floor of 2.

## RPG Maker MZ (v1.10.0)

Verification record: claim = every MZ number in this section; basis =
[MZ help, asset standards](https://rpgmakerofficial.com/product/MZ_help-en/01_11_01.html),
[MZ help, side-view battlers](https://rpgmakerofficial.com/product/MZ_help-en/01_11_02.html), and
the v1.10.0 core scripts (`rmmz_core.js`, `rmmz_sprites.js`, `rmmz_objects.js`,
`rmmz_managers.js`, read from a
[third-party mirror](https://github.com/je-can-code/rmmz-plugins/tree/HEAD/project/js)); as-of
2026-09-23; recheck trigger: an MZ update past v1.10.0 in the
[Steam announcements](https://store.steampowered.com/news/app/1096900), or `Utils.RPGMAKER_VERSION`
in a stock project reading higher. Sizes marked "derived" are computed from stated ratios, not
stated by the source.

### Characters (`img/characters`)

- Frame normally 48x48; 3 patterns x 4 directions; row order down, left, right, up.
- Standard file: 8 characters in 4 columns x 2 rows; frame = width/12, height/8; 576x384 at 48px
  (derived).
- `$name`: one character per file; frame = width/3, height/4.
- `!name`: no 6px upshift, no bush transparency (doors, chests, objects).
- Walk plays patterns 0-1-2-1; each pattern holds (9 - moveSpeed) x 3 game frames at 60 fps
  (15 at default speed 4).
- `$` spec: `columns: 3`, order `down0,down1,down2, left0..2, right0..2, up0..2`, frames 48x48;
  walk animation per direction = `[down0, down1, down2, down1]`, 250 ms each (15 frames at 60 fps).
- 8-character spec: `columns: 12`, 8 rows. Row-major: for block row 0..1, for direction row
  down/left/right/up, for block column 0..3, patterns 0..2 (character = block row x 4 + block
  column). Unused characters are 12 `null` cells.

### Faces (`img/faces`)

- 144x144 each, 4 x 2 = 8 per file, 576x288. Since v1.9.0 face and icon sizes are selectable
  (defaults 144 and 32). Spec: `columns: 4`, frames 144x144.

### Tilesets (`img/tilesets`, 48px tiles; tile size configurable via `$dataSystem.tileSize`)

| Sheet | Size | Content | Spec |
|---|---|---|---|
| A1 | 768x576 | animated water (3 frames, played 0-1-2-1), waterfalls | block layout: see the help page; not restated here |
| A2 | 768x576 | ground autotiles, 2x3-tile blocks, 8 per row | `columns: 8`, frames 96x144 (one block each) |
| A3 | 768x384 | buildings, 8 x 4 blocks of 2x2 | `columns: 8`, frames 96x96 |
| A4 | 768x720 | walls, 8 x 3 (top 2x3 + side 2x2) | author as 48x48 tiles, `columns: 16` |
| A5 | 384x768 | 8 x 16 normal tiles | `columns: 8`, frames 48x48 |
| B-E | 768x768 | 16 x 16 upper-layer tiles; B top-left must be blank | `columns: 16`, B order starts with `null` |

- Autotiles are assembled from 24x24 quarter-tiles: floor autotiles 48 shapes from a 2x3 block,
  walls 16 shapes from 2x2, waterfalls 4. See `craft-tiles.md` for drawing the block.

### Side-view battlers (`img/sv_actors`)

- 9 x 6 = 54 frames; 576x384 standard; frames 64x64 (derived: 576/9, 384/6).
- 18 motions of 3 frames. Motion index = row + 6 x column group (column group = 3 cells).
- Motion list: 0 walk, 1 wait, 2 chant, 3 guard, 4 damage, 5 evade, 6 thrust, 7 swing, 8 missile,
  9 skill, 10 spell, 11 item, 12 escape, 13 victory, 14 dying, 15 abnormal, 16 sleep, 17 dead.
- Looping (plays 1-2-3-2): walk, wait, chant, guard, escape, victory, dying, abnormal,
  sleep, dead. The rest play once. 12 game frames per pattern (200 ms at 60 fps).
- Spec: `columns: 9`, row-major order:
  row 0 walk, thrust, escape; row 1 wait, swing, victory; row 2 chant, missile, dying;
  row 3 guard, skill, abnormal; row 4 damage, spell, sleep; row 5 evade, item, dead
  (each name expands to `name0,name1,name2`).
- `img/enemies`, `img/sv_enemies`: single image, any size; even widths recommended.

### System images (`img/system`)

| File | Layout | Spec |
|---|---|---|
| `IconSet.png` | 32x32 icons, 16 per row; icon n at column n % 16, row floor(n / 16) | `columns: 16`, 32x32 |
| `Window.png` | 192x192 skin: background 0,0 (95x95, stretched); pattern 0,96 (96x96, tiled); frame 96,0 (96x96, 24px corners, 9-slice); cursor 96,96 (48x48); arrows near 120,24; pause sign 144,96 (24x24); 32 text colors in 12px cells from 96,144 | one 192x192 frame; place regions by hand |
| `Balloon.png` | 48x48 frames, 8 per row, one row per balloon | `columns: 8`, 48x48 |
| `States.png` | 96x96 frames, one row per state overlay | 96x96 frames |
| `Weapons1-3.png` | 96x64 cells, 12 weapon types per sheet, 3 frames each | 96x64 frames |

- Name the balloon file `Balloon.png`: the core loads `Balloon` (the help page misspells the name).

### Other folders

- Animations: MZ's native format is Effekseer (`effects/*.efkefc`, not a pixel sheet).
  MV-style sheet animations load from `img/animations`: 192x192 cells, 5 per row (`columns: 5`).
- `img/titles1`, `img/titles2`: 816x624 (background, frame overlay).
- `img/battlebacks1`, `img/battlebacks2`: 1000x740 (floor layer, wall layer).
- `img/parallaxes`: any size, edges loop; `!` prefix = drawn as floor, no parallax.
- `img/pictures`: any size, even widths recommended; up to 500 pictures since v1.9.0.

## RPG Maker U2U

Unity-based, P2D (2.5D) maps; reuses MV/MZ assets; 4-direction character sprites auto-mapped to
diagonals; no project or plugin conversion. Target MZ layouts for U2U. Verification record: claim =
announced, release date "Coming soon"; basis =
[Steam store page](https://store.steampowered.com/app/4856440/RPG_MAKER_U2U/); as-of 2026-09-23;
recheck trigger: the store page showing a release date or U2U publishing its own asset standards.

## Aseprite

- Tags name frame ranges; directions `forward`, `reverse`, `pingpong`, `pingpong_reverse` (the
  docs list three; the source has four), optional `repeat`. Layers (with groups) separate parts;
  slices name regions with optional 9-slice `center` and `pivot`. Frame duration default 100 ms,
  range 1..65535.
- CLI export: `--sheet out.png --data out.json`, `--sheet-type horizontal|vertical|rows|columns|packed`,
  `--format json-hash|json-array`, `--split-layers|--split-tags|--split-slices`, `--tag`,
  `--filename-format` tokens `{title} {layer} {tag} {frame} {tagframe} {duration}`.
- JSON: `frames` with `frame{x,y,w,h}`, `rotated`, `trimmed`, `spriteSourceSize`, `sourceSize`,
  `duration`; `meta` with `app`, `version`, `image`, `format`, `size`, `scale`,
  `frameTags[{name,from,to,direction,repeat}]`, `layers`, `slices`, plus `properties` and `zIndex`.
- Verification record: claim = the three bullets above; basis = [Aseprite CLI docs](https://www.aseprite.org/docs/cli/),
  [tags docs](https://www.aseprite.org/docs/tags/), and source files
  [`doc_exporter.cpp`](https://github.com/aseprite/aseprite/blob/main/src/app/doc_exporter.cpp) and
  [`anidir.h`](https://github.com/aseprite/aseprite/blob/main/src/doc/anidir.h) at v1.3.18.6; as-of
  2026-09-23; recheck trigger: an Aseprite release past v1.3.18.6 whose notes touch sheet export,
  JSON data, or tags.

## Godot 4.7

- `AnimatedSprite2D` plays a `SpriteFrames` resource: named animations, each with fps (default 5.0),
  loop mode (none, linear, pingpong), and frames with relative durations (default 1.0; absolute =
  relative / (fps x |speed|)). The editor slices a sheet by horizontal and vertical counts, so
  `sheet.columns` = horizontal count, rows = vertical count.
- `TileSet`: `TileSetAtlasSource` over a texture with region size, margins, separation. Terrain
  modes: Match Corners and Sides, Match Corners, Match Sides (the exact pairing with Godot 3's 2x2,
  3x3, 3x3-minimal bitmasks is unverified). Animated tiles carry per-frame durations.
- Pixel fonts: BMFont `.fnt` or an Image Font on a glyph grid; Nearest filter, integer size.
- Verification record: basis = [SpriteFrames](https://docs.godotengine.org/en/stable/classes/class_spriteframes.html),
  [Using TileSets](https://docs.godotengine.org/en/stable/tutorials/2d/using_tilesets.html),
  [Using fonts](https://docs.godotengine.org/en/stable/tutorials/ui/gui_using_fonts.html) at 4.7.2;
  as-of 2026-09-23; recheck trigger: a Godot 4.8 (or later) release whose notes touch SpriteFrames,
  TileSet, or font import.

## PICO-8

- 128x128 screen, fixed 16-color palette, 8x8 sprites on one 128x128 sheet (256 sprites; 128-255
  share memory with the lower map half), 8 flags per sprite.
- Spec: `columns: 16`, frames 8x8, palette = the 16 PICO-8 colors only. The renderer writes PNG,
  not a cart; importing into a cart is outside this reference.
- Verification record: basis = [PICO-8 manual](https://www.lexaloffle.com/dl/docs/pico-8_manual.html)
  (states v0.2.7); as-of 2026-09-23; recheck trigger: the manual's version line moving past 0.2.7.

## Pyxel

- Customizable screen, 16-color palette (extensible), 3 image banks of 256x256, 8 tilemaps of
  256x256. Images load from palette-ready PNG/GIF/JPEG or `Image.set` string lists.
- Spec: any frame size whose sheet fits 256x256 per bank; keep the palette to the target's colors.
- Verification record: basis = [Pyxel user guide](https://github.com/kitao/pyxel/blob/main/docs/user-guide.md)
  at v2.9.9; as-of 2026-09-23; recheck trigger: a Pyxel release past 2.9.9 on
  [releases](https://github.com/kitao/pyxel/releases).

## Unity

Unverified; see [Unity Manual](https://docs.unity3d.com/Manual/index.html). Emit a uniform
grid so cell-size slicing can consume it (judgment).
