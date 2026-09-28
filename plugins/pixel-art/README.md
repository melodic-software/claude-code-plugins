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

## How it works

1. The model records a `brief.md` beside the spec (subject, style references, proportions, palette,
   and the done criteria), then turns the request into a spec: a locked palette and frames, written
   by hand for small sprites or by a short procedural generator for larger ones. Tilesets, UI skins,
   and effect sheets use that same spec. A later round reads that brief instead of asking again. The
   palette may be an inline object, a bundled preset (`pico-8`, `nes`, `game-boy`, or a CC0 Lospec
   set in `palettes/`), or a project palette file. The sheet shape comes from
   `reference/engine-layouts.md`.
2. `scripts/render.py` (Python standard library only) writes the engine asset at 1x, an upscaled
   preview, a GIF per animation, and frame data. `scripts/embed.py` builds scenes into one HTML file.
   `scripts/capture.py` serves that file and, when a browser is present, saves timeline shots and
   an optional WebM.
3. The model looks at what it rendered and revises, usually two to four rounds. Each round marks
   the brief's done criteria pass or fail. The loop stops when they all pass, or when the round
   budget is spent and the failures are named.
4. `scripts/gallery.py` writes an `index.html` showing every output on one page.

## Settings

| Setting | Default | Purpose |
|---|---|---|
| `output_dir` | unset (ask) | Where outputs go when the request and the project name no location |
| `backend` | `native` | `native`, `aseprite`, `pixellab`, or `retrodiffusion` |

A project can name its own assets folder in its `CLAUDE.md`; that wins over `output_dir`.

## Prerequisites

- **Python 3**: required. The renderer uses the standard library only.
- **A local browser** (Chrome or Chromium on `PATH`): optional. `scripts/capture.py` drives it
  for the scene review loop. Without one, the command exits 3 and the skill says the scene was
  not reviewed visually.
- **Backends other than `native`**: optional and documented in `reference/backends.md`, not yet
  exercised. The skills check for a selected backend and fall back to `native` with a notice; no
  adapter code ships in this version.

`sheet.json` follows the shape of Aseprite's json-hash export but is not identical: animation tags
list frame names and per-frame durations rather than `from`/`to` ranges.

## Audio

This plugin makes no sound. A scene accepts an audio file you pass in, so a separate audio tool
can supply music or effects without either plugin depending on the other.

## Example

`examples/campfire/` holds the generator for an RPG Maker MZ walking character and a cutscene that
reuses it. `examples/tileset/a2_ground.py`, `examples/ui/window_mz.py`, and `examples/vfx/spark_mz.py`
each write a spec for an engine sheet. Copy a folder somewhere writable, then:

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

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `output_dir` | directory | *(none)* | `CLAUDE_PLUGIN_OPTION_OUTPUT_DIR` | Where rendered sprites, sheets and scenes go when neither the request nor the project names a location. Leave unset to be asked. |
| `backend` | string | `"native"` | `CLAUDE_PLUGIN_OPTION_BACKEND` | native (default, no external tools), aseprite, pixellab, or retrodiffusion. A named backend that is not present falls back to native with a notice. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure pixel-art@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install pixel-art@<marketplace> -s <scope> --config output_dir=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value. The short-circuit message is
   about the install, not the config write. Do **not** `claude plugin uninstall` to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin. The verified-version
   record lives in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior. A check run in the old session
   still reports the old value, and that is not a failed write.

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "pixel-art@<marketplace>": {
         "options": {
           "output_dir": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only, **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->
