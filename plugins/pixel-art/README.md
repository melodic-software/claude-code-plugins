# pixel-art

A Claude Code plugin for making pixel art with nothing installed beyond Python 3: sprites,
animation cycles laid out for game engines, tilesets, UI skins, effect sheets, and animated scenes
that open in any browser.

| Skill | What it does |
|---|---|
| `/pixel-art:sprite` | A static sprite (character, item, icon, portrait, face) as a PNG sheet |
| `/pixel-art:animate` | Idle, walk, attack and other cycles in 1, 4 or 8 directions, as an engine sprite sheet plus GIF previews |
| `/pixel-art:tileset` | Terrain, autotiles, and parallax layers as the target engine's tileset sheet |
| `/pixel-art:ui` | Window skins, icon sets, HUD elements, and bitmap fonts |
| `/pixel-art:vfx` | Hit sparks, spells, and explosions as a cell sheet (MV-style animations for RPG Maker) |
| `/pixel-art:scene` | A cutscene, title screen, ambient loop or short pixel film as one self-contained HTML file |

```shell
/pixel-art:sprite a 32x32 potion icon, PICO-8 palette
/pixel-art:animate a knight, walk and attack, 4 directions, RPG Maker MZ
/pixel-art:tileset an RPG Maker MZ A2 grass autotile
/pixel-art:ui an MZ window skin
/pixel-art:vfx a hit spark for MZ animations
/pixel-art:scene the knight walks to a campfire at dusk and says one line, 240x160
```

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install pixel-art@melodic-software
```

## How it works

1. The model records a `brief.md` beside the spec (subject, style references, proportions, palette,
   and the done criteria), then turns the request into a spec: a locked palette and frames, written
   by hand for small sprites or by a short procedural generator for larger ones. Tilesets, UI skins,
   and effect sheets use that same spec. A later round reads that brief instead of asking again. The
   palette may be an inline object, a bundled preset (`pico-8`, `nes`, `game-boy`, or a CC0 Lospec
   set in `palettes/`), or a project palette file. The sheet shape comes from
   `reference/engine-layouts.md`.
2. `scripts/backends.py` selects the backend and `scripts/render.py` (Python standard library only)
   writes the engine asset at 1x, an upscaled preview, a GIF per animation, and frame data.
   `scripts/embed.py` builds scenes into one HTML file. `scripts/capture.py` serves that file and,
   when a browser is present, saves timeline shots and an optional WebM.
3. The model looks at what it rendered and revises, usually two to four rounds. Each round marks
   the brief's done criteria pass or fail. The loop stops when they all pass, or when the round
   budget is spent and the failures are named.
4. `scripts/gallery.py` writes an `index.html` showing every output on one page.

## Settings

| Setting | Default | Purpose |
|---|---|---|
| `output_dir` | unset (ask) | Where outputs go when the request and the project name no location |
| `backend` | `native` | `native` or `aseprite` |

A project can name its own assets folder in its `CLAUDE.md`; that wins over `output_dir`.

## Prerequisites

- **Python 3**: required. The renderer uses the standard library only.
- **A local browser** (Chrome or Chromium on `PATH`): optional. `scripts/capture.py` drives it
  for the scene review loop. Without one, the command exits 3 and the skill says the scene was
  not reviewed visually.
- **Aseprite**: optional. `scripts/backends.py` runs it when `aseprite --version` works and
  otherwise falls back to `native` with one line. Details are in `reference/backends.md`. The
  adapter is best-effort and unverified against a real Aseprite install; a failed run, missing output or
  a `sheet.json` without frames or meta falls back to native.

Native `sheet.json` follows the shape of Aseprite's json-hash export but is not identical: animation
tags list frame names and per-frame durations rather than `from`/`to` ranges. The Aseprite backend
writes Aseprite's own json-hash file instead (frames keyed by spec name, `meta.image` set to
`sheet.png`), and still writes the native GIFs and preview.

## Audio

This plugin does not synthesize sound. `embed.py` inlines a WAV you place next to the template
(`/*WAV:file.wav*/null`), and the scene plays it on the first click. `examples/campfire/campfire.wav`
is that file for the example. It was rendered from the score in `examples/campfire/AUDIO.txt`.
The renderer that produced it lives in the `retro-audio` plugin and is not imported here. The
`--record` WebM for the example carries the WAV as its audio track when `ffmpeg` is present and is
video only otherwise.

## Example

`scripts/kit.py` is the procedural character kit: proportion presets (`chibi`, `standard`, `tall`),
head and hair shapes, clothing layers, material ramps, top-left shading, a selective outline, and
4-direction handling. Adapt it; do not treat it as a fixed generator. `examples/walker/blacksmith.py`
is a 4-direction walker built on it. `examples/campfire/` holds an earlier hand-written RPG Maker MZ
walker and a cutscene that reuses it. `examples/tileset/a2_ground.py`, `examples/ui/window_mz.py`,
and `examples/vfx/spark_mz.py` each write a spec for an engine sheet. Copy a folder somewhere
writable, then run it there. For `walker/`, put `scripts/kit.py` beside `blacksmith.py`:

```shell
python3 blacksmith.py
python3 <plugin>/scripts/render.py blacksmith.json --out out --scale 4
```

For `campfire/`:

```shell
python3 hero_mz.py
python3 <plugin>/scripts/render.py hero_mz.json --out out --scale 4
python3 <plugin>/scripts/embed.py scene.html out/campfire.html
python3 <plugin>/scripts/gallery.py out
python3 <plugin>/scripts/capture.py out/campfire.html --at 0,3,7 --record 4 --out out/capture
```

## Reference files

`reference/` holds the sourced rules the skills apply: `craft-static.md`, `craft-animation.md`,
`craft-tiles.md`, `engine-layouts.md`, `scene-canvas.md`, and `backends.md`. `palettes/` holds
the bundled preset files and the notes for a project palette file.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `output_dir` | directory | *(none)* | Where rendered sprites, sheets and scenes go when neither the request nor the project names a location. Leave unset to be asked. |
| `backend` | string | `"native"` | Rendering backend. native (default) needs no external tools; aseprite renders through the Aseprite CLI. A named backend that is not present falls back to native with a notice. |

### How to set these

Set the options above for `pixel-art@<marketplace>`, replacing `<marketplace>` with the
marketplace you installed this plugin from:

- **In a session or headless:** [`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session) or
  [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure). The configure command is the preferred
  headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its limits.
- **By hand:** under [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs) in your **user** settings.

Do **not** uninstall the plugin to reconfigure it: see [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).
For a Claude Code release without `plugin configure`, see [Plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install).

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install)
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills)
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect)
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins)

<!-- END GENERATED: plugin options -->
